import 'package:bodytmi_core/bodytmi_core.dart';
import 'progression_decision.dart';
import 'canonical_json.dart';
import 'training_repository.dart';

final class StoredProgressionService {
  const StoredProgressionService(this.repository);
  final TrainingRepository repository;

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
            canonicalJson(before.rule) != canonicalJson(rule)))
      _conflict('Changing an active rule requires explicit reconciliation.');
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
    if (before != null && !matchesProgressionBaseline(next, before))
      _conflict(
        'Session prescription differs from the latest applied progression; reconcile first.',
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
}

Never _conflict(String message) => throw BodyTmiException('conflict', message);
