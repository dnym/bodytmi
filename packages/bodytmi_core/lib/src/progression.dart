import 'dart:convert';
import 'errors.dart';
import 'increment_bands.dart';
import 'set_observations.dart';
import 'effort_condition.dart';
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
    this.effortAssessment,
    this.incrementBandAssessment,
    this.coordination,
    List<ScaleResolution> scaleResolutions = const [],
    this.nextStage,
    this.nextReference,
  }) : scaleResolutions = List.unmodifiable(scaleResolutions),
       nextValues = Map.unmodifiable(nextValues);
  final String outcome;
  final String reason;
  final Metrics nextValues;
  final int failedSessions;
  final int cursor;
  final ThresholdAssessment? assessment;
  final EffortAssessment? effortAssessment;
  final IncrementBandAssessment? incrementBandAssessment;
  final LeverSelection? coordination;
  final List<ScaleResolution> scaleResolutions;

  /// The stage value later sessions plan, for staged rules (null otherwise).
  final String? nextStage;

  /// The cycle reference a cycle-restart rule carries forward (null when the
  /// rule has no cycle restart or no reference is known yet).
  final Metrics? nextReference;
  Map<String, Object?> toJson() => {
    'outcome': outcome,
    'reason': reason,
    'nextValues': metricsToJson(nextValues),
    if (nextStage != null) 'nextStage': nextStage,
    'nextState': {
      'failedSessions': failedSessions,
      'cursor': cursor,
      if (nextReference != null) 'reference': metricsToJson(nextReference!),
    },
    'requiresAcceptance': true,
    if (assessment != null) 'assessment': assessment!.toJson(),
    if (effortAssessment != null)
      'effortAssessment': effortAssessment!.toJson(),
    if (incrementBandAssessment != null)
      'incrementBandAssessment': incrementBandAssessment!.toJson(),
    if (coordination != null) 'coordination': coordination!.toJson(),
    if (scaleResolutions.isNotEmpty)
      'scaleResolutions': [for (final r in scaleResolutions) r.toJson()],
  };
}

/// One authored stage of a staged threshold rule: a value of the slot's stage
/// lever (typically a variant set scheme) with its own inclusive performance
/// limits, since each structure has its own success criterion.
final class ThresholdStage {
  const ThresholdStage(
    this.value,
    this.failureLimit,
    this.advancementLimit, [
    this.offsets = const {},
  ]);
  final String value;
  final Quantity failureLimit, advancementLimit;

  /// Nonnegative amounts this stage adds to the base of each offset metric
  /// (wave loading: A +0, B +5 kg, C +10 kg). Moving between stages shifts
  /// the current value by the offset difference.
  final Metrics offsets;
  Map<String, Object?> toJson() => {
    'value': value,
    'failureLimit': failureLimit.toJson(),
    'advancementLimit': advancementLimit.toJson(),
    if (offsets.isNotEmpty) 'offsets': metricsToJson(offsets),
  };
}

/// Ordered failure-driven stages (e.g. 5x3 → 6x2 → 10x1). When the failed
/// exposure count reaches deloadAfter, the rule moves to the next stage and
/// holds every numeric setting; failing at the last stage applies the
/// configured deload (if any) and restarts at the first stage. Stage order is
/// authored; no difficulty is inferred from it.
/// Restarting a failure-driven tier cycle heavier than a remembered reference
/// (GZCLP T2: back to 10x3, slightly heavier than previously used). The
/// reference is explicit track state: [basis] cycleStart remembers the values
/// a cycle started with, firstStageExit the values at which the first stage
/// was last left. The restart applies [increments] to that reference.
final class CycleRestart {
  CycleRestart._(this.basis, this.increments);
  factory CycleRestart.fromJson(Object? input, Metrics ruleIncrements) {
    final j = jsonObject(input, 'cycleRestart');
    checkKeys(j, {'basis', 'increments'});
    final basis = requiredString(j, 'basis');
    if (basis != 'cycleStart' && basis != 'firstStageExit')
      invalid('cycleRestart basis must be cycleStart or firstStageExit.');
    final increments = metricsFromJson(j['increments']);
    if (increments.isEmpty) invalid('cycleRestart needs increments.');
    for (final e in increments.entries) {
      if (ruleIncrements[e.key]?.dimension != e.value.dimension)
        invalid('cycleRestart increments must name increment metrics.');
    }
    return CycleRestart._(basis, increments);
  }
  final String basis;
  final Metrics increments;
  Metrics referenceOf(Metrics values) =>
      Map.unmodifiable({for (final key in increments.keys) key: values[key]!});
  Map<String, Object?> toJson() => {
    'basis': basis,
    'increments': metricsToJson(increments),
  };
}

final class ThresholdStages {
  ThresholdStages._(
    this.lever,
    List<ThresholdStage> order,
    this.advanceOn, [
    this.cycleRestart,
  ]) : order = List.unmodifiable(order);
  factory ThresholdStages.fromJson(
    Object? input, {
    required Dimension dimension,
    required String direction,
    required bool sameScope,
    Metrics increments = const {},
  }) {
    final json = jsonObject(input, 'stages');
    checkKeys(json, {'lever', 'order', 'advanceOn', 'cycleRestart'});
    final lever = identifier(json, 'lever');
    final advanceOn = json['advanceOn'] ?? 'failure';
    if (advanceOn != 'failure' && advanceOn != 'success')
      invalid('Stages advanceOn must be failure or success.');
    final raw = jsonList(json, 'order');
    if (raw.length < 2 || raw.length > 64)
      invalid('Staged threshold rules need 2–64 stages.');
    final order = <ThresholdStage>[];
    for (final item in raw) {
      final stage = jsonObject(item, 'stage');
      checkKeys(stage, {
        'value',
        'failureLimit',
        'advancementLimit',
        'offsets',
      });
      final value = identifier(stage, 'value');
      if (order.any((s) => s.value == value))
        invalid('Stage $value occurs more than once.');
      final failure = Quantity.fromJson(stage['failureLimit']);
      final advancement = Quantity.fromJson(stage['advancementLimit']);
      if (failure.dimension != dimension || advancement.dimension != dimension)
        invalid('Stage $value limits must match the performance metric.');
      final c = failure.compareTo(advancement);
      if (sameScope && (direction == 'higher' ? c > 0 : c < 0))
        invalid('Stage $value limits contradict the performance direction.');
      final offsets = stage.containsKey('offsets')
          ? metricsFromJson(stage['offsets'])
          : const <String, Quantity>{};
      for (final e in offsets.entries) {
        if (increments[e.key]?.dimension != e.value.dimension)
          invalid('Stage offsets must name increment metrics.');
      }
      order.add(ThresholdStage(value, failure, advancement, offsets));
    }
    final keys = order.first.offsets.keys.toSet();
    if (order.any(
      (s) =>
          s.offsets.length != keys.length ||
          !s.offsets.keys.every(keys.contains),
    ))
      invalid('Every stage declares offsets for the same metrics.');
    final restart = json.containsKey('cycleRestart')
        ? CycleRestart.fromJson(json['cycleRestart'], increments)
        : null;
    if (restart != null && advanceOn != 'failure')
      invalid('cycleRestart applies to failure-driven stages only.');
    return ThresholdStages._(lever, order, advanceOn as String, restart);
  }

  /// Optional heavier cycle restart replacing the last-stage deload/restart.
  final CycleRestart? cycleRestart;
  final String lever;
  final List<ThresholdStage> order;

  /// failure: move on reaching deloadAfter failed exposures (tiers).
  /// success: move on advancement; the wrap applies increments (waves).
  final String advanceOn;

  /// [values] moved from stage [from] to [to] by the offset difference, or
  /// null when a value would become negative.
  Metrics? shift(Metrics values, int from, int to) {
    final next = <String, Quantity>{...values};
    for (final e in order[from].offsets.entries) {
      final current = values[e.key]!;
      final shifted =
          current.value - e.value.value + order[to].offsets[e.key]!.value;
      if (shifted.compareTo(Decimal.zero) < 0) return null;
      next[e.key] = Quantity(shifted.toString(), current.unit.name);
    }
    return next;
  }

  int indexOf(String value) {
    final i = order.indexWhere((s) => s.value == value);
    if (i < 0) invalid('Current stage $value is not declared by the rule.');
    return i;
  }

  Map<String, Object?> toJson() => {
    'lever': lever,
    if (advanceOn != 'failure') 'advanceOn': advanceOn,
    if (cycleRestart != null) 'cycleRestart': cycleRestart!.toJson(),
    'order': [for (final s in order) s.toJson()],
  };
}

/// Explicit retest policy (GZCLP's new 5RM, a training-max test): when the
/// rule would deload — for failure-driven tiers, on exhausting the last stage —
/// the outcome is `retest` instead. A later, explicitly named test result
/// reseeds [metric] at factor × the tested value (optionally floored to
/// [roundTo]) and restarts at [restartStage]. [stage], when set, is the stage
/// lever value whose authored branch plans the test in place of the lift.
final class ThresholdRetest {
  ThresholdRetest._(
    this.metric,
    this.repetitionMetric,
    this.minimumRepetitions,
    this.factor,
    this.roundTo,
    this.stage,
    this.restartStage,
  );
  factory ThresholdRetest.fromJson(
    Object? input, {
    required Metrics increments,
    ThresholdStages? stages,
  }) {
    final j = jsonObject(input, 'retest');
    checkKeys(j, {
      'metric',
      'repetitions',
      'factor',
      'roundTo',
      'stage',
      'restartStage',
    });
    final metric = identifier(j, 'metric');
    final step = increments[metric];
    if (step == null) invalid('Retest metric must be an increment metric.');
    final reps = jsonObject(j['repetitions'], 'retest repetitions');
    checkKeys(reps, {'metric', 'minimum'});
    final repMetric = identifier(reps, 'metric');
    final minimum = Quantity.fromJson(reps['minimum']);
    if (minimum.dimension != Dimension.count ||
        minimum.value.compareTo(Decimal.zero) <= 0)
      invalid('Retest repetitions need a positive count minimum.');
    final factorText = j['factor'];
    if (factorText is! String)
      invalid('Retest factor must be a decimal string.');
    final factor = Decimal.parse(factorText);
    if (factor.compareTo(Decimal.zero) <= 0 ||
        factor.compareTo(Decimal.parse('2')) > 0)
      invalid('Retest factor must be greater than 0 and at most 2.');
    final roundTo = j.containsKey('roundTo')
        ? Quantity.fromJson(j['roundTo'])
        : null;
    if (roundTo != null &&
        (roundTo.dimension != step.dimension ||
            roundTo.value.compareTo(Decimal.zero) <= 0))
      invalid('Retest roundTo must be a positive step of the retest metric.');
    final stage = j.containsKey('stage') ? identifier(j, 'stage') : null;
    final restart = j.containsKey('restartStage')
        ? identifier(j, 'restartStage')
        : null;
    if ((stage != null || restart != null) && stages == null)
      invalid('Retest stages need a staged rule.');
    if (stage != null && stages!.order.any((s) => s.value == stage))
      invalid('The retest stage cannot also be a progression stage.');
    if (restart != null) stages!.indexOf(restart);
    return ThresholdRetest._(
      metric,
      repMetric,
      minimum,
      factor,
      roundTo,
      stage,
      restart ?? stages?.order.first.value,
    );
  }
  final String metric, repetitionMetric;
  final Quantity minimumRepetitions;
  final Decimal factor;
  final Quantity? roundTo;
  final String? stage, restartStage;

  /// The reseeded value from a tested [measured] quantity, exactly.
  Quantity reseed(Quantity measured) {
    var value = measured.value * factor;
    if (roundTo != null) value = value.floorToMultiple(roundTo!.value);
    return Quantity(value.toString(), measured.unit.name);
  }
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
    this.advancementEffort,
    this.incrementBands, [
    this.stages,
    this.retest,
  ]);

  /// Parsed rules by their exact JSON. Stored decisions re-parse the same
  /// rule many times per read (the BBR rules carry a 300-position scale,
  /// about 0.6 ms each); rules are immutable, so identical input shares one
  /// value. Failures are never cached; the memo is bounded.
  factory ThresholdRule.fromJson(Object? input) {
    final String key;
    try {
      key = jsonEncode(input);
    } on JsonUnsupportedObjectError {
      return ThresholdRule._parse(input);
    }
    final hit = _parsed[key];
    if (hit != null) return hit;
    final rule = ThresholdRule._parse(input);
    if (_parsed.length >= 256) _parsed.clear();
    return _parsed[key] = rule;
  }
  static final _parsed = <String, ThresholdRule>{};

  factory ThresholdRule._parse(Object? input) {
    final json = jsonObject(input, 'rule');
    checkKeys(json, {
      'aggregation',
      'failureAggregation',
      'metric',
      'performance',
      'advancementEffort',
      'incrementBands',
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
      'stages',
      'retest',
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
      scales[entry.key] = binding;
      // Instance positions are bound per exposure; checked when bound.
      if (binding.fromInstance) continue;
      if (increments[entry.key] case final Quantity step) {
        if (step.dimension != binding.scale.unit.dimension)
          invalid('Scale and increment dimensions differ.');
      }
      ticks += binding.scale.ticks.length;
      if (ticks > 10000) invalid('Rule scale bindings exceed 10000 ticks.');
      scales[entry.key] = binding;
    }
    final stages = json.containsKey('stages')
        ? ThresholdStages.fromJson(
            json['stages'],
            dimension: min.dimension,
            direction: performanceDirection,
            sameScope:
                (aggregation.mode == 'total') ==
                (failureAggregation.mode == 'total'),
            increments: increments,
          )
        : null;
    return ThresholdRule._(
      identifier(json, 'metric'),
      min,
      threshold,
      Map.unmodifiable(increments),
      Map.unmodifiable(metricsFromJson(json['resets'] ?? <String, Object?>{})),
      Map.unmodifiable(maximums),
      sequence == null ? null : List.unmodifiable(sequence),
      after,
      Decimal.parse('1') - percent * Decimal.parse('0.01'),
      Set.unmodifiable(deload.cast<String>()),
      aggregation,
      failureAggregation,
      json.containsKey('aggregation') || json.containsKey('failureAggregation'),
      Map.unmodifiable(minimums),
      Map<String, String>.unmodifiable(directions.cast<String, String>()),
      json.containsKey('minimums') || json.containsKey('directions'),
      mode as String,
      chosenMetric,
      priorityOrder == null ? null : List.unmodifiable(priorityOrder),
      Map.unmodifiable(scales),
      json.containsKey('scales'),
      performanceDirection,
      performance != null,
      json.containsKey('advancementEffort')
          ? AdvancementEffort.fromJson(json['advancementEffort'])
          : null,
      json.containsKey('incrementBands')
          ? IncrementBands.fromJson(
              json['incrementBands'],
              performanceLimit: min,
              baseIncrements: increments,
              direction: performanceDirection,
            )
          : null,
      stages,
      json.containsKey('retest')
          ? ThresholdRetest.fromJson(
              json['retest'],
              increments: increments,
              stages: stages,
            )
          : null,
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

  /// Metrics whose scale is the instance an exposure was performed on.
  Set<String> get instanceScaleMetrics => {
    for (final e in scales.entries)
      if (e.value.fromInstance) e.key,
  };

  /// This rule with each instance-bound scale replaced by [positions] (the
  /// instance's derived scale for that metric). Dimensions are checked here.
  ThresholdRule bindInstanceScales(Map<String, NumericScale> positions) {
    final bound = <String, ScaleBinding>{};
    for (final e in scales.entries) {
      if (!e.value.fromInstance) {
        bound[e.key] = e.value;
        continue;
      }
      final scale =
          positions[e.key] ??
          invalid('No instance positions bound for ${e.key}.');
      if (increments[e.key] case final Quantity step
          when step.dimension != scale.unit.dimension)
        invalid('The instance positions and increment dimensions differ.');
      bound[e.key] = e.value.bound(scale);
    }
    return ThresholdRule._(
      metric,
      minimum,
      threshold,
      increments,
      resets,
      maximums,
      sequence,
      deloadAfter,
      deloadFactor,
      deloadMetrics,
      aggregation,
      failureAggregation,
      hasExplicitAggregation,
      minimums,
      directions,
      hasNumericPolicy,
      coordinationMode,
      chosenMetric,
      priorityOrder,
      Map.unmodifiable(bound),
      hasScalePolicy,
      performanceDirection,
      hasPerformancePolicy,
      advancementEffort,
      incrementBands,
      stages,
      retest,
    );
  }

  final bool hasScalePolicy;
  final String performanceDirection;
  final bool hasPerformancePolicy;
  final AdvancementEffort? advancementEffort;
  final IncrementBands? incrementBands;

  /// Optional failure-driven stages over one categorical slot lever.
  final ThresholdStages? stages;

  /// Optional explicit retest replacing the deload/restart action.
  final ThresholdRetest? retest;
  Quantity get failureLimit => minimum;
  Quantity get advancementLimit => threshold;
  bool get hasSelectionPolicy => chosenMetric != null || priorityOrder != null;
  bool decreases(String metric) => directions[metric] == 'decrease';

  bool _withinBounds(Metrics values) =>
      minimums.entries.every((e) => values[e.key]!.compareTo(e.value) >= 0) &&
      maximums.entries.every((e) => values[e.key]!.compareTo(e.value) <= 0);

  ProgressionProposal evaluate({
    required Metrics current,
    required List<Metrics?> results,
    List<SetObservations?>? observations,
    int failedSessions = 0,
    int cursor = 0,
    String? stage,
    Metrics? reference,
  }) => evaluateVector(
    currentSets: [current],
    results: results,
    observations: observations,
    failedSessions: failedSessions,
    cursor: cursor,
    stage: stage,
    reference: reference,
  ).single;

  /// Classify once. Chosen/priority advancement selects a whole-vector candidate.
  /// Failure/deload proposals and other coordinator transforms remain per-set;
  /// callers applying any vector must hold it if any transformation is blocked.
  List<ProgressionProposal> evaluateVector({
    required List<Metrics> currentSets,
    required List<Metrics?> results,
    List<SetObservations?>? observations,
    int failedSessions = 0,
    int cursor = 0,
    String? stage,
    Metrics? reference,
  }) {
    final restart = stages?.cycleRestart;
    if (reference != null) {
      if (restart == null)
        invalid('Only cycle-restart rules carry a cycle reference.');
      if (reference.length != restart.increments.length ||
          restart.increments.entries.any(
            (e) => reference[e.key]?.dimension != e.value.dimension,
          ))
        invalid('Cycle reference does not match the restart metrics.');
    }
    final proposals = _evaluateStaged(
      currentSets: currentSets,
      results: results,
      observations: observations,
      failedSessions: failedSessions,
      cursor: cursor,
      stage: stage,
      reference: reference,
    );
    if (restart == null) return proposals;
    final index = stages!.indexOf(stage!);
    final last = stages!.order.length - 1;
    return List.unmodifiable([
      for (var i = 0; i < proposals.length; i++)
        _withReference(proposals[i], () {
          final p = proposals[i], current = restart.referenceOf(currentSets[i]);
          final restarted =
              p.outcome == 'stage' &&
              index == last &&
              p.nextStage == stages!.order.first.value;
          if (restarted)
            return restart.basis == 'cycleStart'
                ? restart.referenceOf(p.nextValues)
                : reference ?? current;
          if (restart.basis == 'firstStageExit')
            return p.outcome == 'stage' && index == 0 ? current : reference;
          return reference ?? (index == 0 ? current : null);
        }()),
    ]);
  }

  ProgressionProposal _withReference(ProgressionProposal p, Metrics? ref) =>
      ProgressionProposal(
        p.outcome,
        p.reason,
        p.nextValues,
        p.failedSessions,
        p.cursor,
        assessment: p.assessment,
        effortAssessment: p.effortAssessment,
        incrementBandAssessment: p.incrementBandAssessment,
        coordination: p.coordination,
        scaleResolutions: p.scaleResolutions,
        nextStage: p.nextStage,
        nextReference: ref,
      );

  List<ProgressionProposal> _evaluateStaged({
    required List<Metrics> currentSets,
    required List<Metrics?> results,
    List<SetObservations?>? observations,
    int failedSessions = 0,
    int cursor = 0,
    String? stage,
    Metrics? reference,
  }) {
    if ((stages == null) != (stage == null))
      invalid(
        stages == null
            ? 'Only staged threshold rules take a current stage.'
            : 'Staged threshold rules need the current stage.',
      );
    final stageIndex = stage == null ? null : stages!.indexOf(stage);
    final limits = stageIndex == null ? null : stages!.order[stageIndex];
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
    if (results.length > 10000) invalid('Too many aggregation results.');
    if (observations != null && observations.length != results.length)
      invalid('Effort observations must match the required result vector.');
    final reported =
        observations ?? List<SetObservations?>.filled(results.length, null);
    for (var i = 0; i < reported.length; i++) {
      reported[i]?.validateStatus(results[i] == null ? 'skipped' : 'completed');
    }
    final eligibleResults = [
      for (var i = 0; i < results.length; i++)
        reported[i]?.interrupted == true ? null : results[i],
    ];
    final effortAssessment = advancementEffort?.assess(reported, [
      for (final r in eligibleResults) r?[metric] != null,
    ]);
    final assessment = ThresholdAssessment.evaluate(
      advancement: aggregation,
      failure: failureAggregation,
      metric: metric,
      minimum: limits?.failureLimit ?? minimum,
      threshold: limits?.advancementLimit ?? threshold,
      results: eligibleResults,
      direction: performanceDirection,
      explicitPerformance: hasPerformancePolicy,
    );
    final incrementBandAssessment = incrementBands?.assess(
      assessment,
      effortAssessment,
      increments,
    );
    List<ProgressionProposal> evaluate(String? selected) => [
      for (final current in currentSets)
        _evaluate(
          current,
          assessment,
          failedSessions,
          cursor,
          selectedMetric: selected,
          effortAssessment: effortAssessment,
          incrementBandAssessment: incrementBandAssessment,
          stageIndex: stageIndex,
          reference: reference,
        ),
    ];
    if (!hasSelectionPolicy) return List.unmodifiable(evaluate(null));
    final candidates = priorityOrder ?? [chosenMetric!];
    if (candidates.length * currentSets.length > 100000)
      invalid('Coordinator exceeds 100000 candidate-set evaluations.');
    final attempts = <LeverCandidate>[];
    for (final metric in candidates) {
      final proposals = evaluate(metric);
      if (!assessment.eligible ||
          (effortAssessment != null && effortAssessment.status != 'met')) {
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
          effortAssessment: effortAssessment,
          incrementBandAssessment: incrementBandAssessment,
          nextStage: stage,
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
    effortAssessment: p.effortAssessment,
    incrementBandAssessment: p.incrementBandAssessment,
    coordination: selection,
    scaleResolutions: p.scaleResolutions,
    nextStage: p.nextStage,
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
    EffortAssessment? effortAssessment,
    IncrementBandAssessment? incrementBandAssessment,
    int? stageIndex,
    Metrics? reference,
  }) {
    final scaleResolutions = <ScaleResolution>[];
    final currentStage = stageIndex == null
        ? null
        : stages!.order[stageIndex].value;
    ProgressionProposal proposal(
      String outcome,
      String reason,
      Metrics values,
      int failures,
      int nextCursor, [
      String? stageValue,
    ]) => ProgressionProposal(
      outcome,
      reason,
      values,
      failures,
      nextCursor,
      assessment: hasExplicitAggregation || hasPerformancePolicy
          ? assessment
          : null,
      scaleResolutions: scaleResolutions,
      effortAssessment: effortAssessment,
      incrementBandAssessment: incrementBandAssessment,
      nextStage: stageValue ?? currentStage,
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
      final tiered = stageIndex != null && stages!.advanceOn == 'failure';
      final last = tiered && stageIndex == stages!.order.length - 1;
      if (retest != null && failures >= deloadAfter && (!tiered || last))
        return proposal(
          'retest',
          'Failed-exposure threshold reached; retest before restarting. '
              'Record the test and apply it with progression retest.',
          current,
          0,
          cursor,
          retest!.stage,
        );
      if (failures >= deloadAfter && tiered && !last) {
        final shifted = stages!.shift(current, stageIndex, stageIndex + 1);
        if (shifted == null)
          return proposal(
            'blocked',
            'A stage offset would make a setting negative; hold all changes.',
            current,
            failures,
            cursor,
          );
        return proposal(
          'stage',
          'Failed-exposure threshold reached; move to the next stage and '
              'hold every numeric setting apart from stage offsets.',
          shifted,
          0,
          cursor,
          stages!.order[stageIndex + 1].value,
        );
      }
      final restarted = last && failures >= deloadAfter
          ? stages!.shift(current, stageIndex, 0)
          : current;
      final cycle = stages?.cycleRestart;
      if (last &&
          failures >= deloadAfter &&
          restarted != null &&
          cycle != null) {
        // Back to the first stage, heavier than the remembered reference
        // (or, before any reference is known, than the current values).
        final next = <String, Quantity>{...restarted};
        for (final e in cycle.increments.entries) {
          final base = reference?[e.key] ?? restarted[e.key]!;
          next[e.key] = base.add(e.value);
        }
        if ((hasNumericPolicy || hasScalePolicy) && !_withinBounds(next))
          return proposal(
            'blocked',
            'A lever bound blocks the cycle restart; hold all changes.',
            current,
            failures,
            cursor,
          );
        return proposal(
          'stage',
          'Last stage exhausted; restart the cycle heavier than its '
              'reference.',
          next,
          0,
          cursor,
          stages!.order.first.value,
        );
      }
      if (restarted == null)
        return proposal(
          'blocked',
          'A stage offset would make a setting negative; hold all changes.',
          current,
          failures,
          cursor,
        );
      if (failures >= deloadAfter && last && deloadMetrics.isEmpty)
        return proposal(
          'stage',
          'Failed-exposure threshold reached at the last stage; restart at '
              'the first stage without a configured deload.',
          restarted,
          0,
          cursor,
          stages!.order.first.value,
        );
      if (failures >= deloadAfter && deloadMetrics.isNotEmpty) {
        final next = <String, Quantity>{...restarted};
        for (final key in deloadMetrics) {
          final value = restarted[key]!;
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
          last ? stages!.order.first.value : null,
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
    if (effortAssessment != null && effortAssessment.status != 'met') {
      final unknown = effortAssessment.status == 'unknown';
      return proposal(
        unknown ? 'unknown' : 'hold',
        unknown
            ? 'Required advancement effort ratings are missing or use a different RPE scale.'
            : 'Numeric thresholds met but advancement effort conditions are not met.',
        current,
        unknown ? failedSessions : 0,
        cursor,
      );
    }
    // Waves: success moves to the next stage by its offsets; only the wrap
    // from the last stage to the first applies the rule's increments.
    var base = current;
    if (stageIndex != null && stages!.advanceOn == 'success') {
      final wraps = stageIndex == stages!.order.length - 1;
      final target = wraps ? 0 : stageIndex + 1;
      final shifted = stages!.shift(current, stageIndex, target);
      if (shifted == null)
        return proposal(
          'blocked',
          'A stage offset would make a setting negative; hold all changes.',
          current,
          0,
          cursor,
        );
      if (!wraps)
        return proposal(
          'stage',
          'Advancement reached; move to the next stage by its offsets.',
          shifted,
          0,
          cursor,
          stages!.order[target].value,
        );
      base = shifted;
    }
    final wrapStage = stageIndex != null && stages!.advanceOn == 'success'
        ? stages!.order.first.value
        : null;
    final selected = selectedMetric != null
        ? [selectedMetric]
        : sequence == null
        ? increments.keys.toList()
        : [sequence![cursor]];
    final next = <String, Quantity>{...base};
    for (final key in selected) {
      final prior = base[key]!;
      final step = (incrementBandAssessment?.increments ?? increments)[key]!;
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
      wrapStage,
    );
  }
}
