import 'equipment.dart';
import 'errors.dart';
import 'quantity.dart';

/// The exact plate stack one completed set actually used on one frozen
/// equipment instance revision. Counts are totals across every side of the
/// declared channel. Only the entered plates are stored; channel and total
/// masses are always recomputed exactly from the frozen loading declaration,
/// so no stored arrangement can claim a mass its own plates do not produce.
/// Nothing is ever assumed: an instance without a declared loading has no
/// arrangements, and a symmetric channel must split every used denomination
/// equally so no asymmetric stack is silently relabeled as symmetric.
final class LoadArrangement {
  LoadArrangement({
    required this.instanceId,
    required this.channel,
    required List<PlateUsage> plates,
  }) : plates = List.unmodifiable(_ordered(plates)) {
    identifier({'instanceId': instanceId}, 'instanceId');
    identifier({'channel': channel}, 'channel');
    if (this.plates.isEmpty || this.plates.length > 64)
      invalid('A plate arrangement needs one to 64 plate entries.');
    final seen = <String>{};
    for (final plate in this.plates) {
      if (!seen.add(plate.mass.value.toString()))
        invalid('Plate arrangement denominations must be distinct.');
    }
  }

  factory LoadArrangement.fromJson(Object? input) {
    final j = jsonObject(input, 'load arrangement');
    checkKeys(j, {'instanceId', 'channel', 'plates'});
    return LoadArrangement(
      instanceId: identifier(j, 'instanceId'),
      channel: identifier(j, 'channel'),
      plates: [
        for (final entry in jsonList(j, 'plates')) PlateUsage.fromJson(entry),
      ],
    );
  }

  final String instanceId;
  final String channel;
  final List<PlateUsage> plates;

  Map<String, Object?> toJson() => {
    'instanceId': instanceId,
    'channel': channel,
    'plates': [for (final plate in plates) plate.toJson()],
  };

  /// Validates this stack against the frozen instance revision's declared
  /// loading. Every denomination must be declared stock, the total count per
  /// denomination may not exceed it, and a symmetric multi-sided channel must
  /// split every denomination equally across its sides.
  void validateAgainst(LoadingSpec loading) {
    if (channel != loading.channel.id)
      invalid('Plate arrangement channel does not match the instance.');
    if (loading.channel.sides == 0)
      invalid('A loading channel needs at least one side.');
    final stock = {
      for (final plate in loading.plates) plate.mass.value.toString(): plate,
    };
    for (final usage in plates) {
      final available = stock[usage.mass.value.toString()];
      if (available == null)
        invalid(
          'Plate arrangement uses a denomination outside the declared '
          'inventory: ${usage.mass.value} kg.',
        );
      if (usage.count > available.count)
        invalid(
          'Plate arrangement exceeds the declared count of '
          '${usage.mass.value} kg plates.',
        );
      if (loading.channel.symmetric &&
          loading.channel.sides > 1 &&
          usage.count % loading.channel.sides != 0)
        invalid(
          'A symmetric channel requires each denomination to split '
          'equally across its sides.',
        );
    }
  }

  /// Exact canonical added channel mass of the recorded plates.
  Decimal get channelMass {
    var scale = 0;
    for (final plate in plates)
      if (plate.mass.value.scale > scale) scale = plate.mass.value.scale;
    var total = BigInt.zero;
    for (final plate in plates) {
      total +=
          plate.mass.value.coefficient *
          BigInt.from(10).pow(scale - plate.mass.value.scale) *
          BigInt.from(plate.count);
    }
    return _decimal(total, scale);
  }

  bool isEquivalentTo(LoadArrangement other) {
    if (instanceId != other.instanceId ||
        channel != other.channel ||
        plates.length != other.plates.length)
      return false;
    for (var i = 0; i < plates.length; i++)
      if (plates[i].mass.value != other.plates[i].mass.value ||
          plates[i].count != other.plates[i].count)
        return false;
    return true;
  }

  static List<PlateUsage> _ordered(List<PlateUsage> plates) {
    final sorted = [...plates];
    sorted.sort((a, b) {
      final byMass = b.mass.compareTo(a.mass);
      return byMass != 0
          ? byMass
          : a.mass.enteredUnit.name.compareTo(b.mass.enteredUnit.name);
    });
    return sorted;
  }

  static Decimal _decimal(BigInt coefficient, int scale) {
    var digits = coefficient.abs().toString();
    if (scale > 0) {
      digits = digits.padLeft(scale + 1, '0');
      digits =
          '${digits.substring(0, digits.length - scale)}.'
          '${digits.substring(digits.length - scale)}';
    }
    return Decimal.parse(coefficient.isNegative ? '-$digits' : digits);
  }
}

/// One entered plate denomination and the total number of those plates used
/// across the whole channel. The entered value and unit are preserved.
final class PlateUsage {
  PlateUsage(this.mass, this.count) {
    if (mass.dimension != Dimension.mass)
      invalid('Plate masses must have mass dimension.');
    if (mass.value.compareTo(Decimal.zero) <= 0)
      invalid('Plate masses must be positive.');
    if (count < 1 || count > 10000)
      invalid('Plate counts must be between 1 and 10000.');
  }

  factory PlateUsage.fromJson(Object? input) {
    final j = jsonObject(input, 'plate usage');
    checkKeys(j, {'mass', 'count'});
    final count = j['count'];
    if (count is! int) invalid('Plate counts must be integers.');
    return PlateUsage(Quantity.fromJson(j['mass']), count);
  }

  final Quantity mass;
  final int count;

  Map<String, Object?> toJson() => {'mass': mass.toJson(), 'count': count};
}

/// Deterministic display split of a validated stack across the channel sides.
/// A symmetric channel splits each denomination equally; an independent
/// channel balances the achieved plates largest-first, which is a display
/// assignment, not stored usage.
List<List<PlateUsage>> arrangementSides(
  LoadArrangement arrangement,
  LoadingSpec loading,
) {
  final sides = loading.channel.sides;
  if (loading.channel.symmetric || sides == 1) {
    return [
      for (var side = 1; side <= sides; side++)
        [
          for (final plate in arrangement.plates)
            if (plate.count ~/ sides > 0)
              PlateUsage(plate.mass, plate.count ~/ sides),
        ],
    ];
  }
  final left = <PlateUsage>[];
  final right = <PlateUsage>[];
  var leftMass = Decimal.zero, rightMass = Decimal.zero;
  for (final plate in arrangement.plates) {
    for (var used = 0; used < plate.count; used++) {
      if (leftMass.compareTo(rightMass) <= 0) {
        _append(left, plate);
        leftMass += plate.mass.value;
      } else {
        _append(right, plate);
        rightMass += plate.mass.value;
      }
    }
  }
  return [left, right];
}

void _append(List<PlateUsage> side, PlateUsage plate) {
  for (var i = 0; i < side.length; i++)
    if (side[i].mass.value == plate.mass.value) {
      side[i] = PlateUsage(plate.mass, side[i].count + 1);
      return;
    }
  side.add(PlateUsage(plate.mass, 1));
}
