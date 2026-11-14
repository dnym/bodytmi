import 'package:bodytmi_core/bodytmi_core.dart';
import 'training_repository.dart';

/// Named progression-rule preset authoring. Publishing is per-id
/// compare-and-set; consumption resolves one explicit revision.
final class PresetService {
  const PresetService(this.repository);
  final TrainingRepository repository;

  Future<ProgressionPresetRevision> revision(String id, [int? number]) async {
    final all =
        (await repository.progressionPresetRevisions())
            .where(
              (r) =>
                  r.preset.id == id && (number == null || r.number == number),
            )
            .toList()
          ..sort((a, b) => b.number.compareTo(a.number));
    return all.firstOrNull ??
        (throw const BodyTmiException(
          'not_found',
          'Progression preset revision not found.',
        ));
  }

  Future<ProgressionPresetRevision> publish(
    ProgressionPreset preset,
    int expectedRevision,
  ) => repository.transaction(() async {
    final all = await repository.progressionPresetRevisions();
    validateProgressionPresetRevisions(all);
    final matches = all.where((r) => r.preset.id == preset.id).toList()
      ..sort((a, b) => b.number.compareTo(a.number));
    final before = matches.firstOrNull;
    if ((before?.number ?? 0) != expectedRevision)
      throw const BodyTmiException(
        'conflict',
        'Progression preset revision changed.',
      );
    final next = ProgressionPresetRevision.publish(preset, previous: before);
    await repository.insertProgressionPresetRevision(next);
    return next;
  });
}
