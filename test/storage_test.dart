import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart' show expectLater, throwsA, isA;
import 'cli_test.dart';
import 'fixtures.dart';
import 'support.dart';

void storageTests() {
  test(
    'unknown, corrupt and future SQLite files fail without modifying existing data',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-schema-');
      try {
        final futurePath = '${dir.path}/future.sqlite';
        final db = sqlite3.open(futurePath);
        db.execute('PRAGMA user_version = 999');
        db.close();
        final before = File(futurePath).readAsBytesSync();
        await expectLater(
          TrainingStore.open(futurePath),
          throwsA(isA<BodyTmiException>()),
        );
        jsonEqual(File(futurePath).readAsBytesSync(), before);
        final foreign = sqlite3.open('${dir.path}/foreign.sqlite');
        foreign.execute('CREATE TABLE valuable (id TEXT)');
        foreign.close();
        await expectLater(
          TrainingStore.open('${dir.path}/foreign.sqlite'),
          throwsA(isA<BodyTmiException>()),
        );
        File('${dir.path}/corrupt.sqlite').writeAsStringSync('not a database');
        final result = await invoke(
          ['store', 'history'],
          jsonEncode({
            'schemaVersion': 1,
            'database': '${dir.path}/corrupt.sqlite',
          }),
        );
        equal(result.code, 4);
        equal(result.output, '');
        equal(
          ((jsonDecode(result.error) as Map)['error'] as Map)['code'],
          'storage',
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'SQLite persists immutable revisions, editable results, history and stable finalization',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-store-');
      final path = '${dir.path}/training.sqlite';
      var store = await TrainingStore.open(path);
      try {
        var service = StoredTrainingService(store);
        final first = await service.publish(definition(), 0);
        final s = await service.start(
          'persist',
          first.definition.id,
          1,
          instant(1),
        );
        final done = await service.edit(s.id, s.contentVersion, finished);
        await service.edit(
          s.id,
          done.contentVersion,
          (s) => s.finish(instant(2)),
        );
        equal(await store.finalizationCount(), 1);
        await store.close();
        store = await TrainingStore.open(path);
        service = StoredTrainingService(store);
        var loaded = await service.session(s.id);
        jsonEqual(loaded.toJson(), done.toJson());
        loaded = await service.edit(
          s.id,
          loaded.contentVersion,
          (s) => const TrainingService().complete(
            s,
            s.sets.first.id,
            metrics({'mass': ('81', 'kg'), 'reps': ('8', 'rep')}),
          ),
        );
        equal(await store.finalizationCount(), 1);
        await expectLater(
          service.edit(s.id, done.contentVersion, (s) => s),
          throwsA(isA<BodyTmiException>()),
        );
        final next = await service.start(
          'next',
          first.definition.id,
          1,
          instant(3),
        );
        equal(next.sets.first.sources['mass']!.sessionId, s.id);
        equal(
          next.sets.first.suggested['mass']!.value,
          Quantity('81', 'kg').value,
        );
        final second = await service.publish(definition(), 1);
        equal(second.number, 2);
        equal((await service.revision(first.definition.id, 1)).number, 1);
        await expectLater(
          service.publish(definition(), 1),
          throwsA(isA<BodyTmiException>()),
        );
        final retry = await service.start(
          'persist',
          first.definition.id,
          1,
          instant(1),
        );
        equal(retry.contentVersion, loaded.contentVersion);
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'transaction rollback and WAL snapshot reopen preserve consistent data',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-snapshot-');
      var store = await TrainingStore.open('${dir.path}/live.sqlite');
      try {
        await expectLater(
          store.transaction(() async {
            await store.insertRevision(revision());
            throw StateError('abort');
          }),
          throwsA(isA<StateError>()),
        );
        equal(await store.revision(definition().id), null);
        await StoredTrainingService(store).publish(definition(), 0);
        await store.snapshot('${dir.path}/snapshot.sqlite');
        await expectLater(
          store.snapshot('${dir.path}/snapshot.sqlite'),
          throwsA(isA<BodyTmiException>()),
        );
        await expectLater(
          TrainingStore.open(store.path),
          throwsA(isA<BodyTmiException>()),
        );
        await store.close();
        store = await TrainingStore.open('${dir.path}/snapshot.sqlite');
        equal((await store.revision(definition().id))!.number, 1);
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'native CLI durable workflow survives separate processes and rejects stale edits',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-cli-');
      try {
        Future<({int code, String output, String error})> call(
          String action,
          Map<String, Object?> data,
        ) => invoke(
          ['store', action],
          jsonEncode({
            'schemaVersion': 1,
            'database': '${dir.path}/db.sqlite',
            ...data,
          }),
        );
        final published = await call('publish', {
          'definition': definition().toJson(),
          'expectedRevision': 0,
        });
        equal(published.code, 0);
        equal(published.error, '');
        final started = await call('start', {
          'id': 'cli-durable',
          'templateId': definition().id,
          'revision': 1,
          'startedAt': '2026-10-01T12:00:00Z',
        });
        equal(started.code, 0);
        final session = sessionFromJson(
          (jsonDecode(started.output) as Map)['data'],
        );
        final complete = await call('complete', {
          'id': session.id,
          'expectedVersion': 1,
          'setId': session.sets.first.id,
          'acceptSuggested': true,
        });
        equal(complete.code, 0);
        final stale = await call('complete', {
          'id': session.id,
          'expectedVersion': 1,
          'setId': session.sets.first.id,
          'acceptSuggested': true,
        });
        equal(stale.code, 5);
        equal(stale.output, '');
        final shown = await call('show', {'id': session.id});
        equal(shown.code, 0);
        equal(
          sessionFromJson(
            (jsonDecode(shown.output) as Map)['data'],
          ).sets.first.status,
          SetStatus.completed,
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'OS owner lock survives contention and recovers after process death with rollback',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-crash-');
      final binary = await compileNative(
        'test/helpers/store_owner.dart',
        '${dir.path}/owner',
      );
      final path = '${dir.path}/db.sqlite';
      final child = await Process.start(binary, [path, 'transaction']);
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
        await expectLater(
          TrainingStore.open(path),
          throwsA(isA<BodyTmiException>()),
        );
        child.kill(ProcessSignal.sigkill);
        await child.exitCode;
        final recovered = await TrainingStore.open(path);
        try {
          equal(await recovered.revision(definition().id), null);
        } finally {
          await recovered.close();
        }
        equal(await errors, '');
      } finally {
        child.kill(ProcessSignal.sigkill);
        await child.exitCode;
        await dir.delete(recursive: true);
      }
    },
  );
}
