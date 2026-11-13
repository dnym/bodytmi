import 'errors.dart';
import 'effort_condition.dart';
import 'quantity.dart';
import 'result_aggregation.dart';
import 'set_observations.dart';

/// One authored step of an ordinal lever: a complete explicit working target
/// vector. Array order is the declared easier-to-harder progression order.
/// Difficulty is never inferred from the numbers inside a level.
final class OrdinalLevel {
  OrdinalLevel._(this.id, this.targets);
  factory OrdinalLevel.fromJson(Object? input) {
    final json = jsonObject(input, 'ordinal level');
    checkKeys(json, {'id', 'targets'});
    final targets = metricsFromJson(json['targets']);
    if (targets.isEmpty) invalid('Ordinal levels need at least one target.');
    return OrdinalLevel._(
      identifier(json, 'id'),
      Map<String, Quantity>.unmodifiable(targets),
    );
  }
  final String id;
  final Metrics targets;
  Map<String, Object?> toJson() => {
    'id': id,
    'targets': metricsToJson(targets),
  };
}

/// A vector proposal over every working set together. Ordinal levers carry no
/// coordinator position. Callers must persist approval before applying
/// nextSets/failedSessions. Evaluation never mutates input.
final class OrdinalProposal {
  OrdinalProposal(
    this.outcome,
    this.reason,
    List<Metrics> nextSets,
    this.failedSessions, {
    this.assessment,
    this.effortAssessment,
  }) : nextSets = List.unmodifiable([
         for (final set in nextSets) Map<String, Quantity>.unmodifiable(set),
       ]);
  final String outcome;
  final String reason;
  final List<Metrics> nextSets;
  final int failedSessions;
  final ThresholdAssessment? assessment;
  final EffortAssessment? effortAssessment;
  Map<String, Object?> toJson() => {
    'outcome': outcome,
    'reason': reason,
    'nextSets': [for (final set in nextSets) metricsToJson(set)],
    'nextState': {'failedSessions': failedSessions},
    'requiresAcceptance': true,
    if (assessment != null) 'assessment': assessment!.toJson(),
    if (effortAssessment != null)
      'effortAssessment': effortAssessment!.toJson(),
  };
}

/// Ordinal/categorical progression levers: the controlled target vector moves
/// between explicitly authored levels as a whole. Success is judged by one
/// explicit numeric performance predicate; the level order itself is authored,
/// never derived from the target numbers.
final class OrdinalRule {
  OrdinalRule._(
    this.metric,
    this.performanceDirection,
    this.failureLimit,
    this.advancementLimit,
    List<OrdinalLevel> levels,
    this.aggregation,
    this.failureAggregation,
    this.advancementEffort,
    this.deloadAfter,
    this.deloadLevelId,
  ) : levels = List.unmodifiable(levels),
      controlledMetrics = Set.unmodifiable(levels.first.targets.keys);

  factory OrdinalRule.fromJson(Object? input) {
    final json = jsonObject(input, 'rule');
    checkKeys(json, {
      'metric',
      'performance',
      'levels',
      'aggregation',
      'failureAggregation',
      'advancementEffort',
      'deloadAfter',
      'deloadLevel',
    });
    final performance = jsonObject(
      json['performance'],
      'performance predicate',
    );
    checkKeys(performance, {'direction', 'failureLimit', 'advancementLimit'});
    final direction = requiredString(performance, 'direction');
    if (!{'higher', 'lower'}.contains(direction))
      invalid('Performance direction must be higher or lower.');
    final failureLimit = Quantity.fromJson(performance['failureLimit']);
    final advancementLimit = Quantity.fromJson(performance['advancementLimit']);
    final boundComparison = failureLimit.compareTo(advancementLimit);
    final levelInput = jsonList(json, 'levels');
    if (levelInput.isEmpty || levelInput.length > 1000)
      invalid('Ordinal progression needs 1 to 1000 levels.');
    final levels = [
      for (final level in levelInput) OrdinalLevel.fromJson(level),
    ];
    if (levels.map((level) => level.id).toSet().length != levels.length)
      invalid('Ordinal level ids must be unique.');
    final controlled = levels.first.targets;
    for (final level in levels.skip(1)) {
      final levelMetrics = level.targets.keys.toSet();
      final controlMetrics = controlled.keys.toSet();
      if (levelMetrics.difference(controlMetrics).isNotEmpty ||
          controlMetrics.difference(levelMetrics).isNotEmpty) {
        invalid('Every ordinal level must control the same metrics.');
      }
      for (final entry in level.targets.entries) {
        if (entry.value.dimension != controlled[entry.key]!.dimension)
          invalid('Ordinal level target dimensions must match.');
      }
    }
    for (var i = 0; i < levels.length; i++) {
      for (var j = i + 1; j < levels.length; j++) {
        if (_sameVector(levels[i].targets, levels[j].targets))
          invalid('Ordinal levels must have distinct target vectors.');
      }
    }
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
        (direction == 'higher' ? boundComparison > 0 : boundComparison < 0))
      invalid(
        'Failure and advancement limits contradict performance direction in the same aggregation scope.',
      );
    if ((aggregation.mode == 'total' || failureAggregation.mode == 'total') &&
        !{
          Dimension.count,
          Dimension.duration,
          Dimension.distance,
        }.contains(failureLimit.dimension))
      invalid('Total aggregation requires count, duration or distance.');
    final after = json['deloadAfter'] ?? 3;
    if (after is! int || after < 1) invalid('deloadAfter must be positive.');
    String? deloadLevelId;
    if (json.containsKey('deloadLevel')) {
      deloadLevelId = identifier(json, 'deloadLevel');
      final index = levels.indexWhere((level) => level.id == deloadLevelId);
      if (index < 0) invalid('deloadLevel must name a published level.');
      if (index == levels.length - 1)
        invalid('deloadLevel must be easier than the hardest level.');
    }
    return OrdinalRule._(
      identifier(json, 'metric'),
      direction,
      failureLimit,
      advancementLimit,
      levels,
      aggregation,
      failureAggregation,
      json.containsKey('advancementEffort')
          ? AdvancementEffort.fromJson(json['advancementEffort'])
          : null,
      after,
      deloadLevelId,
    );
  }

  final String metric;
  final String performanceDirection;
  final Quantity failureLimit, advancementLimit;
  final List<OrdinalLevel> levels;
  final Set<String> controlledMetrics;
  final ResultAggregation aggregation, failureAggregation;
  final AdvancementEffort? advancementEffort;
  final int deloadAfter;
  final String? deloadLevelId;

  bool get hasDeloadLevel => deloadLevelId != null;

  int _levelIndex(String id) => levels.indexWhere((level) => level.id == id);

  /// Classify the whole exposure once, then move (or hold) every working set
  /// together. Ordinal levels never partially advance.
  OrdinalProposal evaluate({
    required List<Metrics> currentSets,
    required List<Metrics?> results,
    List<SetObservations?>? observations,
    int failedSessions = 0,
  }) {
    if (currentSets.isEmpty || currentSets.length > 10000)
      invalid('Ordinal progression needs 1 to 10000 target sets.');
    if (failedSessions < 0) invalid('Invalid progression state.');
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
      minimum: failureLimit,
      threshold: advancementLimit,
      results: eligibleResults,
      direction: performanceDirection,
      explicitPerformance: true,
    );
    OrdinalProposal proposal(
      String outcome,
      String reason,
      List<Metrics> nextSets,
      int failures,
    ) => OrdinalProposal(
      outcome,
      reason,
      nextSets,
      failures,
      assessment: assessment,
      effortAssessment: effortAssessment,
    );
    final current = _resolveLevel(currentSets);
    if (current == null) {
      return proposal(
        'review',
        'Current controlled targets do not match exactly one published ordinal level; reconcile before progression.',
        currentSets,
        failedSessions,
      );
    }
    if (assessment.unknown) {
      return proposal(
        'unknown',
        'Required confirmed results are missing or skipped.',
        currentSets,
        failedSessions,
      );
    }
    if (assessment.failed) {
      final failures =
          failedSessions + 1; // one exposure, regardless of failed set count
      if (deloadLevelId != null && failures >= deloadAfter) {
        final deloadIndex = _levelIndex(deloadLevelId!);
        if (current > deloadIndex) {
          return proposal(
            'deload',
            'Failed-exposure threshold reached; easier ordinal level proposed.',
            _vectorFor(levels[deloadIndex].targets, currentSets.length),
            0,
          );
        }
        return proposal(
          'blocked',
          'The configured deload level is not easier than the current level; hold all changes.',
          currentSets,
          failures,
        );
      }
      return proposal(
        'failed',
        'One failed exercise exposure; advancement blocked.',
        currentSets,
        failures,
      );
    }
    // Passing the failure gate counts as a successful exposure and resets
    // failures, even when the advancement predicate is not yet met.
    if (!assessment.eligible) {
      return proposal(
        'hold',
        'Failure gate passed but advancement predicate is not met.',
        currentSets,
        0,
      );
    }
    if (effortAssessment != null && effortAssessment.status != 'met') {
      final unknown = effortAssessment.status == 'unknown';
      return proposal(
        unknown ? 'unknown' : 'hold',
        unknown
            ? 'Required advancement effort ratings are missing or use a different RPE scale.'
            : 'Numeric thresholds met but advancement effort conditions are not met.',
        currentSets,
        unknown ? failedSessions : 0,
      );
    }
    if (current == levels.length - 1) {
      return proposal(
        'blocked',
        'Already at the hardest published ordinal level; advancement blocked.',
        currentSets,
        0,
      );
    }
    return proposal(
      'advance',
      'Advancement predicate reached (inclusive); next ordinal level proposed.',
      _vectorFor(levels[current + 1].targets, currentSets.length),
      0,
    );
  }

  void _validateCurrent(Metrics current) {
    for (final metric in controlledMetrics) {
      final value = current[metric];
      if (value == null ||
          value.dimension != levels.first.targets[metric]!.dimension)
        invalid('Missing/incompatible current lever $metric.');
    }
  }

  /// All sets must match the same single level; anything else needs explicit
  /// reconciliation. Level target vectors are distinct, so at most one match
  /// exists per set.
  int? _resolveLevel(List<Metrics> currentSets) {
    int? shared;
    for (final current in currentSets) {
      var matched = -1, matches = 0;
      for (var i = 0; i < levels.length; i++) {
        if (_matches(levels[i].targets, current)) {
          matched = i;
          matches++;
        }
      }
      if (matches != 1 || (shared != null && shared != matched)) return null;
      shared = matched;
    }
    return shared;
  }
}

bool _matches(Metrics level, Metrics current) => level.entries.every(
  (entry) => current[entry.key]!.compareTo(entry.value) == 0,
);

bool _sameVector(Metrics left, Metrics right) =>
    left.entries.every((entry) => right[entry.key] != null) &&
    right.entries.every((entry) => left[entry.key] != null) &&
    left.entries.every(
      (entry) => right[entry.key]!.compareTo(entry.value) == 0,
    );

List<Metrics> _vectorFor(Metrics level, int count) => [
  for (var i = 0; i < count; i++) {...level},
];
