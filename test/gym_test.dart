import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'cli_test.dart';
import 'fixtures.dart';
import 'support.dart';

Map<String, Object?> _q(String value, String unit) => {
  'value': value,
  'unit': unit,
};

Map<String, Object?> _slot(
  String id,
  String equipment,
  String mass, {
  bool prefill = false,
}) => {
  'id': id,
  'exercise': id,
  'implementation': equipment,
  'equipment': equipment,
  'targets': {'mass': _q(mass, 'kg'), 'reps': _q('8', 'rep')},
  if (prefill) 'prefill': ['mass'],
};

Map<String, Object?> _workout() => {
  'id': 'legs',
  'name': 'Legs',
  'slots': [
    _slot('squat', 'barbell', '100'),
    _slot('press', 'leg-press', '150'),
    _slot('pulldown', 'cable', '40', prefill: true),
  ],
  'plan': {
    'id': 'w',
    'type': 'sequence',
    'children': [
      for (final slot in ['squat', 'press', 'pulldown'])
        {'id': slot, 'type': 'effort', 'slot': slot},
    ],
  },
};

Map<String, Object?> _double() => {
  'objective': 'reps',
  'lever': 'mass',
  'lower': _q('8', 'rep'),
  'upper': _q('12', 'rep'),
  'objectiveStep': _q('1', 'rep'),
  'leverStep': _q('2.5', 'kg'),
  'deloadAfter': 3,
  'deloadPercent': '10',
};

Future<BodyTmiException> _failure(Future<Object?> Function() action) async {
  try {
    await action();
  } on BodyTmiException catch (error) {
    return error;
  }
  throw StateError('Expected a BodyTmiException.');
}

Future<void> _inventory(EquipmentService equipment) async {
  await equipment.publishEquipment(
    EquipmentDefinition.fromJson({'id': 'barbell', 'interchangeable': true}),
    0,
  );
  for (final id in ['leg-press', 'cable']) {
    await equipment.publishEquipment(
      EquipmentDefinition.fromJson({'id': id}),
      0,
    );
  }
  for (final gym in ['home', 'away']) {
    await equipment.publishGym(GymDefinition.fromJson({'id': gym}), 0);
  }
  for (final (id, kind, gym) in [
    ('home-bar', 'barbell', 'home'),
    ('home-press', 'leg-press', 'home'),
    ('home-cable', 'cable', 'home'),
    ('away-bar', 'barbell', 'away'),
    ('away-cable', 'cable', 'away'),
  ]) {
    await equipment.publishInstance(
      EquipmentInstance.fromJson({'id': id, 'equipmentId': kind, 'gym': gym}),
      0,
    );
  }
}

/// A workout started at a gym binds that gym's equipment; at another gym,
/// interchangeable equipment continues its track while other machines stay
/// neutral for progression and prefill.
void gymTests() {
  test('interchangeability is frozen and compared per instance', () {
    rejects(
      () => EquipmentDefinition.fromJson({'id': 'x', 'interchangeable': false}),
    );
    final bar = EquipmentInstance.fromJson({'id': 'a', 'equipmentId': 'bar'});
    final other = EquipmentInstance.fromJson({'id': 'b', 'equipmentId': 'bar'});
    final a = LoadInstanceReference('a', bar, 1, interchangeable: true);
    final b = LoadInstanceReference('b', other, 1, interchangeable: true);
    final c = LoadInstanceReference('b', other, 1);
    check(comparableInstances(a, b), 'interchangeable instances compare');
    check(!comparableInstances(a, c), 'one non-interchangeable side separates');
    check(comparableInstances(c, c), 'the same instance compares');
    check(comparableInstances(null, c), 'unknown instances never separate');
    jsonEqual(LoadInstanceReference.fromJson(a.toJson()).toJson(), a.toJson());
    equal(c.toJson().containsKey('interchangeable'), false);
  });

  test('a workout at another gym binds its equipment and stays neutral '
      'for machines', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-gym-');
    final store = await TrainingStore.open('${dir.path}/db.sqlite');
    try {
      final equipment = EquipmentService(store);
      final training = StoredTrainingService(store);
      final progression = StoredProgressionService(store);
      await _inventory(equipment);
      await training.publish(WorkoutDefinition.fromJson(_workout()), 0);

      final home = await training.gymCheck('legs', 1, 'home');
      equal(home.ready, true);
      jsonEqual(home.bindings, {
        'squat': 'home-bar',
        'press': 'home-press',
        'pulldown': 'home-cable',
      });
      var s = await training.start(
        's-home',
        'legs',
        1,
        instant(1),
        gym: 'home',
      );
      equal(s.gymId, 'home');
      equal(s.loadInputs['squat']!.instance!.interchangeable, true);
      equal(s.loadInputs['press']!.instance!.interchangeable, false);
      s = await training.edit('s-home', s.contentVersion, (s) {
        for (final set in s.sets) {
          s = const TrainingService().complete(s, set.id, {
            'mass': set.slotId == 'pulldown'
                ? Quantity.fromJson(_q('50', 'kg'))
                : set.suggested['mass']!,
            'reps': Quantity.fromJson(_q('12', 'rep')),
          });
        }
        return s.finish(instant(1).add(const Duration(hours: 1)));
      });
      for (final slot in ['squat', 'press']) {
        final p = await progression.propose('s-home', slot, _double());
        equal(p.proposal.outcome, 'increaseLever');
        await progression.accept(
          's-home',
          slot,
          p.version,
          instant(1).add(const Duration(hours: 2)),
        );
      }

      // The away gym has no leg press: nothing is stored.
      final missing = await training.gymCheck('legs', 1, 'away');
      equal(missing.ready, false);
      equal(
        missing.slots.firstWhere((s) => s.slotId == 'press').status,
        'missing',
      );
      final refused = await _failure(
        () => training.start('s-away', 'legs', 1, instant(2), gym: 'away'),
      );
      equal(refused.code, 'conflict');
      check(refused.message.contains('press (missing)'), refused.message);
      equal(
        (await _failure(() => training.session('s-away'))).code,
        'not_found',
      );
      equal(
        (await _failure(() => training.gymCheck('legs', 1, 'nowhere'))).code,
        'not_found',
      );
      rejects(
        () => GymBindingPlan.plan(
          definition: WorkoutDefinition.fromJson(_workout()),
          gymId: 'away',
          instances: const [],
          unbound: {'press'},
          explicit: {'press': 'x'},
        ),
      );

      // Two presses there: ambiguous until one is chosen.
      for (final id in ['away-press', 'away-press-2']) {
        await equipment.publishInstance(
          EquipmentInstance.fromJson({
            'id': id,
            'equipmentId': 'leg-press',
            'gym': 'away',
          }),
          0,
        );
      }
      final ambiguous = await training.gymCheck('legs', 1, 'away');
      final press = ambiguous.slots.firstWhere((s) => s.slotId == 'press');
      equal(press.status, 'ambiguous');
      jsonEqual(press.candidates, ['away-press', 'away-press-2']);
      s = await training.start(
        's-away',
        'legs',
        1,
        instant(2),
        gym: 'away',
        loadBindings: {'press': 'away-press'},
      );
      equal(s.gymId, 'away');
      equal(s.loadInputs['squat']!.instance!.instanceId, 'away-bar');
      equal(s.loadInputs['press']!.instance!.instanceId, 'away-press');
      // The barbell track continues; another gym's cable stack does not
      // prefill from the home stack.
      equal(s.sets[0].suggested['mass']!.enteredValue, '102.5');
      equal(s.sets[2].suggested['mass']!.enteredValue, '40');
      equal(s.sets[2].sources.isEmpty, true);
      // Retries repeat the explicit request; another gym conflicts.
      equal(
        (await training.start(
          's-away',
          'legs',
          1,
          instant(2),
          gym: 'away',
          loadBindings: {'press': 'away-press'},
        )).contentVersion,
        s.contentVersion,
      );
      equal(
        (await _failure(
          () => training.start('s-away', 'legs', 1, instant(2), gym: 'home'),
        )).code,
        'conflict',
      );

      s = await training.edit('s-away', s.contentVersion, (s) {
        for (final set in s.sets) {
          s = const TrainingService().complete(s, set.id, {
            'mass': set.suggested['mass']!,
            'reps': Quantity.fromJson(_q('9', 'rep')),
          });
        }
        return s.finish(instant(2).add(const Duration(hours: 1)));
      });
      equal(
        (await progression.propose(
          's-away',
          'squat',
          _double(),
        )).proposal.outcome,
        'increaseObjective',
      );
      final neutral = await _failure(
        () => progression.propose('s-away', 'press', _double()),
      );
      equal(neutral.code, 'validation');
      check(neutral.message.contains('countOtherInstance'), neutral.message);
      final counted = await progression.propose(
        's-away',
        'press',
        _double(),
        countOtherInstance: true,
      );
      equal(counted.toJson()['countOtherInstance'], true);

      // Back home, the next session prefills from the home stack again.
      final back = await training.start(
        's-back',
        'legs',
        1,
        instant(3),
        gym: 'home',
      );
      equal(back.sets[2].suggested['mass']!.enteredValue, '50');
      equal(back.sets[2].sources['mass']!.sessionId, 's-home');

      // Archives keep the gym and reject an unpublished one.
      final archive = await training.exportArchive();
      TrainingArchive.fromJson(archive.toJson());
      final forged = jsonDecode(jsonEncode(archive.toJson())) as Map;
      final away =
          (forged['sessions'] as List).firstWhere(
                (s) => (s as Map)['id'] == 's-away',
              )
              as Map;
      equal(away['gym'], 'away');
      away['gym'] = 'nowhere';
      rejects(() => TrainingArchive.fromJson(forged.cast<String, Object?>()));
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });

  test('CLI store gym-check and gym starts', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-gym-cli-');
    final db = '${dir.path}/db.sqlite';
    Future<({int code, Map<String, Object?>? data, String error})> cli(
      String name,
      Map<String, Object?> fields,
    ) async {
      final r = await invoke(
        name.split(' '),
        jsonEncode({'schemaVersion': 1, 'database': db, ...fields}),
      );
      return (
        code: r.code,
        error: r.error,
        data: r.code == 0
            ? jsonObject(jsonObject(jsonDecode(r.output), 'r')['data'], 'd')
            : null,
      );
    }

    try {
      final store = await TrainingStore.open(db);
      try {
        await _inventory(EquipmentService(store));
        await StoredTrainingService(
          store,
        ).publish(WorkoutDefinition.fromJson(_workout()), 0);
      } finally {
        await store.close();
      }
      final report = await cli('store gym-check', {
        'templateId': 'legs',
        'revision': 1,
        'gym': 'away',
      });
      equal(report.code, 0);
      equal(report.data!['policy'], 'bodytmi-gym-binding/1');
      equal(report.data!['ready'], false);
      final start = {
        'id': 's',
        'templateId': 'legs',
        'revision': 1,
        'startedAt': instant(1).toIso8601String(),
        'gym': 'away',
      };
      equal((await cli('store start', start)).code, 5);
      equal(
        (await cli('store start', {
          ...start,
          'unboundSlots': ['nope'],
        })).code,
        2,
      );
      equal(
        (await cli('store start', {
          ...start,
          'gym': null,
          'unboundSlots': ['press'],
        })).code,
        2,
      );
      final started = await cli('store start', {
        ...start,
        'unboundSlots': ['press'],
      });
      equal(started.code, 0);
      equal(started.data!['gym'], 'away');
      check(
        !jsonObject(started.data!['loadInputs'], 'l').containsKey('press'),
        'unbound slot has no binding',
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
