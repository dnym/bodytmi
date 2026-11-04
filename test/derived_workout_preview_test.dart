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
