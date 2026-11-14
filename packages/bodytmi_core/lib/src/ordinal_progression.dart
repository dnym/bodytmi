import 'categorical.dart';
import 'errors.dart';
import 'effort_condition.dart';
import 'quantity.dart';
import 'result_aggregation.dart';
import 'set_observations.dart';

/// One authored step of an ordinal lever: a complete explicit working target
/// vector. Array order is the declared easier-to-harder progression order.
/// Difficulty is never inferred from the numbers inside a level.
final class OrdinalLevel {
  OrdinalLevel._(this.id, this.targets, this.settings);
  factory OrdinalLevel.fromJson(Object? input) {
    final json = jsonObject(input, 'ordinal level');
    checkKeys(json, {'id', 'targets', 'settings'});
    final targets = json.containsKey('targets')
        ? metricsFromJson(json['targets'])
        : <String, Quantity>{};
    final settings = json.containsKey('settings')
        ? categoricalSettingsFromJson(json['settings'], 'level settings')
        : const <String, String>{};
    if (targets.isEmpty && settings.isEmpty)
      invalid('Ordinal levels need at least one target or setting.');
    if (json.containsKey('targets') && targets.isEmpty)
      invalid('Ordinal level targets cannot be empty when present.');
    return OrdinalLevel._(
      identifier(json, 'id'),
      Map<String, Quantity>.unmodifiable(targets),
      settings,
    );
  }
  final String id;
  final Metrics targets;

  /// Categorical lever values this level prescribes (e.g. grip: neutral).
  final Map<String, String> settings;
  Map<String, Object?> toJson() => {
    'id': id,
    if (targets.isNotEmpty) 'targets': metricsToJson(targets),
    if (settings.isNotEmpty) 'settings': settings,
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
    List<String> candidates = const [],
    this.nextLevel,
    this.withLevel = false,
  }) : candidates = List.unmodifiable(candidates),
       nextSets = List.unmodifiable([
         for (final set in nextSets) Map<String, Quantity>.unmodifiable(set),
       ]);
  final String outcome;
  final String reason;
  final List<Metrics> nextSets;
  final int failedSessions;
  final ThresholdAssessment? assessment;
  final EffortAssessment? effortAssessment;

  /// Declared successor levels when more than one is legal ('choice'). No
  /// default branch is chosen: acceptance must name one explicitly.
  final List<String> candidates;

  /// The level advance/deload moves to; null when targets hold.
  final String? nextLevel;

  /// Whether the rule sets categorical levers (serializes nextLevel).
  final bool withLevel;
  Map<String, Object?> toJson() => {
    'outcome': outcome,
    if (candidates.isNotEmpty) 'candidates': candidates,
    'reason': reason,
    'nextSets': [for (final set in nextSets) metricsToJson(set)],
    if (withLevel && nextLevel != null) 'nextLevel': nextLevel,
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
    this.successors,
  ) : levels = List.unmodifiable(levels),
      controlledMetrics = Set.unmodifiable(levels.first.targets.keys),
      controlledSettings = Set.unmodifiable(levels.first.settings.keys);

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
      'successors',
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
      final levers = level.settings.keys.toSet(),
          controlledLevers = levels.first.settings.keys.toSet();
      if (levers.difference(controlledLevers).isNotEmpty ||
          controlledLevers.difference(levers).isNotEmpty)
        invalid('Every ordinal level must set the same categorical levers.');
    }
    for (var i = 0; i < levels.length; i++) {
      for (var j = i + 1; j < levels.length; j++) {
        if (_sameVector(levels[i].targets, levels[j].targets) &&
            _sameSettings(levels[i].settings, levels[j].settings))
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
    final ids = {for (final level in levels) level.id};
    Map<String, List<String>>? successors;
    if (json.containsKey('successors')) {
      final graph = jsonObject(json['successors'], 'successors');
      if (graph.isEmpty) invalid('successors must declare at least one edge.');
      successors = {};
      var edges = 0;
      for (final entry in graph.entries) {
        if (!ids.contains(entry.key))
          invalid('successors names an unknown level ${entry.key}.');
        final targets = <String>[];
        for (final item in jsonList(graph, entry.key)) {
          if (item is! String || !ids.contains(item))
            invalid('successors of ${entry.key} must name published levels.');
          if (item == entry.key) invalid('A level cannot succeed itself.');
          if (targets.contains(item))
            invalid('Duplicate successor $item of ${entry.key}.');
          targets.add(item);
        }
        if (targets.isEmpty || targets.length > 100)
          invalid('A level declares 1–100 successors when listed.');
        edges += targets.length;
        successors[entry.key] = List.unmodifiable(targets);
      }
      if (edges > 10000) invalid('successors exceed 10000 edges.');
      // Harder-only transitions: the declared graph must be acyclic.
      final state = <String, int>{};
      void visit(String id) {
        if (state[id] == 2) return;
        if (state[id] == 1) invalid('successors must not contain a cycle.');
        state[id] = 1;
        for (final next in successors![id] ?? const <String>[]) visit(next);
        state[id] = 2;
      }

      for (final id in successors.keys) visit(id);
    }
    String? deloadLevelId;
    if (json.containsKey('deloadLevel')) {
      deloadLevelId = identifier(json, 'deloadLevel');
      final index = levels.indexWhere((level) => level.id == deloadLevelId);
      if (index < 0) invalid('deloadLevel must name a published level.');
      if (successors == null && index == levels.length - 1)
        invalid('deloadLevel must be easier than the hardest level.');
      if (successors != null && !successors.containsKey(deloadLevelId))
        invalid('A branched deloadLevel must have declared successors.');
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
      successors == null ? null : Map.unmodifiable(successors),
    );
  }

  final String metric;
  final String performanceDirection;
  final Quantity failureLimit, advancementLimit;
  final List<OrdinalLevel> levels;
  final Set<String> controlledMetrics;

  /// Categorical levers every level sets; empty for numeric-only ladders.
  final Set<String> controlledSettings;
  final ResultAggregation aggregation, failureAggregation;
  final AdvancementEffort? advancementEffort;
  final int deloadAfter;
  final String? deloadLevelId;

  /// Optional declared successor graph. When present, only its edges
  /// authorize advancement; array order no longer implies difficulty and
  /// sibling branches stay incomparable.
  final Map<String, List<String>>? successors;

  /// Whether [to] is reachable from [from] by declared successor edges.
  bool reaches(String from, String to) {
    final graph = successors;
    if (graph == null) return _levelIndex(from) < _levelIndex(to);
    final seen = <String>{};
    final pending = [...?graph[from]];
    while (pending.isNotEmpty) {
      final next = pending.removeLast();
      if (next == to) return true;
      if (seen.add(next)) pending.addAll(graph[next] ?? const []);
    }
    return false;
  }

  /// Declared harder levels legal from [index].
  List<String> successorsOf(int index) => successors == null
      ? [if (index + 1 < levels.length) levels[index + 1].id]
      : [...?successors![levels[index].id]];

  Metrics levelTargets(String id) {
    final index = _levelIndex(id);
    if (index < 0) invalid('Unknown ordinal level $id.');
    return levels[index].targets;
  }

  Map<String, String> levelSettings(String id) {
    final index = _levelIndex(id);
    if (index < 0) invalid('Unknown ordinal level $id.');
    return levels[index].settings;
  }

  int _levelIndex(String id) => levels.indexWhere((level) => level.id == id);

  /// Classify the whole exposure once, then move (or hold) every working set
  /// together. Ordinal levels never partially advance.
  OrdinalProposal evaluate({
    required List<Metrics> currentSets,
    required List<Metrics?> results,
    List<SetObservations?>? observations,
    int failedSessions = 0,
    List<Map<String, String>>? currentSettings,
  }) {
    if (currentSets.isEmpty || currentSets.length > 10000)
      invalid('Ordinal progression needs 1 to 10000 target sets.');
    if (controlledSettings.isNotEmpty &&
        currentSettings?.length != currentSets.length)
      invalid('Categorical ordinal levels need the current set settings.');
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
      int failures, {
      List<String> candidates = const [],
      String? nextLevel,
    }) => OrdinalProposal(
      outcome,
      reason,
      nextSets,
      failures,
      assessment: assessment,
      effortAssessment: effortAssessment,
      candidates: candidates,
      nextLevel: nextLevel,
      withLevel: controlledSettings.isNotEmpty,
    );
    final current = _resolveLevel(currentSets, currentSettings);
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
        if (reaches(deloadLevelId!, levels[current].id)) {
          return proposal(
            'deload',
            'Failed-exposure threshold reached; easier ordinal level proposed.',
            _vectorFor(levels[deloadIndex].targets, currentSets.length),
            0,
            nextLevel: deloadLevelId,
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
    final next = successorsOf(current);
    if (next.isEmpty) {
      return proposal(
        'blocked',
        successors == null
            ? 'Already at the hardest published ordinal level; advancement blocked.'
            : 'The current level declares no successor; advancement blocked.',
        currentSets,
        0,
      );
    }
    if (next.length > 1) {
      // Incomparable branches: hold until one declared successor is chosen.
      return proposal(
        'choice',
        'Advancement reached; select one declared successor level.',
        currentSets,
        0,
        candidates: next,
      );
    }
    return proposal(
      'advance',
      'Advancement predicate reached (inclusive); next ordinal level proposed.',
      _vectorFor(levelTargets(next.single), currentSets.length),
      0,
      nextLevel: next.single,
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
  int? _resolveLevel(
    List<Metrics> currentSets,
    List<Map<String, String>>? currentSettings,
  ) {
    int? shared;
    for (var s = 0; s < currentSets.length; s++) {
      final current = currentSets[s];
      var matched = -1, matches = 0;
      for (var i = 0; i < levels.length; i++) {
        if (_matches(levels[i].targets, current) &&
            levels[i].settings.entries.every(
              (e) => currentSettings![s][e.key] == e.value,
            )) {
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

bool _sameSettings(Map<String, String> a, Map<String, String> b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

List<Metrics> _vectorFor(Metrics level, int count) => [
  for (var i = 0; i < count; i++) {...level},
];
