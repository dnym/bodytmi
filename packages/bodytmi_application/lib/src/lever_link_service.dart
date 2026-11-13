import 'package:bodytmi_core/bodytmi_core.dart';
import 'canonical_json.dart';
import 'lever_link.dart';
import 'link_retirement.dart';
import 'progression_anchor.dart';
import 'shared_lever_application.dart';
import 'training_repository.dart';

/// Authoring and inspection of durable shared lever tracks. Creation resolves
/// every member against its current resolved progression track and enforces
/// the shared-writer contract before anything is written.
final class LeverLinkService {
  const LeverLinkService(this.repository);
  final TrainingRepository repository;

  Future<LeverLinkRevision> revision(String id, [int? number]) async {
    final all =
        (await repository.leverLinkRevisions())
            .where(
              (r) => r.link.id == id && (number == null || r.number == number),
            )
            .toList()
          ..sort((a, b) => b.number.compareTo(a.number));
    return all.firstOrNull ??
        (throw const BodyTmiException(
          'not_found',
          'Lever link revision not found.',
        ));
  }

  Future<List<LeverLinkRevision>> list() async =>
      (await repository.leverLinkRevisions())..sort((a, b) {
        final id = a.link.id.compareTo(b.link.id);
        return id == 0 ? a.number.compareTo(b.number) : id;
      });

  Future<LeverLinkRevision> create({
    required Map<String, Object?> input,
    required DateTime createdAt,
    required int expectedRevision,
    required bool confirm,
  }) => repository.transaction(() async {
    if (!confirm) invalid('Creating a lever link requires confirm:true.');
    final json = jsonObject(input, 'lever link');
    checkKeys(json, {
      'id',
      'name',
      'metrics',
      'cadence',
      'members',
      'baseline',
    });
    final id = identifier(json, 'id');
    final memberIds = [
      for (final member in jsonList(json, 'members'))
        anchorReference(member, 'member'),
    ];
    if (memberIds.toSet().length != memberIds.length)
      invalid('Lever link members must be distinct tracks.');
    final all = await repository.leverLinkRevisions();
    validateLeverLinkRevisions(all);
    final matches = all.where((r) => r.link.id == id).toList()
      ..sort((a, b) => b.number.compareTo(a.number));
    final before = matches.firstOrNull;
    if ((before?.number ?? 0) != expectedRevision)
      throw const BodyTmiException('conflict', 'Lever link revision changed.');
    final retirements = await repository.linkRetirements();
    final anchors = <String, ProgressionAnchor>{
      for (final anchor in <ProgressionAnchor>[
        ...await repository.progressionDecisions(),
        ...await repository.progressionReconciliations(),
        ...retirements,
      ])
        if (anchor.resolvedAt != null) anchor.id: anchor,
    };
    final members = <LeverLinkMember>[];
    final memberAnchors = <ProgressionAnchor>[];
    for (final memberId in memberIds) {
      final anchor = anchors[memberId];
      if (anchor == null)
        invalid('Lever link members must be resolved progression tracks.');
      members.add(
        LeverLinkMember(
          anchorId: anchor.id,
          runId: anchor.runId,
          templateId: anchor.templateId,
          slot: anchor.slot,
          role: anchor.role,
        ),
      );
      memberAnchors.add(anchor);
    }
    final metrics = <String>{};
    for (final metric in jsonList(json, 'metrics'))
      if (!metrics.add(identifier({'id': metric}, 'id')))
        invalid('Lever link metrics must be distinct.');
    final link = LeverLink(
      id: id,
      name: json.containsKey('name') ? requiredString(json, 'name') : null,
      metrics: metrics.toList()..sort(),
      cadence: (json['cadence'] ?? 'each-exposure') as String,
      members: members,
      baseline: anchorReference(json['baseline'], 'baseline'),
      createdAt: createdAt,
    );
    requireSharedWriterContract(link, memberAnchors);
    if (before != null) {
      if (canonicalJson([
                for (final member in before.link.members) member.toJson(),
              ]) !=
              canonicalJson([
                for (final member in link.members) member.toJson(),
              ]) ||
          before.link.baseline != link.baseline)
        throw const BodyTmiException(
          'conflict',
          'Lever link membership and baseline are immutable; publish a new '
              'link identity to fork.',
        );
      if (before.link.name == link.name &&
          canonicalJson(before.link.metrics) == canonicalJson(link.metrics) &&
          before.link.cadence == link.cadence)
        return before;
    }
    for (final member in link.members) {
      final others = <String>{
        for (final existing in all)
          if (existing.link.id != link.id &&
              existing.link.members.any(
                (other) => other.contextKey == member.contextKey,
              ))
            existing.link.id,
      };
      if (others.isEmpty) continue;
      final retired = retirements
          .where((r) => r.contextKey == member.contextKey)
          .firstOrNull;
      if (others.length >= 2 ||
          retired == null ||
          !others.contains(retired.linkId) ||
          link.createdAt.isBefore(retired.retiredAt))
        throw const BodyTmiException(
          'conflict',
          'A progression track belongs to at most one lever link.',
        );
    }
    final next = LeverLinkRevision.publish(link, previous: before);
    validateLeverLinkRevisions([...all, next], retirements);
    await repository.insertLeverLinkRevision(next);
    return next;
  });

  /// Read-only preview of the shared-writer contract for a candidate link
  /// before authoring. It resolves members and explains blockers; it writes
  /// nothing and reserves no identity.
  Future<Map<String, Object?>> status(
    Map<String, Object?> input,
  ) => repository.transaction(() async {
    final json = jsonObject(input, 'lever link');
    checkKeys(json, {
      'id',
      'name',
      'metrics',
      'cadence',
      'members',
      'baseline',
    });
    final id = identifier(json, 'id');
    final memberIds = [
      for (final member in jsonList(json, 'members'))
        anchorReference(member, 'member'),
    ];
    if (memberIds.toSet().length != memberIds.length)
      invalid('Lever link members must be distinct tracks.');
    final metrics = <String>{};
    for (final metric in jsonList(json, 'metrics'))
      if (!metrics.add(identifier({'id': metric}, 'id')))
        invalid('Lever link metrics must be distinct.');
    final cadence = (json['cadence'] ?? 'each-exposure') as String;
    if (!{'each-exposure', 'manual'}.contains(cadence))
      invalid('Unknown lever link cadence.');
    final baseline = anchorReference(json['baseline'], 'baseline');
    final links = await buildSharedLinkIndex(repository);
    final decisions = await repository.progressionDecisions();
    final blockers = <String>[];
    final members = <LeverLinkMember>[];
    final memberAnchors = <ProgressionAnchor>[];
    final views = <Map<String, Object?>>[];
    for (final memberId in memberIds) {
      final anchor = links.anchors[memberId];
      if (anchor == null) {
        blockers.add('Member $memberId is not a resolved progression track.');
        views.add({'anchorId': memberId, 'resolved': false});
        continue;
      }
      members.add(
        LeverLinkMember(
          anchorId: anchor.id,
          runId: anchor.runId,
          templateId: anchor.templateId,
          slot: anchor.slot,
          role: anchor.role,
        ),
      );
      memberAnchors.add(anchor);
      views.add({
        'anchorId': anchor.id,
        'resolved': true,
        'contextKey': anchor.contextKey,
        'ruleType': anchor.ruleType,
        'controlledMetrics': anchor.controlledMetrics.toList()..sort(),
        'failedSessions': anchor.failedSessions,
        if (anchor.ruleType == 'threshold') 'cursor': anchor.cursor,
        'nextSets': [for (final set in anchor.nextSets) metricsToJson(set)],
        'existingLinkId': links.linkFor(anchor.contextKey),
        if (links.retirements[anchor.contextKey] case final retired?)
          'retiredAt': retired.retiredAt.toUtc().toIso8601String(),
        'pendingDecision': decisions.any(
          (d) => d.resolvedAt == null && d.contextKey == anchor.contextKey,
        ),
      });
    }
    if (!memberIds.contains(baseline))
      blockers.add('The baseline must be one of the linked members.');
    var contractOk = false;
    List<Metrics>? seedVector;
    int? seedFailures, seedCursor;
    if (blockers.isEmpty) {
      final link = LeverLink(
        id: id,
        name: json.containsKey('name') ? requiredString(json, 'name') : null,
        metrics: metrics.toList()..sort(),
        cadence: cadence,
        members: members,
        baseline: baseline,
        createdAt: DateTime.utc(1),
      );
      try {
        requireSharedWriterContract(link, memberAnchors);
        contractOk = true;
      } on BodyTmiException catch (error) {
        if (error.code != 'validation') rethrow;
        blockers.add(error.message);
      }
      final baselineAnchor = links.anchors[baseline];
      if (baselineAnchor != null) {
        final vector = [
          for (final set in baselineAnchor.nextSets)
            {
              for (final metric in link.metrics)
                if (set[metric] != null) metric: set[metric]!,
            },
        ];
        if (vector.length == baselineAnchor.nextSets.length &&
            vector.every((set) => set.length == link.metrics.length)) {
          seedVector = vector;
          seedFailures = baselineAnchor.failedSessions;
          seedCursor = baselineAnchor.cursor;
        }
      }
    }
    return {
      'policy': 'bodytmi-lever-link-status/1',
      'candidate': {
        'id': id,
        if (json.containsKey('name')) 'name': requiredString(json, 'name'),
        'metrics': metrics.toList()..sort(),
        if (cadence != 'each-exposure') 'cadence': cadence,
        'members': memberIds,
        'baseline': baseline,
      },
      'currentRevision': links.headNumbers[id] ?? 0,
      'contractOk': contractOk,
      'blockers': blockers,
      'members': views,
      if (seedVector != null) ...{
        'seed': {
          'vector': [for (final set in seedVector) metricsToJson(set)],
          'failedSessions': seedFailures,
          if (memberAnchors.first.ruleType == 'threshold') 'cursor': seedCursor,
        },
      },
    };
  });

  /// The published link, its durable shared application chain and the state it
  /// leaves at [asOf]. This is the shared track members consume.
  Future<Map<String, Object?>> state(String linkId, [DateTime? asOf]) =>
      repository.transaction(() async {
        final links = await buildSharedLinkIndex(repository);
        final link = links.link(linkId);
        if (link == null)
          throw const BodyTmiException('not_found', 'Lever link not found.');
        final state = links.stateAt(linkId, asOf);
        if (state == null)
          throw const BodyTmiException(
            'not_found',
            'Shared lever track lacks its baseline state.',
          );
        final baseline = links.anchors[link.baseline];
        return {
          'policy': 'bodytmi-lever-link-state/1',
          'linkId': linkId,
          'revision': links.headNumbers[linkId],
          'link': link.toJson(),
          if (asOf != null) 'asOf': asOf.toUtc().toIso8601String(),
          'chain': [for (final row in links.chain(linkId)) row.toJson()],
          'state': {
            'applicationId': state.applicationId,
            'applicationSequence': state.applicationSequence,
            'failedSessions': state.failedSessions,
            if (baseline?.ruleType == 'threshold') 'cursor': state.cursor,
            'vector': [for (final set in state.vector) metricsToJson(set)],
          },
          'members': [
            for (final member in link.members)
              {
                'anchorId': member.anchorId,
                'contextKey': member.contextKey,
                'retiredAt': links.retirements[member.contextKey]?.retiredAt
                    .toUtc()
                    .toIso8601String(),
              },
          ],
        };
      });

  /// One explicit manual step of a shared lever chain. `manual` cadence links
  /// advance only here; `each-exposure` links also accept explicit steps for
  /// user-driven reconciliation. expectedSequence is compare-and-set against
  /// the current chain head; an identical replayed payload returns the stored
  /// row byte-identically.
  Future<SharedLeverApplication> advance({
    required String linkId,
    required List<Object?> nextSets,
    required int failedSessions,
    int? cursor,
    required int expectedSequence,
    required DateTime at,
    required bool confirm,
  }) => repository.transaction(() async {
    if (!confirm)
      invalid('Advancing a shared lever track requires confirm:true.');
    final links = await buildSharedLinkIndex(repository);
    final link = links.link(linkId);
    if (link == null)
      throw const BodyTmiException('not_found', 'Lever link not found.');
    final seedState = links.seed(linkId);
    if (seedState == null)
      invalid('Shared lever track lacks its baseline shared state.');
    final baseline = links.anchors[link.baseline]!;
    final ruleType = baseline.ruleType;
    final vectors = [for (final set in nextSets) metricsFromJson(set)];
    if (vectors.length != seedState.vector.length)
      invalid('The shared vector must cover every working set.');
    for (final set in vectors)
      if (set.length != link.metrics.length ||
          !set.keys.every(link.metrics.contains))
        invalid('The shared vector must carry exactly the shared metrics.');
    if (failedSessions < 0 ||
        (ruleType != 'threshold' && cursor != null) ||
        (ruleType == 'threshold' && (cursor == null || cursor < 0)))
      invalid('Invalid shared lever counters.');
    final chain = links.chain(linkId);
    if (expectedSequence > chain.length)
      throw BodyTmiException(
        'conflict',
        'The shared lever track advanced (sequence '
            '${chain.length}); expected $expectedSequence.',
      );
    if (expectedSequence < chain.length) {
      final stored = chain[expectedSequence];
      if (stored.occurredAt == at &&
          stored.failedSessions == failedSessions &&
          stored.cursor == (cursor ?? 0) &&
          canonicalJson([
                for (final set in stored.nextSets) metricsToJson(set),
              ]) ==
              canonicalJson([for (final set in vectors) metricsToJson(set)]))
        return stored;
      throw const BodyTmiException(
        'conflict',
        'That shared application sequence is already recorded.',
      );
    }
    final head = chain.lastOrNull;
    if (head != null && at.isBefore(head.occurredAt))
      invalid('A shared application cannot precede the chain step it joins.');
    final application = SharedLeverApplication(
      linkId: linkId,
      sequence: chain.length + 1,
      ruleType: ruleType,
      failedSessions: failedSessions,
      cursor: cursor ?? 0,
      nextSets: vectors,
      originKind: 'manual',
      occurredAt: at,
      previousApplication: head?.id,
      previousSequence: head?.sequence ?? 0,
      previousFailures: head?.failedSessions ?? seedState.failedSessions,
      previousCursor: head?.cursor ?? seedState.cursor,
    );
    validateSharedLeverApplications(
      [for (final rows in links.chains.values) ...rows, application],
      await repository.leverLinkRevisions(),
      links.anchors,
    );
    await repository.insertSharedLeverApplication(application);
    return application;
  });

  /// Explicitly break one member context out of its lever link at [retiredAt].
  /// The retirement copies the chain's counters and shared vector at that
  /// cutoff into an independent local anchor, so the context's later sessions
  /// stop consuming the link while the chain and other members continue. It
  /// refuses while the context has unfinalized work, pending proposals or
  /// finalized exposures in the link that lack a resolved decision.
  Future<LinkRetirementAnchor> retire({
    required String linkId,
    required String memberAnchorId,
    required DateTime retiredAt,
    required bool confirm,
  }) => repository.transaction(() async {
    if (!confirm) invalid('Retiring from a lever link requires confirm:true.');
    final decisions = await repository.progressionDecisions();
    final receipts = await repository.progressionReconciliations();
    final retirements = await repository.linkRetirements();
    final links = await buildSharedLinkIndex(repository);
    final link = links.link(linkId);
    if (link == null)
      throw const BodyTmiException('not_found', 'Lever link not found.');
    final member = link.members
        .where((m) => m.anchorId == memberAnchorId)
        .firstOrNull;
    if (member == null) invalid('Lever link member not found.');
    final existing = retirements
        .where((r) => r.contextKey == member.contextKey)
        .firstOrNull;
    if (existing != null) {
      if (existing.linkId == linkId &&
          existing.memberAnchorId == memberAnchorId &&
          existing.retiredAt == retiredAt)
        return existing;
      throw const BodyTmiException(
        'conflict',
        'This progression context already retired from a lever link.',
      );
    }
    if (retiredAt.isBefore(link.createdAt))
      invalid('Retirement cannot precede its lever link.');
    final runBySession = {
      for (final binding in await repository.sessionPrograms())
        binding.sessionId: binding.runId,
    };
    bool inContext(TrainingSession session) {
      if (runBySession[session.id] != member.runId ||
          session.revision.definition.id != member.templateId)
        return false;
      final ExerciseSlot slot;
      try {
        slot = session.revision.definition.slot(member.slot.id);
      } on BodyTmiException {
        return false;
      }
      if (!slot.compatibleWith(member.slot)) return false;
      return session.sets.any(
        (set) => set.slotId == member.slot.id && set.role == member.role,
      );
    }

    for (final session in await repository.sessions()) {
      if (!inContext(session)) continue;
      if (session.status != SessionStatus.finalized) {
        if (!session.startedAt.isBefore(link.createdAt))
          throw const BodyTmiException(
            'conflict',
            'An unfinalized session started inside this lever link; review or '
                'discard it before retiring.',
          );
        continue;
      }
      if (session.startedAt.isBefore(link.createdAt) ||
          !session.startedAt.isBefore(retiredAt))
        continue;
      if (!decisions.any(
        (d) =>
            d.session.id == session.id &&
            d.slotId == member.slot.id &&
            d.role == member.role &&
            d.resolvedAt != null,
      ))
        throw BodyTmiException(
          'conflict',
          'Session ${session.id} finalized inside this lever link without a '
              'resolved progression decision; resolve it or retire earlier.',
        );
    }
    for (final decision in decisions) {
      if (decision.resolvedAt != null ||
          decision.slotId != member.slot.id ||
          decision.role != member.role ||
          decision.session.startedAt.isBefore(link.createdAt) ||
          !inContext(decision.session))
        continue;
      throw const BodyTmiException(
        'conflict',
        'A pending progression proposal exists in this context; resolve it '
            'before retiring.',
      );
    }
    final headAll = latestAnchor(
      <ProgressionAnchor>[...decisions, ...receipts],
      member.templateId,
      member.slot,
      runId: member.runId,
      role: member.role,
    );
    if (headAll == null)
      throw const BodyTmiException(
        'conflict',
        'This context lacks a resolved progression track to retire from.',
      );
    if (headAll.resolvedAt!.isAfter(retiredAt))
      throw const BodyTmiException(
        'conflict',
        'The context resolved after this retirement cutoff; retire later.',
      );
    final head = headAll;
    final state = links.stateAt(linkId, retiredAt);
    if (state == null)
      throw const BodyTmiException(
        'not_found',
        'Shared lever track lacks its baseline state.',
      );
    if (head.nextSets.length != state.vector.length)
      throw const BodyTmiException(
        'conflict',
        'The context working-set count differs from the shared track; '
            'reconcile before retiring.',
      );
    final retirement = LinkRetirementAnchor(
      id: '$linkId/retire/$memberAnchorId',
      linkId: linkId,
      memberAnchorId: memberAnchorId,
      runId: head.runId,
      slotId: member.slot.id,
      role: member.role,
      revision: head.pinnedRevision,
      sets: head.sets,
      rule: head.rule,
      ruleType: head.ruleType,
      previousApplication: head.id,
      previousSequence: head.sequence,
      previousFailures: state.failedSessions,
      previousCursor: state.cursor,
      failedSessions: state.failedSessions,
      cursor: state.cursor,
      nextSets: [
        for (var i = 0; i < head.nextSets.length; i++)
          {
            ...head.nextSets[i],
            for (final metric in link.metrics) metric: state.vector[i][metric]!,
          },
      ],
      retiredAt: retiredAt,
    );
    validateLinkRetirements(
      [...retirements, retirement],
      await repository.leverLinkRevisions(),
      [for (final rows in links.chains.values) ...rows],
      decisions,
      receipts,
    );
    await repository.insertLinkRetirementAnchor(retirement);
    return retirement;
  });
}
