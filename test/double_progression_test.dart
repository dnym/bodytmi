import 'package:bodytmi_core/bodytmi_core.dart';
import 'fixtures.dart';
import 'support.dart';

Map<String, Object?> doubleRuleJson() => {
  'objective': 'reps',
  'lever': 'mass',
  'lower': {'value': '8', 'unit': 'rep'},
  'upper': {'value': '12', 'unit': 'rep'},
  'objectiveStep': {'value': '1', 'unit': 'rep'},
  'leverStep': {'value': '2.5', 'unit': 'kg'},
};
List<Metrics> workingSets(List<String> reps, {String mass = '80'}) => [
  for (final count in reps)
    metrics({
      'reps': (count, 'rep'),
      'mass': (mass, 'kg'),
      'tempo': ('3', 's'),
    }),
];

void doubleProgressionTests() {
  test(
    'double progression increments every set 8 through 12 then load and reset',
    () {
      final rule = DoubleProgressionRule.fromJson(doubleRuleJson());
      var targets = workingSets(['8', '8', '8']);
      for (var n = 8; n < 12; n++) {
        final proposal = rule.evaluate(
          currentSets: targets,
          results: workingSets(['$n', '$n', '$n']),
        );
        equal(proposal.outcome, 'increaseObjective');
        for (final set in proposal.nextSets) {
          equal(set['reps']!.value.toString(), '${n + 1}');
          equal(set['mass']!.value.toString(), '80');
          equal(set['tempo']!.value.toString(), '3');
        }
        targets = proposal.nextSets;
      }
      final next = rule.evaluate(
        currentSets: targets,
        results: workingSets(['12', '12', '12']),
      );
      equal(next.outcome, 'increaseLever');
      for (final set in next.nextSets) {
        equal(set['mass']!.value.toString(), '82.5');
        equal(set['reps']!.value.toString(), '8');
      }
    },
  );
  test(
    'double progression can increment unequal targets together with an upper cap',
    () {
      final rule = DoubleProgressionRule.fromJson(doubleRuleJson());
      final input = workingSets(['10', '11', '12']);
      final next = rule.evaluate(currentSets: input, results: input);
      equal(next.outcome, 'increaseObjective');
      equal(
        next.nextSets.map((s) => s['reps']!.value.toString()).join(','),
        '11,12,12',
      );
      equal(input.first['reps']!.value.toString(), '10');
    },
  );
  test(
    'overperforming one set does not increase load before the other sets',
    () {
      final rule = DoubleProgressionRule.fromJson(doubleRuleJson());
      final next = rule.evaluate(
        currentSets: workingSets(['8', '8', '8']),
        results: workingSets(['12', '8', '8']),
      );
      equal(next.outcome, 'increaseObjective');
      equal(
        next.nextSets.map((s) => s['reps']!.value.toString()).join(','),
        '9,9,9',
      );
    },
  );
  test(
    'all actual ceilings may trigger lever progression even before planned ceilings',
    () {
      final rule = DoubleProgressionRule.fromJson(doubleRuleJson());
      final next = rule.evaluate(
        currentSets: workingSets(['8', '8', '8']),
        results: workingSets(['13', '12', '12']),
      );
      equal(next.outcome, 'increaseLever');
      equal(next.nextSets.first['mass']!.value.toString(), '82.5');
    },
  );
  test(
    'underperforming prescribed targets adds one failed workout and holds all targets',
    () {
      final rule = DoubleProgressionRule.fromJson(doubleRuleJson());
      final input = workingSets(['10', '10', '10']);
      final next = rule.evaluate(
        currentSets: input,
        results: workingSets(['10', '9', '8']),
        failedSessions: 1,
      );
      equal(next.outcome, 'failed');
      equal(next.failedSessions, 2);
      jsonEqual(
        next.nextSets.map(metricsToJson).toList(),
        input.map(metricsToJson).toList(),
      );
    },
  );
  test(
    'third failed double-progression exposure deloads all loads and resets rep targets',
    () {
      final rule = DoubleProgressionRule.fromJson(doubleRuleJson());
      final next = rule.evaluate(
        currentSets: workingSets(['10', '10', '10'], mass: '100'),
        results: workingSets(['10', '9', '8'], mass: '100'),
        failedSessions: 2,
      );
      equal(next.outcome, 'deload');
      equal(next.failedSessions, 0);
      for (final set in next.nextSets) {
        equal(set['mass']!.value.toString(), '90');
        equal(set['reps']!.value.toString(), '8');
      }
    },
  );
  test(
    'meeting every current target resets the consecutive failure counter',
    () {
      final rule = DoubleProgressionRule.fromJson(doubleRuleJson());
      final next = rule.evaluate(
        currentSets: workingSets(['10', '10', '10']),
        results: workingSets(['10', '10', '10']),
        failedSessions: 2,
      );
      equal(next.failedSessions, 0);
      equal(next.outcome, 'increaseObjective');
    },
  );
  test(
    'a changed actual load requires review instead of rewarding the old prescription',
    () {
      final rule = DoubleProgressionRule.fromJson(doubleRuleJson());
      final next = rule.evaluate(
        currentSets: workingSets(['12', '12', '12']),
        results: workingSets(['12', '12', '12'], mass: '70'),
        failedSessions: 1,
      );
      equal(next.outcome, 'review');
      equal(next.failedSessions, 1);
      equal(next.nextSets.first['mass']!.value.toString(), '80');
    },
  );
  test('missing/skipped required results do not count as failures', () {
    final rule = DoubleProgressionRule.fromJson(doubleRuleJson());
    for (final result in <List<Metrics?>>[
      [null],
      [
        metrics({'reps': ('10', 'rep')}),
      ],
    ]) {
      final next = rule.evaluate(
        currentSets: workingSets(['10']),
        results: result,
        failedSessions: 2,
      );
      equal(next.outcome, 'unknown');
      equal(next.failedSessions, 2);
    }
  });
  test(
    'one bound blocks the entire load/reset transition without partial writes',
    () {
      final rule = DoubleProgressionRule.fromJson({
        ...doubleRuleJson(),
        'maximumLever': {'value': '103', 'unit': 'kg'},
      });
      final targets = [
        for (final mass in ['100', '101', '102'])
          ...workingSets(['12'], mass: mass),
      ];
      final next = rule.evaluate(currentSets: targets, results: targets);
      equal(next.outcome, 'blocked');
      jsonEqual(
        next.nextSets.map(metricsToJson).toList(),
        targets.map(metricsToJson).toList(),
      );
    },
  );
  test(
    'objective increments larger than remaining range clamp to the ceiling',
    () {
      final rule = DoubleProgressionRule.fromJson({
        ...doubleRuleJson(),
        'objectiveStep': {'value': '3', 'unit': 'rep'},
      });
      final next = rule.evaluate(
        currentSets: workingSets(['10']),
        results: workingSets(['10']),
      );
      equal(next.nextSets.single['reps']!.value.toString(), '12');
    },
  );
  test(
    'double progression applies to timed objectives without exercise-name logic',
    () {
      final rule = DoubleProgressionRule.fromJson({
        'objective': 'duration',
        'lever': 'mass',
        'lower': {'value': '10', 'unit': 's'},
        'upper': {'value': '60', 'unit': 's'},
        'objectiveStep': {'value': '5', 'unit': 's'},
        'leverStep': {'value': '2.5', 'unit': 'kg'},
      });
      final target = metrics({'duration': ('60', 's'), 'mass': ('0', 'kg')});
      final next = rule.evaluate(
        currentSets: [target, target],
        results: [target, target],
      );
      equal(next.outcome, 'increaseLever');
      equal(next.nextSets.first['mass']!.value.toString(), '2.5');
      equal(next.nextSets.first['duration']!.value.toString(), '10');
    },
  );
  test('equivalent actual lever units are compatible', () {
    final rule = DoubleProgressionRule.fromJson(doubleRuleJson());
    final target = metrics({'reps': ('8', 'rep'), 'mass': ('100', 'lb')});
    final actual = metrics({'reps': ('8', 'rep'), 'mass': ('45.359237', 'kg')});
    equal(
      rule.evaluate(currentSets: [target], results: [actual]).outcome,
      'increaseObjective',
    );
  });
  test(
    'invalid double-progression dimensions, target vectors and states fail explicitly',
    () {
      final rule = DoubleProgressionRule.fromJson(doubleRuleJson());
      rejects(
        () => rule.evaluate(currentSets: workingSets(['8']), results: const []),
      );
      rejects(() => rule.evaluate(currentSets: const [], results: const []));
      rejects(
        () => rule.evaluate(
          currentSets: workingSets(['7']),
          results: workingSets(['8']),
        ),
      );
      rejects(
        () => rule.evaluate(
          currentSets: workingSets(['8']),
          results: workingSets(['8']),
          failedSessions: -1,
        ),
      );
      rejects(
        () => DoubleProgressionRule.fromJson({
          ...doubleRuleJson(),
          'objective': 'mass',
        }),
      );
      rejects(
        () => DoubleProgressionRule.fromJson({
          ...doubleRuleJson(),
          'lower': {'value': '13', 'unit': 'rep'},
        }),
      );
      rejects(
        () => DoubleProgressionRule.fromJson({
          ...doubleRuleJson(),
          'objectiveStep': {'value': '1', 'unit': 's'},
        }),
      );
      rejects(
        () => DoubleProgressionRule.fromJson({
          ...doubleRuleJson(),
          'deloadPercent': 10,
        }),
      );
    },
  );
  test(
    'proposals are immutable and deterministic but never claim application',
    () {
      final rule = DoubleProgressionRule.fromJson(doubleRuleJson());
      final targets = workingSets(['8']);
      final a = rule.evaluate(currentSets: targets, results: targets);
      final b = rule.evaluate(currentSets: targets, results: targets);
      jsonEqual(a.toJson(), b.toJson());
      equal(a.toJson()['requiresAcceptance'], true);
      var immutable = false;
      try {
        a.nextSets.first.clear();
      } on UnsupportedError {
        immutable = true;
      }
      check(immutable);
      equal(targets.single['reps']!.value.toString(), '8');
    },
  );
}
