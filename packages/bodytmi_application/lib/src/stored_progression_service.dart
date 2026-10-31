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
    Map<String, Object?> rule,
  ) => repository.transaction(() async {
    DoubleProgressionRule.fromJson(rule);
    final all = await repository.progressionDecisions();
    final existing = all.where((d) => d.id == '$sessionId/$slotId').firstOrNull;
    if (existing?.acceptedAt != null) {
      if (canonicalJson(existing!.rule) != canonicalJson(rule))
        _conflict('This exposure already applied a different rule.');
      return existing;
    }
    final session = await StoredTrainingService(repository).session(sessionId);
    final candidates = session.revision.definition.slots.where(
      (s) => s.id == slotId,
    );
    if (candidates.isEmpty) invalid('Unknown progression slot.');
    final before = latestApplication(
      all,
      session.revision.definition.id,
      candidates.single,
    );
    if (before != null && canonicalJson(before.rule) != canonicalJson(rule))
      _conflict('Changing an active rule requires explicit reconciliation.');
    final next = ProgressionDecision(
      session: session,
      slotId: slotId,
      rule: rule,
      previousApplication: before?.id,
      previousSequence: before?.sequence ?? 0,
      previousFailures: before?.proposal.failedSessions ?? 0,
      version: (existing?.version ?? 0) + 1,
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

  Future<ProgressionDecision> decision(String sessionId, String slotId) async {
    final rows = await repository.progressionDecisions();
    return rows.where((d) => d.id == '$sessionId/$slotId').firstOrNull ??
        (throw const BodyTmiException(
          'not_found',
          'Progression decision not found.',
        ));
  }

  Future<bool> stale(ProgressionDecision decision) async {
    final source = await repository.session(decision.session.id);
    if (source == null ||
        canonicalJson(source.toJson()) !=
            canonicalJson(decision.session.toJson()))
      return true;
    if (decision.acceptedAt != null) return false;
    final latest = latestApplication(
      await repository.progressionDecisions(),
      decision.session.revision.definition.id,
      decision.slot,
    );
    return latest?.id != decision.previousApplication;
  }

  Future<ProgressionDecision> accept(
    String sessionId,
    String slotId,
    int expectedVersion,
    DateTime at,
  ) => repository.transaction(() async {
    final pending = await decision(sessionId, slotId);
    if (pending.version != expectedVersion)
      _conflict('Progression decision version changed.');
    if (pending.acceptedAt != null) return pending;
    if (await stale(pending))
      _conflict('Progression inputs changed; propose again before acceptance.');
    if (pending.previousApplication != null) {
      final base = (await repository.progressionDecisions()).firstWhere(
        (d) => d.id == pending.previousApplication,
      );
      if (at.isBefore(base.acceptedAt!))
        invalid('Acceptance cannot precede its base application.');
    }
    final applied = pending.accept(at);
    await repository.saveProgressionDecision(applied);
    return applied;
  });
}

Never _conflict(String message) => throw BodyTmiException('conflict', message);
