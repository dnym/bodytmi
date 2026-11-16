import 'package:bodytmi_core/bodytmi_core.dart';
import 'canonical_json.dart';
import 'family_service.dart';
import 'preset_service.dart';
import 'program_service.dart';
import 'training_repository.dart';

/// Every revision a blueprint instance receipt names must be published.
void validateBlueprintLineage(
  List<BlueprintInstance> instances, {
  required List<WorkoutRevision> workouts,
  required List<ProgramRevision> programs,
  required List<ProgressionPresetRevision> presets,
}) {
  final w = {for (final r in workouts) '${r.definition.id}/${r.number}'};
  final p = {for (final r in programs) '${r.definition.id}/${r.number}'};
  final s = {for (final r in presets) '${r.preset.id}/${r.number}'};
  for (final i in instances) {
    if (i.workouts.entries.any(
          (e) => !w.contains('${i.workoutId(e.key)}/${e.value}'),
        ) ||
        (i.programRevision != null &&
            !p.contains('${i.id}/${i.programRevision}')) ||
        i.presets.entries.any(
          (e) => !s.contains('${i.presetId(e.key)}/${e.value}'),
        ))
      invalid('Blueprint instance ${i.id} names an unpublished revision.');
  }
}

/// The documents a filled-in blueprint publishes, parsed by the ordinary
/// validators.
typedef FilledBlueprint = ({
  Map<String, Object> choices,
  Map<String, WorkoutDefinition> workouts,
  Map<String, ProgressionPreset> presets,
  ProgramDefinition? program,
});

/// Blueprint authoring and filling-in. A blueprint itself is never started;
/// instantiation turns it into ordinary published workouts, an optional
/// programme and presets, and records a lineage receipt.
final class BlueprintService {
  const BlueprintService(this.repository);
  final TrainingRepository repository;

  Future<BlueprintRevision> revision(String id, [int? number]) async {
    final all =
        (await repository.blueprintRevisions())
            .where(
              (r) =>
                  r.blueprint.id == id &&
                  (number == null || r.number == number),
            )
            .toList()
          ..sort((a, b) => b.number.compareTo(a.number));
    return all.firstOrNull ??
        (throw const BodyTmiException(
          'not_found',
          'Blueprint revision not found.',
        ));
  }

  Future<BlueprintRevision> publish(
    Blueprint blueprint,
    int expectedRevision,
  ) => repository.transaction(() async {
    final all = await repository.blueprintRevisions();
    final before =
        (all.where((r) => r.blueprint.id == blueprint.id).toList()
              ..sort((a, b) => b.number.compareTo(a.number)))
            .firstOrNull;
    if ((before?.number ?? 0) != expectedRevision)
      throw const BodyTmiException('conflict', 'Blueprint revision changed.');
    if (before != null &&
        canonicalJson(before.blueprint.toJson()) ==
            canonicalJson(blueprint.toJson()))
      return before;
    final next = BlueprintRevision.publish(blueprint, previous: before);
    await repository.insertBlueprintRevision(next);
    return next;
  });

  /// Latest receipt of instance [id], or null.
  Future<BlueprintInstance?> instance(String id, [int? number]) async {
    final all =
        (await repository.blueprintInstances())
            .where((i) => i.id == id && (number == null || i.number == number))
            .toList()
          ..sort((a, b) => b.number.compareTo(a.number));
    return all.firstOrNull;
  }

  /// Fills [blueprint] in for instance [name] and parses every document,
  /// without writing. [workoutRevisions] are the revisions the workouts
  /// would be published as (1 for a new instance).
  Future<FilledBlueprint> fill(
    Blueprint blueprint,
    String name,
    Map<String, Object?> supplied,
    Map<String, int> workoutRevisions,
  ) async {
    final choices = blueprint.resolveChoices(supplied);
    for (final choice in blueprint.choices) {
      if (choice.family case final family?) {
        final members = (await FamilyService(
          repository,
        ).revision(family)).family.exercises;
        if (!members.contains(choices[choice.id]))
          invalid('Choice ${choice.id} must be an exercise of family $family.');
      }
    }
    final docs = blueprint.fill(name, choices, workoutRevisions);
    return (
      choices: choices,
      workouts: {
        for (final e in docs.workouts.entries)
          e.key: WorkoutDefinition.fromJson(e.value),
      },
      presets: {
        for (final e in docs.presets.entries)
          e.key: ProgressionPreset.fromJson(e.value),
      },
      program: docs.program == null
          ? null
          : ProgramDefinition.fromJson(docs.program),
    );
  }

  /// Read-only: what [instantiate] would publish.
  Future<Map<String, Object?>> preview(
    String blueprintId,
    int number,
    String name,
    Map<String, Object?> supplied,
  ) => repository.transaction(() async {
    final blueprint = (await revision(blueprintId, number)).blueprint;
    final head = await instance(name);
    final filled = await fill(blueprint, name, supplied, {
      for (final key in blueprint.workouts.keys)
        key: head == null ? 1 : (await _head(head.workoutId(key))) + 1,
    });
    return {
      'policy': 'bodytmi-blueprint-fill/1',
      'blueprint': blueprintId,
      'blueprintRevision': number,
      'instance': name,
      'choices': filled.choices,
      'workouts': {
        for (final e in filled.workouts.entries) e.key: e.value.toJson(),
      },
      if (filled.program != null) 'program': filled.program!.toJson(),
      if (filled.presets.isNotEmpty)
        'presets': {
          for (final e in filled.presets.entries) e.key: e.value.toJson(),
        },
    };
  });

  Future<int> _head(String templateId) async =>
      (await repository.revision(templateId))?.number ?? 0;

  /// Publishes the filled-in workouts, presets and programme of instance
  /// [name] in one transaction and records receipt number
  /// [expectedInstance] + 1. A new instance (expectedInstance 0) needs every
  /// identity unused; filling an instance in again publishes the next
  /// revision of each, and conflicts if any was edited since the last
  /// receipt. An identical retry returns the existing receipt.
  Future<BlueprintInstance> instantiate(
    String blueprintId,
    int number,
    String name,
    Map<String, Object?> supplied, {
    required int expectedInstance,
    bool requireCatalog = false,
  }) => repository.transaction(() async {
    final blueprint = (await revision(blueprintId, number)).blueprint;
    final head = await instance(name);
    final choices = blueprint.resolveChoices(supplied);
    if (head != null &&
        head.number == expectedInstance + 1 &&
        head.blueprintId == blueprintId &&
        head.blueprintRevision == number &&
        canonicalJson(head.choices) == canonicalJson(choices))
      return head;
    if ((head?.number ?? 0) != expectedInstance)
      throw const BodyTmiException(
        'conflict',
        'Blueprint instance changed; read its latest receipt.',
      );
    final programs = ProgramService(repository);
    final presetService = PresetService(repository);
    Future<int> presetHead(String id) async {
      try {
        return (await presetService.revision(id)).number;
      } on BodyTmiException catch (e) {
        if (e.code == 'not_found') return 0;
        rethrow;
      }
    }

    Future<int> programHead(String id) async {
      try {
        return (await programs.revision(id)).number;
      } on BodyTmiException catch (e) {
        if (e.code == 'not_found') return 0;
        rethrow;
      }
    }

    // Each identity is either unused (new instance) or exactly what the
    // last receipt published (filling in again).
    void owned(String what, int current, int? recorded) {
      if (current != (recorded ?? 0))
        throw BodyTmiException(
          'conflict',
          head == null
              ? '$what already exists; choose another instance name.'
              : '$what changed since this blueprint was last filled in.',
        );
    }

    final workoutHeads = <String, int>{};
    for (final key in blueprint.workouts.keys) {
      final id = '$name-$key';
      workoutHeads[key] = await _head(id);
      owned('Workout $id', workoutHeads[key]!, head?.workouts[key]);
    }
    final presetHeads = <String, int>{};
    for (final key in blueprint.presets.keys) {
      final id = '$name-$key';
      presetHeads[key] = await presetHead(id);
      owned('Preset $id', presetHeads[key]!, head?.presets[key]);
    }
    final programCurrent = blueprint.program == null
        ? 0
        : await programHead(name);
    if (blueprint.program != null)
      owned('Programme $name', programCurrent, head?.programRevision);
    final filled = await fill(blueprint, name, choices, {
      for (final e in workoutHeads.entries) e.key: e.value + 1,
    });
    final training = StoredTrainingService(repository);
    final workouts = <String, int>{};
    for (final e in filled.workouts.entries) {
      workouts[e.key] = (await training.publish(
        e.value,
        workoutHeads[e.key]!,
        requireCatalog: requireCatalog,
      )).number;
    }
    final presets = <String, int>{};
    for (final e in filled.presets.entries) {
      presets[e.key] = (await presetService.publish(
        e.value,
        presetHeads[e.key]!,
      )).number;
    }
    final program = filled.program == null
        ? null
        : (await programs.publish(filled.program!, programCurrent)).number;
    final receipt = BlueprintInstance(
      id: name,
      number: (head?.number ?? 0) + 1,
      blueprintId: blueprintId,
      blueprintRevision: number,
      choices: choices,
      workouts: workouts,
      programRevision: program,
      presets: presets,
    );
    await repository.insertBlueprintInstance(receipt);
    return receipt;
  });
}
