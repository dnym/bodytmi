import 'dart:convert';
import 'dart:io';

import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart' show expectLater, throwsA, isA;

import 'cli_test.dart';
import 'fixtures.dart';
import 'support.dart';

TrainingArchive _archive() {
  final raw = definition().toJson();
  raw['name'] = 'Övre pass — α';
  final heavy = jsonObject((raw['slots']! as List<Object?>).first, 'slot');
  jsonObject(heavy['targets'], 'targets')['custom-hold'] = {
    'value': '01.500',
    'unit': 's',
  };
  final first = WorkoutRevision.publish(WorkoutDefinition.fromJson(raw));
  var old = finished(start(id: 'a-finished', from: first));
  // Original entered units and decimal spelling must survive portability.
  old = const TrainingService().complete(
    old,
    old.sets.first.id,
    metrics({
      'mass': ('180.00', 'lb'),
      'reps': ('9', 'rep'),
      'custom-hold': ('2.00', 's'),
    }),
  );
  final active = start(id: 'z-active', day: 2, from: first, history: [old]);
  raw['name'] = 'Revised prescription';
  final second = WorkoutRevision.publish(
    WorkoutDefinition.fromJson(raw),
    previous: first,
  );
  var skipped = start(id: 'm-skipped', day: 3, from: second, history: [old]);
  for (final set in skipped.sets) {
    skipped = const TrainingService().skip(skipped, set.id);
  }
  skipped = skipped.finish(instant(3).add(const Duration(hours: 1)));
  return TrainingArchive(
    revisions: [second, first],
    sessions: [active, skipped, old],
    finalizations: [skipped.id, old.id],
  );
}

Future<void> _populate(TrainingStore store, TrainingArchive archive) =>
    store.transaction(() async {
      for (final r in archive.revisions) {
        await store.insertRevision(r);
      }
      for (final s in archive.sessions) {
        await store.insertSession(s);
      }
      for (final id in archive.finalizations) {
        await store.recordFinalization(id);
      }
    });

void _sign(Map<String, Object?> envelope) {
  envelope['sha256'] = sha256
      .convert(
        utf8.encode(
          canonicalJson({
            for (final entry in envelope.entries)
              if (entry.key != 'sha256') entry.key: entry.value,
          }),
        ),
      )
      .toString();
}

void logicalArchiveTests() {
  test(
    'logical model preserves complete current training data and canonicalizes record/key order',
    () {
      final archive = _archive();
      final canonical = canonicalJson(archive.toJson());
      final raw = copyJson(archive.toJson());
      raw['revisions'] = (raw['revisions']! as List<Object?>).reversed.toList();
      raw['sessions'] = (raw['sessions']! as List<Object?>).reversed.toList();
      raw['finalizations'] = (raw['finalizations']! as List<Object?>).reversed
          .toList();
      equal(canonicalJson(TrainingArchive.fromJson(raw).toJson()), canonical);
      final session = archive.sessions.first;
      equal(session.sets.first.actuals['mass']!.enteredValue, '180.00');
      equal(session.sets.first.actuals['mass']!.enteredUnit.name, 'lb');
      equal(session.sets.first.actuals['custom-hold']!.enteredValue, '2.00');
      equal(
        archive.sessions.last.sets.first.sources['mass']!.sessionId,
        session.id,
      );
      equal(
        canonicalJson({
          'b': {'d': 1, 'a': 2},
          'a': [2, 1],
        }),
        '{"a":[2,1],"b":{"a":2,"d":1}}',
      );
    },
  );

  test(
    'logical validation rejects duplicate identities, missing history and mismatched prescriptions',
    () {
      final base = _archive().toJson();
      final mutations = <void Function(Map<String, Object?>)>[
        (j) => (j['revisions']! as List<Object?>).add(
          (j['revisions']! as List<Object?>).first,
        ),
        (j) => (j['revisions']! as List<Object?>).removeAt(0),
        (j) => (j['sessions']! as List<Object?>).add(
          (j['sessions']! as List<Object?>).first,
        ),
        (j) => (j['finalizations']! as List<Object?>).add('missing-session'),
        (j) => (j['finalizations']! as List<Object?>).add(
          (j['finalizations']! as List<Object?>).first,
        ),
        (j) => (j['finalizations']! as List<Object?>).clear(),
        (j) {
          final rows = j['sessions']! as List<Object?>;
          rows.removeWhere(
            (r) => jsonObject(r, 'session')['id'] == 'a-finished',
          );
          (j['finalizations']! as List<Object?>).remove('a-finished');
        },
        (j) {
          final rev = jsonObject(
            (j['revisions']! as List<Object?>).first,
            'revision',
          );
          jsonObject(rev['definition'], 'definition')['name'] = 'Forged name';
        },
        (j) => j['futureRecords'] = [],
      ];
      for (final mutate in mutations) {
        final raw = copyJson(base);
        mutate(raw);
        rejects(() => TrainingArchive.fromJson(raw));
      }
    },
  );

  test(
    'logical export/restore round-trip is deterministic and retains finalization identity after editing',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-logical-roundtrip-',
      );
      var store = await TrainingStore.open('${dir.path}/live.sqlite');
      try {
        final original = _archive();
        await _populate(store, original);
        final data = await store.archive();
        await LogicalArchiveFiles.export(data, '${dir.path}/first.json');
        await LogicalArchiveFiles.export(data, '${dir.path}/second.json');
        equal(
          await File('${dir.path}/first.json').readAsString(),
          await File('${dir.path}/second.json').readAsString(),
        );
        final prepared = await LogicalArchiveFiles.prepare(
          '${dir.path}/first.json',
        );
        try {
          equal(
            canonicalJson(prepared.archive.toJson()),
            canonicalJson(original.toJson()),
          );
          await StoredTrainingService(store).publish(definition(), 2);
          await store.restore(
            prepared.backup,
            recoveryDestination: '${dir.path}/recovery',
            confirm: true,
          );
        } finally {
          await prepared.close();
        }
        await store.close();
        store = await TrainingStore.open('${dir.path}/live.sqlite');
        equal(
          canonicalJson((await store.archive()).toJson()),
          canonicalJson(original.toJson()),
        );
        final s = original.sessions.first;
        await StoredTrainingService(store).edit(
          s.id,
          s.contentVersion,
          (s) => const TrainingService().complete(
            s,
            s.sets.last.id,
            const {},
            acceptSuggested: true,
          ),
        );
        equal(await store.finalizationCount(), 2);
        final recovery = await NativeBackup.prepare('${dir.path}/recovery');
        await recovery.close();
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'logical files reject unknown/future/neutral formats, checksum changes and resigned invalid references',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-logical-invalid-',
      );
      try {
        await LogicalArchiveFiles.export(_archive(), '${dir.path}/good.json');
        final base = jsonObject(
          jsonDecode(await File('${dir.path}/good.json').readAsString()),
          'envelope',
        );
        final mutations =
            <({bool sign, void Function(Map<String, Object?>) change})>[
              (
                sign: true,
                change: (j) => j['format'] = 'bodytmi-logical-export/99',
              ),
              (
                sign: true,
                change: (j) => j['format'] = 'neutral-training-log/0.1',
              ),
              (sign: true, change: (j) => j['unknown'] = true),
              (sign: false, change: (j) => j['applicationVersion'] = 'changed'),
              (
                sign: true,
                change: (j) =>
                    jsonObject(j['data'], 'data')['futureRecords'] = [],
              ),
              (
                sign: true,
                change: (j) =>
                    (jsonObject(j['data'], 'data')['finalizations']!
                            as List<Object?>)
                        .clear(),
              ),
            ];
        for (var n = 0; n < mutations.length; n++) {
          final doc = copyJson(base);
          mutations[n].change(doc);
          if (mutations[n].sign) _sign(doc);
          final path = '${dir.path}/bad-$n.json';
          await File(path).writeAsString(jsonEncode(doc));
          await expectLater(
            LogicalArchiveFiles.prepare(path),
            throwsA(isA<BodyTmiException>()),
          );
        }
        // Reformatting objects and record collections retains the same canonical checksum.
        final reordered = copyJson(base);
        final data = jsonObject(reordered['data'], 'data');
        data['sessions'] = (data['sessions']! as List<Object?>).reversed
            .toList();
        await File(
          '${dir.path}/reordered.json',
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(reordered));
        final prepared = await LogicalArchiveFiles.prepare(
          '${dir.path}/reordered.json',
        );
        await prepared.close();
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'logical export refuses overwrite and unknown SQLite records rather than dropping data',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-logical-schema-',
      );
      final path = '${dir.path}/live.sqlite';
      final store = await TrainingStore.open(path);
      try {
        await _populate(store, _archive());
        await File('${dir.path}/occupied.json').writeAsString('keep me');
        await expectLater(
          LogicalArchiveFiles.export(
            await store.archive(),
            '${dir.path}/occupied.json',
          ),
          throwsA(isA<BodyTmiException>()),
        );
        equal(
          await File('${dir.path}/occupied.json').readAsString(),
          'keep me',
        );
        final native = sqlite3.open(path);
        try {
          native.execute('CREATE TABLE future_records (id TEXT)');
        } finally {
          native.close();
        }
        await expectLater(store.archive(), throwsA(isA<BodyTmiException>()));
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'logical CLI restores across processes and rejects invalid input before touching the profile',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-logical-cli-');
      try {
        final path = '${dir.path}/live.sqlite';
        final store = await TrainingStore.open(path);
        try {
          await _populate(store, _archive());
        } finally {
          await store.close();
        }
        Future<({int code, String output, String error})> call(
          String action,
          Map<String, Object?> fields,
        ) => invoke([
          'archive',
          action,
        ], jsonEncode({'schemaVersion': 1, ...fields}));
        final file = '${dir.path}/logical.json';
        final exported = await call('export', {
          'database': path,
          'destination': file,
        });
        equal(exported.code, 0);
        equal(exported.error, '');
        final valid = await call('validate', {'source': file});
        equal(valid.code, 0);
        equal(valid.error, '');
        final target = '${dir.path}/restored.sqlite';
        final fields = <String, Object?>{
          'database': target,
          'source': file,
          'recoveryDestination': '${dir.path}/recovery',
        };
        equal((await call('restore', fields)).code, 2);
        check(!await File(target).exists());
        final restored = await call('restore', {...fields, 'confirm': true});
        equal(restored.code, 0);
        equal(restored.error, '');
        final loaded = await TrainingStore.open(target);
        try {
          equal(
            canonicalJson((await loaded.archive()).toJson()),
            canonicalJson(_archive().toJson()),
          );
        } finally {
          await loaded.close();
        }
        final self = await call('restore', {
          ...fields,
          'database': file,
          'confirm': true,
        });
        equal(self.code, 2);
        equal(self.output, '');
        final raw = await File(file).readAsString();
        await File(file).writeAsString(raw.replaceFirst('Övre', 'Forged'));
        final bad = await call('restore', {
          ...fields,
          'database': '${dir.path}/untouched.sqlite',
          'confirm': true,
        });
        equal(bad.code, 2);
        equal(bad.output, '');
        check(!await File('${dir.path}/untouched.sqlite').exists());
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'prepared logical copy remains usable after source changes and source aliases are protected',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-logical-source-',
      );
      try {
        final source = '${dir.path}/source.json';
        await LogicalArchiveFiles.export(_archive(), source);
        final prepared = await LogicalArchiveFiles.prepare(source);
        try {
          await Link('${dir.path}/alias.json').create(source);
          await expectLater(
            prepared.checkDestination('${dir.path}/alias.json'),
            throwsA(isA<BodyTmiException>()),
          );
          await File(source).writeAsString('changed after validation');
          final store = await TrainingStore.open('${dir.path}/target.sqlite');
          try {
            await store.restore(
              prepared.backup,
              recoveryDestination: '${dir.path}/recovery',
              confirm: true,
            );
          } finally {
            await store.close();
          }
          final loaded = await TrainingStore.open('${dir.path}/target.sqlite');
          try {
            equal(
              canonicalJson((await loaded.archive()).toJson()),
              canonicalJson(_archive().toJson()),
            );
          } finally {
            await loaded.close();
          }
        } finally {
          await prepared.close();
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
