import 'package:bodytmi_core/bodytmi_core.dart';
import 'canonical_json.dart';
import 'progression_anchor.dart';
import 'progression_decision.dart';
import 'reconciliation_receipt.dart';

/// Explicit differences that stop a new prescription, session or rule from
/// continuing an accepted progression track. None is ever resolved implicitly.
const reconciliationKinds = <String>{
  'workingSetCount',
  'slotTarget',
  'effortTarget',
  'metricDimension',
  'sessionTarget',
  'objectiveCriteria',
  'rule',
};

/// One compared difference explaining why a candidate cannot consume the track.
final class ReconciliationBlocker {
  ReconciliationBlocker(this.kind, this.details) {
    if (!reconciliationKinds.contains(kind))
      invalid('Unknown reconciliation blocker kind.');
  }
  final String kind;
  final Map<String, Object?> details;
  Map<String, Object?> toJson() => {'kind': kind, ...details};
}

/// A candidate workout revision, published session and optional candidate rule
/// compared with the latest resolved progression decision for one run/slot/role
/// context. The comparison set matches the checks that make `store start` and
/// `progression propose` conflict, so a report cannot disagree with enforcement.
final class ProgressionReconciliation {
  ProgressionReconciliation({
    required this.templateId,
    required this.revision,
    required this.slotId,
    required this.role,
    required this.runId,
    required this.asOf,
    required this.ruleType,
    required this.rule,
    required this.prescription,
    required this.session,
    required this.track,
    required this.controlledMetrics,
    required this.blockers,
  }) {
    if (!effortRoles.contains(role)) invalid('Unknown progression role.');
  }

  final String templateId;
  final int revision;
  final String slotId;
  final String role;
  final String? runId;
  final DateTime? asOf;
  final String ruleType;

  /// The candidate rule, or null when the candidate keeps the track's rule.
  final Map<String, Object?>? rule;
  final WorkoutRevision prescription;

  /// An existing session whose frozen suggestions are also compared, or null
  /// when only the published prescription is a candidate for a later start.
  final TrainingSession? session;
  final ProgressionAnchor? track;
  final Set<String> controlledMetrics;
  final List<ReconciliationBlocker> blockers;

  bool get required => blockers.isNotEmpty;
  ExerciseSlot get slot => prescription.definition.slot(slotId);
  List<Metrics> get candidateTargets =>
      prescription.definition.roleTargets(slotId, role);
  List<Effort> get candidateEfforts => [
    for (final occurrence in prescription.definition.plan.occurrences())
      if (occurrence.activity case Effort(
        slotId: final effortSlot,
        role: final effortRole,
      ) when effortSlot == slotId && effortRole == role)
        occurrence.activity as Effort,
  ];
  List<TrainingSet> get candidateSets => session == null
      ? const []
      : List.unmodifiable(
          session!.sets.where(
            (set) => set.slotId == slotId && set.role == role,
          ),
        );

  Map<String, Object?> toJson() => {
    'policy': 'bodytmi-progression-reconciliation/1',
    'templateId': templateId,
    'revision': revision,
    'slotId': slotId,
    'role': role,
    'runId': runId,
    'asOf': asOf?.toUtc().toIso8601String(),
    'controlledMetrics': controlledMetrics.toList()..sort(),
    'track': track == null ? null : _trackView(track!, controlledMetrics),
    'candidate': {
      'sessionId': session?.id,
      'sessionContentVersion': session?.contentVersion,
      'ruleType': ruleType,
      if (rule != null) 'rule': rule,
      'workingSetCount': candidateTargets.length,
      'slotTargets': metricsToJson({
        for (final metric in controlledMetrics)
          if (slot.targets[metric] != null) metric: slot.targets[metric]!,
      }),
      'effortTargets': [
        for (final targets in candidateTargets)
          metricsToJson({
            for (final metric in controlledMetrics)
              if (targets[metric] != null) metric: targets[metric]!,
          }),
      ],
      if (session != null)
        'sessionTargets': [
          for (final set in candidateSets)
            metricsToJson({
              for (final metric in controlledMetrics)
                if (set.suggested[metric] != null)
                  metric: set.suggested[metric]!,
            }),
        ],
    },
    'reconciliationRequired': required,
    'blockerKinds': [
      for (final kind in blockers.map((b) => b.kind).toSet().toList()..sort())
        kind,
    ],
    'blockers': [for (final blocker in blockers) blocker.toJson()],
  };
}

/// Compares one candidate prescription, optionally an existing session's frozen
/// suggestions, and optionally a candidate rule with the latest resolved
/// decision for the same context. When there is no track, nothing reconciles.
ProgressionReconciliation assessProgressionReconciliation({
  required WorkoutRevision prescription,
  required String templateId,
  required int revision,
  required String slotId,
  required String role,
  ProgressionAnchor? track,
  TrainingSession? session,
  String? runId,
  DateTime? asOf,
  String ruleType = 'double',
  Map<String, Object?>? rule,
}) {
  if (session != null &&
      (session.revision.number != revision ||
          session.revision.definition.id != templateId))
    invalid('Candidate session does not use the compared prescription.');
  final base = ProgressionReconciliation(
    templateId: templateId,
    revision: revision,
    slotId: slotId,
    role: role,
    runId: runId,
    asOf: asOf,
    ruleType: ruleType,
    rule: rule,
    prescription: prescription,
    session: session,
    track: track,
    controlledMetrics: track?.controlledMetrics ?? const {},
    blockers: const [],
  );
  if (track == null) return base;
  final metrics = track.controlledMetrics;
  final blockers = _reconciliationBlockers(base, track);
  return ProgressionReconciliation(
    templateId: templateId,
    revision: revision,
    slotId: slotId,
    role: role,
    runId: runId,
    asOf: asOf,
    ruleType: ruleType,
    rule: rule,
    prescription: prescription,
    session: session,
    track: track,
    controlledMetrics: metrics,
    blockers: List.unmodifiable(blockers),
  );
}

List<ReconciliationBlocker> _reconciliationBlockers(
  ProgressionReconciliation candidate,
  ProgressionAnchor track,
) {
  final metrics = track.controlledMetrics, blockers = <ReconciliationBlocker>[];
  final priorCount = track.nextSets.length;
  final priorAuthored = track.pinnedRevision.definition.roleTargets(
    track.slotId,
    track.role,
  );
  final proposedAuthored = candidate.candidateTargets;
  if (proposedAuthored.length != priorCount ||
      priorAuthored.length != priorCount) {
    blockers.add(
      ReconciliationBlocker('workingSetCount', {
        'priorWorkingSetCount': priorCount,
        'proposedWorkingSetCount': proposedAuthored.length,
      }),
    );
  }
  final priorSlot = track.slot, candidateSlot = candidate.slot;
  for (final metric in metrics) {
    final prior = priorSlot.targets[metric],
        next = candidateSlot.targets[metric];
    if (prior == null || next == null) {
      if (prior != null || next != null)
        blockers.add(
          ReconciliationBlocker('slotTarget', {
            'metric': metric,
            'prior': prior?.toJson(),
            'proposed': next?.toJson(),
            'reason':
                'one prescription no longer targets this controlled metric',
          }),
        );
      continue;
    }
    if (prior.dimension != next.dimension) {
      blockers.add(
        ReconciliationBlocker('metricDimension', {
          'scope': 'slot',
          'metric': metric,
          'prior': prior.toJson(),
          'proposed': next.toJson(),
        }),
      );
    } else if (prior.compareTo(next) != 0) {
      blockers.add(
        ReconciliationBlocker('slotTarget', {
          'metric': metric,
          'prior': prior.toJson(),
          'proposed': next.toJson(),
        }),
      );
    }
  }
  final authored =
      candidate.prescription.definition.hasEffortTargets ||
      track.pinnedRevision.definition.hasEffortTargets;
  final shared = proposedAuthored.length < priorAuthored.length
      ? proposedAuthored.length
      : priorAuthored.length;
  final efforts = candidate.candidateEfforts;
  for (var ordinal = 0; ordinal < shared; ordinal++) {
    if (authored) {
      for (final metric in metrics) {
        final prior = priorAuthored[ordinal][metric],
            next = proposedAuthored[ordinal][metric];
        if (prior == null || next == null) {
          if (prior != null || next != null)
            blockers.add(
              ReconciliationBlocker('effortTarget', {
                'ordinal': ordinal,
                'metric': metric,
                'prior': prior?.toJson(),
                'proposed': next?.toJson(),
                'reason': 'one prescription no longer targets this metric',
              }),
            );
        } else if (prior.dimension != next.dimension ||
            prior.compareTo(next) != 0) {
          blockers.add(
            ReconciliationBlocker('effortTarget', {
              'ordinal': ordinal,
              'metric': metric,
              'prior': prior.toJson(),
              'proposed': next.toJson(),
            }),
          );
        }
      }
    }
    final priorSet = track.sets[ordinal], proposedSet = efforts[ordinal];
    if (priorSet.maxEffortMetrics.length !=
            proposedSet.maxEffortMetrics.length ||
        !priorSet.maxEffortMetrics.containsAll(proposedSet.maxEffortMetrics)) {
      blockers.add(
        ReconciliationBlocker('objectiveCriteria', {
          'ordinal': ordinal,
          'reason': 'max-effort metrics changed',
          'priorMaxEffort': priorSet.maxEffortMetrics.toList()..sort(),
          'proposedMaxEffort': proposedSet.maxEffortMetrics.toList()..sort(),
        }),
      );
    }
    final priorCriteria = {
          for (final e in priorSet.criteria.entries)
            e.key: e.value.semanticJson(),
        },
        proposedCriteria = {
          for (final e in proposedSet.criteria.entries)
            e.key: e.value.semanticJson(),
        };
    if (canonicalJson(priorCriteria) != canonicalJson(proposedCriteria)) {
      blockers.add(
        ReconciliationBlocker('objectiveCriteria', {
          'ordinal': ordinal,
          'priorCriteria': priorCriteria,
          'proposedCriteria': proposedCriteria,
        }),
      );
    }
  }
  final sets = candidate.candidateSets;
  if (sets.isNotEmpty) {
    if (sets.length != priorCount) {
      blockers.add(
        ReconciliationBlocker('workingSetCount', {
          'priorWorkingSetCount': priorCount,
          'proposedWorkingSetCount': sets.length,
        }),
      );
    }
    final compared = sets.length < priorCount ? sets.length : priorCount;
    for (var ordinal = 0; ordinal < compared; ordinal++) {
      for (final metric in metrics) {
        final expected = track.nextSets[ordinal][metric],
            actual = sets[ordinal].suggested[metric];
        if (expected == null ||
            actual == null ||
            expected.dimension != actual.dimension ||
            expected.compareTo(actual) != 0)
          blockers.add(
            ReconciliationBlocker('sessionTarget', {
              'ordinal': ordinal,
              'metric': metric,
              'applied': expected?.toJson(),
              'suggested': actual?.toJson(),
            }),
          );
      }
    }
  }
  final proposedRule = candidate.rule;
  if (proposedRule != null &&
      (candidate.ruleType != track.ruleType ||
          canonicalJson(proposedRule) != canonicalJson(track.rule))) {
    blockers.add(
      ReconciliationBlocker('rule', {
        'priorRuleType': track.ruleType,
        'proposedRuleType': candidate.ruleType,
        'priorRule': track.rule,
        'proposedRule': proposedRule,
      }),
    );
  }
  return blockers;
}

/// The current baseline a candidate is compared with, whether it came from a
/// resolved exposure or an explicit reconciliation receipt.
Map<String, Object?> _trackView(ProgressionAnchor track, Set<String> metrics) {
  final decision = track is ProgressionDecision ? track : null;
  final receipt = track is ReconciliationReceipt ? track : null;
  return {
    'decisionId': track.id,
    'sourceKind': receipt == null ? 'decision' : 'reconciliation',
    'sourceSessionId': decision?.session.id ?? receipt?.sourceSessionId,
    'sourceRevision':
        decision?.session.revision.number ?? receipt?.revisionNumber,
    'sourceSessionContentVersion': decision?.session.contentVersion,
    'resolvedAt': track.resolvedAt!.toUtc().toIso8601String(),
    'status': track.status,
    'ruleType': track.ruleType,
    'rule': track.rule,
    'sequence': track.sequence,
    'workingSetCount': track.sets.length,
    if (receipt != null) 'acknowledgedKinds': receipt.acknowledgedKinds,
    'state': {
      'failedSessions': track.failedSessions,
      if (track.ruleType == 'threshold') 'cursor': track.cursor,
      'nextSets': [
        for (final set in track.nextSets)
          metricsToJson({for (final metric in metrics) metric: set[metric]!}),
      ],
    },
  };
}

/// A conflict naming every explicit reconciliation kind that it needs.
BodyTmiException reconciliationConflict(
  ProgressionReconciliation assessment, {
  String? context,
}) {
  final kinds = [
    for (final kind
        in assessment.blockers.map((b) => b.kind).toSet().toList()..sort())
      kind,
  ];
  return BodyTmiException(
    'conflict',
    '${context ?? 'Progression'}: ${assessment.slotId}/${assessment.role} '
        'differs from the latest applied progression and needs explicit '
        'reconciliation (${kinds.join(', ')}). '
        'Use progression reconcile-status to inspect it.',
  );
}
