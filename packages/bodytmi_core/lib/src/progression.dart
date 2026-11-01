import 'errors.dart';
import 'quantity.dart';
import 'result_aggregation.dart';
import 'lever_selection.dart';
import 'numeric_scale.dart';
export 'lever_selection.dart';
export 'result_aggregation.dart';

/// A proposal only: callers must persist approval and an idempotent application
/// identity before applying nextValues/nextState. Evaluation never mutates input.
final class ProgressionProposal {
  ProgressionProposal(
    this.outcome,
    this.reason,
    Metrics nextValues,
    this.failedSessions,
    this.cursor, {
    this.assessment,
    this.coordination,
    List<ScaleResolution> scaleResolutions = const [],
  }) : scaleResolutions = List.unmodifiable(scaleResolutions),
       nextValues = Map.unmodifiable(nextValues);
  final String outcome;
  final String reason;
  final Metrics nextValues;
  final int failedSessions;
  final int cursor;
  final ThresholdAssessment? assessment;
  final LeverSelection? coordination;
  final List<ScaleResolution> scaleResolutions;
  Map<String, Object?> toJson() => {
    'outcome': outcome,
    'reason': reason,
    'nextValues': metricsToJson(nextValues),
    'nextState': {'failedSessions': failedSessions, 'cursor': cursor},
    'requiresAcceptance': true,
    if (assessment != null) 'assessment': assessment!.toJson(),
    if (coordination != null) 'coordination': coordination!.toJson(),
    if (scaleResolutions.isNotEmpty)
      'scaleResolutions': [for (final r in scaleResolutions) r.toJson()],
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
    this.aggregation,
    this.failureAggregation,
    this.hasExplicitAggregation,
    this.minimums,
    this.directions,
    this.hasNumericPolicy,
    this.coordinationMode,
    this.chosenMetric,
    this.priorityOrder,
    this.scales,
    this.hasScalePolicy,
    this.performanceDirection,
    this.hasPerformancePolicy,
  );

  factory ThresholdRule.fromJson(Object? input) {
    final json = jsonObject(input, 'rule');
    checkKeys(json, {
      'aggregation',
      'failureAggregation',
      'metric',
      'performance',
      'minimum',
      'threshold',
      'increments',
      'resets',
      'maximums',
      'minimums',
      'directions',
      'scales',
      'coordination',
      'deloadAfter',
      'deloadPercent',
      'deloadMetrics',
    });
    final performance = json.containsKey('performance')
        ? jsonObject(json['performance'], 'performance predicate')
        : null;
    if (performance != null) {
      checkKeys(performance, {'direction', 'failureLimit', 'advancementLimit'});
      if (json.containsKey('minimum') || json.containsKey('threshold'))
        invalid(
          'Performance bounds cannot be mixed with legacy minimum/threshold.',
        );
    }
    final performanceDirection = performance == null
        ? 'higher'
        : requiredString(performance, 'direction');
    if (!{'higher', 'lower'}.contains(performanceDirection))
      invalid('Performance direction must be higher or lower.');
    final min = Quantity.fromJson(
      performance == null ? json['minimum'] : performance['failureLimit'],
    );
    final threshold = Quantity.fromJson(
      performance == null ? json['threshold'] : performance['advancementLimit'],
    );
    final boundComparison = min.compareTo(threshold);
    final increments = metricsFromJson(json['increments']);
    if (increments.isEmpty) invalid('At least one increment is required.');
    if (increments.values.any((q) => q.value.compareTo(Decimal.zero) <= 0))
      invalid('Increments must be positive.');
    final config = jsonObject(
      json['coordination'] ?? {'mode': 'all'},
      'coordination',
    );
    checkKeys(config, {'mode', 'order', 'metric'});
    final mode = config['mode'] ?? 'all';
    List<String>? sequence, priorityOrder;
    String? chosenMetric;
    if (mode != 'chosen' && config.containsKey('metric'))
      invalid('Only chosen coordination accepts metric.');
    if (mode == 'chosen') {
      if (config.containsKey('order'))
        invalid('Chosen coordination does not accept order.');
      chosenMetric = identifier(config, 'metric');
      if (!increments.containsKey(chosenMetric))
        invalid('Chosen metric must name an increment.');
    } else if (mode == 'roundRobin' ||
        mode == 'weighted' ||
        mode == 'priority') {
      final order = jsonList(config, 'order');
      if (order.isEmpty ||
          order.length > 1000 ||
          order.any((k) => k is! String || !increments.containsKey(k)))
        invalid('Coordinator order must name increment metrics.');
      final values = List<String>.unmodifiable(order.cast<String>());
      if (mode != 'weighted' && values.toSet().length != values.length)
        invalid('Round-robin/priority order must have unique entries.');
      if (mode == 'priority') {
        priorityOrder = values;
      } else {
        sequence = values;
      }
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
    final aggregation = ResultAggregation.fromJson(
      json.containsKey('aggregation') ? json['aggregation'] : {'mode': 'all'},
    );
    final failureAggregation = ResultAggregation.fromJson(
      json.containsKey('failureAggregation')
          ? json['failureAggregation']
          : {'mode': 'all'},
      failure: true,
    );
    if ((aggregation.mode == 'total') == (failureAggregation.mode == 'total') &&
        (performanceDirection == 'higher'
            ? boundComparison > 0
            : boundComparison < 0))
      invalid(
        'Failure and advancement limits contradict performance direction in the same aggregation scope.',
      );
    if ((aggregation.mode == 'total' || failureAggregation.mode == 'total') &&
        !{
          Dimension.count,
          Dimension.duration,
          Dimension.distance,
        }.contains(min.dimension))
      invalid('Total aggregation requires count, duration or distance.');
    final minimums = metricsFromJson(
      json.containsKey('minimums') ? json['minimums'] : <String, Object?>{},
    );
    final maximums = metricsFromJson(json['maximums'] ?? <String, Object?>{});
    for (final lower in minimums.entries) {
      final upper = maximums[lower.key];
      if (upper != null && lower.value.compareTo(upper) > 0)
        invalid('Lower lever bound exceeds upper bound.');
    }
    final directions = jsonObject(
      json.containsKey('directions') ? json['directions'] : <String, Object?>{},
      'directions',
    );
    final controlled = {...increments.keys, ...deload.cast<String>()};
    for (final entry in directions.entries) {
      if (!controlled.contains(entry.key) ||
          !{'increase', 'decrease'}.contains(entry.value))
        invalid(
          'Directions must name an increment or deload metric and increase/decrease.',
        );
    }
    final scaleInput = jsonObject(
      json.containsKey('scales') ? json['scales'] : <String, Object?>{},
      'scales',
    );
    final scales = <String, ScaleBinding>{};
    var ticks = 0;
    for (final entry in scaleInput.entries) {
      if (!controlled.contains(entry.key))
        invalid('Scale bindings must name increment or deload metrics.');
      final binding = ScaleBinding.fromJson(entry.value);
      if (increments[entry.key] case final Quantity step) {
        if (step.dimension != binding.scale.unit.dimension)
          invalid('Scale and increment dimensions differ.');
      }
      ticks += binding.scale.ticks.length;
      if (ticks > 10000) invalid('Rule scale bindings exceed 10000 ticks.');
      scales[entry.key] = binding;
    }
    return ThresholdRule._(
      identifier(json, 'metric'),
      min,
      threshold,
      increments,
      metricsFromJson(json['resets'] ?? <String, Object?>{}),
      maximums,
      sequence,
      after,
      Decimal.parse('1') - percent * Decimal.parse('0.01'),
      Set.unmodifiable(deload.cast<String>()),
      aggregation,
      failureAggregation,
      json.containsKey('aggregation') || json.containsKey('failureAggregation'),
      minimums,
      Map<String, String>.unmodifiable(directions.cast<String, String>()),
      json.containsKey('minimums') || json.containsKey('directions'),
      mode as String,
      chosenMetric,
      priorityOrder,
      Map.unmodifiable(scales),
      json.containsKey('scales'),
      performanceDirection,
      performance != null,
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
  final ResultAggregation aggregation, failureAggregation;
  final bool hasExplicitAggregation;
  final Metrics minimums;
  final Map<String, String> directions;
  final bool hasNumericPolicy;
  final String coordinationMode;
  final String? chosenMetric;
  final List<String>? priorityOrder;
  final Map<String, ScaleBinding> scales;
  final bool hasScalePolicy;
  final String performanceDirection;
  final bool hasPerformancePolicy;
  Quantity get failureLimit => minimum;
  Quantity get advancementLimit => threshold;
  bool get hasScaleRanges =>
      scales.values.any((binding) => binding.scale.range != null);
  bool get hasSelectionPolicy => chosenMetric != null || priorityOrder != null;
  bool decreases(String metric) => directions[metric] == 'decrease';

  bool _withinBounds(Metrics values) =>
      minimums.entries.every((e) => values[e.key]!.compareTo(e.value) >= 0) &&
      maximums.entries.every((e) => values[e.key]!.compareTo(e.value) <= 0);

  ProgressionProposal evaluate({
    required Metrics current,
    required List<Metrics?> results,
    int failedSessions = 0,
    int cursor = 0,
  }) => evaluateVector(
    currentSets: [current],
    results: results,
    failedSessions: failedSessions,
    cursor: cursor,
  ).single;

  /// Classify once. Chosen/priority advancement selects a whole-vector candidate.
  /// Failure/deload proposals and other coordinator transforms remain per-set;
  /// callers applying any vector must hold it if any transformation is blocked.
  List<ProgressionProposal> evaluateVector({
    required List<Metrics> currentSets,
    required List<Metrics?> results,
    int failedSessions = 0,
    int cursor = 0,
  }) {
    if (currentSets.isEmpty || currentSets.length > 10000)
      invalid('Threshold progression needs 1 to 10000 target sets.');
    if (failedSessions < 0 ||
        cursor < 0 ||
        (sequence != null && cursor >= sequence!.length) ||
        (hasSelectionPolicy && cursor != 0))
      invalid('Invalid progression state.');
    for (final current in currentSets) {
      _validateCurrent(current);
    }
    final assessment = ThresholdAssessment.evaluate(
      advancement: aggregation,
      failure: failureAggregation,
      metric: metric,
      minimum: minimum,
      threshold: threshold,
      results: results,
      direction: performanceDirection,
      explicitPerformance: hasPerformancePolicy,
    );
    List<ProgressionProposal> evaluate(String? selected) => [
      for (final current in currentSets)
        _evaluate(
          current,
          assessment,
          failedSessions,
          cursor,
          selectedMetric: selected,
        ),
    ];
    if (!hasSelectionPolicy) return List.unmodifiable(evaluate(null));
    final candidates = priorityOrder ?? [chosenMetric!];
    if (candidates.length * currentSets.length > 100000)
      invalid('Coordinator exceeds 100000 candidate-set evaluations.');
    final attempts = <LeverCandidate>[];
    for (final metric in candidates) {
      final proposals = evaluate(metric);
      if (!assessment.eligible) {
        final selection = LeverSelection(coordinationMode, null, const []);
        return List.unmodifiable([
          for (final p in proposals) _withSelection(p, selection),
        ]);
      }
      final blocked = [
        for (var i = 0; i < proposals.length; i++)
          if (proposals[i].outcome == 'blocked')
            BlockedLeverSet(i, proposals[i].reason),
      ];
      attempts.add(LeverCandidate(metric, blocked));
      if (blocked.isEmpty) {
        final selection = LeverSelection(coordinationMode, metric, attempts);
        return List.unmodifiable([
          for (final p in proposals) _withSelection(p, selection),
        ]);
      }
    }
    final selection = LeverSelection(coordinationMode, null, attempts);
    return List.unmodifiable([
      for (final current in currentSets)
        ProgressionProposal(
          'blocked',
          'No configured candidate can advance the complete target vector; hold all changes.',
          current,
          0,
          cursor,
          assessment: hasExplicitAggregation || hasPerformancePolicy
              ? assessment
              : null,
          coordination: selection,
        ),
    ]);
  }

  ProgressionProposal _withSelection(
    ProgressionProposal p,
    LeverSelection selection,
  ) => ProgressionProposal(
    p.outcome,
    p.reason,
    p.nextValues,
    p.failedSessions,
    p.cursor,
    assessment: p.assessment,
    coordination: selection,
    scaleResolutions: p.scaleResolutions,
  );

  void _validateCurrent(Metrics current) {
    for (final entry in scales.entries) {
      if (current[entry.key]?.dimension != entry.value.scale.unit.dimension)
        invalid('Scale and current setting dimensions differ.');
    }
    for (final values in [increments, resets, maximums, minimums]) {
      for (final entry in values.entries) {
        final value = current[entry.key];
        if (value == null || value.dimension != entry.value.dimension)
          invalid('Missing/incompatible current lever ${entry.key}.');
      }
    }
    if (resets.keys.any(increments.containsKey))
      invalid('A lever cannot be incremented and reset in the same rule.');
    for (final key in deloadMetrics) {
      final value = current[key];
      if (value == null || value.dimension == Dimension.count)
        invalid('Deload needs a non-count current quantity: $key.');
    }
  }

  ProgressionProposal _evaluate(
    Metrics current,
    ThresholdAssessment assessment,
    int failedSessions,
    int cursor, {
    String? selectedMetric,
  }) {
    final scaleResolutions = <ScaleResolution>[];
    ProgressionProposal proposal(
      String outcome,
      String reason,
      Metrics values,
      int failures,
      int nextCursor,
    ) => ProgressionProposal(
      outcome,
      reason,
      values,
      failures,
      nextCursor,
      assessment: hasExplicitAggregation || hasPerformancePolicy
          ? assessment
          : null,
      scaleResolutions: scaleResolutions,
    );
    if (assessment.unknown) {
      return proposal(
        'unknown',
        'Required confirmed results are missing or skipped.',
        current,
        failedSessions,
        cursor,
      );
    }
    if (assessment.failed) {
      final failures =
          failedSessions + 1; // one exposure, regardless of failed set count
      if (failures >= deloadAfter && deloadMetrics.isNotEmpty) {
        final next = <String, Quantity>{...current};
        for (final key in deloadMetrics) {
          final value = current[key]!;
          var target = Quantity(
            (value.value *
                    (decreases(key)
                        ? Decimal.parse('2') - deloadFactor
                        : deloadFactor))
                .toString(),
            value.unit.name,
          );
          if (scales[key] case final ScaleBinding binding) {
            final resolution = binding.scale
                .resolve(
                  target,
                  binding.deloadRounding,
                  beyond: value,
                  direction: decreases(key) ? 'increase' : 'decrease',
                )
                .forMetric(key);
            scaleResolutions.add(resolution);
            if (resolution.tick == null)
              return proposal(
                'blocked',
                'No available easier tick for $key; hold the entire deload.',
                current,
                failures,
                cursor,
              );
            target = resolution.tick!.quantity;
          }
          next[key] = target;
        }
        if ((hasNumericPolicy || hasScalePolicy) && !_withinBounds(next))
          return proposal(
            'blocked',
            'A lever bound blocks the entire deload; hold all changes.',
            current,
            failures,
            cursor,
          );
        return proposal(
          'deload',
          hasNumericPolicy
              ? 'Failed-session threshold reached; easier numeric settings proposed.'
              : 'Failed-session threshold reached; reduction proposed.',
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
    if (!assessment.eligible) {
      return proposal(
        'hold',
        hasPerformancePolicy
            ? 'Failure gate passed but advancement predicate is not met.'
            : hasExplicitAggregation
            ? 'Failure gate passed but advancement aggregation is not met.'
            : 'Minimums met but not every upper threshold reached.',
        current,
        0,
        cursor,
      );
    }
    final selected = selectedMetric != null
        ? [selectedMetric]
        : sequence == null
        ? increments.keys.toList()
        : [sequence![cursor]];
    final next = <String, Quantity>{...current};
    for (final key in selected) {
      final prior = current[key]!;
      final step = increments[key]!;
      if (prior.dimension != step.dimension)
        invalid('Increment dimension mismatch.');
      final nextValue = decreases(key)
          ? prior.value - step.value
          : prior.value + step.value;
      if (nextValue.compareTo(Decimal.zero) < 0)
        return proposal(
          'blocked',
          'Lever $key cannot step below zero; hold all changes.',
          current,
          0,
          cursor,
        );
      var value = Quantity(nextValue.toString(), prior.unit.name);
      if (scales[key] case final ScaleBinding binding) {
        final resolution = binding.scale
            .resolve(
              value,
              binding.rounding,
              beyond: prior,
              direction: decreases(key) ? 'decrease' : 'increase',
            )
            .forMetric(key);
        scaleResolutions.add(resolution);
        if (resolution.tick == null)
          return proposal(
            'blocked',
            'No available harder tick for $key; hold all changes.',
            current,
            0,
            cursor,
          );
        value = resolution.tick!.quantity;
      }
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
    if (minimums.entries.any((e) => next[e.key]!.compareTo(e.value) < 0))
      return proposal(
        'blocked',
        'A lower lever bound blocks the entire advance; hold all changes.',
        current,
        0,
        cursor,
      );
    return proposal(
      'advance',
      hasPerformancePolicy
          ? 'Configured advancement predicate reached (inclusive).'
          : hasExplicitAggregation
          ? 'Configured advancement aggregation reached (inclusive).'
          : 'Every required upper threshold reached (inclusive).',
      next,
      0,
      sequence == null ? cursor : (cursor + 1) % sequence!.length,
    );
  }
}
