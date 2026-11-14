import 'package:bodytmi_core/bodytmi_core.dart';
import 'canonical_json.dart';
import 'lever_link.dart';
import 'progression_anchor.dart';
import 'progression_decision.dart';
import 'reconciliation_receipt.dart';
import 'shared_lever_application.dart';

/// Breaking a member out of a lever link copies the current resolved shared
/// state into that context as an independent local anchor. The retirement
/// anchor keeps the member's own sets, prescription and rule, adopts the
/// chain's counters and shared vector at [retiredAt], and continues the
/// context's local sequence. History keeps its source contexts; the link's
/// published membership is never rewritten.
final class LinkRetirementAnchor implements ProgressionAnchor {
  LinkRetirementAnchor({
    required this.id,
    required this.linkId,
    required this.memberAnchorId,
    required this.runId,
    required this.slotId,
    required this.role,
    required this.revision,
    required List<TrainingSet> sets,
    required this.rule,
    required this.ruleType,
    required this.previousApplication,
    required this.previousSequence,
    required this.previousFailures,
    required this.failedSessions,
    required List<Metrics> nextSets,
    required this.retiredAt,
    this.previousCursor = 0,
    this.cursor = 0,
  }) : sets = List.unmodifiable(sets),
       nextSets = List.unmodifiable([
         for (final set in nextSets) Map<String, Quantity>.unmodifiable(set),
       ]) {
    anchorReference(id, 'id');
    identifier({'id': linkId}, 'id');
    anchorReference(memberAnchorId, 'memberAnchorId');
    if (runId != null) identifier({'id': runId}, 'id');
    identifier({'id': slotId}, 'id');
    if (!effortRoles.contains(role)) invalid('Invalid retirement role.');
    if (previousSequence < 1 ||
        previousFailures < 0 ||
        previousCursor < 0 ||
        failedSessions < 0 ||
        (ruleType != 'double' && ruleType != 'threshold') ||
        (ruleType != 'threshold' && (cursor != 0 || previousCursor != 0)) ||
        sets.isEmpty ||
        nextSets.length != sets.length)
      invalid('Invalid lever link retirement state.');
    if (ruleType == 'threshold') {
      ThresholdRule.fromJson(rule);
    } else {
      DoubleProgressionRule.fromJson(rule);
    }
    for (final set in sets)
      if (set.role != role) invalid('Retirement sets share one role.');
  }

  factory LinkRetirementAnchor.fromJson(Object? input) {
    final json = jsonObject(input, 'lever link retirement');
    checkKeys(json, {
      'id',
      'linkId',
      'memberAnchorId',
      'runId',
      'slotId',
      'role',
      'revision',
      'sets',
      'rule',
      'ruleType',
      'previousApplication',
      'previousSequence',
      'previousFailures',
      'previousCursor',
      'cursor',
      'failedSessions',
      'nextSets',
      'retiredAt',
      'sequence',
    });
    int count(String key, int min) {
      final value = json[key];
      if (value is! int || value < min) invalid('Invalid $key.');
      return value;
    }

    final previous = json['previousApplication'];
    if (previous is! String || previous.trim().isEmpty)
      invalid('Retirement needs the application it supersedes.');
    final kind = json['ruleType'] ?? 'double';
    if (kind is! String || (kind != 'double' && kind != 'threshold'))
      invalid('Invalid retirement rule type.');
    if (json.containsKey('role') && json['role'] == 'work')
      invalid('The default work role must be omitted in stored retirements.');
    if (kind != 'threshold' &&
        (json.containsKey('previousCursor') || json.containsKey('cursor')))
      invalid('Double retirement carries no coordinator state.');
    final anchor = LinkRetirementAnchor(
      id: anchorReference(json['id'], 'id'),
      linkId: identifier(json, 'linkId'),
      memberAnchorId: anchorReference(json['memberAnchorId'], 'memberAnchorId'),
      runId: json['runId'] == null ? null : identifier(json, 'runId'),
      slotId: identifier(json, 'slotId'),
      role: json.containsKey('role') ? requiredString(json, 'role') : 'work',
      revision: WorkoutRevision.fromJson(json['revision']),
      sets: _retiredSetsFromJson(json['sets']),
      rule: jsonObject(json['rule'], 'rule'),
      ruleType: kind,
      previousApplication: previous,
      previousSequence: count('previousSequence', 1),
      previousFailures: count('previousFailures', 0),
      previousCursor: kind == 'threshold' ? count('previousCursor', 0) : 0,
      cursor: kind == 'threshold' ? count('cursor', 0) : 0,
      failedSessions: count('failedSessions', 0),
      nextSets: [
        for (final set in jsonList(json, 'nextSets')) metricsFromJson(set),
      ],
      retiredAt: parseInstant(json['retiredAt'], 'retiredAt'),
    );
    if (count('sequence', 2) != anchor.sequence)
      invalid('Retirement sequence does not match its lineage.');
    return anchor;
  }

  final String id, linkId, memberAnchorId;
  @override
  final String? runId;
  @override
  final String slotId;
  @override
  final String role;
  final WorkoutRevision revision;
  @override
  final List<TrainingSet> sets;
  @override
  final Map<String, Object?> rule;
  @override
  final String ruleType;
  @override
  final String previousApplication;
  @override
  final int previousSequence, previousFailures, previousCursor, cursor;
  @override
  final List<Metrics> nextSets;

  /// Shared links reject ordinal rules, so retirements move no settings.
  @override
  Set<String> get controlledSettings => const {};
  @override
  List<Map<String, String>> get nextSettings => [
    for (final _ in nextSets) const <String, String>{},
  ];
  @override
  final int failedSessions;
  final DateTime retiredAt;

  @override
  DateTime? get resolvedAt => retiredAt;
  @override
  String get status => 'retired';
  @override
  String get templateId => revision.definition.id;
  @override
  int get revisionNumber => revision.number;
  @override
  WorkoutRevision get pinnedRevision => revision;
  @override
  late final ExerciseSlot slot = revision.definition.slot(slotId);
  @override
  late final String contextKey = anchorContextKey(
    runId,
    templateId,
    slot,
    role,
  );
  @override
  int get sequence => previousSequence + 1;
  @override
  bool matches(String candidateTemplate, ExerciseSlot candidate) =>
      templateId == candidateTemplate && slot.compatibleWith(candidate);

  @override
  late final Set<String> controlledMetrics = ruleType == 'double'
      ? {
          DoubleProgressionRule.fromJson(rule).objective,
          DoubleProgressionRule.fromJson(rule).lever,
        }
      : {
          ...ThresholdRule.fromJson(rule).increments.keys,
          ...ThresholdRule.fromJson(rule).resets.keys,
          ...ThresholdRule.fromJson(rule).deloadMetrics,
        };

  Map<String, Object?> toJson() => {
    'id': id,
    'linkId': linkId,
    'memberAnchorId': memberAnchorId,
    if (runId != null) 'runId': runId,
    'slotId': slotId,
    if (role != 'work') 'role': role,
    'revision': revision.toJson(),
    'sets': [
      for (final set in sets)
        {
          'id': set.id,
          'slot': set.slotId,
          'role': set.role,
          'ordinal': set.ordinal,
          'suggested': metricsToJson(set.suggested),
          if (set.objectivesJson.isNotEmpty) 'objectives': set.objectivesJson,
        },
    ],
    'rule': rule,
    if (ruleType == 'threshold') ...{
      'ruleType': ruleType,
      'previousCursor': previousCursor,
      'cursor': cursor,
    },
    'previousApplication': previousApplication,
    'previousSequence': previousSequence,
    'previousFailures': previousFailures,
    'sequence': sequence,
    'failedSessions': failedSessions,
    'nextSets': [for (final set in nextSets) metricsToJson(set)],
    'retiredAt': retiredAt.toUtc().toIso8601String(),
  };
}

List<TrainingSet> _retiredSetsFromJson(Object? input) {
  if (input is! List<Object?>) invalid('Retirement sets must be an array.');
  final sets = <TrainingSet>[];
  for (final item in input) {
    final row = jsonObject(item, 'retirement set');
    checkKeys(row, {
      'id',
      'slot',
      'role',
      'ordinal',
      'suggested',
      'objectives',
    });
    final ordinal = row['ordinal'];
    if (ordinal is! int || ordinal < 0) invalid('Invalid set ordinal.');
    final objectives = row.containsKey('objectives')
        ? numericObjectivesFromJson(row['objectives'])
        : <String, NumericObjective>{};
    sets.add(
      TrainingSet(
        id: requiredString(row, 'id'),
        slotId: identifier(row, 'slot'),
        role: requiredString(row, 'role'),
        ordinal: ordinal,
        suggested: metricsFromJson(row['suggested']),
        maxEffortMetrics: objectives.entries
            .where((entry) => entry.value.mode == 'maxEffort')
            .map((entry) => entry.key)
            .toSet(),
        criteria: Map.fromEntries(
          objectives.entries.where((entry) => entry.value.mode != 'maxEffort'),
        ),
        settings: const {},
        actualSettings: const {},
      ),
    );
  }
  return List.unmodifiable(sets);
}

/// Every retirement must continue one context head without racing another
/// writer, copy exactly the shared chain state at its cutoff for the shared
/// metrics and the context head for the others, and name a published,
/// resolved link member.
void validateLinkRetirements(
  List<LinkRetirementAnchor> retirements,
  List<LeverLinkRevision> revisions,
  List<SharedLeverApplication> applications,
  List<ProgressionDecision> decisions,
  List<ReconciliationReceipt> receipts,
) {
  final anchors = <String, ProgressionAnchor>{
    for (final anchor in <ProgressionAnchor>[...decisions, ...receipts])
      if (anchor.resolvedAt != null) anchor.id: anchor,
  };
  final contexts = <String>{};
  for (final retirement in retirements) {
    if (!retirement.id.startsWith('${retirement.linkId}/retire/'))
      invalid('Retirement identity does not match its link.');
    if (anchors.containsKey(retirement.id))
      invalid('Retirement identity collides with a progression anchor.');
    if (!contexts.add(retirement.contextKey))
      invalid('A progression context may retire from a lever link only once.');
    final published = _latestRevision(revisions, retirement.linkId);
    if (published == null)
      invalid('Retirement names an unpublished lever link.');
    final link = published.link;
    final member = link.members
        .where((m) => m.anchorId == retirement.memberAnchorId)
        .firstOrNull;
    if (member == null ||
        member.contextKey != retirement.contextKey ||
        member.runId != retirement.runId ||
        member.templateId != retirement.templateId ||
        !member.slot.compatibleWith(retirement.slot) ||
        member.role != retirement.role)
      invalid('Retirement does not match a published link member context.');
    final memberAnchor = anchors[retirement.memberAnchorId];
    if (memberAnchor == null || memberAnchor.resolvedAt == null)
      invalid('Retirement member anchor is unresolved.');
    if (retirement.retiredAt.isBefore(link.createdAt))
      invalid('Retirement cannot precede its lever link.');
    final head = latestAnchor(
      <ProgressionAnchor>[...decisions, ...receipts].where(
        (anchor) =>
            anchor.resolvedAt != null &&
            !anchor.resolvedAt!.isAfter(retirement.retiredAt),
      ),
      retirement.templateId,
      retirement.slot,
      runId: retirement.runId,
      role: retirement.role,
    );
    if (head == null ||
        head.resolvedAt == null ||
        head.resolvedAt!.isAfter(retirement.retiredAt) ||
        retirement.previousApplication != head.id ||
        retirement.previousSequence != head.sequence ||
        canonicalJson(retirement.rule) != canonicalJson(head.rule) ||
        retirement.ruleType != head.ruleType)
      invalid('Retirement does not continue its context head.');
    if (retirement.revision.definition.id != head.pinnedRevision.definition.id)
      invalid('Retirement revision changes the template.');
    if (retirement.sets.length != head.sets.length)
      invalid('Retirement must keep the head working-set structure.');
    for (var i = 0; i < retirement.sets.length; i++) {
      final headSet = head.sets[i], copied = retirement.sets[i];
      if (headSet.id != copied.id ||
          headSet.role != copied.role ||
          headSet.ordinal != copied.ordinal ||
          canonicalJson(metricsToJson(headSet.suggested)) !=
              canonicalJson(metricsToJson(copied.suggested)) ||
          canonicalJson({
                for (final e in headSet.criteria.entries)
                  e.key: e.value.semanticJson(),
              }) !=
              canonicalJson({
                for (final e in copied.criteria.entries)
                  e.key: e.value.semanticJson(),
              }))
        invalid('Retirement sets must copy the context head exactly.');
    }
  }
  final index = SharedLinkIndex(
    revisions: revisions,
    applications: applications,
    anchors: anchors,
    retirements: retirements,
  );
  for (final retirement in retirements) {
    final link = index.link(retirement.linkId);
    if (link == null) invalid('Retirement names an unpublished lever link.');
    final state = index.stateAt(retirement.linkId, retirement.retiredAt);
    if (state == null) invalid('Retirement lacks its shared chain state.');
    if (retirement.failedSessions != state.failedSessions ||
        retirement.cursor != state.cursor)
      invalid('Retirement must copy the shared chain counters.');
    if (!link.metrics.every(retirement.controlledMetrics.contains))
      invalid('Retired context must control every shared metric.');
    final head = anchors[retirement.previousApplication]!;
    for (var i = 0; i < retirement.nextSets.length; i++) {
      for (final metric in retirement.controlledMetrics) {
        final expected = link.metrics.contains(metric)
            ? state.vector[i][metric]!
            : head.nextSets[i][metric]!;
        final copied = retirement.nextSets[i][metric];
        if (copied == null || copied.compareTo(expected) != 0)
          invalid('Retirement targets must copy the chain and context head.');
      }
    }
  }
}

LeverLinkRevision? _latestRevision(
  List<LeverLinkRevision> revisions,
  String linkId,
) {
  LeverLinkRevision? best;
  for (final revision in revisions)
    if (revision.link.id == linkId &&
        (best == null || revision.number > best.number))
      best = revision;
  return best;
}
