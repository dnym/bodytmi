import 'activity.dart';
import 'derived_plan_input.dart';
import 'body_mass_input.dart';
import 'categorical.dart';
import 'tempo.dart';
import 'errors.dart';
import 'instant.dart';
import 'effective_mass.dart';
import 'equipment.dart';
import 'load_context.dart';
import 'nearest_setting.dart';
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
    this.categories,
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
      'categories',
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
    final categories = json.containsKey('categories')
        ? categoricalLeversFromJson(json['categories'])
        : const <String, CategoricalLever>{};
    final tempoLevers = categories.values.where((l) => l.isTempo).length;
    if (tempoLevers > 1) invalid('A slot declares at most one tempo lever.');
    if (tempoLevers == 1 && timing?.tempo != null)
      invalid('A slot with a tempo lever cannot also publish timing tempo.');
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
      categories,
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

  /// Declared categorical levers (grip, hand count, …) and their defaults.
  final Map<String, CategoricalLever> categories;

  /// The categorical lever whose values prescribe tempo, or null.
  String? get tempoLever => categories.entries
      .where((e) => e.value.isTempo)
      .map((e) => e.key)
      .firstOrNull;

  /// The tempo a set planned with [settings] follows: its tempo lever's value
  /// (default when unset), else the published timing tempo, else none.
  TempoPlan? tempoFor(Map<String, String> settings) {
    final lever = tempoLever;
    if (lever == null) return timing?.tempo;
    final declared = categories[lever]!;
    return declared.tempos[settings[lever] ?? declared.defaultValue];
  }

  /// Lever defaults, before any effort or progression setting.
  Map<String, String> get defaultSettings => Map.unmodifiable({
    for (final e in categories.entries) e.key: e.value.defaultValue,
  });

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
    if (categories.isNotEmpty)
      'categories': {
        for (final e in categories.entries) e.key: e.value.toJson(),
      },
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
        validateCategoricalSettings(
          node.settings,
          slot.categories,
          'Effort ${node.id}',
        );
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
    // Variants: a slot categorical lever selects one complete branch. Branches
    // cover exactly the lever's values; branch values are imposed on that
    // slot's efforts, so an effort cannot contradict its enclosing branch.
    void checkVariants(
      Activity node,
      Map<String, Map<String, String>> imposed,
    ) {
      if (node is Variant) {
        final slot = slots.where((s) => s.id == node.slotId).firstOrNull;
        if (slot == null) invalid('Unknown slot: ${node.slotId}.');
        final lever = slot.categories[node.lever];
        if (lever == null)
          invalid(
            'Variant ${node.id} names undeclared categorical lever '
            '${node.lever} of slot ${slot.id}.',
          );
        final values = node.branches.keys.toSet();
        if (values.length != lever.values.length ||
            !values.containsAll(lever.values))
          invalid(
            'Variant ${node.id} branches must cover exactly the values of '
            'lever ${node.lever}.',
          );
        if (imposed[node.slotId]?.containsKey(node.lever) ?? false)
          invalid(
            'Variant ${node.id} repeats lever ${node.lever} of an enclosing '
            'variant.',
          );
        for (final e in node.branches.entries) {
          if (!e.value.nodes.any((n) => n is Effort))
            invalid('Variant ${node.id} branch ${e.key} needs an effort.');
          checkVariants(e.value, {
            ...imposed,
            node.slotId: {...?imposed[node.slotId], node.lever: e.key},
          });
        }
        return;
      }
      if (node is Effort) {
        for (final e in (imposed[node.slotId] ?? const {}).entries) {
          final own = node.settings[e.key];
          if (own != null && own != e.value)
            invalid(
              'Effort ${node.id} sets ${e.key} to $own inside variant '
              'branch ${e.value}.',
            );
        }
      }
      for (final child in node.children) checkVariants(child, imposed);
    }

    checkVariants(plan, const {});
    // Parent bouts count once; nesting them would double-count a bout.
    void checkBouts(Activity node, bool inside) {
      final bout = switch (node) {
        Sequence(:final bout) || Repeat(:final bout) => bout,
        _ => false,
      };
      if (bout && inside)
        invalid('Bout ${node.id} cannot sit inside another bout.');
      if (bout &&
          node
                  .structuralOccurrences()
                  .where((o) => o.activity is Effort)
                  .length <
              2)
        invalid('Bout ${node.id} needs at least two effort occurrences.');
      for (final child in node.children) checkBouts(child, inside || bout);
    }

    checkBouts(plan, false);
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
    for (final occurrence in plan.structuralOccurrences()) {
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
    // Placements put a declared block at one unique point of the finite plan.
    final placed = <String>{};
    void place(Activity node, bool repeated, [bool inVariant = false]) {
      if (node case AmrapPlacement(:final amrapId)) {
        if (!amraps.any((a) => a.id == amrapId))
          invalid('AMRAP placement names an undeclared block: $amrapId.');
        if (repeated)
          invalid(
            'An AMRAP placement cannot sit inside a repeat or window; '
            'it must occur exactly once.',
          );
        if (inVariant)
          invalid('An AMRAP placement cannot sit inside a variant branch.');
        if (!placed.add(amrapId))
          invalid('AMRAP block $amrapId is placed more than once.');
      }
      for (final child in node.children)
        place(
          child,
          repeated || node is Repeat || node is TimeWindow,
          inVariant || node is Variant,
        );
    }

    place(plan, false);
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

  /// The authored plan. With variants it cannot be expanded directly: use
  /// [resolveVariants] (sessions expose their frozen resolution).
  final Activity plan;

  late final List<Variant> variants = List.unmodifiable(
    plan.nodes.whereType<Variant>(),
  );
  bool get hasVariants => variants.isNotEmpty;

  /// The categorical levers that select variants enclosing [slotId] efforts.
  Set<String> variantLevers(String slotId) => {
    for (final v in variants)
      if (v.slotId == slotId) v.lever,
  };

  /// A variant-free definition expanding only the selected branches. Every
  /// reached variant needs a selection, and no other selection is accepted.
  /// Variants of the same slot lever must agree.
  WorkoutDefinition resolveVariants(Map<String, String> selections) {
    if (!hasVariants) {
      if (selections.isNotEmpty)
        invalid('Workout $id declares no variants to select.');
      return this;
    }
    final key = [
      for (final k in (selections.keys.toList()..sort())) '$k=${selections[k]}',
    ].join('\u0000');
    return _resolved[key] ??= () {
      final reached = <String>{};
      final resolved = resolveVariantActivity(plan, selections, reached);
      if (reached.length != selections.length)
        invalid('Variant selections name a variant the plan does not reach.');
      final chosen = <String, String>{};
      for (final v in variants.where((v) => reached.contains(v.id))) {
        final previous = chosen['${v.slotId}\u0000${v.lever}'];
        if (previous != null && previous != selections[v.id])
          invalid(
            'Variants of slot ${v.slotId} lever ${v.lever} must select the '
            'same value.',
          );
        chosen['${v.slotId}\u0000${v.lever}'] = selections[v.id]!;
      }
      return WorkoutDefinition._(id, name, slots, resolved, amraps);
    }();
  }

  final Map<String, WorkoutDefinition> _resolved = {};

  /// Selections for every variant reached when each slot lever takes
  /// [slotSettings] (slot → lever → value), else the lever's default.
  Map<String, String> variantSelections([
    Map<String, Map<String, String>> slotSettings = const {},
  ]) {
    final out = <String, String>{};
    void walk(Activity node) {
      if (node is Variant) {
        final value =
            slotSettings[node.slotId]?[node.lever] ??
            slot(node.slotId).categories[node.lever]!.defaultValue;
        out[node.id] = value;
        final branch = node.branches[value];
        if (branch == null) invalid('Variant ${node.id} has no branch $value.');
        walk(branch);
        return;
      }
      for (final child in node.children) walk(child);
    }

    walk(plan);
    return Map.unmodifiable({
      for (final k in (out.keys.toList()..sort())) k: out[k]!,
    });
  }

  final List<WindowRepeatSpec> amraps;
  bool get hasAmraps => amraps.isNotEmpty;
  WindowRepeatSpec? amrap(String id) =>
      amraps.where((a) => a.id == id).firstOrNull;

  /// The plan occurrence path placing [amrapId], or null when unplaced.
  String? amrapPlacement(String amrapId) => [
    for (final o in plan.structuralOccurrences())
      if (o.activity case AmrapPlacement(amrapId: final id) when id == amrapId)
        o.id,
  ].firstOrNull;
  ExerciseSlot slot(String id) => slots.firstWhere((slot) => slot.id == id);
  bool get hasEffortTargets =>
      plan.nodes.whereType<Effort>().any((e) => e.targets.isNotEmpty);

  bool get hasLoadConventions => slots.any((s) => s.convention != null);

  bool get hasEffortSides =>
      plan.nodes.whereType<Effort>().any((e) => e.side != null);

  late final Map<String, String> _sides = Map.unmodifiable({
    for (final occurrence in plan.structuralOccurrences())
      if (occurrence.activity case Effort(:final side?)) occurrence.id: side,
  });

  late final Map<String, Map<String, String>> _settings = Map.unmodifiable({
    for (final (occurrence, imposed) in imposedOccurrences(plan))
      if (occurrence.activity case final Effort effort)
        occurrence.id: sortedSettings({
          ...slot(effort.slotId).defaultSettings,
          ...effort.settings,
          ...?imposed[effort.slotId],
        }),
  });

  /// Authored categorical settings of an effort occurrence: slot defaults
  /// merged with the effort's own settings. Empty without levers.
  Map<String, String> plannedSettings(String occurrenceId) =>
      _settings[occurrenceId] ?? const {};

  /// The authored unilateral side of an effort occurrence, or null.
  String? effortSide(String occurrenceId) => _sides[occurrenceId];

  bool get hasExtendedEffortRoles => plan.nodes.whereType<Effort>().any(
    (e) => e.role == 'backoff' || e.role == 'drop',
  );

  /// Authored efforts of a slot/role in session ordinal order.
  List<Effort> roleEfforts(String slotId, String selectedRole) =>
      List.unmodifiable([
        for (final occurrence in plan.occurrences())
          if (occurrence.activity case final Effort effort
              when effort.slotId == slotId && effort.role == selectedRole)
            effort,
      ]);

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
    this.performedOn,
    List<PlateUsage> unavailablePlates = const [],
    Set<String> maxEffortMetrics = const {},
    Map<String, NumericObjective> criteria = const {},
    this.substitution,
    required Map<String, String> settings,
    required Map<String, String> actualSettings,
  }) : settings = sortedSettings(settings),
       actualSettings = sortedSettings(actualSettings),
       criteria = Map.unmodifiable(criteria),
       carriedTargets = Map.unmodifiable(carriedTargets),
       manualTargets = Set.unmodifiable(manualTargets),
       maxEffortMetrics = Set.unmodifiable(maxEffortMetrics),
       unavailablePlates = List.unmodifiable(unavailablePlates),
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
    if (this.actualSettings.isNotEmpty) {
      if (status != SetStatus.completed)
        invalid('Actual categorical settings record only for completed sets.');
      for (final e in this.actualSettings.entries) {
        if (!this.settings.containsKey(e.key))
          invalid(
            'Actual setting ${e.key} is not a planned lever of this set.',
          );
        if (this.settings[e.key] == e.value)
          invalid('Actual settings record only values that differ from plan.');
      }
    }
    final swap = substitution;
    if (swap != null) {
      if (this.sources.isNotEmpty)
        invalid('A substituted set keeps no original-context history sources.');
      if (loadArrangement != null)
        invalid('A substituted set cannot record the slot plate arrangement.');
      if (performedOn != null)
        invalid('A substituted set names its own equipment, not an instance.');
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
    if (this.unavailablePlates.isNotEmpty) {
      final loading = performedOn?.snapshot.loading;
      if (loading == null)
        invalid(
          'Unavailable plates need a performedOn instance with declared '
          'loading.',
        );
      loading.without(this.unavailablePlates);
    }
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

  /// The equipment instance this set was (or will be) performed on when it
  /// differs from the session's binding, e.g. the kilogram machine because
  /// the pound one was taken. Frozen at the published revision; progression
  /// treats the instance's nearest setting to the target as following it.
  final LoadInstanceReference? performedOn;

  /// Plates of [performedOn]'s stock that were not available for this set
  /// (the micro-plate bag left at home). The nearest setting is then judged
  /// on the remaining stock.
  final List<PlateUsage> unavailablePlates;

  /// The loading this set could use: [performedOn]'s without
  /// [unavailablePlates], or null when nothing is missing.
  LoadingSpec? get availableLoading => unavailablePlates.isEmpty
      ? null
      : performedOn!.snapshot.loading!.without(unavailablePlates);
  final Set<String> maxEffortMetrics;
  final Map<String, NumericObjective> criteria;

  /// A temporary substitution frozen on this set, if any.
  final SetSubstitution? substitution;

  /// Planned categorical settings frozen at start (lever → value).
  final Map<String, String> settings;

  /// Settings actually used where they differed from plan (completed only).
  final Map<String, String> actualSettings;

  /// The settings this result was performed with.
  Map<String, String> get performedSettings =>
      sortedSettings({...settings, ...actualSettings});

  /// Records which categorical values were actually used.
  TrainingSet withActualSettings(Map<String, String> performed) {
    final differing = {
      for (final e in performed.entries)
        if (settings[e.key] != e.value) e.key: e.value,
    };
    for (final key in performed.keys)
      if (!settings.containsKey(key))
        invalid('Actual setting $key is not a planned lever of this set.');
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
      loadArrangement: loadArrangement,
      performedOn: performedOn,
      unavailablePlates: unavailablePlates,
      maxEffortMetrics: maxEffortMetrics,
      criteria: criteria,
      substitution: substitution,
      settings: settings,
      actualSettings: differing,
      contentVersion: contentVersion + 1,
    );
  }

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
      performedOn: performedOn,
      unavailablePlates: unavailablePlates,
      maxEffortMetrics: maxEffortMetrics,
      criteria: criteria,
      substitution: substitution,
      settings: settings,
      actualSettings: actualSettings,
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
      settings: settings,
      actualSettings: const {},
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
      performedOn: performedOn,
      unavailablePlates: unavailablePlates,
      maxEffortMetrics: maxEffortMetrics,
      criteria: criteria,
      substitution: substitution,
      settings: settings,
      actualSettings: actualSettings,
      contentVersion: contentVersion + 1,
    );
  }

  /// Records (or with null clears) the instance this set is performed on.
  /// A recorded plate arrangement belongs to the previous instance, so a
  /// change requires clearing it first.
  TrainingSet performOn(
    LoadInstanceReference? instance, {
    List<PlateUsage> unavailablePlates = const [],
  }) {
    if (substitution != null)
      invalid('A substituted set names its own equipment, not an instance.');
    if (loadArrangement != null &&
        loadArrangement!.instanceId != instance?.instanceId)
      invalid('Clear the recorded plate arrangement before changing instance.');
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
      loadArrangement: loadArrangement,
      performedOn: instance,
      unavailablePlates: instance == null ? const [] : unavailablePlates,
      maxEffortMetrics: maxEffortMetrics,
      criteria: criteria,
      substitution: substitution,
      settings: settings,
      actualSettings: actualSettings,
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
      performedOn: performedOn,
      unavailablePlates: unavailablePlates,
      maxEffortMetrics: maxEffortMetrics,
      criteria: criteria,
      substitution: substitution,
      settings: settings,
      actualSettings: actualSettings,
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
    if (performedOn != null) 'performedOn': performedOn!.toJson(),
    if (unavailablePlates.isNotEmpty)
      'unavailablePlates': [for (final p in unavailablePlates) p.toJson()],
    if (maxEffortMetrics.isNotEmpty || criteria.isNotEmpty)
      'objectives': objectivesJson,
    if (substitution != null) 'substitution': substitution!.toJson(),
    if (settings.isNotEmpty) 'settings': settings,
    if (actualSettings.isNotEmpty) 'actualSettings': actualSettings,
    'contentVersion': contentVersion,
  };
}

final class TrainingSession {
  TrainingSession({
    required this.id,
    required this.revision,
    required this.startedAt,
    required this.startOffsetMinutes,
    required List<TrainingSet> sets,
    required List<TrainingSet> extraSets,
    this.status = SessionStatus.active,
    this.finishedAt,
    required this.finishOffsetMinutes,
    required this.endedAt,
    this.contentVersion = 1,
    Map<String, BodyMassInputSnapshot> bodyMassInputs = const {},
    Map<String, BodyMassOverride>? initialBodyMassOverrides,
    this.derivedPlanInput,
    List<PrescriptionOverrideRecord> prescriptionOverrides = const [],
    Map<String, LoadInputSnapshot> loadInputs = const {},
    required Map<String, String> variantSelections,
    required this.gymId,
    required Map<String, String> gymSetupNotes,
  }) : sets = List.unmodifiable(sets),
       gymSetupNotes = Map.unmodifiable({
         for (final k in (gymSetupNotes.keys.toList()..sort()))
           k: gymSetupNotes[k]!,
       }),
       extraSets = List.unmodifiable(extraSets),
       variantSelections = Map.unmodifiable({
         for (final k in (variantSelections.keys.toList()..sort()))
           k: variantSelections[k]!,
       }),
       prescriptionOverrides = List.unmodifiable(prescriptionOverrides),
       bodyMassInputs = Map.unmodifiable(bodyMassInputs),
       loadInputs = Map.unmodifiable(loadInputs),
       initialBodyMassOverrides = initialBodyMassOverrides == null
           ? null
           : Map.unmodifiable(initialBodyMassOverrides) {
    if (gymId != null) identifier({'gym': gymId}, 'gym');
    if (this.gymSetupNotes.isNotEmpty && gymId == null)
      invalid('Gym setup notes need the session gym.');
    for (final entry in this.gymSetupNotes.entries) {
      if (!revision.definition.slots.any((s) => s.id == entry.key))
        invalid('Gym setup note names an unknown slot.');
      if (entry.value.trim().isEmpty || entry.value.length > 4000)
        invalid('Gym setup notes are nonempty, at most 4000 characters.');
    }
    checkOffsetMinutes(startOffsetMinutes, 'startedAt');
    checkOffsetMinutes(finishOffsetMinutes, 'finishedAt');
    if (finishedAt == null && finishOffsetMinutes != 0)
      invalid('An unfinished session has no finish offset.');
    if (endedAt != null &&
        (finishedAt == null ||
            endedAt!.isBefore(startedAt) ||
            endedAt!.isAfter(finishedAt!)))
      invalid('Training must end between the session start and finish.');
    definition = revision.definition.resolveVariants(this.variantSelections);
    final expected = [
      for (final o in definition.plan.occurrences())
        if (o.activity is Effort) o.id,
    ];
    if (expected.length != sets.length ||
        [
          for (var i = 0; i < expected.length; i++) expected[i] == sets[i].id,
        ].contains(false))
      invalid('Session sets do not match its resolved plan.');
    var lastExtra = 0;
    for (final extra in this.extraSets) {
      lastExtra = _validateExtra(extra, lastExtra);
    }
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
      if (set.performedOn case final used?) {
        requireSameEquipment(
          used.snapshot,
          revision.definition.slot(set.slotId).equipmentId,
        );
      }
      final arrangement = set.loadArrangement;
      if (arrangement == null) continue;
      final instance = instanceOf(set);
      if (instance == null)
        invalid('A plate arrangement requires a frozen session load binding.');
      if (arrangement.instanceId != instance.instanceId)
        invalid('Plate arrangement instance identity is inconsistent.');
      if (instance.snapshot.loading == null)
        invalid(
          'A plate arrangement requires an instance with declared loading.',
        );
      arrangement.validateAgainst(
        set.availableLoading ?? instance.snapshot.loading!,
      );
    }
  }

  /// The instance [set] is performed on: its own [TrainingSet.performedOn],
  /// else the session's frozen binding for its slot, if any.
  LoadInstanceReference? instanceOf(TrainingSet set) =>
      set.performedOn ?? loadInputs[set.slotId]?.instance;
  final String id;
  final WorkoutRevision revision;

  /// The gym the session was started at, when one was selected. It records
  /// where the work happened; instance bindings stay per slot.
  final String? gymId;

  /// The gym's setup notes frozen at start, per slot (from the gym's notes
  /// for each slot's exercise). Shown alongside the slot's own note; they
  /// never change history contexts.
  final Map<String, String> gymSetupNotes;

  /// Frozen variant selections (variant ID → branch value) chosen at start.
  final Map<String, String> variantSelections;

  /// The pinned revision's definition resolved under [variantSelections]:
  /// the plan this session actually expands. Equal to the revision's own
  /// definition when the workout declares no variants.
  late final WorkoutDefinition definition;
  final DateTime startedAt;
  final DateTime? finishedAt;

  /// UTC offsets the start/finish were entered with, in minutes east of UTC.
  /// The instants stay authoritative for ordering; offsets keep the local
  /// wall-clock time of the workout.
  final int startOffsetMinutes, finishOffsetMinutes;

  /// When training actually ended, if the session was finalized later (an
  /// evening workout closed the next morning). Elapsed time runs to it.
  final DateTime? endedAt;

  /// The end of the training itself: [endedAt], else [finishedAt].
  DateTime? get trainingEndedAt => endedAt ?? finishedAt;

  /// [startedAt]/[finishedAt] in the local time they were entered with.
  String get startedAtText => formatInstant(startedAt, startOffsetMinutes);
  String? get finishedAtText => finishedAt == null
      ? null
      : formatInstant(finishedAt!, finishOffsetMinutes);
  final List<TrainingSet> sets;

  /// Sets logged outside the plan (a starting-weight ramp, an extra
  /// back-off set), in the order they were added. They count in summaries,
  /// series and records, but never in progression, prefill or traversal,
  /// which read [sets] only.
  final List<TrainingSet> extraSets;

  /// Planned sets followed by unplanned ones.
  List<TrainingSet> get allSets => [...sets, ...extraSets];

  /// An unplanned set is a completed result of one slot: ID `extra-<n>`
  /// with n strictly increasing (removed sets leave gaps), actuals only, no
  /// plan-derived state. Returns n.
  int _validateExtra(TrainingSet set, int previous) {
    final n = int.tryParse(set.id.replaceFirst('extra-', ''));
    if (!set.id.startsWith('extra-') ||
        n == null ||
        n <= previous ||
        set.id != 'extra-$n')
      invalid('Unplanned sets are numbered extra-1, extra-2, ... in order.');
    final slot = definition.slots.where((s) => s.id == set.slotId).firstOrNull;
    if (slot == null) invalid('Unplanned set ${set.id} names an unknown slot.');
    if (!const {'work', 'warmup', 'backoff', 'drop'}.contains(set.role))
      invalid('Unknown role for unplanned set ${set.id}.');
    if (set.status != SetStatus.completed || set.actuals.isEmpty)
      invalid('An unplanned set records completed actuals.');
    if (set.suggested.isNotEmpty ||
        set.sources.isNotEmpty ||
        set.manualTargets.isNotEmpty ||
        set.timing != null ||
        set.loadArrangement != null ||
        set.performedOn != null ||
        set.substitution != null ||
        set.criteria.isNotEmpty ||
        set.maxEffortMetrics.isNotEmpty ||
        set.actualSettings.isNotEmpty)
      invalid(
        'An unplanned set carries only actuals, settings and observations.',
      );
    for (final entry in set.actuals.entries) {
      final target = slot.targets[entry.key];
      if (target != null && target.dimension != entry.value.dimension)
        invalid('Unplanned ${entry.key} has another dimension than its slot.');
    }
    if (set.settings.isNotEmpty || slot.categories.isNotEmpty)
      validateCategoricalSettings(
        set.settings,
        slot.categories,
        'Unplanned set ${set.id}',
      );
    return n;
  }

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
    if (!allSets.any((s) => s.id == updated.id))
      throw BodyTmiException('not_found', 'Unknown set: ${updated.id}.');
    return TrainingSession(
      id: id,
      revision: revision,
      startedAt: startedAt,
      startOffsetMinutes: startOffsetMinutes,
      sets: [for (final set in sets) set.id == updated.id ? updated : set],
      extraSets: [
        for (final set in extraSets) set.id == updated.id ? updated : set,
      ],
      status: status,
      finishedAt: finishedAt,
      finishOffsetMinutes: finishOffsetMinutes,
      endedAt: endedAt,
      contentVersion: contentVersion + 1,
      bodyMassInputs: bodyMassInputs,
      loadInputs: loadInputs,
      initialBodyMassOverrides: initialBodyMassOverrides,
      derivedPlanInput: derivedPlanInput,
      prescriptionOverrides: prescriptionOverrides,
      variantSelections: variantSelections,
      gymId: gymId,
      gymSetupNotes: gymSetupNotes,
    );
  }

  TrainingSession finish(
    DateTime at, {
    int offsetMinutes = 0,
    DateTime? endedAt,
  }) {
    if (status == SessionStatus.finalized) return this;
    if (at.isBefore(startedAt))
      invalid('Finish time cannot precede start time.');
    if (sets.any((set) => set.status == SetStatus.planned))
      invalid('Complete or explicitly skip every set before finishing.');
    return TrainingSession(
      id: id,
      revision: revision,
      startedAt: startedAt,
      startOffsetMinutes: startOffsetMinutes,
      sets: sets,
      extraSets: extraSets,
      bodyMassInputs: bodyMassInputs,
      loadInputs: loadInputs,
      initialBodyMassOverrides: initialBodyMassOverrides,
      derivedPlanInput: derivedPlanInput,
      prescriptionOverrides: prescriptionOverrides,
      status: SessionStatus.finalized,
      finishedAt: at,
      finishOffsetMinutes: offsetMinutes,
      endedAt: endedAt,
      contentVersion: contentVersion + 1,
      variantSelections: variantSelections,
      gymId: gymId,
      gymSetupNotes: gymSetupNotes,
    );
  }

  TrainingSet set(String id) {
    for (final set in allSets) {
      if (set.id == id) return set;
    }
    throw BodyTmiException('not_found', 'Unknown set: $id.');
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'id': id,
    'revision': revision.toJson(),
    'startedAt': startedAtText,
    if (finishedAt != null) 'finishedAt': finishedAtText,
    if (endedAt != null)
      'endedAt': formatInstant(endedAt!, finishOffsetMinutes),
    'status': status.name,
    'contentVersion': contentVersion,
    if (gymId != null) 'gym': gymId,
    if (gymSetupNotes.isNotEmpty) 'gymSetupNotes': gymSetupNotes,
    if (variantSelections.isNotEmpty) 'variantSelections': variantSelections,
    'sets': [
      for (final set in sets)
        {
          ...set.toJson(),
          if (definition.effortSide(set.id) case final side?) 'side': side,
        },
    ],
    if (extraSets.isNotEmpty)
      'extraSets': [for (final set in extraSets) set.toJson()],
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
