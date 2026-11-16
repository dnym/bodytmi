import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'cli_test.dart';
import 'support.dart';

Map<String, Object?> _q(String value, String unit) => {
  'value': value,
  'unit': unit,
};

Future<BodyTmiException> _failure(Future<Object?> Function() action) async {
  try {
    await action();
  } on BodyTmiException catch (error) {
    return error;
  }
  throw StateError('Expected a BodyTmiException.');
}

MeasureDefinition _builtIn(String id) =>
    builtInMeasures.firstWhere((m) => m.id == id);

String _date(int day) => DateTime.utc(
  2026,
  9,
  1,
).add(Duration(days: day)).toIso8601String().substring(0, 10);

Observation _tape(
  String id,
  int day,
  String cm, {
  Map<String, String> attributes = const {'site': 'waist'},
  int version = 1,
}) => Observation.fromJson({
  'id': id,
  'measure': 'circumference',
  'value': _q(cm, 'cm'),
  'date': _date(day),
  'attributes': attributes,
  'contentVersion': version,
});

Map<String, Object?> _resolve(
  List<Observation> observations,
  int asOfDay, {
  MeasurePolicy? policy,
  Map<String, String> attributes = const {'site': 'waist'},
  String measure = 'circumference',
}) => ObservationResolution.resolve(
  measure: _builtIn(measure),
  attributes: attributes,
  observations: observations,
  asOfText: '${_date(asOfDay)}T21:00:00+01:00',
  policy: policy,
).toJson();

/// Resolution: the value of a series in force at an instant.
void resolutionTests() {
  test('trend reproduces the body-mass trend exactly', () {
    final measurements = <BodyMassMeasurement>[];
    for (var day = 0; day < 14; day++) {
      for (final (hour, delta) in [(7, '0.3'), (21, '0.9')]) {
        if (day % 5 == 3 && hour == 21) continue;
        measurements.add(
          BodyMassMeasurement.fromJson({
            'id': 'm-$day-$hour',
            'context': 'health',
            'observedAt':
                '${_date(day)}T${hour.toString().padLeft(2, '0')}:00:00+01:00',
            'mass': _q(
              (Decimal.parse('84') -
                      Decimal.parse('0.13') * Decimal.parse('$day') +
                      Decimal.parse(delta))
                  .toString(),
              'kg',
            ),
          }),
        );
      }
    }
    for (final mode in [DailyMassMode.mean, DailyMassMode.replace]) {
      final expected = BodyMassTrend.calculate(
        measurements: measurements,
        context: 'health',
        asOf: DateTime.parse('${_date(13)}T23:00:00+01:00'),
        dailyMode: mode,
      ).days.last.trend;
      final resolved = ObservationResolution.resolve(
        measure: _builtIn('body-mass'),
        attributes: {'context': 'health'},
        observations: [
          for (final m in measurements) Observation.fromBodyMass(m),
        ],
        asOfText: '${_date(13)}T23:00:00+01:00',
        dailyMode: mode.name,
      ).toJson();
      equal(resolved['used'], 'trend');
      equal(
        Decimal.parse(
          jsonObject(resolved['value'], 'v')['value']! as String,
        ).compareTo(expected.value),
        0,
      );
      equal(resolved['days'], 14);
    }
  });

  test('latest reports age and staleness; series never merge', () {
    final waist = [_tape('w1', 0, '86'), _tape('w2', 20, '85')];
    var r = _resolve(waist, 41);
    equal(r['used'], 'latest');
    equal(jsonObject(r['value'], 'v')['value'], '85');
    equal(r['observedOn'], _date(20));
    equal(r['ageDays'], 21);
    equal(r['stale'], false);
    r = _resolve(waist, 81);
    equal(r['stale'], true);
    // A later observation is not yet in force.
    r = _resolve(waist, 10);
    equal(jsonObject(r['value'], 'v')['value'], '86');
    r = _resolve(waist, -1);
    equal(r['status'], 'unavailable');
    check(r['reason'] is String);
    // Left and right arms are separate series.
    final arms = [
      _tape('l', 0, '35', attributes: {'site': 'upper-arm', 'side': 'left'}),
      _tape('r', 1, '36', attributes: {'site': 'upper-arm', 'side': 'right'}),
    ];
    r = _resolve(arms, 5, attributes: {'site': 'upper-arm', 'side': 'left'});
    equal(jsonObject(r['value'], 'v')['value'], '35');
    equal(r['sourceCount'], 1);
    equal(
      _resolve(arms, 5, attributes: {'site': 'upper-arm'})['status'],
      'unavailable',
    );
    rejects(() => _resolve(arms, 5, attributes: {'colour': 'red'}));
  });

  test('extrapolation is limited, labelled and falls back with reasons', () {
    final policy = MeasurePolicy.fromJson({
      'policy': 'extrapolated',
      'staleAfterDays': 60,
    });
    final three = [
      _tape('a', 0, '90'),
      _tape('b', 10, '89'),
      _tape('c', 30, '87'),
    ];
    var r = _resolve(three, 40, policy: policy);
    equal(r['used'], 'latest');
    equal(r['estimate'], false);
    check((r['fallbackReason']! as String).contains('needs 4'));
    final four = [...three, _tape('d', 30, '87')];
    final short = [
      _tape('a', 0, '90'),
      _tape('b', 5, '89'),
      _tape('c', 10, '88'),
      _tape('d', 15, '87'),
    ];
    r = _resolve(short, 20, policy: policy);
    check((r['fallbackReason']! as String).contains('span 15 days'));
    final line = [
      _tape('a', 0, '90'),
      _tape('b', 10, '89'),
      _tape('c', 20, '88'),
      _tape('d', 30, '87'),
    ];
    r = _resolve(line, 40, policy: policy);
    equal(r['used'], 'extrapolated');
    equal(r['estimate'], true);
    final value = jsonObject(r['value'], 'v');
    equal(value['unit'], 'm');
    equal(
      Decimal.parse(value['value']! as String).compareTo(Decimal.parse('0.86')),
      0,
    );
    final ex = jsonObject(r['extrapolation'], 'e');
    equal(
      Decimal.parse(
        jsonObject(ex['slopePerDay'], 's')['value']! as String,
      ).compareTo(Decimal.parse('-0.001')),
      0,
    );
    equal(ex['capped'], false);
    equal(ex['points'], 4);
    // Asked 90 days ahead, it stops 30 days past the last point and says so.
    r = _resolve(line, 120, policy: policy);
    final capped = jsonObject(r['extrapolation'], 'e');
    equal(capped['capped'], true);
    equal(capped['evaluatedOn'], _date(60));
    equal(
      Decimal.parse(
        jsonObject(r['value'], 'v')['value']! as String,
      ).compareTo(Decimal.parse('0.84')),
      0,
    );
    check(four.isNotEmpty);
    // Trend and extrapolation are for quantities only.
    final mood = MeasureDefinition.fromJson({
      'id': 'mood',
      'name': 'Mood',
      'kind': 'rating',
      'scale': {'minimum': 1, 'maximum': 5},
    });
    rejects(
      () => ObservationResolution.resolve(
        measure: mood,
        attributes: const {},
        observations: const [],
        asOfText: '2026-11-01T12:00:00Z',
        policy: policy,
      ),
    );
    rejects(
      () => _resolve(
        line,
        40,
        policy: MeasurePolicy.fromJson({'policy': 'trend'}),
      ),
    );
  });

  test('fingerprints change when any eligible observation changes', () {
    final before = _resolve([_tape('a', 0, '90'), _tape('b', 9, '89')], 10);
    final corrected = _resolve([
      _tape('a', 0, '91', version: 2),
      _tape('b', 9, '89'),
    ], 10);
    equal(
      jsonObject(before['value'], 'v')['value'],
      jsonObject(corrected['value'], 'v')['value'],
    );
    check(
      jsonEncode(before['fingerprint']) != jsonEncode(corrected['fingerprint']),
      'a corrected older reading changes the fingerprint',
    );
  });

  test('stored policies apply per series, then per measure', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-policy-');
    final store = await TrainingStore.open('${dir.path}/db.sqlite');
    try {
      final service = ObservationService(store);
      for (final o in [
        _tape('a', 0, '90'),
        _tape('b', 10, '89'),
        _tape('c', 20, '88'),
        _tape('d', 30, '87'),
        _tape('n', 30, '40', attributes: {'site': 'neck'}),
      ]) {
        await service.save(o.toJson()..remove('contentVersion'), 0);
      }
      final asOf = '${_date(40)}T12:00:00+01:00';
      Future<Map<String, Object?>> waist() async => (await service.resolve(
        'circumference',
        asOf,
        attributes: {'site': 'waist'},
      )).toJson();
      var r = await waist();
      equal(r['policySource'], 'default');
      equal(r['used'], 'latest');
      final extrapolated = MeasurePolicy.fromJson({
        'policy': 'extrapolated',
        'staleAfterDays': 60,
      });
      final set = await service.setPolicy(
        'circumference',
        {'site': 'waist'},
        extrapolated,
        0,
      );
      equal(set.number, 1);
      r = await waist();
      equal(r['policySource'], 'series');
      equal(r['used'], 'extrapolated');
      // The neck series keeps the measure default.
      final neck = (await service.resolve(
        'circumference',
        asOf,
        attributes: {'site': 'neck'},
      )).toJson();
      equal(neck['policySource'], 'default');
      // An explicit request policy wins.
      r = (await service.resolve(
        'circumference',
        asOf,
        attributes: {'site': 'waist'},
        policy: MeasurePolicy.fromJson({'policy': 'latest'}),
      )).toJson();
      equal(r['policySource'], 'request');
      // Policies must fit the measure and series; versions are checked.
      equal(
        (await _failure(
          () => service.setPolicy(
            'circumference',
            const {},
            MeasurePolicy.fromJson({'policy': 'trend'}),
            0,
          ),
        )).code,
        'validation',
      );
      equal(
        (await _failure(
          () => service.setPolicy(
            'circumference',
            {'site': 'elbow'},
            extrapolated,
            0,
          ),
        )).code,
        'validation',
      );
      equal(
        (await _failure(
          () => service.setPolicy('circumference', {'site': 'waist'}, null, 0),
        )).code,
        'conflict',
      );
      // Clearing the series policy falls back again.
      await service.setPolicy('circumference', {'site': 'waist'}, null, 1);
      equal((await waist())['policySource'], 'default');
      // Archives carry policies and reject an unfit one.
      final archive = (await store.archive()).toJson();
      equal(TrainingArchive.fromJson(archive).seriesPolicies.length, 2);
      final forged = jsonDecode(jsonEncode(archive)) as Map;
      ((forged['seriesPolicies'] as List).first as Map)['attributes'] = {
        'site': 'elbow',
      };
      rejects(() => TrainingArchive.fromJson(forged.cast<String, Object?>()));
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });

  test('CLI observation resolve', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-resolve-');
    final db = '${dir.path}/db.sqlite';
    try {
      final store = await TrainingStore.open(db);
      try {
        final service = ObservationService(store);
        for (final o in [_tape('w1', 0, '86'), _tape('w2', 20, '85')]) {
          await service.save(o.toJson()..remove('contentVersion'), 0);
        }
        await service.save(
          _tape('gone', 25, '80').toJson()..remove('contentVersion'),
          0,
        );
        await service.delete('gone', 1, confirm: true);
      } finally {
        await store.close();
      }
      final r = await invoke(
        ['observation', 'resolve'],
        jsonEncode({
          'schemaVersion': 1,
          'database': db,
          'measure': 'circumference',
          'attributes': {'site': 'waist'},
          'asOf': '${_date(30)}T12:00:00+01:00',
        }),
      );
      equal(r.code, 0);
      final data = jsonObject(
        jsonObject(jsonDecode(r.output), 'r')['data'],
        'd',
      );
      equal(jsonObject(data['value'], 'v')['value'], '85');
      equal(data['ageDays'], 10);
      final bad = await invoke(
        ['observation', 'resolve'],
        jsonEncode({
          'schemaVersion': 1,
          'database': db,
          'measure': 'circumference',
          'asOf': '2026-11-01',
        }),
      );
      equal(bad.code, 2);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
