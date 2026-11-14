import 'package:bodytmi_core/bodytmi_core.dart';
import 'lever_link.dart';
import 'progression_anchor.dart';
import 'shared_lever_application.dart';

/// The effective view of one linked member context: its own local anchor for
/// identity, prescription, sets and rule, with the shared lever vector and
/// counters replaced by what the link's chain leaves at a chosen cutoff.
/// Merging only happens here; every consumer keeps using the local anchor's
/// identity and lineage for its own context.
final class SharedTrackView implements ProgressionAnchor {
  SharedTrackView({
    required this.local,
    required this.link,
    required this.shared,
  }) {
    if (shared.vector.length != local.nextSets.length)
      throw BodyTmiException(
        'conflict',
        'The linked shared lever track has ${shared.vector.length} working '
            'sets but this context has ${local.nextSets.length}. Resolve the '
            'linked track before continuing.',
      );
  }

  final ProgressionAnchor local;
  final LeverLink link;
  final SharedTrackState shared;

  @override
  String get id => local.id;
  @override
  String? get runId => local.runId;
  @override
  String get role => local.role;
  @override
  String get slotId => local.slotId;
  @override
  ExerciseSlot get slot => local.slot;
  @override
  String get templateId => local.templateId;
  @override
  int get revisionNumber => local.revisionNumber;
  @override
  WorkoutRevision get pinnedRevision => local.pinnedRevision;
  @override
  List<TrainingSet> get sets => local.sets;
  @override
  Set<String> get controlledMetrics => local.controlledMetrics;
  @override
  String get ruleType => local.ruleType;
  @override
  Map<String, Object?> get rule => local.rule;
  @override
  int get sequence => local.sequence;
  @override
  String? get previousApplication => local.previousApplication;
  @override
  int get previousSequence => local.previousSequence;
  @override
  String get status => local.status;
  @override
  DateTime? get resolvedAt => local.resolvedAt;
  @override
  String get contextKey => local.contextKey;
  @override
  bool matches(String templateId, ExerciseSlot candidate) =>
      local.matches(templateId, candidate);

  @override
  Set<String> get controlledSettings => local.controlledSettings;
  @override
  List<Map<String, String>> get nextSettings => local.nextSettings;

  /// A shared metric's target wins; all other controlled metrics stay local.
  @override
  List<Metrics> get nextSets => List.unmodifiable([
    for (var i = 0; i < local.nextSets.length; i++)
      {
        for (final metric in local.controlledMetrics)
          metric: link.metrics.contains(metric)
              ? shared.vector[i][metric]!
              : local.nextSets[i][metric]!,
      },
  ]);

  @override
  int get failedSessions => shared.failedSessions;
  @override
  int get cursor => shared.cursor;

  /// Shared counters are chain state, so the raw lineage counters of the
  /// local anchor remain visible unmerged for validation.
  @override
  int get previousFailures => local.previousFailures;
  @override
  int get previousCursor => local.previousCursor;
}

/// Wraps [local] when its context actively backs an unretired lever link at
/// the chain cutoff [at]. A member context whose session started before the
/// link, or which explicitly retired at or before its own start, keeps the
/// raw local anchor. This mirrors the archive validator's linked-decision
/// predicate so reports never disagree with enforcement.
ProgressionAnchor? linkLinkedTrack(
  SharedLinkIndex index,
  ProgressionAnchor? local, {
  DateTime? at,
  DateTime? sessionStartedAt,
}) {
  if (local == null) return null;
  final linkId = index.linkFor(local.contextKey);
  if (linkId == null) return local;
  final link = index.link(linkId);
  if (link == null) return null;
  final retired = index.retirements[local.contextKey];
  final own = sessionStartedAt ?? at;
  if (retired != null && (own == null || !own.isBefore(retired.retiredAt)))
    return local;
  if (own != null && own.isBefore(link.createdAt)) return local;
  final state = index.stateAt(linkId, at);
  if (state == null) return local;
  return SharedTrackView(local: local, link: link, shared: state);
}

/// True when [anchor]'s context actively backs a link at [own] (its session
/// start or the act's timestamp), matching [linkLinkedTrack] wrapping.
LeverLink? linkedContextFor(
  SharedLinkIndex index,
  ProgressionAnchor anchor,
  DateTime own,
) {
  final linkId = index.linkFor(anchor.contextKey);
  if (linkId == null) return null;
  final link = index.link(linkId);
  if (link == null) return null;
  final retired = index.retirements[anchor.contextKey];
  if (retired != null && !own.isBefore(retired.retiredAt)) return null;
  if (own.isBefore(link.createdAt)) return null;
  return link;
}
