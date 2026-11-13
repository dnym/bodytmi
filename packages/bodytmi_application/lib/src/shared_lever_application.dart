import 'package:bodytmi_core/bodytmi_core.dart';
import 'lever_link.dart';
import 'link_retirement.dart';
import 'progression_anchor.dart';
import 'progression_decision.dart';

/// One step of one durable shared lever track. A member context still resolves
/// its own exposure, but an `each-exposure` link advances one common
/// application chain: the shared target vector, failure counter and
/// coordinator position. A chain is contiguous per link, seeds from the
/// published baseline member anchor, and never decides a member exposure.
final class SharedLeverApplication {
  SharedLeverApplication({
    required this.linkId,
    required this.sequence,
    required this.ruleType,
    required this.failedSessions,
    required this.cursor,
    required List<Metrics> nextSets,
    required this.originKind,
    required this.occurredAt,
    this.previousApplication,
    this.previousSequence = 0,
    this.previousFailures = 0,
    this.previousCursor = 0,
    this.originSessionId,
    this.originDecisionId,
  }) : nextSets = List.unmodifiable([
         for (final set in nextSets) Map<String, Quantity>.unmodifiable(set),
       ]) {
    identifier({'id': linkId}, 'id');
    if (sequence < 1 ||
        !{'double', 'threshold'}.contains(ruleType) ||
        !{'accept', 'decline', 'manual'}.contains(originKind) ||
        failedSessions < 0 ||
        cursor < 0 ||
        previousSequence < 0 ||
        previousFailures < 0 ||
        previousCursor < 0 ||
        (previousApplication == null) != (previousSequence == 0) ||
        (previousApplication != null &&
            previousApplication != '$linkId/$previousSequence'))
      invalid('Invalid shared lever application state.');
    if (ruleType != 'threshold' && (cursor != 0 || previousCursor != 0))
      invalid('Double shared progression carries no coordinator position.');
    if (nextSets.isEmpty || nextSets.any((set) => set.isEmpty))
      invalid('Shared lever applications need nonempty target vectors.');
    if (originKind == 'manual' &&
        (originSessionId != null || originDecisionId != null))
      invalid('Manual shared advances name no training exposure.');
    if (originKind != 'manual') {
      if (originSessionId == null || originDecisionId == null)
        invalid('Shared exposure advances name their source decision.');
      identifier({'id': originSessionId}, 'id');
      anchorReference(originDecisionId, 'originDecisionId');
    }
  }

  factory SharedLeverApplication.fromJson(Object? input) {
    final json = jsonObject(input, 'shared lever application');
    checkKeys(json, {
      'id',
      'linkId',
      'sequence',
      'ruleType',
      'previousApplication',
      'previousSequence',
      'previousFailures',
      'previousCursor',
      'failedSessions',
      'cursor',
      'nextSets',
      'originKind',
      'originSessionId',
      'originDecisionId',
      'occurredAt',
    });
    int count(String key, int min) {
      final value = json[key];
      if (value is! int || value < min) invalid('Invalid $key.');
      return value;
    }

    final previous = json['previousApplication'];
    if (previous != null && previous is! String)
      invalid('Invalid shared previous application identity.');
    final kind = json['ruleType'] ?? 'double';
    final originKind = json['originKind'];
    if (originKind is! String ||
        !{'accept', 'decline', 'manual'}.contains(originKind))
      invalid('Invalid shared lever origin kind.');
    if (json.containsKey('originSessionId') && json['originSessionId'] == null)
      invalid('Stored shared origin session must be omitted when absent.');
    if (json.containsKey('originDecisionId') &&
        json['originDecisionId'] == null)
      invalid('Stored shared origin decision must be omitted when absent.');
    if (kind is! String ||
        (kind != 'threshold' && json.containsKey('previousCursor')))
      invalid('Invalid stored shared rule type or coordinator state.');
    final vectors = [
      for (final set in jsonList(json, 'nextSets')) metricsFromJson(set),
    ];
    final application = SharedLeverApplication(
      linkId: identifier(json, 'linkId'),
      sequence: count('sequence', 1),
      ruleType: kind,
      previousApplication: previous as String?,
      previousSequence: count('previousSequence', 0),
      previousFailures: count('previousFailures', 0),
      previousCursor: kind == 'threshold' ? count('previousCursor', 0) : 0,
      failedSessions: count('failedSessions', 0),
      cursor: kind == 'threshold' ? count('cursor', 0) : 0,
      nextSets: vectors,
      originKind: originKind,
      originSessionId: json['originSessionId'] == null
          ? null
          : identifier(json, 'originSessionId'),
      originDecisionId: json['originDecisionId'] == null
          ? null
          : anchorReference(json['originDecisionId'], 'originDecisionId'),
      occurredAt: parseInstant(json['occurredAt'], 'occurredAt'),
    );
    if (json['id'] != application.id)
      invalid('Shared lever application identity does not match its chain.');
    return application;
  }

  final String linkId;
  final int sequence;
  final String ruleType;
  final String? previousApplication;
  final int previousSequence, previousFailures, previousCursor;
  final int failedSessions, cursor;
  final List<Metrics> nextSets;
  final String originKind;
  final String? originSessionId, originDecisionId;
  final DateTime occurredAt;

  String get id => '$linkId/$sequence';

  Map<String, Object?> toJson() => {
    'id': id,
    'linkId': linkId,
    'sequence': sequence,
    'previousApplication': previousApplication,
    'previousSequence': previousSequence,
    'previousFailures': previousFailures,
    if (ruleType == 'threshold') ...{
      'ruleType': ruleType,
      'previousCursor': previousCursor,
      'cursor': cursor,
    },
    'failedSessions': failedSessions,
    'nextSets': [for (final set in nextSets) metricsToJson(set)],
    'originKind': originKind,
    if (originSessionId != null) 'originSessionId': originSessionId,
    if (originDecisionId != null) 'originDecisionId': originDecisionId,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
  };
}

/// The effective shared vector and counters one link leaves at a cutoff.
final class SharedTrackState {
  SharedTrackState({
    required List<Metrics> vector,
    required this.failedSessions,
    required this.cursor,
    this.applicationId,
    this.applicationSequence = 0,
  }) : vector = List.unmodifiable([
         for (final set in vector) Map<String, Quantity>.unmodifiable(set),
       ]);

  final List<Metrics> vector;
  final int failedSessions, cursor;

  /// The chain application that left this state, or null when the link is
  /// still seeded from its published baseline member anchor.
  final String? applicationId;
  final int applicationSequence;
}

/// Read-only join of published lever link revisions, their durable shared
/// chains, and the resolved anchors that seed them. It powers consumption and
/// archive validation; it decides and writes nothing.
final class SharedLinkIndex {
  SharedLinkIndex({
    required List<LeverLinkRevision> revisions,
    required List<SharedLeverApplication> applications,
    required Map<String, ProgressionAnchor> anchors,
    List<LinkRetirementAnchor> retirements = const [],
  }) {
    for (final revision in revisions) {
      final current = headNumbers[revision.link.id];
      if (current == null || revision.number > current) {
        headNumbers[revision.link.id] = revision.number;
        heads[revision.link.id] = revision.link;
      }
      for (final member in revision.link.members)
        members.putIfAbsent(member.contextKey, () => revision.link.id);
    }
    for (final retirement in retirements)
      this.retirements[retirement.contextKey] = retirement;
    for (final application in applications)
      chains.putIfAbsent(application.linkId, () => []).add(application);
    for (final chain in chains.values)
      chain.sort((a, b) => a.sequence.compareTo(b.sequence));
    this.anchors = anchors;
  }

  final Map<String, LeverLink> heads = {};
  final Map<String, int> headNumbers = {};
  final Map<String, String> members = {};
  final Map<String, LinkRetirementAnchor> retirements = {};
  final Map<String, List<SharedLeverApplication>> chains = {};
  late final Map<String, ProgressionAnchor> anchors;

  /// The link identity whose published membership includes a progression
  /// context, retired or not. Validation uses this full view.
  String? linkFor(String contextKey) => members[contextKey];

  /// The link [contextKey] still actively backs: published membership minus
  /// contexts that explicitly retired. Sessions that started before the link
  /// or before the retirement keep their raw local semantics.
  LeverLink? activeLink(String? linkId, String contextKey) {
    if (linkId == null) return null;
    final link = heads[linkId];
    if (link == null) return null;
    if (!members.containsKey(contextKey)) return null;
    return retirements.containsKey(contextKey) ? null : link;
  }

  /// The latest published link definition for one identity.
  LeverLink? link(String linkId) => heads[linkId];

  List<SharedLeverApplication> chain(String linkId) =>
      List.unmodifiable(chains[linkId] ?? const []);

  /// The chain step whose origin is this member context's resolved decision.
  SharedLeverApplication? rowForOrigin(String decisionId) {
    for (final chain in chains.values)
      for (final application in chain)
        if (application.originDecisionId == decisionId) return application;
    return null;
  }

  /// The state seeded directly from the published baseline member anchor.
  SharedTrackState? seed(String linkId) {
    final link = heads[linkId];
    if (link == null) return null;
    final baseline = anchors[link.baseline];
    if (baseline == null || baseline.resolvedAt == null) return null;
    final vector = <Metrics>[
      for (final set in baseline.nextSets)
        {
          for (final metric in link.metrics)
            if (set[metric] != null) metric: set[metric]!,
        },
    ];
    if (vector.length != baseline.nextSets.length ||
        vector.any((set) => set.length != link.metrics.length))
      return null;
    return SharedTrackState(
      vector: vector,
      failedSessions: baseline.failedSessions,
      cursor: baseline.cursor,
    );
  }

  /// The shared state a link leaves at [at] (the whole chain when null).
  SharedTrackState? stateAt(String linkId, [DateTime? at]) {
    if (heads[linkId] == null) return null;
    for (final application in (chains[linkId] ?? const []).reversed) {
      if (at != null && application.occurredAt.isAfter(at)) continue;
      return SharedTrackState(
        vector: application.nextSets,
        failedSessions: application.failedSessions,
        cursor: application.cursor,
        applicationId: application.id,
        applicationSequence: application.sequence,
      );
    }
    return seed(linkId);
  }
}

/// Structural validation of shared lever chains. Chains are contiguous per
/// link, replay the prior row's counters, carry exactly the published shared
/// metrics at the baseline's working-set count, and name resolvable origin
/// exposures whose own state matches the recorded step.
void validateSharedLeverApplications(
  List<SharedLeverApplication> applications,
  List<LeverLinkRevision> revisions,
  Map<String, ProgressionAnchor> anchors,
) {
  final index = SharedLinkIndex(
    revisions: revisions,
    applications: applications,
    anchors: anchors,
  );
  final ids = <String>{};
  for (final application in applications) {
    if (!ids.add(application.id))
      invalid('Duplicate shared lever application identity.');
    if (index.link(application.linkId) == null)
      invalid('Shared lever applications name an unpublished lever link.');
  }
  for (final linkId in index.chains.keys) {
    final link = index.link(linkId)!;
    final chain = index.chain(linkId);
    final baseline = anchors[link.baseline];
    if (baseline == null || baseline.resolvedAt == null)
      invalid('Shared lever chain lacks its published baseline anchor.');
    final seedState = index.seed(linkId);
    if (seedState == null)
      invalid('Shared lever chain baseline lacks the shared metrics.');
    for (var i = 0; i < chain.length; i++) {
      final application = chain[i];
      if (application.sequence != i + 1)
        invalid('Shared lever applications must be contiguous per link.');
      if (application.ruleType != baseline.ruleType)
        invalid('Shared lever chain changes its rule type.');
      if (application.nextSets.length != baseline.nextSets.length)
        invalid('Shared lever vector length must match the linked tracks.');
      final shared = link.metrics.toSet();
      for (final set in application.nextSets)
        if (set.length != shared.length || !set.keys.every(shared.contains))
          invalid(
            'Shared lever vectors must carry exactly the shared metrics.',
          );
      final previous = i == 0 ? null : chain[i - 1];
      if (previous == null) {
        if (application.previousApplication != null ||
            application.previousSequence != 0 ||
            application.previousFailures != seedState.failedSessions ||
            application.previousCursor != seedState.cursor)
          invalid(
            'The first shared application must replay the baseline state.',
          );
      } else if (application.previousApplication != previous.id ||
          application.previousSequence != previous.sequence ||
          application.previousFailures != previous.failedSessions ||
          application.previousCursor != previous.cursor ||
          application.occurredAt.isBefore(previous.occurredAt))
        invalid('Shared lever chain lineage is inconsistent.');
      if (application.originKind == 'manual') continue;
      var origin = anchors[application.originDecisionId];
      if (origin == null ||
          origin.resolvedAt == null ||
          origin.id != application.originDecisionId ||
          index.linkFor(origin.contextKey) != linkId)
        invalid('Shared lever origin is not a linked resolved decision.');
      if (origin is! ProgressionDecision)
        invalid('Shared lever origins must be exposure decisions.');
      final expectedStatus = application.originKind == 'accept'
          ? 'accepted'
          : 'declined';
      if (origin.status != expectedStatus ||
          origin.resolvedAt != application.occurredAt ||
          origin.failedSessions != application.failedSessions ||
          origin.cursor != application.cursor ||
          (application.originKind == 'accept' &&
              origin.session.id != application.originSessionId))
        invalid('Shared lever origin does not match its application.');
      if (application.originKind == 'accept') {
        for (
          var setIndex = 0;
          setIndex < application.nextSets.length;
          setIndex++
        ) {
          final from = origin.nextSets[setIndex];
          for (final metric in link.metrics) {
            final value = from[metric];
            if (value == null ||
                value.compareTo(application.nextSets[setIndex][metric]!) != 0)
              invalid('Shared application does not match its source decision.');
          }
        }
      } else {
        final held = previous == null ? seedState.vector : previous.nextSets;
        for (
          var setIndex = 0;
          setIndex < application.nextSets.length;
          setIndex++
        )
          for (final metric in link.metrics)
            if (application.nextSets[setIndex][metric]!.compareTo(
                  held[setIndex][metric]!,
                ) !=
                0)
              invalid('A declined shared application must hold its vector.');
      }
    }
  }
}
