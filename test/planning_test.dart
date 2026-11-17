import 'package:bodytmi_core/bodytmi_core.dart';

import 'support.dart';

void planningTests() {
  test('daily metrics, targets and planning records validate', () {
    DailyMetric.fromJson({'source': 'sleep', 'field': 'onsetClock'});
    DailyMetric.fromJson({
      'source': 'observation',
      'measure': 'pain',
      'attributes': {'site': 'knee'},
      'summary': 'max',
    });
    rejects(() => DailyMetric.fromJson({'source': 'weather'}));
    rejects(() => DailyMetric.fromJson({'source': 'sleep', 'field': 'naps'}));
    rejects(
      () => DailyMetric.fromJson({
        'source': 'observation',
        'measure': 'body-mass',
        'resolved': true,
        'summary': 'mean',
      }),
    );
    rejects(
      () => DailyMetric.fromJson({
        'source': 'activity',
        'category': 'movement',
        'kind': 'walk',
        'field': 'minutes',
      }),
    );
    final within = Target.fromJson({
      'relation': 'within',
      'minimum': '420',
      'maximum': '540',
    });
    check(within.met(480) && !within.met(400));
    rejects(
      () => Target.fromJson({
        'relation': 'within',
        'minimum': '5',
        'maximum': '4',
      }),
    );
    final stats = describeValues([
      (date: 'a', status: 'value', value: 1),
      (date: 'b', status: 'value', value: 2),
      (date: 'c', status: 'unknown', value: null),
      (date: 'd', status: 'value', value: 6),
    ]);
    equal(stats['known'], 3);
    equal(stats['mean'], 3.0);
    equal(stats['median'], 2.0);
    equal(stats['sd'], 2.646);
    rejects(
      () => Goal.fromJson({
        'id': 'g',
        'version': 1,
        'name': 'G',
        'metric': {'source': 'sleep', 'field': 'onsetClock'},
        'aggregate': 'sum',
        'target': {'relation': 'atMost', 'value': '0'},
        'from': '2026-11-01',
        'status': 'active',
      }),
    );
    final r = Routine.fromJson({
      'id': 'r',
      'version': 1,
      'name': 'R',
      'action': {'kind': 'check'},
      'schedule': {
        'weekdays': [1, 3, 5],
        'relative': {'anchor': 'meal', 'meal': 'lunch', 'offsetMinutes': 60},
      },
      'from': '2026-11-16',
    });
    check(r.activeOn('2026-11-16') && !r.activeOn('2026-11-17'));
    check(!r.activeOn('2026-11-09'));
    rejects(
      () => Routine.fromJson({
        'id': 'r',
        'version': 1,
        'name': 'R',
        'action': {'kind': 'check'},
        'schedule': {
          'relative': {'anchor': 'meal'},
        },
        'from': '2026-11-16',
      }),
    );
  });
}
