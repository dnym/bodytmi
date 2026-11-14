import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_core/bodytmi_core.dart' show jsonObject;
import 'cli_test.dart';
import 'fixtures.dart';
import 'support.dart';

/// Specification acceptance A49 (12-window EMOM) through the CLI: window
/// bounds stay on the authored grid, partial final work is preserved, and no
/// clock transition records a result.
void emomTests() {
  test(
    'a 12-minute EMOM runs through the CLI without shifting boundaries',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-emom-');
      try {
        final db = '${dir.path}/db.sqlite';
        Future<Map<String, Object?>> cmd(
          String action,
          Map<String, Object?> input, {
          int code = 0,
        }) async {
          final result = await invoke(
            action.split(' '),
            jsonEncode({...input, 'schemaVersion': 1, 'database': db}),
          );
          equal(result.code, code);
          if (code != 0) {
            equal(result.output, '');
            return const {};
          }
          return jsonObject(
            jsonObject(jsonDecode(result.output), 'response')['data'],
            'data',
          );
        }

        Future<Map<String, Object?>> status() =>
            cmd('checkpoint status', {'id': 'emom-clock'});
        Future<Map<String, Object?>> session() =>
            cmd('store show', {'id': 'emom-session'});
        Future<Map<String, Object?>> act(
          String command,
          Map<String, Object?> input, {
          int code = 0,
        }) async {
          final checkpoint = await cmd('checkpoint show', {'id': 'emom-clock'});
          return cmd('checkpoint $command', {
            'id': 'emom-clock',
            'expectedVersion': checkpoint['version'],
            'expectedSessionVersion': (await session())['contentVersion'],
            'expectedClockVersion': jsonObject(
              jsonObject(checkpoint['clock'], 'clock')['clock'],
              'clock',
            )['version'],
            ...input,
          }, code: code);
        }

        var owner = 0;
        Future<void> run(int ms, {bool pause = false}) async {
          final id = 'owner-${owner++}';
          await act('action', {'action': 'resume', 'ownerId': id});
          await act('action', {
            'action': pause ? 'pause' : 'advance',
            'ownerId': id,
            'ownerElapsedMilliseconds': ms,
          });
        }

        Future<void> window(int minute, int start) async {
          final windows = (await status())['windows']! as List;
          final current = jsonObject(windows.single, 'window');
          equal(current['startMilliseconds'], start);
          equal(current['deadlineMilliseconds'], start + 60000);
          equal(
            jsonObject((await status())['currentOccurrence'], 'o')['id'],
            'minutes[$minute]/minute/swings',
          );
        }

        Future<String> setStatus(int minute) async =>
            jsonObject(
                  ((await session())['sets']! as List)[minute],
                  'set',
                )['status']!
                as String;

        // Early finish: record, recover in the window, reach the boundary.
        Future<void> early(int minute, int workMs) async {
          final start = minute * 60000;
          await window(minute, start);
          await run(workMs, pause: true);
          await act('complete-current', {'acceptSuggested': true});
          equal(await setStatus(minute), 'completed');
          // A long owner sample clips at the boundary; it never shifts it.
          await run(90000);
          final boundary = await status();
          equal(
            jsonObject(boundary['boundary'], 'b')['canAdvanceReviewed'],
            true,
          );
          await act('advance-boundary', {});
        }

        await cmd('store publish', example('emom-workout'));
        await cmd('store start', {
          'id': 'emom-session',
          'templateId': 'emom-12',
          'revision': 1,
          'startedAt': '2026-11-14T18:00:00+01:00',
        });
        await cmd('checkpoint start', example('emom-checkpoint-start'));
        await cmd('checkpoint reserve', {
          'id': 'emom-clock',
          'expectedVersion': 1,
        });
        equal(
          (await status())['overrunPolicy'],
          'bodytmi-window-overrun/1:stop-partial',
        );

        await early(0, 25000);

        // Minute 2 overruns: the boundary blocks advancing until the
        // unfinished effort is explicitly reviewed; the partial result is
        // kept and the next window still starts on the grid.
        await window(1, 60000);
        await run(75000);
        equal(await setStatus(1), 'planned');
        await act('advance-boundary', {}, code: 2);
        await act('review-expired', {
          'confirm': true,
          'actuals': {
            'reps': {'value': '7', 'unit': 'rep'},
            'mass': {'value': '24', 'unit': 'kg'},
          },
        });

        // Minute 3 passes idle; it needs a confirmed skip, not a result.
        await window(2, 120000);
        await run(60000);
        await act('skip-expired', {}, code: 2);
        await act('skip-expired', {'confirm': true});
        equal(await setStatus(2), 'skipped');

        for (var minute = 3; minute < 10; minute++) {
          if (minute == 5) {
            // Interruption: a running owner disappears mid-minute. Recovery
            // freezes at the last sample; no catch-up time or work appears.
            await window(5, 300000);
            await act('action', {'action': 'resume', 'ownerId': 'lost'});
            await act('action', {
              'action': 'advance',
              'ownerId': 'lost',
              'ownerElapsedMilliseconds': 12000,
            });
            check((await status())['requiresRecoveryBeforeNewOwner'] == true);
            await act('action', {'action': 'recover'});
            equal(await setStatus(5), 'planned');
            await run(10000, pause: true);
            await act('complete-current', {'acceptSuggested': true});
            await run(90000);
            await act('advance-boundary', {});
            continue;
          }
          await early(minute, 20000 + minute * 1000);
        }

        // Minute 11: the effort ends exactly at the boundary and is then
        // explicitly recorded in full before advancing.
        await window(10, 600000);
        await run(60000);
        await act('complete-current', {'acceptSuggested': true});
        await act('advance-boundary', {});

        await early(11, 30000);

        final done = await cmd('checkpoint show', {'id': 'emom-clock'});
        final clock = jsonObject(
          jsonObject(done['clock'], 'clock')['clock'],
          'clock',
        );
        equal(clock['status'], 'complete');
        equal(clock['elapsedMilliseconds'], 720000);
        check(done['reserved'] != true, 'completion releases the clock');

        final sets = [
          for (final s in (await session())['sets']! as List)
            jsonObject(s, 'set'),
        ];
        jsonEqual(
          [for (final s in sets) s['status']],
          [for (var i = 0; i < 12; i++) i == 2 ? 'skipped' : 'completed'],
        );
        equal(
          jsonObject(
            jsonObject(sets[1]['actuals'], 'actuals')['reps'],
            'reps',
          )['value'],
          '7',
        );
        final finished = await cmd('store finish', {
          'id': 'emom-session',
          'expectedVersion': (await session())['contentVersion'],
          'finishedAt': '2026-11-14T18:13:00+01:00',
        });
        equal(finished['status'], 'finalized');
        // Rounds view: 11 confirmed minutes, minute 3 skipped.
        final rounds = await cmd('store rounds', {
          'id': 'emom-session',
          'groupPath': 'minutes',
        });
        equal(rounds['confirmedRounds'], 11);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'checkpoint start is idempotent and requires an active session',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-emom-start-');
      try {
        final db = '${dir.path}/db.sqlite';
        Future<({int code, String output, String error})> cmd(
          String action,
          Map<String, Object?> input,
        ) => invoke(
          action.split(' '),
          jsonEncode({...input, 'schemaVersion': 1, 'database': db}),
        );
        equal((await cmd('store publish', example('emom-workout'))).code, 0);
        equal(
          (await cmd(
            'checkpoint start',
            example('emom-checkpoint-start'),
          )).code,
          3,
        );
        equal(
          (await cmd('store start', {
            'id': 'emom-session',
            'templateId': 'emom-12',
            'revision': 1,
            'startedAt': '2026-11-14T18:00:00+01:00',
          })).code,
          0,
        );
        final first = await cmd(
          'checkpoint start',
          example('emom-checkpoint-start'),
        );
        equal(first.code, 0);
        final retry = await cmd(
          'checkpoint start',
          example('emom-checkpoint-start'),
        );
        equal(retry.output, first.output);
        equal(
          (await cmd('checkpoint reserve', {
            'id': 'emom-clock',
            'expectedVersion': 1,
          })).code,
          0,
        );
        // Once changed, the same start conflicts instead of resetting it.
        equal(
          (await cmd(
            'checkpoint start',
            example('emom-checkpoint-start'),
          )).code,
          5,
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
