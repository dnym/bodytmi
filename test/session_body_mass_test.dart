import 'dart:convert';
import 'dart:io';

import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart' show expectLater, throwsA, isA;
import 'cli_test.dart';
import 'fixtures.dart';
import 'support.dart';

WorkoutDefinition _definition() {
  final j = definition().toJson();
  final slots = jsonList(j, 'slots');
  jsonObject(slots.first, 'slot')['bodyMass'] = {'context': 'clothed-training'};
  jsonObject(slots.last, 'slot')['bodyMass'] = {
    'context': 'health',
    'dailyMode': 'replace',
    'warnIfStale': false,
  };
  return WorkoutDefinition.fromJson(j);
}

BodyMassMeasurement _mass(
  String id,
  String value, {
  String context = 'clothed-training',
  int day = 1,
  int version = 1,
}) => BodyMassMeasurement.fromJson({
  'id': id,
  'context': context,
  'observedAt': instant(
    day,
  ).subtract(const Duration(hours: 1)).toIso8601String(),
  'mass': {'value': value, 'unit': 'kg'},
  'contentVersion': version,
});
Map<String, Object?> _observation(BodyMassMeasurement m) =>
    Map<String, Object?>.from(m.toJson())..remove('contentVersion');
BodyMassOverride _override(Map<String, Object?> j) =>
    BodyMassOverride.fromJson(j);
TrainingSession _start({
  List<BodyMassMeasurement>? measurements,
  Map<String, BodyMassOverride> overrides = const {},
}) => const TrainingService().start(
  sessionId: 'bound',
  revision: WorkoutRevision.publish(_definition()),
  startedAt: instant(10),
  bodyMassMeasurements:
      measurements ??
      [_mass('training', '75'), _mass('health', '70', context: 'health')],
  bodyMassOverrides: overrides,
);
Future<void> _fails(Future<Object?> action) =>
    expectLater(action, throwsA(isA<BodyTmiException>()));
Map<String, Object?> _input(
  Map<String, Object?> session, [
  String slot = 'bench-heavy',
]) =>
    jsonObject(jsonObject(session['bodyMassInputs'], 'inputs')[slot], 'input');
Future<void> _withStore(
  Future<void> Function(TrainingStore, String) action,
) async {
  final dir = await Directory.systemTemp.createTemp('bodytmi-session-mass-');
  final store = await TrainingStore.open('${dir.path}/db.sqlite');
  try {
    await action(store, dir.path);
  } finally {
    await store.close();
    await dir.delete(recursive: true);
  }
}

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

void sessionBodyMassTests() {
  test(
    'captured mass metadata remains frozen and prevents older format relabeling',
    () => _withStore((store, dir) async {
      final training = StoredTrainingService(store);
      final mass = StoredBodyMassService(store);
      await training.publish(_definition(), 0);
      final original = {
        ..._observation(_mass('training', '75')),
        'source': 'Scale',
        'notes': 'Morning',
      };
      await mass.save(original, 0);
      final session = await training.start(
        'metadata-session',
        definition().id,
        1,
        instant(10),
      );
      await mass.save(_observation(_mass('training', '75')), 1);
      final saved = await training.session(session.id);
      equal(
        saved.bodyMassInputs['bench-heavy']!.measurements.single.notes,
        'Morning',
      );
      final status = const TrainingService().bodyMassStatus(saved, [
        (await mass.show('training')).measurement,
      ]);
      equal(
        jsonObject(
          jsonObject(status['inputs'], 'inputs')['bench-heavy'],
          'input',
        )['changed'],
        true,
      );
      final archive = await store.archive();
      check(!archive.bodyMass.single.measurement.hasMetadata);
      await LogicalArchiveFiles.export(archive, '$dir/captured-metadata.json');
      final envelope =
          jsonDecode(await File('$dir/captured-metadata.json').readAsString())
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
      await File('$dir/captured-v34.json').writeAsString(jsonEncode(envelope));
      await _fails(LogicalArchiveFiles.prepare('$dir/captured-v34.json'));
      await store.snapshot('$dir/captured.sqlite');
      final db = sqlite3.open('$dir/captured.sqlite');
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
      db.userVersion = 34;
      db.close();
      rejects(() => NativeBackup.validateDatabase('$dir/captured.sqlite'));
    }),
  );

  test(
    'body mass rebinding changes only selected slots and retains original overrides',
    () {
      final original = _start(
        overrides: {
          'bench-light': _override({
            'mass': {'value': '68', 'unit': 'kg'},
          }),
        },
      );
      final inputs = [
        _mass('training', '75'),
        _mass('other', '82', day: 2),
        _mass('health', '70', context: 'health'),
      ];
      final updates = {
        'bench-heavy': _override({'measurementId': 'other'}),
        'bench-light': null,
      };
      rejects(
        () => const TrainingService().rebindBodyMass(
          original,
          inputs,
          updates,
          confirm: false,
        ),
      );
      final next = const TrainingService().rebindBodyMass(
        original,
        inputs,
        updates,
        confirm: true,
      );
      equal(next.contentVersion, original.contentVersion + 1);
      equal(
        next.bodyMassInputs['bench-heavy']!.resolution.mass!.value.toString(),
        '82',
      );
      equal(
        next.bodyMassInputs['bench-light']!.resolution.mass!.value.toString(),
        '70',
      );
      equal(next.initialBodyMassOverrides!.length, 1);
      equal(
        next.initialBodyMassOverrides!['bench-light']!.mass!.value.toString(),
        '68',
      );
      equal(
        canonicalJson(sessionFromJson(next.toJson()).toJson()),
        canonicalJson(next.toJson()),
      );
      final skipped = const TrainingService().skipRemaining(
        next,
        confirm: true,
      );
      equal(
        canonicalJson(
          skipped.initialBodyMassOverrides!.map(
            (k, v) => MapEntry(k, v.toJson()),
          ),
        ),
        canonicalJson(
          next.initialBodyMassOverrides!.map((k, v) => MapEntry(k, v.toJson())),
        ),
      );

      check(
        identical(
          const TrainingService().rebindBodyMass(
            next,
            inputs,
            updates,
            confirm: true,
          ),
          next,
        ),
      );
      rejects(
        () => const TrainingService().rebindBodyMass(next, inputs, {
          'missing': null,
        }, confirm: true),
      );
      rejects(
        () => const TrainingService().rebindBodyMass(
          next,
          inputs,
          {},
          confirm: true,
        ),
      );
      rejects(
        () => const TrainingService().rebindBodyMass(next, inputs, {
          'bench-heavy': _override({'measurementId': 'health'}),
        }, confirm: true),
      );
      final complete = const TrainingService().complete(
        next,
        next.sets.first.id,
        {},
        acceptSuggested: true,
      );
      rejects(
        () => const TrainingService().rebindBodyMass(
          complete,
          inputs,
          updates,
          confirm: true,
        ),
      );
      equal(
        canonicalJson(
          complete.initialBodyMassOverrides!['bench-light']!.toJson(),
        ),
        canonicalJson(
          original.bodyMassInputs['bench-light']!.override!.toJson(),
        ),
      );
    },
  );

  test(
    'stored rebinding preserves start retry identity through changes and completion',
    () => _withStore((store, dir) async {
      final training = StoredTrainingService(store);
      final mass = StoredBodyMassService(store);
      await training.publish(_definition(), 0);
      await mass.save(_observation(_mass('training', '75')), 0);
      await mass.save(_observation(_mass('other', '82', day: 2)), 0);
      final initial = {
        'bench-light': _override({
          'mass': {'value': '68', 'unit': 'kg'},
        }),
      };
      final started = await training.start(
        'rebind',
        definition().id,
        1,
        instant(10),
        bodyMassOverrides: initial,
      );
      final updated = await training.rebindBodyMass(
        started.id,
        started.contentVersion,
        {
          'bench-heavy': _override({'measurementId': 'other'}),
        },
        confirm: true,
      );
      equal(
        updated.bodyMassInputs['bench-heavy']!.resolution.mass!.value
            .toString(),
        '82',
      );
      final retry = await training.start(
        'rebind',
        definition().id,
        1,
        instant(10),
        bodyMassOverrides: initial,
      );
      equal(canonicalJson(retry.toJson()), canonicalJson(updated.toJson()));
      await _fails(training.start('rebind', definition().id, 1, instant(10)));
      await _fails(
        training.rebindBodyMass(started.id, started.contentVersion, {
          'bench-heavy': null,
        }, confirm: true),
      );
      final cleared = await training.rebindBodyMass(
        updated.id,
        updated.contentVersion,
        {'bench-heavy': null},
        confirm: true,
      );
      equal(
        cleared.bodyMassInputs['bench-heavy']!.resolution.mass!.value
            .toString(),
        '82',
      );
      final done = await training.edit(
        cleared.id,
        cleared.contentVersion,
        finished,
      );
      final proposal = await StoredProgressionService(store).propose(
        done.id,
        'bench-heavy',
        jsonObject(example('double-progression')['rule'], 'rule'),
      );
      check(proposal.session.initialBodyMassOverrides != null);
      await LogicalArchiveFiles.export(
        await store.archive(),
        '$dir/rebind.json',
      );
      final prepared = await LogicalArchiveFiles.prepare('$dir/rebind.json');
      try {
        await store.restore(
          prepared.backup,
          recoveryDestination: '$dir/recovery-rebind',
          confirm: true,
        );
        await store.close();
        final reopened = await TrainingStore.open('$dir/db.sqlite');
        try {
          final retry = await StoredTrainingService(reopened).start(
            'rebind',
            definition().id,
            1,
            instant(10),
            bodyMassOverrides: initial,
          );
          equal(canonicalJson(retry.toJson()), canonicalJson(done.toJson()));
        } finally {
          await reopened.close();
        }
      } finally {
        await prepared.close();
      }
    }),
  );

  test(
    'rebinding records an empty initial identity and rejects unavailable choices atomically',
    () => _withStore((store, _) async {
      final training = StoredTrainingService(store);
      final mass = StoredBodyMassService(store);
      await training.publish(_definition(), 0);
      await mass.save(_observation(_mass('training', '75')), 0);
      await mass.save(_observation(_mass('future', '90', day: 11)), 0);
      final started = await training.start(
        'plain',
        definition().id,
        1,
        instant(10),
      );
      final before = canonicalJson(started.toJson());
      await _fails(
        training.rebindBodyMass(started.id, started.contentVersion, {
          'bench-heavy': _override({'measurementId': 'future'}),
          'bench-light': _override({
            'mass': {'value': '70', 'unit': 'kg'},
          }),
        }, confirm: true),
      );
      equal(
        canonicalJson((await training.session(started.id)).toJson()),
        before,
      );
      final rebound = await training.rebindBodyMass(
        started.id,
        started.contentVersion,
        {
          'bench-heavy': _override({
            'mass': {'value': '90', 'unit': 'kg'},
          }),
        },
        confirm: true,
      );
      check(
        rebound.initialBodyMassOverrides != null &&
            rebound.initialBodyMassOverrides!.isEmpty,
      );
      final retry = await training.start(
        'plain',
        definition().id,
        1,
        instant(10),
      );
      equal(canonicalJson(retry.toJson()), canonicalJson(rebound.toJson()));
      final bad = copyJson(rebound.toJson());
      bad['initialBodyMassOverrides'] = {
        'unknown': {
          'mass': {'value': '80', 'unit': 'kg'},
        },
      };
      rejects(() => sessionFromJson(bad));
      bad['initialBodyMassOverrides'] = null;
      rejects(() => sessionFromJson(bad));
    }),
  );

  test(
    'rebound body mass survives group skip and keeps independent run start identities',
    () => _withStore((store, _) async {
      final training = StoredTrainingService(store);
      final programs = ProgramService(store);
      await training.publish(_definition(), 0);
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
        instant(10),
      );
      final b = await programs.start(
        'cardio',
        1,
        'cardio-session',
        instant(10),
      );
      final rebound = await training.rebindBodyMass(a.id, a.contentVersion, {
        'bench-heavy': _override({
          'mass': {'value': '80', 'unit': 'kg'},
        }),
      }, confirm: true);
      final retry = await programs.start('strength', 1, a.id, instant(10));
      equal(canonicalJson(retry.toJson()), canonicalJson(rebound.toJson()));
      equal(
        canonicalJson((await training.session(b.id)).toJson()),
        canonicalJson(b.toJson()),
      );
      final execution = await ExecutionService(
        store,
      ).start('walk-rebound', a.id, instant(10));
      await ExecutionService(store).skipGroup(
        execution.id,
        execution.version,
        rebound.contentVersion,
        'skip-all',
        'workout',
        instant(10),
        confirm: true,
      );
      final skipped = await training.session(a.id);
      check(
        skipped.initialBodyMassOverrides != null &&
            skipped.initialBodyMassOverrides!.isEmpty,
      );
      await training.edit(
        skipped.id,
        skipped.contentVersion,
        (s) => s.finish(instant(10)),
      );
      final retried = await programs.start('strength', 1, a.id, instant(10));
      check(retried.initialBodyMassOverrides != null);
      equal((await programs.run('strength')).cursor, 1);
      equal((await programs.run('cardio')).cursor, 0);
      await store.archive();
    }),
  );

  test(
    'v33 labels reject rebound start identities and v33 sessions migrate unchanged',
    () => _withStore((store, dir) async {
      final training = StoredTrainingService(store);
      await training.publish(_definition(), 0);
      final original = await training.start(
        'original',
        definition().id,
        1,
        instant(10),
      );
      await store.snapshot('$dir/old.sqlite');
      final old = sqlite3.open('$dir/old.sqlite');
      old.execute('DROP TABLE IF EXISTS repeat_checkpoints');
      old.execute('DROP TABLE IF EXISTS window_checkpoints');
      old.execute('DROP TABLE IF EXISTS progression_reconciliations');
      old.execute('DROP TABLE IF EXISTS lever_link_revisions');
      old.execute('DROP TABLE IF EXISTS shared_lever_applications');
      old.execute('DROP TABLE IF EXISTS link_retirement_anchors');
      old.execute('DROP TABLE IF EXISTS program_upgrade_receipts');
      old.execute('DROP TABLE IF EXISTS exercise_revisions');
      old.execute('DROP TABLE IF EXISTS implementation_revisions');
      old.execute('DROP TABLE IF EXISTS equipment_revisions');
      old.execute('DROP TABLE IF EXISTS gym_revisions');
      old.execute('DROP TABLE IF EXISTS equipment_instance_revisions');
      old.userVersion = 33;
      old.close();
      final migrated = await TrainingStore.open('$dir/old.sqlite');
      try {
        equal(
          canonicalJson(
            (await StoredTrainingService(
              migrated,
            ).session(original.id)).toJson(),
          ),
          canonicalJson(original.toJson()),
        );
      } finally {
        await migrated.close();
      }
      await training.rebindBodyMass(original.id, original.contentVersion, {
        'bench-heavy': _override({
          'mass': {'value': '80', 'unit': 'kg'},
        }),
      }, confirm: true);
      await LogicalArchiveFiles.export(
        await store.archive(),
        '$dir/rebind-version.json',
      );
      final envelope =
          jsonDecode(await File('$dir/rebind-version.json').readAsString())
              as Map<String, Object?>;
      envelope['format'] = 'bodytmi-logical-export/33';
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
      await File('$dir/rebind-v33.json').writeAsString(jsonEncode(envelope));
      await _fails(LogicalArchiveFiles.prepare('$dir/rebind-v33.json'));
      await store.snapshot('$dir/rebind.sqlite');
      equal(NativeBackup.validateDatabase('$dir/rebind.sqlite'), 61);
      final raw = sqlite3.open('$dir/rebind.sqlite');
      raw.execute('DROP TABLE IF EXISTS repeat_checkpoints');
      raw.execute('DROP TABLE IF EXISTS window_checkpoints');
      raw.execute('DROP TABLE IF EXISTS progression_reconciliations');
      raw.execute('DROP TABLE IF EXISTS lever_link_revisions');
      raw.execute('DROP TABLE IF EXISTS shared_lever_applications');
      raw.execute('DROP TABLE IF EXISTS link_retirement_anchors');
      raw.execute('DROP TABLE IF EXISTS program_upgrade_receipts');
      raw.execute('DROP TABLE IF EXISTS exercise_revisions');
      raw.execute('DROP TABLE IF EXISTS implementation_revisions');
      raw.execute('DROP TABLE IF EXISTS equipment_revisions');
      raw.execute('DROP TABLE IF EXISTS gym_revisions');
      raw.execute('DROP TABLE IF EXISTS equipment_instance_revisions');
      raw.userVersion = 33;
      raw.close();
      rejects(() => NativeBackup.validateDatabase('$dir/rebind.sqlite'));
    }),
  );

  test(
    'original measurement override remains a portable identity after rebinding',
    () => _withStore((store, _) async {
      final training = StoredTrainingService(store);
      final mass = StoredBodyMassService(store);
      await training.publish(_definition(), 0);
      await mass.save(_observation(_mass('training', '75')), 0);
      final original = await training.start(
        'selected-original',
        definition().id,
        1,
        instant(10),
        bodyMassOverrides: {
          'bench-heavy': _override({'measurementId': 'training'}),
        },
      );
      final rebound = await training.rebindBodyMass(
        original.id,
        original.contentVersion,
        {
          'bench-heavy': _override({
            'mass': {'value': '80', 'unit': 'kg'},
          }),
        },
        confirm: true,
      );
      final doc = copyJson((await store.archive()).toJson());
      jsonList(doc, 'bodyMass').clear();
      rejects(() => TrainingArchive.fromJson(doc));
      final forged = copyJson(rebound.toJson());
      forged['contentVersion'] = 1;
      rejects(() => sessionFromJson(forged));
      await mass.delete('training', 1, confirm: true);
      await store.archive();
      final retry = await training.start(
        'selected-original',
        definition().id,
        1,
        instant(10),
        bodyMassOverrides: {
          'bench-heavy': _override({'measurementId': 'training'}),
        },
      );
      equal(canonicalJson(retry.toJson()), canonicalJson(rebound.toJson()));
    }),
  );

  test(
    'explicit body mass refresh preserves cutoff, overrides and session targets',
    () {
      final original = _start(
        overrides: {
          'bench-light': _override({
            'mass': {'value': '68', 'unit': 'kg'},
          }),
        },
      );
      final inputs = [
        _mass('training', '80', version: 2),
        _mass('future', '120', day: 11),
        _mass('health', '100', context: 'health'),
      ];
      rejects(
        () => const TrainingService().refreshBodyMass(
          original,
          inputs,
          confirm: false,
        ),
      );
      final next = const TrainingService().refreshBodyMass(
        original,
        inputs,
        confirm: true,
      );
      equal(next.contentVersion, original.contentVersion + 1);
      equal(
        next.bodyMassInputs['bench-heavy']!.resolution.mass!.value.toString(),
        '80',
      );
      equal(
        next.bodyMassInputs['bench-light']!.resolution.mass!.value.toString(),
        '68',
      );
      equal(next.bodyMassInputs['bench-heavy']!.asOf, original.startedAt);
      equal(
        canonicalJson(next.sets.map((s) => s.toJson()).toList()),
        canonicalJson(original.sets.map((s) => s.toJson()).toList()),
      );
      equal(
        canonicalJson(sessionFromJson(next.toJson()).toJson()),
        canonicalJson(next.toJson()),
      );
      check(
        identical(
          const TrainingService().refreshBodyMass(next, inputs, confirm: true),
          next,
        ),
      );
      final completed = const TrainingService().complete(
        next,
        next.sets.first.id,
        {},
        acceptSuggested: true,
      );
      rejects(
        () => const TrainingService().refreshBodyMass(
          completed,
          inputs,
          confirm: true,
        ),
      );
      rejects(
        () => const TrainingService().refreshBodyMass(
          finished(next),
          inputs,
          confirm: true,
        ),
      );
    },
  );

  test(
    'stored mass refresh is transactional, versioned and survives logical restore',
    () => _withStore((store, dir) async {
      final training = StoredTrainingService(store);
      final mass = StoredBodyMassService(store);
      await training.publish(_definition(), 0);
      await mass.save(_observation(_mass('training', '75')), 0);
      final session = await training.start(
        'refresh',
        definition().id,
        1,
        instant(10),
      );
      await mass.save(_observation(_mass('training', '80')), 1);
      await mass.save(_observation(_mass('future', '120', day: 11)), 0);
      await _fails(
        training.refreshBodyMass(
          session.id,
          session.contentVersion,
          confirm: false,
        ),
      );
      await _fails(
        training.refreshBodyMass(
          session.id,
          session.contentVersion + 1,
          confirm: true,
        ),
      );
      final changed = await training.refreshBodyMass(
        session.id,
        session.contentVersion,
        confirm: true,
      );
      equal(changed.contentVersion, session.contentVersion + 1);
      equal(
        changed.bodyMassInputs['bench-heavy']!.resolution.mass!.value
            .toString(),
        '80',
      );
      final retryStart = await training.start(
        'refresh',
        definition().id,
        1,
        instant(10),
      );
      equal(
        canonicalJson(retryStart.toJson()),
        canonicalJson(changed.toJson()),
      );
      final noChange = await training.refreshBodyMass(
        changed.id,
        changed.contentVersion,
        confirm: true,
      );
      equal(noChange.contentVersion, changed.contentVersion);
      await _fails(
        training.refreshBodyMass(
          session.id,
          session.contentVersion,
          confirm: true,
        ),
      );
      await LogicalArchiveFiles.export(
        await store.archive(),
        '$dir/export-refresh.json',
      );
      final prepared = await LogicalArchiveFiles.prepare(
        '$dir/export-refresh.json',
      );
      try {
        await store.restore(
          prepared.backup,
          recoveryDestination: '$dir/recovery-refresh',
          confirm: true,
        );
        await store.close();
        final reopened = await TrainingStore.open('$dir/db.sqlite');
        try {
          equal(
            canonicalJson(
              (await StoredTrainingService(
                reopened,
              ).session(session.id)).toJson(),
            ),
            canonicalJson(changed.toJson()),
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
    'refresh leaves an independently captured derived plan unchanged',
    () => _withStore((store, _) async {
      final training = StoredTrainingService(store);
      final mass = StoredBodyMassService(store);
      await training.publish(_definition(), 0);
      await mass.save(_observation(_mass('training', '75')), 0);
      await DerivedTargetGraphService(store).publish(
        DerivedTargetGraph.fromJson({
          'id': 'mass-target',
          'nodes': [
            {'id': 'body', 'kind': 'source', 'unit': 'kg', 'sourceId': 'mass'},
            {
              'id': 'work',
              'kind': 'scale',
              'unit': 'kg',
              'input': 'body',
              'factor': '0.8',
            },
          ],
          'bindings': {
            'mass': {'kind': 'bodyMass', 'context': 'clothed-training'},
          },
          'plans': [
            {
              'id': 'plan',
              'templateId': definition().id,
              'revision': 1,
              'bindings': [
                {
                  'occurrenceId': 'workout/heavy[0]/heavy-set',
                  'metric': 'mass',
                  'nodeId': 'work',
                },
              ],
            },
          ],
        }),
        0,
      );
      final ref = const DerivedPlanRef('mass-target', 1, 'plan');
      final session = await training.start(
        'derived-refresh',
        definition().id,
        1,
        instant(10),
        derivedPlan: ref,
      );
      final before = canonicalJson(session.derivedPlanInput!.toJson());
      await mass.save(_observation(_mass('training', '80')), 1);
      final after = await training.refreshBodyMass(
        session.id,
        session.contentVersion,
        confirm: true,
      );
      equal(canonicalJson(after.derivedPlanInput!.toJson()), before);
      equal(after.sets.first.suggested['mass']!.value.toString(), '60');
      equal(
        after.bodyMassInputs['bench-heavy']!.resolution.mass!.value.toString(),
        '80',
      );
      equal(
        jsonObject(
          (await DerivedWorkoutPreview(
            store,
          ).sessionStatus(after.id))['comparison'],
          'comparison',
        )['changed'],
        true,
      );
      equal(
        canonicalJson(
          (await training.start(
            session.id,
            definition().id,
            1,
            instant(10),
            derivedPlan: ref,
          )).toJson(),
        ),
        canonicalJson(after.toJson()),
      );
      final rebound = await training.rebindBodyMass(
        after.id,
        after.contentVersion,
        {
          'bench-heavy': _override({
            'mass': {'value': '77', 'unit': 'kg'},
          }),
        },
        confirm: true,
      );
      final updatedPlan = await _refreshPlan(
        store,
        rebound.id,
        rebound.contentVersion,
        confirm: true,
      );
      equal(updatedPlan.sets.first.suggested['mass']!.value.toString(), '64');
      equal(
        updatedPlan.bodyMassInputs['bench-heavy']!.resolution.mass!.value
            .toString(),
        '77',
      );
      check(
        updatedPlan.initialBodyMassOverrides != null &&
            updatedPlan.initialBodyMassOverrides!.isEmpty,
      );
      equal(
        canonicalJson(
          (await training.start(
            session.id,
            definition().id,
            1,
            instant(10),
            derivedPlan: ref,
          )).toJson(),
        ),
        canonicalJson(updatedPlan.toJson()),
      );
      await store.archive();
    }),
  );

  test(
    'refresh changes only the selected active program session',
    () => _withStore((store, _) async {
      final training = StoredTrainingService(store);
      final mass = StoredBodyMassService(store);
      final programs = ProgramService(store);
      await training.publish(_definition(), 0);
      await mass.save(_observation(_mass('training', '75')), 0);
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
      final strength = await programs.start(
        'strength',
        1,
        'strength-session',
        instant(10),
      );
      final cardio = await programs.start(
        'cardio',
        1,
        'cardio-session',
        instant(10),
      );
      final strengthRun = (await programs.run('strength')).toJson();
      final cardioRun = (await programs.run('cardio')).toJson();
      await mass.save(_observation(_mass('training', '80')), 1);
      final refreshed = await training.refreshBodyMass(
        strength.id,
        strength.contentVersion,
        confirm: true,
      );
      equal(
        refreshed.bodyMassInputs['bench-heavy']!.resolution.mass!.value
            .toString(),
        '80',
      );
      equal(
        (await training.session(
          cardio.id,
        )).bodyMassInputs['bench-heavy']!.resolution.mass!.value.toString(),
        '75',
      );
      jsonEqual((await programs.run('strength')).toJson(), strengthRun);
      jsonEqual((await programs.run('cardio')).toJson(), cardioRun);
      final retry = await programs.start(
        'strength',
        1,
        strength.id,
        instant(10),
      );
      equal(canonicalJson(retry.toJson()), canonicalJson(refreshed.toJson()));
      await store.archive();
    }),
  );

  test(
    'stored mass refresh rejects unavailable overrides and prior timing or traversal',
    () => _withStore((store, _) async {
      final training = StoredTrainingService(store);
      final mass = StoredBodyMassService(store);
      final raw = _definition().toJson();
      final slot = jsonObject(jsonList(raw, 'slots').first, 'slot');
      jsonObject(slot['targets'], 'targets')['duration'] = {
        'value': '30',
        'unit': 's',
      };
      await training.publish(WorkoutDefinition.fromJson(raw), 0);
      await mass.save(_observation(_mass('training', '75')), 0);
      final selected = await training.start(
        'selected',
        definition().id,
        1,
        instant(10),
        bodyMassOverrides: {
          'bench-heavy': _override({'measurementId': 'training'}),
        },
      );
      await mass.delete('training', 1, confirm: true);
      await _fails(
        training.refreshBodyMass(
          selected.id,
          selected.contentVersion,
          confirm: true,
        ),
      );
      equal(
        canonicalJson((await training.session(selected.id)).toJson()),
        canonicalJson(selected.toJson()),
      );
      final traversed = await training.start(
        'traversed',
        definition().id,
        1,
        instant(10),
      );
      await ExecutionService(store).start('walk', traversed.id, instant(10));
      await _fails(
        training.rebindBodyMass(traversed.id, traversed.contentVersion, {
          'bench-heavy': _override({
            'mass': {'value': '77', 'unit': 'kg'},
          }),
        }, confirm: true),
      );
      await _fails(
        training.refreshBodyMass(
          traversed.id,
          traversed.contentVersion,
          confirm: true,
        ),
      );
      final timed = await training.start(
        'timed',
        definition().id,
        1,
        instant(10),
      );
      final timer = await TimingService(store).start(
        'clock',
        timed.id,
        timed.sets.first.id,
        'duration',
        null,
        instant(10),
      );
      await TimingService(store).stop(
        timer.id,
        timer.version,
        instant(10),
        confirm: true,
        discard: true,
      );
      await _fails(
        training.refreshBodyMass(timed.id, timed.contentVersion, confirm: true),
      );
      await _fails(
        training.rebindBodyMass(timed.id, timed.contentVersion, {
          'bench-heavy': null,
        }, confirm: true),
      );
    }),
  );

  test(
    'session body mass is explicitly selected, frozen separately from targets and retained through result edits',
    () {
      final s = _start();
      equal(s.bodyMassInputs.length, 2);
      equal(
        s.bodyMassInputs['bench-heavy']!.resolution.mass!.value.toString(),
        '75',
      );
      equal(
        s.bodyMassInputs['bench-light']!.resolution.mass!.value.toString(),
        '70',
      );
      equal(s.bodyMassInputs['bench-heavy']!.resolution.stale, true);
      equal(
        s.bodyMassInputs['bench-light']!.resolution
            .toJson()['warnings']
            .toString(),
        '[]',
      );
      equal(s.sets.first.suggested['mass']!.value.toString(), '60');
      equal(s.sets.first.actuals.isEmpty, true);
      final frozen = canonicalJson(s.bodyMassInputs['bench-heavy']!.toJson());
      final done = finished(s);
      final edited = const TrainingService().complete(
        done,
        done.sets.first.id,
        {'mass': Quantity('65', 'kg'), 'reps': Quantity('9', 'rep')},
      );
      equal(
        canonicalJson(edited.bodyMassInputs['bench-heavy']!.toJson()),
        frozen,
      );
      jsonEqual(sessionFromJson(edited.toJson()).toJson(), edited.toJson());
      final missing = _start(
        measurements: [_mass('health', '70', context: 'health')],
      );
      equal(
        missing.bodyMassInputs['bench-heavy']!.resolution.source,
        'unavailable',
      );
      equal(missing.bodyMassInputs['bench-heavy']!.resolution.mass, null);
      equal(finished(missing).status, SessionStatus.finalized);
      check(!start().toJson().containsKey('bodyMassInputs'));
    },
  );

  test(
    'session overrides select a same-context eligible weigh-in or manual mass without changing prescriptions',
    () {
      final s = _start(
        overrides: {
          'bench-heavy': _override({'measurementId': 'training'}),
          'bench-light': _override({
            'mass': {'value': '154', 'unit': 'lb'},
          }),
        },
      );
      equal(s.bodyMassInputs['bench-heavy']!.resolution.source, 'measurement');
      equal(
        s.bodyMassInputs['bench-heavy']!.measurements.single.id,
        'training',
      );
      equal(s.bodyMassInputs['bench-light']!.resolution.source, 'manual');
      equal(s.bodyMassInputs['bench-light']!.measurements.length, 0);
      equal(s.sets.last.suggested['mass']!.value.toString(), '45');
      jsonEqual(sessionFromJson(s.toJson()).toJson(), s.toJson());
      rejects(
        () => _start(
          overrides: {
            'bench-heavy': _override({'measurementId': 'health'}),
          },
        ),
      );
      rejects(
        () => _start(
          measurements: [_mass('future', '80', day: 11)],
          overrides: {
            'bench-heavy': _override({'measurementId': 'future'}),
          },
        ),
      );
      rejects(
        () => _start(
          overrides: {
            'unknown': _override({
              'mass': {'value': '70', 'unit': 'kg'},
            }),
          },
        ),
      );
      rejects(() => _override({}));
      rejects(
        () => _override({
          'mass': {'value': '0', 'unit': 'kg'},
        }),
      );
      rejects(
        () => BodyMassSelection.fromJson({
          'context': 'training',
          'staleAfterDays': -1,
        }),
      );
    },
  );

  test(
    'freshness detects edited, inserted and deleted source membership while ignoring future, other-context and unused override inputs',
    () {
      final original = [
        _mass('training', '75'),
        _mass('health', '70', context: 'health'),
      ];
      final s = _start(measurements: original);
      final binding = s.bodyMassInputs['bench-heavy']!;
      equal(binding.freshness(original)['changed'], false);
      equal(
        binding.freshness([
          ...original,
          _mass('future', '80', day: 11),
        ])['changed'],
        false,
      );
      equal(
        binding.freshness([
          ...original,
          _mass('other', '80', context: 'other'),
        ])['changed'],
        false,
      );
      equal(
        binding.freshness([_mass('training', '76'), original.last])['changed'],
        true,
      );
      equal(
        binding.freshness([
          ...original,
          _mass('backdated', '77', day: 2),
        ])['changed'],
        true,
      );
      equal(binding.freshness([original.last])['changed'], true);
      final selected = _start(
        overrides: {
          'bench-heavy': _override({'measurementId': 'training'}),
        },
      ).bodyMassInputs['bench-heavy']!;
      equal(
        selected.freshness([
          ...original,
          _mass('new', '78', day: 2),
        ])['changed'],
        false,
      );
      equal(
        selected.freshness([original.last])['reason'],
        'source_unavailable',
      );
      final manual = _start(
        overrides: {
          'bench-heavy': _override({
            'mass': {'value': '77', 'unit': 'kg'},
          }),
        },
      ).bodyMassInputs['bench-heavy']!;
      equal(manual.freshness([])['changed'], false);
      rejects(() => binding.freshness([original.first, original.first]));
      equal(binding.resolution.mass!.value.toString(), '75');
    },
  );

  test(
    'stored and program starts capture sources atomically and identity retries never re-resolve changed inputs',
    () => _withStore((store, dir) async {
      final service = StoredTrainingService(store);
      final measurements = StoredBodyMassService(store);
      await service.publish(_definition(), 0);
      await measurements.save(_observation(_mass('training', '75')), 0);
      final s = await service.start('saved', definition().id, 1, instant(10));
      await measurements.save(_observation(_mass('training', '76')), 1);
      jsonEqual(
        (await service.start(
          'saved',
          definition().id,
          1,
          instant(10),
        )).toJson(),
        s.toJson(),
      );
      final current = await service.start(
        'new',
        definition().id,
        1,
        instant(10),
      );
      equal(
        current.bodyMassInputs['bench-heavy']!.resolution.mass!.value
            .toString(),
        '76',
      );
      await _fails(
        service.edit(
          s.id,
          s.contentVersion,
          (s) => TrainingSession(
            id: s.id,
            revision: s.revision,
            startedAt: s.startedAt,
            sets: s.sets,
            bodyMassInputs: current.bodyMassInputs,
          ),
        ),
      );
      final program = ProgramDefinition.fromJson({
        'id': 'program',
        'name': 'Program',
        'plan': {
          'id': 'day',
          'type': 'day',
          'templateId': definition().id,
          'revision': 1,
        },
      });
      final programs = ProgramService(store);
      await programs.publish(program, 0);
      await programs.create('run', 'program', 1, instant(10));
      final overrides = {
        'bench-heavy': _override({'measurementId': 'training'}),
      };
      final bound = await programs.start(
        'run',
        1,
        'program-session',
        instant(10),
        bodyMassOverrides: overrides,
      );
      await measurements.delete('training', 2, confirm: true);
      jsonEqual(
        (await programs.start(
          'run',
          1,
          'program-session',
          instant(10),
          bodyMassOverrides: overrides,
        )).toJson(),
        bound.toJson(),
      );
      await _fails(programs.start('run', 1, 'program-session', instant(10)));
      await service.edit(bound.id, bound.contentVersion, finished);
      equal((await programs.run('run')).cursor, 1);
      await _fails(
        programs.start(
          'run',
          3,
          'bad',
          instant(11),
          bodyMassOverrides: overrides,
        ),
      );
      equal(await store.session('bad'), null);
      equal((await programs.run('run')).contentVersion, 3);
      equal(
        (await store.session(
          'saved',
        ))!.bodyMassInputs['bench-heavy']!.resolution.mass!.value.toString(),
        '75',
      );
      await store.archive();
    }),
  );

  test(
    'snapshot and archive validation reject forged resolution, selection, source versions, missing bindings and current-version content',
    () => _withStore((store, dir) async {
      final service = StoredTrainingService(store);
      final measurements = StoredBodyMassService(store);
      await service.publish(_definition(), 0);
      await measurements.save(_observation(_mass('training', '75')), 0);
      final s = await service.start('saved', definition().id, 1, instant(10));
      final mutations = <void Function(Map<String, Object?>)>[
        (j) => jsonObject(_input(j)['resolution'], 'resolution')['mass'] = {
          'value': '999',
          'unit': 'kg',
        },
        (j) => jsonObject(_input(j)['selection'], 'selection')['context'] =
            'other',
        (j) => _input(j)['asOf'] = instant(9).toIso8601String(),
        (j) => jsonObject(j['bodyMassInputs'], 'inputs').remove('bench-heavy'),
        (j) => jsonObject(j['bodyMassInputs'], 'inputs')['other'] = _input(j),
      ];
      for (final mutate in mutations) {
        final j = copyJson(s.toJson());
        mutate(j);
        rejects(() => sessionFromJson(j));
      }
      final archive = (await store.archive()).toJson();
      final missing = copyJson(archive);
      jsonList(missing, 'bodyMass').clear();
      rejects(() => TrainingArchive.fromJson(missing));
      final changed = copyJson(archive);
      jsonObject(
        jsonObject(
          jsonList(changed, 'bodyMass').single,
          'record',
        )['measurement'],
        'measurement',
      )['mass'] = {
        'value': '76',
        'unit': 'kg',
      };
      rejects(() => TrainingArchive.fromJson(changed));
      await measurements.save(_observation(_mass('training', '76')), 1);
      await measurements.delete('training', 2, confirm: true);
      jsonEqual(
        TrainingArchive.fromJson(
          (await store.archive()).toJson(),
        ).sessions.single.toJson(),
        s.toJson(),
      );
    }),
  );

  test(
    'numeric progression retains frozen mass inputs across measurement and result corrections',
    () => _withStore((store, dir) async {
      final training = StoredTrainingService(store);
      final mass = StoredBodyMassService(store);
      await training.publish(_definition(), 0);
      await mass.save(_observation(_mass('training', '75')), 0);
      var s = await training.start(
        'progression',
        definition().id,
        1,
        instant(10),
      );
      s = await training.edit(s.id, s.contentVersion, finished);
      final progression = StoredProgressionService(store);
      final rule = jsonObject(example('double-progression')['rule'], 'rule');
      final proposed = await progression.propose(s.id, 'bench-heavy', rule);
      await mass.save(_observation(_mass('training', '76')), 1);
      // The existing numeric preset consumes reps/external load, not body mass.
      equal(await progression.stale(proposed), false);
      await progression.accept(
        s.id,
        'bench-heavy',
        proposed.version,
        instant(10).add(const Duration(hours: 2)),
      );
      s = await training.edit(
        s.id,
        s.contentVersion,
        (s) => const TrainingService().complete(s, s.sets.first.id, {
          'mass': Quantity('60', 'kg'),
          'reps': Quantity('9', 'rep'),
        }),
      );
      final archive = (await store.archive()).toJson();
      final decision = jsonObject(
        jsonList(archive, 'progressions').single,
        'decision',
      );
      final oldSession = jsonObject(decision['session'], 'session');
      final replacement = BodyMassInputSnapshot.capture(
        selection: s.bodyMassInputs['bench-heavy']!.selection,
        asOf: s.startedAt,
        measurements: [],
        override: _override({
          'mass': {'value': '80', 'unit': 'kg'},
        }),
      );
      jsonObject(oldSession['bodyMassInputs'], 'inputs')['bench-heavy'] =
          replacement.toJson();
      rejects(() => TrainingArchive.fromJson(archive));
    }),
  );

  test(
    'body-mass session snapshots survive full native/logical restore and cannot be relabeled as older formats',
    () => _withStore((store, dir) async {
      final service = StoredTrainingService(store);
      await service.publish(_definition(), 0);
      final mass = StoredBodyMassService(store);
      await mass.save(_observation(_mass('training', '75')), 0);
      final s = await service.start('saved', definition().id, 1, instant(10));
      await service.edit(s.id, s.contentVersion, finished);
      await mass.delete('training', 1, confirm: true);
      final original = canonicalJson((await store.archive()).toJson());
      equal((await store.backup('$dir/native'))['databaseSchemaVersion'], 61);
      await LogicalArchiveFiles.export(
        await store.archive(),
        '$dir/export.json',
      );
      final logical = await LogicalArchiveFiles.prepare('$dir/export.json');
      try {
        await store.restore(
          logical.backup,
          recoveryDestination: '$dir/recovery',
          confirm: true,
        );
      } finally {
        await logical.close();
        await store.close();
      }
      final reopened = await TrainingStore.open('$dir/db.sqlite');
      try {
        equal(canonicalJson((await reopened.archive()).toJson()), original);
        equal(
          (await reopened.session(
            'saved',
          ))!.bodyMassInputs['bench-heavy']!.resolution.mass!.value.toString(),
          '75',
        );
        final native = await NativeBackup.prepare('$dir/native');
        try {
          await reopened.restore(
            native,
            recoveryDestination: '$dir/recovery2',
            confirm: true,
          );
        } finally {
          await native.close();
        }
      } finally {
        await reopened.close();
      }
      final again = await TrainingStore.open('$dir/db.sqlite');
      try {
        equal(canonicalJson((await again.archive()).toJson()), original);
      } finally {
        await again.close();
      }
      final doc = jsonObject(
        jsonDecode(await File('$dir/export.json').readAsString()),
        'export',
      )..remove('sha256');
      jsonObject(doc['data'], 'data').remove('families');
      doc['format'] = 'bodytmi-logical-export/4';
      doc['sha256'] = sha256
          .convert(utf8.encode(canonicalJson(doc)))
          .toString();
      await File('$dir/forged.json').writeAsString(jsonEncode(doc));
      await _fails(LogicalArchiveFiles.prepare('$dir/forged.json'));
      final raw = sqlite3.open('$dir/native/database.sqlite');
      try {
        raw.execute('DROP TABLE family_revisions');
        raw.execute('DROP TABLE workout_executions');
        raw.execute('DROP TABLE timing_activities');
        raw.execute('DROP TABLE derived_target_graphs');
        raw.execute('DROP TABLE IF EXISTS repeat_checkpoints');
        raw.execute('DROP TABLE IF EXISTS window_checkpoints');
        raw.execute('DROP TABLE IF EXISTS progression_reconciliations');
        raw.execute('DROP TABLE IF EXISTS lever_link_revisions');
        raw.execute('DROP TABLE IF EXISTS shared_lever_applications');
        raw.execute('DROP TABLE IF EXISTS link_retirement_anchors');
        raw.execute('DROP TABLE IF EXISTS program_upgrade_receipts');
        raw.execute('DROP TABLE IF EXISTS exercise_revisions');
        raw.execute('DROP TABLE IF EXISTS implementation_revisions');
        raw.execute('DROP TABLE IF EXISTS equipment_revisions');
        raw.execute('DROP TABLE IF EXISTS gym_revisions');
        raw.execute('DROP TABLE IF EXISTS equipment_instance_revisions');
        raw.execute('PRAGMA user_version = 4');
      } finally {
        raw.close();
      }
      rejects(
        () => NativeBackup.validateDatabase('$dir/native/database.sqlite'),
      );
    }),
  );

  test(
    'v4 databases and logical exports upgrade without changing legacy measurements or sessions',
    () => _withStore((store, dir) async {
      await StoredTrainingService(store).publish(definition(), 0);
      await StoredTrainingService(
        store,
      ).start('legacy', definition().id, 1, instant(10));
      await StoredBodyMassService(
        store,
      ).save(_observation(_mass('training', '75')), 0);
      final original = (await store.archive()).toJson();
      final doc = <String, Object?>{
        'format': 'bodytmi-logical-export/4',
        'applicationVersion': '0.1.0',
        'data': (Map<String, Object?>.from(original)
          ..remove('timers')
          ..remove('families')
          ..remove('executions')),
      };
      doc['sha256'] = sha256
          .convert(utf8.encode(canonicalJson(doc)))
          .toString();
      await File('$dir/v4.json').writeAsString(jsonEncode(doc));
      final old = await LogicalArchiveFiles.prepare('$dir/v4.json');
      try {
        jsonEqual(old.archive.toJson(), original);
      } finally {
        await old.close();
      }
      await store.close();
      final raw = sqlite3.open('$dir/db.sqlite');
      try {
        raw.execute('DROP TABLE family_revisions');
        raw.execute('DROP TABLE workout_executions');
        raw.execute('DROP TABLE timing_activities');
        raw.execute('DROP TABLE derived_target_graphs');
        raw.execute('DROP TABLE IF EXISTS repeat_checkpoints');
        raw.execute('DROP TABLE IF EXISTS window_checkpoints');
        raw.execute('DROP TABLE IF EXISTS progression_reconciliations');
        raw.execute('DROP TABLE IF EXISTS lever_link_revisions');
        raw.execute('DROP TABLE IF EXISTS shared_lever_applications');
        raw.execute('DROP TABLE IF EXISTS link_retirement_anchors');
        raw.execute('DROP TABLE IF EXISTS program_upgrade_receipts');
        raw.execute('DROP TABLE IF EXISTS exercise_revisions');
        raw.execute('DROP TABLE IF EXISTS implementation_revisions');
        raw.execute('DROP TABLE IF EXISTS equipment_revisions');
        raw.execute('DROP TABLE IF EXISTS gym_revisions');
        raw.execute('DROP TABLE IF EXISTS equipment_instance_revisions');
        raw.execute('PRAGMA user_version = 4');
      } finally {
        raw.close();
      }
      equal(
        (await NativeBackup.create(
          '$dir/db.sqlite',
          '$dir/v4-native',
        ))['databaseSchemaVersion'],
        4,
      );
      final upgraded = await TrainingStore.open('$dir/db.sqlite');
      try {
        jsonEqual((await upgraded.archive()).toJson(), original);
      } finally {
        await upgraded.close();
      }
      final check = sqlite3.open('$dir/db.sqlite');
      try {
        equal(check.userVersion, 61);
      } finally {
        check.close();
      }
    }),
  );

  test(
    'pure and stored native CLI expose matching captures and freshness without rewriting session results',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-session-mass-cli-',
      );
      try {
        Future<Object?> command(
          String command,
          Map<String, Object?> input, {
          bool stored = true,
        }) async {
          final response = await invoke(
            command.split(' '),
            jsonEncode({
              'schemaVersion': 1,
              if (stored) 'database': '${dir.path}/db.sqlite',
              ...input,
            }),
          );
          equal(response.code, 0);
          equal(response.error, '');
          return jsonObject(jsonDecode(response.output), 'response')['data'];
        }

        final rev = await command('store publish', {
          'definition': _definition().toJson(),
          'expectedRevision': 0,
        });
        final observation = _mass('training', '75');
        await command('mass record', {
          'measurement': _observation(observation),
        });
        final stored = jsonObject(
          await command('store start', {
            'id': 'same',
            'templateId': definition().id,
            'revision': 1,
            'startedAt': instant(10).toIso8601String(),
          }),
          'session',
        );
        final pure = await command('session start', {
          'id': 'same',
          'revision': rev,
          'startedAt': instant(10).toIso8601String(),
          'bodyMassMeasurements': [observation.toJson()],
        }, stored: false);
        jsonEqual(stored, pure);
        final changed = _mass('training', '76', version: 2);
        await command('mass update', {
          'measurement': _observation(changed),
          'expectedVersion': 1,
        });
        final status = await command('store mass-status', {'id': 'same'});
        jsonEqual(
          status,
          await command('session mass-status', {
            'session': pure,
            'measurements': [changed.toJson()],
          }, stored: false),
        );
        equal(
          jsonObject(
            jsonObject(
              jsonObject(status, 'status')['inputs'],
              'inputs',
            )['bench-heavy'],
            'input',
          )['changed'],
          true,
        );
        jsonEqual(await command('store show', {'id': 'same'}), stored);
        final refused = await invoke(
          ['store', 'mass-refresh'],
          jsonEncode({
            'schemaVersion': 1,
            'database': '${dir.path}/db.sqlite',
            'id': 'same',
            'expectedVersion': 1,
          }),
        );
        equal(refused.code, 2);
        equal(refused.output, '');
        final refreshed = await command('store mass-refresh', {
          'id': 'same',
          'expectedVersion': 1,
          'confirm': true,
        });
        final pureRefresh = await command('session mass-refresh', {
          'session': pure,
          'measurements': [changed.toJson()],
          'confirm': true,
        }, stored: false);
        jsonEqual(refreshed, pureRefresh);
        equal(jsonObject(refreshed, 'session')['contentVersion'], 2);
        final updates = {
          'bench-heavy': {
            'mass': {'value': '81', 'unit': 'kg'},
          },
        };
        final rebound = await command('store mass-rebind', {
          'id': 'same',
          'expectedVersion': 2,
          'bodyMassOverrides': updates,
          'confirm': true,
        });
        final pureRebind = await command('session mass-rebind', {
          'session': pureRefresh,
          'measurements': [changed.toJson()],
          'bodyMassOverrides': updates,
          'confirm': true,
        }, stored: false);
        jsonEqual(rebound, pureRebind);
        final retry = await command('store start', {
          'id': 'same',
          'templateId': definition().id,
          'revision': 1,
          'startedAt': instant(10).toIso8601String(),
        });
        jsonEqual(retry, rebound);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
