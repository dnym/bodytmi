import 'package:bodytmi_core/bodytmi_core.dart';
import 'training_repository.dart';

/// Authoring for equipment kinds, gyms and their actual instances. Inventory
/// entries are descriptive only; they decide nothing and change no
/// prescription, progression or record.
final class EquipmentService {
  const EquipmentService(this.repository);
  final TrainingRepository repository;

  Future<EquipmentRevision> equipmentRevision(String id, [int? number]) async {
    final all =
        (await repository.equipmentRevisions())
            .where(
              (r) =>
                  r.equipment.id == id &&
                  (number == null || r.number == number),
            )
            .toList()
          ..sort((a, b) => b.number.compareTo(a.number));
    return all.firstOrNull ??
        (throw const BodyTmiException(
          'not_found',
          'Equipment revision not found.',
        ));
  }

  Future<GymRevision> gymRevision(String id, [int? number]) async {
    final all =
        (await repository.gymRevisions())
            .where(
              (r) => r.gym.id == id && (number == null || r.number == number),
            )
            .toList()
          ..sort((a, b) => b.number.compareTo(a.number));
    return all.firstOrNull ??
        (throw const BodyTmiException('not_found', 'Gym revision not found.'));
  }

  Future<EquipmentInstanceRevision> instanceRevision(
    String id, [
    int? number,
  ]) async {
    final all =
        (await repository.equipmentInstanceRevisions())
            .where(
              (r) =>
                  r.instance.id == id && (number == null || r.number == number),
            )
            .toList()
          ..sort((a, b) => b.number.compareTo(a.number));
    return all.firstOrNull ??
        (throw const BodyTmiException(
          'not_found',
          'Equipment instance revision not found.',
        ));
  }

  Future<EquipmentRevision> publishEquipment(
    EquipmentDefinition equipment,
    int expectedRevision,
  ) => repository.transaction(() async {
    final all = await repository.equipmentRevisions();
    validateEquipmentRevisions(all);
    final matches = all.where((r) => r.equipment.id == equipment.id).toList()
      ..sort((a, b) => b.number.compareTo(a.number));
    final before = matches.firstOrNull;
    if ((before?.number ?? 0) != expectedRevision)
      throw const BodyTmiException('conflict', 'Equipment revision changed.');
    final next = EquipmentRevision.publish(equipment, previous: before);
    await repository.insertEquipmentRevision(next);
    return next;
  });

  Future<GymRevision> publishGym(GymDefinition gym, int expectedRevision) =>
      repository.transaction(() async {
        final all = await repository.gymRevisions();
        validateGymRevisions(all);
        final matches = all.where((r) => r.gym.id == gym.id).toList()
          ..sort((a, b) => b.number.compareTo(a.number));
        final before = matches.firstOrNull;
        if ((before?.number ?? 0) != expectedRevision)
          throw const BodyTmiException('conflict', 'Gym revision changed.');
        final next = GymRevision.publish(gym, previous: before);
        await repository.insertGymRevision(next);
        return next;
      });

  /// Publishing an instance freezes its equipment kind; a gym move or a scale
  /// change is a new numbered revision, never an edit of published history.
  Future<EquipmentInstanceRevision> publishInstance(
    EquipmentInstance instance,
    int expectedRevision,
  ) => repository.transaction(() async {
    final equipment = await repository.equipmentRevisions();
    validateEquipmentRevisions(equipment);
    if (!equipment.any((r) => r.equipment.id == instance.equipmentId))
      throw const BodyTmiException(
        'not_found',
        'Instance references equipment that is not published.',
      );
    final gyms = await repository.gymRevisions();
    validateGymRevisions(gyms);
    if (instance.gymId != null && !gyms.any((r) => r.gym.id == instance.gymId))
      throw const BodyTmiException(
        'not_found',
        'Instance references a gym that is not published.',
      );
    final all = await repository.equipmentInstanceRevisions();
    validateEquipmentInstanceRevisions(all, equipment, gyms);
    final matches = all.where((r) => r.instance.id == instance.id).toList()
      ..sort((a, b) => b.number.compareTo(a.number));
    final before = matches.firstOrNull;
    if ((before?.number ?? 0) != expectedRevision)
      throw const BodyTmiException('conflict', 'Instance revision changed.');
    final next = EquipmentInstanceRevision.publish(instance, previous: before);
    await repository.insertEquipmentInstanceRevision(next);
    return next;
  });

  /// Current inventory view: the latest revision of every instance, optionally
  /// restricted to one gym. The latest revision is the effective placement.
  Future<List<EquipmentInstanceRevision>> inventory({String? gymId}) =>
      repository.transaction(() async {
        final equipment = await repository.equipmentRevisions();
        final gyms = await repository.gymRevisions();
        final all = await repository.equipmentInstanceRevisions();
        validateEquipmentInstanceRevisions(all, equipment, gyms);
        final latest = <String, EquipmentInstanceRevision>{};
        for (final revision in all) {
          final current = latest[revision.instance.id];
          if (current == null || revision.number > current.number)
            latest[revision.instance.id] = revision;
        }
        return [
          for (final revision in latest.values)
            if (gymId == null || revision.instance.gymId == gymId) revision,
        ]..sort((a, b) => a.instance.id.compareTo(b.instance.id));
      });

  /// Read-only feasible plate helper against one actual instance's declared
  /// loading configuration (latest revision by default). Instances without a
  /// declared configuration have no plate arithmetic: no bar mass, collar or
  /// symmetric-side convention is ever assumed for them.
  Future<Map<String, Object?>> platePlan(
    String instanceId,
    Quantity target, [
    int? revision,
  ]) => repository.transaction(() async {
    final selected = await instanceRevision(instanceId, revision);
    final loading = selected.instance.loading;
    if (loading == null)
      throw const BodyTmiException(
        'not_found',
        'Equipment instance declares no loading configuration.',
      );
    return {
      'instanceId': selected.instance.id,
      'instanceRevision': selected.number,
      'plan': PlatePlan.evaluate(loading, target),
    };
  });

  /// Read-only entry-convention resolution: an explicit request convention
  /// wins over a slot composition override, which wins over the equipment
  /// instance default. Capability is validated against the pinned instance
  /// revision's declared loading configuration, and an optional interpretation
  /// is exact and descriptive. Nothing is written; entered values are never
  /// rewritten and no workload totals are computed.
  Future<Map<String, Object?>> loadConvention({
    required String instanceId,
    int? revision,
    String? templateId,
    int? templateRevision,
    String? slotId,
    LoadConvention? explicit,
    Quantity? mass,
    Quantity? repetitions,
  }) => repository.transaction(() async {
    if ((templateId == null) != (slotId == null))
      throw const BodyTmiException(
        'validation',
        'Slot resolution needs both templateId and slotId.',
      );
    final selected = await instanceRevision(instanceId, revision);
    ExerciseSlot? slot;
    int? resolvedTemplateRevision;
    if (templateId != null) {
      final templateRev = await repository.revision(
        templateId,
        templateRevision,
      );
      if (templateRev == null)
        throw const BodyTmiException(
          'not_found',
          'Workout revision not found.',
        );
      final matches = templateRev.definition.slots.where(
        (candidate) => candidate.id == slotId,
      );
      if (matches.isEmpty)
        throw const BodyTmiException('not_found', 'Slot not found.');
      slot = matches.single;
      resolvedTemplateRevision = templateRev.number;
    }
    final String source;
    final LoadConvention convention;
    if (explicit != null) {
      source = 'explicit';
      convention = explicit;
    } else if (slot?.convention != null) {
      source = 'slot';
      convention = slot!.convention!;
    } else if (selected.instance.convention != null) {
      source = 'instance';
      convention = selected.instance.convention!;
    } else {
      throw const BodyTmiException(
        'not_found',
        'No load entry convention is declared for this slot or instance.',
      );
    }
    requireLoadConventionCapability(convention, selected.instance.loading);
    final loading = selected.instance.loading;
    return {
      'policy': 'bodytmi-load-convention/1',
      'resolution': {
        'source': source,
        'instanceId': selected.instance.id,
        'instanceRevision': selected.number,
        if (templateId != null) 'templateId': templateId,
        if (templateId != null) 'templateRevision': resolvedTemplateRevision,
        if (slotId != null) 'slotId': slotId,
      },
      'convention': convention.toJson(),
      'capability': {
        'declaredLoading': loading != null,
        if (loading != null) 'channelSides': loading.channel.sides,
        if (loading != null) 'channelSymmetry': loading.channel.symmetry,
      },
      'interpretation': mass == null
          ? null
          : LoadInterpretation.interpret(
              convention,
              mass,
              repetitions: repetitions,
              loading: loading,
            ),
    };
  });
}
