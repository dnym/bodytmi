import 'package:bodytmi_core/bodytmi_core.dart';
import 'training_service.dart';
import 'training_archive.dart';
import 'progression_decision.dart';
import 'program_service.dart';
import 'canonical_json.dart';
import 'stored_body_mass_service.dart';
import 'timing_service.dart';
import 'execution_service.dart';

/// One repository transaction is the durability boundary of each operation.
abstract interface class TrainingRepository {
  Future<T> transaction<T>(Future<T> Function() action);
  Future<WorkoutRevision?> revision(String templateId, [int? number]);
  Future<List<WorkoutRevision>> revisions();
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
          !sameBodyMassOverrides(existing, bodyMassOverrides))
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
          d.acceptedAt != null &&
          !d.acceptedAt!.isAfter(startedAt) &&
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
    for (final set in next.sets) {
      final applied = set.role == 'work' ? bySlot[set.slotId] : null;
      if (applied == null) {
        sets.add(set);
        continue;
      }
      final rule = DoubleProgressionRule.fromJson(applied.rule);
      final vector = applied.proposal.nextSets;
      final count = workingCounts[set.slotId];
      if (vector.length != count) _conflict();
      final slot = prescription.definition.slot(set.slotId);
      for (final metric in [rule.objective, rule.lever]) {
        if (set.suggested[metric]?.dimension !=
            vector[set.ordinal][metric]!.dimension)
          _conflict();
        if (slot.targets[metric]!.compareTo(applied.slot.targets[metric]!) != 0)
          _conflict();
      }
      final suggested = {
        ...set.suggested,
        rule.objective: vector[set.ordinal][rule.objective]!,
        rule.lever: vector[set.ordinal][rule.lever]!,
      };
      sets.add(
        TrainingSet(
          id: set.id,
          slotId: set.slotId,
          role: set.role,
          ordinal: set.ordinal,
          suggested: suggested,
          sources: {
            for (final e in set.sources.entries)
              if (e.key != rule.objective && e.key != rule.lever)
                e.key: e.value,
          },
        ),
      );
    }
    next = TrainingSession(
      id: next.id,
      revision: next.revision,
      startedAt: next.startedAt,
      sets: sets,
      bodyMassInputs: next.bodyMassInputs,
    );
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
) =>
    overrides.keys.every((k) => session.bodyMassInputs.containsKey(k)) &&
    session.bodyMassInputs.entries.every(
      (e) => e.value.sameOverride(overrides[e.key]),
    );

Never _conflict() => throw const BodyTmiException(
  'conflict',
  'Stored content changed or identity already exists. Refresh before retrying.',
);
Never _missing(String kind) =>
    throw BodyTmiException('not_found', '$kind not found.');
