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

Map<String, Object?> _blueprint() =>
    copyJson(jsonObject(example('blueprint-ab')['blueprint'], 'b'));

Map<String, Object?> _minimal(Map<String, Object?> extra) => {
  'id': 'm',
  'name': 'M',
  'workouts': {
    'a': {
      'name': 'A',
      'slots': [
        {
          'id': 's',
          'exercise': 'e',
          'implementation': 'i',
          'targets': {
            'mass': {r'$choice': 'load'},
          },
        },
      ],
      'plan': {'id': 'w', 'type': 'effort', 'slot': 's'},
    },
  },
  'choices': [
    {'id': 'load', 'kind': 'quantity', 'dimension': 'mass'},
  ],
  ...extra,
};

Future<BodyTmiException> _failure(Future<Object?> Function() action) async {
  try {
    await action();
  } on BodyTmiException catch (error) {
    return error;
  }
  throw StateError('Expected a BodyTmiException.');
}

/// Blueprints are programmes and workouts with open choices: they cannot be
/// started, and filling them in publishes ordinary records with lineage.
void blueprintTests() {
  test('blueprint choices and placeholders are validated', () {
    Blueprint.fromJson(_minimal({}));
    rejects(
      () => Blueprint.fromJson(
        _minimal({
          'choices': [
            {'id': 'load', 'kind': 'quantity', 'dimension': 'mass'},
            {'id': 'unused', 'kind': 'equipment'},
          ],
        }),
      ),
    );
    rejects(() => Blueprint.fromJson(_minimal({'choices': <Object?>[]})));
    rejects(
      () => Blueprint.fromJson(
        _minimal({
          'choices': [
            {'id': 'load', 'kind': 'setting'},
          ],
        }),
      ),
    );
    rejects(
      () => Blueprint.fromJson(
        _minimal({
          'choices': [
            {
              'id': 'load',
              'kind': 'quantity',
              'dimension': 'mass',
              'default': _q('5', 'rep'),
            },
          ],
        }),
      ),
    );
    final withId = _minimal({});
    (jsonObject(withId['workouts'], 'w')['a'] as Map)['id'] = 'x';
    rejects(() => Blueprint.fromJson(withId));
    final unknown = _minimal({});
    final slot =
        ((jsonObject(unknown['workouts'], 'w')['a'] as Map)['slots'] as List)
                .single
            as Map;
    (slot['targets'] as Map)['reps'] = {r'$nope': 'x'};
    rejects(() => Blueprint.fromJson(unknown));

    final blueprint = Blueprint.fromJson(_blueprint());
    rejects(() => blueprint.resolveChoices({}));
    rejects(() => blueprint.resolveChoices({'mystery': 'x'}));
    rejects(
      () => blueprint.resolveChoices({
        'lower-5rm': _q('100', 'kg'),
        'row-machine': 'cable',
        'lower': 'deadlift',
      }),
    );
    rejects(
      () => blueprint.resolveChoices({
        'lower-5rm': _q('10', 'kg'),
        'row-machine': 'cable',
      }),
    );
    // 0.85 × 93 = 79.05: down 77.5, nearest 80, up 80 (step 2.5).
    String scaled(String rounding) {
      final b = Blueprint.fromJson(
        _minimal({
          'workouts': {
            'a': {
              'name': 'A',
              'slots': [
                {
                  'id': 's',
                  'exercise': 'e',
                  'implementation': 'i',
                  'targets': {
                    'mass': {
                      r'$scale': {
                        'choice': 'load',
                        'factor': '0.85',
                        'step': '2.5',
                        'rounding': rounding,
                      },
                    },
                  },
                },
              ],
              'plan': {'id': 'w', 'type': 'effort', 'slot': 's'},
            },
          },
        }),
      );
      final filled = b.fill('x', b.resolveChoices({'load': _q('93', 'kg')}), {
        'a': 1,
      });
      final slots = filled.workouts['a']!['slots']! as List;
      return (((slots.single as Map)['targets'] as Map)['mass'] as Map)['value']
          as String;
    }

    equal(Decimal.parse(scaled('down')).compareTo(Decimal.parse('77.5')), 0);
    equal(Decimal.parse(scaled('nearest')).compareTo(Decimal.parse('80')), 0);
    equal(Decimal.parse(scaled('up')).compareTo(Decimal.parse('80')), 0);
  });

  test(
    'filling a blueprint in publishes ordinary records with lineage',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-blueprint-');
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final blueprints = BlueprintService(store);
        final training = StoredTrainingService(store);
        final programs = ProgramService(store);
        final published = await blueprints.publish(
          Blueprint.fromJson(_blueprint()),
          0,
        );
        equal(published.number, 1);
        // Publishing the identical blueprint again replays the head.
        equal(
          (await blueprints.publish(
            Blueprint.fromJson(_blueprint()),
            1,
          )).number,
          1,
        );
        // A blueprint is never a startable workout.
        equal(
          (await _failure(
            () => training.start('s', 'example-ab', 1, instant(1)),
          )).code,
          'not_found',
        );

        final choices = {
          'lower-5rm': _q('100', 'kg'),
          'row-machine': 'cable-row',
        };
        final preview = await blueprints.preview(
          'example-ab',
          1,
          'mine',
          choices,
        );
        final a = jsonObject(jsonObject(preview['workouts'], 'w')['a'], 'a');
        equal(a['id'], 'mine-a');
        equal(await store.revision('mine-a'), null);

        equal(
          (await _failure(
            () => blueprints.instantiate('example-ab', 1, 'mine', {
              'row-machine': 'cable-row',
            }, expectedInstance: 0),
          )).code,
          'validation',
        );
        final receipt = await blueprints.instantiate(
          'example-ab',
          1,
          'mine',
          choices,
          expectedInstance: 0,
        );
        equal(receipt.number, 1);
        jsonEqual(receipt.workouts, {'a': 1, 'b': 1});
        equal(receipt.programRevision, 1);
        jsonEqual(receipt.presets, {'lower': 1});
        equal(receipt.choices['lower'], 'back-squat');
        final dayA = await training.revision('mine-a', 1);
        equal(dayA.definition.slots.single.exerciseId, 'back-squat');
        equal(dayA.definition.slots.single.targets['mass']!.enteredValue, '85');
        equal(
          (await training.revision(
            'mine-b',
            1,
          )).definition.slots.single.equipmentId,
          'cable-row',
        );
        final preset = await PresetService(store).revision('mine-lower');
        equal(
          jsonObject(preset.preset.rule['leverStep'], 'step')['value'],
          '2.5',
        );
        // The programme runs like any other.
        final run = await programs.create(
          'r',
          'mine',
          1,
          instant(1),
          loop: true,
        );
        final s = await programs.start(
          'r',
          run.contentVersion,
          'r1',
          instant(2),
        );
        equal(s.definition.id, 'mine-a');
        // A lost response retried returns the same receipt.
        equal(
          (await blueprints.instantiate(
            'example-ab',
            1,
            'mine',
            choices,
            expectedInstance: 0,
          )).number,
          1,
        );
        // Another name whose identities are taken conflicts, writing nothing.
        await training.publish(
          WorkoutDefinition.fromJson({
            ...dayA.definition.toJson(),
            'id': 'taken-a',
          }),
          0,
        );
        equal(
          (await _failure(
            () => blueprints.instantiate(
              'example-ab',
              1,
              'taken',
              choices,
              expectedInstance: 0,
            ),
          )).code,
          'conflict',
        );
        equal(await store.revision('taken-b'), null);
        equal(await blueprints.instance('taken'), null);

        // Filling in again publishes the next revision of each record.
        final again = await blueprints.instantiate('example-ab', 1, 'mine', {
          ...choices,
          'lower-5rm': _q('110', 'kg'),
        }, expectedInstance: 1);
        equal(again.number, 2);
        jsonEqual(again.workouts, {'a': 2, 'b': 2});
        equal(
          (await training.revision(
            'mine-a',
            2,
          )).definition.slots.single.targets['mass']!.enteredValue,
          '92.5',
        );
        final program = await programs.revision('mine', 2);
        final day = program.definition.plan.nodes.whereType<ProgramDay>().first;
        equal(day.revision, 2);
        // Running runs keep their pin until explicitly upgraded.
        equal((await programs.run('r')).program.number, 1);
        // A record edited since the last fill-in is not overwritten.
        await training.publish(
          WorkoutDefinition.fromJson({
            ...(await training.revision('mine-b', 2)).definition.toJson(),
            'name': 'My edit',
          }),
          2,
        );
        equal(
          (await _failure(
            () => blueprints.instantiate(
              'example-ab',
              1,
              'mine',
              choices,
              expectedInstance: 2,
            ),
          )).code,
          'conflict',
        );
        equal(
          (await _failure(
            () => blueprints.instantiate(
              'example-ab',
              1,
              'mine',
              choices,
              expectedInstance: 0,
            ),
          )).code,
          'conflict',
        );

        // Family-limited choices check membership.
        final family = Blueprint.fromJson({
          ...(_minimal({})),
          'id': 'fam',
          'choices': [
            {'id': 'load', 'kind': 'quantity', 'dimension': 'mass'},
            {'id': 'lift', 'kind': 'exercise', 'family': 'squats'},
          ],
          'workouts': {
            'a': {
              'name': 'A',
              'slots': [
                {
                  'id': 's',
                  'exercise': {r'$choice': 'lift'},
                  'implementation': 'i',
                  'targets': {
                    'mass': {r'$choice': 'load'},
                  },
                },
              ],
              'plan': {'id': 'w', 'type': 'effort', 'slot': 's'},
            },
          },
        });
        await blueprints.publish(family, 0);
        final famChoices = {'load': _q('50', 'kg'), 'lift': 'back-squat'};
        equal(
          (await _failure(
            () => blueprints.preview('fam', 1, 'f', famChoices),
          )).code,
          'not_found',
        );
        await FamilyService(store).publish(
          ExerciseFamily.fromJson({
            'id': 'squats',
            'name': 'Squats',
            'exercises': ['back-squat'],
          }),
          0,
        );
        await blueprints.preview('fam', 1, 'f', famChoices);
        equal(
          (await _failure(
            () => blueprints.preview('fam', 1, 'f', {
              ...famChoices,
              'lift': 'curl',
            }),
          )).code,
          'validation',
        );

        // Archives keep blueprints and lineage, and reject broken lineage.
        final archive = await training.exportArchive();
        TrainingArchive.fromJson(archive.toJson());
        equal(archive.blueprintInstances.length, 2);
        final forged = jsonDecode(jsonEncode(archive.toJson())) as Map;
        final first = (forged['blueprintInstances'] as List).first as Map;
        (first['workouts'] as Map)['a'] = 9;
        rejects(() => TrainingArchive.fromJson(forged.cast<String, Object?>()));
        final orphan = jsonDecode(jsonEncode(archive.toJson())) as Map;
        (orphan['blueprints'] as List).clear();
        rejects(() => TrainingArchive.fromJson(orphan.cast<String, Object?>()));
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'equipment blueprints publish instances with their open specifics',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-eq-blueprint-',
      );
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final blueprints = BlueprintService(store);
        final equipment = EquipmentService(store);
        for (final id in ['barbell', 'leg-press']) {
          await equipment.publishEquipment(
            EquipmentDefinition.fromJson({'id': id}),
            0,
          );
        }
        await equipment.publishGym(GymDefinition.fromJson({'id': 'home'}), 0);
        for (final name in [
          'blueprint-olympic-bar',
          'blueprint-selectorized',
        ]) {
          await blueprints.publish(
            Blueprint.fromJson(example(name)['blueprint']),
            0,
          );
        }
        final plates = [
          {'mass': _q('20', 'kg'), 'count': 4},
          {'mass': _q('10', 'kg'), 'count': 2},
          {'mass': _q('2.5', 'kg'), 'count': 2},
        ];
        equal(
          (await _failure(
            () => blueprints.instantiate('olympic-barbell', 1, 'rack', {
              'gym': 'home',
              'plates': <Object?>[],
            }, expectedInstance: 0),
          )).code,
          'validation',
        );
        final bar = await blueprints.instantiate('olympic-barbell', 1, 'rack', {
          'gym': 'home',
          'plates': plates,
        }, expectedInstance: 0);
        jsonEqual(bar.instances, {'bar': 1});
        equal(bar.workouts.isEmpty, true);
        final plan = await equipment.platePlan(
          'rack-bar',
          Quantity.fromJson(_q('65', 'kg')),
        );
        equal(jsonObject(plan['plan'], 'plan')['status'], 'exact');

        final machine = {
          'machine': 'leg-press',
          'gym': 'home',
          'first': _q('10', 'lb'),
          'step': '10',
          'pins': 20,
        };
        for (final bad in [
          {...machine, 'pins': 0},
          {...machine, 'pins': '20'},
          {...machine, 'step': '0.25'},
          {...machine, 'step': 10},
        ]) {
          equal(
            (await _failure(
              () => blueprints.preview('selectorized-machine', 1, 'press', bad),
            )).code,
            'validation',
          );
        }
        await blueprints.instantiate(
          'selectorized-machine',
          1,
          'press',
          machine,
          expectedInstance: 0,
        );
        final stack = await equipment.instanceRevision('press-stack');
        equal(stack.instance.equipmentId, 'leg-press');
        equal(stack.instance.gymId, 'home');
        equal(stack.instance.scale!.ticks.length, 20);
        equal(stack.instance.scale!.ticks.last.quantity.enteredValue, '200');
        // Filling in again with another plate stock publishes revision 2.
        final again = await blueprints.instantiate(
          'olympic-barbell',
          1,
          'rack',
          {
            'gym': 'home',
            'plates': [
              ...plates,
              {'mass': _q('1.25', 'kg'), 'count': 2},
            ],
          },
          expectedInstance: 1,
        );
        jsonEqual(again.instances, {'bar': 2});
        // The instance is ordinary inventory: a gym binds it.
        final archive = await StoredTrainingService(store).exportArchive();
        TrainingArchive.fromJson(archive.toJson());
        final forged = jsonDecode(jsonEncode(archive.toJson())) as Map;
        final receipt = (forged['blueprintInstances'] as List).first as Map;
        (receipt['instances'] as Map)['bar'] = 7;
        rejects(() => TrainingArchive.fromJson(forged.cast<String, Object?>()));
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test('CLI blueprint commands and portability', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-blueprint-cli-');
    final db = '${dir.path}/db.sqlite';
    Future<({int code, Object? data})> cli(
      String name,
      Map<String, Object?> fields,
    ) async {
      final r = await invoke(
        name.split(' '),
        jsonEncode({'schemaVersion': 1, 'database': db, ...fields}),
      );
      return (
        code: r.code,
        data: r.code == 0
            ? jsonObject(jsonDecode(r.output), 'r')['data']
            : null,
      );
    }

    try {
      final pure = await invoke([
        'blueprint',
        'validate',
      ], jsonEncode({'schemaVersion': 1, 'blueprint': _blueprint()}));
      equal(pure.code, 0);
      equal(
        (await cli('blueprint publish', {
          'blueprint': _blueprint(),
          'expectedRevision': 0,
        })).code,
        0,
      );
      equal(
        (await cli('blueprint publish', {
          'blueprint': _blueprint(),
          'expectedRevision': 0,
        })).code,
        5,
      );
      equal((await cli('blueprint show', {'blueprintId': 'nope'})).code, 3);
      final listed = await cli('blueprint list', {});
      equal((listed.data! as List).length, 1);
      final fill = {
        'blueprintId': 'example-ab',
        'revision': 1,
        'name': 'mine',
        'choices': {'lower-5rm': _q('100', 'kg'), 'row-machine': 'cable-row'},
      };
      equal((await cli('blueprint preview', fill)).code, 0);
      equal(
        (await cli('blueprint instantiate', {...fill, 'choices': {}})).code,
        2,
      );
      final made = await cli('blueprint instantiate', {
        ...fill,
        'expectedInstance': 0,
      });
      equal(made.code, 0);
      equal(jsonObject(made.data, 'd')['programRevision'], 1);
      final instances = await cli('blueprint instances', {'name': 'mine'});
      equal((instances.data! as List).length, 1);
      equal(
        (await cli('archive export', {
          'destination': '${dir.path}/archive.json',
        })).code,
        0,
      );
      final validated = await invoke(
        ['archive', 'validate'],
        jsonEncode({'schemaVersion': 1, 'source': '${dir.path}/archive.json'}),
      );
      equal(validated.code, 0);
      equal(
        (await cli('backup create', {
          'destination': '${dir.path}/backup',
        })).code,
        0,
      );
      final backup = await invoke([
        'backup',
        'validate',
      ], jsonEncode({'schemaVersion': 1, 'source': '${dir.path}/backup'}));
      equal(backup.code, 0);
      final restored = '${dir.path}/restored.sqlite';
      final restore = await invoke(
        ['archive', 'restore'],
        jsonEncode({
          'schemaVersion': 1,
          'database': restored,
          'source': '${dir.path}/archive.json',
          'recoveryDestination': '${dir.path}/recovery',
          'confirm': true,
        }),
      );
      equal(restore.code, 0);
      final again = await invoke([
        'blueprint',
        'instances',
      ], jsonEncode({'schemaVersion': 1, 'database': restored}));
      equal(
        (jsonObject(jsonDecode(again.output), 'r')['data']! as List).length,
        1,
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
