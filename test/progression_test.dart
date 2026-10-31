import 'package:bodytmi_core/bodytmi_core.dart';
import 'fixtures.dart';
import 'support.dart';

void progressionTests() {
  ThresholdRule hangRule() =>
      ThresholdRule.fromJson(example('hang-progression')['rule']);
  final current = metrics({'mass': ('0', 'kg'), 'duration': ('60', 's')});
  List<Metrics?> holds(List<String> seconds) => [
    for (final value in seconds) metrics({'duration': (value, 's')}),
  ];

  test(
    'inclusive hold threshold proposes added mass and duration reset together',
    () {
      final before = metricsToJson(current);
      final result = hangRule().evaluate(
        current: current,
        results: holds(['60', '62', '60']),
      );
      equal(result.outcome, 'advance');
      equal(result.nextValues['mass']!.value.toString(), '2.5');
      equal(result.nextValues['duration']!.value.toString(), '10');
      jsonEqual(metricsToJson(current), before);
    },
  );
  test(
    'mixed upper-threshold performance holds instead of inventing success',
    () {
      final result = hangRule().evaluate(
        current: current,
        results: holds(['60', '62', '25']),
      );
      equal(result.outcome, 'hold');
      equal(result.nextValues['mass']!.value.toString(), '0');
    },
  );
  test(
    'several failed sets contribute one failed exposure, not one per set',
    () {
      final result = hangRule().evaluate(
        current: current,
        results: holds(['5', '4', '3']),
        failedSessions: 1,
      );
      equal(result.outcome, 'failed');
      equal(result.failedSessions, 2);
    },
  );
  test('successful exposure resets consecutive failure counter', () {
    final result = hangRule().evaluate(
      current: current,
      results: holds(['30', '30', '30']),
      failedSessions: 2,
    );
    equal(result.outcome, 'hold');
    equal(result.failedSessions, 0);
  });
  test(
    'empty/skipped/missing work cannot progress or add failure penalties',
    () {
      for (final results in <List<Metrics?>>[
        [],
        [null],
        [
          metrics({'mass': ('5', 'kg')}),
        ],
      ]) {
        final result = hangRule().evaluate(
          current: current,
          results: results,
          failedSessions: 2,
        );
        equal(result.outcome, 'unknown');
        equal(result.failedSessions, 2);
      }
    },
  );
  test(
    'configured third failed session proposes exactly ten percent deload',
    () {
      final json = jsonObject(example('hang-progression')['rule'], 'rule');
      json['deloadMetrics'] = ['mass'];
      final rule = ThresholdRule.fromJson(json);
      final result = rule.evaluate(
        current: metrics({'mass': ('100', 'kg'), 'duration': ('60', 's')}),
        results: holds(['2', '3', '4']),
        failedSessions: 2,
      );
      equal(result.outcome, 'deload');
      equal(result.nextValues['mass']!.value.toString(), '90');
      equal(result.failedSessions, 0);
    },
  );
  test(
    'weighted 3:2:1 selects one step per event and wraps deterministically',
    () {
      final rule = ThresholdRule.fromJson({
        'metric': 'reps',
        'minimum': {'value': '8', 'unit': 'rep'},
        'threshold': {'value': '8', 'unit': 'rep'},
        'increments': {
          'one': {'value': '1', 'unit': 'kg'},
          'two': {'value': '1', 'unit': 'm'},
          'three': {'value': '1', 'unit': 's'},
        },
        'coordination': {
          'mode': 'weighted',
          'order': ['one', 'one', 'one', 'two', 'two', 'three'],
        },
      });
      var values = metrics({
        'one': ('0', 'kg'),
        'two': ('0', 'm'),
        'three': ('0', 's'),
      });
      var cursor = 0;
      final changed = <String>[];
      for (var i = 0; i < 12; i++) {
        final result = rule.evaluate(
          current: values,
          results: [
            metrics({'reps': ('8', 'rep')}),
          ],
          cursor: cursor,
        );
        changed.add(
          values.keys.singleWhere(
            (k) => result.nextValues[k]!.compareTo(values[k]!) != 0,
          ),
        );
        values = result.nextValues;
        cursor = result.cursor;
      }
      equal(
        changed.join(','),
        'one,one,one,two,two,three,one,one,one,two,two,three',
      );
      equal(cursor, 0);
    },
  );
  test('all-together bound failure holds all values and cursor', () {
    final json = jsonObject(example('hang-progression')['rule'], 'rule');
    json['maximums'] = {
      'mass': {'value': '1', 'unit': 'kg'},
    };
    final result = ThresholdRule.fromJson(
      json,
    ).evaluate(current: current, results: holds(['60']));
    equal(result.outcome, 'blocked');
    jsonEqual(metricsToJson(result.nextValues), metricsToJson(current));
    equal(result.cursor, 0);
  });
  test('reset targets are bounded atomically too', () {
    final json = jsonObject(example('hang-progression')['rule'], 'rule');
    json['maximums'] = {
      'duration': {'value': '5', 'unit': 's'},
    };
    final result = ThresholdRule.fromJson(
      json,
    ).evaluate(current: current, results: holds(['60']));
    equal(result.outcome, 'blocked');
    jsonEqual(metricsToJson(result.nextValues), metricsToJson(current));
  });
  test(
    'threshold engine handles repetitions without exercise-specific logic',
    () {
      final rule = ThresholdRule.fromJson({
        'metric': 'reps',
        'minimum': {'value': '8', 'unit': 'rep'},
        'threshold': {'value': '12', 'unit': 'rep'},
        'increments': {
          'mass': {'value': '2.5', 'unit': 'kg'},
        },
        'resets': {
          'reps': {'value': '8', 'unit': 'rep'},
        },
      });
      final result = rule.evaluate(
        current: metrics({'mass': ('80', 'kg'), 'reps': ('12', 'rep')}),
        results: [
          metrics({'reps': ('12', 'rep')}),
          metrics({'reps': ('13', 'rep')}),
        ],
      );
      equal(result.nextValues['mass']!.value.toString(), '82.5');
      equal(result.nextValues['reps']!.value.toString(), '8');
    },
  );
  test('invalid bounds, state and unit combinations are rejected', () {
    final json = jsonObject(example('hang-progression')['rule'], 'rule');
    json['deloadPercent'] = 10;
    rejects(() => ThresholdRule.fromJson(json));
    rejects(
      () => hangRule().evaluate(
        current: current,
        results: holds(['60']),
        cursor: -1,
      ),
    );
    rejects(
      () => hangRule().evaluate(
        current: current,
        results: [
          metrics({'duration': ('60', 'kg')}),
        ],
      ),
    );
    rejects(
      () => hangRule().evaluate(
        current: metrics({'mass': ('1', 's'), 'duration': ('60', 's')}),
        results: holds(['60']),
      ),
    );
  });
}
