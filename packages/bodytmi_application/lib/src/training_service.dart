import 'package:bodytmi_core/bodytmi_core.dart';

final class TrainingService {
  const TrainingService();

  TrainingSession start({
    required String sessionId,
    required WorkoutRevision revision,
    required DateTime startedAt,
    List<TrainingSession> history = const [],
    List<BodyMassMeasurement> bodyMassMeasurements = const [],
    Map<String, BodyMassOverride> bodyMassOverrides = const {},
  }) {
    identifier({'id': sessionId}, 'id');
    if (bodyMassOverrides.keys.any(
      (id) => !revision.definition.slots.any(
        (s) => s.id == id && s.bodyMass != null,
      ),
    ))
      invalid('Body-mass override names an unconfigured slot.');
    final massInputs = {
      for (final slot in revision.definition.slots)
        if (slot.bodyMass != null)
          slot.id: BodyMassInputSnapshot.capture(
            selection: slot.bodyMass!,
            asOf: startedAt,
            measurements: bodyMassMeasurements,
            override: bodyMassOverrides[slot.id],
          ),
    };
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
      final suggested = <String, Quantity>{
        ...effort.resolveTargets(slot.targets),
      };
      final sources = <String, HistorySource>{};
      if (effort.role != 'warmup') {
        for (final metric in slot.prefillMetrics) {
          if (effort.targets.containsKey(metric) ||
              effort.maxEffortMetrics.contains(metric))
            continue;
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
                  set.eligibleForPerformance &&
                  !set.maxEffortMetrics.contains(metric) &&
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
          maxEffortMetrics: effort.maxEffortMetrics,
        ),
      );
    }
    return TrainingSession(
      id: sessionId,
      revision: revision,
      startedAt: startedAt,
      sets: sets,
      bodyMassInputs: massInputs,
    );
  }

  Map<String, Object?> bodyMassStatus(
    TrainingSession session,
    List<BodyMassMeasurement> measurements,
  ) => {
    'sessionId': session.id,
    'contentVersion': session.contentVersion,
    'inputs': {
      for (final e in session.bodyMassInputs.entries)
        e.key: {
          'captured': e.value.resolution.toJson(),
          ...e.value.freshness(measurements),
        },
    },
  };

  TrainingSession complete(
    TrainingSession session,
    String setId,
    Metrics actuals, {
    bool acceptSuggested = false,
  }) => session.replaceSet(
    session.set(setId).complete(actuals, acceptSuggested: acceptSuggested),
  );

  TrainingSession annotate(
    TrainingSession session,
    String setId,
    SetObservations observations, {
    bool confirm = false,
  }) => session.replaceSet(
    session.set(setId).annotate(observations, confirm: confirm),
  );

  TrainingSession skip(
    TrainingSession session,
    String setId, {
    bool confirm = false,
  }) => session.replaceSet(session.set(setId).skip(confirm: confirm));
}
