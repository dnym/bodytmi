import 'errors.dart';
import 'quantity.dart';
import 'result_aggregation.dart';
import 'effort_condition.dart';

/// Ordered performance thresholds choose one complete replacement step vector.
/// This never changes which levers a rule owns or which coordinator selects them.
final class IncrementBand {
  IncrementBand._(this.id, this.threshold, Metrics increments)
    : increments = Map.unmodifiable(increments);
  final String id;
  final Quantity threshold;
  final Metrics increments;
  Map<String, Object?> toJson() => {
    'id': id,
    'threshold': threshold.toJson(),
    'increments': metricsToJson(increments),
  };
}

final class IncrementBands {
  IncrementBands._(this.aggregation, List<IncrementBand> bands, this.direction)
    : bands = List.unmodifiable(bands);
  factory IncrementBands.fromJson(
    Object? input, {
    required Quantity performanceLimit,
    required Metrics baseIncrements,
    required String direction,
  }) {
    final j = jsonObject(input, 'incrementBands');
    checkKeys(j, {'aggregation', 'bands'});
    final aggregation = ResultAggregation.fromJson(j['aggregation']);
    if (!{'last', 'best', 'total'}.contains(aggregation.mode))
      invalid('Increment bands require last, best or total aggregation.');
    if (aggregation.mode == 'total' &&
        !{
          Dimension.count,
          Dimension.duration,
          Dimension.distance,
        }.contains(performanceLimit.dimension))
      invalid('Total increment bands require count, duration or distance.');
    if (!{'higher', 'lower'}.contains(direction))
      invalid('Invalid band direction.');
    final items = jsonList(j, 'bands');
    if (items.isEmpty ||
        items.length > 100 ||
        items.length * baseIncrements.length > 10000)
      invalid(
        'Increment bands need 1–100 bands and at most 10000 step entries.',
      );
    final bands = <IncrementBand>[];
    final ids = <String>{};
    for (final inputBand in items) {
      final row = jsonObject(inputBand, 'increment band');
      checkKeys(row, {'id', 'threshold', 'increments'});
      final id = identifier(row, 'id');
      if (!ids.add(id)) invalid('Increment band IDs must be unique.');
      final threshold = Quantity.fromJson(row['threshold']);
      if (threshold.dimension != performanceLimit.dimension)
        invalid('Increment band threshold dimension differs from performance.');
      if (bands.isNotEmpty) {
        final comparison = threshold.compareTo(bands.last.threshold);
        if (direction == 'higher' ? comparison <= 0 : comparison >= 0)
          invalid(
            'Band thresholds must be strictly ordered from easier to harder performance.',
          );
      }
      final increments = metricsFromJson(row['increments']);
      if (increments.length != baseIncrements.length ||
          baseIncrements.entries.any(
            (e) =>
                increments[e.key]?.dimension != e.value.dimension ||
                increments[e.key]!.value.compareTo(Decimal.zero) <= 0,
          ))
        invalid(
          'Each band must replace every base increment with a positive compatible step.',
        );
      bands.add(IncrementBand._(id, threshold, increments));
    }
    return IncrementBands._(aggregation, bands, direction);
  }
  final ResultAggregation aggregation;
  final List<IncrementBand> bands;
  final String direction;

  IncrementBandAssessment assess(
    ThresholdAssessment numeric,
    EffortAssessment? effort,
    Metrics baseIncrements,
  ) {
    final reason = numeric.unknown
        ? 'numeric-unknown'
        : numeric.failed
        ? 'numeric-failure'
        : !numeric.eligible
        ? 'numeric-hold'
        : effort != null && effort.status != 'met'
        ? 'effort-${effort.status}'
        : null;
    if (reason != null)
      return IncrementBandAssessment._(this, null, null, null, reason);
    // Numeric eligibility requires a complete, nonempty performance vector.
    var selected = numeric.values.first!;
    for (final value in numeric.values.skip(1)) {
      if (aggregation.mode == 'total') {
        selected = selected.add(value!);
      } else if (aggregation.mode == 'last' ||
          (direction == 'higher'
              ? value!.compareTo(selected) > 0
              : value!.compareTo(selected) < 0)) {
        selected = value!;
      }
    }
    IncrementBand? chosen;
    for (final band in bands) {
      if (direction == 'higher'
          ? selected.compareTo(band.threshold) >= 0
          : selected.compareTo(band.threshold) <= 0) {
        chosen = band;
      } else {
        break;
      }
    }
    return IncrementBandAssessment._(
      this,
      selected,
      chosen,
      chosen?.increments ?? baseIncrements,
      null,
    );
  }
}

final class IncrementBandAssessment {
  IncrementBandAssessment._(
    this.policy,
    this.selected,
    this.band,
    Metrics? increments,
    this.reason,
  ) : increments = increments == null ? null : Map.unmodifiable(increments);
  final IncrementBands policy;
  final Quantity? selected;
  final IncrementBand? band;
  final Metrics? increments;
  final String? reason;
  Map<String, Object?> toJson() => {
    'aggregation': policy.aggregation.toJson(),
    'direction': policy.direction,
    'status': reason != null
        ? 'not-evaluated'
        : band == null
        ? 'base'
        : 'band',
    if (reason != null) 'reason': reason,
    'selected': selected?.toJson(),
    'selectedBandId': band?.id,
    'bands': [
      for (final candidate in policy.bands)
        {
          ...candidate.toJson(),
          'reached': selected == null
              ? null
              : policy.direction == 'higher'
              ? selected!.compareTo(candidate.threshold) >= 0
              : selected!.compareTo(candidate.threshold) <= 0,
        },
    ],
    'effectiveIncrements': increments == null
        ? null
        : metricsToJson(increments!),
  };
}
