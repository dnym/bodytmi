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
  );
  factory ProgressionEvaluation.double(DoubleProgressionProposal p) =>
      ProgressionEvaluation._(
        p.outcome,
        p.reason,
        p.nextSets,
        p.failedSessions,
        0,
        p,
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
      if (target == null || target.dimension != rule.minimum.dimension)
        invalid(
          'Stored threshold progression needs a configured performance metric.',
        );
    }
    // All-required bounds are exactly represented by the minimum observation.
    // Avoid rescanning every result for each per-set target transformation.
    Quantity? minimum;
    var missing = false;
    for (final set in sets) {
      final value = set.status == SetStatus.completed
          ? set.actuals[rule.metric]
          : null;
      if (value == null) {
        missing = true;
      } else if (minimum == null || value.compareTo(minimum) < 0) {
        minimum = value;
      }
    }
    final results = <Metrics?>[
      missing ? null : {rule.metric: minimum!},
    ];
    final proposals = [
      for (final s in sets)
        rule.evaluate(
          current: s.suggested,
          results: results,
          failedSessions: failures,
          cursor: cursor,
        ),
    ];
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
      changed ? failures : first.failedSessions,
      hold ? cursor : first.cursor,
      null,
    );
  }
  final String outcome, reason;
  final List<Metrics> nextSets;
  final int failedSessions, cursor;
  final DoubleProgressionProposal? _double;
  Map<String, Object?> toJson() =>
      _double?.toJson() ??
      {
        'outcome': outcome,
        'reason': reason,
        'nextSets': [for (final set in nextSets) metricsToJson(set)],
        'nextState': {'failedSessions': failedSessions, 'cursor': cursor},
        'requiresAcceptance': true,
      };
}
