import 'package:bodytmi_core/bodytmi_core.dart';
import 'lever_link.dart';
import 'link_retirement.dart';
import 'progression_anchor.dart';
import 'progression_decision.dart';
import 'progression_reconciliation.dart';
import 'reconciliation_receipt.dart';
import 'role_progression_preview.dart';
import 'shared_lever_application.dart';
import 'shared_track_view.dart';
import 'canonical_json.dart';
import 'training_repository.dart';

final class StoredProgressionService {
  const StoredProgressionService(this.repository);
  final TrainingRepository repository;

  Future<List<ReconciliationReceipt>> _reconciliations() =>
      repository.progressionReconciliations();

  Future<List<LinkRetirementAnchor>> _retirements() =>
      repository.linkRetirements();

  Future<SharedLinkIndex> _links() => buildSharedLinkIndex(repository);

  /// The shared chain state a linked each-exposure resolution must continue.
  /// If the chain moved after the session started, or the plan was not the
  /// chain's, this is a competing-writer conflict: there is no automatic
  /// rebase. The explicit escape is `link retire` at the session start.
  SharedTrackState _sharedCas(
    SharedLinkIndex links,
    LeverLink link,
    ProgressionDecision pending,
  ) {
    final frozen = links.stateAt(link.id, pending.session.startedAt);
    if (frozen == null)
      _conflict('The linked shared lever track lacks its baseline state.');
    final chain = links.chain(link.id);
    final head = chain.isEmpty ? null : chain.last;
    if ((head?.sequence ?? 0) != frozen.applicationSequence)
      _conflict(
        'The shared lever track advanced after this session started '
        '(chain ${frozen.applicationSequence} to ${head!.sequence}). Use '
        'link retire at the session start to keep this context independent.',
      );
    final sets = pending.sets;
    if (frozen.vector.length != sets.length)
      _conflict(
        'The linked shared lever track has ${frozen.vector.length} working '
        'sets but this session has ${sets.length}.',
      );
    for (var i = 0; i < sets.length; i++)
      for (final metric in link.metrics) {
        final planned = sets[i].suggested[metric];
        if (planned == null ||
            planned.compareTo(frozen.vector[i][metric]!) != 0)
          _conflict(
            'This session did not plan against the shared lever track; '
            'resolve the link before continuing.',
          );
      }
    if (pending.previousFailures != frozen.failedSessions ||
        pending.previousCursor != frozen.cursor)
      _conflict(
        'The shared lever counters changed; propose again before resolving.',
      );
    return frozen;
  }

  Future<void> _appendChain(
    SharedLinkIndex links,
    LeverLink link,
    SharedTrackState frozen,
    ProgressionDecision resolved,
    String originKind,
    DateTime at,
  ) async {
    final chain = links.chain(link.id);
    final head = chain.isEmpty ? null : chain.last;
    if (head != null && at.isBefore(head.occurredAt))
      invalid('A shared application cannot precede the chain step it joins.');
    await repository.insertSharedLeverApplication(
      SharedLeverApplication(
        linkId: link.id,
        sequence: (head?.sequence ?? 0) + 1,
        ruleType: resolved.ruleType,
        failedSessions: resolved.failedSessions,
        cursor: resolved.cursor,
        nextSets: [
          for (final set in resolved.nextSets)
            {for (final metric in link.metrics) metric: set[metric]!},
        ],
        originKind: originKind,
        occurredAt: at,
        previousApplication: head?.id,
        previousSequence: head?.sequence ?? 0,
        previousFailures: frozen.failedSessions,
        previousCursor: frozen.cursor,
        originSessionId: resolved.session.id,
        originDecisionId: resolved.id,
      ),
    );
  }

  /// Preview against the current durable lineage without writing a decision.
  Future<Map<String, Object?>> previewFromTrack(
    String sessionId,
    String slotId,
    Map<String, Object?> rule, {
    String ruleType = 'double',
    String role = 'work',
  }) => repository.transaction(() async {
    if (!{'work', 'warmup', 'backoff', 'drop'}.contains(role))
      invalid('Unknown progression role.');
    if (ruleType == 'double') {
      DoubleProgressionRule.fromJson(rule);
    } else if (ruleType == 'threshold') {
      ThresholdRule.fromJson(rule);
    } else if (ruleType == 'ordinal') {
      OrdinalRule.fromJson(rule);
    } else {
      invalid('Unknown stored progression rule type.');
    }
    final session = await StoredTrainingService(repository).session(sessionId);
    final candidates = session.revision.definition.slots.where(
      (s) => s.id == slotId,
    );
    if (candidates.isEmpty) invalid('Unknown progression slot.');
    final runId = (await repository.sessionPrograms())
        .where((b) => b.sessionId == sessionId)
        .firstOrNull
        ?.runId;
    final all = await repository.progressionDecisions();
    final existing = all
        .where(
          (d) =>
              d.session.id == sessionId && d.slotId == slotId && d.role == role,
        )
        .firstOrNull;
    if (existing?.resolvedAt != null)
      _conflict('This exposure is already resolved; use progression show.');
    final before = linkLinkedTrack(
      await _links(),
      latestTrack(
        all,
        <ProgressionAnchor>[
          ...await _reconciliations(),
          ...await _retirements(),
        ],
        session.revision.definition.id,
        candidates.single,
        runId: runId,
        role: role,
      ),
      at: session.startedAt,
      sessionStartedAt: session.startedAt,
    );
    if (before != null &&
        (before.ruleType != ruleType ||
            canonicalJson(before.rule) != canonicalJson(rule) ||
            !matchesSessionProgressionBaseline(
              session,
              slotId,
              role,
              before.controlledMetrics,
              before,
            ))) {
      _reconcileRequired(session, slotId, role, before, ruleType, rule);
    }
    final preview = const RoleProgressionPreview().evaluate(
      session: session,
      slotId: slotId,
      role: role,
      ruleType: ruleType,
      rule: rule,
      failedSessions: before?.failedSessions ?? 0,
      cursor: before?.cursor ?? 0,
    );
    return {
      ...preview,
      'policy': 'bodytmi-stored-progression-preview/1',
      'stateSource': {
        'runId': runId,
        'previousApplication': before?.id,
        'previousSequence': before?.sequence ?? 0,
        'previousResolvedAt': before?.resolvedAt?.toUtc().toIso8601String(),
        'previousResolvedAfterSessionStart':
            before?.resolvedAt?.isAfter(session.startedAt) ?? false,
        'previousInputsChanged': before == null ? false : await stale(before),
        'pendingVersion': existing?.version,
        'pendingStale': existing == null ? null : await stale(existing),
      },
    };
  });

  /// Explains every explicit difference between a candidate prescription,
  /// existing session and rule and the latest resolved track. This writes
  /// nothing and reconciles nothing; it only names the reconciliation kinds
  /// that `store start` and `progression propose` would require.
  Future<Map<String, Object?>> reconcileStatus({
    required String templateId,
    required int revision,
    required String slotId,
    required DateTime asOf,
    String role = 'work',
    String? runId,
    String? sessionId,
    Map<String, Object?>? rule,
    String ruleType = 'double',
  }) => repository.transaction(() async {
    identifier({'id': templateId}, 'id');
    identifier({'id': slotId}, 'id');
    if (revision < 1 || !effortRoles.contains(role))
      invalid('Invalid progression reconciliation revision or role.');
    if (runId != null) {
      identifier({'id': runId}, 'id');
      if (!(await repository.programRuns()).any((run) => run.id == runId)) {
        throw const BodyTmiException('not_found', 'Program run not found.');
      }
    }
    if (rule != null) {
      if (ruleType == 'double') {
        DoubleProgressionRule.fromJson(rule);
      } else if (ruleType == 'threshold') {
        ThresholdRule.fromJson(rule);
      } else if (ruleType == 'ordinal') {
        OrdinalRule.fromJson(rule);
      } else {
        invalid('Unknown stored progression rule type.');
      }
    }
    final prescription = await StoredTrainingService(
      repository,
    ).revision(templateId, revision);
    final slots = prescription.definition.slots.where((s) => s.id == slotId);
    if (slots.isEmpty) invalid('Unknown progression slot.');
    TrainingSession? session;
    String? sessionRunId;
    if (sessionId != null) {
      session = await StoredTrainingService(repository).session(sessionId);
      sessionRunId = (await repository.sessionPrograms())
          .where((b) => b.sessionId == sessionId)
          .firstOrNull
          ?.runId;
      if (runId != null && runId != sessionRunId)
        invalid('Candidate session belongs to another program run.');
    }
    final decisions = (await repository.progressionDecisions()).where(
      (d) =>
          d.resolvedAt != null &&
          !d.resolvedAt!.isAfter(asOf) &&
          d.session.startedAt.isBefore(asOf),
    );
    final wrapAt = session?.startedAt ?? asOf;
    final latest = linkLinkedTrack(
      await _links(),
      latestTrack(
        decisions,
        <ProgressionAnchor>[
          ...(await _reconciliations()).where(
            (r) => !r.reconciledAt.isAfter(asOf),
          ),
          ...(await _retirements()).where((r) => !r.retiredAt.isAfter(asOf)),
        ],
        templateId,
        slots.single,
        runId: runId,
        role: role,
      ),
      at: wrapAt,
      sessionStartedAt: wrapAt,
    );
    final assessment = assessProgressionReconciliation(
      prescription: prescription,
      templateId: templateId,
      revision: revision,
      slotId: slotId,
      role: role,
      track: latest,
      session: session,
      runId: runId,
      asOf: asOf,
      ruleType: ruleType,
      rule: rule,
    );
    final kinds = {for (final blocker in assessment.blockers) blocker.kind};
    return {
      ...assessment.toJson(),
      'inputsChanged': latest == null ? false : await stale(latest),
      'blockedCommands': {
        'store start': [
          for (final kind in _startReconciliationKinds)
            if (kinds.contains(kind)) kind,
        ],
        'progression propose': [
          for (final kind in _proposeReconciliationKinds)
            if (kinds.contains(kind)) kind,
        ],
      },
    };
  });

  /// Inspect the latest resolved track at a session-start cutoff. This does not
  /// assert that a new prescription is compatible with the stored baseline.
  Future<Map<String, Object?>> track({
    required String templateId,
    required int revision,
    required String slotId,
    required DateTime asOf,
    String? runId,
    String role = 'work',
  }) => repository.transaction(() async {
    identifier({'id': templateId}, 'id');
    identifier({'id': slotId}, 'id');
    if (revision < 1 || !{'work', 'warmup', 'backoff', 'drop'}.contains(role))
      invalid('Invalid progression track revision or role.');
    if (runId != null) {
      identifier({'id': runId}, 'id');
      if (!(await repository.programRuns()).any((run) => run.id == runId)) {
        throw const BodyTmiException('not_found', 'Program run not found.');
      }
    }
    final prescription = await StoredTrainingService(
      repository,
    ).revision(templateId, revision);
    final slots = prescription.definition.slots.where((s) => s.id == slotId);
    if (slots.isEmpty) invalid('Unknown progression slot.');
    final decisions = (await repository.progressionDecisions()).where(
      (d) =>
          d.resolvedAt != null &&
          !d.resolvedAt!.isAfter(asOf) &&
          d.session.startedAt.isBefore(asOf),
    );
    final raw = latestTrack(
      decisions,
      <ProgressionAnchor>[
        ...(await _reconciliations()).where(
          (r) => !r.reconciledAt.isAfter(asOf),
        ),
        ...(await _retirements()).where((r) => !r.retiredAt.isAfter(asOf)),
      ],
      templateId,
      slots.single,
      runId: runId,
      role: role,
    );
    final latest = linkLinkedTrack(await _links(), raw, at: asOf);
    final source = switch (latest) {
      final value? when value is SharedTrackView => value.local,
      final value? => value,
      _ => null,
    };
    final decision = source is ProgressionDecision ? source : null;
    final receipt = source is ReconciliationReceipt ? source : null;
    final retirement = source is LinkRetirementAnchor ? source : null;
    return {
      'policy': 'bodytmi-progression-track/3',
      'asOf': asOf.toUtc().toIso8601String(),
      'templateId': templateId,
      'revision': revision,
      'slotId': slotId,
      'role': role,
      'runId': runId,
      'resolved': latest != null,
      if (latest != null) ...{
        'decisionId': latest.id,
        'sourceKind': decision != null
            ? 'decision'
            : receipt != null
            ? 'reconciliation'
            : 'retirement',
        'sourceSessionId': decision?.session.id ?? receipt?.sourceSessionId,
        'sourceContentVersion': decision?.session.contentVersion,
        'sourceRevision':
            decision?.session.revision.number ??
            receipt?.revisionNumber ??
            retirement?.revisionNumber,
        'resolvedAt': latest.resolvedAt!.toUtc().toIso8601String(),
        'status': latest.status,
        if (receipt != null) ...{
          'acknowledgedKinds': receipt.acknowledgedKinds,
          'supersedes': receipt.previousApplication,
          'resetFailures': receipt.resetFailures,
          if (receipt.resetCursor) 'resetCursor': true,
        },
        if (retirement != null) ...{
          'supersedes': retirement.previousApplication,
          'retirementLink': retirement.linkId,
        },
        'inputsChanged': await stale(source!),
        'sequence': latest.sequence,
        'ruleType': latest.ruleType,
        'rule': latest.rule,
        'controlledMetrics': latest.controlledMetrics.toList()..sort(),
        if (latest case SharedTrackView(:final link, :final shared)) ...{
          'link': {
            'linkId': link.id,
            'cadence': link.cadence,
            'sharedMetrics': link.metrics,
            'chainApplicationId': shared.applicationId,
            'chainSequence': shared.applicationSequence,
            'baselineAnchor': link.baseline,
            'members': [for (final member in link.members) member.anchorId],
          },
        },
        'state': {
          'failedSessions': latest.failedSessions,
          if (latest.ruleType == 'threshold') 'cursor': latest.cursor,
          'nextSets': [
            for (final set in latest.nextSets)
              metricsToJson({
                for (final metric in latest.controlledMetrics)
                  metric: set[metric]!,
              }),
          ],
        },
      },
    };
  });

  Future<ProgressionDecision> propose(
    String sessionId,
    String slotId,
    Map<String, Object?> rule, {
    String ruleType = 'double',
    String role = 'work',
  }) => repository.transaction(() async {
    if (!{'work', 'warmup', 'backoff', 'drop'}.contains(role))
      invalid('Unknown progression role.');
    if (ruleType == 'double') {
      DoubleProgressionRule.fromJson(rule);
    } else if (ruleType == 'threshold') {
      ThresholdRule.fromJson(rule);
    } else if (ruleType == 'ordinal') {
      OrdinalRule.fromJson(rule);
    } else {
      invalid('Unknown stored progression rule type.');
    }
    final all = await repository.progressionDecisions();
    final existing = all
        .where(
          (d) =>
              d.session.id == sessionId && d.slotId == slotId && d.role == role,
        )
        .firstOrNull;
    if (existing?.resolvedAt != null) {
      if (existing!.ruleType != ruleType ||
          canonicalJson(existing.rule) != canonicalJson(rule))
        _conflict('This exposure already resolved a different rule.');
      return existing;
    }
    final session = await StoredTrainingService(repository).session(sessionId);
    final runId = (await repository.sessionPrograms())
        .where((b) => b.sessionId == sessionId)
        .firstOrNull
        ?.runId;
    final candidates = session.revision.definition.slots.where(
      (s) => s.id == slotId,
    );
    if (candidates.isEmpty) invalid('Unknown progression slot.');
    final links = await _links();
    final before = linkLinkedTrack(
      links,
      latestTrack(
        all,
        <ProgressionAnchor>[
          ...await _reconciliations(),
          ...await _retirements(),
        ],
        session.revision.definition.id,
        candidates.single,
        runId: runId,
        role: role,
      ),
      at: session.startedAt,
      sessionStartedAt: session.startedAt,
    );
    if (before case SharedTrackView(
      :final link,
    ) when link.cadence == 'each-exposure') {
      final frozen = links.stateAt(link.id, session.startedAt);
      final head = links.chain(link.id).lastOrNull;
      if (frozen == null || (head?.sequence ?? 0) != frozen.applicationSequence)
        _conflict(
          'The shared lever track advanced after this session started. '
          'Resolve linked exposures one session at a time, or use link '
          'retire at the session start to keep this context independent.',
        );
    }
    if (before != null &&
        (before.ruleType != ruleType ||
            canonicalJson(before.rule) != canonicalJson(rule) ||
            !matchesSessionProgressionBaseline(
              session,
              slotId,
              role,
              before.controlledMetrics,
              before,
            )))
      _reconcileRequired(session, slotId, role, before, ruleType, rule);
    final ruleMetrics = <String>{
      if (ruleType == 'double') ...[
        DoubleProgressionRule.fromJson(rule).objective,
        DoubleProgressionRule.fromJson(rule).lever,
      ],
      if (ruleType == 'threshold') ...[
        ...ThresholdRule.fromJson(rule).increments.keys,
        ...ThresholdRule.fromJson(rule).resets.keys,
        ...ThresholdRule.fromJson(rule).deloadMetrics,
      ],
      if (ruleType == 'ordinal')
        ...OrdinalRule.fromJson(rule).controlledMetrics,
    };
    for (final record in session.prescriptionOverrides) {
      if (record.slotId == slotId && ruleMetrics.contains(record.metric)) {
        _conflict(
          'This session applied a program prescription override to a '
          'progression-controlled metric; reconcile or retire the track '
          'before resolving this exposure.',
        );
      }
    }
    final next = ProgressionDecision(
      session: session,
      slotId: slotId,
      rule: rule,
      previousApplication: before?.id,
      previousSequence: before?.sequence ?? 0,
      previousFailures: before?.failedSessions ?? 0,
      version: (existing?.version ?? 0) + 1,
      runId: runId,
      ruleType: ruleType,
      previousCursor: before?.cursor ?? 0,
      role: role,
    );
    final comparable = next.toJson()
      ..['version'] = existing?.version ?? next.version;
    if (existing != null &&
        canonicalJson(existing.toJson()) == canonicalJson(comparable))
      return existing;
    await repository.saveProgressionDecision(next);
    return next;
  });

  Future<ProgressionDecision> decision(
    String sessionId,
    String slotId, {
    String role = 'work',
  }) async {
    if (!{'work', 'warmup', 'backoff', 'drop'}.contains(role))
      invalid('Unknown progression role.');
    final rows = await repository.progressionDecisions();
    return rows
            .where(
              (d) =>
                  d.session.id == sessionId &&
                  d.slotId == slotId &&
                  d.role == role,
            )
            .firstOrNull ??
        (throw const BodyTmiException(
          'not_found',
          'Progression decision not found.',
        ));
  }

  Future<bool> stale(ProgressionAnchor anchor) async {
    if (anchor case SharedTrackView(:final local)) return stale(local);
    if (anchor case ReconciliationReceipt(
      :final revision,
      :final runId,
      :final sourceSessionId,
    )) {
      final current = (await repository.revisions()).where(
        (r) =>
            r.definition.id == revision.definition.id &&
            r.number == revision.number,
      );
      if (current.isEmpty ||
          canonicalJson(current.single.toJson()) !=
              canonicalJson(revision.toJson()))
        return true;
      if (sourceSessionId == null) return false;
      final session = await repository.session(sourceSessionId);
      if (session == null ||
          session.revision.definition.id != revision.definition.id ||
          session.revision.number != revision.number)
        return true;
      final bound = (await repository.sessionPrograms())
          .where((b) => b.sessionId == sourceSessionId)
          .firstOrNull
          ?.runId;
      return bound != runId;
    }
    if (anchor case LinkRetirementAnchor retirement) {
      final anchors = <ProgressionAnchor>[
        ...await repository.progressionDecisions(),
        ...await _reconciliations(),
        ...await _retirements(),
      ];
      if (!anchors.any((a) => a.id == retirement.previousApplication))
        return true;
      final links = await _links();
      final state = links.stateAt(retirement.linkId, retirement.retiredAt);
      if (links.link(retirement.linkId) == null || state == null) return true;
      if (state.failedSessions != retirement.failedSessions ||
          state.cursor != retirement.cursor)
        return true;
      for (var i = 0; i < retirement.nextSets.length; i++)
        for (final metric in links.link(retirement.linkId)!.metrics)
          if (retirement.nextSets[i][metric]?.compareTo(
                state.vector[i][metric]!,
              ) !=
              0)
            return true;
      return false;
    }
    final decision = anchor as ProgressionDecision;
    final runId = (await repository.sessionPrograms())
        .where((b) => b.sessionId == decision.session.id)
        .firstOrNull
        ?.runId;
    if (decision.runId != runId) return true;
    final source = await repository.session(decision.session.id);
    if (source == null ||
        canonicalJson(source.toJson()) !=
            canonicalJson(decision.session.toJson()))
      return true;
    if (decision.resolvedAt != null) return false;
    final latest = latestTrack(
      await repository.progressionDecisions(),
      <ProgressionAnchor>[...await _reconciliations(), ...await _retirements()],
      decision.session.revision.definition.id,
      decision.slot,
      runId: runId,
      role: decision.role,
    );
    if (latest?.id != decision.previousApplication) return true;
    final links = await _links();
    final link = linkedContextFor(links, decision, decision.session.startedAt);
    if (link != null && link.cadence == 'each-exposure') {
      final frozen = links.stateAt(link.id, decision.session.startedAt);
      if (frozen == null ||
          (links.chain(link.id).lastOrNull?.sequence ?? 0) !=
              frozen.applicationSequence)
        return true;
    }
    return false;
  }

  /// The application or reconciliation a pending exposure continues from.
  Future<ProgressionAnchor?> _base(String? previousApplication) async {
    if (previousApplication == null) return null;
    return (await repository.progressionDecisions())
            .where((d) => d.id == previousApplication)
            .firstOrNull ??
        (await repository.progressionReconciliations())
            .where((r) => r.id == previousApplication)
            .firstOrNull ??
        (await repository.linkRetirements())
            .where((r) => r.id == previousApplication)
            .firstOrNull;
  }

  Future<ProgressionDecision> accept(
    String sessionId,
    String slotId,
    int expectedVersion,
    DateTime at, {
    String role = 'work',
  }) => repository.transaction(() async {
    final pending = await decision(sessionId, slotId, role: role);
    if (pending.version != expectedVersion)
      _conflict('Progression decision version changed.');
    if (pending.acceptedAt != null) return pending;
    if (pending.declinedAt != null)
      _conflict('This exposure was already declined.');
    if (await stale(pending))
      _conflict('Progression inputs changed; propose again before acceptance.');
    if (pending.previousApplication != null) {
      final base = await _base(pending.previousApplication);
      if (base?.resolvedAt == null)
        _conflict('Progression base application is missing.');
      if (at.isBefore(base!.resolvedAt!))
        invalid('Acceptance cannot precede its base application.');
    }
    final links = await _links();
    final link = linkedContextFor(links, pending, pending.session.startedAt);
    final shared = link != null && link.cadence == 'each-exposure'
        ? _sharedCas(links, link, pending)
        : null;
    final applied = pending.accept(at);
    await repository.saveProgressionDecision(applied);
    if (shared != null)
      await _appendChain(links, link!, shared, applied, 'accept', at);
    return applied;
  });

  Future<ProgressionDecision> decline(
    String sessionId,
    String slotId,
    int expectedVersion,
    DateTime at, {
    String role = 'work',
  }) => repository.transaction(() async {
    final pending = await decision(sessionId, slotId, role: role);
    if (pending.version != expectedVersion)
      _conflict('Progression decision version changed.');
    if (pending.declinedAt != null) return pending;
    if (pending.acceptedAt != null)
      _conflict('This exposure was already accepted.');
    if (await stale(pending))
      _conflict('Progression inputs changed; propose again before declining.');
    if (pending.previousApplication != null) {
      final base = await _base(pending.previousApplication);
      if (base?.resolvedAt == null)
        _conflict('Progression base application is missing.');
      if (at.isBefore(base!.resolvedAt!))
        invalid('Decline cannot precede its base application.');
    }
    final links = await _links();
    final link = linkedContextFor(links, pending, pending.session.startedAt);
    final shared = link != null && link.cadence == 'each-exposure'
        ? _sharedCas(links, link, pending)
        : null;
    final declined = pending.decline(at);
    await repository.saveProgressionDecision(declined);
    if (shared != null)
      await _appendChain(links, link!, shared, declined, 'decline', at);
    return declined;
  });

  /// Enforcement stays with the predicates above; this only explains them with
  /// the same comparison that `progression reconcile-status` reports.
  /// One stored reconciliation by identity.
  Future<ReconciliationReceipt> reconciliation(String id) async =>
      (await repository.progressionReconciliations())
          .where((r) => r.id == id)
          .firstOrNull ??
      (throw const BodyTmiException(
        'not_found',
        'Progression reconciliation not found.',
      ));

  Future<List<ReconciliationReceipt>> reconciliations() =>
      repository.progressionReconciliations();

  /// Explicitly re-anchors one run/slot/role progression track onto a different
  /// published prescription (and optionally a different rule). The caller must
  /// name exactly the blocker kinds that `progression reconcile-status` reports
  /// for the same candidate, supply the track sequence it saw, and confirm.
  /// Nothing implicit is carried: failure and coordinator state persist unless
  /// explicitly reset, and terminal receipts and program cursors never change.
  Future<ReconciliationReceipt> reconcile({
    required String id,
    required String templateId,
    required int revision,
    required String slotId,
    required int expectedSequence,
    required List<String> kinds,
    required DateTime reconciledAt,
    required bool confirm,
    String role = 'work',
    String? runId,
    String? sessionId,
    Map<String, Object?>? rule,
    String ruleType = 'double',
    bool resetFailures = false,
    bool resetCursor = false,
  }) => repository.transaction(() async {
    if (!confirm) invalid('Reconciling progression requires confirm:true.');
    identifier({'id': id}, 'id');
    identifier({'id': templateId}, 'id');
    identifier({'id': slotId}, 'id');
    if (runId != null) identifier({'id': runId}, 'id');
    if (revision < 1 || !effortRoles.contains(role) || expectedSequence < 0)
      invalid('Invalid reconciliation target.');
    if (kinds.isEmpty ||
        kinds.toSet().length != kinds.length ||
        !reconciliationKinds.containsAll(kinds))
      invalid('Reconciliation must name every blocker kind once.');
    if (rule != null) {
      if (ruleType == 'double') {
        DoubleProgressionRule.fromJson(rule);
      } else if (ruleType == 'threshold') {
        ThresholdRule.fromJson(rule);
      } else if (ruleType == 'ordinal') {
        OrdinalRule.fromJson(rule);
      } else {
        invalid('Unknown stored progression rule type.');
      }
    }
    final prescription = await StoredTrainingService(
      repository,
    ).revision(templateId, revision);
    final slots = prescription.definition.slots.where((s) => s.id == slotId);
    if (slots.isEmpty) invalid('Unknown progression slot.');
    if (runId != null &&
        !(await repository.programRuns()).any((run) => run.id == runId))
      throw const BodyTmiException('not_found', 'Program run not found.');
    TrainingSession? session;
    if (sessionId != null) {
      session = await StoredTrainingService(repository).session(sessionId);
      final bound = (await repository.sessionPrograms())
          .where((b) => b.sessionId == sessionId)
          .firstOrNull
          ?.runId;
      if (runId != null && runId != bound)
        invalid('Candidate session belongs to another program run.');
      if (session.startedAt.isAfter(reconciledAt))
        invalid('Reconciliation cannot adopt a session that starts later.');
    }
    final decisions = (await repository.progressionDecisions()).where(
      (d) =>
          d.resolvedAt != null &&
          !d.resolvedAt!.isAfter(reconciledAt) &&
          d.session.startedAt.isBefore(reconciledAt),
    );
    final receipts = await _reconciliations();
    final retirements = await _retirements();
    final prior = receipts.where((r) => r.id == id).firstOrNull;
    final base = linkLinkedTrack(
      await _links(),
      prior == null
          ? latestTrack(
              decisions,
              <ProgressionAnchor>[...receipts, ...retirements],
              templateId,
              slots.single,
              runId: runId,
              role: role,
            )
          : <String, ProgressionAnchor>{
              for (final anchor in <ProgressionAnchor>[
                ...decisions,
                ...receipts,
                ...retirements,
              ])
                anchor.id: anchor,
            }[prior.previousApplication],
      at: reconciledAt,
      sessionStartedAt: reconciledAt,
    );
    if (base == null || base.resolvedAt == null)
      invalid('There is no resolved progression track to reconcile.');
    if (prior == null && base.sequence != expectedSequence)
      _conflict(
        'Progression track changed: expected sequence $expectedSequence but '
        'the current track is ${base.sequence}. Inspect progression '
        'reconcile-status again before reconciling.',
      );
    final effectiveRuleType = rule == null ? base.ruleType : ruleType;
    final assessment = assessProgressionReconciliation(
      prescription: prescription,
      templateId: templateId,
      revision: revision,
      slotId: slotId,
      role: role,
      track: base,
      session: session,
      runId: runId,
      asOf: reconciledAt,
      ruleType: effectiveRuleType,
      rule: rule,
    );
    final assessed = {for (final blocker in assessment.blockers) blocker.kind};
    if (!assessment.required)
      _conflict(
        'This candidate already matches the current progression track; nothing '
        'needs reconciliation.',
      );
    if (assessed.length != kinds.length || !assessed.containsAll(kinds))
      _conflict(
        'Reconciliation kinds differ from the current blockers: '
        '${(assessed.toList()..sort()).join(', ')}.',
      );
    final next = ReconciliationReceipt(
      id: id,
      runId: runId,
      revision: prescription,
      slotId: slotId,
      role: role,
      sets: [
        for (final set in _adoptedSets(prescription, slotId, role, session))
          TrainingSet(
            id: set.id,
            slotId: set.slotId,
            role: set.role,
            ordinal: set.ordinal,
            suggested: set.suggested,
            maxEffortMetrics: set.maxEffortMetrics,
            criteria: set.criteria,
          ),
      ],
      rule: rule ?? base.rule,
      ruleType: effectiveRuleType,
      previousApplication: base.id,
      previousSequence: base.sequence,
      previousFailures: base.failedSessions,
      previousCursor: base.cursor,
      reconciledAt: reconciledAt,
      acknowledgedKinds: kinds,
      resetFailures: resetFailures,
      resetCursor: resetCursor,
      sourceSessionId: session?.id,
    );
    if (prior != null) {
      if (canonicalJson(prior.toJson()) == canonicalJson(next.toJson()))
        return prior;
      _conflict(
        'This reconciliation identity already records a different act.',
      );
    }
    if (reconciledAt.isBefore(base.resolvedAt!))
      invalid('Reconciliation cannot precede the application it supersedes.');
    await repository.saveProgressionReconciliation(next);
    return next;
  });

  /// The candidate's planned suggestions for the slot and role. An existing
  /// session's frozen suggestions, including manual edits, win over the bare
  /// prescription. Results are never adopted.
  List<TrainingSet> _adoptedSets(
    WorkoutRevision revision,
    String slotId,
    String role,
    TrainingSession? session,
  ) {
    if (session == null) return baselineSets(revision, slotId, role);
    final sets = [
      for (final set in session.sets)
        if (set.slotId == slotId && set.role == role) set,
    ];
    if (sets.isEmpty)
      invalid('Candidate session has no sets for this slot and role.');
    return sets;
  }

  Never _reconcileRequired(
    TrainingSession session,
    String slotId,
    String role,
    ProgressionAnchor before,
    String ruleType,
    Map<String, Object?> rule,
  ) {
    final assessment = assessProgressionReconciliation(
      prescription: session.revision,
      templateId: session.revision.definition.id,
      revision: session.revision.number,
      slotId: slotId,
      role: role,
      track: before,
      session: session,
      runId: before.runId,
      ruleType: ruleType,
      rule: rule,
    );
    if (!assessment.required)
      _conflict(
        'Session prescription or rule differs from the latest applied '
        'progression; explicit reconciliation is required.',
      );
    throw reconciliationConflict(
      assessment,
      context: 'Progression ${session.id}',
    );
  }
}

/// Kinds that stop a later `store start` from consuming the stored track.
const _startReconciliationKinds = [
  'workingSetCount',
  'slotTarget',
  'metricDimension',
  'effortTarget',
  'objectiveCriteria',
];

/// Kinds that stop `progression propose` from continuing the stored lineage.
const _proposeReconciliationKinds = [
  'workingSetCount',
  'effortTarget',
  'objectiveCriteria',
  'sessionTarget',
  'rule',
];

Never _conflict(String message) => throw BodyTmiException('conflict', message);
