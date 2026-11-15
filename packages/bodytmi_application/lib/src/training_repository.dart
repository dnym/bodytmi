import 'package:bodytmi_core/bodytmi_core.dart';
import 'training_service.dart';
import 'session_codec.dart';
import 'training_archive.dart';
import 'progression_decision.dart';
import 'progression_anchor.dart';
import 'progression_reconciliation.dart';
import 'reconciliation_receipt.dart';
import 'lever_link.dart';
import 'shared_lever_application.dart';
import 'link_retirement.dart';
import 'shared_track_view.dart';
import 'program_service.dart';
import 'canonical_json.dart';
import 'stored_body_mass_service.dart';
import 'timing_service.dart';
import 'execution_service.dart';
import 'derived_workout_preview.dart';
import 'derived_plan_session.dart';
import 'window_checkpoint.dart';
import 'session_window_clock.dart';
import 'repeat_checkpoint.dart';
import 'window_repeat_execution.dart';
import 'history_import_service.dart';
import 'block_progression.dart';

/// One repository transaction is the durability boundary of each operation.
abstract interface class TrainingRepository {
  Future<T> transaction<T>(Future<T> Function() action);
  Future<WorkoutRevision?> revision(String templateId, [int? number]);
  Future<List<WorkoutRevision>> revisions();
  Future<List<FamilyRevision>> familyRevisions();
  Future<void> insertFamilyRevision(FamilyRevision revision);
  Future<List<ExerciseRevision>> exerciseRevisions();
  Future<void> insertExerciseRevision(ExerciseRevision revision);
  Future<List<ImplementationRevision>> implementationRevisions();
  Future<void> insertImplementationRevision(ImplementationRevision revision);
  Future<List<ProgressionPresetRevision>> progressionPresetRevisions();
  Future<void> insertProgressionPresetRevision(
    ProgressionPresetRevision revision,
  );
  Future<List<EquipmentRevision>> equipmentRevisions();
  Future<void> insertEquipmentRevision(EquipmentRevision revision);
  Future<List<GymRevision>> gymRevisions();
  Future<void> insertGymRevision(GymRevision revision);
  Future<List<EquipmentInstanceRevision>> equipmentInstanceRevisions();
  Future<void> insertEquipmentInstanceRevision(
    EquipmentInstanceRevision revision,
  );
  Future<List<DerivedTargetGraphRevision>> derivedTargetGraphRevisions();
  Future<void> insertDerivedTargetGraphRevision(
    DerivedTargetGraphRevision revision,
  );
  Future<List<String>> finalizationIds();
  Future<List<ProgressionDecision>> progressionDecisions();

  /// One exposure's decision by its identity (session and storage slot key).
  Future<ProgressionDecision?> progressionDecision(
    String sessionId,
    String slotKey,
  );

  /// The decisions at the highest sequence satisfying [where] among one
  /// template/slot key/run track, read newest first so older history is not
  /// decoded. Usually one decision; ties are kept for the caller's order.
  Future<List<ProgressionDecision>> latestTrackDecisions(
    String templateId,
    String slotKey,
    String? runId,
    bool Function(ProgressionDecision) where,
  );
  Future<void> saveProgressionDecision(ProgressionDecision decision);
  Future<List<ReconciliationReceipt>> progressionReconciliations();
  Future<void> saveProgressionReconciliation(ReconciliationReceipt receipt);
  Future<List<LeverLinkRevision>> leverLinkRevisions();
  Future<void> insertLeverLinkRevision(LeverLinkRevision revision);
  Future<List<SharedLeverApplication>> sharedLeverApplications();
  Future<void> insertSharedLeverApplication(SharedLeverApplication application);
  Future<List<LinkRetirementAnchor>> linkRetirements();
  Future<void> insertLinkRetirementAnchor(LinkRetirementAnchor retirement);
  Future<List<ProgramRevision>> programRevisions();
  Future<void> insertProgramRevision(ProgramRevision revision);
  Future<WorkoutExecution?> execution(String id);

  /// All executions, or only [sessionId]'s (filtered before decoding).
  Future<List<WorkoutExecution>> executions({String? sessionId});
  Future<void> saveExecution(WorkoutExecution execution);
  Future<TimingActivity?> timingActivity(String id);

  /// All clocks, or only [sessionId]'s, or only those whose ID starts with
  /// [idPrefix] (filtered before decoding; a prefix match may include
  /// extra rows, callers compare exact IDs).
  Future<List<TimingActivity>> timingActivities({
    String? sessionId,
    String? idPrefix,
  });

  /// Running or paused clocks across the profile (at most one when valid),
  /// selected without decoding every stored clock.
  Future<List<TimingActivity>> activeTimingActivities();
  Future<void> saveTimingActivity(TimingActivity timer);
  Future<RepeatCheckpoint?> repeatCheckpoint(String id);
  Future<List<RepeatCheckpoint>> repeatCheckpoints();
  Future<void> saveRepeatCheckpoint(RepeatCheckpoint checkpoint);
  Future<void> deleteRepeatCheckpoint(String id);
  Future<WindowCheckpoint?> windowCheckpoint(String id);
  Future<List<WindowCheckpoint>> windowCheckpoints();
  Future<void> saveWindowCheckpoint(WindowCheckpoint checkpoint);
  Future<void> deleteWindowCheckpoint(String id);
  Future<List<BodyMassRecord>> bodyMassRecords();
  Future<void> saveBodyMassRecord(BodyMassRecord record);
  Future<List<ImportedSessionRecord>> importedSessions();
  Future<void> saveImportedSession(ImportedSessionRecord record);
  Future<void> deleteImportedSession(String namespace, String sourceId);
  Future<List<BlockProgressionDecision>> blockProgressions();
  Future<void> saveBlockProgression(BlockProgressionDecision decision);
  Future<List<ProgramRun>> programRuns();
  Future<void> saveProgramRun(ProgramRun run);
  Future<List<SessionProgramBinding>> sessionPrograms();
  Future<void> insertSessionProgram(SessionProgramBinding binding);
  Future<List<ProgramReceipt>> programReceipts();
  Future<void> insertProgramReceipt(ProgramReceipt receipt);
  Future<List<ProgramUpgradeReceipt>> programUpgrades();
  Future<void> insertProgramUpgrade(ProgramUpgradeReceipt receipt);
  Future<void> insertRevision(WorkoutRevision revision);
  Future<TrainingSession?> session(String id);

  /// All sessions, or only those of one workout template.
  Future<List<TrainingSession>> sessions({String? templateId});
  Future<void> insertSession(TrainingSession session);
  Future<void> updateSession(TrainingSession session);
  Future<void> recordFinalization(String sessionId);
}

/// The resolved decisions that can be the latest anchor of one track
/// (template, slot, run, role), read newest first through the repository's
/// track index instead of decoding every stored decision. [where] narrows
/// further (e.g. resolved before a session start). Feed the result to
/// [latestTrack] together with the track's other anchors.
Future<List<ProgressionDecision>> trackDecisions(
  TrainingRepository repository,
  String templateId,
  ExerciseSlot slot, {
  String? runId,
  String role = 'work',
  bool Function(ProgressionDecision)? where,
}) => repository.latestTrackDecisions(
  templateId,
  role == 'work' ? slot.id : '${slot.id}/$role',
  runId,
  (d) =>
      d.resolvedAt != null &&
      d.role == role &&
      d.matches(templateId, slot) &&
      (where?.call(d) ?? true),
);

/// Read-only join of published lever links, durable shared chains,
/// retirements and resolved anchors inside one repository transaction.
Future<SharedLinkIndex> buildSharedLinkIndex(
  TrainingRepository repository,
) async {
  final revisions = await repository.leverLinkRevisions();
  final receipts = await repository.progressionReconciliations();
  final retirements = await repository.linkRetirements();
  // Without any published link there is nothing to join, so the decision
  // history need not be decoded.
  final decisions = revisions.isEmpty
      ? const <ProgressionDecision>[]
      : await repository.progressionDecisions();
  return SharedLinkIndex(
    revisions: revisions,
    applications: await repository.sharedLeverApplications(),
    retirements: retirements,
    anchors: {
      for (final anchor in <ProgressionAnchor>[
        ...decisions,
        ...receipts,
        ...retirements,
      ])
        if (anchor.resolvedAt != null) anchor.id: anchor,
    },
  );
}

final class StoredTrainingService {
  const StoredTrainingService(this.repository);
  final TrainingRepository repository;

  Future<TrainingArchive> exportArchive() => repository.transaction(
    () async => TrainingArchive(
      revisions: await repository.revisions(),
      families: await repository.familyRevisions(),
      exercises: await repository.exerciseRevisions(),
      implementations: await repository.implementationRevisions(),
      presets: await repository.progressionPresetRevisions(),
      equipment: await repository.equipmentRevisions(),
      gyms: await repository.gymRevisions(),
      instances: await repository.equipmentInstanceRevisions(),
      sessions: await repository.sessions(),
      finalizations: await repository.finalizationIds(),
      progressions: await repository.progressionDecisions(),
      programRevisions: await repository.programRevisions(),
      bodyMass: await repository.bodyMassRecords(),
      importedSessions: await repository.importedSessions(),
      blockProgressions: await repository.blockProgressions(),
      timers: await repository.timingActivities(),
      windowCheckpoints: await repository.windowCheckpoints(),
      repeatCheckpoints: await repository.repeatCheckpoints(),
      reconciliations: await repository.progressionReconciliations(),
      links: await repository.leverLinkRevisions(),
      sharedApplications: await repository.sharedLeverApplications(),
      linkRetirements: await repository.linkRetirements(),
      executions: await repository.executions(),
      programRuns: await repository.programRuns(),
      sessionPrograms: await repository.sessionPrograms(),
      programReceipts: await repository.programReceipts(),
      programUpgrades: await repository.programUpgrades(),
      graphs: await repository.derivedTargetGraphRevisions(),
    ),
  );

  Future<WorkoutRevision> publish(
    WorkoutDefinition definition,
    int expectedRevision, {
    bool requireCatalog = false,
  }) => repository.transaction(() async {
    final previous = await repository.revision(definition.id);
    if ((previous?.number ?? 0) != expectedRevision) _conflict();
    final implementations = await repository.implementationRevisions();
    final owners = implementationOwners(implementations);
    validateCatalogSlotAdoption(definition.slots, owners);
    // Every authored AMRAP loop must be startable by the repeat engine.
    for (final amrap in definition.amraps)
      const WindowRepeatExecution().start(amrap);
    if (requireCatalog) {
      final exercises = {
        for (final revision in await repository.exerciseRevisions())
          revision.exercise.id,
      };
      final equipment = {
        for (final revision in await repository.equipmentRevisions())
          revision.equipment.id,
      };
      for (final slot in definition.slots) {
        if (!exercises.contains(slot.exerciseId))
          throw BodyTmiException(
            'not_found',
            'Slot exercise ${slot.exerciseId} is not published in the catalog.',
          );
        if (owners[slot.implementation] != slot.exerciseId)
          throw BodyTmiException(
            'not_found',
            'Slot implementation ${slot.implementation} is not a published '
                'implementation of exercise ${slot.exerciseId}.',
          );
      }
      // Equipment adoption follows exercise/implementation adoption.
      for (final slot in definition.slots) {
        if (slot.equipmentId case final id? when !equipment.contains(id))
          throw BodyTmiException(
            'not_found',
            'Slot equipment $id is not published in the catalog.',
          );
      }
    }
    final next = WorkoutRevision.publish(definition, previous: previous);
    await repository.insertRevision(next);
    return next;
  });

  Future<WorkoutRevision> revision(String id, [int? number]) async =>
      await repository.revision(id, number) ?? _missing('Revision');

  Future<TrainingSession> session(String id) async =>
      await repository.session(id) ?? _missing('Session');

  Future<TrainingSession> start(
    String id,
    String templateId,
    int number,
    DateTime startedAt, {
    int startOffsetMinutes = 0,
    ProgramRun? programRun,
    Map<String, BodyMassOverride> bodyMassOverrides = const {},
    DerivedPlanRef? derivedPlan,
    Map<String, String> loadBindings = const {},
    Map<String, LoadConvention> loadConventions = const {},
    Map<String, Map<String, String>> variantSettings = const {},
  }) => repository.transaction(() async {
    final runId = programRun?.id;
    final prescription = await revision(templateId, number);
    final existing = await repository.session(id);
    final bindings = await repository.sessionPrograms();
    final runBySession = {for (final b in bindings) b.sessionId: b.runId};
    if (existing != null) {
      if (runBySession[id] != runId ||
          existing.definition.id != templateId ||
          existing.revision.number != number ||
          existing.startedAt != startedAt ||
          existing.startOffsetMinutes != startOffsetMinutes ||
          !sameBodyMassOverrides(existing, bodyMassOverrides) ||
          !sameLoadInputs(existing, loadBindings, loadConventions) ||
          !sameVariantRequest(existing, variantSettings) ||
          canonicalJson(existing.derivedPlanInput?.reference.toJson()) !=
              canonicalJson(derivedPlan?.toJson()))
        _conflict();
      if (runId != null) {
        final binding = bindings.firstWhere((b) => b.sessionId == id);
        requireFrozenPrescriptionOverrides(
          existing,
          (await ProgramService(repository).run(runId)).program.definition,
          binding.path,
        );
      }
      return existing;
    }
    String? dayPath;
    if (programRun != null) {
      final current = await ProgramService(repository).run(programRun.id);
      final day = current.current;
      if (current.status != 'active' ||
          canonicalJson(current.toJson()) !=
              canonicalJson(programRun.toJson()) ||
          day == null ||
          day.day.templateId != templateId ||
          day.day.revision != number ||
          bindings.any((b) => b.runId == runId && b.ordinal == current.cursor))
        _conflict();
      if (startedAt.isBefore(current.startedAt) ||
          (await repository.programReceipts())
              .where((r) => r.runId == runId)
              .any((r) => r.occurredAt.isAfter(startedAt)))
        invalid('Session precedes program occurrence history.');
      dayPath = day.path;
    }
    // Backdated sessions never use later decisions or later sources.
    bool before(ProgressionDecision d) =>
        !d.resolvedAt!.isAfter(startedAt) &&
        d.session.startedAt.isBefore(startedAt);
    final receipts = (await repository.progressionReconciliations()).where(
      (r) => r.runId == runId && !r.reconciledAt.isAfter(startedAt),
    );
    final sets = <TrainingSet>[];
    final retirements = (await repository.linkRetirements()).where(
      (r) => r.runId == runId && !r.retiredAt.isAfter(startedAt),
    );
    final links = await buildSharedLinkIndex(repository);
    final bySlot = <(String, String), ProgressionAnchor?>{
      for (final slot in prescription.definition.slots)
        for (final role in ['work', 'warmup', 'backoff', 'drop'])
          (slot.id, role): linkLinkedTrack(
            links,
            latestTrack(
              await trackDecisions(
                repository,
                prescription.definition.id,
                slot,
                runId: runId,
                role: role,
                where: before,
              ),
              <ProgressionAnchor>[...receipts, ...retirements],
              prescription.definition.id,
              slot,
              runId: runId,
              role: role,
            ),
            at: startedAt,
            sessionStartedAt: startedAt,
          ),
    };
    // Variant structures (set schemes): a progression-controlled slot lever
    // selects its branch; explicit request settings choose uncontrolled
    // variant levers; each lever's default applies otherwise.
    final slotSettings = <String, Map<String, String>>{};
    for (final entry in bySlot.entries) {
      final anchor = entry.value;
      if (anchor == null) continue;
      final slotId = entry.key.$1;
      for (final lever
          in prescription.definition
              .variantLevers(slotId)
              .intersection(anchor.controlledSettings)) {
        final values = {
          for (final settings in anchor.nextSettings) settings[lever],
        };
        if (values.length != 1 || values.single == null)
          _startReconciliationRequired(
            prescription,
            slotId,
            entry.key.$2,
            anchor,
            startedAt,
            runId,
          );
        final previous = slotSettings[slotId]?[lever];
        if (previous != null && previous != values.single)
          throw BodyTmiException(
            'conflict',
            'Progression tracks of slot $slotId select different variant '
                'values for lever $lever.',
          );
        (slotSettings[slotId] ??= {})[lever] = values.single!;
      }
    }
    for (final requested in variantSettings.entries) {
      for (final setting in requested.value.entries) {
        if (!prescription.definition
            .variantLevers(requested.key)
            .contains(setting.key))
          invalid(
            'Variant request names lever ${setting.key} of slot '
            '${requested.key}, which selects no variant.',
          );
        final progressed = slotSettings[requested.key]?[setting.key];
        if (progressed != null && progressed != setting.value)
          throw BodyTmiException(
            'conflict',
            'Variant lever ${setting.key} of slot ${requested.key} is '
                'progression-controlled; reconcile the track first.',
          );
        (slotSettings[requested.key] ??= {})[setting.key] = setting.value;
      }
    }
    final selections = prescription.definition.variantSelections(slotSettings);
    final resolved = prescription.definition.resolveVariants(selections);
    final plannedCounts = <(String, String), int>{};
    for (final occurrence in resolved.plan.occurrences()) {
      if (occurrence.activity case Effort(:final slotId, :final role))
        plannedCounts.update((slotId, role), (n) => n + 1, ifAbsent: () => 1);
    }
    // Ordinal tracks with categorical levels supply those levers' settings;
    // a uniform level resizes with a structural change.
    final progressedSettings = <String, Map<String, String>>{};
    {
      final ordinals = <(String, String), int>{};
      for (final occurrence in resolved.plan.occurrences()) {
        final effort = occurrence.activity;
        if (effort is! Effort) continue;
        final key = (effort.slotId, effort.role);
        final ordinal = ordinals.update(key, (v) => v + 1, ifAbsent: () => 0);
        final anchor = bySlot[key];
        if (anchor == null || anchor.controlledSettings.isEmpty) continue;
        final vector = resizedSettings(
          anchor.nextSettings,
          plannedCounts[key]!,
        );
        if (ordinal >= vector.length) continue;
        final settings = vector[ordinal];
        if (settings.isNotEmpty) progressedSettings[occurrence.id] = settings;
      }
    }
    var next = const TrainingService().start(
      sessionId: id,
      revision: prescription,
      bodyMassOverrides: bodyMassOverrides,
      bodyMassMeasurements: [
        for (final r in await repository.bodyMassRecords())
          if (!r.deleted) r.measurement,
      ],
      startedAt: startedAt,
      startOffsetMinutes: startOffsetMinutes,
      loadInstances: await _resolveLoadBindings(
        prescription,
        loadBindings,
        await repository.equipmentInstanceRevisions(),
      ),
      loadConventions: loadConventions,
      // Prefill is opt-in per slot and scoped to this workout template, so
      // other templates' sessions (and all history, when nothing prefills)
      // are never decoded.
      history:
          prescription.definition.slots.any((s) => s.prefillMetrics.isNotEmpty)
          ? (await repository.sessions(
              templateId: prescription.definition.id,
            )).where((s) => runBySession[s.id] == runId).toList()
          : const [],
      progressedSettings: progressedSettings,
      variantSelections: selections,
    );
    final scopedOverrides = programRun == null || dayPath == null
        ? const <ScopedProgramOverride>[]
        : programRun.program.definition.effectiveOverrides(dayPath);
    if (scopedOverrides.isNotEmpty) {
      if (derivedPlan != null) {
        invalid(
          'Sessions cannot combine derived plans and prescription overrides.',
        );
      }
      for (final scoped in scopedOverrides) {
        for (final role in ['work', 'warmup', 'backoff', 'drop']) {
          if (bySlot[(scoped.override.slotId, role)]?.controlledMetrics
                  .contains(scoped.override.metric) ??
              false) {
            throw BodyTmiException(
              'conflict',
              'Program prescription overrides cannot target a '
                  'progression-controlled metric; reconcile the track first.',
            );
          }
        }
      }
    }
    final overridden = applyPrescriptionOverrides(
      resolved,
      next.sets,
      scopedOverrides,
    );
    final workingCounts = <(String, String), int>{};
    for (final set in overridden.sets) {
      workingCounts.update(
        (set.slotId, set.role),
        (n) => n + 1,
        ifAbsent: () => 1,
      );
    }
    final authored = {
      for (final entry in bySlot.entries)
        if (entry.value != null)
          entry.key: resolved.roleTargets(entry.key.$1, entry.key.$2),
    };
    // The anchor's revision resolved under this session's structure; null
    // when it cannot express it (reconciliation required).
    final previousResolved = {
      for (final entry in bySlot.entries)
        if (entry.value != null)
          entry.key: resolveAlike(
            entry.value!.pinnedRevision.definition,
            selections,
          ),
    };
    final previousAuthored = {
      for (final entry in previousResolved.entries)
        entry.key: entry.value?.roleTargets(entry.key.$1, entry.key.$2),
    };
    for (final set in overridden.sets) {
      final applied = bySlot[(set.slotId, set.role)];
      if (applied == null) {
        sets.add(set);
        continue;
      }
      final vector = applied.nextSets;
      final count = workingCounts[(set.slotId, set.role)]!;
      // A structural change (another variant branch) may resize a uniform
      // controlled vector; objectives then compare with the anchor revision
      // resolved under this session's structure.
      final broadcast = broadcastsVector(
        applied,
        prescription.definition,
        set.slotId,
        set.settings,
        count,
      );
      final prior = previousAuthored[(set.slotId, set.role)];
      if ((vector.length != count && !broadcast) ||
          prior == null ||
          prior.length != count)
        _startReconciliationRequired(
          prescription,
          set.slotId,
          set.role,
          applied,
          startedAt,
          runId,
        );
      final priorEffort = broadcast
          ? previousResolved[(set.slotId, set.role)]!.roleEfforts(
              set.slotId,
              set.role,
            )[set.ordinal]
          : null;
      final oldObjectives =
          priorEffort?.maxEffortMetrics ??
          applied.sets[set.ordinal].maxEffortMetrics;
      final oldCriteria =
          priorEffort?.criteria ?? applied.sets[set.ordinal].criteria;
      final consumed = broadcast ? vector.first : vector[set.ordinal];
      if (oldObjectives.length != set.maxEffortMetrics.length ||
          !oldObjectives.containsAll(set.maxEffortMetrics) ||
          canonicalJson({
                for (final e in oldCriteria.entries)
                  e.key: e.value.semanticJson(),
              }) !=
              canonicalJson({
                for (final e in set.criteria.entries)
                  e.key: e.value.semanticJson(),
              }))
        _startReconciliationRequired(
          prescription,
          set.slotId,
          set.role,
          applied,
          startedAt,
          runId,
        );
      final slot = prescription.definition.slot(set.slotId);
      for (final metric in applied.controlledMetrics) {
        if (set.suggested[metric]?.dimension != consumed[metric]!.dimension)
          _startReconciliationRequired(
            prescription,
            set.slotId,
            set.role,
            applied,
            startedAt,
            runId,
          );
        final target = slot.targets[metric],
            priorTarget = applied.slot.targets[metric];
        if (target == null ||
            priorTarget == null ||
            target.compareTo(priorTarget) != 0)
          _startReconciliationRequired(
            prescription,
            set.slotId,
            set.role,
            applied,
            startedAt,
            runId,
          );
        if (authored[(set.slotId, set.role)]![set.ordinal][metric]!.compareTo(
              prior[set.ordinal][metric]!,
            ) !=
            0)
          _startReconciliationRequired(
            prescription,
            set.slotId,
            set.role,
            applied,
            startedAt,
            runId,
          );
      }
      final suggested = {
        ...set.suggested,
        for (final metric in applied.controlledMetrics)
          metric: consumed[metric]!,
      };
      sets.add(
        TrainingSet(
          id: set.id,
          slotId: set.slotId,
          role: set.role,
          ordinal: set.ordinal,
          settings: set.settings,
          actualSettings: set.actualSettings,
          suggested: suggested,
          maxEffortMetrics: set.maxEffortMetrics,
          criteria: set.criteria,
          sources: {
            for (final e in set.sources.entries)
              if (!applied.controlledMetrics.contains(e.key)) e.key: e.value,
          },
        ),
      );
    }
    DerivedPlanInput? derivedInput;
    var finalSets = sets;
    if (derivedPlan != null) {
      final resolved = await _resolveSessionPlan(
        session: next,
        sets: sets,
        reference: derivedPlan,
        runId: runId,
        bySlot: bySlot,
        incrementSetVersions: false,
      );
      finalSets = resolved.$1;
      derivedInput = resolved.$2;
    }
    next = TrainingSession(
      id: next.id,
      extraSets: next.extraSets,
      revision: next.revision,
      variantSelections: next.variantSelections,
      startedAt: next.startedAt,
      startOffsetMinutes: next.startOffsetMinutes,
      finishOffsetMinutes: next.finishOffsetMinutes,
      sets: finalSets,
      bodyMassInputs: next.bodyMassInputs,
      loadInputs: next.loadInputs,
      initialBodyMassOverrides: next.initialBodyMassOverrides,
      derivedPlanInput: derivedInput,
      prescriptionOverrides: overridden.records,
    );
    if (derivedInput != null) {
      validateDerivedPlanReferences(
        [...await repository.sessions(), next],
        await repository.derivedTargetGraphRevisions(),
        {...runBySession, if (runId != null) id: runId},
        await repository.bodyMassRecords(),
      );
    }
    await repository.insertSession(next);
    if (programRun != null) {
      await repository.insertSessionProgram(
        SessionProgramBinding(
          sessionId: id,
          runId: programRun.id,
          ordinal: programRun.cursor,
          path: programRun.current!.path,
        ),
      );
      await repository.saveProgramRun(programRun.changed());
    }
    return next;
  });

  /// Resolve and freeze a pinned plan using the same rules at start and refresh.
  Future<(List<TrainingSet>, DerivedPlanInput)> _resolveSessionPlan({
    required TrainingSession session,
    required List<TrainingSet> sets,
    required DerivedPlanRef reference,
    required String? runId,
    required Map<(String, String), ProgressionAnchor?> bySlot,
    required bool incrementSetVersions,
    Map<String, Object?>? reviewedPreview,
  }) async {
    final prescription = session.revision;
    final templateId = prescription.definition.id;
    final number = prescription.number;
    final startedAt = session.startedAt;
    var finalSets = sets;
    final resolved = await DerivedWorkoutPreview(repository).previewPlan(
      graphId: reference.graphId,
      graphRevision: reference.graphRevision,
      planId: reference.planId,
      asOf: startedAt,
      runId: runId,
      strictHistoryStart: true,
      variantSelections: session.variantSelections,
    );
    if (reviewedPreview != null &&
        canonicalJson(reviewedPreview) != canonicalJson(resolved['preview'])) {
      throw const BodyTmiException(
        'conflict',
        'Derived plan sources or targets changed since the reviewed preview.',
      );
    }
    final plan = DerivedWorkoutPlan.fromJson(resolved['plan']);
    if (plan.templateId != templateId || plan.revision != number)
      invalid('Derived plan pins another workout revision.');
    final preview = jsonObject(resolved['preview'], 'derived preview');
    final graph = jsonObject(preview['graphResolution'], 'graph resolution');
    final bodyMassSources = <String, Object?>{};
    final bodyRecords = await repository.bodyMassRecords();
    for (final entry in jsonObject(
      graph['bindings'],
      'graph bindings',
    ).entries) {
      final source = jsonObject(entry.value, 'graph source');
      if (source['kind'] == 'bodyMass') {
        final cutoff = source['asOf'] == null
            ? startedAt
            : parseInstant(source['asOf'], 'asOf');
        final selected = [
          for (final record in bodyRecords)
            if (!record.deleted &&
                record.measurement.context == source['context'] &&
                !record.measurement.observedAt.isAfter(cutoff))
              record.measurement,
        ];
        selected.sort((a, b) {
          final order = a.observedAt.compareTo(b.observedAt);
          return order != 0 ? order : a.id.compareTo(b.id);
        });
        bodyMassSources[entry.key] = [for (final m in selected) m.toJson()];
      } else if (source['kind'] != 'manual' && source['kind'] != 'history') {
        invalid('Unsupported session plan source.');
      }
    }
    final rows = {
      for (final value in jsonList(preview, 'occurrences'))
        requiredString(jsonObject(value, 'occurrence'), 'id'): jsonObject(
          value,
          'occurrence',
        ),
    };
    final mapped = <String, Map<String, Quantity>>{};
    for (final binding in plan.bindings) {
      final occurrenceId = binding['occurrenceId']! as String;
      final metric = binding['metric']! as String;
      // Bindings into unselected variant branches are inactive here.
      if (!rows.containsKey(occurrenceId)) continue;
      final set = sets.firstWhere((item) => item.id == occurrenceId);
      final applied = bySlot[(set.slotId, set.role)];
      if (applied != null && applied.controlledMetrics.contains(metric)) {
        invalid(
          'Derived plan conflicts with an accepted progression target; reconciliation is required.',
        );
      }
      final target = jsonObject(
        jsonObject(rows[occurrenceId]!['targets'], 'targets')[metric],
        'target',
      );
      if (target['status'] != 'resolved' || target['value'] == null)
        invalid('Derived plan target is unresolved.');
      mapped.putIfAbsent(occurrenceId, () => <String, Quantity>{})[metric] =
          Quantity.fromJson(target['value']);
    }
    finalSets = [
      for (final set in sets)
        if (!mapped.containsKey(set.id))
          set
        else
          () {
            final suggested = {...set.suggested, ...mapped[set.id]!};
            if (incrementSetVersions &&
                canonicalJson(metricsToJson(suggested)) ==
                    canonicalJson(metricsToJson(set.suggested)) &&
                !mapped[set.id]!.keys.any(set.sources.containsKey))
              return set;
            prescription.definition.slot(set.slotId).timing?.resolve(suggested);
            return TrainingSet(
              id: set.id,
              slotId: set.slotId,
              role: set.role,
              ordinal: set.ordinal,
              settings: set.settings,
              actualSettings: set.actualSettings,
              status: set.status,
              actuals: set.actuals,
              timing: set.timing,
              observations: set.observations,
              contentVersion:
                  set.contentVersion + (incrementSetVersions ? 1 : 0),
              suggested: suggested,
              maxEffortMetrics: set.maxEffortMetrics,
              criteria: set.criteria,
              manualTargets: set.manualTargets,
              carriedTargets: set.carriedTargets,
              substitution: set.substitution,
              sources: {
                for (final e in set.sources.entries)
                  if (!mapped[set.id]!.containsKey(e.key)) e.key: e.value,
              },
            );
          }(),
    ];
    final derivedInput = DerivedPlanInput.fromJson({
      'reference': reference.toJson(),
      'snapshot': resolved,
      if (bodyMassSources.isNotEmpty) 'bodyMassSources': bodyMassSources,
    });
    return (finalSets, derivedInput);
  }

  /// Re-resolve the same pinned plan before any workout activity begins.
  Future<TrainingSession> refreshPlan(
    String id,
    int expectedVersion, {
    required Object? expectedPreview,
    required bool confirm,
  }) => repository.transaction(() async {
    if (!confirm) invalid('Refreshing a session plan requires confirm:true.');
    final reviewedPreview = jsonObject(expectedPreview, 'expectedPreview');
    final current = await session(id);
    if (current.contentVersion != expectedVersion) _conflict();
    if (current.status != SessionStatus.active ||
        current.sets.any((set) => set.status != SetStatus.planned)) {
      invalid(
        'A session plan can only be refreshed before any effort is completed or skipped.',
      );
    }
    if ((await repository.timingActivities()).any((t) => t.sessionId == id) ||
        (await repository.windowCheckpoints()).any(
          (c) => c.sessionId == id && c.reserved,
        ) ||
        (await repository.executions()).any((e) => e.sessionId == id)) {
      invalid(
        'A session plan cannot be refreshed after timing or traversal has started.',
      );
    }
    final reference = current.derivedPlanInput?.reference;
    if (reference == null) invalid('Session has no derived plan to refresh.');
    final runBySession = {
      for (final binding in await repository.sessionPrograms())
        binding.sessionId: binding.runId,
    };
    final runId = runBySession[id];
    bool before(ProgressionDecision d) =>
        !d.resolvedAt!.isAfter(current.startedAt) &&
        d.session.startedAt.isBefore(current.startedAt);
    final receipts = (await repository.progressionReconciliations()).where(
      (r) => r.runId == runId && !r.reconciledAt.isAfter(current.startedAt),
    );
    final refreshRetirements = (await repository.linkRetirements()).where(
      (r) => r.runId == runId && !r.retiredAt.isAfter(current.startedAt),
    );
    final bySlot = <(String, String), ProgressionAnchor?>{
      for (final slot in current.definition.slots)
        for (final role in ['work', 'warmup', 'backoff', 'drop'])
          (slot.id, role): linkLinkedTrack(
            await buildSharedLinkIndex(repository),
            latestTrack(
              await trackDecisions(
                repository,
                current.definition.id,
                slot,
                runId: runId,
                role: role,
                where: before,
              ),
              <ProgressionAnchor>[...receipts, ...refreshRetirements],
              current.definition.id,
              slot,
              runId: runId,
              role: role,
            ),
            at: current.startedAt,
            sessionStartedAt: current.startedAt,
          ),
    };
    final result = await _resolveSessionPlan(
      session: current,
      sets: current.sets,
      reference: reference,
      runId: runId,
      bySlot: bySlot,
      incrementSetVersions: true,
      reviewedPreview: reviewedPreview,
    );
    if (canonicalJson(result.$2.toJson()) ==
            canonicalJson(current.derivedPlanInput!.toJson()) &&
        canonicalJson([for (final set in result.$1) set.toJson()]) ==
            canonicalJson([for (final set in current.sets) set.toJson()]))
      return current;
    final next = TrainingSession(
      id: current.id,
      extraSets: current.extraSets,
      revision: current.revision,
      variantSelections: current.variantSelections,
      startedAt: current.startedAt,
      startOffsetMinutes: current.startOffsetMinutes,
      sets: result.$1,
      bodyMassInputs: current.bodyMassInputs,
      loadInputs: current.loadInputs,
      initialBodyMassOverrides: current.initialBodyMassOverrides,
      derivedPlanInput: result.$2,
      prescriptionOverrides: current.prescriptionOverrides,
      status: current.status,
      finishedAt: current.finishedAt,
      finishOffsetMinutes: current.finishOffsetMinutes,
      contentVersion: current.contentVersion + 1,
    );
    final sessions = await repository.sessions();
    validateDerivedPlanReferences(
      [for (final session in sessions) session.id == id ? next : session],
      await repository.derivedTargetGraphRevisions(),
      runBySession,
      await repository.bodyMassRecords(),
    );
    await repository.updateSession(next);
    return next;
  });

  /// Refresh mass inputs only before any persisted timing or traversal exists.
  Future<TrainingSession> refreshBodyMass(
    String id,
    int expectedVersion, {
    required bool confirm,
  }) => repository.transaction(() async {
    final current = await session(id);
    if (current.contentVersion != expectedVersion) _conflict();
    if ((await repository.timingActivities()).any(
          (timer) => timer.sessionId == id,
        ) ||
        (await repository.windowCheckpoints()).any(
          (c) => c.sessionId == id && c.reserved,
        ) ||
        (await repository.executions()).any(
          (execution) => execution.sessionId == id,
        )) {
      invalid(
        'Body mass cannot be refreshed after timing or traversal has started.',
      );
    }
    final next = const TrainingService().refreshBodyMass(current, [
      for (final record in await repository.bodyMassRecords())
        if (!record.deleted) record.measurement,
    ], confirm: confirm);
    if (identical(next, current)) return current;
    await repository.updateSession(next);
    return next;
  });

  /// Rebind before any timing/traversal, retaining initial start overrides.
  Future<TrainingSession> rebindBodyMass(
    String id,
    int expectedVersion,
    Map<String, BodyMassOverride?> updates, {
    required bool confirm,
  }) => repository.transaction(() async {
    final current = await session(id);
    if (current.contentVersion != expectedVersion) _conflict();
    if ((await repository.timingActivities()).any(
          (timer) => timer.sessionId == id,
        ) ||
        (await repository.windowCheckpoints()).any(
          (c) => c.sessionId == id && c.reserved,
        ) ||
        (await repository.executions()).any(
          (execution) => execution.sessionId == id,
        )) {
      invalid(
        'Body mass cannot be rebound after timing or traversal has started.',
      );
    }
    final next = const TrainingService().rebindBodyMass(
      current,
      [
        for (final record in await repository.bodyMassRecords())
          if (!record.deleted) record.measurement,
      ],
      updates,
      confirm: confirm,
    );
    if (identical(next, current)) return current;
    await repository.updateSession(next);
    return next;
  });

  /// Edit planned targets atomically without changing live or unreviewed clocks.
  Future<TrainingSession> editTarget(
    String id,
    int expectedVersion,
    String setId,
    String metric,
    Quantity value, {
    bool applyToRemaining = false,
  }) => _changeTargets(
    id,
    expectedVersion,
    (current) => const TrainingService().editTarget(
      current,
      setId,
      metric,
      value,
      applyToRemaining: applyToRemaining,
    ),
  );

  Future<TrainingSession> carryActual(
    String id,
    int expectedVersion,
    String setId,
    String metric,
  ) => _changeTargets(
    id,
    expectedVersion,
    (current) => const TrainingService().carryActual(current, setId, metric),
  );

  Future<void> _validateReservedClockChange(
    TrainingSession current,
    TrainingSession next,
  ) async {
    final id = current.id;
    for (final checkpoint in await repository.windowCheckpoints()) {
      if (!checkpoint.reserved || checkpoint.sessionId != id) continue;
      if (next.status == SessionStatus.finalized)
        invalid(
          'Release the reserved window clock before finishing the session.',
        );
      final wrapper = const SessionWindowClock().validateSnapshot(
        current,
        checkpoint.clock,
      );
      final clock = jsonObject(wrapper['clock'], 'window clock');
      if (clock['status'] == 'running') {
        final occurrence = clock['occurrence'] as int;
        final plan = current.definition.plan.occurrences().toList();
        if (plan[occurrence].activity is Effort &&
            canonicalJson(current.set(plan[occurrence].id).toJson()) !=
                canonicalJson(next.set(plan[occurrence].id).toJson()))
          invalid(
            'Pause or recover the reserved window clock before changing its current effort.',
          );
      }
    }
  }

  Future<TrainingSession> _changeTargets(
    String id,
    int expectedVersion,
    TrainingSession Function(TrainingSession) change,
  ) => repository.transaction(() async {
    final current = await session(id);
    if (current.contentVersion != expectedVersion) _conflict();
    final next = change(current);
    await _validateReservedClockChange(current, next);
    if (identical(current, next)) return current;
    final changed = {
      for (var i = 0; i < current.sets.length; i++)
        if (!identical(current.sets[i], next.sets[i])) current.sets[i].id,
    };
    if ((await repository.timingActivities()).any(
      (t) =>
          t.sessionId == id &&
          !t.plan.restOnly &&
          changed.contains(t.setId) &&
          (t.active || t.status == 'awaitingConfirmation'),
    )) {
      invalid(
        'Review or discard the affected effort clock before editing its target.',
      );
    }
    for (final execution in await repository.executions()) {
      if (execution.sessionId != id || execution.complete) continue;
      final plan = executionPlan(current);
      if (plan
          .take(execution.cursor)
          .any((occurrence) => changed.contains(occurrence.id))) {
        invalid('Targets cannot be edited behind the traversal cursor.');
      }
    }
    return edit(id, expectedVersion, (_) => next);
  });

  /// Skip unperformed efforts atomically, leaving clock/traversal review explicit.
  Future<TrainingSession> skipRemaining(
    String id,
    int expectedVersion, {
    required bool confirm,
  }) => _skipPlanned(id, expectedVersion, confirm: confirm);

  Future<TrainingSession> skipSlot(
    String id,
    int expectedVersion,
    String slotId, {
    String? role,
    required bool confirm,
  }) => _skipPlanned(
    id,
    expectedVersion,
    slotId: slotId,
    role: role,
    confirm: confirm,
  );

  Future<TrainingSession> _skipPlanned(
    String id,
    int expectedVersion, {
    String? slotId,
    String? role,
    required bool confirm,
  }) => repository.transaction(() async {
    final current = await session(id);
    if (current.contentVersion != expectedVersion) _conflict();
    if ((await repository.executions()).any(
      (e) => e.sessionId == id && !e.complete,
    ))
      invalid('Use execution skip-group while workout traversal is active.');
    if ((await repository.timingActivities()).any(
      (t) =>
          t.sessionId == id && (t.active || t.status == 'awaitingConfirmation'),
    ))
      invalid('Stop and review or discard the session clock before skipping.');
    final next = slotId == null
        ? const TrainingService().skipRemaining(current, confirm: confirm)
        : const TrainingService().skipSlot(
            current,
            slotId,
            role: role,
            confirm: confirm,
          );
    if (identical(next, current)) return current;
    return edit(id, expectedVersion, (_) => next);
  });

  /// Guards shared by substitution and its revert: no guided traversal,
  /// effort clock or reserved scoped clock may own the session.
  /// A substitution may happen mid-workout (the benches are all taken when
  /// you reach them), but only for sets still ahead: never behind a guided
  /// traversal's cursor and never a set whose effort clock is running or
  /// awaiting review. Rest clocks and other sets are unaffected.
  Future<void> _guardSubstitution(
    TrainingSession current,
    TrainingSession next,
  ) async {
    final id = current.id;
    final changed = {
      for (final set in next.sets)
        if (canonicalJson(set.toJson()) !=
            canonicalJson(current.set(set.id).toJson()))
          set.id,
    };
    if ((await repository.timingActivities(sessionId: id)).any(
      (t) =>
          !t.plan.restOnly &&
          changed.contains(t.setId) &&
          (t.active || t.status == 'awaitingConfirmation'),
    ))
      invalid(
        'Stop and review or discard the effort clock of a set before '
        'substituting it.',
      );
    for (final execution in await repository.executions(sessionId: id)) {
      if (execution.complete) continue;
      if (executionPlan(current)
          .take(execution.cursor)
          .any((occurrence) => changed.contains(occurrence.id)))
        invalid('Sets behind the traversal cursor cannot be substituted.');
    }
    if ((await repository.windowCheckpoints()).any(
      (c) => c.sessionId == id && c.reserved,
    ))
      invalid('Release the scoped clock before substituting.');
  }

  Future<TrainingSession> substitute(
    String id,
    int expectedVersion, {
    required String slotId,
    required String scope,
    String? setId,
    required SubstituteComposition composition,
    Map<String, Map<String, Object?>> targets = const {},
  }) => repository.transaction(() async {
    final current = await session(id);
    if (current.contentVersion != expectedVersion) _conflict();
    final owner = implementationOwners(
      await repository.implementationRevisions(),
    )[composition.implementation];
    if (owner != null && owner != composition.exerciseId)
      invalid(
        'Implementation ${composition.implementation} belongs to exercise '
        '$owner, not ${composition.exerciseId}.',
      );
    // Substitution history only searches this workout template.
    final history = await repository.sessions(
      templateId: current.definition.id,
    );
    final next = const TrainingService().substitute(
      current,
      slotId: slotId,
      scope: scope,
      setId: setId,
      composition: composition,
      targets: targets,
      history: history,
    );
    await _guardSubstitution(current, next);
    return edit(id, expectedVersion, (_) => next);
  });

  Future<TrainingSession> revertSubstitution(
    String id,
    int expectedVersion, {
    required String slotId,
    required String scope,
    String? setId,
  }) => repository.transaction(() async {
    final current = await session(id);
    if (current.contentVersion != expectedVersion) _conflict();
    final next = const TrainingService().revertSubstitution(
      current,
      slotId: slotId,
      scope: scope,
      setId: setId,
    );
    await _guardSubstitution(current, next);
    return edit(id, expectedVersion, (_) => next);
  });

  Future<TrainingSession> edit(
    String id,
    int expectedVersion,
    TrainingSession Function(TrainingSession) change,
  ) => repository.transaction(() async {
    final current = await session(id);
    if (current.contentVersion != expectedVersion) _conflict();
    final next = change(current);
    await _validateReservedClockChange(current, next);
    final executions = await repository.executions(sessionId: id);
    final clocks = await sessionClocks(repository, id, [
      for (final e in executions) e.id,
    ]);
    for (final t in clocks) {
      if (t.active &&
          (next.status == SessionStatus.finalized ||
              (!t.plan.restOnly &&
                  canonicalJson(current.set(t.setId).toJson()) !=
                      canonicalJson(next.set(t.setId).toJson()))))
        invalid(
          'Stop the active timing activity before changing its result or finishing the session.',
        );
    }
    if (next.id != current.id ||
        next.startedAt != current.startedAt ||
        canonicalJson({
              for (final e
                  in (next.initialBodyMassOverrides ??
                          <String, BodyMassOverride>{})
                      .entries)
                e.key: e.value.toJson(),
            }) !=
            canonicalJson({
              for (final e
                  in (current.initialBodyMassOverrides ??
                          <String, BodyMassOverride>{})
                      .entries)
                e.key: e.value.toJson(),
            }) ||
        (next.initialBodyMassOverrides == null) !=
            (current.initialBodyMassOverrides == null) ||
        canonicalJson(next.derivedPlanInput?.toJson()) !=
            canonicalJson(current.derivedPlanInput?.toJson()) ||
        canonicalJson({
              for (final e in next.bodyMassInputs.entries)
                e.key: e.value.toJson(),
            }) !=
            canonicalJson({
              for (final e in current.bodyMassInputs.entries)
                e.key: e.value.toJson(),
            }) ||
        canonicalJson(next.revision.toJson()) !=
            canonicalJson(current.revision.toJson())) {
      invalid(
        'Editing results cannot change session identity, start time, pinned prescription or captured body-mass inputs.',
      );
    }
    validateDerivedPlanSession(next);
    // Only this session changed, so only its own clocks and execution can
    // newly disagree with it; profile-wide clock rules do not depend on
    // results. Validating the whole history here made every logged set
    // cost time proportional to all past sessions.
    validateTimingData(
      [
        for (final t in clocks)
          if (t.sessionId == id) t,
      ],
      [next],
    );
    if (next.status == SessionStatus.finalized &&
        executions.any((e) => e.sessionId == id && !e.complete))
      invalid(
        'Acknowledge all execution occurrences before finishing the session.',
      );
    if (next.status == SessionStatus.finalized &&
        (await repository.repeatCheckpoints()).any(
          (checkpoint) =>
              checkpoint.sessionId == id &&
              jsonObject(checkpoint.execution['cursor'], 'cursor')['status'] !=
                  'finished',
        ))
      invalid(
        'Finish or explicitly discard associated repeats before finishing the session.',
      );
    if (next.status == SessionStatus.finalized) {
      final missing = missingAmrapBlocks(
        next,
        await repository.repeatCheckpoints(),
      );
      if (missing.isNotEmpty)
        invalid(
          'Start and finish, or explicitly stop, AMRAP blocks before '
          'finishing the session: ${missing.join(', ')}.',
        );
    }
    validateExecutionData(executions, [next], clocks);
    await repository.updateSession(next);
    if (next.status == SessionStatus.finalized) {
      await repository.recordFinalization(id);
      await ProgramService(repository).finalized(next);
    }
    return next;
  });
}

bool sameBodyMassOverrides(
  TrainingSession session,
  Map<String, BodyMassOverride> overrides,
) {
  if (overrides.keys.any((key) => !session.bodyMassInputs.containsKey(key)))
    return false;
  final initial = session.initialBodyMassOverrides;
  if (initial != null) {
    return canonicalJson({
          for (final e in initial.entries) e.key: e.value.toJson(),
        }) ==
        canonicalJson({
          for (final e in overrides.entries) e.key: e.value.toJson(),
        });
  }
  return session.bodyMassInputs.entries.every(
    (e) => e.value.sameOverride(overrides[e.key]),
  );
}

/// Resolves requested slot-to-instance bindings to the latest published
/// revision snapshot of each instance. Unknown instances are a not_found
/// error; slot membership and convention capability are checked purely.
Future<Map<String, LoadInstanceReference>> _resolveLoadBindings(
  WorkoutRevision revision,
  Map<String, String> bindings,
  List<EquipmentInstanceRevision> instances,
) async {
  if (bindings.isEmpty) return const {};
  final latest = <String, EquipmentInstanceRevision>{};
  for (final revisionRow in instances) {
    final prior = latest[revisionRow.instance.id];
    if (prior == null || revisionRow.number > prior.number)
      latest[revisionRow.instance.id] = revisionRow;
  }
  for (final slotId in bindings.keys) {
    if (!revision.definition.slots.any((s) => s.id == slotId))
      invalid('Load binding names an unknown slot.');
  }
  return {
    for (final entry in bindings.entries)
      entry.key: (() {
        final found = latest[entry.value];
        if (found == null)
          throw BodyTmiException(
            'not_found',
            'Equipment instance not found: ${entry.value}.',
          );
        return LoadInstanceReference(
          found.instance.id,
          found.instance,
          found.number,
        );
      })(),
  };
}

/// A start retry must present the same load request the frozen session
/// recorded: the same slot-to-instance bindings (by instance identity; the
/// pinned revision stays frozen) and the same explicit session conventions.
bool sameLoadInputs(
  TrainingSession session,
  Map<String, String> bindings,
  Map<String, LoadConvention> conventions,
) {
  if (bindings.length !=
      session.loadInputs.values.where((s) => s.instance != null).length)
    return false;
  for (final entry in bindings.entries) {
    if (session.loadInputs[entry.key]?.instance?.instanceId != entry.value)
      return false;
  }
  if (conventions.length !=
      session.loadInputs.values.where((s) => s.source == 'session').length)
    return false;
  for (final entry in conventions.entries) {
    final captured = session.loadInputs[entry.key];
    if (captured?.source != 'session' ||
        canonicalJson(captured!.convention!.toJson()) !=
            canonicalJson(entry.value.toJson()))
      return false;
  }
  return true;
}

/// A bound-start retry must reproduce the effective prescription overrides
/// that were frozen at the original start. Later program revisions, upgrades
/// or authored edits cannot silently change an existing session's provenance.
void requireFrozenPrescriptionOverrides(
  TrainingSession session,
  ProgramDefinition definition,
  String path,
) {
  final pure = const TrainingService().start(
    sessionId: session.id,
    revision: session.revision,
    startedAt: session.startedAt,
    startOffsetMinutes: session.startOffsetMinutes,
  );
  final expected = applyPrescriptionOverrides(
    session.definition,
    pure.sets,
    definition.effectiveOverrides(path),
  ).records;
  if (canonicalJson([for (final record in expected) record.toJson()]) !=
      canonicalJson([
        for (final record in session.prescriptionOverrides) record.toJson(),
      ]))
    _conflict();
}

Never _conflict() => throw const BodyTmiException(
  'conflict',
  'Stored content changed or identity already exists. Refresh before retrying.',
);

/// Names the explicit reconciliation kinds that stop a new session from
/// consuming an accepted progression track. The guarded predicates above stay
/// authoritative; this only explains a difference that already blocked the start.
Never _startReconciliationRequired(
  WorkoutRevision prescription,
  String slotId,
  String role,
  ProgressionAnchor applied,
  DateTime asOf,
  String? runId,
) {
  final assessment = assessProgressionReconciliation(
    prescription: prescription,
    templateId: prescription.definition.id,
    revision: prescription.number,
    slotId: slotId,
    role: role,
    track: applied,
    runId: runId,
    asOf: asOf,
  );
  if (!assessment.required) _conflict();
  throw reconciliationConflict(assessment, context: 'Store start');
}

Never _missing(String kind) =>
    throw BodyTmiException('not_found', '$kind not found.');
