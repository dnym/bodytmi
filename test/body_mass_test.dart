import 'dart:convert';

import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'support.dart';

BodyMassMeasurement massObservation(
  int day,
  String mass, {
  String? id,
  String context = 'health',
  int hour = 8,
  String unit = 'kg',
  int version = 1,
}) => BodyMassMeasurement.fromJson({
  'id': id ?? 'm$day',
  'context': context,
  'observedAt':
      '2026-10-${day.toString().padLeft(2, '0')}T${hour.toString().padLeft(2, '0')}:00:00Z',
  'mass': {'value': mass, 'unit': unit},
  'contentVersion': version,
});

List<BodyMassMeasurement> exampleMasses() => [
  for (var i = 1; i <= 7; i++) massObservation(i, '${79 + i}'),
  massObservation(8, '88'),
];
BodyMassTrend trend(
  List<BodyMassMeasurement> measurements, {
  String context = 'health',
  DailyMassMode mode = DailyMassMode.mean,
  String asOf = '2026-10-10T12:00:00Z',
}) => BodyMassTrend.calculate(
  measurements: measurements,
  context: context,
  asOf: parseInstant(asOf, 'asOf'),
  dailyMode: mode,
);

void bodyMassTests() {
  test(
    'body-mass source and notes are exact optional metadata and part of source fingerprints',
    () {
      final original = BodyMassMeasurement.fromJson({
        'id': 'mass',
        'context': 'health',
        'observedAt': '2026-10-01T08:00:00+02:00',
        'mass': {'value': '80', 'unit': 'kg'},
        'source': 'Bathroom scale 🏋️',
        'notes': 'Morning\nBefore breakfast',
      });
      equal(original.toJson()['source'], 'Bathroom scale 🏋️');
      equal(original.toJson()['notes'], 'Morning\nBefore breakfast');
      final changed = BodyMassMeasurement.fromJson({
        ...original.toJson(),
        'notes': 'Later note',
      });
      final before = trend([original]);
      final after = trend([changed]);
      equal(
        before.days.single.trend.value.toString(),
        after.days.single.trend.value.toString(),
      );
      check(
        canonicalJson(before.sourceFingerprint) !=
            canonicalJson(after.sourceFingerprint),
      );
      final selectedBefore = BodyMassResolution.resolve(
        trend: before,
        measurementId: 'mass',
      );
      final selectedAfter = BodyMassResolution.resolve(
        trend: after,
        measurementId: 'mass',
      );
      check(
        canonicalJson(selectedBefore.sourceFingerprint) !=
            canonicalJson(selectedAfter.sourceFingerprint),
      );
      final manualBefore = BodyMassResolution.resolve(
        trend: before,
        manualMass: Quantity('80', 'kg'),
      );
      final manualAfter = BodyMassResolution.resolve(
        trend: after,
        manualMass: Quantity('80', 'kg'),
      );
      equal(
        canonicalJson(manualBefore.sourceFingerprint),
        canonicalJson(manualAfter.sourceFingerprint),
      );
      for (final bad in [
        {'source': ''},
        {'source': null},
        {'source': 'x' * 257},
        {'notes': '  '},
        {'notes': 4},
        {'notes': 'x' * 4001},
      ]) {
        rejects(
          () => BodyMassMeasurement.fromJson({...original.toJson(), ...bad}),
        );
      }
      final legacy = massObservation(1, '80');
      check(
        !legacy.toJson().containsKey('source') &&
            !legacy.toJson().containsKey('notes'),
      );
    },
  );

  test(
    'Q38 first seven daily values are raw; eighth uses ten-percent difference',
    () {
      final result = trend(exampleMasses());
      equal(result.days.length, 8);
      for (var i = 0; i < 7; i++)
        equal(result.days[i].trend.value.toString(), '${80 + i}');
      equal(result.days.last.trend.value.toString(), '86.2');
      equal(result.days.last.mass.value.toString(), '88');
    },
  );
  test('same-day mean and replace recompute once, giving 86.3 and 86.4', () {
    final data = [
      ...exampleMasses(),
      massObservation(8, '90', id: 'm8-later', hour: 18),
    ];
    final mean = trend(data);
    final replacement = trend(data, mode: DailyMassMode.replace);
    equal(mean.days.length, 8);
    equal(mean.days.last.mass.value.toString(), '89');
    equal(mean.days.last.trend.value.toString(), '86.3');
    equal(replacement.days.last.mass.value.toString(), '90');
    equal(replacement.days.last.trend.value.toString(), '86.4');
    equal(mean.days.last.sources.length, 2);
    equal(replacement.days.last.sources.single.id, 'm8-later');
    equal(data.first.mass.value.toString(), '80');
  });
  test('seven readings on the same day count as one representative', () {
    final result = trend([
      for (var i = 0; i < 7; i++)
        massObservation(1, '${80 + i}', id: 'r$i', hour: 8 + i),
      massObservation(2, '90'),
    ]);
    equal(result.days.length, 2);
    equal(result.days.first.mass.value.toString(), '83');
    equal(result.days.last.trend.value.toString(), '90');
  });
  test('missing dates create no synthetic samples or smoothing steps', () {
    final result = trend([
      ...exampleMasses().take(7),
      massObservation(31, '88'),
    ], asOf: '2026-11-01T12:00:00Z');
    equal(result.days.length, 8);
    equal(result.days.last.date, '2026-10-31');
    equal(result.days.last.trend.value.toString(), '86.2');
  });
  test(
    'contexts and future measurements never leak into a selected series',
    () {
      final data = [
        massObservation(1, '80'),
        massObservation(1, '200', id: 'clothed', context: 'training'),
        massObservation(20, '100'),
      ];
      final health = trend(data);
      equal(health.days.single.mass.value.toString(), '80');
      final training = trend(data, context: 'training');
      equal(training.days.single.mass.value.toString(), '200');
      final missing = BodyMassResolution.resolve(
        trend: trend(data, context: 'other'),
      );
      equal(missing.source, 'unavailable');
      equal(missing.mass, null);
      equal(missing.stale, false);
    },
  );
  test(
    'daily grouping retains original local date even when UTC day differs',
    () {
      final observation = BodyMassMeasurement.fromJson({
        'id': 'offset',
        'context': 'health',
        'observedAt': '2026-10-02T00:30:00+02:00',
        'mass': {'value': '80', 'unit': 'kg'},
      });
      final result = trend([observation], asOf: '2026-10-01T23:00:00Z');
      equal(result.days.single.date, '2026-10-02');
      equal(observation.observedAt.day, 1);
      equal(observation.toJson()['observedAt'], '2026-10-02T00:30:00+02:00');
    },
  );
  test(
    'daily mean supports exact canonical conversion of mixed entry units',
    () {
      final result = trend([
        massObservation(1, '100', unit: 'lb'),
        massObservation(1, '45.359237', id: 'metric', hour: 9),
      ]);
      equal(result.days.single.mass.value.toString(), '45.359237');
      equal(result.days.single.sources.first.mass.enteredUnit, Unit.lb);
    },
  );
  test(
    'derived decimal division has explicit nine-digit half-away precision',
    () {
      equal(Decimal.parse('1').dividedByInt(3).toString(), '0.333333333');
      equal(Decimal.parse('-1').dividedByInt(6).toString(), '-0.166666667');
      equal(
        Decimal.parse('1.005').dividedByInt(1, fractionDigits: 2).toString(),
        '1.01',
      );
      equal(
        Decimal.parse('-1.005').dividedByInt(1, fractionDigits: 2).toString(),
        '-1.01',
      );
      rejects(() => Decimal.parse('1').dividedByInt(0));
      rejects(() => Decimal.parse('1').dividedByInt(1, fractionDigits: 41));
    },
  );
  test('staleness is based on observation time; warning is disableable', () {
    final data = [massObservation(1, '80')];
    final boundary = BodyMassResolution.resolve(
      trend: trend(data, asOf: '2026-10-08T08:00:00Z'),
    );
    equal(boundary.stale, false);
    final old = BodyMassResolution.resolve(
      trend: trend(data, asOf: '2026-10-08T08:00:00.000001Z'),
    );
    equal(old.stale, true);
    equal(
      (old.toJson()['warnings']! as List<Object?>).single,
      'stale_body_mass',
    );
    final muted = BodyMassResolution.resolve(
      trend: trend(data),
      warningEnabled: false,
    );
    equal(muted.stale, true);
    check((muted.toJson()['warnings']! as List<Object?>).isEmpty);
    equal(muted.mass!.value.toString(), '80');
  });
  test(
    'selected observed mass overrides trend without changing the source series',
    () {
      final data = exampleMasses();
      final series = trend(data);
      final selected = BodyMassResolution.resolve(
        trend: series,
        measurementId: 'm8',
      );
      equal(selected.source, 'measurement');
      equal(selected.mass!.value.toString(), '88');
      equal(series.days.last.trend.value.toString(), '86.2');
      final manual = BodyMassResolution.resolve(
        trend: series,
        manualMass: Quantity('90', 'kg'),
      );
      equal(manual.source, 'manual');
      equal(manual.stale, false);
      equal(data.last.mass.value.toString(), '88');
      rejects(
        () => BodyMassResolution.resolve(
          trend: series,
          measurementId: 'm8',
          manualMass: Quantity('90', 'kg'),
        ),
      );
    },
  );
  test(
    'override cannot silently select future or another-context measurements',
    () {
      final series = trend([
        massObservation(1, '80'),
        massObservation(20, '90'),
        massObservation(2, '85', id: 'clothed', context: 'training'),
      ]);
      for (final id in ['m20', 'clothed', 'missing']) {
        rejects(
          () => BodyMassResolution.resolve(trend: series, measurementId: id),
        );
      }
    },
  );
  test(
    'choosing an old weigh-in retains its own staleness despite recent readings',
    () {
      final series = trend([
        massObservation(1, '80'),
        massObservation(9, '82'),
      ]);
      final result = BodyMassResolution.resolve(
        trend: series,
        measurementId: 'm1',
      );
      equal(result.stale, true);
      equal(
        result.sourceObservedAt,
        parseInstant('2026-10-01T08:00:00Z', 'date'),
      );
    },
  );
  test('fingerprint detects insertions, deletions and unversioned edits', () {
    final data = exampleMasses();
    final original = trend(data);
    final oldFingerprint = jsonEncode(original.sourceFingerprint);
    final inserted = trend([
      ...data,
      massObservation(1, '80', id: 'new', hour: 9),
    ]);
    equal(inserted.days.last.trend.value, original.days.last.trend.value);
    check(jsonEncode(inserted.sourceFingerprint) != oldFingerprint);
    check(
      jsonEncode(trend(data.skip(1).toList()).sourceFingerprint) !=
          oldFingerprint,
    );
    check(
      jsonEncode(
            trend([
              massObservation(1, '81'),
              ...data.skip(1),
            ]).sourceFingerprint,
          ) !=
          oldFingerprint,
    );
    final frozen = BodyMassResolution.resolve(trend: original);
    trend([...data, massObservation(9, '100')]);
    equal(frozen.mass!.value.toString(), '86.2');
    equal(jsonEncode(original.sourceFingerprint), oldFingerprint);
  });
  test('sorting and same-instant replacement ties are deterministic', () {
    final data = [
      massObservation(1, '80', id: 'a'),
      massObservation(1, '82', id: 'z'),
    ];
    final a = trend(data, mode: DailyMassMode.replace);
    final b = trend(data.reversed.toList(), mode: DailyMassMode.replace);
    jsonEqual(a.toJson(), b.toJson());
    equal(a.days.single.mass.value.toString(), '82');
  });
  test(
    'measurement validation rejects duplicates, bad dates, zero mass and unknown fields',
    () {
      rejects(
        () => trend([massObservation(1, '80'), massObservation(1, '82')]),
      );
      rejects(() => massObservation(1, '0'));
      rejects(() => massObservation(1, '80', unit: 's'));
      rejects(() => massObservation(1, '80', version: 0));
      rejects(() => massObservation(32, '80'));
      rejects(
        () => BodyMassMeasurement.fromJson({
          ...massObservation(1, '80').toJson(),
          'unknown': true,
        }),
      );
    },
  );
  test(
    'body-mass application service validates override and warning configuration',
    () {
      const service = BodyMassService();
      final request = <String, Object?>{
        'measurements': [massObservation(1, '80').toJson()],
        'context': 'health',
        'asOf': '2026-10-10T12:00:00Z',
      };
      equal(service.resolve(request).mass!.value.toString(), '80');
      rejects(
        () => service.resolve({...request, 'override': <String, Object?>{}}),
      );
      rejects(() => service.resolve({...request, 'dailyMode': 'mixed'}));
      rejects(() => service.resolve({...request, 'staleAfterDays': -1}));
      rejects(() => service.resolve({...request, 'warnIfStale': 'no'}));
    },
  );
}
