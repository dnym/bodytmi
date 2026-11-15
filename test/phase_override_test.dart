import 'dart:io';

import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';

import 'fixtures.dart';
import 'support.dart';

Map<String, Object?> _phase(
  String id,
  String label,
  String day, [
  List<Map<String, Object?>>? overrides,
]) => {
  'id': id,
  'type': 'group',
  'label': label,
  'children': [
    {
      'id': day,
      'type': 'day',
      'label': 'Upper',
      'templateId': 'upper-a',
      'revision': 1,
    },
  ],
  if (overrides != null) 'overrides': overrides,
};

/// A looping block without a calendar: accumulation, deload, then taper.
final _program = {
  'id': 'phased',
  'name': 'Phased upper block',
  'plan': {
    'id': 'block',
    'type': 'group',
    'label': 'Block',
    'children': [
      _phase('accumulation', 'accumulation', 'a'),
      _phase('deload', 'deload', 'b', [
        {
          'slotId': 'bench-heavy',
          'metric': 'mass',
          'mode': 'scale',
          'factor': '0.6',
        },
      ]),
      _phase('taper', 'taper', 'c', [
        {
          'slotId': 'bench-heavy',
          'metric': 'mass',
          'mode': 'set',
          'quantity': {'value': '50', 'unit': 'kg'},
        },
      ]),
    ],
  },
};

void phaseOverrideTests() {
  test(
    'deload and taper phases override targets without seeding later prefill',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-phase-');
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final training = StoredTrainingService(store);
        await training.publish(definition(), 0);
        final programs = ProgramService(store);
        await programs.publish(ProgramDefinition.fromJson(_program), 0);
        await programs.create('run', 'phased', 1, instant(1), loop: true);

        final schedule = await programs.schedule(
          'run',
          count: 3,
          includeScopes: true,
        );
        final labels = [
          for (final day in jsonList(schedule, 'days'))
            [
              for (final scope in jsonList(jsonObject(day, 'day'), 'scopes'))
                jsonObject(scope, 'scope')['label'],
            ],
        ];
        jsonEqual(labels, [
          ['Block', 'accumulation'],
          ['Block', 'deload'],
          ['Block', 'taper'],
        ]);

        Future<TrainingSession> session(String id, int day, String heavy) =>
            () async {
              final run = await programs.run('run');
              final started = await programs.start(
                'run',
                run.contentVersion,
                id,
                instant(day),
              );
              return training.edit(id, started.contentVersion, (s) {
                for (final set in s.sets) {
                  final work =
                      set.slotId == 'bench-heavy' && set.role == 'work';
                  s = const TrainingService().complete(
                    s,
                    set.id,
                    work
                        ? {
                            'mass': Quantity(heavy, 'kg'),
                            'reps': set.suggested['reps']!,
                          }
                        : const {},
                    acceptSuggested: !work,
                  );
                }
                return s.finish(instant(day).add(const Duration(hours: 1)));
              });
            }();
        List<String> heavyTargets(TrainingSession s) => [
          for (final set in s.sets)
            if (set.slotId == 'bench-heavy' && set.role == 'work')
              set.suggested['mass']!.enteredValue,
        ];

        final accumulation = await session('s1', 1, '62.5');
        check(heavyTargets(accumulation).every((v) => v == '60'));
        final deload = await session('s2', 2, '36');
        check(heavyTargets(deload).every((v) => v == '36'));
        equal(deload.prescriptionOverrides.single.path, 'block/deload');
        final taper = await session('s3', 3, '50');
        check(heavyTargets(taper).every((v) => v == '50'));
        equal(taper.prescriptionOverrides.single.path, 'block/taper');

        // Back in accumulation, prefill skips phase-prescribed results and
        // continues from the last ordinary session.
        final run = await programs.run('run');
        final next = await programs.start(
          'run',
          run.contentVersion,
          's4',
          instant(4),
        );
        check(next.prescriptionOverrides.isEmpty);
        final heavy = [
          for (final set in next.sets)
            if (set.slotId == 'bench-heavy' && set.role == 'work') set,
        ];
        check(heavy.every((s) => s.suggested['mass']!.enteredValue == '62.5'));
        check(heavy.every((s) => s.sources['mass']!.sessionId == 's1'));
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
