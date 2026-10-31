import 'package:bodytmi_core/bodytmi_core.dart';
import 'training_repository.dart';

final class FamilyService {
  const FamilyService(this.repository);
  final TrainingRepository repository;
  Future<FamilyRevision> revision(String id, [int? number]) async {
    final all =
        (await repository.familyRevisions())
            .where(
              (r) =>
                  r.family.id == id && (number == null || r.number == number),
            )
            .toList()
          ..sort((a, b) => b.number.compareTo(a.number));
    return all.firstOrNull ??
        (throw const BodyTmiException(
          'not_found',
          'Family revision not found.',
        ));
  }

  Future<FamilyRevision> publish(ExerciseFamily family, int expectedRevision) =>
      repository.transaction(() async {
        final all = await repository.familyRevisions();
        validateFamilyRevisions(all);
        final matches = all.where((r) => r.family.id == family.id).toList()
          ..sort((a, b) => b.number.compareTo(a.number));
        final before = matches.firstOrNull;
        if ((before?.number ?? 0) != expectedRevision)
          throw const BodyTmiException('conflict', 'Family revision changed.');
        final next = FamilyRevision.publish(family, previous: before);
        await repository.insertFamilyRevision(next);
        return next;
      });
}
