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
  bool maxEffort = true,
  bool emptyTargets = false,
}) => WorkoutDefinition.fromJson({
  'id': 'max-effort',
  'name': 'Explicit max-effort repetitions',
  'slots': [
    {
      'id': 'movement',
      'exercise': 'custom',
      'implementation': 'custom',
      'targets': emptyTargets
          ? <String, Object?>{}
          : {
              'mass': {'value': '10', 'unit': 'kg'},
              'reps': {'value': '6', 'unit': 'rep'},
              'duration': {'value': '10', 'unit': 's'},
            },
      if (!emptyTargets) 'prefill': ['reps'],
    },
  ],
  'plan': {
    'id': 'practice',
    'type': 'sequence',
    'children': [
      if (!emptyTargets)
        {
          'id': 'fixed',
          'type': 'repeat',
          'count': 2,
          'child': {'id': 'set', 'type': 'effort', 'slot': 'movement'},
        },
      {
        'id': 'last',
        'type': 'effort',
        'slot': 'movement',
        if (maxEffort)
          'objectives': {
            'reps': {'mode': 'maxEffort', 'unit': 'rep'},
          },
      },
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
TrainingSession _finish(TrainingSession s, {String reps = '12'}) {
  for (final set in s.sets) {
    s = const TrainingService().complete(
      s,
      set.id,
      set.maxEffortMetrics.isEmpty ? {} : {'reps': Quantity(reps, 'rep')},
      acceptSuggested: true,
    );
  }
  return s.finish(s.startedAt.add(const Duration(hours: 1)));
}

Map<String, Object?> _rule() => {
  'metric': 'reps',
  'minimum': {'value': '18', 'unit': 'rep'},
  'threshold': {'value': '6', 'unit': 'rep'},
  'aggregation': {'mode': 'last'},
  'failureAggregation': {'mode': 'total'},
  'increments': {
    'mass': {'value': '1', 'unit': 'kg'},
  },
  'deloadAfter': 1,
  'deloadMetrics': ['mass'],
  'incrementBands': {
    'aggregation': {'mode': 'last'},
    'bands': [
      {
        'id': 'bonus',
        'threshold': {'value': '12', 'unit': 'rep'},
        'increments': {
          'mass': {'value': '2', 'unit': 'kg'},
        },
      },
    ],
  },
};
Future<void> _withStore(
  Future<void> Function(TrainingStore, String) action,
) async {
  final dir = await Directory.systemTemp.createTemp('bodytmi-max-effort-');
  final store = await TrainingStore.open('${dir.path}/db.sqlite');
  try {
    await StoredTrainingService(store).publish(_definition(), 0);
    await action(store, dir.path);
  } finally {
    await store.close();
    await dir.delete(recursive: true);
  }
}

Future<TrainingSession> _storedFinish(
  TrainingStore store,
  String id,
  int day, {
  String reps = '12',
}) async {
  final service = StoredTrainingService(store);
  final s = await service.start(id, 'max-effort', 1, instant(day));
  return service.edit(id, s.contentVersion, (s) => _finish(s, reps: reps));
}

Future<ProgressionDecision> _propose(TrainingStore store, String id) =>
    StoredProgressionService(
      store,
    ).propose(id, 'movement', _rule(), ruleType: 'threshold');
Future<void> _fails(Future<Object?> action) =>
    expectLater(action, throwsA(isA<BodyTmiException>()));
DateTime _at(int day) => instant(day).add(const Duration(hours: 2));

void maxEffortTests() {
  test(
    'max-effort objectives remove numeric target and require an explicit count including zero',
    () {
      final s = _start();
      final last = s.sets.last;
      check(last.maxEffortMetrics.contains('reps'));
      check(!last.suggested.containsKey('reps'));
      equal(last.suggested['mass']!.value.toString(), '10');
      rejects(
        () => const TrainingService().complete(
          s,
          last.id,
          {},
          acceptSuggested: true,
        ),
      );
      rejects(
        () => const TrainingService().complete(s, last.id, {
          'reps': Quantity('1', 's'),
        }, acceptSuggested: true),
      );
      final done = const TrainingService().complete(s, last.id, {
        'reps': Quantity('0', 'rep'),
      }, acceptSuggested: true);
      equal(done.sets.last.actuals['reps']!.value.toString(), '0');
      equal(done.sets.last.actuals['mass']!.value.toString(), '10');
      check(done.sets.last.maxEffortMetrics.contains('reps'));
      final skipped = const TrainingService().skip(
        done,
        last.id,
        confirm: true,
      );
      check(skipped.sets.last.actuals.isEmpty);
      check(skipped.sets.last.maxEffortMetrics.contains('reps'));
    },
  );
  test(
    'max-effort objectives permit an otherwise targetless bodyweight effort and display planned and observed status',
    () {
      final s = _start(
        revision: WorkoutRevision.publish(_definition(emptyTargets: true)),
      );
      check(s.sets.single.suggested.isEmpty);
      rejects(
        () => const TrainingService().complete(
          s,
          s.sets.single.id,
          {},
          acceptSuggested: true,
        ),
      );
      final planned = const TrainingAnalytics().summary(
        s,
        sumMetrics: ['reps'],
      );
      equal(
        jsonObject(planned['policy'], 'policy')['id'],
        'bodytmi-session-summary/2',
      );
      final plannedMetric = jsonObject(
        jsonObject(jsonList(planned, 'sets').single, 'set')['metrics'],
        'metrics',
      )['reps'];
      equal(jsonObject(plannedMetric, 'metric')['relation'], 'unobserved');
      equal(
        jsonObject(jsonList(planned, 'totals').single, 'total')['planned'],
        1,
      );
      final completed = _finish(s, reps: '0');
      final report = const TrainingAnalytics().summary(
        completed,
        sumMetrics: ['reps'],
      );
      final metric = jsonObject(
        jsonObject(jsonList(report, 'sets').single, 'set')['metrics'],
        'metrics',
      )['reps'];
      equal(jsonObject(metric, 'metric')['relation'], 'observed');
      equal(jsonObject(metric, 'metric')['target'], null);
      equal(
        jsonObject(jsonList(report, 'totals').single, 'total')['value'],
        '0',
      );
      final series = const TrainingAnalytics().series([
        completed,
      ], metric: 'reps');
      equal(
        jsonObject(series['policy'], 'policy')['id'],
        'bodytmi-history-series/2',
      );
      final records = const ContextualRecords().evaluate(
        [completed],
        metric: 'reps',
        direction: 'higher',
      );
      equal(
        jsonObject(records['policy'], 'policy')['id'],
        'bodytmi-contextual-records/3',
      );
      final point = jsonObject(
        jsonList(
          jsonObject(jsonList(series, 'series').single, 'series'),
          'points',
        ).single,
        'point',
      );
      equal(point['relation'], 'observed');
      equal(point['target'], null);
      jsonEqual(point['objective'], {'mode': 'maxEffort', 'unit': 'rep'});
    },
  );
  test(
    'max-effort objectives validate declarations and cannot be mixed with an authored target for the same occurrence',
    () {
      final raw = _definition().toJson();
      for (final objectives in <Object?>[
        null,
        <String, Object?>{},
        {
          'reps': {'mode': 'maxEffort'},
        },
        {
          'reps': {'mode': 'maxEffort', 'unit': 's'},
        },
        {
          'reps': {'mode': 'unknown', 'unit': 'rep'},
        },
        {
          'reps': {'mode': 'maxEffort', 'unit': 'rep', 'unknown': true},
        },
        {
          'bad key': {'mode': 'maxEffort', 'unit': 'rep'},
        },
      ]) {
        final copy = copyJson(raw);
        final node = jsonObject(
          jsonList(jsonObject(copy['plan'], 'plan'), 'children').last,
          'effort',
        );
        node['objectives'] = objectives;
        rejects(() => WorkoutDefinition.fromJson(copy));
      }
      final both = copyJson(raw);
      final node = jsonObject(
        jsonList(jsonObject(both['plan'], 'plan'), 'children').last,
        'effort',
      );
      node['targets'] = <String, Object?>{};
      rejects(() => WorkoutDefinition.fromJson(both));
      node['targets'] = {
        'reps': {'value': '10', 'unit': 'rep'},
      };
      rejects(() => WorkoutDefinition.fromJson(both));
      final wrong = copyJson(raw);
      final slot = jsonObject(jsonList(wrong, 'slots').single, 'slot');
      jsonObject(slot['targets'], 'targets')['reps'] = {
        'value': '5',
        'unit': 's',
      };
      rejects(() => WorkoutDefinition.fromJson(wrong));
      rejects(
        () => WorkoutDefinition.fromJson(
          _definition(emptyTargets: true, maxEffort: false).toJson(),
        ),
      );
    },
  );
  test(
    'max-effort objectives pin occurrence identity across codec corrections and reject forged snapshot modes or suggestions',
    () {
      final s = _finish(_start());
      equal(
        canonicalJson(sessionFromJson(s.toJson()).toJson()),
        canonicalJson(s.toJson()),
      );
      final old = _start(
        revision: WorkoutRevision.publish(_definition(maxEffort: false)),
      );
      equal(
        s.sets.map((x) => x.id).join(','),
        old.sets.map((x) => x.id).join(','),
      );
      check(!old.sets.last.toJson().containsKey('objectives'));
      for (final mutate in <void Function(Map<String, Object?>)>[
        (row) => row.remove('objectives'),
        (row) => jsonObject(row['suggested'], 'suggested')['reps'] = {
          'value': '6',
          'unit': 'rep',
        },
        (row) => jsonObject(row['actuals'], 'actuals').remove('reps'),
        (row) => jsonObject(row['objectives'], 'objectives')['reps'] = {
          'mode': 'maxEffort',
          'unit': 's',
        },
      ]) {
        final forged = copyJson(s.toJson());
        mutate(jsonObject(jsonList(forged, 'sets').last, 'set'));
        rejects(() => sessionFromJson(forged));
      }
      final changed = const TrainingService().complete(s, s.sets.last.id, {
        'reps': Quantity('13', 'rep'),
      }, acceptSuggested: true);
      equal(changed.sets.last.actuals['reps']!.value.toString(), '13');
      equal(changed.sets.first.actuals['reps']!.value.toString(), '6');
    },
  );
  test(
    'max-effort objectives do not turn previous maximums into prefills for a fixed target',
    () {
      final past = _finish(_start(), reps: '20');
      final fixed = WorkoutRevision.publish(
        _definition(maxEffort: false),
        previous: past.revision,
      );
      final next = _start(id: 'next', day: 2, revision: fixed, history: [past]);
      equal(next.sets.last.suggested['reps']!.value.toString(), '6');
      check(!next.sets.last.sources.containsKey('reps'));
      equal(next.sets.first.sources['reps']!.sessionId, past.id);
      final max = _start(id: 'again', day: 2, history: [past]);
      check(!max.sets.last.suggested.containsKey('reps'));
    },
  );
  test(
    'max-effort objectives feed explicit total failure and last-set bonus rules without being suggested or becoming failures automatically',
    () => _withStore((store, dir) async {
      final s = await _storedFinish(store, 'one', 1);
      final p = await _propose(store, s.id);
      equal(p.proposal.outcome, 'advance');
      equal(p.proposal.incrementBandAssessment!.band!.id, 'bonus');
      final doubleRule = copyJson(
        jsonObject(example('double-progression')['rule'], 'rule'),
      );
      doubleRule['lower'] = {'value': '6', 'unit': 'rep'};
      rejects(
        () => ProgressionDecision(
          session: s,
          slotId: 'movement',
          rule: doubleRule,
        ).toJson(),
      );
      final service = StoredProgressionService(store);
      final accepted = await service.accept(
        s.id,
        'movement',
        p.version,
        _at(1),
      );
      final next = await StoredTrainingService(
        store,
      ).start('two', 'max-effort', 1, instant(2));
      equal(next.sets.first.suggested['mass']!.value.toString(), '12');
      equal(next.sets.last.suggested['mass']!.value.toString(), '12');
      check(next.sets.last.maxEffortMetrics.contains('reps'));
      check(!next.sets.last.suggested.containsKey('reps'));
      var corrected = await StoredTrainingService(store).edit(
        s.id,
        s.contentVersion,
        (s) => const TrainingService().complete(s, s.sets.last.id, {
          'reps': Quantity('13', 'rep'),
        }, acceptSuggested: true),
      );
      corrected = await StoredTrainingService(store).edit(
        corrected.id,
        corrected.contentVersion,
        (s) => s.finish(s.finishedAt!),
      );
      equal(
        canonicalJson((await _propose(store, s.id)).toJson()),
        canonicalJson(accepted.toJson()),
      );
      equal(
        (await service.accept(s.id, 'movement', p.version, _at(1))).sequence,
        1,
      );
      final weak = await _storedFinish(store, 'weak', 3, reps: '0');
      final failed = await _propose(store, weak.id);
      equal(failed.proposal.outcome, 'deload');
      await store.archive();
    }),
  );
  test(
    'max-effort objectives require reconciliation if a later revision changes a working set objective mode',
    () => _withStore((store, dir) async {
      final s = await _storedFinish(store, 'one', 1);
      final p = await _propose(store, s.id);
      await StoredProgressionService(
        store,
      ).accept(s.id, 'movement', p.version, _at(1));
      await StoredTrainingService(
        store,
      ).publish(_definition(maxEffort: false), 1);
      await _fails(
        StoredTrainingService(
          store,
        ).start('blocked', 'max-effort', 2, instant(2)),
      );
      check(await store.session('blocked') == null);
      await store.archive();
    }),
  );
  test(
    'max-effort objectives require explicit reps during timer review without advancing or writing actuals on failure',
    () => _withStore((store, dir) async {
      final training = StoredTrainingService(store);
      final s = await training.start('one', 'max-effort', 1, instant(1));
      final timing = TimingService(store);
      var t = await timing.start(
        'clock',
        s.id,
        s.sets.last.id,
        'duration',
        null,
        instant(1),
      );
      t = await timing.resume(t.id, t.version, 'owner', instant(1));
      t = (await timing.advance(
        t.id,
        t.version,
        'owner',
        10000,
        instant(1),
      )).activity;
      await _fails(
        timing.confirm(
          t.id,
          t.version,
          s.contentVersion,
          instant(1),
          {},
          acceptSuggested: true,
        ),
      );
      check((await training.session(s.id)).sets.last.actuals.isEmpty);
      t = await timing.confirm(t.id, t.version, s.contentVersion, instant(1), {
        'reps': Quantity('0', 'rep'),
      }, acceptSuggested: true);
      final done = await training.session(s.id);
      equal(done.sets.last.actuals['reps']!.value.toString(), '0');
      equal(done.sets.last.actuals['duration']!.value.toString(), '10');
      check(done.sets.last.timing != null);
      await store.archive();
    }),
  );
  test(
    'max-effort objectives require explicit reps in finite execution and retain stable completion receipts',
    () => _withStore((store, dir) async {
      final training = StoredTrainingService(store);
      var s = await training.start('one', 'max-effort', 1, instant(1));
      final execution = ExecutionService(store);
      var e = await execution.start('walk', s.id, instant(1));
      for (var i = 0; i < 2; i++) {
        e = await execution.step(
          e.id,
          e.version,
          s.contentVersion,
          'fixed-$i',
          instant(1),
          action: 'complete',
          acceptSuggested: true,
        );
        s = await training.session(s.id);
      }
      await _fails(
        execution.step(
          e.id,
          e.version,
          s.contentVersion,
          'last',
          instant(1),
          action: 'complete',
          acceptSuggested: true,
        ),
      );
      check((await training.session(s.id)).sets.last.actuals.isEmpty);
      final version = e.version, sessionVersion = s.contentVersion;
      e = await execution.step(
        e.id,
        version,
        sessionVersion,
        'last',
        instant(1),
        action: 'complete',
        actuals: {'reps': Quantity('12', 'rep')},
        acceptSuggested: true,
      );
      check(e.complete);
      final retry = await execution.step(
        e.id,
        version,
        sessionVersion,
        'last',
        instant(1),
        action: 'complete',
        actuals: {'reps': Quantity('12', 'rep')},
        acceptSuggested: true,
      );
      equal(canonicalJson(retry.toJson()), canonicalJson(e.toJson()));
      s = await training.session(s.id);
      equal(s.sets.last.actuals['reps']!.value.toString(), '12');
      await store.archive();
    }),
  );
  test(
    'max-effort objectives isolate bonus and failure outcomes across simultaneous program runs',
    () => _withStore((store, dir) async {
      final programs = ProgramService(store);
      await programs.publish(
        ProgramDefinition.fromJson({
          'id': 'shared',
          'name': 'Independent max effort',
          'plan': {
            'id': 'day',
            'type': 'day',
            'templateId': 'max-effort',
            'revision': 1,
          },
        }),
        0,
      );
      for (final run in ['strength', 'cardio'])
        await programs.create(run, 'shared', 1, instant(1));
      final training = StoredTrainingService(store);
      final progression = StoredProgressionService(store);
      for (final (run, reps, outcome) in [
        ('strength', '12', 'advance'),
        ('cardio', '0', 'deload'),
      ]) {
        var s = await programs.start(
          run,
          (await programs.run(run)).contentVersion,
          '$run-one',
          instant(1),
        );
        s = await training.edit(
          s.id,
          s.contentVersion,
          (s) => _finish(s, reps: reps),
        );
        final p = await _propose(store, s.id);
        equal(p.proposal.outcome, outcome);
        await progression.accept(s.id, 'movement', p.version, _at(1));
      }
      for (final (run, target) in [('strength', '12'), ('cardio', '9')]) {
        final next = await programs.start(
          run,
          (await programs.run(run)).contentVersion,
          '$run-next',
          instant(2),
        );
        equal(next.sets.last.suggested['mass']!.value.toString(), target);
        check(next.sets.last.maxEffortMetrics.contains('reps'));
        check(!next.sets.last.suggested.containsKey('reps'));
      }
      await store.archive();
    }),
  );
  test(
    'max-effort objectives reject old labels even on unused revisions and survive full logical restoration',
    () => _withStore((store, dir) async {
      final s = await _storedFinish(store, 'one', 1);
      await _propose(store, s.id);
      final before = canonicalJson((await store.archive()).toJson());
      await store.backup('$dir/native');
      await LogicalArchiveFiles.export(
        await store.archive(),
        '$dir/logical.json',
      );
      final prepared = await LogicalArchiveFiles.prepare('$dir/logical.json');
      final target = await TrainingStore.open('$dir/restored.sqlite');
      try {
        await target.restore(
          prepared.backup,
          recoveryDestination: '$dir/recovery',
          confirm: true,
        );
      } finally {
        await target.close();
        await prepared.close();
      }
      final reopened = await TrainingStore.open('$dir/restored.sqlite');
      try {
        equal(canonicalJson((await reopened.archive()).toJson()), before);
      } finally {
        await reopened.close();
      }
      final raw = jsonObject(
        jsonDecode(await File('$dir/logical.json').readAsString()),
        'logical',
      );
      raw['format'] = 'bodytmi-logical-export/24';
      raw.remove('sha256');
      raw['sha256'] = sha256
          .convert(utf8.encode(canonicalJson(raw)))
          .toString();
      await File('$dir/wrong.json').writeAsString(jsonEncode(raw));
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
      db.userVersion = 24;
      db.close();
      rejects(
        () => NativeBackup.validateDatabase('$dir/native/database.sqlite'),
      );
      final unused = TrainingArchive(
        revisions: [WorkoutRevision.publish(_definition())],
        sessions: [],
        finalizations: [],
      );
      await LogicalArchiveFiles.export(unused, '$dir/unused.json');
      final j = jsonObject(
        jsonDecode(await File('$dir/unused.json').readAsString()),
        'logical',
      );
      j['format'] = 'bodytmi-logical-export/24';
      j.remove('sha256');
      j['sha256'] = sha256.convert(utf8.encode(canonicalJson(j))).toString();
      await File('$dir/unused-old.json').writeAsString(jsonEncode(j));
      await _fails(LogicalArchiveFiles.prepare('$dir/unused-old.json'));
    }),
  );
  test(
    'max-effort objectives migrate v24 snapshots without inventing objective fields',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-max-effort-legacy-',
      );
      var store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final training = StoredTrainingService(store);
        await training.publish(_definition(maxEffort: false), 0);
        final s = await training.start('legacy', 'max-effort', 1, instant(1));
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
        old.userVersion = 24;
        old.close();
        equal(
          NativeBackup.validateDatabase('${dir.path}/old/database.sqlite'),
          24,
        );
        store = await TrainingStore.open('${dir.path}/old/database.sqlite');
        equal(canonicalJson((await store.archive()).toJson()), before);
        equal(
          (await store.backup('${dir.path}/upgraded'))['databaseSchemaVersion'],
          69,
        );
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'max-effort objectives pure and native CLI agree and reject acceptSuggested without a count',
    () => _withStore((store, dir) async {
      await store.close();
      final started = await invoke(
        ['store', 'start'],
        jsonEncode({
          'schemaVersion': 1,
          'database': '$dir/db.sqlite',
          'id': 'one',
          'templateId': 'max-effort',
          'revision': 1,
          'startedAt': instant(1).toIso8601String(),
        }),
      );
      equal(started.code, 0);
      final s = sessionFromJson(
        jsonObject(jsonDecode(started.output), 'response')['data'],
      );
      final pure = const Commands().execute('session start', {
        'schemaVersion': 1,
        'id': 'one',
        'revision': s.revision.toJson(),
        'startedAt': instant(1).toIso8601String(),
      });
      equal(canonicalJson(pure['data']), canonicalJson(s.toJson()));
      final bad = await invoke(
        ['store', 'complete'],
        jsonEncode({
          'schemaVersion': 1,
          'database': '$dir/db.sqlite',
          'id': s.id,
          'expectedVersion': s.contentVersion,
          'setId': s.sets.last.id,
          'acceptSuggested': true,
        }),
      );
      equal(bad.code, 2);
      equal(bad.output, '');
      check(!bad.error.contains('internal'));
    }),
  );
}
