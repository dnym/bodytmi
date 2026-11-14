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

const _ref = DerivedPlanRef('mass-graph', 1, 'mass-plan');
Map<String, Object?> _graph({bool unused = false}) => {
  'id': 'mass-graph',
  'nodes': [
    {'id': 'body', 'kind': 'source', 'unit': 'kg', 'sourceId': 'body-source'},
    if (unused)
      {
        'id': 'manual',
        'kind': 'source',
        'unit': 'kg',
        'sourceId': 'manual-source',
      },
    {
      'id': 'target',
      'kind': 'scale',
      'unit': 'kg',
      'input': unused ? 'manual' : 'body',
      'factor': '0.8',
    },
  ],
  'bindings': {
    'body-source': {'kind': 'bodyMass', 'context': 'clothed-training'},
    if (unused)
      'manual-source': {
        'kind': 'manual',
        'version': 1,
        'value': {'value': '100', 'unit': 'kg'},
      },
  },
  'plans': [
    {
      'id': 'mass-plan',
      'templateId': definition().id,
      'revision': 1,
      'bindings': [
        {
          'occurrenceId': 'workout/heavy[0]/heavy-set',
          'metric': 'mass',
          'nodeId': 'target',
        },
        {
          'occurrenceId': 'workout/heavy[1]/heavy-set',
          'metric': 'mass',
          'nodeId': 'target',
        },
        {
          'occurrenceId': 'workout/heavy[2]/heavy-set',
          'metric': 'mass',
          'nodeId': 'target',
        },
      ],
    },
  ],
};
Map<String, Object?> _observation(
  String id,
  String context,
  String at,
  String value,
  String unit,
) => {
  'id': id,
  'context': context,
  'observedAt': at,
  'mass': {'value': value, 'unit': unit},
};

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

void derivedPlanBodyMassTests() {
  Future<void> withStore(
    Future<void> Function(TrainingStore, String) action,
  ) async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-plan-mass-');
    final store = await TrainingStore.open('${dir.path}/profile.sqlite');
    try {
      await StoredTrainingService(store).publish(definition(), 0);
      await action(store, dir.path);
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  }

  test(
    'derived body mass sessions freeze original eligible observations and survive corrections and restore',
    () => withStore((store, dir) async {
      final mass = StoredBodyMassService(store);
      await mass.save(
        _observation(
          'm1',
          'clothed-training',
          '2026-10-01T08:00:00+02:00',
          '200',
          'lb',
        ),
        0,
      );
      await mass.save(
        _observation(
          'm2',
          'clothed-training',
          '2026-10-02T08:00:00+02:00',
          '85',
          'kg',
        ),
        0,
      );
      await mass.save(
        _observation(
          'future',
          'clothed-training',
          '2026-10-04T08:00:00Z',
          '100',
          'kg',
        ),
        0,
      );
      await mass.save(
        _observation('health', 'health', '2026-10-02T08:00:00Z', '40', 'kg'),
        0,
      );
      await DerivedTargetGraphService(
        store,
      ).publish(DerivedTargetGraph.fromJson(_graph()), 0);
      final training = StoredTrainingService(store);
      final session = await training.start(
        'body-session',
        definition().id,
        1,
        instant(3),
        derivedPlan: _ref,
      );
      equal(session.sets.first.suggested['mass']!.value.toString(), '68');
      final statusService = DerivedWorkoutPreview(store);
      final beforeStatus = await statusService.sessionStatus(session.id);
      equal(beforeStatus['configured'], true);
      equal(
        jsonObject(beforeStatus['comparison'], 'comparison')['changed'],
        false,
      );
      final captured =
          session.derivedPlanInput!.bodyMassSources['body-source']!;
      equal(captured.length, 2);
      equal(captured.first.id, 'm1');
      equal(captured.first.mass.enteredUnit, Unit.lb);
      equal(captured.first.observedAtText, '2026-10-01T08:00:00+02:00');
      equal(
        canonicalJson(sessionFromJson(session.toJson()).toJson()),
        canonicalJson(session.toJson()),
      );
      await mass.save(
        _observation(
          'm2',
          'clothed-training',
          '2026-10-02T08:00:00+02:00',
          '90',
          'kg',
        ),
        1,
      );
      await mass.delete('m1', 1, confirm: true);
      await mass.save(
        _observation(
          'backdated',
          'clothed-training',
          '2026-10-02T09:00:00Z',
          '92',
          'kg',
        ),
        0,
      );
      final checksumBeforeStatus = canonicalJson(
        (await store.archive()).toJson(),
      );
      final afterStatus = await statusService.sessionStatus(session.id);
      final comparison = jsonObject(afterStatus['comparison'], 'comparison');
      equal(comparison['changed'], true);
      equal(
        jsonObject(
          jsonObject(comparison['sources'], 'sources')['body-source'],
          'source',
        )['changed'],
        true,
      );
      check(
        jsonList(
          comparison,
          'targetChanges',
        ).any((item) => jsonObject(item, 'target change')['changed'] == true),
      );
      equal(
        canonicalJson((await store.archive()).toJson()),
        checksumBeforeStatus,
      );
      final retry = await training.start(
        'body-session',
        definition().id,
        1,
        instant(3),
        derivedPlan: _ref,
      );
      equal(canonicalJson(retry.toJson()), canonicalJson(session.toJson()));
      final archive = await store.archive();
      final export = '$dir/body.json';
      await LogicalArchiveFiles.export(archive, export);
      final prepared = await LogicalArchiveFiles.prepare(export);
      try {
        equal(
          canonicalJson(
            prepared.archive.sessions.single.derivedPlanInput!.toJson(),
          ),
          canonicalJson(session.derivedPlanInput!.toJson()),
        );
        await store.restore(
          prepared.backup,
          recoveryDestination: '$dir/recovery',
          confirm: true,
        );
      } finally {
        await prepared.close();
      }
      await store.close();
      final reopened = await TrainingStore.open('$dir/profile.sqlite');
      try {
        equal(
          canonicalJson(
            (await StoredTrainingService(
              reopened,
            ).session(session.id)).derivedPlanInput!.toJson(),
          ),
          canonicalJson(session.derivedPlanInput!.toJson()),
        );
      } finally {
        await reopened.close();
      }
    }),
  );
  test(
    'captured derived body-mass metadata remains portable after current metadata is cleared',
    () => withStore((store, dir) async {
      final mass = StoredBodyMassService(store);
      final observation = _observation(
        'm1',
        'clothed-training',
        '2026-10-01T08:00:00Z',
        '80',
        'kg',
      );
      await mass.save({
        ...observation,
        'source': 'Scale',
        'notes': 'Clothed',
      }, 0);
      await DerivedTargetGraphService(
        store,
      ).publish(DerivedTargetGraph.fromJson(_graph()), 0);
      final session = await StoredTrainingService(store).start(
        'derived-meta',
        definition().id,
        1,
        instant(3),
        derivedPlan: _ref,
      );
      await mass.save(observation, 1);
      equal(
        session.derivedPlanInput!.bodyMassSources['body-source']!.single.notes,
        'Clothed',
      );
      final comparison = jsonObject(
        (await DerivedWorkoutPreview(
          store,
        ).sessionStatus(session.id))['comparison'],
        'comparison',
      );
      equal(comparison['changed'], true);
      check(
        jsonList(
          comparison,
          'targetChanges',
        ).every((row) => jsonObject(row, 'target change')['changed'] == false),
      );
      final archive = await store.archive();
      check(!archive.bodyMass.single.measurement.hasMetadata);
      await LogicalArchiveFiles.export(archive, '$dir/derived-meta.json');
      final prepared = await LogicalArchiveFiles.prepare(
        '$dir/derived-meta.json',
      );
      try {
        equal(
          prepared
              .archive
              .sessions
              .single
              .derivedPlanInput!
              .bodyMassSources['body-source']!
              .single
              .notes,
          'Clothed',
        );
      } finally {
        await prepared.close();
      }
      final envelope =
          jsonDecode(await File('$dir/derived-meta.json').readAsString())
              as Map<String, Object?>;
      envelope['format'] = 'bodytmi-logical-export/34';
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
      await File(
        '$dir/derived-meta-v34.json',
      ).writeAsString(jsonEncode(envelope));
      await expectLater(
        LogicalArchiveFiles.prepare('$dir/derived-meta-v34.json'),
        throwsA(isA<BodyTmiException>()),
      );
      await store.snapshot('$dir/derived-meta.sqlite');
      final db = sqlite3.open('$dir/derived-meta.sqlite');
      db.execute('DROP TABLE IF EXISTS repeat_checkpoints');
      db.execute('DROP TABLE IF EXISTS window_checkpoints');
      db.execute('DROP TABLE IF EXISTS progression_reconciliations');
      db.execute('DROP TABLE IF EXISTS lever_link_revisions');
      db.execute('DROP TABLE IF EXISTS shared_lever_applications');
      db.execute('DROP TABLE IF EXISTS link_retirement_anchors');
      db.execute('DROP TABLE IF EXISTS program_upgrade_receipts');
      db.execute('DROP TABLE IF EXISTS exercise_revisions');
      db.execute('DROP TABLE IF EXISTS implementation_revisions');
      db.execute('DROP TABLE IF EXISTS equipment_revisions');
      db.execute('DROP TABLE IF EXISTS gym_revisions');
      db.execute('DROP TABLE IF EXISTS equipment_instance_revisions');
      db.execute('DROP TABLE IF EXISTS imported_sessions');
      db.userVersion = 34;
      db.close();
      rejects(() => NativeBackup.validateDatabase('$dir/derived-meta.sqlite'));
    }),
  );

  test(
    'explicit plan refresh freezes current sources and preserves unowned targets',
    () => withStore((store, dir) async {
      final mass = StoredBodyMassService(store);
      final original = _observation(
        'm',
        'clothed-training',
        '2026-10-01T08:00:00Z',
        '80',
        'kg',
      );
      await mass.save(original, 0);
      await DerivedTargetGraphService(
        store,
      ).publish(DerivedTargetGraph.fromJson(_graph()), 0);
      final training = StoredTrainingService(store);
      final session = await training.start(
        'refresh-plan',
        definition().id,
        1,
        instant(3),
        derivedPlan: _ref,
      );
      equal(session.sets.first.suggested['mass']!.value.toString(), '64');
      final reviewed = jsonObject(
        (await DerivedWorkoutPreview(
          store,
        ).sessionStatus(session.id))['comparison'],
        'comparison',
      )['currentPreview'];
      await mass.save({
        ...original,
        'mass': {'value': '90', 'unit': 'kg'},
      }, 1);
      final before = canonicalJson((await store.archive()).toJson());
      await expectLater(
        training.refreshPlan(
          session.id,
          session.contentVersion,
          expectedPreview: reviewed,
          confirm: true,
        ),
        throwsA(isA<BodyTmiException>()),
      );
      await expectLater(
        _refreshPlan(store, session.id, session.contentVersion, confirm: false),
        throwsA(isA<BodyTmiException>()),
      );
      await expectLater(
        _refreshPlan(
          store,
          session.id,
          session.contentVersion + 1,
          confirm: true,
        ),
        throwsA(isA<BodyTmiException>()),
      );
      equal(canonicalJson((await store.archive()).toJson()), before);
      final refreshed = await _refreshPlan(
        store,
        session.id,
        session.contentVersion,
        confirm: true,
      );
      equal(refreshed.contentVersion, session.contentVersion + 1);
      equal(refreshed.sets.first.suggested['mass']!.value.toString(), '72');
      equal(
        refreshed.sets.first.contentVersion,
        session.sets.first.contentVersion + 1,
      );
      equal(
        canonicalJson(refreshed.sets.last.toJson()),
        canonicalJson(session.sets.last.toJson()),
      );
      equal(
        refreshed
            .derivedPlanInput!
            .bodyMassSources['body-source']!
            .single
            .mass
            .value
            .toString(),
        '90',
      );
      equal(
        jsonObject(
          (await DerivedWorkoutPreview(
            store,
          ).sessionStatus(refreshed.id))['comparison'],
          'comparison',
        )['changed'],
        false,
      );
      final retry = await training.start(
        session.id,
        definition().id,
        1,
        instant(3),
        derivedPlan: _ref,
      );
      equal(canonicalJson(retry.toJson()), canonicalJson(refreshed.toJson()));
      equal(
        (await _refreshPlan(
          store,
          refreshed.id,
          refreshed.contentVersion,
          confirm: true,
        )).contentVersion,
        refreshed.contentVersion,
      );
      await expectLater(
        _refreshPlan(store, session.id, session.contentVersion, confirm: true),
        throwsA(isA<BodyTmiException>()),
      );
      await LogicalArchiveFiles.export(
        await store.archive(),
        '$dir/refreshed-plan.json',
      );
      final prepared = await LogicalArchiveFiles.prepare(
        '$dir/refreshed-plan.json',
      );
      try {
        await store.restore(
          prepared.backup,
          recoveryDestination: '$dir/recovery-plan-refresh',
          confirm: true,
        );
        await store.close();
        final reopened = await TrainingStore.open('$dir/profile.sqlite');
        try {
          equal(
            canonicalJson(
              (await StoredTrainingService(
                reopened,
              ).session(session.id)).toJson(),
            ),
            canonicalJson(refreshed.toJson()),
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
    'native plan refresh rejects stale reviewed previews across processes',
    () => withStore((store, dir) async {
      final mass = StoredBodyMassService(store);
      final observation = _observation(
        'm',
        'clothed-training',
        '2026-10-01T08:00:00Z',
        '80',
        'kg',
      );
      await mass.save(observation, 0);
      await DerivedTargetGraphService(
        store,
      ).publish(DerivedTargetGraph.fromJson(_graph()), 0);
      final training = StoredTrainingService(store);
      final session = await training.start(
        'cli-refresh',
        definition().id,
        1,
        instant(3),
        derivedPlan: _ref,
      );
      final reviewed = jsonObject(
        (await DerivedWorkoutPreview(
          store,
        ).sessionStatus(session.id))['comparison'],
        'comparison',
      )['currentPreview'];
      await mass.save({
        ...observation,
        'mass': {'value': '90', 'unit': 'kg'},
      }, 1);
      await store.close();
      Future<({int code, String output, String error})> call(
        String action,
        Map<String, Object?> data,
      ) => invoke(
        action.split(' '),
        jsonEncode({
          'schemaVersion': 1,
          'database': '$dir/profile.sqlite',
          ...data,
        }),
      );
      final stale = await call('store plan-refresh', {
        'id': session.id,
        'expectedVersion': session.contentVersion,
        'expectedPreview': reviewed,
        'confirm': true,
      });
      equal(stale.code, 5);
      equal(stale.output, '');
      final status = await call('store plan-status', {'id': session.id});
      equal(status.code, 0);
      final data = jsonObject(
        jsonObject(jsonDecode(status.output), 'response')['data'],
        'status',
      );
      final current = jsonObject(
        data['comparison'],
        'comparison',
      )['currentPreview'];
      final fresh = await call('store plan-refresh', {
        'id': session.id,
        'expectedVersion': session.contentVersion,
        'expectedPreview': current,
        'confirm': true,
      });
      equal(fresh.code, 0);
      final updated = sessionFromJson(
        jsonObject(jsonDecode(fresh.output), 'response')['data'],
      );
      equal(updated.sets.first.suggested['mass']!.value.toString(), '72');
      final missing = await call('store plan-refresh', {
        'id': session.id,
        'expectedVersion': updated.contentVersion,
        'confirm': true,
      });
      equal(missing.code, 2);
      equal(missing.output, '');
    }),
  );

  test(
    'plan refresh records metadata-only source changes without changing set versions',
    () => withStore((store, _) async {
      final mass = StoredBodyMassService(store);
      final original = _observation(
        'm',
        'clothed-training',
        '2026-10-01T08:00:00Z',
        '80',
        'kg',
      );
      await mass.save({...original, 'notes': 'Before'}, 0);
      await DerivedTargetGraphService(
        store,
      ).publish(DerivedTargetGraph.fromJson(_graph()), 0);
      final training = StoredTrainingService(store);
      final session = await training.start(
        'metadata-plan',
        definition().id,
        1,
        instant(3),
        derivedPlan: _ref,
      );
      await mass.save({...original, 'notes': 'After'}, 1);
      final next = await _refreshPlan(
        store,
        session.id,
        session.contentVersion,
        confirm: true,
      );
      equal(next.contentVersion, session.contentVersion + 1);
      equal(next.sets.first.contentVersion, session.sets.first.contentVersion);
      equal(
        next.sets.first.suggested['mass']!.value.toString(),
        session.sets.first.suggested['mass']!.value.toString(),
      );
      equal(
        next.derivedPlanInput!.bodyMassSources['body-source']!.single.notes,
        'After',
      );
    }),
  );

  test(
    'plan refresh rejects unresolved sources and leaves captured session unchanged',
    () => withStore((store, _) async {
      final mass = StoredBodyMassService(store);
      await mass.save(
        _observation(
          'm',
          'clothed-training',
          '2026-10-01T08:00:00Z',
          '80',
          'kg',
        ),
        0,
      );
      await DerivedTargetGraphService(
        store,
      ).publish(DerivedTargetGraph.fromJson(_graph()), 0);
      final training = StoredTrainingService(store);
      final session = await training.start(
        'unresolved-plan',
        definition().id,
        1,
        instant(3),
        derivedPlan: _ref,
      );
      final reviewed = jsonObject(
        (await DerivedWorkoutPreview(
          store,
        ).sessionStatus(session.id))['comparison'],
        'comparison',
      )['currentPreview'];
      await mass.delete('m', 1, confirm: true);
      final before = canonicalJson((await store.archive()).toJson());
      try {
        await training.refreshPlan(
          session.id,
          session.contentVersion,
          expectedPreview: reviewed,
          confirm: true,
        );
        throw StateError('Expected stale preview conflict.');
      } on BodyTmiException catch (error) {
        equal(error.code, 'conflict');
      }
      await expectLater(
        _refreshPlan(store, session.id, session.contentVersion, confirm: true),
        throwsA(isA<BodyTmiException>()),
      );
      equal(canonicalJson((await store.archive()).toJson()), before);
    }),
  );

  test(
    'body mass plan rejects missing mapped values but permits unused unresolved sources',
    () => withStore((store, _) async {
      final graphs = DerivedTargetGraphService(store);
      final training = StoredTrainingService(store);
      await graphs.publish(DerivedTargetGraph.fromJson(_graph()), 0);
      await expectLater(
        training.start(
          'missing',
          definition().id,
          1,
          instant(3),
          derivedPlan: _ref,
        ),
        throwsA(isA<BodyTmiException>()),
      );
      equal((await store.sessions()).length, 0);
      await graphs.publish(
        DerivedTargetGraph.fromJson(_graph(unused: true)),
        1,
      );
      final session = await training.start(
        'unused',
        definition().id,
        1,
        instant(3),
        derivedPlan: const DerivedPlanRef('mass-graph', 2, 'mass-plan'),
      );
      equal(session.sets.first.suggested['mass']!.value.toString(), '80');
      equal(
        session.derivedPlanInput!.bodyMassSources['body-source']!.length,
        0,
      );
      equal((await store.archive()).sessions.length, 1);
    }),
  );
  test(
    'body mass derived sessions reject forged inputs and prior capability labels',
    () => withStore((store, dir) async {
      final mass = StoredBodyMassService(store);
      await mass.save(
        _observation(
          'm1',
          'clothed-training',
          '2026-10-01T08:00:00Z',
          '80',
          'kg',
        ),
        0,
      );
      await DerivedTargetGraphService(
        store,
      ).publish(DerivedTargetGraph.fromJson(_graph()), 0);
      final session = await StoredTrainingService(
        store,
      ).start('session', definition().id, 1, instant(3), derivedPlan: _ref);
      final forged = copyJson(session.toJson());
      final inputs = jsonObject(
        jsonObject(forged['derivedPlanInput'], 'input')['bodyMassSources'],
        'sources',
      );
      final m = jsonObject(
        (inputs['body-source']! as List<Object?>).single,
        'measurement',
      );
      m['mass'] = {'value': '81', 'unit': 'kg'};
      rejects(() => sessionFromJson(forged));
      final archive = await store.archive();
      final doc = copyJson(archive.toJson());
      final record = jsonObject(
        (doc['bodyMass']! as List<Object?>).single,
        'record',
      );
      final measurement = jsonObject(record['measurement'], 'measurement');
      measurement['mass'] = {'value': '81', 'unit': 'kg'};
      rejects(() => TrainingArchive.fromJson(doc));
      final path = '$dir/export.json';
      await LogicalArchiveFiles.export(archive, path);
      final envelope =
          jsonDecode(await File(path).readAsString()) as Map<String, Object?>;
      envelope['format'] = 'bodytmi-logical-export/29';
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
      final legacy = '$dir/old.json';
      await File(legacy).writeAsString(jsonEncode(envelope));
      await expectLater(
        LogicalArchiveFiles.prepare(legacy),
        throwsA(isA<BodyTmiException>()),
      );
      final snapshot = '$dir/snapshot.sqlite';
      await store.snapshot(snapshot);
      equal(NativeBackup.validateDatabase(snapshot), 64);
      final db = sqlite3.open(snapshot);
      db.execute('DROP TABLE IF EXISTS repeat_checkpoints');
      db.execute('DROP TABLE IF EXISTS window_checkpoints');
      db.execute('DROP TABLE IF EXISTS progression_reconciliations');
      db.execute('DROP TABLE IF EXISTS lever_link_revisions');
      db.execute('DROP TABLE IF EXISTS shared_lever_applications');
      db.execute('DROP TABLE IF EXISTS link_retirement_anchors');
      db.execute('DROP TABLE IF EXISTS program_upgrade_receipts');
      db.execute('DROP TABLE IF EXISTS exercise_revisions');
      db.execute('DROP TABLE IF EXISTS implementation_revisions');
      db.execute('DROP TABLE IF EXISTS equipment_revisions');
      db.execute('DROP TABLE IF EXISTS gym_revisions');
      db.execute('DROP TABLE IF EXISTS equipment_instance_revisions');
      db.execute('DROP TABLE IF EXISTS imported_sessions');
      db.userVersion = 29;
      db.close();
      rejects(() => NativeBackup.validateDatabase(snapshot));
    }),
  );
  test(
    'derived body mass sessions isolate run ownership while using explicit measurement context',
    () => withStore((store, _) async {
      await StoredBodyMassService(store).save(
        _observation(
          'm1',
          'clothed-training',
          '2026-10-01T08:00:00Z',
          '80',
          'kg',
        ),
        0,
      );
      await DerivedTargetGraphService(
        store,
      ).publish(DerivedTargetGraph.fromJson(_graph()), 0);
      final programs = ProgramService(store);
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
      }
      final a = await programs.start(
        'strength',
        1,
        'strength-session',
        instant(3),
        derivedPlan: _ref,
      );
      final b = await programs.start(
        'cardio',
        1,
        'cardio-session',
        instant(3),
        derivedPlan: _ref,
      );
      final aScope = jsonObject(
        jsonObject(
          jsonObject(
            a.derivedPlanInput!.snapshot['preview'],
            'preview',
          )['graphResolution'],
          'graph',
        )['historyScope'],
        'scope',
      );
      final bScope = jsonObject(
        jsonObject(
          jsonObject(
            b.derivedPlanInput!.snapshot['preview'],
            'preview',
          )['graphResolution'],
          'graph',
        )['historyScope'],
        'scope',
      );
      equal(aScope['runId'], 'strength');
      equal(bScope['runId'], 'cardio');
      equal(a.sets.first.suggested['mass']!.value.toString(), '64');
      equal(b.sets.first.suggested['mass']!.value.toString(), '64');
      equal((await store.archive()).sessions.length, 2);
    }),
  );
  test(
    'derived body mass honors a pinned cutoff and preserves offset quantities',
    () => withStore((store, _) async {
      final mass = StoredBodyMassService(store);
      await mass.save(
        _observation(
          'm1',
          'clothed-training',
          '2026-10-01T08:00:00+02:00',
          '200',
          'lb',
        ),
        0,
      );
      await mass.save(
        _observation(
          'm2',
          'clothed-training',
          '2026-10-02T08:00:00Z',
          '90',
          'kg',
        ),
        0,
      );
      final graph = _graph();
      jsonObject(
        jsonObject(graph['bindings'], 'bindings')['body-source'],
        'source',
      )['asOf'] = '2026-10-01T12:00:00Z';
      await DerivedTargetGraphService(
        store,
      ).publish(DerivedTargetGraph.fromJson(graph), 0);
      final session = await StoredTrainingService(
        store,
      ).start('fixed', definition().id, 1, instant(3), derivedPlan: _ref);
      equal(
        session.sets.first.suggested['mass']!.value.toString(),
        '72.5747792',
      );
      final sources = session.derivedPlanInput!.bodyMassSources['body-source']!;
      equal(sources.length, 1);
      equal(sources.single.id, 'm1');
      equal(sources.single.mass.enteredUnit, Unit.lb);
      equal((await store.archive()).sessions.length, 1);
    }),
  );

  test(
    'v29 manual derived sessions migrate without changing snapshots',
    () => withStore((store, dir) async {
      final graph = _graph(unused: true);
      // Remove the unused body node so this is a genuine v29 manual-only snapshot.
      final nodes = graph['nodes']! as List<Object?>;
      nodes.removeWhere((n) => (n as Map<String, Object?>)['id'] == 'body');
      jsonObject(graph['bindings'], 'bindings').remove('body-source');
      await DerivedTargetGraphService(
        store,
      ).publish(DerivedTargetGraph.fromJson(graph), 0);
      final session = await StoredTrainingService(
        store,
      ).start('manual', definition().id, 1, instant(3), derivedPlan: _ref);
      final before = canonicalJson(session.toJson());
      final logical = '$dir/current.json';
      await LogicalArchiveFiles.export(await store.archive(), logical);
      final envelope =
          jsonDecode(await File(logical).readAsString())
              as Map<String, Object?>;
      envelope['format'] = 'bodytmi-logical-export/29';
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
      final oldLogical = '$dir/v29.json';
      await File(oldLogical).writeAsString(jsonEncode(envelope));
      final prepared = await LogicalArchiveFiles.prepare(oldLogical);
      try {
        equal(canonicalJson(prepared.archive.sessions.single.toJson()), before);
      } finally {
        await prepared.close();
      }
      final extraField = copyJson(envelope);
      final logicalSessions =
          jsonObject(extraField['data'], 'data')['sessions']! as List<Object?>;
      final legacySession = jsonObject(logicalSessions.single, 'session');
      jsonObject(
        legacySession['derivedPlanInput'],
        'derived plan input',
      )['bodyMassSources'] = <String, Object?>{};
      final invalidLogical = '$dir/forged-v29.json';
      await File(invalidLogical).writeAsString(jsonEncode(extraField));
      await expectLater(
        LogicalArchiveFiles.prepare(invalidLogical),
        throwsA(isA<BodyTmiException>()),
      );
      final forgedPath = '$dir/forged-v29.sqlite';
      await store.snapshot(forgedPath);
      final forgedDb = sqlite3.open(forgedPath);
      final forgedSession = copyJson(session.toJson());
      jsonObject(
        forgedSession['derivedPlanInput'],
        'input',
      )['bodyMassSources'] = <String, Object?>{};
      forgedDb.execute('UPDATE sessions SET snapshot = ? WHERE id = ?', [
        jsonEncode(forgedSession),
        session.id,
      ]);
      forgedDb.execute('DROP TABLE IF EXISTS repeat_checkpoints');
      forgedDb.execute('DROP TABLE IF EXISTS window_checkpoints');
      forgedDb.execute('DROP TABLE IF EXISTS progression_reconciliations');
      forgedDb.execute('DROP TABLE IF EXISTS lever_link_revisions');
      forgedDb.execute('DROP TABLE IF EXISTS shared_lever_applications');
      forgedDb.execute('DROP TABLE IF EXISTS link_retirement_anchors');
      forgedDb.execute('DROP TABLE IF EXISTS program_upgrade_receipts');
      forgedDb.execute('DROP TABLE IF EXISTS exercise_revisions');
      forgedDb.execute('DROP TABLE IF EXISTS implementation_revisions');
      forgedDb.execute('DROP TABLE IF EXISTS equipment_revisions');
      forgedDb.execute('DROP TABLE IF EXISTS gym_revisions');
      forgedDb.execute('DROP TABLE IF EXISTS equipment_instance_revisions');
      forgedDb.execute('DROP TABLE IF EXISTS imported_sessions');
      forgedDb.userVersion = 29;
      forgedDb.close();
      rejects(() => NativeBackup.validateDatabase(forgedPath));
      final path = '$dir/v29.sqlite';
      await store.snapshot(path);
      await store.close();
      final db = sqlite3.open(path);
      db.execute('DROP TABLE IF EXISTS repeat_checkpoints');
      db.execute('DROP TABLE IF EXISTS window_checkpoints');
      db.execute('DROP TABLE IF EXISTS progression_reconciliations');
      db.execute('DROP TABLE IF EXISTS lever_link_revisions');
      db.execute('DROP TABLE IF EXISTS shared_lever_applications');
      db.execute('DROP TABLE IF EXISTS link_retirement_anchors');
      db.execute('DROP TABLE IF EXISTS program_upgrade_receipts');
      db.execute('DROP TABLE IF EXISTS exercise_revisions');
      db.execute('DROP TABLE IF EXISTS implementation_revisions');
      db.execute('DROP TABLE IF EXISTS equipment_revisions');
      db.execute('DROP TABLE IF EXISTS gym_revisions');
      db.execute('DROP TABLE IF EXISTS equipment_instance_revisions');
      db.execute('DROP TABLE IF EXISTS imported_sessions');
      db.userVersion = 29;
      db.close();
      equal(NativeBackup.validateDatabase(path), 29);
      final migrated = await TrainingStore.open(path);
      try {
        equal(
          canonicalJson(
            (await StoredTrainingService(migrated).session('manual')).toJson(),
          ),
          before,
        );
      } finally {
        await migrated.close();
      }
    }),
  );
}
