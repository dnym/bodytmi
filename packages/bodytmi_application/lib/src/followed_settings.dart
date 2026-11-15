import 'package:bodytmi_core/bodytmi_core.dart';

/// Evidence that a set's controlled actual followed its target on the
/// equipment instance it was performed on: the actual differs from the
/// target only because that instance's nearest setting does (40 lb done as
/// 17.5 kg on a kilogram stack). Derived from frozen session data, so it is
/// recomputed, never stored.
final class FollowedSetting {
  const FollowedSetting(
    this.setId,
    this.metric,
    this.target,
    this.actual,
    this.instance,
  );
  final String setId, metric;
  final Quantity target, actual;
  final LoadInstanceReference instance;

  Map<String, Object?> toJson() => {
    'setId': setId,
    'metric': metric,
    'target': target.toJson(),
    'actual': actual.toJson(),
    'instanceId': instance.instanceId,
    'instanceRevision': instance.revision,
  };
}

/// The completed [sets] whose [levers] actual is not the target but is the
/// nearest setting to it on the instance the set was performed on (its own
/// `performedOn`, else the session's binding for its slot).
List<FollowedSetting> followedSettings(
  TrainingSession session,
  Iterable<TrainingSet> sets,
  Set<String> levers,
) => [
  for (final set in sets)
    if (set.status == SetStatus.completed)
      if (session.instanceOf(set) case final instance?)
        for (final metric in levers)
          if ((set.suggested[metric], set.actuals[metric])
              case (final target?, final actual?)
              when actual.compareTo(target) != 0 &&
                  followsOn(
                    instance.snapshot,
                    target,
                    actual,
                    loading: set.availableLoading,
                  ))
            FollowedSetting(set.id, metric, target, actual, instance),
];

/// Evaluation-only copies of [sets] in which each followed actual reads as
/// its target, so every progression rule treats it as following the plan
/// and keeps progressing in the track's own unit.
List<TrainingSet> asFollowed(
  List<TrainingSet> sets,
  List<FollowedSetting> followed,
) {
  if (followed.isEmpty) return sets;
  return [
    for (final set in sets)
      if (followed.where((f) => f.setId == set.id).toList() case final mine
          when mine.isNotEmpty)
        TrainingSet(
          id: set.id,
          slotId: set.slotId,
          role: set.role,
          ordinal: set.ordinal,
          suggested: set.suggested,
          sources: set.sources,
          manualTargets: set.manualTargets,
          carriedTargets: set.carriedTargets,
          status: set.status,
          actuals: {...set.actuals, for (final f in mine) f.metric: f.target},
          contentVersion: set.contentVersion,
          timing: set.timing,
          observations: set.observations,
          loadArrangement: set.loadArrangement,
          performedOn: set.performedOn,
          unavailablePlates: set.unavailablePlates,
          maxEffortMetrics: set.maxEffortMetrics,
          criteria: set.criteria,
          substitution: set.substitution,
          settings: set.settings,
          actualSettings: set.actualSettings,
        )
      else
        set,
  ];
}
