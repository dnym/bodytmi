import 'package:bodytmi_core/bodytmi_core.dart';
import 'support.dart';

String _canonical(String value, String unit) =>
    Quantity(value, unit).value.toString();

/// Health quantities convert exactly to their canonical units; count-like
/// dimensions stay whole numbers and never convert into each other.
void unitTests() {
  test('health units convert exactly to canonical units', () {
    equal(_canonical('1', 'kcal'), '4.184');
    equal(Quantity('1', 'kcal').unit, Unit.kJ);
    equal(_canonical('250', 'ml'), '0.25');
    equal(_canonical('2', 'dl'), '0.2');
    equal(_canonical('33', 'cl'), '0.33');
    equal(_canonical('25', 'percent'), '0.25');
    equal(_canonical('500', 'mg'), '0.0005');
    equal(_canonical('120', 'g'), '0.12');
    equal(_canonical('400', 'mcg'), '0.0000004');
    equal(_canonical('1', 'wk'), '604800');
    equal(_canonical('2', 'd'), '172800');
    equal(_canonical('1.5', 'h'), '5400');
    equal(_canonical('5', 'km'), '5000');
    equal(Quantity('36.8', 'degC').dimension, Dimension.temperature);
    equal(Quantity('120', 'mmHg').dimension, Dimension.pressure);
    equal(Quantity('58', 'bpm').dimension, Dimension.frequency);
    // Entered value and unit are kept for display and provenance.
    final kcal = Quantity.fromJson({'value': '2000', 'unit': 'kcal'});
    equal(kcal.enteredValue, '2000');
    equal(kcal.enteredUnit, Unit.kcal);
    jsonEqual(Quantity.fromJson(kcal.toJson()).toJson(), kcal.toJson());
  });

  test('steps, repetitions and tallies are separate whole counts', () {
    equal(Quantity('8000', 'step').dimension, Dimension.steps);
    equal(Quantity('3', 'count').dimension, Dimension.tally);
    rejects(() => Quantity('8000.5', 'step'));
    rejects(() => Quantity('1.5', 'count'));
    rejects(() => Quantity('8', 'rep').compareTo(Quantity('8', 'step')));
    rejects(() => Quantity('-1', 'kcal'));
    rejects(() => Unit.parse('µg'));
  });
}
