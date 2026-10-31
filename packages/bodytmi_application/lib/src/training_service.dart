import 'package:bodytmi_core/bodytmi_core.dart';

final class TrainingService {
  const TrainingService();

  TrainingSession start({
    required String sessionId,
    required WorkoutRevision revision,
    required DateTime startedAt,
    List<TrainingSession> history = const [],
  }) {
    identifier({'id': sessionId}, 'id');
    if (history.any((s) => s.id == sessionId))
      invalid('Session ID already occurs in supplied history.');
    final compatibleHistory =
        history
            .where(
              (s) =>
                  s.status == SessionStatus.finalized &&
                  s.revision.definition.id == revision.definition.id &&
                  s.startedAt.isBefore(startedAt) &&
                  s.finishedAt != null &&
                  !s.finishedAt!.isAfter(startedAt),
            )
            .toList()
          ..sort((a, b) {
            final date = b.startedAt.compareTo(a.startedAt);
            return date == 0 ? a.id.compareTo(b.id) : date;
          });
    final ordinals = <String, int>{};
    final sets = <TrainingSet>[];
    for (final occurrence in revision.definition.plan.occurrences()) {
      final effort = occurrence.activity;
      if (effort is! Effort) continue;
      final slot = revision.definition.slot(effort.slotId);
      final ordinalKey = '${slot.id}:${effort.role}';
      final ordinal = ordinals.update(
        ordinalKey,
        (v) => v + 1,
        ifAbsent: () => 0,
      );
      final suggested = <String, Quantity>{...slot.targets};
      final sources = <String, HistorySource>{};
      if (effort.role != 'warmup') {
        for (final metric in slot.prefillMetrics) {
          search:
          for (final past in compatibleHistory) {
            final oldSlots = past.revision.definition.slots.where(
              (s) => slot.compatibleWith(s),
            );
            if (oldSlots.isEmpty) continue;
            for (final set in past.sets) {
              final value = set.actuals[metric];
              if (set.slotId == slot.id &&
                  set.role == effort.role &&
                  set.ordinal == ordinal &&
                  set.status == SetStatus.completed &&
                  value != null &&
                  value.dimension == suggested[metric]!.dimension) {
                suggested[metric] = value;
                sources[metric] = HistorySource(
                  past.id,
                  set.id,
                  set.contentVersion,
                );
                break search;
              }
            }
          }
        }
      }
      sets.add(
        TrainingSet(
          id: occurrence.id,
          slotId: slot.id,
          role: effort.role,
          ordinal: ordinal,
          suggested: suggested,
          sources: sources,
        ),
      );
    }
    return TrainingSession(
      id: sessionId,
      revision: revision,
      startedAt: startedAt,
      sets: sets,
    );
  }

  TrainingSession complete(
    TrainingSession session,
    String setId,
    Metrics actuals, {
    bool acceptSuggested = false,
  }) => session.replaceSet(
    session.set(setId).complete(actuals, acceptSuggested: acceptSuggested),
  );

  TrainingSession skip(
    TrainingSession session,
    String setId, {
    bool confirm = false,
  }) => session.replaceSet(session.set(setId).skip(confirm: confirm));
}
