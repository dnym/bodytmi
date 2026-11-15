import 'package:bodytmi_core/bodytmi_core.dart';
import 'canonical_json.dart';
import 'training_repository.dart';
import 'training_service.dart';
import 'derived_target_graph_service.dart';

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
      final ref = node.derivedPlan;
      if (ref != null) {
        final graph = await DerivedTargetGraphService(
          repository,
        ).revision(ref.graphId, ref.graphRevision);
        final matches = graph.graph.plans.where(
          (plan) => plan.id == ref.planId,
        );
        if (matches.length != 1 ||
            matches.single.templateId != node.templateId ||
            matches.single.revision != node.revision) {
          invalid(
            'Program day derived plan does not match its workout revision.',
          );
        }
      }
    }
    if (definition.hasPrescriptionOverrides &&
        definition.plan.nodes.any(
          (node) => node is ProgramDay && node.derivedPlan != null,
        )) {
      invalid(
        'Programs cannot combine day derived plans with prescription overrides.',
      );
    }
    for (final node in definition.plan.nodes) {
      for (final override in node.overrides) {
        var applies = false;
        for (final occurrence in node.occurrences()) {
          final revision = await StoredTrainingService(
            repository,
          ).revision(occurrence.day.templateId, occurrence.day.revision);
          if (!revision.definition.slots.any((s) => s.id == override.slotId)) {
            continue;
          }
          for (final role in const ['work', 'warmup', 'backoff', 'drop']) {
            if (revision.definition
                .roleTargets(override.slotId, role)
                .any((targets) => targets.containsKey(override.metric))) {
              applies = true;
              break;
            }
          }
          if (applies) break;
        }
        if (!applies) {
          invalid(
            'Prescription overrides require an authored target for their '
            'slot metric under the declaring program node.',
          );
        }
      }
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

  /// Read the authored days ahead of one run without resolving or advancing it.
  Future<Map<String, Object?>> schedule(
    String runId, {
    int count = 10,
    bool includeScopes = false,
  }) => repository.transaction(() async {
    identifier({'runId': runId}, 'runId');
    if (count < 1 || count > 1000)
      invalid('Schedule count must be between 1 and 1000.');
    final current = await run(runId);
    final cycle = current.program.definition.plan.occurrences().toList();
    // Positions, not ordinals, name the program days (jumps move them).
    final start = current.positionAt(current.cursor);
    final available = current.loop ? count : cycle.length - start;
    final length = available < count ? available : count;
    final scopesByIndex = <int, List<ProgramScope>>{};
    if (includeScopes && length > 0) {
      final needed = {
        for (var offset = 0; offset < length; offset++)
          (start + offset) % cycle.length,
      };
      var index = 0;
      for (final occurrence
          in current.program.definition.plan.scopedOccurrences()) {
        if (needed.contains(index)) scopesByIndex[index] = occurrence.scopes;
        if (scopesByIndex.length == needed.length) break;
        index++;
      }
    }
    final bindings = await repository.sessionPrograms();
    final currentSession = bindings
        .where(
          (binding) =>
              binding.runId == runId && binding.ordinal == current.cursor,
        )
        .firstOrNull
        ?.sessionId;
    return {
      'policy': includeScopes
          ? 'bodytmi-program-run-schedule/2'
          : 'bodytmi-program-run-schedule/1',
      'runId': current.id,
      'programId': current.program.definition.id,
      'programRevision': current.program.number,
      'runVersion': current.contentVersion,
      'status': current.status,
      'loop': current.loop,
      'cursor': current.cursor,
      'cycleLength': cycle.length,
      'requestedCount': count,
      'remaining': current.loop ? null : available,
      'hasMore': current.loop || available > length,
      'days': [
        for (var offset = 0; offset < length; offset++)
          () {
            final ordinal = current.cursor + offset;
            final position = start + offset;
            final occurrence = cycle[position % cycle.length];
            final scoped = current.program.definition.hasPrescriptionOverrides
                ? current.program.definition.effectiveOverrides(occurrence.path)
                : const <ScopedProgramOverride>[];
            return {
              'ordinal': ordinal,
              'cycle': position ~/ cycle.length,
              'index': position % cycle.length,
              ...occurrence.toJson(),
              if (scoped.isNotEmpty)
                'effectiveOverrides': [
                  for (final override in scoped) override.toJson(),
                ],
              if (includeScopes)
                'scopes': [
                  for (final scope in scopesByIndex[position % cycle.length]!)
                    scope.toJson(),
                ],
              if (offset == 0 && currentSession != null)
                'sessionId': currentSession,
            };
          }(),
      ],
    };
  });

  Future<ProgramRun> create(
    String id,
    String programId,
    int number,
    DateTime at, {
    required bool loop,
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

  /// Explicitly re-pin one run onto another published revision of the same
  /// program. The receipt records the cursor, so completed days stay bound
  /// to the revision they ran under (see [programRevisionAt]); the current
  /// day must be resolved first, and no cursor state changes.
  Future<ProgramUpgradeReceipt> upgrade(
    String runId,
    int expectedVersion,
    int toRevision,
    String requestId,
    DateTime at,
  ) => repository.transaction(() async {
    identifier({'id': requestId}, 'id');
    if (toRevision < 1) invalid('Program upgrade revision must be positive.');
    final current = await run(runId);
    final prior = (await repository.programUpgrades())
        .where((u) => u.runId == runId && u.requestId == requestId)
        .firstOrNull;
    if (prior != null) {
      if (prior.toRevision != toRevision || prior.occurredAt != at)
        programConflict(
          'Upgrade request identity was reused with different inputs.',
        );
      return prior;
    }
    if (current.contentVersion != expectedVersion)
      programConflict('Run version changed.');
    if (current.status == 'completed')
      programConflict(
        'Completed finite runs cannot upgrade; create a new run.',
      );
    if (at.isBefore(current.startedAt))
      invalid('Upgrade cannot precede its program run.');
    final target = await revision(current.program.definition.id, toRevision);
    if (target.number == current.program.number)
      programConflict('Run already pins this program revision.');
    if (!current.loop &&
        target.definition.dayCount <= current.positionAt(current.cursor))
      programConflict(
        'Program upgrade must publish enough days to hold the run cursor.',
      );
    // Completed days may differ in the new revision: they stay bound to the
    // revision recorded for their ordinal. The cycle length must hold so
    // that the cursor keeps its place in the cycle.
    if (current.cursor > 0 &&
        current.program.definition.dayCount != target.definition.dayCount)
      programConflict(
        'Program upgrade cannot change cycle length after a run has advanced.',
      );
    if ((await repository.sessionPrograms()).any(
      (b) => b.runId == runId && b.ordinal == current.cursor,
    ))
      programConflict(
        'Current program day already has a session; finish or skip it '
        'before upgrading.',
      );
    final receipt = ProgramUpgradeReceipt(
      runId: runId,
      programId: current.program.definition.id,
      fromRevision: current.program.number,
      toRevision: target.number,
      cursor: current.cursor,
      occurredAt: at,
      requestId: requestId,
    );
    await repository.insertProgramUpgrade(receipt);
    await repository.saveProgramRun(current.repinned(target));
    return receipt;
  });

  /// Explicitly move a run's cursor to the program day at [dayPath]: back to
  /// repeat days (a week after a break), or ahead to skip them without
  /// recording each skip. History, receipts and bindings stay as they are;
  /// later occurrences simply continue from that day. A looping run stays in
  /// its current cycle. A finished finite run reopens when moved back. The
  /// current day must have no session yet. Retrying a request ID returns
  /// the same run; reusing it with other inputs conflicts.
  Future<ProgramRun> jump(
    String runId,
    int expectedVersion,
    String dayPath,
    String requestId,
    DateTime at,
  ) => repository.transaction(() async {
    identifier({'id': requestId}, 'id');
    final current = await run(runId);
    final cycle = current.program.definition.plan.occurrences().toList();
    final index = cycle.indexWhere((o) => o.path == dayPath);
    if (index < 0)
      invalid('No day of the pinned program revision has path $dayPath.');
    final here = current.positionAt(current.cursor);
    final position = current.loop ? here - here % cycle.length + index : index;
    final prior = current.jumps
        .where((j) => j.requestId == requestId)
        .firstOrNull;
    if (prior != null) {
      if (prior.position != position || prior.at != at)
        programConflict('Jump request identity was reused with other inputs.');
      return current;
    }
    if (current.contentVersion != expectedVersion)
      programConflict('Run version changed.');
    if (at.isBefore(current.startedAt) ||
        (current.jumps.isNotEmpty && at.isBefore(current.jumps.last.at)))
      invalid('A jump cannot precede its run or an earlier jump.');
    if (position == here)
      programConflict('The run is already at this program day.');
    if ((await repository.sessionPrograms()).any(
      (b) => b.runId == runId && b.ordinal == current.cursor,
    ))
      programConflict(
        'Current program day already has a session; finish or skip it '
        'before moving the run.',
      );
    final next = current.withJump(
      RunJump(
        ordinal: current.cursor,
        position: position,
        requestId: requestId,
        at: at,
      ),
    );
    await repository.saveProgramRun(next);
    return next;
  });

  Future<List<ProgramUpgradeReceipt>> upgrades(String runId) =>
      repository.transaction(() async {
        identifier({'id': runId}, 'id');
        await run(runId);
        final upgrades =
            (await repository.programUpgrades())
                .where((u) => u.runId == runId)
                .toList()
              ..sort((a, b) {
                final time = a.occurredAt.compareTo(b.occurredAt);
                return time == 0 ? a.requestId.compareTo(b.requestId) : time;
              });
        return upgrades;
      });

  Future<TrainingSession> start(
    String runId,
    int expectedVersion,
    String sessionId,
    DateTime at, {
    Map<String, BodyMassOverride> bodyMassOverrides = const {},
    DerivedPlanRef? derivedPlan,
    Map<String, String> loadBindings = const {},
    Map<String, LoadConvention> loadConventions = const {},
    Map<String, Map<String, String>> variantSettings = const {},
  }) => repository.transaction(() async {
    final current = await run(runId);
    final bindings = await repository.sessionPrograms();
    final existing = bindings
        .where((b) => b.sessionId == sessionId)
        .firstOrNull;
    if (existing != null) {
      final session = await StoredTrainingService(
        repository,
      ).session(sessionId);
      final pinned = current.dayAtOrdinal(existing.ordinal).day.derivedPlan;
      if (pinned != null &&
          derivedPlan != null &&
          canonicalJson(pinned.toJson()) != canonicalJson(derivedPlan.toJson()))
        programConflict('Program day pins another derived plan.');
      final effectivePlan = pinned ?? derivedPlan;
      if (existing.runId != runId ||
          session.startedAt != at ||
          !sameBodyMassOverrides(session, bodyMassOverrides) ||
          !sameLoadInputs(session, loadBindings, loadConventions) ||
          canonicalJson(session.derivedPlanInput?.reference.toJson()) !=
              canonicalJson(effectivePlan?.toJson()))
        programConflict('Session identity belongs to another occurrence.');
      requireFrozenPrescriptionOverrides(
        session,
        current.program.definition,
        existing.path,
      );
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
    final pinned = day.day.derivedPlan;
    if (pinned != null &&
        derivedPlan != null &&
        canonicalJson(pinned.toJson()) != canonicalJson(derivedPlan.toJson()))
      programConflict('Program day pins another derived plan.');
    return await StoredTrainingService(repository).start(
      sessionId,
      day.day.templateId,
      day.day.revision,
      at,
      programRun: current,
      bodyMassOverrides: bodyMassOverrides,
      derivedPlan: pinned ?? derivedPlan,
      loadBindings: loadBindings,
      loadConventions: loadConventions,
      variantSettings: variantSettings,
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

/// The upgrade chain of one run, oldest first.
List<ProgramUpgradeReceipt> upgradeChain(
  List<ProgramUpgradeReceipt> upgrades,
  String runId,
) => upgrades.where((u) => u.runId == runId).toList()
  ..sort((a, b) {
    final time = a.occurredAt.compareTo(b.occurredAt);
    return time == 0 ? a.requestId.compareTo(b.requestId) : time;
  });

/// The program revision number a run pinned for the day at [ordinal]:
/// the creation pin, replaced by each upgrade made at or before it.
int programRevisionAt(
  ProgramRun run,
  List<ProgramUpgradeReceipt> chain,
  int ordinal,
) {
  if (chain.isEmpty) return run.program.number;
  var number = chain.first.fromRevision;
  for (final u in chain) {
    if (ordinal >= u.cursor) number = u.toRevision;
  }
  return number;
}

void validateProgramData({
  required List<ProgramRevision> programs,
  required List<ProgramRun> runs,
  required List<ProgramUpgradeReceipt> upgrades,
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
  final chains = {
    for (final run in runs) run.id: upgradeChain(upgrades, run.id),
  };
  ProgramDefinition pinnedAt(ProgramRun run, int ordinal) {
    final number = programRevisionAt(run, chains[run.id]!, ordinal);
    final program = programMap['${run.program.definition.id}/$number'];
    if (program == null)
      invalid('Program upgrade refers to a missing run or revision.');
    return program.definition;
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
        (!run.loop &&
            run.positionAt(b.ordinal) >= run.program.definition.dayCount) ||
        session.startedAt.isBefore(run.startedAt))
      invalid('Invalid program session binding.');
    final day = pinnedAt(run, b.ordinal).dayAt(run.positionAt(b.ordinal));
    if (day.path != b.path ||
        day.day.templateId != session.definition.id ||
        day.day.revision != session.revision.number ||
        (day.day.derivedPlan != null &&
            canonicalJson(day.day.derivedPlan!.toJson()) !=
                canonicalJson(session.derivedPlanInput?.reference.toJson())))
      invalid('Program session prescription or path mismatch.');
  }
  for (final s in sessions) {
    if (s.prescriptionOverrides.isEmpty) continue;
    final binding = bySession[s.id];
    if (binding == null)
      invalid('Prescription override sessions require a program binding.');
    final run = runMap[binding.runId]!;
    final candidates = [
      run.program,
      for (final p in programs)
        if (p.definition.id == run.program.definition.id &&
            p.number != run.program.number)
          p,
    ];
    final pinned = workoutMap['${s.definition.id}/${s.revision.number}'];
    if (pinned == null)
      invalid('Program session prescription overrides lack their revision.');
    final pure = const TrainingService().start(
      sessionId: s.id,
      revision: pinned,
      startedAt: s.startedAt,
    );
    var matched = false;
    for (final candidate in candidates) {
      try {
        final expected = applyPrescriptionOverrides(
          pinned.definition,
          pure.sets,
          candidate.definition.effectiveOverrides(binding.path),
        ).records;
        if (canonicalJson([for (final r in expected) r.toJson()]) ==
            canonicalJson([
              for (final r in s.prescriptionOverrides) r.toJson(),
            ]))
          matched = true;
      } on BodyTmiException {
        continue;
      }
      if (matched) break;
    }
    if (!matched)
      invalid(
        'Program session prescription overrides do not match a published plan.',
      );
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
        r.path !=
            pinnedAt(run, r.ordinal).dayAt(run.positionAt(r.ordinal)).path)
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

/// Check durable explicit run re-pins: every upgrade names one run and two
/// published revisions of its own program, times are strictly increasing,
/// each upgrade continues the previous chain, and the run's current pin is
/// exactly the newest target. Creation-time pins are not receipted.
void validateProgramUpgrades(
  List<ProgramRevision> programs,
  List<ProgramRun> runs,
  List<ProgramUpgradeReceipt> upgrades,
) {
  final programMap = <String, ProgramRevision>{
    for (final p in programs) '${p.definition.id}/${p.number}': p,
  };
  final runMap = {for (final r in runs) r.id: r};
  final identities = <String>{};
  final byRun = <String, List<ProgramUpgradeReceipt>>{};
  for (final u in upgrades) {
    if (!identities.add('${u.runId}/${u.requestId}'))
      invalid('Duplicate program upgrade request identity.');
    final run = runMap[u.runId];
    if (run == null ||
        u.programId != run.program.definition.id ||
        !programMap.containsKey('${u.programId}/${u.fromRevision}') ||
        !programMap.containsKey('${u.programId}/${u.toRevision}') ||
        u.occurredAt.isBefore(run.startedAt))
      invalid('Program upgrade refers to a missing run or revision.');
    byRun.putIfAbsent(u.runId, () => []).add(u);
  }
  for (final entry in byRun.entries) {
    final rows = entry.value
      ..sort((a, b) {
        final time = a.occurredAt.compareTo(b.occurredAt);
        return time == 0 ? a.requestId.compareTo(b.requestId) : time;
      });
    for (var i = 1; i < rows.length; i++) {
      if (!rows[i].occurredAt.isAfter(rows[i - 1].occurredAt) ||
          rows[i].fromRevision != rows[i - 1].toRevision ||
          rows[i].cursor < rows[i - 1].cursor) {
        invalid('Program upgrade chain is inconsistent.');
      }
    }
    if (rows.last.cursor > runMap[entry.key]!.cursor)
      invalid('Program upgrade cursor is ahead of its run.');
    if (rows.last.toRevision != runMap[entry.key]!.program.number)
      invalid('Program run pin does not match its upgrade chain.');
  }
}

/// Check pinned day plans even when no run or session has yet been created.
void validateProgramPlanReferences(
  List<ProgramRevision> programs,
  List<DerivedTargetGraphRevision> graphs,
) {
  final byId = {
    for (final graph in graphs) '${graph.graph.id}:${graph.number}': graph,
  };
  for (final program in programs) {
    for (final day in program.definition.plan.nodes.whereType<ProgramDay>()) {
      final ref = day.derivedPlan;
      if (ref == null) continue;
      final graph = byId['${ref.graphId}:${ref.graphRevision}'];
      if (graph == null)
        invalid('Program derived plan graph revision is missing.');
      final plans = graph.graph.plans.where((plan) => plan.id == ref.planId);
      if (plans.length != 1 ||
          plans.single.templateId != day.templateId ||
          plans.single.revision != day.revision) {
        invalid(
          'Program day derived plan does not match its workout revision.',
        );
      }
    }
  }
}
