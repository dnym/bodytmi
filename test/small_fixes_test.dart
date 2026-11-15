import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'fixtures.dart';
import 'support.dart';

void smallFixesTests() {
  test('a running clock owned elsewhere is a conflict, not invalid input', () {
    final plan = TimingPlan.fromJson({'effortMilliseconds': 10000});
    final running = TimingActivity.create(
      id: 't',
      sessionId: 's',
      setId: 'x',
      metric: 'duration',
      plan: plan,
      at: instant(1),
    ).resume('first', instant(1));
    rejects(() => running.resume('second', instant(1)), 'conflict');
    rejects(() => running.advance(10, 'second', instant(1)), 'conflict');
    rejects(() => running.advance(-1, 'first', instant(1)));
  });

  test('computed plate masses read without padding', () {
    final example = jsonObject(
      jsonDecode(File('examples/plate-plan.json').readAsStringSync()),
      'example',
    );
    final loading = LoadingSpec.fromJson(example['loading']);
    final plan = jsonEncode(
      PlatePlan.evaluate(loading, Quantity('47.5', 'kg')),
    );
    check(!RegExp(r'"value":"\d+\.\d*0"').hasMatch(plan), plan);
    check(plan.contains('"value":"47.5"'), plan);
  });

  test('session sets show their side and timed durations use the target '
      'unit; a late finish keeps the training end', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-fixes-');
    final store = await TrainingStore.open('${dir.path}/db.sqlite');
    try {
      final service = StoredTrainingService(store);
      await service.publish(
        WorkoutDefinition.fromJson(example('unilateral-row')['definition']),
        0,
      );
      final sided = await service.start('u', 'unilateral-row', 1, instant(1));
      final first = (sided.toJson()['sets'] as List).first as Map;
      equal(first['side'], sided.definition.effortSide(first['id'] as String));
      jsonEqual(sessionFromJson(sided.toJson()).toJson(), sided.toJson());
      rejects(
        () => sessionFromJson({
          ...sided.toJson(),
          'sets': [
            {...first, 'side': 'both'},
            ...(sided.toJson()['sets'] as List).skip(1),
          ],
        }),
      );

      // Measured durations are written in the set's target unit.
      final set = TrainingSet(
        id: 'x',
        slotId: 'bench-heavy',
        role: 'work',
        ordinal: 0,
        suggested: {'hold': Quantity('5', 'min')},
        settings: const {},
        actualSettings: const {},
      );
      final session = start();
      jsonEqual(
        measuredDuration(session, set, 'hold', 300000).toJson(),
        Quantity('5', 'min').toJson(),
      );
      jsonEqual(
        measuredDuration(session, set, 'hold', 300500).toJson(),
        Quantity('300.5', 's').toJson(),
      );
      jsonEqual(
        measuredDuration(session, set, 'other', 120000).toJson(),
        Quantity('120', 's').toJson(),
      );

      // Finalized the next morning; the workout ended at 19:00.
      await service.publish(definition(), 0);
      final evening = await service.start('e', definition().id, 1, instant(2));
      final closed = await service.edit(
        'e',
        evening.contentVersion,
        (s) => const TrainingService()
            .skipRemaining(s, confirm: true)
            .finish(
              instant(3),
              endedAt: instant(2).add(const Duration(hours: 1)),
            ),
      );
      jsonEqual(sessionFromJson(closed.toJson()).toJson(), closed.toJson());
      final summary = const TrainingAnalytics().summary(closed);
      equal((summary['elapsed'] as Map)['value'], '3600');
      equal(summary['endedAt'], closed.toJson()['endedAt']);
      rejects(
        () => const TrainingService()
            .skipRemaining(evening, confirm: true)
            .finish(instant(3), endedAt: instant(4)),
      );
      equal(restTotals(await store.executions(sessionId: 'e')), null);
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });
}
