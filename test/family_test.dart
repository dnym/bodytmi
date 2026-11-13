import 'dart:convert';
import 'dart:io';
import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart' show expectLater, throwsA, isA;
import 'cli_test.dart';
import 'fixtures.dart';
import 'support.dart';

ExerciseFamily _family(String id, List<String> exercises) =>
    ExerciseFamily.fromJson({'id': id, 'name': id, 'exercises': exercises});
WorkoutDefinition _workout() => WorkoutDefinition.fromJson({
  'id': 'mixed',
  'name': 'Mixed practice',
  'slots': [
    for (final id in ['barbell', 'dumbbell', 'machine', 'squat'])
      {
        'id': id,
        'exercise': id == 'squat' ? 'squat' : 'row',
        'implementation': id,
        'equipment': 'equipment-$id',
        'targets': {
          'mass': {'value': '20', 'unit': 'kg'},
          'reps': {'value': '8', 'unit': 'rep'},
        },
      },
  ],
  'plan': {
    'id': 'practice',
    'type': 'sequence',
    'children': [
      for (final id in ['barbell', 'dumbbell', 'machine', 'squat'])
        {'id': 'set-$id', 'type': 'effort', 'slot': id},
    ],
  },
});
Future<void> _withStore(
  Future<void> Function(TrainingStore, String) action,
) async {
  final dir = await Directory.systemTemp.createTemp('bodytmi-family-');
  final store = await TrainingStore.open('${dir.path}/db.sqlite');
  try {
    final training = StoredTrainingService(store);
    await training.publish(_workout(), 0);
    final s = await training.start('session', 'mixed', 1, instant(1));
    await training.edit(s.id, s.contentVersion, (s) {
      for (final set in s.sets)
        s = const TrainingService().complete(
          s,
          set.id,
          {},
          acceptSuggested: true,
        );
      return s.finish(instant(2));
    });
    await action(store, dir.path);
  } finally {
    await store.close();
    await dir.delete(recursive: true);
  }
}

Future<void> _fails(Future<Object?> action) =>
    expectLater(action, throwsA(isA<BodyTmiException>()));

void familyTests() {
  test(
    'families have explicit sorted overlapping membership, bounded validation and immutable revision identities',
    () {
      final input = {
        'id': 'pull',
        'name': 'Pulling',
        'exercises': ['row', 'hang'],
      };
      final family = ExerciseFamily.fromJson(input);
      jsonEqual(family.exercises, ['hang', 'row']);
      (input['exercises']! as List<String>).clear();
      equal(family.exercises.length, 2);
      final first = FamilyRevision.publish(family);
      final next = FamilyRevision.publish(
        _family('pull', ['row']),
        previous: first,
      );
      equal(next.number, 2);
      equal(first.family.exercises.length, 2);
      equal(_family('other', ['row']).exercises.single, 'row');
      equal(_family('empty', []).exercises.length, 0);
      rejects(() => _family('bad', ['row', 'row']));
      rejects(() => _family('bad', ['bad id']));
      rejects(() => _family('bad', List.generate(10001, (i) => 'e$i')));
      rejects(
        () => FamilyRevision.publish(
          _family('different', ['row']),
          previous: first,
        ),
      );
      rejects(
        () => FamilyRevision.fromJson({
          'schemaVersion': 1,
          'revision': 0,
          'family': family.toJson(),
        }),
      );
      rejects(() => validateFamilyRevisions([first, first]));
      rejects(() => validateFamilyRevisions([next]));
    },
  );
  test(
    'durable family publication checks expected revisions and leaves optional exercise composition and past membership untouched',
    () => _withStore((store, dir) async {
      equal((await store.familyRevisions()).length, 0);
      final before = canonicalJson((await store.session('session'))!.toJson());
      final service = FamilyService(store);
      final first = await service.publish(_family('rows', ['row']), 0);
      await _fails(service.publish(_family('rows', ['row', 'squat']), 0));
      final second = await service.publish(
        _family('rows', ['row', 'squat']),
        1,
      );
      equal(second.number, 2);
      equal((await service.revision('rows')).number, 2);
      jsonEqual((await service.revision('rows', 1)).toJson(), first.toJson());
      await service.publish(
        _family('pulling', ['row', 'unused-future-exercise']),
        0,
      );
      equal((await store.familyRevisions()).length, 3);
      equal(canonicalJson((await store.session('session'))!.toJson()), before);
      await store.archive();
    }),
  );
  test(
    'family series pin membership revisions, preserve all implementation/equipment/slot/run contexts and support empty/intersected selections',
    () => _withStore((store, dir) async {
      final sessions = await store.sessions();
      final first = FamilyRevision.publish(_family('rows', ['row']));
      final second = FamilyRevision.publish(
        _family('rows', ['row', 'squat']),
        previous: first,
      );
      const analytics = TrainingAnalytics();
      final old = analytics.series(
        sessions,
        metric: 'mass',
        family: first,
        runBySession: {'session': 'strength'},
      );
      equal(old['pointCount'], 3);
      equal(jsonList(old, 'series').length, 3);
      for (final row in jsonList(old, 'series')) {
        final context = jsonObject(
          jsonObject(row, 'series')['context'],
          'context',
        );
        equal(context['exercise'], 'row');
        equal(context['runId'], 'strength');
      }
      equal(
        jsonObject(
          jsonObject(old['policy'], 'policy')['family'],
          'family',
        )['revision'],
        1,
      );
      equal(
        analytics.series(
          sessions,
          metric: 'mass',
          family: second,
        )['pointCount'],
        4,
      );
      equal(
        analytics.series(
          sessions,
          metric: 'mass',
          family: first,
          context: {'implementation': 'barbell'},
        )['pointCount'],
        1,
      );
      equal(
        analytics.series(
          sessions,
          metric: 'mass',
          family: first,
          context: {'exercise': 'squat'},
        )['pointCount'],
        0,
      );
      equal(
        analytics.series(
          sessions,
          metric: 'mass',
          family: FamilyRevision.publish(_family('empty', [])),
        )['pointCount'],
        0,
      );
      final overlap = analytics.series(
        sessions,
        metric: 'mass',
        family: FamilyRevision.publish(_family('pull', ['row'])),
      );
      jsonEqual(
        jsonList(
          overlap,
          'series',
        ).map((r) => jsonObject(r, 'series')['key']).toList(),
        jsonList(
          analytics.series(sessions, metric: 'mass', family: first),
          'series',
        ).map((r) => jsonObject(r, 'series')['key']).toList(),
      );
    }),
  );
  test(
    'family archives reject duplicate/gapped revisions and native row/snapshot mismatches',
    () => _withStore((store, dir) async {
      await FamilyService(store).publish(_family('rows', ['row']), 0);
      final base = (await store.archive()).toJson();
      final duplicate = copyJson(base);
      jsonList(
        duplicate,
        'families',
      ).add(jsonList(duplicate, 'families').single);
      rejects(() => TrainingArchive.fromJson(duplicate));
      final gap = copyJson(base);
      jsonObject(jsonList(gap, 'families').single, 'family')['revision'] = 2;
      rejects(() => TrainingArchive.fromJson(gap));
      await store.backup('$dir/native');
      final db = sqlite3.open('$dir/native/database.sqlite');
      db.execute("UPDATE family_revisions SET family_id = 'forged'");
      db.close();
      rejects(
        () => NativeBackup.validateDatabase('$dir/native/database.sqlite'),
      );
    }),
  );
  test(
    'v11 schema/logical profiles migrate without inferred families and v12 portability preserves every published membership',
    () => _withStore((store, dir) async {
      final original = canonicalJson((await store.archive()).toJson());
      await store.backup('$dir/old');
      final old = sqlite3.open('$dir/old/database.sqlite');
      old.execute('DROP TABLE family_revisions');
      old.execute('DROP TABLE derived_target_graphs');
      old.execute('DROP TABLE IF EXISTS repeat_checkpoints');
      old.execute('DROP TABLE IF EXISTS window_checkpoints');
      old.execute('DROP TABLE IF EXISTS progression_reconciliations');
      old.execute('DROP TABLE IF EXISTS lever_link_revisions');
      old.execute('DROP TABLE IF EXISTS shared_lever_applications');
      old.execute('DROP TABLE IF EXISTS link_retirement_anchors');
      old.execute('DROP TABLE IF EXISTS program_upgrade_receipts');
      old.execute('DROP TABLE IF EXISTS exercise_revisions');
      old.execute('DROP TABLE IF EXISTS implementation_revisions');
      old.execute('DROP TABLE IF EXISTS equipment_revisions');
      old.execute('DROP TABLE IF EXISTS gym_revisions');
      old.execute('DROP TABLE IF EXISTS equipment_instance_revisions');
      old.userVersion = 11;
      old.close();
      equal(NativeBackup.validateDatabase('$dir/old/database.sqlite'), 11);
      await LogicalArchiveFiles.export(await store.archive(), '$dir/old.json');
      final legacy = jsonObject(
        jsonDecode(await File('$dir/old.json').readAsString()),
        'logical',
      );
      legacy['format'] = 'bodytmi-logical-export/11';
      jsonObject(legacy['data'], 'data').remove('families');
      legacy.remove('sha256');
      legacy['sha256'] = sha256
          .convert(utf8.encode(canonicalJson(legacy)))
          .toString();
      await File('$dir/old.json').writeAsString(jsonEncode(legacy));
      final prepared = await LogicalArchiveFiles.prepare('$dir/old.json');
      try {
        equal(canonicalJson(prepared.archive.toJson()), original);
      } finally {
        await prepared.close();
      }
      await store.close();
      final migrated = await TrainingStore.open('$dir/old/database.sqlite');
      try {
        equal(canonicalJson((await migrated.archive()).toJson()), original);
        equal(
          (await migrated.backup('$dir/upgraded'))['databaseSchemaVersion'],
          61,
        );
      } finally {
        await migrated.close();
      }
      var active = await TrainingStore.open('$dir/db.sqlite');
      try {
        await FamilyService(active).publish(_family('rows', ['row']), 0);
        await FamilyService(
          active,
        ).publish(_family('rows', ['row', 'squat']), 1);
        await FamilyService(active).publish(_family('pulling', ['row']), 0);
        final expected = canonicalJson((await active.archive()).toJson());
        await active.backup('$dir/native');
        equal(
          (await LogicalArchiveFiles.export(
            await active.archive(),
            '$dir/logical.json',
          ))['format'],
          'bodytmi-logical-export/61',
        );
        final logical = await LogicalArchiveFiles.prepare('$dir/logical.json');
        try {
          await active.restore(
            logical.backup,
            recoveryDestination: '$dir/recovery',
            confirm: true,
          );
        } finally {
          await logical.close();
          await active.close();
        }
        active = await TrainingStore.open('$dir/db.sqlite');
        equal(canonicalJson((await active.archive()).toJson()), expected);
        final native = await NativeBackup.prepare('$dir/native');
        try {
          await active.restore(
            native,
            recoveryDestination: '$dir/recovery2',
            confirm: true,
          );
        } finally {
          await native.close();
          await active.close();
        }
        active = await TrainingStore.open('$dir/db.sqlite');
        equal(canonicalJson((await active.archive()).toJson()), expected);
        equal(
          (await FamilyService(
            active,
          ).revision('rows', 1)).family.exercises.length,
          1,
        );
      } finally {
        await active.close();
      }
      final mislabeled = jsonObject(
        jsonDecode(await File('$dir/logical.json').readAsString()),
        'logical',
      );
      mislabeled['format'] = 'bodytmi-logical-export/11';
      mislabeled.remove('sha256');
      mislabeled['sha256'] = sha256
          .convert(utf8.encode(canonicalJson(mislabeled)))
          .toString();
      await File('$dir/logical.json').writeAsString(jsonEncode(mislabeled));
      await _fails(LogicalArchiveFiles.prepare('$dir/logical.json'));
      final missing = jsonObject(
        jsonDecode(await File('$dir/logical.json').readAsString()),
        'logical',
      );
      missing['format'] = 'bodytmi-logical-export/12';
      jsonObject(missing['data'], 'data').remove('families');
      missing.remove('sha256');
      missing['sha256'] = sha256
          .convert(utf8.encode(canonicalJson(missing)))
          .toString();
      await File('$dir/logical.json').writeAsString(jsonEncode(missing));
      await _fails(LogicalArchiveFiles.prepare('$dir/logical.json'));
    }),
  );
  test(
    'native family authoring and pinned/latest chart queries match the pure report and do not mutate training',
    () => _withStore((store, dir) async {
      final sessions = await store.sessions();
      await store.close();
      Future<Object?> cmd(String action, Map<String, Object?> input) async {
        final r = await invoke(
          action.split(' '),
          jsonEncode({
            'schemaVersion': 1,
            'database': '$dir/db.sqlite',
            ...input,
          }),
        );
        equal(r.code, 0);
        equal(r.error, '');
        return jsonObject(jsonDecode(r.output), 'response')['data'];
      }

      final first = jsonObject(
        await cmd('family publish', {
          'family': _family('rows', ['row']).toJson(),
          'expectedRevision': 0,
        }),
        'family',
      );
      await cmd('family publish', {
        'family': _family('rows', ['row', 'squat']).toJson(),
        'expectedRevision': 1,
      });
      final report = jsonObject(
        await cmd('store series', {
          'familyId': 'rows',
          'familyRevision': 1,
          'metric': 'mass',
        }),
        'report',
      );
      equal(report['pointCount'], 3);
      final pure = const Commands().execute('history series', {
        'schemaVersion': 1,
        'sessions': [for (final s in sessions) s.toJson()],
        'family': first,
        'metric': 'mass',
      })['data'];
      equal(canonicalJson(pure), canonicalJson(report));
      equal(
        jsonObject(
          await cmd('store series', {'familyId': 'rows', 'metric': 'mass'}),
          'report',
        )['pointCount'],
        4,
      );
      jsonEqual(
        await cmd('family show', {'familyId': 'rows', 'revision': 1}),
        first,
      );
      equal((await cmd('family list', {}) as List<Object?>).length, 2);
      final rejected = await invoke(
        ['store', 'series'],
        jsonEncode({
          'schemaVersion': 1,
          'database': '$dir/db.sqlite',
          'familyRevision': 1,
        }),
      );
      check(rejected.code != 0);
      equal(rejected.output, '');
      equal(
        jsonObject(
          await cmd('store show', {'id': 'session'}),
          'session',
        )['contentVersion'],
        sessions.single.contentVersion,
      );
    }),
  );
  test(
    'process death rolls family publication back or commits a complete immutable revision',
    () => _withStore((store, dir) async {
      await store.close();
      final binary = await compileNative(
        'test/helpers/store_owner.dart',
        '$dir/owner',
      );
      for (final mode in ['family-rollback', 'family-commit']) {
        final child = await Process.start(binary, ['$dir/db.sqlite', mode]);
        final errors = child.stderr.transform(utf8.decoder).join();
        try {
          equal(
            await child.stdout
                .transform(utf8.decoder)
                .transform(const LineSplitter())
                .first
                .timeout(const Duration(seconds: 15)),
            'ready',
          );
          child.kill(ProcessSignal.sigkill);
          await child.exitCode;
          equal(await errors, '');
        } finally {
          child.kill(ProcessSignal.sigkill);
          await child.exitCode;
        }
        final recovered = await TrainingStore.open('$dir/db.sqlite');
        try {
          final committed = mode.endsWith('commit');
          equal((await recovered.familyRevisions()).length, committed ? 1 : 0);
          if (committed) {
            equal(
              (await FamilyService(
                recovered,
              ).revision('rows')).family.exercises.single,
              'row',
            );
            await _fails(
              FamilyService(recovered).publish(_family('rows', ['squat']), 0),
            );
          }
          await recovered.archive();
        } finally {
          await recovered.close();
        }
      }
    }),
  );
}
