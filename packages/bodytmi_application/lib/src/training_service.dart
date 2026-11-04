import 'package:bodytmi_core/bodytmi_core.dart';
import 'canonical_json.dart';

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
              effort.maxEffortMetrics.contains(metric) ||
              effort.criteria[metric]?.mode == 'observe')
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
                  set.criteria[metric]?.mode != 'observe' &&
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
          criteria: effort.criteria,
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

  /// Explicitly recapture slot mass inputs at the original session cutoff.
  TrainingSession refreshBodyMass(
    TrainingSession session,
    List<BodyMassMeasurement> measurements, {
    required bool confirm,
  }) {
    if (!confirm) invalid('Refreshing body mass requires confirm:true.');
    if (session.status != SessionStatus.active ||
        session.sets.any((set) => set.status != SetStatus.planned)) {
      invalid(
        'Body mass can only be refreshed before any effort is completed or skipped.',
      );
    }
    if (session.bodyMassInputs.isEmpty)
      invalid('Session has no configured body mass inputs.');
    final refreshed = <String, BodyMassInputSnapshot>{
      for (final entry in session.bodyMassInputs.entries)
        entry.key: BodyMassInputSnapshot.capture(
          selection: entry.value.selection,
          asOf: session.startedAt,
          measurements: measurements,
          override: entry.value.override,
        ),
    };
    if (canonicalJson({
          for (final e in refreshed.entries) e.key: e.value.toJson(),
        }) ==
        canonicalJson({
          for (final e in session.bodyMassInputs.entries)
            e.key: e.value.toJson(),
        }))
      return session;
    return TrainingSession(
      id: session.id,
      revision: session.revision,
      startedAt: session.startedAt,
      sets: session.sets,
      status: session.status,
      finishedAt: session.finishedAt,
      contentVersion: session.contentVersion + 1,
      bodyMassInputs: refreshed,
      initialBodyMassOverrides: session.initialBodyMassOverrides,
      derivedPlanInput: session.derivedPlanInput,
    );
  }

  /// Replace explicitly selected slot overrides while retaining start identity.
  TrainingSession rebindBodyMass(
    TrainingSession session,
    List<BodyMassMeasurement> measurements,
    Map<String, BodyMassOverride?> updates, {
    required bool confirm,
  }) {
    if (!confirm) invalid('Rebinding body mass requires confirm:true.');
    if (session.status != SessionStatus.active ||
        session.sets.any((set) => set.status != SetStatus.planned)) {
      invalid(
        'Body mass can only be rebound before any effort is completed or skipped.',
      );
    }
    if (updates.isEmpty ||
        updates.keys.any((id) => !session.bodyMassInputs.containsKey(id)))
      invalid('Rebinding requires configured body-mass slot IDs.');
    final changedOverride = updates.entries.any(
      (entry) => !session.bodyMassInputs[entry.key]!.sameOverride(entry.value),
    );
    final original =
        session.initialBodyMassOverrides ??
        (changedOverride
            ? {
                for (final entry in session.bodyMassInputs.entries)
                  if (entry.value.override != null)
                    entry.key: entry.value.override!,
              }
            : null);
    final inputs = <String, BodyMassInputSnapshot>{
      for (final entry in session.bodyMassInputs.entries)
        entry.key: updates.containsKey(entry.key)
            ? BodyMassInputSnapshot.capture(
                selection: entry.value.selection,
                asOf: session.startedAt,
                measurements: measurements,
                override: updates[entry.key],
              )
            : entry.value,
    };
    if (canonicalJson({
              for (final e in inputs.entries) e.key: e.value.toJson(),
            }) ==
            canonicalJson({
              for (final e in session.bodyMassInputs.entries)
                e.key: e.value.toJson(),
            }) &&
        (original == null) == (session.initialBodyMassOverrides == null))
      return session;
    return TrainingSession(
      id: session.id,
      revision: session.revision,
      startedAt: session.startedAt,
      sets: session.sets,
      status: session.status,
      finishedAt: session.finishedAt,
      contentVersion: session.contentVersion + 1,
      bodyMassInputs: inputs,
      initialBodyMassOverrides: original,
      derivedPlanInput: session.derivedPlanInput,
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

  /// Assess supplied criteria against current confirmed actuals without editing them.
  Map<String, Object?> assessObjectives(
    TrainingSession session,
    String setId,
    Object? objectives,
  ) {
    final set = session.set(setId);
    return {
      'source': {
        'sessionId': session.id,
        'sessionContentVersion': session.contentVersion,
        'templateId': session.revision.definition.id,
        'revision': session.revision.number,
        'setId': set.id,
        'setContentVersion': set.contentVersion,
        'slotId': set.slotId,
        'role': set.role,
        'ordinal': set.ordinal,
        'sessionStatus': session.status.name,
        'setStatus': set.status.name,
        'interrupted': set.observations?.interrupted ?? false,
        if (set.maxEffortMetrics.isNotEmpty || set.criteria.isNotEmpty)
          'authoredObjectives': set.objectivesJson,
      },
      ...const ObjectiveAssessment().evaluate(objectives, set.actuals),
    };
  }

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

  /// Skip only planned efforts; confirmed results and prior skips stay intact.
  TrainingSession skipRemaining(
    TrainingSession session, {
    required bool confirm,
  }) => _skipPlanned(session, (_) => true, confirm: confirm);

  /// Skip planned efforts in a slot, optionally limited to one effort role.
  TrainingSession skipSlot(
    TrainingSession session,
    String slotId, {
    String? role,
    required bool confirm,
  }) {
    identifier({'slotId': slotId}, 'slotId');
    if (!session.revision.definition.slots.any((slot) => slot.id == slotId)) {
      invalid('Unknown workout slot: $slotId.');
    }
    if (role != null && role != 'work' && role != 'warmup') {
      invalid('Unknown effort role.');
    }
    return _skipPlanned(
      session,
      (set) => set.slotId == slotId && (role == null || set.role == role),
      confirm: confirm,
    );
  }

  TrainingSession _skipPlanned(
    TrainingSession session,
    bool Function(TrainingSet) selected, {
    required bool confirm,
  }) {
    if (!confirm) invalid('Skipping remaining efforts requires confirm:true.');
    if (session.status != SessionStatus.active)
      invalid('Remaining efforts can only be skipped in an active session.');
    if (!session.sets.any(
      (set) => set.status == SetStatus.planned && selected(set),
    ))
      return session;
    return TrainingSession(
      id: session.id,
      revision: session.revision,
      startedAt: session.startedAt,
      sets: [
        for (final set in session.sets)
          set.status == SetStatus.planned && selected(set)
              ? set.skip(confirm: true)
              : set,
      ],
      bodyMassInputs: session.bodyMassInputs,
      initialBodyMassOverrides: session.initialBodyMassOverrides,
      derivedPlanInput: session.derivedPlanInput,
      status: session.status,
      finishedAt: session.finishedAt,
      contentVersion: session.contentVersion + 1,
    );
  }

  TrainingSession skip(
    TrainingSession session,
    String setId, {
    bool confirm = false,
  }) => session.replaceSet(session.set(setId).skip(confirm: confirm));
}
