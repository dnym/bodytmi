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
    String? policySource,
  }) {
    final asOf = parseInstant(asOfText, 'asOf');
    final asOfDate = asOfText.substring(0, 10);
    if (!{'mean', 'replace'}.contains(dailyMode))
      invalid('dailyMode is mean or replace.');
    final effective = policy ?? measure.resolution;
    requirePolicyFits(measure, effective);
    requireSeries(measure, attributes);
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
      'policySource': policySource ?? (policy == null ? 'default' : 'request'),
      'sourceCount': eligible.length,
      'fingerprint': observationFingerprint(eligible),
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

/// A policy a measure kind supports: trend for mass and ratio quantities,
/// extrapolation for quantities, latest for anything.
void requirePolicyFits(MeasureDefinition measure, MeasurePolicy policy) {
  if (policy.policy != 'latest' && measure.kind != 'quantity')
    invalid('Only quantity measures resolve by ${policy.policy}.');
  if (policy.policy == 'trend' &&
      measure.dimension != Dimension.mass &&
      measure.dimension != Dimension.ratio)
    invalid('Trend resolution applies to mass and ratio quantities.');
}

/// Series attributes the measure declares, with allowed values.
void requireSeries(MeasureDefinition measure, Map<String, String> attributes) {
  for (final e in attributes.entries) {
    if (!measure.attributes.containsKey(e.key))
      invalid('Measure ${measure.id} has no attribute ${e.key}.');
    final allowed = measure.attributes[e.key];
    if (allowed != null && !allowed.contains(e.value))
      invalid(
        'Attribute ${e.key} of ${measure.id} is one of '
        '${allowed.join(', ')}.',
      );
  }
}

/// A stored resolution policy for a measure (empty [attributes]) or one
/// series of it, as an immutable numbered revision. A revision without a
/// [policy] clears it, so the next level applies again.
final class SeriesPolicy {
  SeriesPolicy._(this.measureId, this.attributes, this.number, this.policy);
  factory SeriesPolicy.publish(
    String measureId,
    Map<String, String> attributes,
    MeasurePolicy? policy, {
    SeriesPolicy? previous,
  }) {
    identifier({'measure': measureId}, 'measure');
    final sorted = {
      for (final k in (attributes.keys.toList()..sort())) k: attributes[k]!,
    };
    final next = SeriesPolicy._(
      measureId,
      Map.unmodifiable(sorted),
      (previous?.number ?? 0) + 1,
      policy,
    );
    if (previous != null && previous.key != next.key)
      invalid('A series policy revision keeps its series.');
    return next;
  }
  factory SeriesPolicy.fromJson(Object? input) {
    final j = jsonObject(input, 'series policy');
    checkKeys(j, {
      'schemaVersion',
      'revision',
      'measure',
      'attributes',
      'policy',
    });
    final revision = j['revision'];
    if (j['schemaVersion'] != 1 || revision is! int || revision < 1)
      invalid('Invalid series policy revision.');
    final attributes = <String, String>{
      for (final e in jsonObject(
        j['attributes'] ?? <String, Object?>{},
        'attributes',
      ).entries)
        identifier({'attribute': e.key}, 'attribute'): identifier({
          e.key: e.value,
        }, e.key),
    };
    final sorted = {
      for (final k in (attributes.keys.toList()..sort())) k: attributes[k]!,
    };
    return SeriesPolicy._(
      identifier(j, 'measure'),
      Map.unmodifiable(sorted),
      revision,
      j['policy'] == null ? null : MeasurePolicy.fromJson(j['policy']),
    );
  }
  final String measureId;
  final Map<String, String> attributes;
  final int number;
  final MeasurePolicy? policy;

  /// The series identity: measure plus sorted attributes.
  String get key => jsonEncode([measureId, attributes]);

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'revision': number,
    'measure': measureId,
    if (attributes.isNotEmpty) 'attributes': attributes,
    if (policy != null) 'policy': policy!.toJson(),
  };
}

/// Contiguous revisions per series, each fitting its measure.
void validateSeriesPolicies(
  List<SeriesPolicy> policies,
  List<MeasureDefinition> measures,
) {
  final byId = {for (final m in measures) m.id: m};
  final numbers = <String, Set<int>>{};
  for (final p in policies) {
    if (!numbers.putIfAbsent(p.key, () => <int>{}).add(p.number))
      invalid('Duplicate series policy revision.');
    final measure =
        byId[p.measureId] ??
        invalid('Series policy names unknown measure ${p.measureId}.');
    requireSeries(measure, p.attributes);
    if (p.policy != null) requirePolicyFits(measure, p.policy!);
  }
  for (final versions in numbers.values)
    if (versions.any((n) => n > versions.length))
      invalid('Series policy revisions must start at one with no gaps.');
}

/// The policy in force for a series and where it came from: the series'
/// own, then the measure-wide one, then the measure definition's default.
({MeasurePolicy policy, String source}) effectivePolicy(
  MeasureDefinition measure,
  Map<String, String> attributes,
  List<SeriesPolicy> policies,
) {
  SeriesPolicy? latest(Map<String, String> attrs) {
    SeriesPolicy? found;
    for (final p in policies) {
      if (p.measureId == measure.id &&
          _sameAttributes(p.attributes, attrs) &&
          (found == null || p.number > found.number))
        found = p;
    }
    return found;
  }

  final series = attributes.isEmpty ? null : latest(attributes)?.policy;
  if (series != null) return (policy: series, source: 'series');
  final wide = latest(const {})?.policy;
  if (wide != null) return (policy: wide, source: 'measure');
  return (policy: measure.resolution, source: 'default');
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

/// SHA-256 over the identity, version, time and value of [sources], in order.
Map<String, Object?> observationFingerprint(List<Observation> sources) => {
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
