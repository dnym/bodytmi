import 'package:bodytmi_core/bodytmi_core.dart';
import 'canonical_json.dart';
import 'training_repository.dart';

final class ProgramService {
  const ProgramService(this.repository);
  final TrainingRepository repository;

  Future<ProgramRevision> revision(String id, [int? number]) async {
    final matches =
        (await repository.programRevisions())
            .where(
              (p) =>
                  p.definition.id == id &&
                  (number == null || p.number == number),
            )
            .toList()
          ..sort((a, b) => b.number.compareTo(a.number));
    return matches.firstOrNull ??
        (throw const BodyTmiException(
          'not_found',
          'Program revision not found.',
        ));
  }

  Future<ProgramRevision> publish(
    ProgramDefinition definition,
    int expectedRevision,
  ) => repository.transaction(() async {
    final previous =
        (await repository.programRevisions())
            .where((p) => p.definition.id == definition.id)
            .toList()
          ..sort((a, b) => b.number.compareTo(a.number));
    if ((previous.firstOrNull?.number ?? 0) != expectedRevision)
      programConflict('Program revision changed.');
    for (final node in definition.plan.nodes.whereType<ProgramDay>()) {
      await StoredTrainingService(
        repository,
      ).revision(node.templateId, node.revision);
    }
    final next = ProgramRevision.publish(
      definition,
      previous: previous.firstOrNull,
    );
    await repository.insertProgramRevision(next);
    return next;
  });
  Future<ProgramRun> run(String id) async =>
      (await repository.programRuns()).where((r) => r.id == id).firstOrNull ??
      (throw const BodyTmiException('not_found', 'Program run not found.'));
  Future<ProgramRun> create(
    String id,
    String programId,
    int number,
    DateTime at, {
    bool loop = true,
  }) => repository.transaction(() async {
    final existing = (await repository.programRuns())
        .where((r) => r.id == id)
        .firstOrNull;
    if (existing != null) {
      if (existing.program.definition.id != programId ||
          existing.program.number != number ||
          existing.startedAt != at ||
          existing.loop != loop)
        programConflict('Run identity already exists with other inputs.');
      return existing;
    }
    final next = ProgramRun(
      id: id,
      program: await revision(programId, number),
      startedAt: at,
      loop: loop,
    );
    await repository.saveProgramRun(next);
    return next;
  });
  Future<ProgramRun> status(String id, int expectedVersion, String status) =>
      repository.transaction(() async {
        if (!{'active', 'paused'}.contains(status))
          invalid('Run status must be active or paused.');
        final current = await run(id);
        if (current.contentVersion != expectedVersion)
          programConflict('Run version changed.');
        if (current.status == 'completed')
          programConflict(
            'Completed finite runs cannot resume; create a new run.',
          );
        if (current.status == status) return current;
        final next = current.changed(status: status);
        await repository.saveProgramRun(next);
        return next;
      });
  Future<TrainingSession> start(
    String runId,
    int expectedVersion,
    String sessionId,
    DateTime at,
  ) => repository.transaction(() async {
    final current = await run(runId);
    final bindings = await repository.sessionPrograms();
    final existing = bindings
        .where((b) => b.sessionId == sessionId)
        .firstOrNull;
    if (existing != null) {
      final session = await StoredTrainingService(
        repository,
      ).session(sessionId);
      if (existing.runId != runId || session.startedAt != at)
        programConflict('Session identity belongs to another occurrence.');
      return session;
    }
    if (current.status != 'active' || current.contentVersion != expectedVersion)
      programConflict('Run is not active or its version changed.');
    if (at.isBefore(current.startedAt))
      invalid('Session cannot precede its program run.');
    if ((await repository.programReceipts())
        .where((r) => r.runId == runId)
        .any((r) => r.occurredAt.isAfter(at)))
      invalid('Session cannot precede an earlier program receipt.');
    if (bindings.any((b) => b.runId == runId && b.ordinal == current.cursor))
      programConflict(
        'Current program day already has a session; resume that session.',
      );
    final day = current.current!;
    return await StoredTrainingService(repository).start(
      sessionId,
      day.day.templateId,
      day.day.revision,
      at,
      programRun: current,
    );
  });
  Future<ProgramReceipt> skip(
    String runId,
    int expectedVersion,
    String requestId,
    DateTime at,
  ) => repository.transaction(() async {
    identifier({'id': requestId}, 'id');
    final prior = (await repository.programReceipts())
        .where((r) => r.runId == runId && r.requestId == requestId)
        .firstOrNull;
    if (prior != null) {
      if (prior.occurredAt != at)
        programConflict(
          'Skip request identity was reused with different inputs.',
        );
      return prior;
    }
    final current = await run(runId);
    if (current.contentVersion != expectedVersion || current.status != 'active')
      programConflict('Run is not active or its version changed.');
    if (at.isBefore(current.startedAt))
      invalid('Skip cannot precede its program run.');
    final receipts = (await repository.programReceipts()).where(
      (r) => r.runId == runId,
    );
    if (receipts.any((r) => r.occurredAt.isAfter(at)))
      invalid('Skip cannot precede an earlier occurrence receipt.');
    if ((await repository.sessionPrograms()).any(
      (b) => b.runId == runId && b.ordinal == current.cursor,
    ))
      programConflict(
        'Current day has a session; finish it before skipping another day.',
      );
    final receipt = ProgramReceipt(
      runId: runId,
      ordinal: current.cursor,
      path: current.current!.path,
      occurredAt: at,
      requestId: requestId,
    );
    await repository.insertProgramReceipt(receipt);
    await repository.saveProgramRun(current.changed(advance: true));
    return receipt;
  });

  /// Called inside the same transaction that saves finalized results.
  Future<void> finalized(TrainingSession session) async {
    final binding = (await repository.sessionPrograms())
        .where((b) => b.sessionId == session.id)
        .firstOrNull;
    if (binding == null) return;
    final receipts = await repository.programReceipts();
    if (receipts.any((r) => r.sessionId == session.id)) return;
    final current = await run(binding.runId);
    if (current.cursor != binding.ordinal || current.status == 'completed')
      programConflict('Program cursor no longer owns this session.');
    if (receipts
        .where((r) => r.runId == current.id)
        .any((r) => r.occurredAt.isAfter(session.finishedAt!)))
      invalid('Session finish cannot precede an earlier program receipt.');
    await repository.insertProgramReceipt(
      ProgramReceipt(
        runId: binding.runId,
        ordinal: binding.ordinal,
        path: binding.path,
        occurredAt: session.finishedAt!,
        sessionId: session.id,
      ),
    );
    await repository.saveProgramRun(current.changed(advance: true));
  }
}

Never programConflict(String message) =>
    throw BodyTmiException('conflict', message);

void validateProgramData({
  required List<ProgramRevision> programs,
  required List<ProgramRun> runs,
  required List<SessionProgramBinding> bindings,
  required List<ProgramReceipt> receipts,
  required List<WorkoutRevision> revisions,
  required List<TrainingSession> sessions,
  required List<String> finalizations,
}) {
  final workoutMap = {
    for (final r in revisions) '${r.definition.id}/${r.number}': r,
  };
  final programMap = <String, ProgramRevision>{};
  final numbers = <String, int>{};
  final sorted = [...programs]
    ..sort((a, b) {
      final d = a.definition.id.compareTo(b.definition.id);
      return d == 0 ? a.number.compareTo(b.number) : d;
    });
  for (final p in sorted) {
    if (p.number != (numbers[p.definition.id] ?? 0) + 1)
      invalid('Program revisions must be unique and contiguous.');
    numbers[p.definition.id] = p.number;
    programMap['${p.definition.id}/${p.number}'] = p;
    for (final day in p.definition.plan.nodes.whereType<ProgramDay>()) {
      if (!workoutMap.containsKey('${day.templateId}/${day.revision}'))
        invalid('Program refers to missing workout revision.');
    }
  }
  final runMap = <String, ProgramRun>{};
  for (final run in runs) {
    if (runMap.containsKey(run.id)) invalid('Duplicate program run.');
    runMap[run.id] = run;
    final program =
        programMap['${run.program.definition.id}/${run.program.number}'];
    if (program == null ||
        canonicalJson(program.toJson()) != canonicalJson(run.program.toJson()))
      invalid('Run program snapshot is inconsistent.');
  }
  final sessionMap = {for (final s in sessions) s.id: s};
  final bySession = <String, SessionProgramBinding>{};
  final byBoundOccurrence = <String, SessionProgramBinding>{};
  final occupied = <String>{};
  for (final b in bindings) {
    final run = runMap[b.runId];
    final session = sessionMap[b.sessionId];
    if (bySession.containsKey(b.sessionId) ||
        !occupied.add('${b.runId}/${b.ordinal}'))
      invalid('Duplicate program session binding.');
    bySession[b.sessionId] = b;
    byBoundOccurrence['${b.runId}/${b.ordinal}'] = b;
    if (run == null ||
        session == null ||
        b.ordinal > run.cursor ||
        (!run.loop && b.ordinal >= run.program.definition.dayCount) ||
        session.startedAt.isBefore(run.startedAt))
      invalid('Invalid program session binding.');
    final day = run.program.definition.dayAt(b.ordinal);
    if (day.path != b.path ||
        day.day.templateId != session.revision.definition.id ||
        day.day.revision != session.revision.number)
      invalid('Program session prescription or path mismatch.');
  }
  for (final s in sessions) {
    final owner = bySession[s.id]?.runId;
    for (final set in s.sets)
      for (final source in set.sources.values) {
        if (bySession[source.sessionId]?.runId != owner)
          invalid('Session history cannot cross program-run ownership.');
      }
  }
  final byOccurrence = <String, ProgramReceipt>{};
  final operations = <String>{};
  final byRun = <String, List<ProgramReceipt>>{};
  for (final r in receipts) {
    final run = runMap[r.runId];
    final key = '${r.runId}/${r.ordinal}';
    if (byOccurrence.containsKey(key) ||
        !operations.add('${r.runId}/${r.operationKey}'))
      invalid('Duplicate program advancement receipt.');
    byOccurrence[key] = r;
    byRun.putIfAbsent(r.runId, () => []).add(r);
    if (run == null ||
        r.ordinal >= run.cursor ||
        r.occurredAt.isBefore(run.startedAt) ||
        r.path != run.program.definition.dayAt(r.ordinal).path)
      invalid('Program receipt path or cursor mismatch.');
    final bound = byBoundOccurrence[key];
    if (r.sessionId == null) {
      if (bound != null)
        invalid('Skipped program day cannot also own a session.');
    } else {
      if (bound?.sessionId != r.sessionId ||
          !finalizations.contains(r.sessionId) ||
          sessionMap[r.sessionId]?.status != SessionStatus.finalized ||
          r.occurredAt.isBefore(sessionMap[r.sessionId]!.startedAt))
        invalid('Program completion has no matching finalized session.');
    }
  }
  for (final b in bindings) {
    final receipt = byOccurrence['${b.runId}/${b.ordinal}'];
    final session = sessionMap[b.sessionId]!;
    final previous = byOccurrence['${b.runId}/${b.ordinal - 1}'];
    if (previous != null && session.startedAt.isBefore(previous.occurredAt))
      invalid('Session precedes the previous program receipt.');
    if (b.ordinal < runMap[b.runId]!.cursor &&
        receipt?.sessionId != b.sessionId)
      invalid('Advanced program session has no receipt.');
    if (session.status == SessionStatus.finalized &&
        receipt?.sessionId != b.sessionId)
      invalid('Finalized program session has no advancement receipt.');
  }
  for (final run in runs) {
    final rows = byRun[run.id] ?? [];
    rows.sort((a, b) => a.ordinal.compareTo(b.ordinal));
    if (rows.length != run.cursor)
      invalid('Program cursor lacks its occurrence receipts.');
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].ordinal != i ||
          (i > 0 && rows[i].occurredAt.isBefore(rows[i - 1].occurredAt)))
        invalid('Program receipt sequence is inconsistent.');
    }
  }
}
