import 'errors.dart';
import 'equipment.dart';
import 'quantity.dart';

/// Deterministic exact-decimal plate helper for one declared loading channel.
/// It only returns arrangements physically available from the declared
/// inventory and components. When the target is not exactly reachable it
/// returns explicitly labeled nearest lower and higher choices instead of
/// silently re-rounding the prescription into an unavailable arrangement, and
/// equipment without a declared loading configuration never receives an
/// assumed bar, collar or symmetric-side convention. A symmetric channel
/// consumes plate pairs; an independent channel may differ per side and its
/// two-side allocation is a display assignment of the achieved total.
final class PlatePlan {
  PlatePlan._();

  static const policy = 'bodytmi-plate-plan/1';

  static Map<String, Object?> evaluate(LoadingSpec loading, Quantity target) {
    if (target.dimension != Dimension.mass)
      invalid('The plate plan target must have mass dimension.');
    final tare = loading.tareMass;
    final channel = loading.channel;
    final factor = BigInt.from(channel.sides);
    // The finest declared or requested fraction drives the working scale;
    // target and tare compare through exact BigInt rescaling so no unit or
    // decimal place is lost.
    var scale = 0;
    for (final plate in loading.plates)
      if (plate.mass.value.scale > scale) scale = plate.mass.value.scale;
    if (target.value.scale > scale) scale = target.value.scale;
    if (tare.scale > scale) scale = tare.scale;
    BigInt at(Decimal value) =>
        value.coefficient * BigInt.from(10).pow(scale - value.scale);
    Quantity mass(BigInt coefficient) =>
        Quantity(_decimalString(coefficient, scale), 'kg');
    final tareScaled = at(tare);
    final remaining = at(target.value) - tareScaled;
    var unit = BigInt.zero;
    var maxStep = BigInt.zero;
    for (final plate in loading.plates) {
      final value = at(plate.mass.value);
      unit = unit == BigInt.zero ? value : _gcd(unit, value);
      if (value > maxStep) maxStep = value;
    }
    final steps = <BigInt>[
      for (final plate in loading.plates) at(plate.mass.value) ~/ unit,
    ];
    // A symmetric side receives one plate of each available group, where a
    // group holds one plate per side of the channel.
    final group = BigInt.from(channel.sides);
    final available = [
      for (final plate in loading.plates)
        if (channel.symmetric)
          (BigInt.from(plate.count) ~/ group).toInt()
        else
          plate.count,
    ];
    // A symmetric arrangement reconstructs one side, so each search step
    // carries the denomination on every side. An independent pool holds all
    // plates together, so a step adds the denomination once across sides.
    final perStep = (channel.symmetric ? factor : BigInt.one) * unit;
    var parent = const <int>[];
    var coin = const <int>[];

    List<int> reconstruct(int k) {
      final used = List<int>.filled(loading.plates.length, 0);
      var at_ = k;
      while (at_ > 0) {
        used[coin[at_]] += 1;
        at_ = parent[at_];
      }
      return used;
    }

    List<Map<String, Object?>> sidePlates(List<int> used) {
      final order = _descending(loading);
      List<Map<String, Object?>> platesOf(int Function(int index) countOf) => [
        for (var position = order.length - 1; position >= 0; position--)
          if (countOf(order[position]) > 0)
            {
              'mass': loading.plates[order[position]].mass.toJson(),
              'count': countOf(order[position]),
            },
      ];
      if (channel.symmetric || channel.sides == 1)
        return [
          for (var side = 1; side <= channel.sides; side++)
            {'side': side, 'plates': platesOf((i) => used[i])},
        ];
      // Independent two-sided channel: balance the achieved plates per side
      // largest-first. The split is display-only; the total is the arrangement.
      final left = List<int>.filled(used.length, 0);
      final right = List<int>.filled(used.length, 0);
      var leftMass = BigInt.zero, rightMass = BigInt.zero;
      for (var i = 0; i < used.length; i++) {
        for (var n = 0; n < used[i]; n++) {
          if (leftMass <= rightMass) {
            left[i] += 1;
            leftMass += at(loading.plates[i].mass.value);
          } else {
            right[i] += 1;
            rightMass += at(loading.plates[i].mass.value);
          }
        }
      }
      return [
        {'side': 1, 'plates': platesOf((i) => left[i])},
        {'side': 2, 'plates': platesOf((i) => right[i])},
      ];
    }

    Map<String, Object?> arrangement(int k, String relation) {
      final used = reconstruct(k);
      final channelMass = BigInt.from(k) * perStep;
      return {
        'relation': relation,
        'channelMass': mass(channelMass).toJson(),
        'totalMass': mass(channelMass + tareScaled).toJson(),
        'sides': sidePlates(used),
        'remaining': [
          for (var i = 0; i < used.length; i++)
            if (loading.plates[i].count -
                    used[i] * (channel.symmetric ? channel.sides : 1) >
                0)
              {
                'mass': loading.plates[i].mass.toJson(),
                'count':
                    loading.plates[i].count -
                    used[i] * (channel.symmetric ? channel.sides : 1),
              },
        ],
      };
    }

    if (remaining < BigInt.zero) {
      // The included components alone already exceed the target; no plate can
      // be removed from a channel that carries none, so only the tare-only
      // arrangement is offered and honestly labeled.
      return _envelope(loading, target, mass(tareScaled), 'below-components', [
        arrangement(0, 'nearest-higher'),
      ]);
    }
    final floor = remaining ~/ perStep;
    final cap = floor + maxStep ~/ unit;
    if (cap > BigInt.from(1000000))
      invalid('The plate plan search exceeds the 1000000-step limit.');
    final limit = cap.toInt();
    final reachable = List<bool>.filled(limit + 1, false);
    parent = List<int>.filled(limit + 1, -1);
    coin = List<int>.filled(limit + 1, -1);
    reachable[0] = true;
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i].toInt();
      final count = available[i];
      if (step > limit || count == 0) continue;
      final used = List<int>.generate(
        limit + 1,
        (k) => reachable[k] ? 0 : count + 1,
      );
      for (var k = step; k <= limit; k++) {
        if (reachable[k]) {
          used[k] = 0;
        } else if (used[k - step] < count) {
          reachable[k] = true;
          used[k] = used[k - step] + 1;
          parent[k] = k - step;
          coin[k] = i;
        }
      }
    }
    final String status;
    final arrangements = <Map<String, Object?>>[];
    if (remaining % perStep == BigInt.zero &&
        floor <= BigInt.from(limit) &&
        reachable[floor.toInt()]) {
      status = 'exact';
      arrangements.add(arrangement(floor.toInt(), 'exact'));
    } else {
      final belowBound = floor > BigInt.from(limit) ? limit : floor.toInt();
      var belowK = 0;
      for (var k = belowBound; k >= 0; k--)
        if (reachable[k]) {
          belowK = k;
          break;
        }
      var aboveK = -1;
      for (var k = belowBound + 1; k <= limit; k++)
        if (reachable[k]) {
          aboveK = k;
          break;
        }
      if (aboveK < 0) {
        status = 'missing-inventory';
        arrangements.add(arrangement(belowK, 'nearest-lower'));
      } else {
        status = 'nearest';
        arrangements.add(arrangement(belowK, 'nearest-lower'));
        arrangements.add(arrangement(aboveK, 'nearest-higher'));
      }
    }
    return _envelope(loading, target, mass(tareScaled), status, arrangements);
  }

  static Map<String, Object?> _envelope(
    LoadingSpec loading,
    Quantity target,
    Quantity tareMass,
    String status,
    List<Map<String, Object?>> arrangements,
  ) => {
    'policy': policy,
    'target': target.toJson(),
    'channel': loading.channel.toJson(),
    'components': [for (final c in loading.components) c.toJson()],
    'tareMass': tareMass.toJson(),
    'inventory': [for (final plate in loading.plates) plate.toJson()],
    if (loading.channel.sides == 2 && !loading.channel.symmetric)
      'sideAllocation': 'display-only',
    'status': status,
    'arrangements': arrangements,
  };

  /// Denomination indices ordered by descending canonical mass.
  static List<int> _descending(LoadingSpec loading) {
    final order = [for (var i = 0; i < loading.plates.length; i++) i];
    order.sort(
      (a, b) => loading.plates[a].mass.compareTo(loading.plates[b].mass),
    );
    return order;
  }

  /// Every total mass [loading] can make exactly with its declared stock, in
  /// ascending order (the tare alone included). A symmetric channel carries
  /// each plate on every side; an independent channel pools all plates.
  /// Exact decimal arithmetic in units of the plates' common divisor; more
  /// than 100000 distinct steps is a validation error, never a truncation.
  static List<Quantity> loadableTotals(LoadingSpec loading) {
    final channel = loading.channel;
    final tare = loading.tareMass;
    var scale = tare.scale;
    for (final plate in loading.plates)
      if (plate.mass.value.scale > scale) scale = plate.mass.value.scale;
    BigInt at(Decimal value) =>
        value.coefficient * BigInt.from(10).pow(scale - value.scale);
    var unit = BigInt.zero;
    for (final plate in loading.plates) {
      final value = at(plate.mass.value);
      unit = unit == BigInt.zero ? value : _gcd(unit, value);
    }
    final sides = BigInt.from(channel.sides);
    final steps = [
      for (final plate in loading.plates)
        (at(plate.mass.value) ~/ unit).toInt(),
    ];
    final available = [
      for (final plate in loading.plates)
        channel.symmetric ? plate.count ~/ channel.sides : plate.count,
    ];
    var maxSteps = 0;
    for (var i = 0; i < steps.length; i++) maxSteps += steps[i] * available[i];
    if (maxSteps > 100000)
      invalid('The declared loading has more than 100000 loadable steps.');
    final reachable = List<bool>.filled(maxSteps + 1, false)..[0] = true;
    var reach = 0;
    for (var i = 0; i < steps.length; i++) {
      for (var copy = 0; copy < available[i]; copy++) {
        for (var k = reach; k >= 0; k--) {
          if (reachable[k]) reachable[k + steps[i]] = true;
        }
        reach += steps[i];
      }
    }
    final perStep = (channel.symmetric ? sides : BigInt.one) * unit;
    final tareScaled = at(tare);
    return [
      for (var k = 0; k <= maxSteps; k++)
        if (reachable[k])
          Quantity(
            _trimmed(
              _decimalString(tareScaled + BigInt.from(k) * perStep, scale),
            ),
            'kg',
          ),
    ];
  }

  /// '47.50' → '47.5', '20.00' → '20': targets read as they are written.
  static String _trimmed(String decimal) => decimal.contains('.')
      ? decimal
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '')
      : decimal;

  static BigInt _gcd(BigInt a, BigInt b) =>
      b == BigInt.zero ? a : _gcd(b, a % b);

  static String _decimalString(BigInt coefficient, int scale) {
    var digits = coefficient.abs().toString();
    if (scale > 0) {
      digits = digits.padLeft(scale + 1, '0');
      digits =
          '${digits.substring(0, digits.length - scale)}.'
          '${digits.substring(digits.length - scale)}';
    }
    return coefficient.isNegative ? '-$digits' : digits;
  }
}
