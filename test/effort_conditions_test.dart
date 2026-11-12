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

final _current = metrics({'mass': ('10', 'kg'), 'reps': ('8', 'rep')});
Map<String, Object?> _rule() => {
  'metric': 'reps',
  'minimum': {'value': '6', 'unit': 'rep'},
  'threshold': {'value': '8', 'unit': 'rep'},
  'increments': {
    'mass': {'value': '1', 'unit': 'kg'},
  },
  'resets': {
    'reps': {'value': '6', 'unit': 'rep'},
  },
  'coordination': {
    'mode': 'weighted',
    'order': ['mass', 'mass'],
  },
  'deloadAfter': 2,
  'deloadMetrics': ['mass'],
  'advancementEffort': {
    'rpe': {'scale': '0-10', 'maximum': '8'},
    'rir': {'minimum': '2'},
  },
};
SetObservations _rating({
  String rpe = '8',
  String rir = '2',
  String scale = '0-10',
  String? reason,
}) => SetObservations.fromJson({
  'rpe': {'value': rpe, 'scale': scale},
  'rir': rir,
  if (reason != null) 'terminationReason': reason,
});
ProgressionProposal _evaluate({
  Map<String, Object?>? rule,
  List<String?> reps = const ['8', '8'],
  List<SetObservations?>? ratings,
  int failures = 1,
  int cursor = 1,
}) => ThresholdRule.fromJson(rule ?? _rule()).evaluate(
  current: _current,
  results: [
    for (final r in reps) r == null ? null : metrics({'reps': (r, 'rep')}),
  ],
  observations: ratings,
  failedSessions: failures,
  cursor: cursor,
);
WorkoutDefinition _definition() => WorkoutDefinition.fromJson({
  'id': 'effort',
  'name': 'Optional explicit effort gate',
  'slots': [
    {
      'id': 'movement',
      'exercise': 'custom',
      'implementation': 'custom',
      'targets': metricsToJson(_current),
    },
  ],
  'plan': {
    'id': 'practice',
    'type': 'sequence',
    'children': [
      {'id': 'warmup', 'type': 'effort', 'slot': 'movement', 'role': 'warmup'},
      {
        'id': 'work',
        'type': 'repeat',
        'count': 2,
        'child': {'id': 'set', 'type': 'effort', 'slot': 'movement'},
      },
    ],
  },
});
TrainingSession _complete(
  TrainingSession s, {
  List<SetObservations?>? ratings,
  List<String?> reps = const ['8', '8'],
}) {
  var i = 0;
  for (final set in s.sets) {
    final work = set.role == 'work';
    final value = work ? reps[i] : '1';
    s = value == null
        ? const TrainingService().skip(s, set.id)
        : const TrainingService().complete(s, set.id, {
            'reps': Quantity(value, 'rep'),
          }, acceptSuggested: true);
    final rating = work ? (ratings == null ? _rating() : ratings[i]) : null;
    if (rating != null) s = const TrainingService().annotate(s, set.id, rating);
    if (work) i++;
  }
  return s.finish(s.startedAt.add(const Duration(hours: 1)));
}

Future<void> _withStore(
  Future<void> Function(TrainingStore, String) action,
) async {
  final dir = await Directory.systemTemp.createTemp('bodytmi-effort-');
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
  List<SetObservations?>? ratings,
  List<String?> reps = const ['8', '8'],
}) async {
  final service = StoredTrainingService(store);
  final s = run == null
      ? await service.start(id, 'effort', 1, instant(day))
      : await ProgramService(store).start(
          run,
          (await ProgramService(store).run(run)).contentVersion,
          id,
          instant(day),
        );
  return service.edit(
    id,
    s.contentVersion,
    (s) => _complete(s, ratings: ratings, reps: reps),
  );
}

Future<ProgressionDecision> _propose(
  TrainingStore store,
  String id, {
  Map<String, Object?>? rule,
}) => StoredProgressionService(
  store,
).propose(id, 'movement', rule ?? _rule(), ruleType: 'threshold');
Future<void> _fails(Future<Object?> value) =>
    expectLater(value, throwsA(isA<BodyTmiException>()));
DateTime _at(int day) => instant(day).add(const Duration(hours: 2));
Future<void> _relabel(String source, String destination, String label) async {
  final j = jsonObject(
    jsonDecode(await File(source).readAsString()),
    'logical',
  );
  j['format'] = label;
  j.remove('sha256');
  j['sha256'] = sha256.convert(utf8.encode(canonicalJson(j))).toString();
  await File(destination).writeAsString(jsonEncode(j));
}

void effortConditionsTests() {
  test(
    'effort gates validate explicit scales, inclusive decimal ranges and bounded input shapes',
    () {
      for (final config in <Object?>[
        {},
        null,
        {'notes': 'never'},
        {'rpe': <String, Object?>{}},
        {'rir': <String, Object?>{}},
        {
          'rpe': {'maximum': '8'},
        },
        {
          'rpe': {'scale': 'unknown', 'maximum': '8'},
        },
        {
          'rpe': {'scale': '6-20', 'minimum': '5'},
        },
        {
          'rpe': {'scale': '0-10', 'maximum': '10.1'},
        },
        {
          'rir': {'minimum': '-1'},
        },
        {
          'rir': {'minimum': '3', 'maximum': '2'},
        },
        {
          'rir': {'maximum': 2},
        },
        {
          'rir': {'maximum': null},
        },
        {
          'rir': {'scale': '0-10', 'minimum': '1'},
        },
        {'terminationReason': 'pain-discomfort'},
      ]) {
        rejects(
          () =>
              ThresholdRule.fromJson({..._rule(), 'advancementEffort': config}),
        );
      }
      rejects(() => _evaluate(ratings: [_rating()]));
      rejects(() => _evaluate(reps: [null], ratings: [_rating()]));
      rejects(() => _evaluate(reps: List.filled(10001, '8')));
      final parsed = AdvancementEffort.fromJson({
        'rpe': {'scale': '6-20', 'minimum': '06.00', 'maximum': '20'},
        'rir': {'minimum': '0'},
      });
      equal(parsed.rpe!.minimum.toString(), '6');
      check(parsed.rir!.contains(Decimal.zero));
    },
  );
  test(
    'effort gates require every configured rating independently and never convert RPE scales',
    () {
      final met = _evaluate(
        ratings: [
          _rating(),
          _rating(rpe: '7.5', rir: '2.5'),
        ],
      );
      equal(met.outcome, 'advance');
      equal(met.cursor, 0);
      equal(met.nextValues['mass']!.value.toString(), '11');
      equal(met.effortAssessment!.status, 'met');
      for (final other in [_rating(rpe: '8.0001'), _rating(rir: '1.9999')]) {
        final held = _evaluate(ratings: [_rating(), other]);
        equal(held.outcome, 'hold');
        equal(held.failedSessions, 0);
        equal(held.cursor, 1);
        equal(held.effortAssessment!.status, 'not-met');
        equal(held.nextValues['mass']!.value.toString(), '10');
      }
      final wrongScale = _evaluate(
        ratings: [
          _rating(scale: '6-20'),
          _rating(),
        ],
      );
      equal(wrongScale.outcome, 'unknown');
      equal(wrongScale.failedSessions, 1);
      final row = wrongScale.effortAssessment!.results.first;
      equal(jsonObject(row['rpe'], 'rpe')['reason'], 'rpe-scale-mismatch');
      final zeroRule = {
        ..._rule(),
        'advancementEffort': {
          'rpe': {'scale': '0-10', 'minimum': '0', 'maximum': '0'},
          'rir': {'minimum': '0', 'maximum': '0'},
        },
      };
      equal(
        _evaluate(
          rule: zeroRule,
          ratings: [
            _rating(rpe: '0', rir: '0'),
            _rating(rpe: '0', rir: '0'),
          ],
        ).outcome,
        'advance',
      );
    },
  );
  test(
    'effort gates keep missing advancement inputs neutral and numeric failure and deload precedence explicit',
    () {
      for (final ratings in <List<SetObservations?>?>[
        null,
        [null, _rating()],
        [
          _rating(),
          SetObservations.fromJson({'rir': '2'}),
        ],
      ]) {
        final unknown = _evaluate(ratings: ratings);
        equal(unknown.outcome, 'unknown');
        equal(unknown.failedSessions, 1);
        equal(unknown.cursor, 1);
        equal(
          _evaluate(ratings: ratings, reps: ['5', '8'], failures: 0).outcome,
          'failed',
        );
        final deload = _evaluate(ratings: ratings, reps: ['5', '8']);
        equal(deload.outcome, 'deload');
        equal(deload.failedSessions, 0);
        equal(deload.cursor, 1);
        equal(deload.nextValues['mass']!.value.toString(), '9');
        // Numeric hold never needs an effort rating to invent a reason to advance.
        final numericHold = _evaluate(ratings: ratings, reps: ['7', '8']);
        equal(numericHold.outcome, 'hold');
        equal(numericHold.failedSessions, 0);
      }
      final partial = _evaluate(reps: ['5', null], ratings: [null, null]);
      equal(partial.outcome, 'unknown');
      equal(partial.failedSessions, 1);
      final interrupted = _evaluate(
        ratings: [
          _rating(reason: 'interrupted'),
          _rating(),
        ],
      );
      equal(interrupted.outcome, 'unknown');
      equal(interrupted.failedSessions, 1);
      final mixedUnknown = _evaluate(
        ratings: [
          _rating(rpe: '9'),
          null,
        ],
      );
      equal(mixedUnknown.outcome, 'unknown');
    },
  );
  test(
    'effort gates apply all-required scope even when numeric selection uses any last total or K-of-N',
    () {
      for (final aggregation in [
        {'mode': 'any'},
        {'mode': 'last'},
        {'mode': 'best'},
        {'mode': 'total'},
        {'mode': 'kOfN', 'count': 1},
      ]) {
        final rule = {..._rule(), 'aggregation': aggregation};
        final p = _evaluate(
          rule: rule,
          ratings: [
            _rating(rpe: '9'),
            _rating(),
          ],
        );
        equal(p.outcome, 'hold');
        equal(p.effortAssessment!.status, 'not-met');
        equal(p.assessment!.eligible, true);
        equal(
          _evaluate(rule: rule, ratings: [_rating(), _rating()]).outcome,
          'advance',
        );
      }
      final lower = _rule()
        ..remove('minimum')
        ..remove('threshold');
      lower['performance'] = {
        'direction': 'lower',
        'failureLimit': {'value': '10', 'unit': 'rep'},
        'advancementLimit': {'value': '8', 'unit': 'rep'},
      };
      equal(
        _evaluate(rule: lower, ratings: [_rating(), _rating()]).outcome,
        'advance',
      );
      equal(
        _evaluate(rule: lower, ratings: [null, _rating()]).outcome,
        'unknown',
      );
    },
  );
  test(
    'effort gates do not select a coordinator candidate or evaluate scale steps before qualification',
    () {
      for (final coordination in [
        {'mode': 'chosen', 'metric': 'mass'},
        {
          'mode': 'priority',
          'order': ['mass'],
        },
      ]) {
        final rule = {
          ..._rule(),
          'coordination': coordination,
          'maximums': {
            'mass': {'value': '10', 'unit': 'kg'},
          },
        };
        final hold = _evaluate(
          rule: rule,
          cursor: 0,
          ratings: [
            _rating(rpe: '9'),
            _rating(),
          ],
        );
        equal(hold.outcome, 'hold');
        equal(hold.coordination!.selectedMetric, null);
        check(hold.coordination!.candidates.isEmpty);
        equal(
          _evaluate(
            rule: rule,
            cursor: 0,
            ratings: [_rating(), _rating()],
          ).outcome,
          'blocked',
        );
        final unknown = _evaluate(rule: rule, cursor: 0);
        equal(unknown.outcome, 'unknown');
        equal(unknown.coordination!.selectedMetric, null);
      }
    },
  );
  test(
    'effort gates preserve legacy numeric serialization and keep symptom annotations descriptive',
    () {
      final legacy = _rule()..remove('advancementEffort');
      final plain = _evaluate(rule: legacy).toJson();
      check(!plain.containsKey('effortAssessment'));
      check(!plain.containsKey('assessment'));
      for (final reason in ['pain-discomfort', 'grip-failure', 'max-effort']) {
        jsonEqual(
          _evaluate(
            rule: legacy,
            ratings: [
              _rating(rpe: '10', reason: reason),
              _rating(),
            ],
          ).toJson(),
          plain,
        );
        equal(
          _evaluate(
            ratings: [
              _rating(reason: reason),
              _rating(),
            ],
          ).outcome,
          'advance',
        );
      }
      equal(
        _evaluate(
          rule: legacy,
          ratings: [
            _rating(reason: 'interrupted'),
            _rating(),
          ],
        ).outcome,
        'unknown',
      );
      final request = {
        'schemaVersion': 1,
        'rule': _rule(),
        'current': metricsToJson(_current),
        'results': [metricsToJson(_current), metricsToJson(_current)],
        'observations': [_rating().toJson(), _rating().toJson()],
        'state': {'failedSessions': 1, 'cursor': 1},
      };
      jsonEqual(
        const Commands().execute('progression evaluate', request)['data'],
        _evaluate(ratings: [_rating(), _rating()]).toJson(),
      );
    },
  );
  test(
    'effort gates stored approvals preserve per-set evidence targets and counters without copying ratings or counting warmups',
    () => _withStore((store, dir) async {
      final service = StoredProgressionService(store);
      final one = await _finish(store, 'one', 1);
      final p = await _propose(store, one.id);
      equal(p.proposal.effortAssessment!.results.length, 2);
      equal(p.proposal.outcome, 'advance');
      final accepted = await service.accept(
        one.id,
        'movement',
        p.version,
        _at(1),
      );
      equal(accepted.cursor, 1);
      final next = await StoredTrainingService(
        store,
      ).start('next', 'effort', 1, instant(2));
      equal(next.sets.first.suggested['mass']!.value.toString(), '10');
      equal(next.sets.last.suggested['mass']!.value.toString(), '11');
      check(next.sets.every((s) => s.observations == null));
      var s = await StoredTrainingService(store).edit(
        next.id,
        next.contentVersion,
        (s) => _complete(
          s,
          ratings: [
            _rating(rpe: '9'),
            _rating(),
          ],
        ),
      );
      final q = await _propose(store, s.id);
      equal(q.proposal.outcome, 'hold');
      final declined = await service.decline(
        s.id,
        'movement',
        q.version,
        _at(2),
      );
      equal(declined.cursor, 1);
      equal(declined.failedSessions, 0);
      s = await StoredTrainingService(store).edit(
        s.id,
        s.contentVersion,
        (s) => const TrainingService().annotate(s, s.sets[1].id, _rating()),
      );
      equal(
        canonicalJson((await _propose(store, s.id)).toJson()),
        canonicalJson(declined.toJson()),
      );
      equal(
        canonicalJson(
          (await service.accept(
            one.id,
            'movement',
            p.version,
            _at(1),
          )).toJson(),
        ),
        canonicalJson(accepted.toJson()),
      );
      await _fails(
        _propose(store, s.id, rule: _rule()..remove('advancementEffort')),
      );
      await store.archive();
    }),
  );
  test(
    'effort gates missing ratings cannot be accepted and annotation edits invalidate pending or forged evidence',
    () => _withStore((store, dir) async {
      final progression = StoredProgressionService(store);
      var s = await _finish(store, 'one', 1, ratings: [null, _rating()]);
      final p = await _propose(store, s.id);
      equal(p.proposal.outcome, 'unknown');
      await _fails(progression.accept(s.id, 'movement', p.version, _at(1)));
      s = await StoredTrainingService(store).edit(
        s.id,
        s.contentVersion,
        (s) => const TrainingService().annotate(s, s.sets[1].id, _rating()),
      );
      await _fails(progression.accept(s.id, 'movement', p.version, _at(1)));
      final q = await _propose(store, s.id);
      equal(q.proposal.outcome, 'advance');
      final forged = copyJson(q.toJson());
      final evidence = jsonObject(
        jsonObject(forged['proposal'], 'proposal')['effortAssessment'],
        'effort',
      );
      evidence['status'] = 'not-met';
      rejects(() => ProgressionDecision.fromJson(forged));
      final forgedSource = copyJson(q.toJson());
      final source = jsonObject(forgedSource['session'], 'session');
      final set = jsonObject(jsonList(source, 'sets')[1], 'set');
      jsonObject(
        jsonObject(set['observations'], 'observations')['rpe'],
        'rpe',
      )['value'] = '9';
      rejects(() => ProgressionDecision.fromJson(forgedSource));
      s = await StoredTrainingService(store).edit(
        s.id,
        s.contentVersion,
        (s) => const TrainingService().complete(s, s.sets[1].id, {
          'mass': Quantity('12', 'kg'),
        }, acceptSuggested: true),
      );
      equal((await _propose(store, s.id)).proposal.outcome, 'review');
    }),
  );
  test(
    'effort gates remain independent across simultaneous programs using one workout template',
    () => _withStore((store, dir) async {
      final programs = ProgramService(store);
      await programs.publish(
        ProgramDefinition.fromJson({
          'id': 'shared',
          'name': 'Independent gates',
          'plan': {
            'id': 'day',
            'type': 'day',
            'templateId': 'effort',
            'revision': 1,
          },
        }),
        0,
      );
      for (final run in ['strength', 'cardio'])
        await programs.create(run, 'shared', 1, instant(1));
      final strength = await _finish(store, 'strength-one', 1, run: 'strength');
      final cardio = await _finish(store, 'cardio-one', 1, run: 'cardio');
      final p = await _propose(store, strength.id);
      final strict = _rule();
      jsonObject(
        jsonObject(strict['advancementEffort'], 'effort')['rpe'],
        'rpe',
      )['maximum'] = '7';
      final q = await _propose(store, cardio.id, rule: strict);
      equal(p.proposal.outcome, 'advance');
      equal(q.proposal.outcome, 'hold');
      final service = StoredProgressionService(store);
      await service.accept(strength.id, 'movement', p.version, _at(1));
      await service.accept(cardio.id, 'movement', q.version, _at(1));
      for (final (run, mass) in [('strength', '11'), ('cardio', '10')]) {
        final s = await programs.start(
          run,
          (await programs.run(run)).contentVersion,
          '$run-next',
          instant(2),
        );
        equal(s.sets.last.suggested['mass']!.value.toString(), mass);
        check(s.sets.every((set) => set.observations == null));
      }
      await store.archive();
    }),
  );
  test(
    'effort gates v21 profiles migrate unchanged while v22 native and logical restore preserve pending assessment and reject old labels',
    () => _withStore((store, dir) async {
      final s = await _finish(store, 'one', 1);
      final legacy = _rule()..remove('advancementEffort');
      await _propose(store, s.id, rule: legacy);
      final before = canonicalJson((await store.archive()).toJson());
      await store.backup('$dir/old');
      await LogicalArchiveFiles.export(await store.archive(), '$dir/old.json');
      final old = sqlite3.open('$dir/old/database.sqlite');
      old.execute('DROP TABLE derived_target_graphs');
      old.execute('DROP TABLE IF EXISTS repeat_checkpoints');
      old.execute('DROP TABLE IF EXISTS window_checkpoints');
      old.userVersion = 21;
      old.close();
      equal(NativeBackup.validateDatabase('$dir/old/database.sqlite'), 21);
      final upgraded = await TrainingStore.open('$dir/old/database.sqlite');
      try {
        equal(canonicalJson((await upgraded.archive()).toJson()), before);
        equal(
          (await upgraded.backup('$dir/upgraded'))['databaseSchemaVersion'],
          51,
        );
      } finally {
        await upgraded.close();
      }
      await _relabel(
        '$dir/old.json',
        '$dir/old-label.json',
        'bodytmi-logical-export/21',
      );
      final preparedOld = await LogicalArchiveFiles.prepare(
        '$dir/old-label.json',
      );
      try {
        equal(canonicalJson(preparedOld.archive.toJson()), before);
      } finally {
        await preparedOld.close();
      }
      final p = await _propose(store, s.id);
      final current = canonicalJson((await store.archive()).toJson());
      await store.backup('$dir/native');
      final native = await NativeBackup.prepare('$dir/native');
      final target = await TrainingStore.open('$dir/restored.sqlite');
      try {
        await target.restore(
          native,
          recoveryDestination: '$dir/recovery',
          confirm: true,
        );
      } finally {
        await target.close();
        await native.close();
      }
      final restored = await TrainingStore.open('$dir/restored.sqlite');
      try {
        equal(canonicalJson((await restored.archive()).toJson()), current);
        final accepted = await StoredProgressionService(
          restored,
        ).accept(s.id, 'movement', p.version, _at(1));
        equal(accepted.cursor, 1);
        equal(accepted.proposal.effortAssessment!.status, 'met');
      } finally {
        await restored.close();
      }
      await LogicalArchiveFiles.export(await store.archive(), '$dir/new.json');
      final logical = await LogicalArchiveFiles.prepare('$dir/new.json');
      try {
        equal(canonicalJson(logical.archive.toJson()), current);
      } finally {
        await logical.close();
      }
      await _relabel(
        '$dir/new.json',
        '$dir/wrong.json',
        'bodytmi-logical-export/21',
      );
      await _fails(LogicalArchiveFiles.prepare('$dir/wrong.json'));
      final wrong = sqlite3.open('$dir/native/database.sqlite');
      wrong.execute('DROP TABLE derived_target_graphs');
      wrong.execute('DROP TABLE IF EXISTS repeat_checkpoints');
      wrong.execute('DROP TABLE IF EXISTS window_checkpoints');
      wrong.userVersion = 21;
      wrong.close();
      rejects(
        () => NativeBackup.validateDatabase('$dir/native/database.sqlite'),
      );
    }),
  );
  test(
    'effort gates persist neutral missing ratings, known holds and numeric failure/deload counters across exposures',
    () => _withStore((store, dir) async {
      final progression = StoredProgressionService(store);
      final exposures = [
        (['5', '8'], <SetObservations?>[null, null], 'failed', 1, false),
        (['8', '8'], <SetObservations?>[null, null], 'unknown', 1, true),
        (
          ['8', '8'],
          <SetObservations?>[_rating(rpe: '9'), _rating()],
          'hold',
          0,
          false,
        ),
        (['5', '8'], <SetObservations?>[null, null], 'failed', 1, false),
        (['5', '8'], <SetObservations?>[null, null], 'deload', 0, false),
      ];
      for (var i = 0; i < exposures.length; i++) {
        final (reps, ratings, outcome, failures, decline) = exposures[i];
        final s = await _finish(
          store,
          'exposure-$i',
          i + 1,
          reps: reps,
          ratings: ratings,
        );
        final p = await _propose(store, s.id);
        equal(p.proposal.outcome, outcome);
        final terminal = decline
            ? await progression.decline(s.id, 'movement', p.version, _at(i + 1))
            : await progression.accept(s.id, 'movement', p.version, _at(i + 1));
        equal(terminal.failedSessions, failures);
        equal(terminal.cursor, 0);
      }
      final next = await StoredTrainingService(
        store,
      ).start('after-deload', 'effort', 1, instant(6));
      equal(next.sets.last.suggested['mass']!.value.toString(), '9');
      check(next.sets.every((s) => s.observations == null));
      await store.archive();
    }),
  );
  test(
    'effort gates native pure and stored CLI return matching evidence and reject malformed vectors cleanly',
    () => _withStore((store, dir) async {
      final s = await _finish(store, 'one', 1);
      await store.close();
      final pure = await invoke(
        ['progression', 'evaluate'],
        jsonEncode({
          'schemaVersion': 1,
          'rule': _rule(),
          'current': metricsToJson(_current),
          'results': [metricsToJson(_current), metricsToJson(_current)],
          'observations': [_rating().toJson(), _rating().toJson()],
        }),
      );
      equal(pure.code, 0);
      final stored = await invoke(
        ['progression', 'propose'],
        jsonEncode({
          'schemaVersion': 1,
          'database': '$dir/db.sqlite',
          'sessionId': s.id,
          'slotId': 'movement',
          'ruleType': 'threshold',
          'rule': _rule(),
        }),
      );
      equal(stored.code, 0);
      final pureData = jsonObject(
        jsonObject(jsonDecode(pure.output), 'response')['data'],
        'data',
      );
      final storedData = jsonObject(
        jsonObject(jsonDecode(stored.output), 'response')['data'],
        'data',
      );
      equal(
        canonicalJson(pureData['effortAssessment']),
        canonicalJson(
          jsonObject(storedData['proposal'], 'proposal')['effortAssessment'],
        ),
      );
      final bad = await invoke(
        ['progression', 'evaluate'],
        jsonEncode({
          'schemaVersion': 1,
          'rule': _rule(),
          'current': metricsToJson(_current),
          'results': [metricsToJson(_current)],
          'observations': <Object?>[],
        }),
      );
      equal(bad.code, 2);
      equal(bad.output, '');
      check(!bad.error.contains('internal'));
    }),
  );
}
