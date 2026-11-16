import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'support.dart';

Map<String, Object?> _q(String value, String unit) => {
  'value': value,
  'unit': unit,
};

MeasureDefinition _builtIn(String id) =>
    builtInMeasures.firstWhere((m) => m.id == id);

Future<BodyTmiException> _failure(Future<Object?> Function() action) async {
  try {
    await action();
  } on BodyTmiException catch (error) {
    return error;
  }
  throw StateError('Expected a BodyTmiException.');
}

/// Observations are the one store for every measure; body-mass records are
/// observations of `body-mass`, converted exactly both ways.
void observationTests() {
  test('body-mass measurements convert to observations exactly', () {
    final measurement = BodyMassMeasurement.fromJson({
      'id': 'w1',
      'context': 'health',
      'observedAt': '2026-11-16T07:05:00+01:00',
      'mass': _q('82.40', 'kg'),
      'contentVersion': 3,
      'source': 'bathroom scale',
      'notes': 'after coffee',
    });
    final observation = Observation.fromBodyMass(measurement);
    equal(observation.measureId, 'body-mass');
    equal(observation.localDate, '2026-11-16');
    jsonEqual(observation.attributes, {'context': 'health'});
    observation.validateAgainst(_builtIn('body-mass'));
    jsonEqual(observation.toBodyMass().toJson(), measurement.toJson());
    jsonEqual(
      Observation.fromJson(observation.toJson()).toJson(),
      observation.toJson(),
    );
  });

  test('observation values are checked against their measure', () {
    Observation make(Map<String, Object?> extra) => Observation.fromJson({
      'id': 'o',
      'measure': 'circumference',
      'value': _q('84.5', 'cm'),
      'date': '2026-11-01',
      'attributes': {'site': 'waist'},
      ...extra,
    });
    final waist = make({});
    waist.validateAgainst(_builtIn('circumference'));
    equal(waist.localDate, '2026-11-01');
    equal(waist.observedAt, null);
    rejects(
      () => make({
        'attributes': {'site': 'elbow'},
      }).validateAgainst(_builtIn('circumference')),
    );
    rejects(
      () => make({
        'attributes': {'colour': 'blue'},
      }).validateAgainst(_builtIn('circumference')),
    );
    rejects(
      () => make({
        'value': _q('80', 'kg'),
      }).validateAgainst(_builtIn('circumference')),
    );
    // Exactly one of instant and date; dates are real dates.
    rejects(() => make({'observedAt': '2026-11-01T08:00:00Z'}));
    rejects(() => make({'date': '2026-02-30'}));
    rejects(() => make({'date': null}));
    rejects(() => make({'attributes': <String, Object?>{}}));
    // Other kinds.
    final mood = MeasureDefinition.fromJson({
      'id': 'mood',
      'name': 'Mood',
      'kind': 'rating',
      'scale': {'minimum': 1, 'maximum': 5},
    });
    Observation of(String measure, Object? value) => Observation.fromJson({
      'id': 'x',
      'measure': measure,
      'value': ?value,
      'observedAt': '2026-11-01T20:00:00+01:00',
    });
    of('mood', 4).validateAgainst(mood);
    rejects(() => of('mood', 6).validateAgainst(mood));
    final nap = MeasureDefinition.fromJson({
      'id': 'nap',
      'name': 'Nap',
      'kind': 'interval',
    });
    of('nap', {'end': '2026-11-01T20:30:00+01:00'}).validateAgainst(nap);
    rejects(
      () =>
          of('nap', {'end': '2026-11-01T19:00:00+01:00'}).validateAgainst(nap),
    );
    final coffee = MeasureDefinition.fromJson({
      'id': 'coffee',
      'name': 'Coffee',
      'kind': 'event',
      'summaries': ['count'],
    });
    of('coffee', null).validateAgainst(coffee);
    rejects(() => of('coffee', true).validateAgainst(coffee));
    rejects(
      () => validateObservationRecords([ObservationRecord(of('mystery', 1))]),
    );
  });

  test('body mass lives in the observation table', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-observations-');
    final store = await TrainingStore.open('${dir.path}/db.sqlite');
    try {
      final mass = StoredBodyMassService(store);
      for (final (id, day) in [('a', 1), ('b', 2), ('c', 3)]) {
        await mass.save({
          'id': id,
          'context': 'health',
          'observedAt': '2026-11-0${day}T07:00:00+01:00',
          'mass': _q('8$day', 'kg'),
        }, 0);
      }
      final waist = Observation.fromJson({
        'id': 'waist-1',
        'measure': 'circumference',
        'value': _q('84', 'cm'),
        'date': '2026-11-02',
        'attributes': {'site': 'waist'},
      });
      await store.saveObservationRecord(ObservationRecord(waist));
      equal((await store.observationRecords()).length, 4);
      final range = await store.observationRecords(
        measureId: 'body-mass',
        fromDate: '2026-11-02',
        untilDate: '2026-11-03',
      );
      jsonEqual([for (final r in range) r.observation.id], ['b']);
      equal((await store.bodyMassRecords()).length, 3);
      // An observation identity cannot become a body-mass record.
      equal(
        (await _failure(
          () => mass.save({
            'id': 'waist-1',
            'context': 'health',
            'observedAt': '2026-11-04T07:00:00+01:00',
            'mass': _q('80', 'kg'),
          }, 0),
        )).code,
        'conflict',
      );
      // Archives carry every observation in one section and restore it.
      final archive = await StoredTrainingService(store).exportArchive();
      final json = archive.toJson();
      equal((json['observations']! as List).length, 4);
      equal(json.containsKey('bodyMass'), false);
      equal(TrainingArchive.fromJson(json).bodyMass.length, 3);
      final forged = jsonDecode(jsonEncode(json)) as Map;
      final row =
          (forged['observations'] as List).firstWhere(
                (r) => ((r as Map)['observation'] as Map)['id'] == 'waist-1',
              )
              as Map;
      (row['observation'] as Map)['attributes'] = {'site': 'elbow'};
      rejects(() => TrainingArchive.fromJson(forged.cast<String, Object?>()));
      final backup = '${dir.path}/backup';
      await store.backup(backup);
      NativeBackup.validateDatabase('$backup/database.sqlite');
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });
}
