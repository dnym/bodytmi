import 'package:bodytmi_core/bodytmi_core.dart';
import 'canonical_json.dart';

/// One durable progression baseline for a run/slot/role context. It is either a
/// resolved exposure decision or an explicit reconciliation that re-anchors the
/// track to a different prescription without publishing a workout revision.
abstract interface class ProgressionAnchor {
  String get id;
  String? get runId;
  String get role;
  String get slotId;
  ExerciseSlot get slot;
  String get templateId;
  int get revisionNumber;
  WorkoutRevision get pinnedRevision;

  /// Frozen planned sets for this slot and role, in authored order.
  List<TrainingSet> get sets;

  /// The target vector later sessions consume for these sets.
  List<Metrics> get nextSets;
  Set<String> get controlledMetrics;
  String get ruleType;
  Map<String, Object?> get rule;
  int get sequence;
  int get failedSessions;
  int get cursor;
  String? get previousApplication;
  int get previousSequence;
  int get previousFailures;
  int get previousCursor;
  DateTime? get resolvedAt;
  String get status;
  String get contextKey;
  bool matches(String templateId, ExerciseSlot candidate);
}

/// Shared identity of the progression context an anchor belongs to.
String anchorContextKey(
  String? runId,
  String templateId,
  ExerciseSlot slot,
  String role,
) => canonicalJson([
  runId,
  templateId,
  slot.id,
  slot.exerciseId,
  slot.implementation,
  slot.equipmentId,
  slot.setupNote,
  if (role != 'work') role,
]);

bool sameAnchorContext(ProgressionAnchor anchor, ProgressionAnchor other) =>
    anchor.runId == other.runId &&
    anchor.role == other.role &&
    anchor.templateId == other.templateId &&
    anchor.slot.compatibleWith(other.slot);

ProgressionAnchor? latestAnchor(
  Iterable<ProgressionAnchor> anchors,
  String templateId,
  ExerciseSlot slot, {
  String? runId,
  String role = 'work',
}) {
  ProgressionAnchor? latest;
  for (final anchor in anchors) {
    if (anchor.runId != runId ||
        anchor.role != role ||
        anchor.resolvedAt == null ||
        !anchor.matches(templateId, slot))
      continue;
    if (latest == null || anchor.sequence > latest.sequence) {
      latest = anchor;
    } else if (anchor.sequence == latest.sequence) {
      // Validated archives hold one writer per context sequence. Keep a total,
      // deterministic order anyway so an inconsistent read can never flip.
      final date = anchor.resolvedAt!.compareTo(latest.resolvedAt!);
      if (date > 0 || (date == 0 && anchor.id.compareTo(latest.id) > 0))
        latest = anchor;
    }
  }
  return latest;
}
