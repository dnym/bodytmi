import 'package:bodytmi_core/bodytmi_core.dart';
import 'support.dart';

void quantityTests() {
  test('100 lb is exactly 45.359237 kg with original input retained', () {
    final q = Quantity('100', 'lb');
    equal(q.value.toString(), '45.359237');
    equal(q.unit, Unit.kg);
    equal(q.enteredUnit, Unit.lb);
    for (var i = 0; i < 100; i++) {
      final restored = Quantity.fromJson(q.toJson());
      equal(restored.value, q.value);
      equal(restored.enteredValue, '100');
    }
  });
  test('decimal arithmetic and equality do not depend on scale', () {
    equal((Decimal.parse('0.1') + Decimal.parse('0.2')).toString(), '0.3');
    equal(Decimal.parse('1.000'), Decimal.parse('1'));
    equal(Decimal.parse('1.000').hashCode, Decimal.parse('1').hashCode);
    equal((Decimal.parse('1') - Decimal.parse('0.25')).toString(), '0.75');
  });
  test('zero added mass is valid; invalid/fractional counts are rejected', () {
    equal(Quantity('0', 'kg').value, Decimal.zero);
    equal(Quantity('8.0', 'rep').value.toString(), '8');
    for (final v in ['NaN', 'Infinity', '1e3', '-1', '.1']) {
      rejects(() => Quantity(v, 'kg'));
    }
    rejects(() => Quantity('1.5', 'rep'));
    rejects(() => Quantity('1', 'stone'));
  });
  test('metric dimension checks forbid seconds added to kilograms', () {
    rejects(() => Quantity('10', 'kg').add(Quantity('1', 's')));
    rejects(() => Quantity('10', 'kg').compareTo(Quantity('10', 's')));
    equal(Quantity('100', 'cm').compareTo(Quantity('1', 'm')), 0);
    equal(Quantity('60000', 'ms').compareTo(Quantity('1', 'min')), 0);
  });
  test('contradictory provenance and nested entered payloads are rejected', () {
    rejects(
      () => Quantity.fromJson({
        'value': '10',
        'unit': 'kg',
        'entered': {'value': '10', 'unit': 'lb'},
      }),
    );
    rejects(
      () => Quantity.fromJson({
        'value': '10',
        'unit': 'kg',
        'entered': {
          'value': '10',
          'unit': 'kg',
          'entered': <String, Object?>{},
        },
      }),
    );
    rejects(() => Quantity.fromJson({'value': 10, 'unit': 'kg'}));
  });
}
