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

Map<String, Object?> _q(String v, String u) => {'value': v, 'unit': u};
WorkoutDefinition _definition({
  bool typed = true,
  String maximum = '2',
  String upperUnit = 'min',
  String mode = 'range',
  bool targetless = false,
}) => WorkoutDefinition.fromJson({
  'id': 'typed-objectives',
  'name': 'Published numeric objectives',
  'slots': [
    {
      'id': 'movement',
      'exercise': 'custom',
      'implementation': 'custom',
      'targets': targetless
          ? <String, Object?>{}
          : {
              'mass': _q('10', 'kg'),
              'reps': _q('6', 'rep'),
              'duration': _q('60', 's'),
            },
      if (!targetless) 'prefill': ['reps'],
    },
  ],
  'plan': {
    'id': 'practice',
    'type': 'sequence',
    'children': [
      if (!targetless)
        {
          'id': 'warmup',
          'type': 'effort',
          'slot': 'movement',
          'role': 'warmup',
        },
      {
        'id': 'work',
        'type': 'repeat',
        'count': 2,
        'child': {
          'id': 'set',
          'type': 'effort',
          'slot': 'movement',
          if (typed)
            'objectives': {
              'duration': mode == 'observe'
                  ? {'mode': 'observe', 'unit': 's'}
                  : {
                      'mode': 'range',
                      'minimum': _q('60', 's'),
                      'maximum': _q(maximum, upperUnit),
                      'upperMeaning': 'progressionThreshold',
                    },
              if (targetless)
                'reps': {'mode': 'minimum', 'minimum': _q('6', 'rep')},
            },
        },
      },
    ],
  },
});
Map<String, Object?> _rule() => {
  'metric': 'reps',
  'minimum': _q('6', 'rep'),
  'threshold': _q('6', 'rep'),
  'increments': {'mass': _q('1', 'kg')},
};
DateTime _at(int day) => instant(day).add(const Duration(hours: 2));
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
TrainingSession _finish(TrainingSession s, {String? duration}) {
  for (final set in s.sets) {
    final actuals = <String, Quantity>{};
    if (set.criteria.containsKey('duration') &&
        !set.suggested.containsKey('duration'))
      actuals['duration'] = Quantity(duration ?? '60', 's');
    if (set.criteria.containsKey('reps') && !set.suggested.containsKey('reps'))
      actuals['reps'] = Quantity('6', 'rep');
    if (duration != null && set.role == 'work')
      actuals['duration'] = Quantity(duration, 's');
    s = const TrainingService().complete(
      s,
      set.id,
      actuals,
      acceptSuggested: true,
    );
  }
  return s.finish(s.startedAt.add(const Duration(hours: 1)));
}

Future<void> _withStore(
  Future<void> Function(TrainingStore, String) action,
) async {
  final dir = await Directory.systemTemp.createTemp(
    'bodytmi-published-objectives-',
  );
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
  String? duration,
}) async {
  final service = StoredTrainingService(store);
  final s = await service.start(id, 'typed-objectives', 1, instant(day));
  return service.edit(
    id,
    s.contentVersion,
    (s) => _finish(s, duration: duration),
  );
}

Future<ProgressionDecision> _propose(TrainingStore store, String id) =>
    StoredProgressionService(
      store,
    ).propose(id, 'movement', _rule(), ruleType: 'threshold');
Future<void> _fails(Future<Object?> action) =>
    expectLater(action, throwsA(isA<BodyTmiException>()));

void publishedObjectiveTests() {
  test(
    'published objectives pin inclusive bounds, allow overperformance and retain independently accepted numeric suggestions',
    () {
      var s = _start();
      final work = s.sets[1];
      equal(work.suggested['duration']!.value.toString(), '60');
      equal(work.criteria['duration']!.mode, 'range');
      equal(work.criteria['duration']!.upper!.value.toString(), '120');
      final planned = const TrainingAnalytics().summary(s);
      equal(
        jsonObject(planned['policy'], 'policy')['id'],
        'bodytmi-session-summary/3',
      );
      s = const TrainingService().complete(s, work.id, {
        'duration': Quantity('121', 's'),
      }, acceptSuggested: true);
      final summary = const TrainingAnalytics().summary(s);
      final metric = jsonObject(
        jsonObject(
          jsonObject(jsonList(summary, 'sets').first, 'set')['metrics'],
          'metrics',
        )['duration'],
        'duration',
      );
      equal(metric['relation'], 'above');
      equal(metric['upperReached'], true);
      equal(
        jsonObject(metric['objective'], 'objective')['upperMeaning'],
        'progressionThreshold',
      );
      equal(s.sets[1].actuals['duration']!.value.toString(), '121');
      equal(
        canonicalJson(sessionFromJson(s.toJson()).toJson()),
        canonicalJson(s.toJson()),
      );
      final accepted = const TrainingService().complete(
        _start(),
        work.id,
        {},
        acceptSuggested: true,
      );
      equal(accepted.sets[1].actuals['duration']!.value.toString(), '60');
    },
  );
  test(
    'published objectives support all explicit modes and separate simultaneous max-effort intent',
    () {
      final d = {
        'id': 'modes',
        'name': 'Modes',
        'slots': [
          {
            'id': 'm',
            'exercise': 'e',
            'implementation': 'custom',
            'targets': {
              'mass': _q('10', 'kg'),
              'reps': _q('6', 'rep'),
              'distance': _q('10', 'm'),
              'duration': _q('60', 's'),
            },
          },
        ],
        'plan': {
          'id': 'work',
          'type': 'effort',
          'slot': 'm',
          'objectives': {
            'mass': {'mode': 'exact', 'value': _q('10', 'kg')},
            'distance': {
              'mode': 'maximum',
              'maximum': _q('12', 'm'),
              'upperMeaning': 'stoppingCue',
            },
            'duration': {'mode': 'minimum', 'minimum': _q('30', 's')},
            'reps': {'mode': 'maxEffort', 'unit': 'rep'},
            'angle': {'mode': 'observe', 'unit': 'rad'},
          },
        },
      };
      var s = _start(
        revision: WorkoutRevision.publish(WorkoutDefinition.fromJson(d)),
      );
      check(s.sets.single.maxEffortMetrics.contains('reps'));
      check(!s.sets.single.suggested.containsKey('reps'));
      check(!s.sets.single.suggested.containsKey('angle'));
      rejects(
        () => const TrainingService().complete(s, s.sets.single.id, {
          'reps': Quantity('12', 'rep'),
        }, acceptSuggested: true),
      );
      s = const TrainingService().complete(s, s.sets.single.id, {
        'reps': Quantity('12', 'rep'),
        'angle': Quantity('0', 'rad'),
      }, acceptSuggested: true);
      equal(s.sets.single.actuals['angle']!.value.toString(), '0');
      equal(s.sets.single.criteria.length, 4);
      equal(
        canonicalJson(sessionFromJson(s.toJson()).toJson()),
        canonicalJson(s.toJson()),
      );
      final source = const TrainingService().assessObjectives(
        s,
        s.sets.single.id,
        {
          'reps': {'mode': 'observe', 'unit': 'rep'},
        },
      )['source'];
      equal(
        jsonObject(
          jsonObject(source, 'source')['authoredObjectives'],
          'objectives',
        ).length,
        5,
      );
    },
  );
  test(
    'published objectives on targetless slots require explicit actuals and never synthesize a bound as a suggestion',
    () {
      var s = _start(
        revision: WorkoutRevision.publish(_definition(targetless: true)),
      );
      check(s.sets.first.suggested.isEmpty);
      rejects(
        () => const TrainingService().complete(
          s,
          s.sets.first.id,
          {},
          acceptSuggested: true,
        ),
      );
      rejects(
        () => const TrainingService().complete(s, s.sets.first.id, {
          'reps': Quantity('8', 'rep'),
        }, acceptSuggested: true),
      );
      s = const TrainingService().complete(s, s.sets.first.id, {
        'reps': Quantity('5', 'rep'),
        'duration': Quantity('130', 's'),
      });
      final report = const TrainingAnalytics().summary(
        s,
        sumMetrics: ['reps', 'duration'],
      );
      final metrics = jsonObject(
        jsonObject(jsonList(report, 'sets').first, 'set')['metrics'],
        'metrics',
      );
      equal(jsonObject(metrics['reps'], 'reps')['relation'], 'below');
      equal(jsonObject(metrics['duration'], 'duration')['relation'], 'above');
      equal(jsonObject(metrics['reps'], 'reps')['target'], null);
      equal(
        canonicalJson(sessionFromJson(s.toJson()).toJson()),
        canonicalJson(s.toJson()),
      );
    },
  );
  test(
    'published objectives validate dimensions, bounds, observation conflicts and incompatible clock defaults',
    () {
      final raw = _definition().toJson();
      final broken = <Object?>[
        {
          'duration': {
            'mode': 'range',
            'minimum': _q('120', 's'),
            'maximum': _q('60', 's'),
            'upperMeaning': 'desiredCeiling',
          },
        },
        {
          'duration': {
            'mode': 'range',
            'minimum': _q('1', 'kg'),
            'maximum': _q('2', 'kg'),
            'upperMeaning': 'desiredCeiling',
          },
        },
        {
          'duration': {
            'mode': 'range',
            'minimum': _q('1', 's'),
            'maximum': _q('2', 's'),
          },
        },
        {
          'duration': {'mode': 'maxEffort', 'unit': 's'},
        },
        {
          'duration': {'mode': 'observe', 'unit': 'bad'},
        },
        <String, Object?>{},
        null,
      ];
      for (final objective in broken) {
        final copy = copyJson(raw);
        final work = jsonObject(
          jsonList(jsonObject(copy['plan'], 'plan'), 'children').last,
          'repeat',
        );
        final child = jsonObject(work['child'], 'effort');
        child['objectives'] = objective;
        rejects(() => WorkoutDefinition.fromJson(copy));
      }
      final observation = copyJson(raw);
      final slot = jsonObject(jsonList(observation, 'slots').single, 'slot');
      slot['timing'] = {'metric': 'duration'};
      final child = jsonObject(
        jsonObject(
          jsonList(jsonObject(observation['plan'], 'plan'), 'children').last,
          'repeat',
        )['child'],
        'effort',
      );
      child['objectives'] = {
        'duration': {'mode': 'observe', 'unit': 's'},
      };
      rejects(() => WorkoutDefinition.fromJson(observation));
      final conflict = copyJson(raw);
      final effort = jsonObject(
        jsonObject(
          jsonList(jsonObject(conflict['plan'], 'plan'), 'children').last,
          'repeat',
        )['child'],
        'effort',
      );
      effort['objectives'] = {
        'reps': {'mode': 'observe', 'unit': 'rep'},
      };
      effort['targets'] = {'reps': _q('8', 'rep')};
      rejects(() => WorkoutDefinition.fromJson(conflict));
    },
  );
  test(
    'published objectives preserve pinned intent through edit, skip and reject forged snapshots',
    () {
      final s = _finish(_start());
      final original = canonicalJson(s.toJson());
      equal(canonicalJson(sessionFromJson(s.toJson()).toJson()), original);
      for (final mutate in <void Function(Map<String, Object?>)>[
        (row) => row.remove('objectives'),
        (row) => jsonObject(
          jsonObject(row['objectives'], 'objectives')['duration'],
          'duration',
        )['upperMeaning'] = 'stoppingCue',
        (row) => jsonObject(row['actuals'], 'actuals').remove('duration'),
      ]) {
        final raw = copyJson(s.toJson());
        mutate(jsonObject(jsonList(raw, 'sets')[1], 'set'));
        rejects(() => sessionFromJson(raw));
      }
      final changed = const TrainingService().complete(s, s.sets[1].id, {
        'duration': Quantity('121', 's'),
      }, acceptSuggested: true);
      equal(
        changed.sets[1].criteria['duration']!.upper!.value.toString(),
        '120',
      );
      equal(changed.sets[2].actuals['duration']!.value.toString(), '60');
      final skipped = const TrainingService().skip(
        changed,
        changed.sets[1].id,
        confirm: true,
      );
      check(skipped.sets[1].criteria.containsKey('duration'));
      check(skipped.sets[1].actuals.isEmpty);
    },
  );
  test(
    'published objectives preserve opt-in history for bounded metrics and do not prefill observational metrics',
    () {
      var old = _finish(_start());
      old = const TrainingService().complete(old, old.sets[1].id, {
        'reps': Quantity('9', 'rep'),
      }, acceptSuggested: true);
      final next = _start(id: 'next', day: 2, history: [old]);
      equal(next.sets[1].suggested['reps']!.value.toString(), '9');
      equal(next.sets[1].sources['reps']!.sessionId, old.id);
      final observed = WorkoutDefinition.fromJson({
        'id': 'observe',
        'name': 'Observation',
        'slots': [
          {
            'id': 'm',
            'exercise': 'e',
            'implementation': 'custom',
            'targets': {'reps': _q('6', 'rep')},
            'prefill': ['reps'],
          },
        ],
        'plan': {
          'id': 'work',
          'type': 'effort',
          'slot': 'm',
          'objectives': {
            'reps': {'mode': 'observe', 'unit': 'rep'},
          },
        },
      });
      var prior = _start(
        id: 'old-observe',
        revision: WorkoutRevision.publish(observed),
      );
      prior = const TrainingService().complete(prior, prior.sets.single.id, {
        'reps': Quantity('20', 'rep'),
      });
      prior = prior.finish(instant(1).add(const Duration(hours: 1)));
      final fixedRaw = observed.toJson();
      jsonObject(fixedRaw['plan'], 'plan').remove('objectives');
      final fixed = WorkoutRevision.publish(
        WorkoutDefinition.fromJson(fixedRaw),
        previous: prior.revision,
      );
      final later = _start(
        id: 'fixed',
        day: 2,
        revision: fixed,
        history: [prior],
      );
      equal(later.sets.single.suggested['reps']!.value.toString(), '6');
      check(later.sets.single.sources.isEmpty);
      final again = _start(
        id: 'observe-again',
        day: 2,
        revision: prior.revision,
        history: [prior],
      );
      check(!again.sets.single.suggested.containsKey('reps'));
    },
  );
  test(
    'published objectives report per-point bounds without changing explicit threshold progression',
    () => _withStore((store, dir) async {
      final s = await _storedFinish(store, 'one', 1, duration: '121');
      final report = const TrainingAnalytics().summary(s);
      equal(
        jsonObject(report['policy'], 'policy')['id'],
        'bodytmi-session-summary/3',
      );
      final series = const TrainingAnalytics().series([s], metric: 'duration');
      equal(
        jsonObject(series['policy'], 'policy')['id'],
        'bodytmi-history-series/3',
      );
      final points = jsonList(
        jsonObject(jsonList(series, 'series').single, 'series'),
        'points',
      );
      check(points.any((p) => jsonObject(p, 'point')['relation'] == 'above'));
      check(points.any((p) => jsonObject(p, 'point')['upperReached'] == true));
      final records = const ContextualRecords().evaluate(
        [s],
        metric: 'duration',
        direction: 'higher',
      );
      equal(
        jsonObject(records['policy'], 'policy')['id'],
        'bodytmi-contextual-records/4',
      );
      final p = await _propose(store, s.id);
      equal(p.proposal.outcome, 'advance');
      await StoredProgressionService(
        store,
      ).accept(s.id, 'movement', p.version, _at(1));
      final next = await StoredTrainingService(
        store,
      ).start('next', 'typed-objectives', 1, instant(2));
      equal(next.sets.last.suggested['mass']!.value.toString(), '11');
      equal(
        next.sets.last.criteria['duration']!.upper!.value.toString(),
        '120',
      );
      await store.archive();
    }),
  );
  test(
    'published objectives require reconciliation for changed criteria but accept canonically equal unit edits',
    () => _withStore((store, dir) async {
      final service = StoredTrainingService(store);
      final s = await _storedFinish(store, 'one', 1);
      final p = await _propose(store, s.id);
      await StoredProgressionService(
        store,
      ).accept(s.id, 'movement', p.version, _at(1));
      await service.publish(_definition(maximum: '121', upperUnit: 's'), 1);
      await _fails(service.start('blocked', 'typed-objectives', 2, instant(2)));
      check(await store.session('blocked') == null);
      await service.publish(_definition(maximum: '120', upperUnit: 's'), 2);
      final next = await service.start(
        'equivalent',
        'typed-objectives',
        3,
        instant(2),
      );
      equal(next.sets.last.suggested['mass']!.value.toString(), '11');
      equal(next.sets.last.criteria['duration']!.upper!.enteredUnit, Unit.s);
      await store.archive();
    }),
  );
  test(
    'published objectives let explicit threshold rules evaluate targetless performance without inventing a target',
    () => _withStore((store, dir) async {
      final d = WorkoutDefinition.fromJson({
        'id': 'targetless-performance',
        'name': 'Range without a numeric suggestion',
        'slots': [
          {
            'id': 'movement',
            'exercise': 'custom',
            'implementation': 'custom',
            'targets': {'mass': _q('10', 'kg')},
          },
        ],
        'plan': {
          'id': 'work',
          'type': 'effort',
          'slot': 'movement',
          'objectives': {
            'reps': {
              'mode': 'range',
              'minimum': _q('6', 'rep'),
              'maximum': _q('10', 'rep'),
              'upperMeaning': 'desiredCeiling',
            },
          },
        },
      });
      final training = StoredTrainingService(store);
      await training.publish(d, 0);
      var s = await training.start(
        'targetless',
        'targetless-performance',
        1,
        instant(1),
      );
      check(!s.sets.single.suggested.containsKey('reps'));
      s = await training.edit(s.id, s.contentVersion, (s) {
        s = const TrainingService().complete(s, s.sets.single.id, {
          'reps': Quantity('12', 'rep'),
        }, acceptSuggested: true);
        return s.finish(instant(1).add(const Duration(hours: 1)));
      });
      final rule = {
        'metric': 'reps',
        'minimum': _q('6', 'rep'),
        'threshold': _q('8', 'rep'),
        'increments': {'mass': _q('1', 'kg')},
      };
      final progression = StoredProgressionService(store);
      final p = await progression.propose(
        s.id,
        'movement',
        rule,
        ruleType: 'threshold',
      );
      equal(p.proposal.outcome, 'advance');
      await progression.accept(s.id, 'movement', p.version, _at(1));
      final next = await training.start(
        'targetless-next',
        'targetless-performance',
        1,
        instant(2),
      );
      equal(next.sets.single.suggested['mass']!.value.toString(), '11');
      check(!next.sets.single.suggested.containsKey('reps'));
      equal(next.sets.single.criteria['reps']!.mode, 'range');
      await store.archive();
    }),
  );
  test(
    'published objectives reject forged progression lineage across changed authored bounds',
    () => _withStore((store, dir) async {
      final training = StoredTrainingService(store);
      final one = await _storedFinish(store, 'one', 1);
      final p = await _propose(store, one.id);
      final accepted = await StoredProgressionService(
        store,
      ).accept(one.id, 'movement', p.version, _at(1));
      final revision = await training.publish(
        _definition(maximum: '121', upperUnit: 's'),
        1,
      );
      final raw = _start(id: 'forged', day: 2, revision: revision).toJson();
      var i = 0;
      for (final item in jsonList(raw, 'sets')) {
        final row = jsonObject(item, 'set');
        if (row['role'] != 'work') continue;
        jsonObject(row['suggested'], 'suggested')['mass'] = accepted
            .nextSets[i++]['mass']!
            .toJson();
      }
      final forged = _finish(sessionFromJson(raw));
      await store.transaction(() async {
        await store.insertSession(forged);
        await store.recordFinalization(forged.id);
      });
      await _fails(_propose(store, forged.id));
      final archive = (await store.archive()).toJson();
      final fake = ProgressionDecision(
        session: forged,
        slotId: 'movement',
        rule: _rule(),
        ruleType: 'threshold',
        previousApplication: accepted.id,
        previousSequence: accepted.sequence,
        previousFailures: accepted.failedSessions,
        previousCursor: accepted.cursor,
      );
      equal(fake.proposal.outcome, 'advance');
      jsonList(archive, 'progressions').add(fake.toJson());
      rejects(() => TrainingArchive.fromJson(archive));
    }),
  );
  test(
    'published objectives and progression stay independent for simultaneous program revisions',
    () => _withStore((store, dir) async {
      await StoredTrainingService(
        store,
      ).publish(_definition(maximum: '121', upperUnit: 's'), 1);
      final programs = ProgramService(store);
      for (final revision in [1, 2])
        await programs.publish(
          ProgramDefinition.fromJson({
            'id': 'shared',
            'name': 'Independent criteria',
            'plan': {
              'id': 'day',
              'type': 'day',
              'templateId': 'typed-objectives',
              'revision': revision,
            },
          }),
          revision - 1,
        );
      for (final (run, revision) in [('strength', 1), ('cardio', 2)])
        await programs.create(run, 'shared', revision, instant(1));
      final training = StoredTrainingService(store);
      final progression = StoredProgressionService(store);
      for (final run in ['strength', 'cardio']) {
        var s = await programs.start(
          run,
          (await programs.run(run)).contentVersion,
          '$run-one',
          instant(1),
        );
        s = await training.edit(s.id, s.contentVersion, _finish);
        final p = await _propose(store, s.id);
        equal(p.proposal.outcome, 'advance');
        await progression.accept(s.id, 'movement', p.version, _at(1));
      }
      for (final (run, upper) in [('strength', '120'), ('cardio', '121')]) {
        final next = await programs.start(
          run,
          (await programs.run(run)).contentVersion,
          '$run-next',
          instant(2),
        );
        equal(next.sets.last.suggested['mass']!.value.toString(), '11');
        equal(
          next.sets.last.criteria['duration']!.upper!.value.toString(),
          upper,
        );
      }
      await store.archive();
    }),
  );
  test(
    'published objectives require explicit targetless observations during timer confirmation',
    () => _withStore((store, dir) async {
      final definition = WorkoutDefinition.fromJson({
        'id': 'timed-observation',
        'name': 'Timed observation',
        'slots': [
          {
            'id': 'm',
            'exercise': 'e',
            'implementation': 'custom',
            'targets': {'duration': _q('10', 's')},
          },
        ],
        'plan': {
          'id': 'work',
          'type': 'effort',
          'slot': 'm',
          'objectives': {
            'reps': {'mode': 'observe', 'unit': 'rep'},
          },
        },
      });
      final service = StoredTrainingService(store);
      await service.publish(definition, 0);
      final s = await service.start(
        'clock-session',
        'timed-observation',
        1,
        instant(1),
      );
      final timing = TimingService(store);
      var t = await timing.start(
        'clock',
        s.id,
        s.sets.single.id,
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
      check((await service.session(s.id)).sets.single.actuals.isEmpty);
      await timing.confirm(t.id, t.version, s.contentVersion, instant(1), {
        'reps': Quantity('0', 'rep'),
      }, acceptSuggested: true);
      final completed = await service.session(s.id);
      equal(completed.sets.single.actuals['reps']!.value.toString(), '0');
      equal(completed.sets.single.criteria['reps']!.mode, 'observe');
      await store.archive();
    }),
  );
  test(
    'published objectives restore pinned criteria and reject schema labels predating their capability',
    () => _withStore((store, dir) async {
      final s = await _storedFinish(store, 'one', 1);
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
        equal(
          (await StoredProgressionService(
            reopened,
          ).accept(s.id, 'movement', p.version, _at(1))).sequence,
          1,
        );
      } finally {
        await reopened.close();
      }
      final raw = jsonObject(
        jsonDecode(await File('$dir/logical.json').readAsString()),
        'logical',
      );
      raw['format'] = 'bodytmi-logical-export/25';
      raw.remove('sha256');
      raw['sha256'] = sha256
          .convert(utf8.encode(canonicalJson(raw)))
          .toString();
      await File('$dir/old.json').writeAsString(jsonEncode(raw));
      await _fails(LogicalArchiveFiles.prepare('$dir/old.json'));
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
      db.userVersion = 25;
      db.close();
      rejects(
        () => NativeBackup.validateDatabase('$dir/native/database.sqlite'),
      );
    }),
  );
  test(
    'published objectives migrate existing v25 max-effort data without changing its serialization',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-published-legacy-',
      );
      var store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final raw = example('max-effort-bodyweight');
        final service = StoredTrainingService(store);
        final revision = await service.publish(
          WorkoutDefinition.fromJson(raw['definition']),
          0,
        );
        var s = await service.start(
          'legacy',
          revision.definition.id,
          revision.number,
          instant(1),
        );
        s = await service.edit(s.id, s.contentVersion, (s) {
          s = const TrainingService().complete(s, s.sets.single.id, {
            'reps': Quantity('0', 'rep'),
          });
          return s.finish(instant(1).add(const Duration(hours: 1)));
        });
        final before = canonicalJson((await store.archive()).toJson());
        await store.backup('${dir.path}/old');
        await store.close();
        final db = sqlite3.open('${dir.path}/old/database.sqlite');
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
        db.userVersion = 25;
        db.close();
        equal(
          NativeBackup.validateDatabase('${dir.path}/old/database.sqlite'),
          25,
        );
        store = await TrainingStore.open('${dir.path}/old/database.sqlite');
        equal(canonicalJson((await store.archive()).toJson()), before);
        equal(
          (await store.backup('${dir.path}/upgraded'))['databaseSchemaVersion'],
          64,
        );
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'published objectives CLI retains pinned bounds and pure/stored summary parity',
    () => _withStore((store, dir) async {
      final s = await _storedFinish(store, 'one', 1, duration: '121');
      final pure = const TrainingAnalytics().summary(s);
      await store.close();
      final native = await invoke(
        ['store', 'summary'],
        jsonEncode({
          'schemaVersion': 1,
          'database': '$dir/db.sqlite',
          'id': s.id,
        }),
      );
      equal(native.code, 0);
      equal(
        canonicalJson(
          jsonObject(jsonDecode(native.output), 'response')['data'],
        ),
        canonicalJson(pure),
      );
      final definition = _definition().toJson();
      final validation = const Commands().execute('template validate', {
        'schemaVersion': 1,
        'definition': definition,
      });
      equal(canonicalJson(validation['data']), canonicalJson(definition));
    }),
  );
}
