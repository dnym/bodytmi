import 'package:bodytmi_core/bodytmi_core.dart';
import 'training_service.dart';
import 'training_archive.dart';
import 'progression_decision.dart';
import 'program_service.dart';
import 'canonical_json.dart';
import 'stored_body_mass_service.dart';
import 'timing_service.dart';
import 'execution_service.dart';
import 'derived_workout_preview.dart';
import 'derived_plan_session.dart';

/// One repository transaction is the durability boundary of each operation.
abstract interface class TrainingRepository {
  Future<T> transaction<T>(Future<T> Function() action);
  Future<WorkoutRevision?> revision(String templateId, [int? number]);
  Future<List<WorkoutRevision>> revisions();
  Future<List<FamilyRevision>> familyRevisions();
  Future<void> insertFamilyRevision(FamilyRevision revision);
  Future<List<DerivedTargetGraphRevision>> derivedTargetGraphRevisions();
  Future<void> insertDerivedTargetGraphRevision(
    DerivedTargetGraphRevision revision,
  );
  Future<List<String>> finalizationIds();
  Future<List<ProgressionDecision>> progressionDecisions();
  Future<void> saveProgressionDecision(ProgressionDecision decision);
  Future<List<ProgramRevision>> programRevisions();
  Future<void> insertProgramRevision(ProgramRevision revision);
  Future<WorkoutExecution?> execution(String id);
  Future<List<WorkoutExecution>> executions();
  Future<void> saveExecution(WorkoutExecution execution);
  Future<TimingActivity?> timingActivity(String id);
  Future<List<TimingActivity>> timingActivities();
  Future<void> saveTimingActivity(TimingActivity timer);
  Future<List<BodyMassRecord>> bodyMassRecords();
  Future<void> saveBodyMassRecord(BodyMassRecord record);
  Future<List<ProgramRun>> programRuns();
  Future<void> saveProgramRun(ProgramRun run);
  Future<List<SessionProgramBinding>> sessionPrograms();
  Future<void> insertSessionProgram(SessionProgramBinding binding);
  Future<List<ProgramReceipt>> programReceipts();
  Future<void> insertProgramReceipt(ProgramReceipt receipt);
  Future<void> insertRevision(WorkoutRevision revision);
  Future<TrainingSession?> session(String id);
  Future<List<TrainingSession>> sessions();
  Future<void> insertSession(TrainingSession session);
  Future<void> updateSession(TrainingSession session);
  Future<void> recordFinalization(String sessionId);
}

final class StoredTrainingService {
  const StoredTrainingService(this.repository);
  final TrainingRepository repository;

  Future<TrainingArchive> exportArchive() => repository.transaction(
    () async => TrainingArchive(
      revisions: await repository.revisions(),
      families: await repository.familyRevisions(),
      sessions: await repository.sessions(),
      finalizations: await repository.finalizationIds(),
      progressions: await repository.progressionDecisions(),
      programRevisions: await repository.programRevisions(),
      bodyMass: await repository.bodyMassRecords(),
      timers: await repository.timingActivities(),
      executions: await repository.executions(),
      programRuns: await repository.programRuns(),
      sessionPrograms: await repository.sessionPrograms(),
      programReceipts: await repository.programReceipts(),
      graphs: await repository.derivedTargetGraphRevisions(),
    ),
  );

  Future<WorkoutRevision> publish(
    WorkoutDefinition definition,
    int expectedRevision,
  ) => repository.transaction(() async {
    final previous = await repository.revision(definition.id);
    if ((previous?.number ?? 0) != expectedRevision) _conflict();
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
    ProgramRun? programRun,
    Map<String, BodyMassOverride> bodyMassOverrides = const {},
    DerivedPlanRef? derivedPlan,
  }) => repository.transaction(() async {
    final runId = programRun?.id;
    final prescription = await revision(templateId, number);
    final existing = await repository.session(id);
    final bindings = await repository.sessionPrograms();
    final runBySession = {for (final b in bindings) b.sessionId: b.runId};
    if (existing != null) {
      if (runBySession[id] != runId ||
          existing.revision.definition.id != templateId ||
          existing.revision.number != number ||
          existing.startedAt != startedAt ||
          !sameBodyMassOverrides(existing, bodyMassOverrides) ||
          canonicalJson(existing.derivedPlanInput?.reference.toJson()) !=
              canonicalJson(derivedPlan?.toJson()))
        _conflict();
      return existing;
    }
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
      history: (await repository.sessions())
          .where((s) => runBySession[s.id] == runId)
          .toList(),
    );
    final decisions = (await repository.progressionDecisions()).where(
      (d) =>
          d.runId == runId &&
          d.resolvedAt != null &&
          !d.resolvedAt!.isAfter(startedAt) &&
          d.session.startedAt.isBefore(startedAt),
    );
    final sets = <TrainingSet>[];
    final bySlot = {
      for (final slot in prescription.definition.slots)
        slot.id: latestApplication(
          decisions,
          prescription.definition.id,
          slot,
          runId: runId,
        ),
    };
    final workingCounts = <String, int>{};
    for (final set in next.sets.where((s) => s.role == 'work')) {
      workingCounts.update(set.slotId, (n) => n + 1, ifAbsent: () => 1);
    }
    final authored = {
      for (final entry in bySlot.entries)
        if (entry.value != null)
          entry.key: prescription.definition.workingTargets(entry.key),
    };
    final previousAuthored = {
      for (final entry in bySlot.entries)
        if (entry.value != null)
          entry.key: entry.value!.session.revision.definition.workingTargets(
            entry.key,
          ),
    };
    for (final set in next.sets) {
      final applied = set.role == 'work' ? bySlot[set.slotId] : null;
      if (applied == null) {
        sets.add(set);
        continue;
      }
      final vector = applied.nextSets;
      final count = workingCounts[set.slotId];
      if (vector.length != count ||
          previousAuthored[set.slotId]!.length != count)
        _conflict();
      final oldObjectives = applied.sets[set.ordinal].maxEffortMetrics;
      if (oldObjectives.length != set.maxEffortMetrics.length ||
          !oldObjectives.containsAll(set.maxEffortMetrics) ||
          canonicalJson({
                for (final e in applied.sets[set.ordinal].criteria.entries)
                  e.key: e.value.semanticJson(),
              }) !=
              canonicalJson({
                for (final e in set.criteria.entries)
                  e.key: e.value.semanticJson(),
              }))
        _conflict();
      final slot = prescription.definition.slot(set.slotId);
      for (final metric in applied.controlledMetrics) {
        if (set.suggested[metric]?.dimension !=
            vector[set.ordinal][metric]!.dimension)
          _conflict();
        final target = slot.targets[metric],
            priorTarget = applied.slot.targets[metric];
        if (target == null ||
            priorTarget == null ||
            target.compareTo(priorTarget) != 0)
          _conflict();
        if (authored[set.slotId]![set.ordinal][metric]!.compareTo(
              previousAuthored[set.slotId]![set.ordinal][metric]!,
            ) !=
            0)
          _conflict();
      }
      final suggested = {
        ...set.suggested,
        for (final metric in applied.controlledMetrics)
          metric: vector[set.ordinal][metric]!,
      };
      sets.add(
        TrainingSet(
          id: set.id,
          slotId: set.slotId,
          role: set.role,
          ordinal: set.ordinal,
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
      final resolved = await DerivedWorkoutPreview(repository).previewPlan(
        graphId: derivedPlan.graphId,
        graphRevision: derivedPlan.graphRevision,
        planId: derivedPlan.planId,
        asOf: startedAt,
        runId: runId,
        strictHistoryStart: true,
      );
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
        final set = sets.firstWhere((item) => item.id == occurrenceId);
        final applied = set.role == 'work' ? bySlot[set.slotId] : null;
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
              prescription.definition
                  .slot(set.slotId)
                  .timing
                  ?.resolve(suggested);
              return TrainingSet(
                id: set.id,
                slotId: set.slotId,
                role: set.role,
                ordinal: set.ordinal,
                suggested: suggested,
                maxEffortMetrics: set.maxEffortMetrics,
                criteria: set.criteria,
                sources: {
                  for (final e in set.sources.entries)
                    if (!mapped[set.id]!.containsKey(e.key)) e.key: e.value,
                },
              );
            }(),
      ];
      derivedInput = DerivedPlanInput.fromJson({
        'reference': derivedPlan.toJson(),
        'snapshot': resolved,
        if (bodyMassSources.isNotEmpty) 'bodyMassSources': bodyMassSources,
      });
    }
    next = TrainingSession(
      id: next.id,
      revision: next.revision,
      startedAt: next.startedAt,
      sets: finalSets,
      bodyMassInputs: next.bodyMassInputs,
      initialBodyMassOverrides: next.initialBodyMassOverrides,
      derivedPlanInput: derivedInput,
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

  Future<TrainingSession> edit(
    String id,
    int expectedVersion,
    TrainingSession Function(TrainingSession) change,
  ) => repository.transaction(() async {
    final current = await session(id);
    if (current.contentVersion != expectedVersion) _conflict();
    final next = change(current);
    for (final t in await repository.timingActivities()) {
      if (t.active &&
          t.sessionId == id &&
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
    validateTimingData(await repository.timingActivities(), [
      for (final s in await repository.sessions()) s.id == id ? next : s,
    ]);
    final executions = await repository.executions();
    if (next.status == SessionStatus.finalized &&
        executions.any((e) => e.sessionId == id && !e.complete))
      invalid(
        'Acknowledge all execution occurrences before finishing the session.',
      );
    validateExecutionData(executions, [
      for (final s in await repository.sessions()) s.id == id ? next : s,
    ], await repository.timingActivities());
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

Never _conflict() => throw const BodyTmiException(
  'conflict',
  'Stored content changed or identity already exists. Refresh before retrying.',
);
Never _missing(String kind) =>
    throw BodyTmiException('not_found', '$kind not found.');
