import 'errors.dart';
import 'instant.dart';
import 'quantity.dart';

/// A raw observation. The original offset and quantity entry are retained.
final class BodyMassMeasurement {
  BodyMassMeasurement._(
    this.id,
    this.context,
    this.observedAtText,
    this.observedAt,
    this.mass,
    this.contentVersion,
  );

  factory BodyMassMeasurement.fromJson(Object? input) {
    final json = jsonObject(input, 'body-mass measurement');
    checkKeys(json, {'id', 'context', 'observedAt', 'mass', 'contentVersion'});
    final text = requiredString(json, 'observedAt');
    final mass = Quantity.fromJson(json['mass']);
    _requireMass(mass);
    final version = json['contentVersion'] ?? 1;
    if (version is! int || version < 1)
      invalid('contentVersion must be positive.');
    return BodyMassMeasurement._(
      identifier(json, 'id'),
      identifier(json, 'context'),
      text,
      parseInstant(text, 'observedAt'),
      mass,
      version,
    );
  }

  final String id;
  final String context;
  final String observedAtText;
  final DateTime observedAt;
  final Quantity mass;
  final int contentVersion;
  // Calendar grouping uses the observation's original offset, never this
  // process's current timezone. Timestamp validation fixes the first ten chars.
  String get localDate => observedAtText.substring(0, 10);

  Map<String, Object?> toJson() => {
    'id': id,
    'context': context,
    'observedAt': observedAtText,
    'mass': mass.toJson(),
    'contentVersion': contentVersion,
  };
}

void _requireMass(Quantity mass) {
  if (mass.dimension != Dimension.mass ||
      mass.value.compareTo(Decimal.zero) <= 0) {
    invalid('Body mass must be a positive mass quantity.');
  }
}

enum DailyMassMode { mean, replace }

/// A derived representative and trend, not a replacement for its raw inputs.
final class BodyMassDay {
  BodyMassDay(
    this.date,
    this.mass,
    this.trend,
    List<BodyMassMeasurement> sources,
  ) : sources = List.unmodifiable(sources);
  final String date;
  final Quantity mass;
  final Quantity trend;
  final List<BodyMassMeasurement> sources;
  Map<String, Object?> toJson() => {
    'date': date,
    'mass': mass.toJson(),
    'trend': trend.toJson(),
    'sources': [
      for (final m in sources) {'id': m.id, 'contentVersion': m.contentVersion},
    ],
  };
}

/// Body-mass trend policy version 1: daily representative, first seven days as-is,
/// then prior trend + 10% of (daily representative - prior trend).
/// Derived values use nine fractional decimal places in kg, half-away rounding.
final class BodyMassTrend {
  BodyMassTrend._(
    this.context,
    this.asOf,
    this.dailyMode,
    this.days,
    this.eligibleMeasurements,
  );
  static const policy = 'body-mass-ewma/1';

  factory BodyMassTrend.calculate({
    required List<BodyMassMeasurement> measurements,
    required String context,
    required DateTime asOf,
    DailyMassMode dailyMode = DailyMassMode.mean,
  }) {
    identifier({'context': context}, 'context');
    if (measurements.map((m) => m.id).toSet().length != measurements.length) {
      invalid('Measurement IDs must be unique, including across contexts.');
    }
    final eligible =
        measurements
            .where((m) => m.context == context && !m.observedAt.isAfter(asOf))
            .toList()
          ..sort((a, b) {
            final time = a.observedAt.compareTo(b.observedAt);
            return time != 0 ? time : a.id.compareTo(b.id);
          });
    final grouped = <String, List<BodyMassMeasurement>>{};
    for (final m in eligible) {
      grouped.putIfAbsent(m.localDate, () => []).add(m);
    }
    final dates = grouped.keys.toList()..sort();
    final days = <BodyMassDay>[];
    Decimal? previous;
    for (final date in dates) {
      final entries = grouped[date]!;
      final selected = dailyMode == DailyMassMode.replace
          ? [entries.last]
          : entries;
      final daily = selected
          .fold<Decimal>(Decimal.zero, (sum, m) => sum + m.mass.value)
          .dividedByInt(selected.length);
      final trend = days.length < 7
          ? daily
          : (previous! + (daily - previous) * Decimal.parse('0.1'))
                .dividedByInt(1);
      days.add(
        BodyMassDay(
          date,
          Quantity(daily.toString(), 'kg'),
          Quantity(trend.toString(), 'kg'),
          selected,
        ),
      );
      previous = trend;
    }
    return BodyMassTrend._(
      context,
      asOf.toUtc(),
      dailyMode,
      List.unmodifiable(days),
      List.unmodifiable(eligible),
    );
  }

  final String context;
  final DateTime asOf;
  final DailyMassMode dailyMode;
  final List<BodyMassDay> days;
  final List<BodyMassMeasurement> eligibleMeasurements;

  /// Structured fingerprint rather than an unverified hash. Includes membership,
  /// versions and values, so insertion/deletion or a wrongly unversioned edit is
  /// still visible. It belongs to the frozen resolver input, not a global clock.
  Map<String, Object?> get sourceFingerprint => {
    'policy': policy,
    'dailyMode': dailyMode.name,
    'context': context,
    'sources': List<Map<String, Object?>>.unmodifiable([
      for (final m in eligibleMeasurements)
        Map<String, Object?>.unmodifiable({
          'id': m.id,
          'contentVersion': m.contentVersion,
          'observedAt': m.observedAtText,
          'massKg': m.mass.value.toString(),
        }),
    ]),
  };

  Map<String, Object?> toJson() => {
    'policy': policy,
    'context': context,
    'asOf': asOf.toIso8601String(),
    'dailyMode': dailyMode.name,
    'fractionDigitsKg': 9,
    'days': [for (final day in days) day.toJson()],
    'sourceFingerprint': sourceFingerprint,
  };
}

final class BodyMassResolution {
  BodyMassResolution._({
    required this.context,
    required this.asOf,
    required this.source,
    required this.mass,
    required this.sourceObservedAt,
    required this.stale,
    required this.warningEnabled,
    required Map<String, Object?> sourceFingerprint,
  }) : sourceFingerprint = Map.unmodifiable(sourceFingerprint);

  factory BodyMassResolution.resolve({
    required BodyMassTrend trend,
    String? measurementId,
    Quantity? manualMass,
    int staleAfterDays = 7,
    bool warningEnabled = true,
  }) {
    if (measurementId != null && manualMass != null)
      invalid('Choose one override source.');
    if (staleAfterDays < 0 || staleAfterDays > 36500)
      invalid('Invalid staleAfterDays.');
    var source = 'unavailable';
    Quantity? mass;
    DateTime? observedAt;
    Map<String, Object?> fingerprint = trend.sourceFingerprint;
    if (manualMass != null) {
      _requireMass(manualMass);
      source = 'manual';
      mass = manualMass;
      observedAt = trend.asOf;
      fingerprint = {
        'policy': 'manual/1',
        'context': trend.context,
        'massKg': mass.value.toString(),
      };
    } else if (measurementId != null) {
      final selected = trend.eligibleMeasurements
          .where((m) => m.id == measurementId)
          .toList();
      if (selected.isEmpty)
        invalid(
          'Override measurement is missing, future, or in another context.',
        );
      final measurement = selected.single;
      source = 'measurement';
      mass = measurement.mass;
      observedAt = measurement.observedAt;
      fingerprint = {
        'policy': 'measurement/1',
        'context': trend.context,
        'id': measurement.id,
        'contentVersion': measurement.contentVersion,
        'observedAt': measurement.observedAtText,
        'massKg': mass.value.toString(),
      };
    } else if (trend.days.isNotEmpty) {
      source = 'trend';
      mass = trend.days.last.trend;
      // Use observation age, not the time at which a derived value was computed.
      observedAt = trend.eligibleMeasurements.last.observedAt;
    }
    final stale =
        observedAt != null &&
        trend.asOf.difference(observedAt) > Duration(days: staleAfterDays);
    return BodyMassResolution._(
      context: trend.context,
      asOf: trend.asOf,
      source: source,
      mass: mass,
      sourceObservedAt: observedAt,
      stale: stale,
      warningEnabled: warningEnabled,
      sourceFingerprint: fingerprint,
    );
  }

  final String context;
  final DateTime asOf;
  final String source;
  final Quantity? mass;
  final DateTime? sourceObservedAt;
  final bool stale;
  final bool warningEnabled;
  final Map<String, Object?> sourceFingerprint;
  Map<String, Object?> toJson() => {
    'policy': 'training-mass/1',
    'context': context,
    'asOf': asOf.toIso8601String(),
    'source': source,
    'mass': mass?.toJson(),
    'sourceObservedAt': sourceObservedAt?.toIso8601String(),
    'stale': stale,
    'warnings': [if (stale && warningEnabled) 'stale_body_mass'],
    'sourceFingerprint': sourceFingerprint,
  };
}
