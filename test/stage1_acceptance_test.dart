import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'cli_test.dart';
import 'support.dart';

Map<String, Object?> _q(String value, String unit) => {
  'value': value,
  'unit': unit,
};

String _date(int day) => DateTime.utc(
  2025,
  11,
  17,
).add(Duration(days: day)).toIso8601String().substring(0, 10);

String _tenths(int tenths) =>
    Decimal.parse('$tenths').dividedByInt(10).toString();

/// Stage 1 "done when" (APP-PLAN section 5), entirely through the native
/// CLI: a year of imported daily mass, bio-impedance and steps plus waist,
/// hip, neck and caliper readings.
void stage1AcceptanceTests() {
  test('stage 1 acceptance: a year of body data through the CLI', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-stage1-');
    var db = '${dir.path}/db.sqlite';
    Future<({int code, Object? data, String error})> cli(
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
        error: r.error,
      );
    }

    Future<Map<String, Object?>> ok(
      String name,
      Map<String, Object?> fields,
    ) async {
      final r = await cli(name, fields);
      check(r.code == 0, '$name: ${r.error}');
      return r.data is Map<String, Object?>
          ? r.data! as Map<String, Object?>
          : {'list': r.data};
    }

    Map<String, Object?> at(Object? json, List<String> path) {
      Object? v = json;
      for (final key in path) {
        v = jsonObject(v, key)[key];
      }
      return jsonObject(v, path.last);
    }

    const asOf = '2026-11-16T21:00:00+01:00';
    try {
      await ok('profile set', {
        'profile': {
          'sex': 'female',
          'birthDate': '1990-06-15',
          'stepLength': _q('70', 'cm'),
        },
        'expectedRevision': 0,
      });
      // A custom measure, defined before the import that uses it.
      await ok('measure define', {
        'measure': {
          'id': 'body-water',
          'name': 'Body water',
          'kind': 'quantity',
          'dimension': 'ratio',
          'unit': 'percent',
          'attributes': {'method': <String, Object?>{}},
          'summaries': ['mean', 'last', 'count'],
        },
        'expectedRevision': 0,
      });
      final observations = <Map<String, Object?>>[
        for (var day = 0; day < 365; day++) ...[
          {
            'sourceId': 'mass/${_date(day)}',
            'measure': 'body-mass',
            'value': _q(_tenths(720 - day ~/ 10), 'kg'),
            'observedAt': '${_date(day)}T07:00:00+01:00',
            'attributes': {'context': 'health'},
          },
          {
            'sourceId': 'bia/${_date(day)}',
            'measure': 'body-fat',
            'value': _q(_tenths(300 - day ~/ 20), 'percent'),
            'date': _date(day),
            'attributes': {'method': 'bio-impedance'},
          },
          {
            'sourceId': 'water/${_date(day)}',
            'measure': 'body-water',
            'value': _q('52', 'percent'),
            'date': _date(day),
            'attributes': {'method': 'bio-impedance'},
          },
          {
            'sourceId': 'steps/${_date(day)}',
            'measure': 'steps',
            'value': _q('${7000 + day % 7 * 500}', 'step'),
            'date': _date(day),
          },
        ],
        // Waist every two weeks, shrinking 2 mm each time.
        for (var day = 0; day < 365; day += 14)
          {
            'sourceId': 'waist/${_date(day)}',
            'measure': 'circumference',
            'value': _q(_tenths(850 - day ~/ 14 * 2), 'cm'),
            'date': _date(day),
            'attributes': {'site': 'waist'},
          },
        for (final (site, cm) in [('hip', '100'), ('neck', '33')])
          {
            'sourceId': '$site/${_date(340)}',
            'measure': 'circumference',
            'value': _q(cm, 'cm'),
            'date': _date(340),
            'attributes': {'site': site},
          },
        for (final (site, mm) in [
          ('triceps', '18'),
          ('suprailiac', '14'),
          ('thigh', '24'),
        ])
          {
            'sourceId': 'caliper/$site/${_date(350)}',
            'measure': 'skinfold',
            'value': _q(mm, 'mm'),
            'date': _date(350),
            'attributes': {'site': site},
          },
        {
          'sourceId': 'height',
          'measure': 'height',
          'value': _q('168', 'cm'),
          'date': _date(0),
        },
      ];
      final document = {
        'format': 'bodytmi-observation-import/1',
        'source': {'namespace': 'workbook'},
        'observations': observations,
      };
      final applied = await ok('observation import-apply', {
        'document': document,
        'confirm': true,
      });
      equal(at(applied, ['counts'])['new'], observations.length);

      var report = await ok('body report', {'asOf': asOf});
      final mass = at(report, ['measures', 'mass']);
      equal(mass['used'], 'trend');
      // Fat-free mass from the default Navy source; waist age shown.
      final source = at(report, ['bodyFatSource']);
      equal(source['origin'], 'default');
      equal(source['status'], 'resolved');
      final navy = at(report, ['calculations', 'navy-body-fat']);
      equal(navy['status'], 'resolved');
      final waist = at(navy, ['inputs', 'waist', 'provenance']);
      equal(waist['observedOn'], _date(364 - 364 % 14));
      equal(waist['ageDays'], 364 % 14);
      equal(at(navy, ['inputs', 'neck', 'provenance'])['ageDays'], 24);
      for (final name in [
        'fat-free-mass',
        'ffmi',
        'bmi',
        'jackson-pollock-3',
      ]) {
        equal(at(report, ['calculations', name])['status'], 'resolved');
      }
      equal(
        at(report, ['calculations', 'jackson-pollock-7'])['status'],
        'unavailable',
      );

      // Weekly step totals.
      final weekly = await ok('series query', {
        'measure': 'steps',
        'from': '2026-11-02',
        'until': '2026-11-16',
        'bucket': 'week',
        'summary': 'sum',
      });
      final weeks = (weekly['points']! as List).cast<Map<String, Object?>>();
      equal(weeks.length, 2);
      for (final week in weeks) {
        // Every weekday offset 0..6 once: 7×7000 + 500×21.
        jsonEqual(week['value'], {'value': '59500', 'unit': 'step'});
        jsonEqual(week['coverage'], {'daysWithData': 7, 'days': 7});
      }
      // The custom measure queries like any other.
      final water = await ok('series query', {
        'measure': 'body-water',
        'attributes': {'method': 'bio-impedance'},
        'from': '2026-10-01',
        'until': '2026-11-01',
        'summary': 'mean',
      });
      jsonEqual(at(water, ['overall'])['value'], {
        'value': '0.52',
        'unit': 'ratio',
      });

      // A mean of Navy and bio-impedance lists both components.
      await ok('body source', {
        'from': _date(360),
        'source': {
          'kind': 'mean',
          'components': [
            {'kind': 'calculation', 'calculation': 'navy-body-fat'},
            {'kind': 'series', 'method': 'bio-impedance'},
          ],
        },
        'expectedRevision': 0,
      });
      report = await ok('body report', {'asOf': asOf});
      final mean = at(report, ['bodyFatSource']);
      equal(mean['status'], 'resolved');
      final components = (mean['components']! as List)
          .cast<Map<String, Object?>>();
      jsonEqual(
        [for (final c in components) jsonObject(c['source'], 's')['kind']],
        ['calculation', 'series'],
      );
      final parts = [
        for (final c in components) Quantity.fromJson(c['value']).value,
      ];
      equal(
        Quantity.fromJson(mean['value']).value,
        (parts[0] + parts[1]).dividedByInt(2),
      );

      // Switching waist to extrapolated gives a labelled estimate.
      await ok('measure policy', {
        'measure': 'circumference',
        'attributes': {'site': 'waist'},
        'resolution': {'policy': 'extrapolated'},
        'expectedRevision': 0,
      });
      report = await ok('body report', {'asOf': asOf});
      final extrapolated = at(report, ['measures', 'waist']);
      equal(extrapolated['used'], 'extrapolated');
      equal(extrapolated['estimate'], true);
      equal(extrapolated['policySource'], 'series');
      equal(
        at(report, [
          'calculations',
          'navy-body-fat',
          'inputs',
          'waist',
          'provenance',
        ])['estimate'],
        true,
      );

      // A correction changes the report.
      final last = jsonObject(
        (at(
                  {
                    'x': await ok('observation list', {
                      'measure': 'body-mass',
                      'from': _date(364),
                      'until': _date(365),
                    }),
                  },
                  ['x'],
                )['list']!
                as List)
            .single,
        'row',
      );
      final lastObs = jsonObject(last['observation'], 'o');
      final before = canonicalJson(at(report, ['measures', 'mass'])['value']);
      await ok('observation update', {
        'observation': {
          for (final e in lastObs.entries)
            if (e.key != 'contentVersion') e.key: e.value,
          'value': _q('60', 'kg'),
        },
        'expectedVersion': 1,
      });
      report = await ok('body report', {'asOf': asOf});
      check(
        canonicalJson(at(report, ['measures', 'mass'])['value']) != before,
        'the corrected weigh-in moved the trend',
      );

      // Backup and restore round trip: the restored report is identical.
      final backup = '${dir.path}/backup';
      await ok('backup create', {'destination': backup});
      final export = '${dir.path}/export.json';
      await ok('archive export', {'destination': export});
      for (final (command, source) in [
        ('backup restore', backup),
        ('archive restore', export),
      ]) {
        db = '${dir.path}/${command.split(' ').first}.sqlite';
        await ok(command, {
          'source': source,
          'recoveryDestination': '${dir.path}/recovery-$command',
          'confirm': true,
        });
        final restored = await ok('body report', {'asOf': asOf});
        equal(canonicalJson(restored), canonicalJson(report));
        final again = await ok('observation import-preview', {
          'document': document,
        });
        equal(at(again, ['counts'])['changed'], 1);
        equal(at(again, ['counts'])['new'], 0);
      }
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
