import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'fixtures.dart';
import 'support.dart';

Map<String, Object?> _rule() =>
    copyJson(jsonObject(example('retest-propose')['rule'], 'rule'));

Future<BodyTmiException> _failure(Object? Function() action) async {
  try {
    await action();
  } on BodyTmiException catch (error) {
    return error;
  }
  throw StateError('Expected a BodyTmiException.');
}

Map<String, Object?> _maxDay(String implementation) => {
  'id': 'max-day-$implementation',
  'name': 'Max test day',
  'slots': [
    {
      'id': 'squat-test',
      'exercise': 'squat',
      'implementation': implementation,
      'targets': {
        'load': {'value': '60', 'unit': 'kg'},
        'reps': {'value': '5', 'unit': 'rep'},
      },
    },
  ],
  'plan': {'id': 'test', 'type': 'effort', 'slot': 'squat-test'},
};

void retestTests() {
  test('retest policies validate and replace the exhausted deload', () {
    final rule = ThresholdRule.fromJson(_rule());
    equal(rule.retest!.restartStage, 'triples');
    equal(rule.retest!.reseed(Quantity('80', 'kg')).enteredValue, '67.5');
    final p = rule.evaluate(
      current: {'load': Quantity('60', 'kg')},
      results: [
        for (final r in [...List.filled(9, '1'), '0'])
          {'reps': Quantity(r, 'rep')},
      ],
      stage: 'singles',
    );
    equal(p.outcome, 'retest');
    equal(p.nextStage, 'retest');
    equal(p.nextValues['load']!.enteredValue, '60');
    // Earlier stages still move on failure.
    equal(
      rule
          .evaluate(
            current: {'load': Quantity('60', 'kg')},
            results: [
              for (final r in ['3', '3', '3', '3', '2'])
                {'reps': Quantity(r, 'rep')},
            ],
            stage: 'triples',
          )
          .outcome,
      'stage',
    );
    Map<String, Object?> retest(Map<String, Object?> r) =>
        jsonObject(r['retest'], 'retest');
    for (final change in <void Function(Map<String, Object?>)>[
      (r) => retest(r)['metric'] = 'reps',
      (r) => retest(r)['factor'] = '0',
      (r) => retest(r)['stage'] = 'doubles',
      (r) => retest(r)['restartStage'] = 'quads',
      (r) => retest(r)['roundTo'] = {'value': '1', 'unit': 'rep'},
    ]) {
      final bad = _rule();
      change(bad);
      rejects(() => ThresholdRule.fromJson(bad));
    }
  });

  test('a retest replaces the lift, then reseeds and restarts the track', () {
    return () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-retest-');
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final training = StoredTrainingService(store);
        final progression = StoredProgressionService(store);
        await training.publish(
          WorkoutDefinition.fromJson(
            jsonObject(example('retest-practice')['definition'], 'definition'),
          ),
          0,
        );
        var day = 0;
        Future<TrainingSession> logged(
          String id,
          List<String> reps, {
          String? load,
          String template = 'squat-t1',
        }) async {
          day += 2;
          var s = await training.start(id, template, 1, instant(day));
          return training.edit(id, s.contentVersion, (s) {
            var r = 0;
            for (final set in s.sets) {
              s = const TrainingService().complete(s, set.id, {
                'load': set.role == 'work' && load != null
                    ? Quantity(load, 'kg')
                    : set.suggested['load']!,
                'reps': Quantity(reps[r++], 'rep'),
              });
            }
            return s.finish(instant(day).add(const Duration(hours: 1)));
          });
        }

        Future<ProgressionDecision> resolve(String id) async {
          final p = await progression.propose(
            id,
            'squat',
            _rule(),
            ruleType: 'threshold',
          );
          return progression.accept(
            id,
            'squat',
            p.version,
            instant(day).add(const Duration(hours: 2)),
          );
        }

        await logged('t1', ['3', '3', '3', '3', '2']);
        equal((await resolve('t1')).proposal.outcome, 'stage');
        await logged('t2', ['2', '2', '2', '2', '2', '1']);
        equal((await resolve('t2')).proposal.outcome, 'stage');
        await logged('t3', [...List.filled(9, '1'), '0']);
        final exhausted = await resolve('t3');
        equal(exhausted.proposal.outcome, 'retest');
        jsonEqual(exhausted.nextSettings.first, {'scheme': 'retest'});
        final track = await progression.track(
          templateId: 'squat-t1',
          revision: 1,
          slotId: 'squat',
          asOf: instant(day + 1),
        );
        equal(track['retestPending'], true);

        // The next session plans the authored test in place of the lift.
        final tested = await logged('t4', ['5', '3', '5'], load: '80');
        jsonEqual(tested.variantSelections, {'scheme': 'retest'});
        jsonEqual(
          [for (final s in tested.sets) s.role],
          ['warmup', 'warmup', 'work'],
        );
        equal(
          (await _failure(
            () => progression.propose(
              't4',
              'squat',
              _rule(),
              ruleType: 'threshold',
            ),
          )).code,
          'validation',
        );
        final receipt = await progression.retest(
          id: 'squat-5rm',
          templateId: 'squat-t1',
          revision: 1,
          slotId: 'squat',
          sourceSessionId: 't4',
          sourceSetId: 'workout/retest/five-rep-max',
          expectedSequence: exhausted.sequence,
          reseededAt: instant(day + 1),
          confirm: true,
        );
        equal(receipt.retest!.reseeded.enteredValue, '67.5');
        equal(receipt.failedSessions, 0);
        jsonEqual(receipt.variantSelections, {'scheme': 'triples'});
        jsonEqual(
          ReconciliationReceipt.fromJson(receipt.toJson()).toJson(),
          receipt.toJson(),
        );
        // Retry is identical; a stale sequence conflicts.
        jsonEqual(
          (await progression.retest(
            id: 'squat-5rm',
            templateId: 'squat-t1',
            revision: 1,
            slotId: 'squat',
            sourceSessionId: 't4',
            sourceSetId: 'workout/retest/five-rep-max',
            expectedSequence: exhausted.sequence,
            reseededAt: instant(day + 1),
            confirm: true,
          )).toJson(),
          receipt.toJson(),
        );
        final restart = await training.start(
          'restart',
          'squat-t1',
          1,
          instant(day + 2),
        );
        equal(restart.sets.length, 5);
        for (final set in restart.sets) {
          equal(set.suggested['load']!.enteredValue, '67.5');
          jsonEqual(set.settings, {'scheme': 'triples'});
        }

        // A separate test day counts only when named, and only with the
        // same exercise, implementation and equipment.
        await training.publish(
          WorkoutDefinition.fromJson(_maxDay('barbell')),
          0,
        );
        await training.publish(
          WorkoutDefinition.fromJson(_maxDay('safety-bar')),
          0,
        );
        day += 2;
        await logged('max-day', ['5'], load: '90', template: 'max-day-barbell');
        await logged(
          'ssb-day',
          ['5'],
          load: '95',
          template: 'max-day-safety-bar',
        );
        await logged(
          'short-day',
          ['4'],
          load: '100',
          template: 'max-day-barbell',
        );
        Future<ReconciliationReceipt> apply(String source) =>
            progression.retest(
              id: 'from-$source',
              templateId: 'squat-t1',
              revision: 1,
              slotId: 'squat',
              sourceSessionId: source,
              sourceSetId: 'test',
              expectedSequence: receipt.sequence,
              reseededAt: instant(day + 1),
              confirm: true,
            );
        equal((await _failure(() => apply('ssb-day'))).code, 'validation');
        equal((await _failure(() => apply('short-day'))).code, 'validation');
        final fromTestDay = await apply('max-day');
        equal(fromTestDay.retest!.reseeded.enteredValue, '75');
        final again = await training.start(
          'after-test-day',
          'squat-t1',
          1,
          instant(day + 2),
        );
        equal(again.sets.first.suggested['load']!.enteredValue, '75');
        TrainingArchive.fromJson((await training.exportArchive()).toJson());
        // Forged provenance is rejected on load.
        final forged = copyJson(fromTestDay.toJson());
        jsonObject(forged['retest'], 'retest')['reseeded'] = {
          'value': '80',
          'unit': 'kg',
        };
        rejects(() => ReconciliationReceipt.fromJson(forged));
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    }();
  });
}
