import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'fixtures.dart';
import 'cli_test.dart';
import 'support.dart';

Future<void> expectCheckpointFailure(
  Future<Object?> action, [
  String code = 'validation',
]) async {
  try {
    await action;
  } on BodyTmiException catch (error) {
    equal(error.code, code);
    return;
  }
  throw StateError('Expected BodyTmiException($code).');
}

void activityTests() {
  test(
    'schema v50 repeat snapshots migrate without session associations',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-repeat-v50-');
      final path = '${dir.path}/profile.sqlite';
      try {
        var store = await TrainingStore.open(path);
        final execution = const WindowRepeatExecution().start(
          WindowRepeatSpec.fromJson(example('window-repeat-page')['loop']),
        );
        await RepeatCheckpointService(store).save('repeat', 0, execution);
        await store.close();
        final raw = sqlite3.open(path);
        raw.execute('DROP TABLE IF EXISTS progression_reconciliations');
        raw.execute('DROP TABLE IF EXISTS lever_link_revisions');
        raw.execute('DROP TABLE IF EXISTS shared_lever_applications');
        raw.execute('DROP TABLE IF EXISTS link_retirement_anchors');
        raw.execute('DROP TABLE IF EXISTS program_upgrade_receipts');
        raw.userVersion = 50;
        raw.close();
        store = await TrainingStore.open(path);
        try {
          final repeat = await RepeatCheckpointService(store).show('repeat');
          equal(repeat.sessionId, null);
          equal(canonicalJson(repeat.execution), canonicalJson(execution));
        } finally {
          await store.close();
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'repeat session associations survive backup and reject older labels or missing sessions',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-repeat-session-',
      );
      final path = '${dir.path}/profile.sqlite';
      try {
        var store = await TrainingStore.open(path);
        final training = StoredTrainingService(store);
        final workout = definition();
        await training.publish(workout, 0);
        final session = await training.start(
          'session',
          workout.id,
          1,
          instant(1),
        );
        final loop = WindowRepeatSpec.fromJson(
          example('window-repeat-page')['loop'],
        );
        final execution = const WindowRepeatExecution().start(loop);
        final repeatService = RepeatCheckpointService(store);
        await repeatService.save('repeat', 0, execution, sessionId: session.id);
        final reserved = await repeatService.reserve('repeat', 1);
        equal(reserved.sessionId, session.id);
        final released = await repeatService.release(
          'repeat',
          2,
          confirm: true,
        );
        equal(released.sessionId, session.id);
        await store.backup('${dir.path}/native');
        final archivePath = '${dir.path}/logical.json';
        await LogicalArchiveFiles.export(await store.archive(), archivePath);
        final old = jsonObject(
          jsonDecode(await File(archivePath).readAsString()),
          'archive',
        );
        old['format'] = 'bodytmi-logical-export/50';
        old.remove('sha256');
        old['sha256'] = sha256
            .convert(utf8.encode(canonicalJson(old)))
            .toString();
        await File('${dir.path}/old.json').writeAsString(canonicalJson(old));
        await expectCheckpointFailure(
          LogicalArchiveFiles.prepare('${dir.path}/old.json'),
        );
        final oldDbPath = '${dir.path}/old.sqlite';
        await File('${dir.path}/native/database.sqlite').copy(oldDbPath);
        final oldDb = sqlite3.open(oldDbPath);
        oldDb.execute('DROP TABLE IF EXISTS progression_reconciliations');
        oldDb.execute('DROP TABLE IF EXISTS lever_link_revisions');
        oldDb.execute('DROP TABLE IF EXISTS shared_lever_applications');
        oldDb.execute('DROP TABLE IF EXISTS link_retirement_anchors');
        oldDb.execute('DROP TABLE IF EXISTS program_upgrade_receipts');
        oldDb.userVersion = 50;
        oldDb.close();
        rejects(() => NativeBackup.validateDatabase(oldDbPath));
        final brokenPath = '${dir.path}/broken.sqlite';
        await File('${dir.path}/native/database.sqlite').copy(brokenPath);
        final brokenDb = sqlite3.open(brokenPath);
        final snapshot = jsonObject(
          jsonDecode(
            brokenDb
                    .select('SELECT snapshot FROM repeat_checkpoints')
                    .single['snapshot']
                as String,
          ),
          'checkpoint',
        );
        snapshot['sessionId'] = 'missing';
        brokenDb.execute('UPDATE repeat_checkpoints SET snapshot=?', [
          canonicalJson(snapshot),
        ]);
        brokenDb.close();
        rejects(() => NativeBackup.validateDatabase(brokenPath));
        await store.close();
        final native = await NativeBackup.prepare('${dir.path}/native');
        try {
          store = await TrainingStore.open('${dir.path}/restored.sqlite');
          try {
            await store.restore(
              native,
              recoveryDestination: '${dir.path}/recovery',
              confirm: true,
            );
          } finally {
            await store.close();
          }
        } finally {
          await native.close();
        }
        store = await TrainingStore.open('${dir.path}/restored.sqlite');
        try {
          equal(
            (await RepeatCheckpointService(store).show('repeat')).sessionId,
            session.id,
          );
        } finally {
          await store.close();
        }
        final logical = await LogicalArchiveFiles.prepare(archivePath);
        try {
          equal(logical.archive.repeatCheckpoints.single.sessionId, session.id);
        } finally {
          await logical.close();
        }
        final cli = await invoke([
          'repeat-checkpoint',
          'show',
        ], jsonEncode({'schemaVersion': 1, 'database': path, 'id': 'repeat'}));
        equal(cli.code, 0);
        equal(
          jsonObject(
            jsonObject(jsonDecode(cli.output), 'response')['data'],
            'checkpoint',
          )['sessionId'],
          session.id,
        );
        final created = await invoke(
          ['repeat-checkpoint', 'save'],
          jsonEncode({
            'schemaVersion': 1,
            'database': path,
            'id': 'cli-repeat',
            'expectedVersion': 0,
            'sessionId': session.id,
            'execution': execution,
          }),
        );
        equal(created.code, 0);
        equal(
          jsonObject(
            jsonObject(jsonDecode(created.output), 'response')['data'],
            'checkpoint',
          )['sessionId'],
          session.id,
        );
        final filtered = await invoke(
          ['repeat-checkpoint', 'list'],
          jsonEncode({
            'schemaVersion': 1,
            'database': path,
            'sessionId': session.id,
          }),
        );
        equal(filtered.code, 0);
        equal(
          (jsonObject(jsonDecode(filtered.output), 'response')['data'] as List)
              .length,
          2,
        );
        final absent = await invoke(
          ['repeat-checkpoint', 'list'],
          jsonEncode({
            'schemaVersion': 1,
            'database': path,
            'sessionId': 'other',
          }),
        );
        equal(
          (jsonObject(jsonDecode(absent.output), 'response')['data'] as List)
              .length,
          0,
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'foreground repeat runner recovers after kill and pauses on SIGINT',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-repeat-interrupt-',
      );
      final path = '${dir.path}/profile.sqlite';
      try {
        final initialStore = await TrainingStore.open(path);
        try {
          final loop = WindowRepeatSpec.fromJson({
            ...jsonObject(example('window-repeat-page')['loop'], 'loop'),
            'durationMilliseconds': 60000,
          });
          final service = RepeatCheckpointService(initialStore);
          await service.save(
            'repeat',
            0,
            const WindowRepeatExecution().start(loop),
          );
          await service.reserve('repeat', 1);
        } finally {
          await initialStore.close();
        }
        final binary = await compileNative(
          'bin/bodytmi.dart',
          '${dir.path}/native',
        );
        Future<
          ({Process child, StreamIterator<String> lines, Future<String> errors})
        >
        launch(int checkpointVersion, int executionVersion) async {
          final child = await Process.start(binary, [
            'repeat-checkpoint',
            'run',
          ]);
          final lines = StreamIterator(
            child.stdout
                .transform(utf8.decoder)
                .transform(const LineSplitter()),
          );
          final errors = child.stderr.transform(utf8.decoder).join();
          child.stdin.writeln(
            jsonEncode({
              'schemaVersion': 1,
              'database': path,
              'id': 'repeat',
              'expectedVersion': checkpointVersion,
              'expectedExecutionVersion': executionVersion,
              'stream': true,
            }),
          );
          await child.stdin.close();
          check(await lines.moveNext().timeout(const Duration(seconds: 10)));
          equal(
            jsonObject(
              jsonObject(jsonDecode(lines.current), 'event')['data'],
              'event',
            )['type'],
            'repeat-started',
          );
          return (child: child, lines: lines, errors: errors);
        }

        var process = await launch(2, 1);
        process.child.kill(ProcessSignal.sigkill);
        await process.child.exitCode;
        await process.lines.cancel();
        equal(await process.errors, '');
        var store = await TrainingStore.open(path);
        late RepeatCheckpoint recovered;
        try {
          final service = RepeatCheckpointService(store);
          final running = await service.show('repeat');
          check(running.reserved);
          equal(
            jsonObject(running.execution['cursor'], 'cursor')['status'],
            'running',
          );
          final before = jsonObject(
            running.execution['cursor'],
            'cursor',
          )['elapsedMilliseconds'];
          await expectCheckpointFailure(
            service.release('repeat', running.version, confirm: true),
          );
          await expectCheckpointFailure(
            service.action(
              'repeat',
              expectedVersion: running.version,
              expectedExecutionVersion: running.execution['version'] as int,
              action: 'resume',
              ownerId: 'fresh',
            ),
          );
          recovered = await service.action(
            'repeat',
            expectedVersion: running.version,
            expectedExecutionVersion: running.execution['version'] as int,
            action: 'recover',
          );
          equal(
            jsonObject(
              recovered.execution['cursor'],
              'cursor',
            )['elapsedMilliseconds'],
            before,
          );
          equal(
            jsonObject(recovered.execution['cursor'], 'cursor')['status'],
            'paused',
          );
        } finally {
          await store.close();
        }
        process = await launch(
          recovered.version,
          recovered.execution['version'] as int,
        );
        process.child.kill(ProcessSignal.sigint);
        check(
          await process.lines.moveNext().timeout(const Duration(seconds: 10)),
        );
        final data = jsonObject(
          jsonObject(jsonDecode(process.lines.current), 'response')['data'],
          'data',
        );
        equal(data['interrupted'], true);
        final checkpoint = jsonObject(data['checkpoint'], 'checkpoint');
        final execution = jsonObject(checkpoint['execution'], 'execution');
        equal(jsonObject(execution['cursor'], 'cursor')['status'], 'paused');
        equal((execution['entries'] as List).length, 0);
        equal(await process.child.exitCode, 0);
        await process.lines.cancel();
        equal(await process.errors, '');
        store = await TrainingStore.open(path);
        try {
          check((await RepeatCheckpointService(store).show('repeat')).reserved);
        } finally {
          await store.close();
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'foreground repeat runner pauses at limits and deadline without recording work',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-repeat-run-');
      final path = '${dir.path}/profile.sqlite';
      try {
        final initialStore = await TrainingStore.open(path);
        try {
          final loop = WindowRepeatSpec.fromJson({
            ...jsonObject(example('window-repeat-page')['loop'], 'loop'),
            'durationMilliseconds': 400,
          });
          final service = RepeatCheckpointService(initialStore);
          await service.save(
            'repeat',
            0,
            const WindowRepeatExecution().start(loop),
          );
          await service.reserve('repeat', 1);
        } finally {
          await initialStore.close();
        }
        Future<Map<String, Object?>> run(
          int checkpointVersion,
          int executionVersion,
          int duration, {
          bool stream = false,
        }) async {
          final response = await invoke(
            ['repeat-checkpoint', 'run'],
            jsonEncode({
              'schemaVersion': 1,
              'database': path,
              'id': 'repeat',
              'expectedVersion': checkpointVersion,
              'expectedExecutionVersion': executionVersion,
              'runForMilliseconds': duration,
              'stream': stream,
            }),
          );
          equal(response.code, 0);
          final lines = const LineSplitter().convert(response.output);
          if (stream) {
            equal(
              jsonObject(
                jsonObject(jsonDecode(lines.first), 'event')['data'],
                'data',
              )['type'],
              'repeat-started',
            );
          }
          return jsonObject(
            jsonObject(jsonDecode(lines.last), 'response')['data'],
            'data',
          );
        }

        final first = await run(2, 1, 100);
        var checkpoint = jsonObject(first['checkpoint'], 'checkpoint');
        var execution = jsonObject(checkpoint['execution'], 'execution');
        var cursor = jsonObject(execution['cursor'], 'cursor');
        equal(cursor['status'], 'paused');
        equal(cursor['elapsedMilliseconds'], 100);
        equal(first['cueCount'], 0);
        check(checkpoint['reserved'] == true);
        final second = await run(
          checkpoint['version'] as int,
          execution['version'] as int,
          1000,
          stream: true,
        );
        checkpoint = jsonObject(second['checkpoint'], 'checkpoint');
        execution = jsonObject(checkpoint['execution'], 'execution');
        cursor = jsonObject(execution['cursor'], 'cursor');
        equal(cursor['status'], 'boundary');
        equal(cursor['elapsedMilliseconds'], 400);
        equal(second['cueCount'], 1);
        equal(
          jsonObject((second['cues'] as List).single, 'cue')['type'],
          'repeat-boundary',
        );
        equal((execution['entries'] as List).length, 0);
        equal(checkpoint['reserved'], true);
        final store = await TrainingStore.open(path);
        try {
          final service = RepeatCheckpointService(store);
          final saved = await service.show('repeat');
          equal(saved.version, checkpoint['version']);
          await expectCheckpointFailure(
            service.action(
              'repeat',
              expectedVersion: saved.version,
              expectedExecutionVersion: saved.execution['version'] as int,
              action: 'finish',
              confirm: true,
            ),
          );
        } finally {
          await store.close();
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'reserved repeat clocks pause with monotonic owner samples before release',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-repeat-clock-pause-',
      );
      final store = await TrainingStore.open('${dir.path}/profile.sqlite');
      try {
        final service = RepeatCheckpointService(store);
        await service.save(
          'repeat',
          0,
          const WindowRepeatExecution().start(
            WindowRepeatSpec.fromJson(example('window-repeat-page')['loop']),
          ),
        );
        await service.reserve('repeat', 1);
        await service.action(
          'repeat',
          expectedVersion: 2,
          expectedExecutionVersion: 1,
          action: 'resume',
          ownerId: 'owner',
        );
        await service.action(
          'repeat',
          expectedVersion: 3,
          expectedExecutionVersion: 2,
          action: 'advance',
          ownerId: 'owner',
          ownerElapsedMilliseconds: 100,
        );
        await expectCheckpointFailure(
          service.action(
            'repeat',
            expectedVersion: 4,
            expectedExecutionVersion: 3,
            action: 'pause',
            ownerId: 'owner',
            ownerElapsedMilliseconds: 99,
          ),
        );
        final paused = await service.action(
          'repeat',
          expectedVersion: 4,
          expectedExecutionVersion: 3,
          action: 'pause',
          ownerId: 'owner',
          ownerElapsedMilliseconds: 150,
        );
        equal(
          jsonObject(
            paused.execution['cursor'],
            'cursor',
          )['elapsedMilliseconds'],
          150,
        );
        equal(
          jsonObject(paused.execution['cursor'], 'cursor')['status'],
          'paused',
        );
        check(paused.reserved);
        final released = await service.release('repeat', 5, confirm: true);
        check(!released.reserved);
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'schema v49 repeat reservations migrate without running clocks',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-repeat-v49-');
      final path = '${dir.path}/profile.sqlite';
      try {
        var store = await TrainingStore.open(path);
        final service = RepeatCheckpointService(store);
        await service.save(
          'repeat',
          0,
          const WindowRepeatExecution().start(
            WindowRepeatSpec.fromJson(example('window-repeat-page')['loop']),
          ),
        );
        await service.reserve('repeat', 1);
        await store.close();
        final raw = sqlite3.open(path);
        raw.execute('DROP TABLE IF EXISTS progression_reconciliations');
        raw.execute('DROP TABLE IF EXISTS lever_link_revisions');
        raw.execute('DROP TABLE IF EXISTS shared_lever_applications');
        raw.execute('DROP TABLE IF EXISTS link_retirement_anchors');
        raw.execute('DROP TABLE IF EXISTS program_upgrade_receipts');
        raw.userVersion = 49;
        raw.close();
        store = await TrainingStore.open(path);
        try {
          final state = await RepeatCheckpointService(store).show('repeat');
          check(state.reserved);
          equal(
            jsonObject(state.execution['cursor'], 'cursor')['status'],
            'paused',
          );
          equal(
            (await store.backup('${dir.path}/backup'))['databaseSchemaVersion'],
            56,
          );
        } finally {
          await store.close();
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'reserved repeat clock samples survive process death without wall-time catch-up',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-repeat-clock-crash-',
      );
      try {
        final path = '${dir.path}/profile.sqlite';
        final store = await TrainingStore.open(path);
        try {
          final service = RepeatCheckpointService(store);
          await service.save(
            'repeat',
            0,
            const WindowRepeatExecution().start(
              WindowRepeatSpec.fromJson(example('window-repeat-page')['loop']),
            ),
          );
          await service.reserve('repeat', 1);
        } finally {
          await store.close();
        }
        final binary = await compileNative(
          'test/helpers/store_owner.dart',
          '${dir.path}/owner',
        );
        for (final mode in ['repeat-clock-rollback', 'repeat-clock-commit']) {
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
            final reopened = await TrainingStore.open(path);
            try {
              final service = RepeatCheckpointService(reopened);
              final state = await service.show('repeat');
              final committed = mode.endsWith('commit');
              check(state.reserved);
              equal(state.version, committed ? 4 : 2);
              final cursor = jsonObject(state.execution['cursor'], 'cursor');
              equal(cursor['status'], committed ? 'running' : 'paused');
              equal(cursor['elapsedMilliseconds'], committed ? 400 : 0);
              if (committed) {
                final recovered = await service.action(
                  'repeat',
                  expectedVersion: 4,
                  expectedExecutionVersion: 3,
                  action: 'recover',
                  adjustmentMilliseconds: 125,
                );
                equal(
                  jsonObject(
                    recovered.execution['cursor'],
                    'cursor',
                  )['elapsedMilliseconds'],
                  525,
                );
                equal(
                  jsonObject(recovered.execution['cursor'], 'cursor')['status'],
                  'paused',
                );
                check(recovered.reserved);
              }
            } finally {
              await reopened.close();
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
    'reserved repeat clocks persist owner samples and recover explicitly',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-repeat-clock-',
      );
      final path = '${dir.path}/profile.sqlite';
      var store = await TrainingStore.open(path);
      try {
        final loop = WindowRepeatSpec.fromJson({
          ...jsonObject(example('window-repeat-page')['loop'], 'loop'),
          'durationMilliseconds': 1000,
        });
        var service = RepeatCheckpointService(store);
        await service.save(
          'repeat',
          0,
          const WindowRepeatExecution().start(loop),
        );
        await expectCheckpointFailure(
          service.action(
            'repeat',
            expectedVersion: 1,
            expectedExecutionVersion: 1,
            action: 'resume',
            ownerId: 'first',
          ),
        );
        await service.reserve('repeat', 1);
        var state = await service.action(
          'repeat',
          expectedVersion: 2,
          expectedExecutionVersion: 1,
          action: 'resume',
          ownerId: 'first',
        );
        check(state.reserved);
        equal(
          jsonObject(state.execution['cursor'], 'cursor')['status'],
          'running',
        );
        await expectCheckpointFailure(
          service.release('repeat', 3, confirm: true),
        );
        await expectCheckpointFailure(
          service.action(
            'repeat',
            expectedVersion: 3,
            expectedExecutionVersion: 2,
            action: 'advance',
            ownerId: 'wrong',
            ownerElapsedMilliseconds: 400,
          ),
        );
        state = await service.action(
          'repeat',
          expectedVersion: 3,
          expectedExecutionVersion: 2,
          action: 'review',
          ownerId: 'first',
          ownerElapsedMilliseconds: 400,
          review: {'outcome': 'completed', 'acceptSuggested': true},
        );
        equal(state.version, 4);
        equal(
          jsonObject(
            state.execution['cursor'],
            'cursor',
          )['elapsedMilliseconds'],
          400,
        );
        equal(
          jsonObject(state.execution['cursor'], 'cursor')['status'],
          'running',
        );
        equal((state.execution['entries'] as List).length, 1);
        await expectCheckpointFailure(
          service.action(
            'repeat',
            expectedVersion: 4,
            expectedExecutionVersion: 3,
            action: 'advance',
            ownerId: 'first',
            ownerElapsedMilliseconds: 399,
          ),
        );
        await store.backup('${dir.path}/native');
        final archivePath = '${dir.path}/logical.json';
        await LogicalArchiveFiles.export(await store.archive(), archivePath);
        final prepared = await LogicalArchiveFiles.prepare(archivePath);
        try {
          equal(
            jsonObject(
              prepared.archive.repeatCheckpoints.single.execution['cursor'],
              'cursor',
            )['status'],
            'running',
          );
        } finally {
          await prepared.close();
        }
        final old = jsonObject(
          jsonDecode(await File(archivePath).readAsString()),
          'archive',
        );
        old['format'] = 'bodytmi-logical-export/49';
        old.remove('sha256');
        old['sha256'] = sha256
            .convert(utf8.encode(canonicalJson(old)))
            .toString();
        final oldPath = '${dir.path}/old.json';
        await File(oldPath).writeAsString(canonicalJson(old));
        await expectCheckpointFailure(LogicalArchiveFiles.prepare(oldPath));
        final oldDbPath = '${dir.path}/old.sqlite';
        await File('${dir.path}/native/database.sqlite').copy(oldDbPath);
        final oldDb = sqlite3.open(oldDbPath);
        oldDb.execute('DROP TABLE IF EXISTS progression_reconciliations');
        oldDb.execute('DROP TABLE IF EXISTS lever_link_revisions');
        oldDb.execute('DROP TABLE IF EXISTS shared_lever_applications');
        oldDb.execute('DROP TABLE IF EXISTS link_retirement_anchors');
        oldDb.execute('DROP TABLE IF EXISTS program_upgrade_receipts');
        oldDb.userVersion = 49;
        oldDb.close();
        rejects(() => NativeBackup.validateDatabase(oldDbPath));
        final native = await NativeBackup.prepare('${dir.path}/native');
        try {
          final restored = await TrainingStore.open(
            '${dir.path}/restored.sqlite',
          );
          try {
            await restored.restore(
              native,
              recoveryDestination: '${dir.path}/recovery',
              confirm: true,
            );
          } finally {
            await restored.close();
          }
          final reopened = await TrainingStore.open(
            '${dir.path}/restored.sqlite',
          );
          try {
            final restoredState = await RepeatCheckpointService(
              reopened,
            ).show('repeat');
            check(restoredState.reserved);
            equal(
              jsonObject(restoredState.execution['cursor'], 'cursor')['status'],
              'running',
            );
          } finally {
            await reopened.close();
          }
        } finally {
          await native.close();
        }
        await store.close();
        store = await TrainingStore.open(path);
        service = RepeatCheckpointService(store);
        state = await service.show('repeat');
        equal(
          jsonObject(state.execution['cursor'], 'cursor')['status'],
          'running',
        );
        await store.close();
        final cli = await invoke(
          ['repeat-checkpoint', 'action'],
          jsonEncode({
            'schemaVersion': 1,
            'database': path,
            'id': 'repeat',
            'expectedVersion': 4,
            'expectedExecutionVersion': 3,
            'action': 'recover',
          }),
        );
        equal(cli.code, 0);
        store = await TrainingStore.open(path);
        service = RepeatCheckpointService(store);
        state = await service.show('repeat');
        equal(
          jsonObject(
            state.execution['cursor'],
            'cursor',
          )['elapsedMilliseconds'],
          400,
        );
        check(state.reserved);
        state = await service.action(
          'repeat',
          expectedVersion: 5,
          expectedExecutionVersion: 4,
          action: 'resume',
          ownerId: 'second',
        );
        state = await service.action(
          'repeat',
          expectedVersion: 6,
          expectedExecutionVersion: 5,
          action: 'advance',
          ownerId: 'second',
          ownerElapsedMilliseconds: 700,
        );
        final boundary = jsonObject(state.execution['cursor'], 'cursor');
        equal(boundary['status'], 'boundary');
        equal(boundary['elapsedMilliseconds'], 1000);
        equal(boundary['unappliedMilliseconds'], 100);
        check(state.reserved);
        state = await service.action(
          'repeat',
          expectedVersion: 7,
          expectedExecutionVersion: 6,
          action: 'review',
          review: {'outcome': 'skipped'},
          confirm: true,
        );
        state = await service.action(
          'repeat',
          expectedVersion: 8,
          expectedExecutionVersion: 7,
          action: 'finish',
          confirm: true,
        );
        check(!state.reserved);
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test('repeat reservation commits or rolls back on process death', () async {
    final dir = await Directory.systemTemp.createTemp(
      'bodytmi-repeat-reservation-crash-',
    );
    try {
      final path = '${dir.path}/profile.sqlite';
      final store = await TrainingStore.open(path);
      try {
        await RepeatCheckpointService(store).save(
          'repeat',
          0,
          const WindowRepeatExecution().start(
            WindowRepeatSpec.fromJson(example('window-repeat-page')['loop']),
          ),
        );
      } finally {
        await store.close();
      }
      final binary = await compileNative(
        'test/helpers/store_owner.dart',
        '${dir.path}/owner',
      );
      for (final mode in ['repeat-reserve-rollback', 'repeat-reserve-commit']) {
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
          final reopened = await TrainingStore.open(path);
          try {
            final saved = await RepeatCheckpointService(
              reopened,
            ).show('repeat');
            final committed = mode.endsWith('commit');
            equal(saved.version, committed ? 2 : 1);
            equal(saved.reserved, committed);
            if (committed)
              await expectCheckpointFailure(
                RepeatCheckpointService(reopened).reserve('repeat', 1),
                'conflict',
              );
          } finally {
            await reopened.close();
          }
        } finally {
          child.kill(ProcessSignal.sigkill);
          await child.exitCode;
        }
      }
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test('schema v48 repeat snapshots migrate without reservations', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-repeat-v48-');
    final path = '${dir.path}/profile.sqlite';
    try {
      var store = await TrainingStore.open(path);
      final execution = const WindowRepeatExecution().start(
        WindowRepeatSpec.fromJson(example('window-repeat-page')['loop']),
      );
      await RepeatCheckpointService(store).save('repeat', 0, execution);
      await store.close();
      final raw = sqlite3.open(path);
      raw.execute('DROP TABLE IF EXISTS progression_reconciliations');
      raw.execute('DROP TABLE IF EXISTS lever_link_revisions');
      raw.execute('DROP TABLE IF EXISTS shared_lever_applications');
      raw.execute('DROP TABLE IF EXISTS link_retirement_anchors');
      raw.execute('DROP TABLE IF EXISTS program_upgrade_receipts');
      raw.userVersion = 48;
      raw.close();
      store = await TrainingStore.open(path);
      try {
        final migrated = await RepeatCheckpointService(store).show('repeat');
        check(!migrated.reserved);
        equal(canonicalJson(migrated.execution), canonicalJson(execution));
        equal(
          (await store.backup('${dir.path}/backup'))['databaseSchemaVersion'],
          56,
        );
      } finally {
        await store.close();
      }
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test(
    'repeat reservations share the profile clock and survive portability',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-repeat-reservation-',
      );
      final path = '${dir.path}/profile.sqlite';
      var store = await TrainingStore.open(path);
      try {
        final training = StoredTrainingService(store);
        final otherWorkout = definition();
        await training.publish(otherWorkout, 0);
        final other = await training.start(
          'other',
          otherWorkout.id,
          1,
          instant(1),
        );
        final scopedInput = definition().toJson();
        scopedInput['id'] = 'scoped-repeat-test';
        scopedInput['plan'] = {
          'id': 'window',
          'type': 'window',
          'durationSeconds': 5,
          'child': {'id': 'set', 'type': 'effort', 'slot': 'bench-heavy'},
        };
        final scopedWorkout = WorkoutDefinition.fromJson(scopedInput);
        await training.publish(scopedWorkout, 0);
        final scoped = await training.start(
          'scoped',
          scopedWorkout.id,
          1,
          instant(1),
        );
        final windows = WindowCheckpointService(store);
        await windows.save(
          'window',
          scoped.id,
          0,
          const SessionWindowClock().start(scoped),
        );
        final repeats = RepeatCheckpointService(store);
        final loop = WindowRepeatSpec.fromJson(
          example('window-repeat-page')['loop'],
        );
        final execution = const WindowRepeatExecution().start(loop);
        await repeats.save('one', 0, execution);
        await repeats.save('two', 0, execution);
        var first = await repeats.reserve('one', 1);
        equal(first.reserved, true);
        await expectCheckpointFailure(repeats.reserve('two', 1), 'conflict');
        await expectCheckpointFailure(windows.reserve('window', 1), 'conflict');
        final plan = TimingPlan.fromJson({
          'unplannedDuration': true,
          'effortMilliseconds': 1000,
        });
        await expectCheckpointFailure(
          TimingService(store).start(
            'timer',
            other.id,
            other.sets.first.id,
            'duration',
            plan,
            instant(1),
          ),
          'conflict',
        );
        await expectCheckpointFailure(repeats.save('one', 2, execution));
        await expectCheckpointFailure(repeats.delete('one', 2, confirm: true));
        await expectCheckpointFailure(
          repeats.release('one', 2, confirm: false),
        );
        final duplicate = copyJson((await store.archive()).toJson());
        jsonObject(
          jsonList(duplicate, 'repeatCheckpoints').last,
          'checkpoint',
        )['reserved'] = true;
        rejects(() => TrainingArchive.fromJson(duplicate));
        await store.backup('${dir.path}/native');
        final archive = '${dir.path}/logical.json';
        await LogicalArchiveFiles.export(await store.archive(), archive);
        final old = jsonObject(
          jsonDecode(await File(archive).readAsString()),
          'archive',
        );
        old['format'] = 'bodytmi-logical-export/48';
        old.remove('sha256');
        old['sha256'] = sha256
            .convert(utf8.encode(canonicalJson(old)))
            .toString();
        final oldPath = '${dir.path}/old.json';
        await File(oldPath).writeAsString(canonicalJson(old));
        await expectCheckpointFailure(LogicalArchiveFiles.prepare(oldPath));
        final oldDbPath = '${dir.path}/old.sqlite';
        await File('${dir.path}/native/database.sqlite').copy(oldDbPath);
        final oldDb = sqlite3.open(oldDbPath);
        oldDb.execute('DROP TABLE IF EXISTS progression_reconciliations');
        oldDb.execute('DROP TABLE IF EXISTS lever_link_revisions');
        oldDb.execute('DROP TABLE IF EXISTS shared_lever_applications');
        oldDb.execute('DROP TABLE IF EXISTS link_retirement_anchors');
        oldDb.execute('DROP TABLE IF EXISTS program_upgrade_receipts');
        oldDb.userVersion = 48;
        oldDb.close();
        rejects(() => NativeBackup.validateDatabase(oldDbPath));
        final collisionDbPath = '${dir.path}/collision.sqlite';
        await File('${dir.path}/native/database.sqlite').copy(collisionDbPath);
        final collisionDb = sqlite3.open(collisionDbPath);
        final snapshot = jsonObject(
          jsonDecode(
            collisionDb
                    .select(
                      "SELECT snapshot FROM repeat_checkpoints WHERE id = 'two'",
                    )
                    .single['snapshot']
                as String,
          ),
          'checkpoint',
        );
        snapshot['reserved'] = true;
        collisionDb.execute(
          "UPDATE repeat_checkpoints SET snapshot=? WHERE id='two'",
          [canonicalJson(snapshot)],
        );
        collisionDb.close();
        rejects(() => NativeBackup.validateDatabase(collisionDbPath));
        final prepared = await LogicalArchiveFiles.prepare(archive);
        try {
          check(prepared.archive.repeatCheckpoints.first.reserved);
        } finally {
          await prepared.close();
        }
        final native = await NativeBackup.prepare('${dir.path}/native');
        try {
          final restored = await TrainingStore.open(
            '${dir.path}/restored.sqlite',
          );
          try {
            await restored.restore(
              native,
              recoveryDestination: '${dir.path}/recovery',
              confirm: true,
            );
          } finally {
            await restored.close();
          }
          final reopened = await TrainingStore.open(
            '${dir.path}/restored.sqlite',
          );
          try {
            check(
              (await RepeatCheckpointService(reopened).show('one')).reserved,
            );
          } finally {
            await reopened.close();
          }
        } finally {
          await native.close();
        }
        await store.close();
        final cli = await invoke([
          'repeat-checkpoint',
          'show',
        ], jsonEncode({'schemaVersion': 1, 'database': path, 'id': 'one'}));
        equal(cli.code, 0);
        equal(
          jsonObject(
            jsonObject(jsonDecode(cli.output), 'response')['data'],
            'checkpoint',
          )['reserved'],
          true,
        );
        store = await TrainingStore.open(path);
        first = await RepeatCheckpointService(store).show('one');
        check(first.reserved);
        first = await RepeatCheckpointService(store).action(
          'one',
          expectedVersion: 2,
          expectedExecutionVersion: 1,
          action: 'elapse',
          elapsedMilliseconds: 100,
        );
        check(first.reserved);
        first = await RepeatCheckpointService(store).action(
          'one',
          expectedVersion: 3,
          expectedExecutionVersion: 3,
          action: 'stop',
          confirm: true,
        );
        check(!first.reserved);
        final timer = await TimingService(store).start(
          'timer',
          other.id,
          other.sets.first.id,
          'duration',
          plan,
          instant(1),
        );
        await expectCheckpointFailure(
          RepeatCheckpointService(store).reserve('two', 1),
          'conflict',
        );
        await TimingService(store).stop(
          timer.id,
          timer.version,
          instant(1),
          confirm: true,
          discard: true,
        );
        final window = await WindowCheckpointService(
          store,
        ).reserve('window', 1);
        await expectCheckpointFailure(
          RepeatCheckpointService(store).reserve('two', 1),
          'conflict',
        );
        await WindowCheckpointService(
          store,
        ).release('window', window.version, confirm: true);
        final second = await RepeatCheckpointService(store).reserve('two', 1);
        check(second.reserved);
        final released = await RepeatCheckpointService(
          store,
        ).release('two', second.version, confirm: true);
        check(!released.reserved);
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'stored repeat elapsed review commits or rolls back on process death',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-repeat-review-elapsed-crash-',
      );
      try {
        final path = '${dir.path}/profile.sqlite';
        final store = await TrainingStore.open(path);
        try {
          await RepeatCheckpointService(store).save(
            'repeat',
            0,
            const WindowRepeatExecution().start(
              WindowRepeatSpec.fromJson(example('window-repeat-page')['loop']),
            ),
          );
        } finally {
          await store.close();
        }
        final binary = await compileNative(
          'test/helpers/store_owner.dart',
          '${dir.path}/owner',
        );
        for (final mode in [
          'repeat-review-elapsed-rollback',
          'repeat-review-elapsed-commit',
        ]) {
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
            final reopened = await TrainingStore.open(path);
            try {
              final saved = await RepeatCheckpointService(
                reopened,
              ).show('repeat');
              final committed = mode.endsWith('commit');
              equal(saved.version, committed ? 2 : 1);
              equal(saved.execution['version'], committed ? 4 : 1);
              equal(
                jsonObject(
                  saved.execution['cursor'],
                  'cursor',
                )['elapsedMilliseconds'],
                committed ? 400 : 0,
              );
              equal(
                (saved.execution['entries'] as List).length,
                committed ? 1 : 0,
              );
              if (committed)
                await expectCheckpointFailure(
                  RepeatCheckpointService(reopened).action(
                    'repeat',
                    expectedVersion: 1,
                    expectedExecutionVersion: 1,
                    action: 'review-elapsed',
                    elapsedMilliseconds: 400,
                    review: {'outcome': 'completed', 'acceptSuggested': true},
                  ),
                  'conflict',
                );
            } finally {
              await reopened.close();
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
    'stored elapsed rest review yields to deadline and preserves explicit limits',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-repeat-rest-elapsed-',
      );
      try {
        final base = jsonObject(example('window-repeat-page')['loop'], 'loop');
        final definition = jsonObject(
          base['roundDefinition'],
          'roundDefinition',
        );
        final loop = WindowRepeatSpec.fromJson({
          ...base,
          'durationMilliseconds': 1000,
          'roundDefinition': {
            ...definition,
            'plan': {
              'id': 'round',
              'type': 'sequence',
              'children': [
                {'id': 'rest', 'type': 'rest', 'manual': true},
                {'id': 'push-set', 'type': 'effort', 'slot': 'push'},
              ],
            },
          },
        });
        final store = await TrainingStore.open('${dir.path}/profile.sqlite');
        try {
          final service = RepeatCheckpointService(store);
          await service.save(
            'rest',
            0,
            const WindowRepeatExecution().start(loop),
          );
          final result = await service.action(
            'rest',
            expectedVersion: 1,
            expectedExecutionVersion: 1,
            action: 'review-elapsed',
            elapsedMilliseconds: 1200,
            review: {'outcome': 'rest'},
            confirm: true,
          );
          final cursor = jsonObject(result.execution['cursor'], 'cursor');
          equal(cursor['status'], 'boundary');
          equal(cursor['unappliedMilliseconds'], 200);
          equal((result.execution['entries'] as List).length, 0);
          final limited = WindowRepeatSpec.fromJson({
            ...base,
            'maxRounds': 1,
            'maxOccurrences': 2,
          });
          await service.save(
            'limit',
            0,
            const WindowRepeatExecution().start(limited),
          );
          var value = await service.action(
            'limit',
            expectedVersion: 1,
            expectedExecutionVersion: 1,
            action: 'review-elapsed',
            elapsedMilliseconds: 100,
            review: {'outcome': 'skipped'},
            confirm: true,
          );
          equal(value.execution['version'], 4);
          value = await service.action(
            'limit',
            expectedVersion: 2,
            expectedExecutionVersion: 4,
            action: 'review-elapsed',
            elapsedMilliseconds: 100,
            review: {'outcome': 'skipped'},
            confirm: true,
          );
          equal(value.execution['version'], 6);
          equal(
            jsonObject(value.execution['cursor'], 'cursor')['status'],
            'limitReached',
          );
          equal((value.execution['entries'] as List).length, 2);
        } finally {
          await store.close();
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'stored repeat elapsed reviews atomically record time and results',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-repeat-review-elapsed-',
      );
      final path = '${dir.path}/profile.sqlite';
      try {
        final loop = WindowRepeatSpec.fromJson({
          ...jsonObject(example('window-repeat-page')['loop'], 'loop'),
          'durationMilliseconds': 1000,
        });
        var store = await TrainingStore.open(path);
        var service = RepeatCheckpointService(store);
        await service.save(
          'repeat',
          0,
          const WindowRepeatExecution().start(loop),
        );
        await expectCheckpointFailure(
          service.action(
            'repeat',
            expectedVersion: 1,
            expectedExecutionVersion: 1,
            action: 'review-elapsed',
            elapsedMilliseconds: 400,
            review: {'outcome': 'completed'},
          ),
        );
        var result = await service.show('repeat');
        equal(result.version, 1);
        equal(
          jsonObject(
            result.execution['cursor'],
            'cursor',
          )['elapsedMilliseconds'],
          0,
        );
        result = await service.action(
          'repeat',
          expectedVersion: 1,
          expectedExecutionVersion: 1,
          action: 'review-elapsed',
          elapsedMilliseconds: 400,
          review: {'outcome': 'completed', 'acceptSuggested': true},
        );
        equal(result.version, 2);
        equal(result.execution['version'], 4);
        var cursor = jsonObject(result.execution['cursor'], 'cursor');
        equal(cursor['status'], 'paused');
        equal(cursor['elapsedMilliseconds'], 400);
        equal(cursor['occurrence'], 1);
        equal((result.execution['entries'] as List).length, 1);
        await expectCheckpointFailure(
          service.action(
            'repeat',
            expectedVersion: 1,
            expectedExecutionVersion: 1,
            action: 'review-elapsed',
            elapsedMilliseconds: 400,
            review: {'outcome': 'completed', 'acceptSuggested': true},
          ),
          'conflict',
        );
        await store.close();
        final request = {
          'schemaVersion': 1,
          'database': path,
          'id': 'repeat',
          'expectedVersion': 2,
          'expectedExecutionVersion': 4,
          'action': 'review-elapsed',
          'elapsedMilliseconds': 700,
          'review': {
            'outcome': 'completed',
            'actuals': {
              'reps': {'value': '3', 'unit': 'rep'},
            },
            'observations': {'terminationReason': 'interrupted'},
          },
        };
        final cli = await invoke([
          'repeat-checkpoint',
          'action',
        ], jsonEncode(request));
        equal(cli.code, 0);
        final saved = jsonObject(
          jsonObject(jsonDecode(cli.output), 'response')['data'],
          'checkpoint',
        );
        equal(saved['version'], 3);
        final execution = jsonObject(saved['execution'], 'execution');
        equal(execution['version'], 6);
        cursor = jsonObject(execution['cursor'], 'cursor');
        equal(cursor['status'], 'boundary');
        equal(cursor['elapsedMilliseconds'], 1000);
        equal(cursor['unappliedMilliseconds'], 100);
        equal(
          jsonObject(
            (execution['entries'] as List).last,
            'entry',
          )['reportedAfterBoundary'],
          true,
        );
        equal(
          const WindowRepeatExecution().view(execution)['partialRounds'],
          1,
        );
        store = await TrainingStore.open(path);
        service = RepeatCheckpointService(store);
        try {
          equal(
            canonicalJson((await service.show('repeat')).execution),
            canonicalJson(execution),
          );
          result = await service.action(
            'repeat',
            expectedVersion: 3,
            expectedExecutionVersion: 6,
            action: 'finish',
            confirm: true,
          );
          equal(
            jsonObject(result.execution['cursor'], 'cursor')['status'],
            'finished',
          );
          final file = '${dir.path}/archive.json';
          await LogicalArchiveFiles.export(await store.archive(), file);
          final prepared = await LogicalArchiveFiles.prepare(file);
          try {
            equal(
              canonicalJson(prepared.archive.repeatCheckpoints.single.toJson()),
              canonicalJson(result.toJson()),
            );
          } finally {
            await prepared.close();
          }
        } finally {
          await store.close();
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'stored repeat elapsed samples commit or roll back on process death',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-repeat-elapse-crash-',
      );
      try {
        final path = '${dir.path}/profile.sqlite';
        final store = await TrainingStore.open(path);
        try {
          await RepeatCheckpointService(store).save(
            'repeat',
            0,
            const WindowRepeatExecution().start(
              WindowRepeatSpec.fromJson(example('window-repeat-page')['loop']),
            ),
          );
        } finally {
          await store.close();
        }
        final binary = await compileNative(
          'test/helpers/store_owner.dart',
          '${dir.path}/owner',
        );
        for (final mode in ['repeat-elapse-rollback', 'repeat-elapse-commit']) {
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
            final reopened = await TrainingStore.open(path);
            try {
              final saved = await RepeatCheckpointService(
                reopened,
              ).show('repeat');
              final committed = mode.endsWith('commit');
              equal(saved.version, committed ? 2 : 1);
              equal(saved.execution['version'], committed ? 3 : 1);
              equal(
                jsonObject(
                  saved.execution['cursor'],
                  'cursor',
                )['elapsedMilliseconds'],
                committed ? 400 : 0,
              );
              equal((saved.execution['entries'] as List).length, 0);
            } finally {
              await reopened.close();
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
    'stored repeat elapsed samples stop at the deadline without logging work',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-repeat-elapse-',
      );
      final path = '${dir.path}/profile.sqlite';
      try {
        final loop = WindowRepeatSpec.fromJson({
          ...jsonObject(example('window-repeat-page')['loop'], 'loop'),
          'durationMilliseconds': 1000,
        });
        var store = await TrainingStore.open(path);
        var service = RepeatCheckpointService(store);
        await service.save(
          'repeat',
          0,
          const WindowRepeatExecution().start(loop),
        );
        await expectCheckpointFailure(
          service.action(
            'repeat',
            expectedVersion: 1,
            expectedExecutionVersion: 1,
            action: 'elapse',
            elapsedMilliseconds: 0,
          ),
        );
        await expectCheckpointFailure(
          service.action(
            'repeat',
            expectedVersion: 1,
            expectedExecutionVersion: 1,
            action: 'elapse',
            elapsedMilliseconds: 400,
            review: {'outcome': 'skipped'},
          ),
        );
        equal((await service.show('repeat')).version, 1);
        var checkpoint = await service.action(
          'repeat',
          expectedVersion: 1,
          expectedExecutionVersion: 1,
          action: 'elapse',
          elapsedMilliseconds: 400,
        );
        equal(checkpoint.version, 2);
        equal(checkpoint.execution['version'], 3);
        var cursor = jsonObject(checkpoint.execution['cursor'], 'cursor');
        equal(cursor['status'], 'paused');
        equal(cursor['elapsedMilliseconds'], 400);
        equal((checkpoint.execution['entries'] as List).length, 0);
        await expectCheckpointFailure(
          service.action(
            'repeat',
            expectedVersion: 1,
            expectedExecutionVersion: 1,
            action: 'elapse',
            elapsedMilliseconds: 400,
          ),
          'conflict',
        );
        await expectCheckpointFailure(
          service.action(
            'repeat',
            expectedVersion: 2,
            expectedExecutionVersion: 2,
            action: 'elapse',
            elapsedMilliseconds: 400,
          ),
          'conflict',
        );
        await store.close();
        final request = {
          'schemaVersion': 1,
          'database': path,
          'id': 'repeat',
          'expectedVersion': 2,
          'expectedExecutionVersion': 3,
          'action': 'elapse',
          'elapsedMilliseconds': 700,
        };
        final result = await invoke([
          'repeat-checkpoint',
          'action',
        ], jsonEncode(request));
        equal(result.code, 0);
        final json = jsonObject(
          jsonObject(jsonDecode(result.output), 'response')['data'],
          'checkpoint',
        );
        equal(json['version'], 3);
        final execution = jsonObject(json['execution'], 'execution');
        equal(execution['version'], 5);
        cursor = jsonObject(execution['cursor'], 'cursor');
        equal(cursor['status'], 'boundary');
        equal(cursor['elapsedMilliseconds'], 1000);
        equal(cursor['unappliedMilliseconds'], 100);
        equal((execution['entries'] as List).length, 0);
        store = await TrainingStore.open(path);
        service = RepeatCheckpointService(store);
        try {
          await expectCheckpointFailure(
            service.action(
              'repeat',
              expectedVersion: 3,
              expectedExecutionVersion: 5,
              action: 'elapse',
              elapsedMilliseconds: 1,
            ),
          );
          checkpoint = await service.action(
            'repeat',
            expectedVersion: 3,
            expectedExecutionVersion: 5,
            action: 'review',
            review: {'outcome': 'skipped'},
            confirm: true,
          );
          equal(checkpoint.version, 4);
          equal((checkpoint.execution['entries'] as List).length, 1);
          final backup = '${dir.path}/backup';
          await store.backup(backup);
          final archive = '${dir.path}/archive.json';
          await LogicalArchiveFiles.export(await store.archive(), archive);
          final prepared = await LogicalArchiveFiles.prepare(archive);
          try {
            equal(
              canonicalJson(prepared.archive.repeatCheckpoints.single.toJson()),
              canonicalJson(checkpoint.toJson()),
            );
          } finally {
            await prepared.close();
          }
          equal(NativeBackup.validateDatabase('$backup/database.sqlite'), 56);
        } finally {
          await store.close();
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test('stored repeat review commits or rolls back on process death', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-repeat-crash-');
    try {
      final path = '${dir.path}/profile.sqlite';
      final store = await TrainingStore.open(path);
      try {
        final loop = WindowRepeatSpec.fromJson(
          example('window-repeat-page')['loop'],
        );
        await RepeatCheckpointService(
          store,
        ).save('repeat', 0, const WindowRepeatExecution().start(loop));
      } finally {
        await store.close();
      }
      final binary = await compileNative(
        'test/helpers/store_owner.dart',
        '${dir.path}/owner',
      );
      for (final mode in ['repeat-action-rollback', 'repeat-action-commit']) {
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
          final reopened = await TrainingStore.open(path);
          try {
            final saved = await RepeatCheckpointService(
              reopened,
            ).show('repeat');
            final committed = mode.endsWith('commit');
            equal(saved.version, committed ? 2 : 1);
            equal(saved.execution['version'], committed ? 2 : 1);
            equal(
              (saved.execution['entries'] as List).length,
              committed ? 1 : 0,
            );
            if (committed) {
              await expectCheckpointFailure(
                RepeatCheckpointService(reopened).action(
                  'repeat',
                  expectedVersion: 1,
                  expectedExecutionVersion: 1,
                  action: 'review',
                  review: {'outcome': 'completed', 'acceptSuggested': true},
                ),
                'conflict',
              );
            }
          } finally {
            await reopened.close();
          }
        } finally {
          child.kill(ProcessSignal.sigkill);
          await child.exitCode;
        }
      }
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test(
    'stored repeat batch review survives logical export and refuses clock actions',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-repeat-batch-',
      );
      try {
        final loop = WindowRepeatSpec.fromJson({
          ...jsonObject(example('window-repeat-page')['loop'], 'loop'),
          'durationMilliseconds': 1000,
        });
        const engine = WindowRepeatExecution();
        var state = engine.start(loop);
        state = engine.apply(
          state,
          expectedVersion: 1,
          action: 'resume',
          ownerId: 'owner',
        );
        state = engine.apply(
          state,
          expectedVersion: 2,
          action: 'advance',
          ownerId: 'owner',
          ownerElapsedMilliseconds: 1100,
        );
        final store = await TrainingStore.open('${dir.path}/profile.sqlite');
        try {
          final service = RepeatCheckpointService(store);
          await service.save('repeat', 0, state);
          await expectCheckpointFailure(
            service.action(
              'repeat',
              expectedVersion: 1,
              expectedExecutionVersion: 3,
              action: 'recover',
            ),
          );
          final batch = {
            'reviews': [
              {
                'occurrenceId': 'amrap[0]/round/push-set',
                'outcome': 'completed',
                'acceptSuggested': true,
              },
              {'occurrenceId': 'amrap[0]/round/pull-set', 'outcome': 'skipped'},
            ],
          };
          await expectCheckpointFailure(
            service.action(
              'repeat',
              expectedVersion: 1,
              expectedExecutionVersion: 3,
              action: 'review-batch',
              review: batch,
            ),
          );
          final result = await service.action(
            'repeat',
            expectedVersion: 1,
            expectedExecutionVersion: 3,
            action: 'review-batch',
            review: batch,
            confirm: true,
          );
          equal(engine.view(result.execution)['partialRounds'], 1);
          equal(engine.view(result.execution)['reportedAfterBoundary'], 2);
          final file = '${dir.path}/export.json';
          await LogicalArchiveFiles.export(await store.archive(), file);
          final prepared = await LogicalArchiveFiles.prepare(file);
          try {
            equal(
              canonicalJson(prepared.archive.repeatCheckpoints.single.toJson()),
              canonicalJson(result.toJson()),
            );
          } finally {
            await prepared.close();
          }
        } finally {
          await store.close();
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'stored repeat actions atomically review and correct inert checkpoints',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-repeat-action-',
      );
      final path = '${dir.path}/profile.sqlite';
      try {
        final loop = WindowRepeatSpec.fromJson({
          ...jsonObject(example('window-repeat-page')['loop'], 'loop'),
          'maxRounds': 1,
          'maxOccurrences': 2,
        });
        var store = await TrainingStore.open(path);
        var service = RepeatCheckpointService(store);
        await service.save(
          'repeat',
          0,
          const WindowRepeatExecution().start(loop),
        );
        await expectCheckpointFailure(
          service.action(
            'repeat',
            expectedVersion: 1,
            expectedExecutionVersion: 1,
            action: 'resume',
          ),
        );
        await expectCheckpointFailure(
          service.action(
            'repeat',
            expectedVersion: 1,
            expectedExecutionVersion: 1,
            action: 'review',
            review: {'outcome': 'completed'},
          ),
        );
        equal((await service.show('repeat')).version, 1);
        var result = await service.action(
          'repeat',
          expectedVersion: 1,
          expectedExecutionVersion: 1,
          action: 'review',
          review: {'outcome': 'completed', 'acceptSuggested': true},
        );
        equal(result.version, 2);
        equal(result.execution['version'], 2);
        await expectCheckpointFailure(
          service.action(
            'repeat',
            expectedVersion: 1,
            expectedExecutionVersion: 2,
            action: 'review',
            review: {'outcome': 'skipped'},
            confirm: true,
          ),
          'conflict',
        );
        await expectCheckpointFailure(
          service.action(
            'repeat',
            expectedVersion: 2,
            expectedExecutionVersion: 1,
            action: 'review',
            review: {'outcome': 'skipped'},
            confirm: true,
          ),
          'conflict',
        );
        equal((await service.show('repeat')).version, 2);
        await store.close();
        final request = {
          'schemaVersion': 1,
          'database': path,
          'id': 'repeat',
          'expectedVersion': 2,
          'expectedExecutionVersion': 2,
          'action': 'review',
          'review': {'outcome': 'skipped'},
          'confirm': true,
        };
        final cli = await invoke([
          'repeat-checkpoint',
          'action',
        ], jsonEncode(request));
        equal(cli.code, 0);
        equal(
          jsonObject(
            jsonObject(jsonDecode(cli.output), 'response')['data'],
            'checkpoint',
          )['version'],
          3,
        );
        final retry = await invoke([
          'repeat-checkpoint',
          'action',
        ], jsonEncode(request));
        check(retry.code != 0);
        store = await TrainingStore.open(path);
        service = RepeatCheckpointService(store);
        result = await service.action(
          'repeat',
          expectedVersion: 3,
          expectedExecutionVersion: 3,
          action: 'finish',
          confirm: true,
        );
        result = await service.action(
          'repeat',
          expectedVersion: 4,
          expectedExecutionVersion: 4,
          action: 'revise',
          correction: {
            'occurrenceId': 'amrap[0]/round/pull-set',
            'outcome': 'completed',
            'actuals': {
              'reps': {'value': '3', 'unit': 'rep'},
            },
          },
        );
        equal(
          const WindowRepeatExecution().view(
            result.execution,
          )['confirmedRounds'],
          1,
        );
        equal(
          jsonObject(result.execution['cursor'], 'cursor')['status'],
          'finished',
        );
        await store.backup('${dir.path}/backup');
        await store.close();
        final prepared = await NativeBackup.prepare('${dir.path}/backup');
        try {
          final restored = await TrainingStore.open(
            '${dir.path}/restored.sqlite',
          );
          try {
            await restored.restore(
              prepared,
              recoveryDestination: '${dir.path}/recovery',
              confirm: true,
            );
          } finally {
            await restored.close();
          }
        } finally {
          await prepared.close();
        }
        final restored = await TrainingStore.open(
          '${dir.path}/restored.sqlite',
        );
        try {
          equal(
            (await RepeatCheckpointService(restored).show('repeat')).version,
            5,
          );
        } finally {
          await restored.close();
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test('schema v47 migrates to empty repeat checkpoints', () async {
    final directory = await Directory.systemTemp.createTemp(
      'bodytmi-repeat-migration-',
    );
    final path = '${directory.path}/profile.sqlite';
    try {
      final initial = await TrainingStore.open(path);
      await initial.close();
      final raw = sqlite3.open(path);
      raw.execute('DROP TABLE repeat_checkpoints');
      raw.execute('DROP TABLE IF EXISTS progression_reconciliations');
      raw.execute('DROP TABLE IF EXISTS lever_link_revisions');
      raw.execute('DROP TABLE IF EXISTS shared_lever_applications');
      raw.execute('DROP TABLE IF EXISTS link_retirement_anchors');
      raw.execute('DROP TABLE IF EXISTS program_upgrade_receipts');
      raw.userVersion = 47;
      raw.close();
      final store = await TrainingStore.open(path);
      try {
        equal((await store.repeatCheckpoints()).length, 0);
        equal(
          (await store.backup(
            '${directory.path}/migrated',
          ))['databaseSchemaVersion'],
          56,
        );
      } finally {
        await store.close();
      }
    } finally {
      await directory.delete(recursive: true);
    }
  });
  test(
    'inert repeat checkpoints persist, reject conflicts and survive archives',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'bodytmi-repeat-checkpoint-',
      );
      final path = '${directory.path}/profile.sqlite';
      try {
        final loop = WindowRepeatSpec.fromJson(
          example('window-repeat-page')['loop'],
        );
        const engine = WindowRepeatExecution();
        var state = engine.start(loop);
        var store = await TrainingStore.open(path);
        var service = RepeatCheckpointService(store);
        var saved = await service.save('repeat-one', 0, state);
        equal(saved.version, 1);
        await expectCheckpointFailure(
          service.save('repeat-one', 0, state),
          'conflict',
        );
        final running = engine.apply(
          state,
          expectedVersion: 1,
          action: 'resume',
          ownerId: 'owner',
        );
        await expectCheckpointFailure(service.save('repeat-one', 1, running));
        state = engine.apply(
          state,
          expectedVersion: 1,
          action: 'review',
          review: {'outcome': 'completed', 'acceptSuggested': true},
        );
        saved = await service.save('repeat-one', 1, state);
        equal(saved.version, 2);
        equal(canonicalJson(saved.execution), canonicalJson(state));
        final existingEntry = jsonObject(
          (state['entries'] as List).single,
          'entry',
        );
        final forgedState = {
          ...state,
          'entries': [
            {
              ...existingEntry,
              'actuals': {
                'reps': {'value': '7', 'unit': 'rep'},
              },
            },
          ],
        };
        await expectCheckpointFailure(
          service.save('repeat-one', 2, forgedState),
        );
        await expectCheckpointFailure(
          service.save('repeat-one', 2, engine.start(loop)),
        );
        final changedLoop = WindowRepeatSpec.fromJson({
          ...loop.toJson(),
          'durationMilliseconds': 999,
        });
        await expectCheckpointFailure(
          service.save('repeat-one', 2, engine.start(changedLoop)),
        );
        equal((await service.show('repeat-one')).version, 2);
        final backupPath = '${directory.path}/backup';
        await store.backup(backupPath);
        final archivePath = '${directory.path}/archive.json';
        await LogicalArchiveFiles.export(await store.archive(), archivePath);
        final oldEnvelope = jsonObject(
          jsonDecode(await File(archivePath).readAsString()),
          'archive',
        );
        oldEnvelope['format'] = 'bodytmi-logical-export/47';
        oldEnvelope.remove('sha256');
        oldEnvelope['sha256'] = sha256
            .convert(utf8.encode(canonicalJson(oldEnvelope)))
            .toString();
        final forgedPath = '${directory.path}/old-label.json';
        await File(forgedPath).writeAsString(canonicalJson(oldEnvelope));
        await expectCheckpointFailure(LogicalArchiveFiles.prepare(forgedPath));
        final forgedDbPath = '${directory.path}/forged.sqlite';
        await File('$backupPath/database.sqlite').copy(forgedDbPath);
        final forgedDb = sqlite3.open(forgedDbPath);
        forgedDb.execute("UPDATE repeat_checkpoints SET id='wrong'");
        forgedDb.close();
        rejects(() => NativeBackup.validateDatabase(forgedDbPath));
        await store.close();
        store = await TrainingStore.open(path);
        service = RepeatCheckpointService(store);
        equal(
          canonicalJson((await service.show('repeat-one')).execution),
          canonicalJson(state),
        );
        equal((await service.list()).length, 1);
        await expectCheckpointFailure(
          service.delete('repeat-one', 2, confirm: false),
        );
        await expectCheckpointFailure(
          service.delete('repeat-one', 1, confirm: true),
          'conflict',
        );
        final native = await NativeBackup.prepare(backupPath);
        try {
          await store.restore(
            native,
            recoveryDestination: '${directory.path}/recovery',
            confirm: true,
          );
        } finally {
          await native.close();
        }
        await store.close();
        store = await TrainingStore.open(path);
        equal(
          canonicalJson(
            (await RepeatCheckpointService(store).show('repeat-one')).execution,
          ),
          canonicalJson(state),
        );
        await store.close();
        final logical = await LogicalArchiveFiles.prepare(archivePath);
        try {
          equal(
            canonicalJson(logical.archive.repeatCheckpoints.single.execution),
            canonicalJson(state),
          );
          final restored = await TrainingStore.open(
            '${directory.path}/logical.sqlite',
          );
          try {
            await restored.restore(
              logical.backup,
              recoveryDestination: '${directory.path}/logical-recovery',
              confirm: true,
            );
          } finally {
            await restored.close();
          }
          final reopened = await TrainingStore.open(
            '${directory.path}/logical.sqlite',
          );
          try {
            equal(
              canonicalJson(
                (await RepeatCheckpointService(
                  reopened,
                ).show('repeat-one')).execution,
              ),
              canonicalJson(state),
            );
          } finally {
            await reopened.close();
          }
        } finally {
          await logical.close();
        }
        final show = await invoke(
          ['repeat-checkpoint', 'show'],
          jsonEncode({
            'schemaVersion': 1,
            'database': path,
            'id': 'repeat-one',
          }),
        );
        equal(show.code, 0);
        jsonEqual(
          jsonObject(jsonDecode(show.output), 'response')['data'],
          saved.toJson(),
        );
        final delete = await invoke(
          ['repeat-checkpoint', 'delete'],
          jsonEncode({
            'schemaVersion': 1,
            'database': path,
            'id': 'repeat-one',
            'expectedVersion': 2,
            'confirm': true,
          }),
        );
        equal(delete.code, 0);
        final list = await invoke([
          'repeat-checkpoint',
          'list',
        ], jsonEncode({'schemaVersion': 1, 'database': path}));
        equal(list.code, 0);
        equal(
          (jsonObject(jsonDecode(list.output), 'response')['data'] as List)
              .length,
          0,
        );
        final create = await invoke(
          ['repeat-checkpoint', 'save'],
          jsonEncode({
            'schemaVersion': 1,
            'database': path,
            'id': 'created-by-cli',
            'expectedVersion': 0,
            'execution': state,
          }),
        );
        equal(create.code, 0);
        equal(
          jsonObject(
            jsonObject(jsonDecode(create.output), 'response')['data'],
            'checkpoint',
          )['version'],
          1,
        );
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
  test(
    'repeat outcome revisions repair skips and confirm discarding actuals',
    () async {
      final loop = WindowRepeatSpec.fromJson({
        ...jsonObject(example('window-repeat-page')['loop'], 'loop'),
        'maxRounds': 1,
        'maxOccurrences': 2,
      });
      const engine = WindowRepeatExecution();
      var state = engine.start(loop);
      state = engine.apply(
        state,
        expectedVersion: 1,
        action: 'review',
        review: {'outcome': 'skipped'},
        confirm: true,
      );
      state = engine.apply(
        state,
        expectedVersion: 2,
        action: 'review',
        review: {'outcome': 'completed', 'acceptSuggested': true},
      );
      state = engine.apply(
        state,
        expectedVersion: 3,
        action: 'finish',
        confirm: true,
      );
      equal(engine.view(state)['partialRounds'], 1);
      final cursor = state['cursor'];
      const first = 'amrap[0]/round/push-set';
      const second = 'amrap[0]/round/pull-set';
      rejects(
        () => engine.apply(
          state,
          expectedVersion: 4,
          action: 'revise',
          correction: {'occurrenceId': second, 'outcome': 'skipped'},
        ),
      );
      rejects(
        () => engine.apply(
          state,
          expectedVersion: 4,
          action: 'revise',
          correction: {'occurrenceId': first, 'outcome': 'completed'},
        ),
      );
      final request = {
        'schemaVersion': 1,
        'action': 'revise',
        'execution': state,
        'expectedVersion': 4,
        'correction': {
          'occurrenceId': first,
          'outcome': 'completed',
          'actuals': {
            'reps': {'value': '4', 'unit': 'rep'},
          },
        },
      };
      final response = const Commands().execute(
        'activity window-repeat-execution',
        request,
      );
      final native = await invoke([
        'activity',
        'window-repeat-execution',
      ], jsonEncode(request));
      equal(native.code, 0);
      jsonEqual(
        jsonObject(jsonDecode(native.output), 'response')['data'],
        response['data'],
      );
      final view = jsonObject(response['data'], 'data');
      equal(view['confirmedRounds'], 1);
      state = jsonObject(view['execution'], 'execution');
      jsonEqual(state['cursor'], cursor);
      try {
        engine.apply(
          state,
          expectedVersion: 4,
          action: 'revise',
          correction: {'occurrenceId': second, 'outcome': 'skipped'},
          confirm: true,
        );
        throw StateError('Expected stale conflict.');
      } on BodyTmiException catch (error) {
        equal(error.code, 'conflict');
      }
      state = engine.apply(
        state,
        expectedVersion: 5,
        action: 'revise',
        correction: {'occurrenceId': second, 'outcome': 'skipped'},
        confirm: true,
      );
      final skipped = jsonObject((state['entries'] as List).last, 'entry');
      equal(skipped['outcome'], 'skipped');
      equal(skipped.containsKey('actuals'), false);
      equal(engine.view(state)['partialRounds'], 1);
      jsonEqual(state['cursor'], cursor);
      rejects(
        () => engine.apply(
          state,
          expectedVersion: 6,
          action: 'revise',
          correction: {'occurrenceId': second, 'outcome': 'skipped'},
          confirm: true,
        ),
      );
      var active = engine.start(loop);
      active = engine.apply(
        active,
        expectedVersion: 1,
        action: 'review',
        review: {'outcome': 'skipped'},
        confirm: true,
      );
      active = engine.apply(
        active,
        expectedVersion: 2,
        action: 'resume',
        ownerId: 'owner',
      );
      rejects(
        () => engine.apply(
          active,
          expectedVersion: 3,
          action: 'revise',
          correction: {
            'occurrenceId': first,
            'outcome': 'completed',
            'acceptSuggested': true,
          },
        ),
      );
    },
  );
  test('boundary batch reviews require explicit consecutive results', () async {
    final loop = WindowRepeatSpec.fromJson({
      ...jsonObject(example('window-repeat-page')['loop'], 'loop'),
      'durationMilliseconds': 1000,
      'maxRounds': 2,
      'maxOccurrences': 4,
    });
    const engine = WindowRepeatExecution();
    var state = engine.start(loop);
    state = engine.apply(
      state,
      expectedVersion: 1,
      action: 'resume',
      ownerId: 'owner',
    );
    state = engine.apply(
      state,
      expectedVersion: 2,
      action: 'advance',
      ownerId: 'owner',
      ownerElapsedMilliseconds: 1100,
    );
    equal(
      jsonObject(engine.view(state)['nextBoundaryReview'], 'next')['id'],
      'amrap[0]/round/push-set',
    );
    final reviews = [
      {
        'occurrenceId': 'amrap[0]/round/push-set',
        'outcome': 'completed',
        'acceptSuggested': true,
      },
      {
        'occurrenceId': 'amrap[0]/round/pull-set',
        'outcome': 'completed',
        'actuals': {
          'reps': {'value': '4', 'unit': 'rep'},
        },
      },
      {
        'occurrenceId': 'amrap[1]/round/push-set',
        'outcome': 'completed',
        'actuals': {
          'reps': {'value': '2', 'unit': 'rep'},
        },
        'observations': {'terminationReason': 'interrupted'},
      },
      {'occurrenceId': 'amrap[1]/round/pull-set', 'outcome': 'skipped'},
    ];
    rejects(
      () => engine.apply(
        state,
        expectedVersion: 3,
        action: 'review-batch',
        review: {'reviews': reviews},
      ),
    );
    rejects(
      () => engine.apply(
        state,
        expectedVersion: 3,
        action: 'review-batch',
        confirm: true,
        review: {
          'reviews': [reviews[1], reviews[0]],
        },
      ),
    );
    equal((state['entries'] as List).length, 0);
    final request = {
      'schemaVersion': 1,
      'action': 'review-batch',
      'execution': state,
      'expectedVersion': 3,
      'confirm': true,
      'review': {'reviews': reviews},
    };
    final response = const Commands().execute(
      'activity window-repeat-execution',
      request,
    );
    final native = await invoke([
      'activity',
      'window-repeat-execution',
    ], jsonEncode(request));
    equal(native.code, 0);
    jsonEqual(
      jsonObject(jsonDecode(native.output), 'response')['data'],
      response['data'],
    );
    final view = jsonObject(response['data'], 'data');
    equal(view['confirmedRounds'], 1);
    equal(view['partialRounds'], 1);
    equal(view['nextBoundaryReview'], null);
    state = jsonObject(view['execution'], 'execution');
    final first = jsonObject((state['entries'] as List).first, 'entry');
    equal(first['reportedAfterBoundary'], true);
    final forged = (state['entries'] as List)
        .map((entry) => jsonObject(entry, 'entry'))
        .toList();
    forged[1] = {...forged[1]}..remove('reportedAfterBoundary');
    rejects(() => engine.view({...state, 'entries': forged}));
    equal(jsonObject(state['cursor'], 'cursor')['occurrence'], 0);
    rejects(
      () => engine.apply(
        state,
        expectedVersion: 4,
        action: 'review-batch',
        confirm: true,
        review: {
          'reviews': [reviews.first],
        },
      ),
    );
    try {
      engine.apply(
        state,
        expectedVersion: 3,
        action: 'review-batch',
        confirm: true,
        review: {'reviews': reviews},
      );
      throw StateError('Expected stale conflict.');
    } on BodyTmiException catch (error) {
      equal(error.code, 'conflict');
    }
    state = engine.apply(
      state,
      expectedVersion: 4,
      action: 'finish',
      confirm: true,
    );
    equal(engine.view(state)['partialRounds'], 1);
    equal((state['entries'] as List).length, 4);
    state = engine.apply(
      state,
      expectedVersion: 5,
      action: 'correct',
      correction: {
        'occurrenceId': 'amrap[0]/round/push-set',
        'actuals': {
          'reps': {'value': '3', 'unit': 'rep'},
        },
      },
    );
    equal(
      jsonObject(
        (state['entries'] as List).first,
        'entry',
      )['reportedAfterBoundary'],
      true,
    );
    state = engine.apply(
      state,
      expectedVersion: 6,
      action: 'revise',
      correction: {
        'occurrenceId': 'amrap[0]/round/push-set',
        'outcome': 'skipped',
      },
      confirm: true,
    );
    equal(
      jsonObject(
        (state['entries'] as List).first,
        'entry',
      )['reportedAfterBoundary'],
      true,
    );
  });
  test('running rest review yields to the window deadline', () {
    final loopJson = jsonObject(example('window-repeat-page')['loop'], 'loop');
    final definition = jsonObject(
      loopJson['roundDefinition'],
      'roundDefinition',
    );
    final loop = WindowRepeatSpec.fromJson({
      ...loopJson,
      'durationMilliseconds': 1000,
      'roundDefinition': {
        ...definition,
        'plan': {
          'id': 'round',
          'type': 'sequence',
          'children': [
            {'id': 'rest', 'type': 'rest', 'manual': true},
            {'id': 'push-set', 'type': 'effort', 'slot': 'push'},
          ],
        },
      },
    });
    const engine = WindowRepeatExecution();
    var state = engine.start(loop);
    state = engine.apply(
      state,
      expectedVersion: 1,
      action: 'resume',
      ownerId: 'owner',
    );
    state = engine.apply(
      state,
      expectedVersion: 2,
      action: 'review',
      ownerId: 'owner',
      ownerElapsedMilliseconds: 1200,
      review: {'outcome': 'rest'},
      confirm: true,
    );
    final cursor = jsonObject(state['cursor'], 'cursor');
    equal(cursor['status'], 'boundary');
    equal(cursor['occurrence'], 0);
    equal(cursor['unappliedMilliseconds'], 200);
    equal((state['entries'] as List).length, 0);
    state = engine.apply(
      state,
      expectedVersion: 3,
      action: 'finish',
      confirm: true,
    );
    equal(jsonObject(state['cursor'], 'cursor')['status'], 'finished');
  });
  test(
    'running repeat reviews sample the clock and stop at its boundary',
    () async {
      final loop = WindowRepeatSpec.fromJson({
        ...jsonObject(example('window-repeat-page')['loop'], 'loop'),
        'durationMilliseconds': 1000,
        'maxRounds': 2,
        'maxOccurrences': 4,
      });
      const engine = WindowRepeatExecution();
      var state = engine.start(loop);
      state = engine.apply(
        state,
        expectedVersion: 1,
        action: 'resume',
        ownerId: 'owner',
      );
      final request = {
        'schemaVersion': 1,
        'action': 'review',
        'execution': state,
        'expectedVersion': 2,
        'ownerId': 'owner',
        'ownerElapsedMilliseconds': 400,
        'review': {'outcome': 'completed', 'acceptSuggested': true},
      };
      final response = const Commands().execute(
        'activity window-repeat-execution',
        request,
      );
      final native = await invoke([
        'activity',
        'window-repeat-execution',
      ], jsonEncode(request));
      equal(native.code, 0);
      jsonEqual(
        jsonObject(jsonDecode(native.output), 'response')['data'],
        response['data'],
      );
      state = jsonObject(
        jsonObject(response['data'], 'data')['execution'],
        'execution',
      );
      var cursor = jsonObject(state['cursor'], 'cursor');
      equal(cursor['status'], 'running');
      equal(cursor['elapsedMilliseconds'], 400);
      equal(cursor['ownerElapsedMilliseconds'], 400);
      equal(cursor['occurrence'], 1);
      rejects(
        () => engine.apply(
          state,
          expectedVersion: 3,
          action: 'review',
          ownerId: 'owner',
          ownerElapsedMilliseconds: 399,
          review: {'outcome': 'completed', 'acceptSuggested': true},
        ),
      );
      rejects(
        () => engine.apply(
          state,
          expectedVersion: 3,
          action: 'review',
          ownerId: 'other',
          ownerElapsedMilliseconds: 500,
          review: {'outcome': 'completed', 'acceptSuggested': true},
        ),
      );
      state = engine.apply(
        state,
        expectedVersion: 3,
        action: 'review',
        ownerId: 'owner',
        ownerElapsedMilliseconds: 1100,
        review: {
          'outcome': 'completed',
          'acceptSuggested': true,
          'observations': {'terminationReason': 'interrupted'},
        },
      );
      cursor = jsonObject(state['cursor'], 'cursor');
      equal(cursor['status'], 'boundary');
      equal(cursor['occurrence'], 1);
      equal(cursor['elapsedMilliseconds'], 1000);
      equal(cursor['unappliedMilliseconds'], 100);
      equal(engine.view(state)['partialRounds'], 1);
      equal(engine.view(state)['currentReviewed'], true);
      equal(engine.view(state)['reportedAfterBoundary'], 1);
      equal(
        jsonObject(
          (state['entries'] as List).last,
          'entry',
        )['reportedAfterBoundary'],
        true,
      );
      state = engine.apply(
        state,
        expectedVersion: 4,
        action: 'finish',
        confirm: true,
      );
      equal(jsonObject(state['cursor'], 'cursor')['status'], 'finished');
      final limitedLoop = WindowRepeatSpec.fromJson({
        ...loop.toJson(),
        'maxRounds': 1,
        'maxOccurrences': 2,
      });
      state = engine.start(limitedLoop);
      state = engine.apply(
        state,
        expectedVersion: 1,
        action: 'resume',
        ownerId: 'owner',
      );
      state = engine.apply(
        state,
        expectedVersion: 2,
        action: 'review',
        ownerId: 'owner',
        ownerElapsedMilliseconds: 100,
        review: {'outcome': 'skipped'},
        confirm: true,
      );
      state = engine.apply(
        state,
        expectedVersion: 3,
        action: 'review',
        ownerId: 'owner',
        ownerElapsedMilliseconds: 200,
        review: {'outcome': 'skipped'},
        confirm: true,
      );
      cursor = jsonObject(state['cursor'], 'cursor');
      equal(cursor['status'], 'limitReached');
      equal(cursor['ownerId'], null);
      equal(cursor['elapsedMilliseconds'], 200);
    },
  );
  test(
    'repeat corrections preserve cursor and update round assessment',
    () async {
      final loop = WindowRepeatSpec.fromJson({
        ...jsonObject(example('window-repeat-page')['loop'], 'loop'),
        'maxRounds': 1,
        'maxOccurrences': 2,
      });
      const engine = WindowRepeatExecution();
      var state = engine.start(loop);
      state = engine.apply(
        state,
        expectedVersion: 1,
        action: 'review',
        review: {
          'outcome': 'completed',
          'acceptSuggested': true,
          'observations': {'terminationReason': 'interrupted'},
        },
      );
      state = engine.apply(
        state,
        expectedVersion: 2,
        action: 'review',
        review: {'outcome': 'completed', 'acceptSuggested': true},
      );
      equal(engine.view(state)['partialRounds'], 1);
      state = engine.apply(
        state,
        expectedVersion: 3,
        action: 'finish',
        confirm: true,
      );
      final cursor = state['cursor'];
      const occurrence = 'amrap[0]/round/push-set';
      rejects(
        () => engine.apply(
          state,
          expectedVersion: 4,
          action: 'correct',
          correction: {'occurrenceId': occurrence, 'observations': null},
        ),
      );
      final request = {
        'schemaVersion': 1,
        'action': 'correct',
        'execution': state,
        'expectedVersion': 4,
        'confirm': true,
        'correction': {
          'occurrenceId': occurrence,
          'observations': null,
          'actuals': {
            'reps': {'value': '3', 'unit': 'rep'},
          },
        },
      };
      final response = const Commands().execute(
        'activity window-repeat-execution',
        request,
      );
      final native = await invoke([
        'activity',
        'window-repeat-execution',
      ], jsonEncode(request));
      equal(native.code, 0);
      jsonEqual(
        jsonObject(jsonDecode(native.output), 'response')['data'],
        response['data'],
      );
      final view = jsonObject(response['data'], 'data');
      state = jsonObject(view['execution'], 'execution');
      jsonEqual(state['cursor'], cursor);
      equal(view['confirmedRounds'], 1);
      equal(view['partialRounds'], 0);
      final entry = jsonObject((state['entries'] as List).first, 'entry');
      equal(entry.containsKey('observations'), false);
      equal(
        jsonObject(
          jsonObject(entry['actuals'], 'actuals')['reps'],
          'reps',
        )['value'],
        '3',
      );
      try {
        engine.apply(
          state,
          expectedVersion: 4,
          action: 'correct',
          correction: {'occurrenceId': occurrence, 'observations': null},
        );
        throw StateError('Expected stale conflict.');
      } on BodyTmiException catch (error) {
        equal(error.code, 'conflict');
      }
      rejects(
        () => engine.apply(
          state,
          expectedVersion: 5,
          action: 'correct',
          correction: {'occurrenceId': 'unknown', 'observations': null},
        ),
      );
      rejects(
        () => engine.apply(
          state,
          expectedVersion: 5,
          action: 'correct',
          correction: {'occurrenceId': occurrence, 'actuals': null},
        ),
      );
      final updated = engine.apply(
        state,
        expectedVersion: 5,
        action: 'correct',
        correction: {
          'occurrenceId': occurrence,
          'observations': {'terminationReason': 'interrupted'},
        },
      );
      equal(engine.view(updated)['partialRounds'], 1);
      jsonEqual(
        jsonObject((updated['entries'] as List).first, 'entry')['actuals'],
        entry['actuals'],
      );
      var active = engine.start(loop);
      active = engine.apply(
        active,
        expectedVersion: 1,
        action: 'review',
        review: {'outcome': 'skipped'},
        confirm: true,
      );
      rejects(
        () => engine.apply(
          active,
          expectedVersion: 2,
          action: 'correct',
          correction: {'occurrenceId': occurrence, 'observations': null},
        ),
      );
      active = engine.apply(
        active,
        expectedVersion: 2,
        action: 'resume',
        ownerId: 'owner',
      );
      rejects(
        () => engine.apply(
          active,
          expectedVersion: 3,
          action: 'correct',
          correction: {'occurrenceId': occurrence, 'observations': null},
        ),
      );
    },
  );
  test('repeat execution recovery requires explicit boundary review', () {
    final loop = WindowRepeatSpec.fromJson({
      ...jsonObject(example('window-repeat-page')['loop'], 'loop'),
      'durationMilliseconds': 1000,
    });
    const engine = WindowRepeatExecution();
    var state = engine.start(loop);
    state = engine.apply(
      state,
      expectedVersion: 1,
      action: 'resume',
      ownerId: 'owner',
    );
    state = engine.apply(
      state,
      expectedVersion: 2,
      action: 'advance',
      ownerId: 'owner',
      ownerElapsedMilliseconds: 200,
    );
    state = engine.apply(
      state,
      expectedVersion: 3,
      action: 'recover',
      adjustmentMilliseconds: 900,
    );
    rejects(
      () => engine.apply(
        state,
        expectedVersion: 4,
        action: 'finish',
        confirm: true,
      ),
    );
    rejects(
      () => engine.apply(
        state,
        expectedVersion: 4,
        action: 'review',
        review: {'outcome': 'skipped'},
      ),
    );
    state = engine.apply(
      state,
      expectedVersion: 4,
      action: 'review',
      review: {'outcome': 'skipped'},
      confirm: true,
    );
    state = engine.apply(
      state,
      expectedVersion: 5,
      action: 'finish',
      confirm: true,
    );
    final view = engine.view(state);
    equal(view['confirmedRounds'], 0);
    equal(view['partialRounds'], 0);
    equal(
      jsonObject((state['entries'] as List).single, 'entry')['outcome'],
      'skipped',
    );
  });
  test(
    'caller-owned repeat execution explicitly records confirmed and partial rounds',
    () async {
      final loopJson = {
        ...jsonObject(example('window-repeat-page')['loop'], 'loop'),
        'durationMilliseconds': 1000,
        'maxRounds': 3,
        'maxOccurrences': 6,
      };
      final loop = WindowRepeatSpec.fromJson(loopJson);
      const engine = WindowRepeatExecution();
      var state = engine.start(loop);
      rejects(
        () => engine.apply(state, expectedVersion: 1, action: 'acknowledge'),
      );
      rejects(
        () => engine.apply(
          state,
          expectedVersion: 1,
          action: 'review',
          review: {'outcome': 'completed'},
        ),
      );
      state = engine.apply(
        state,
        expectedVersion: 1,
        action: 'review',
        review: {'outcome': 'completed', 'acceptSuggested': true},
      );
      state = engine.apply(
        state,
        expectedVersion: 2,
        action: 'review',
        review: {
          'outcome': 'completed',
          'actuals': {
            'reps': {'value': '4', 'unit': 'rep'},
          },
        },
      );
      var view = engine.view(state);
      equal(view['confirmedRounds'], 1);
      equal(view['partialRounds'], 0);
      equal(
        jsonObject(view['current'], 'current')['id'],
        'amrap[1]/round/push-set',
      );
      state = engine.apply(
        state,
        expectedVersion: 3,
        action: 'review',
        review: {
          'outcome': 'completed',
          'actuals': {
            'reps': {'value': '3', 'unit': 'rep'},
          },
        },
      );
      state = engine.apply(
        state,
        expectedVersion: 4,
        action: 'resume',
        ownerId: 'epoch',
      );
      state = engine.apply(
        state,
        expectedVersion: 5,
        action: 'advance',
        ownerId: 'epoch',
        ownerElapsedMilliseconds: 1100,
      );
      view = engine.view(state);
      equal(view['confirmedRounds'], 1);
      equal(view['partialRounds'], 1);
      equal(view['currentReviewed'], false);
      rejects(
        () => engine.apply(
          state,
          expectedVersion: 6,
          action: 'finish',
          confirm: true,
        ),
      );
      state = engine.apply(
        state,
        expectedVersion: 6,
        action: 'review',
        review: {
          'outcome': 'completed',
          'actuals': {
            'reps': {'value': '2', 'unit': 'rep'},
          },
          'observations': {'terminationReason': 'interrupted'},
        },
      );
      view = engine.view(state);
      equal(view['currentReviewed'], true);
      equal(view['confirmedRounds'], 1);
      equal(view['partialRounds'], 1);
      rejects(
        () => engine.apply(
          state,
          expectedVersion: 7,
          action: 'review',
          review: {'outcome': 'skipped'},
          confirm: true,
        ),
      );
      final entries = (state['entries'] as List)
          .map((item) => jsonObject(item, 'entry'))
          .toList();
      equal(entries.length, 4);
      equal(entries.last['id'], 'amrap[1]/round/pull-set');
      equal(
        jsonObject(
          entries.last['observations'],
          'observations',
        )['terminationReason'],
        'interrupted',
      );
      rejects(() => engine.view({...state, 'entries': entries.sublist(0, 2)}));
      rejects(
        () => engine.view({
          ...state,
          'entries': [
            ...entries.take(3),
            {...entries.last, 'id': 'forged'},
          ],
        }),
      );
      state = engine.apply(
        state,
        expectedVersion: 7,
        action: 'finish',
        confirm: true,
      );
      equal(jsonObject(state['cursor'], 'cursor')['status'], 'finished');
      equal(engine.view(state)['partialRounds'], 1);
      try {
        engine.apply(
          state,
          expectedVersion: 7,
          action: 'finish',
          confirm: true,
        );
        throw StateError('Expected stale conflict.');
      } on BodyTmiException catch (error) {
        equal(error.code, 'conflict');
      }
      final request = {'schemaVersion': 1, 'action': 'start', 'loop': loopJson};
      final pure = const Commands().execute(
        'activity window-repeat-execution',
        request,
      );
      jsonEqual(pure['data'], engine.view(engine.start(loop)));
      final native = await invoke([
        'activity',
        'window-repeat-execution',
      ], jsonEncode(request));
      equal(native.code, 0);
      jsonEqual(
        jsonObject(jsonDecode(native.output), 'response')['data'],
        pure['data'],
      );
      final reviewRequest = {
        'schemaVersion': 1,
        'action': 'review',
        'execution': engine.start(loop),
        'expectedVersion': 1,
        'review': {'outcome': 'completed', 'acceptSuggested': true},
      };
      final reviewed = await invoke([
        'activity',
        'window-repeat-execution',
      ], jsonEncode(reviewRequest));
      equal(reviewed.code, 0);
      jsonEqual(
        jsonObject(jsonDecode(reviewed.output), 'response')['data'],
        engine.view(
          engine.apply(
            engine.start(loop),
            expectedVersion: 1,
            action: 'review',
            review: {'outcome': 'completed', 'acceptSuggested': true},
          ),
        ),
      );
    },
  );
  test(
    'caller-owned repeat cursor bounds time and requires explicit structural steps',
    () async {
      final loopJson = {
        ...jsonObject(example('window-repeat-page')['loop'], 'loop'),
        'durationMilliseconds': 1000,
        'maxRounds': 2,
        'maxOccurrences': 4,
      };
      final loop = WindowRepeatSpec.fromJson(loopJson);
      const engine = WindowRepeatCursor();
      var state = engine.start(loop);
      equal(state['status'], 'paused');
      try {
        engine.apply(state, expectedVersion: 2, action: 'acknowledge');
        throw StateError('Expected a stale cursor conflict.');
      } on BodyTmiException catch (error) {
        equal(error.code, 'conflict');
      }
      equal(
        jsonObject(engine.view(state)['current'], 'current')['id'],
        'amrap[0]/round/push-set',
      );
      rejects(() => engine.apply(state, expectedVersion: 1, action: 'resume'));
      state = engine.apply(
        state,
        expectedVersion: 1,
        action: 'resume',
        ownerId: 'epoch',
      );
      rejects(
        () => engine.apply(
          state,
          expectedVersion: 2,
          action: 'advance',
          ownerId: 'wrong',
          ownerElapsedMilliseconds: 1,
        ),
      );
      state = engine.apply(
        state,
        expectedVersion: 2,
        action: 'advance',
        ownerId: 'epoch',
        ownerElapsedMilliseconds: 300,
      );
      rejects(
        () => engine.apply(
          state,
          expectedVersion: 3,
          action: 'pause',
          ownerId: 'epoch',
          ownerElapsedMilliseconds: 299,
        ),
      );
      state = engine.apply(
        state,
        expectedVersion: 3,
        action: 'pause',
        ownerId: 'epoch',
        ownerElapsedMilliseconds: 400,
      );
      state = engine.apply(state, expectedVersion: 4, action: 'acknowledge');
      equal(state['elapsedMilliseconds'], 400);
      equal(
        jsonObject(engine.view(state)['current'], 'current')['id'],
        'amrap[0]/round/pull-set',
      );
      state = engine.apply(state, expectedVersion: 5, action: 'acknowledge');
      equal(state['round'], 1);
      equal(
        jsonObject(engine.view(state)['current'], 'current')['id'],
        'amrap[1]/round/push-set',
      );
      state = engine.apply(
        state,
        expectedVersion: 6,
        action: 'resume',
        ownerId: 'next',
      );
      state = engine.apply(
        state,
        expectedVersion: 7,
        action: 'advance',
        ownerId: 'next',
        ownerElapsedMilliseconds: 700,
      );
      equal(state['status'], 'boundary');
      equal(state['elapsedMilliseconds'], 1000);
      equal(state['unappliedMilliseconds'], 100);
      equal(
        jsonObject(engine.view(state)['current'], 'current')['id'],
        'amrap[1]/round/push-set',
      );
      rejects(
        () => engine.apply(state, expectedVersion: 8, action: 'acknowledge'),
      );
      rejects(() => engine.apply(state, expectedVersion: 8, action: 'finish'));
      state = engine.apply(
        state,
        expectedVersion: 8,
        action: 'finish',
        confirm: true,
      );
      equal(state['status'], 'finished');
      equal(state['terminalReason'], 'windowExpired');
      equal(engine.view(state)['current'], null);
      check(!state.containsKey('results'));
      rejects(() => engine.view({...state, 'elapsedMilliseconds': 999}));
      rejects(() => engine.view({...state, 'unappliedMilliseconds': -1}));
      final limitedLoop = WindowRepeatSpec.fromJson({
        ...loopJson,
        'maxRounds': 1,
      });
      final tooSmall = WindowRepeatSpec.fromJson({
        ...loopJson,
        'maxOccurrences': 1,
      });
      equal(engine.start(tooSmall)['status'], 'limitReached');
      var limited = engine.start(limitedLoop);
      limited = engine.apply(
        limited,
        expectedVersion: 1,
        action: 'acknowledge',
      );
      limited = engine.apply(
        limited,
        expectedVersion: 2,
        action: 'acknowledge',
      );
      equal(limited['status'], 'limitReached');
      equal(limited['terminalReason'], 'resourceLimit');
      final stopped = engine.apply(
        engine.start(loop),
        expectedVersion: 1,
        action: 'stop',
        confirm: true,
      );
      equal(stopped['terminalReason'], 'stopped');
      equal(stopped['status'], 'finished');
      equal(limited['elapsedMilliseconds'], 0);
      rejects(() => engine.view({...limited, 'round': 2, 'version': 8}));
      rejects(() => engine.view({...engine.start(loop), 'round': 1}));
      limited = engine.apply(
        limited,
        expectedVersion: 3,
        action: 'finish',
        confirm: true,
      );
      equal(limited['status'], 'finished');
      equal(limited['terminalReason'], 'resourceLimit');
      var interrupted = engine.start(loop);
      interrupted = engine.apply(
        interrupted,
        expectedVersion: 1,
        action: 'resume',
        ownerId: 'interrupted',
      );
      interrupted = engine.apply(
        interrupted,
        expectedVersion: 2,
        action: 'advance',
        ownerId: 'interrupted',
        ownerElapsedMilliseconds: 300,
      );
      interrupted = engine.apply(
        interrupted,
        expectedVersion: 3,
        action: 'recover',
        adjustmentMilliseconds: 800,
      );
      equal(interrupted['status'], 'boundary');
      equal(interrupted['unappliedMilliseconds'], 100);
      final request = {'schemaVersion': 1, 'action': 'start', 'loop': loopJson};
      final pure = const Commands().execute(
        'activity window-repeat-cursor',
        request,
      );
      jsonEqual(pure['data'], engine.view(engine.start(loop)));
      final native = await invoke([
        'activity',
        'window-repeat-cursor',
      ], jsonEncode(request));
      equal(native.code, 0);
      jsonEqual(
        jsonObject(jsonDecode(native.output), 'response')['data'],
        pure['data'],
      );
      final resumeRequest = {
        'schemaVersion': 1,
        'action': 'resume',
        'cursor': engine.start(loop),
        'expectedVersion': 1,
        'ownerId': 'native',
      };
      final nativeResume = await invoke([
        'activity',
        'window-repeat-cursor',
      ], jsonEncode(resumeRequest));
      equal(nativeResume.code, 0);
      jsonEqual(
        jsonObject(jsonDecode(nativeResume.output), 'response')['data'],
        engine.view(
          engine.apply(
            engine.start(loop),
            expectedVersion: 1,
            action: 'resume',
            ownerId: 'native',
          ),
        ),
      );
      rejects(
        () => const Commands().execute('activity window-repeat-cursor', {
          ...request,
          'ownerId': 'extra',
        }),
      );
    },
  );
  test(
    'deadline-bounded repeat pages generate stable virtual rounds without execution',
    () async {
      final definitionJson = definition().toJson();
      definitionJson['plan'] = {
        'id': 'round',
        'type': 'sequence',
        'children': [
          {'id': 'first', 'type': 'effort', 'slot': 'bench-heavy'},
          {
            'id': 'nested',
            'type': 'repeat',
            'count': 2,
            'restBetweenSeconds': 2,
            'child': {'id': 'set', 'type': 'effort', 'slot': 'bench-light'},
          },
          {'id': 'rest', 'type': 'rest', 'manual': true},
        ],
      };
      final loopJson = <String, Object?>{
        'id': 'amrap',
        'durationMilliseconds': 600000,
        'maxRounds': 3,
        'maxOccurrences': 12,
        'roundDefinition': definitionJson,
      };
      final loop = WindowRepeatSpec.fromJson(loopJson);
      final copy = WindowRepeatSpec.fromJson(loop.toJson());
      jsonEqual(copy.toJson(), loop.toJson());
      const preview = WindowRepeatPreview();
      final first = preview.page(
        loop,
        round: 0,
        elapsedMilliseconds: 100,
        limit: 2,
      );
      equal(first['status'], 'ready');
      equal(first['occurrenceCount'], 5);
      equal(first['nextOffset'], 2);
      final second = preview.page(
        loop,
        round: 0,
        elapsedMilliseconds: 100,
        offset: 2,
        limit: 2,
      );
      equal(second['nextOffset'], 4);
      final third = preview.page(
        loop,
        round: 0,
        elapsedMilliseconds: 100,
        offset: 4,
        limit: 2,
      );
      equal(third['nextOffset'], null);
      final all = [
        ...first['occurrences'] as List,
        ...second['occurrences'] as List,
        ...third['occurrences'] as List,
      ];
      final full = preview.page(loop, round: 0, elapsedMilliseconds: 100);
      jsonEqual(all, full['occurrences']);
      equal(jsonObject(all.first, 'occurrence')['id'], 'amrap[0]/round/first');
      final next = preview.page(loop, round: 1, elapsedMilliseconds: 500);
      equal(
        jsonObject((next['occurrences'] as List).first, 'occurrence')['id'],
        'amrap[1]/round/first',
      );
      equal(next['status'], 'ready');
      final limited = preview.page(loop, round: 2, elapsedMilliseconds: 500);
      equal(limited['status'], 'resourceLimit');
      equal(limited['limitReason'], 'maxOccurrences');
      jsonEqual(limited['occurrences'], []);
      equal(
        preview.page(loop, round: 3, elapsedMilliseconds: 500)['limitReason'],
        'maxRounds',
      );
      final expired = preview.page(loop, round: 3, elapsedMilliseconds: 600000);
      equal(expired['status'], 'windowExpired');
      equal(expired['limitReason'], null);
      jsonEqual(expired['occurrences'], []);
      final singleDefinition = definition().toJson()
        ..['plan'] = {'id': 'set', 'type': 'effort', 'slot': 'bench-heavy'};
      final large = WindowRepeatSpec.fromJson({
        ...loopJson,
        'maxRounds': 10000,
        'maxOccurrences': 10000,
        'roundDefinition': singleDefinition,
      });
      final distant = preview.page(large, round: 9999, elapsedMilliseconds: 1);
      equal(distant['status'], 'ready');
      equal((distant['occurrences'] as List).length, 1);
      equal(
        jsonObject((distant['occurrences'] as List).single, 'occurrence')['id'],
        'amrap[9999]/set',
      );
      equal(
        preview.page(large, round: 10000, elapsedMilliseconds: 1)['status'],
        'resourceLimit',
      );
      rejects(() => preview.page(loop, round: 0, elapsedMilliseconds: -1));
      rejects(
        () => preview.page(loop, round: 0, elapsedMilliseconds: 0, offset: 6),
      );
      rejects(
        () => preview.page(loop, round: 0, elapsedMilliseconds: 0, limit: 1001),
      );
      rejects(() => WindowRepeatSpec.fromJson({...loopJson, 'maxRounds': 0}));
      rejects(() => WindowRepeatSpec.fromJson({...loopJson, 'extra': true}));
      final request = {
        'schemaVersion': 1,
        'loop': loopJson,
        'round': 0,
        'elapsedMilliseconds': 100,
        'offset': 2,
        'limit': 2,
      };
      jsonEqual(
        const Commands().execute(
          'activity window-repeat-page',
          request,
        )['data'],
        second,
      );
      final native = await invoke([
        'activity',
        'window-repeat-page',
      ], jsonEncode(request));
      equal(native.code, 0);
      jsonEqual(
        jsonObject(jsonDecode(native.output), 'response')['data'],
        second,
      );
      rejects(
        () => const Commands().execute('activity window-repeat-page', {
          ...request,
          'round': null,
        }),
      );
    },
  );
  test(
    'expired batch reviews explicit work and preserves other results atomically',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-window-batch-',
      );
      final path = '${dir.path}/db.sqlite';
      var store = await TrainingStore.open(path);
      try {
        final input = definition().toJson();
        input['plan'] = {
          'id': 'plan',
          'type': 'sequence',
          'children': [
            {
              'id': 'window',
              'type': 'window',
              'durationSeconds': 1,
              'child': {
                'id': 'rounds',
                'type': 'repeat',
                'count': 4,
                'child': {'id': 'set', 'type': 'effort', 'slot': 'bench-heavy'},
              },
            },
            {'id': 'after', 'type': 'effort', 'slot': 'bench-light'},
          ],
        };
        final workout = WorkoutDefinition.fromJson(input);
        final training = StoredTrainingService(store);
        await training.publish(workout, 0);
        var session = await training.start(
          'session',
          workout.id,
          1,
          instant(1),
        );
        final ids = session.sets.map((set) => set.id).toList();
        session = await training.edit(
          'session',
          1,
          (s) => const TrainingService().complete(
            s,
            ids[2],
            const {},
            acceptSuggested: true,
          ),
        );
        final prior = session.set(ids[2]).toJson();
        final service = WindowCheckpointService(store);
        var cp = await service.save(
          'cp',
          session.id,
          0,
          const SessionWindowClock().start(session),
        );
        cp = await service.reserve('cp', cp.version);
        cp = await service.action(
          'cp',
          expectedVersion: cp.version,
          expectedSessionVersion: 2,
          expectedClockVersion: 1,
          action: 'resume',
          ownerId: 'owner',
        );
        cp = await service.action(
          'cp',
          expectedVersion: cp.version,
          expectedSessionVersion: 2,
          expectedClockVersion: 2,
          action: 'advance',
          ownerId: 'owner',
          ownerElapsedMilliseconds: 1000,
        );
        final payloads = <Map<String, Object?>>[
          {
            'occurrenceId': ids[1],
            'acceptSuggested': true,
            'actuals': {
              'reps': {'value': '3', 'unit': 'rep'},
            },
            'observations': {'terminationReason': 'interrupted'},
          },
          {'occurrenceId': ids[0], 'acceptSuggested': true},
        ];
        Future<Object?> attempt(
          List<Map<String, Object?>> entries, {
          bool confirm = true,
          int clock = 3,
        }) => service.reviewExpiredBatch(
          'cp',
          expectedVersion: cp.version,
          expectedSessionVersion: 2,
          expectedClockVersion: clock,
          confirm: confirm,
          reviews: [
            for (final entry in entries) WindowEffortReview.fromJson(entry),
          ],
        );
        await expectCheckpointFailure(attempt(payloads, confirm: false));
        await expectCheckpointFailure(attempt(payloads, clock: 2), 'conflict');
        await expectCheckpointFailure(
          attempt([payloads.first, payloads.first]),
        );
        await expectCheckpointFailure(
          attempt([
            {'occurrenceId': ids[4], 'acceptSuggested': true},
          ]),
        );
        await expectCheckpointFailure(
          attempt([
            {'occurrenceId': ids[2], 'acceptSuggested': true},
          ]),
        );
        await expectCheckpointFailure(
          attempt([
            {'occurrenceId': ids[0]},
          ]),
        );
        final raw = sqlite3.open(path);
        try {
          raw.execute(
            "CREATE TRIGGER test_batch_failure BEFORE UPDATE ON window_checkpoints BEGIN SELECT RAISE(ABORT, 'forced checkpoint failure'); END",
          );
          var failed = false;
          try {
            await attempt(payloads);
          } catch (_) {
            failed = true;
          }
          check(failed);
          equal((await training.session('session')).contentVersion, 2);
          equal(
            (await training.session('session')).sets.first.status,
            SetStatus.planned,
          );
          equal((await service.show('cp')).version, cp.version);
          raw.execute('DROP TRIGGER test_batch_failure');
        } finally {
          raw.close();
        }
        await store.close();
        final request = jsonEncode({
          'schemaVersion': 1,
          'database': path,
          'id': 'cp',
          'expectedVersion': cp.version,
          'expectedSessionVersion': 2,
          'expectedClockVersion': 3,
          'confirm': true,
          'reviews': payloads,
        });
        final response = await invoke([
          'checkpoint',
          'review-expired-batch',
        ], request);
        equal(response.code, 0);
        final result = jsonObject(
          jsonObject(jsonDecode(response.output), 'response')['data'],
          'data',
        );
        jsonEqual(result['reviewed'], [ids[0], ids[1]]);
        jsonEqual(result['skipped'], [ids[3]]);
        equal(
          (await invoke(['checkpoint', 'review-expired-batch'], request)).code,
          5,
        );
        store = await TrainingStore.open(path);
        final saved = await StoredTrainingService(store).session('session');
        equal(saved.contentVersion, 3);
        equal(saved.set(ids[0]).status, SetStatus.completed);
        equal(saved.set(ids[1]).actuals['reps']!.value.toString(), '3');
        check(!saved.set(ids[1]).eligibleForPerformance);
        jsonEqual(saved.set(ids[2]).toJson(), prior);
        equal(saved.set(ids[3]).status, SetStatus.skipped);
        equal(saved.set(ids[4]).status, SetStatus.planned);
        final progress = const RoundProgress().evaluate(
          saved,
          'plan/window/rounds',
        );
        equal(progress['confirmedRounds'], 2);
        equal(progress['partialRounds'], 1);
        final clock = jsonObject(
          (await WindowCheckpointService(store).show('cp')).clock['clock'],
          'clock',
        );
        equal(clock['occurrence'], 4);
        equal(clock['status'], 'paused');
        await store.archive();
        await store.backup('${dir.path}/backup');
        equal(
          NativeBackup.validateDatabase('${dir.path}/backup/database.sqlite'),
          56,
        );
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'round reports resolve nested repeat paths and reject rest-only rounds',
    () {
      final input = definition().toJson();
      input['plan'] = {
        'id': 'outer',
        'type': 'repeat',
        'count': 2,
        'child': {
          'id': 'inner',
          'type': 'repeat',
          'count': 2,
          'child': {'id': 'set', 'type': 'effort', 'slot': 'bench-heavy'},
        },
      };
      final workout = WorkoutDefinition.fromJson(input);
      final session = const TrainingService().start(
        sessionId: 'nested',
        revision: WorkoutRevision.publish(workout),
        startedAt: instant(1),
      );
      final inner = const RoundProgress().evaluate(session, 'outer[0]/inner');
      equal((inner['rounds'] as List).length, 2);
      equal(inner['confirmedRounds'], 0);
      equal(
        (const RoundProgress().evaluate(session, 'outer')['rounds'] as List)
            .length,
        2,
      );
      input['plan'] = {
        'id': 'plan',
        'type': 'sequence',
        'children': [
          {
            'id': 'breaks',
            'type': 'repeat',
            'count': 2,
            'child': {'id': 'rest', 'type': 'rest', 'durationSeconds': 1},
          },
          {'id': 'set', 'type': 'effort', 'slot': 'bench-heavy'},
        ],
      };
      final rests = WorkoutDefinition.fromJson(input);
      final restSession = const TrainingService().start(
        sessionId: 'rests',
        revision: WorkoutRevision.publish(rests),
        startedAt: instant(1),
      );
      rejects(() => const RoundProgress().evaluate(restSession, 'plan/breaks'));
    },
  );
  test(
    'round progress counts explicit results and preserves partial and skipped rounds',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-round-progress-',
      );
      final path = '${dir.path}/db.sqlite';
      var store = await TrainingStore.open(path);
      try {
        final input = definition().toJson();
        input['plan'] = {
          'id': 'window',
          'type': 'window',
          'durationSeconds': 600,
          'child': {
            'id': 'rounds',
            'type': 'repeat',
            'count': 5,
            'restBetweenSeconds': 10,
            'child': {
              'id': 'pair',
              'type': 'sequence',
              'children': [
                {'id': 'one', 'type': 'effort', 'slot': 'bench-heavy'},
                {'id': 'two', 'type': 'effort', 'slot': 'bench-light'},
              ],
            },
          },
        };
        final workout = WorkoutDefinition.fromJson(input);
        final training = StoredTrainingService(store);
        await training.publish(workout, 0);
        var session = await training.start(
          'session',
          workout.id,
          1,
          instant(1),
        );
        final ids = session.sets.map((set) => set.id).toList();
        session = await training.edit('session', 1, (s) {
          const engine = TrainingService();
          for (final i in [0, 1, 2]) {
            s = engine.complete(s, ids[i], const {}, acceptSuggested: true);
          }
          s = engine.completeWithObservations(
            s,
            ids[3],
            const {},
            acceptSuggested: true,
            observations: SetObservations.fromJson({
              'terminationReason': 'interrupted',
            }),
          );
          for (final i in [4, 5, 6]) {
            s = engine.skip(s, ids[i], confirm: true);
          }
          return s;
        });
        const progress = RoundProgress();
        final view = progress.evaluate(session, 'window/rounds');
        equal(view['confirmedRounds'], 1);
        equal(view['partialRounds'], 1);
        final rounds = view['rounds'] as List;
        jsonEqual(
          [for (final r in rounds) jsonObject(r, 'round')['status']],
          ['confirmed', 'partial', 'skipped', 'incomplete', 'unstarted'],
        );
        final second = jsonObject(rounds[1], 'round');
        final efforts = second['efforts'] as List;
        final interrupted = jsonObject(efforts.last, 'effort');
        equal(interrupted['eligibleForPerformance'], false);
        equal(
          jsonObject(
            interrupted['observations'],
            'observations',
          )['terminationReason'],
          'interrupted',
        );
        equal(jsonObject(rounds.first, 'round')['endOccurrence'], 2);
        equal(jsonObject(rounds[1], 'round')['startOccurrence'], 3);
        rejects(() => progress.evaluate(session, 'window'));
        rejects(() => progress.evaluate(session, 'window/rounds[0]'));
        final pure = const Commands().execute('session rounds', {
          'schemaVersion': 1,
          'session': session.toJson(),
          'groupPath': 'window/rounds',
        });
        jsonEqual(pure['data'], view);
        final before = canonicalJson((await store.archive()).toJson());
        await store.close();
        final response = await invoke(
          ['store', 'rounds'],
          jsonEncode({
            'schemaVersion': 1,
            'database': path,
            'id': 'session',
            'groupPath': 'window/rounds',
          }),
        );
        equal(response.code, 0);
        jsonEqual(
          jsonObject(jsonDecode(response.output), 'response')['data'],
          view,
        );
        store = await TrainingStore.open(path);
        equal(canonicalJson((await store.archive()).toJson()), before);
        final current = StoredTrainingService(store);
        final corrected = await current.edit(
          'session',
          session.contentVersion,
          (s) => const TrainingService().annotate(
            s,
            ids[3],
            SetObservations.fromJson({'notes': 'Corrected'}),
          ),
        );
        final updated = progress.evaluate(corrected, 'window/rounds');
        equal(updated['confirmedRounds'], 2);
        equal(updated['partialRounds'], 0);
        equal(updated['sessionContentVersion'], corrected.contentVersion);
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'window review atomically retains explicit interrupted effort observations',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-window-observations-',
      );
      final path = '${dir.path}/db.sqlite';
      var store = await TrainingStore.open(path);
      try {
        final input = definition().toJson();
        input['plan'] = {
          'id': 'window',
          'type': 'window',
          'durationSeconds': 1,
          'child': {
            'id': 'rounds',
            'type': 'repeat',
            'count': 2,
            'child': {'id': 'set', 'type': 'effort', 'slot': 'bench-heavy'},
          },
        };
        final workout = WorkoutDefinition.fromJson(input);
        final training = StoredTrainingService(store);
        await training.publish(workout, 0);
        final session = await training.start(
          'session',
          workout.id,
          1,
          instant(1),
        );
        final actuals = {
          ...session.sets.first.suggested,
          'reps': Quantity('3', 'rep'),
        };
        final reports = SetObservations.fromJson({
          'terminationReason': 'interrupted',
          'notes': 'Window elapsed',
          'rpe': {'value': '8', 'scale': '0-10'},
        });
        final initial = const SessionWindowClock().start(session);
        final pure = const SessionWindowReview().review(
          session,
          initial,
          expectedSessionVersion: 1,
          expectedClockVersion: 1,
          toOccurrence: 1,
          action: 'complete',
          actuals: actuals,
          observations: reports,
        );
        check(!pure.session.sets.first.eligibleForPerformance);
        equal(
          pure.session.sets.first.observations!.terminationReason,
          'interrupted',
        );
        final pureCli = const Commands().execute('session window-review', {
          'schemaVersion': 1,
          'session': session.toJson(),
          'clock': initial,
          'expectedSessionVersion': 1,
          'expectedClockVersion': 1,
          'toOccurrence': 1,
          'action': 'complete',
          'actuals': metricsToJson(actuals),
          'observations': reports.toJson(),
        });
        jsonEqual(pureCli['data'], {
          'session': pure.session.toJson(),
          'clock': pure.clock,
          'occurrenceId': pure.occurrenceId,
        });
        rejects(
          () => const SessionWindowReview().review(
            session,
            initial,
            expectedSessionVersion: 1,
            expectedClockVersion: 1,
            toOccurrence: 1,
            action: 'skip',
            confirm: true,
            observations: reports,
          ),
        );
        final service = WindowCheckpointService(store);
        final other = await training.start('other', workout.id, 1, instant(1));
        final otherClock = const SessionWindowClock().start(other);
        await service.save('other-cp', other.id, 0, otherClock);
        final early = await service.completeCurrent(
          'other-cp',
          expectedVersion: 1,
          expectedSessionVersion: 1,
          expectedClockVersion: 1,
          actuals: actuals,
          observations: reports,
        );
        check(!early.session.sets.first.eligibleForPerformance);
        final third = await training.start('third', workout.id, 1, instant(1));
        await service.save(
          'third-cp',
          third.id,
          0,
          const SessionWindowClock().start(third),
        );
        final moved = await service.review(
          'third-cp',
          expectedVersion: 1,
          expectedSessionVersion: 1,
          expectedClockVersion: 1,
          toOccurrence: 1,
          action: 'complete',
          actuals: actuals,
          observations: reports,
        );
        check(!moved.session.sets.first.eligibleForPerformance);
        var cp = await service.save('cp', session.id, 0, initial);
        cp = await service.reserve('cp', cp.version);
        cp = await service.action(
          'cp',
          expectedVersion: cp.version,
          expectedSessionVersion: 1,
          expectedClockVersion: 1,
          action: 'resume',
          ownerId: 'owner',
        );
        cp = await service.action(
          'cp',
          expectedVersion: cp.version,
          expectedSessionVersion: 1,
          expectedClockVersion: 2,
          action: 'advance',
          ownerId: 'owner',
          ownerElapsedMilliseconds: 1000,
        );
        await expectCheckpointFailure(
          service.reviewExpired(
            'cp',
            expectedVersion: cp.version,
            expectedSessionVersion: 1,
            expectedClockVersion: 3,
            confirm: true,
            actuals: actuals,
            observations: SetObservations.fromJson(<String, Object?>{}),
          ),
        );
        final raw = sqlite3.open(path);
        try {
          raw.execute(
            "CREATE TRIGGER test_observation_failure BEFORE UPDATE ON window_checkpoints BEGIN SELECT RAISE(ABORT, 'forced checkpoint failure'); END",
          );
          var failed = false;
          try {
            await service.reviewExpired(
              'cp',
              expectedVersion: cp.version,
              expectedSessionVersion: 1,
              expectedClockVersion: 3,
              confirm: true,
              actuals: actuals,
              observations: reports,
            );
          } catch (_) {
            failed = true;
          }
          check(failed);
          equal((await training.session('session')).contentVersion, 1);
          equal(
            (await training.session('session')).sets.first.observations,
            null,
          );
          equal((await service.show('cp')).version, cp.version);
          raw.execute('DROP TRIGGER test_observation_failure');
        } finally {
          raw.close();
        }
        await store.close();
        final payload = jsonEncode({
          'schemaVersion': 1,
          'database': path,
          'id': 'cp',
          'expectedVersion': cp.version,
          'expectedSessionVersion': 1,
          'expectedClockVersion': 3,
          'confirm': true,
          'actuals': metricsToJson(actuals),
          'observations': reports.toJson(),
        });
        final response = await invoke([
          'checkpoint',
          'review-expired',
        ], payload);
        equal(response.code, 0);
        final retry = await invoke(['checkpoint', 'review-expired'], payload);
        equal(retry.code, 5);
        store = await TrainingStore.open(path);
        final saved = await StoredTrainingService(store).session('session');
        equal(saved.sets.first.status, SetStatus.completed);
        check(!saved.sets.first.eligibleForPerformance);
        equal(saved.sets.first.actuals['reps']!.value.toString(), '3');
        jsonEqual(saved.sets.first.observations!.toJson(), reports.toJson());
        equal(saved.sets.last.status, SetStatus.skipped);
        equal(saved.contentVersion, 4);
        equal(
          jsonObject(
            (await WindowCheckpointService(store).show('cp')).clock['clock'],
            'clock',
          )['status'],
          'complete',
        );
        await store.archive();
        await store.backup('${dir.path}/backup');
        equal(
          NativeBackup.validateDatabase('${dir.path}/backup/database.sqlite'),
          56,
        );
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'scoped rest advancement prepares the next occurrence without recording work',
    () async {
      for (final windowSeconds in [5, 1]) {
        final dir = await Directory.systemTemp.createTemp(
          'bodytmi-advance-rest-',
        );
        final path = '${dir.path}/db.sqlite';
        var store = await TrainingStore.open(path);
        try {
          final input = definition().toJson();
          input['plan'] = {
            'id': 'window',
            'type': 'window',
            'durationSeconds': windowSeconds,
            'child': {
              'id': 'sequence',
              'type': 'sequence',
              'children': [
                {'id': 'rest', 'type': 'rest', 'durationSeconds': 1},
                {'id': 'set', 'type': 'effort', 'slot': 'bench-heavy'},
              ],
            },
          };
          final workout = WorkoutDefinition.fromJson(input);
          final training = StoredTrainingService(store);
          await training.publish(workout, 0);
          final session = await training.start(
            'session',
            workout.id,
            1,
            instant(1),
          );
          final service = WindowCheckpointService(store);
          var cp = await service.save(
            'cp',
            session.id,
            0,
            const SessionWindowClock().start(session),
          );
          cp = await service.reserve('cp', cp.version);
          await expectCheckpointFailure(
            service.advanceRest(
              'cp',
              expectedVersion: cp.version,
              expectedSessionVersion: 1,
              expectedClockVersion: 1,
            ),
          );
          await store.close();
          Future<({int code, Map<String, Object?>? data})> call(
            List<String> command,
            Map<String, Object?> args,
          ) async {
            final response = await invoke(
              command,
              jsonEncode({
                'schemaVersion': 1,
                'database': path,
                'id': 'cp',
                ...args,
              }),
            );
            return (
              code: response.code,
              data: response.code == 0
                  ? jsonObject(
                      jsonObject(
                        jsonDecode(response.output),
                        'response',
                      )['data'],
                      'data',
                    )
                  : null,
            );
          }

          final invalidOption = await call(
            ['checkpoint', 'run'],
            {
              'expectedVersion': cp.version,
              'expectedSessionVersion': 1,
              'expectedClockVersion': 1,
              'advanceRest': true,
            },
          );
          equal(invalidOption.code, 2);
          final run = await call(
            ['checkpoint', 'run'],
            {
              'expectedVersion': cp.version,
              'expectedSessionVersion': 1,
              'expectedClockVersion': 1,
              'stopAtRest': true,
              'advanceRest': true,
            },
          );
          equal(run.code, 0);
          equal(run.data!['restAdvanced'], windowSeconds != 1);
          final checkpoint = jsonObject(run.data!['checkpoint'], 'checkpoint');
          final clock = jsonObject(
            jsonObject(checkpoint['clock'], 'binding')['clock'],
            'clock',
          );
          equal(clock['elapsedMilliseconds'], 1000);
          equal(clock['status'], windowSeconds == 1 ? 'boundary' : 'paused');
          equal(clock['occurrence'], windowSeconds == 1 ? 0 : 1);
          final cue = jsonObject((run.data!['cues'] as List).single, 'cue');
          equal(
            cue['type'],
            windowSeconds == 1 ? 'window-boundary' : 'window-rest-target',
          );
          final retry = await call(
            ['checkpoint', 'advance-rest'],
            {
              'expectedVersion': cp.version,
              'expectedSessionVersion': 1,
              'expectedClockVersion': 1,
            },
          );
          equal(retry.code, 5);
          store = await TrainingStore.open(path);
          final current = await StoredTrainingService(store).session('session');
          equal(current.contentVersion, 1);
          equal(current.sets.single.status, SetStatus.planned);
          await store.archive();
          await store.backup('${dir.path}/backup');
          equal(
            NativeBackup.validateDatabase('${dir.path}/backup/database.sqlite'),
            56,
          );
        } finally {
          await store.close();
          await dir.delete(recursive: true);
        }
      }
    },
  );
  test(
    'manual scoped rests require explicit confirmation to advance',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-advance-manual-',
      );
      var store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final input = definition().toJson();
        input['plan'] = {
          'id': 'window',
          'type': 'window',
          'durationSeconds': 10,
          'child': {
            'id': 'sequence',
            'type': 'sequence',
            'children': [
              {'id': 'rest', 'type': 'rest', 'manual': true},
              {'id': 'set', 'type': 'effort', 'slot': 'bench-heavy'},
            ],
          },
        };
        final workout = WorkoutDefinition.fromJson(input);
        final training = StoredTrainingService(store);
        await training.publish(workout, 0);
        final session = await training.start(
          'session',
          workout.id,
          1,
          instant(1),
        );
        final service = WindowCheckpointService(store);
        var cp = await service.save(
          'cp',
          session.id,
          0,
          const SessionWindowClock().start(session),
        );
        cp = await service.reserve('cp', cp.version);
        await expectCheckpointFailure(
          service.advanceRest(
            'cp',
            expectedVersion: cp.version,
            expectedSessionVersion: 1,
            expectedClockVersion: 1,
          ),
        );
        await store.close();
        final response = await invoke(
          ['checkpoint', 'advance-rest'],
          jsonEncode({
            'schemaVersion': 1,
            'database': '${dir.path}/db.sqlite',
            'id': 'cp',
            'expectedVersion': cp.version,
            'expectedSessionVersion': 1,
            'expectedClockVersion': 1,
            'confirm': true,
          }),
        );
        equal(response.code, 0);
        store = await TrainingStore.open('${dir.path}/db.sqlite');
        final next = await WindowCheckpointService(store).show('cp');
        final clock = jsonObject(next.clock['clock'], 'clock');
        equal(clock['occurrence'], 1);
        equal(clock['elapsedMilliseconds'], 0);
        equal(clock['status'], 'paused');
        equal(
          (await StoredTrainingService(
            store,
          ).session('session')).sets.single.status,
          SetStatus.planned,
        );
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'scoped timed rests stop at their target or enclosing window boundary',
    () async {
      for (final windowSeconds in [5, 1]) {
        final dir = await Directory.systemTemp.createTemp(
          'bodytmi-window-rest-',
        );
        final path = '${dir.path}/db.sqlite';
        var store = await TrainingStore.open(path);
        try {
          final input = definition().toJson();
          input['plan'] = {
            'id': 'window',
            'type': 'window',
            'durationSeconds': windowSeconds,
            'child': {
              'id': 'sequence',
              'type': 'sequence',
              'children': [
                {'id': 'rest', 'type': 'rest', 'durationSeconds': 1},
                {'id': 'set', 'type': 'effort', 'slot': 'bench-heavy'},
              ],
            },
          };
          final workout = WorkoutDefinition.fromJson(input);
          final training = StoredTrainingService(store);
          await training.publish(workout, 0);
          final session = await training.start(
            'session',
            workout.id,
            1,
            instant(1),
          );
          final service = WindowCheckpointService(store);
          final legacy = const SessionWindowClock().start(session);
          final legacyState = {...jsonObject(legacy['clock'], 'clock')}
            ..['policy'] = 'bodytmi-window-clock/1'
            ..remove('occurrenceStartedMilliseconds');
          await service.save('legacy', session.id, 0, {
            ...legacy,
            'clock': legacyState,
          });
          equal(
            jsonObject(
              (await service.status('legacy'))['rest'],
              'rest',
            )['remainingMilliseconds'],
            null,
          );
          var cp = await service.save(
            'cp',
            session.id,
            0,
            const SessionWindowClock().start(session),
          );
          cp = await service.reserve('cp', cp.version);
          final initial = await service.status('cp');
          final rest = jsonObject(initial['rest'], 'rest');
          equal(rest['durationMilliseconds'], 1000);
          equal(rest['remainingMilliseconds'], 1000);
          await store.close();
          Future<Map<String, Object?>> run(
            int version,
            int clockVersion, {
            int? limit,
          }) async {
            final response = await invoke(
              ['checkpoint', 'run'],
              jsonEncode({
                'schemaVersion': 1,
                'database': path,
                'id': 'cp',
                'expectedVersion': version,
                'expectedSessionVersion': 1,
                'expectedClockVersion': clockVersion,
                'stopAtRest': true,
                if (limit != null) 'runForMilliseconds': limit,
              }),
            );
            equal(response.code, 0);
            return jsonObject(
              jsonObject(jsonDecode(response.output), 'response')['data'],
              'run',
            );
          }

          final early = await run(cp.version, 1, limit: 100);
          equal(early['cueCount'], 0);
          final earlyCp = jsonObject(early['checkpoint'], 'checkpoint');
          final earlyClock = jsonObject(
            jsonObject(earlyCp['clock'], 'binding')['clock'],
            'clock',
          );
          equal(earlyClock['elapsedMilliseconds'], 100);
          final reached = await run(
            earlyCp['version'] as int,
            earlyClock['version'] as int,
          );
          final result = jsonObject(reached['checkpoint'], 'checkpoint');
          final clock = jsonObject(
            jsonObject(result['clock'], 'binding')['clock'],
            'clock',
          );
          equal(clock['elapsedMilliseconds'], 1000);
          equal(clock['status'], windowSeconds == 1 ? 'boundary' : 'paused');
          final cue = jsonObject((reached['cues'] as List).single, 'cue');
          equal(
            cue['type'],
            windowSeconds == 1 ? 'window-boundary' : 'window-rest-target',
          );
          store = await TrainingStore.open(path);
          final after = await WindowCheckpointService(store).status('cp');
          equal(jsonObject(after['rest'], 'rest')['remainingMilliseconds'], 0);
          equal(
            (await StoredTrainingService(
              store,
            ).session('session')).sets.single.status,
            SetStatus.planned,
          );
          await store.archive();
          await store.backup('${dir.path}/backup');
          equal(
            NativeBackup.validateDatabase('${dir.path}/backup/database.sqlite'),
            56,
          );
        } finally {
          await store.close();
          await dir.delete(recursive: true);
        }
      }
    },
  );
  test(
    'scoped rest runner rejects manual rests without starting an owner',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-window-manual-rest-',
      );
      final path = '${dir.path}/db.sqlite';
      var store = await TrainingStore.open(path);
      try {
        final input = definition().toJson();
        input['plan'] = {
          'id': 'window',
          'type': 'window',
          'durationSeconds': 10,
          'child': {
            'id': 'sequence',
            'type': 'sequence',
            'children': [
              {'id': 'rest', 'type': 'rest', 'manual': true},
              {'id': 'set', 'type': 'effort', 'slot': 'bench-heavy'},
            ],
          },
        };
        final workout = WorkoutDefinition.fromJson(input);
        final training = StoredTrainingService(store);
        await training.publish(workout, 0);
        final session = await training.start(
          'session',
          workout.id,
          1,
          instant(1),
        );
        final service = WindowCheckpointService(store);
        var cp = await service.save(
          'cp',
          session.id,
          0,
          const SessionWindowClock().start(session),
        );
        cp = await service.reserve('cp', cp.version);
        final view = await service.status('cp');
        final rest = jsonObject(view['rest'], 'rest');
        equal(rest['manual'], true);
        equal(rest['remainingMilliseconds'], null);
        await store.close();
        final result = await invoke(
          ['checkpoint', 'run'],
          jsonEncode({
            'schemaVersion': 1,
            'database': path,
            'id': 'cp',
            'expectedVersion': cp.version,
            'expectedSessionVersion': 1,
            'expectedClockVersion': 1,
            'stopAtRest': true,
          }),
        );
        equal(result.code, 2);
        store = await TrainingStore.open(path);
        final unchanged = await WindowCheckpointService(store).show('cp');
        equal(unchanged.version, cp.version);
        equal(
          jsonObject(unchanged.clock['clock'], 'clock')['status'],
          'paused',
        );
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'checkpoint status exposes deadlines, pending reviews and recovery without mutation',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-window-status-',
      );
      final path = '${dir.path}/db.sqlite';
      var store = await TrainingStore.open(path);
      try {
        final input = definition().toJson();
        input['plan'] = {
          'id': 'minute',
          'type': 'window',
          'durationSeconds': 1,
          'child': {
            'id': 'rounds',
            'type': 'repeat',
            'count': 2,
            'child': {'id': 'set', 'type': 'effort', 'slot': 'bench-heavy'},
          },
        };
        final workout = WorkoutDefinition.fromJson(input);
        final training = StoredTrainingService(store);
        await training.publish(workout, 0);
        final session = await training.start(
          'session',
          workout.id,
          1,
          instant(1),
        );
        final ids = session.sets.map((set) => set.id).toList();
        final service = WindowCheckpointService(store);
        final initial = const SessionWindowClock().start(session);
        final legacyClock = {...jsonObject(initial['clock'], 'clock')}
          ..['policy'] = 'bodytmi-window-clock/1'
          ..remove('occurrenceStartedMilliseconds');
        await service.save('legacy', session.id, 0, {
          ...initial,
          'clock': legacyClock,
        });
        equal(
          (await service.status('legacy'))['occurrenceElapsedMilliseconds'],
          null,
        );
        var cp = await service.save('cp', session.id, 0, initial);
        cp = await service.reserve('cp', cp.version);
        final paused = await service.status('cp');
        equal(paused['policy'], 'bodytmi-window-checkpoint-status/1');
        equal(paused['sessionContentVersion'], 1);
        equal(paused['occurrenceElapsedMilliseconds'], 0);
        equal(paused['earliestDeadlineMilliseconds'], 1000);
        equal(
          jsonObject(paused['currentOccurrence'], 'occurrence')['setStatus'],
          'planned',
        );
        equal(paused['boundary'], null);
        equal(paused['requiresRecoveryBeforeNewOwner'], false);
        cp = await service.action(
          'cp',
          expectedVersion: cp.version,
          expectedSessionVersion: 1,
          expectedClockVersion: 1,
          action: 'resume',
          ownerId: 'owner',
        );
        equal(
          (await service.status('cp'))['requiresRecoveryBeforeNewOwner'],
          true,
        );
        cp = await service.action(
          'cp',
          expectedVersion: cp.version,
          expectedSessionVersion: 1,
          expectedClockVersion: 2,
          action: 'advance',
          ownerId: 'owner',
          ownerElapsedMilliseconds: 1200,
        );
        var view = await service.status('cp');
        equal(view['occurrenceElapsedMilliseconds'], 1000);
        var boundary = jsonObject(view['boundary'], 'boundary');
        equal(boundary['endOccurrence'], 2);
        jsonEqual(boundary['pendingEfforts'], ids);
        equal(boundary['canAdvanceReviewed'], false);
        final completed = await service.completeCurrent(
          'cp',
          expectedVersion: cp.version,
          expectedSessionVersion: 1,
          expectedClockVersion: 3,
          acceptSuggested: true,
        );
        cp = completed.checkpoint;
        view = await service.status('cp');
        boundary = jsonObject(view['boundary'], 'boundary');
        jsonEqual(boundary['pendingEfforts'], [ids.last]);
        equal(
          jsonObject(view['currentOccurrence'], 'occurrence')['setStatus'],
          'completed',
        );
        final skipped = await training.edit(
          'session',
          2,
          (s) => const TrainingService().skip(s, ids.last, confirm: true),
        );
        view = await service.status('cp');
        boundary = jsonObject(view['boundary'], 'boundary');
        jsonEqual(boundary['pendingEfforts'], []);
        equal(boundary['canAdvanceReviewed'], true);
        final archiveBefore = canonicalJson((await store.archive()).toJson());
        await store.close();
        final response = await invoke([
          'checkpoint',
          'status',
        ], jsonEncode({'schemaVersion': 1, 'database': path, 'id': 'cp'}));
        equal(response.code, 0);
        jsonEqual(
          jsonObject(jsonDecode(response.output), 'response')['data'],
          view,
        );
        store = await TrainingStore.open(path);
        equal(canonicalJson((await store.archive()).toJson()), archiveBefore);
        final resumedService = WindowCheckpointService(store);
        final advanced = await resumedService.advanceReviewedBoundary(
          'cp',
          expectedVersion: cp.version,
          expectedSessionVersion: skipped.contentVersion,
          expectedClockVersion: 3,
        );
        check(advanced != null);
        final finished = await resumedService.status('cp');
        equal(finished['currentOccurrence'], null);
        equal(finished['occurrenceElapsedMilliseconds'], null);
        equal(finished['earliestDeadlineMilliseconds'], null);
        jsonEqual(finished['windows'], []);
        equal(finished['boundary'], null);
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'reviewed window boundaries advance without certifying unreviewed work',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-window-auto-');
      final path = '${dir.path}/db.sqlite';
      var store = await TrainingStore.open(path);
      try {
        final input = definition().toJson();
        input['plan'] = {
          'id': 'rounds',
          'type': 'repeat',
          'count': 2,
          'child': {
            'id': 'minute',
            'type': 'window',
            'durationSeconds': 1,
            'child': {'id': 'set', 'type': 'effort', 'slot': 'bench-heavy'},
          },
        };
        final workout = WorkoutDefinition.fromJson(input);
        final training = StoredTrainingService(store);
        await training.publish(workout, 0);
        final session = await training.start(
          'session',
          workout.id,
          1,
          instant(1),
        );
        var service = WindowCheckpointService(store);
        var cp = await service.save(
          'cp',
          session.id,
          0,
          const SessionWindowClock().start(session),
        );
        cp = await service.reserve('cp', cp.version);
        final completed = await service.completeCurrent(
          'cp',
          expectedVersion: cp.version,
          expectedSessionVersion: 1,
          expectedClockVersion: 1,
          acceptSuggested: true,
        );
        cp = completed.checkpoint;
        await store.close();
        Future<({int code, Map<String, Object?>? data})> call(
          String command,
          Map<String, Object?> args,
        ) async {
          final result = await invoke(
            command.split(' '),
            jsonEncode({
              'schemaVersion': 1,
              'database': path,
              'id': 'cp',
              ...args,
            }),
          );
          return (
            code: result.code,
            data: result.code == 0
                ? jsonObject(
                    jsonObject(jsonDecode(result.output), 'response')['data'],
                    'data',
                  )
                : null,
          );
        }

        final first = await call('checkpoint run', {
          'expectedVersion': cp.version,
          'expectedSessionVersion': 2,
          'expectedClockVersion': 1,
          'runForMilliseconds': 1200,
          'advanceReviewed': true,
        });
        equal(first.code, 0);
        equal(first.data!['boundaryAdvanced'], true);
        equal(first.data!['cueCount'], 1);
        final cue = jsonObject((first.data!['cues'] as List).single, 'cue');
        equal(
          jsonObject(
            cue['boundaryEvidence'],
            'boundary',
          )['deadlineMilliseconds'],
          1000,
        );
        final firstCheckpoint = jsonObject(
          first.data!['checkpoint'],
          'checkpoint',
        );
        final firstClock = jsonObject(
          jsonObject(firstCheckpoint['clock'], 'binding')['clock'],
          'clock',
        );
        equal(firstClock['status'], 'paused');
        equal(firstClock['occurrence'], 1);
        equal(firstClock['elapsedMilliseconds'], 1000);
        equal(
          jsonObject(firstClock['windowStarts'], 'starts').values.single,
          1000,
        );
        final second = await call('checkpoint run', {
          'expectedVersion': firstCheckpoint['version'],
          'expectedSessionVersion': 2,
          'expectedClockVersion': firstClock['version'],
          'runForMilliseconds': 1200,
          'advanceReviewed': true,
        });
        equal(second.code, 0);
        equal(second.data!['boundaryAdvanced'], false);
        final boundary = jsonObject(second.data!['checkpoint'], 'checkpoint');
        final boundaryClock = jsonObject(
          jsonObject(boundary['clock'], 'binding')['clock'],
          'clock',
        );
        equal(boundaryClock['status'], 'boundary');
        equal(boundaryClock['elapsedMilliseconds'], 2000);
        final rejected = await call('checkpoint advance-boundary', {
          'expectedVersion': boundary['version'],
          'expectedSessionVersion': 2,
          'expectedClockVersion': boundaryClock['version'],
        });
        equal(rejected.code, 2);
        store = await TrainingStore.open(path);
        service = WindowCheckpointService(store);
        cp = await service.show('cp');
        final saved = await StoredTrainingService(store).session('session');
        equal(saved.sets.first.status, SetStatus.completed);
        equal(saved.sets.last.status, SetStatus.planned);
        equal(saved.contentVersion, 2);
        final reviewed = await service.completeCurrent(
          'cp',
          expectedVersion: cp.version,
          expectedSessionVersion: 2,
          expectedClockVersion: boundaryClock['version'] as int,
          actuals: saved.sets.last.suggested,
        );
        cp = reviewed.checkpoint;
        await store.close();
        final last = await call('checkpoint advance-boundary', {
          'expectedVersion': cp.version,
          'expectedSessionVersion': 3,
          'expectedClockVersion': boundaryClock['version'],
        });
        equal(last.code, 0);
        final lastClock = jsonObject(
          jsonObject(last.data!['clock'], 'binding')['clock'],
          'clock',
        );
        equal(lastClock['status'], 'complete');
        equal(last.data!['reserved'], null);
        final retry = await call('checkpoint advance-boundary', {
          'expectedVersion': cp.version,
          'expectedSessionVersion': 3,
          'expectedClockVersion': boundaryClock['version'],
        });
        equal(retry.code, 5);
        store = await TrainingStore.open(path);
        try {
          final finalSession = await StoredTrainingService(
            store,
          ).session('session');
          equal(finalSession.contentVersion, 3);
          equal(finalSession.sets.last.status, SetStatus.completed);
          await store.archive();
          await store.backup('${dir.path}/backup');
          equal(
            NativeBackup.validateDatabase('${dir.path}/backup/database.sqlite'),
            56,
          );
        } finally {
          await store.close();
        }
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'early completion preserves the EMOM boundary and rolls back atomically',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-window-early-',
      );
      final path = '${dir.path}/db.sqlite';
      var store = await TrainingStore.open(path);
      try {
        final input = definition().toJson();
        input['plan'] = {
          'id': 'rounds',
          'type': 'repeat',
          'count': 2,
          'child': {
            'id': 'minute',
            'type': 'window',
            'durationSeconds': 1,
            'child': {'id': 'set', 'type': 'effort', 'slot': 'bench-heavy'},
          },
        };
        final workout = WorkoutDefinition.fromJson(input);
        final training = StoredTrainingService(store);
        await training.publish(workout, 0);
        final session = await training.start(
          'session',
          workout.id,
          1,
          instant(1),
        );
        var service = WindowCheckpointService(store);
        var cp = await service.save(
          'cp',
          session.id,
          0,
          const SessionWindowClock().start(session),
        );
        cp = await service.reserve('cp', cp.version);
        cp = await service.action(
          'cp',
          expectedVersion: cp.version,
          expectedSessionVersion: 1,
          expectedClockVersion: 1,
          action: 'resume',
          ownerId: 'first',
        );
        await expectCheckpointFailure(
          service.completeCurrent(
            'cp',
            expectedVersion: cp.version,
            expectedSessionVersion: 1,
            expectedClockVersion: 2,
            acceptSuggested: true,
          ),
        );
        cp = await service.action(
          'cp',
          expectedVersion: cp.version,
          expectedSessionVersion: 1,
          expectedClockVersion: 2,
          action: 'pause',
          ownerId: 'first',
          ownerElapsedMilliseconds: 300,
        );
        await expectCheckpointFailure(
          service.completeCurrent(
            'cp',
            expectedVersion: cp.version,
            expectedSessionVersion: 1,
            expectedClockVersion: 3,
          ),
        );
        await expectCheckpointFailure(
          service.completeCurrent(
            'cp',
            expectedVersion: cp.version,
            expectedSessionVersion: 1,
            expectedClockVersion: 2,
            acceptSuggested: true,
          ),
          'conflict',
        );
        final raw = sqlite3.open(path);
        try {
          raw.execute(
            "CREATE TRIGGER test_early_failure BEFORE UPDATE ON window_checkpoints BEGIN SELECT RAISE(ABORT, 'forced checkpoint failure'); END",
          );
          var failed = false;
          try {
            await service.completeCurrent(
              'cp',
              expectedVersion: cp.version,
              expectedSessionVersion: 1,
              expectedClockVersion: 3,
              acceptSuggested: true,
            );
          } catch (_) {
            failed = true;
          }
          check(failed);
          equal((await training.session('session')).contentVersion, 1);
          equal((await service.show('cp')).version, cp.version);
          raw.execute('DROP TRIGGER test_early_failure');
        } finally {
          raw.close();
        }
        await store.close();
        final payload = jsonEncode({
          'schemaVersion': 1,
          'database': path,
          'id': 'cp',
          'expectedVersion': cp.version,
          'expectedSessionVersion': 1,
          'expectedClockVersion': 3,
          'acceptSuggested': true,
        });
        final response = await invoke([
          'checkpoint',
          'complete-current',
        ], payload);
        equal(response.code, 0);
        final result = jsonObject(
          jsonObject(jsonDecode(response.output), 'response')['data'],
          'data',
        );
        equal(result['occurrenceId'], session.sets.first.id);
        final next = jsonObject(result['checkpoint'], 'checkpoint');
        final wrapper = jsonObject(next['clock'], 'wrapper');
        final clock = jsonObject(wrapper['clock'], 'clock');
        equal(wrapper['sessionContentVersion'], 2);
        equal(clock['version'], 3);
        equal(clock['elapsedMilliseconds'], 300);
        equal(clock['occurrence'], 0);
        final retry = await invoke(['checkpoint', 'complete-current'], payload);
        equal(retry.code, 5);
        store = await TrainingStore.open(path);
        service = WindowCheckpointService(store);
        cp = await service.show('cp');
        await store.archive();
        await store.backup('${dir.path}/early-backup');
        equal(
          NativeBackup.validateDatabase(
            '${dir.path}/early-backup/database.sqlite',
          ),
          56,
        );
        await expectCheckpointFailure(
          service.completeCurrent(
            'cp',
            expectedVersion: cp.version,
            expectedSessionVersion: 2,
            expectedClockVersion: 3,
            acceptSuggested: true,
          ),
        );
        cp = await service.action(
          'cp',
          expectedVersion: cp.version,
          expectedSessionVersion: 2,
          expectedClockVersion: 3,
          action: 'resume',
          ownerId: 'second',
        );
        cp = await service.action(
          'cp',
          expectedVersion: cp.version,
          expectedSessionVersion: 2,
          expectedClockVersion: 4,
          action: 'advance',
          ownerId: 'second',
          ownerElapsedMilliseconds: 700,
        );
        final boundary = jsonObject(cp.clock['clock'], 'clock');
        equal(boundary['elapsedMilliseconds'], 1000);
        equal(boundary['status'], 'boundary');
        final advanced = await service.skipExpired(
          'cp',
          expectedVersion: cp.version,
          expectedSessionVersion: 2,
          expectedClockVersion: 5,
          confirm: true,
        );
        jsonEqual(advanced.skipped, []);
        equal(advanced.session.sets.first.status, SetStatus.completed);
        equal(advanced.session.sets.first.timing, null);
        equal(advanced.session.sets.last.status, SetStatus.planned);
        final nextClock = jsonObject(
          advanced.checkpoint.clock['clock'],
          'clock',
        );
        equal(nextClock['occurrence'], 1);
        equal(nextClock['elapsedMilliseconds'], 1000);
        equal(nextClock['occurrenceStartedMilliseconds'], 1000);
        equal(
          jsonObject(nextClock['windowStarts'], 'starts').values.single,
          1000,
        );
        check(advanced.checkpoint.reserved);
        await store.archive();
        await store.backup('${dir.path}/backup');
        equal(
          NativeBackup.validateDatabase('${dir.path}/backup/database.sqlite'),
          56,
        );
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'expired review of final effort releases reservation without inferred duration',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-review-last-');
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final input = definition().toJson();
        input['plan'] = {
          'id': 'window',
          'type': 'window',
          'durationSeconds': 1,
          'child': {'id': 'set', 'type': 'effort', 'slot': 'bench-heavy'},
        };
        final workout = WorkoutDefinition.fromJson(input);
        final training = StoredTrainingService(store);
        await training.publish(workout, 0);
        final session = await training.start(
          'session',
          workout.id,
          1,
          instant(1),
        );
        final service = WindowCheckpointService(store);
        var cp = await service.save(
          'cp',
          session.id,
          0,
          const SessionWindowClock().start(session),
        );
        cp = await service.reserve('cp', cp.version);
        cp = await service.action(
          'cp',
          expectedVersion: cp.version,
          expectedSessionVersion: 1,
          expectedClockVersion: 1,
          action: 'resume',
          ownerId: 'owner',
        );
        cp = await service.action(
          'cp',
          expectedVersion: cp.version,
          expectedSessionVersion: 1,
          expectedClockVersion: 2,
          action: 'advance',
          ownerId: 'owner',
          ownerElapsedMilliseconds: 1000,
        );
        final result = await service.reviewExpired(
          'cp',
          expectedVersion: cp.version,
          expectedSessionVersion: 1,
          expectedClockVersion: 3,
          confirm: true,
          actuals: session.sets.single.suggested,
        );
        jsonEqual(result.skipped, []);
        equal(result.session.contentVersion, 2);
        equal(result.session.sets.single.status, SetStatus.completed);
        equal(result.session.sets.single.timing, null);
        check(!result.checkpoint.reserved);
        equal(
          jsonObject(result.checkpoint.clock['clock'], 'clock')['status'],
          'complete',
        );
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'expired review completes current effort and skips remaining work atomically',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-expired-review-',
      );
      final path = '${dir.path}/db.sqlite';
      final store = await TrainingStore.open(path);
      try {
        final input = definition().toJson();
        input['plan'] = {
          'id': 'plan',
          'type': 'sequence',
          'children': [
            {
              'id': 'window',
              'type': 'window',
              'durationSeconds': 1,
              'child': {
                'id': 'work',
                'type': 'repeat',
                'count': 3,
                'child': {'id': 'set', 'type': 'effort', 'slot': 'bench-heavy'},
              },
            },
            {'id': 'after', 'type': 'effort', 'slot': 'bench-light'},
          ],
        };
        final workout = WorkoutDefinition.fromJson(input);
        final training = StoredTrainingService(store);
        await training.publish(workout, 0);
        final session = await training.start(
          'session',
          workout.id,
          1,
          instant(1),
        );
        final ids = session.sets.map((set) => set.id).toList();
        final service = WindowCheckpointService(store);
        var cp = await service.save(
          'cp',
          session.id,
          0,
          const SessionWindowClock().start(session),
        );
        cp = await service.reserve('cp', cp.version);
        cp = await service.action(
          'cp',
          expectedVersion: cp.version,
          expectedSessionVersion: 1,
          expectedClockVersion: 1,
          action: 'resume',
          ownerId: 'owner',
        );
        cp = await service.action(
          'cp',
          expectedVersion: cp.version,
          expectedSessionVersion: 1,
          expectedClockVersion: 2,
          action: 'advance',
          ownerId: 'owner',
          ownerElapsedMilliseconds: 1000,
        );
        Future<Object?> review({
          bool confirm = true,
          bool accept = true,
          int version = 3,
        }) => service.reviewExpired(
          'cp',
          expectedVersion: cp.version,
          expectedSessionVersion: 1,
          expectedClockVersion: version,
          confirm: confirm,
          acceptSuggested: accept,
        );
        await expectCheckpointFailure(review(confirm: false));
        await expectCheckpointFailure(review(accept: false));
        await expectCheckpointFailure(review(version: 2), 'conflict');
        final raw = sqlite3.open(path);
        try {
          raw.execute(
            "CREATE TRIGGER test_review_expired_failure BEFORE UPDATE ON window_checkpoints BEGIN SELECT RAISE(ABORT, 'forced checkpoint failure'); END",
          );
          var failed = false;
          try {
            await review();
          } catch (_) {
            failed = true;
          }
          check(failed);
          final unchanged = await training.session(session.id);
          equal(unchanged.contentVersion, 1);
          for (final id in ids) {
            equal(unchanged.set(id).status, SetStatus.planned);
          }
          equal((await service.show('cp')).version, cp.version);
          raw.execute('DROP TRIGGER test_review_expired_failure');
        } finally {
          raw.close();
        }
        await store.close();
        final payload = jsonEncode({
          'schemaVersion': 1,
          'database': path,
          'id': 'cp',
          'expectedVersion': cp.version,
          'expectedSessionVersion': 1,
          'expectedClockVersion': 3,
          'confirm': true,
          'acceptSuggested': true,
        });
        final response = await invoke([
          'checkpoint',
          'review-expired',
        ], payload);
        equal(response.code, 0);
        final result = jsonObject(
          jsonObject(jsonDecode(response.output), 'response')['data'],
          'data',
        );
        equal(result['occurrenceId'], ids.first);
        jsonEqual(result['skipped'], [ids[1], ids[2]]);
        final retry = await invoke(['checkpoint', 'review-expired'], payload);
        equal(retry.code, 5);
        final reopened = await TrainingStore.open(path);
        try {
          final saved = await StoredTrainingService(
            reopened,
          ).session(session.id);
          equal(saved.set(ids[0]).status, SetStatus.completed);
          equal(saved.set(ids[1]).status, SetStatus.skipped);
          equal(saved.set(ids[2]).status, SetStatus.skipped);
          equal(saved.set(ids[3]).status, SetStatus.planned);
          equal(saved.contentVersion, 3);
          final updated = await WindowCheckpointService(reopened).show('cp');
          equal(jsonObject(updated.clock['clock'], 'clock')['occurrence'], 3);
          check(updated.reserved);
          await reopened.archive();
          await reopened.backup('${dir.path}/backup');
          equal(
            NativeBackup.validateDatabase('${dir.path}/backup/database.sqlite'),
            56,
          );
        } finally {
          await reopened.close();
        }
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'skip-expired CLI releases a finished window with no remaining work',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-expired-cli-');
      final path = '${dir.path}/db.sqlite';
      final store = await TrainingStore.open(path);
      try {
        final input = definition().toJson();
        input['plan'] = {
          'id': 'window',
          'type': 'window',
          'durationSeconds': 1,
          'child': {'id': 'set', 'type': 'effort', 'slot': 'bench-heavy'},
        };
        final workout = WorkoutDefinition.fromJson(input);
        final training = StoredTrainingService(store);
        await training.publish(workout, 0);
        var session = await training.start(
          'session',
          workout.id,
          1,
          instant(1),
        );
        session = await training.edit(
          session.id,
          session.contentVersion,
          (s) => const TrainingService().complete(
            s,
            s.sets.first.id,
            const {},
            acceptSuggested: true,
          ),
        );
        final service = WindowCheckpointService(store);
        var cp = await service.save(
          'cp',
          session.id,
          0,
          const SessionWindowClock().start(session),
        );
        cp = await service.reserve('cp', cp.version);
        cp = await service.action(
          'cp',
          expectedVersion: cp.version,
          expectedSessionVersion: session.contentVersion,
          expectedClockVersion: 1,
          action: 'resume',
          ownerId: 'owner',
        );
        cp = await service.action(
          'cp',
          expectedVersion: cp.version,
          expectedSessionVersion: session.contentVersion,
          expectedClockVersion: 2,
          action: 'advance',
          ownerId: 'owner',
          ownerElapsedMilliseconds: 1000,
        );
        await store.close();
        final result = await invoke(
          ['checkpoint', 'skip-expired'],
          jsonEncode({
            'schemaVersion': 1,
            'database': path,
            'id': 'cp',
            'expectedVersion': cp.version,
            'expectedSessionVersion': session.contentVersion,
            'expectedClockVersion': 3,
            'confirm': true,
          }),
        );
        equal(result.code, 0);
        final data = jsonObject(
          jsonObject(jsonDecode(result.output), 'response')['data'],
          'data',
        );
        jsonEqual(data['skipped'], []);
        final checkpoint = jsonObject(data['checkpoint'], 'checkpoint');
        equal(checkpoint['reserved'], null);
        equal(
          jsonObject(
            jsonObject(checkpoint['clock'], 'wrapper')['clock'],
            'clock',
          )['status'],
          'complete',
        );
        final reopened = await TrainingStore.open(path);
        try {
          equal(
            (await StoredTrainingService(
              reopened,
            ).session(session.id)).contentVersion,
            session.contentVersion,
          );
        } finally {
          await reopened.close();
        }
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test('expired tied windows skip only planned descendants atomically', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-expired-skip-');
    final store = await TrainingStore.open('${dir.path}/db.sqlite');
    try {
      final input = definition().toJson();
      input['plan'] = {
        'id': 'plan',
        'type': 'sequence',
        'children': [
          {
            'id': 'outer',
            'type': 'window',
            'durationSeconds': 1,
            'child': {
              'id': 'outer-work',
              'type': 'sequence',
              'children': [
                {
                  'id': 'inner',
                  'type': 'window',
                  'durationSeconds': 1,
                  'child': {
                    'id': 'inner-work',
                    'type': 'sequence',
                    'children': [
                      {'id': 'one', 'type': 'effort', 'slot': 'bench-heavy'},
                      {'id': 'two', 'type': 'effort', 'slot': 'bench-heavy'},
                    ],
                  },
                },
                {'id': 'three', 'type': 'effort', 'slot': 'bench-heavy'},
              ],
            },
          },
          {'id': 'after', 'type': 'effort', 'slot': 'bench-light'},
        ],
      };
      final workout = WorkoutDefinition.fromJson(input);
      final training = StoredTrainingService(store);
      await training.publish(workout, 0);
      var session = await training.start('session', workout.id, 1, instant(1));
      final ids = session.sets.map((set) => set.id).toList();
      session = await training.edit(
        session.id,
        session.contentVersion,
        (s) => const TrainingService().complete(
          s,
          ids[0],
          const {},
          acceptSuggested: true,
        ),
      );
      final service = WindowCheckpointService(store);
      var checkpoint = await service.save(
        'cp',
        session.id,
        0,
        const SessionWindowClock().start(session),
      );
      checkpoint = await service.reserve('cp', checkpoint.version);
      checkpoint = await service.action(
        'cp',
        expectedVersion: checkpoint.version,
        expectedSessionVersion: session.contentVersion,
        expectedClockVersion: 1,
        action: 'resume',
        ownerId: 'owner',
      );
      checkpoint = await service.action(
        'cp',
        expectedVersion: checkpoint.version,
        expectedSessionVersion: session.contentVersion,
        expectedClockVersion: 2,
        action: 'advance',
        ownerId: 'owner',
        ownerElapsedMilliseconds: 1000,
      );
      equal(
        await service.advanceReviewedBoundary(
          'cp',
          expectedVersion: checkpoint.version,
          expectedSessionVersion: session.contentVersion,
          expectedClockVersion: 3,
        ),
        null,
      );
      await expectCheckpointFailure(
        service.skipExpired(
          'cp',
          expectedVersion: checkpoint.version,
          expectedSessionVersion: session.contentVersion,
          expectedClockVersion: 3,
          confirm: false,
        ),
      );
      await expectCheckpointFailure(
        service.skipExpired(
          'cp',
          expectedVersion: checkpoint.version,
          expectedSessionVersion: session.contentVersion,
          expectedClockVersion: 2,
          confirm: true,
        ),
        'conflict',
      );
      equal((await service.show('cp')).version, checkpoint.version);
      final raw = sqlite3.open('${dir.path}/db.sqlite');
      try {
        raw.execute(
          "CREATE TRIGGER test_skip_failure BEFORE UPDATE ON window_checkpoints BEGIN SELECT RAISE(ABORT, 'forced checkpoint failure'); END",
        );
        var failed = false;
        try {
          await service.skipExpired(
            'cp',
            expectedVersion: checkpoint.version,
            expectedSessionVersion: session.contentVersion,
            expectedClockVersion: 3,
            confirm: true,
          );
        } catch (_) {
          failed = true;
        }
        check(failed);
        equal(
          (await training.session(session.id)).contentVersion,
          session.contentVersion,
        );
        equal(
          (await training.session(session.id)).set(ids[1]).status,
          SetStatus.planned,
        );
        equal((await service.show('cp')).version, checkpoint.version);
        raw.execute('DROP TRIGGER test_skip_failure');
      } finally {
        raw.close();
      }
      final result = await service.skipExpired(
        'cp',
        expectedVersion: checkpoint.version,
        expectedSessionVersion: session.contentVersion,
        expectedClockVersion: 3,
        confirm: true,
      );
      jsonEqual(result.skipped, [ids[1], ids[2]]);
      equal(result.session.set(ids[0]).status, SetStatus.completed);
      equal(result.session.set(ids[1]).status, SetStatus.skipped);
      equal(result.session.set(ids[2]).status, SetStatus.skipped);
      equal(result.session.set(ids[3]).status, SetStatus.planned);
      equal(result.session.contentVersion, session.contentVersion + 1);
      final state = jsonObject(result.checkpoint.clock['clock'], 'clock');
      equal(state['occurrence'], 3);
      equal(state['status'], 'paused');
      check(result.checkpoint.reserved);
      await expectCheckpointFailure(
        service.skipExpired(
          'cp',
          expectedVersion: checkpoint.version,
          expectedSessionVersion: session.contentVersion,
          expectedClockVersion: 3,
          confirm: true,
        ),
        'conflict',
      );
      equal(
        (await training.session(session.id)).contentVersion,
        session.contentVersion + 1,
      );
      final archive = await store.archive();
      equal(archive.windowCheckpoints.length, 1);
      await store.backup('${dir.path}/backup');
      equal(
        NativeBackup.validateDatabase('${dir.path}/backup/database.sqlite'),
        56,
      );
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });
  test(
    'foreground scoped clock pauses at a deadline without logging effort',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-window-run-');
      final path = '${dir.path}/db.sqlite';
      final store = await TrainingStore.open(path);
      try {
        final input = definition().toJson();
        input['plan'] = {
          'id': 'minute',
          'type': 'window',
          'durationSeconds': 1,
          'child': {'id': 'set', 'type': 'effort', 'slot': 'bench-heavy'},
        };
        final workout = WorkoutDefinition.fromJson(input);
        final training = StoredTrainingService(store);
        await training.publish(workout, 0);
        final session = await training.start(
          'session',
          workout.id,
          1,
          instant(1),
        );
        final checkpoints = WindowCheckpointService(store);
        await checkpoints.save(
          'cp',
          session.id,
          0,
          const SessionWindowClock().start(session),
        );
        await checkpoints.reserve('cp', 1);
        await store.close();
        Future<Map<String, Object?>> run(
          int version,
          int clockVersion,
          int limit, {
          bool stream = false,
        }) async {
          final result = await invoke(
            ['checkpoint', 'run'],
            jsonEncode({
              'schemaVersion': 1,
              'database': path,
              'id': 'cp',
              'expectedVersion': version,
              'expectedSessionVersion': 1,
              'expectedClockVersion': clockVersion,
              'runForMilliseconds': limit,
              'stream': stream,
            }),
          );
          equal(result.code, 0);
          final lines = const LineSplitter().convert(result.output);
          if (stream) {
            equal(lines.length, 3);
            equal(
              jsonObject(
                jsonObject(jsonDecode(lines[0]), 'event')['data'],
                'event',
              )['type'],
              'window-started',
            );
            equal(
              jsonObject(
                jsonObject(jsonDecode(lines[1]), 'event')['data'],
                'event',
              )['type'],
              'window-boundary',
            );
          }
          return jsonObject(
            jsonObject(jsonDecode(lines.last), 'response')['data'],
            'run',
          );
        }

        final first = await run(2, 1, 100);
        final checkpoint = jsonObject(first['checkpoint'], 'checkpoint');
        final state = jsonObject(
          jsonObject(checkpoint['clock'], 'binding')['clock'],
          'clock',
        );
        equal(state['status'], 'paused');
        equal(state['elapsedMilliseconds'], 100);
        equal(first['cueCount'], 0);
        final second = await run(
          checkpoint['version'] as int,
          state['version'] as int,
          1500,
          stream: true,
        );
        final finalCheckpoint = jsonObject(second['checkpoint'], 'checkpoint');
        final finalState = jsonObject(
          jsonObject(finalCheckpoint['clock'], 'binding')['clock'],
          'clock',
        );
        equal(finalState['status'], 'boundary');
        equal(finalState['elapsedMilliseconds'], 1000);
        equal(second['cueCount'], 1);
        check(finalState['boundaryEvidence'] != null);
        final reopened = await TrainingStore.open(path);
        try {
          equal(
            (await reopened.session('session'))!.sets.first.status,
            SetStatus.planned,
          );
          check((await WindowCheckpointService(reopened).show('cp')).reserved);
        } finally {
          await reopened.close();
        }
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'scoped foreground interruption requires recovery or pauses on SIGINT',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-window-interrupt-',
      );
      final path = '${dir.path}/db.sqlite';
      final store = await TrainingStore.open(path);
      try {
        final input = definition().toJson();
        input['plan'] = {
          'id': 'window',
          'type': 'window',
          'durationSeconds': 60,
          'child': {'id': 'set', 'type': 'effort', 'slot': 'bench-heavy'},
        };
        final workout = WorkoutDefinition.fromJson(input);
        final training = StoredTrainingService(store);
        await training.publish(workout, 0);
        final session = await training.start(
          'session',
          workout.id,
          1,
          instant(1),
        );
        final checkpoints = WindowCheckpointService(store);
        await checkpoints.save(
          'cp',
          session.id,
          0,
          const SessionWindowClock().start(session),
        );
        await checkpoints.reserve('cp', 1);
        await store.close();
        final binary = await compileNative(
          'bin/bodytmi.dart',
          '${dir.path}/native',
        );
        Future<
          ({Process child, StreamIterator<String> lines, Future<String> errors})
        >
        launch(int version, int clockVersion) async {
          final child = await Process.start(binary, ['checkpoint', 'run']);
          final lines = StreamIterator(
            child.stdout
                .transform(utf8.decoder)
                .transform(const LineSplitter()),
          );
          final errors = child.stderr.transform(utf8.decoder).join();
          child.stdin.writeln(
            jsonEncode({
              'schemaVersion': 1,
              'database': path,
              'id': 'cp',
              'expectedVersion': version,
              'expectedSessionVersion': 1,
              'expectedClockVersion': clockVersion,
              'stream': true,
            }),
          );
          await child.stdin.close();
          check(await lines.moveNext().timeout(const Duration(seconds: 10)));
          equal(
            jsonObject(
              jsonObject(jsonDecode(lines.current), 'event')['data'],
              'data',
            )['type'],
            'window-started',
          );
          return (child: child, lines: lines, errors: errors);
        }

        var process = await launch(2, 1);
        process.child.kill(ProcessSignal.sigkill);
        await process.child.exitCode;
        await process.lines.cancel();
        equal(await process.errors, '');
        var reopened = await TrainingStore.open(path);
        late WindowCheckpoint recovered;
        try {
          final service = WindowCheckpointService(reopened);
          final running = await service.show('cp');
          final state = jsonObject(running.clock['clock'], 'clock');
          equal(state['status'], 'running');
          recovered = await service.action(
            'cp',
            expectedVersion: running.version,
            expectedSessionVersion: 1,
            expectedClockVersion: state['version'] as int,
            action: 'recover',
          );
          equal(
            jsonObject(recovered.clock['clock'], 'clock')['status'],
            'paused',
          );
        } finally {
          await reopened.close();
        }
        final state = jsonObject(recovered.clock['clock'], 'clock');
        process = await launch(recovered.version, state['version'] as int);
        process.child.kill(ProcessSignal.sigint);
        check(
          await process.lines.moveNext().timeout(const Duration(seconds: 10)),
        );
        final response = jsonObject(
          jsonObject(jsonDecode(process.lines.current), 'response')['data'],
          'data',
        );
        equal(response['interrupted'], true);
        final checkpoint = jsonObject(response['checkpoint'], 'checkpoint');
        equal(
          jsonObject(
            jsonObject(checkpoint['clock'], 'binding')['clock'],
            'clock',
          )['status'],
          'paused',
        );
        equal(await process.child.exitCode, 0);
        await process.lines.cancel();
        equal(await process.errors, '');
        reopened = await TrainingStore.open(path);
        try {
          equal(
            (await reopened.session('session'))!.sets.first.status,
            SetStatus.planned,
          );
        } finally {
          await reopened.close();
        }
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test('manual rest is explicit and cannot imply a duration', () {
    final rest =
        Activity.fromJson({'id': 'recover', 'type': 'rest', 'manual': true})
            as Rest;
    check(rest.isManual);
    equal(rest.durationSeconds, null);
    jsonEqual(rest.toJson(), {'type': 'rest', 'id': 'recover', 'manual': true});
    for (final fields in [
      {'manual': false},
      {'manual': null},
      {'manual': true, 'durationSeconds': 10},
      {'durationSeconds': 0},
      <String, Object?>{},
    ]) {
      rejects(
        () => Activity.fromJson({'id': 'recover', 'type': 'rest', ...fields}),
      );
    }
    final timed =
        Activity.fromJson({
              'id': 'recover',
              'type': 'rest',
              'durationSeconds': 10,
            })
            as Rest;
    check(!timed.isManual);
    equal(timed.durationSeconds, 10);
  });
  test(
    'requested nested walk/run plan has 72 efforts and only two outer rests',
    () {
      final plan = Activity.fromJson({
        'id': 'blocks',
        'type': 'repeat',
        'count': 3,
        'restBetweenSeconds': 120,
        'child': {
          'id': 'rounds',
          'type': 'repeat',
          'count': 12,
          'child': {
            'id': 'pair',
            'type': 'sequence',
            'children': [
              {'id': 'walk', 'type': 'effort', 'slot': 'walk'},
              {'id': 'run', 'type': 'effort', 'slot': 'run'},
            ],
          },
        },
      });
      final occurrences = plan.occurrences().toList();
      equal(occurrences.where((o) => o.activity is Effort).length, 72);
      final rests = occurrences.map((o) => o.activity).whereType<Rest>();
      equal(rests.length, 2);
      equal(
        rests.fold<int>(0, (sum, rest) => sum + rest.durationSeconds!),
        240,
      );
      equal(occurrences.map((o) => o.id).toSet().length, 74);
      equal(72 * 30 + 240, 40 * 60);
      jsonEqual(Activity.fromJson(plan.toJson()).toJson(), plan.toJson());
    },
  );
  test('window structure preserves deadlines without claiming execution', () {
    final plan = Activity.fromJson({
      'id': 'minute',
      'type': 'window',
      'durationSeconds': 60,
      'child': {'id': 'set', 'type': 'effort', 'slot': 'clean'},
    });
    check(plan is TimeWindow);
    equal((plan as TimeWindow).durationSeconds, 60);
    equal(plan.occurrences().single.id, 'minute/set');
  });
  test(
    'nested repeated windows expose structural bounds without claiming timing or results',
    () async {
      final input = definition().toJson();
      input['plan'] = {
        'id': 'outer',
        'type': 'window',
        'durationSeconds': 600,
        'child': {
          'id': 'rounds',
          'type': 'repeat',
          'count': 2,
          'restBetweenSeconds': 30,
          'child': {
            'id': 'minute',
            'type': 'window',
            'durationSeconds': 60,
            'child': {
              'id': 'pair',
              'type': 'sequence',
              'children': [
                {'id': 'a', 'type': 'effort', 'slot': 'bench-heavy'},
                {'id': 'rest', 'type': 'rest', 'manual': true},
                {'id': 'b', 'type': 'effort', 'slot': 'bench-light'},
              ],
            },
          },
        },
      };
      final workout = WorkoutDefinition.fromJson(input);
      final groups = activityGroups(workout.plan);
      final byPath = {for (final group in groups) group.path: group};
      final first = byPath['outer/rounds[0]/minute']!;
      final second = byPath['outer/rounds[1]/minute']!;
      equal(first.start, 0);
      equal(first.end, 3);
      equal(first.windowDurationSeconds, 60);
      equal(second.start, 4);
      equal(second.end, 7);
      equal(byPath['outer']!.windowDurationSeconds, 600);
      equal(byPath['outer']!.end, 7);
      final between = activityGroups(workout.plan, containing: 3);
      check(between.any((g) => g.path == 'outer'));
      check(between.any((g) => g.path == 'outer/rounds'));
      check(between.every((g) => g.windowDurationSeconds != 60));
      final report = jsonObject(
        const Commands().execute('activity groups', {
          'schemaVersion': 1,
          'definition': input,
          'containing': 4,
        })['data'],
        'groups',
      );
      final cli = await invoke(
        ['activity', 'groups'],
        jsonEncode({'schemaVersion': 1, 'definition': input, 'containing': 4}),
      );
      equal(cli.code, 0);
      jsonEqual(jsonObject(jsonDecode(cli.output), 'response')['data'], report);
      equal(report['occurrenceCount'], 7);
      equal(report['containing'], 4);
      final visible = jsonList(
        report,
        'groups',
      ).map((g) => jsonObject(g, 'group')).toList();
      check(
        visible.any(
          (g) =>
              g['path'] == 'outer/rounds[1]/minute' &&
              g['windowDurationSeconds'] == 60,
        ),
      );
      check(
        visible.every(
          (g) => !g.containsKey('elapsed') && !g.containsKey('completed'),
        ),
      );
      final session = const TrainingService().start(
        sessionId: 'window-session',
        revision: WorkoutRevision.publish(workout),
        startedAt: instant(1),
      );
      rejects(() => executionPlan(session));
      rejects(
        () => const Commands().execute('activity groups', {
          'schemaVersion': 1,
          'definition': input,
          'containing': 7,
        }),
      );
      rejects(
        () => const Commands().execute('activity groups', {
          'schemaVersion': 1,
          'definition': input,
          'containing': -1,
        }),
      );
    },
  );
  test('duplicate IDs and unknown slots fail before a session is created', () {
    final input = definition().toJson();
    input['plan'] = {
      'id': 'dup',
      'type': 'sequence',
      'children': [
        {'id': 'same', 'type': 'effort', 'slot': 'bench-heavy'},
        {'id': 'same', 'type': 'effort', 'slot': 'bench-light'},
      ],
    };
    rejects(() => WorkoutDefinition.fromJson(input));
    input['plan'] = {'id': 'bad', 'type': 'effort', 'slot': 'missing'};
    rejects(() => WorkoutDefinition.fromJson(input));
  });
  test(
    'window deadlines use one explicit logical timeline and never certify effort',
    () async {
      final input = definition().toJson();
      input['plan'] = {
        'id': 'outer',
        'type': 'window',
        'durationSeconds': 10,
        'child': {
          'id': 'inner',
          'type': 'window',
          'durationSeconds': 3,
          'child': {'id': 'set', 'type': 'effort', 'slot': 'bench-heavy'},
        },
      };
      final workout = WorkoutDefinition.fromJson(input);
      const resolver = WindowDeadlines();
      final starts = <String, Object?>{'outer': 0, 'outer/inner': 9000};
      Map<String, Object?> resolve(
        int elapsed, [
        Map<String, Object?>? windows,
      ]) => resolver.evaluate(
        definition: workout,
        occurrence: 0,
        elapsedMilliseconds: elapsed,
        windowStarts: windows ?? starts,
      );
      final before = resolve(9999);
      equal(before['expired'], false);
      equal(before['earliestDeadlineMilliseconds'], 10000);
      final after = resolve(11000);
      final rows = jsonList(
        after,
        'windows',
      ).map((r) => jsonObject(r, 'window')).toList();
      equal(after['expired'], true);
      equal(rows[0]['expired'], true);
      equal(rows[0]['overrunMilliseconds'], 1000);
      equal(rows[1]['expired'], false);
      equal(rows[1]['remainingMilliseconds'], 1000);
      equal(resolve(12000)['expired'], true);
      equal(
        jsonObject(jsonList(resolve(12000), 'windows')[1], 'inner')['expired'],
        true,
      );
      final tied = resolve(10000, {'outer': 0, 'outer/inner': 7000});
      check(
        jsonList(
          tied,
          'windows',
        ).every((row) => jsonObject(row, 'window')['expired'] == true),
      );
      jsonEqual(resolve(11000), after);
      check(!after.containsKey('results') && !after.containsKey('completed'));
      rejects(() => resolve(11000, {'outer': 0}));
      rejects(() => resolve(11000, {'outer': 0, 'outer/inner': 10000}));
      rejects(() => resolve(11000, {'outer': 5000, 'outer/inner': 4000}));
      rejects(() => resolve(8000));
      rejects(() => resolve(2000000001));
      final request = {
        'schemaVersion': 1,
        'definition': input,
        'occurrence': 0,
        'elapsedMilliseconds': 11000,
        'windowStarts': starts,
      };
      final result = const Commands().execute(
        'activity window-status',
        request,
      );
      jsonEqual(result['data'], after);
      final cli = await invoke([
        'activity',
        'window-status',
      ], jsonEncode(request));
      equal(cli.code, 0);
      jsonEqual(jsonObject(jsonDecode(cli.output), 'response')['data'], after);
    },
  );
  test(
    'window crossing reports the first nested boundary without claiming work',
    () async {
      final input = definition().toJson();
      input['plan'] = {
        'id': 'outer',
        'type': 'window',
        'durationSeconds': 10,
        'child': {
          'id': 'sequence',
          'type': 'sequence',
          'children': [
            {'id': 'before', 'type': 'effort', 'slot': 'bench-heavy'},
            {
              'id': 'inner',
              'type': 'window',
              'durationSeconds': 3,
              'child': {
                'id': 'during',
                'type': 'effort',
                'slot': 'bench-heavy',
              },
            },
            {'id': 'after', 'type': 'effort', 'slot': 'bench-light'},
          ],
        },
      };
      final workout = WorkoutDefinition.fromJson(input);
      const resolver = WindowDeadlines();
      Map<String, Object?> crossing(int before, int after, int innerStart) =>
          resolver.crossing(
            definition: workout,
            occurrence: 1,
            previousElapsedMilliseconds: before,
            elapsedMilliseconds: after,
            windowStarts: {'outer': 0, 'outer/sequence/inner': innerStart},
          );
      equal(crossing(8000, 9999, 8000)['status'], 'within');
      final parent = crossing(8000, 12000, 8000);
      equal(parent['status'], 'crossed');
      final parentBoundary = jsonObject(parent['boundary'], 'boundary');
      equal(parentBoundary['elapsedMilliseconds'], 10000);
      jsonEqual(parentBoundary['paths'], ['outer']);
      equal(parentBoundary['scopeStart'], 0);
      equal(parentBoundary['scopeEnd'], 3);
      final child = jsonObject(
        crossing(1000, 11000, 1000)['boundary'],
        'boundary',
      );
      equal(child['elapsedMilliseconds'], 4000);
      jsonEqual(child['paths'], ['outer/sequence/inner']);
      equal(child['scopeStart'], 1);
      equal(child['scopeEnd'], 2);
      final tied = jsonObject(
        crossing(7000, 10000, 7000)['boundary'],
        'boundary',
      );
      jsonEqual(tied['paths'], ['outer', 'outer/sequence/inner']);
      equal(tied['scopeEnd'], 3);
      equal(crossing(10000, 11000, 8000)['status'], 'alreadyExpired');
      equal(crossing(10000, 10000, 8000)['boundary'], null);
      final unscoped = resolver.crossing(
        definition: definition(),
        occurrence: 0,
        previousElapsedMilliseconds: 0,
        elapsedMilliseconds: 10000,
        windowStarts: {},
      );
      equal(unscoped['status'], 'within');
      equal(unscoped['boundary'], null);
      rejects(() => crossing(9000, 8999, 8000));
      rejects(() => crossing(7999, 9000, 8000));
      check(!parent.containsKey('results') && !parent.containsKey('completed'));
      final request = {
        'schemaVersion': 1,
        'definition': input,
        'occurrence': 1,
        'previousElapsedMilliseconds': 8000,
        'elapsedMilliseconds': 12000,
        'windowStarts': {'outer': 0, 'outer/sequence/inner': 8000},
      };
      jsonEqual(
        const Commands().execute('activity window-crossing', request)['data'],
        parent,
      );
      final result = await invoke([
        'activity',
        'window-crossing',
      ], jsonEncode(request));
      equal(result.code, 0);
      jsonEqual(
        jsonObject(jsonDecode(result.output), 'response')['data'],
        parent,
      );
    },
  );
  test(
    'window transitions retain enclosing starts and validate scope entries',
    () async {
      final input = definition().toJson();
      input['plan'] = {
        'id': 'workout',
        'type': 'sequence',
        'children': [
          {
            'id': 'outer',
            'type': 'window',
            'durationSeconds': 10,
            'child': {
              'id': 'rounds',
              'type': 'repeat',
              'count': 2,
              'child': {
                'id': 'inner',
                'type': 'window',
                'durationSeconds': 5,
                'child': {
                  'id': 'pair',
                  'type': 'sequence',
                  'children': [
                    {'id': 'first', 'type': 'effort', 'slot': 'bench-heavy'},
                    {'id': 'second', 'type': 'effort', 'slot': 'bench-light'},
                  ],
                },
              },
            },
          },
          {'id': 'outside', 'type': 'effort', 'slot': 'bench-light'},
        ],
      };
      final workout = WorkoutDefinition.fromJson(input);
      const resolver = WindowDeadlines();
      const outer = 'workout/outer';
      const first = 'workout/outer/rounds[0]/inner';
      const second = 'workout/outer/rounds[1]/inner';
      Map<String, Object?> move(
        int from,
        int to,
        int time,
        Map<String, Object?> starts,
      ) => resolver.transition(
        definition: workout,
        fromOccurrence: from,
        toOccurrence: to,
        elapsedMilliseconds: time,
        windowStarts: starts,
      );
      final within = move(0, 1, 2000, {outer: 0, first: 0});
      jsonEqual(within['windowStarts'], {outer: 0, first: 0});
      jsonEqual(within['entered'], []);
      jsonEqual(within['exited'], []);
      final next = move(1, 2, 5000, {outer: 0, first: 0});
      jsonEqual(next['exited'], [first]);
      jsonEqual(next['entered'], [second]);
      jsonEqual(next['windowStarts'], {outer: 0, second: 5000});
      final exit = move(1, 4, 10000, {outer: 0, first: 0});
      jsonEqual(exit['exited'], [first, outer]);
      jsonEqual(exit['windowStarts'], {});
      final end = move(4, 5, 10000, {});
      equal(end['toOccurrenceId'], null);
      rejects(() => move(0, 1, 5000, {outer: 0, first: 0}));
      rejects(() => move(1, 2, 10000, {outer: 0, first: 0}));
      rejects(() => move(0, 3, 2000, {outer: 0, first: 0}));
      rejects(() => move(0, 0, 2000, {outer: 0, first: 0}));
      rejects(() => move(0, 6, 2000, {outer: 0, first: 0}));
      rejects(() => move(1, 2, 5000, {outer: 0}));
      check(!next.containsKey('results') && !next.containsKey('completed'));
      final request = {
        'schemaVersion': 1,
        'definition': input,
        'fromOccurrence': 1,
        'toOccurrence': 2,
        'elapsedMilliseconds': 5000,
        'windowStarts': {outer: 0, first: 0},
      };
      jsonEqual(
        const Commands().execute('activity window-transition', request)['data'],
        next,
      );
      final cli = await invoke([
        'activity',
        'window-transition',
      ], jsonEncode(request));
      equal(cli.code, 0);
      jsonEqual(jsonObject(jsonDecode(cli.output), 'response')['data'], next);
    },
  );
  test(
    'caller-owned window clock freezes on recovery and waits at boundaries',
    () async {
      final input = definition().toJson();
      input['plan'] = {
        'id': 'rounds',
        'type': 'repeat',
        'count': 2,
        'child': {
          'id': 'minute',
          'type': 'window',
          'durationSeconds': 5,
          'child': {'id': 'set', 'type': 'effort', 'slot': 'bench-heavy'},
        },
      };
      final workout = WorkoutDefinition.fromJson(input);
      const clock = WindowClock();
      var state = clock.start(workout);
      equal(state['status'], 'paused');
      jsonEqual(state['windowStarts'], {'rounds[0]/minute': 0});
      state = clock.apply(
        workout,
        state,
        expectedVersion: 1,
        action: 'resume',
        ownerId: 'epoch',
      );
      rejects(
        () => clock.apply(
          workout,
          state,
          expectedVersion: 2,
          action: 'advance',
          ownerId: 'other',
          ownerElapsedMilliseconds: 1,
        ),
      );
      rejects(
        () =>
            clock.apply(workout, state, expectedVersion: 1, action: 'recover'),
        'conflict',
      );
      state = clock.apply(
        workout,
        state,
        expectedVersion: 2,
        action: 'advance',
        ownerId: 'epoch',
        ownerElapsedMilliseconds: 3000,
      );
      equal(state['elapsedMilliseconds'], 3000);
      rejects(
        () => clock.apply(
          workout,
          state,
          expectedVersion: 3,
          action: 'advance',
          ownerId: 'epoch',
          ownerElapsedMilliseconds: 2999,
        ),
      );
      state = clock.apply(
        workout,
        state,
        expectedVersion: 3,
        action: 'recover',
      );
      equal(state['elapsedMilliseconds'], 3000);
      equal(state['status'], 'paused');
      state = clock.apply(
        workout,
        state,
        expectedVersion: 4,
        action: 'resume',
        ownerId: 'new-epoch',
      );
      state = clock.apply(
        workout,
        state,
        expectedVersion: 5,
        action: 'advance',
        ownerId: 'new-epoch',
        ownerElapsedMilliseconds: 4000,
      );
      equal(state['status'], 'boundary');
      equal(state['elapsedMilliseconds'], 5000);
      equal(state['occurrenceStartedMilliseconds'], 0);
      jsonEqual(state['boundaryEvidence'], {
        'deadlineMilliseconds': 5000,
        'paths': ['rounds[0]/minute'],
        'unappliedMilliseconds': 2000,
        'trigger': 'advance',
      });
      final forgedBoundary = {
        ...state,
        'boundaryEvidence': {
          ...jsonObject(state['boundaryEvidence'], 'evidence'),
          'paths': ['wrong'],
        },
      };
      rejects(
        () => clock.apply(
          workout,
          forgedBoundary,
          expectedVersion: 6,
          action: 'move',
          toOccurrence: 1,
        ),
      );
      final legacy = {...state, 'policy': 'bodytmi-window-clock/1'}
        ..remove('occurrenceStartedMilliseconds')
        ..remove('boundaryEvidence');
      final legacyNext = clock.apply(
        workout,
        legacy,
        expectedVersion: 6,
        action: 'move',
        toOccurrence: 1,
      );
      equal(legacyNext['occurrenceStartedMilliseconds'], 5000);
      rejects(
        () => clock.apply(
          workout,
          state,
          expectedVersion: 6,
          action: 'resume',
          ownerId: 'epoch',
        ),
      );
      state = clock.apply(
        workout,
        state,
        expectedVersion: 6,
        action: 'move',
        toOccurrence: 1,
      );
      jsonEqual(state['windowStarts'], {'rounds[1]/minute': 5000});
      equal(state['occurrenceStartedMilliseconds'], 5000);
      check(!state.containsKey('boundaryEvidence'));
      state = clock.apply(
        workout,
        state,
        expectedVersion: 7,
        action: 'resume',
        ownerId: 'third',
      );
      state = clock.apply(
        workout,
        state,
        expectedVersion: 8,
        action: 'pause',
        ownerId: 'third',
        ownerElapsedMilliseconds: 1000,
      );
      equal(state['elapsedMilliseconds'], 6000);
      state = clock.apply(
        workout,
        state,
        expectedVersion: 9,
        action: 'move',
        toOccurrence: 2,
      );
      equal(state['status'], 'complete');
      equal(state['occurrenceStartedMilliseconds'], null);
      check(!state.containsKey('results'));
      final forged = {...clock.start(workout), 'status': 'boundary'};
      final future = {
        ...clock.start(workout),
        'policy': 'bodytmi-window-clock/3',
      };
      rejects(
        () => clock.apply(
          workout,
          future,
          expectedVersion: 1,
          action: 'resume',
          ownerId: 'epoch',
        ),
      );
      rejects(
        () => clock.apply(
          workout,
          forged,
          expectedVersion: 1,
          action: 'move',
          toOccurrence: 1,
        ),
      );
      final badSample = {
        ...clock.start(workout),
        'status': 'running',
        'ownerId': 'owner',
        'ownerElapsedMilliseconds': 1,
      };
      rejects(
        () => clock.apply(
          workout,
          badSample,
          expectedVersion: 1,
          action: 'recover',
        ),
      );
      final changed = workout.toJson();
      changed['name'] = 'Different workout';
      rejects(
        () => clock.apply(
          WorkoutDefinition.fromJson(changed),
          clock.start(workout),
          expectedVersion: 1,
          action: 'resume',
          ownerId: 'epoch',
        ),
      );
      final request = {
        'schemaVersion': 1,
        'definition': input,
        'action': 'start',
      };
      final cli = await invoke([
        'activity',
        'window-clock',
      ], jsonEncode(request));
      equal(cli.code, 0);
      jsonEqual(
        jsonObject(jsonDecode(cli.output), 'response')['data'],
        clock.start(workout),
      );
      final resumeRequest = {
        'schemaVersion': 1,
        'definition': input,
        'action': 'resume',
        'clock': clock.start(workout),
        'expectedVersion': 1,
        'ownerId': 'cli-epoch',
      };
      final resumed = await invoke([
        'activity',
        'window-clock',
      ], jsonEncode(resumeRequest));
      equal(resumed.code, 0);
      equal(
        jsonObject(
          jsonObject(jsonDecode(resumed.output), 'response')['data'],
          'clock',
        )['status'],
        'running',
      );
    },
  );
  test(
    'window clock recovery applies only explicit bounded elapsed time',
    () async {
      final input = definition().toJson();
      input['plan'] = {
        'id': 'outer',
        'type': 'window',
        'durationSeconds': 5,
        'child': {
          'id': 'inner',
          'type': 'window',
          'durationSeconds': 10,
          'child': {'id': 'set', 'type': 'effort', 'slot': 'bench-heavy'},
        },
      };
      final workout = WorkoutDefinition.fromJson(input);
      const service = WindowClock();
      var clock = service.start(workout);
      clock = service.apply(
        workout,
        clock,
        expectedVersion: 1,
        action: 'resume',
        ownerId: 'epoch',
      );
      clock = service.apply(
        workout,
        clock,
        expectedVersion: 2,
        action: 'advance',
        ownerId: 'epoch',
        ownerElapsedMilliseconds: 3000,
      );
      final frozen = service.apply(
        workout,
        clock,
        expectedVersion: 3,
        action: 'recover',
      );
      equal(frozen['elapsedMilliseconds'], 3000);
      equal(frozen['status'], 'paused');
      final adjusted = service.apply(
        workout,
        clock,
        expectedVersion: 3,
        action: 'recover',
        adjustmentMilliseconds: 1500,
      );
      equal(adjusted['elapsedMilliseconds'], 4500);
      equal(adjusted['status'], 'paused');
      equal(adjusted['ownerId'], null);
      final boundary = service.apply(
        workout,
        clock,
        expectedVersion: 3,
        action: 'recover',
        adjustmentMilliseconds: 9000,
      );
      equal(boundary['status'], 'boundary');
      equal(boundary['elapsedMilliseconds'], 5000);
      jsonEqual(boundary['boundaryEvidence'], {
        'deadlineMilliseconds': 5000,
        'paths': ['outer'],
        'unappliedMilliseconds': 7000,
        'trigger': 'recover',
      });
      final tiedInput = copyJson(input);
      jsonObject(
        jsonObject(tiedInput['plan'], 'outer')['child'],
        'inner',
      )['durationSeconds'] = 5;
      final tiedWorkout = WorkoutDefinition.fromJson(tiedInput);
      var tiedClock = service.start(tiedWorkout);
      tiedClock = service.apply(
        tiedWorkout,
        tiedClock,
        expectedVersion: 1,
        action: 'resume',
        ownerId: 'tied',
      );
      tiedClock = service.apply(
        tiedWorkout,
        tiedClock,
        expectedVersion: 2,
        action: 'pause',
        ownerId: 'tied',
        ownerElapsedMilliseconds: 5000,
      );
      jsonEqual(
        jsonObject(tiedClock['boundaryEvidence'], 'evidence')['paths'],
        ['outer', 'outer/inner'],
      );
      equal(jsonObject(boundary['windowStarts'], 'starts')['outer/inner'], 0);
      check(!boundary.containsKey('results'));
      rejects(
        () => service.apply(
          workout,
          clock,
          expectedVersion: 3,
          action: 'recover',
          adjustmentMilliseconds: -1,
        ),
      );
      rejects(
        () => service.apply(
          workout,
          clock,
          expectedVersion: 3,
          action: 'recover',
          adjustmentMilliseconds: 2000000000,
        ),
      );
      rejects(
        () => service.apply(
          workout,
          clock,
          expectedVersion: 3,
          action: 'advance',
          ownerId: 'epoch',
          ownerElapsedMilliseconds: 3001,
          adjustmentMilliseconds: 1,
        ),
      );
      rejects(
        () => service.apply(
          workout,
          frozen,
          expectedVersion: 4,
          action: 'recover',
          adjustmentMilliseconds: 1,
        ),
      );
      final request = {
        'schemaVersion': 1,
        'definition': input,
        'action': 'recover',
        'clock': clock,
        'expectedVersion': 3,
        'adjustmentMilliseconds': 9000,
      };
      jsonEqual(
        const Commands().execute('activity window-clock', request)['data'],
        boundary,
      );
      final cli = await invoke([
        'activity',
        'window-clock',
      ], jsonEncode(request));
      equal(cli.code, 0);
      jsonEqual(
        jsonObject(jsonDecode(cli.output), 'response')['data'],
        boundary,
      );
      request['adjustmentMilliseconds'] = '1';
      final bad = await invoke([
        'activity',
        'window-clock',
      ], jsonEncode(request));
      equal(bad.code, 2);
      equal(bad.output, '');
    },
  );
  test(
    'session window clocks require explicit review before movement',
    () async {
      final input = definition().toJson();
      input['plan'] = {
        'id': 'rounds',
        'type': 'repeat',
        'count': 2,
        'child': {
          'id': 'minute',
          'type': 'window',
          'durationSeconds': 5,
          'child': {'id': 'set', 'type': 'effort', 'slot': 'bench-heavy'},
        },
      };
      final workout = WorkoutDefinition.fromJson(input);
      final revision = WorkoutRevision.publish(workout);
      const training = TrainingService();
      const windows = SessionWindowClock();
      var session = training.start(
        sessionId: 'session',
        revision: revision,
        startedAt: instant(1),
      );
      final original = session.toJson();
      var state = windows.start(session);
      state = windows.apply(
        session,
        state,
        expectedVersion: 1,
        action: 'resume',
        ownerId: 'epoch',
      );
      state = windows.apply(
        session,
        state,
        expectedVersion: 2,
        action: 'advance',
        ownerId: 'epoch',
        ownerElapsedMilliseconds: 6000,
      );
      equal(jsonObject(state['clock'], 'clock')['status'], 'boundary');
      rejects(
        () => windows.apply(
          session,
          state,
          expectedVersion: 3,
          action: 'move',
          toOccurrence: 1,
        ),
      );
      jsonEqual(session.toJson(), original);
      final old = session;
      final reviewed = const SessionWindowReview().review(
        session,
        state,
        expectedSessionVersion: session.contentVersion,
        expectedClockVersion: 3,
        toOccurrence: 1,
        action: 'complete',
        actuals: session.sets.first.suggested,
      );
      equal(reviewed.session.sets.first.status, SetStatus.completed);
      equal(jsonObject(reviewed.clock['clock'], 'clock')['occurrence'], 1);
      final pureReview = const Commands().execute('session window-review', {
        'schemaVersion': 1,
        'session': session.toJson(),
        'clock': state,
        'expectedSessionVersion': 1,
        'expectedClockVersion': 3,
        'toOccurrence': 1,
        'action': 'complete',
        'actuals': metricsToJson(session.sets.first.suggested),
      });
      jsonEqual(pureReview['data'], {
        'session': reviewed.session.toJson(),
        'clock': reviewed.clock,
        'occurrenceId': reviewed.occurrenceId,
      });
      final skipped = const SessionWindowReview().review(
        session,
        state,
        expectedSessionVersion: 1,
        expectedClockVersion: 3,
        toOccurrence: 1,
        action: 'skip',
        confirm: true,
      );
      equal(skipped.session.sets.first.status, SetStatus.skipped);
      check(skipped.session.sets.first.actuals.isEmpty);
      rejects(
        () => const SessionWindowReview().review(
          session,
          state,
          expectedSessionVersion: 1,
          expectedClockVersion: 3,
          toOccurrence: 2,
          action: 'complete',
          actuals: session.sets.first.suggested,
        ),
      );
      rejects(
        () => const SessionWindowReview().review(
          session,
          state,
          expectedSessionVersion: 1,
          expectedClockVersion: 3,
          toOccurrence: 1,
          action: 'skip',
        ),
      );
      rejects(
        () => const SessionWindowReview().review(
          reviewed.session,
          state,
          expectedSessionVersion: 1,
          expectedClockVersion: 3,
          toOccurrence: 1,
          action: 'complete',
          actuals: session.sets.first.suggested,
        ),
        'conflict',
      );
      jsonEqual(session.toJson(), original);
      session = training.complete(
        session,
        session.sets.first.id,
        session.sets.first.suggested,
      );
      state = windows.apply(
        session,
        state,
        expectedVersion: 3,
        action: 'move',
        toOccurrence: 1,
      );
      equal(state['sessionContentVersion'], session.contentVersion);
      rejects(
        () => windows.apply(
          old,
          state,
          expectedVersion: 4,
          action: 'resume',
          ownerId: 'next',
        ),
      );
      final other = training.start(
        sessionId: 'other',
        revision: revision,
        startedAt: instant(1),
      );
      rejects(
        () => windows.apply(
          other,
          state,
          expectedVersion: 4,
          action: 'resume',
          ownerId: 'next',
        ),
      );
      final newer = training.start(
        sessionId: 'session',
        revision: WorkoutRevision.publish(workout, previous: revision),
        startedAt: instant(1),
      );
      rejects(
        () => windows.apply(
          newer,
          windows.start(old),
          expectedVersion: 1,
          action: 'resume',
          ownerId: 'epoch',
        ),
      );
      session = training.skip(session, session.sets.last.id, confirm: true);
      state = windows.apply(
        session,
        state,
        expectedVersion: 4,
        action: 'move',
        toOccurrence: 2,
      );
      equal(jsonObject(state['clock'], 'clock')['status'], 'complete');
      equal(session.sets.last.status, SetStatus.skipped);
      rejects(() => windows.start(session.finish(instant(2))));

      final startRequest = {
        'schemaVersion': 1,
        'session': old.toJson(),
        'action': 'start',
      };
      final pure = const Commands().execute(
        'session window-clock',
        startRequest,
      );
      jsonEqual(pure['data'], windows.start(old));
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-session-window-',
      );
      try {
        final db = '${dir.path}/db.sqlite';
        Future<Map<String, Object?>> command(
          String name,
          Map<String, Object?> request,
        ) async {
          final result = await invoke(
            name.split(' '),
            jsonEncode({'schemaVersion': 1, 'database': db, ...request}),
          );
          equal(result.code, 0);
          return jsonObject(
            jsonObject(jsonDecode(result.output), 'response')['data'],
            'data',
          );
        }

        await command('store publish', {
          'definition': input,
          'expectedRevision': 0,
        });
        await command('store start', {
          'id': 'session',
          'templateId': workout.id,
          'revision': 1,
          'startedAt': instant(1).toIso8601String(),
        });
        final stored = await command('store window-clock', {
          'id': 'session',
          'action': 'start',
        });
        jsonEqual(stored, windows.start(old));
        final resumed = await command('store window-clock', {
          'id': 'session',
          'action': 'resume',
          'clock': stored,
          'expectedVersion': 1,
          'ownerId': 'cli',
        });
        equal(jsonObject(resumed['clock'], 'clock')['status'], 'running');
        final recovered = await command('store window-clock', {
          'id': 'session',
          'action': 'recover',
          'clock': resumed,
          'expectedVersion': 2,
          'adjustmentMilliseconds': 6000,
        });
        equal(jsonObject(recovered['clock'], 'clock')['status'], 'boundary');
        equal(
          jsonObject(recovered['clock'], 'clock')['elapsedMilliseconds'],
          5000,
        );
        final loaded = await command('store show', {'id': 'session'});
        jsonEqual(loaded, old.toJson());
        final payload = {
          'id': 'session',
          'clock': recovered,
          'expectedSessionVersion': 1,
          'expectedClockVersion': 3,
          'toOccurrence': 1,
          'action': 'complete',
          'actuals': metricsToJson(old.sets.first.suggested),
        };
        final invalidMove = await invoke(
          ['store', 'window-review'],
          jsonEncode({
            'schemaVersion': 1,
            'database': db,
            ...payload,
            'toOccurrence': 2,
          }),
        );
        equal(invalidMove.code, 2);
        equal(
          (await command('store show', {'id': 'session'}))['contentVersion'],
          1,
        );
        final storedReview = await command('store window-review', payload);
        equal(
          jsonObject(storedReview['session'], 'session')['contentVersion'],
          2,
        );
        equal(
          jsonObject(
            jsonObject(storedReview['clock'], 'wrapper')['clock'],
            'clock',
          )['occurrence'],
          1,
        );
        final retry = await invoke([
          'store',
          'window-review',
        ], jsonEncode({'schemaVersion': 1, 'database': db, ...payload}));
        equal(retry.code, 5);
        equal(retry.output, '');
        final saved = await command('store show', {'id': 'session'});
        equal(saved['contentVersion'], 2);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'inert window checkpoints persist, validate and survive portability',
    () async {
      final input = definition().toJson();
      input['plan'] = {
        'id': 'window',
        'type': 'window',
        'durationSeconds': 5,
        'child': {'id': 'effort', 'type': 'effort', 'slot': 'bench-heavy'},
      };
      final workout = WorkoutDefinition.fromJson(input);
      final dir = await Directory.systemTemp.createTemp('bodytmi-checkpoints-');
      final path = '${dir.path}/db.sqlite';
      var store = await TrainingStore.open(path);
      try {
        final training = StoredTrainingService(store);
        await training.publish(workout, 0);
        final session = await training.start(
          'session',
          workout.id,
          1,
          instant(1),
        );
        const scoped = SessionWindowClock();
        var clock = scoped.start(session);
        final advanced = const WindowClock().apply(
          workout,
          jsonObject(clock['clock'], 'clock'),
          expectedVersion: 1,
          action: 'move',
          toOccurrence: 1,
        );
        final forgedAhead = {...clock, 'clock': advanced};
        await expectCheckpointFailure(
          WindowCheckpointService(
            store,
          ).save('forged', session.id, 0, forgedAhead),
        );
        equal(await store.windowCheckpoint('forged'), null);
        clock = scoped.apply(
          session,
          clock,
          expectedVersion: 1,
          action: 'resume',
          ownerId: 'epoch',
        );
        clock = scoped.apply(
          session,
          clock,
          expectedVersion: 2,
          action: 'advance',
          ownerId: 'epoch',
          ownerElapsedMilliseconds: 1000,
        );
        var checkpoint = await WindowCheckpointService(
          store,
        ).save('checkpoint', session.id, 0, clock);
        equal(checkpoint.version, 1);
        try {
          await store.transaction<void>(() async {
            await WindowCheckpointService(
              store,
            ).save('rollback', session.id, 0, clock);
            throw StateError('rollback');
          });
          throw StateError('Transaction unexpectedly committed.');
        } on StateError catch (error) {
          equal(error.message, 'rollback');
        }
        equal(await store.windowCheckpoint('rollback'), null);
        await expectCheckpointFailure(
          WindowCheckpointService(
            store,
          ).save('checkpoint', session.id, 0, clock),
          'conflict',
        );
        final copy = checkpoint.clock;
        copy['sessionId'] = 'other';
        equal(checkpoint.clock['sessionId'], session.id);
        await store.close();
        store = await TrainingStore.open(path);
        checkpoint = await WindowCheckpointService(store).show('checkpoint');
        equal(canonicalJson(checkpoint.clock), canonicalJson(clock));
        final frozen = scoped.apply(
          await StoredTrainingService(store).session('session'),
          checkpoint.clock,
          expectedVersion: 3,
          action: 'recover',
        );
        equal(
          jsonObject(frozen['clock'], 'clock')['elapsedMilliseconds'],
          1000,
        );
        checkpoint = await WindowCheckpointService(
          store,
        ).save('checkpoint', 'session', 1, frozen);
        equal(checkpoint.version, 2);
        await WindowCheckpointService(
          store,
        ).save('running', 'session', 0, clock);
        final forgedArchive = copyJson((await store.archive()).toJson());
        final row = jsonObject(
          jsonList(forgedArchive, 'windowCheckpoints').first,
          'checkpoint',
        );
        jsonObject(row['clock'], 'session clock')['sessionStartedAt'] =
            '2026-01-01T00:00:00.000Z';
        rejects(() => TrainingArchive.fromJson(forgedArchive));
        final before = canonicalJson((await store.archive()).toJson());
        await store.backup('${dir.path}/native');
        await LogicalArchiveFiles.export(
          await store.archive(),
          '${dir.path}/logical.json',
        );
        final logical = await LogicalArchiveFiles.prepare(
          '${dir.path}/logical.json',
        );
        try {
          equal(canonicalJson(logical.archive.toJson()), before);
          await store.restore(
            logical.backup,
            recoveryDestination: '${dir.path}/recovery',
            confirm: true,
          );
        } finally {
          await logical.close();
          await store.close();
        }
        store = await TrainingStore.open(path);
        equal(canonicalJson((await store.archive()).toJson()), before);
        final restoredRunning = await WindowCheckpointService(
          store,
        ).show('running');
        final restoredFrozen = scoped.apply(
          await StoredTrainingService(store).session('session'),
          restoredRunning.clock,
          expectedVersion: 3,
          action: 'recover',
        );
        equal(jsonObject(restoredFrozen['clock'], 'clock')['status'], 'paused');
        final nativePrepared = await NativeBackup.prepare('${dir.path}/native');
        try {
          await store.restore(
            nativePrepared,
            recoveryDestination: '${dir.path}/recovery2',
            confirm: true,
          );
        } finally {
          await nativePrepared.close();
          await store.close();
        }
        store = await TrainingStore.open(path);
        equal(canonicalJson((await store.archive()).toJson()), before);
        equal(
          NativeBackup.validateDatabase('${dir.path}/native/database.sqlite'),
          56,
        );
        final archive = jsonObject(
          jsonDecode(await File('${dir.path}/logical.json').readAsString()),
          'archive',
        );
        archive['format'] = 'bodytmi-logical-export/45';
        archive.remove('sha256');
        archive['sha256'] = sha256
            .convert(utf8.encode(canonicalJson(archive)))
            .toString();
        await File('${dir.path}/old.json').writeAsString(jsonEncode(archive));
        await expectCheckpointFailure(
          LogicalArchiveFiles.prepare('${dir.path}/old.json'),
        );
        final raw = sqlite3.open('${dir.path}/native/database.sqlite');
        final originalSnapshot =
            raw
                    .select(
                      "SELECT snapshot FROM window_checkpoints WHERE id = 'checkpoint'",
                    )
                    .single['snapshot']
                as String;
        final badSnapshot = jsonObject(
          jsonDecode(originalSnapshot),
          'checkpoint',
        );
        jsonObject(
          jsonObject(badSnapshot['clock'], 'wrapper')['clock'],
          'clock',
        )['ownerElapsedMilliseconds'] = 1;
        raw.execute(
          "UPDATE window_checkpoints SET snapshot = ? WHERE id = 'checkpoint'",
          [jsonEncode(badSnapshot)],
        );
        rejects(
          () => NativeBackup.validateDatabase(
            '${dir.path}/native/database.sqlite',
          ),
        );
        raw.execute(
          "UPDATE window_checkpoints SET snapshot = ? WHERE id = 'checkpoint'",
          [originalSnapshot],
        );
        raw.execute('DROP TABLE IF EXISTS progression_reconciliations');
        raw.execute('DROP TABLE IF EXISTS lever_link_revisions');
        raw.execute('DROP TABLE IF EXISTS shared_lever_applications');
        raw.execute('DROP TABLE IF EXISTS link_retirement_anchors');
        raw.execute('DROP TABLE IF EXISTS program_upgrade_receipts');
        raw.userVersion = 45;
        raw.close();
        rejects(
          () => NativeBackup.validateDatabase(
            '${dir.path}/native/database.sqlite',
          ),
        );
        final current = await StoredTrainingService(store).session('session');
        await StoredTrainingService(store).edit(
          'session',
          current.contentVersion,
          (s) => const TrainingService()
              .complete(s, s.sets.single.id, s.sets.single.suggested)
              .finish(instant(2)),
        );
        equal(
          (await WindowCheckpointService(store).show('checkpoint')).version,
          2,
        );
        equal((await store.archive()).windowCheckpoints.length, 2);
        await store.backup('${dir.path}/finished-native');
        equal(
          NativeBackup.validateDatabase(
            '${dir.path}/finished-native/database.sqlite',
          ),
          56,
        );
        await expectCheckpointFailure(
          WindowCheckpointService(
            store,
          ).delete('checkpoint', 2, confirm: false),
        );
        await WindowCheckpointService(
          store,
        ).delete('checkpoint', 2, confirm: true);
        await WindowCheckpointService(
          store,
        ).delete('running', 1, confirm: true);
        equal((await WindowCheckpointService(store).list()).length, 0);
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'checkpoint review commits result and clock together or rolls both back',
    () async {
      final input = definition().toJson();
      input['plan'] = {
        'id': 'rounds',
        'type': 'repeat',
        'count': 2,
        'child': {
          'id': 'window',
          'type': 'window',
          'durationSeconds': 5,
          'child': {'id': 'set', 'type': 'effort', 'slot': 'bench-heavy'},
        },
      };
      final workout = WorkoutDefinition.fromJson(input);
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-checkpoint-review-',
      );
      final path = '${dir.path}/db.sqlite';
      final store = await TrainingStore.open(path);
      try {
        final training = StoredTrainingService(store);
        await training.publish(workout, 0);
        final session = await training.start(
          'session',
          workout.id,
          1,
          instant(1),
        );
        final checkpoints = WindowCheckpointService(store);
        await checkpoints.save(
          'cp',
          session.id,
          0,
          const SessionWindowClock().start(session),
        );
        Future<Object?> review({int destination = 1, int version = 1}) =>
            checkpoints.review(
              'cp',
              expectedVersion: version,
              expectedSessionVersion: 1,
              expectedClockVersion: 1,
              toOccurrence: destination,
              action: 'complete',
              actuals: session.sets.first.suggested,
            );
        await expectCheckpointFailure(review(destination: 2));
        equal((await training.session('session')).contentVersion, 1);
        equal((await checkpoints.show('cp')).version, 1);
        final raw = sqlite3.open(path);
        try {
          raw.execute(
            "CREATE TRIGGER test_checkpoint_failure BEFORE UPDATE ON window_checkpoints BEGIN SELECT RAISE(ABORT, 'forced checkpoint failure'); END",
          );
          var failed = false;
          try {
            await review();
          } catch (_) {
            failed = true;
          }
          check(failed);
          equal((await training.session('session')).contentVersion, 1);
          equal((await checkpoints.show('cp')).version, 1);
          raw.execute('DROP TRIGGER test_checkpoint_failure');
        } finally {
          raw.close();
        }
        final result = await checkpoints.review(
          'cp',
          expectedVersion: 1,
          expectedSessionVersion: 1,
          expectedClockVersion: 1,
          toOccurrence: 1,
          action: 'complete',
          actuals: session.sets.first.suggested,
        );
        equal(result.session.sets.first.status, SetStatus.completed);
        equal(result.checkpoint.version, 2);
        equal(
          jsonObject(result.checkpoint.clock['clock'], 'clock')['occurrence'],
          1,
        );
        await expectCheckpointFailure(review(), 'conflict');
        final skipped = await checkpoints.review(
          'cp',
          expectedVersion: 2,
          expectedSessionVersion: 2,
          expectedClockVersion: 2,
          toOccurrence: 2,
          action: 'skip',
          confirm: true,
        );
        equal(skipped.session.sets.last.status, SetStatus.skipped);
        equal(skipped.checkpoint.version, 3);
        equal(
          jsonObject(skipped.checkpoint.clock['clock'], 'clock')['status'],
          'complete',
        );
        await store.backup('${dir.path}/native');
        equal(
          NativeBackup.validateDatabase('${dir.path}/native/database.sqlite'),
          56,
        );
        await LogicalArchiveFiles.export(
          await store.archive(),
          '${dir.path}/archive.json',
        );
        final restored = await LogicalArchiveFiles.prepare(
          '${dir.path}/archive.json',
        );
        try {
          equal(restored.archive.windowCheckpoints.single.version, 3);
          equal(restored.archive.sessions.single.contentVersion, 3);
        } finally {
          await restored.close();
        }
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'checkpoint review survives process death before and after commit',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-checkpoint-crash-',
      );
      final path = '${dir.path}/db.sqlite';
      final store = await TrainingStore.open(path);
      try {
        final workout = definition();
        await StoredTrainingService(store).publish(workout, 0);
        final session = await StoredTrainingService(
          store,
        ).start('session', workout.id, 1, instant(1));
        await WindowCheckpointService(
          store,
        ).save('cp', session.id, 0, const SessionWindowClock().start(session));
        await store.close();
        final binary = await compileNative(
          'test/helpers/store_owner.dart',
          '${dir.path}/owner',
        );
        for (final mode in [
          'checkpoint-review-rollback',
          'checkpoint-review-commit',
        ]) {
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
          } finally {
            child.kill(ProcessSignal.sigkill);
            await child.exitCode;
          }
          final reopened = await TrainingStore.open(path);
          try {
            final committed = mode.endsWith('commit');
            final saved = await StoredTrainingService(
              reopened,
            ).session('session');
            final checkpoint = await WindowCheckpointService(
              reopened,
            ).show('cp');
            equal(
              saved.sets.first.status,
              committed ? SetStatus.skipped : SetStatus.planned,
            );
            equal(saved.contentVersion, committed ? 2 : 1);
            equal(checkpoint.version, committed ? 2 : 1);
            equal(
              jsonObject(checkpoint.clock['clock'], 'clock')['occurrence'],
              committed ? 1 : 0,
            );
            if (committed) {
              await expectCheckpointFailure(
                WindowCheckpointService(reopened).review(
                  'cp',
                  expectedVersion: 1,
                  expectedSessionVersion: 1,
                  expectedClockVersion: 1,
                  toOccurrence: 1,
                  action: 'skip',
                  confirm: true,
                ),
                'conflict',
              );
            }
            await reopened.archive();
          } finally {
            await reopened.close();
          }
        }
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'reserved scoped clocks enforce one timing owner and survive recovery',
    () async {
      final input = definition().toJson();
      input['id'] = 'scoped-workout';
      input['plan'] = {
        'id': 'window',
        'type': 'window',
        'durationSeconds': 5,
        'child': {'id': 'set', 'type': 'effort', 'slot': 'bench-heavy'},
      };
      final scopedWorkout = WorkoutDefinition.fromJson(input);
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-reserved-window-',
      );
      final path = '${dir.path}/db.sqlite';
      var store = await TrainingStore.open(path);
      try {
        var training = StoredTrainingService(store);
        await training.publish(scopedWorkout, 0);
        final scopedSession = await training.start(
          'scoped',
          scopedWorkout.id,
          1,
          instant(1),
        );
        final otherWorkout = definition();
        await training.publish(otherWorkout, 0);
        final other = await training.start(
          'other',
          otherWorkout.id,
          1,
          instant(1),
        );
        var timers = TimingService(store);
        final plan = TimingPlan.fromJson({
          'unplannedDuration': true,
          'effortMilliseconds': 1000,
        });
        var timer = await timers.start(
          'timer',
          other.id,
          other.sets.first.id,
          'duration',
          plan,
          instant(1),
        );
        final originalTimer = timer;
        var checkpoints = WindowCheckpointService(store);
        final initial = const SessionWindowClock().start(scopedSession);
        await checkpoints.save('cp', scopedSession.id, 0, initial);
        await checkpoints.save('other-cp', scopedSession.id, 0, initial);
        await expectCheckpointFailure(checkpoints.reserve('cp', 1), 'conflict');
        timer = await timers.stop(
          timer.id,
          timer.version,
          instant(1),
          confirm: true,
          discard: true,
        );
        var cp = await checkpoints.reserve('cp', 1);
        check(cp.reserved);
        equal(cp.version, 2);
        final duplicate = copyJson((await store.archive()).toJson());
        final duplicateRows = jsonList(duplicate, 'windowCheckpoints');
        jsonObject(duplicateRows.last, 'checkpoint')['reserved'] = true;
        rejects(() => TrainingArchive.fromJson(duplicate));
        final collision = copyJson((await store.archive()).toJson());
        jsonList(collision, 'timers')[0] = originalTimer.toJson();
        rejects(() => TrainingArchive.fromJson(collision));
        await expectCheckpointFailure(
          checkpoints.release('cp', 2, confirm: false),
        );
        await expectCheckpointFailure(
          timers.start(
            'other-timer',
            other.id,
            other.sets.first.id,
            'duration',
            plan,
            instant(1),
          ),
          'conflict',
        );
        final restId = other.revision.definition.plan
            .occurrences()
            .firstWhere((o) => o.activity is Rest)
            .id;
        await expectCheckpointFailure(
          timers.startRest('other-rest', other.id, restId, instant(1)),
          'conflict',
        );
        await expectCheckpointFailure(
          checkpoints.reserve('other-cp', 1),
          'conflict',
        );
        await expectCheckpointFailure(
          checkpoints.save('cp', scopedSession.id, 2, initial),
        );
        await expectCheckpointFailure(
          checkpoints.delete('cp', 2, confirm: true),
        );
        await expectCheckpointFailure(
          checkpoints.action(
            'other-cp',
            expectedVersion: 1,
            expectedSessionVersion: 1,
            expectedClockVersion: 1,
            action: 'resume',
            ownerId: 'epoch',
          ),
        );
        await expectCheckpointFailure(
          checkpoints.action(
            'cp',
            expectedVersion: 2,
            expectedSessionVersion: 2,
            expectedClockVersion: 1,
            action: 'resume',
            ownerId: 'epoch',
          ),
          'conflict',
        );
        await expectCheckpointFailure(
          checkpoints.action(
            'cp',
            expectedVersion: 2,
            expectedSessionVersion: 1,
            expectedClockVersion: 2,
            action: 'resume',
            ownerId: 'epoch',
          ),
          'conflict',
        );
        cp = await checkpoints.action(
          'cp',
          expectedVersion: 2,
          expectedSessionVersion: 1,
          expectedClockVersion: 1,
          action: 'resume',
          ownerId: 'epoch',
        );
        equal(cp.version, 3);
        await expectCheckpointFailure(
          checkpoints.release('cp', 3, confirm: true),
        );
        await expectCheckpointFailure(
          training.edit(
            scopedSession.id,
            1,
            (s) => const TrainingService().complete(
              s,
              s.sets.first.id,
              s.sets.first.suggested,
            ),
          ),
        );
        await store.backup('${dir.path}/native');
        await LogicalArchiveFiles.export(
          await store.archive(),
          '${dir.path}/logical.json',
        );
        final archive = jsonObject(
          jsonDecode(await File('${dir.path}/logical.json').readAsString()),
          'archive',
        );
        archive['format'] = 'bodytmi-logical-export/46';
        archive.remove('sha256');
        archive['sha256'] = sha256
            .convert(utf8.encode(canonicalJson(archive)))
            .toString();
        await File('${dir.path}/old.json').writeAsString(jsonEncode(archive));
        await expectCheckpointFailure(
          LogicalArchiveFiles.prepare('${dir.path}/old.json'),
        );
        final old = sqlite3.open('${dir.path}/native/database.sqlite');
        old.execute('DROP TABLE IF EXISTS progression_reconciliations');
        old.execute('DROP TABLE IF EXISTS lever_link_revisions');
        old.execute('DROP TABLE IF EXISTS shared_lever_applications');
        old.execute('DROP TABLE IF EXISTS link_retirement_anchors');
        old.execute('DROP TABLE IF EXISTS program_upgrade_receipts');
        old.userVersion = 46;
        old.close();
        rejects(
          () => NativeBackup.validateDatabase(
            '${dir.path}/native/database.sqlite',
          ),
        );
        final logical = await LogicalArchiveFiles.prepare(
          '${dir.path}/logical.json',
        );
        try {
          await store.restore(
            logical.backup,
            recoveryDestination: '${dir.path}/recovery',
            confirm: true,
          );
        } finally {
          await logical.close();
          await store.close();
        }
        store = await TrainingStore.open(path);
        training = StoredTrainingService(store);
        timers = TimingService(store);
        checkpoints = WindowCheckpointService(store);
        check((await checkpoints.show('cp')).reserved);
        await expectCheckpointFailure(
          timers.start(
            'after-restore',
            other.id,
            other.sets.first.id,
            'duration',
            plan,
            instant(1),
          ),
          'conflict',
        );
        cp = await checkpoints.action(
          'cp',
          expectedVersion: 3,
          expectedSessionVersion: 1,
          expectedClockVersion: 2,
          action: 'recover',
        );
        equal(jsonObject(cp.clock['clock'], 'clock')['status'], 'paused');
        cp = await checkpoints.action(
          'cp',
          expectedVersion: 4,
          expectedSessionVersion: 1,
          expectedClockVersion: 3,
          action: 'resume',
          ownerId: 'new-epoch',
        );
        cp = await checkpoints.action(
          'cp',
          expectedVersion: 5,
          expectedSessionVersion: 1,
          expectedClockVersion: 4,
          action: 'advance',
          ownerId: 'new-epoch',
          ownerElapsedMilliseconds: 6000,
        );
        equal(jsonObject(cp.clock['clock'], 'clock')['status'], 'boundary');
        equal(
          (await training.session('scoped')).sets.first.status,
          SetStatus.planned,
        );
        final reviewed = await checkpoints.review(
          'cp',
          expectedVersion: 6,
          expectedSessionVersion: 1,
          expectedClockVersion: 5,
          toOccurrence: 1,
          action: 'skip',
          confirm: true,
        );
        check(!reviewed.checkpoint.reserved);
        equal(reviewed.session.sets.first.status, SetStatus.skipped);
        timer = await timers.start(
          'after-release',
          other.id,
          other.sets.first.id,
          'duration',
          plan,
          instant(1),
        );
        equal(timer.status, 'paused');
        await timers.stop(
          timer.id,
          timer.version,
          instant(1),
          confirm: true,
          discard: true,
        );
        final second = await checkpoints.reserve('other-cp', 1);
        await expectCheckpointFailure(
          training.edit('scoped', 2, (s) => s.finish(instant(2))),
        );
        final released = await checkpoints.release(
          'other-cp',
          second.version,
          confirm: true,
        );
        check(!released.reserved);
        await checkpoints.save('third', 'scoped', 0, initial);
        await checkpoints.reserve('third', 1);
        final moved = await checkpoints.action(
          'third',
          expectedVersion: 2,
          expectedSessionVersion: 2,
          expectedClockVersion: 1,
          action: 'move',
          toOccurrence: 1,
        );
        check(!moved.reserved);
        equal(jsonObject(moved.clock['clock'], 'clock')['status'], 'complete');
        final finished = await training.edit(
          'scoped',
          2,
          (s) => s.finish(instant(2)),
        );
        equal(finished.status, SessionStatus.finalized);
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'reserved clocks cannot compete with traversal in the same session',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-reserved-traversal-',
      );
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final workout = definition();
        final training = StoredTrainingService(store);
        await training.publish(workout, 0);
        final first = await training.start('first', workout.id, 1, instant(1));
        final second = await training.start(
          'second',
          workout.id,
          1,
          instant(1),
        );
        final checkpoints = WindowCheckpointService(store);
        await checkpoints.save(
          'first-cp',
          first.id,
          0,
          const SessionWindowClock().start(first),
        );
        await checkpoints.save(
          'second-cp',
          second.id,
          0,
          const SessionWindowClock().start(second),
        );
        await ExecutionService(
          store,
        ).start('first-execution', first.id, instant(1));
        await expectCheckpointFailure(checkpoints.reserve('first-cp', 1));
        final saved = await checkpoints.reserve('second-cp', 1);
        check(saved.reserved);
        await expectCheckpointFailure(
          ExecutionService(
            store,
          ).start('second-execution', second.id, instant(1)),
        );
        final forged = copyJson((await store.archive()).toJson());
        for (final row in jsonList(forged, 'windowCheckpoints')) {
          final checkpoint = jsonObject(row, 'checkpoint');
          if (checkpoint['id'] == 'first-cp') checkpoint['reserved'] = true;
          if (checkpoint['id'] == 'second-cp') checkpoint.remove('reserved');
        }
        rejects(() => TrainingArchive.fromJson(forged));
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'reserved checkpoint review preserves ownership across process death',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-reserved-review-crash-',
      );
      final path = '${dir.path}/db.sqlite';
      final store = await TrainingStore.open(path);
      try {
        final workout = definition();
        await StoredTrainingService(store).publish(workout, 0);
        final session = await StoredTrainingService(
          store,
        ).start('session', workout.id, 1, instant(1));
        await WindowCheckpointService(
          store,
        ).save('cp', session.id, 0, const SessionWindowClock().start(session));
        await WindowCheckpointService(store).reserve('cp', 1);
        await store.close();
        final binary = await compileNative(
          'test/helpers/store_owner.dart',
          '${dir.path}/owner',
        );
        for (final mode in [
          'reserved-review-rollback',
          'reserved-review-commit',
        ]) {
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
          } finally {
            child.kill(ProcessSignal.sigkill);
            await child.exitCode;
          }
          final reopened = await TrainingStore.open(path);
          try {
            final committed = mode.endsWith('commit');
            final checkpoint = await WindowCheckpointService(
              reopened,
            ).show('cp');
            final result = await StoredTrainingService(
              reopened,
            ).session('session');
            check(checkpoint.reserved);
            equal(checkpoint.version, committed ? 3 : 2);
            equal(
              result.sets.first.status,
              committed ? SetStatus.skipped : SetStatus.planned,
            );
            equal(
              jsonObject(checkpoint.clock['clock'], 'clock')['occurrence'],
              committed ? 1 : 0,
            );
            await reopened.archive();
          } finally {
            await reopened.close();
          }
        }
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'reserved clock ownership survives process death and rollback',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-reservation-crash-',
      );
      final path = '${dir.path}/db.sqlite';
      final store = await TrainingStore.open(path);
      try {
        final workout = definition();
        await StoredTrainingService(store).publish(workout, 0);
        final session = await StoredTrainingService(
          store,
        ).start('session', workout.id, 1, instant(1));
        await WindowCheckpointService(
          store,
        ).save('cp', session.id, 0, const SessionWindowClock().start(session));
        await LogicalArchiveFiles.export(
          await store.archive(),
          '${dir.path}/old.json',
        );
        final envelope = jsonObject(
          jsonDecode(await File('${dir.path}/old.json').readAsString()),
          'archive',
        );
        envelope['format'] = 'bodytmi-logical-export/46';
        envelope.remove('sha256');
        envelope['sha256'] = sha256
            .convert(utf8.encode(canonicalJson(envelope)))
            .toString();
        await File('${dir.path}/old.json').writeAsString(jsonEncode(envelope));
        final prepared = await LogicalArchiveFiles.prepare(
          '${dir.path}/old.json',
        );
        try {
          check(!prepared.archive.windowCheckpoints.single.reserved);
        } finally {
          await prepared.close();
        }
        await store.close();
        final binary = await compileNative(
          'test/helpers/store_owner.dart',
          '${dir.path}/owner',
        );
        for (final mode in [
          'checkpoint-reserve-rollback',
          'checkpoint-reserve-commit',
        ]) {
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
          } finally {
            child.kill(ProcessSignal.sigkill);
            await child.exitCode;
          }
          final reopened = await TrainingStore.open(path);
          try {
            final committed = mode.endsWith('commit');
            final checkpoint = await WindowCheckpointService(
              reopened,
            ).show('cp');
            equal(checkpoint.reserved, committed);
            equal(checkpoint.version, committed ? 2 : 1);
            final plan = TimingPlan.fromJson({
              'unplannedDuration': true,
              'effortMilliseconds': 1000,
            });
            final attempt = TimingService(reopened).start(
              'timer-$mode',
              session.id,
              session.sets.first.id,
              'duration',
              plan,
              instant(1),
            );
            if (committed) {
              await expectCheckpointFailure(attempt, 'conflict');
            } else {
              final timer = await attempt;
              await TimingService(reopened).stop(
                timer.id,
                timer.version,
                instant(1),
                confirm: true,
                discard: true,
              );
            }
            await reopened.archive();
          } finally {
            await reopened.close();
          }
        }
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test('reserved clock action recovers after process death', () async {
    final dir = await Directory.systemTemp.createTemp(
      'bodytmi-reserved-action-crash-',
    );
    final path = '${dir.path}/db.sqlite';
    final store = await TrainingStore.open(path);
    try {
      final workout = definition();
      await StoredTrainingService(store).publish(workout, 0);
      final session = await StoredTrainingService(
        store,
      ).start('session', workout.id, 1, instant(1));
      await WindowCheckpointService(
        store,
      ).save('cp', session.id, 0, const SessionWindowClock().start(session));
      await WindowCheckpointService(store).reserve('cp', 1);
      await store.close();
      final binary = await compileNative(
        'test/helpers/store_owner.dart',
        '${dir.path}/owner',
      );
      for (final mode in [
        'checkpoint-action-rollback',
        'checkpoint-action-commit',
      ]) {
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
        } finally {
          child.kill(ProcessSignal.sigkill);
          await child.exitCode;
        }
        final reopened = await TrainingStore.open(path);
        try {
          final committed = mode.endsWith('commit');
          final checkpoints = WindowCheckpointService(reopened);
          final checkpoint = await checkpoints.show('cp');
          check(checkpoint.reserved);
          equal(checkpoint.version, committed ? 3 : 2);
          equal(
            jsonObject(checkpoint.clock['clock'], 'clock')['status'],
            committed ? 'running' : 'paused',
          );
          if (committed) {
            final recovered = await checkpoints.action(
              'cp',
              expectedVersion: 3,
              expectedSessionVersion: 1,
              expectedClockVersion: 2,
              action: 'recover',
            );
            check(recovered.reserved);
            equal(
              jsonObject(recovered.clock['clock'], 'clock')['status'],
              'paused',
            );
          }
          await reopened.archive();
        } finally {
          await reopened.close();
        }
      }
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });
  test('schema v46 checkpoints migrate without reservations', () async {
    final dir = await Directory.systemTemp.createTemp(
      'bodytmi-reservation-v46-',
    );
    final path = '${dir.path}/db.sqlite';
    var store = await TrainingStore.open(path);
    try {
      final workout = definition();
      await StoredTrainingService(store).publish(workout, 0);
      final session = await StoredTrainingService(
        store,
      ).start('session', workout.id, 1, instant(1));
      await WindowCheckpointService(
        store,
      ).save('cp', session.id, 0, const SessionWindowClock().start(session));
      await store.close();
      final raw = sqlite3.open(path);
      raw.execute('DROP TABLE repeat_checkpoints');
      raw.execute('DROP TABLE IF EXISTS progression_reconciliations');
      raw.execute('DROP TABLE IF EXISTS lever_link_revisions');
      raw.execute('DROP TABLE IF EXISTS shared_lever_applications');
      raw.execute('DROP TABLE IF EXISTS link_retirement_anchors');
      raw.execute('DROP TABLE IF EXISTS program_upgrade_receipts');
      raw.userVersion = 46;
      raw.close();
      store = await TrainingStore.open(path);
      final checkpoint = await WindowCheckpointService(store).show('cp');
      check(!checkpoint.reserved);
      equal(checkpoint.version, 1);
      equal(
        (await store.backup('${dir.path}/backup'))['databaseSchemaVersion'],
        56,
      );
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });
  test('schema v45 migrates to an empty checkpoint collection', () async {
    final dir = await Directory.systemTemp.createTemp(
      'bodytmi-checkpoint-v45-',
    );
    final path = '${dir.path}/db.sqlite';
    var store = await TrainingStore.open(path);
    try {
      final workout = definition();
      await StoredTrainingService(store).publish(workout, 0);
      await StoredTrainingService(
        store,
      ).start('session', workout.id, 1, instant(1));
      await store.close();
      final raw = sqlite3.open(path);
      raw.execute('DROP TABLE IF EXISTS repeat_checkpoints');
      raw.execute('DROP TABLE window_checkpoints');
      raw.execute('DROP TABLE IF EXISTS progression_reconciliations');
      raw.execute('DROP TABLE IF EXISTS lever_link_revisions');
      raw.execute('DROP TABLE IF EXISTS shared_lever_applications');
      raw.execute('DROP TABLE IF EXISTS link_retirement_anchors');
      raw.execute('DROP TABLE IF EXISTS program_upgrade_receipts');
      raw.userVersion = 45;
      raw.close();
      store = await TrainingStore.open(path);
      equal((await WindowCheckpointService(store).list()).length, 0);
      equal(
        (await StoredTrainingService(store).session('session')).id,
        'session',
      );
      equal(
        (await store.backup('${dir.path}/backup'))['databaseSchemaVersion'],
        56,
      );
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });
  test(
    'checkpoint CLI uses versions and explicit deletion across processes',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-checkpoint-cli-',
      );
      final path = '${dir.path}/db.sqlite';
      final store = await TrainingStore.open(path);
      try {
        final workout = definition();
        await StoredTrainingService(store).publish(workout, 0);
        final session = await StoredTrainingService(
          store,
        ).start('session', workout.id, 1, instant(1));
        final clock = const SessionWindowClock().start(session);
        await store.close();
        Future<({int code, String output, String error})> command(
          String action,
          Map<String, Object?> args,
        ) => invoke(
          action.split(' '),
          jsonEncode({'schemaVersion': 1, 'database': path, ...args}),
        );
        final saved = await command('checkpoint save', {
          'id': 'one',
          'sessionId': 'session',
          'expectedVersion': 0,
          'clock': clock,
        });
        equal(saved.code, 0);
        final shown = await command('checkpoint show', {'id': 'one'});
        equal(shown.code, 0);
        jsonEqual(
          jsonObject(jsonDecode(saved.output), 'result')['data'],
          jsonObject(jsonDecode(shown.output), 'result')['data'],
        );
        final stale = await command('checkpoint save', {
          'id': 'one',
          'sessionId': 'session',
          'expectedVersion': 0,
          'clock': clock,
        });
        equal(stale.code, 5);
        final reserved = await command('checkpoint reserve', {
          'id': 'one',
          'expectedVersion': 1,
        });
        equal(reserved.code, 0);
        final running = await command('checkpoint action', {
          'id': 'one',
          'expectedVersion': 2,
          'expectedSessionVersion': 1,
          'expectedClockVersion': 1,
          'action': 'resume',
          'ownerId': 'cli',
        });
        equal(running.code, 0);
        final recovered = await command('checkpoint action', {
          'id': 'one',
          'expectedVersion': 3,
          'expectedSessionVersion': 1,
          'expectedClockVersion': 2,
          'action': 'recover',
        });
        equal(recovered.code, 0);
        final review = await command('checkpoint review', {
          'id': 'one',
          'expectedVersion': 4,
          'expectedSessionVersion': 1,
          'expectedClockVersion': 3,
          'toOccurrence': 1,
          'action': 'skip',
          'confirm': true,
        });
        equal(review.code, 0);
        final reviewed = jsonObject(
          jsonObject(jsonDecode(review.output), 'response')['data'],
          'data',
        );
        equal(jsonObject(reviewed['checkpoint'], 'checkpoint')['version'], 5);
        final retry = await command('checkpoint review', {
          'id': 'one',
          'expectedVersion': 4,
          'expectedSessionVersion': 1,
          'expectedClockVersion': 3,
          'toOccurrence': 1,
          'action': 'skip',
          'confirm': true,
        });
        equal(retry.code, 5);
        final refused = await command('checkpoint delete', {
          'id': 'one',
          'expectedVersion': 5,
        });
        equal(refused.code, 2);
        final released = await command('checkpoint release', {
          'id': 'one',
          'expectedVersion': 5,
          'confirm': true,
        });
        equal(released.code, 0);
        final removed = await command('checkpoint delete', {
          'id': 'one',
          'expectedVersion': 6,
          'confirm': true,
        });
        equal(removed.code, 0);
        final missing = await command('checkpoint show', {'id': 'one'});
        equal(missing.code, 3);
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'group queries bound their output and allow a narrow occurrence filter',
    () {
      final plan = Repeat(
        'rounds',
        5001,
        const TimeWindow('minute', 60, Effort('set', 'lift')),
        0,
      );
      rejects(() => activityGroups(plan));
      final selected = activityGroups(plan, containing: 0);
      equal(selected.length, 3);
      check(selected.any((g) => g.windowDurationSeconds == 60));
    },
  );
  test('invalid/empty/oversized plans fail with resource errors', () {
    rejects(
      () => Activity.fromJson({
        'id': 'bad',
        'type': 'sequence',
        'children': <Object?>[],
      }),
    );
    rejects(
      () => Activity.fromJson({
        'id': 'bad',
        'type': 'repeat',
        'count': -1,
        'child': <String, Object?>{},
      }),
    );
    final input = definition().toJson();
    input['plan'] = {
      'id': 'many',
      'type': 'repeat',
      'count': 10001,
      'child': {'id': 'set', 'type': 'effort', 'slot': 'bench-heavy'},
    };
    rejects(() => WorkoutDefinition.fromJson(input));
  });
}
