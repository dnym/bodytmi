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

String _date(int day) => DateTime.utc(
  2026,
  10,
  1,
).add(Duration(days: day)).toIso8601String().substring(0, 10);

Future<BodyTmiException> _failure(Future<Object?> Function() action) async {
  try {
    await action();
  } on BodyTmiException catch (error) {
    return error;
  }
  throw StateError('Expected a BodyTmiException.');
}

Map<String, Object?> _calc(Map<String, Object?> report, String name) =>
    jsonObject(jsonObject(report['calculations'], 'c')[name], name);

/// The body report resolves every body measure at a time and evaluates
/// every calculation, showing each input's age, policy and source.
void bodyReportTests() {
  test('the body report from observations', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-body-');
    final store = await TrainingStore.open('${dir.path}/db.sqlite');
    try {
      final body = BodyService(store);
      final observations = ObservationService(store);
      await body.setProfile(
        Profile.fromJson({
          'sex': 'male',
          'birthDate': '1985-03-01',
          'stepLength': _q('75', 'cm'),
        }),
        0,
      );
      equal(
        (await _failure(
          () => body.setProfile(Profile.fromJson({'sex': 'female'}), 0),
        )).code,
        'conflict',
      );
      Future<void> record(Map<String, Object?> o) => observations.save(o, 0);
      await record({
        'id': 'height',
        'measure': 'height',
        'value': _q('180', 'cm'),
        'date': _date(0),
      });
      for (var day = 0; day < 30; day++) {
        await record({
          'id': 'mass-$day',
          'measure': 'body-mass',
          'value': _q('${85 - day * 0.1}', 'kg'),
          'observedAt': '${_date(day)}T07:00:00+01:00',
          'attributes': {'context': 'health'},
        });
        await record({
          'id': 'bia-$day',
          'measure': 'body-fat',
          'value': _q('22', 'percent'),
          'date': _date(day),
          'attributes': {'method': 'bio-impedance'},
        });
      }
      for (final (site, cm) in [('navel', '92'), ('neck', '39')]) {
        await record({
          'id': site,
          'measure': 'circumference',
          'value': _q(cm, 'cm'),
          'date': _date(8),
          'attributes': {'site': site},
        });
      }
      final asOf = '${_date(29)}T20:00:00+01:00';
      var report = await body.report(asOf);
      equal(report['policy'], 'bodytmi-body-report/1');
      // Navy from today's trend context and a three-week-old navel/neck.
      final navy = _calc(report, 'navy-body-fat');
      equal(navy['status'], 'resolved');
      final inputs = jsonObject(navy['inputs'], 'inputs');
      final navel = jsonObject(
        jsonObject(inputs['navel'], 'navel')['provenance'],
        'p',
      );
      equal(navel['ageDays'], 21);
      equal(navel['observedOn'], _date(8));
      final mass = jsonObject(
        jsonObject(report['measures'], 'm')['mass'],
        'mass',
      );
      equal(mass['used'], 'trend');
      equal(mass['ageDays'], 0);
      // The default source is Navy; fat-free mass uses it.
      final source = jsonObject(report['bodyFatSource'], 'source');
      equal(source['origin'], 'default');
      jsonEqual(
        jsonObject(source['source'], 's')['calculation'],
        'navy-body-fat',
      );
      equal(_calc(report, 'fat-free-mass')['status'], 'resolved');
      equal(_calc(report, 'bmi')['status'], 'resolved');
      // No skinfolds: Jackson–Pollock is unavailable, naming sites.
      final jp = _calc(report, 'jackson-pollock-3');
      equal(jp['status'], 'unavailable');
      check((jp['missing']! as List).contains('chest'));

      // Selecting bio-impedance from day 20 changes later reports only.
      await body.selectSource(
        _date(20),
        BodyFatSource.fromJson({'kind': 'series', 'method': 'bio-impedance'}),
        0,
      );
      final before = await body.report('${_date(15)}T20:00:00+01:00');
      equal(jsonObject(before['bodyFatSource'], 's')['origin'], 'default');
      report = await body.report(asOf);
      final bia = jsonObject(report['bodyFatSource'], 's');
      equal(bia['origin'], 'selected');
      equal(
        Quantity.fromJson(bia['value']).value.compareTo(Decimal.parse('0.22')),
        0,
      );
      // An explicit mean lists both components.
      await body.selectSource(
        _date(25),
        BodyFatSource.fromJson({
          'kind': 'mean',
          'components': [
            {'kind': 'calculation', 'calculation': 'navy-body-fat'},
            {'kind': 'series', 'method': 'bio-impedance'},
          ],
        }),
        1,
      );
      report = await body.report(asOf);
      final mean = jsonObject(report['bodyFatSource'], 's');
      equal(mean['status'], 'resolved');
      equal((mean['components']! as List).length, 2);
      // A mean with an unavailable component is unavailable.
      await body.selectSource(
        _date(26),
        BodyFatSource.fromJson({
          'kind': 'mean',
          'components': [
            {'kind': 'series', 'method': 'dexa'},
            {'kind': 'series', 'method': 'bio-impedance'},
          ],
        }),
        2,
      );
      report = await body.report(asOf);
      equal(jsonObject(report['bodyFatSource'], 's')['status'], 'unavailable');
      equal(_calc(report, 'fat-free-mass')['status'], 'unavailable');

      // Skinfolds from different days are refused; one day works.
      for (final (site, mm, day) in [
        ('chest', '10', 27),
        ('abdomen', '20', 28),
        ('thigh', '15', 28),
      ]) {
        await record({
          'id': 'sf-$site',
          'measure': 'skinfold',
          'value': _q(mm, 'mm'),
          'date': _date(day),
          'attributes': {'site': site},
        });
      }
      report = await body.report(asOf);
      check(
        (_calc(report, 'jackson-pollock-3')['reason']! as String).contains(
          'different days',
        ),
      );
      await observations.save({
        'id': 'sf-chest',
        'measure': 'skinfold',
        'value': _q('10', 'mm'),
        'date': _date(28),
        'attributes': {'site': 'chest'},
      }, 1);
      report = await body.report(asOf);
      final jp3 = _calc(report, 'jackson-pollock-3');
      equal(jp3['status'], 'resolved');
      equal(
        jsonObject(jsonObject(jp3['inputs'], 'i')['age'], 'age')['value'],
        41,
      );

      // A corrected weigh-in changes the next report.
      final massBefore = jsonObject(
        jsonObject(report['measures'], 'm')['mass'],
        'mass',
      )['value'];
      await observations.save({
        'id': 'mass-29',
        'measure': 'body-mass',
        'value': _q('70', 'kg'),
        'observedAt': '${_date(29)}T07:00:00+01:00',
        'attributes': {'context': 'health'},
      }, 1);
      report = await body.report(asOf);
      check(
        jsonEncode(
              jsonObject(
                jsonObject(report['measures'], 'm')['mass'],
                'm',
              )['value'],
            ) !=
            jsonEncode(massBefore),
        'the corrected weigh-in moved the trend',
      );
      // Archives carry profile and selections.
      final archive = (await store.archive()).toJson();
      final parsed = TrainingArchive.fromJson(archive);
      equal(parsed.profile.length, 1);
      equal(parsed.bodyFatSources.length, 3);
      final backup = '${dir.path}/backup';
      await store.backup(backup);
      NativeBackup.validateDatabase('$backup/database.sqlite');
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });

  test('CLI profile, body source and body report', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-body-cli-');
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
      equal((await cli('profile show', {})).data, null);
      equal(
        (await cli('profile set', {
          'profile': {'sex': 'female'},
          'expectedRevision': 0,
        })).code,
        0,
      );
      equal(
        (await cli('profile set', {
          'profile': {'sex': 'other'},
          'expectedRevision': 1,
        })).code,
        2,
      );
      equal(
        (await cli('body source', {
          'from': '2026-11-01',
          'source': {'kind': 'series', 'method': 'scale'},
          'expectedRevision': 0,
        })).code,
        2,
      );
      equal(
        (await cli('body source', {
          'from': '2026-11-01',
          'source': {'kind': 'series', 'method': 'dexa'},
          'expectedRevision': 0,
        })).code,
        0,
      );
      equal(((await cli('body sources', {})).data! as List).length, 1);
      final report = await cli('body report', {
        'asOf': '2026-11-16T12:00:00+01:00',
      });
      equal(report.code, 0);
      equal(
        jsonObject(jsonObject(report.data, 'r')['calculations'], 'c').length,
        11,
      );
      equal((await cli('body report', {'asOf': '2026-11-16'})).code, 2);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
