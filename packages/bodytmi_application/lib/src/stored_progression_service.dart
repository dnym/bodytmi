import 'package:bodytmi_core/bodytmi_core.dart';
import 'progression_decision.dart';
import 'progression_reconciliation.dart';
import 'role_progression_preview.dart';
import 'canonical_json.dart';
import 'training_repository.dart';

final class StoredProgressionService {
  const StoredProgressionService(this.repository);
  final TrainingRepository repository;

  /// Preview against the current durable lineage without writing a decision.
  Future<Map<String, Object?>> previewFromTrack(
    String sessionId,
    String slotId,
    Map<String, Object?> rule, {
    String ruleType = 'double',
    String role = 'work',
  }) => repository.transaction(() async {
    if (!{'work', 'warmup', 'backoff', 'drop'}.contains(role))
      invalid('Unknown progression role.');
    if (ruleType == 'double') {
      DoubleProgressionRule.fromJson(rule);
    } else if (ruleType == 'threshold') {
      ThresholdRule.fromJson(rule);
    } else {
      invalid('Unknown stored progression rule type.');
    }
    final session = await StoredTrainingService(repository).session(sessionId);
    final candidates = session.revision.definition.slots.where(
      (s) => s.id == slotId,
    );
    if (candidates.isEmpty) invalid('Unknown progression slot.');
    final runId = (await repository.sessionPrograms())
        .where((b) => b.sessionId == sessionId)
        .firstOrNull
        ?.runId;
    final all = await repository.progressionDecisions();
    final existing = all
        .where(
          (d) =>
              d.session.id == sessionId && d.slotId == slotId && d.role == role,
        )
        .firstOrNull;
    if (existing?.resolvedAt != null)
      _conflict('This exposure is already resolved; use progression show.');
    final before = latestApplication(
      all,
      session.revision.definition.id,
      candidates.single,
      runId: runId,
      role: role,
    );
    if (before != null &&
        (before.ruleType != ruleType ||
            canonicalJson(before.rule) != canonicalJson(rule) ||
            !matchesSessionProgressionBaseline(
              session,
              slotId,
              role,
              before.controlledMetrics,
              before,
            ))) {
      _reconcileRequired(session, slotId, role, before, ruleType, rule);
    }
    final preview = const RoleProgressionPreview().evaluate(
      session: session,
      slotId: slotId,
      role: role,
      ruleType: ruleType,
      rule: rule,
      failedSessions: before?.failedSessions ?? 0,
      cursor: before?.cursor ?? 0,
    );
    return {
      ...preview,
      'policy': 'bodytmi-stored-progression-preview/1',
      'stateSource': {
        'runId': runId,
        'previousApplication': before?.id,
        'previousSequence': before?.sequence ?? 0,
        'previousResolvedAt': before?.resolvedAt?.toUtc().toIso8601String(),
        'previousResolvedAfterSessionStart':
            before?.resolvedAt?.isAfter(session.startedAt) ?? false,
        'previousInputsChanged': before == null ? false : await stale(before),
        'pendingVersion': existing?.version,
        'pendingStale': existing == null ? null : await stale(existing),
      },
    };
  });

  /// Explains every explicit difference between a candidate prescription,
  /// existing session and rule and the latest resolved track. This writes
  /// nothing and reconciles nothing; it only names the reconciliation kinds
  /// that `store start` and `progression propose` would require.
  Future<Map<String, Object?>> reconcileStatus({
    required String templateId,
    required int revision,
    required String slotId,
    required DateTime asOf,
    String role = 'work',
    String? runId,
    String? sessionId,
    Map<String, Object?>? rule,
    String ruleType = 'double',
  }) => repository.transaction(() async {
    identifier({'id': templateId}, 'id');
    identifier({'id': slotId}, 'id');
    if (revision < 1 || !effortRoles.contains(role))
      invalid('Invalid progression reconciliation revision or role.');
    if (runId != null) {
      identifier({'id': runId}, 'id');
      if (!(await repository.programRuns()).any((run) => run.id == runId)) {
        throw const BodyTmiException('not_found', 'Program run not found.');
      }
    }
    if (rule != null) {
      if (ruleType == 'double') {
        DoubleProgressionRule.fromJson(rule);
      } else if (ruleType == 'threshold') {
        ThresholdRule.fromJson(rule);
      } else {
        invalid('Unknown stored progression rule type.');
      }
    }
    final prescription = await StoredTrainingService(
      repository,
    ).revision(templateId, revision);
    final slots = prescription.definition.slots.where((s) => s.id == slotId);
    if (slots.isEmpty) invalid('Unknown progression slot.');
    TrainingSession? session;
    String? sessionRunId;
    if (sessionId != null) {
      session = await StoredTrainingService(repository).session(sessionId);
      sessionRunId = (await repository.sessionPrograms())
          .where((b) => b.sessionId == sessionId)
          .firstOrNull
          ?.runId;
      if (runId != null && runId != sessionRunId)
        invalid('Candidate session belongs to another program run.');
    }
    final decisions = (await repository.progressionDecisions()).where(
      (d) =>
          d.resolvedAt != null &&
          !d.resolvedAt!.isAfter(asOf) &&
          d.session.startedAt.isBefore(asOf),
    );
    final latest = latestApplication(
      decisions,
      templateId,
      slots.single,
      runId: runId,
      role: role,
    );
    final assessment = assessProgressionReconciliation(
      prescription: prescription,
      templateId: templateId,
      revision: revision,
      slotId: slotId,
      role: role,
      track: latest,
      session: session,
      runId: runId,
      asOf: asOf,
      ruleType: ruleType,
      rule: rule,
    );
    final kinds = {for (final blocker in assessment.blockers) blocker.kind};
    return {
      ...assessment.toJson(),
      'inputsChanged': latest == null ? false : await stale(latest),
      'blockedCommands': {
        'store start': [
          for (final kind in _startReconciliationKinds)
            if (kinds.contains(kind)) kind,
        ],
        'progression propose': [
          for (final kind in _proposeReconciliationKinds)
            if (kinds.contains(kind)) kind,
        ],
      },
    };
  });

  /// Inspect the latest resolved track at a session-start cutoff. This does not
  /// assert that a new prescription is compatible with the stored baseline.
  Future<Map<String, Object?>> track({
    required String templateId,
    required int revision,
    required String slotId,
    required DateTime asOf,
    String? runId,
    String role = 'work',
  }) => repository.transaction(() async {
    identifier({'id': templateId}, 'id');
    identifier({'id': slotId}, 'id');
    if (revision < 1 || !{'work', 'warmup', 'backoff', 'drop'}.contains(role))
      invalid('Invalid progression track revision or role.');
    if (runId != null) {
      identifier({'id': runId}, 'id');
      if (!(await repository.programRuns()).any((run) => run.id == runId)) {
        throw const BodyTmiException('not_found', 'Program run not found.');
      }
    }
    final prescription = await StoredTrainingService(
      repository,
    ).revision(templateId, revision);
    final slots = prescription.definition.slots.where((s) => s.id == slotId);
    if (slots.isEmpty) invalid('Unknown progression slot.');
    final decisions = (await repository.progressionDecisions()).where(
      (d) =>
          d.resolvedAt != null &&
          !d.resolvedAt!.isAfter(asOf) &&
          d.session.startedAt.isBefore(asOf),
    );
    final latest = latestApplication(
      decisions,
      templateId,
      slots.single,
      runId: runId,
      role: role,
    );
    return {
      'policy': 'bodytmi-progression-track/1',
      'asOf': asOf.toUtc().toIso8601String(),
      'templateId': templateId,
      'revision': revision,
      'slotId': slotId,
      'role': role,
      'runId': runId,
      'resolved': latest != null,
      if (latest != null) ...{
        'decisionId': latest.id,
        'sourceSessionId': latest.session.id,
        'sourceContentVersion': latest.session.contentVersion,
        'sourceRevision': latest.session.revision.number,
        'resolvedAt': latest.resolvedAt!.toUtc().toIso8601String(),
        'status': latest.status,
        'inputsChanged': await stale(latest),
        'sequence': latest.sequence,
        'ruleType': latest.ruleType,
        'rule': latest.rule,
        'controlledMetrics': latest.controlledMetrics.toList()..sort(),
        'state': {
          'failedSessions': latest.failedSessions,
          if (latest.ruleType == 'threshold') 'cursor': latest.cursor,
          'nextSets': [
            for (final set in latest.nextSets)
              metricsToJson({
                for (final metric in latest.controlledMetrics)
                  metric: set[metric]!,
              }),
          ],
        },
      },
    };
  });

  Future<ProgressionDecision> propose(
    String sessionId,
    String slotId,
    Map<String, Object?> rule, {
    String ruleType = 'double',
    String role = 'work',
  }) => repository.transaction(() async {
    if (!{'work', 'warmup', 'backoff', 'drop'}.contains(role))
      invalid('Unknown progression role.');
    if (ruleType == 'double') {
      DoubleProgressionRule.fromJson(rule);
    } else if (ruleType == 'threshold') {
      ThresholdRule.fromJson(rule);
    } else {
      invalid('Unknown stored progression rule type.');
    }
    final all = await repository.progressionDecisions();
    final existing = all
        .where(
          (d) =>
              d.session.id == sessionId && d.slotId == slotId && d.role == role,
        )
        .firstOrNull;
    if (existing?.resolvedAt != null) {
      if (existing!.ruleType != ruleType ||
          canonicalJson(existing.rule) != canonicalJson(rule))
        _conflict('This exposure already resolved a different rule.');
      return existing;
    }
    final session = await StoredTrainingService(repository).session(sessionId);
    final runId = (await repository.sessionPrograms())
        .where((b) => b.sessionId == sessionId)
        .firstOrNull
        ?.runId;
    final candidates = session.revision.definition.slots.where(
      (s) => s.id == slotId,
    );
    if (candidates.isEmpty) invalid('Unknown progression slot.');
    final before = latestApplication(
      all,
      session.revision.definition.id,
      candidates.single,
      runId: runId,
      role: role,
    );
    if (before != null &&
        (before.ruleType != ruleType ||
            canonicalJson(before.rule) != canonicalJson(rule) ||
            !matchesSessionProgressionBaseline(
              session,
              slotId,
              role,
              before.controlledMetrics,
              before,
            )))
      _reconcileRequired(session, slotId, role, before, ruleType, rule);
    final next = ProgressionDecision(
      session: session,
      slotId: slotId,
      rule: rule,
      previousApplication: before?.id,
      previousSequence: before?.sequence ?? 0,
      previousFailures: before?.failedSessions ?? 0,
      version: (existing?.version ?? 0) + 1,
      runId: runId,
      ruleType: ruleType,
      previousCursor: before?.cursor ?? 0,
      role: role,
    );
    final comparable = next.toJson()
      ..['version'] = existing?.version ?? next.version;
    if (existing != null &&
        canonicalJson(existing.toJson()) == canonicalJson(comparable))
      return existing;
    await repository.saveProgressionDecision(next);
    return next;
  });

  Future<ProgressionDecision> decision(
    String sessionId,
    String slotId, {
    String role = 'work',
  }) async {
    if (!{'work', 'warmup', 'backoff', 'drop'}.contains(role))
      invalid('Unknown progression role.');
    final rows = await repository.progressionDecisions();
    return rows
            .where(
              (d) =>
                  d.session.id == sessionId &&
                  d.slotId == slotId &&
                  d.role == role,
            )
            .firstOrNull ??
        (throw const BodyTmiException(
          'not_found',
          'Progression decision not found.',
        ));
  }

  Future<bool> stale(ProgressionDecision decision) async {
    final runId = (await repository.sessionPrograms())
        .where((b) => b.sessionId == decision.session.id)
        .firstOrNull
        ?.runId;
    if (decision.runId != runId) return true;
    final source = await repository.session(decision.session.id);
    if (source == null ||
        canonicalJson(source.toJson()) !=
            canonicalJson(decision.session.toJson()))
      return true;
    if (decision.resolvedAt != null) return false;
    final latest = latestApplication(
      await repository.progressionDecisions(),
      decision.session.revision.definition.id,
      decision.slot,
      runId: runId,
      role: decision.role,
    );
    return latest?.id != decision.previousApplication;
  }

  Future<ProgressionDecision> accept(
    String sessionId,
    String slotId,
    int expectedVersion,
    DateTime at, {
    String role = 'work',
  }) => repository.transaction(() async {
    final pending = await decision(sessionId, slotId, role: role);
    if (pending.version != expectedVersion)
      _conflict('Progression decision version changed.');
    if (pending.acceptedAt != null) return pending;
    if (pending.declinedAt != null)
      _conflict('This exposure was already declined.');
    if (await stale(pending))
      _conflict('Progression inputs changed; propose again before acceptance.');
    if (pending.previousApplication != null) {
      final base = (await repository.progressionDecisions()).firstWhere(
        (d) => d.id == pending.previousApplication,
      );
      if (at.isBefore(base.resolvedAt!))
        invalid('Acceptance cannot precede its base application.');
    }
    final applied = pending.accept(at);
    await repository.saveProgressionDecision(applied);
    return applied;
  });

  Future<ProgressionDecision> decline(
    String sessionId,
    String slotId,
    int expectedVersion,
    DateTime at, {
    String role = 'work',
  }) => repository.transaction(() async {
    final pending = await decision(sessionId, slotId, role: role);
    if (pending.version != expectedVersion)
      _conflict('Progression decision version changed.');
    if (pending.declinedAt != null) return pending;
    if (pending.acceptedAt != null)
      _conflict('This exposure was already accepted.');
    if (await stale(pending))
      _conflict('Progression inputs changed; propose again before declining.');
    if (pending.previousApplication != null) {
      final base = (await repository.progressionDecisions()).firstWhere(
        (d) => d.id == pending.previousApplication,
      );
      if (at.isBefore(base.resolvedAt!))
        invalid('Decline cannot precede its base application.');
    }
    final declined = pending.decline(at);
    await repository.saveProgressionDecision(declined);
    return declined;
  });

  /// Enforcement stays with the predicates above; this only explains them with
  /// the same comparison that `progression reconcile-status` reports.
  Never _reconcileRequired(
    TrainingSession session,
    String slotId,
    String role,
    ProgressionDecision before,
    String ruleType,
    Map<String, Object?> rule,
  ) {
    final assessment = assessProgressionReconciliation(
      prescription: session.revision,
      templateId: session.revision.definition.id,
      revision: session.revision.number,
      slotId: slotId,
      role: role,
      track: before,
      session: session,
      runId: before.runId,
      ruleType: ruleType,
      rule: rule,
    );
    if (!assessment.required)
      _conflict(
        'Session prescription or rule differs from the latest applied '
        'progression; explicit reconciliation is required.',
      );
    throw reconciliationConflict(
      assessment,
      context: 'Progression ${session.id}',
    );
  }
}

/// Kinds that stop a later `store start` from consuming the stored track.
const _startReconciliationKinds = [
  'workingSetCount',
  'slotTarget',
  'metricDimension',
  'effortTarget',
  'objectiveCriteria',
];

/// Kinds that stop `progression propose` from continuing the stored lineage.
const _proposeReconciliationKinds = [
  'workingSetCount',
  'effortTarget',
  'objectiveCriteria',
  'sessionTarget',
  'rule',
];

Never _conflict(String message) => throw BodyTmiException('conflict', message);
