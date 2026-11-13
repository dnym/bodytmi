import 'errors.dart';
import 'numeric_scale.dart';

/// One catalog equipment kind. Entries are descriptive only: they prescribe
/// nothing, and a published identity never implies bar mass, plate loading,
/// channels or any other loading topology.
final class EquipmentDefinition {
  EquipmentDefinition._(this.id, this.name, this.notes);
  factory EquipmentDefinition.fromJson(Object? input) {
    final j = jsonObject(input, 'equipment definition');
    checkKeys(j, {'id', 'name', 'notes'});
    final name = j['name'];
    if (name != null &&
        (name is! String || name.trim().isEmpty || name.length > 200)) {
      invalid(
        'Equipment name must be a nonempty string of at most 200 characters.',
      );
    }
    final notes = j['notes'];
    if (notes != null &&
        (notes is! String || notes.trim().isEmpty || notes.length > 4000)) {
      invalid(
        'Equipment notes must be a nonempty string of at most 4000 characters.',
      );
    }
    return EquipmentDefinition._(
      identifier(j, 'id'),
      name as String?,
      notes as String?,
    );
  }
  final String id;
  final String? name, notes;
  Map<String, Object?> toJson() => {
    'id': id,
    if (name != null) 'name': name,
    if (notes != null) 'notes': notes,
  };
}

/// One user-defined location such as Home or a gym. Gyms carry no prescription
/// semantics; membership of an instance is expressed by that instance.
final class GymDefinition {
  GymDefinition._(this.id, this.name, this.notes);
  factory GymDefinition.fromJson(Object? input) {
    final j = jsonObject(input, 'gym definition');
    checkKeys(j, {'id', 'name', 'notes'});
    final name = j['name'];
    if (name != null &&
        (name is! String || name.trim().isEmpty || name.length > 200)) {
      invalid('Gym name must be a nonempty string of at most 200 characters.');
    }
    final notes = j['notes'];
    if (notes != null &&
        (notes is! String || notes.trim().isEmpty || notes.length > 4000)) {
      invalid(
        'Gym notes must be a nonempty string of at most 4000 characters.',
      );
    }
    return GymDefinition._(
      identifier(j, 'id'),
      name as String?,
      notes as String?,
    );
  }
  final String id;
  final String? name, notes;
  Map<String, Object?> toJson() => {
    'id': id,
    if (name != null) 'name': name,
    if (notes != null) 'notes': notes,
  };
}

/// One actual physical piece of equipment. A declared scale holds native
/// markings with alternate same-dimension labels, not independent loads.
final class EquipmentInstance {
  EquipmentInstance._(
    this.id,
    this.equipmentId,
    this.gymId,
    this.name,
    this.notes,
    this.scale,
  );
  factory EquipmentInstance.fromJson(Object? input) {
    final j = jsonObject(input, 'equipment instance');
    checkKeys(j, {'id', 'equipmentId', 'gym', 'name', 'notes', 'scale'});
    final name = j['name'];
    if (name != null &&
        (name is! String || name.trim().isEmpty || name.length > 200)) {
      invalid(
        'Instance name must be a nonempty string of at most 200 characters.',
      );
    }
    final notes = j['notes'];
    if (notes != null &&
        (notes is! String || notes.trim().isEmpty || notes.length > 4000)) {
      invalid(
        'Instance notes must be a nonempty string of at most 4000 characters.',
      );
    }
    return EquipmentInstance._(
      identifier(j, 'id'),
      identifier(j, 'equipmentId'),
      j['gym'] == null ? null : identifier(j, 'gym'),
      name as String?,
      notes as String?,
      j['scale'] == null ? null : NumericScale.fromJson(j['scale']),
    );
  }
  final String id, equipmentId;
  final String? gymId, name, notes;
  final NumericScale? scale;
  Map<String, Object?> toJson() => {
    'id': id,
    'equipmentId': equipmentId,
    if (gymId != null) 'gym': gymId,
    if (name != null) 'name': name,
    if (notes != null) 'notes': notes,
    if (scale != null) 'scale': scale!.toJson(),
  };
}

final class EquipmentRevision {
  EquipmentRevision._(this.number, this.equipment);
  factory EquipmentRevision.publish(
    EquipmentDefinition equipment, {
    EquipmentRevision? previous,
  }) {
    if (previous != null && previous.equipment.id != equipment.id)
      invalid('Equipment revision must retain identity.');
    return EquipmentRevision._((previous?.number ?? 0) + 1, equipment);
  }
  factory EquipmentRevision.fromJson(Object? input) {
    final j = jsonObject(input, 'equipment revision');
    checkKeys(j, {'schemaVersion', 'revision', 'equipment'});
    final revision = j['revision'];
    if (j['schemaVersion'] != 1 || revision is! int || revision < 1)
      invalid('Invalid equipment revision.');
    return EquipmentRevision._(
      revision,
      EquipmentDefinition.fromJson(j['equipment']),
    );
  }
  final int number;
  final EquipmentDefinition equipment;
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'revision': number,
    'equipment': equipment.toJson(),
  };
}

final class GymRevision {
  GymRevision._(this.number, this.gym);
  factory GymRevision.publish(GymDefinition gym, {GymRevision? previous}) {
    if (previous != null && previous.gym.id != gym.id)
      invalid('Gym revision must retain identity.');
    return GymRevision._((previous?.number ?? 0) + 1, gym);
  }
  factory GymRevision.fromJson(Object? input) {
    final j = jsonObject(input, 'gym revision');
    checkKeys(j, {'schemaVersion', 'revision', 'gym'});
    final revision = j['revision'];
    if (j['schemaVersion'] != 1 || revision is! int || revision < 1)
      invalid('Invalid gym revision.');
    return GymRevision._(revision, GymDefinition.fromJson(j['gym']));
  }
  final int number;
  final GymDefinition gym;
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'revision': number,
    'gym': gym.toJson(),
  };
}

final class EquipmentInstanceRevision {
  EquipmentInstanceRevision._(this.number, this.instance);
  factory EquipmentInstanceRevision.publish(
    EquipmentInstance instance, {
    EquipmentInstanceRevision? previous,
  }) {
    if (previous != null &&
        (previous.instance.id != instance.id ||
            previous.instance.equipmentId != instance.equipmentId))
      invalid('Instance revision must retain its identity and equipment.');
    return EquipmentInstanceRevision._((previous?.number ?? 0) + 1, instance);
  }
  factory EquipmentInstanceRevision.fromJson(Object? input) {
    final j = jsonObject(input, 'equipment instance revision');
    checkKeys(j, {'schemaVersion', 'revision', 'instance'});
    final revision = j['revision'];
    if (j['schemaVersion'] != 1 || revision is! int || revision < 1)
      invalid('Invalid equipment instance revision.');
    return EquipmentInstanceRevision._(
      revision,
      EquipmentInstance.fromJson(j['instance']),
    );
  }
  final int number;
  final EquipmentInstance instance;
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'revision': number,
    'instance': instance.toJson(),
  };
}

void validateEquipmentRevisions(List<EquipmentRevision> revisions) {
  final numbers = <String, Set<int>>{};
  for (final revision in revisions)
    if (!numbers
        .putIfAbsent(revision.equipment.id, () => <int>{})
        .add(revision.number))
      invalid('Duplicate equipment revision.');
  for (final versions in numbers.values)
    if (versions.any((n) => n > versions.length))
      invalid('Equipment revisions must start at one with no gaps.');
}

void validateGymRevisions(List<GymRevision> revisions) {
  final numbers = <String, Set<int>>{};
  for (final revision in revisions)
    if (!numbers
        .putIfAbsent(revision.gym.id, () => <int>{})
        .add(revision.number))
      invalid('Duplicate gym revision.');
  for (final versions in numbers.values)
    if (versions.any((n) => n > versions.length))
      invalid('Gym revisions must start at one with no gaps.');
}

/// Instance revisions are contiguous per identity, never change their equipment
/// kind, and reference equipment and gym identities present in the same record
/// set. A gym change is a new revision, not an edit of history.
void validateEquipmentInstanceRevisions(
  List<EquipmentInstanceRevision> revisions,
  List<EquipmentRevision> equipment,
  List<GymRevision> gyms,
) {
  final numbers = <String, Set<int>>{};
  final equipmentIds = <String>{
    for (final revision in equipment) revision.equipment.id,
  };
  final gymIds = <String>{for (final revision in gyms) revision.gym.id};
  final seen = <String, String>{};
  for (final revision in revisions) {
    if (!numbers
        .putIfAbsent(revision.instance.id, () => <int>{})
        .add(revision.number))
      invalid('Duplicate instance revision.');
    final owner = seen.putIfAbsent(
      revision.instance.id,
      () => revision.instance.equipmentId,
    );
    if (owner != revision.instance.equipmentId)
      invalid('Instance revisions cannot change equipment.');
    if (!equipmentIds.contains(revision.instance.equipmentId))
      invalid('Instance references equipment that is not published.');
    if (revision.instance.gymId != null &&
        !gymIds.contains(revision.instance.gymId))
      invalid('Instance references a gym that is not published.');
  }
  for (final versions in numbers.values)
    if (versions.any((n) => n > versions.length))
      invalid('Instance revisions must start at one with no gaps.');
}
