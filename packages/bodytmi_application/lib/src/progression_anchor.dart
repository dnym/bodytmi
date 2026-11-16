import 'package:bodytmi_core/bodytmi_core.dart';
import 'canonical_json.dart';
import 'progression_decision.dart';
import 'shared_track_view.dart';

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

  /// Categorical levers this track moves (ordinal levels with settings).
  Set<String> get controlledSettings;

  /// Per working set, the categorical settings later sessions consume for
  /// [controlledSettings]; other levers keep the plan's values.
  List<Map<String, String>> get nextSettings;
  String get ruleType;
  Map<String, Object?> get rule;
  int get sequence;
  int get failedSessions;
  int get cursor;
  String? get previousApplication;
  int get previousSequence;
  int get previousFailures;
  int get previousCursor;

  /// Cycle-restart reference state (staged threshold rules), or null.
  Metrics? get cycleReference;
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

/// Resolves an anchor's pinned definition [prior] under the current session's
/// variant [selections], restricted to the variants [prior] declares. Null
/// when the prior revision cannot express that same structure, which callers
/// treat as requiring reconciliation.
WorkoutDefinition? resolveAlike(
  WorkoutDefinition prior,
  Map<String, String> selections,
) {
  try {
    if (!prior.hasVariants) return selections.isEmpty ? prior : null;
    final ids = {for (final v in prior.variants) v.id};
    return prior.resolveVariants({
      for (final e in selections.entries)
        if (ids.contains(e.key)) e.key: e.value,
    });
  } on BodyTmiException {
    return null;
  }
}

/// Whether every working set of [vector] holds the same controlled values.
bool uniformVector(List<Metrics> vector, Set<String> metrics) =>
    vector.isNotEmpty &&
    vector.every(
      (set) => metrics.every(
        (m) =>
            set[m] != null &&
            vector.first[m] != null &&
            set[m]!.dimension == vector.first[m]!.dimension &&
            set[m]!.compareTo(vector.first[m]!) == 0,
      ),
    );

/// Whether the session plans a different variant branch for [slotId] than
/// the anchor's frozen sets: a structural (set scheme) change. [current] is
/// the authored (unresolved) definition, which still declares its variants.
bool structureMoved(
  ProgressionAnchor anchor,
  WorkoutDefinition current,
  String slotId,
  Map<String, String> currentSettings,
) {
  final prior = anchor.sets.firstOrNull?.settings ?? const {};
  return current
      .variantLevers(slotId)
      .any((lever) => prior[lever] != currentSettings[lever]);
}

/// A structural change may resize the controlled vector only when it is
/// uniform, so every set of the new structure receives the same values.
/// Returns whether [count] sets consume [anchor] by broadcasting its first
/// set; throws nothing and decides nothing else.
bool broadcastsVector(
  ProgressionAnchor anchor,
  WorkoutDefinition current,
  String slotId,
  Map<String, String> currentSettings,
  int count,
) =>
    anchor.nextSets.length != count &&
    structureMoved(anchor, current, slotId, currentSettings) &&
    uniformVector(anchor.nextSets, anchor.controlledMetrics);

/// The same broadcast rule for an ordinal track's progressed settings.
List<Map<String, String>> resizedSettings(
  List<Map<String, String>> settings,
  int count,
) {
  if (settings.length == count || settings.isEmpty) return settings;
  final first = canonicalJson(settings.first);
  if (settings.any((s) => canonicalJson(s) != first)) return settings;
  return List.filled(count, settings.first);
}

/// The instance the track last progressed on: the anchoring decision's
/// frozen session binding for its slot. Receipts and retirements record no
/// instance, so they never separate a visit from the usual equipment.
LoadInstanceReference? anchorInstance(ProgressionAnchor? anchor) {
  final local = anchor is SharedTrackView ? anchor.local : anchor;
  if (local is! ProgressionDecision) return null;
  return local.session.loadInputs[local.slotId]?.instance;
}
