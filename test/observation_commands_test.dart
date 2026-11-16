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

Map<String, Object?> _hr({Map<String, Object?> extra = const {}}) => {
  'id': 'resting-hr',
  'name': 'Resting heart rate',
  'kind': 'quantity',
  'dimension': 'frequency',
  'unit': 'bpm',
  'attributes': {
    'position': {
      'values': ['lying', 'sitting'],
    },
  },
  'summaries': ['mean', 'min', 'max', 'last', 'count'],
  ...extra,
};

Map<String, Object?> _obs(
  String id,
  String bpm, {
  String day = '2026-11-01',
  Map<String, Object?> extra = const {},
}) => {
  'id': id,
  'measure': 'resting-hr',
  'value': _q(bpm, 'bpm'),
  'observedAt': '${day}T06:30:00+01:00',
  'attributes': {'position': 'lying'},
  ...extra,
};

Future<BodyTmiException> _failure(Future<Object?> Function() action) async {
  try {
    await action();
  } on BodyTmiException catch (error) {
    return error;
  }
  throw StateError('Expected a BodyTmiException.');
}

/// Custom measures and the observation commands follow the body-mass rules:
/// version checks, idempotent retries, confirmed deletion keeping a marker.
void observationCommandTests() {
  test('custom measures and observations', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-obs-cmd-');
    final store = await TrainingStore.open('${dir.path}/db.sqlite');
    try {
      final service = ObservationService(store);
      // Built-in identities are reserved.
      equal(
        (await _failure(
          () => service.define(
            MeasureDefinition.fromJson({
              'id': 'steps',
              'name': 'Steps',
              'kind': 'event',
              'summaries': ['count'],
            }),
            0,
          ),
        )).code,
        'validation',
      );
      final defined = await service.define(
        MeasureDefinition.fromJson(_hr()),
        0,
      );
      equal(defined.number, 1);
      equal((await service.measures()).last.id, 'resting-hr');

      final first = await service.save(_obs('hr-1', '58'), 0);
      equal(first.observation.contentVersion, 1);
      // An identical retry returns the stored record; a different one
      // under the same version conflicts.
      equal(
        (await service.save(_obs('hr-1', '58'), 0)).toJson()['deleted'],
        false,
      );
      equal(
        (await _failure(() => service.save(_obs('hr-1', '60'), 0))).code,
        'conflict',
      );
      final corrected = await service.save(_obs('hr-1', '57'), 1);
      equal(corrected.observation.contentVersion, 2);
      equal(
        (await _failure(
          () => service.save(
            _obs(
              'hr-1',
              '57',
              extra: {
                'attributes': {'position': 'standing'},
              },
            ),
            2,
          ),
        )).code,
        'validation',
      );
      await service.save(
        _obs(
          'hr-2',
          '61',
          day: '2026-11-02',
          extra: {
            'attributes': {'position': 'sitting'},
          },
        ),
        0,
      );
      await service.save(_obs('hr-3', '59', day: '2026-11-03'), 0);

      // Changing kind or dimension, or dropping a value in use, is refused.
      equal(
        (await _failure(
          () => service.define(
            MeasureDefinition.fromJson(
              _hr(extra: {'dimension': 'mass', 'unit': 'kg'}),
            ),
            1,
          ),
        )).code,
        'validation',
      );
      equal(
        (await _failure(
          () => service.define(
            MeasureDefinition.fromJson(
              _hr(
                extra: {
                  'attributes': {
                    'position': {
                      'values': ['lying'],
                    },
                  },
                },
              ),
            ),
            1,
          ),
        )).code,
        'validation',
      );
      equal(
        (await service.define(
          MeasureDefinition.fromJson(_hr(extra: {'name': 'Morning pulse'})),
          1,
        )).number,
        2,
      );

      // Lists filter by measure, dates and attributes, in date order.
      final lying = await service.list(
        measureId: 'resting-hr',
        attributes: {'position': 'lying'},
      );
      jsonEqual([for (final r in lying) r.observation.id], ['hr-1', 'hr-3']);
      final range = await service.list(
        measureId: 'resting-hr',
        fromDate: '2026-11-02',
        untilDate: '2026-11-03',
      );
      jsonEqual([for (final r in range) r.observation.id], ['hr-2']);

      // Deletion needs confirmation, keeps a marker and blocks reuse.
      equal(
        (await _failure(() => service.delete('hr-3', 1, confirm: false))).code,
        'validation',
      );
      final deleted = await service.delete('hr-3', 1, confirm: true);
      equal(deleted.deleted, true);
      equal(deleted.observation.contentVersion, 2);
      equal((await service.delete('hr-3', 1, confirm: true)).deleted, true);
      equal(
        (await _failure(() => service.save(_obs('hr-3', '59'), 0))).code,
        'conflict',
      );
      equal((await service.list(measureId: 'resting-hr')).length, 2);
      equal(
        (await service.list(
          measureId: 'resting-hr',
          includeDeleted: true,
        )).length,
        3,
      );

      // Import identities name one observation.
      final imported = {
        'import': {'namespace': 'band', 'sourceId': '2026-11-04'},
      };
      await service.save(
        _obs('hr-4', '60', day: '2026-11-04', extra: imported),
        0,
      );
      equal(
        (await _failure(
          () => service.save(
            _obs('hr-5', '60', day: '2026-11-04', extra: imported),
            0,
          ),
        )).code,
        'conflict',
      );

      // Body mass recorded as an observation is a mass record.
      await service.save({
        'id': 'w-1',
        'measure': 'body-mass',
        'value': _q('82', 'kg'),
        'observedAt': '2026-11-01T07:00:00+01:00',
        'attributes': {'context': 'health'},
      }, 0);
      equal(
        (await StoredBodyMassService(
          store,
        ).show('w-1')).measurement.mass.enteredValue,
        '82',
      );
      equal(
        (await _failure(
          () => service.save({
            'id': 'w-2',
            'measure': 'body-mass',
            'value': _q('82', 'kg'),
            'date': '2026-11-02',
            'attributes': {'context': 'health'},
          }, 0),
        )).code,
        'validation',
      );

      // Archives carry measures and reject observations of a missing one.
      final archive = (await store.archive()).toJson();
      equal(TrainingArchive.fromJson(archive).measures.length, 2);
      final forged = jsonDecode(jsonEncode(archive)) as Map;
      (forged['measures'] as List).clear();
      rejects(() => TrainingArchive.fromJson(forged.cast<String, Object?>()));
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });

  test('CLI measure and observation commands', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-obs-cli-');
    final db = '${dir.path}/db.sqlite';
    Future<({int code, Object? data})> cli(
      String name,
      Map<String, Object?> fields,
    ) async {
      final r = await invoke(
        name.split(' '),
        jsonEncode({'schemaVersion': 1, 'database': db, ...fields}),
      );
      return (
        code: r.code,
        data: r.code == 0
            ? jsonObject(jsonDecode(r.output), 'r')['data']
            : null,
      );
    }

    try {
      equal(
        (await cli('measure define', {
          'measure': _hr(),
          'expectedRevision': 0,
        })).code,
        0,
      );
      final builtIn = await cli('measure show', {'measureId': 'steps'});
      equal(jsonObject(builtIn.data, 'd')['builtIn'], true);
      equal((await cli('measure show', {'measureId': 'nope'})).code, 3);
      equal(
        ((await cli('measure list', {})).data! as List).length,
        builtInMeasures.length + 1,
      );
      equal(
        (await cli('observation record', {
          'observation': _obs('hr-1', '58'),
        })).code,
        0,
      );
      equal(
        (await cli('observation update', {
          'observation': _obs('hr-1', '57'),
          'expectedVersion': 1,
        })).code,
        0,
      );
      equal(
        (await cli('observation update', {
          'observation': _obs('hr-1', '56'),
          'expectedVersion': 1,
        })).code,
        5,
      );
      equal(
        (await cli('observation record', {
          'observation': {
            'id': 'steps-1',
            'measure': 'steps',
            'value': _q('8123', 'step'),
            'date': '2026-11-01',
          },
        })).code,
        0,
      );
      final listed = await cli('observation list', {'from': '2026-11-01'});
      equal((listed.data! as List).length, 2);
      equal((await cli('observation list', {'from': '1 Nov'})).code, 2);
      equal(
        (await cli('observation delete', {
          'id': 'steps-1',
          'expectedVersion': 1,
        })).code,
        2,
      );
      equal((await cli('observation show', {'id': 'nope'})).code, 3);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
