import 'errors.dart';
import 'quantity.dart';

/// Explicit numeric threshold selection. "Best" follows the performance direction;
/// "total" means an exact sum of the named metric, never inferred load-volume.
final class ResultAggregation {
  ResultAggregation._(this.mode, this.count);
  factory ResultAggregation.fromJson(Object? input, {bool failure = false}) {
    final j = jsonObject(input, 'result aggregation');
    checkKeys(j, {'mode', 'count'});
    final mode = requiredString(j, 'mode');
    final modes = failure
        ? {'all', 'total'}
        : {'all', 'any', 'best', 'last', 'total', 'kOfN'};
    if (!modes.contains(mode)) invalid('Unsupported result aggregation.');
    final count = j['count'];
    if (mode == 'kOfN') {
      if (count is! int || count < 1 || count > 10000)
        invalid('K-of-N needs an integer count from 1 to 10000.');
    } else if (j.containsKey('count')) {
      invalid('Only K-of-N accepts a count.');
    }
    return ResultAggregation._(mode, count as int?);
  }
  final String mode;
  final int? count;
  Map<String, Object?> toJson() => {
    'mode': mode,
    if (count != null) 'count': count,
  };
}

/// Keeps individual comparisons visible even when an aggregate is eligible.
/// Missing observations remain missing; they are never synthesized as zero.
final class ThresholdAssessment {
  ThresholdAssessment._(
    this.advancement,
    this.failure,
    this.values,
    this.failsFailureLimit,
    this.reachesThreshold,
    this.total,
    this.selected,
    this.unknown,
    this.failed,
    this.eligible,
    this.direction,
    this.explicitPerformance,
    this.failureLimit,
    this.advancementLimit,
  );
  factory ThresholdAssessment.evaluate({
    required ResultAggregation advancement,
    required ResultAggregation failure,
    required String metric,
    required Quantity minimum,
    required Quantity threshold,
    required List<Metrics?> results,
    String direction = 'higher',
    bool explicitPerformance = false,
  }) {
    if (!{'higher', 'lower'}.contains(direction))
      invalid('Unknown performance direction.');
    minimum.compareTo(
      threshold,
    ); // Always validate compatible bound dimensions.
    final lower = direction == 'lower';
    bool fails(Quantity value) =>
        lower ? value.compareTo(minimum) > 0 : value.compareTo(minimum) < 0;
    bool qualifies(Quantity value) => lower
        ? value.compareTo(threshold) <= 0
        : value.compareTo(threshold) >= 0;
    if (results.length > 10000) invalid('Too many aggregation results.');
    if (results.isNotEmpty &&
        advancement.count != null &&
        advancement.count! > results.length)
      invalid('K-of-N count exceeds the required result count.');
    final values = <Quantity?>[];
    final below = <bool?>[];
    final reaches = <bool?>[];
    Quantity? total, best;
    var missing = results.isEmpty;
    for (final result in results) {
      final value = result?[metric];
      values.add(value);
      if (value == null) {
        missing = true;
        below.add(null);
        reaches.add(null);
        continue;
      }
      below.add(fails(value));
      reaches.add(qualifies(value));
      if (advancement.mode == 'total' || failure.mode == 'total') {
        total = total == null ? value : total.add(value);
      }
      if (best == null ||
          (lower ? value.compareTo(best) < 0 : value.compareTo(best) > 0))
        best = value;
    }
    // Partial sums and partial bests must not certify an incomplete exposure.
    final selected = missing
        ? null
        : switch (advancement.mode) {
            'best' => best,
            'last' => values.last,
            'total' => total,
            _ => null,
          };
    final failed =
        !missing &&
        (failure.mode == 'total' ? fails(total!) : below.any((v) => v == true));
    final count = reaches.where((v) => v == true).length;
    final eligible =
        !missing &&
        !failed &&
        switch (advancement.mode) {
          'all' => count == values.length,
          'any' => count > 0,
          'kOfN' => count >= advancement.count!,
          _ => qualifies(selected!),
        };
    return ThresholdAssessment._(
      advancement,
      failure,
      List.unmodifiable(values),
      List.unmodifiable(below),
      List.unmodifiable(reaches),
      missing ? null : total,
      selected,
      missing,
      failed,
      eligible,
      direction,
      explicitPerformance || lower,
      minimum,
      threshold,
    );
  }
  final ResultAggregation advancement, failure;
  final List<Quantity?> values;
  final List<bool?> failsFailureLimit, reachesThreshold;

  /// Literal numeric comparison retained for existing core clients.
  List<bool?> get belowMinimum => List.unmodifiable([
    for (final v in values) v == null ? null : v.compareTo(failureLimit) < 0,
  ]);
  final Quantity? total, selected;
  final bool unknown, failed, eligible;
  final String direction;
  final bool explicitPerformance;
  final Quantity failureLimit, advancementLimit;
  Map<String, Object?> toJson() => {
    'advancement': advancement.toJson(),
    'failure': failure.toJson(),
    if (explicitPerformance)
      'performance': {
        'direction': direction,
        'failureLimit': failureLimit.toJson(),
        'advancementLimit': advancementLimit.toJson(),
      },
    'results': [
      for (var i = 0; i < values.length; i++)
        {
          'value': values[i]?.toJson(),
          if (explicitPerformance)
            'failsFailureLimit': failsFailureLimit[i]
          else
            'belowMinimum': failsFailureLimit[i],
          'reachesThreshold': reachesThreshold[i],
        },
    ],
    'total': total?.toJson(),
    'selected': selected?.toJson(),
    'unknown': unknown,
    'failed': failed,
    'eligible': eligible,
  };
}
