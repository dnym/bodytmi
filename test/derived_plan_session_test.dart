import 'dart:convert';
import 'dart:io';

import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart' show expectLater, isA, throwsA;

import 'fixtures.dart';
import 'cli_test.dart' show invoke;
import 'support.dart';

Future<TrainingSession> _refreshPlan(
  TrainingStore store,
  String id,
  int version, {
  required bool confirm,
}) async {
  final status = await DerivedWorkoutPreview(store).sessionStatus(id);
  final comparison = status['comparison'];
  final preview = comparison == null
      ? <String, Object?>{}
      : jsonObject(comparison, 'comparison')['currentPreview'];
  return StoredTrainingService(
    store,
  ).refreshPlan(id, version, expectedPreview: preview, confirm: confirm);
}

void sameJson(Object? a, Object? b) =>
    equal(canonicalJson(a), canonicalJson(b));

DerivedPlanRef get _ref => const DerivedPlanRef('manual-graph', 1, 'bench');
Map<String, Object?> _graph({bool manual = true}) => {
  'id': 'manual-graph',
  'nodes': [
    {'id': 'max', 'kind': 'source', 'unit': 'kg', 'sourceId': 'max-source'},
    {
      'id': 'work',
      'kind': 'scale',
      'unit': 'kg',
      'input': 'max',
      'factor': '0.8',
    },
  ],
  'bindings': {
    'max-source': manual
        ? {
            'kind': 'manual',
            'version': 1,
            'value': {'value': '100', 'unit': 'kg'},
          }
        : {'kind': 'history', 'metric': 'mass', 'slotId': 'bench-heavy'},
  },
  'plans': [
    {
      'id': 'bench',
      'templateId': definition().id,
      'revision': 1,
      'bindings': [
        {
          'occurrenceId': 'workout/heavy[0]/heavy-set',
          'metric': 'mass',
          'nodeId': 'work',
        },
        {
          'occurrenceId': 'workout/heavy[1]/heavy-set',
          'metric': 'mass',
          'nodeId': 'work',
        },
        {
          'occurrenceId': 'workout/heavy[2]/heavy-set',
          'metric': 'mass',
          'nodeId': 'work',
        },
      ],
    },
  ],
};

Map<String, Object?> _programWithPlan({
  String graphId = 'manual-graph',
  int workoutRevision = 1,
}) => {
  'id': 'planned-program',
  'name': 'Planned program',
  'plan': {
    'id': 'day',
    'type': 'day',
    'templateId': definition().id,
    'revision': workoutRevision,
    'derivedPlan': {'graphId': graphId, 'graphRevision': 1, 'planId': 'bench'},
  },
};

void derivedPlanSessionTests() {
  Future<void> withStore(
    Future<void> Function(TrainingStore, String) action,
  ) async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-plan-session-');
    final path = '${dir.path}/profile.sqlite';
    final store = await TrainingStore.open(path);
    try {
      await StoredTrainingService(store).publish(definition(), 0);
      await action(store, dir.path);
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  }

  test(
    'derived workout plans freeze rounded native ticks through restore',
    () => withStore((store, dir) async {
      await store.snapshot('$dir/v38.sqlite');
      final old = sqlite3.open('$dir/v38.sqlite');
      old.userVersion = 38;
      old.close();
      equal(NativeBackup.validateDatabase('$dir/v38.sqlite'), 38);
      final migrated = await TrainingStore.open('$dir/v38.sqlite');
      equal(
        (await StoredTrainingService(
          migrated,
        ).revision(definition().id)).number,
        1,
      );
      await migrated.close();
      final graph = copyJson(_graph());
      (graph['nodes']! as List<Object?>).add({
        'id': 'rounded',
        'kind': 'round',
        'unit': 'kg',
        'input': 'work',
        'rounding': 'nearest',
        'scale': {
          'id': 'stack',
          'unit': 'kg',
          'range': {'start': '0', 'step': '7.5', 'count': 20},
        },
      });
      final plan = jsonObject(
        (graph['plans']! as List<Object?>).single,
        'plan',
      );
      for (final binding in jsonList(plan, 'bindings')) {
        jsonObject(binding, 'binding')['nodeId'] = 'rounded';
      }
      await DerivedTargetGraphService(
        store,
      ).publish(DerivedTargetGraph.fromJson(graph), 0);
      final service = StoredTrainingService(store);
      final session = await service.start(
        'rounded-session',
        definition().id,
        1,
        instant(1),
        derivedPlan: _ref,
      );
      check(
        session.sets
            .where((s) => s.slotId == 'bench-heavy')
            .every((s) => s.suggested['mass']!.value.toString() == '82.5'),
      );
      final snapshot = session.derivedPlanInput!.snapshot;
      check(canonicalJson(snapshot).contains('tick-11'));
      final unavailable = copyJson(graph);
      unavailable['id'] = 'unavailable-graph';
      final roundNode = jsonList(unavailable, 'nodes')
          .map((n) => jsonObject(n, 'node'))
          .singleWhere((n) => n['id'] == 'rounded');
      roundNode['rounding'] = 'atLeast';
      jsonObject(
        jsonObject(roundNode['scale'], 'scale')['range'],
        'range',
      )['count'] = 10;
      await DerivedTargetGraphService(
        store,
      ).publish(DerivedTargetGraph.fromJson(unavailable), 0);
      await expectLater(
        service.start(
          'unavailable',
          definition().id,
          1,
          instant(1),
          derivedPlan: const DerivedPlanRef('unavailable-graph', 1, 'bench'),
        ),
        throwsA(isA<BodyTmiException>()),
      );
      equal(await store.session('unavailable'), null);
      final before = canonicalJson((await store.archive()).toJson());
      await store.backup('$dir/round-native');
      final file = '$dir/rounded.json';
      await LogicalArchiveFiles.export(await store.archive(), file);
      final prepared = await LogicalArchiveFiles.prepare(file);
      final destination = await TrainingStore.open('$dir/restore.sqlite');
      try {
        await destination.restore(
          prepared.backup,
          recoveryDestination: '$dir/recovery',
          confirm: true,
        );
      } finally {
        await destination.close();
        await prepared.close();
      }
      final restored = await TrainingStore.open('$dir/restore.sqlite');
      try {
        equal(canonicalJson((await restored.archive()).toJson()), before);
      } finally {
        await restored.close();
      }
      final envelope =
          jsonDecode(await File(file).readAsString()) as Map<String, Object?>;
      envelope['format'] = 'bodytmi-logical-export/38';
      envelope['sha256'] = sha256
          .convert(
            utf8.encode(
              canonicalJson({
                for (final e in envelope.entries)
                  if (e.key != 'sha256') e.key: e.value,
              }),
            ),
          )
          .toString();
      await File('$dir/old-round.json').writeAsString(jsonEncode(envelope));
      await expectLater(
        LogicalArchiveFiles.prepare('$dir/old-round.json'),
        throwsA(isA<BodyTmiException>()),
      );
      await store.snapshot('$dir/round.sqlite');
      equal(NativeBackup.validateDatabase('$dir/round.sqlite'), 44);
      final oldLabel = sqlite3.open('$dir/round.sqlite');
      oldLabel.userVersion = 38;
      oldLabel.close();
      rejects(() => NativeBackup.validateDatabase('$dir/round.sqlite'));
    }),
  );

  test(
    'binary graph targets survive session capture and portability',
    () => withStore((store, dir) async {
      await store.snapshot('$dir/v37.sqlite');
      final old = sqlite3.open('$dir/v37.sqlite');
      old.userVersion = 37;
      old.close();
      equal(NativeBackup.validateDatabase('$dir/v37.sqlite'), 37);
      final migrated = await TrainingStore.open('$dir/v37.sqlite');
      equal(
        (await StoredTrainingService(
          migrated,
        ).revision(definition().id)).number,
        1,
      );
      await migrated.close();
      final graph = copyJson(_graph());
      final nodes = graph['nodes']! as List<Object?>;
      nodes.addAll([
        {
          'id': 'offset',
          'kind': 'source',
          'unit': 'kg',
          'sourceId': 'offset-source',
        },
        {
          'id': 'adjusted',
          'kind': 'subtract',
          'unit': 'kg',
          'left': 'work',
          'right': 'offset',
        },
      ]);
      jsonObject(graph['bindings'], 'bindings')['offset-source'] = {
        'kind': 'manual',
        'version': 1,
        'value': {'value': '2.5', 'unit': 'kg'},
      };
      final plan = jsonObject(
        (graph['plans']! as List<Object?>).single,
        'plan',
      );
      for (final binding in jsonList(plan, 'bindings')) {
        jsonObject(binding, 'binding')['nodeId'] = 'adjusted';
      }
      await DerivedTargetGraphService(
        store,
      ).publish(DerivedTargetGraph.fromJson(graph), 0);
      final service = StoredTrainingService(store);
      final session = await service.start(
        'binary-session',
        definition().id,
        1,
        instant(1),
        derivedPlan: _ref,
      );
      for (final set in session.sets.where((s) => s.slotId == 'bench-heavy')) {
        equal(set.suggested['mass']!.value.toString(), '77.5');
      }
      final before = canonicalJson((await store.archive()).toJson());
      await store.backup('$dir/binary-native');
      final file = '$dir/binary.json';
      await LogicalArchiveFiles.export(await store.archive(), file);
      final prepared = await LogicalArchiveFiles.prepare(file);
      final dest = await TrainingStore.open('$dir/restore.sqlite');
      try {
        await dest.restore(
          prepared.backup,
          recoveryDestination: '$dir/recovery',
          confirm: true,
        );
      } finally {
        await dest.close();
        await prepared.close();
      }
      final restored = await TrainingStore.open('$dir/restore.sqlite');
      try {
        equal(canonicalJson((await restored.archive()).toJson()), before);
      } finally {
        await restored.close();
      }
      final envelope =
          jsonDecode(await File(file).readAsString()) as Map<String, Object?>;
      envelope['format'] = 'bodytmi-logical-export/37';
      envelope['sha256'] = sha256
          .convert(
            utf8.encode(
              canonicalJson({
                for (final e in envelope.entries)
                  if (e.key != 'sha256') e.key: e.value,
              }),
            ),
          )
          .toString();
      await File('$dir/old-binary.json').writeAsString(jsonEncode(envelope));
      await expectLater(
        LogicalArchiveFiles.prepare('$dir/old-binary.json'),
        throwsA(isA<BodyTmiException>()),
      );
      await store.snapshot('$dir/binary.sqlite');
      equal(NativeBackup.validateDatabase('$dir/binary.sqlite'), 44);
      final oldLabel = sqlite3.open('$dir/binary.sqlite');
      oldLabel.userVersion = 37;
      oldLabel.close();
      rejects(() => NativeBackup.validateDatabase('$dir/binary.sqlite'));
    }),
  );
  test(
    'a history-backed best repetition result can prescribe one fewer rep',
    () => withStore((store, _) async {
      final service = StoredTrainingService(store);
      var history = await service.start(
        'rep-history',
        definition().id,
        1,
        instant(1),
      );
      history = await service.edit(
        history.id,
        history.contentVersion,
        finished,
      );
      final graph = DerivedTargetGraph.fromJson({
        'id': 'rep-margin',
        'nodes': [
          {
            'id': 'best',
            'kind': 'source',
            'unit': 'rep',
            'sourceId': 'best-reps',
          },
          {
            'id': 'reserve',
            'kind': 'source',
            'unit': 'rep',
            'sourceId': 'rep-reserve',
          },
          {
            'id': 'goal',
            'kind': 'subtract',
            'unit': 'rep',
            'left': 'best',
            'right': 'reserve',
          },
        ],
        'bindings': {
          'best-reps': {
            'kind': 'history',
            'metric': 'reps',
            'templateId': definition().id,
            'slotId': 'bench-heavy',
          },
          'rep-reserve': {
            'kind': 'manual',
            'version': 1,
            'value': {'value': '1', 'unit': 'rep'},
          },
        },
        'plans': [
          {
            'id': 'bench',
            'templateId': definition().id,
            'revision': 1,
            'bindings': [
              for (var i = 0; i < 3; i++)
                {
                  'occurrenceId': 'workout/heavy[$i]/heavy-set',
                  'metric': 'reps',
                  'nodeId': 'goal',
                },
            ],
          },
        ],
      });
      await DerivedTargetGraphService(store).publish(graph, 0);
      final next = await service.start(
        'rep-next',
        definition().id,
        1,
        instant(2),
        derivedPlan: const DerivedPlanRef('rep-margin', 1, 'bench'),
      );
      check(
        next.sets
            .where((s) => s.slotId == 'bench-heavy')
            .every((s) => s.suggested['reps']!.value.toString() == '7'),
      );
      history = await service.edit(
        history.id,
        history.contentVersion,
        (s) => const TrainingService().complete(s, s.sets.first.id, {
          'reps': Quantity('9', 'rep'),
        }, acceptSuggested: true),
      );
      equal(
        (await service.session(
          next.id,
        )).sets.first.suggested['reps']!.value.toString(),
        '7',
      );
      final status = await DerivedWorkoutPreview(store).sessionStatus(next.id);
      equal(jsonObject(status['comparison'], 'comparison')['changed'], true);
      check(history.sets.first.contentVersion > 1);
      await store.archive();
    }),
  );

  test(
    'manual derived session targets are frozen, retry-safe and survive edits and portability',
    () => withStore((store, dir) async {
      final service = StoredTrainingService(store);
      final graphs = DerivedTargetGraphService(store);
      await graphs.publish(DerivedTargetGraph.fromJson(_graph()), 0);
      final session = await service.start(
        'derived',
        definition().id,
        1,
        instant(1),
        derivedPlan: _ref,
      );
      for (final set in session.sets.where((s) => s.slotId == 'bench-heavy')) {
        equal(set.suggested['mass']!.value.toString(), '80');
        check(!set.sources.containsKey('mass'));
      }
      rejects(
        () => const TrainingService().editTarget(
          session,
          session.sets.first.id,
          'mass',
          Quantity('90', 'kg'),
        ),
      );
      equal(session.derivedPlanInput!.reference.planId, 'bench');
      final skipped = const TrainingService().skipRemaining(
        session,
        confirm: true,
      );
      sameJson(
        skipped.derivedPlanInput!.toJson(),
        session.derivedPlanInput!.toJson(),
      );
      sameJson(sessionFromJson(skipped.toJson()).toJson(), skipped.toJson());

      sameJson(sessionFromJson(session.toJson()).toJson(), session.toJson());
      final changedGraph = _graph();
      jsonObject(
        jsonObject(changedGraph['bindings'], 'bindings')['max-source'],
        'source',
      )['value'] = {
        'value': '150',
        'unit': 'kg',
      };
      await graphs.publish(DerivedTargetGraph.fromJson(changedGraph), 1);
      final retry = await service.start(
        'derived',
        definition().id,
        1,
        instant(1),
        derivedPlan: _ref,
      );
      sameJson(retry.toJson(), session.toJson());
      await expectLater(
        service.start('derived', definition().id, 1, instant(1)),
        throwsA(isA<BodyTmiException>()),
      );
      final finished = await service.edit(session.id, session.contentVersion, (
        s,
      ) {
        for (final set in s.sets) {
          s = const TrainingService().complete(
            s,
            set.id,
            {},
            acceptSuggested: true,
          );
        }
        return s.finish(instant(1).add(const Duration(hours: 1)));
      });
      sameJson(
        finished.derivedPlanInput!.toJson(),
        session.derivedPlanInput!.toJson(),
      );
      final progression = StoredProgressionService(store);
      final rule = jsonObject(example('double-progression')['rule'], 'rule');
      final proposal = await progression.propose(
        finished.id,
        'bench-heavy',
        rule,
      );
      await progression.accept(
        finished.id,
        'bench-heavy',
        proposal.version,
        instant(1).add(const Duration(hours: 2)),
      );
      await expectLater(
        service.start(
          'after-accept',
          definition().id,
          1,
          instant(2),
          derivedPlan: _ref,
        ),
        throwsA(isA<BodyTmiException>()),
      );
      final archive = await store.archive();
      final forgedArchive = copyJson(archive.toJson());
      final firstGraph = jsonObject(
        (forgedArchive['graphs']! as List<Object?>).first,
        'graph revision',
      );
      final graphDefinition = jsonObject(firstGraph['graph'], 'graph');
      final sources = jsonObject(graphDefinition['bindings'], 'bindings');
      jsonObject(sources['max-source'], 'source')['value'] = {
        'value': '101',
        'unit': 'kg',
      };
      rejects(() => TrainingArchive.fromJson(forgedArchive));
      final path = '$dir/export.json';
      await LogicalArchiveFiles.export(archive, path);
      final restored = await LogicalArchiveFiles.prepare(path);
      try {
        sameJson(
          restored.archive.sessions.single.derivedPlanInput!.toJson(),
          session.derivedPlanInput!.toJson(),
        );
      } finally {
        await restored.close();
      }
      final native = '$dir/native';
      await store.backup(native);
      final backup = await NativeBackup.prepare(native);
      try {
        equal(backup.manifest['databaseSchemaVersion'], 44);
      } finally {
        await backup.close();
      }
      final old =
          jsonDecode(await File(path).readAsString()) as Map<String, Object?>;
      old['format'] = 'bodytmi-logical-export/28';
      old['sha256'] = sha256
          .convert(
            utf8.encode(
              canonicalJson({
                for (final e in old.entries)
                  if (e.key != 'sha256') e.key: e.value,
              }),
            ),
          )
          .toString();
      final oldPath = '$dir/old.json';
      await File(oldPath).writeAsString(jsonEncode(old));
      await expectLater(
        LogicalArchiveFiles.prepare(oldPath),
        throwsA(isA<BodyTmiException>()),
      );
      final sqlite = '$dir/snapshot.sqlite';
      await store.snapshot(sqlite);
      final db = sqlite3.open(sqlite);
      db.userVersion = 28;
      db.close();
      rejects(() => NativeBackup.validateDatabase(sqlite));
      final restoreCopy = await LogicalArchiveFiles.prepare(path);
      try {
        await store.restore(
          restoreCopy.backup,
          recoveryDestination: '$dir/recovery',
          confirm: true,
        );
      } finally {
        await restoreCopy.close();
      }
      await store.close();
      final reopened = await TrainingStore.open('$dir/profile.sqlite');
      try {
        sameJson(
          (await StoredTrainingService(
            reopened,
          ).session(session.id)).derivedPlanInput!.toJson(),
          session.derivedPlanInput!.toJson(),
        );
      } finally {
        await reopened.close();
      }
    }),
  );

  test(
    'plan session rejects forged snapshots, unsupported sources and conflicting progression',
    () => withStore((store, _) async {
      final service = StoredTrainingService(store);
      final graphs = DerivedTargetGraphService(store);
      await graphs.publish(
        DerivedTargetGraph.fromJson(_graph(manual: false)),
        0,
      );
      await expectLater(
        service.start(
          'unsupported',
          definition().id,
          1,
          instant(1),
          derivedPlan: _ref,
        ),
        throwsA(isA<BodyTmiException>()),
      );
      equal((await store.sessions()).length, 0);
      await graphs.publish(DerivedTargetGraph.fromJson(_graph()), 1);
      final ref = const DerivedPlanRef('manual-graph', 2, 'bench');
      final planned = await service.start(
        'planned',
        definition().id,
        1,
        instant(1),
        derivedPlan: ref,
      );
      final forged = copyJson(planned.toJson());
      final first = jsonObject((forged['sets']! as List<Object?>).first, 'set');
      jsonObject(first['suggested'], 'suggested')['mass'] = {
        'value': '999',
        'unit': 'kg',
      };
      rejects(() => sessionFromJson(forged));
      final old = await service.start(
        'ordinary',
        definition().id,
        1,
        instant(2),
      );
      final done = await service.edit(old.id, old.contentVersion, (s) {
        for (final set in s.sets) {
          s = const TrainingService().complete(
            s,
            set.id,
            {},
            acceptSuggested: true,
          );
        }
        return s.finish(instant(2).add(const Duration(hours: 1)));
      });
      final progression = StoredProgressionService(store);
      final rule = jsonObject(example('double-progression')['rule'], 'rule');
      final proposal = await progression.propose(done.id, 'bench-heavy', rule);
      await progression.accept(
        done.id,
        'bench-heavy',
        proposal.version,
        instant(2).add(const Duration(hours: 2)),
      );
      await expectLater(
        service.start(
          'conflict',
          definition().id,
          1,
          instant(3),
          derivedPlan: ref,
        ),
        throwsA(isA<BodyTmiException>()),
      );
      check((await store.session('conflict')) == null);
    }),
  );

  test(
    'history derived targets freeze evidence through correction and logical restore',
    () => withStore((store, dir) async {
      final training = StoredTrainingService(store);
      await DerivedTargetGraphService(
        store,
      ).publish(DerivedTargetGraph.fromJson(_graph(manual: false)), 0);
      final source = await training.start(
        'source',
        definition().id,
        1,
        instant(1),
      );
      final completed = await training.edit(
        source.id,
        source.contentVersion,
        finished,
      );
      final session = await training.start(
        'history-plan',
        definition().id,
        1,
        instant(3),
        derivedPlan: _ref,
      );
      final graph = jsonObject(
        jsonObject(
          session.derivedPlanInput!.snapshot['preview'],
          'preview',
        )['graphResolution'],
        'graph',
      );
      final binding = jsonObject(
        jsonObject(graph['bindings'], 'bindings')['max-source'],
        'source',
      );
      final fingerprint = jsonObject(
        jsonObject(binding['provenance'], 'provenance')['sourceFingerprint'],
        'fingerprint',
      );
      check(jsonList(fingerprint, 'sources').isNotEmpty);
      equal(
        jsonObject(
          (await DerivedWorkoutPreview(
            store,
          ).sessionStatus(session.id))['comparison'],
          'comparison',
        )['changed'],
        false,
      );
      final selected = Quantity.fromJson(binding['value']);
      equal(
        session.sets.first.suggested['mass']!.value,
        (selected.value * Decimal.parse('0.8')),
      );
      final edit = await training.edit(
        completed.id,
        completed.contentVersion,
        (s) => const TrainingService().complete(s, s.sets.first.id, {
          'mass': Quantity('99', 'kg'),
          'reps': Quantity('5', 'rep'),
        }),
      );
      check(edit.contentVersion > completed.contentVersion);
      equal(
        jsonObject(
          (await DerivedWorkoutPreview(
            store,
          ).sessionStatus(session.id))['comparison'],
          'comparison',
        )['changed'],
        true,
      );
      final retry = await training.start(
        'history-plan',
        definition().id,
        1,
        instant(3),
        derivedPlan: _ref,
      );
      sameJson(retry.toJson(), session.toJson());
      final archive = await store.archive();
      await LogicalArchiveFiles.export(archive, '$dir/history.json');
      final prepared = await LogicalArchiveFiles.prepare('$dir/history.json');
      try {
        await store.restore(
          prepared.backup,
          recoveryDestination: '$dir/recovery',
          confirm: true,
        );
        await store.close();
        final reopened = await TrainingStore.open('$dir/profile.sqlite');
        try {
          sameJson(
            (await StoredTrainingService(
              reopened,
            ).session(session.id)).derivedPlanInput!.toJson(),
            session.derivedPlanInput!.toJson(),
          );
        } finally {
          await reopened.close();
        }
      } finally {
        await prepared.close();
      }
    }),
  );

  test(
    'history derived sessions reject forged evidence and exclude same-start history',
    () => withStore((store, _) async {
      final training = StoredTrainingService(store);
      await DerivedTargetGraphService(
        store,
      ).publish(DerivedTargetGraph.fromJson(_graph(manual: false)), 0);
      final source = await training.start(
        'source',
        definition().id,
        1,
        instant(1),
      );
      await training.edit(source.id, source.contentVersion, finished);
      final session = await training.start(
        'history-plan',
        definition().id,
        1,
        instant(3),
        derivedPlan: _ref,
      );
      final forged = copyJson(session.toJson());
      final input = jsonObject(forged['derivedPlanInput'], 'input');
      final snapshot = jsonObject(input['snapshot'], 'snapshot');
      final preview = jsonObject(snapshot['preview'], 'preview');
      final graph = jsonObject(preview['graphResolution'], 'graph');
      final binding = jsonObject(
        jsonObject(graph['bindings'], 'bindings')['max-source'],
        'binding',
      );
      final fingerprint = jsonObject(
        jsonObject(binding['provenance'], 'provenance')['sourceFingerprint'],
        'fingerprint',
      );
      final row = jsonObject(jsonList(fingerprint, 'sources').first, 'row');
      row['runId'] = 'forged-run';
      rejects(() => sessionFromJson(forged));
      final sameTime = await training.start(
        'same-time-source',
        definition().id,
        1,
        instant(4),
      );
      await training.edit(sameTime.id, sameTime.contentVersion, (s) {
        for (final set in s.sets) {
          s = const TrainingService().complete(
            s,
            set.id,
            {},
            acceptSuggested: true,
          );
        }
        return s.finish(instant(4));
      });
      final planned = await training.start(
        'same-time-plan',
        definition().id,
        1,
        instant(4),
        derivedPlan: _ref,
      );
      final captured = jsonObject(
        jsonObject(
          jsonObject(
            planned.derivedPlanInput!.snapshot['preview'],
            'preview',
          )['graphResolution'],
          'graph',
        )['bindings'],
        'bindings',
      );
      final history = jsonObject(captured['max-source'], 'history');
      final evidence = jsonObject(
        jsonObject(history['provenance'], 'provenance')['sourceFingerprint'],
        'fingerprint',
      );
      check(
        jsonList(evidence, 'sources').every(
          (row) => jsonObject(row, 'source')['sessionId'] != 'same-time-source',
        ),
      );
      final status = DerivedWorkoutPreview(store);
      equal(
        jsonObject(
          (await status.sessionStatus(planned.id))['comparison'],
          'comparison',
        )['changed'],
        false,
      );
      final completed = await training.edit(
        planned.id,
        planned.contentVersion,
        (s) {
          for (final set in s.sets) {
            s = const TrainingService().complete(
              s,
              set.id,
              {},
              acceptSuggested: true,
            );
          }
          return s.finish(instant(4));
        },
      );
      equal(
        jsonObject(
          (await status.sessionStatus(completed.id))['comparison'],
          'comparison',
        )['changed'],
        false,
      );
      final graphResolution = await DerivedTargetGraphService(
        store,
      ).resolve('manual-graph', 1, instant(4));
      final normal = jsonObject(
        jsonObject(graphResolution['bindings'], 'bindings')['max-source'],
        'source',
      );
      final normalFingerprint = jsonObject(
        jsonObject(normal['provenance'], 'provenance')['sourceFingerprint'],
        'fingerprint',
      );
      check(
        jsonList(normalFingerprint, 'sources').any(
          (row) => jsonObject(row, 'source')['sessionId'] == 'same-time-source',
        ),
      );
    }),
  );

  test(
    'same-start history alone cannot supply a derived target',
    () => withStore((store, _) async {
      final training = StoredTrainingService(store);
      await DerivedTargetGraphService(
        store,
      ).publish(DerivedTargetGraph.fromJson(_graph(manual: false)), 0);
      final source = await training.start(
        'same',
        definition().id,
        1,
        instant(2),
      );
      await training.edit(source.id, source.contentVersion, (s) {
        for (final set in s.sets) {
          s = const TrainingService().complete(
            s,
            set.id,
            {},
            acceptSuggested: true,
          );
        }
        return s.finish(instant(2));
      });
      await expectLater(
        training.start(
          'missing',
          definition().id,
          1,
          instant(2),
          derivedPlan: _ref,
        ),
        throwsA(isA<BodyTmiException>()),
      );
      check(await store.session('missing') == null);
    }),
  );

  test(
    'history finishing exactly at session start remains eligible',
    () => withStore((store, _) async {
      final training = StoredTrainingService(store);
      await DerivedTargetGraphService(
        store,
      ).publish(DerivedTargetGraph.fromJson(_graph(manual: false)), 0);
      final source = await training.start(
        'earlier',
        definition().id,
        1,
        instant(1),
      );
      await training.edit(source.id, source.contentVersion, (s) {
        for (final set in s.sets) {
          s = const TrainingService().complete(
            s,
            set.id,
            {},
            acceptSuggested: true,
          );
        }
        return s.finish(instant(2));
      });
      final planned = await training.start(
        'next',
        definition().id,
        1,
        instant(2),
        derivedPlan: _ref,
      );
      final comparison = jsonObject(
        (await DerivedWorkoutPreview(
          store,
        ).sessionStatus(planned.id))['comparison'],
        'comparison',
      );
      equal(comparison['changed'], false);
      check(planned.sets.first.suggested['mass'] != null);
    }),
  );

  test(
    'history session evidence stays isolated between active runs',
    () => withStore((store, _) async {
      final training = StoredTrainingService(store);
      final programs = ProgramService(store);
      await DerivedTargetGraphService(
        store,
      ).publish(DerivedTargetGraph.fromJson(_graph(manual: false)), 0);
      await programs.publish(
        ProgramDefinition.fromJson({
          'id': 'program',
          'name': 'Program',
          'plan': {
            'id': 'day',
            'type': 'day',
            'templateId': definition().id,
            'revision': 1,
          },
        }),
        0,
      );
      for (final run in ['strength', 'cardio']) {
        await programs.create(run, 'program', 1, instant(1));
        final source = await programs.start(run, 1, '$run-source', instant(1));
        await training.edit(source.id, source.contentVersion, (session) {
          for (final set in session.sets) {
            session = const TrainingService().complete(session, set.id, {
              'mass': Quantity(run == 'strength' ? '100' : '50', 'kg'),
              'reps': Quantity('5', 'rep'),
            });
          }
          return session.finish(instant(1).add(const Duration(hours: 1)));
        });
      }
      final a = await programs.start(
        'strength',
        (await programs.run('strength')).contentVersion,
        'strength-next',
        instant(3),
        derivedPlan: _ref,
      );
      final b = await programs.start(
        'cardio',
        (await programs.run('cardio')).contentVersion,
        'cardio-next',
        instant(3),
        derivedPlan: _ref,
      );
      equal(a.sets.first.suggested['mass']!.value.toString(), '80');
      equal(b.sets.first.suggested['mass']!.value.toString(), '40');
      final cardioSource = await training.session('cardio-source');
      final cardioSet = cardioSource.sets.firstWhere(
        (s) => s.slotId == 'bench-heavy',
      );
      await training.edit(
        cardioSource.id,
        cardioSource.contentVersion,
        (s) => const TrainingService().complete(s, cardioSet.id, {
          'mass': Quantity('45', 'kg'),
          'reps': Quantity('5', 'rep'),
        }),
      );
      final statuses = DerivedWorkoutPreview(store);
      equal(
        jsonObject(
          (await statuses.sessionStatus(a.id))['comparison'],
          'comparison',
        )['changed'],
        false,
      );
      equal(
        jsonObject(
          (await statuses.sessionStatus(b.id))['comparison'],
          'comparison',
        )['changed'],
        true,
      );
      final cardioComparison = jsonObject(
        (await statuses.sessionStatus(b.id))['comparison'],
        'comparison',
      );
      check(
        jsonList(
          cardioComparison,
          'targetChanges',
        ).every((row) => jsonObject(row, 'target change')['changed'] == false),
      );
      final runBefore = canonicalJson((await programs.run('cardio')).toJson());
      final refreshed = await _refreshPlan(
        store,
        b.id,
        b.contentVersion,
        confirm: true,
      );
      equal(refreshed.contentVersion, b.contentVersion + 1);
      equal(refreshed.sets.first.contentVersion, b.sets.first.contentVersion);
      equal(refreshed.sets.first.suggested['mass']!.value.toString(), '40');
      equal(
        jsonObject(
          (await statuses.sessionStatus(refreshed.id))['comparison'],
          'comparison',
        )['changed'],
        false,
      );
      equal(
        canonicalJson((await training.session(a.id)).toJson()),
        canonicalJson(a.toJson()),
      );
      equal(canonicalJson((await programs.run('cardio')).toJson()), runBefore);
      final currentSource = await training.session(cardioSource.id);
      final second = currentSource.sets
          .where((s) => s.slotId == 'bench-heavy')
          .skip(1)
          .first;
      await training.edit(
        currentSource.id,
        currentSource.contentVersion,
        (s) => const TrainingService().complete(s, second.id, {
          'mass': Quantity('60', 'kg'),
          'reps': Quantity('5', 'rep'),
        }),
      );
      final refreshedAgain = await _refreshPlan(
        store,
        refreshed.id,
        refreshed.contentVersion,
        confirm: true,
      );
      equal(
        refreshedAgain.sets.first.suggested['mass']!.value.toString(),
        '48',
      );
      equal(
        refreshedAgain.sets.first.contentVersion,
        refreshed.sets.first.contentVersion + 1,
      );
      final retry = await programs.start(
        'cardio',
        1,
        b.id,
        instant(3),
        derivedPlan: _ref,
      );
      sameJson(retry.toJson(), refreshedAgain.toJson());
      equal((await store.archive()).sessions.length, 4);
    }),
  );

  test(
    'plan refresh rejects started work and backdated progression ownership',
    () => withStore((store, _) async {
      final training = StoredTrainingService(store);
      final graphs = DerivedTargetGraphService(store);
      await graphs.publish(DerivedTargetGraph.fromJson(_graph()), 0);
      final ordinary = await training.start(
        'ordinary-source',
        definition().id,
        1,
        instant(1),
      );
      final completed = await training.edit(
        ordinary.id,
        ordinary.contentVersion,
        finished,
      );
      final session = await training.start(
        'planned-before-accept',
        definition().id,
        1,
        instant(3),
        derivedPlan: _ref,
      );
      final progress = StoredProgressionService(store);
      final proposal = await progress.propose(
        completed.id,
        'bench-heavy',
        jsonObject(example('double-progression')['rule'], 'rule'),
      );
      await progress.accept(
        completed.id,
        'bench-heavy',
        proposal.version,
        instant(2),
      );
      final before = canonicalJson((await store.archive()).toJson());
      await expectLater(
        _refreshPlan(store, session.id, session.contentVersion, confirm: true),
        throwsA(isA<BodyTmiException>()),
      );
      equal(canonicalJson((await store.archive()).toJson()), before);
    }),
  );

  test(
    'plan refresh is limited to untouched sessions without clocks or traversal',
    () => withStore((store, _) async {
      final training = StoredTrainingService(store);
      await DerivedTargetGraphService(
        store,
      ).publish(DerivedTargetGraph.fromJson(_graph()), 0);
      final noPlan = await training.start(
        'no-plan-refresh',
        definition().id,
        1,
        instant(1),
      );
      await expectLater(
        _refreshPlan(store, noPlan.id, noPlan.contentVersion, confirm: true),
        throwsA(isA<BodyTmiException>()),
      );
      final used = await training.start(
        'used-plan',
        definition().id,
        1,
        instant(1),
        derivedPlan: _ref,
      );
      final done = await training.edit(
        used.id,
        used.contentVersion,
        (s) => const TrainingService().complete(
          s,
          s.sets.first.id,
          {},
          acceptSuggested: true,
        ),
      );
      await expectLater(
        _refreshPlan(store, done.id, done.contentVersion, confirm: true),
        throwsA(isA<BodyTmiException>()),
      );
      final walked = await training.start(
        'walked-plan',
        definition().id,
        1,
        instant(1),
        derivedPlan: _ref,
      );
      await ExecutionService(
        store,
      ).start('walk-refresh', walked.id, instant(1));
      await expectLater(
        _refreshPlan(store, walked.id, walked.contentVersion, confirm: true),
        throwsA(isA<BodyTmiException>()),
      );
    }),
  );

  test(
    'plan refresh rejects timing guidance made invalid by changed targets',
    () => withStore((store, _) async {
      final training = StoredTrainingService(store);
      final workout = WorkoutDefinition.fromJson(
        example('tempo-practice')['definition'],
      );
      await training.publish(workout, 0);
      await DerivedTargetGraphService(store).publish(
        DerivedTargetGraph.fromJson({
          'id': 'duration-history',
          'nodes': [
            {
              'id': 'duration',
              'kind': 'source',
              'unit': 's',
              'sourceId': 'history',
            },
          ],
          'bindings': {
            'history': {
              'kind': 'history',
              'metric': 'duration',
              'templateId': workout.id,
              'slotId': 'movement',
            },
          },
          'plans': [
            {
              'id': 'timed',
              'templateId': workout.id,
              'revision': 1,
              'bindings': [
                {
                  'occurrenceId': 'practice',
                  'metric': 'duration',
                  'nodeId': 'duration',
                },
              ],
            },
          ],
        }),
        0,
      );
      final old = await training.start(
        'duration-source',
        workout.id,
        1,
        instant(1),
      );
      final done = await training.edit(old.id, old.contentVersion, finished);
      final planned = await training.start(
        'duration-plan',
        workout.id,
        1,
        instant(3),
        derivedPlan: const DerivedPlanRef('duration-history', 1, 'timed'),
      );
      await training.edit(
        done.id,
        done.contentVersion,
        (s) => const TrainingService().complete(s, s.sets.single.id, {
          'duration': Quantity('4', 's'),
          'reps': Quantity('5', 'rep'),
        }),
      );
      final before = canonicalJson((await store.archive()).toJson());
      await expectLater(
        _refreshPlan(store, planned.id, planned.contentVersion, confirm: true),
        throwsA(isA<BodyTmiException>()),
      );
      equal(canonicalJson((await store.archive()).toJson()), before);
    }),
  );

  test(
    'plan refresh rejects even discarded session clocks',
    () => withStore((store, _) async {
      final training = StoredTrainingService(store);
      final workout = definition().toJson();
      final slot = jsonObject(jsonList(workout, 'slots').first, 'slot');
      jsonObject(slot['targets'], 'targets')['duration'] = {
        'value': '30',
        'unit': 's',
      };
      await training.publish(WorkoutDefinition.fromJson(workout), 1);
      final graph = _graph();
      jsonObject(jsonList(graph, 'plans').single, 'plan')['revision'] = 2;
      await DerivedTargetGraphService(
        store,
      ).publish(DerivedTargetGraph.fromJson(graph), 0);
      final session = await training.start(
        'timed-refresh',
        definition().id,
        2,
        instant(1),
        derivedPlan: _ref,
      );
      final clock = await TimingService(store).start(
        'refresh-clock',
        session.id,
        session.sets.first.id,
        'duration',
        null,
        instant(1),
      );
      await TimingService(
        store,
      ).stop(clock.id, clock.version, instant(1), confirm: true, discard: true);
      await expectLater(
        _refreshPlan(store, session.id, session.contentVersion, confirm: true),
        throwsA(isA<BodyTmiException>()),
      );
    }),
  );

  test(
    'v30 portability labels reject history-derived session evidence',
    () => withStore((store, dir) async {
      final training = StoredTrainingService(store);
      await DerivedTargetGraphService(
        store,
      ).publish(DerivedTargetGraph.fromJson(_graph(manual: false)), 0);
      final source = await training.start(
        'source',
        definition().id,
        1,
        instant(1),
      );
      await training.edit(source.id, source.contentVersion, finished);
      await training.start(
        'next',
        definition().id,
        1,
        instant(3),
        derivedPlan: _ref,
      );
      final path = '$dir/export.json';
      await LogicalArchiveFiles.export(await store.archive(), path);
      final envelope =
          jsonDecode(await File(path).readAsString()) as Map<String, Object?>;
      envelope['format'] = 'bodytmi-logical-export/30';
      envelope['sha256'] = sha256
          .convert(
            utf8.encode(
              canonicalJson({
                for (final e in envelope.entries)
                  if (e.key != 'sha256') e.key: e.value,
              }),
            ),
          )
          .toString();
      await File('$dir/old.json').writeAsString(jsonEncode(envelope));
      await expectLater(
        LogicalArchiveFiles.prepare('$dir/old.json'),
        throwsA(isA<BodyTmiException>()),
      );
      final snapshot = '$dir/snapshot.sqlite';
      await store.snapshot(snapshot);
      equal(NativeBackup.validateDatabase(snapshot), 44);
      final db = sqlite3.open(snapshot);
      db.userVersion = 30;
      db.close();
      rejects(() => NativeBackup.validateDatabase(snapshot));
    }),
  );

  test(
    'session plan status handles absent plans and pinned graph revisions',
    () => withStore((store, _) async {
      final training = StoredTrainingService(store);
      final graphService = DerivedTargetGraphService(store);
      final statusService = DerivedWorkoutPreview(store);
      final ordinary = await training.start(
        'ordinary-status',
        definition().id,
        1,
        instant(1),
      );
      final empty = await statusService.sessionStatus(ordinary.id);
      equal(empty['configured'], false);
      equal(empty['comparison'], null);
      equal(empty['sessionVersion'], ordinary.contentVersion);
      await expectLater(
        statusService.sessionStatus('missing'),
        throwsA(isA<BodyTmiException>()),
      );
      await graphService.publish(DerivedTargetGraph.fromJson(_graph()), 0);
      final session = await training.start(
        'planned-status',
        definition().id,
        1,
        instant(2),
        derivedPlan: _ref,
      );
      final changed = _graph();
      jsonObject(
        jsonObject(changed['bindings'], 'bindings')['max-source'],
        'source',
      )['value'] = {
        'value': '120',
        'unit': 'kg',
      };
      await graphService.publish(DerivedTargetGraph.fromJson(changed), 1);
      final result = await statusService.sessionStatus(session.id);
      equal(result['sessionStatus'], 'active');
      equal(jsonObject(result['comparison'], 'comparison')['changed'], false);
      equal(jsonObject(result['comparison'], 'comparison')['graphRevision'], 1);
    }),
  );

  test(
    'store plan-status CLI reports stored session evidence and rejects extra fields',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-plan-status-cli-',
      );
      final db = '${dir.path}/profile.sqlite';
      final store = await TrainingStore.open(db);
      try {
        final training = StoredTrainingService(store);
        await training.publish(definition(), 0);
        await DerivedTargetGraphService(
          store,
        ).publish(DerivedTargetGraph.fromJson(_graph()), 0);
        await training.start(
          'session',
          definition().id,
          1,
          instant(1),
          derivedPlan: _ref,
        );
        await store.close();
        final result = await invoke([
          'store',
          'plan-status',
        ], jsonEncode({'schemaVersion': 1, 'database': db, 'id': 'session'}));
        equal(result.code, 0);
        equal(result.error, '');
        final data = jsonObject(
          jsonObject(jsonDecode(result.output), 'envelope')['data'],
          'status',
        );
        equal(data['policy'], 'bodytmi-derived-session-plan-status/1');
        equal(data['configured'], true);
        equal(jsonObject(data['comparison'], 'comparison')['changed'], false);
        final bad = await invoke(
          ['store', 'plan-status'],
          jsonEncode({
            'schemaVersion': 1,
            'database': db,
            'id': 'session',
            'runId': 'other',
          }),
        );
        equal(bad.code, 2);
        equal(bad.output, '');
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'program day automatically selects its pinned plan in independent runs',
    () => withStore((store, dir) async {
      final training = StoredTrainingService(store);
      final graphs = DerivedTargetGraphService(store);
      final programs = ProgramService(store);
      await graphs.publish(DerivedTargetGraph.fromJson(_graph()), 0);
      await programs.publish(ProgramDefinition.fromJson(_programWithPlan()), 0);
      final initialProgram = await programs.revision('planned-program');
      final pinned = initialProgram.definition.plan.nodes
          .whereType<ProgramDay>()
          .single
          .derivedPlan;
      sameJson(pinned!.toJson(), _ref.toJson());
      for (final run in ['strength', 'cardio']) {
        await programs.create(run, 'planned-program', 1, instant(1));
        final schedule = await programs.schedule(run, count: 1);
        final scheduleDay = jsonObject(
          jsonObject(jsonList(schedule, 'days').single, 'entry')['day'],
          'day',
        );
        sameJson(scheduleDay['derivedPlan'], _ref.toJson());
        final started = await programs.start(
          run,
          1,
          '$run-session',
          instant(2),
        );
        equal(started.sets.first.suggested['mass']!.value.toString(), '80');
        sameJson(started.derivedPlanInput!.reference.toJson(), _ref.toJson());
        final retry = await programs.start(
          run,
          1,
          started.id,
          instant(2),
          derivedPlan: _ref,
        );
        sameJson(retry.toJson(), started.toJson());
        await expectLater(
          programs.start(
            run,
            1,
            started.id,
            instant(2),
            derivedPlan: const DerivedPlanRef('different', 1, 'other'),
          ),
          throwsA(isA<BodyTmiException>()),
        );
      }
      final changed = _graph();
      jsonObject(
        jsonObject(changed['bindings'], 'bindings')['max-source'],
        'source',
      )['value'] = {
        'value': '200',
        'unit': 'kg',
      };
      await graphs.publish(DerivedTargetGraph.fromJson(changed), 1);
      final first = await training.session('strength-session');
      await training.edit(first.id, first.contentVersion, finished);
      final again = await programs.start(
        'strength',
        (await programs.run('strength')).contentVersion,
        'strength-next',
        instant(3),
      );
      equal(again.sets.first.suggested['mass']!.value.toString(), '80');
      final archive = await store.archive();
      await LogicalArchiveFiles.export(archive, '$dir/plan.json');
      final prepared = await LogicalArchiveFiles.prepare('$dir/plan.json');
      try {
        equal(
          prepared.archive.programRevisions.single.definition.plan.nodes
              .whereType<ProgramDay>()
              .single
              .derivedPlan!
              .graphRevision,
          1,
        );
        await store.restore(
          prepared.backup,
          recoveryDestination: '$dir/recovery',
          confirm: true,
        );
        await store.close();
        final reopened = await TrainingStore.open('$dir/profile.sqlite');
        try {
          equal(
            (await ProgramService(reopened).run('strength'))
                .program
                .definition
                .plan
                .nodes
                .whereType<ProgramDay>()
                .single
                .derivedPlan!
                .planId,
            'bench',
          );
        } finally {
          await reopened.close();
        }
      } finally {
        await prepared.close();
      }
    }),
  );

  test(
    'program day pins resolve history separately for each run',
    () => withStore((store, _) async {
      final training = StoredTrainingService(store);
      final programs = ProgramService(store);
      await DerivedTargetGraphService(
        store,
      ).publish(DerivedTargetGraph.fromJson(_graph(manual: false)), 0);
      final pinnedDay = jsonObject(_programWithPlan()['plan'], 'day');
      pinnedDay['id'] = 'derived';
      await programs.publish(
        ProgramDefinition.fromJson({
          'id': 'two-days',
          'name': 'Two days',
          'plan': {
            'id': 'cycle',
            'type': 'group',
            'children': [
              {
                'id': 'seed',
                'type': 'day',
                'templateId': definition().id,
                'revision': 1,
              },
              pinnedDay,
            ],
          },
        }),
        0,
      );
      for (final run in ['strength', 'cardio']) {
        await programs.create(run, 'two-days', 1, instant(1));
        final source = await programs.start(run, 1, '$run-source', instant(1));
        await training.edit(source.id, source.contentVersion, (s) {
          for (final set in s.sets) {
            s = const TrainingService().complete(s, set.id, {
              'mass': Quantity(run == 'strength' ? '100' : '50', 'kg'),
              'reps': Quantity('5', 'rep'),
            });
          }
          return s.finish(instant(1).add(const Duration(hours: 1)));
        });
        final version = (await programs.run(run)).contentVersion;
        await expectLater(
          programs.start(
            run,
            version,
            '$run-wrong',
            instant(2),
            derivedPlan: const DerivedPlanRef('other', 1, 'other'),
          ),
          throwsA(isA<BodyTmiException>()),
        );
        check(await store.session('$run-wrong') == null);
        final planned = await programs.start(
          run,
          version,
          '$run-plan',
          instant(2),
        );
        equal(
          planned.sets.first.suggested['mass']!.value.toString(),
          run == 'strength' ? '80' : '40',
        );
      }
      final source = await training.session('cardio-source');
      final set = source.sets.firstWhere((s) => s.slotId == 'bench-heavy');
      await training.edit(
        source.id,
        source.contentVersion,
        (s) => const TrainingService().complete(s, set.id, {
          'mass': Quantity('60', 'kg'),
          'reps': Quantity('5', 'rep'),
        }),
      );
      final cardio = await training.session('cardio-plan');
      final refreshed = await _refreshPlan(
        store,
        cardio.id,
        cardio.contentVersion,
        confirm: true,
      );
      equal(refreshed.sets.first.suggested['mass']!.value.toString(), '48');
      final retry = await programs.start('cardio', 1, cardio.id, instant(2));
      sameJson(retry.toJson(), refreshed.toJson());
      equal(
        (await training.session(
          'strength-plan',
        )).sets.first.suggested['mass']!.value.toString(),
        '80',
      );
      equal((await store.archive()).sessions.length, 4);
    }),
  );

  test(
    'program day plan pins validate publication and archive references',
    () => withStore((store, _) async {
      final graphs = DerivedTargetGraphService(store);
      final programs = ProgramService(store);
      await expectLater(
        programs.publish(
          ProgramDefinition.fromJson(_programWithPlan(graphId: 'missing')),
          0,
        ),
        throwsA(isA<BodyTmiException>()),
      );
      await graphs.publish(DerivedTargetGraph.fromJson(_graph()), 0);
      final wrong = _programWithPlan();
      jsonObject(
        jsonObject(wrong['plan'], 'day')['derivedPlan'],
        'plan',
      )['planId'] = 'unknown';
      await expectLater(
        programs.publish(ProgramDefinition.fromJson(wrong), 0),
        throwsA(isA<BodyTmiException>()),
      );
      await programs.publish(ProgramDefinition.fromJson(_programWithPlan()), 0);
      final doc = copyJson((await store.archive()).toJson());
      final program = jsonObject(
        jsonList(doc, 'programRevisions').single,
        'program',
      );
      final plan = jsonObject(
        jsonObject(program['definition'], 'definition')['plan'],
        'day',
      );
      jsonObject(plan['derivedPlan'], 'derivedPlan')['graphId'] = 'missing';
      rejects(() => TrainingArchive.fromJson(doc));
    }),
  );

  test(
    'program day plan pins reject older portability labels',
    () => withStore((store, dir) async {
      await DerivedTargetGraphService(
        store,
      ).publish(DerivedTargetGraph.fromJson(_graph()), 0);
      await ProgramService(
        store,
      ).publish(ProgramDefinition.fromJson(_programWithPlan()), 0);
      final archive = await store.archive();
      await LogicalArchiveFiles.export(archive, '$dir/export.json');
      final envelope =
          jsonDecode(await File('$dir/export.json').readAsString())
              as Map<String, Object?>;
      envelope['format'] = 'bodytmi-logical-export/32';
      envelope['sha256'] = sha256
          .convert(
            utf8.encode(
              canonicalJson({
                for (final e in envelope.entries)
                  if (e.key != 'sha256') e.key: e.value,
              }),
            ),
          )
          .toString();
      await File('$dir/old.json').writeAsString(jsonEncode(envelope));
      await expectLater(
        LogicalArchiveFiles.prepare('$dir/old.json'),
        throwsA(isA<BodyTmiException>()),
      );
      await store.snapshot('$dir/snapshot.sqlite');
      equal(NativeBackup.validateDatabase('$dir/snapshot.sqlite'), 44);
      final db = sqlite3.open('$dir/snapshot.sqlite');
      db.userVersion = 32;
      db.close();
      rejects(() => NativeBackup.validateDatabase('$dir/snapshot.sqlite'));
    }),
  );

  test(
    'v32 program runs migrate without acquiring a derived plan',
    () => withStore((store, dir) async {
      final programs = ProgramService(store);
      final definitionJson = _programWithPlan();
      jsonObject(definitionJson['plan'], 'day').remove('derivedPlan');
      await programs.publish(ProgramDefinition.fromJson(definitionJson), 0);
      await programs.create('old-run', 'planned-program', 1, instant(1));
      final original = (await programs.run('old-run')).toJson();
      await store.snapshot('$dir/old.sqlite');
      final db = sqlite3.open('$dir/old.sqlite');
      db.userVersion = 32;
      db.close();
      final reopened = await TrainingStore.open('$dir/old.sqlite');
      try {
        sameJson(
          (await ProgramService(reopened).run('old-run')).toJson(),
          original,
        );
        final session = await ProgramService(
          reopened,
        ).start('old-run', 1, 'old-session', instant(2));
        check(session.derivedPlanInput == null);
      } finally {
        await reopened.close();
      }
    }),
  );

  test(
    'group skip retains frozen plan inputs and permits idempotent finalization',
    () => withStore((store, _) async {
      await DerivedTargetGraphService(
        store,
      ).publish(DerivedTargetGraph.fromJson(_graph()), 0);
      final training = StoredTrainingService(store);
      final session = await training.start(
        'traverse',
        definition().id,
        1,
        instant(1),
        derivedPlan: _ref,
      );
      final execution = ExecutionService(store);
      await execution.start('walk', session.id, instant(1));
      await execution.skipGroup(
        'walk',
        1,
        1,
        'skip-all',
        'workout',
        instant(1),
        confirm: true,
      );
      final skipped = await training.session(session.id);
      sameJson(
        skipped.derivedPlanInput!.toJson(),
        session.derivedPlanInput!.toJson(),
      );
      final done = await training.edit(
        skipped.id,
        skipped.contentVersion,
        (s) => s.finish(instant(1).add(const Duration(hours: 1))),
      );
      sameJson(
        done.derivedPlanInput!.toJson(),
        session.derivedPlanInput!.toJson(),
      );
      equal((await store.archive()).finalizations.length, 1);
    }),
  );

  test(
    'schema v28 profiles migrate without inventing session plan inputs',
    () => withStore((store, dir) async {
      await DerivedTargetGraphService(
        store,
      ).publish(DerivedTargetGraph.fromJson(_graph()), 0);
      final before = canonicalJson((await store.archive()).toJson());
      final path = '$dir/v28.sqlite';
      await store.snapshot(path);
      await store.close();
      final db = sqlite3.open(path);
      db.userVersion = 28;
      db.close();
      equal(NativeBackup.validateDatabase(path), 28);
      final upgraded = await TrainingStore.open(path);
      try {
        equal(canonicalJson((await upgraded.archive()).toJson()), before);
      } finally {
        await upgraded.close();
      }
      final reopened = sqlite3.open(path);
      try {
        equal(reopened.userVersion, 44);
      } finally {
        reopened.close();
      }
    }),
  );

  test(
    'manual plan sessions retain independent run bindings and idempotent start identities',
    () => withStore((store, _) async {
      await DerivedTargetGraphService(
        store,
      ).publish(DerivedTargetGraph.fromJson(_graph()), 0);
      final programs = ProgramService(store);
      await programs.publish(
        ProgramDefinition.fromJson({
          'id': 'program',
          'name': 'Program',
          'plan': {
            'id': 'cycle',
            'type': 'group',
            'children': [
              {
                'id': 'day',
                'type': 'day',
                'templateId': definition().id,
                'revision': 1,
              },
            ],
          },
        }),
        0,
      );
      for (final run in ['run-a', 'run-b']) {
        await programs.create(run, 'program', 1, instant(1));
      }
      final a = await programs.start(
        'run-a',
        1,
        'session-a',
        instant(2),
        derivedPlan: _ref,
      );
      final b = await programs.start(
        'run-b',
        1,
        'session-b',
        instant(2),
        derivedPlan: _ref,
      );
      final scopeA = jsonObject(
        jsonObject(
          jsonObject(
            a.derivedPlanInput!.snapshot['preview'],
            'preview',
          )['graphResolution'],
          'graph',
        )['historyScope'],
        'scope',
      );
      final scopeB = jsonObject(
        jsonObject(
          jsonObject(
            b.derivedPlanInput!.snapshot['preview'],
            'preview',
          )['graphResolution'],
          'graph',
        )['historyScope'],
        'scope',
      );
      equal(scopeA['runId'], 'run-a');
      equal(scopeB['runId'], 'run-b');
      sameJson(
        (await programs.start(
          'run-a',
          1,
          'session-a',
          instant(2),
          derivedPlan: _ref,
        )).toJson(),
        a.toJson(),
      );
      await expectLater(
        programs.start('run-a', 1, 'session-a', instant(2)),
        throwsA(isA<BodyTmiException>()),
      );
      equal((await store.archive()).sessions.length, 2);
    }),
  );
}
