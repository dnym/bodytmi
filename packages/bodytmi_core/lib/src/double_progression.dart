import 'errors.dart';
import 'quantity.dart';

/// Vector double progression: change every prescribed set together, not just the
/// last set. This is a proposal; approval/application still belongs to storage.
final class DoubleProgressionProposal {
  DoubleProgressionProposal(
    this.outcome,
    this.reason,
    List<Metrics> nextSets,
    this.failedSessions,
  ) : nextSets = List.unmodifiable([
        for (final set in nextSets) Map<String, Quantity>.unmodifiable(set),
      ]);
  final String outcome;
  final String reason;
  final List<Metrics> nextSets;
  final int failedSessions;
  Map<String, Object?> toJson() => {
    'outcome': outcome,
    'reason': reason,
    'nextSets': [for (final set in nextSets) metricsToJson(set)],
    'nextState': {'failedSessions': failedSessions},
    'requiresAcceptance': true,
  };
}

final class DoubleProgressionRule {
  DoubleProgressionRule._(
    this.objective,
    this.lever,
    this.lower,
    this.upper,
    this.objectiveStep,
    this.leverStep,
    this.maximumLever,
    this.deloadAfter,
    this.deloadFactor,
  );

  factory DoubleProgressionRule.fromJson(Object? input) {
    final json = jsonObject(input, 'double-progression rule');
    checkKeys(json, {
      'objective',
      'lever',
      'lower',
      'upper',
      'objectiveStep',
      'leverStep',
      'maximumLever',
      'deloadAfter',
      'deloadPercent',
    });
    final objective = identifier(json, 'objective');
    final lever = identifier(json, 'lever');
    if (objective == lever)
      invalid('Objective and lever must be distinct metrics.');
    final lower = Quantity.fromJson(json['lower']);
    final upper = Quantity.fromJson(json['upper']);
    final objectiveStep = Quantity.fromJson(json['objectiveStep']);
    final leverStep = Quantity.fromJson(json['leverStep']);
    if (lower.compareTo(upper) > 0 ||
        objectiveStep.dimension != lower.dimension ||
        lower.value.compareTo(Decimal.zero) <= 0 ||
        objectiveStep.value.compareTo(Decimal.zero) <= 0 ||
        leverStep.value.compareTo(Decimal.zero) <= 0 ||
        leverStep.dimension == Dimension.count) {
      invalid('Invalid double-progression range or increments.');
    }
    final maximum = json['maximumLever'] == null
        ? null
        : Quantity.fromJson(json['maximumLever']);
    if (maximum != null && maximum.dimension != leverStep.dimension)
      invalid('Lever bound dimension mismatch.');
    final after = json['deloadAfter'] ?? 3;
    if (after is! int || after < 1) invalid('deloadAfter must be positive.');
    final percentText = json['deloadPercent'] ?? '10';
    if (percentText is! String)
      invalid('deloadPercent must be a decimal string.');
    final percent = Decimal.parse(percentText);
    if (percent.compareTo(Decimal.zero) <= 0 ||
        percent.compareTo(Decimal.parse('100')) >= 0)
      invalid('deloadPercent must be between 0 and 100.');
    return DoubleProgressionRule._(
      objective,
      lever,
      lower,
      upper,
      objectiveStep,
      leverStep,
      maximum,
      after,
      Decimal.parse('1') - percent * Decimal.parse('0.01'),
    );
  }

  final String objective;
  final String lever;
  final Quantity lower;
  final Quantity upper;
  final Quantity objectiveStep;
  final Quantity leverStep;
  final Quantity? maximumLever;
  final int deloadAfter;
  final Decimal deloadFactor;

  DoubleProgressionProposal evaluate({
    required List<Metrics> currentSets,
    required List<Metrics?> results,
    int failedSessions = 0,
  }) {
    if (currentSets.isEmpty ||
        results.length != currentSets.length ||
        failedSessions < 0) {
      invalid(
        'Provide one result (or null) per prescribed set and valid state.',
      );
    }
    for (final set in currentSets) {
      final target = set[objective];
      final difficulty = set[lever];
      if (target == null ||
          difficulty == null ||
          target.dimension != lower.dimension ||
          difficulty.dimension != leverStep.dimension ||
          target.compareTo(lower) < 0 ||
          target.compareTo(upper) > 0) {
        invalid(
          'Current sets need a compatible lever and objective inside the range.',
        );
      }
    }
    DoubleProgressionProposal proposal(
      String outcome,
      String reason,
      List<Metrics> sets,
      int failures,
    ) => DoubleProgressionProposal(outcome, reason, sets, failures);
    var missing = false;
    var changedSetup = false;
    for (var i = 0; i < results.length; i++) {
      final result = results[i];
      if (result == null ||
          result[objective] == null ||
          result[lever] == null) {
        missing = true;
        continue;
      }
      if (result[objective]!.dimension != lower.dimension ||
          result[lever]!.dimension != leverStep.dimension) {
        invalid('Result dimensions do not match the prescription.');
      }
      if (result[lever]!.compareTo(currentSets[i][lever]!) != 0)
        changedSetup = true;
    }
    if (missing)
      return proposal(
        'unknown',
        'Required confirmed work is missing; no penalty.',
        currentSets,
        failedSessions,
      );
    if (changedSetup)
      return proposal(
        'review',
        'Actual lever differs from prescription; reconcile before progression.',
        currentSets,
        failedSessions,
      );

    final failed = [
      for (var i = 0; i < results.length; i++)
        results[i]![objective]!.compareTo(currentSets[i][objective]!) < 0,
    ].any((v) => v);
    if (failed) {
      final failures = failedSessions + 1;
      if (failures >= deloadAfter) {
        final next = [
          for (final set in currentSets)
            <String, Quantity>{
              ...set,
              lever: Quantity(
                (set[lever]!.value * deloadFactor).toString(),
                set[lever]!.unit.name,
              ),
              objective: lower,
            },
        ];
        return proposal(
          'deload',
          'Failed exposure limit reached; reduce lever and reset targets.',
          next,
          0,
        );
      }
      return proposal(
        'failed',
        'One failed exercise exposure; retain all targets.',
        currentSets,
        failures,
      );
    }

    if (results.every((result) => result![objective]!.compareTo(upper) >= 0)) {
      final next = <Metrics>[];
      for (final set in currentSets) {
        final harder = set[lever]!.add(leverStep);
        if (maximumLever != null && harder.compareTo(maximumLever!) > 0) {
          return proposal(
            'blocked',
            'Lever bound blocks the entire transition.',
            currentSets,
            0,
          );
        }
        next.add({...set, lever: harder, objective: lower});
      }
      return proposal(
        'increaseLever',
        'Every set reached the inclusive upper bound; reset objectives.',
        next,
        0,
      );
    }
    final next = [
      for (final set in currentSets)
        <String, Quantity>{
          ...set,
          objective: set[objective]!.add(objectiveStep).compareTo(upper) > 0
              ? upper
              : set[objective]!.add(objectiveStep),
        },
    ];
    return proposal(
      'increaseObjective',
      'All prescribed targets met; increment every set objective.',
      next,
      0,
    );
  }
}
