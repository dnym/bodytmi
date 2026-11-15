import 'package:bodytmi_core/bodytmi_core.dart';

/// Adapts pure rule proposals to a per-set stored application without weakening
/// vector atomicity or allowing changed controlled inputs to certify progression.
final class ProgressionEvaluation {
  ProgressionEvaluation._(
    this.outcome,
    this.reason,
    this.nextSets,
    this.failedSessions,
    this.cursor,
    this._double,
    this.assessment,
    this.coordination,
    this.scaleResolutions,
    this.effortAssessment,
    this.incrementBandAssessment, [
    this._ordinal,
    this._withCursor = true,
    this.nextStage,
  ]);

  /// The stage a staged threshold rule plans next (held unless it moved).
  final String? nextStage;

  /// Sets performed with categorical settings other than planned are not an
  /// exposure of the planned prescription: hold every target and counter.
  factory ProgressionEvaluation.categoricalReview(
    List<TrainingSet> sets,
    int failures,
    int cursor, {
    required bool withCursor,
  }) => ProgressionEvaluation._(
    'review',
    'Sets were performed with categorical settings that differ from plan; '
        'reconcile before progression.',
    List.unmodifiable([for (final s in sets) s.suggested]),
    failures,
    cursor,
    null,
    null,
    null,
    const [],
    null,
    null,
    null,
    withCursor,
  );
  final bool _withCursor;
  factory ProgressionEvaluation.double(DoubleProgressionProposal p) =>
      ProgressionEvaluation._(
        p.outcome,
        p.reason,
        p.nextSets,
        p.failedSessions,
        0,
        p,
        null,
        null,
        const [],
        null,
        null,
      );
  factory ProgressionEvaluation.threshold(
    ThresholdRule rule,
    List<TrainingSet> sets,
    int failures,
    int cursor,
  ) {
    final controlled = {
      ...rule.increments.keys,
      ...rule.resets.keys,
      ...rule.deloadMetrics,
    };
    for (final set in sets) {
      final target = set.suggested[rule.metric];
      if ((target == null &&
              !((set.maxEffortMetrics.contains(rule.metric) &&
                      rule.minimum.dimension == Dimension.count) ||
                  set.criteria[rule.metric]?.unit.dimension ==
                      rule.minimum.dimension)) ||
          (target != null && target.dimension != rule.minimum.dimension))
        invalid(
          'Stored threshold progression needs a configured performance metric.',
        );
    }
    final results = [
      for (final s in sets) s.eligibleForPerformance ? s.actuals : null,
    ];
    final missing = results.any((r) => r == null || r[rule.metric] == null);
    String? stage;
    if (rule.stages case final staged?) {
      final values = {for (final s in sets) s.settings[staged.lever]};
      if (values.length != 1 || values.single == null)
        invalid(
          'Staged threshold progression needs every working set to plan the '
          'same value of lever ${staged.lever}.',
        );
      stage = values.single;
      if (stage == rule.retest?.stage)
        invalid(
          'This session planned the retest; apply its result with '
          'progression retest.',
        );
    }
    final proposals = rule.evaluateVector(
      currentSets: [for (final s in sets) s.suggested],
      results: [
        for (final s in sets)
          s.status == SetStatus.completed ? s.actuals : null,
      ],
      observations: [for (final s in sets) s.observations],
      failedSessions: failures,
      cursor: cursor,
      stage: stage,
    );
    final first = proposals.first;
    final changed =
        !missing &&
        sets.any(
          (s) => controlled
              .where((m) => m != rule.metric)
              .any(
                (m) =>
                    s.actuals[m] == null ||
                    s.actuals[m]!.compareTo(s.suggested[m]!) != 0,
              ),
        );
    final blocked = proposals.any((p) => p.outcome == 'blocked');
    final outcome = changed
        ? 'review'
        : blocked
        ? 'blocked'
        : first.outcome;
    final reason = changed
        ? 'Actual controlled values differ from prescription; reconcile before progression.'
        : blocked
        ? 'A set bound blocks the entire vector; hold all controlled targets.'
        : first.reason;
    final hold = changed || blocked;
    return ProgressionEvaluation._(
      outcome,
      reason,
      List.unmodifiable([
        for (var i = 0; i < sets.length; i++)
          Map<String, Quantity>.unmodifiable(
            hold ? sets[i].suggested : proposals[i].nextValues,
          ),
      ]),
      changed
          ? failures
          : blocked
          ? proposals.firstWhere((p) => p.outcome == 'blocked').failedSessions
          : first.failedSessions,
      hold ? cursor : first.cursor,
      null,
      first.assessment,
      first.coordination,
      List.unmodifiable([for (final p in proposals) p.scaleResolutions]),
      first.effortAssessment,
      first.incrementBandAssessment,
      null,
      true,
      hold ? stage : first.nextStage,
    );
  }

  /// Ordinal levers move the whole working vector between authored levels.
  /// Changed controlled actuals still require review before application.
  factory ProgressionEvaluation.ordinal(
    OrdinalRule rule,
    List<TrainingSet> sets,
    int failures,
  ) {
    for (final set in sets) {
      final target = set.suggested[rule.metric];
      if ((target == null &&
              !((set.maxEffortMetrics.contains(rule.metric) &&
                      rule.failureLimit.dimension == Dimension.count) ||
                  set.criteria[rule.metric]?.unit.dimension ==
                      rule.failureLimit.dimension)) ||
          (target != null && target.dimension != rule.failureLimit.dimension))
        invalid(
          'Stored ordinal progression needs a configured performance metric.',
        );
    }
    final results = [
      for (final s in sets) s.eligibleForPerformance ? s.actuals : null,
    ];
    final missing = results.any((r) => r == null || r[rule.metric] == null);
    final proposal = rule.evaluate(
      currentSets: [for (final s in sets) s.suggested],
      results: [
        for (final s in sets)
          s.status == SetStatus.completed ? s.actuals : null,
      ],
      observations: [for (final s in sets) s.observations],
      failedSessions: failures,
      currentSettings: [for (final s in sets) s.settings],
    );
    final changed =
        !missing &&
        sets.any(
          (s) => rule.controlledMetrics
              .where((m) => m != rule.metric)
              .any(
                (m) =>
                    s.actuals[m] == null ||
                    s.actuals[m]!.compareTo(s.suggested[m]!) != 0,
              ),
        );
    final outcome = changed ? 'review' : proposal.outcome;
    final reason = changed
        ? 'Actual controlled values differ from prescription; reconcile before progression.'
        : proposal.reason;
    final nextSets = changed
        ? [for (final s in sets) s.suggested]
        : proposal.nextSets;
    return ProgressionEvaluation._(
      outcome,
      reason,
      List.unmodifiable(nextSets),
      changed ? failures : proposal.failedSessions,
      0,
      null,
      proposal.assessment,
      null,
      const [],
      proposal.effortAssessment,
      null,
      proposal,
    );
  }
  final String outcome, reason;
  final List<Metrics> nextSets;
  final int failedSessions, cursor;
  final DoubleProgressionProposal? _double;
  final OrdinalProposal? _ordinal;

  /// Declared successor levels of an ordinal 'choice' outcome.
  List<String> get candidates => _ordinal?.candidates ?? const [];

  /// The ordinal level an advance/deload proposes.
  String? get nextLevel => _ordinal?.nextLevel;
  final ThresholdAssessment? assessment;
  final EffortAssessment? effortAssessment;
  final IncrementBandAssessment? incrementBandAssessment;
  final LeverSelection? coordination;
  final List<List<ScaleResolution>> scaleResolutions;
  Map<String, Object?> toJson() =>
      _double?.toJson() ??
      _ordinal?.toJson() ??
      {
        'outcome': outcome,
        'reason': reason,
        'nextSets': [for (final set in nextSets) metricsToJson(set)],
        'nextState': {
          'failedSessions': failedSessions,
          if (_withCursor) 'cursor': cursor,
        },
        if (nextStage != null) 'nextStage': nextStage,
        'requiresAcceptance': true,
        if (assessment != null) 'assessment': assessment!.toJson(),
        if (effortAssessment != null)
          'effortAssessment': effortAssessment!.toJson(),
        if (incrementBandAssessment != null)
          'incrementBandAssessment': incrementBandAssessment!.toJson(),
        if (coordination != null) 'coordination': coordination!.toJson(),
        if (scaleResolutions.any((r) => r.isNotEmpty))
          'scaleResolutions': [
            for (var i = 0; i < scaleResolutions.length; i++)
              {
                'ordinal': i,
                'resolutions': [
                  for (final r in scaleResolutions[i]) r.toJson(),
                ],
              },
          ],
      };
}
