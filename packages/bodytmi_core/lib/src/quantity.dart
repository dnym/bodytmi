import 'errors.dart';

/// Exact base-ten arithmetic for quantities, avoiding unit-conversion drift.
final class Decimal implements Comparable<Decimal> {
  Decimal._(this.coefficient, this.scale);

  factory Decimal.parse(String text) {
    if (text.length > 80 || !RegExp(r'^-?\d+(\.\d+)?$').hasMatch(text)) {
      invalid('Expected a decimal string of at most 80 characters: $text.');
    }
    final parts = text.split('.');
    return Decimal._(
      BigInt.parse(parts.join()),
      parts.length == 2 ? parts[1].length : 0,
    );
  }

  final BigInt coefficient;
  final int scale;
  static final zero = Decimal.parse('0');
  static BigInt _pow(int n) => BigInt.from(10).pow(n);
  BigInt _at(int targetScale) => coefficient * _pow(targetScale - scale);

  Decimal operator +(Decimal other) {
    final targetScale = scale > other.scale ? scale : other.scale;
    return Decimal._(_at(targetScale) + other._at(targetScale), targetScale);
  }

  Decimal operator -(Decimal other) =>
      this + Decimal._(-other.coefficient, other.scale);

  Decimal operator *(Decimal other) =>
      Decimal._(coefficient * other.coefficient, scale + other.scale);

  /// Division for derived statistics, rounded half away from zero to the
  /// explicitly chosen precision. Raw observations are never rounded by this.
  Decimal dividedByInt(int divisor, {int fractionDigits = 9}) {
    if (divisor <= 0 || fractionDigits < 0 || fractionDigits > 40) {
      invalid('Division needs a positive divisor and precision from 0 to 40.');
    }
    final numerator = coefficient.abs() * _pow(fractionDigits);
    final denominator = BigInt.from(divisor) * _pow(scale);
    var rounded = numerator ~/ denominator;
    if ((numerator % denominator) * BigInt.two >= denominator) {
      rounded += BigInt.one;
    }
    return Decimal._(
      coefficient.isNegative ? -rounded : rounded,
      fractionDigits,
    );
  }

  bool get isInteger => coefficient % _pow(scale) == BigInt.zero;

  /// The largest multiple of a positive [step] not above this nonnegative
  /// value, exactly.
  Decimal floorToMultiple(Decimal step) {
    if (step.coefficient <= BigInt.zero || coefficient.isNegative)
      invalid('Rounding needs a positive step and a nonnegative value.');
    final s = scale > step.scale ? scale : step.scale;
    final unit = step._at(s);
    return Decimal._((_at(s) ~/ unit) * unit, s);
  }

  @override
  int compareTo(Decimal other) {
    final targetScale = scale > other.scale ? scale : other.scale;
    return _at(targetScale).compareTo(other._at(targetScale));
  }

  @override
  bool operator ==(Object other) => other is Decimal && compareTo(other) == 0;
  @override
  int get hashCode => toString().hashCode;

  @override
  String toString() {
    var digits = coefficient.abs().toString().padLeft(scale + 1, '0');
    if (scale > 0) {
      digits =
          '${digits.substring(0, digits.length - scale)}.'
          '${digits.substring(digits.length - scale)}';
      digits = digits.replaceFirst(RegExp(r'0+$'), '');
      digits = digits.replaceFirst(RegExp(r'\.$'), '');
    }
    return coefficient.isNegative ? '-$digits' : digits;
  }
}

enum Dimension { mass, distance, duration, count, angle }

enum Unit {
  kg(Dimension.mass, '1'),
  lb(Dimension.mass, '0.45359237'),
  m(Dimension.distance, '1'),
  cm(Dimension.distance, '0.01'),
  mm(Dimension.distance, '0.001'),
  s(Dimension.duration, '1'),
  ms(Dimension.duration, '0.001'),
  min(Dimension.duration, '60'),
  rep(Dimension.count, '1'),
  deg(Dimension.angle, '1');

  const Unit(this.dimension, this.factor);
  final Dimension dimension;
  final String factor;

  static Unit parse(String name) {
    for (final unit in values) {
      if (unit.name == name) return unit;
    }
    invalid('Unsupported unit: $name.');
  }

  Unit get canonical => switch (dimension) {
    Dimension.mass => kg,
    Dimension.distance => m,
    Dimension.duration => s,
    Dimension.count => rep,
    Dimension.angle => deg,
  };
}

final class Quantity implements Comparable<Quantity> {
  Quantity._(this.value, this.unit, this.enteredValue, this.enteredUnit);

  factory Quantity(String value, String unit) {
    final parsed = Decimal.parse(value);
    final parsedUnit = Unit.parse(unit);
    if (parsed.compareTo(Decimal.zero) < 0)
      invalid('Quantity cannot be negative.');
    if (parsedUnit.dimension == Dimension.count && !parsed.isInteger) {
      invalid('Repetitions must be integers.');
    }
    return Quantity._(
      parsed * Decimal.parse(parsedUnit.factor),
      parsedUnit.canonical,
      value,
      parsedUnit,
    );
  }

  factory Quantity.fromJson(Object? input) {
    final json = jsonObject(input, 'quantity');
    checkKeys(json, {'value', 'unit', 'entered'});
    final quantity = Quantity(
      requiredString(json, 'value'),
      requiredString(json, 'unit'),
    );
    if (json['entered'] case final Object entered) {
      final sourceJson = jsonObject(entered, 'entered quantity');
      checkKeys(sourceJson, {'value', 'unit'});
      final source = Quantity(
        requiredString(sourceJson, 'value'),
        requiredString(sourceJson, 'unit'),
      );
      if (source.unit != quantity.unit || source.value != quantity.value) {
        invalid('Entered value does not match canonical quantity.');
      }
      return source;
    }
    return quantity;
  }

  final Decimal value;
  final Unit unit;
  final String enteredValue;
  final Unit enteredUnit;
  Dimension get dimension => unit.dimension;

  @override
  int compareTo(Quantity other) {
    if (dimension != other.dimension)
      invalid('Cannot compare different dimensions.');
    return value.compareTo(other.value);
  }

  Quantity add(Quantity delta) {
    if (dimension != delta.dimension) invalid('Increment dimension mismatch.');
    return Quantity((value + delta.value).toString(), unit.name);
  }

  Map<String, Object?> toJson() => {
    'value': value.toString(),
    'unit': unit.name,
    'entered': {'value': enteredValue, 'unit': enteredUnit.name},
  };
}

typedef Metrics = Map<String, Quantity>;

Metrics metricsFromJson(Object? input) {
  final json = jsonObject(input, 'metrics');
  return Map.unmodifiable({
    for (final entry in json.entries)
      identifier({'metric': entry.key}, 'metric'): Quantity.fromJson(
        entry.value,
      ),
  });
}

Map<String, Object?> metricsToJson(Metrics metrics) => {
  for (final entry in metrics.entries) entry.key: entry.value.toJson(),
};
