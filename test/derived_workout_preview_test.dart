import 'dart:io';
import 'dart:convert';

import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
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
    'published plan status detects source changes and rejects a different valid occurrence mapping',
    () => withStore((store) async {
      final workout = revision();
      final set = start(
        from: workout,
      ).sets.firstWhere((s) => s.slotId == 'bench-heavy');
      final spec = _graph();
      jsonObject(spec['bindings'], 'bindings')['max_source'] = {
        'kind': 'bodyMass',
        'context': 'training',
      };
      spec['plans'] = [
        {
          'id': 'bench-plan',
          'templateId': workout.definition.id,
          'revision': 1,
          'bindings': [binding(set.id, 'mass', 'working')],
        },
      ];
      final service = DerivedWorkoutPreview(store);
      final graphs = DerivedTargetGraphService(store);
      await graphs.publish(DerivedTargetGraph.fromJson(spec), 0);
      final mass = StoredBodyMassService(store);
      await mass.save({
        'id': 'm1',
        'context': 'training',
        'observedAt': '2026-10-01T08:00:00Z',
        'mass': {'value': '80', 'unit': 'kg'},
      }, 0);
      final captured = await service.previewPlan(
        graphId: 'preview-graph',
        graphRevision: 1,
        planId: 'bench-plan',
        asOf: instant(10),
      );
      final storedBefore = canonicalJson((await store.archive()).toJson());
      final unchanged = await service.planStatus(captured);
      equal(unchanged['policy'], 'bodytmi-derived-workout-plan-status/1');
      equal(unchanged['changed'], false);
      equal(canonicalJson((await store.archive()).toJson()), storedBefore);
      // This alternate preview is internally valid, but not the published plan.
      final alternate = await service.preview(
        templateId: workout.definition.id,
        revision: 1,
        graphId: 'preview-graph',
        graphRevision: 1,
        asOf: instant(10),
        bindings: [binding(set.id, 'mass', 'warmup')],
      );
      equal((await service.status(alternate))['changed'], false);
      final wrong = copyJson(captured);
      wrong['preview'] = alternate;
      await expectLater(
        service.planStatus(wrong),
        throwsA(isA<BodyTmiException>()),
      );
      final wrongPlan = copyJson(captured);
      jsonObject(wrongPlan['plan'], 'plan')['id'] = 'not-published';
      await expectLater(
        service.planStatus(wrongPlan),
        throwsA(isA<BodyTmiException>()),
      );
      await mass.save({
        'id': 'm2',
        'context': 'training',
        'observedAt': '2026-10-02T08:00:00Z',
        'mass': {'value': '90', 'unit': 'kg'},
      }, 0);
      await graphs.publish(DerivedTargetGraph.fromJson(_graph()), 1);
      final changed = await service.planStatus(captured);
      equal(changed['changed'], true);
      equal(changed['graphRevision'], 1);
      equal(
        jsonObject(
          jsonObject(changed['sources'], 'sources')['max_source'],
          'source',
        )['changed'],
        true,
      );
      final target = jsonObject(
        (changed['targetChanges']! as List<Object?>).single,
        'target',
      );
      equal(target['changed'], true);
      equal(
        jsonObject(
          jsonObject(target['captured'], 'value')['value'],
          'quantity',
        )['value'],
        '64',
      );
      equal(
        jsonObject(
          jsonObject(target['current'], 'value')['value'],
          'quantity',
        )['value'],
        '72',
      );
    }),
  );

  test(
    'published workout plans pin valid effort mappings and preview against the selected graph revision',
    () => withStore((store) async {
      final workout = revision();
      final ids = start(
        from: workout,
      ).sets.where((s) => s.slotId == 'bench-heavy').map((s) => s.id).toList();
      Map<String, Object?> plan() => {
        'id': 'bench-plan',
        'templateId': workout.definition.id,
        'revision': 1,
        'bindings': [
          binding(ids[1], 'mass', 'working'),
          binding(ids[0], 'mass', 'warmup'),
        ],
      };
      final spec = _graph();
      spec['plans'] = [plan()];
      final graph = DerivedTargetGraph.fromJson(spec);
      equal(graph.plans.single.bindings.first['occurrenceId'], ids[0]);
      final service = DerivedTargetGraphService(store);
      await service.publish(graph, 0);
      final before = canonicalJson(
        (await StoredTrainingService(store).exportArchive()).toJson(),
      );
      final result = await DerivedWorkoutPreview(store).previewPlan(
        graphId: graph.id,
        graphRevision: 1,
        planId: 'bench-plan',
        asOf: instant(10),
      );
      final preview = jsonObject(result['preview'], 'preview');
      equal(
        jsonObject(target(preview, ids[0], 'mass')['value'], 'value')['value'],
        '50',
      );
      equal(
        jsonObject(target(preview, ids[1], 'mass')['value'], 'value')['value'],
        '80',
      );
      equal(
        canonicalJson(
          (await StoredTrainingService(store).exportArchive()).toJson(),
        ),
        before,
      );
      await service.publish(DerivedTargetGraph.fromJson(_graph()), 1);
      equal(
        (await service.revision(graph.id, 1)).graph.plans.single.id,
        'bench-plan',
      );
      await expectLater(
        DerivedWorkoutPreview(store).previewPlan(
          graphId: graph.id,
          graphRevision: 2,
          planId: 'bench-plan',
          asOf: instant(10),
        ),
        throwsA(isA<BodyTmiException>()),
      );
    }),
  );

  test(
    'published workout plans reject invalid references, mismatched units and duplicate mappings',
    () => withStore((store) async {
      final workout = revision();
      final id = start(
        from: workout,
      ).sets.firstWhere((s) => s.slotId == 'bench-heavy').id;
      Map<String, Object?> plan(
        String template,
        String occurrence,
        String metric,
        String node,
      ) => {
        'id': 'bad-plan',
        'templateId': template,
        'revision': 1,
        'bindings': [binding(occurrence, metric, node)],
      };
      Future<void> reject(Map<String, Object?> plan) async {
        final spec = _graph();
        spec['plans'] = [plan];
        try {
          await DerivedTargetGraphService(
            store,
          ).publish(DerivedTargetGraph.fromJson(spec), 0);
        } on BodyTmiException {
          return;
        }
        throw StateError('Expected invalid workout plan.');
      }

      await reject(plan('missing', id, 'mass', 'working'));
      await reject(
        plan(workout.definition.id, 'missing-occurrence', 'mass', 'working'),
      );
      await reject(plan(workout.definition.id, id, 'mass', 'seconds'));
      await reject(
        plan(workout.definition.id, id, 'missing-metric', 'working'),
      );
      await reject(plan(workout.definition.id, id, 'mass', 'missing-node'));
      final duplicate = plan(workout.definition.id, id, 'mass', 'working');
      duplicate['bindings'] = [
        binding(id, 'mass', 'working'),
        binding(id, 'mass', 'warmup'),
      ];
      await reject(duplicate);
      equal((await store.derivedTargetGraphRevisions()).length, 0);
    }),
  );

  test(
    'schema v27 graphs without workout plans migrate to v30 unchanged',
    () => withStore((store) async {
      await DerivedTargetGraphService(
        store,
      ).publish(DerivedTargetGraph.fromJson(_graph()), 0);
      final before = canonicalJson((await store.archive()).toJson());
      final temp = await Directory.systemTemp.createTemp(
        'bodytmi-plan-migration-',
      );
      try {
        final path = '${temp.path}/v27.sqlite';
        await store.snapshot(path);
        final db = sqlite3.open(path);
        db.userVersion = 27;
        db.close();
        equal(NativeBackup.validateDatabase(path), 27);
        final export = '${temp.path}/v30.json';
        await LogicalArchiveFiles.export(await store.archive(), export);
        final document =
            jsonDecode(await File(export).readAsString())
                as Map<String, Object?>;
        document['format'] = 'bodytmi-logical-export/27';
        document['sha256'] = sha256
            .convert(
              utf8.encode(
                canonicalJson({
                  for (final e in document.entries)
                    if (e.key != 'sha256') e.key: e.value,
                }),
              ),
            )
            .toString();
        final legacy = '${temp.path}/v27.json';
        await File(legacy).writeAsString(jsonEncode(document));
        final prepared = await LogicalArchiveFiles.prepare(legacy);
        try {
          equal(prepared.archive.graphs.single.graph.plans.length, 0);
        } finally {
          await prepared.close();
        }
        await store.close();
        final upgraded = await TrainingStore.open(path);
        try {
          equal(canonicalJson((await upgraded.archive()).toJson()), before);
          equal(
            (await DerivedTargetGraphService(
              upgraded,
            ).revision('preview-graph')).graph.plans.length,
            0,
          );
        } finally {
          await upgraded.close();
        }
        final reopened = sqlite3.open(path);
        try {
          equal(reopened.userVersion, 44);
        } finally {
          reopened.close();
        }
      } finally {
        await temp.delete(recursive: true);
      }
    }),
  );

  test(
    'published workout plans survive portability and old schema labels reject them',
    () => withStore((store) async {
      final workout = revision();
      final id = start(
        from: workout,
      ).sets.firstWhere((s) => s.slotId == 'bench-heavy').id;
      final spec = _graph();
      spec['plans'] = [
        {
          'id': 'plan',
          'templateId': workout.definition.id,
          'revision': 1,
          'bindings': [binding(id, 'mass', 'working')],
        },
      ];
      await DerivedTargetGraphService(
        store,
      ).publish(DerivedTargetGraph.fromJson(spec), 0);
      final archive = await StoredTrainingService(store).exportArchive();
      rejects(
        () => TrainingArchive(
          revisions: [],
          sessions: [],
          finalizations: [],
          graphs: archive.graphs,
        ),
      );
      final temp = await Directory.systemTemp.createTemp(
        'bodytmi-plan-portability-',
      );
      try {
        final export = '${temp.path}/logical.json';
        await LogicalArchiveFiles.export(archive, export);
        final prepared = await LogicalArchiveFiles.prepare(export);
        try {
          equal(prepared.archive.graphs.single.graph.plans.single.id, 'plan');
        } finally {
          await prepared.close();
        }
        final document =
            jsonDecode(await File(export).readAsString())
                as Map<String, Object?>;
        document['format'] = 'bodytmi-logical-export/27';
        document['sha256'] = sha256
            .convert(
              utf8.encode(
                canonicalJson({
                  for (final e in document.entries)
                    if (e.key != 'sha256') e.key: e.value,
                }),
              ),
            )
            .toString();
        final old = '${temp.path}/old.json';
        await File(old).writeAsString(jsonEncode(document));
        await expectLater(
          LogicalArchiveFiles.prepare(old),
          throwsA(isA<BodyTmiException>()),
        );
        final copy = '${temp.path}/snapshot.sqlite';
        await store.snapshot(copy);
        equal(NativeBackup.validateDatabase(copy), 44);
        final db = sqlite3.open(copy);
        db.userVersion = 27;
        db.close();
        rejects(() => NativeBackup.validateDatabase(copy));
      } finally {
        await temp.delete(recursive: true);
      }
    }),
  );

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
