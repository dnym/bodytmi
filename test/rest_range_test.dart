import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'fixtures.dart';
import 'support.dart';

WorkoutDefinition _workout() =>
    WorkoutDefinition.fromJson(example('rest-range-practice')['definition']);

void restRangeTests() {
  test('rest ranges validate and round-trip', () {
    final definition = _workout();
    jsonEqual(
      WorkoutDefinition.fromJson(definition.toJson()).toJson(),
      definition.toJson(),
    );
    final between =
        definition.plan
                .occurrences()
                .firstWhere((o) => o.id.endsWith('/between'))
                .activity
            as Rest;
    equal(between.durationSeconds, 120);
    equal(between.maxDurationSeconds, 180);
    Map<String, Object?> rest(Map<String, Object?> fields) => {
      'id': 'r',
      'type': 'rest',
      ...fields,
    };
    rejects(
      () => Activity.fromJson(
        rest({'durationSeconds': 120, 'maxDurationSeconds': 120}),
      ),
    );
    rejects(
      () => Activity.fromJson(rest({'manual': true, 'maxDurationSeconds': 9})),
    );
    rejects(
      () => Activity.fromJson({
        'id': 'x',
        'type': 'repeat',
        'count': 2,
        'restBetweenMaxSeconds': 60,
        'child': {'id': 'e', 'type': 'effort', 'slot': 'rows'},
      }),
    );
    rejects(
      () => TimingPlan.fromJson({
        'effortMilliseconds': 1000,
        'restMilliseconds': 1000,
        'restMaximumMilliseconds': 2000,
      }),
    );
  });

  test('traversal records the rest actually taken', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-rest-');
    final store = await TrainingStore.open('${dir.path}/db.sqlite');
    try {
      final training = StoredTrainingService(store);
      final timing = TimingService(store);
      final execution = ExecutionService(store);
      await training.publish(_workout(), 0);
      var session = await training.start(
        's',
        'rest-range-practice',
        1,
        instant(1),
      );
      var e = await execution.start('x', 's', instant(1));
      var n = 0;
      Future<void> complete() async {
        e = await execution.step(
          e.id,
          e.version,
          session.contentVersion,
          'r${n++}',
          instant(1),
          action: 'complete',
          acceptSuggested: true,
        );
        session = await training.session('s');
      }

      Future<WorkoutExecution> advance() => execution.step(
        e.id,
        e.version,
        session.contentVersion,
        'r${n++}',
        instant(1),
      );

      await complete();
      // The range rest clock is prepared; its minimum is a ready cue, not
      // the end of the rest.
      var clock = (await store.timingActivity(e.clockId('rest')))!;
      equal(clock.plan.restMaximumMilliseconds, 180000);
      clock = await timing.resume(clock.id, clock.version, 'o1', instant(1));
      final ready = await timing.advance(
        clock.id,
        clock.version,
        'o1',
        125000,
        instant(1),
      );
      jsonEqual(ready.cues.map((c) => c['kind']).toList(), ['rest-ready']);
      equal(ready.activity.status, 'running');
      // A running clock must be paused before the user ends the rest.
      await expectRejects(advance);
      final paused = await timing.advance(
        clock.id,
        ready.activity.version,
        'o1',
        150000,
        instant(1),
        action: 'pause',
      );
      e = await advance();
      equal(e.receipts.last['restElapsedMilliseconds'], 150000);
      equal(
        (await store.timingActivity(paused.activity.id))!.status,
        'completed',
      );

      await complete();
      // A fixed rest still runs to its boundary and records it.
      clock = (await store.timingActivity(e.clockId('rest')))!;
      equal(clock.plan.restMaximumMilliseconds, null);
      clock = await timing.resume(clock.id, clock.version, 'o2', instant(1));
      await expectRejects(advance);
      final done = await timing.advance(
        clock.id,
        clock.version,
        'o2',
        60000,
        instant(1),
      );
      equal(done.activity.status, 'completed');
      e = await advance();
      equal(e.receipts.last['restElapsedMilliseconds'], 60000);
      final totals = restTotals([e])!;
      equal(totals['timed'], 2);
      equal((totals['elapsed']! as Map)['value'], '210');

      // Portability validates the recorded rest against its clock.
      await store.backup('${dir.path}/native');
      await LogicalArchiveFiles.export(
        await store.archive(),
        '${dir.path}/logical.json',
      );
      await LogicalArchiveFiles.prepare('${dir.path}/logical.json');
      rejects(
        () => WorkoutExecution.fromJson({
          ...e.toJson(),
          'receipts': [
            for (final r in e.receipts)
              {...r, if (r['kind'] == 'effort') 'restElapsedMilliseconds': 1},
          ],
        }),
      );
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });
}

Future<void> expectRejects(Future<Object?> Function() action) async {
  try {
    await action();
  } on BodyTmiException catch (error) {
    equal(error.code, 'validation');
    return;
  }
  throw StateError('Expected a validation error.');
}
