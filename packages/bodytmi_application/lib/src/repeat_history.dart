import 'package:bodytmi_core/bodytmi_core.dart';
import 'repeat_checkpoint.dart';

/// Read-only results from repeat ledgers associated with training sessions.
final class RepeatHistory {
  const RepeatHistory();

  Map<String, Object?> series(
    List<RepeatCheckpoint> checkpoints,
    List<TrainingSession> sessions, {
    Map<String, String> runBySession = const {},
    String? sessionId,
    String? runId,
    String? metric,
    DateTime? from,
    DateTime? until,
    bool includeWarmups = false,
    bool includeActive = false,
  }) {
    for (final value in [sessionId, runId, metric]) {
      if (value != null) identifier({'id': value}, 'id');
    }
    if (from != null && until != null && !from.isBefore(until)) {
      invalid('Series from must precede exclusive until.');
    }
    final byId = {for (final session in sessions) session.id: session};
    if (byId.length != sessions.length ||
        checkpoints.map((c) => c.id).toSet().length != checkpoints.length ||
        runBySession.keys.any((id) => !byId.containsKey(id))) {
      invalid('Repeat series sources need unique IDs and known run bindings.');
    }
    for (final run in runBySession.values) identifier({'id': run}, 'id');
    validateRepeatSessionBindings(checkpoints, sessions);
    final ordered = checkpoints.where((c) => c.sessionId != null).toList()
      ..sort((a, b) {
        final left = byId[a.sessionId]!;
        final right = byId[b.sessionId]!;
        final date = left.startedAt.compareTo(right.startedAt);
        if (date != 0) return date;
        final session = left.id.compareTo(right.id);
        return session != 0 ? session : a.id.compareTo(b.id);
      });
    final rows = <Object?>[];
    var count = 0;
    for (final checkpoint in ordered) {
      final session = byId[checkpoint.sessionId]!;
      final run = runBySession[session.id];
      if ((sessionId != null && sessionId != session.id) ||
          (runId != null && runId != run) ||
          (!includeActive && session.status != SessionStatus.finalized) ||
          (from != null && session.startedAt.isBefore(from)) ||
          (until != null && !session.startedAt.isBefore(until)))
        continue;
      final execution = checkpoint.execution;
      final cursor = jsonObject(execution['cursor'], 'cursor');
      final loop = WindowRepeatSpec.fromJson(cursor['loop']);
      final plan = loop.roundDefinition.plan.occurrences().toList();
      final entries = jsonList(execution, 'entries');
      final points = <Object?>[];
      for (var i = 0; i < entries.length; i++) {
        final entry = jsonObject(entries[i], 'entry');
        if (entry['outcome'] != 'completed') continue;
        final effort = plan[i % plan.length].activity as Effort;
        if (!includeWarmups && effort.role == 'warmup') continue;
        final slot = loop.roundDefinition.slot(effort.slotId);
        final actuals = metricsFromJson(entry['actuals']);
        for (final name in (actuals.keys.toList()..sort())) {
          if (metric != null && name != metric) continue;
          if (++count > 10000) {
            invalid('Repeat series exceeds 10000 points; narrow its filters.');
          }
          final observations = entry['observations'];
          points.add({
            'occurrenceId': entry['id'],
            'round': i ~/ plan.length,
            'index': i % plan.length,
            'slotId': slot.id,
            'exercise': slot.exerciseId,
            'implementation': slot.implementation,
            'equipment': slot.equipmentId,
            'setupNote': slot.setupNote,
            'role': effort.role,
            'metric': name,
            'actual': actuals[name]!.toJson(),
            if (observations != null) 'observations': observations,
            'performanceEligible':
                observations == null ||
                !SetObservations.fromJson(observations).interrupted,
            if (entry['reportedAfterBoundary'] == true)
              'reportedAfterBoundary': true,
          });
        }
      }
      if (points.isEmpty) continue;
      rows.add({
        'checkpointId': checkpoint.id,
        'checkpointVersion': checkpoint.version,
        'executionVersion': execution['version'],
        'executionStatus': cursor['status'],
        'sessionId': session.id,
        'sessionContentVersion': session.contentVersion,
        'sessionStatus': session.status.name,
        'runId': run,
        'templateId': session.revision.definition.id,
        'revision': session.revision.number,
        'sessionStartedAt': session.startedAt.toUtc().toIso8601String(),
        'sessionFinishedAt': session.finishedAt?.toUtc().toIso8601String(),
        'loop': loop.toJson(),
        'points': points,
      });
    }
    return {
      'policy': {
        'id': 'bodytmi-repeat-series/1',
        'dateBasis': 'sessionStartedAt',
        'occurrenceTimes': 'unrecorded',
        'sessionId': sessionId,
        'runId': runId,
        'metric': metric,
        'from': from?.toUtc().toIso8601String(),
        'until': until?.toUtc().toIso8601String(),
        'includeWarmups': includeWarmups,
        'includeActive': includeActive,
      },
      'series': rows,
    };
  }
}
