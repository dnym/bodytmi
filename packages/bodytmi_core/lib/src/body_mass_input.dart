import 'body_mass.dart';
import 'errors.dart';
import 'instant.dart';
import 'quantity.dart';

/// Explicit selection; no default series, cross-context fallback or correction.
final class BodyMassSelection {
  BodyMassSelection._(
    this.context,
    this.dailyMode,
    this.staleAfterDays,
    this.warnIfStale,
  );
  factory BodyMassSelection.fromJson(Object? input) {
    final j = jsonObject(input, 'body-mass selection');
    checkKeys(j, {'context', 'dailyMode', 'staleAfterDays', 'warnIfStale'});
    final mode = switch (j['dailyMode'] ?? 'mean') {
      'mean' => DailyMassMode.mean,
      'replace' => DailyMassMode.replace,
      _ => invalid('dailyMode must be mean or replace.'),
    };
    final days = j['staleAfterDays'] ?? 7;
    final warn = j['warnIfStale'] ?? true;
    if (days is! int || days < 0 || days > 36500 || warn is! bool)
      invalid('Invalid body-mass staleness configuration.');
    return BodyMassSelection._(identifier(j, 'context'), mode, days, warn);
  }
  final String context;
  final DailyMassMode dailyMode;
  final int staleAfterDays;
  final bool warnIfStale;
  Map<String, Object?> toJson() => {
    'context': context,
    'dailyMode': dailyMode.name,
    'staleAfterDays': staleAfterDays,
    'warnIfStale': warnIfStale,
  };
}

final class BodyMassOverride {
  BodyMassOverride._(this.measurementId, this.mass);
  factory BodyMassOverride.fromJson(Object? input) {
    final j = jsonObject(input, 'body-mass override');
    checkKeys(j, {'measurementId', 'mass'});
    if (j.length != 1) invalid('Choose exactly one measurementId or mass.');
    final mass = j.containsKey('mass') ? Quantity.fromJson(j['mass']) : null;
    if (mass != null &&
        (mass.dimension != Dimension.mass ||
            mass.value.compareTo(Decimal.zero) <= 0))
      invalid('Body mass must be positive mass.');
    return BodyMassOverride._(
      j.containsKey('measurementId') ? identifier(j, 'measurementId') : null,
      mass,
    );
  }
  final String? measurementId;
  final Quantity? mass;
  Map<String, Object?> toJson() => {
    if (measurementId != null) 'measurementId': measurementId,
    if (mass != null) 'mass': mass!.toJson(),
  };
}

/// Frozen resolver input and reproducible output. Corrections to the live series
/// do not rewrite this input. Retain raw inputs to validate historical provenance.
final class BodyMassInputSnapshot {
  BodyMassInputSnapshot._(
    this.selection,
    this.asOf,
    this.override,
    List<BodyMassMeasurement> measurements,
    this.resolution,
  ) : measurements = List.unmodifiable(measurements);
  factory BodyMassInputSnapshot.capture({
    required BodyMassSelection selection,
    required DateTime asOf,
    required List<BodyMassMeasurement> measurements,
    BodyMassOverride? override,
  }) {
    final trend = BodyMassTrend.calculate(
      measurements: measurements,
      context: selection.context,
      asOf: asOf,
      dailyMode: selection.dailyMode,
    );
    final resolution = BodyMassResolution.resolve(
      trend: trend,
      measurementId: override?.measurementId,
      manualMass: override?.mass,
      staleAfterDays: selection.staleAfterDays,
      warningEnabled: selection.warnIfStale,
    );
    final selected = override?.mass != null
        ? <BodyMassMeasurement>[]
        : trend.eligibleMeasurements
              .where(
                (m) =>
                    override?.measurementId == null ||
                    m.id == override!.measurementId,
              )
              .toList();
    return BodyMassInputSnapshot._(
      selection,
      asOf.toUtc(),
      override,
      selected,
      resolution,
    );
  }
  factory BodyMassInputSnapshot.fromJson(Object? input) {
    final j = jsonObject(input, 'body-mass input snapshot');
    checkKeys(j, {
      'selection',
      'asOf',
      'override',
      'measurements',
      'resolution',
    });
    final result = BodyMassInputSnapshot.capture(
      selection: BodyMassSelection.fromJson(j['selection']),
      asOf: parseInstant(j['asOf'], 'asOf'),
      measurements: [
        for (final m in jsonList(j, 'measurements'))
          BodyMassMeasurement.fromJson(m),
      ],
      override: j.containsKey('override')
          ? BodyMassOverride.fromJson(j['override'])
          : null,
    );
    if (!_sameJson(j, result.toJson()))
      invalid(
        'Body-mass input snapshot is inconsistent with its resolver output.',
      );
    return result;
  }
  final BodyMassSelection selection;
  final DateTime asOf;
  final BodyMassOverride? override;
  final List<BodyMassMeasurement> measurements;
  final BodyMassResolution resolution;
  Map<String, Object?> toJson() => {
    'selection': selection.toJson(),
    'asOf': asOf.toIso8601String(),
    if (override != null) 'override': override!.toJson(),
    'measurements': [for (final m in measurements) m.toJson()],
    'resolution': resolution.toJson(),
  };

  bool sameSelection(BodyMassSelection other) =>
      _sameJson(selection.toJson(), other.toJson());
  bool sameOverride(BodyMassOverride? other) =>
      _sameJson(override?.toJson(), other?.toJson());

  /// Membership changes matter as well as changes to already captured sources.
  Map<String, Object?> freshness(List<BodyMassMeasurement> current) {
    if (current.map((m) => m.id).toSet().length != current.length)
      invalid('Measurement IDs must be unique.');
    BodyMassInputSnapshot latest;
    try {
      latest = BodyMassInputSnapshot.capture(
        selection: selection,
        asOf: asOf,
        measurements: current,
        override: override,
      );
    } on BodyTmiException catch (e) {
      if (e.code != 'validation') rethrow;
      return {'changed': true, 'current': null, 'reason': 'source_unavailable'};
    }
    return {
      'changed': !_sameJson(
        resolution.sourceFingerprint,
        latest.resolution.sourceFingerprint,
      ),
      'current': latest.resolution.toJson(),
    };
  }
}

bool _sameJson(Object? a, Object? b) {
  if (a is Map && b is Map)
    return a.length == b.length &&
        a.keys.every((k) => b.containsKey(k) && _sameJson(a[k], b[k]));
  if (a is List && b is List)
    return a.length == b.length &&
        List.generate(a.length, (i) => i).every((i) => _sameJson(a[i], b[i]));
  return a == b;
}
