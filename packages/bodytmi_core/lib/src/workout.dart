import 'activity.dart';
import 'derived_plan_input.dart';
import 'body_mass_input.dart';
import 'errors.dart';
import 'effective_mass.dart';
import 'load_context.dart';
import 'load_arrangement.dart';
import 'load_convention.dart';
import 'quantity.dart';
import 'timing.dart';
import 'set_observations.dart';
import 'objective.dart';
import 'window_repeat.dart';
import 'substitution.dart';
import 'prescription_overrides.dart';

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
    this.convention,
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
      'convention',
    });
    final targets = metricsFromJson(json['targets']);
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
      json['convention'] == null
          ? null
          : LoadConvention.fromJson(json['convention']),
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
  final LoadConvention? convention;

  bool compatibleWith(ExerciseSlot other) =>
      id == other.id &&
      exerciseId == other.exerciseId &&
      implementation == other.implementation &&
      equipmentId == other.equipmentId &&
      setupNote == other.setupNote &&
      convention == other.convention;

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
    if (convention != null) 'convention': convention!.toJson(),
  };
}

final class WorkoutDefinition {
  WorkoutDefinition._(
    this.id,
    this.name,
    this.slots,
    this.plan, [
    this.amraps = const [],
  ]);
  factory WorkoutDefinition.fromJson(Object? input) {
    final json = jsonObject(input, 'workout definition');
    checkKeys(json, {'id', 'name', 'slots', 'plan', 'amraps'});
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
      if (node is Effort) {
        final slot = slots.firstWhere((s) => s.id == node.slotId);
        final resolved = node.resolveTargets(slot.targets);
        if (resolved.isEmpty &&
            node.maxEffortMetrics.isEmpty &&
            node.criteria.isEmpty)
          invalid('Each effort needs targets or explicit objectives.');
        slot.timing?.resolve(resolved);
        final timing = slot.timing;
        if (timing != null &&
            timing.openEnded &&
            (node.maxEffortMetrics.contains(timing.metric) ||
                (node.criteria[timing.metric] != null &&
                    node.criteria[timing.metric]!.unit.dimension !=
                        Dimension.duration)))
          invalid(
            'Open-ended timing metric conflicts with an effort objective.',
          );
      }
    }
    for (final slot in slots) {
      if (slot.targets.isEmpty &&
          !plan.nodes.whereType<Effort>().any(
            (e) =>
                e.slotId == slot.id &&
                (e.maxEffortMetrics.isNotEmpty || e.criteria.isNotEmpty),
          ))
        invalid('A slot needs targets or an explicit effort objective.');
    }
    var count = 0;
    var efforts = 0;
    for (final occurrence in plan.occurrences()) {
      if (++count > 10000)
        invalid('Plan exceeds the current 10000-occurrence resource limit.');
      if (occurrence.activity is Effort) efforts++;
    }
    if (efforts == 0) invalid('Plan must contain at least one effort.');
    // Authored deadline-bounded AMRAP blocks. Each is executed as its own
    // repeat ledger bound to a session; it is not part of the finite plan.
    final amraps = <WindowRepeatSpec>[];
    if (json.containsKey('amraps')) {
      final list = jsonList(json, 'amraps');
      if (list.isEmpty || list.length > 16)
        invalid('amraps must list 1–16 AMRAP blocks when present.');
      for (final item in list) {
        final amrap = WindowRepeatSpec.fromJson(item);
        if (amrap.roundDefinition.amraps.isNotEmpty)
          invalid('An AMRAP round cannot declare nested AMRAP blocks.');
        amraps.add(amrap);
      }
      if (amraps.map((a) => a.id).toSet().length != amraps.length)
        invalid('AMRAP block IDs must be unique.');
      amraps.sort((a, b) => a.id.compareTo(b.id));
    }
    return WorkoutDefinition._(
      identifier(json, 'id'),
      requiredString(json, 'name'),
      List.unmodifiable(slots),
      plan,
      List.unmodifiable(amraps),
    );
  }
  final String id;
  final String name;
  final List<ExerciseSlot> slots;
  final Activity plan;
  final List<WindowRepeatSpec> amraps;
  bool get hasAmraps => amraps.isNotEmpty;
  WindowRepeatSpec? amrap(String id) =>
      amraps.where((a) => a.id == id).firstOrNull;
  ExerciseSlot slot(String id) => slots.firstWhere((slot) => slot.id == id);
  bool get hasEffortTargets =>
      plan.nodes.whereType<Effort>().any((e) => e.targets.isNotEmpty);

  bool get hasLoadConventions => slots.any((s) => s.convention != null);

  bool get hasEffortSides =>
      plan.nodes.whereType<Effort>().any((e) => e.side != null);

  late final Map<String, String> _sides = Map.unmodifiable({
    for (final occurrence in plan.occurrences())
      if (occurrence.activity case Effort(:final side?)) occurrence.id: side,
  });

  /// The authored unilateral side of an effort occurrence, or null.
  String? effortSide(String occurrenceId) => _sides[occurrenceId];

  bool get hasManualRest => plan.nodes.whereType<Rest>().any((r) => r.isManual);

  bool get hasExtendedEffortRoles => plan.nodes.whereType<Effort>().any(
    (e) => e.role == 'backoff' || e.role == 'drop',
  );

  bool get hasMaxEffortObjectives =>
      plan.nodes.whereType<Effort>().any((e) => e.maxEffortMetrics.isNotEmpty);

  bool get hasTypedObjectives =>
      plan.nodes.whereType<Effort>().any((e) => e.criteria.isNotEmpty);

  /// Published working targets in the same slot/role ordinal order as sessions.
  List<Metrics> workingTargets(String slotId) => roleTargets(slotId, 'work');

  /// Published targets in the selected slot and effort role's ordinal order.
  List<Metrics> roleTargets(String slotId, String selectedRole) =>
      List.unmodifiable([
        for (final occurrence in plan.occurrences())
          if (occurrence.activity case Effort(
            :final role,
            slotId: final id,
          ) when id == slotId && role == selectedRole)
            (occurrence.activity as Effort).resolveTargets(
              slot(slotId).targets,
            ),
      ]);
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'slots': [for (final slot in slots) slot.toJson()],
    'plan': plan.toJson(),
    if (amraps.isNotEmpty) 'amraps': [for (final a in amraps) a.toJson()],
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

final class CarriedTargetSource {
  const CarriedTargetSource(this.setId, this.contentVersion);
  final String setId;
  final int contentVersion;
  Map<String, Object?> toJson() => {
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
    Set<String> manualTargets = const {},
    Map<String, CarriedTargetSource> carriedTargets = const {},
    this.status = SetStatus.planned,
    Metrics actuals = const {},
    this.contentVersion = 1,
    this.timing,
    SetObservations? observations,
    this.loadArrangement,
    Set<String> maxEffortMetrics = const {},
    Map<String, NumericObjective> criteria = const {},
    this.substitution,
  }) : criteria = Map.unmodifiable(criteria),
       carriedTargets = Map.unmodifiable(carriedTargets),
       manualTargets = Set.unmodifiable(manualTargets),
       maxEffortMetrics = Set.unmodifiable(maxEffortMetrics),
       observations = observations == null || observations.isEmpty
           ? null
           : observations,
       suggested = Map.unmodifiable(suggested),
       sources = Map.unmodifiable(sources),
       actuals = Map.unmodifiable(actuals) {
    if (this.manualTargets.any(
      (key) =>
          !this.suggested.containsKey(key) || this.sources.containsKey(key),
    )) {
      invalid(
        'Manual targets must identify suggestions without history sources.',
      );
    }
    if (this.carriedTargets.keys.any(
      (key) => !this.manualTargets.contains(key),
    )) {
      invalid('Carried targets must be manually selected suggestions.');
    }
    this.observations?.validateStatus(status.name);
    final swap = substitution;
    if (swap != null) {
      if (this.sources.isNotEmpty)
        invalid('A substituted set keeps no original-context history sources.');
      if (loadArrangement != null)
        invalid('A substituted set cannot record the slot plate arrangement.');
      for (final metric in this.suggested.keys) {
        if (!swap.targets.containsKey(metric))
          invalid('Substituted suggestion $metric has no target source.');
      }
      for (final entry in swap.targets.entries) {
        final suggested = this.suggested.containsKey(entry.key);
        if (entry.value.source == 'unresolved' &&
            suggested &&
            !this.manualTargets.contains(entry.key))
          invalid('An unresolved substitute target cannot be suggested.');
        if (entry.value.source != 'unresolved' && !suggested)
          invalid('A resolved substitute target must be suggested.');
      }
    }
    if (loadArrangement != null && status != SetStatus.completed)
      invalid('Plate arrangements record only for completed sets.');
    if (this.criteria.length + this.maxEffortMetrics.length > 100)
      invalid('Too many set objectives.');
    for (final entry in this.criteria.entries) {
      identifier({'metric': entry.key}, 'metric');
      if (entry.value.mode == 'maxEffort' ||
          this.maxEffortMetrics.contains(entry.key))
        invalid('Duplicate or invalid objective mode.');
      final suggestion = this.suggested[entry.key];
      if (suggestion != null &&
          (entry.value.mode == 'observe' ||
              suggestion.dimension != entry.value.unit.dimension))
        invalid('Suggested quantity conflicts with the objective.');
      if (status == SetStatus.completed &&
          this.actuals[entry.key]?.dimension != entry.value.unit.dimension)
        invalid('Objective requires a compatible actual: ${entry.key}.');
    }
    for (final metric in this.maxEffortMetrics) {
      identifier({'metric': metric}, 'metric');
      if (this.suggested.containsKey(metric))
        invalid('Max-effort metrics cannot have suggested targets.');
      if (status == SetStatus.completed &&
          this.actuals[metric]?.dimension != Dimension.count)
        invalid('Max-effort repetitions require an explicit count actual.');
    }
  }
  final String id;
  final String slotId;
  final String role;
  final int ordinal;
  final Metrics suggested;
  final Map<String, HistorySource> sources;
  final Set<String> manualTargets;
  final Map<String, CarriedTargetSource> carriedTargets;
  final SetStatus status;
  final Metrics actuals;
  final TimedResult? timing;
  final SetObservations? observations;
  final LoadArrangement? loadArrangement;
  final Set<String> maxEffortMetrics;
  final Map<String, NumericObjective> criteria;

  /// A temporary substitution frozen on this set, if any.
  final SetSubstitution? substitution;
  Map<String, Object?> get objectivesJson => {
    ...maxEffortObjectivesToJson(maxEffortMetrics),
    ...numericObjectivesToJson(criteria),
  };
  bool get eligibleForPerformance =>
      status == SetStatus.completed && !(observations?.interrupted ?? false);
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
    for (final entry in criteria.entries) {
      if (actual[entry.key]?.dimension != entry.value.unit.dimension)
        invalid(
          'Objective requires an explicit compatible actual: ${entry.key}.',
        );
    }
    for (final metric in maxEffortMetrics) {
      if (observations[metric]?.dimension != Dimension.count)
        invalid(
          'Max-effort repetitions require an explicitly supplied count: $metric.',
        );
    }
    // An unresolved substitute target is never filled from the original.
    for (final metric in substitution?.unresolved ?? const <String>{}) {
      if (suggested.containsKey(metric)) continue;
      if (observations[metric]?.dimension !=
          substitution!.targets[metric]!.dimension)
        invalid(
          'Substituted target $metric is unresolved; supply its actual explicitly.',
        );
    }
    return TrainingSet(
      id: id,
      slotId: slotId,
      role: role,
      ordinal: ordinal,
      suggested: suggested,
      sources: sources,
      manualTargets: manualTargets,
      carriedTargets: carriedTargets,
      timing:
          timingResult ??
          (timing == null
              ? null
              : actual[timing!.metric]?.compareTo(actuals[timing!.metric]!) == 0
              ? timing
              : timing!.edited()),
      status: SetStatus.completed,
      observations: this.observations,
      loadArrangement: loadArrangement,
      maxEffortMetrics: maxEffortMetrics,
      criteria: criteria,
      substitution: substitution,
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
      manualTargets: manualTargets,
      carriedTargets: carriedTargets,
      status: SetStatus.skipped,
      observations: observations?.notesOnly,
      maxEffortMetrics: maxEffortMetrics,
      criteria: criteria,
      substitution: substitution,
      contentVersion: contentVersion + 1,
    );
  }

  /// Replaces the complete annotation object; explicit confirmation clears it.
  TrainingSet annotate(SetObservations replacement, {bool confirm = false}) {
    if (replacement.isEmpty && observations != null && !confirm)
      invalid('Confirm before clearing set observations.');
    return TrainingSet(
      id: id,
      slotId: slotId,
      role: role,
      ordinal: ordinal,
      suggested: suggested,
      sources: sources,
      manualTargets: manualTargets,
      carriedTargets: carriedTargets,
      status: status,
      actuals: actuals,
      timing: timing,
      observations: replacement,
      loadArrangement: loadArrangement,
      maxEffortMetrics: maxEffortMetrics,
      criteria: criteria,
      substitution: substitution,
      contentVersion: contentVersion + 1,
    );
  }

  /// Replaces the recorded plate stack; the caller validates it against the
  /// session's frozen instance loading before storing.
  TrainingSet arrange(LoadArrangement? replacement) {
    if (replacement == null && status != SetStatus.completed)
      invalid('Only completed sets can clear a plate arrangement.');
    return TrainingSet(
      id: id,
      slotId: slotId,
      role: role,
      ordinal: ordinal,
      suggested: suggested,
      sources: sources,
      manualTargets: manualTargets,
      carriedTargets: carriedTargets,
      status: status,
      actuals: actuals,
      timing: timing,
      observations: observations,
      loadArrangement: replacement,
      maxEffortMetrics: maxEffortMetrics,
      criteria: criteria,
      substitution: substitution,
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
    if (manualTargets.isNotEmpty)
      'manualTargets': (manualTargets.toList()..sort()),
    if (carriedTargets.isNotEmpty)
      'carriedTargets': {
        for (final e in carriedTargets.entries) e.key: e.value.toJson(),
      },
    'status': status.name,
    'actuals': metricsToJson(actuals),
    if (timing != null) 'timing': timing!.toJson(),
    if (observations != null) 'observations': observations!.toJson(),
    if (loadArrangement != null) 'loadArrangement': loadArrangement!.toJson(),
    if (maxEffortMetrics.isNotEmpty || criteria.isNotEmpty)
      'objectives': objectivesJson,
    if (substitution != null) 'substitution': substitution!.toJson(),
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
    Map<String, BodyMassOverride>? initialBodyMassOverrides,
    this.derivedPlanInput,
    List<PrescriptionOverrideRecord> prescriptionOverrides = const [],
    Map<String, LoadInputSnapshot> loadInputs = const {},
  }) : sets = List.unmodifiable(sets),
       prescriptionOverrides = List.unmodifiable(prescriptionOverrides),
       bodyMassInputs = Map.unmodifiable(bodyMassInputs),
       loadInputs = Map.unmodifiable(loadInputs),
       initialBodyMassOverrides = initialBodyMassOverrides == null
           ? null
           : Map.unmodifiable(initialBodyMassOverrides) {
    if (this.initialBodyMassOverrides != null && contentVersion < 2)
      invalid('Rebound body-mass inputs require a later session version.');
    if (this.initialBodyMassOverrides?.keys.any(
          (id) => !bodyMassInputs.containsKey(id),
        ) ??
        false)
      invalid('Initial body-mass override names an unconfigured slot.');
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
    for (final entry in this.loadInputs.entries) {
      final slot = revision.definition.slots
          .where((s) => s.id == entry.key)
          .firstOrNull;
      if (slot == null || entry.value.isTrivial)
        invalid('Session load inputs name an unknown or trivial slot.');
      entry.value.matchesSlot(
        slotId: entry.key,
        slotConvention: slot.convention,
        slotEquipmentId: slot.equipmentId,
      );
    }
    for (final set in sets) {
      final arrangement = set.loadArrangement;
      if (arrangement == null) continue;
      final instance = loadInputs[set.slotId]?.instance;
      if (instance == null)
        invalid('A plate arrangement requires a frozen session load binding.');
      if (arrangement.instanceId != instance.instanceId)
        invalid('Plate arrangement instance identity is inconsistent.');
      if (instance.snapshot.loading == null)
        invalid(
          'A plate arrangement requires an instance with declared loading.',
        );
      arrangement.validateAgainst(instance.snapshot.loading!);
    }
  }
  final String id;
  final WorkoutRevision revision;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final List<TrainingSet> sets;
  final Map<String, BodyMassInputSnapshot> bodyMassInputs;

  /// Frozen load entry contexts captured at start: the entry convention
  /// resolved per slot and the equipment instance revision the session used.
  final Map<String, LoadInputSnapshot> loadInputs;

  /// Original start request overrides, retained after explicit rebinding.
  final Map<String, BodyMassOverride>? initialBodyMassOverrides;
  final DerivedPlanInput? derivedPlanInput;

  /// Frozen program prescription overrides applied at session start, with
  /// authored prior targets and applied results per rewritten set.
  final List<PrescriptionOverrideRecord> prescriptionOverrides;
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
      loadInputs: loadInputs,
      initialBodyMassOverrides: initialBodyMassOverrides,
      derivedPlanInput: derivedPlanInput,
      prescriptionOverrides: prescriptionOverrides,
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
      loadInputs: loadInputs,
      initialBodyMassOverrides: initialBodyMassOverrides,
      derivedPlanInput: derivedPlanInput,
      prescriptionOverrides: prescriptionOverrides,
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
    if (derivedPlanInput != null)
      'derivedPlanInput': derivedPlanInput!.toJson(),
    if (initialBodyMassOverrides != null)
      'initialBodyMassOverrides': {
        for (final e in initialBodyMassOverrides!.entries)
          e.key: e.value.toJson(),
      },
    if (bodyMassInputs.isNotEmpty)
      'bodyMassInputs': {
        for (final e in bodyMassInputs.entries) e.key: e.value.toJson(),
      },
    if (loadInputs.isNotEmpty)
      'loadInputs': {
        for (final e in loadInputs.entries) e.key: e.value.toJson(),
      },
    if (prescriptionOverrides.isNotEmpty)
      'prescriptionOverrides': [
        for (final record in prescriptionOverrides) record.toJson(),
      ],
  };
}

/// The composition a set was actually performed with: its frozen
/// substitution when present, otherwise the pinned slot's own.
typedef EffectiveComposition = ({
  String exercise,
  String implementation,
  String? equipment,
  String? setupNote,
  bool substituted,
});

EffectiveComposition effectiveComposition(ExerciseSlot slot, TrainingSet set) {
  final swap = set.substitution?.composition;
  return swap == null
      ? (
          exercise: slot.exerciseId,
          implementation: slot.implementation,
          equipment: slot.equipmentId,
          setupNote: slot.setupNote,
          substituted: false,
        )
      : (
          exercise: swap.exerciseId,
          implementation: swap.implementation,
          equipment: swap.equipmentId,
          setupNote: swap.setupNote,
          substituted: true,
        );
}
