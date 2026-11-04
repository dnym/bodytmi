import 'dart:convert';
import 'dart:io';

import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart' show expectLater, isA, throwsA;

import 'fixtures.dart';
import 'support.dart';

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
      equal(session.derivedPlanInput!.reference.planId, 'bench');
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
        equal(backup.manifest['databaseSchemaVersion'], 31);
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
    'history derived sessions reject forged evidence',
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
      await expectLater(
        training.start(
          'same-time-plan',
          definition().id,
          1,
          instant(4),
          derivedPlan: _ref,
        ),
        throwsA(isA<BodyTmiException>()),
      );
      check(await store.session('same-time-plan') == null);
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
      equal((await store.archive()).sessions.length, 4);
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
      equal(NativeBackup.validateDatabase(snapshot), 31);
      final db = sqlite3.open(snapshot);
      db.userVersion = 30;
      db.close();
      rejects(() => NativeBackup.validateDatabase(snapshot));
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
        equal(reopened.userVersion, 31);
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
