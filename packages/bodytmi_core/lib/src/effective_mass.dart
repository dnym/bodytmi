import 'body_mass_input.dart';
import 'errors.dart';
import 'quantity.dart';

/// A declared mass component, not an inferred implement count or machine ratio.
final class MassComponent {
  MassComponent._(this.metric, this.mass, this.multiplier);
  factory MassComponent.fromJson(Object? input) {
    final j = jsonObject(input, 'mass component');
    checkKeys(j, {'metric', 'mass', 'multiplier'});
    if (j.containsKey('mass')) {
      if (j.length != 1) invalid('Constant mass component takes only mass.');
      final mass = Quantity.fromJson(j['mass']);
      if (mass.dimension != Dimension.mass)
        invalid('Mass component requires a mass quantity.');
      return MassComponent._(null, mass, Decimal.parse('1'));
    }
    final metric = identifier(j, 'metric');
    final multiplier = Decimal.parse(requiredString(j, 'multiplier'));
    if (multiplier.compareTo(Decimal.zero) < 0)
      invalid('Mass multiplier cannot be negative.');
    return MassComponent._(metric, null, multiplier);
  }
  final String? metric;
  final Quantity? mass;
  final Decimal multiplier;
  Map<String, Object?> toJson() => mass != null
      ? {'mass': mass!.toJson()}
      : {'metric': metric, 'multiplier': multiplier.toString()};
  Quantity? resolve(Metrics metrics) => mass ?? metrics[metric];
  Map<String, Object?> input(Metrics metrics) => {
    'source': metric == null ? 'constant' : 'metric',
    if (metric != null) 'metric': metric,
    'mass': resolve(metrics)?.toJson(),
    'multiplier': multiplier.toString(),
  };
}

/// Optional model: fraction * captured body mass + added mass - assistance.
/// Neither a machine's setting nor a body's supported fraction is assumed.
final class EffectiveMassModel {
  EffectiveMassModel._(
    this.id,
    this.version,
    this.bodyMassFraction,
    this.addedMass,
    this.assistance,
  );
  factory EffectiveMassModel.fromJson(Object? input) {
    final j = jsonObject(input, 'effective-mass model');
    checkKeys(j, {
      'id',
      'version',
      'bodyMassFraction',
      'addedMass',
      'assistance',
    });
    final version = j['version'];
    if (version is! int || version < 1)
      invalid('Effective-mass model version must be positive.');
    final fraction = Decimal.parse(requiredString(j, 'bodyMassFraction'));
    if (fraction.compareTo(Decimal.zero) < 0 ||
        fraction.compareTo(Decimal.parse('1')) > 0)
      invalid('Body-mass fraction must be between zero and one.');
    return EffectiveMassModel._(
      identifier(j, 'id'),
      version,
      fraction,
      MassComponent.fromJson(j['addedMass']),
      MassComponent.fromJson(j['assistance']),
    );
  }
  static const policy = 'effective-mass/1';
  final String id;
  final int version;
  final Decimal bodyMassFraction;
  final MassComponent addedMass, assistance;
  bool get usesBodyMass => bodyMassFraction.compareTo(Decimal.zero) > 0;
  Map<String, Object?> toJson() => {
    'id': id,
    'version': version,
    'bodyMassFraction': bodyMassFraction.toString(),
    'addedMass': addedMass.toJson(),
    'assistance': assistance.toJson(),
  };

  void validateBindings(Metrics targets, {required bool hasBodyMass}) {
    if (usesBodyMass && !hasBodyMass)
      invalid('Effective-mass model requires an explicit bodyMass selection.');
    for (final component in [addedMass, assistance]) {
      if (component.metric != null &&
          targets[component.metric]?.dimension != Dimension.mass)
        invalid('Effective-mass metric must name a configured mass target.');
    }
  }

  /// All arithmetic is decimal; round the final derived kg once, to nine digits,
  /// half away from zero. Unconfirmed actuals never become estimated actuals.
  Map<String, Object?> evaluate({
    required Metrics metrics,
    BodyMassInputSnapshot? bodyMass,
    bool confirmed = true,
  }) {
    final body = usesBodyMass ? bodyMass?.resolution.mass : null;
    final added = addedMass.resolve(metrics);
    final removed = assistance.resolve(metrics);
    final inputs = <String, Object?>{
      if (usesBodyMass)
        'bodyMass': {
          'mass': body?.toJson(),
          'fraction': bodyMassFraction.toString(),
          'sourceFingerprint': bodyMass?.resolution.sourceFingerprint,
          'sourceObservedAt': bodyMass?.resolution.sourceObservedAt
              ?.toIso8601String(),
        },
      'addedMass': addedMass.input(metrics),
      'assistance': assistance.input(metrics),
    };
    final missing = <String>[
      if (!confirmed) 'confirmation',
      if (usesBodyMass && body == null) 'bodyMass',
      if (added == null) 'addedMass',
      if (removed == null) 'assistance',
    ];
    if ((added != null && added.dimension != Dimension.mass) ||
        (removed != null && removed.dimension != Dimension.mass))
      invalid('Effective-mass input has a non-mass dimension.');
    var reason = !confirmed
        ? 'unconfirmed'
        : missing.isNotEmpty
        ? 'missing_inputs'
        : null;
    Quantity? result;
    if (reason == null) {
      final total =
          (body?.value ?? Decimal.zero) * bodyMassFraction +
          added!.value * addedMass.multiplier -
          removed!.value * assistance.multiplier;
      if (total.compareTo(Decimal.zero) < 0) {
        reason = 'negative_estimate';
      } else {
        final rounded = total.dividedByInt(1).toString();
        if (rounded.length > 80) {
          reason = 'out_of_range';
        } else {
          result = Quantity(rounded, 'kg');
        }
      }
    }
    return {
      'policy': policy,
      'model': toJson(),
      'status': result == null ? 'unavailable' : 'available',
      'mass': result?.toJson(),
      if (reason != null) 'reason': reason,
      'missingInputs': missing,
      'inputs': inputs,
      'fractionDigitsKg': 9,
      'rounding': 'half-away-from-zero',
      'warnings': [
        if (usesBodyMass &&
            bodyMass?.resolution.stale == true &&
            bodyMass!.resolution.warningEnabled)
          'stale_body_mass',
      ],
    };
  }
}
