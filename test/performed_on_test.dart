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

Map<String, Object?> _instance(String id, String unit, String start) => {
  'id': id,
  'equipmentId': 'assist-machine',
  'name': 'Assisted chin-up machine ($unit stack)',
  'scale': {
    'id': '$id-stack',
    'unit': unit,
    'range': {'start': start, 'step': unit == 'kg' ? '2.5' : '5', 'count': 24},
  },
};

Map<String, Object?> _workout() => {
  'id': 'chins',
  'name': 'Assisted chin-ups',
  'slots': [
    {
      'id': 'chinup',
      'exercise': 'chin-up',
      'implementation': 'assisted-machine',
      'equipment': 'assist-machine',
      'targets': {'assistance': _q('40', 'lb'), 'reps': _q('5', 'rep')},
    },
  ],
  'plan': {
    'id': 'w',
    'type': 'repeat',
    'count': 3,
    'child': {'id': 'set', 'type': 'effort', 'slot': 'chinup'},
  },
};

/// Less assistance is harder; 5 lb steps on the pound stack.
Map<String, Object?> _rule() => {
  'metric': 'reps',
  'performance': {
    'direction': 'higher',
    'failureLimit': _q('15', 'rep'),
    'advancementLimit': _q('15', 'rep'),
  },
  'aggregation': {'mode': 'total'},
  'failureAggregation': {'mode': 'total'},
  'increments': {'assistance': _q('5', 'lb')},
  'directions': {'assistance': 'decrease'},
  'minimums': {'assistance': _q('10', 'lb')},
  'scales': {
    'assistance': {
      'scale': (_instance('assist-lb', 'lb', '10')['scale']),
      'rounding': 'nearest',
    },
  },
};

Future<BodyTmiException> _failure(Future<Object?> Function() action) async {
  try {
    await action();
  } on BodyTmiException catch (error) {
    return error;
  }
  throw StateError('Expected a BodyTmiException.');
}

/// A set may record the equipment instance it was performed on; progression
/// treats that instance's nearest setting to the target as following it.
void performedOnTests() {
  test('nearest settings follow a target on scales and plate loading', () {
    final kg = EquipmentInstance.fromJson(_instance('kg', 'kg', '5'));
    final lb40 = Quantity.fromJson(_q('40', 'lb')); // 18.14 kg
    jsonEqual(
      [for (final q in nearestSettings(kg, lb40)) q.toJson()],
      [Quantity.fromJson(_q('17.5', 'kg')).toJson()],
    );
    check(followsOn(kg, lb40, Quantity.fromJson(_q('17.5', 'kg'))), '17.5');
    check(!followsOn(kg, lb40, Quantity.fromJson(_q('20', 'kg'))), '20');
    // Exactly midway keeps both neighbours.
    final midway = Quantity.fromJson(_q('18.75', 'kg'));
    equal(nearestSettings(kg, midway).length, 2);
    // Exact availability leaves no room for a neighbour.
    final exact = Quantity.fromJson(_q('20', 'kg'));
    equal(nearestSettings(kg, exact).single.compareTo(exact), 0);
    check(
      !followsOn(kg, exact, Quantity.fromJson(_q('17.5', 'kg'))),
      'an available target must be met exactly',
    );
    // Plate loading: 20 kg bar, 1.25 kg smallest plate pair.
    final bar = EquipmentInstance.fromJson({
      'id': 'bar',
      'equipmentId': 'barbell',
      'loading': {
        'components': [
          {'id': 'bar', 'kind': 'bar', 'mass': _q('20', 'kg')},
        ],
        'channel': {'id': 'barbell', 'sides': 2, 'symmetry': 'required'},
        'plates': [
          {'mass': _q('1.25', 'kg'), 'count': 4},
          {'mass': _q('10', 'kg'), 'count': 4},
        ],
      },
    });
    final onBar = nearestSettings(bar, Quantity.fromJson(_q('43', 'kg')));
    equal(onBar.single.compareTo(Quantity.fromJson(_q('42.5', 'kg'))), 0);
    // A selector scale of another dimension offers nothing.
    equal(nearestSettings(kg, Quantity.fromJson(_q('5', 'rep'))).length, 0);
  });

  test(
    'a lb target done on the kg machine progresses instead of needing review',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-performed-');
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final equipment = EquipmentService(store);
        await equipment.publishEquipment(
          EquipmentDefinition.fromJson({'id': 'assist-machine'}),
          0,
        );
        await equipment.publishEquipment(
          EquipmentDefinition.fromJson({'id': 'barbell'}),
          0,
        );
        for (final (id, unit, start) in [
          ('assist-lb', 'lb', '10'),
          ('assist-kg', 'kg', '5'),
        ]) {
          await equipment.publishInstance(
            EquipmentInstance.fromJson(_instance(id, unit, start)),
            0,
          );
        }
        await equipment.publishInstance(
          EquipmentInstance.fromJson({'id': 'rack', 'equipmentId': 'barbell'}),
          0,
        );
        final training = StoredTrainingService(store);
        final progression = StoredProgressionService(store);
        await training.publish(WorkoutDefinition.fromJson(_workout()), 0);
        final kg = await equipment.instanceRevision('assist-kg');
        final reference = LoadInstanceReference(
          kg.instance.id,
          kg.instance,
          kg.number,
        );

        Future<ProgressionDecision> session(
          String id,
          int day, {
          required bool onKg,
        }) async {
          var s = await training.start(
            id,
            'chins',
            1,
            instant(day),
            loadBindings: {'chinup': 'assist-lb'},
          );
          if (onKg) {
            s = await training.edit(
              id,
              s.contentVersion,
              (s) => const TrainingService().performOn(
                s,
                s.sets.first.id,
                reference,
                applyToRemaining: true,
              ),
            );
            check(
              s.sets.every((set) => set.performedOn?.instanceId == 'assist-kg'),
              'applies to the remaining sets',
            );
          }
          s = await training.edit(id, s.contentVersion, (s) {
            for (final set in s.sets) {
              s = const TrainingService().complete(s, set.id, {
                'assistance': Quantity.fromJson(_q('17.5', 'kg')),
                'reps': Quantity.fromJson(_q('5', 'rep')),
              });
            }
            return s.finish(instant(day).add(const Duration(hours: 1)));
          });
          final p = await progression.propose(
            id,
            'chinup',
            _rule(),
            ruleType: 'threshold',
          );
          return p;
        }

        // On the lb machine, 17.5 kg is not the 40 lb target: review.
        final strict = await session('lb', 1, onKg: false);
        equal(strict.proposal.outcome, 'review');
        equal(strict.followed.length, 0);
        await progression.decline(
          'lb',
          'chinup',
          strict.version,
          instant(1).add(const Duration(hours: 2)),
        );
        // On the kg machine, 17.5 kg is the nearest marking to 40 lb.
        final followed = await session('kg', 2, onKg: true);
        equal(followed.proposal.outcome, 'advance');
        equal(followed.followed.length, 3);
        equal(followed.followed.first.toJson()['instanceId'], 'assist-kg');
        // The track keeps progressing in its own unit.
        equal(followed.nextSets.first['assistance']!.enteredValue, '35');
        equal(followed.nextSets.first['assistance']!.enteredUnit.name, 'lb');
        await progression.accept(
          'kg',
          'chinup',
          followed.version,
          instant(2).add(const Duration(hours: 2)),
        );
        final next = await training.start(
          'next',
          'chins',
          1,
          instant(3),
          loadBindings: {'chinup': 'assist-lb'},
        );
        equal(next.sets.first.suggested['assistance']!.enteredValue, '35');

        // Other equipment, a substituted set and an unconfirmed clear are
        // refused.
        final rack = await equipment.instanceRevision('rack');
        final error = await _failure(
          () => training.edit(
            'next',
            next.contentVersion,
            (s) => const TrainingService().performOn(
              s,
              s.sets.first.id,
              LoadInstanceReference('rack', rack.instance, rack.number),
            ),
          ),
        );
        check(error.message.contains('not the slot equipment'), error.message);
        final marked = await training.edit(
          'next',
          next.contentVersion,
          (s) =>
              const TrainingService().performOn(s, s.sets.first.id, reference),
        );
        await _failure(
          () => training.edit(
            'next',
            marked.contentVersion,
            (s) => const TrainingService().performOn(s, s.sets.first.id, null),
          ),
        );

        // Archives keep and validate the frozen instance.
        final archive = await training.exportArchive();
        TrainingArchive.fromJson(archive.toJson());
        final forged = jsonDecode(jsonEncode(archive.toJson())) as Map;
        final sessions = forged['sessions'] as List;
        final kgSession =
            sessions.firstWhere((s) => (s as Map)['id'] == 'kg') as Map;
        final set = (kgSession['sets'] as List).first as Map;
        ((set['performedOn'] as Map)['snapshot'] as Map)['name'] = 'Forged';
        rejects(() => TrainingArchive.fromJson(forged.cast<String, Object?>()));
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'forgotten micro plates: the nearest load without them follows the target',
    () async {
      Map<String, Object?> bar() => {
        'id': 'main-bar',
        'equipmentId': 'barbell',
        'loading': {
          'components': [
            {'id': 'bar', 'kind': 'bar', 'mass': _q('20', 'kg')},
          ],
          'channel': {'id': 'barbell', 'sides': 2, 'symmetry': 'required'},
          'plates': [
            {'mass': _q('10', 'kg'), 'count': 4},
            {'mass': _q('2.5', 'kg'), 'count': 4},
            {'mass': _q('1.25', 'kg'), 'count': 4},
            {'mass': _q('0.5', 'kg'), 'count': 4},
          ],
        },
      };
      final loading = EquipmentInstance.fromJson(bar()).loading!;
      final micro = [PlateUsage(Quantity.fromJson(_q('0.5', 'kg')), 4)];
      // Stock checks: unknown plate, too many, nothing left.
      for (final missing in [
        [PlateUsage(Quantity.fromJson(_q('5', 'kg')), 2)],
        [PlateUsage(Quantity.fromJson(_q('0.5', 'kg')), 6)],
        [
          PlateUsage(Quantity.fromJson(_q('10', 'kg')), 4),
          PlateUsage(Quantity.fromJson(_q('2.5', 'kg')), 4),
          PlateUsage(Quantity.fromJson(_q('1.25', 'kg')), 4),
          ...micro,
        ],
      ]) {
        rejects(() => loading.without(missing));
      }
      final target = Quantity.fromJson(_q('47', 'kg'));
      final instance = EquipmentInstance.fromJson(bar());
      equal(nearestSettings(instance, target).single.compareTo(target), 0);
      final without = nearestSettings(
        instance,
        target,
        loading: loading.without(micro),
      );
      equal(without.single.compareTo(Quantity.fromJson(_q('47.5', 'kg'))), 0);

      final dir = await Directory.systemTemp.createTemp('bodytmi-micro-');
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final equipment = EquipmentService(store);
        await equipment.publishEquipment(
          EquipmentDefinition.fromJson({'id': 'barbell'}),
          0,
        );
        await equipment.publishInstance(EquipmentInstance.fromJson(bar()), 0);
        final training = StoredTrainingService(store);
        final progression = StoredProgressionService(store);
        await training.publish(
          WorkoutDefinition.fromJson({
            'id': 'bench',
            'name': 'Bench',
            'slots': [
              {
                'id': 'bench',
                'exercise': 'bench-press',
                'implementation': 'barbell',
                'equipment': 'barbell',
                'targets': {'load': _q('47', 'kg'), 'reps': _q('5', 'rep')},
              },
            ],
            'plan': {
              'id': 'w',
              'type': 'repeat',
              'count': 3,
              'child': {'id': 'set', 'type': 'effort', 'slot': 'bench'},
            },
          }),
          0,
        );
        final rule = {
          'metric': 'reps',
          'minimum': _q('5', 'rep'),
          'threshold': _q('5', 'rep'),
          'increments': {'load': _q('1', 'kg')},
        };
        final head = await equipment.instanceRevision('main-bar');
        final reference = LoadInstanceReference(
          head.instance.id,
          head.instance,
          head.number,
        );
        Future<ProgressionDecision> day(String id, int n, bool forgot) async {
          var s = await training.start(
            id,
            'bench',
            1,
            instant(n),
            loadBindings: {'bench': 'main-bar'},
          );
          if (forgot) {
            s = await training.edit(
              id,
              s.contentVersion,
              (s) => const TrainingService().performOn(
                s,
                s.sets.first.id,
                reference,
                unavailablePlates: micro,
                applyToRemaining: true,
              ),
            );
          }
          s = await training.edit(id, s.contentVersion, (s) {
            for (final set in s.sets) {
              s = const TrainingService().complete(s, set.id, {
                'load': Quantity.fromJson(_q('47.5', 'kg')),
                'reps': Quantity.fromJson(_q('5', 'rep')),
              });
            }
            return s.finish(instant(n).add(const Duration(hours: 1)));
          });
          if (forgot) {
            // A recorded stack may not use the plates that were missing.
            await _failure(
              () => training.edit(
                id,
                s.contentVersion,
                (s) => const TrainingService().arrange(
                  s,
                  s.sets.first.id,
                  LoadArrangement.fromJson({
                    'instanceId': 'main-bar',
                    'channel': 'barbell',
                    'plates': [
                      {'mass': _q('10', 'kg'), 'count': 2},
                      {'mass': _q('2.5', 'kg'), 'count': 2},
                      {'mass': _q('0.5', 'kg'), 'count': 4},
                    ],
                  }),
                ),
              ),
            );
          }
          return progression.propose(id, 'bench', rule, ruleType: 'threshold');
        }

        final strict = await day('plates-at-home', 1, false);
        equal(strict.proposal.outcome, 'review');
        await progression.decline(
          'plates-at-home',
          'bench',
          strict.version,
          instant(1).add(const Duration(hours: 2)),
        );
        final forgot = await day('forgot', 2, true);
        equal(forgot.proposal.outcome, 'advance');
        equal(forgot.followed.length, 3);
        equal(
          forgot.nextSets.first['load']!.compareTo(
            Quantity.fromJson(_q('48', 'kg')),
          ),
          0,
        );
        TrainingArchive.fromJson((await training.exportArchive()).toJson());
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test('a rule can round to the weights the bar can load', () async {
    Map<String, Object?> bar() => {
      'id': 'main-bar',
      'equipmentId': 'barbell',
      'loading': {
        'components': [
          {'id': 'bar', 'kind': 'bar', 'mass': _q('20', 'kg')},
        ],
        'channel': {'id': 'barbell', 'sides': 2, 'symmetry': 'required'},
        'plates': [
          {'mass': _q('10', 'kg'), 'count': 4},
          {'mass': _q('2.5', 'kg'), 'count': 4},
          {'mass': _q('1.25', 'kg'), 'count': 4},
          {'mass': _q('0.5', 'kg'), 'count': 4},
        ],
      },
    };
    final totals = PlatePlan.loadableTotals(
      EquipmentInstance.fromJson(bar()).loading!,
    );
    bool has(String kg) =>
        totals.any((t) => t.compareTo(Quantity.fromJson(_q(kg, 'kg'))) == 0);
    check(has('20') && has('47') && has('47.5') && has('48.5'), 'loadable');
    check(!has('48'), '48 kg needs 14 kg a side, which these plates miss');
    equal(totals.first.enteredValue, '20');
    check(
      [
        for (var i = 1; i < totals.length; i++)
          totals[i].compareTo(totals[i - 1]) > 0,
      ].every((ascending) => ascending),
      'ascending and distinct',
    );
    // Independent channels pool plates: one 0.5 kg plate makes 20.5 kg.
    final pooled = jsonObject(copyJson(bar())['loading'], 'loading');
    pooled['channel'] = {'id': 'horns', 'sides': 2, 'symmetry': 'independent'};
    check(
      PlatePlan.loadableTotals(
        LoadingSpec.fromJson(pooled),
      ).any((t) => t.compareTo(Quantity.fromJson(_q('20.5', 'kg'))) == 0),
      'pooled',
    );

    Map<String, Object?> rule({Object? binding}) => {
      'metric': 'reps',
      'minimum': _q('15', 'rep'),
      'threshold': _q('15', 'rep'),
      'aggregation': {'mode': 'total'},
      'failureAggregation': {'mode': 'total'},
      'increments': {'load': _q('1', 'kg')},
      'deloadAfter': 1,
      'deloadMetrics': ['load'],
      'deloadPercent': '10',
      'scales': {
        'load':
            binding ??
            {
              'instance': true,
              'rounding': 'nearest',
              'deloadRounding': 'atMost',
            },
      },
    };
    for (final bad in [
      {'instance': false, 'rounding': 'nearest'},
      {
        'instance': true,
        'scale': {
          'id': 's',
          'unit': 'kg',
          'ticks': [
            {'id': 't', 'value': '20'},
          ],
        },
        'rounding': 'nearest',
      },
    ]) {
      rejects(() => ThresholdRule.fromJson(rule(binding: bad)));
    }
    final unbound = ThresholdRule.fromJson(rule());
    final pure = await _failure(
      () async => unbound.evaluate(
        current: {'load': Quantity.fromJson(_q('47', 'kg'))},
        results: [
          {'reps': Quantity.fromJson(_q('15', 'rep'))},
        ],
      ),
    );
    check(pure.message.contains('rounds to the equipment instance'), '');

    final dir = await Directory.systemTemp.createTemp('bodytmi-loadable-');
    final store = await TrainingStore.open('${dir.path}/db.sqlite');
    try {
      final equipment = EquipmentService(store);
      await equipment.publishEquipment(
        EquipmentDefinition.fromJson({'id': 'barbell'}),
        0,
      );
      await equipment.publishInstance(EquipmentInstance.fromJson(bar()), 0);
      final training = StoredTrainingService(store);
      final progression = StoredProgressionService(store);
      await training.publish(
        WorkoutDefinition.fromJson({
          'id': 'bench',
          'name': 'Bench',
          'slots': [
            {
              'id': 'bench',
              'exercise': 'bench-press',
              'implementation': 'barbell',
              'equipment': 'barbell',
              'targets': {'load': _q('47', 'kg'), 'reps': _q('5', 'rep')},
            },
          ],
          'plan': {
            'id': 'w',
            'type': 'repeat',
            'count': 3,
            'child': {'id': 'set', 'type': 'effort', 'slot': 'bench'},
          },
        }),
        0,
      );
      Future<ProgressionDecision> day(
        String id,
        int n, {
        required String reps,
        bool bind = true,
      }) async {
        var s = await training.start(
          id,
          'bench',
          1,
          instant(n),
          loadBindings: bind ? {'bench': 'main-bar'} : const {},
        );
        s = await training.edit(id, s.contentVersion, (s) {
          for (final set in s.sets) {
            s = const TrainingService().complete(s, set.id, {
              'reps': Quantity.fromJson(_q(reps, 'rep')),
            }, acceptSuggested: true);
          }
          return s.finish(instant(n).add(const Duration(hours: 1)));
        });
        return progression.propose(id, 'bench', rule(), ruleType: 'threshold');
      }

      // 47 + 1 = 48 kg is not loadable; the nearest harder totals are
      // 47.5 and 48.5 kg, equally close, and the tie goes harder.
      final up = await day('up', 1, reps: '5');
      equal(up.proposal.outcome, 'advance');
      equal(up.nextSets.first['load']!.enteredValue, '48.5');
      await progression.accept(
        'up',
        'bench',
        up.version,
        instant(1).add(const Duration(hours: 2)),
      );
      // A failed exposure deloads 10 % (43.65 kg) to the loadable total at
      // most that: 43.5 kg.
      final down = await day('down', 2, reps: '3');
      equal(down.proposal.outcome, 'deload');
      equal(down.nextSets.first['load']!.enteredValue, '43.5');
      check(
        totals.any((t) => t.compareTo(down.nextSets.first['load']!) == 0),
        'loadable',
      );
      await progression.accept(
        'down',
        'bench',
        down.version,
        instant(2).add(const Duration(hours: 2)),
      );
      TrainingArchive.fromJson((await training.exportArchive()).toJson());
      // Without an instance there is nothing to round to.
      final error = await _failure(
        () => day('unbound', 3, reps: '5', bind: false),
      );
      check(error.message.contains('bind one for the slot'), error.message);
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });

  test('CLI store perform-on reports the settings to use', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-performed-cli-');
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
      equal(
        (await cli('equipment publish', {
          'equipment': {'id': 'assist-machine'},
          'expectedRevision': 0,
        })).code,
        0,
      );
      for (final (id, unit, start) in [
        ('assist-lb', 'lb', '10'),
        ('assist-kg', 'kg', '5'),
      ]) {
        equal(
          (await cli('instance publish', {
            'instance': _instance(id, unit, start),
            'expectedRevision': 0,
          })).code,
          0,
        );
      }
      equal(
        (await cli('store publish', {
          'definition': _workout(),
          'expectedRevision': 0,
        })).code,
        0,
      );
      final started = await cli('store start', {
        'id': 's',
        'templateId': 'chins',
        'revision': 1,
        'startedAt': instant(1).toIso8601String(),
        'loadBindings': {'chinup': 'assist-lb'},
      });
      final marked = await cli('store perform-on', {
        'id': 's',
        'expectedVersion': started.data!['contentVersion'],
        'setId': 'w[0]/set',
        'instanceId': 'assist-kg',
        'applyToRemaining': true,
      });
      equal(marked.code, 0);
      final settings = jsonList(marked.data!, 'settings');
      equal(settings.length, 3);
      final first = jsonObject(settings.first, 'setting');
      equal(first['metric'], 'assistance');
      jsonEqual(jsonList(first, 'settings'), [
        Quantity.fromJson(_q('17.5', 'kg')).toJson(),
      ]);
      final version = jsonObject(
        marked.data!['session'],
        'session',
      )['contentVersion'];
      equal(
        (await cli('store perform-on', {
          'id': 's',
          'expectedVersion': version,
          'setId': 'w[0]/set',
          'instanceId': 'missing',
        })).code,
        3,
      );
      equal(
        (await cli('store perform-on', {
          'id': 's',
          'expectedVersion': version,
          'setId': 'w[0]/set',
        })).code,
        2,
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
