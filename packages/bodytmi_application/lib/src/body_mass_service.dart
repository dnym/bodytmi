import 'package:bodytmi_core/bodytmi_core.dart';

/// Resolves an explicit measurement collection; no device clock or hidden store.
final class BodyMassService {
  const BodyMassService();
  BodyMassTrend trend(Map<String, Object?> input) {
    checkKeys(input, {'measurements', 'context', 'asOf', 'dailyMode'});
    final mode = switch (input['dailyMode'] ?? 'mean') {
      'mean' => DailyMassMode.mean,
      'replace' => DailyMassMode.replace,
      _ => invalid('dailyMode must be mean or replace.'),
    };
    return BodyMassTrend.calculate(
      measurements: [
        for (final m in jsonList(input, 'measurements'))
          BodyMassMeasurement.fromJson(m),
      ],
      context: identifier(input, 'context'),
      asOf: parseInstant(input['asOf'], 'asOf'),
      dailyMode: mode,
    );
  }

  BodyMassResolution resolve(Map<String, Object?> input) {
    checkKeys(input, {
      'measurements',
      'context',
      'asOf',
      'dailyMode',
      'override',
      'staleAfterDays',
      'warnIfStale',
    });
    final series = trend({
      for (final key in ['measurements', 'context', 'asOf', 'dailyMode'])
        if (input.containsKey(key)) key: input[key],
    });
    final override = input['override'] == null
        ? <String, Object?>{}
        : jsonObject(input['override'], 'override');
    checkKeys(override, {'measurementId', 'mass'});
    if (input.containsKey('override') && override.length != 1)
      invalid('Override must select exactly one measurementId or mass.');
    final staleDays = input['staleAfterDays'] ?? 7;
    final warn = input['warnIfStale'] ?? true;
    if (staleDays is! int || warn is! bool)
      invalid('Invalid staleness configuration.');
    return BodyMassResolution.resolve(
      trend: series,
      measurementId: override.containsKey('measurementId')
          ? identifier(override, 'measurementId')
          : null,
      manualMass: override.containsKey('mass')
          ? Quantity.fromJson(override['mass'])
          : null,
      staleAfterDays: staleDays,
      warningEnabled: warn,
    );
  }
}
