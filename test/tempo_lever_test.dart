import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'fixtures.dart';
import 'support.dart';

Map<String, Object?> _json() => copyJson(
  jsonObject(example('tempo-lever-practice')['definition'], 'definition'),
);

Map<String, Object?> _slot(Map<String, Object?> json) =>
    jsonObject(jsonList(json, 'slots').single, 'slot');

Map<String, Object?> _lever(Map<String, Object?> json) => jsonObject(
  jsonObject(_slot(json)['categories'], 'categories')['tempo'],
  'tempo',
);

List<String> _phases(Object? tempo) => [
  for (final p in jsonList(jsonObject(tempo, 'tempo'), 'phases'))
    '${jsonObject(p, 'p')['id']}:${jsonObject(p, 'p')['milliseconds']}',
];

const _ladder = {
  'metric': 'reps',
  'performance': {
    'direction': 'higher',
    'failureLimit': {'value': '5', 'unit': 'rep'},
    'advancementLimit': {'value': '8', 'unit': 'rep'},
  },
  'levels': [
    {
      'id': 'standard',
      'settings': {'tempo': 'standard'},
    },
    {
      'id': 'slow',
      'settings': {'tempo': 'slow-eccentric'},
    },
    {
      'id': 'paused',
      'settings': {'tempo': 'paused'},
    },
  ],
};

void tempoLeverTests() {
  test('tempo levers validate one authored tempo per value', () {
    final definition = WorkoutDefinition.fromJson(_json());
    jsonEqual(
      WorkoutDefinition.fromJson(definition.toJson()).toJson(),
      definition.toJson(),
    );
    final slot = definition.slot('pushup');
    equal(slot.tempoLever, 'tempo');
    jsonEqual(_phases(slot.tempoFor({})!.toJson()), [
      'eccentric:2000',
      'concentric:1000',
    ]);
    equal(slot.tempoFor({'tempo': 'paused'})!.phases.length, 3);
    final missing = _json();
    jsonObject(_lever(missing)['tempos'], 'tempos').remove('paused');
    rejects(() => WorkoutDefinition.fromJson(missing));
    final both = _json();
    jsonObject(_slot(both)['timing'], 'timing')['tempo'] = {
      'phases': [
        {'id': 'beat', 'milliseconds': 1000},
      ],
    };
    rejects(() => WorkoutDefinition.fromJson(both));
    final two = _json();
    jsonObject(_slot(two)['categories'], 'categories')['pace'] = _lever(two);
    rejects(() => WorkoutDefinition.fromJson(two));
  });

  test('progression moves tempo through the lever and timers follow it', () {
    return () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-tempo-');
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final training = StoredTrainingService(store);
        final timing = TimingService(store);
        final progression = StoredProgressionService(store);
        await training.publish(WorkoutDefinition.fromJson(_json()), 0);
        var s = await training.start('t1', 'tempo-pushups', 1, instant(1));
        final first = s.sets.first.id;
        final clock = await timing.start(
          'clock-1',
          't1',
          first,
          null,
          null,
          instant(1),
        );
        jsonEqual(_phases(clock.plan.tempo!.toJson()), [
          'eccentric:2000',
          'concentric:1000',
        ]);
        await timing.stop(
          'clock-1',
          clock.version,
          instant(1),
          confirm: true,
          discard: true,
        );
        s = await training.session('t1');
        s = await training.edit('t1', s.contentVersion, (s) {
          for (final set in s.sets)
            s = const TrainingService().complete(s, set.id, {
              'reps': Quantity.fromJson({'value': '8', 'unit': 'rep'}),
            });
          return s.finish(instant(1).add(const Duration(hours: 1)));
        });
        final summary = const TrainingAnalytics().summary(s);
        jsonEqual(
          _phases(
            jsonObject(jsonList(summary, 'sets').first, 's')['plannedTempo'],
          ),
          ['eccentric:2000', 'concentric:1000'],
        );
        final p = await progression.propose(
          't1',
          'pushup',
          _ladder,
          ruleType: 'ordinal',
        );
        equal(p.proposal.outcome, 'advance');
        equal(p.proposal.nextLevel, 'slow');
        await progression.accept('t1', 'pushup', p.version, instant(2));

        var next = await training.start('t2', 'tempo-pushups', 1, instant(3));
        jsonEqual(next.sets.first.settings, {'tempo': 'slow-eccentric'});
        final slow = await timing.start(
          'clock-2',
          't2',
          next.sets.first.id,
          null,
          null,
          instant(3),
        );
        jsonEqual(_phases(slow.plan.tempo!.toJson()), [
          'eccentric:4000',
          'concentric:1000',
        ]);
        await timing.stop(
          'clock-2',
          slow.version,
          instant(3),
          confirm: true,
          discard: true,
        );
        // A set performed at another tempo reports both and holds progression.
        next = await training.session('t2');
        next = await training.edit('t2', next.contentVersion, (s) {
          for (final set in s.sets)
            s = const TrainingService().complete(s, set.id, {
              'reps': Quantity.fromJson({'value': '8', 'unit': 'rep'}),
            });
          return const TrainingService().recordSettings(s, s.sets.first.id, {
            'tempo': 'standard',
          });
        });
        final row = jsonObject(
          jsonList(const TrainingAnalytics().summary(next), 'sets').first,
          'row',
        );
        jsonEqual(_phases(row['plannedTempo']), [
          'eccentric:4000',
          'concentric:1000',
        ]);
        jsonEqual(_phases(row['performedTempo']), [
          'eccentric:2000',
          'concentric:1000',
        ]);
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    }();
  });
}
