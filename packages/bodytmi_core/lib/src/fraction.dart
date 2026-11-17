import 'errors.dart';
import 'quantity.dart';

/// An exact nonnegative-or-negative rational number. Food arithmetic divides
/// (densities, batch weights, portions of a batch), so totals are kept as
/// fractions and rounded once, when shown.
final class Fraction implements Comparable<Fraction> {
  Fraction._(this.numerator, this.denominator);

  factory Fraction(BigInt numerator, BigInt denominator) {
    if (denominator == BigInt.zero) invalid('Division by zero.');
    if (denominator.isNegative) {
      numerator = -numerator;
      denominator = -denominator;
    }
    final g = numerator.gcd(denominator);
    if (g > BigInt.one) {
      numerator = numerator ~/ g;
      denominator = denominator ~/ g;
    }
    return Fraction._(numerator, denominator);
  }

  factory Fraction.decimal(Decimal value) =>
      Fraction(value.coefficient, BigInt.from(10).pow(value.scale));

  factory Fraction.parse(String text) => Fraction.decimal(Decimal.parse(text));

  factory Fraction.integer(int value) =>
      Fraction._(BigInt.from(value), BigInt.one);

  static final zero = Fraction._(BigInt.zero, BigInt.one);
  static final one = Fraction._(BigInt.one, BigInt.one);

  final BigInt numerator;
  final BigInt denominator;

  bool get isZero => numerator == BigInt.zero;

  Fraction operator +(Fraction o) => Fraction(
    numerator * o.denominator + o.numerator * denominator,
    denominator * o.denominator,
  );
  Fraction operator -(Fraction o) => Fraction(
    numerator * o.denominator - o.numerator * denominator,
    denominator * o.denominator,
  );
  Fraction operator *(Fraction o) =>
      Fraction(numerator * o.numerator, denominator * o.denominator);
  Fraction operator /(Fraction o) {
    if (o.isZero) invalid('Division by zero.');
    return Fraction(numerator * o.denominator, denominator * o.numerator);
  }

  /// Exact when the denominator has only factors 2 and 5.
  bool get isTerminating {
    var d = denominator;
    for (final p in [BigInt.two, BigInt.from(5)]) {
      while (d % p == BigInt.zero) {
        d = d ~/ p;
      }
    }
    return d == BigInt.one;
  }

  /// Rounded half away from zero to [fractionDigits] digits.
  Decimal round({int fractionDigits = 9}) {
    final scale = BigInt.from(10).pow(fractionDigits);
    final n = numerator.abs() * scale;
    var q = n ~/ denominator;
    if ((n % denominator) * BigInt.two >= denominator) q += BigInt.one;
    final digits = q.toString().padLeft(fractionDigits + 1, '0');
    final text = fractionDigits == 0
        ? digits
        : '${digits.substring(0, digits.length - fractionDigits)}.'
              '${digits.substring(digits.length - fractionDigits)}';
    final parsed = Decimal.parse(text);
    return numerator.isNegative
        ? Decimal.parse('-${parsed.toString()}')
        : Decimal.parse(parsed.toString());
  }

  @override
  int compareTo(Fraction o) =>
      (numerator * o.denominator).compareTo(o.numerator * denominator);
  @override
  bool operator ==(Object o) =>
      o is Fraction && numerator == o.numerator && denominator == o.denominator;
  @override
  int get hashCode => Object.hash(numerator, denominator);
  @override
  String toString() => '$numerator/$denominator';
}
