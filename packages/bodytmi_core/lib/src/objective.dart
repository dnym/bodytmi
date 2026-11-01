import 'errors.dart';
import 'quantity.dart';

/// An explicit, unit-aware descriptive predicate. It never changes progression.
final class NumericObjective {
  NumericObjective._(
    this.mode,
    this.lower,
    this.upper,
    this.unit,
    this.upperMeaning,
  );

  factory NumericObjective.fromJson(Object? input) {
    final json = jsonObject(input, 'objective');
    final mode = requiredString(json, 'mode');
    if (!{
      'exact',
      'minimum',
      'maximum',
      'range',
      'observe',
      'maxEffort',
    }.contains(mode))
      invalid('Unknown objective mode.');
    final keys = <String>{'mode'};
    switch (mode) {
      case 'exact':
        keys.add('value');
      case 'minimum':
        keys.add('minimum');
      case 'maximum':
        keys.addAll({'maximum', 'upperMeaning'});
      case 'range':
        keys.addAll({'minimum', 'maximum', 'upperMeaning'});
      case 'observe' || 'maxEffort':
        keys.add('unit');
    }
    checkKeys(json, keys);
    Quantity? lower, upper;
    Unit? unit;
    String? upperMeaning;
    if (mode == 'exact') {
      lower = Quantity.fromJson(json['value']);
      upper = lower;
      unit = lower.unit;
    } else if (mode == 'minimum') {
      lower = Quantity.fromJson(json['minimum']);
      unit = lower.unit;
    } else if (mode == 'maximum') {
      upper = Quantity.fromJson(json['maximum']);
      unit = upper.unit;
    } else if (mode == 'range') {
      lower = Quantity.fromJson(json['minimum']);
      upper = Quantity.fromJson(json['maximum']);
      if (lower.compareTo(upper) > 0)
        invalid('Objective minimum exceeds maximum.');
      unit = lower.unit;
    } else {
      unit = Unit.parse(requiredString(json, 'unit'));
      if (mode == 'maxEffort' && unit != Unit.rep)
        invalid('Max-effort objectives currently require repetitions.');
    }
    if (mode == 'maximum' || mode == 'range') {
      upperMeaning = requiredString(json, 'upperMeaning');
      if (!{
        'desiredCeiling',
        'progressionThreshold',
        'stoppingCue',
      }.contains(upperMeaning))
        invalid(
          'upperMeaning must be desiredCeiling, progressionThreshold or stoppingCue.',
        );
    }
    return NumericObjective._(mode, lower, upper, unit, upperMeaning);
  }

  final String mode;
  final Quantity? lower, upper;
  final Unit unit;
  final String? upperMeaning;

  Map<String, Object?> toJson() => {
    'mode': mode,
    if (mode == 'exact') 'value': lower!.toJson(),
    if (mode == 'minimum' || mode == 'range') 'minimum': lower!.toJson(),
    if (mode == 'maximum' || mode == 'range') 'maximum': upper!.toJson(),
    if (upperMeaning != null) 'upperMeaning': upperMeaning,
    if (mode == 'observe' || mode == 'maxEffort') 'unit': unit.name,
  };

  /// Comparison policy without entered-unit display provenance.
  Map<String, Object?> semanticJson() => {
    'mode': mode,
    if (lower != null)
      'lower': {'value': lower!.value.toString(), 'unit': lower!.unit.name},
    if (upper != null)
      'upper': {'value': upper!.value.toString(), 'unit': upper!.unit.name},
    if (upperMeaning != null) 'upperMeaning': upperMeaning,
    'unit': unit.canonical.name,
  };

  Map<String, Object?> assess(Quantity? actual) {
    if (actual != null && actual.dimension != unit.dimension)
      invalid('Actual quantity has an incompatible objective dimension.');
    final lowerMet = actual == null || lower == null
        ? null
        : actual.compareTo(lower!) >= 0;
    final upperMet = actual == null || upper == null
        ? null
        : actual.compareTo(upper!) <= 0;
    final reached = actual == null || upper == null
        ? null
        : actual.compareTo(upper!) >= 0;
    final relation = actual == null
        ? 'unknown'
        : mode == 'observe' || mode == 'maxEffort'
        ? 'observed'
        : lowerMet == false
        ? 'below'
        : upperMet == false
        ? 'above'
        : 'met';
    return {
      'objective': toJson(),
      'actual': actual?.toJson(),
      'relation': relation,
      'lowerSatisfied': lowerMet,
      'upperSatisfied': upperMet,
      if (upperMeaning != null) 'upperReached': reached,
    };
  }
}

/// Independent, descriptive outcomes; mixed/unknown never become a failure count.
final class ObjectiveAssessment {
  const ObjectiveAssessment();
  Map<String, Object?> evaluate(Object? input, Metrics actuals) {
    final json = jsonObject(input, 'objectives');
    if (json.isEmpty || json.length > 100 || actuals.length > 10000)
      invalid(
        'Assessment requires 1 to 100 objectives and at most 10000 actual metrics.',
      );
    final names = json.keys.toList()..sort();
    final rows = <String, Object?>{};
    final counts = <String, int>{
      for (final relation in ['below', 'above', 'met', 'observed', 'unknown'])
        relation: 0,
    };
    for (final name in names) {
      identifier({'metric': name}, 'metric');
      final result = NumericObjective.fromJson(
        json[name],
      ).assess(actuals[name]);
      rows[name] = result;
      final relation = result['relation']! as String;
      counts[relation] = counts[relation]! + 1;
    }
    final summary = counts['unknown']! > 0
        ? 'unknown'
        : counts['below']! > 0 && counts['above']! > 0
        ? 'mixed'
        : counts['below']! > 0
        ? 'below'
        : counts['above']! > 0
        ? 'above'
        : counts['met']! > 0
        ? 'met'
        : 'observed';
    final ignored = actuals.keys.where((key) => !json.containsKey(key)).toList()
      ..sort();
    return {
      'policy': {
        'id': 'bodytmi-objective-assessment/1',
        'bounds': 'inclusive',
        'purpose': 'descriptive',
      },
      'summary': {'relation': summary, 'counts': counts},
      'metrics': rows,
      'ignoredActualMetrics': ignored,
    };
  }
}

Map<String, NumericObjective> numericObjectivesFromJson(Object? input) {
  final json = jsonObject(input, 'objectives');
  if (json.isEmpty || json.length > 100)
    invalid('Objectives need 1 to 100 metrics.');
  return Map.unmodifiable({
    for (final entry in json.entries)
      identifier({'metric': entry.key}, 'metric'): NumericObjective.fromJson(
        entry.value,
      ),
  });
}

Map<String, Object?> numericObjectivesToJson(
  Map<String, NumericObjective> objectives,
) => {
  for (final key in (objectives.keys.toList()..sort()))
    key: objectives[key]!.toJson(),
};
