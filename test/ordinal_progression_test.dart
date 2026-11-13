import 'dart:convert';
import 'dart:io';

import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart' show expectLater, throwsA, isA;
import 'cli_test.dart' show invoke;
import 'fixtures.dart';
import 'support.dart';

Map<String, Object?> _q(String value, String unit) => {
  'value': value,
  'unit': unit,
};

Map<String, Object?> _level(String id, String mass, {String reps = '8'}) => {
  'id': id,
  'targets': {'mass': _q(mass, 'kg'), 'reps': _q(reps, 'rep')},
};

Map<String, Object?> _rule({
  int? deloadAfter,
  String? deloadLevel,
  Map<String, Object?>? advancementEffort,
  String? aggregationMode,
}) => {
  'metric': 'reps',
  'performance': {
    'direction': 'higher',
    'failureLimit': _q('4', 'rep'),
    'advancementLimit': _q('8', 'rep'),
  },
  'levels': [
    _level('band-a', '20'),
    _level('band-b', '22.5'),
    _level('band-c', '25'),
  ],
  if (aggregationMode != null) 'aggregation': {'mode': aggregationMode},
  if (advancementEffort != null) 'advancementEffort': advancementEffort,
  if (deloadAfter != null) 'deloadAfter': deloadAfter,
  if (deloadLevel != null) 'deloadLevel': deloadLevel,
};

WorkoutDefinition _definition() =>
    WorkoutDefinition.fromJson(example('ordinal-practice')['definition']);

WorkoutDefinition _pairDefinition() => WorkoutDefinition.fromJson({
  'id': 'ordinal-practice',
  'name': 'Ordinal pair practice',
  'slots': [
    {
      'id': 'row-a',
      'exercise': 'custom',
      'implementation': 'custom',
      'targets': {'mass': _q('20', 'kg'), 'reps': _q('8', 'rep')},
    },
    {
      'id': 'row-b',
      'exercise': 'custom',
      'implementation': 'custom',
      'targets': {'mass': _q('20', 'kg'), 'reps': _q('8', 'rep')},
    },
  ],
  'plan': {
    'id': 'practice',
    'type': 'sequence',
    'children': [
      {'id': 'warmup', 'type': 'effort', 'slot': 'row-a', 'role': 'warmup'},
      {'id': 'effort-a', 'type': 'effort', 'slot': 'row-a'},
      {'id': 'effort-b', 'type': 'effort', 'slot': 'row-b'},
    ],
  },
});

OrdinalProposal _evaluate(
  Map<String, Object?> rule,
  List<Metrics> currentSets,
  List<Metrics?> results, {
  List<SetObservations?>? observations,
  int failedSessions = 0,
}) => OrdinalRule.fromJson(rule).evaluate(
  currentSets: currentSets,
  results: results,
  observations: observations,
  failedSessions: failedSessions,
);

Metrics _metrics(Map<String, Object?> json) => metricsFromJson(json);

List<Metrics> _repeated(Map<String, Object?> targets, int count) => [
  for (var i = 0; i < count; i++) _metrics(targets),
];

String _masses(OrdinalProposal proposal) =>
    proposal.nextSets.map((s) => s['mass']!.value.toString()).join(',');

Future<void> _fails(Future<Object?> Function() action) =>
    expectLater(action(), throwsA(isA<BodyTmiException>()));

Future<String?> _invalid(Future<Object?> Function() action) async {
  try {
    await action();
  } on BodyTmiException catch (error) {
    equal(error.code, 'validation');
    return error.message;
  }
  throw StateError('Expected a validation error.');
}

Future<String?> _conflict(Future<Object?> Function() action) async {
  try {
    await action();
  } on BodyTmiException catch (error) {
    equal(error.code, 'conflict');
    return error.message;
  }
  throw StateError('Expected a conflict.');
}

String _invalidError(void Function() action) {
  try {
    action();
  } on BodyTmiException catch (error) {
    return error.message;
  }
  throw StateError('Expected a validation error.');
}

String _nativeError(String database) {
  try {
    return 'ok:${NativeBackup.validateDatabase(database)}';
  } on BodyTmiException catch (error) {
    return error.message;
  }
}

String _digest(String canonical) =>
    sha256.convert(utf8.encode(canonical)).toString();

const _slot = 'row';

Future<TrainingSession> _finished(
  TrainingStore store,
  String id,
  int day, {
  String reps = '8',
  String? mass,
  bool skip = false,
  int revision = 1,
}) async {
  final service = StoredTrainingService(store);
  final session = await service.start(
    id,
    'ordinal-practice',
    revision,
    instant(day),
  );
  return service.edit(id, session.contentVersion, (s) {
    for (final set in s.sets) {
      s = skip
          ? const TrainingService().skip(s, set.id, confirm: true)
          : const TrainingService().complete(s, set.id, {
              'reps': Quantity(reps, 'rep'),
              'mass': Quantity(
                mass ?? set.suggested['mass']!.value.toString(),
                'kg',
              ),
            });
    }
    return s.finish(instant(day).add(const Duration(hours: 1)));
  });
}

DateTime _approval(int day) => instant(day).add(const Duration(hours: 2));

void ordinalProgressionTests() {
  test('ordinal rules validate authored level structure strictly', () {
    final base = _rule();
    check(
      OrdinalRule.fromJson(
        base,
      ).controlledMetrics.containsAll({'mass', 'reps'}),
      'level target keys are the controlled metrics',
    );
    equal(OrdinalRule.fromJson(base).levels.length, 3);
    rejects(() => OrdinalRule.fromJson({...base, 'levels': <Object?>[]}));
    rejects(
      () => OrdinalRule.fromJson({
        ...base,
        'levels': [_level('x', '20'), _level('y', '20')],
      }),
    );
    rejects(
      () => OrdinalRule.fromJson({
        ...base,
        'levels': [_level('x', '20'), _level('x', '22.5')],
      }),
    );
    rejects(
      () => OrdinalRule.fromJson({
        ...base,
        'levels': [
          _level('x', '20'),
          {
            'id': 'y',
            'targets': {'mass': _q('22.5', 'kg')},
          },
        ],
      }),
    );
    rejects(
      () => OrdinalRule.fromJson({
        ...base,
        'levels': [
          _level('x', '20'),
          {
            'id': 'y',
            'targets': {'mass': _q('20', 'm'), 'reps': _q('8', 'rep')},
          },
        ],
      }),
    );
    equal(
      _invalidError(
        () => OrdinalRule.fromJson({...base, 'deloadLevel': 'missing'}),
      ),
      'deloadLevel must name a published level.',
    );
    equal(
      _invalidError(
        () => OrdinalRule.fromJson({...base, 'deloadLevel': 'band-c'}),
      ),
      'deloadLevel must be easier than the hardest level.',
    );
    equal(
      _invalidError(
        () => OrdinalRule.fromJson({
          ...base,
          'performance': {
            'direction': 'higher',
            'failureLimit': _q('10', 'rep'),
            'advancementLimit': _q('8', 'rep'),
          },
        }),
      ),
      'Failure and advancement limits contradict performance direction in '
      'the same aggregation scope.',
    );
    equal(
      _invalidError(
        () => OrdinalRule.fromJson({
          'metric': 'mass',
          'performance': {
            'direction': 'higher',
            'failureLimit': _q('10', 'kg'),
            'advancementLimit': _q('20', 'kg'),
          },
          'aggregation': {'mode': 'total'},
          'levels': [
            {
              'id': 'x',
              'targets': {'mass': _q('20', 'kg')},
            },
          ],
        }),
      ),
      'Total aggregation requires count, duration or distance.',
    );
    rejects(
      () => OrdinalRule.fromJson({
        ...base,
        'performance': {
          'direction': 'harder',
          'failureLimit': _q('4', 'rep'),
          'advancementLimit': _q('8', 'rep'),
        },
      }),
    );
  });

  test(
    'ordinal evaluation moves the whole vector between levels once per exposure',
    () {
      final rule = _rule(deloadAfter: 2, deloadLevel: 'band-a');
      final bandA = _level('band-a', '20')['targets']! as Map<String, Object?>;
      final bandB =
          _level('band-b', '22.5')['targets']! as Map<String, Object?>;
      final bandC = _level('band-c', '25')['targets']! as Map<String, Object?>;

      final advanced = _evaluate(rule, _repeated(bandA, 2), [
        {'reps': Quantity('8', 'rep')},
        {'reps': Quantity('8', 'rep')},
      ]);
      equal(advanced.outcome, 'advance');
      equal(_masses(advanced), '22.5,22.5');
      equal(advanced.failedSessions, 0);
      check(advanced.assessment != null, 'assessment evidence is retained');
      check(
        !jsonEncode(advanced.toJson()).contains('cursor'),
        'no coordinator position exists anywhere in ordinal output',
      );

      final hold = _evaluate(rule, _repeated(bandA, 2), [
        {'reps': Quantity('6', 'rep')},
        {'reps': Quantity('6', 'rep')},
      ], failedSessions: 1);
      equal(hold.outcome, 'hold');
      check(hold.failedSessions == 0, 'a passing exposure resets the counter');
      equal(_masses(hold), '20,20');

      final failed = _evaluate(rule, _repeated(bandA, 2), [
        {'reps': Quantity('2', 'rep')},
        {'reps': Quantity('8', 'rep')},
      ]);
      equal(failed.outcome, 'failed');
      check(failed.failedSessions == 1, 'one exposure, not one failed set');

      final deload = _evaluate(rule, _repeated(bandB, 2), [
        {'reps': Quantity('2', 'rep')},
        {'reps': Quantity('2', 'rep')},
      ], failedSessions: 1);
      equal(deload.outcome, 'deload');
      equal(deload.failedSessions, 0);
      equal(_masses(deload), '20,20');

      final blockedDeload = _evaluate(rule, _repeated(bandA, 2), [
        {'reps': Quantity('2', 'rep')},
        {'reps': Quantity('2', 'rep')},
      ], failedSessions: 1);
      equal(blockedDeload.outcome, 'blocked');
      check(
        blockedDeload.failedSessions == 2,
        'an unreachable deload still counts the failed exposure',
      );

      final hardest = _evaluate(rule, _repeated(bandC, 2), [
        {'reps': Quantity('9', 'rep')},
        {'reps': Quantity('9', 'rep')},
      ], failedSessions: 1);
      equal(hardest.outcome, 'blocked');
      equal(hardest.failedSessions, 0);
      equal(_masses(hardest), '25,25');

      final review = _evaluate(
        rule,
        [_metrics(bandA), _metrics(bandB)],
        [
          {'reps': Quantity('8', 'rep')},
          {'reps': Quantity('8', 'rep')},
        ],
        failedSessions: 2,
      );
      equal(review.outcome, 'review');
      check(review.failedSessions == 2, 'review never touches the counter');
      equal(
        review.reason,
        'Current controlled targets do not match exactly one published '
        'ordinal level; reconcile before progression.',
      );

      final unknown = _evaluate(rule, _repeated(bandA, 2), [
        null,
        {'reps': Quantity('8', 'rep')},
      ], failedSessions: 1);
      equal(unknown.outcome, 'unknown');
      equal(unknown.failedSessions, 1);

      final interrupted = _evaluate(
        rule,
        _repeated(bandA, 2),
        [
          {'reps': Quantity('8', 'rep')},
          {'reps': Quantity('8', 'rep')},
        ],
        observations: [
          null,
          SetObservations.fromJson({'terminationReason': 'interrupted'}),
        ],
        failedSessions: 1,
      );
      equal(interrupted.outcome, 'unknown');
      equal(interrupted.failedSessions, 1);
    },
  );

  test('ordinal performance can be lower-is-better and total-scoped', () {
    final rule = {
      'metric': 'duration',
      'performance': {
        'direction': 'lower',
        'failureLimit': _q('300', 's'),
        'advancementLimit': _q('120', 's'),
      },
      'levels': [
        {
          'id': 'hold-60',
          'targets': {'duration': _q('60', 's')},
        },
        {
          'id': 'hold-90',
          'targets': {'duration': _q('90', 's')},
        },
      ],
    };
    final advanced = _evaluate(
      rule,
      [
        {'duration': Quantity('60', 's')},
        {'duration': Quantity('60', 's')},
      ],
      [
        {'duration': Quantity('110', 's')},
        {'duration': Quantity('115', 's')},
      ],
    );
    check(
      advanced.outcome == 'advance',
      'level order is authored, not numeric',
    );
    equal(
      advanced.nextSets.map((s) => s['duration']!.value.toString()).join(','),
      '90,90',
    );

    final totals = {
      'metric': 'reps',
      'aggregation': {'mode': 'total'},
      'performance': {
        'direction': 'higher',
        'failureLimit': _q('4', 'rep'),
        'advancementLimit': _q('10', 'rep'),
      },
      'levels': [_level('a', '20'), _level('b', '22.5')],
    };
    final totalAdvance = _evaluate(
      totals,
      _repeated(_level('a', '20')['targets']! as Map<String, Object?>, 2),
      [
        {'reps': Quantity('5', 'rep')},
        {'reps': Quantity('5', 'rep')},
      ],
    );
    equal(totalAdvance.outcome, 'advance');
    equal(totalAdvance.assessment?.selected?.value.toString(), '10');
  });

  test(
    'ordinal advancement effort gates only qualified numeric advancement',
    () {
      final rule = _rule(
        advancementEffort: {
          'rpe': {'scale': '0-10', 'minimum': '7'},
        },
      );
      final sets = _repeated(
        _level('band-a', '20')['targets']! as Map<String, Object?>,
        1,
      );
      final results = [
        {'reps': Quantity('8', 'rep')},
      ];

      final met = _evaluate(
        rule,
        sets,
        results,
        observations: [
          SetObservations.fromJson({
            'rpe': {'value': '8', 'scale': '0-10'},
          }),
        ],
      );
      equal(met.outcome, 'advance');
      equal(met.effortAssessment?.status, 'met');

      final unmet = _evaluate(
        rule,
        sets,
        results,
        observations: [
          SetObservations.fromJson({
            'rpe': {'value': '6', 'scale': '0-10'},
          }),
        ],
        failedSessions: 1,
      );
      equal(unmet.outcome, 'hold');
      equal(unmet.failedSessions, 0);
      equal(unmet.effortAssessment?.status, 'not-met');

      final missing = _evaluate(rule, sets, results, failedSessions: 1);
      equal(missing.outcome, 'unknown');
      equal(missing.failedSessions, 1);

      final scaleMismatch = _evaluate(
        rule,
        sets,
        results,
        observations: [
          SetObservations.fromJson({
            'rpe': {'value': '8', 'scale': '6-20'},
          }),
        ],
        failedSessions: 1,
      );
      equal(scaleMismatch.outcome, 'unknown');
      equal(scaleMismatch.failedSessions, 1);

      final numericHoldNeedsNoRating = _evaluate(rule, sets, [
        {'reps': Quantity('6', 'rep')},
      ], failedSessions: 1);
      equal(numericHoldNeedsNoRating.outcome, 'hold');
      equal(numericHoldNeedsNoRating.failedSessions, 0);
    },
  );

  test(
    'stored ordinal progression proposes, accepts and later starts consume one whole level',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-ordinal-');
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        await StoredTrainingService(store).publish(_definition(), 0);
        final progression = StoredProgressionService(store);
        final rule = _rule(deloadAfter: 2, deloadLevel: 'band-a');

        final first = await _finished(store, 'ord-1', 1);
        var decision = await progression.propose(
          first.id,
          _slot,
          rule,
          ruleType: 'ordinal',
        );
        equal(decision.ruleType, 'ordinal');
        equal(decision.previousCursor, 0);
        equal(decision.proposal.outcome, 'advance');
        equal(
          canonicalJson(decision.proposal.toJson()['nextState']),
          canonicalJson({'failedSessions': 0}),
        );
        check(
          !jsonEncode(decision.proposal.toJson()).contains('cursor'),
          'ordinal proposals carry no coordinator position',
        );
        decision = await progression.accept(
          first.id,
          _slot,
          decision.version,
          _approval(1),
        );
        equal(decision.cursor, 0);
        check(
          !jsonEncode(decision.toJson()).contains('Cursor'),
          'ordinal decisions never serialize cursor keys',
        );

        final second = await _finished(store, 'ord-2', 2);
        equal(second.sets.last.suggested['mass']!.value.toString(), '22.5');
        equal(second.sets.last.suggested['reps']!.value.toString(), '8');

        // Durable track view: rule and controlled metrics, never a cursor.
        final view = await progression.track(
          templateId: 'ordinal-practice',
          revision: 1,
          slotId: _slot,
          asOf: instant(3),
        );
        equal(view['resolved'], true);
        equal(view['ruleType'], 'ordinal');
        check(
          !jsonEncode(view).contains('cursor'),
          'ordinal track views report no coordinator position',
        );
        final state = jsonObject(view['state'], 'state');
        equal(state['failedSessions'], 0);
        final firstSet = jsonObject(
          (state['nextSets']! as List).first! as Map<String, Object?>,
          'set',
        );
        equal(jsonObject(firstSet['mass'], 'mass')['value'], '22.5');

        // Two failed exposures against deloadAfter=2:
        // first fails, second proposes the authored deload level.
        final failed = await _finished(store, 'ord-3', 3, reps: '2');
        var pending = await progression.propose(
          failed.id,
          _slot,
          rule,
          ruleType: 'ordinal',
        );
        equal(pending.previousFailures, 0);
        equal(pending.proposal.outcome, 'failed');
        pending = await progression.accept(
          failed.id,
          _slot,
          pending.version,
          _approval(3),
        );
        equal(pending.failedSessions, 1);

        final again = await _finished(store, 'ord-4', 4, reps: '2');
        pending = await progression.propose(
          again.id,
          _slot,
          rule,
          ruleType: 'ordinal',
        );
        equal(pending.previousFailures, 1);
        equal(pending.proposal.outcome, 'deload');
        pending = await progression.decline(
          again.id,
          _slot,
          pending.version,
          _approval(4),
        );
        check(
          pending.failedSessions == 2,
          'declining a deload keeps the failed-exposure count',
        );
        equal(pending.nextSets.first['mass']!.value.toString(), '22.5');
        final retry = await progression.decline(
          again.id,
          _slot,
          pending.version,
          _approval(5),
        );
        equal(canonicalJson(retry.toJson()), canonicalJson(pending.toJson()));

        final third = await _finished(store, 'ord-5', 5, reps: '2');
        pending = await progression.propose(
          third.id,
          _slot,
          rule,
          ruleType: 'ordinal',
        );
        equal(pending.previousFailures, 2);
        equal(pending.proposal.outcome, 'deload');
        pending = await progression.accept(
          third.id,
          _slot,
          pending.version,
          _approval(5),
        );
        equal(pending.failedSessions, 0);
        equal(pending.nextSets.first['mass']!.value.toString(), '20');

        final after = await _finished(store, 'ord-6', 6);
        equal(after.sets.last.suggested['mass']!.value.toString(), '20');
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'changed loads and missing work block ordinal application without counter drift',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-ordinal-rev-');
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        await StoredTrainingService(store).publish(_definition(), 0);
        final progression = StoredProgressionService(store);
        final rule = _rule();
        final changed = await _finished(store, 'changed', 1, mass: '21');
        var pending = await progression.propose(
          changed.id,
          _slot,
          rule,
          ruleType: 'ordinal',
        );
        equal(pending.proposal.outcome, 'review');
        await _fails(
          () => progression.accept(
            changed.id,
            _slot,
            pending.version,
            _approval(1),
          ),
        );
        pending = await progression.decline(
          changed.id,
          _slot,
          pending.version,
          _approval(1),
        );
        equal(pending.failedSessions, 0);

        final skipped = await _finished(store, 'skipped', 2, skip: true);
        pending = await progression.propose(
          skipped.id,
          _slot,
          rule,
          ruleType: 'ordinal',
        );
        equal(pending.proposal.outcome, 'unknown');
        await _fails(
          () => progression.accept(
            skipped.id,
            _slot,
            pending.version,
            _approval(2),
          ),
        );
        pending = await progression.decline(
          skipped.id,
          _slot,
          pending.version,
          _approval(2),
        );
        equal(pending.failedSessions, 0);

        final next = await _finished(store, 'after', 3);
        equal(next.sets.last.suggested['mass']!.value.toString(), '20');
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'ordinal tracks re-anchor through explicit reconciliation receipts',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-ordinal-rec-');
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        await StoredTrainingService(store).publish(_definition(), 0);
        final service = StoredTrainingService(store);
        final progression = StoredProgressionService(store);
        final rule = _rule();
        final first = await _finished(store, 'anchor', 1);
        final accepted = await progression.propose(
          first.id,
          _slot,
          rule,
          ruleType: 'ordinal',
        );
        await progression.accept(
          first.id,
          _slot,
          accepted.version,
          _approval(1),
        );

        // Prescription drift: level targets change in a new revision.
        final raw = _definition().toJson();
        final slots = raw['slots']! as List<Object?>;
        jsonObject(slots.first! as Map<String, Object?>, 'slot')['targets'] = {
          'mass': _q('21', 'kg'),
          'reps': _q('8', 'rep'),
        };
        await StoredTrainingService(
          store,
        ).publish(WorkoutDefinition.fromJson(raw), 1);
        final drifted = _rule();
        drifted['levels'] = [
          _level('band-a', '21'),
          _level('band-b', '23.5'),
          _level('band-c', '26'),
        ];
        check(
          (await _conflict(
                () =>
                    service.start('drifted', 'ordinal-practice', 2, instant(2)),
              )) !=
              null,
          'a drifted start is blocked',
        );
        final report = await progression.reconcileStatus(
          templateId: 'ordinal-practice',
          revision: 2,
          slotId: _slot,
          asOf: instant(3),
          rule: drifted,
          ruleType: 'ordinal',
        );
        equal(report['reconciliationRequired'], true);
        final kinds = (report['blockerKinds']! as List).cast<String>();
        check(kinds.isNotEmpty, 'the report names its blockers');
        final receipt = await progression.reconcile(
          id: 'ordinal-reanchor',
          templateId: 'ordinal-practice',
          revision: 2,
          slotId: _slot,
          expectedSequence: 1,
          kinds: kinds,
          reconciledAt: _approval(3),
          confirm: true,
          rule: drifted,
          ruleType: 'ordinal',
        );
        equal(receipt.ruleType, 'ordinal');
        equal(receipt.cursor, 0);
        check(
          !jsonEncode(receipt.toJson()).contains('Cursor'),
          'ordinal receipts hold no coordinator state',
        );
        check(
          (await _conflict(
                () => progression.reconcile(
                  id: 'ordinal-reanchor-2',
                  templateId: 'ordinal-practice',
                  revision: 2,
                  slotId: _slot,
                  expectedSequence: 1,
                  kinds: kinds,
                  reconciledAt: _approval(3),
                  confirm: true,
                  rule: drifted,
                  ruleType: 'ordinal',
                ),
              )) !=
              null,
          'the same sequence cannot be re-anchored twice',
        );

        final consumed = await _finished(store, 'consumed', 4, revision: 2);
        equal(consumed.sets.last.suggested['mass']!.value.toString(), '21');
        final pending = await progression.propose(
          consumed.id,
          _slot,
          drifted,
          ruleType: 'ordinal',
        );
        equal(pending.previousApplication, 'ordinal-reanchor');
        equal(pending.proposal.outcome, 'advance');
        equal(pending.nextSets.first['mass']!.value.toString(), '23.5');
        final track = await progression.track(
          templateId: 'ordinal-practice',
          revision: 2,
          slotId: _slot,
          asOf: instant(9),
        );
        equal(track['sourceKind'], 'reconciliation');
        equal(canonicalJson(track['acknowledgedKinds']), canonicalJson(kinds));
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test('ordinal levers cannot back shared lever links', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-ordinal-link-');
    final store = await TrainingStore.open('${dir.path}/db.sqlite');
    try {
      await StoredTrainingService(store).publish(_pairDefinition(), 0);
      final service = StoredTrainingService(store);
      final progression = StoredProgressionService(store);
      final rule = _rule();
      final started = await service.start(
        'linked',
        'ordinal-practice',
        1,
        instant(1),
      );
      final finished = await service.edit('linked', started.contentVersion, (
        s,
      ) {
        for (final set in s.sets) {
          s = const TrainingService().complete(s, set.id, {
            'reps': Quantity('8', 'rep'),
            'mass': Quantity(set.suggested['mass']!.value.toString(), 'kg'),
          });
        }
        return s.finish(instant(1).add(const Duration(hours: 1)));
      });
      for (final slot in ['row-a', 'row-b']) {
        final pending = await progression.propose(
          finished.id,
          slot,
          rule,
          ruleType: 'ordinal',
        );
        await progression.accept(
          finished.id,
          slot,
          pending.version,
          _approval(1),
        );
      }
      equal(
        await _invalid(
          () => LeverLinkService(store).create(
            input: {
              'id': 'shared-rows',
              'metrics': ['mass'],
              'members': ['linked/row-a', 'linked/row-b'],
              'baseline': 'linked/row-a',
            },
            expectedRevision: 0,
            createdAt: instant(2),
            confirm: true,
          ),
        ),
        'Ordinal progression levers cannot back shared lever links.',
      );
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });

  test(
    'native and logical v55 archives carry ordinal progression while older labels reject it',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-ordinal-port-',
      );
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      TrainingArchive? archived;
      String before;
      try {
        await StoredTrainingService(store).publish(_definition(), 0);
        final progression = StoredProgressionService(store);
        final rule = _rule();
        final finished = await _finished(store, 'portable', 1);
        final pending = await progression.propose(
          finished.id,
          _slot,
          rule,
          ruleType: 'ordinal',
        );
        await progression.accept(
          finished.id,
          _slot,
          pending.version,
          _approval(1),
        );
        archived = await store.archive();
        before = canonicalJson(archived.toJson());
        equal(
          (await store.backup('${dir.path}/native'))['databaseSchemaVersion'],
          58,
        );
        await LogicalArchiveFiles.export(archived, '${dir.path}/full.json');
      } finally {
        await store.close();
      }
      try {
        equal(
          NativeBackup.validateDatabase('${dir.path}/native/database.sqlite'),
          58,
        );
        final full = await LogicalArchiveFiles.prepare('${dir.path}/full.json');
        try {
          equal(canonicalJson(full.archive.toJson()), before);
          check(
            full.archive.progressions.any((d) => d.ruleType == 'ordinal'),
            'the ordinal decision survives the logical round trip',
          );
        } finally {
          await full.close();
        }
        // Same tables, but a v54 label may not claim an ordinal decision.
        File('${dir.path}/labeled.sqlite').writeAsBytesSync(
          File('${dir.path}/native/database.sqlite').readAsBytesSync(),
        );
        final labeled = sqlite3.open('${dir.path}/labeled.sqlite');
        labeled.execute('DROP TABLE IF EXISTS program_upgrade_receipts');
        labeled.execute('DROP TABLE IF EXISTS exercise_revisions');
        labeled.execute('DROP TABLE IF EXISTS implementation_revisions');
        labeled.userVersion = 54;
        labeled.close();
        equal(
          _nativeError('${dir.path}/labeled.sqlite'),
          'Ordinal progression requires schema v55.',
        );
        final json = jsonObject(
          jsonDecode(await File('${dir.path}/full.json').readAsString()),
          'file',
        );
        json['format'] = 'bodytmi-logical-export/54';
        json.remove('sha256');
        json['sha256'] = _digest(canonicalJson(json));
        await File(
          '${dir.path}/relabeled.json',
        ).writeAsString(jsonEncode(json));
        final message = await _invalid(
          () async => (await LogicalArchiveFiles.prepare(
            '${dir.path}/relabeled.json',
          )).close(),
        );
        equal(message, 'Ordinal progression requires logical v55.');

        // Restore keeps the track durable. Restore closes its store handle,
        // so query through a fresh connection afterwards.
        final backup = await NativeBackup.prepare('${dir.path}/native');
        final restorer = await TrainingStore.open(
          '${dir.path}/restored.sqlite',
        );
        try {
          await restorer.restore(
            backup,
            recoveryDestination: '${dir.path}/recovery',
            confirm: true,
          );
        } finally {
          await restorer.close();
        }
        final restored = await TrainingStore.open(
          '${dir.path}/restored.sqlite',
        );
        try {
          final track = await StoredProgressionService(restored).track(
            templateId: 'ordinal-practice',
            revision: 1,
            slotId: _slot,
            asOf: instant(9),
          );
          equal(track['ruleType'], 'ordinal');
          equal(
            (await restored.archive()).progressions.single.ruleType,
            'ordinal',
          );
          final next = await _finished(restored, 'after-restore', 3);
          equal(next.sets.last.suggested['mass']!.value.toString(), '22.5');
        } finally {
          await restored.close();
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test('CLI progression ordinal evaluates pure level moves', () async {
    final result = await invoke(
      ['progression', 'ordinal'],
      jsonEncode({
        'schemaVersion': 1,
        'rule': example('ordinal-practice')['rule'],
        'currentSets': [
          {'mass': _q('20', 'kg'), 'reps': _q('8', 'rep')},
          {'mass': _q('20', 'kg'), 'reps': _q('8', 'rep')},
        ],
        'results': [
          {'reps': _q('8', 'rep')},
          {'reps': _q('9', 'rep')},
        ],
        'state': {'failedSessions': 0},
      }),
    );
    equal(result.code, 0);
    equal(result.error, '');
    final data = jsonObject(
      jsonObject(jsonDecode(result.output), 'response')['data'],
      'data',
    );
    equal(data['outcome'], 'advance');
    for (final set in data['nextSets']! as List) {
      equal(
        jsonObject(jsonObject(set, 'set')['mass'], 'mass')['value'],
        '22.5',
      );
    }
    check(
      !jsonEncode(data).contains('cursor'),
      'pure ordinal responses never report a coordinator position',
    );
    final invalid = await invoke(
      ['progression', 'ordinal'],
      jsonEncode({
        'schemaVersion': 1,
        'rule': example('ordinal-practice')['rule'],
        'currentSets': [
          {'mass': _q('20', 'kg'), 'reps': _q('8', 'rep')},
        ],
        'results': [
          {'reps': _q('8', 'rep')},
        ],
        'state': {'failedSessions': -1},
      }),
    );
    equal(invalid.code, 2);
    final badRule = await invoke(
      ['progression', 'ordinal'],
      jsonEncode({
        'schemaVersion': 1,
        'rule': _rule(
          deloadLevel: 'band-c',
        ), // hardest level cannot deload onto itself
        'currentSets': [
          {'mass': _q('20', 'kg'), 'reps': _q('8', 'rep')},
        ],
        'results': [
          {'reps': _q('8', 'rep')},
        ],
      }),
    );
    equal(badRule.code, 2);
  });
}
