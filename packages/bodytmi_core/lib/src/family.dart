import 'errors.dart';

/// Optional overlapping exercise groupings; membership implies no load equivalence.
final class ExerciseFamily {
  ExerciseFamily._(this.id, this.name, this.exercises);
  factory ExerciseFamily.fromJson(Object? input) {
    final j = jsonObject(input, 'exercise family');
    checkKeys(j, {'id', 'name', 'exercises'});
    final members = jsonList(j, 'exercises');
    if (members.length > 10000) invalid('Family exceeds 10000 exercise IDs.');
    final ids = <String>{};
    for (final member in members)
      if (!ids.add(identifier({'id': member}, 'id')))
        invalid('Family exercise IDs must be distinct.');
    return ExerciseFamily._(
      identifier(j, 'id'),
      requiredString(j, 'name'),
      List.unmodifiable(ids.toList()..sort()),
    );
  }
  final String id, name;
  final List<String> exercises;
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'exercises': exercises,
  };
}

final class FamilyRevision {
  FamilyRevision._(this.number, this.family);
  factory FamilyRevision.publish(
    ExerciseFamily family, {
    FamilyRevision? previous,
  }) {
    if (previous != null && previous.family.id != family.id)
      invalid('Family revision must retain identity.');
    return FamilyRevision._((previous?.number ?? 0) + 1, family);
  }
  factory FamilyRevision.fromJson(Object? input) {
    final j = jsonObject(input, 'family revision');
    checkKeys(j, {'schemaVersion', 'revision', 'family'});
    final revision = j['revision'];
    if (j['schemaVersion'] != 1 || revision is! int || revision < 1)
      invalid('Invalid family revision.');
    return FamilyRevision._(revision, ExerciseFamily.fromJson(j['family']));
  }
  final int number;
  final ExerciseFamily family;
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'revision': number,
    'family': family.toJson(),
  };
}

void validateFamilyRevisions(List<FamilyRevision> revisions) {
  final numbers = <String, Set<int>>{};
  for (final revision in revisions)
    if (!numbers
        .putIfAbsent(revision.family.id, () => <int>{})
        .add(revision.number))
      invalid('Duplicate family revision.');
  for (final versions in numbers.values)
    if (versions.any((n) => n > versions.length))
      invalid('Family revisions must start at one with no gaps.');
}
