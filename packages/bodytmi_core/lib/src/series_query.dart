import 'errors.dart';
import 'instant.dart';
import 'measure.dart';
import 'observation.dart';
import 'quantity.dart';
import 'resolution.dart';

const seriesQueryPolicy = 'bodytmi-series-query/1';
const seriesComparePolicy = 'bodytmi-series-compare/1';
const seriesSlopePolicy = 'bodytmi-series-slope/1';
const _maxPoints = 10000;
const _maxDays = 36600;

/// A local date range [from, until) of whole days.
final class DateRange {
  DateRange(this.from, this.until) {
    if (!_isDate(from) || !_isDate(until))
      invalid('from and until are valid YYYY-MM-DD dates.');
    if (days < 1) invalid('until must be after from.');
    if (days > _maxDays) invalid('A range spans at most $_maxDays days.');
  }
  factory DateRange.fromJson(Object? input, String name) {
    final j = jsonObject(input, name);
    checkKeys(j, {'from', 'until'});
    return DateRange(requiredString(j, 'from'), requiredString(j, 'until'));
  }
  final String from, until;
  int get days => _days(from, until);
  bool contains(String date) =>
      date.compareTo(from) >= 0 && date.compareTo(until) < 0;
  Map<String, Object?> toJson() => {'from': from, 'until': until};
}

/// One series (a measure and its exact attribute combination) over a date
/// range. Observations are placed by their local date (date-only entries by
/// their date); nothing is invented for days without data.
///
/// Summaries, each only if the measure declares it:
/// * `count` — observations;
/// * `sum` — exact total (an interval sums its duration in seconds);
/// * `mean` — the mean of daily means, so each day with data weighs once;
///   days without data are not zero;
/// * `min`, `max` — over observations;
/// * `last` — the chronologically last observation.
/// Quantities are reported in the dimension's canonical unit.
final class SeriesData {
  SeriesData._(this.measure, this.attributes, this.observations);

  factory SeriesData.select({
    required MeasureDefinition measure,
    required Map<String, String> attributes,
    required List<Observation> observations,
  }) {
    requireSeries(measure, attributes);
    final selected = [
      for (final o in observations)
        if (o.measureId == measure.id && _same(o.attributes, attributes)) o,
    ]..sort(_chronological);
    return SeriesData._(measure, Map.unmodifiable(attributes), selected);
  }

  final MeasureDefinition measure;
  final Map<String, String> attributes;
  final List<Observation> observations;

  List<Observation> within(DateRange range) => [
    for (final o in observations)
      if (range.contains(o.localDate)) o,
  ];

  void requireSummary(String summary) {
    if (!const {'mean', 'sum', 'min', 'max', 'last', 'count'}.contains(summary))
      invalid('summary is mean, sum, min, max, last or count.');
    if (!measure.summaries.contains(summary))
      invalid(
        'Measure ${measure.id} summarises by '
        '${measure.summaries.join(', ')}, not $summary.',
      );
  }

  Unit? get unit => measure.kind == 'quantity'
      ? Unit.values
            .firstWhere((u) => u.dimension == measure.dimension)
            .canonical
      : measure.kind == 'interval'
      ? Unit.s
      : null;

  /// The numeric value of [o]: canonical quantity, rating, or interval
  /// duration in seconds. Null for kinds without a number.
  Decimal? number(Observation o) => switch (measure.kind) {
    'quantity' => Quantity.fromJson(o.value).value,
    'rating' => Decimal.parse('${o.value}'),
    'interval' => Decimal.parse(
      '${parseInstant(jsonObject(o.value, 'interval')['end'], 'end').difference(o.observedAt!).inMicroseconds}',
    ).dividedByInt(1000000, fractionDigits: 6),
    _ => null,
  };

  Object? _output(Decimal value) => unit == null
      ? value.toString()
      : {'value': value.toString(), 'unit': unit!.name};

  /// The summary over [items] (one bucket), or null when empty.
  Object? summarise(List<Observation> items, String summary) {
    if (summary == 'count') return items.length;
    if (items.isEmpty) return null;
    if (summary == 'last') {
      final o = items.last;
      final n = number(o);
      return n == null ? o.value : _output(n);
    }
    final values = [for (final o in items) number(o)!];
    switch (summary) {
      case 'sum':
        return _output(values.reduce((a, b) => a + b));
      case 'min':
        return _output(values.reduce((a, b) => a.compareTo(b) <= 0 ? a : b));
      case 'max':
        return _output(values.reduce((a, b) => a.compareTo(b) >= 0 ? a : b));
      default:
        final daily = _dailyMeans(items);
        // Daily means are kept to 30 digits; the result rounds once.
        return _output(
          daily.values
              .reduce((a, b) => a + b)
              .dividedByInt(daily.length, fractionDigits: 30)
              .dividedByInt(1, fractionDigits: 9),
        );
    }
  }

  Map<String, Decimal> _dailyMeans(List<Observation> items) {
    final days = <String, List<Decimal>>{};
    for (final o in items) {
      days.putIfAbsent(o.localDate, () => []).add(number(o)!);
    }
    return {
      for (final e in days.entries)
        e.key: e.value
            .reduce((a, b) => a + b)
            .dividedByInt(e.value.length, fractionDigits: 30),
    };
  }

  Map<String, Object?> get _header => {
    'measure': measure.id,
    'series': {'attributes': attributes},
    'unit': ?unit?.name,
  };

  /// Policy bodytmi-series-query/1: bucket none returns each observation as
  /// a point (with its entered value and version); day, week (starting on
  /// [weekStart], 1 = Monday … 7 = Sunday) and month return one point per
  /// bucket, clipped to the range, with its summary and coverage.
  Map<String, Object?> query(
    DateRange range, {
    required String bucket,
    required String summary,
    int weekStart = DateTime.monday,
  }) {
    requireSummary(summary);
    if (weekStart < 1 || weekStart > 7)
      invalid('weekStart is 1 (Monday) to 7 (Sunday).');
    final items = within(range);
    final List<Map<String, Object?>> points;
    if (bucket == 'none') {
      if (items.length > _maxPoints)
        invalid('More than $_maxPoints points match; narrow the query.');
      points = [
        for (final o in items)
          {
            'id': o.id,
            'contentVersion': o.contentVersion,
            'date': o.localDate,
            'observedAt': ?o.observedAtText,
            if (o.value != null) 'value': o.value,
            if (number(o) != null && unit != null)
              'canonical': _output(number(o)!),
          },
      ];
    } else {
      final buckets = _buckets(range, bucket, weekStart);
      if (buckets.length > _maxPoints)
        invalid('More than $_maxPoints buckets; narrow the query.');
      final byBucket = [for (final _ in buckets) <Observation>[]];
      var b = 0;
      for (final o in items) {
        while (!buckets[b].contains(o.localDate)) {
          b++;
        }
        byBucket[b].add(o);
      }
      points = [
        for (var i = 0; i < buckets.length; i++)
          {
            ...buckets[i].toJson(),
            'observations': byBucket[i].length,
            'coverage': _coverage(byBucket[i], buckets[i]),
            'value': summarise(byBucket[i], summary),
          },
      ];
    }
    return {
      'policy': seriesQueryPolicy,
      ..._header,
      'range': range.toJson(),
      'bucket': bucket,
      if (bucket == 'week') 'weekStart': weekStart,
      'summary': summary,
      'overall': {
        'observations': items.length,
        'coverage': _coverage(items, range),
        'value': summarise(items, summary),
      },
      'points': points,
      'fingerprint': observationFingerprint(items),
    };
  }

  /// Policy bodytmi-series-compare/1: one summary over two periods with
  /// both coverages and, for numbers, the signed change from [a] to [b].
  Map<String, Object?> compare(DateRange a, DateRange b, String summary) {
    requireSummary(summary);
    Map<String, Object?> period(DateRange r) {
      final items = within(r);
      return {
        ...r.toJson(),
        'observations': items.length,
        'coverage': _coverage(items, r),
        'value': summarise(items, summary),
        'fingerprint': observationFingerprint(items),
      };
    }

    final first = period(a), second = period(b);
    final numbers =
        summary == 'count' ||
        const {'quantity', 'rating', 'interval'}.contains(measure.kind);
    Decimal? numeric(Object? v) => !numbers
        ? null
        : switch (v) {
            int() => Decimal.parse('$v'),
            String() => Decimal.parse(v),
            Map() => Decimal.parse(v['value']! as String),
            _ => null,
          };
    final x = numeric(first['value']), y = numeric(second['value']);
    return {
      'policy': seriesComparePolicy,
      ..._header,
      'summary': summary,
      'a': first,
      'b': second,
      'change': x == null || y == null
          ? null
          : summary == 'count'
          ? (y - x).toString()
          : _output(y - x),
      if (x == null || y == null)
        'changeReason': first['value'] == null || second['value'] == null
            ? 'A period has no observations.'
            : 'The summary is not a number.',
    };
  }

  /// Policy bodytmi-series-slope/1: a least-squares line through the daily
  /// means in [range], as change per [perDays] days. Needs two days with
  /// data; the fit is floating point, rounded once to nine digits.
  Map<String, Object?> slope(DateRange range, {int perDays = 7}) {
    if (!const {'quantity', 'rating'}.contains(measure.kind))
      invalid('A slope needs a quantity or rating measure.');
    if (perDays < 1 || perDays > 366) invalid('per is 1 to 366 days.');
    final items = within(range);
    final daily = _dailyMeans(items);
    final base = {
      'policy': seriesSlopePolicy,
      ..._header,
      'range': range.toJson(),
      'perDays': perDays,
      'points': daily.length,
      'fingerprint': observationFingerprint(items),
    };
    if (daily.length < 2)
      return {
        ...base,
        'status': 'unavailable',
        'reason':
            'A slope needs observations on two days; '
            'found ${daily.length}.',
      };
    final days = daily.keys.toList()..sort();
    final xs = [for (final d in days) _days(days.first, d).toDouble()];
    final ys = [for (final d in days) double.parse(daily[d]!.toString())];
    final n = xs.length;
    final mx = xs.reduce((a, b) => a + b) / n;
    final my = ys.reduce((a, b) => a + b) / n;
    var sxx = 0.0, sxy = 0.0;
    for (var i = 0; i < n; i++) {
      sxx += (xs[i] - mx) * (xs[i] - mx);
      sxy += (xs[i] - mx) * (ys[i] - my);
    }
    final perDay = sxy / sxx;
    final value = _signed9(perDay * perDays);
    return {
      ...base,
      'status': 'resolved',
      'estimate': true,
      'first': days.first,
      'last': days.last,
      'spanDays': _days(days.first, days.last),
      'slope': unit == null ? value : {'value': value, 'unit': unit!.name},
    };
  }
}

Map<String, Object?> _coverage(List<Observation> items, DateRange range) => {
  'daysWithData': {for (final o in items) o.localDate}.length,
  'days': range.days,
};

List<DateRange> _buckets(DateRange range, String bucket, int weekStart) {
  if (!const {'day', 'week', 'month'}.contains(bucket))
    invalid('bucket is none, day, week or month.');
  final result = <DateRange>[];
  var start = range.from;
  while (start.compareTo(range.until) < 0) {
    final d = DateTime.parse('${start}T00:00:00Z');
    final String next = switch (bucket) {
      'day' => _addDays(start, 1),
      'week' => _addDays(start, 7 - (d.weekday - weekStart) % 7),
      _ => DateTime.utc(d.year, d.month + 1).toIso8601String().substring(0, 10),
    };
    final end = next.compareTo(range.until) < 0 ? next : range.until;
    result.add(DateRange(start, end));
    if (result.length > _maxPoints)
      invalid('More than $_maxPoints buckets; narrow the query.');
    start = end;
  }
  return result;
}

bool _same(Map<String, String> a, Map<String, String> b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

int _chronological(Observation a, Observation b) {
  final day = a.localDate.compareTo(b.localDate);
  if (day != 0) return day;
  final at = (a.observedAt?.microsecondsSinceEpoch ?? -1).compareTo(
    b.observedAt?.microsecondsSinceEpoch ?? -1,
  );
  return at != 0 ? at : a.id.compareTo(b.id);
}

bool _isDate(String value) =>
    RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) &&
    DateTime.tryParse(
          '${value}T00:00:00Z',
        )?.toIso8601String().substring(0, 10) ==
        value;

int _days(String from, String to) => DateTime.parse(
  '${to}T00:00:00Z',
).difference(DateTime.parse('${from}T00:00:00Z')).inDays;

String _addDays(String date, int days) => DateTime.parse(
  '${date}T00:00:00Z',
).add(Duration(days: days)).toIso8601String().substring(0, 10);

String _signed9(double value) {
  final scaled = (value.abs() * 1e9).round();
  final text = Decimal.parse(
    BigInt.from(scaled).toString(),
  ).dividedByInt(1000000000).toString();
  return value < 0 && scaled != 0 ? '-$text' : text;
}
