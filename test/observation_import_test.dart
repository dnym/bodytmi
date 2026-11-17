import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'cli_test.dart';
import 'support.dart';

Map<String, Object?> _q(String value, String unit) => {
  'value': value,
  'unit': unit,
};

String _date(int day) => DateTime.utc(
  2026,
  1,
  1,
).add(Duration(days: day)).toIso8601String().substring(0, 10);

/// A workbook-style year: daily mass and bio-impedance, daily steps
/// (date-only) and a few waist readings.
Map<String, Object?> _document({String steps0 = '8000'}) => {
  'format': 'bodytmi-observation-import/1',
  'source': {'namespace': 'workbook', 'app': 'spreadsheet'},
  'observations': [
    for (var day = 0; day < 365; day++) ...[
      {
        'sourceId': 'mass/${_date(day)}',
        'measure': 'body-mass',
        'value': _q('${90 - day / 100}', 'kg'),
        'observedAt': '${_date(day)}T07:00:00+01:00',
        'attributes': {'context': 'health'},
      },
      {
        'sourceId': 'bia/${_date(day)}',
        'measure': 'body-fat',
        'value': _q('24.5', 'percent'),
        'date': _date(day),
        'attributes': {'method': 'bio-impedance'},
      },
      {
        'sourceId': 'steps/${_date(day)}',
        'measure': 'steps',
        'value': _q(day == 0 ? steps0 : '${6000 + day}', 'step'),
        'date': _date(day),
      },
    ],
    for (final day in [10, 100, 300])
      {
        'sourceId': 'waist/${_date(day)}',
        'id': 'waist-$day',
        'measure': 'circumference',
        'value': _q('88.9', 'cm'),
        'date': _date(day),
        'attributes': {'site': 'waist'},
      },
  ],
};

void observationImportTests() {
  test('observation import document validation', () {
    final doc = ObservationImportDocument.fromJson(_document());
    equal(doc.observations.length, 365 * 3 + 3);
    final steps = doc.observations[2];
    final id = steps.id('workbook');
    check(RegExp(r'^workbook-[0-9a-f]{24}$').hasMatch(id), id);
    equal(steps.id("workbook"), id);
    equal(doc.observations.last.id('workbook'), 'waist-300');
    final observation = steps.observation('workbook', 1);
    equal(observation.date, _date(0));
    equal(observation.observedAtText, null);
    equal(observation.importSourceId, 'steps/${_date(0)}');
    Map<String, Object?> one(List<Object?> list) => {
      'format': 'bodytmi-observation-import/1',
      'source': {'namespace': 'x'},
      'observations': list,
    };
    final entry = {
      'sourceId': 'a',
      'measure': 'height',
      'value': _q('180', 'cm'),
      'date': '2026-01-01',
    };
    rejects(() => ObservationImportDocument.fromJson(one([entry, entry])));
    rejects(() => ObservationImportDocument.fromJson(one(const [])));
    rejects(
      () => ObservationImportDocument.fromJson(
        one([
          {...entry, 'id': 'same'},
          {...entry, 'sourceId': 'b', 'id': 'same'},
        ]),
      ),
    );
    rejects(
      () => ObservationImportDocument.fromJson(
        one([
          {...entry, 'contentVersion': 2},
        ]),
      ),
    );
    rejects(
      () => ObservationImportDocument.fromJson({
        ...one([entry]),
        'format': 'bodytmi-observation-import/2',
      }),
    );
    rejects(
      () => ObservationImportDocument.fromJson(
        one([
          {...entry, 'observedAt': '2026-01-01T07:00:00+01:00'},
        ]),
      ),
    );
  });

  test('CLI observation import preview, apply and re-import', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-obs-import-');
    final db = '${dir.path}/db.sqlite';
    Future<({int code, Object? data, String error})> cli(
      String name,
      Map<String, Object?> fields, {
      String? database,
    }) async {
      final r = await invoke(
        name.split(' '),
        jsonEncode({'schemaVersion': 1, 'database': database ?? db, ...fields}),
      );
      return (
        code: r.code,
        data: r.code == 0
            ? jsonObject(jsonDecode(r.output), 'r')['data']
            : null,
        error: r.error,
      );
    }

    Map<String, Object?> counts(Object? data) =>
        jsonObject(jsonObject(data, 'r')['counts'], 'counts');

    try {
      final document = _document();
      final validated = await invoke([
        'observation',
        'import-validate',
      ], jsonEncode({'schemaVersion': 1, 'document': document}));
      check(validated.code == 0, validated.error);
      jsonEqual(
        jsonObject(
          jsonObject(jsonDecode(validated.output), 'r')['data'],
          'd',
        )['measures'],
        ['body-fat', 'body-mass', 'circumference', 'steps'],
      );
      final badUnit = await invoke(
        ['observation', 'import-validate'],
        jsonEncode({
          'schemaVersion': 1,
          'document': {
            ...document,
            'observations': [
              {
                'sourceId': 'w',
                'measure': 'circumference',
                'value': _q('35', 'in'),
                'date': '2026-01-01',
                'attributes': {'site': 'waist'},
              },
            ],
          },
        }),
      );
      equal(badUnit.code, 2);
      // A hand-entered waist reading occupies one of the explicit ids.
      equal(
        (await cli('observation record', {
          'observation': {
            'id': 'waist-100',
            'measure': 'circumference',
            'value': _q('90', 'cm'),
            'date': _date(100),
            'attributes': {'site': 'waist'},
          },
        })).code,
        0,
      );
      final preview = await cli('observation import-preview', {
        'document': document,
      });
      check(preview.code == 0, preview.error);
      jsonEqual(counts(preview.data), {
        'new': 365 * 3 + 2,
        'unchanged': 0,
        'changed': 0,
        'deleted': 0,
        'conflict': 1,
      });
      equal(
        (await cli('observation import-apply', {'document': document})).code,
        2,
      );
      // A conflict blocks the whole import: nothing is written.
      equal(
        (await cli('observation import-apply', {
          'document': document,
          'confirm': true,
        })).code,
        5,
      );
      equal(
        ((await cli('observation list', {'measure': 'steps'})).data! as List)
            .length,
        0,
      );
      equal(
        (await cli('observation delete', {
          'id': 'waist-100',
          'expectedVersion': 1,
          'confirm': true,
        })).code,
        0,
      );
      // The deleted hand entry still owns its id: rename the import's.
      final waist = (document['observations']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere((o) => o['id'] == 'waist-100');
      waist['id'] = 'waist-100-import';
      final applied = await cli('observation import-apply', {
        'document': document,
        'confirm': true,
      });
      check(applied.code == 0, applied.error);
      equal(counts(applied.data)['new'], 365 * 3 + 3);

      // Importing again writes nothing; steps stay one record per day.
      final again = await cli('observation import-apply', {
        'document': document,
        'confirm': true,
      });
      equal(counts(again.data)['unchanged'], 365 * 3 + 3);
      final day0 =
          (await cli('observation list', {
                'measure': 'steps',
                'from': _date(0),
                'until': _date(1),
              })).data!
              as List;
      equal(day0.length, 1);

      // The source corrected day 0's steps: rejected unless update.
      final edited = _document(steps0: '9000');
      edited['observations'] = [
        for (final o
            in (edited['observations']! as List).cast<Map<String, Object?>>())
          if (o['id'] == 'waist-100') {...o, 'id': 'waist-100-import'} else o,
      ];
      final changed = await cli('observation import-preview', {
        'document': edited,
      });
      equal(counts(changed.data)['changed'], 1);
      equal(
        (await cli('observation import-apply', {
          'document': edited,
          'confirm': true,
        })).code,
        5,
      );
      final updated = await cli('observation import-apply', {
        'document': edited,
        'onChanged': 'update',
        'confirm': true,
      });
      check(updated.code == 0, updated.error);
      final stepsRow = jsonObject(
        ((await cli('observation list', {
                  'measure': 'steps',
                  'from': _date(0),
                  'until': _date(1),
                })).data!
                as List)
            .single,
        'row',
      );
      final stepsObs = jsonObject(stepsRow['observation'], 'o');
      equal(jsonObject(stepsObs['value'], 'v')['value'], '9000');
      equal(stepsObs['contentVersion'], 2);
      equal(stepsObs['date'], _date(0));

      // A deleted import stays deleted; a dropped entry is absent and kept.
      final waistId = 'waist-300';
      equal(
        (await cli('observation delete', {
          'id': waistId,
          'expectedVersion': 1,
          'confirm': true,
        })).code,
        0,
      );
      final shorter = {
        ...edited,
        'observations': (edited['observations']! as List)
            .where((o) => (o as Map)['sourceId'] != 'bia/${_date(364)}')
            .toList(),
      };
      final last = await cli('observation import-apply', {
        'document': shorter,
        'confirm': true,
      });
      check(last.code == 0, last.error);
      equal(counts(last.data)['deleted'], 1);
      jsonEqual(jsonObject(last.data, 'r')['absent'], ['bia/${_date(364)}']);
      equal(
        jsonObject(
          (await cli('observation show', {'id': waistId})).data,
          'w',
        )['deleted'],
        true,
      );

      // Imported mass feeds the body report like any weigh-in.
      final report = await cli('body report', {
        'asOf': '${_date(364)}T20:00:00+01:00',
      });
      check(report.code == 0, report.error);
      final measures = jsonObject(
        jsonObject(report.data, 'r')['measures'],
        'm',
      );
      equal(jsonObject(measures['mass'], 'mass')['used'], 'trend');

      // Unknown measures are named.
      final unknown = await cli('observation import-preview', {
        'document': {
          'format': 'bodytmi-observation-import/1',
          'source': {'namespace': 'band'},
          'observations': [
            {
              'sourceId': 'x',
              'measure': 'grip-strength',
              'value': _q('40', 'kg'),
              'date': '2026-01-01',
            },
          ],
        },
      });
      equal(unknown.code, 3);

      // Date-only imports stay date-only through export and restore.
      final export = '${dir.path}/export.json';
      equal((await cli('archive export', {'destination': export})).code, 0);
      final restored = '${dir.path}/restored.sqlite';
      final restore = await cli('archive restore', {
        'database': restored,
        'source': export,
        'recoveryDestination': '${dir.path}/recovery',
        'confirm': true,
      }, database: restored);
      check(restore.code == 0, restore.error);
      final back = jsonObject(
        ((await cli('observation list', {
                  'measure': 'steps',
                  'from': _date(0),
                  'until': _date(1),
                }, database: restored)).data!
                as List)
            .single,
        'row',
      );
      jsonEqual(back, stepsRow);
      final reimport = await cli('observation import-preview', {
        'document': shorter,
      }, database: restored);
      equal(counts(reimport.data)['new'], 0);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
