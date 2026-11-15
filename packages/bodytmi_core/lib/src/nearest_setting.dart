import 'equipment.dart';
import 'errors.dart';
import 'plate_plan.dart';
import 'quantity.dart';

/// The settings of [instance] that follow [target] as closely as that
/// instance allows: the target itself when available, otherwise the nearest
/// available value below and above it, keeping only the closer one (both on
/// an exact tie). This is how a 40 lb target is followed on a kilogram
/// stack: 17.5 kg, the closest marking to 18.14 kg.
///
/// Settings come from the instance's declared selector scale and/or plate
/// loading, never from assumptions; an instance declaring neither for the
/// target's dimension has no settings and nothing can follow on it.
List<Quantity> nearestSettings(EquipmentInstance instance, Quantity target) {
  final below = <Quantity>[];
  final above = <Quantity>[];
  final scale = instance.scale;
  if (scale != null && scale.unit.dimension == target.dimension) {
    final lower = scale.resolve(target, 'atMost').tick?.quantity;
    final upper = scale.resolve(target, 'atLeast').tick?.quantity;
    if (lower != null) below.add(lower);
    if (upper != null) above.add(upper);
  }
  final loading = instance.loading;
  if (loading != null && target.dimension == Dimension.mass) {
    final plan = PlatePlan.evaluate(loading, target);
    for (final arrangement in plan['arrangements']! as List<Object?>) {
      final a = arrangement! as Map<String, Object?>;
      final total = Quantity.fromJson(a['totalMass']);
      switch (a['relation']) {
        case 'exact':
          below.add(total);
          above.add(total);
        case 'nearest-lower':
          below.add(total);
        case 'nearest-higher':
          above.add(total);
      }
    }
  }
  Quantity? closest(List<Quantity> values, bool lower) {
    Quantity? best;
    for (final v in values) {
      if (best == null ||
          (lower ? v.compareTo(best) > 0 : v.compareTo(best) < 0)) {
        best = v;
      }
    }
    return best;
  }

  final lower = closest(below, true);
  final upper = closest(above, false);
  if (lower == null || upper == null) {
    return [?lower, ?upper];
  }
  final lowerDistance = target.value - lower.value;
  final upperDistance = upper.value - target.value;
  final comparison = lowerDistance.compareTo(upperDistance);
  if (comparison < 0) return [lower];
  if (comparison > 0) return [upper];
  return lower.compareTo(upper) == 0 ? [lower] : [lower, upper];
}

/// Whether [actual] follows [target] on [instance]: equal to the target, or
/// one of its [nearestSettings].
bool followsOn(EquipmentInstance instance, Quantity target, Quantity actual) {
  if (actual.dimension != target.dimension) return false;
  if (actual.compareTo(target) == 0) return true;
  return nearestSettings(
    instance,
    target,
  ).any((setting) => setting.compareTo(actual) == 0);
}

/// Validates that an instance can stand in for a slot's equipment.
void requireSameEquipment(EquipmentInstance instance, String? equipmentId) {
  if (equipmentId == null || instance.equipmentId != equipmentId)
    invalid(
      'Instance ${instance.id} is ${instance.equipmentId}, not the slot '
      'equipment ${equipmentId ?? '(none)'}.',
    );
}
