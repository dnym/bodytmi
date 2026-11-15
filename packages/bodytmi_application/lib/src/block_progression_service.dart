import 'package:bodytmi_core/bodytmi_core.dart';

import 'block_progression.dart';
import 'canonical_json.dart';
import 'repeat_checkpoint.dart';
import 'training_repository.dart';

Never _conflict(String message) => throw BodyTmiException('conflict', message);

/// Durable AMRAP block progression. A finished session's block exposure is
/// proposed once per round slot; accepting or declining it is an immutable
/// receipt that later `repeat-checkpoint start-block` calls consume for the
/// same run, template, block and round slot.
final class BlockProgressionService {
  const BlockProgressionService(this.repository);
  final TrainingRepository repository;

  Future<BlockProgressionDecision?> _find(String id) async =>
      (await repository.blockProgressions())
          .where((d) => d.id == id)
          .firstOrNull;

  Future<BlockProgressionDecision> show(
    String sessionId,
    String amrapId,
    String roundSlotId,
  ) async =>
      await _find(blockDecisionId(sessionId, amrapId, roundSlotId)) ??
      (throw const BodyTmiException(
        'not_found',
        'Block progression decision not found.',
      ));

  /// The checkpoint, session and run that a decision is derived from.
  Future<
    ({RepeatCheckpoint checkpoint, TrainingSession session, String? runId})
  >
  _exposure(String sessionId, String amrapId) async {
    final session =
        await repository.session(sessionId) ??
        (throw const BodyTmiException('not_found', 'Session not found.'));
    if (session.status != SessionStatus.finalized)
      invalid('Block progression needs a finished session.');
    final checkpoint =
        (await repository.repeatCheckpoints())
            .where((c) => c.sessionId == sessionId && c.amrapId == amrapId)
            .firstOrNull ??
        (throw const BodyTmiException(
          'not_found',
          'The session has no checkpoint for this AMRAP block.',
        ));
    final runId = (await repository.sessionPrograms())
        .where((b) => b.sessionId == sessionId)
        .firstOrNull
        ?.runId;
    return (checkpoint: checkpoint, session: session, runId: runId);
  }

  Future<BlockProgressionDecision> propose(
    String sessionId,
    String amrapId,
    String roundSlotId,
    BlockProgressionRule rule,
  ) => repository.transaction(() async {
    final (:checkpoint, :session, :runId) = await _exposure(sessionId, amrapId);
    final loop = WindowRepeatSpec.fromJson(
      jsonObject(checkpoint.execution['cursor'], 'cursor')['loop'],
    );
    rule.validateFor(loop, roundSlotId);
    final id = blockDecisionId(sessionId, amrapId, roundSlotId);
    final existing = await _find(id);
    if (existing != null && existing.status != 'pending') return existing;
    // The base is what this block actually started with, and its lineage.
    final targets = {
      for (final metric in rule.increments.keys)
        metric: loop.roundDefinition.slot(roundSlotId).targets[metric]!,
    };
    final anchorId = checkpoint.blockTargets[roundSlotId]?.decisionId;
    final anchor = anchorId == null ? null : await _find(anchorId);
    if (anchorId != null && anchor?.resolvedAt == null)
      invalid('The block start names an unresolved decision.');
    final failures = anchor?.resolvedFailures ?? 0;
    final evaluation = evaluateBlockExposure(
      checkpoint,
      roundSlotId,
      rule,
      targets,
      failures,
    );
    final next = BlockProgressionDecision.fromJson({
      'schemaVersion': 1,
      'id': id,
      'version': (existing?.version ?? 0) + 1,
      'sessionId': sessionId,
      'runId': runId,
      'templateId': session.definition.id,
      'revision': session.revision.number,
      'amrapId': amrapId,
      'roundSlotId': roundSlotId,
      'sessionStartedAt': session.startedAt.toUtc().toIso8601String(),
      'rule': rule.toJson(),
      'source': {
        'checkpointId': checkpoint.id,
        'checkpointVersion': checkpoint.version,
        'executionVersion': checkpoint.execution['version'],
      },
      'score': {
        'confirmedRounds': evaluation.confirmedRounds,
        'partialRounds': evaluation.partialRounds,
      },
      'base': {
        'anchorId': anchorId,
        'targets': metricsToJson(targets),
        'failedSessions': failures,
      },
      'outcome': evaluation.outcome,
      'reason': evaluation.reason,
      'proposed': {
        'targets': metricsToJson(evaluation.proposedTargets),
        'failedSessions': evaluation.proposedFailures,
      },
      'status': 'pending',
      'sequence': (anchor?.sequence ?? 0) + 1,
    });
    if (existing != null &&
        canonicalJson({...existing.toJson(), 'version': next.version}) ==
            canonicalJson(next.toJson()))
      return existing;
    await repository.saveBlockProgression(next);
    return next;
  });

  /// Whether a pending decision's source changed since it was proposed.
  Future<bool> stale(BlockProgressionDecision decision) async {
    final checkpoint = (await repository.repeatCheckpoints())
        .where((c) => c.id == decision.source['checkpointId'])
        .firstOrNull;
    return checkpoint == null ||
        checkpoint.version != decision.source['checkpointVersion'] ||
        checkpoint.execution['version'] != decision.source['executionVersion'];
  }

  Future<BlockProgressionDecision> resolve(
    String sessionId,
    String amrapId,
    String roundSlotId, {
    required int expectedVersion,
    required DateTime at,
    required bool accept,
  }) => repository.transaction(() async {
    final current = await show(sessionId, amrapId, roundSlotId);
    if (current.status != 'pending') {
      if (current.status == (accept ? 'accepted' : 'declined') &&
          current.version == expectedVersion + 1)
        return current; // lost-response retry of the same resolution
      _conflict('This block exposure is already resolved.');
    }
    if (current.version != expectedVersion)
      _conflict('Block progression decision version changed.');
    if (await stale(current))
      _conflict('The block results changed since proposal; propose again.');
    final latest = latestBlockDecision(
      await repository.blockProgressions(),
      current.trackKey,
    );
    if (latest?.id != current.anchorId)
      _conflict(
        'Another exposure of this block track resolved since this block '
        'started; its targets no longer follow this result.',
      );
    if (latest != null && at.isBefore(latest.resolvedAt!))
      invalid('A resolution cannot precede the previous one.');
    final json = current.toJson();
    final outcome = current.outcome;
    if (accept && {'unknown', 'review'}.contains(outcome))
      invalid('Unknown or review exposures can only be declined.');
    final base = jsonObject(json['base'], 'base');
    final proposed = jsonObject(json['proposed'], 'proposed');
    final baseFailures = base['failedSessions']! as int;
    final Map<String, Object?> resolved = accept
        ? proposed
        : {
            'targets': base['targets'],
            'failedSessions': switch (outcome) {
              'failed' || 'deload' => baseFailures + 1,
              'unknown' || 'review' => baseFailures,
              'blocked' => proposed['failedSessions'],
              _ => 0,
            },
          };
    final next = BlockProgressionDecision.fromJson({
      ...json,
      'version': current.version + 1,
      'status': accept ? 'accepted' : 'declined',
      'resolvedAt': at.toUtc().toIso8601String(),
      'resolved': resolved,
    });
    await repository.saveBlockProgression(next);
    return next;
  });

  /// Read-only resolved state of one track as of [asOf].
  Future<Map<String, Object?>> track({
    required String templateId,
    required String amrapId,
    required String roundSlotId,
    String? runId,
    required DateTime asOf,
  }) => repository.transaction(() async {
    final latest = latestBlockDecision(
      await repository.blockProgressions(),
      blockTrackKey(runId, templateId, amrapId, roundSlotId),
      asOf: asOf,
    );
    return {
      'policy': blockProgressionPolicy,
      'runId': runId,
      'templateId': templateId,
      'amrapId': amrapId,
      'roundSlotId': roundSlotId,
      'asOf': asOf.toUtc().toIso8601String(),
      'source': latest == null ? 'authored' : 'decision',
      'decisionId': latest?.id,
      'targets': latest == null ? null : metricsToJson(latest.resolvedTargets),
      'failedSessions': latest?.resolvedFailures ?? 0,
    };
  });
}

/// Archive/backup validation of block decisions and the accepted targets
/// that block checkpoints consumed.
void validateBlockProgressions(
  List<BlockProgressionDecision> decisions,
  List<RepeatCheckpoint> checkpoints,
  List<TrainingSession> sessions,
  List<SessionProgramBinding> bindings,
) {
  final byId = {for (final d in decisions) d.id: d};
  if (byId.length != decisions.length)
    invalid('Duplicate block progression decision.');
  final sessionsById = {for (final s in sessions) s.id: s};
  final runs = {for (final b in bindings) b.sessionId: b.runId};
  for (final d in decisions) {
    final session = sessionsById[d.sessionId];
    if (session == null || session.status != SessionStatus.finalized)
      invalid('A block decision needs its finished session.');
    if (session.definition.id != d.templateId ||
        runs[d.sessionId] != d.runId ||
        session.definition.amrap(d.amrapId) == null)
      invalid('A block decision does not match its session.');
    if (!checkpoints.any(
      (c) =>
          c.id == d.source['checkpointId'] &&
          c.sessionId == d.sessionId &&
          c.amrapId == d.amrapId,
    ))
      invalid('A block decision source checkpoint is missing.');
    final anchorId = d.anchorId;
    if (anchorId == null) {
      if (d.sequence != 1) invalid('A block decision lineage is broken.');
      continue;
    }
    final anchor = byId[anchorId];
    if (anchor == null ||
        anchor.resolvedAt == null ||
        anchor.trackKey != d.trackKey ||
        anchor.sequence + 1 != d.sequence)
      invalid('A block decision lineage is broken.');
  }
  for (final c in checkpoints) {
    if (c.blockTargets.isEmpty) continue;
    final session = sessionsById[c.sessionId]!;
    for (final entry in c.blockTargets.entries) {
      final d = byId[entry.value.decisionId];
      if (d == null ||
          d.resolvedAt == null ||
          d.resolvedAt!.isAfter(session.startedAt) ||
          d.trackKey !=
              blockTrackKey(
                runs[session.id],
                session.definition.id,
                c.amrapId!,
                entry.key,
              ) ||
          canonicalJson(metricsToJson(d.resolvedTargets)) !=
              canonicalJson(metricsToJson(entry.value.targets)))
        invalid('Block targets do not match an accepted decision.');
    }
  }
}
