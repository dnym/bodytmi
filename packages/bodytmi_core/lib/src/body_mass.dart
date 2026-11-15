import 'dart:convert';
import 'package:crypto/crypto.dart';
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
    this.source,
    this.notes,
  );

  factory BodyMassMeasurement.fromJson(Object? input) {
    final json = jsonObject(input, 'body-mass measurement');
    checkKeys(json, {
      'id',
      'context',
      'observedAt',
      'mass',
      'contentVersion',
      'source',
      'notes',
    });
    final source = json.containsKey('source')
        ? requiredString(json, 'source')
        : null;
    final notes = json.containsKey('notes')
        ? requiredString(json, 'notes')
        : null;
    if (source != null && source.length > 256)
      invalid('Body-mass source must be at most 256 characters.');
    if (notes != null && notes.length > 4000)
      invalid('Body-mass notes must be at most 4000 characters.');
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
      source,
      notes,
    );
  }

  final String id;
  final String context;
  final String observedAtText;
  final DateTime observedAt;
  final Quantity mass;
  final int contentVersion;
  final String? source, notes;
  bool get hasMetadata => source != null || notes != null;
  // Calendar grouping uses the observation's original offset, never this
  // process's current timezone. Timestamp validation fixes the first ten chars.
  String get localDate => observedAtText.substring(0, 10);

  Map<String, Object?> toJson() => {
    'id': id,
    'context': context,
    'observedAt': observedAtText,
    'mass': mass.toJson(),
    'contentVersion': contentVersion,
    if (source != null) 'source': source,
    if (notes != null) 'notes': notes,
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

  /// A compact fingerprint of every eligible observation: membership,
  /// versions, times, values and metadata hashed (SHA-256 over canonical
  /// JSON), so insertions, deletions and edits stay visible while a frozen
  /// session stores a constant-size value rather than the whole history.
  Map<String, Object?> get sourceFingerprint =>
      bodyMassFingerprint(context, dailyMode, eligibleMeasurements);

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

/// The policy `body-mass-ewma/2` fingerprint over [sources], in order.
Map<String, Object?> bodyMassFingerprint(
  String context,
  DailyMassMode dailyMode,
  List<BodyMassMeasurement> sources,
) {
  final canonical = jsonEncode([
    for (final m in sources)
      [
        m.id,
        m.contentVersion,
        m.observedAtText,
        m.mass.value.toString(),
        m.source,
        m.notes,
      ],
  ]);
  return Map.unmodifiable({
    'policy': 'body-mass-ewma/2',
    'dailyMode': dailyMode.name,
    'context': context,
    'sourceCount': sources.length,
    'sha256': sha256.convert(utf8.encode(canonical)).toString(),
  });
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
        if (measurement.source != null) 'source': measurement.source,
        if (measurement.notes != null) 'notes': measurement.notes,
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

  /// A frozen resolution, checked for internal consistency under the
  /// selection's staleness settings. Its raw trend inputs are not retained,
  /// so the trend mass itself is taken as captured.
  factory BodyMassResolution.fromJson(
    Object? input, {
    required int staleAfterDays,
    required bool warningEnabled,
  }) {
    final j = jsonObject(input, 'body-mass resolution');
    checkKeys(j, {
      'policy',
      'context',
      'asOf',
      'source',
      'mass',
      'sourceObservedAt',
      'stale',
      'warnings',
      'sourceFingerprint',
    });
    if (j['policy'] != 'training-mass/1')
      invalid('Unsupported body-mass resolution policy.');
    final source = j['source'];
    if (!{'unavailable', 'manual', 'measurement', 'trend'}.contains(source))
      invalid('Invalid body-mass resolution source.');
    final mass = j['mass'] == null ? null : Quantity.fromJson(j['mass']);
    if ((mass == null) != (source == 'unavailable'))
      invalid('Only an unavailable body mass has no mass.');
    if (mass != null) _requireMass(mass);
    final asOf = parseInstant(j['asOf'], 'asOf');
    final observed = j['sourceObservedAt'] == null
        ? null
        : parseInstant(j['sourceObservedAt'], 'sourceObservedAt');
    if ((observed == null) != (source == 'unavailable') ||
        (observed?.isAfter(asOf) ?? false))
      invalid('Invalid body-mass source observation time.');
    final fingerprint = jsonObject(
      j['sourceFingerprint'],
      'source fingerprint',
    );
    final expectedPolicy = switch (source) {
      'manual' => 'manual/1',
      'measurement' => 'measurement/1',
      _ => 'body-mass-ewma/2',
    };
    if (fingerprint['policy'] != expectedPolicy ||
        fingerprint['context'] != j['context'])
      invalid('Body-mass fingerprint does not match its resolution.');
    if (expectedPolicy == 'body-mass-ewma/2') {
      checkKeys(fingerprint, {
        'policy',
        'dailyMode',
        'context',
        'sourceCount',
        'sha256',
      });
      final count = fingerprint['sourceCount'];
      if (count is! int ||
          (count == 0) != (source == 'unavailable') ||
          fingerprint['sha256'] is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint['sha256'] as String))
        invalid('Invalid body-mass trend fingerprint.');
    }
    final result = BodyMassResolution._(
      context: identifier(j, 'context'),
      asOf: asOf.toUtc(),
      source: source as String,
      mass: mass,
      sourceObservedAt: observed,
      stale:
          observed != null &&
          asOf.difference(observed) > Duration(days: staleAfterDays),
      warningEnabled: warningEnabled,
      sourceFingerprint: expectedPolicy == 'body-mass-ewma/2'
          ? {
              'policy': fingerprint['policy'],
              'dailyMode': fingerprint['dailyMode'],
              'context': fingerprint['context'],
              'sourceCount': fingerprint['sourceCount'],
              'sha256': fingerprint['sha256'],
            }
          : fingerprint,
    );
    if (_sortedJson(result.toJson()) != _sortedJson(j))
      invalid('Body-mass resolution is internally inconsistent.');
    return result;
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

String _sortedJson(Object? value) => jsonEncode(_sorted(value));
Object? _sorted(Object? value) => switch (value) {
  Map() => {
    for (final k in (value.keys.map((k) => k as String).toList()..sort()))
      k: _sorted(value[k]),
  },
  List() => [for (final v in value) _sorted(v)],
  _ => value,
};
