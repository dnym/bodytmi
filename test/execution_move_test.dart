import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'fixtures.dart';
import 'support.dart';

Future<String> _code(Future<Object?> Function() action) async {
  try {
    await action();
  } on BodyTmiException catch (error) {
    return error.code;
  }
  throw StateError('Expected a BodyTmiException.');
}

void executionMoveTests() {
  test(
    'a guided workout can do another exercise next and keep its order',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-move-');
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final training = StoredTrainingService(store);
        final execution = ExecutionService(store);
        await training.publish(
          WorkoutDefinition.fromJson(example('reorder-practice')['definition']),
          0,
        );
        await training.start('s', 'reorder-practice', 1, instant(1));
        var e = await execution.start('x', 's', instant(1));
        var n = 0;
        Future<WorkoutExecution> step(String action) async {
          final s = await training.session('s');
          return e = await execution.step(
            e.id,
            e.version,
            s.contentVersion,
            'r${n++}',
            instant(1),
            action: action,
            acceptSuggested: true,
            confirm: true,
          );
        }

        await step('complete');
        // Resting after bench set 1, the bench is taken: squats go next,
        // right after the current rest.
        final before = e.version;
        e = await execution.move(
          e.id,
          e.version,
          'm1',
          instant(1),
          groupPath: 'workout/squats',
        );
        equal(e.version, before + 1);
        // Retrying the same request is a no-op; a stale step conflicts.
        equal(
          (await execution.move(
            e.id,
            before,
            'm1',
            instant(1),
            groupPath: 'workout/squats',
          )).version,
          e.version,
        );
        final s = await training.session('s');
        equal(
          await _code(
            () => execution.step(
              e.id,
              before,
              s.contentVersion,
              'stale',
              instant(1),
              action: 'skip',
              confirm: true,
            ),
          ),
          'conflict',
        );
        final view = await execution.view(e.id);
        jsonEqual((view['remaining']! as List).take(3).toList(), [
          'workout/bench[0]/between',
          'workout/squats[0]/squat',
          'workout/squats[0]/between',
        ]);
        // Group skips are structural and refused after a reorder.
        equal(
          await _code(
            () => execution.skipGroup(
              e.id,
              e.version,
              s.contentVersion,
              'g',
              'workout',
              instant(1),
              confirm: true,
            ),
          ),
          'validation',
        );

        await step('skip'); // the bench rest
        equal(
          jsonObject((await execution.view(e.id))['current'], 'c')['id'],
          'workout/squats[0]/squat',
        );
        // An effort that has started timing cannot be reordered around.
        await execution.time(
          e.id,
          e.version,
          instant(1),
          metric: 'duration',
          plan: TimingPlan.fromJson({
            'effortMilliseconds': 30000,
            'unplannedDuration': true,
          }),
        );
        equal(
          await _code(
            () => execution.move(
              e.id,
              e.version,
              'm2',
              instant(1),
              occurrenceId: 'workout/bench[1]/press',
            ),
          ),
          'validation',
        );
        final clock = (await store.timingActivity(e.clockId('effort')))!;
        await TimingService(store).stop(
          clock.id,
          clock.version,
          instant(1),
          confirm: true,
          discard: true,
        );
        await step('skip');
        final walked = <String>[];
        while (!e.complete) {
          final current = jsonObject(
            (await execution.view(e.id))['current'],
            'current',
          );
          walked.add(current['id']! as String);
          await step(current['kind'] == 'rest' ? 'skip' : 'complete');
        }
        jsonEqual(walked, [
          'workout/squats[0]/between',
          'workout/squats[1]/squat',
          'workout/squats[1]/between',
          'workout/squats[2]/squat',
          'workout/bench[1]/press',
          'workout/bench[1]/between',
          'workout/bench[2]/press',
        ]);
        final done = await training.session('s');
        await training.edit(
          's',
          done.contentVersion,
          (s) => s.finish(instant(2)),
        );
        // Both portability formats validate the reordered traversal.
        await store.backup('${dir.path}/native');
        await LogicalArchiveFiles.export(
          await store.archive(),
          '${dir.path}/logical.json',
        );
        await LogicalArchiveFiles.prepare('${dir.path}/logical.json');
        rejects(
          () => WorkoutExecution.fromJson({
            ...e.toJson(),
            'moves': [
              {...e.moves.single, 'position': 0},
            ],
          }),
        );
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
