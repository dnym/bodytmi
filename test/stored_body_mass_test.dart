import 'dart:convert';
import 'dart:io';

import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:bodytmi_storage/src/schema.dart';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart' show expectLater, throwsA, isA;
import 'cli_test.dart';
import 'fixtures.dart';
import 'support.dart';

Map<String, Object?> _observation(
  String id,
  String mass, {
  String context = 'health',
  String at = '2026-10-01T07:00:00+02:00',
  String unit = 'kg',
}) => {
  'id': id,
  'context': context,
  'observedAt': at,
  'mass': {'value': mass, 'unit': unit},
};
Map<String, Object?> _query([String context = 'health']) => {
  'context': context,
  'asOf': '2026-10-10T12:00:00Z',
};
Future<void> _fails(Future<Object?> action) =>
    expectLater(action, throwsA(isA<BodyTmiException>()));
Future<void> _inStore(
  Future<void> Function(TrainingStore store, String dir) action,
) async {
  final dir = await Directory.systemTemp.createTemp('bodytmi-stored-mass-');
  final store = await TrainingStore.open('${dir.path}/db.sqlite');
  try {
    await action(store, dir.path);
  } finally {
    await store.close();
    await dir.delete(recursive: true);
  }
}

void storedBodyMassTests() {
  test(
    'raw body-mass metadata survives edits, deletion and logical restore',
    () => _inStore((store, dir) async {
      final mass = StoredBodyMassService(store);
      final input = {
        ..._observation('one', '80'),
        'source': 'Home scale 🏋️',
        'notes': 'Morning\nBefore breakfast',
      };
      final first = await mass.save(input, 0);
      jsonEqual((await mass.save(input, 0)).toJson(), first.toJson());
      final before = await mass.resolve(_query());
      final changed = {...input, 'notes': 'Changed note'};
      final updated = await mass.save(changed, 1);
      final after = await mass.resolve(_query());
      equal(after.mass!.value.toString(), before.mass!.value.toString());
      check(
        canonicalJson(after.sourceFingerprint) !=
            canonicalJson(before.sourceFingerprint),
      );
      equal(updated.measurement.source, 'Home scale 🏋️');
      equal(updated.measurement.notes, 'Changed note');
      final deleted = await mass.delete('one', 2, confirm: true);
      equal(deleted.measurement.notes, 'Changed note');
      await LogicalArchiveFiles.export(
        await store.archive(),
        '$dir/metadata.json',
      );
      final prepared = await LogicalArchiveFiles.prepare('$dir/metadata.json');
      try {
        await store.restore(
          prepared.backup,
          recoveryDestination: '$dir/recovery-metadata',
          confirm: true,
        );
        await store.close();
        final reopened = await TrainingStore.open('$dir/db.sqlite');
        try {
          final record = await StoredBodyMassService(reopened).show('one');
          equal(record.deleted, true);
          equal(record.measurement.source, 'Home scale 🏋️');
          equal(record.measurement.notes, 'Changed note');
        } finally {
          await reopened.close();
        }
      } finally {
        await prepared.close();
      }
    }),
  );

  test(
    'v34 labels reject retained body-mass metadata and legacy records migrate unchanged',
    () => _inStore((store, dir) async {
      final mass = StoredBodyMassService(store);
      await mass.save(_observation('legacy', '75'), 0);
      await store.snapshot('$dir/legacy.sqlite');
      final old = sqlite3.open('$dir/legacy.sqlite');
      old.userVersion = 34;
      old.close();
      final upgraded = await TrainingStore.open('$dir/legacy.sqlite');
      try {
        final legacy = await StoredBodyMassService(upgraded).show('legacy');
        check(!legacy.measurement.toJson().containsKey('source'));
        check(!legacy.measurement.toJson().containsKey('notes'));
      } finally {
        await upgraded.close();
      }
      await mass.save({
        ..._observation('annotated', '80'),
        'source': 'Scale',
        'notes': 'Morning',
      }, 0);
      await LogicalArchiveFiles.export(
        await store.archive(),
        '$dir/export-meta.json',
      );
      final envelope =
          jsonDecode(await File('$dir/export-meta.json').readAsString())
              as Map<String, Object?>;
      envelope['format'] = 'bodytmi-logical-export/34';
      envelope['sha256'] = sha256
          .convert(
            utf8.encode(
              canonicalJson({
                for (final e in envelope.entries)
                  if (e.key != 'sha256') e.key: e.value,
              }),
            ),
          )
          .toString();
      await File('$dir/old-meta.json').writeAsString(jsonEncode(envelope));
      await _fails(LogicalArchiveFiles.prepare('$dir/old-meta.json'));
      await store.snapshot('$dir/meta.sqlite');
      equal(NativeBackup.validateDatabase('$dir/meta.sqlite'), 38);
      final db = sqlite3.open('$dir/meta.sqlite');
      db.userVersion = 34;
      db.close();
      rejects(() => NativeBackup.validateDatabase('$dir/meta.sqlite'));
    }),
  );

  test(
    'stored observations preserve exact entry/offset, retry edits safely and reject stale or reused identities',
    () => _inStore((store, dir) async {
      final service = StoredBodyMassService(store);
      final input = _observation('one', '154.5', unit: 'lb');
      final first = await service.save(input, 0);
      equal(first.measurement.contentVersion, 1);
      equal(first.measurement.observedAtText, input['observedAt']);
      equal(first.measurement.mass.toJson()['entered'] is Map, true);
      jsonEqual((await service.save(input, 0)).toJson(), first.toJson());
      await _fails(service.save({...input, 'contentVersion': 9}, 0));
      await _fails(service.save(_observation('one', '80'), 0));
      await _fails(service.save(_observation('missing', '80'), 2));
      final edit = _observation(
        'one',
        '71',
        context: 'clothed-training',
        at: '2026-10-02T07:00:00+02:00',
      );
      final updated = await service.save(edit, 1);
      equal(updated.measurement.contentVersion, 2);
      jsonEqual((await service.save(edit, 1)).toJson(), updated.toJson());
      await _fails(service.save(_observation('one', '72'), 1));
      equal((await service.list(context: 'health')).length, 0);
      equal(
        (await service.list(context: 'clothed-training')).single.measurement.id,
        'one',
      );
      await store.close();
      final reopened = await TrainingStore.open('$dir/db.sqlite');
      try {
        jsonEqual(
          (await StoredBodyMassService(reopened).show('one')).toJson(),
          updated.toJson(),
        );
      } finally {
        await reopened.close();
      }
    }),
  );

  test(
    'stored mean/replacement resolution matches pure policy with context, as-of and raw-entry preservation',
    () => _inStore((store, dir) async {
      final service = StoredBodyMassService(store);
      final inputs = [
        _observation('early', '70'),
        _observation('late', '72', at: '2026-10-01T09:00:00+02:00'),
        _observation('training', '77', context: 'clothed-training'),
        _observation('future', '99', at: '2026-11-01T07:00:00+02:00'),
        for (var i = 2; i <= 9; i++)
          _observation(
            'day-$i',
            '74',
            at: '2026-10-${i.toString().padLeft(2, '0')}T07:00:00+02:00',
          ),
      ];
      for (final j in inputs.reversed) await service.save(j, 0);
      final before = canonicalJson((await store.archive()).toJson());
      for (final mode in ['mean', 'replace']) {
        final query = {..._query(), 'dailyMode': mode};
        jsonEqual(
          (await service.trend(query)).toJson(),
          const BodyMassService().trend({
            ...query,
            'measurements': inputs,
          }).toJson(),
        );
        jsonEqual(
          (await service.resolve(query)).toJson(),
          const BodyMassService().resolve({
            ...query,
            'measurements': inputs,
          }).toJson(),
        );
      }
      equal(
        (await service.trend(_query())).days.first.mass.value.toString(),
        '71',
      );
      equal(
        (await service.trend({
          ..._query(),
          'dailyMode': 'replace',
        })).days.first.mass.value.toString(),
        '72',
      );
      equal(
        (await service.resolve(
          _query('clothed-training'),
        )).mass!.value.toString(),
        '77',
      );
      equal(
        (await service.resolve(_query('missing-context'))).source,
        'unavailable',
      );
      await _fails(
        service.resolve({
          ..._query(),
          'override': {'measurementId': 'training'},
        }),
      );
      await _fails(
        service.resolve({
          ..._query(),
          'override': {'measurementId': 'future'},
        }),
      );
      await _fails(service.trend({..._query(), 'measurements': []}));
      equal(canonicalJson((await store.archive()).toJson()), before);
    }),
  );

  test(
    'correction and confirmed deletion change derived fingerprints without mutating captured resolutions or reusing IDs',
    () => _inStore((store, dir) async {
      final service = StoredBodyMassService(store);
      await service.save(_observation('one', '70'), 0);
      await service.save(_observation('two', '72'), 0);
      final initial = await service.resolve(_query());
      final frozen = canonicalJson(initial.toJson());
      await service.save(_observation('one', '74'), 1);
      final changed = await service.resolve(_query());
      check(
        canonicalJson(changed.sourceFingerprint) !=
            canonicalJson(initial.sourceFingerprint),
      );
      equal(changed.mass!.value.toString(), '73');
      await _fails(service.delete('one', 2, confirm: false));
      await _fails(service.delete('one', 1, confirm: true));
      final deleted = await service.delete('one', 2, confirm: true);
      equal(deleted.deleted, true);
      equal(deleted.measurement.contentVersion, 3);
      jsonEqual(
        (await service.delete('one', 2, confirm: true)).toJson(),
        deleted.toJson(),
      );
      await _fails(service.save(_observation('one', '70'), 0));
      await _fails(service.save(_observation('one', '70'), 3));
      await _fails(service.delete('one', 1, confirm: true));
      equal((await service.list()).length, 1);
      equal((await service.list(includeDeleted: true)).length, 2);
      final current = await service.resolve(_query());
      equal(current.mass!.value.toString(), '72');
      check(
        canonicalJson(current.sourceFingerprint) !=
            canonicalJson(changed.sourceFingerprint),
      );
      equal(current.stale, true);
      equal(
        (await service.resolve({
          ..._query(),
          'warnIfStale': false,
        })).toJson()['warnings'].toString(),
        '[]',
      );
      await _fails(
        service.resolve({
          ..._query(),
          'override': {'measurementId': 'one'},
        }),
      );
      final manual = await service.resolve({
        ..._query(),
        'override': {
          'mass': {'value': '75', 'unit': 'kg'},
        },
      });
      equal(manual.source, 'manual');
      equal(canonicalJson(initial.toJson()), frozen);
      await service.delete('two', 1, confirm: true);
      equal((await service.resolve(_query())).source, 'unavailable');
    }),
  );

  test(
    'body-mass writes, corrections and deletion roll back with their transaction',
    () => _inStore((store, dir) async {
      final service = StoredBodyMassService(store);
      await service.save(_observation('one', '70'), 0);
      final before = canonicalJson((await store.archive()).toJson());
      try {
        await store.transaction(() async {
          await service.save(_observation('one', '72'), 1);
          await service.save(_observation('two', '80'), 0);
          await service.delete('one', 2, confirm: true);
          throw StateError('rollback');
        });
      } on StateError {}
      equal(canonicalJson((await store.archive()).toJson()), before);
      for (final mass in ['0', '-1'])
        await _fails(service.save(_observation('invalid', mass), 0));
      await _fails(service.save(_observation('invalid', '1', unit: 's'), 0));
      rejects(
        () => BodyMassRecord.fromJson({
          'measurement': _observation('one', '70'),
          'deleted': true,
        }),
      );
      final duplicated = (await store.archive()).toJson();
      final rows = duplicated['bodyMass']! as List<Object?>;
      rows.add(rows.first);
      rejects(() => TrainingArchive.fromJson(duplicated));
    }),
  );

  test(
    'native and logical portability retain edited/deleted observations and reject new sections under legacy formats',
    () => _inStore((store, dir) async {
      final service = StoredBodyMassService(store);
      await service.save(_observation('one', '70'), 0);
      await service.save(_observation('two', '154', unit: 'lb'), 0);
      await service.save(_observation('one', '72'), 1);
      await service.delete('one', 2, confirm: true);
      final original = canonicalJson((await store.archive()).toJson());
      final resolved = canonicalJson(
        (await service.resolve(_query())).toJson(),
      );
      equal((await store.backup('$dir/native'))['databaseSchemaVersion'], 38);
      equal(
        (await LogicalArchiveFiles.export(
          await store.archive(),
          '$dir/export.json',
        ))['format'],
        'bodytmi-logical-export/38',
      );
      final logical = await LogicalArchiveFiles.prepare('$dir/export.json');
      try {
        equal(canonicalJson(logical.archive.toJson()), original);
        await service.save(_observation('extra', '90'), 0);
        await store.restore(
          logical.backup,
          recoveryDestination: '$dir/recovery',
          confirm: true,
        );
      } finally {
        await logical.close();
      }
      await store.close();
      final restored = await TrainingStore.open('$dir/db.sqlite');
      final native = await NativeBackup.prepare('$dir/native');
      try {
        equal(canonicalJson((await restored.archive()).toJson()), original);
        await restored.restore(
          native,
          recoveryDestination: '$dir/recovery2',
          confirm: true,
        );
      } finally {
        await native.close();
        await restored.close();
      }
      final reopened = await TrainingStore.open('$dir/db.sqlite');
      try {
        final service = StoredBodyMassService(reopened);
        equal(
          canonicalJson((await service.resolve(_query())).toJson()),
          resolved,
        );
        equal((await service.show('one')).deleted, true);
      } finally {
        await reopened.close();
      }
      final doc = jsonObject(
        jsonDecode(await File('$dir/export.json').readAsString()),
        'export',
      );
      for (final format in [1, 2, 3]) {
        doc['format'] = 'bodytmi-logical-export/$format';
        await File('$dir/forged.json').writeAsString(jsonEncode(doc));
        await _fails(LogicalArchiveFiles.prepare('$dir/forged.json'));
      }
      final raw = sqlite3.open('$dir/native/database.sqlite');
      try {
        raw.execute("UPDATE body_mass_records SET id='forged' WHERE id='one'");
      } finally {
        raw.close();
      }
      rejects(
        () => NativeBackup.validateDatabase('$dir/native/database.sqlite'),
      );
    }),
  );

  test(
    'schema and logical v3 profiles migrate without changing pinned program/session state',
    () => _inStore((store, dir) async {
      final revision = await StoredTrainingService(
        store,
      ).publish(definition(), 0);
      final program = ProgramDefinition.fromJson({
        'id': 'program',
        'name': 'Program',
        'plan': {
          'id': 'day',
          'type': 'day',
          'templateId': revision.definition.id,
          'revision': 1,
        },
      });
      await ProgramService(store).publish(program, 0);
      await ProgramService(store).create('run', 'program', 1, instant(1));
      await ProgramService(store).start('run', 1, 'session', instant(1));
      final original = (await store.archive()).toJson();
      final legacy = Map<String, Object?>.from(original)
        ..remove('bodyMass')
        ..remove('timers')
        ..remove('families')
        ..remove('executions');
      final envelope = <String, Object?>{
        'format': 'bodytmi-logical-export/3',
        'applicationVersion': '0.1.0',
        'data': legacy,
      };
      envelope['sha256'] = sha256
          .convert(utf8.encode(canonicalJson(envelope)))
          .toString();
      await File('$dir/legacy.json').writeAsString(jsonEncode(envelope));
      final prepared = await LogicalArchiveFiles.prepare('$dir/legacy.json');
      try {
        jsonEqual(prepared.archive.toJson(), original);
      } finally {
        await prepared.close();
      }
      await store.close();
      final raw = sqlite3.open('$dir/db.sqlite');
      try {
        raw.execute('DROP TABLE body_mass_records');
        raw.execute('DROP TABLE family_revisions');
        raw.execute('DROP TABLE workout_executions');
        raw.execute('DROP TABLE timing_activities');
        raw.execute('DROP TABLE derived_target_graphs');
        raw.execute('PRAGMA user_version = 3');
        validateSchema(
          raw.select(
            'SELECT name,sql FROM sqlite_master WHERE sql IS NOT NULL',
          ),
          3,
        );
      } finally {
        raw.close();
      }
      equal(
        (await NativeBackup.create(
          '$dir/db.sqlite',
          '$dir/legacy-native',
        ))['databaseSchemaVersion'],
        3,
      );
      final reopened = await TrainingStore.open('$dir/db.sqlite');
      try {
        jsonEqual((await reopened.archive()).toJson(), original);
        await StoredBodyMassService(
          reopened,
        ).save(_observation('new', '70'), 0);
        equal((await reopened.bodyMassRecords()).length, 1);
        equal((await ProgramService(reopened).run('run')).cursor, 0);
      } finally {
        await reopened.close();
      }
      final upgraded = sqlite3.open('$dir/db.sqlite');
      try {
        equal(upgraded.userVersion, 38);
      } finally {
        upgraded.close();
      }
    }),
  );

  test(
    'process death preserves the atomic boundary of body-mass edits and deletion',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-mass-crash-');
      try {
        final path = '${dir.path}/db.sqlite';
        final store = await TrainingStore.open(path);
        try {
          await StoredBodyMassService(store).save(_observation('one', '70'), 0);
        } finally {
          await store.close();
        }
        final binary = await compileNative(
          'test/helpers/store_owner.dart',
          '${dir.path}/owner',
        );
        for (final mode in ['mass-rollback', 'mass-commit']) {
          final child = await Process.start(binary, [path, mode]);
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
            final recovered = await TrainingStore.open(path);
            try {
              final service = StoredBodyMassService(recovered);
              final committed = mode == 'mass-commit';
              final one = await service.show('one');
              equal(one.deleted, committed);
              equal(one.measurement.contentVersion, committed ? 3 : 1);
              equal(
                (await service.list(includeDeleted: true)).length,
                committed ? 2 : 1,
              );
              if (committed) {
                jsonEqual(
                  (await service.delete('one', 2, confirm: true)).toJson(),
                  one.toJson(),
                );
                equal(
                  (await service.resolve(_query())).mass!.value.toString(),
                  '72',
                );
              }
            } finally {
              await recovered.close();
            }
          } finally {
            child.kill(ProcessSignal.sigkill);
            await child.exitCode;
          }
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'native mass CLI persists edits, resolves stored context and requires destructive confirmation',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-mass-cli-');
      try {
        Future<Object?> command(
          String action,
          Map<String, Object?> input,
        ) async {
          final result = await invoke(
            ['mass', action],
            jsonEncode({
              'schemaVersion': 1,
              'database': '${dir.path}/db.sqlite',
              ...input,
            }),
          );
          equal(result.code, 0);
          equal(result.error, '');
          return jsonObject(jsonDecode(result.output), 'response')['data'];
        }

        await command('record', {
          'measurement': {
            ..._observation('one', '70'),
            'source': 'Scale',
            'notes': 'Before breakfast',
          },
        });
        final updated = jsonObject(
          await command('update', {
            'measurement': {
              ..._observation('one', '72'),
              'source': 'Scale',
              'notes': 'Corrected',
            },
            'expectedVersion': 1,
          }),
          'record',
        );
        equal(
          jsonObject(updated['measurement'], 'measurement')['contentVersion'],
          2,
        );
        equal(
          jsonObject(updated['measurement'], 'measurement')['notes'],
          'Corrected',
        );
        final resolved = jsonObject(
          await command('resolve', _query()),
          'resolution',
        );
        equal(jsonObject(resolved['mass'], 'mass')['value'], '72');
        final denied = await invoke(
          ['mass', 'delete'],
          jsonEncode({
            'schemaVersion': 1,
            'database': '${dir.path}/db.sqlite',
            'id': 'one',
            'expectedVersion': 2,
          }),
        );
        check(denied.code != 0);
        equal(denied.output, '');
        await command('delete', {
          'id': 'one',
          'expectedVersion': 2,
          'confirm': true,
        });
        equal((await command('list', {}) as List<Object?>).length, 0);
        equal(
          (await command('list', {'includeDeleted': true}) as List<Object?>)
              .length,
          1,
        );
        equal(
          jsonObject(
            await command('resolve', _query()),
            'resolution',
          )['source'],
          'unavailable',
        );
        equal(
          jsonObject(await command('show', {'id': 'one'}), 'record')['deleted'],
          true,
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
