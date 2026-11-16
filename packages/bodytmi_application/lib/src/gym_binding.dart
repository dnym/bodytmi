import 'package:bodytmi_core/bodytmi_core.dart';

/// The frozen reference to [instance], carrying its equipment definition's
/// latest interchangeability declaration from [equipment].
LoadInstanceReference instanceReference(
  EquipmentInstanceRevision instance,
  List<EquipmentRevision> equipment,
) {
  EquipmentRevision? definition;
  for (final revision in equipment) {
    if (revision.equipment.id == instance.instance.equipmentId &&
        (definition == null || revision.number > definition.number))
      definition = revision;
  }
  return LoadInstanceReference(
    instance.instance.id,
    instance.instance,
    instance.number,
    interchangeable: definition?.equipment.interchangeable ?? false,
  );
}

/// Latest revision of every published equipment instance.
Map<String, EquipmentInstanceRevision> latestInstances(
  List<EquipmentInstanceRevision> revisions,
) {
  final latest = <String, EquipmentInstanceRevision>{};
  for (final revision in revisions) {
    final prior = latest[revision.instance.id];
    if (prior == null || revision.number > prior.number)
      latest[revision.instance.id] = revision;
  }
  return latest;
}

/// How one slot's declared equipment binds at a gym.
final class GymSlotBinding {
  GymSlotBinding(
    this.slotId,
    this.equipmentId,
    this.status, {
    this.instanceId,
    this.candidates = const [],
  });
  final String slotId;
  final String? equipmentId;

  /// `explicit` (a requested binding), `bound` (the gym's only instance),
  /// `preferred` (the gym's declared choice among several),
  /// `unbound` (explicitly done without a binding), `missing` (the gym has
  /// none), `ambiguous` (the gym has several), or `none` (the slot declares
  /// no equipment).
  final String status;
  final String? instanceId;
  final List<String> candidates;
  bool get ready => status != 'missing' && status != 'ambiguous';
  Map<String, Object?> toJson() => {
    'slotId': slotId,
    if (equipmentId != null) 'equipmentId': equipmentId,
    'status': status,
    if (instanceId != null) 'instanceId': instanceId,
    if (candidates.isNotEmpty) 'candidates': candidates,
  };
}

/// Read-only plan of how a gym's inventory binds a workout's slot
/// equipment. Nothing is chosen for an ambiguous slot and nothing is invented
/// for a missing one: both make the plan not ready, and the person resolves
/// them with explicit bindings, `unboundSlots`, a temporary substitution
/// after start, or a skip.
final class GymBindingPlan {
  GymBindingPlan(this.gymId, this.slots);

  factory GymBindingPlan.plan({
    required WorkoutDefinition definition,
    required String gymId,
    required List<EquipmentInstanceRevision> instances,
    Map<String, String> preferred = const {},
    Map<String, String> explicit = const {},
    Set<String> unbound = const {},
  }) {
    final slotIds = {for (final slot in definition.slots) slot.id};
    for (final id in {...explicit.keys, ...unbound}) {
      if (!slotIds.contains(id)) invalid('Gym binding names unknown slot $id.');
    }
    for (final id in unbound) {
      if (explicit.containsKey(id))
        invalid('Slot $id cannot be both bound and unbound.');
      if (definition.slot(id).equipmentId == null)
        invalid('Slot $id declares no equipment to leave unbound.');
    }
    final latest = latestInstances(instances).values;
    return GymBindingPlan(gymId, [
      for (final slot in definition.slots)
        if (explicit[slot.id] case final instanceId?)
          GymSlotBinding(
            slot.id,
            slot.equipmentId,
            'explicit',
            instanceId: instanceId,
          )
        else if (slot.equipmentId == null)
          GymSlotBinding(slot.id, null, 'none')
        else if (unbound.contains(slot.id))
          GymSlotBinding(slot.id, slot.equipmentId, 'unbound')
        else
          (() {
            final candidates = [
              for (final r in latest)
                if (r.instance.gymId == gymId &&
                    r.instance.equipmentId == slot.equipmentId)
                  r.instance.id,
            ]..sort();
            return switch (candidates.length) {
              0 => GymSlotBinding(slot.id, slot.equipmentId, 'missing'),
              1 => GymSlotBinding(
                slot.id,
                slot.equipmentId,
                'bound',
                instanceId: candidates.single,
              ),
              _ when candidates.contains(preferred[slot.equipmentId]) =>
                GymSlotBinding(
                  slot.id,
                  slot.equipmentId,
                  'preferred',
                  instanceId: preferred[slot.equipmentId],
                  candidates: candidates,
                ),
              _ => GymSlotBinding(
                slot.id,
                slot.equipmentId,
                'ambiguous',
                candidates: candidates,
              ),
            };
          })(),
    ]);
  }

  final String gymId;
  final List<GymSlotBinding> slots;
  bool get ready => slots.every((s) => s.ready);

  /// Slot → instance bindings the start uses (explicit and automatic).
  Map<String, String> get bindings => {
    for (final slot in slots)
      if (slot.instanceId != null) slot.slotId: slot.instanceId!,
  };

  /// The conflict a start reports when the plan is not ready.
  Never refuse() => throw BodyTmiException(
    'conflict',
    'Gym $gymId cannot bind every slot: '
        '${[for (final s in slots)
          if (!s.ready) '${s.slotId} (${s.status})'].join(', ')}. '
        'See store gym-check; pass loadBindings, or unboundSlots to train '
        'without a binding.',
  );

  Map<String, Object?> toJson() => {
    'policy': 'bodytmi-gym-binding/1',
    'gym': gymId,
    'ready': ready,
    'slots': [for (final slot in slots) slot.toJson()],
  };
}
