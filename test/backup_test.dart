import 'dart:async';
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

Future<void> _resign(String directory) async {
  final file = File('$directory/database.sqlite');
  final manifestFile = File('$directory/manifest.json');
  final manifest = jsonObject(
    jsonDecode(await manifestFile.readAsString()),
    'manifest',
  );
  manifest['database'] = {
    'file': 'database.sqlite',
    'bytes': await file.length(),
    'sha256': (await sha256.bind(file.openRead()).first).toString(),
  };
  await manifestFile.writeAsString(jsonEncode(manifest));
}

Future<void> _clone(String from, String to) async {
  await Directory(to).create();
  for (final name in ['manifest.json', 'database.sqlite']) {
    await File('$from/$name').copy('$to/$name');
  }
}

void backupTests() {
  test(
    'native backup round-trips revisions, units, edited results, history and finalization identities',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-backup-');
      final path = '${dir.path}/live.sqlite';
      var store = await TrainingStore.open(path);
      try {
        final service = StoredTrainingService(store);
        final first = await service.publish(definition(), 0);
        final s = await service.start(
          'original',
          first.definition.id,
          1,
          instant(1),
        );
        final done = await service.edit(s.id, s.contentVersion, finished);
        await service.start('with-history', first.definition.id, 1, instant(2));
        final original = await store.sessions();
        final manifest = await store.backup('${dir.path}/backup');
        equal(manifest['format'], 'bodytmi-native-backup/1');
        final prepared = await NativeBackup.prepare('${dir.path}/backup');
        try {
          await service.publish(definition(), 1);
          await service.edit(
            done.id,
            done.contentVersion,
            (s) => const TrainingService().complete(
              s,
              s.sets.first.id,
              metrics({'mass': ('180', 'lb'), 'reps': ('9', 'rep')}),
            ),
          );
          await expectLater(
            store.restore(
              prepared,
              recoveryDestination: '${dir.path}/denied',
              confirm: false,
            ),
            throwsA(isA<BodyTmiException>()),
          );
          check(!await Directory('${dir.path}/denied').exists());
          await store.restore(
            prepared,
            recoveryDestination: '${dir.path}/recovery',
            confirm: true,
          );
        } finally {
          await prepared.close();
        }
        await store.close();
        store = await TrainingStore.open(path);
        jsonEqual(
          [for (final s in await store.sessions()) s.toJson()],
          [for (final s in original) s.toJson()],
        );
        equal((await store.revision(definition().id))!.number, 1);
        equal(await store.finalizationCount(), 1);
        // The recovery backup holds the complete profile just before replacement.
        final recovery = await NativeBackup.prepare('${dir.path}/recovery');
        try {
          await store.restore(
            recovery,
            recoveryDestination: '${dir.path}/second-recovery',
            confirm: true,
          );
        } finally {
          await recovery.close();
        }
        await store.close();
        store = await TrainingStore.open(path);
        equal((await store.revision(definition().id))!.number, 2);
        final entered = (await store.session(
          done.id,
        ))!.sets.first.actuals['mass']!;
        equal(entered.enteredValue, '180');
        equal(entered.enteredUnit.name, 'lb');
        equal(await store.finalizationCount(), 1);
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'backup validation rejects corruption, future formats, schema changes and forged domain references',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-invalid-backup-',
      );
      final store = await TrainingStore.open('${dir.path}/live.sqlite');
      try {
        final service = StoredTrainingService(store);
        final rev = await service.publish(definition(), 0);
        final s = await service.start(
          'finished',
          rev.definition.id,
          1,
          instant(1),
        );
        await service.edit(s.id, s.contentVersion, finished);
        await store.backup('${dir.path}/valid');
        final modifications = <String, void Function(Database)>{
          'future-schema': (db) => db.userVersion = 99,
          'trigger': (db) => db.execute(
            'CREATE TRIGGER unexpected AFTER INSERT ON sessions BEGIN DELETE FROM revisions; END',
          ),
          'missing-revision': (db) => db.execute('DELETE FROM revisions'),
          'missing-finalization': (db) =>
              db.execute('DELETE FROM finalizations'),
          'invalid-identity': (db) =>
              db.execute("UPDATE sessions SET id = 'forged'"),
          'orphan-finalization': (db) =>
              db.execute("INSERT INTO finalizations VALUES ('missing')"),
          'forged-result': (db) {
            final raw = jsonObject(
              jsonDecode(
                db.select('SELECT snapshot FROM sessions').single['snapshot']
                    as String,
              ),
              'session',
            );
            final sets = raw['sets']! as List<Object?>;
            jsonObject(sets.first, 'set')['ordinal'] = 999;
            db.execute('UPDATE sessions SET snapshot = ?', [jsonEncode(raw)]);
          },
        };
        for (final entry in modifications.entries) {
          final target = '${dir.path}/${entry.key}';
          await _clone('${dir.path}/valid', target);
          final db = sqlite3.open('$target/database.sqlite');
          try {
            entry.value(db);
          } finally {
            db.close();
          }
          await _resign(target);
          await expectLater(
            NativeBackup.prepare(target),
            throwsA(isA<BodyTmiException>()),
          );
        }
        await _clone('${dir.path}/valid', '${dir.path}/checksum');
        final corrupt = File('${dir.path}/checksum/database.sqlite');
        final corruptBytes = await corrupt.readAsBytes();
        corruptBytes[100] ^= 1;
        await corrupt.writeAsBytes(corruptBytes);
        await expectLater(
          NativeBackup.prepare('${dir.path}/checksum'),
          throwsA(isA<BodyTmiException>()),
        );
        await _clone('${dir.path}/valid', '${dir.path}/future-format');
        final manifestFile = File('${dir.path}/future-format/manifest.json');
        final manifest = jsonObject(
          jsonDecode(await manifestFile.readAsString()),
          'manifest',
        )..['format'] = 'bodytmi-native-backup/99';
        await manifestFile.writeAsString(jsonEncode(manifest));
        await expectLater(
          NativeBackup.prepare('${dir.path}/future-format'),
          throwsA(isA<BodyTmiException>()),
        );
        await _clone('${dir.path}/valid', '${dir.path}/symlink');
        await File('${dir.path}/symlink/database.sqlite').delete();
        await Link(
          '${dir.path}/symlink/database.sqlite',
        ).create('${dir.path}/valid/database.sqlite');
        await expectLater(
          NativeBackup.prepare('${dir.path}/symlink'),
          throwsA(isA<BodyTmiException>()),
        );
        final prepared = await NativeBackup.prepare('${dir.path}/valid');
        try {
          await expectLater(
            prepared.checkDestination(
              '${dir.path}/valid/nested/profile.sqlite',
            ),
            throwsA(isA<BodyTmiException>()),
          );
        } finally {
          await prepared.close();
        }
        equal((await store.revision(definition().id))!.number, 1);
        equal(await store.finalizationCount(), 1);
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'CLI validates restore before opening the target and requires explicit confirmation',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-backup-cli-');
      try {
        final path = '${dir.path}/live.sqlite';
        final store = await TrainingStore.open(path);
        try {
          await StoredTrainingService(store).publish(definition(), 0);
        } finally {
          await store.close();
        }
        Future<({int code, String output, String error})> call(
          String command,
          Map<String, Object?> fields,
        ) => invoke([
          'backup',
          command,
        ], jsonEncode({'schemaVersion': 1, ...fields}));
        final created = await call('create', {
          'database': path,
          'destination': '${dir.path}/backup',
        });
        equal(created.code, 0);
        equal(created.error, '');
        final valid = await call('validate', {'source': '${dir.path}/backup'});
        equal(valid.code, 0);
        equal(valid.error, '');
        final existing = await call('create', {
          'database': path,
          'destination': '${dir.path}/backup',
        });
        equal(existing.code, 5);
        equal(existing.output, '');
        final denied = await call('restore', {
          'database': path,
          'source': '${dir.path}/backup',
          'recoveryDestination': '${dir.path}/recovery',
        });
        equal(denied.code, 2);
        equal(denied.output, '');
        final protected = await call('restore', {
          'database': '${dir.path}/backup/database.sqlite',
          'source': '${dir.path}/backup',
          'recoveryDestination': '${dir.path}/recovery',
          'confirm': true,
        });
        equal(protected.code, 2);
        equal(protected.output, '');
        final updated = await TrainingStore.open(path);
        try {
          await StoredTrainingService(updated).publish(definition(), 1);
        } finally {
          await updated.close();
        }
        final restored = await call('restore', {
          'database': path,
          'source': '${dir.path}/backup',
          'recoveryDestination': '${dir.path}/saved-profile',
          'confirm': true,
        });
        equal(restored.code, 0);
        equal(restored.error, '');
        final reopened = await TrainingStore.open(path);
        try {
          equal((await reopened.revision(definition().id))!.number, 1);
        } finally {
          await reopened.close();
        }
        equal(
          (await call('validate', {
            'source': '${dir.path}/saved-profile',
          })).code,
          0,
        );
        // Corruption must not even create the new destination profile.
        await File(
          '${dir.path}/backup/database.sqlite',
        ).writeAsString('corrupt');
        final bad = await call('restore', {
          'database': '${dir.path}/untouched.sqlite',
          'source': '${dir.path}/backup',
          'recoveryDestination': '${dir.path}/recovery',
          'confirm': true,
        });
        equal(bad.code, 2);
        equal(bad.output, '');
        check(!await File('${dir.path}/untouched.sqlite').exists());
        check(!await Directory('${dir.path}/recovery').exists());
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'validated private copy survives source edits and recovery conflicts leave live data unchanged',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-staged-backup-',
      );
      var store = await TrainingStore.open('${dir.path}/live.sqlite');
      try {
        final service = StoredTrainingService(store);
        await service.publish(definition(), 0);
        await store.backup('${dir.path}/backup');
        final prepared = await NativeBackup.prepare('${dir.path}/backup');
        try {
          await service.publish(definition(), 1);
          await Directory('${dir.path}/occupied').create();
          await expectLater(
            store.restore(
              prepared,
              recoveryDestination: '${dir.path}/occupied',
              confirm: true,
            ),
            throwsA(isA<BodyTmiException>()),
          );
          equal((await store.revision(definition().id))!.number, 2);
          await File(
            '${dir.path}/backup/database.sqlite',
          ).writeAsString('changed after validation');
          await store.restore(
            prepared,
            recoveryDestination: '${dir.path}/recovery',
            confirm: true,
          );
        } finally {
          await prepared.close();
        }
        await store.close();
        store = await TrainingStore.open('${dir.path}/live.sqlite');
        equal((await store.revision(definition().id))!.number, 1);
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'process kill during native restore rolls back and retains a validated recovery backup',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-restore-crash-',
      );
      try {
        final source = await TrainingStore.open('${dir.path}/source.sqlite');
        try {
          final raw = definition().toJson();
          (raw['slots']! as List<Object?>)
              .cast<Map<String, Object?>>()
              .first['setupNote'] = List.filled(
            6 * 1024 * 1024,
            'x',
          ).join();
          final large = WorkoutDefinition.fromJson(raw);
          for (var n = 0; n < 3; n++) {
            await StoredTrainingService(source).publish(large, n);
          }
          await source.backup('${dir.path}/backup');
        } finally {
          await source.close();
        }
        final path = '${dir.path}/target.sqlite';
        final target = await TrainingStore.open(path);
        try {
          await StoredTrainingService(target).publish(definition(), 0);
        } finally {
          await target.close();
        }
        final binary = await compileNative(
          'test/helpers/store_owner.dart',
          '${dir.path}/owner',
        );
        final child = await Process.start(binary, [
          path,
          'restore',
          '${dir.path}/backup',
          '${dir.path}/recovery',
        ]);
        final error = child.stderr.transform(utf8.decoder).join();
        try {
          equal(
            await child.stdout
                .transform(utf8.decoder)
                .transform(const LineSplitter())
                .first
                .timeout(const Duration(seconds: 30)),
            'ready',
          );
          // Owner lock remains held even though Drift has closed for replacement.
          await expectLater(
            TrainingStore.open(path),
            throwsA(isA<BodyTmiException>()),
          );
          child.kill(ProcessSignal.sigkill);
          await child.exitCode;
          final recovered = await TrainingStore.open(path);
          try {
            jsonEqual(
              (await recovered.revision(definition().id))!.definition.toJson(),
              definition().toJson(),
            );
            equal((await recovered.revision(definition().id))!.number, 1);
          } finally {
            await recovered.close();
          }
          final recovery = await NativeBackup.prepare('${dir.path}/recovery');
          await recovery.close();
          equal(await error, '');
        } finally {
          child.kill(ProcessSignal.sigkill);
          await child.exitCode;
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
