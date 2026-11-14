import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'cli_test.dart';
import 'fixtures.dart';
import 'support.dart';

Map<String, Object?> _json() =>
    copyJson(jsonObject(example('amrap-placed-workout')['definition'], 'def'));

Map<String, Object?> _withPlan(Map<String, Object?> plan) => {
  ..._json(),
  'plan': plan,
};

Future<BodyTmiException> _failure(Object? Function() action) async {
  try {
    await action();
  } on BodyTmiException catch (error) {
    return error;
  }
  throw StateError('Expected a BodyTmiException.');
}

final _at = DateTime.utc(2026, 11, 14, 17);

void amrapPlacementTests() {
  test('AMRAP placements occupy one unique occurrence of the finite plan', () {
    final definition = WorkoutDefinition.fromJson(_json());
    jsonEqual(
      WorkoutDefinition.fromJson(definition.toJson()).toJson(),
      definition.toJson(),
    );
    equal(definition.amrapPlacement('finisher'), 'workout/finisher-slot');
    final kinds = [
      for (final o in definition.plan.occurrences()) occurrenceKind(o.activity),
    ];
    equal(kinds.join(','), 'effort,rest,effort,rest,effort,amrap,effort');
    equal(
      activityGroups(
        definition.plan,
      ).firstWhere((g) => g.path == 'workout').end,
      7,
    );
    final placement = {'id': 'p', 'type': 'amrap', 'amrapId': 'finisher'};
    final effort = {'id': 'e', 'type': 'effort', 'slot': 'bench-light'};
    for (final plan in [
      // Undeclared block.
      {
        'id': 'w',
        'type': 'sequence',
        'children': [
          effort,
          {...placement, 'amrapId': 'missing'},
        ],
      },
      // Placed twice.
      {
        'id': 'w',
        'type': 'sequence',
        'children': [
          effort,
          placement,
          {...placement, 'id': 'q'},
        ],
      },
      // Repeated placement would not be unique.
      {
        'id': 'w',
        'type': 'sequence',
        'children': [
          effort,
          {'id': 'r', 'type': 'repeat', 'count': 2, 'child': placement},
        ],
      },
      // Unknown fields.
      {
        'id': 'w',
        'type': 'sequence',
        'children': [
          effort,
          {...placement, 'durationSeconds': 60},
        ],
      },
    ]) {
      rejects(() => WorkoutDefinition.fromJson(_withPlan(plan)));
    }
    // A placement alone is not an effort.
    rejects(() => WorkoutDefinition.fromJson(_withPlan(placement)));
    // Unplaced blocks keep their previous meaning.
    equal(
      WorkoutDefinition.fromJson(
        copyJson(
          jsonObject(example('amrap-block-workout')['definition'], 'def'),
        ),
      ).amrapPlacement('finisher'),
      null,
    );
  });

  test(
    'traversal reaches a placed block, which must finish before advancing',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-placed-');
      var store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final training = StoredTrainingService(store);
        await training.publish(WorkoutDefinition.fromJson(_json()), 0);
        await training.start('s', 'upper-amrap-placed', 1, _at);
        final executions = ExecutionService(store);
        final repeats = RepeatCheckpointService(store);
        var e = await executions.start('x', 's', _at);
        var n = 0;
        Future<WorkoutExecution> step(
          String action, {
          bool confirm = false,
        }) async => e = await executions.step(
          'x',
          e.version,
          (await training.session('s')).contentVersion,
          'r${n++}',
          _at.add(Duration(minutes: n)),
          action: action,
          acceptSuggested: action == 'complete',
          confirm: confirm,
        );

        // Block order: not before traversal reaches the placement.
        final early = await _failure(
          () => repeats.startBlock('b', 's', 'finisher'),
        );
        check(early.message.contains('advance the traversal'), early.message);
        for (final action in [
          'complete',
          'skip',
          'complete',
          'skip',
          'complete',
        ])
          await step(action, confirm: action == 'skip');
        equal(e.cursor, 5);
        final view = await executions.view('x');
        final current = jsonObject(view['current'], 'current');
        equal(current['kind'], 'amrap');
        jsonEqual(current['block'], {
          'amrapId': 'finisher',
          'checkpointId': null,
          'status': 'not-started',
        });
        equal(view['timer'], null);
        for (final bad in [
          () => step('advance'),
          () => step('complete'),
          () => step('skip', confirm: true),
          () => executions.time('x', e.version, _at),
        ]) {
          equal((await _failure(bad)).code, 'validation');
        }
        final started = await repeats.startBlock('b', 's', 'finisher');
        check(
          jsonObject(
                jsonObject(
                  (await executions.view('x'))['current'],
                  'c',
                )['block'],
                'b',
              )['status'] !=
              'finished',
        );
        // An unfinished block still holds the cursor.
        await _failure(() => step('advance'));
        await repeats.action(
          'b',
          expectedVersion: started.version,
          expectedExecutionVersion: started.execution['version']! as int,
          action: 'stop',
          confirm: true,
        );
        await step('advance');
        equal(e.receipts.last['kind'], 'amrap');
        equal(e.receipts.last['checkpointId'], 'b');
        // The advancement source cannot disappear.
        final block = await repeats.show('b');
        final kept = await _failure(
          () => repeats.delete('b', block.version, confirm: true),
        );
        check(kept.message.contains('advanced past'), kept.message);
        await step('complete');
        check(e.complete);
        final session = await training.session('s');
        await training.edit(
          's',
          session.contentVersion,
          (s) => s.finish(_at.add(const Duration(hours: 1))),
        );

        // Portability validates the checkpoint behind the placement advance.
        final archive = (await store.archive()).toJson();
        TrainingArchive.fromJson(archive);
        Map<String, Object?> tamper(void Function(Map<String, Object?>) f) {
          final copy = jsonObject(jsonDecode(jsonEncode(archive)), 'a');
          final execution = jsonObject(jsonList(copy, 'executions')[0], 'e');
          f(jsonObject(jsonList(execution, 'receipts')[5], 'r'));
          return copy;
        }

        rejects(
          () =>
              TrainingArchive.fromJson(tamper((r) => r.remove('checkpointId'))),
        );
        rejects(
          () => TrainingArchive.fromJson(
            tamper((r) => r['checkpointId'] = 'other'),
          ),
        );
        rejects(
          () => TrainingArchive.fromJson(tamper((r) => r['kind'] = 'rest')),
        );
        await store.backup('${dir.path}/native');
        await NativeBackup.validateDatabase(
          '${dir.path}/native/database.sqlite',
        );
        await LogicalArchiveFiles.export(
          await store.archive(),
          '${dir.path}/l.json',
        );
        final logical = await LogicalArchiveFiles.prepare('${dir.path}/l.json');
        try {
          await store.restore(
            logical.backup,
            recoveryDestination: '${dir.path}/recovery',
            confirm: true,
          );
        } finally {
          await logical.close();
        }
        await store.close();
        store = await TrainingStore.open('${dir.path}/db.sqlite');
        equal(
          (await ExecutionService(store).show('x')).receipts[5]['checkpointId'],
          'b',
        );
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'CLI exposes a placed block through execution show and advance',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-placed-cli-');
      try {
        final database = '${dir.path}/db.sqlite';
        Future<({int code, String output, String error})> cmd(
          String action,
          Map<String, Object?> input,
        ) => invoke(
          action.split(' '),
          jsonEncode({'schemaVersion': 1, 'database': database, ...input}),
        );
        Map<String, Object?> data(({int code, String output, String error}) r) {
          check(r.code == 0, r.error);
          return jsonObject(jsonObject(jsonDecode(r.output), 'r')['data'], 'd');
        }

        data(
          await cmd('store publish', {
            ...example('amrap-placed-workout'),
            'database': database,
          }),
        );
        data(
          await cmd('store start', {
            'id': 's',
            'templateId': 'upper-amrap-placed',
            'revision': 1,
            'startedAt': '2026-11-14T17:00:00Z',
          }),
        );
        data(
          await cmd('execution start', {
            'id': 'x',
            'sessionId': 's',
            'at': '2026-11-14T17:00:00Z',
          }),
        );
        equal(
          (await cmd('repeat-checkpoint start-block', {
            'id': 'b',
            'sessionId': 's',
            'amrapId': 'finisher',
          })).code,
          2,
        );
        // Group-skipping the heavy block skips through to the placement.
        final shown = data(await cmd('execution show', {'id': 'x'}));
        final skipped = data(
          await cmd('execution skip-group', {
            'id': 'x',
            'expectedVersion': shown['version'],
            'expectedSessionVersion': shown['sessionContentVersion'],
            'requestId': 'g',
            'groupPath': 'workout/heavy',
            'at': '2026-11-14T17:01:00Z',
            'confirm': true,
          }),
        );
        equal(skipped['cursor'], 5);
        final atBlock = data(await cmd('execution show', {'id': 'x'}));
        equal(jsonObject(atBlock['current'], 'c')['kind'], 'amrap');
        data(
          await cmd('repeat-checkpoint start-block', {
            ...example('amrap-block-start'),
            'database': database,
            'id': 'b',
            'sessionId': 's',
          }),
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
