import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'cli_test.dart';
import 'support.dart';

Map<String, Object?> _q(String value, String unit) => {
  'value': value,
  'unit': unit,
};

MeasureDefinition _measure(String id) =>
    builtInMeasures.firstWhere((m) => m.id == id);

Observation _obs(
  String id,
  String measure,
  Object? value, {
  String? date,
  String? at,
  Map<String, String>? attributes,
}) => Observation.fromJson({
  'id': id,
  'measure': measure,
  'value': value,
  'date': ?date,
  'observedAt': ?at,
  'attributes': ?attributes,
});

Object? _value(Map<String, Object?> point) {
  final v = point['value'];
  return v is Map ? v['value'] : v;
}

void seriesQueryTests() {
  test('series buckets, coverage and summaries', () {
    // 2026-11-02 is a Monday. Steps on six days, two entries on the 3rd.
    final steps = SeriesData.select(
      measure: _measure('steps'),
      attributes: const {},
      observations: [
        for (final (id, date, n) in [
          ('a', '2026-10-31', '1000'),
          ('b', '2026-11-02', '8000'),
          ('c', '2026-11-03', '6000'),
          ('d', '2026-11-03', '2000'),
          ('e', '2026-11-08', '10000'),
          ('f', '2026-11-09', '7000'),
          ('g', '2026-12-01', '5000'),
        ])
          _obs(id, 'steps', _q(n, 'step'), date: date),
        _obs(
          'other',
          'body-mass',
          _q('80', 'kg'),
          at: '2026-11-02T07:00:00+01:00',
          attributes: {'context': 'health'},
        ),
      ],
    );
    final range = DateRange('2026-11-01', '2026-11-15');
    final weekly = steps.query(range, bucket: 'week', summary: 'sum');
    equal(weekly['policy'], 'bodytmi-series-query/1');
    equal(weekly['unit'], 'step');
    final points = (weekly['points']! as List).cast<Map<String, Object?>>();
    // Sunday 1st (clipped), Mon 2nd–Sun 8th, Mon 9th–14th (clipped).
    jsonEqual(
      [
        for (final p in points) [p['from'], p['until']],
      ],
      [
        ['2026-11-01', '2026-11-02'],
        ['2026-11-02', '2026-11-09'],
        ['2026-11-09', '2026-11-15'],
      ],
    );
    jsonEqual([for (final p in points) _value(p)], [null, '26000', '7000']);
    jsonEqual(points[1]['coverage'], {'daysWithData': 3, 'days': 7});
    equal(points[1]['observations'], 4);
    jsonEqual(points[0]['coverage'], {'daysWithData': 0, 'days': 1});
    // Sunday weeks.
    final sundays = steps.query(
      range,
      bucket: 'week',
      summary: 'sum',
      weekStart: 7,
    );
    jsonEqual(
      [
        for (final p
            in (sundays['points']! as List).cast<Map<String, Object?>>())
          p['from'],
      ],
      ['2026-11-01', '2026-11-08'],
    );
    // Mean of daily means: (8000 + 4000 + 10000 + 7000) / 4 days.
    final mean = steps.query(range, bucket: 'none', summary: 'mean');
    equal(_value(jsonObject(mean['overall'], 'o')), '7250');
    equal((mean['points']! as List).length, 5);
    final firstPoint = jsonObject((mean['points']! as List).first, 'p');
    equal(firstPoint['date'], '2026-11-02');
    equal(firstPoint['contentVersion'], 1);
    // Months, clipped.
    final monthly = steps.query(
      DateRange('2026-10-15', '2026-12-10'),
      bucket: 'month',
      summary: 'count',
    );
    jsonEqual(
      [
        for (final p
            in (monthly['points']! as List).cast<Map<String, Object?>>())
          [p['from'], p['until'], p['value']],
      ],
      [
        ['2026-10-15', '2026-11-01', 1],
        ['2026-11-01', '2026-12-01', 5],
        ['2026-12-01', '2026-12-10', 1],
      ],
    );
    // Every daily bucket over a year.
    final daily = steps.query(
      DateRange('2026-01-01', '2027-01-01'),
      bucket: 'day',
      summary: 'max',
    );
    equal((daily['points']! as List).length, 365);

    // Undeclared summaries and bad ranges are refused.
    rejects(
      () => SeriesData.select(
        measure: _measure('height'),
        attributes: const {},
        observations: const [],
      ).query(range, bucket: 'none', summary: 'mean'),
    );
    rejects(() => DateRange('2026-11-02', '2026-11-02'));
    rejects(() => DateRange('2026-02-30', '2026-03-02'));
    rejects(() => steps.query(range, bucket: 'year', summary: 'sum'));
    rejects(
      () => SeriesData.select(
        measure: _measure('circumference'),
        attributes: const {'site': 'elbow'},
        observations: const [],
      ),
    );
  });

  test('series compare and slope', () {
    // Left and right arm never merge: the left series ignores the right.
    final arms = SeriesData.select(
      measure: _measure('circumference'),
      attributes: const {'site': 'upper-arm', 'side': 'left'},
      observations: [
        _obs(
          'l1',
          'circumference',
          _q('35', 'cm'),
          date: '2026-10-05',
          attributes: {'site': 'upper-arm', 'side': 'left'},
        ),
        _obs(
          'l2',
          'circumference',
          _q('36.5', 'cm'),
          date: '2026-11-05',
          attributes: {'site': 'upper-arm', 'side': 'left'},
        ),
        _obs(
          'r1',
          'circumference',
          _q('50', 'cm'),
          date: '2026-11-06',
          attributes: {'site': 'upper-arm', 'side': 'right'},
        ),
      ],
    );
    final compared = arms.compare(
      DateRange('2026-10-01', '2026-11-01'),
      DateRange('2026-11-01', '2026-12-01'),
      'max',
    );
    equal(compared['policy'], 'bodytmi-series-compare/1');
    jsonEqual(compared['change'], {'value': '0.015', 'unit': 'm'});
    jsonEqual(jsonObject(compared['b'], 'b')['coverage'], {
      'daysWithData': 1,
      'days': 30,
    });
    final empty = arms.compare(
      DateRange('2026-09-01', '2026-10-01'),
      DateRange('2026-11-01', '2026-12-01'),
      'max',
    );
    equal(empty['change'], null);
    equal(empty['changeReason'], 'A period has no observations.');

    // Mass falling 0.1 kg a day: −0.7 kg per week, two readings a day
    // averaged first.
    final mass = SeriesData.select(
      measure: _measure('body-mass'),
      attributes: const {'context': 'health'},
      observations: [
        for (var day = 0; day < 20; day++) ...[
          for (final (hour, offset) in [(7, '-0.2'), (21, '0.2')])
            _obs(
              'm$day-$hour',
              'body-mass',
              _q(
                (Decimal.parse('${900 - day}').dividedByInt(10) +
                        Decimal.parse(offset))
                    .toString(),
                'kg',
              ),
              at:
                  '${DateTime.utc(2026, 10, 1 + day).toIso8601String().substring(0, 10)}'
                  'T${hour.toString().padLeft(2, '0')}:00:00+01:00',
              attributes: {'context': 'health'},
            ),
        ],
      ],
    );
    final slope = mass.slope(DateRange('2026-10-01', '2026-11-01'));
    equal(slope['status'], 'resolved');
    jsonEqual(slope['slope'], {'value': '-0.7', 'unit': 'kg'});
    equal(slope['points'], 20);
    equal(slope['spanDays'], 19);
    final monthly = mass.slope(
      DateRange('2026-10-01', '2026-11-01'),
      perDays: 30,
    );
    jsonEqual(monthly['slope'], {'value': '-3', 'unit': 'kg'});
    final one = mass.slope(DateRange('2026-10-01', '2026-10-02'));
    equal(one['status'], 'unavailable');
    rejects(
      () => SeriesData.select(
        measure: _measure('body-mass'),
        attributes: const {'context': 'health'},
        observations: const [],
      ).slope(DateRange('2026-10-01', '2026-10-02'), perDays: 0),
    );
  });

  test('CLI series query, compare and slope', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-series-');
    final db = '${dir.path}/db.sqlite';
    Future<({int code, Object? data, String error})> cli(
      String name,
      Map<String, Object?> fields,
    ) async {
      final r = await invoke(
        name.split(' '),
        jsonEncode({'schemaVersion': 1, 'database': db, ...fields}),
      );
      return (
        code: r.code,
        data: r.code == 0
            ? jsonObject(jsonDecode(r.output), 'r')['data']
            : null,
        error: r.error,
      );
    }

    try {
      final imported = await cli('observation import-apply', {
        'confirm': true,
        'document': {
          'format': 'bodytmi-observation-import/1',
          'source': {'namespace': 'band'},
          'observations': [
            for (var day = 0; day < 28; day++)
              {
                'sourceId': 'steps-$day',
                'measure': 'steps',
                'value': _q('${5000 + day * 100}', 'step'),
                'date': DateTime.utc(
                  2026,
                  11,
                  2 + day,
                ).toIso8601String().substring(0, 10),
              },
          ],
        },
      });
      check(imported.code == 0, imported.error);
      // A deleted day drops out of every summary.
      final days =
          (await cli('observation list', {'measure': 'steps'})).data! as List;
      final first = jsonObject(jsonObject(days.first, 'r')['observation'], 'o');
      check(
        (await cli('observation delete', {
              'id': first['id'],
              'expectedVersion': 1,
              'confirm': true,
            })).code ==
            0,
      );
      final weekly = await cli('series query', {
        'measure': 'steps',
        'from': '2026-11-02',
        'until': '2026-11-30',
        'bucket': 'week',
        'summary': 'sum',
      });
      check(weekly.code == 0, weekly.error);
      final points = (jsonObject(weekly.data, 'w')['points']! as List)
          .cast<Map<String, Object?>>();
      equal(points.length, 4);
      // Week one: 5100..5600 (5000 deleted) = 32100 over six days.
      equal(_value(points.first), '32100');
      jsonEqual(points.first['coverage'], {'daysWithData': 6, 'days': 7});
      equal(
        _value(points.last),
        '${[for (var d = 21; d < 28; d++) 5000 + d * 100].reduce((a, b) => a + b)}',
      );
      final compared = await cli('series compare', {
        'measure': 'steps',
        'a': {'from': '2026-11-02', 'until': '2026-11-09'},
        'b': {'from': '2026-11-23', 'until': '2026-11-30'},
        'summary': 'mean',
      });
      check(compared.code == 0, compared.error);
      // Means 5350 (six days) and 7400: change 2050 steps a day.
      jsonEqual(jsonObject(compared.data, 'c')['change'], {
        'value': '2050',
        'unit': 'step',
      });
      final slope = await cli('series slope', {
        'measure': 'steps',
        'from': '2026-11-02',
        'until': '2026-11-30',
      });
      jsonEqual(jsonObject(slope.data, 's')['slope'], {
        'value': '700',
        'unit': 'step',
      });
      equal(
        (await cli('series query', {
          'measure': 'steps',
          'from': '2026-11-02',
          'until': '2026-11-30',
          'summary': 'median',
        })).code,
        2,
      );
      equal(
        (await cli('series query', {
          'measure': 'no-such',
          'from': '2026-11-02',
          'until': '2026-11-30',
          'summary': 'sum',
        })).code,
        3,
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
