import 'dart:convert';
import 'dart:io';
import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:test/test.dart' show expectLater, throwsA, isA;
import 'cli_test.dart';
import 'fixtures.dart';
import 'support.dart';

final _current = metrics({'mass': ('10', 'kg'), 'reps': ('6', 'rep')});
Map<String, Object?> _band(String id, String threshold, String step) => {
  'id': id,
  'threshold': {'value': threshold, 'unit': 'rep'},
  'increments': {
    'mass': {'value': step, 'unit': 'kg'},
  },
};
Map<String, Object?> _rule() => {
  'metric': 'reps',
  'minimum': {'value': '18', 'unit': 'rep'},
  'threshold': {'value': '6', 'unit': 'rep'},
  'aggregation': {'mode': 'last'},
  'failureAggregation': {'mode': 'total'},
  'increments': {
    'mass': {'value': '1', 'unit': 'kg'},
  },
  'coordination': {
    'mode': 'weighted',
    'order': ['mass', 'mass'],
  },
  'deloadAfter': 1,
  'deloadMetrics': ['mass'],
  'incrementBands': {
    'aggregation': {'mode': 'last'},
    'bands': [_band('strong', '12', '2'), _band('stronger', '16', '3')],
  },
};
ProgressionProposal _eval(
  List<String?> values, {
  Map<String, Object?>? rule,
  List<SetObservations?>? observations,
  int failures = 0,
  int cursor = 0,
}) => ThresholdRule.fromJson(rule ?? _rule()).evaluate(
  current: _current,
  results: [
    for (final v in values) v == null ? null : metrics({'reps': (v, 'rep')}),
  ],
  observations: observations,
  failedSessions: failures,
  cursor: cursor,
);
WorkoutDefinition _definition() => WorkoutDefinition.fromJson({
  'id': 'bands',
  'name': 'Performance-dependent numeric steps',
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
        'count': 3,
        'child': {'id': 'set', 'type': 'effort', 'slot': 'movement'},
      },
    ],
  },
});
Future<void> _withStore(
  Future<void> Function(TrainingStore, String) action,
) async {
  final dir = await Directory.systemTemp.createTemp('bodytmi-bands-');
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
  List<String?> values = const ['6', '6', '12'],
}) async {
  final service = StoredTrainingService(store);
  final s = run == null
      ? await service.start(id, 'bands', 1, instant(day))
      : await ProgramService(store).start(
          run,
          (await ProgramService(store).run(run)).contentVersion,
          id,
          instant(day),
        );
  return service.edit(id, s.contentVersion, (s) {
    var i = 0;
    for (final set in s.sets) {
      final value = set.role == 'warmup' ? '100' : values[i++];
      s = value == null
          ? const TrainingService().skip(s, set.id)
          : const TrainingService().complete(s, set.id, {
              'reps': Quantity(value, 'rep'),
            }, acceptSuggested: true);
    }
    return s.finish(instant(day).add(const Duration(hours: 1)));
  });
}

Future<ProgressionDecision> _propose(
  TrainingStore store,
  String id, {
  Map<String, Object?>? rule,
}) => StoredProgressionService(
  store,
).propose(id, 'movement', rule ?? _rule(), ruleType: 'threshold');
DateTime _at(int day) => instant(day).add(const Duration(hours: 2));
Future<void> _fails(Future<Object?> action) =>
    expectLater(action, throwsA(isA<BodyTmiException>()));
void incrementBandsTests() {
  test(
    'increment bands validate ordered thresholds dimensions full step ownership and bounded configuration',
    () {
      final valid = jsonObject(_rule()['incrementBands'], 'bands');
      for (final invalid in <Object?>[
        null,
        <String, Object?>{},
        {
          'aggregation': {'mode': 'all'},
          'bands': [_band('one', '12', '2')],
        },
        {
          'aggregation': {'mode': 'any'},
          'bands': [_band('one', '12', '2')],
        },
        {
          'aggregation': {'mode': 'last'},
          'bands': <Object?>[],
        },
        {
          'aggregation': {'mode': 'last'},
          'bands': [_band('one', '16', '2'), _band('two', '12', '3')],
        },
        {
          'aggregation': {'mode': 'last'},
          'bands': [_band('one', '12', '2'), _band('two', '12', '3')],
        },
        {
          'aggregation': {'mode': 'last'},
          'bands': [_band('same', '12', '2'), _band('same', '16', '3')],
        },
        {
          'aggregation': {'mode': 'last'},
          'bands': [_band('one', '12', '0')],
        },
        {
          'aggregation': {'mode': 'last'},
          'bands': [
            {..._band('one', '12', '2'), 'increments': <String, Object?>{}},
          ],
        },
        {
          'aggregation': {'mode': 'last'},
          'bands': [
            {
              ..._band('one', '12', '2'),
              'increments': {
                'distance': {'value': '2', 'unit': 'm'},
              },
            },
          ],
        },
        {
          'aggregation': {'mode': 'last'},
          'bands': [
            {
              ..._band('one', '12', '2'),
              'increments': {
                'mass': {'value': '2', 'unit': 's'},
              },
            },
          ],
        },
        {
          'aggregation': {'mode': 'last'},
          'bands': [
            {
              ..._band('one', '12', '2'),
              'threshold': {'value': '12', 'unit': 's'},
            },
          ],
        },
        {
          'aggregation': {'mode': 'last'},
          'bands': List.generate(101, (i) => _band('b$i', '${i + 1}', '2')),
        },
        {...valid, 'unknown': true},
      ]) {
        rejects(
          () => ThresholdRule.fromJson({..._rule(), 'incrementBands': invalid}),
        );
      }
      final badTotal = {
        ..._rule(),
        'metric': 'mass',
        'minimum': {'value': '0', 'unit': 'kg'},
        'threshold': {'value': '1', 'unit': 'kg'},
        'failureAggregation': {'mode': 'all'},
        'incrementBands': {
          'aggregation': {'mode': 'total'},
          'bands': [
            {
              'id': 'x',
              'threshold': {'value': '2', 'unit': 'kg'},
              'increments': {
                'mass': {'value': '1', 'unit': 'kg'},
              },
            },
          ],
        },
      };
      rejects(() => ThresholdRule.fromJson(badTotal));
    },
  );
  test(
    'increment bands use inclusive strongest threshold or base steps without stacking or modifying inputs',
    () {
      final source = _rule();
      final before = canonicalJson(source);
      for (final (last, id, mass) in [
        ('11', null, '11'),
        ('12', 'strong', '12'),
        ('15', 'strong', '12'),
        ('16', 'stronger', '13'),
        ('99', 'stronger', '13'),
      ]) {
        final p = _eval(['6', '6', last], rule: source);
        equal(p.outcome, 'advance');
        equal(p.cursor, 1);
        equal(p.nextValues['mass']!.value.toString(), mass);
        equal(p.incrementBandAssessment!.band?.id, id);
        equal(p.incrementBandAssessment!.selected!.value.toString(), last);
        equal(p.failedSessions, 0);
      }
      equal(canonicalJson(source), before);
      final legacy = _rule()..remove('incrementBands');
      check(
        !_eval([
          '6',
          '6',
          '16',
        ], rule: legacy).toJson().containsKey('incrementBandAssessment'),
      );
      equal(
        _eval([
          '6',
          '6',
          '16',
        ], rule: legacy).nextValues['mass']!.value.toString(),
        '11',
      );
    },
  );
  test(
    'increment bands never override failure unknown interruption or effort gates and do not consume their cursors',
    () {
      for (final (values, outcome, reason) in <(List<String?>, String, String)>[
        (['0', '1', '16'], 'deload', 'numeric-failure'),
        (['6', null, '16'], 'unknown', 'numeric-unknown'),
        (['8', '8', '5'], 'hold', 'numeric-hold'),
      ]) {
        final p = _eval(values, cursor: 1, failures: 2);
        equal(p.outcome, outcome);
        equal(p.cursor, 1);
        equal(p.incrementBandAssessment!.reason, reason);
        check(p.incrementBandAssessment!.selected == null);
        check(p.incrementBandAssessment!.increments == null);
      }
      final interrupted = _eval(
        ['6', '6', '16'],
        observations: [
          null,
          null,
          SetObservations.fromJson({'terminationReason': 'interrupted'}),
        ],
      );
      equal(interrupted.outcome, 'unknown');
      equal(interrupted.incrementBandAssessment!.reason, 'numeric-unknown');
      final rule = {
        ..._rule(),
        'advancementEffort': {
          'rir': {'minimum': '2'},
        },
      };
      equal(
        _eval(['6', '6', '16'], rule: rule).incrementBandAssessment!.reason,
        'effort-unknown',
      );
      final low = SetObservations.fromJson({'rir': '1'});
      final held = _eval(
        ['6', '6', '16'],
        rule: rule,
        observations: [low, low, low],
      );
      equal(held.outcome, 'hold');
      equal(held.incrementBandAssessment!.reason, 'effort-not-met');
      // A total failure gate permits individual under-target sets when explicitly configured.
      equal(_eval(['4', '4', '12']).nextValues['mass']!.value.toString(), '12');
    },
  );
  test(
    'increment bands support best total lower direction and exact mixed-unit scalar selection',
    () {
      final best = _rule();
      jsonObject(best['incrementBands'], 'bands')['aggregation'] = {
        'mode': 'best',
      };
      equal(
        _eval(['6', '16', '12'], rule: best).incrementBandAssessment!.band!.id,
        'stronger',
      );
      final total = _rule();
      total['incrementBands'] = {
        'aggregation': {'mode': 'total'},
        'bands': [_band('total', '24', '2'), _band('more', '30', '3')],
      };
      equal(
        _eval(['8', '8', '8'], rule: total).incrementBandAssessment!.band!.id,
        'total',
      );
      equal(
        _eval([
          '10',
          '10',
          '10',
        ], rule: total).incrementBandAssessment!.band!.id,
        'more',
      );
      final lower = {
        'metric': 'elapsed',
        'performance': {
          'direction': 'lower',
          'failureLimit': {'value': '120', 'unit': 's'},
          'advancementLimit': {'value': '90', 'unit': 's'},
        },
        'aggregation': {'mode': 'best'},
        'increments': {
          'mass': {'value': '1', 'unit': 'kg'},
        },
        'incrementBands': {
          'aggregation': {'mode': 'best'},
          'bands': [
            {
              'id': 'faster',
              'threshold': {'value': '90', 'unit': 's'},
              'increments': {
                'mass': {'value': '2', 'unit': 'kg'},
              },
            },
            {
              'id': 'fastest',
              'threshold': {'value': '1', 'unit': 'min'},
              'increments': {
                'mass': {'value': '3', 'unit': 'kg'},
              },
            },
          ],
        },
      };
      final p = ThresholdRule.fromJson(lower).evaluate(
        current: {'mass': Quantity('10', 'kg')},
        results: [
          {'elapsed': Quantity('90', 's')},
          {'elapsed': Quantity('1', 'min')},
        ],
      );
      equal(p.incrementBandAssessment!.band!.id, 'fastest');
      equal(p.nextValues['mass']!.value.toString(), '13');
      equal(p.incrementBandAssessment!.selected!.enteredUnit, Unit.min);
      final wrong = copyJson(lower);
      final bands = jsonList(
        jsonObject(wrong['incrementBands'], 'bands'),
        'bands',
      );
      jsonObject(bands.last, 'band')['threshold'] = {
        'value': '1.5',
        'unit': 'min',
      };
      rejects(() => ThresholdRule.fromJson(wrong));
      final duration = copyJson(lower);
      duration['performance'] = {
        'direction': 'higher',
        'failureLimit': {'value': '0', 'unit': 's'},
        'advancementLimit': {'value': '6', 'unit': 's'},
      };
      duration['incrementBands'] = {
        'aggregation': {'mode': 'total'},
        'bands': [
          {
            'id': 'sum',
            'threshold': {'value': '12', 'unit': 's'},
            'increments': {
              'mass': {'value': '2', 'unit': 'kg'},
            },
          },
        ],
      };
      final summed = ThresholdRule.fromJson(duration).evaluate(
        current: {'mass': Quantity('10', 'kg')},
        results: [
          {'elapsed': Quantity('0.1', 'min')},
          {'elapsed': Quantity('6', 's')},
        ],
      );
      equal(summed.incrementBandAssessment!.selected!.value.toString(), '12');
      equal(summed.incrementBandAssessment!.band!.id, 'sum');
    },
  );
  test(
    'increment bands respect weighted coordination native ticks and atomic bounds without downgrading the selected band',
    () {
      final maximum = {
        ..._rule(),
        'maximums': {
          'mass': {'value': '12', 'unit': 'kg'},
        },
      };
      final blocked = _eval(['6', '6', '16'], rule: maximum, cursor: 1);
      equal(blocked.outcome, 'blocked');
      equal(blocked.cursor, 1);
      equal(blocked.incrementBandAssessment!.band!.id, 'stronger');
      equal(blocked.nextValues['mass']!.value.toString(), '10');
      final scaled = {
        ..._rule(),
        'scales': {
          'mass': {
            'scale': {
              'id': 'stack',
              'unit': 'kg',
              'ticks': [
                {'id': 'a', 'value': '10'},
                {'id': 'b', 'value': '12.5'},
                {'id': 'c', 'value': '15'},
              ],
            },
            'rounding': 'atLeast',
          },
        },
      };
      final p = _eval(['6', '6', '12'], rule: scaled);
      equal(p.nextValues['mass']!.value.toString(), '12.5');
      equal(
        p.incrementBandAssessment!.increments!['mass']!.value.toString(),
        '2',
      );
      check(p.scaleResolutions.isNotEmpty);
      final decrease = {
        ..._rule(),
        'directions': {'mass': 'decrease'},
        'minimums': {
          'mass': {'value': '8', 'unit': 'kg'},
        },
      };
      equal(
        _eval([
          '6',
          '6',
          '12',
        ], rule: decrease).nextValues['mass']!.value.toString(),
        '8',
      );
      equal(_eval(['6', '6', '16'], rule: decrease).outcome, 'blocked');
    },
  );
  test(
    'increment bands coordinate full replacement vectors across unequal targets and hold every set on any bound',
    () {
      final rule = _rule();
      rule['increments'] = {
        'mass': {'value': '1', 'unit': 'kg'},
        'distance': {'value': '1', 'unit': 'm'},
      };
      rule['incrementBands'] = {
        'aggregation': {'mode': 'last'},
        'bands': [
          {
            'id': 'bonus',
            'threshold': {'value': '12', 'unit': 'rep'},
            'increments': {
              'mass': {'value': '2', 'unit': 'kg'},
              'distance': {'value': '4', 'unit': 'm'},
            },
          },
        ],
      };
      rule['maximums'] = {
        'mass': {'value': '12', 'unit': 'kg'},
      };
      rule['resets'] = {
        'reps': {'value': '5', 'unit': 'rep'},
      };
      final sets = [
        for (var i = 0; i < 3; i++)
          TrainingSet(
            id: 'set-$i',
            slotId: 'movement',
            role: 'work',
            ordinal: i,
            suggested: {
              'mass': Quantity(i == 1 ? '11' : '10', 'kg'),
              'distance': Quantity('100', 'm'),
              'reps': Quantity('6', 'rep'),
            },
          ).complete({
            'mass': Quantity(i == 1 ? '11' : '10', 'kg'),
            'distance': Quantity('100', 'm'),
            'reps': Quantity(i == 2 ? '12' : '6', 'rep'),
          }),
      ];
      rule['coordination'] = {'mode': 'all'};
      final blocked = ProgressionEvaluation.threshold(
        ThresholdRule.fromJson(rule),
        sets,
        0,
        0,
      );
      equal(blocked.outcome, 'blocked');
      for (var i = 0; i < sets.length; i++)
        equal(
          canonicalJson(metricsToJson(blocked.nextSets[i])),
          canonicalJson(metricsToJson(sets[i].suggested)),
        );
      equal(blocked.incrementBandAssessment!.band!.id, 'bonus');
      rule['coordination'] = {
        'mode': 'priority',
        'order': ['mass', 'distance'],
      };
      final priority = ProgressionEvaluation.threshold(
        ThresholdRule.fromJson(rule),
        sets,
        0,
        0,
      );
      equal(priority.outcome, 'advance');
      equal(priority.coordination!.selectedMetric, 'distance');
      equal(
        priority.coordination!.candidates.first.blockedSets.single.ordinal,
        1,
      );
      for (var i = 0; i < sets.length; i++) {
        equal(
          priority.nextSets[i]['mass']!.value.toString(),
          i == 1 ? '11' : '10',
        );
        equal(priority.nextSets[i]['distance']!.value.toString(), '104');
        equal(priority.nextSets[i]['reps']!.value.toString(), '5');
      }
    },
  );
  test(
    'increment bands stored approvals freeze the chosen steps exclude warmups and seed every compatible working set once',
    () => _withStore((store, dir) async {
      final s = await _finish(store, 'one', 1);
      final p = await _propose(store, s.id);
      equal(p.proposal.incrementBandAssessment!.band!.id, 'strong');
      equal(
        p.proposal.incrementBandAssessment!.selected!.value.toString(),
        '12',
      );
      final service = StoredProgressionService(store);
      final accepted = await service.accept(
        s.id,
        'movement',
        p.version,
        _at(1),
      );
      for (final set in accepted.nextSets)
        equal(set['mass']!.value.toString(), '12');
      var corrected = await StoredTrainingService(store).edit(
        s.id,
        s.contentVersion,
        (s) => const TrainingService().complete(s, s.sets.last.id, {
          'reps': Quantity('16', 'rep'),
        }, acceptSuggested: true),
      );
      corrected = await StoredTrainingService(store).edit(
        corrected.id,
        corrected.contentVersion,
        (s) => s.finish(instant(1).add(const Duration(hours: 1))),
      );
      equal(
        canonicalJson((await _propose(store, s.id)).toJson()),
        canonicalJson(accepted.toJson()),
      );
      equal(
        (await service.accept(s.id, 'movement', p.version, _at(1))).sequence,
        1,
      );
      final next = await StoredTrainingService(
        store,
      ).start('next', 'bands', 1, instant(2));
      equal(next.sets.first.suggested['mass']!.value.toString(), '10');
      for (final set in next.sets.skip(1))
        equal(set.suggested['mass']!.value.toString(), '12');
      await store.archive();
    }),
  );
  test(
    'increment bands declines retain targets and coordinator while total failure applies only its deload path',
    () => _withStore((store, dir) async {
      final service = StoredProgressionService(store);
      final one = await _finish(store, 'one', 1, values: ['6', '6', '16']);
      final p = await _propose(store, one.id);
      final declined = await service.decline(
        one.id,
        'movement',
        p.version,
        _at(1),
      );
      equal(declined.cursor, 0);
      equal(declined.failedSessions, 0);
      final two = await _finish(store, 'two', 2, values: ['0', '1', '16']);
      final q = await _propose(store, two.id);
      equal(q.proposal.outcome, 'deload');
      check(q.proposal.incrementBandAssessment!.band == null);
      final reduced = await service.accept(
        two.id,
        'movement',
        q.version,
        _at(2),
      );
      equal(reduced.nextSets.first['mass']!.value.toString(), '9');
      equal(reduced.cursor, 0);
      final next = await _finish(store, 'three', 3, values: ['6', '6', '8']);
      final r = await _propose(store, next.id);
      equal(r.proposal.incrementBandAssessment!.band, null);
      equal(r.proposal.nextSets.first['mass']!.value.toString(), '10');
      await service.accept(next.id, 'movement', r.version, _at(3));
      await store.archive();
    }),
  );
  test(
    'increment bands reject stale sources forged choices changed controlled work and policy changes in resolved contexts',
    () => _withStore((store, dir) async {
      final service = StoredProgressionService(store);
      var s = await _finish(store, 'one', 1);
      final p = await _propose(store, s.id);
      final forged = copyJson(p.toJson());
      jsonObject(
        jsonObject(forged['proposal'], 'proposal')['incrementBandAssessment'],
        'bands',
      )['selectedBandId'] = 'stronger';
      rejects(() => ProgressionDecision.fromJson(forged));
      s = await StoredTrainingService(store).edit(
        s.id,
        s.contentVersion,
        (s) => const TrainingService().complete(s, s.sets.last.id, {
          'reps': Quantity('16', 'rep'),
        }, acceptSuggested: true),
      );
      await _fails(service.accept(s.id, 'movement', p.version, _at(1)));
      final q = await _propose(store, s.id);
      equal(q.proposal.incrementBandAssessment!.band!.id, 'stronger');
      s = await StoredTrainingService(store).edit(
        s.id,
        s.contentVersion,
        (s) => const TrainingService().complete(s, s.sets.last.id, {
          'mass': Quantity('12', 'kg'),
        }, acceptSuggested: true),
      );
      final review = await _propose(store, s.id);
      equal(review.proposal.outcome, 'review');
      await _fails(service.accept(s.id, 'movement', review.version, _at(1)));
      await service.decline(s.id, 'movement', review.version, _at(1));
      await _fails(
        _propose(store, s.id, rule: _rule()..remove('incrementBands')),
      );
      await store.archive();
    }),
  );
  test(
    'increment bands stay independent between simultaneous programs even with the same workout and band identities',
    () => _withStore((store, dir) async {
      final programs = ProgramService(store);
      await programs.publish(
        ProgramDefinition.fromJson({
          'id': 'shared',
          'name': 'Independent steps',
          'plan': {
            'id': 'day',
            'type': 'day',
            'templateId': 'bands',
            'revision': 1,
          },
        }),
        0,
      );
      for (final run in ['strength', 'cardio'])
        await programs.create(run, 'shared', 1, instant(1));
      for (final (run, step) in [('strength', '2'), ('cardio', '4')]) {
        final s = await _finish(store, '$run-one', 1, run: run);
        final rule = _rule();
        final bands = jsonList(
          jsonObject(rule['incrementBands'], 'bands'),
          'bands',
        );
        jsonObject(bands.first, 'band')['increments'] = {
          'mass': {'value': step, 'unit': 'kg'},
        };
        final p = await _propose(store, s.id, rule: rule);
        await StoredProgressionService(
          store,
        ).accept(s.id, 'movement', p.version, _at(1));
        final next = await programs.start(
          run,
          (await programs.run(run)).contentVersion,
          '$run-next',
          instant(2),
        );
        equal(
          next.sets.last.suggested['mass']!.value.toString(),
          step == '2' ? '12' : '14',
        );
      }
      await store.archive();
    }),
  );
  test(
    'increment bands native and pure CLI expose the same selected band and clean configuration errors',
    () => _withStore((store, dir) async {
      final s = await _finish(store, 'one', 1);
      await store.close();
      final request = {
        'schemaVersion': 1,
        'rule': _rule(),
        'current': metricsToJson(_current),
        'results': [
          for (final r in ['6', '6', '12'])
            metricsToJson({'reps': Quantity(r, 'rep')}),
        ],
      };
      final pure = const Commands().execute('progression evaluate', request);
      final cli = await invoke([
        'progression',
        'evaluate',
      ], jsonEncode(request));
      equal(cli.code, 0);
      equal(canonicalJson(jsonDecode(cli.output)), canonicalJson(pure));
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
      final proposal = jsonObject(
        jsonObject(
          jsonObject(jsonDecode(stored.output), 'response')['data'],
          'data',
        )['proposal'],
        'proposal',
      );
      equal(
        canonicalJson(proposal['incrementBandAssessment']),
        canonicalJson(
          jsonObject(pure['data'], 'data')['incrementBandAssessment'],
        ),
      );
      final bad = await invoke(
        ['progression', 'evaluate'],
        jsonEncode({
          ...request,
          'rule': {..._rule(), 'incrementBands': null},
        }),
      );
      equal(bad.code, 2);
      equal(bad.output, '');
      check(!bad.error.contains('internal'));
    }),
  );
  test(
    'increment bands approval survives process death with one chosen step and one coordinator advance',
    () => _withStore((store, dir) async {
      await _finish(store, 'one', 1);
      await _propose(store, 'one');
      await store.close();
      final binary = await compileNative(
        'test/helpers/store_owner.dart',
        '$dir/owner',
      );
      for (final mode in ['accept-rollback', 'accept-commit']) {
        final child = await Process.start(binary, [
          '$dir/db.sqlite',
          mode,
          'one',
          'movement',
          _at(1).toIso8601String(),
        ]);
        final errors = child.stderr.transform(utf8.decoder).join();
        try {
          equal(
            await child.stdout
                .transform(utf8.decoder)
                .transform(const LineSplitter())
                .first
                .timeout(const Duration(seconds: 15)),
            'ready',
          );
          child.kill(ProcessSignal.sigkill);
          await child.exitCode;
          equal(await errors, '');
        } finally {
          child.kill(ProcessSignal.sigkill);
          await child.exitCode;
        }
        final recovered = await TrainingStore.open('$dir/db.sqlite');
        try {
          final service = StoredProgressionService(recovered);
          final p = await service.decision('one', 'movement');
          equal(p.status, mode.endsWith('commit') ? 'accepted' : 'pending');
          equal(p.proposal.incrementBandAssessment!.band!.id, 'strong');
          if (p.acceptedAt != null) {
            equal(
              (await service.accept(
                'one',
                'movement',
                p.version,
                _at(1),
              )).sequence,
              1,
            );
            equal(
              (await service.accept(
                'one',
                'movement',
                p.version,
                _at(1),
              )).cursor,
              1,
            );
            final next = await _finish(recovered, 'two', 2);
            equal(next.sets.last.suggested['mass']!.value.toString(), '12');
          }
          await recovered.archive();
        } finally {
          await recovered.close();
        }
      }
    }),
  );
}
