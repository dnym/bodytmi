import 'package:bodytmi_core/bodytmi_core.dart';
import 'training_repository.dart';

/// Authoring for the shared exercise/implementation catalog. Catalog entries
/// are descriptive only; they decide nothing and change no prescription.
final class CatalogService {
  const CatalogService(this.repository);
  final TrainingRepository repository;

  Future<ExerciseRevision> exerciseRevision(String id, [int? number]) async {
    final all =
        (await repository.exerciseRevisions())
            .where(
              (r) =>
                  r.exercise.id == id && (number == null || r.number == number),
            )
            .toList()
          ..sort((a, b) => b.number.compareTo(a.number));
    return all.firstOrNull ??
        (throw const BodyTmiException(
          'not_found',
          'Exercise revision not found.',
        ));
  }

  Future<ImplementationRevision> implementationRevision(
    String id, [
    int? number,
  ]) async {
    final all =
        (await repository.implementationRevisions())
            .where(
              (r) =>
                  r.implementation.id == id &&
                  (number == null || r.number == number),
            )
            .toList()
          ..sort((a, b) => b.number.compareTo(a.number));
    return all.firstOrNull ??
        (throw const BodyTmiException(
          'not_found',
          'Implementation revision not found.',
        ));
  }

  Future<ExerciseRevision> publishExercise(
    ExerciseDefinition exercise,
    int expectedRevision,
  ) => repository.transaction(() async {
    final all = await repository.exerciseRevisions();
    validateExerciseRevisions(all);
    final matches = all.where((r) => r.exercise.id == exercise.id).toList()
      ..sort((a, b) => b.number.compareTo(a.number));
    final before = matches.firstOrNull;
    if ((before?.number ?? 0) != expectedRevision)
      throw const BodyTmiException('conflict', 'Exercise revision changed.');
    final next = ExerciseRevision.publish(exercise, previous: before);
    await repository.insertExerciseRevision(next);
    return next;
  });

  Future<ImplementationRevision> publishImplementation(
    ExerciseImplementation implementation,
    int expectedRevision,
  ) => repository.transaction(() async {
    final exercises = await repository.exerciseRevisions();
    validateExerciseRevisions(exercises);
    if (!exercises.any((r) => r.exercise.id == implementation.exerciseId))
      throw const BodyTmiException(
        'not_found',
        'Implementation references an exercise that is not published.',
      );
    final all = await repository.implementationRevisions();
    validateImplementationRevisions(all, exercises);
    final matches =
        all.where((r) => r.implementation.id == implementation.id).toList()
          ..sort((a, b) => b.number.compareTo(a.number));
    final before = matches.firstOrNull;
    if ((before?.number ?? 0) != expectedRevision)
      throw const BodyTmiException(
        'conflict',
        'Implementation revision changed.',
      );
    final next = ImplementationRevision.publish(
      implementation,
      previous: before,
    );
    await repository.insertImplementationRevision(next);
    return next;
  });
}
