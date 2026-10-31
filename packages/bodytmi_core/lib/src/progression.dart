import 'errors.dart';
import 'quantity.dart';

/// A proposal only: callers must persist approval and an idempotent application
/// identity before applying nextValues/nextState. Evaluation never mutates input.
final class ProgressionProposal {
  ProgressionProposal(
    this.outcome,
    this.reason,
    Metrics nextValues,
    this.failedSessions,
    this.cursor,
  ) : nextValues = Map.unmodifiable(nextValues);
  final String outcome;
  final String reason;
  final Metrics nextValues;
  final int failedSessions;
  final int cursor;
  Map<String, Object?> toJson() => {
    'outcome': outcome,
    'reason': reason,
    'nextValues': metricsToJson(nextValues),
    'nextState': {'failedSessions': failedSessions, 'cursor': cursor},
    'requiresAcceptance': true,
  };
}

/// First numeric threshold rule, reusable for reps, duration, or other dimensions.
final class ThresholdRule {
  ThresholdRule._(
    this.metric,
    this.minimum,
    this.threshold,
    this.increments,
    this.resets,
    this.maximums,
    this.sequence,
    this.deloadAfter,
    this.deloadFactor,
    this.deloadMetrics,
  );

  factory ThresholdRule.fromJson(Object? input) {
    final json = jsonObject(input, 'rule');
    checkKeys(json, {
      'metric',
      'minimum',
      'threshold',
      'increments',
      'resets',
      'maximums',
      'coordination',
      'deloadAfter',
      'deloadPercent',
      'deloadMetrics',
    });
    final min = Quantity.fromJson(json['minimum']);
    final threshold = Quantity.fromJson(json['threshold']);
    if (min.compareTo(threshold) > 0) invalid('minimum exceeds threshold.');
    final increments = metricsFromJson(json['increments']);
    if (increments.isEmpty) invalid('At least one increment is required.');
    if (increments.values.any((q) => q.value.compareTo(Decimal.zero) <= 0))
      invalid('Increments must be positive.');
    final config = jsonObject(
      json['coordination'] ?? {'mode': 'all'},
      'coordination',
    );
    checkKeys(config, {'mode', 'order'});
    final mode = config['mode'] ?? 'all';
    List<String>? sequence;
    if (mode == 'roundRobin' || mode == 'weighted') {
      final order = jsonList(config, 'order');
      if (order.isEmpty ||
          order.length > 1000 ||
          order.any((k) => k is! String || !increments.containsKey(k)))
        invalid('Coordinator order must name increment metrics.');
      sequence = List.unmodifiable(order.cast<String>());
      if (mode == 'roundRobin' && sequence.toSet().length != sequence.length)
        invalid('Round-robin order must have unique entries.');
    } else if (mode != 'all') {
      invalid('Unknown coordination mode.');
    }
    final after = json['deloadAfter'] ?? 3;
    if (after is! int || after < 1) invalid('deloadAfter must be positive.');
    final percentValue = json['deloadPercent'] ?? '10';
    if (percentValue is! String)
      invalid('deloadPercent must be a decimal string.');
    final percent = Decimal.parse(percentValue);
    if (percent.compareTo(Decimal.zero) <= 0 ||
        percent.compareTo(Decimal.parse('100')) >= 0)
      invalid('deloadPercent must be greater than 0 and less than 100.');
    final deload = json['deloadMetrics'] ?? <Object?>[];
    if (deload is! List<Object?> || deload.any((k) => k is! String))
      invalid('deloadMetrics must be strings.');
    return ThresholdRule._(
      identifier(json, 'metric'),
      min,
      threshold,
      increments,
      metricsFromJson(json['resets'] ?? <String, Object?>{}),
      metricsFromJson(json['maximums'] ?? <String, Object?>{}),
      sequence,
      after,
      Decimal.parse('1') - percent * Decimal.parse('0.01'),
      Set.unmodifiable(deload.cast<String>()),
    );
  }

  final String metric;
  final Quantity minimum;
  final Quantity threshold;
  final Metrics increments;
  final Metrics resets;
  final Metrics maximums;
  final List<String>? sequence;
  final int deloadAfter;
  final Decimal deloadFactor;
  final Set<String> deloadMetrics;

  ProgressionProposal evaluate({
    required Metrics current,
    required List<Metrics?> results,
    int failedSessions = 0,
    int cursor = 0,
  }) {
    if (failedSessions < 0 ||
        cursor < 0 ||
        (sequence != null && cursor >= sequence!.length))
      invalid('Invalid progression state.');
    for (final entry in {...increments, ...resets, ...maximums}.entries) {
      final value = current[entry.key];
      if (value == null || value.dimension != entry.value.dimension)
        invalid('Missing/incompatible current lever ${entry.key}.');
    }
    if (resets.keys.any(increments.containsKey))
      invalid('A lever cannot be incremented and reset in the same rule.');
    for (final key in deloadMetrics) {
      final value = current[key];
      if (value == null || value.dimension == Dimension.count)
        invalid('Deload needs a non-count current quantity: $key.');
    }
    ProgressionProposal proposal(
      String outcome,
      String reason,
      Metrics values,
      int failures,
      int nextCursor,
    ) => ProgressionProposal(outcome, reason, values, failures, nextCursor);
    if (results.isEmpty || results.any((r) => r == null || r[metric] == null)) {
      return proposal(
        'unknown',
        'Required confirmed results are missing or skipped.',
        current,
        failedSessions,
        cursor,
      );
    }
    final values = [for (final r in results) r![metric]!];
    if (values.any((v) => v.compareTo(minimum) < 0)) {
      final failures =
          failedSessions + 1; // one exposure, regardless of failed set count
      if (failures >= deloadAfter && deloadMetrics.isNotEmpty) {
        final next = <String, Quantity>{...current};
        for (final key in deloadMetrics) {
          final value = current[key]!;
          next[key] = Quantity(
            (value.value * deloadFactor).toString(),
            value.unit.name,
          );
        }
        return proposal(
          'deload',
          'Failed-session threshold reached; reduction proposed.',
          next,
          0,
          cursor,
        );
      }
      return proposal(
        'failed',
        'One failed exercise exposure; advancement blocked.',
        current,
        failures,
        cursor,
      );
    }
    // Meeting all minimums counts as a successful exposure and resets failures.
    if (values.any((v) => v.compareTo(threshold) < 0)) {
      return proposal(
        'hold',
        'Minimums met but not every upper threshold reached.',
        current,
        0,
        cursor,
      );
    }
    final selected = sequence == null
        ? increments.keys.toList()
        : [sequence![cursor]];
    final next = <String, Quantity>{...current};
    for (final key in selected) {
      final value = current[key]!.add(increments[key]!);
      if (maximums[key] case final Quantity maximum) {
        if (value.compareTo(maximum) > 0)
          return proposal(
            'blocked',
            'Lever $key reached its bound; hold all changes.',
            current,
            0,
            cursor,
          );
      }
      next[key] = value;
    }
    next.addAll(resets);
    for (final bound in maximums.entries) {
      if (next[bound.key]!.compareTo(bound.value) > 0) {
        return proposal(
          'blocked',
          'Reset/current value exceeds ${bound.key} bound; hold all changes.',
          current,
          0,
          cursor,
        );
      }
    }
    return proposal(
      'advance',
      'Every required upper threshold reached (inclusive).',
      next,
      0,
      sequence == null ? cursor : (cursor + 1) % sequence!.length,
    );
  }
}
