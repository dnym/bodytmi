import 'dart:io';

import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:test/test.dart' show expectLater, isA, throwsA;

import 'fixtures.dart';
import 'support.dart';

Map<String, Object?> _graph({bool missing = false}) => {
  'id': 'preview-graph',
  'nodes': [
    {'id': 'max', 'kind': 'source', 'unit': 'kg', 'sourceId': 'max_source'},
    {
      'id': 'working',
      'kind': 'scale',
      'unit': 'kg',
      'input': 'max',
      'factor': '0.8',
    },
    {
      'id': 'warmup',
      'kind': 'scale',
      'unit': 'kg',
      'input': 'max',
      'factor': '0.5',
    },
    {'id': 'seconds', 'kind': 'source', 'unit': 's', 'sourceId': 'time'},
  ],
  'bindings': {
    'max_source': missing
        ? {'kind': 'history', 'metric': 'mass', 'templateId': 'no-history'}
        : {
            'kind': 'manual',
            'version': 1,
            'value': {'value': '100', 'unit': 'kg'},
          },
    'time': {
      'kind': 'manual',
      'version': 1,
      'value': {'value': '20', 'unit': 's'},
    },
  },
};

void derivedWorkoutPreviewTests() {
  Future<void> withStore(Future<void> Function(TrainingStore) action) async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-preview-');
    final store = await TrainingStore.open('${dir.path}/db.sqlite');
    try {
      await store.insertRevision(revision());
      await action(store);
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  }

  Map<String, Object?> occurrence(Map<String, Object?> result, String id) =>
      (result['occurrences']! as List<Object?>)
          .map((v) => jsonObject(v, 'occurrence'))
          .singleWhere((v) => v['id'] == id);
  Map<String, Object?> target(
    Map<String, Object?> result,
    String id,
    String metric,
  ) => jsonObject(
    jsonObject(occurrence(result, id)['targets'], 'targets')[metric],
    'target',
  );
  Map<String, Object?> binding(String id, String metric, String node) => {
    'occurrenceId': id,
    'metric': metric,
    'nodeId': node,
  };

  test(
    'preview status detects backdated input and mapped target changes while retaining pinned revisions',
    () => withStore((store) async {
      final graphs = DerivedTargetGraphService(store);
      final graph = _graph();
      jsonObject(graph['bindings'], 'bindings')['max_source'] = {
        'kind': 'bodyMass',
        'context': 'training',
      };
      await graphs.publish(DerivedTargetGraph.fromJson(graph), 0);
      final mass = StoredBodyMassService(store);
      await mass.save({
        'id': 'first',
        'context': 'training',
        'observedAt': '2026-10-01T08:00:00Z',
        'mass': {'value': '80', 'unit': 'kg'},
      }, 0);
      final workout = revision();
      final set = start(
        from: workout,
      ).sets.firstWhere((s) => s.slotId == 'bench-heavy');
      final service = DerivedWorkoutPreview(store);
      final captured = await service.preview(
        templateId: workout.definition.id,
        revision: 1,
        graphId: 'preview-graph',
        graphRevision: 1,
        asOf: instant(10),
        bindings: [binding(set.id, 'mass', 'working')],
      );
      equal((await service.status(captured))['changed'], false);
      await mass.save({
        'id': 'second',
        'context': 'training',
        'observedAt': '2026-10-02T08:00:00Z',
        'mass': {'value': '90', 'unit': 'kg'},
      }, 0);
      await graphs.publish(DerivedTargetGraph.fromJson(graph), 1);
      final status = await service.status(captured);
      equal(status['policy'], 'bodytmi-derived-workout-preview-status/1');
      equal(status['changed'], true);
      equal(
        jsonObject(
          jsonObject(status['sources'], 'sources')['max_source'],
          'source',
        )['changed'],
        true,
      );
      final change = jsonObject(
        (status['targetChanges']! as List<Object?>).single,
        'change',
      );
      equal(change['changed'], true);
      equal(
        jsonObject(
          jsonObject(change['captured'], 'target')['value'],
          'quantity',
        )['value'],
        '64',
      );
      equal(
        jsonObject(
          jsonObject(change['current'], 'target')['value'],
          'quantity',
        )['value'],
        '72',
      );
      equal(
        jsonObject(
          jsonObject(status['currentPreview'], 'preview')['workout'],
          'workout',
        )['revision'],
        1,
      );
    }),
  );

  test(
    'preview status reports changed source membership when the mapped value remains unchanged',
    () => withStore((store) async {
      final graph = _graph();
      jsonObject(graph['bindings'], 'bindings')['max_source'] = {
        'kind': 'history',
        'metric': 'mass',
        'slotId': 'bench-heavy',
      };
      await DerivedTargetGraphService(
        store,
      ).publish(DerivedTargetGraph.fromJson(graph), 0);
      Future<void> insertSession(String id, int day, String mass) async {
        var session = start(id: id, day: day, from: revision());
        for (final set in session.sets) {
          session = const TrainingService().complete(session, set.id, {
            'mass': Quantity(mass, 'kg'),
            'reps': Quantity('8', 'rep'),
          });
        }
        session = session.finish(instant(day).add(const Duration(hours: 1)));
        await store.insertSession(session);
        await store.recordFinalization(session.id);
      }

      await insertSession('maximum', 1, '70');
      final workout = revision();
      final set = start(
        from: workout,
      ).sets.firstWhere((s) => s.slotId == 'bench-heavy');
      final service = DerivedWorkoutPreview(store);
      final preview = await service.preview(
        templateId: workout.definition.id,
        revision: 1,
        graphId: 'preview-graph',
        graphRevision: 1,
        asOf: instant(10),
        bindings: [binding(set.id, 'mass', 'working')],
      );
      await insertSession('lower', 2, '60');
      final result = await service.status(preview);
      equal(result['changed'], true);
      equal(
        jsonObject(
          jsonObject(result['sources'], 'sources')['max_source'],
          'source',
        )['changed'],
        true,
      );
      equal(
        jsonObject(
          (result['targetChanges']! as List<Object?>).single,
          'change',
        )['changed'],
        false,
      );
    }),
  );

  test(
    'preview status rejects forged authored targets, node mappings and graph arithmetic',
    () => withStore((store) async {
      await DerivedTargetGraphService(
        store,
      ).publish(DerivedTargetGraph.fromJson(_graph()), 0);
      final workout = revision();
      final set = start(
        from: workout,
      ).sets.firstWhere((s) => s.slotId == 'bench-heavy');
      final service = DerivedWorkoutPreview(store);
      final captured = await service.preview(
        templateId: workout.definition.id,
        revision: 1,
        graphId: 'preview-graph',
        graphRevision: 1,
        asOf: instant(10),
        bindings: [binding(set.id, 'mass', 'working')],
      );
      Future<void> reject(Map<String, Object?> altered) async => expectLater(
        service.status(altered),
        throwsA(isA<BodyTmiException>()),
      );
      final wrongTarget = copyJson(captured);
      jsonObject(
        target(wrongTarget, set.id, 'mass')['value'],
        'quantity',
      )['value'] = '999';
      await reject(wrongTarget);
      final wrongAuthored = copyJson(captured);
      jsonObject(
        jsonObject(
          occurrence(wrongAuthored, set.id)['authoredTargets'],
          'authored',
        )['mass'],
        'quantity',
      )['value'] = '999';
      await reject(wrongAuthored);
      final wrongGraph = copyJson(captured);
      jsonObject(
        jsonObject(wrongGraph['graphResolution'], 'graph')['resolution'],
        'resolution',
      )['policy'] = 'invalid';
      await reject(wrongGraph);
      final wrongNode = copyJson(captured);
      target(wrongNode, set.id, 'mass')['nodeId'] = 'absent';
      await reject(wrongNode);
    }),
  );

  test(
    'derived workout preview maps exact graph values onto individual efforts without changing stored data',
    () => withStore((store) async {
      final graphs = DerivedTargetGraphService(store);
      await graphs.publish(DerivedTargetGraph.fromJson(_graph()), 0);
      final workout = revision();
      final setIds = start(
        from: workout,
      ).sets.where((s) => s.slotId == 'bench-heavy').map((s) => s.id).toList();
      final before = canonicalJson(
        (await StoredTrainingService(store).exportArchive()).toJson(),
      );
      final preview = await DerivedWorkoutPreview(store).preview(
        templateId: workout.definition.id,
        revision: 1,
        graphId: 'preview-graph',
        graphRevision: 1,
        asOf: instant(10),
        bindings: [
          binding(setIds[0], 'mass', 'warmup'),
          binding(setIds[1], 'mass', 'working'),
        ],
      );
      equal(preview['policy'], 'bodytmi-derived-workout-preview/1');
      equal(
        jsonObject(
          target(preview, setIds[0], 'mass')['value'],
          'value',
        )['value'],
        '50',
      );
      equal(
        jsonObject(
          target(preview, setIds[1], 'mass')['value'],
          'value',
        )['value'],
        '80',
      );
      equal(target(preview, setIds[0], 'reps')['status'], 'authored');
      equal(
        canonicalJson(
          (await StoredTrainingService(store).exportArchive()).toJson(),
        ),
        before,
      );
    }),
  );

  test(
    'preview supports bounded targetless objectives but never invents observe suggestions',
    () => withStore((store) async {
      await DerivedTargetGraphService(
        store,
      ).publish(DerivedTargetGraph.fromJson(_graph()), 0);
      final workout = WorkoutRevision.publish(
        WorkoutDefinition.fromJson({
          'id': 'preview-objectives',
          'name': 'Objective preview',
          'slots': [
            {
              'id': 'slot',
              'exercise': 'x',
              'implementation': 'x',
              'targets': <String, Object?>{},
            },
          ],
          'plan': {
            'id': 'work',
            'type': 'sequence',
            'children': [
              {
                'id': 'bounded',
                'type': 'effort',
                'slot': 'slot',
                'objectives': {
                  'mass': {
                    'mode': 'minimum',
                    'minimum': {'value': '1', 'unit': 'kg'},
                  },
                },
              },
              {
                'id': 'observe',
                'type': 'effort',
                'slot': 'slot',
                'objectives': {
                  'mass': {'mode': 'observe', 'unit': 'kg'},
                },
              },
            ],
          },
        }),
      );
      await store.insertRevision(workout);
      Future<Map<String, Object?>> preview(String id) =>
          DerivedWorkoutPreview(store).preview(
            templateId: 'preview-objectives',
            revision: 1,
            graphId: 'preview-graph',
            graphRevision: 1,
            asOf: instant(10),
            bindings: [binding(id, 'mass', 'working')],
          );
      final result = await preview('work/bounded');
      equal(
        jsonObject(
          target(result, 'work/bounded', 'mass')['value'],
          'value',
        )['value'],
        '80',
      );
      await expectLater(
        preview('work/observe'),
        throwsA(isA<BodyTmiException>()),
      );
    }),
  );

  test(
    'derived workout preview preserves unresolved values and rejects incompatible or ambiguous mappings',
    () => withStore((store) async {
      await DerivedTargetGraphService(
        store,
      ).publish(DerivedTargetGraph.fromJson(_graph(missing: true)), 0);
      final workout = revision();
      final set = start(
        from: workout,
      ).sets.firstWhere((s) => s.slotId == 'bench-heavy');
      Future<Map<String, Object?>> preview(List<Object?> bindings) =>
          DerivedWorkoutPreview(store).preview(
            templateId: workout.definition.id,
            revision: 1,
            graphId: 'preview-graph',
            graphRevision: 1,
            asOf: instant(10),
            bindings: bindings,
          );
      final result = await preview([binding(set.id, 'mass', 'working')]);
      equal(target(result, set.id, 'mass')['status'], 'unresolved');
      equal(target(result, set.id, 'mass')['value'], null);
      check(
        jsonObject(
              occurrence(result, set.id)['authoredTargets'],
              'authored',
            )['mass'] !=
            null,
      );
      Future<void> rejectsPreview(List<Object?> mappings) async =>
          expectLater(preview(mappings), throwsA(isA<BodyTmiException>()));
      await rejectsPreview([binding(set.id, 'mass', 'seconds')]);
      await rejectsPreview([binding(set.id, 'unknown', 'working')]);
      await rejectsPreview([binding('invalid-path', 'mass', 'working')]);
      await rejectsPreview([binding(set.id, 'mass', 'absent')]);
      await rejectsPreview([
        binding(set.id, 'mass', 'working'),
        binding(set.id, 'mass', 'warmup'),
      ]);
      await rejectsPreview([]);
    }),
  );
}
