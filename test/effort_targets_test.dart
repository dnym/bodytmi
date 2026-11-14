import 'dart:convert';
import 'dart:io';
import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart' show expectLater, throwsA, isA;
import 'cli_test.dart';
import 'fixtures.dart';
import 'support.dart';

WorkoutDefinition _definition({
  bool overrides = true,
  String heavyMass = '60',
  String heavyReps = '8',
  String warmupMass = '20',
}) => WorkoutDefinition.fromJson({
  'id': 'effort-targets',
  'name': 'Different targets in one exercise slot',
  'slots': [
    {
      'id': 'movement',
      'exercise': 'custom',
      'implementation': 'custom',
      'targets': {
        'mass': {'value': '50', 'unit': 'kg'},
        'reps': {'value': '10', 'unit': 'rep'},
        'duration': {'value': '10', 'unit': 's'},
      },
      'prefill': ['mass', 'reps'],
      'timing': {'metric': 'duration', 'nearEndMilliseconds': 2000},
    },
  ],
  'plan': {
    'id': 'practice',
    'type': 'sequence',
    'children': [
      {
        'id': 'warmup',
        'type': 'effort',
        'slot': 'movement',
        'role': 'warmup',
        if (overrides)
          'targets': {
            'mass': {'value': warmupMass, 'unit': 'kg'},
            'reps': {'value': '5', 'unit': 'rep'},
            'duration': {'value': '5', 'unit': 's'},
          },
      },
      {
        'id': 'pair',
        'type': 'repeat',
        'count': 2,
        'child': {
          'id': 'pair-work',
          'type': 'sequence',
          'children': [
            {
              'id': 'heavy',
              'type': 'effort',
              'slot': 'movement',
              if (overrides)
                'targets': {
                  'mass': {'value': heavyMass, 'unit': 'kg'},
                  'reps': {'value': heavyReps, 'unit': 'rep'},
                },
            },
            {
              'id': 'backoff',
              'type': 'effort',
              'slot': 'movement',
              if (overrides)
                'targets': {
                  'mass': {'value': '90', 'unit': 'lb'},
                  'reps': {'value': '12', 'unit': 'rep'},
                  'duration': {'value': '8', 'unit': 's'},
                },
            },
          ],
        },
      },
      {'id': 'ordinary', 'type': 'effort', 'slot': 'movement'},
    ],
  },
});
TrainingSession _start({
  String id = 'one',
  int day = 1,
  WorkoutRevision? revision,
  List<TrainingSession> history = const [],
}) => const TrainingService().start(
  sessionId: id,
  revision: revision ?? WorkoutRevision.publish(_definition()),
  startedAt: instant(day),
  history: history,
);
Map<String, Object?> _rule() => {
  'metric': 'reps',
  'minimum': {'value': '8', 'unit': 'rep'},
  'threshold': {'value': '12', 'unit': 'rep'},
  'aggregation': {'mode': 'any'},
  'increments': {
    'mass': {'value': '2', 'unit': 'kg'},
  },
};
DateTime _at(int day) => instant(day).add(const Duration(hours: 2));
Future<void> _fails(Future<Object?> action) =>
    expectLater(action, throwsA(isA<BodyTmiException>()));
Future<void> _withStore(
  Future<void> Function(TrainingStore, String) action,
) async {
  final dir = await Directory.systemTemp.createTemp('bodytmi-effort-targets-');
  final store = await TrainingStore.open('${dir.path}/db.sqlite');
  try {
    await StoredTrainingService(store).publish(_definition(), 0);
    await action(store, dir.path);
  } finally {
    await store.close();
    await dir.delete(recursive: true);
  }
}

Future<TrainingSession> _finish(
  TrainingStore store,
  String id,
  int day, {
  String? run,
}) async {
  final service = StoredTrainingService(store);
  final s = run == null
      ? await service.start(id, 'effort-targets', 1, instant(day))
      : await ProgramService(store).start(
          run,
          (await ProgramService(store).run(run)).contentVersion,
          id,
          instant(day),
        );
  return service.edit(id, s.contentVersion, finished);
}

Future<ProgressionDecision> _propose(TrainingStore store, String id) =>
    StoredProgressionService(
      store,
    ).propose(id, 'movement', _rule(), ruleType: 'threshold');

void effortTargetsTests() {
  test(
    'effort targets resolve per-occurrence values without splitting slots or changing inherited metrics and identity',
    () {
      final s = _start();
      equal(s.sets.length, 6);
      equal(s.revision.definition.slots.length, 1);
      equal(s.sets.first.role, 'warmup');
      equal(s.sets.first.suggested['mass']!.value.toString(), '20');
      equal(s.sets[1].suggested['mass']!.value.toString(), '60');
      equal(s.sets[1].suggested['duration']!.value.toString(), '10');
      equal(s.sets[2].suggested['mass']!.enteredUnit, Unit.lb);
      equal(s.sets[2].suggested['reps']!.value.toString(), '12');
      equal(s.sets[3].suggested['reps']!.value.toString(), '8');
      equal(s.sets.last.suggested['mass']!.value.toString(), '50');
      equal(
        s.sets
            .where((set) => set.role == 'work')
            .map((s) => s.ordinal)
            .join(','),
        '0,1,2,3,4',
      );
      final old = _start(
        revision: WorkoutRevision.publish(_definition(overrides: false)),
      );
      equal(
        s.sets.map((s) => s.id).join(','),
        old.sets.map((s) => s.id).join(','),
      );
      equal(
        canonicalJson(sessionFromJson(s.toJson()).toJson()),
        canonicalJson(s.toJson()),
      );
      equal(s.revision.definition.workingTargets('movement').length, 5);
      check(s.revision.definition.hasEffortTargets);
    },
  );
  test(
    'effort targets reject empty unknown incompatible and timing-invalid overrides at publication',
    () {
      final original = _definition().toJson();
      for (final targets in <Object?>[
        null,
        <String, Object?>{},
        {
          'unknown': {'value': '1', 'unit': 'rep'},
        },
        {
          'mass': {'value': '1', 'unit': 's'},
        },
        {
          'reps': {'value': '1.5', 'unit': 'rep'},
        },
        {
          'duration': {'value': '0', 'unit': 's'},
        },
        {
          'duration': {'value': '1', 'unit': 's'},
        },
      ]) {
        final raw = copyJson(original);
        final effort = jsonObject(
          jsonList(jsonObject(raw['plan'], 'plan'), 'children').first,
          'effort',
        );
        effort['targets'] = targets;
        rejects(() => WorkoutDefinition.fromJson(raw));
      }
      rejects(
        () => Activity.fromJson({
          'id': 'e',
          'type': 'effort',
          'slot': 'movement',
          'targets': <String, Object?>{},
        }),
      );
      const old = Effort('old', 'movement');
      check(old.targets.isEmpty);
      check(!old.toJson().containsKey('targets'));
      final values = {'mass': Quantity('1', 'kg')};
      final effort = Effort.withTargets('e', 'movement', 'work', values);
      values['mass'] = Quantity('2', 'kg');
      equal(effort.targets['mass']!.value.toString(), '1');
      rejects(() => effort.resolveTargets({'mass': Quantity('1', 's')}));
    },
  );
  test(
    'effort targets retain explicit entered values over history and allow other metrics to prefill by ordinal',
    () {
      var previous = finished(_start());
      for (final set in previous.sets)
        previous = const TrainingService().complete(previous, set.id, {
          'mass': Quantity('100', 'kg'),
          'reps': Quantity('9', 'rep'),
        }, acceptSuggested: true);
      final next = _start(id: 'next', day: 2, history: [previous]);
      equal(next.sets[1].suggested['mass']!.value.toString(), '60');
      equal(next.sets[1].suggested['reps']!.value.toString(), '8');
      check(next.sets[1].sources.isEmpty);
      equal(next.sets.last.suggested['mass']!.value.toString(), '100');
      equal(next.sets.last.sources['mass']!.sessionId, previous.id);
      final raw = _definition().toJson();
      final pair = jsonObject(
        jsonObject(
          jsonList(jsonObject(raw['plan'], 'plan'), 'children')[1],
          'pair',
        )['child'],
        'sequence',
      );
      jsonObject(jsonList(pair, 'children').first, 'effort')['targets'] = {
        'mass': {'value': '60', 'unit': 'kg'},
      };
      final mixed = _start(
        id: 'mixed',
        day: 3,
        revision: WorkoutRevision.publish(WorkoutDefinition.fromJson(raw)),
        history: [previous],
      );
      equal(mixed.sets[1].suggested['mass']!.value.toString(), '60');
      equal(mixed.sets[1].suggested['reps']!.value.toString(), '9');
      equal(mixed.sets[1].sources['reps']!.setId, previous.sets[1].id);
    },
  );
  test(
    'effort targets pin published revisions and keep repeated result edits skips and summaries independent',
    () {
      final r = WorkoutRevision.publish(_definition());
      var s = finished(_start(revision: r));
      final old = canonicalJson(s.toJson());
      final newer = WorkoutRevision.publish(
        _definition(heavyMass: '61'),
        previous: r,
      );
      equal(newer.number, 2);
      equal(canonicalJson(s.toJson()), old);
      s = const TrainingService().complete(s, s.sets[1].id, {
        'mass': Quantity('65', 'kg'),
      }, acceptSuggested: true);
      equal(s.sets[3].actuals['mass']!.value.toString(), '60');
      s = const TrainingService().skip(s, s.sets[2].id, confirm: true);
      equal(s.sets[4].status, SetStatus.completed);
      final report = const TrainingAnalytics().summary(s);
      final first = jsonObject(jsonList(report, 'sets').first, 'set');
      equal(
        jsonObject(
          jsonObject(
            jsonObject(first['metrics'], 'metrics')['mass'],
            'mass',
          )['target'],
          'quantity',
        )['value'],
        '60',
      );
    },
  );
  test(
    'effort targets seed unequal threshold vectors and preserve authored warmups while accepted controlled targets advance',
    () => _withStore((store, dir) async {
      final s = await _finish(store, 'one', 1);
      final p = await _propose(store, s.id);
      equal(p.proposal.outcome, 'advance');
      equal(p.sets.length, 5);
      final accepted = await StoredProgressionService(
        store,
      ).accept(s.id, 'movement', p.version, _at(1));
      equal(accepted.nextSets.first['mass']!.value.toString(), '62');
      equal(
        accepted.nextSets[1]['mass']!.compareTo(
          s.sets[2].suggested['mass']!.add(Quantity('2', 'kg')),
        ),
        0,
      );
      final next = await StoredTrainingService(
        store,
      ).start('next', 'effort-targets', 1, instant(2));
      equal(next.sets.first.suggested['mass']!.value.toString(), '20');
      for (var i = 0; i < p.sets.length; i++)
        equal(
          next.sets[i + 1].suggested['mass']!.compareTo(
            accepted.nextSets[i]['mass']!,
          ),
          0,
        );
      equal(next.sets[1].suggested['reps']!.value.toString(), '8');
      equal(next.sets[2].suggested['reps']!.value.toString(), '12');
      await store.archive();
    }),
  );
  test(
    'effort targets double progression changes every unequal objective without rewriting the authored baseline',
    () => _withStore((store, dir) async {
      final s = await _finish(store, 'one', 1);
      final rule = jsonObject(example('double-progression')['rule'], 'rule');
      final p = await StoredProgressionService(
        store,
      ).propose(s.id, 'movement', rule);
      equal(p.proposal.outcome, 'increaseObjective');
      await StoredProgressionService(
        store,
      ).accept(s.id, 'movement', p.version, _at(1));
      final next = await StoredTrainingService(
        store,
      ).start('next', 'effort-targets', 1, instant(2));
      equal(
        next.sets
            .skip(1)
            .map((s) => s.suggested['reps']!.value.toString())
            .join(','),
        '9,12,9,12,11',
      );
      equal(next.sets.first.suggested['reps']!.value.toString(), '5');
      equal(
        next.revision.definition
            .workingTargets('movement')
            .map((s) => s['reps']!.value.toString())
            .join(','),
        '8,12,8,12,10',
      );
      await store.archive();
    }),
  );
  test(
    'effort targets require reconciliation on controlled revision changes but preserve unrelated overrides',
    () => _withStore((store, dir) async {
      final service = StoredTrainingService(store);
      final s = await _finish(store, 'one', 1);
      final p = await _propose(store, s.id);
      await StoredProgressionService(
        store,
      ).accept(s.id, 'movement', p.version, _at(1));
      await service.publish(_definition(heavyMass: '61'), 1);
      await _fails(service.start('blocked', 'effort-targets', 2, instant(2)));
      check(await store.session('blocked') == null);
      await service.publish(_definition(heavyReps: '9', warmupMass: '25'), 2);
      final next = await service.start(
        'compatible',
        'effort-targets',
        3,
        instant(2),
      );
      equal(next.sets[1].suggested['mass']!.value.toString(), '62');
      equal(next.sets[1].suggested['reps']!.value.toString(), '9');
      equal(next.sets.first.suggested['mass']!.value.toString(), '25');
      // Canonical equality permits equivalent entered-unit edits of controlled overrides.
      final canonical = _definition().toJson();
      final pair = jsonObject(
        jsonObject(
          jsonList(jsonObject(canonical['plan'], 'plan'), 'children')[1],
          'pair',
        )['child'],
        'sequence',
      );
      final backoff = jsonObject(jsonList(pair, 'children').last, 'effort');
      jsonObject(backoff['targets'], 'targets')['mass'] = {
        'value': '40.82331330',
        'unit': 'kg',
      };
      await service.publish(WorkoutDefinition.fromJson(canonical), 3);
      final equalBaseline = await service.start(
        'equivalent',
        'effort-targets',
        4,
        instant(3),
      );
      equal(equalBaseline.sets[1].suggested['mass']!.value.toString(), '62');
      await store.archive();
    }),
  );
  test(
    'effort targets reject forged progression lineage even when session suggestions mimic prior accepted targets',
    () => _withStore((store, dir) async {
      final service = StoredTrainingService(store);
      final one = await _finish(store, 'one', 1);
      final p = await _propose(store, one.id);
      final accepted = await StoredProgressionService(
        store,
      ).accept(one.id, 'movement', p.version, _at(1));
      final revision = await service.publish(_definition(heavyMass: '61'), 1);
      final raw = _start(id: 'forged', day: 2, revision: revision).toJson();
      var ordinal = 0;
      for (final value in jsonList(raw, 'sets')) {
        final row = jsonObject(value, 'set');
        if (row['role'] != 'work') continue;
        jsonObject(row['suggested'], 'suggested')['mass'] = accepted
            .nextSets[ordinal++]['mass']!
            .toJson();
      }
      final forged = finished(sessionFromJson(raw));
      await store.transaction(() async {
        await store.insertSession(forged);
        await store.recordFinalization(forged.id);
      });
      await _fails(_propose(store, forged.id));
      final archive = (await store.archive()).toJson();
      final fakeDecision = ProgressionDecision(
        session: forged,
        slotId: 'movement',
        rule: _rule(),
        ruleType: 'threshold',
        previousApplication: accepted.id,
        previousSequence: accepted.sequence,
        previousFailures: accepted.failedSessions,
        previousCursor: accepted.cursor,
      );
      equal(fakeDecision.proposal.outcome, 'advance');
      jsonList(archive, 'progressions').add(fakeDecision.toJson());
      rejects(() => TrainingArchive.fromJson(archive));
    }),
  );
  test(
    'effort targets resolve slot clock defaults per occurrence without inventing results',
    () => _withStore((store, dir) async {
      final training = StoredTrainingService(store);
      final s = await training.start('one', 'effort-targets', 1, instant(1));
      final timer = TimingService(store);
      final warmup = await timer.start(
        'warmup-clock',
        s.id,
        s.sets.first.id,
        'duration',
        null,
        instant(1),
      );
      equal(warmup.plan.effortMilliseconds, 5000);
      check((await training.session(s.id)).sets.first.actuals.isEmpty);
      await timer.stop(
        warmup.id,
        warmup.version,
        instant(1),
        confirm: true,
        discard: true,
      );
      final heavy = await timer.start(
        'heavy-clock',
        s.id,
        s.sets[1].id,
        'duration',
        null,
        instant(1),
      );
      equal(heavy.plan.effortMilliseconds, 10000);
      await timer.stop(
        heavy.id,
        heavy.version,
        instant(1),
        confirm: true,
        discard: true,
      );
      final light = await timer.start(
        'backoff-clock',
        s.id,
        s.sets[2].id,
        'duration',
        null,
        instant(1),
      );
      equal(light.plan.effortMilliseconds, 8000);
      await timer.stop(
        light.id,
        light.version,
        instant(1),
        confirm: true,
        discard: true,
      );
      await store.archive();
    }),
  );
  test(
    'effort targets remain pinned to independent program runs and retries do not replay applications',
    () => _withStore((store, dir) async {
      final programs = ProgramService(store);
      await programs.publish(
        ProgramDefinition.fromJson({
          'id': 'shared',
          'name': 'Per-effort run isolation',
          'plan': {
            'id': 'day',
            'type': 'day',
            'templateId': 'effort-targets',
            'revision': 1,
          },
        }),
        0,
      );
      for (final run in ['strength', 'cardio'])
        await programs.create(run, 'shared', 1, instant(1));
      final s = await _finish(store, 'strength-one', 1, run: 'strength');
      final p = await _propose(store, s.id);
      final progression = StoredProgressionService(store);
      final accepted = await progression.accept(
        s.id,
        'movement',
        p.version,
        _at(1),
      );
      final cardio = await programs.start(
        'cardio',
        (await programs.run('cardio')).contentVersion,
        'cardio-one',
        instant(2),
      );
      equal(cardio.sets[1].suggested['mass']!.value.toString(), '60');
      final next = await programs.start(
        'strength',
        (await programs.run('strength')).contentVersion,
        'strength-next',
        instant(2),
      );
      equal(next.sets[1].suggested['mass']!.value.toString(), '62');
      equal(
        canonicalJson(
          (await progression.accept(
            s.id,
            'movement',
            p.version,
            _at(1),
          )).toJson(),
        ),
        canonicalJson(accepted.toJson()),
      );
      equal((await programs.run('strength')).cursor, 1);
      await store.archive();
    }),
  );
  test(
    'effort targets old labels reject unused revisions and full portability preserves pinned overrides and pending progression',
    () => _withStore((store, dir) async {
      final s = await _finish(store, 'one', 1);
      final p = await _propose(store, s.id);
      final before = canonicalJson((await store.archive()).toJson());
      await store.backup('$dir/native');
      await LogicalArchiveFiles.export(
        await store.archive(),
        '$dir/logical.json',
      );
      final logical = await LogicalArchiveFiles.prepare('$dir/logical.json');
      final target = await TrainingStore.open('$dir/restored.sqlite');
      try {
        await target.restore(
          logical.backup,
          recoveryDestination: '$dir/recovery',
          confirm: true,
        );
      } finally {
        await target.close();
        await logical.close();
      }
      final reopened = await TrainingStore.open('$dir/restored.sqlite');
      try {
        equal(canonicalJson((await reopened.archive()).toJson()), before);
        final receipt = await StoredProgressionService(
          reopened,
        ).accept(s.id, 'movement', p.version, _at(1));
        equal(receipt.nextSets.first['mass']!.value.toString(), '62');
      } finally {
        await reopened.close();
      }
      final invalid = jsonObject(
        jsonDecode(await File('$dir/logical.json').readAsString()),
        'logical',
      );
      invalid['format'] = 'bodytmi-logical-export/23';
      invalid.remove('sha256');
      invalid['sha256'] = sha256
          .convert(utf8.encode(canonicalJson(invalid)))
          .toString();
      await File('$dir/wrong.json').writeAsString(jsonEncode(invalid));
      await _fails(LogicalArchiveFiles.prepare('$dir/wrong.json'));
      final db = sqlite3.open('$dir/native/database.sqlite');
      db.execute('DROP TABLE derived_target_graphs');
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
      db.execute('DROP TABLE IF EXISTS block_progressions');
      db.userVersion = 23;
      db.close();
      rejects(
        () => NativeBackup.validateDatabase('$dir/native/database.sqlite'),
      );
      // Even a published revision without sessions needs the new format label.
      final empty = TrainingArchive(
        revisions: [WorkoutRevision.publish(_definition())],
        sessions: [],
        finalizations: [],
      );
      await LogicalArchiveFiles.export(empty, '$dir/unused.json');
      final unused = jsonObject(
        jsonDecode(await File('$dir/unused.json').readAsString()),
        'logical',
      );
      unused['format'] = 'bodytmi-logical-export/23';
      unused.remove('sha256');
      unused['sha256'] = sha256
          .convert(utf8.encode(canonicalJson(unused)))
          .toString();
      await File('$dir/unused-old.json').writeAsString(jsonEncode(unused));
      await _fails(LogicalArchiveFiles.prepare('$dir/unused-old.json'));
    }),
  );
  test(
    'effort targets legacy v23 revisions migrate without synthesized overrides or changed sessions',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-effort-targets-legacy-',
      );
      var store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final training = StoredTrainingService(store);
        await training.publish(_definition(overrides: false), 0);
        final s = await training.start(
          'legacy',
          'effort-targets',
          1,
          instant(1),
        );
        await training.edit(s.id, s.contentVersion, finished);
        final before = canonicalJson((await store.archive()).toJson());
        await store.backup('${dir.path}/old');
        await store.close();
        final old = sqlite3.open('${dir.path}/old/database.sqlite');
        old.execute('DROP TABLE derived_target_graphs');
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
        old.execute('DROP TABLE IF EXISTS imported_sessions');
        old.execute('DROP TABLE IF EXISTS block_progressions');
        old.userVersion = 23;
        old.close();
        equal(
          NativeBackup.validateDatabase('${dir.path}/old/database.sqlite'),
          23,
        );
        store = await TrainingStore.open('${dir.path}/old/database.sqlite');
        equal(canonicalJson((await store.archive()).toJson()), before);
        equal(
          (await store.backup('${dir.path}/upgraded'))['databaseSchemaVersion'],
          67,
        );
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'effort targets pure and native CLI preserve authored quantities and reject malformed bindings cleanly',
    () => _withStore((store, dir) async {
      await store.close();
      final request = {
        'schemaVersion': 1,
        'database': '$dir/db.sqlite',
        'id': 'one',
        'templateId': 'effort-targets',
        'revision': 1,
        'startedAt': instant(1).toIso8601String(),
      };
      final native = await invoke(['store', 'start'], jsonEncode(request));
      equal(native.code, 0);
      final stored = sessionFromJson(
        jsonObject(jsonDecode(native.output), 'response')['data'],
      );
      final pure = const Commands().execute('session start', {
        'schemaVersion': 1,
        'id': 'one',
        'revision': stored.revision.toJson(),
        'startedAt': instant(1).toIso8601String(),
      });
      equal(canonicalJson(pure['data']), canonicalJson(stored.toJson()));
      final bad = _definition().toJson();
      final effort = jsonObject(
        jsonList(jsonObject(bad['plan'], 'plan'), 'children').first,
        'effort',
      );
      effort['targets'] = {
        'unknown': {'value': '1', 'unit': 'rep'},
      };
      final invalid = await invoke([
        'template',
        'validate',
      ], jsonEncode({'schemaVersion': 1, 'definition': bad}));
      equal(invalid.code, 2);
      equal(invalid.output, '');
      check(!invalid.error.contains('internal'));
    }),
  );
}
