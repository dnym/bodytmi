import 'errors.dart';
import 'workout.dart';

/// One independent catalog exercise. Catalog entries carry no prescription,
/// progression or timing semantics, and nothing in the application keys
/// behaviour off an exercise name.
final class ExerciseDefinition {
  ExerciseDefinition._(this.id, this.name, this.notes);
  factory ExerciseDefinition.fromJson(Object? input) {
    final j = jsonObject(input, 'exercise definition');
    checkKeys(j, {'id', 'name', 'notes'});
    final name = j['name'];
    if (name != null &&
        (name is! String || name.trim().isEmpty || name.length > 200)) {
      invalid(
        'Exercise name must be a nonempty string of at most 200 characters.',
      );
    }
    final notes = j['notes'];
    if (notes != null &&
        (notes is! String || notes.trim().isEmpty || notes.length > 4000)) {
      invalid(
        'Exercise notes must be a nonempty string of at most 4000 characters.',
      );
    }
    return ExerciseDefinition._(
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

/// One authored variant of an existing exercise, such as the three cable,
/// barbell and dumbbell rows of one row exercise. Implementations are not
/// automatically comparable loads or records; they only group authored intent.
final class ExerciseImplementation {
  ExerciseImplementation._(this.id, this.exerciseId, this.name, this.notes);
  factory ExerciseImplementation.fromJson(Object? input) {
    final j = jsonObject(input, 'exercise implementation');
    checkKeys(j, {'id', 'exerciseId', 'name', 'notes'});
    final name = j['name'];
    if (name != null &&
        (name is! String || name.trim().isEmpty || name.length > 200)) {
      invalid(
        'Implementation name must be a nonempty string of at most 200 characters.',
      );
    }
    final notes = j['notes'];
    if (notes != null &&
        (notes is! String || notes.trim().isEmpty || notes.length > 4000)) {
      invalid(
        'Implementation notes must be a nonempty string of at most 4000 characters.',
      );
    }
    return ExerciseImplementation._(
      identifier(j, 'id'),
      identifier(j, 'exerciseId'),
      name as String?,
      notes as String?,
    );
  }
  final String id, exerciseId;
  final String? name, notes;
  Map<String, Object?> toJson() => {
    'id': id,
    'exerciseId': exerciseId,
    if (name != null) 'name': name,
    if (notes != null) 'notes': notes,
  };
}

final class ExerciseRevision {
  ExerciseRevision._(this.number, this.exercise);
  factory ExerciseRevision.publish(
    ExerciseDefinition exercise, {
    ExerciseRevision? previous,
  }) {
    if (previous != null && previous.exercise.id != exercise.id)
      invalid('Exercise revision must retain identity.');
    return ExerciseRevision._((previous?.number ?? 0) + 1, exercise);
  }
  factory ExerciseRevision.fromJson(Object? input) {
    final j = jsonObject(input, 'exercise revision');
    checkKeys(j, {'schemaVersion', 'revision', 'exercise'});
    final revision = j['revision'];
    if (j['schemaVersion'] != 1 || revision is! int || revision < 1)
      invalid('Invalid exercise revision.');
    return ExerciseRevision._(
      revision,
      ExerciseDefinition.fromJson(j['exercise']),
    );
  }
  final int number;
  final ExerciseDefinition exercise;
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'revision': number,
    'exercise': exercise.toJson(),
  };
}

final class ImplementationRevision {
  ImplementationRevision._(this.number, this.implementation);
  factory ImplementationRevision.publish(
    ExerciseImplementation implementation, {
    ImplementationRevision? previous,
  }) {
    if (previous != null &&
        (previous.implementation.id != implementation.id ||
            previous.implementation.exerciseId != implementation.exerciseId))
      invalid('Implementation revision must retain its identity and exercise.');
    return ImplementationRevision._(
      (previous?.number ?? 0) + 1,
      implementation,
    );
  }
  factory ImplementationRevision.fromJson(Object? input) {
    final j = jsonObject(input, 'implementation revision');
    checkKeys(j, {'schemaVersion', 'revision', 'implementation'});
    final revision = j['revision'];
    if (j['schemaVersion'] != 1 || revision is! int || revision < 1)
      invalid('Invalid implementation revision.');
    return ImplementationRevision._(
      revision,
      ExerciseImplementation.fromJson(j['implementation']),
    );
  }
  final int number;
  final ExerciseImplementation implementation;
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'revision': number,
    'implementation': implementation.toJson(),
  };
}

void validateExerciseRevisions(List<ExerciseRevision> revisions) {
  final numbers = <String, Set<int>>{};
  for (final revision in revisions)
    if (!numbers
        .putIfAbsent(revision.exercise.id, () => <int>{})
        .add(revision.number))
      invalid('Duplicate exercise revision.');
  for (final versions in numbers.values)
    if (versions.any((n) => n > versions.length))
      invalid('Exercise revisions must start at one with no gaps.');
}

/// Catalog revisions must be contiguous per identity, and every implementation
/// must reference an exercise that is present in the same record set.
void validateImplementationRevisions(
  List<ImplementationRevision> revisions,
  List<ExerciseRevision> exercises,
) {
  final numbers = <String, Set<int>>{};
  final exerciseIds = <String>{
    for (final exercise in exercises) exercise.exercise.id,
  };
  final seen = <String, String>{};
  for (final revision in revisions) {
    if (!numbers
        .putIfAbsent(revision.implementation.id, () => <int>{})
        .add(revision.number))
      invalid('Duplicate implementation revision.');
    final owner = seen.putIfAbsent(
      revision.implementation.id,
      () => revision.implementation.exerciseId,
    );
    if (owner != revision.implementation.exerciseId)
      invalid('Implementation revisions cannot change exercise.');
    if (!exerciseIds.contains(revision.implementation.exerciseId))
      invalid('Implementation references a missing exercise.');
  }
  for (final versions in numbers.values)
    if (versions.any((n) => n > versions.length))
      invalid('Implementation revisions must start at one with no gaps.');
}

/// Owners of every published implementation identity, one exercise each.
Map<String, String> implementationOwners(
  List<ImplementationRevision> revisions,
) => {
  for (final revision in revisions)
    revision.implementation.id: revision.implementation.exerciseId,
};

/// When a slot's implementation identifier matches a published implementation,
/// that implementation must belong to the slot's exercise. Catalog adoption is
/// checked within one record set; unmatched identifiers stay legacy authoring
/// shorthand and no behaviour is ever inferred from an exercise name.
void validateCatalogSlotAdoption(
  Iterable<ExerciseSlot> slots,
  Map<String, String> owners,
) {
  for (final slot in slots) {
    final owner = owners[slot.implementation];
    if (owner != null && owner != slot.exerciseId)
      invalid(
        'Slot implementation ${slot.implementation} belongs to exercise '
        '$owner, not ${slot.exerciseId}.',
      );
  }
}
