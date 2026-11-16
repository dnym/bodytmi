import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'errors.dart';
import 'instant.dart';
import 'measure.dart';
import 'observation.dart';
import 'quantity.dart';

/// The value of one series in force at an instant (policy
/// `bodytmi-observation-resolution/1`). A series is one measure with one
/// exact attribute combination; observations with other attributes never
/// take part. A missing input is unavailable with a reason, never zero.
final class ObservationResolution {
  ObservationResolution._(this.json);
  final Map<String, Object?> json;

  bool get resolved => json['status'] == 'resolved';
  Map<String, Object?> toJson() => json;

  static const policyId = 'bodytmi-observation-resolution/1';

  factory ObservationResolution.resolve({
    required MeasureDefinition measure,
    required Map<String, String> attributes,
    required List<Observation> observations,
    required String asOfText,
    MeasurePolicy? policy,
    String dailyMode = 'mean',
  }) {
    final asOf = parseInstant(asOfText, 'asOf');
    final asOfDate = asOfText.substring(0, 10);
    if (!{'mean', 'replace'}.contains(dailyMode))
      invalid('dailyMode is mean or replace.');
    final effective = policy ?? measure.resolution;
    if (effective.policy != 'latest' && measure.kind != 'quantity')
      invalid('Only quantity measures resolve by ${effective.policy}.');
    if (effective.policy == 'trend' &&
        measure.dimension != Dimension.mass &&
        measure.dimension != Dimension.ratio)
      invalid('Trend resolution applies to mass and ratio quantities.');
    for (final key in attributes.keys) {
      if (!measure.attributes.containsKey(key))
        invalid('Measure ${measure.id} has no attribute $key.');
    }
    final eligible = [
      for (final o in observations)
        if (o.measureId == measure.id &&
            _sameAttributes(o.attributes, attributes) &&
            (o.observedAt == null
                ? o.localDate.compareTo(asOfDate) <= 0
                : !o.observedAt!.isAfter(asOf)))
          o,
    ]..sort(_chronological);
    final base = <String, Object?>{
      'policy': policyId,
      'measure': measure.id,
      'series': {'attributes': attributes},
      'asOf': asOfText,
      'resolution': effective.toJson(),
      'sourceCount': eligible.length,
      'fingerprint': _fingerprint(eligible),
    };
    if (eligible.isEmpty) {
      return ObservationResolution._({
        ...base,
        'status': 'unavailable',
        'reason': 'No observation of this series on or before asOf.',
      });
    }
    Map<String, Object?> finish(
      Map<String, Object?> value,
      String lastDate,
      String used, {
      bool estimate = false,
      Map<String, Object?> extra = const {},
    }) {
      final age = _days(lastDate, asOfDate);
      final staleAfter = effective.staleAfterDays;
      return {
        ...base,
        'status': 'resolved',
        'used': used,
        'estimate': estimate,
        'value': value['value'],
        'observedOn': lastDate,
        'ageDays': age,
        'stale': staleAfter != null && age > staleAfter,
        ...extra,
      };
    }

    final last = eligible.last;
    Map<String, Object?> latest({String? fallbackReason}) => finish(
      {'value': last.value},
      last.localDate,
      'latest',
      extra: {
        'sources': [
          {'id': last.id, 'contentVersion': last.contentVersion},
        ],
        'fallbackReason': ?fallbackReason,
      },
    );

    switch (effective.policy) {
      case 'latest':
        return ObservationResolution._(latest());
      case 'trend':
        final days = <String, List<Observation>>{};
        for (final o in eligible) {
          days.putIfAbsent(o.localDate, () => []).add(o);
        }
        Decimal? trend;
        var count = 0;
        for (final date in (days.keys.toList()..sort())) {
          final selected = dailyMode == 'replace'
              ? [days[date]!.last]
              : days[date]!;
          final daily = selected
              .fold<Decimal>(Decimal.zero, (s, o) => s + _canonical(o))
              .dividedByInt(selected.length);
          trend = count < 7
              ? daily
              : (trend! + (daily - trend) * Decimal.parse('0.1')).dividedByInt(
                  1,
                );
          count++;
        }
        return ObservationResolution._(
          finish(
            {
              'value': {
                'value': trend.toString(),
                'unit': measure.dimension!.canonicalUnit.name,
              },
            },
            last.localDate,
            'trend',
            extra: {'dailyMode': dailyMode, 'days': count},
          ),
        );
      default:
        // The recent window ends at the last observation in force.
        final windowStart = _addDays(last.localDate, -effective.windowDays);
        final window = [
          for (final o in eligible)
            if (o.localDate.compareTo(windowStart) > 0) o,
        ];
        if (window.length < effective.minPoints)
          return ObservationResolution._(
            latest(
              fallbackReason:
                  '${window.length} observations in the ${effective.windowDays} days '
                  'up to the last one; extrapolation needs '
                  '${effective.minPoints}.',
            ),
          );
        final first = window.first.localDate, end = window.last.localDate;
        final span = _days(first, end);
        if (span < effective.minSpanDays)
          return ObservationResolution._(
            latest(
              fallbackReason:
                  'The observations span $span days; extrapolation needs '
                  '${effective.minSpanDays}.',
            ),
          );
        final xs = [for (final o in window) _days(first, o.localDate)];
        final ys = [for (final o in window) _canonical(o).toDouble()];
        final n = xs.length;
        final mx = xs.reduce((a, b) => a + b) / n;
        final my = ys.reduce((a, b) => a + b) / n;
        var sxx = 0.0, sxy = 0.0;
        for (var i = 0; i < n; i++) {
          sxx += (xs[i] - mx) * (xs[i] - mx);
          sxy += (xs[i] - mx) * (ys[i] - my);
        }
        final slope = sxx == 0 ? 0.0 : sxy / sxx;
        final ahead = _days(end, asOfDate);
        final capped = ahead > effective.maxAheadDays;
        final atDay =
            _days(first, end) + (capped ? effective.maxAheadDays : ahead);
        final estimate = my + slope * (atDay - mx);
        if (estimate < 0)
          return ObservationResolution._({
            ...base,
            'status': 'unavailable',
            'reason': 'The fitted line falls below zero by the requested date.',
          });
        final unit = measure.dimension!.canonicalUnit.name;
        return ObservationResolution._(
          finish(
            {
              'value': {'value': _round9(estimate), 'unit': unit},
            },
            end,
            'extrapolated',
            estimate: true,
            extra: {
              'extrapolation': {
                'slopePerDay': {'value': _signed9(slope), 'unit': unit},
                'points': n,
                'from': first,
                'to': end,
                'evaluatedOn': _addDays(first, atDay),
                'capped': capped,
              },
              'sources': [
                for (final o in window)
                  {'id': o.id, 'contentVersion': o.contentVersion},
              ],
            },
          ),
        );
    }
  }
}

bool _sameAttributes(Map<String, String> a, Map<String, String> b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

int _chronological(Observation a, Observation b) {
  final day = a.localDate.compareTo(b.localDate);
  if (day != 0) return day;
  final at = (a.observedAt?.microsecondsSinceEpoch ?? -1).compareTo(
    b.observedAt?.microsecondsSinceEpoch ?? -1,
  );
  return at != 0 ? at : a.id.compareTo(b.id);
}

Decimal _canonical(Observation o) => Quantity.fromJson(o.value).value;

int _days(String from, String to) => DateTime.parse(
  '${to}T00:00:00Z',
).difference(DateTime.parse('${from}T00:00:00Z')).inDays;

String _addDays(String date, int days) => DateTime.parse(
  '${date}T00:00:00Z',
).add(Duration(days: days)).toIso8601String().substring(0, 10);

/// Rounds a double once to nine fractional digits, half away from zero.
String _round9(double value) => _signed9(value);
String _signed9(double value) {
  final scaled = (value.abs() * 1e9).round();
  final text = Decimal.parse(
    (BigInt.from(scaled)).toString(),
  ).dividedByInt(1000000000).toString();
  return value < 0 && scaled != 0 ? '-$text' : text;
}

Map<String, Object?> _fingerprint(List<Observation> sources) => {
  'sourceCount': sources.length,
  'sha256': sha256
      .convert(
        utf8.encode(
          jsonEncode([
            for (final o in sources)
              [o.id, o.contentVersion, o.observedAtText, o.date, o.value],
          ]),
        ),
      )
      .toString(),
};

extension on Dimension {
  Unit get canonicalUnit =>
      Unit.values.firstWhere((u) => u.dimension == this).canonical;
}

extension on Decimal {
  double toDouble() => double.parse(toString());
}
