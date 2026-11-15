import 'package:bodytmi_core/bodytmi_core.dart';
import 'canonical_json.dart';

final class TrainingService {
  const TrainingService();

  TrainingSession start({
    required String sessionId,
    required WorkoutRevision revision,
    required DateTime startedAt,
    List<TrainingSession> history = const [],
    List<BodyMassMeasurement> bodyMassMeasurements = const [],
    Map<String, BodyMassOverride> bodyMassOverrides = const {},
    Map<String, LoadInstanceReference> loadInstances = const {},
    Map<String, LoadConvention> loadConventions = const {},
    Map<String, Map<String, String>> progressedSettings = const {},
    Map<String, String>? variantSelections,
  }) {
    identifier({'id': sessionId}, 'id');
    // Variants resolve once: explicit selections, else each lever's default.
    final selections =
        variantSelections ?? revision.definition.variantSelections();
    final definition = revision.definition.resolveVariants(selections);
    if (bodyMassOverrides.keys.any(
      (id) => !revision.definition.slots.any(
        (s) => s.id == id && s.bodyMass != null,
      ),
    ))
      invalid('Body-mass override names an unconfigured slot.');
    for (final id in {...loadInstances.keys, ...loadConventions.keys}) {
      if (!revision.definition.slots.any((s) => s.id == id))
        invalid('Load binding names an unknown slot.');
    }
    for (final entry in loadInstances.entries) {
      final slot = revision.definition.slot(entry.key);
      if (slot.equipmentId != null &&
          slot.equipmentId != entry.value.snapshot.equipmentId)
        invalid(
          'Equipment instance ${entry.value.instanceId} belongs to '
          '${entry.value.snapshot.equipmentId}, not the equipment declared '
          'by slot ${entry.key}.',
        );
    }
    final loadInputs = <String, LoadInputSnapshot>{};
    for (final slot in revision.definition.slots) {
      final snapshot = LoadInputSnapshot.capture(
        sessionConvention: loadConventions[slot.id],
        slotConvention: slot.convention,
        instance: loadInstances[slot.id],
      );
      if (!snapshot.isTrivial) loadInputs[slot.id] = snapshot;
    }
    final massInputs = {
      for (final slot in revision.definition.slots)
        if (slot.bodyMass != null)
          slot.id: BodyMassInputSnapshot.capture(
            selection: slot.bodyMass!,
            asOf: startedAt,
            measurements: bodyMassMeasurements,
            override: bodyMassOverrides[slot.id],
          ),
    };
    if (history.any((s) => s.id == sessionId))
      invalid('Session ID already occurs in supplied history.');
    final compatibleHistory =
        history
            .where(
              (s) =>
                  s.status == SessionStatus.finalized &&
                  s.definition.id == revision.definition.id &&
                  s.startedAt.isBefore(startedAt) &&
                  s.finishedAt != null &&
                  !s.finishedAt!.isAfter(startedAt),
            )
            .toList()
          ..sort((a, b) {
            final date = b.startedAt.compareTo(a.startedAt);
            return date == 0 ? a.id.compareTo(b.id) : date;
          });
    final ordinals = <String, int>{};
    final sets = <TrainingSet>[];
    for (final occurrence in definition.plan.occurrences()) {
      final effort = occurrence.activity;
      if (effort is! Effort) continue;
      final slot = definition.slot(effort.slotId);
      final ordinalKey = '${slot.id}:${effort.role}';
      final ordinal = ordinals.update(
        ordinalKey,
        (v) => v + 1,
        ifAbsent: () => 0,
      );
      final suggested = <String, Quantity>{
        ...effort.resolveTargets(slot.targets),
      };
      // Progressed categorical levels replace their levers' planned values,
      // before prefill, so history only seeds the settings actually planned.
      final planned = sortedSettings({
        ...definition.plannedSettings(occurrence.id),
        ...?progressedSettings[occurrence.id],
      });
      validateCategoricalSettings(
        planned,
        slot.categories,
        'Progressed set ${occurrence.id}',
      );
      final sources = <String, HistorySource>{};
      if (effort.role != 'warmup') {
        for (final metric in slot.prefillMetrics) {
          if (effort.targets.containsKey(metric) ||
              effort.maxEffortMetrics.contains(metric) ||
              effort.criteria[metric]?.mode == 'observe')
            continue;
          search:
          for (final past in compatibleHistory) {
            final oldSlots = past.definition.slots.where(
              (s) => slot.compatibleWith(s),
            );
            if (oldSlots.isEmpty) continue;
            for (final set in past.sets) {
              final value = set.actuals[metric];
              if (set.slotId == slot.id &&
                  set.substitution == null &&
                  set.role == effort.role &&
                  past.definition.effortSide(set.id) == effort.side &&
                  // Categorical settings (grip, hand count...) are separate
                  // contexts: only results performed the same way prefill.
                  canonicalJson(set.performedSettings) ==
                      canonicalJson(planned) &&
                  set.ordinal == ordinal &&
                  set.eligibleForPerformance &&
                  !set.maxEffortMetrics.contains(metric) &&
                  set.criteria[metric]?.mode != 'observe' &&
                  // A phase override (deload, taper...) prescribed this
                  // result; it stays in its phase rather than seeding
                  // ordinary history prefill.
                  !past.prescriptionOverrides.any(
                    (r) =>
                        r.metric == metric &&
                        r.applied.any((a) => a.setId == set.id),
                  ) &&
                  value != null &&
                  value.dimension == suggested[metric]!.dimension) {
                suggested[metric] = value;
                sources[metric] = HistorySource(
                  past.id,
                  set.id,
                  set.contentVersion,
                );
                break search;
              }
            }
          }
        }
      }
      sets.add(
        TrainingSet(
          id: occurrence.id,
          slotId: slot.id,
          role: effort.role,
          ordinal: ordinal,
          suggested: suggested,
          sources: sources,
          maxEffortMetrics: effort.maxEffortMetrics,
          criteria: effort.criteria,
          settings: planned,
          actualSettings: const {},
        ),
      );
    }
    return TrainingSession(
      id: sessionId,
      revision: revision,
      startedAt: startedAt,
      sets: sets,
      bodyMassInputs: massInputs,
      loadInputs: loadInputs,
      variantSelections: selections,
    );
  }

  /// Explicitly recapture slot mass inputs at the original session cutoff.
  TrainingSession refreshBodyMass(
    TrainingSession session,
    List<BodyMassMeasurement> measurements, {
    required bool confirm,
  }) {
    if (!confirm) invalid('Refreshing body mass requires confirm:true.');
    if (session.status != SessionStatus.active ||
        session.sets.any((set) => set.status != SetStatus.planned)) {
      invalid(
        'Body mass can only be refreshed before any effort is completed or skipped.',
      );
    }
    if (session.bodyMassInputs.isEmpty)
      invalid('Session has no configured body mass inputs.');
    final refreshed = <String, BodyMassInputSnapshot>{
      for (final entry in session.bodyMassInputs.entries)
        entry.key: BodyMassInputSnapshot.capture(
          selection: entry.value.selection,
          asOf: session.startedAt,
          measurements: measurements,
          override: entry.value.override,
        ),
    };
    if (canonicalJson({
          for (final e in refreshed.entries) e.key: e.value.toJson(),
        }) ==
        canonicalJson({
          for (final e in session.bodyMassInputs.entries)
            e.key: e.value.toJson(),
        }))
      return session;
    return TrainingSession(
      id: session.id,
      revision: session.revision,
      variantSelections: session.variantSelections,
      startedAt: session.startedAt,
      sets: session.sets,
      status: session.status,
      finishedAt: session.finishedAt,
      contentVersion: session.contentVersion + 1,
      bodyMassInputs: refreshed,
      loadInputs: session.loadInputs,
      initialBodyMassOverrides: session.initialBodyMassOverrides,
      derivedPlanInput: session.derivedPlanInput,
      prescriptionOverrides: session.prescriptionOverrides,
    );
  }

  /// Replace explicitly selected slot overrides while retaining start identity.
  TrainingSession rebindBodyMass(
    TrainingSession session,
    List<BodyMassMeasurement> measurements,
    Map<String, BodyMassOverride?> updates, {
    required bool confirm,
  }) {
    if (!confirm) invalid('Rebinding body mass requires confirm:true.');
    if (session.status != SessionStatus.active ||
        session.sets.any((set) => set.status != SetStatus.planned)) {
      invalid(
        'Body mass can only be rebound before any effort is completed or skipped.',
      );
    }
    if (updates.isEmpty ||
        updates.keys.any((id) => !session.bodyMassInputs.containsKey(id)))
      invalid('Rebinding requires configured body-mass slot IDs.');
    final changedOverride = updates.entries.any(
      (entry) => !session.bodyMassInputs[entry.key]!.sameOverride(entry.value),
    );
    final original =
        session.initialBodyMassOverrides ??
        (changedOverride
            ? {
                for (final entry in session.bodyMassInputs.entries)
                  if (entry.value.override != null)
                    entry.key: entry.value.override!,
              }
            : null);
    final inputs = <String, BodyMassInputSnapshot>{
      for (final entry in session.bodyMassInputs.entries)
        entry.key: updates.containsKey(entry.key)
            ? BodyMassInputSnapshot.capture(
                selection: entry.value.selection,
                asOf: session.startedAt,
                measurements: measurements,
                override: updates[entry.key],
              )
            : entry.value,
    };
    if (canonicalJson({
              for (final e in inputs.entries) e.key: e.value.toJson(),
            }) ==
            canonicalJson({
              for (final e in session.bodyMassInputs.entries)
                e.key: e.value.toJson(),
            }) &&
        (original == null) == (session.initialBodyMassOverrides == null))
      return session;
    return TrainingSession(
      id: session.id,
      revision: session.revision,
      variantSelections: session.variantSelections,
      startedAt: session.startedAt,
      sets: session.sets,
      status: session.status,
      finishedAt: session.finishedAt,
      contentVersion: session.contentVersion + 1,
      bodyMassInputs: inputs,
      loadInputs: session.loadInputs,
      initialBodyMassOverrides: original,
      derivedPlanInput: session.derivedPlanInput,
      prescriptionOverrides: session.prescriptionOverrides,
    );
  }

  Map<String, Object?> bodyMassStatus(
    TrainingSession session,
    List<BodyMassMeasurement> measurements,
  ) => {
    'sessionId': session.id,
    'contentVersion': session.contentVersion,
    'inputs': {
      for (final e in session.bodyMassInputs.entries)
        e.key: {
          'captured': e.value.resolution.toJson(),
          ...e.value.freshness(measurements),
        },
    },
  };

  /// Assess supplied criteria against current confirmed actuals without editing them.
  Map<String, Object?> assessObjectives(
    TrainingSession session,
    String setId,
    Object? objectives,
  ) {
    final set = session.set(setId);
    return {
      'source': {
        'sessionId': session.id,
        'sessionContentVersion': session.contentVersion,
        'templateId': session.definition.id,
        'revision': session.revision.number,
        'setId': set.id,
        'setContentVersion': set.contentVersion,
        'slotId': set.slotId,
        'role': set.role,
        'ordinal': set.ordinal,
        'sessionStatus': session.status.name,
        'setStatus': set.status.name,
        'interrupted': set.observations?.interrupted ?? false,
        if (set.maxEffortMetrics.isNotEmpty || set.criteria.isNotEmpty)
          'authoredObjectives': set.objectivesJson,
      },
      ...const ObjectiveAssessment().evaluate(objectives, set.actuals),
    };
  }

  TrainingSession complete(
    TrainingSession session,
    String setId,
    Metrics actuals, {
    bool acceptSuggested = false,
  }) => session.replaceSet(
    session.set(setId).complete(actuals, acceptSuggested: acceptSuggested),
  );

  /// Complete an effort and optionally replace its explicit observations.
  TrainingSession completeWithObservations(
    TrainingSession session,
    String setId,
    Metrics actuals, {
    bool acceptSuggested = false,
    SetObservations? observations,
  }) {
    if (observations?.isEmpty == true)
      invalid('Provide nonempty observations or omit them.');
    final completed = complete(
      session,
      setId,
      actuals,
      acceptSuggested: acceptSuggested,
    );
    return observations == null
        ? completed
        : annotate(completed, setId, observations);
  }

  TrainingSession annotate(
    TrainingSession session,
    String setId,
    SetObservations observations, {
    bool confirm = false,
  }) => session.replaceSet(
    session.set(setId).annotate(observations, confirm: confirm),
  );

  /// Records which categorical values a completed set was actually performed
  /// with. [performed] replaces the record: levers it omits count as planned,
  /// and an empty map clears it. A difference from plan makes the exposure
  /// review-only for progression and a separate history context.
  TrainingSession recordSettings(
    TrainingSession session,
    String setId,
    Map<String, String> performed,
  ) {
    final set = session.set(setId);
    if (set.status != SetStatus.completed)
      invalid('Actual categorical settings record only for completed sets.');
    validateCategoricalSettings(
      performed,
      session.definition.slot(set.slotId).categories,
      'Set $setId',
    );
    return session.replaceSet(set.withActualSettings(performed));
  }

  /// Records or clears the exact plate stack one completed set used. The
  /// arrangement must reference the session's frozen instance binding and is
  /// validated against that pinned revision's declared loading before it is
  /// stored; later instance revisions never invalidate the recorded stack.
  TrainingSession arrange(
    TrainingSession session,
    String setId,
    LoadArrangement? arrangement, {
    bool confirm = false,
  }) {
    if (arrangement == null &&
        session.set(setId).loadArrangement != null &&
        !confirm)
      invalid('Confirm before clearing a recorded plate arrangement.');
    if (arrangement != null) {
      final instance = session.loadInputs[session.set(setId).slotId]?.instance;
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
    return session.replaceSet(session.set(setId).arrange(arrangement));
  }

  /// Edit one planned suggestion and optionally carry it to compatible later sets.
  TrainingSession editTarget(
    TrainingSession session,
    String setId,
    String metric,
    Quantity value, {
    bool applyToRemaining = false,
  }) {
    if (session.status != SessionStatus.active) {
      invalid('Targets can only be edited in an active session.');
    }
    identifier({'metric': metric}, 'metric');
    final selected = session.set(setId);
    if (selected.status != SetStatus.planned) {
      invalid('Only planned effort targets can be edited.');
    }
    final old = selected.suggested[metric];
    if (old == null || old.dimension != value.dimension) {
      invalid('Target must match an existing suggestion and its dimension.');
    }
    return _applyTarget(
      session,
      selected,
      metric,
      value,
      includeSelected: true,
      applyToRemaining: applyToRemaining,
    );
  }

  /// Explicitly carry one confirmed actual into untouched later suggestions.
  TrainingSession carryActual(
    TrainingSession session,
    String setId,
    String metric,
  ) {
    if (session.status != SessionStatus.active) {
      invalid('Actuals can only be carried in an active session.');
    }
    identifier({'metric': metric}, 'metric');
    final source = session.set(setId);
    if (source.status != SetStatus.completed) {
      invalid('Carry requires a completed effort.');
    }
    final actual = source.actuals[metric];
    if (actual == null)
      invalid('The completed effort has no actual for this metric.');
    return _applyTarget(
      session,
      source,
      metric,
      actual,
      includeSelected: false,
      applyToRemaining: true,
    );
  }

  TrainingSession _applyTarget(
    TrainingSession session,
    TrainingSet selected,
    String metric,
    Quantity value, {
    required bool includeSelected,
    required bool applyToRemaining,
  }) {
    final occurrences = {
      for (final occurrence in session.definition.plan.occurrences())
        if (occurrence.activity is Effort)
          occurrence.id: occurrence.activity as Effort,
    };
    final derived = <String>{};
    final input = session.derivedPlanInput;
    if (input != null) {
      final plan = DerivedWorkoutPlan.fromJson(input.snapshot['plan']);
      for (final binding in plan.bindings) {
        if (binding['metric'] == metric) {
          derived.add(binding['occurrenceId']! as String);
        }
      }
    }
    if (includeSelected && derived.contains(selected.id)) {
      invalid('A derived plan target must be changed through plan refresh.');
    }
    final sourceIndex = session.sets.indexWhere((set) => set.id == selected.id);
    var changed = false;
    final sets = <TrainingSet>[];
    for (var i = 0; i < session.sets.length; i++) {
      final set = session.sets[i];
      final eligible =
          (includeSelected && i == sourceIndex) ||
          (applyToRemaining &&
              i > sourceIndex &&
              set.slotId == selected.slotId &&
              set.role == selected.role &&
              set.status == SetStatus.planned &&
              set.suggested[metric]?.dimension == value.dimension &&
              !set.manualTargets.contains(metric) &&
              !derived.contains(set.id) &&
              !occurrences[set.id]!.targets.containsKey(metric) &&
              !occurrences[set.id]!.criteria.containsKey(metric));
      if (!eligible ||
          (set.manualTargets.contains(metric) &&
              (!includeSelected || !set.carriedTargets.containsKey(metric)) &&
              canonicalJson(set.suggested[metric]!.toJson()) ==
                  canonicalJson(value.toJson()))) {
        sets.add(set);
        continue;
      }
      final suggested = {...set.suggested, metric: value};
      session.definition.slot(set.slotId).timing?.resolve(suggested);
      sets.add(
        TrainingSet(
          id: set.id,
          slotId: set.slotId,
          role: set.role,
          ordinal: set.ordinal,
          settings: set.settings,
          actualSettings: set.actualSettings,
          suggested: suggested,
          sources: {
            for (final e in set.sources.entries)
              if (e.key != metric) e.key: e.value,
          },
          manualTargets: {...set.manualTargets, metric},
          carriedTargets: {
            for (final e in set.carriedTargets.entries)
              if (e.key != metric) e.key: e.value,
            if (!includeSelected)
              metric: CarriedTargetSource(selected.id, selected.contentVersion),
          },
          substitution: set.substitution,
          status: set.status,
          actuals: set.actuals,
          timing: set.timing,
          observations: set.observations,
          maxEffortMetrics: set.maxEffortMetrics,
          criteria: set.criteria,
          contentVersion: set.contentVersion + 1,
        ),
      );
      changed = true;
    }
    if (!changed) return session;
    return TrainingSession(
      id: session.id,
      revision: session.revision,
      variantSelections: session.variantSelections,
      startedAt: session.startedAt,
      sets: sets,
      status: session.status,
      finishedAt: session.finishedAt,
      contentVersion: session.contentVersion + 1,
      bodyMassInputs: session.bodyMassInputs,
      loadInputs: session.loadInputs,
      initialBodyMassOverrides: session.initialBodyMassOverrides,
      derivedPlanInput: session.derivedPlanInput,
      prescriptionOverrides: session.prescriptionOverrides,
    );
  }

  /// Skip only planned efforts; confirmed results and prior skips stay intact.
  TrainingSession skipRemaining(
    TrainingSession session, {
    required bool confirm,
  }) => _skipPlanned(session, (_) => true, confirm: confirm);

  /// Skip a specified set of planned occurrences without changing other results.
  TrainingSession skipOccurrences(
    TrainingSession session,
    Set<String> occurrenceIds, {
    required bool confirm,
  }) {
    final known = session.sets.map((set) => set.id).toSet();
    if (!known.containsAll(occurrenceIds))
      invalid('Unknown effort occurrence.');
    return _skipPlanned(
      session,
      (set) => occurrenceIds.contains(set.id),
      confirm: confirm,
    );
  }

  /// Skip planned efforts in a slot, optionally limited to one effort role.
  TrainingSession skipSlot(
    TrainingSession session,
    String slotId, {
    String? role,
    required bool confirm,
  }) {
    identifier({'slotId': slotId}, 'slotId');
    if (!session.definition.slots.any((slot) => slot.id == slotId)) {
      invalid('Unknown workout slot: $slotId.');
    }
    if (role != null && !effortRoles.contains(role)) {
      invalid('Unknown effort role.');
    }
    return _skipPlanned(
      session,
      (set) => set.slotId == slotId && (role == null || set.role == role),
      confirm: confirm,
    );
  }

  TrainingSession _skipPlanned(
    TrainingSession session,
    bool Function(TrainingSet) selected, {
    required bool confirm,
  }) {
    if (!confirm) invalid('Skipping remaining efforts requires confirm:true.');
    if (session.status != SessionStatus.active)
      invalid('Remaining efforts can only be skipped in an active session.');
    if (!session.sets.any(
      (set) => set.status == SetStatus.planned && selected(set),
    ))
      return session;
    return TrainingSession(
      id: session.id,
      revision: session.revision,
      variantSelections: session.variantSelections,
      startedAt: session.startedAt,
      sets: [
        for (final set in session.sets)
          set.status == SetStatus.planned && selected(set)
              ? set.skip(confirm: true)
              : set,
      ],
      bodyMassInputs: session.bodyMassInputs,
      loadInputs: session.loadInputs,
      initialBodyMassOverrides: session.initialBodyMassOverrides,
      derivedPlanInput: session.derivedPlanInput,
      prescriptionOverrides: session.prescriptionOverrides,
      status: session.status,
      finishedAt: session.finishedAt,
      contentVersion: session.contentVersion + 1,
    );
  }

  TrainingSession skip(
    TrainingSession session,
    String setId, {
    bool confirm = false,
  }) => session.replaceSet(session.set(setId).skip(confirm: confirm));

  /// Planned sets a substitution or revert addresses: exactly one occurrence,
  /// or every remaining planned set of the slot.
  List<TrainingSet> _scope(
    TrainingSession session,
    String slotId,
    String scope,
    String? setId,
  ) {
    identifier({'slotId': slotId}, 'slotId');
    if (!session.definition.slots.any((s) => s.id == slotId))
      invalid('Unknown workout slot: $slotId.');
    if (session.status != SessionStatus.active)
      invalid('Substitution needs an active session.');
    switch (scope) {
      case 'occurrence':
        if (setId == null) invalid('An occurrence substitution needs setId.');
        final set = session.set(setId);
        if (set.slotId != slotId) invalid('The set belongs to another slot.');
        if (set.status != SetStatus.planned)
          invalid('Only a planned set can be substituted.');
        return [set];
      case 'remaining':
        if (setId != null) invalid('A remaining substitution takes no setId.');
        final sets = [
          for (final set in session.sets)
            if (set.slotId == slotId && set.status == SetStatus.planned) set,
        ];
        if (sets.isEmpty) invalid('The slot has no remaining planned sets.');
        return sets;
      default:
        invalid('scope must be occurrence or remaining.');
    }
  }

  /// Temporary substitution (policy bodytmi-substitution/1). Each target
  /// metric resolves from `keep` (the slot's planned value), `history` (the
  /// latest finished result for the same template, slot, role, ordinal and
  /// replacement composition) or `explicit`; anything else stays unresolved
  /// with a reason, so an original implementation's value is never
  /// inherited silently. Unlisted metrics default to `history`.
  TrainingSession substitute(
    TrainingSession session, {
    required String slotId,
    required String scope,
    String? setId,
    required SubstituteComposition composition,
    Map<String, Map<String, Object?>> targets = const {},
    List<TrainingSession> history = const [],
  }) {
    final slot = session.definition.slot(slotId);
    if (composition.sameAs(
      exerciseId: slot.exerciseId,
      implementation: slot.implementation,
      equipmentId: slot.equipmentId,
      setupNote: slot.setupNote,
    ))
      invalid('The replacement equals the slot composition; revert instead.');
    final selected = _scope(session, slotId, scope, setId);
    final input = session.derivedPlanInput;
    if (input != null) {
      final plan = DerivedWorkoutPlan.fromJson(input.snapshot['plan']);
      final mapped = {for (final b in plan.bindings) b['occurrenceId']};
      if (selected.any((set) => mapped.contains(set.id)))
        invalid('Sets with derived plan targets cannot be substituted.');
    }
    for (final metric in targets.keys) {
      if (!selected.any((set) => set.suggested.containsKey(metric)))
        invalid('Substitution target $metric is not planned for these sets.');
    }
    final past =
        history
            .where(
              (h) =>
                  h.status == SessionStatus.finalized &&
                  h.id != session.id &&
                  h.definition.id == session.definition.id &&
                  h.startedAt.isBefore(session.startedAt),
            )
            .toList()
          ..sort((a, b) {
            final date = b.startedAt.compareTo(a.startedAt);
            return date == 0 ? a.id.compareTo(b.id) : date;
          });
    final replaced = <String, TrainingSet>{};
    for (final set in selected) {
      // Re-substituting keeps the original prior planned state.
      final original = set.substitution;
      final originalSuggested = original?.originalSuggested ?? set.suggested;
      final suggested = <String, Quantity>{};
      final resolved = <String, SubstitutionTarget>{};
      for (final entry in originalSuggested.entries) {
        final metric = entry.key;
        final dimension = entry.value.dimension;
        final request = targets[metric] ?? const {'source': 'history'};
        checkKeys(request, {'source', 'value'});
        final source = requiredString(request, 'source');
        switch (source) {
          case 'keep':
            if (request.containsKey('value'))
              invalid('A keep target takes no value.');
            suggested[metric] = entry.value;
            resolved[metric] = SubstitutionTarget.keep(dimension);
          case 'explicit':
            final value = Quantity.fromJson(request['value']);
            if (value.dimension != dimension)
              invalid('Explicit $metric has another dimension.');
            suggested[metric] = value;
            resolved[metric] = SubstitutionTarget.explicit(dimension);
          case 'history':
            if (request.containsKey('value'))
              invalid('A history target takes no value.');
            TrainingSet? found;
            TrainingSession? foundSession;
            search:
            for (final h in past) {
              for (final old in h.sets) {
                final value = old.actuals[metric];
                if (old.slotId == slotId &&
                    old.role == set.role &&
                    old.ordinal == set.ordinal &&
                    old.substitution?.composition == composition &&
                    old.eligibleForPerformance &&
                    value != null &&
                    value.dimension == dimension) {
                  found = old;
                  foundSession = h;
                  break search;
                }
              }
            }
            if (found == null) {
              resolved[metric] = SubstitutionTarget.unresolved(
                dimension,
                'No finished result for this slot with the replacement '
                'composition; supply an explicit value or actual.',
              );
            } else {
              suggested[metric] = found.actuals[metric]!;
              resolved[metric] = SubstitutionTarget.history(
                dimension,
                foundSession!.id,
                found.id,
                found.contentVersion,
              );
            }
          default:
            invalid(
              'Substitution target source must be keep, history or explicit.',
            );
        }
      }
      replaced[set.id] = TrainingSet(
        id: set.id,
        slotId: set.slotId,
        role: set.role,
        ordinal: set.ordinal,
        settings: set.settings,
        actualSettings: set.actualSettings,
        suggested: suggested,
        status: set.status,
        observations: set.observations,
        maxEffortMetrics: set.maxEffortMetrics,
        criteria: set.criteria,
        contentVersion: set.contentVersion + 1,
        substitution: SetSubstitution(
          composition: composition,
          scope: scope,
          targets: resolved,
          originalSuggested: originalSuggested,
          originalSources:
              original?.originalSources ??
              {for (final e in set.sources.entries) e.key: e.value.toJson()},
          originalManualTargets:
              original?.originalManualTargets ?? set.manualTargets,
        ),
      );
    }
    return _withSets(session, replaced);
  }

  /// Restores substituted planned sets to their exact prior planned state.
  TrainingSession revertSubstitution(
    TrainingSession session, {
    required String slotId,
    required String scope,
    String? setId,
  }) {
    final selected = [
      for (final set in _scope(session, slotId, scope, setId))
        if (set.substitution != null) set,
    ];
    if (selected.isEmpty) invalid('No substituted planned sets in scope.');
    final replaced = <String, TrainingSet>{};
    for (final set in selected) {
      final original = set.substitution!;
      replaced[set.id] = TrainingSet(
        id: set.id,
        slotId: set.slotId,
        role: set.role,
        ordinal: set.ordinal,
        settings: set.settings,
        actualSettings: set.actualSettings,
        suggested: original.originalSuggested,
        sources: {
          for (final e in original.originalSources.entries)
            e.key: () {
              final h = jsonObject(e.value, 'history source');
              return HistorySource(
                identifier(h, 'sessionId'),
                requiredString(h, 'setId'),
                h['contentVersion']! as int,
              );
            }(),
        },
        manualTargets: original.originalManualTargets,
        status: set.status,
        observations: set.observations,
        maxEffortMetrics: set.maxEffortMetrics,
        criteria: set.criteria,
        contentVersion: set.contentVersion + 1,
      );
    }
    return _withSets(session, replaced);
  }

  TrainingSession _withSets(
    TrainingSession session,
    Map<String, TrainingSet> replaced,
  ) => TrainingSession(
    id: session.id,
    revision: session.revision,
    variantSelections: session.variantSelections,
    startedAt: session.startedAt,
    sets: [for (final set in session.sets) replaced[set.id] ?? set],
    bodyMassInputs: session.bodyMassInputs,
    loadInputs: session.loadInputs,
    initialBodyMassOverrides: session.initialBodyMassOverrides,
    derivedPlanInput: session.derivedPlanInput,
    prescriptionOverrides: session.prescriptionOverrides,
    status: session.status,
    finishedAt: session.finishedAt,
    contentVersion: session.contentVersion + 1,
  );
}
