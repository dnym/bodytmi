import 'activity.dart';
import 'body_mass_input.dart';
import 'errors.dart';
import 'effective_mass.dart';
import 'quantity.dart';
import 'timing.dart';

final class ExerciseSlot {
  ExerciseSlot._(
    this.id,
    this.exerciseId,
    this.implementation,
    this.equipmentId,
    this.setupNote,
    this.targets,
    this.prefillMetrics,
    this.bodyMass,
    this.effectiveMass,
    this.timing,
  );

  factory ExerciseSlot.fromJson(Object? input) {
    final json = jsonObject(input, 'slot');
    checkKeys(json, {
      'id',
      'exercise',
      'implementation',
      'equipment',
      'setupNote',
      'targets',
      'prefill',
      'bodyMass',
      'effectiveMass',
      'timing',
    });
    final targets = metricsFromJson(json['targets']);
    if (targets.isEmpty) invalid('A slot needs at least one target metric.');
    final prefill = json['prefill'] ?? <Object?>[];
    if (prefill is! List<Object?> ||
        prefill.any((key) => key is! String || !targets.containsKey(key))) {
      invalid('prefill must list configured target metric names.');
    }
    final note = json['setupNote'];
    if (note != null && note is! String) invalid('setupNote must be a string.');
    final bodyMass = json['bodyMass'] == null
        ? null
        : BodyMassSelection.fromJson(json['bodyMass']);
    final effectiveMass = json['effectiveMass'] == null
        ? null
        : EffectiveMassModel.fromJson(json['effectiveMass']);
    effectiveMass?.validateBindings(targets, hasBodyMass: bodyMass != null);
    final timing = json['timing'] == null
        ? null
        : EffortTimingDefaults.fromJson(json['timing']);
    timing?.resolve(targets);
    return ExerciseSlot._(
      identifier(json, 'id'),
      identifier(json, 'exercise'),
      identifier(json, 'implementation'),
      json['equipment'] == null ? null : identifier(json, 'equipment'),
      note as String?,
      targets,
      Set.unmodifiable(prefill.cast<String>()),
      bodyMass,
      effectiveMass,
      timing,
    );
  }

  final String id;
  final String exerciseId;
  final String implementation;
  final String? equipmentId;
  final String? setupNote;
  final Metrics targets;
  final Set<String> prefillMetrics;
  final BodyMassSelection? bodyMass;
  final EffectiveMassModel? effectiveMass;
  final EffortTimingDefaults? timing;

  bool compatibleWith(ExerciseSlot other) =>
      id == other.id &&
      exerciseId == other.exerciseId &&
      implementation == other.implementation &&
      equipmentId == other.equipmentId &&
      setupNote == other.setupNote;

  Map<String, Object?> toJson() => {
    'id': id,
    'exercise': exerciseId,
    'implementation': implementation,
    if (equipmentId != null) 'equipment': equipmentId,
    if (setupNote != null) 'setupNote': setupNote,
    'targets': metricsToJson(targets),
    'prefill': prefillMetrics.toList(),
    if (bodyMass != null) 'bodyMass': bodyMass!.toJson(),
    if (effectiveMass != null) 'effectiveMass': effectiveMass!.toJson(),
    if (timing != null) 'timing': timing!.toJson(),
  };
}

final class WorkoutDefinition {
  WorkoutDefinition._(this.id, this.name, this.slots, this.plan);
  factory WorkoutDefinition.fromJson(Object? input) {
    final json = jsonObject(input, 'workout definition');
    checkKeys(json, {'id', 'name', 'slots', 'plan'});
    final slots = [
      for (final slot in jsonList(json, 'slots')) ExerciseSlot.fromJson(slot),
    ];
    if (slots.isEmpty ||
        slots.map((s) => s.id).toSet().length != slots.length) {
      invalid('Slots must be nonempty and have unique IDs.');
    }
    final plan = Activity.fromJson(json['plan']);
    final ids = <String>{};
    final slotIds = slots.map((s) => s.id).toSet();
    for (final node in plan.nodes) {
      if (!ids.add(node.id)) invalid('Duplicate activity ID: ${node.id}.');
      if (node is Effort && !slotIds.contains(node.slotId))
        invalid('Unknown slot: ${node.slotId}.');
    }
    var count = 0;
    var efforts = 0;
    for (final occurrence in plan.occurrences()) {
      if (++count > 10000)
        invalid('Plan exceeds the current 10000-occurrence resource limit.');
      if (occurrence.activity is Effort) efforts++;
    }
    if (efforts == 0) invalid('Plan must contain at least one effort.');
    return WorkoutDefinition._(
      identifier(json, 'id'),
      requiredString(json, 'name'),
      List.unmodifiable(slots),
      plan,
    );
  }
  final String id;
  final String name;
  final List<ExerciseSlot> slots;
  final Activity plan;
  ExerciseSlot slot(String id) => slots.firstWhere((slot) => slot.id == id);
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'slots': [for (final slot in slots) slot.toJson()],
    'plan': plan.toJson(),
  };
}

final class WorkoutRevision {
  WorkoutRevision._(this.number, this.definition);
  factory WorkoutRevision.publish(
    WorkoutDefinition definition, {
    WorkoutRevision? previous,
  }) {
    if (previous != null && previous.definition.id != definition.id) {
      invalid('A revision must retain the template identity.');
    }
    return WorkoutRevision._((previous?.number ?? 0) + 1, definition);
  }
  factory WorkoutRevision.fromJson(Object? input) {
    final json = jsonObject(input, 'revision');
    checkKeys(json, {'schemaVersion', 'revision', 'definition'});
    if (json['schemaVersion'] != 1)
      invalid('Unsupported revision schema version.');
    final number = json['revision'];
    if (number is! int || number < 1)
      invalid('revision must be a positive integer.');
    return WorkoutRevision._(
      number,
      WorkoutDefinition.fromJson(json['definition']),
    );
  }
  final int number;
  final WorkoutDefinition definition;
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'revision': number,
    'definition': definition.toJson(),
  };
}

enum SetStatus { planned, completed, skipped }

enum SessionStatus { active, finalized }

final class HistorySource {
  const HistorySource(this.sessionId, this.setId, this.contentVersion);
  final String sessionId;
  final String setId;
  final int contentVersion;
  Map<String, Object?> toJson() => {
    'sessionId': sessionId,
    'setId': setId,
    'contentVersion': contentVersion,
  };
}

final class TrainingSet {
  TrainingSet({
    required this.id,
    required this.slotId,
    required this.role,
    required this.ordinal,
    required Metrics suggested,
    Map<String, HistorySource> sources = const {},
    this.status = SetStatus.planned,
    Metrics actuals = const {},
    this.contentVersion = 1,
    this.timing,
  }) : suggested = Map.unmodifiable(suggested),
       sources = Map.unmodifiable(sources),
       actuals = Map.unmodifiable(actuals);
  final String id;
  final String slotId;
  final String role;
  final int ordinal;
  final Metrics suggested;
  final Map<String, HistorySource> sources;
  final SetStatus status;
  final Metrics actuals;
  final TimedResult? timing;
  final int contentVersion;

  TrainingSet complete(
    Metrics observations, {
    bool acceptSuggested = false,
    TimedResult? timingResult,
  }) {
    final actual = <String, Quantity>{
      if (acceptSuggested) ...suggested,
      ...observations,
    };
    for (final target in suggested.entries) {
      if (actual[target.key] == null)
        invalid('Missing actual metric: ${target.key}.');
      if (actual[target.key]!.dimension != target.value.dimension)
        invalid('Dimension mismatch for ${target.key}.');
    }
    return TrainingSet(
      id: id,
      slotId: slotId,
      role: role,
      ordinal: ordinal,
      suggested: suggested,
      sources: sources,
      timing:
          timingResult ??
          (timing == null
              ? null
              : actual[timing!.metric]?.compareTo(actuals[timing!.metric]!) == 0
              ? timing
              : timing!.edited()),
      status: SetStatus.completed,
      actuals: actual,
      contentVersion: contentVersion + 1,
    );
  }

  TrainingSet skip({bool confirm = false}) {
    if (status == SetStatus.completed && !confirm)
      invalid('Confirm before discarding completed actuals.');
    return TrainingSet(
      id: id,
      slotId: slotId,
      role: role,
      ordinal: ordinal,
      suggested: suggested,
      sources: sources,
      status: SetStatus.skipped,
      contentVersion: contentVersion + 1,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'slot': slotId,
    'role': role,
    'ordinal': ordinal,
    'suggested': metricsToJson(suggested),
    'sources': {for (final e in sources.entries) e.key: e.value.toJson()},
    'status': status.name,
    'actuals': metricsToJson(actuals),
    if (timing != null) 'timing': timing!.toJson(),
    'contentVersion': contentVersion,
  };
}

final class TrainingSession {
  TrainingSession({
    required this.id,
    required this.revision,
    required this.startedAt,
    required List<TrainingSet> sets,
    this.status = SessionStatus.active,
    this.finishedAt,
    this.contentVersion = 1,
    Map<String, BodyMassInputSnapshot> bodyMassInputs = const {},
  }) : sets = List.unmodifiable(sets),
       bodyMassInputs = Map.unmodifiable(bodyMassInputs) {
    final configured = revision.definition.slots
        .where((s) => s.bodyMass != null)
        .toList();
    if (configured.length != bodyMassInputs.length ||
        configured.any(
          (s) =>
              bodyMassInputs[s.id] == null ||
              bodyMassInputs[s.id]!.asOf != startedAt ||
              !bodyMassInputs[s.id]!.sameSelection(s.bodyMass!),
        ))
      invalid(
        'Session body-mass inputs do not match its pinned slots and start time.',
      );
  }
  final String id;
  final WorkoutRevision revision;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final List<TrainingSet> sets;
  final Map<String, BodyMassInputSnapshot> bodyMassInputs;
  final SessionStatus status;
  final int contentVersion;

  TrainingSession replaceSet(TrainingSet updated) {
    if (!sets.any((s) => s.id == updated.id))
      throw BodyTmiException('not_found', 'Unknown set: ${updated.id}.');
    return TrainingSession(
      id: id,
      revision: revision,
      startedAt: startedAt,
      sets: [for (final set in sets) set.id == updated.id ? updated : set],
      status: status,
      finishedAt: finishedAt,
      contentVersion: contentVersion + 1,
      bodyMassInputs: bodyMassInputs,
    );
  }

  TrainingSession finish(DateTime at) {
    if (status == SessionStatus.finalized) return this;
    if (at.isBefore(startedAt))
      invalid('Finish time cannot precede start time.');
    if (sets.any((set) => set.status == SetStatus.planned))
      invalid('Complete or explicitly skip every set before finishing.');
    return TrainingSession(
      id: id,
      revision: revision,
      startedAt: startedAt,
      sets: sets,
      bodyMassInputs: bodyMassInputs,
      status: SessionStatus.finalized,
      finishedAt: at,
      contentVersion: contentVersion + 1,
    );
  }

  TrainingSet set(String id) {
    for (final set in sets) {
      if (set.id == id) return set;
    }
    throw BodyTmiException('not_found', 'Unknown set: $id.');
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'id': id,
    'revision': revision.toJson(),
    'startedAt': startedAt.toUtc().toIso8601String(),
    if (finishedAt != null) 'finishedAt': finishedAt!.toUtc().toIso8601String(),
    'status': status.name,
    'contentVersion': contentVersion,
    'sets': [for (final set in sets) set.toJson()],
    if (bodyMassInputs.isNotEmpty)
      'bodyMassInputs': {
        for (final e in bodyMassInputs.entries) e.key: e.value.toJson(),
      },
  };
}
