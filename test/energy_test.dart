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

EnergyInputs _inputs({
  double? massKg,
  double? heightCm,
  double? fatFreeMassKg,
  int? age,
  String? sex,
  int? category,
}) => (
  massKg: massKg,
  heightCm: heightCm,
  fatFreeMassKg: fatFreeMassKg,
  age: age,
  sex: sex,
  category: category,
);

String _kcal(Map<String, Object?> result) =>
    jsonObject(result['value'], 'value')['value']! as String;

Future<BodyTmiException> _failure(Future<Object?> Function() action) async {
  try {
    await action();
  } on BodyTmiException catch (error) {
    return error;
  }
  throw StateError('Expected a BodyTmiException.');
}

void energyTests() {
  test('diet categories and maintenance formulas', () {
    Decimal d(String v) => Decimal.parse(v);
    equal(dietCategory(d('0.15'), 'male'), 1);
    equal(dietCategory(d('0.154'), 'male'), 1);
    equal(dietCategory(d('0.155'), 'male'), 2);
    equal(dietCategory(d('0.25'), 'male'), 2);
    equal(dietCategory(d('0.26'), 'male'), 3);
    equal(dietCategory(d('0.24'), 'female'), 1);
    equal(dietCategory(d('0.345'), 'female'), 3);
    rejects(() => dietCategory(d('0.2'), 'other'));

    MaintenanceMethod m(Map<String, Object?> j) =>
        MaintenanceMethod.fromJson(j);
    final lb200 = 200 * kgPerLb, lb135 = 135 * kgPerLb;
    // IMF ch. 14, Joe: 200 lb, category 2, moderate 1.3 + 120 min medium
    // aerobic 0.6 = 1.9 → 17.1 cal/lb × 200 = 3,420 (the book rounds to
    // 3,400).
    final joe = m({
      'formula': 'mcdonald-imf-tdee',
      'activity': 'moderate',
      'exercise': [
        {'kind': 'medium-aerobic', 'hours': '2'},
      ],
    }).evaluate(_inputs(massKg: lb200, category: 2));
    equal(_kcal(joe), '3420');
    equal(jsonObject(joe['factors'], 'f')['multiplier'], '1.9');
    // Sue: 135 lb, category 1, light 1.2 + one hour of high-intensity
    // weights 0.2 = 1.4 → 14 cal/lb × 135 = 1,890. (The book's example
    // writes 0.3 for that hour, which its own table does not give.)
    equal(
      _kcal(
        m({
          'formula': 'mcdonald-imf-tdee',
          'activity': 'light',
          'exercise': [
            {'kind': 'high-weights', 'hours': '1'},
          ],
        }).evaluate(_inputs(massKg: lb135, category: 1)),
      ),
      '1890',
    );
    // RFL handbook ch. 14: body weight × cal/lb within the range.
    equal(
      _kcal(
        m({
          'formula': 'mcdonald-rfl-maintenance',
          'activity': 'moderate',
          'calPerLb': '12.5',
        }).evaluate(_inputs(massKg: lb200)),
      ),
      '2500',
    );
    rejects(
      () => m({
        'formula': 'mcdonald-rfl-maintenance',
        'activity': 'very',
        'calPerLb': '13',
      }),
    );
    // Mifflin–St Jeor: 10·80 + 6.25·180 − 5·30 + 5 = 1,780 × 1.5.
    equal(
      _kcal(
        m({
          'formula': 'mifflin-st-jeor',
          'pal': '1.5',
        }).evaluate(_inputs(massKg: 80, heightCm: 180, age: 30, sex: 'male')),
      ),
      '2670',
    );
    // Female −161, and a −10 % adjustment.
    equal(
      _kcal(
        m({
          'formula': 'mifflin-st-jeor',
          'pal': '1.4',
          'adjustment': '-0.1',
        }).evaluate(_inputs(massKg: 60, heightCm: 165, age: 40, sex: 'female')),
      ),
      // (600 + 1031.25 − 200 − 161) × 1.4 × 0.9
      '1600.515',
    );
    // Katch–McArdle: 370 + 21.6 · 60.
    equal(
      _kcal(
        m({
          'formula': 'katch-mcardle',
          'pal': '1',
        }).evaluate(_inputs(fatFreeMassKg: 60)),
      ),
      '1666',
    );
    equal(
      _kcal(
        m({
          'formula': 'manual',
          'energy': _q('10000', 'kJ'),
        }).evaluate(_inputs()),
      ),
      '2390.057361377',
    );
    final missing = m({
      'formula': 'mifflin-st-jeor',
      'pal': '1.5',
    }).evaluate(_inputs(massKg: 80));
    equal(missing['status'], 'unavailable');
    jsonEqual(missing['missing'], ['height', 'age', 'sex']);
    rejects(() => m({'formula': 'mcdonald-imf-tdee', 'activity': 'very-high'}));
    rejects(
      () => m({
        'formula': 'mcdonald-imf-tdee',
        'activity': 'light',
        'exercise': [
          {'kind': 'yoga', 'hours': '1'},
        ],
      }),
    );
    rejects(() => m({'formula': 'manual', 'energy': _q('80', 'kg')}));
  });

  test('stored maintenance method and energy estimate', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-energy-');
    final store = await TrainingStore.open('${dir.path}/db.sqlite');
    try {
      final body = BodyService(store);
      final observations = ObservationService(store);
      final energy = EnergyService(store);
      const asOf = '2026-11-16T20:00:00+01:00';
      var estimate = await energy.estimate(asOf);
      equal(jsonObject(estimate['maintenance'], 'm')['status'], 'unavailable');
      equal(estimate['methodOrigin'], 'none');
      await body.setProfile(
        Profile.fromJson({'sex': 'male', 'birthDate': '1990-01-01'}),
        0,
      );
      Future<void> record(Map<String, Object?> o) => observations.save(o, 0);
      await record({
        'id': 'h',
        'measure': 'height',
        'value': _q('180', 'cm'),
        'date': '2026-01-01',
      });
      await record({
        'id': 'm',
        'measure': 'body-mass',
        'value': _q('200', 'lb'),
        'observedAt': '2026-11-16T07:00:00+01:00',
        'attributes': {'context': 'health'},
      });
      await record({
        'id': 'bf',
        'measure': 'body-fat',
        'value': _q('22', 'percent'),
        'date': '2026-11-16',
        'attributes': {'method': 'dexa'},
      });
      await body.selectSource(
        '2026-01-01',
        BodyFatSource.fromJson({'kind': 'series', 'method': 'dexa'}),
        0,
      );
      await energy.selectMethod(
        '2026-11-01',
        MaintenanceMethod.fromJson({
          'formula': 'mcdonald-imf-tdee',
          'activity': 'moderate',
          'exercise': [
            {'kind': 'medium-aerobic', 'hours': '2'},
          ],
        }),
        0,
      );
      equal(
        (await _failure(
          () => energy.selectMethod(
            '2026-11-01',
            MaintenanceMethod.fromJson({
              'formula': 'katch-mcardle',
              'pal': '1',
            }),
            0,
          ),
        )).code,
        'conflict',
      );
      estimate = await energy.estimate(asOf);
      equal(estimate['methodOrigin'], 'selected');
      final inputs = jsonObject(estimate['inputs'], 'inputs');
      equal(jsonObject(inputs['category'], 'c')['value'], 2);
      equal(jsonObject(inputs['mass'], 'mass')['ageDays'], 0);
      final maintenance = jsonObject(estimate['maintenance'], 'm');
      equal(_kcal(maintenance), '3420');
      // Before the selection there is no method; a request method works.
      final earlier = await energy.estimate(
        '2026-10-30T20:00:00+01:00',
        method: MaintenanceMethod.fromJson({
          'formula': 'katch-mcardle',
          'pal': '1',
        }),
      );
      equal(earlier['methodOrigin'], 'request');
      // No mass before 2026-11-16: unavailable, naming it.
      jsonEqual(jsonObject(earlier['maintenance'], 'm')['missing'], [
        'fatFreeMass',
      ]);

      // Archives carry diet records; a forged row is rejected.
      final json = (await store.archive()).toJson();
      equal((json['dietRecords']! as List).length, 1);
      TrainingArchive.fromJson(json);
      final forged = jsonDecode(jsonEncode(json)) as Map<String, Object?>;
      ((forged['dietRecords']! as List).single as Map)['number'] = 2;
      rejects(() => TrainingArchive.fromJson(forged));
      final unknown = jsonDecode(jsonEncode(json)) as Map<String, Object?>;
      ((unknown['dietRecords']! as List).single as Map)['kind'] = 'mystery';
      rejects(() => TrainingArchive.fromJson(unknown));
      final backup = '${dir.path}/backup';
      await store.backup(backup);
      NativeBackup.validateDatabase('$backup/database.sqlite');
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });

  test('CLI energy method and estimate', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-energy-cli-');
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
        (await cli('energy method', {
          'from': '2026-11-01',
          'method': {
            'formula': 'mcdonald-rfl-maintenance',
            'activity': 'light',
            'calPerLb': '20',
          },
          'expectedRevision': 0,
        })).code,
        2,
      );
      equal(
        (await cli('energy method', {
          'from': '2026-11-01',
          'method': {'formula': 'manual', 'energy': _q('2500', 'kcal')},
          'expectedRevision': 0,
        })).code,
        0,
      );
      equal(((await cli('energy methods', {})).data! as List).length, 1);
      final estimate = await cli('energy estimate', {
        'asOf': '2026-11-16T12:00:00+01:00',
      });
      equal(estimate.code, 0);
      equal(
        _kcal(jsonObject(jsonObject(estimate.data, 'e')['maintenance'], 'm')),
        '2500',
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
