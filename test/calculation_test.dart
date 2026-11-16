import 'dart:convert';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'cli_test.dart';
import 'support.dart';

Quantity _q(String value, String unit) => Quantity(value, unit);

Map<String, Object?> _eval(String id, Map<String, Object?> inputs) =>
    calculation('bodytmi-calc/$id/1').evaluate(inputs);

String? _value(Map<String, Object?> r) =>
    jsonObject(r['value'], 'value')['value'] as String?;

String? _label(Map<String, Object?> r) =>
    jsonObject(r['category'], 'category')['label'] as String?;

/// Named, versioned formulas with their sources, inputs and categories.
void calculationTests() {
  test('BMI, waist ratios and their reference categories', () {
    var r = _eval('bmi', {'mass': _q('80', 'kg'), 'height': _q('180', 'cm')});
    equal(r['status'], 'resolved');
    equal(_value(r), '24.691358025');
    equal(_label(r), 'normal');
    equal(jsonObject(r['category'], 'c')['policy'], 'who-bmi-adult/1');
    // Entered units are kept in the input echo; lb converts exactly.
    r = _eval('bmi', {
      'mass': _q('176.3698097', 'lb'),
      'height': _q('1.8', 'm'),
    });
    check(_value(r)!.startsWith('24.69135'), _value(r)!);
    jsonEqual(jsonObject(jsonObject(r['inputs'], 'i')['mass'], 'm')['value'], {
      'value': '176.3698097',
      'unit': 'lb',
    });
    r = _eval('waist-to-height', {
      'waist': _q('90', 'cm'),
      'height': _q('180', 'cm'),
    });
    equal(_value(r), '0.5');
    equal(_label(r), 'increased health risk');
    r = _eval('waist-to-hip', {
      'sex': 'male',
      'waist': _q('90', 'cm'),
      'hip': _q('100', 'cm'),
    });
    equal(_label(r), 'substantially increased risk');
    r = _eval('waist-risk', {'sex': 'female', 'waist': _q('85', 'cm')});
    equal(_label(r), 'increased');
  });

  test('body-fat estimates', () {
    var r = _eval('navy-body-fat', {
      'sex': 'male',
      'navel': _q('90', 'cm'),
      'neck': _q('38', 'cm'),
      'height': _q('180', 'cm'),
    });
    equal(_value(r), '0.198119884');
    r = _eval('navy-body-fat', {
      'sex': 'female',
      'waist': _q('75', 'cm'),
      'hip': _q('100', 'cm'),
      'neck': _q('33', 'cm'),
      'height': _q('165', 'cm'),
    });
    equal(_value(r), '0.294342376');
    r = _eval('jackson-pollock-3', {
      'sex': 'male',
      'chest': _q('10', 'mm'),
      'abdomen': _q('20', 'mm'),
      'thigh': _q('15', 'mm'),
      'age': 30,
    });
    equal(_value(r), '0.136148943');
    r = _eval('jackson-pollock-7', {
      'sex': 'female',
      for (final site in [
        'chest',
        'midaxillary',
        'triceps',
        'subscapular',
        'abdomen',
        'suprailiac',
        'thigh',
      ])
        site: _q('12', 'mm'),
      'age': 40,
    });
    equal(_value(r), '0.185882483');
  });

  test('missing inputs make a calculation unavailable, naming them', () {
    var r = _eval('navy-body-fat', {
      'neck': _q('38', 'cm'),
      'height': _q('180', 'cm'),
    });
    equal(r['status'], 'unavailable');
    jsonEqual(r['missing'], ['sex']);
    r = _eval('navy-body-fat', {
      'sex': 'male',
      'neck': _q('38', 'cm'),
      'height': _q('180', 'cm'),
    });
    jsonEqual(r['missing'], ['navel']);
    r = _eval('jackson-pollock-3', {
      'sex': 'female',
      'triceps': _q('12', 'mm'),
      'thigh': _q('20', 'mm'),
      'age': 35,
    });
    jsonEqual(r['missing'], ['suprailiac']);
    rejects(
      () => _eval('bmi', {'mass': _q('80', 'cm'), 'height': _q('1', 'm')}),
    );
    rejects(
      () => _eval('waist-risk', {'sex': 'other', 'waist': _q('80', 'cm')}),
    );
    rejects(() => calculation('bodytmi-calc/mystery/1'), 'not_found');
  });

  test('fat-free mass, FFMI, target mass and walking energy', () {
    final body = {
      'mass': _q('80', 'kg'),
      'bodyFat': _q('20', 'percent'),
      'height': _q('180', 'cm'),
    };
    equal(_value(_eval('fat-mass', body)), '16');
    equal(_value(_eval('fat-free-mass', body)), '64');
    equal(_value(_eval('ffmi', body)), '19.75308642');
    equal(_value(_eval('normalized-ffmi', body)), '19.75308642');
    equal(
      _value(
        _eval('target-mass', {...body, 'goalBodyFat': _q('15', 'percent')}),
      ),
      '75.294117647',
    );
    equal(
      _value(
        _eval('walking-energy', {
          'steps': _q('10000', 'step'),
          'stepLength': _q('75', 'cm'),
          'mass': _q('80', 'kg'),
        }),
      ),
      '450',
    );
  });

  test('CLI calc list and evaluate', () async {
    final list = await invoke([
      'calc',
      'list',
    ], jsonEncode({'schemaVersion': 1}));
    equal(list.code, 0);
    equal(
      (jsonObject(jsonDecode(list.output), 'r')['data']! as List).length,
      calculations.length,
    );
    final r = await invoke(
      ['calc', 'evaluate'],
      jsonEncode({
        'schemaVersion': 1,
        'calculation': 'bodytmi-calc/bmi/1',
        'inputs': {
          'mass': {'value': '80', 'unit': 'kg'},
          'height': {'value': '180', 'unit': 'cm'},
        },
      }),
    );
    equal(r.code, 0);
    final unknown = await invoke(
      ['calc', 'evaluate'],
      jsonEncode({
        'schemaVersion': 1,
        'calculation': 'nope',
        'inputs': <String, Object?>{},
      }),
    );
    equal(unknown.code, 3);
  });
}
