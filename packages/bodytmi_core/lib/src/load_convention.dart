import 'equipment.dart';
import 'errors.dart';
import 'quantity.dart';

/// How an entered training mass or repetition count must be interpreted:
/// dumbbell mass per dumbbell, plates per loading side, a barbell including
/// the bar, added load beyond declared components, or a selectorized nominal
/// setting. Conventions are declared intent; they never rewrite stored
/// entered values and an entry convention cannot make incompatible equipment
/// capabilities valid: a selectorized stack has no imaginary 20 kg bar.
final class LoadConvention {
  LoadConvention._(
    this.massBasis,
    this.implements,
    this.sides,
    this.repCounting,
    this.notes,
  );

  factory LoadConvention.fromJson(Object? input) {
    final j = jsonObject(input, 'load convention');
    checkKeys(j, {'massBasis', 'implements', 'sides', 'repCounting', 'notes'});
    final basis = j['massBasis'];
    if (basis is! String || !_massBases.contains(basis)) {
      invalid(
        'A load convention needs a per-implement, per-side, assembly-total, '
        'added-load or nominal-setting mass basis.',
      );
    }
    final implements = j['implements'] ?? 1;
    if (implements is! int || implements < 1 || implements > 64) {
      invalid('A load convention declares between 1 and 64 implements.');
    }
    if (implements > 1 && basis == 'nominal-setting') {
      invalid('A nominal-setting basis cannot declare multiple implements.');
    }
    final sides = j['sides'] ?? 'both';
    if (sides is! String || !_sides.contains(sides)) {
      invalid('A load convention declares both, left or right working sides.');
    }
    final repCounting = j['repCounting'] ?? 'per-side';
    if (repCounting is! String || !_repCounting.contains(repCounting)) {
      invalid('A load convention counts repetitions per-side or combined.');
    }
    if (repCounting == 'combined' && sides != 'both') {
      invalid('Combined repetition counting requires both working sides.');
    }
    final notes = j['notes'];
    if (notes != null &&
        (notes is! String || notes.trim().isEmpty || notes.length > 4000)) {
      invalid(
        'Load convention notes must be a nonempty string of at most '
        '4000 characters.',
      );
    }
    return LoadConvention._(
      basis,
      implements,
      sides,
      repCounting,
      notes as String?,
    );
  }

  static const _massBases = {
    'per-implement',
    'per-side',
    'assembly-total',
    'added-load',
    'nominal-setting',
  };
  static const _sides = {'both', 'left', 'right'};
  static const _repCounting = {'per-side', 'combined'};

  final String massBasis;
  final int implements;
  final String sides;
  final String repCounting;
  final String? notes;

  @override
  bool operator ==(Object other) =>
      other is LoadConvention &&
      other.massBasis == massBasis &&
      other.implements == implements &&
      other.sides == sides &&
      other.repCounting == repCounting &&
      other.notes == notes;

  @override
  int get hashCode => Object.hash(massBasis, implements, sides, repCounting);

  Map<String, Object?> toJson() => {
    'massBasis': massBasis,
    if (implements != 1) 'implements': implements,
    if (sides != 'both') 'sides': sides,
    if (repCounting != 'per-side') 'repCounting': repCounting,
    if (notes != null) 'notes': notes,
  };
}

/// The single authoritative capability rule shared by authoring, stored
/// resolution and archive validation. Mass bases that depend on component
/// masses require an explicit declared loading configuration, and a per-side
/// basis requires a symmetric two-sided channel so one entered value cannot
/// silently misrepresent an asymmetric or single-sided stack. Returns the
/// block reason, or null when the convention is supported.
String? loadConventionBlock(LoadConvention convention, LoadingSpec? loading) {
  switch (convention.massBasis) {
    case 'per-side':
      if (loading == null) {
        return 'A per-side load basis requires a declared loading configuration.';
      }
      if (loading.channel.sides != 2 ||
          loading.channel.symmetry != 'required') {
        return 'A per-side load basis requires a symmetric two-sided loading channel.';
      }
    case 'added-load':
      if (loading == null) {
        return 'An added-load basis requires a declared loading configuration.';
      }
  }
  return null;
}

void requireLoadConventionCapability(
  LoadConvention convention,
  LoadingSpec? loading,
) {
  final block = loadConventionBlock(convention, loading);
  if (block != null) invalid(block);
}

/// Exact descriptive interpretation of one entered mass and optional entered
/// repetitions under a convention. Known outputs are exact canonical decimal
/// quantities; anything requiring an assumed bar, collar or invented
/// component mass stays explicitly unknown with its reason. This calculator
/// never rewrites stored values and computes no workload totals.
final class LoadInterpretation {
  LoadInterpretation._();

  static const policy = 'bodytmi-load-interpretation/1';

  static Map<String, Object?> interpret(
    LoadConvention convention,
    Quantity mass, {
    Quantity? repetitions,
    LoadingSpec? loading,
  }) {
    if (mass.dimension != Dimension.mass) {
      invalid('The interpreted mass must have mass dimension.');
    }
    if (repetitions != null && repetitions.dimension != Dimension.count) {
      invalid('The interpreted repetitions must have count dimension.');
    }
    requireLoadConventionCapability(convention, loading);
    final tare = loading?.tareMass;
    Map<String, Object?> known(Quantity q) => {
      'status': 'known',
      if (q.dimension == Dimension.count) 'repetitions': q.toJson(),
      if (q.dimension == Dimension.mass) 'mass': q.toJson(),
    };
    Map<String, Object?> unknown(String reason) => {
      'status': 'unknown',
      'reason': reason,
    };
    Quantity times(Quantity q, int n) =>
        Quantity((q.value * Decimal.parse('$n')).toString(), q.unit.name);
    final outputs = <String, Object?>{};
    switch (convention.massBasis) {
      case 'per-implement':
        outputs['perImplementMass'] = known(mass);
        outputs['assemblyMass'] = known(times(mass, convention.implements));
        outputs['addedMass'] = tare == null
            ? unknown(
                'No declared loading configuration; component mass is unknown.',
              )
            : _minus(
                mass.value * Decimal.parse('${convention.implements}'),
                tare,
                known,
                unknown,
              );
      case 'per-side':
        final channelSides = loading!.channel.sides;
        outputs['addedMass'] = known(times(mass, channelSides));
        final assembly = Quantity(
          (tare! + mass.value * Decimal.parse('$channelSides')).toString(),
          'kg',
        );
        outputs['assemblyMass'] = known(assembly);
        outputs['perImplementMass'] = _exactDivide(
          assembly,
          convention.implements,
          known,
          unknown,
        );
      case 'assembly-total':
        outputs['assemblyMass'] = known(mass);
        outputs['perImplementMass'] = _exactDivide(
          mass,
          convention.implements,
          known,
          unknown,
        );
        outputs['addedMass'] = tare == null
            ? unknown(
                'No declared loading configuration; component mass is unknown.',
              )
            : _minus(mass.value, tare, known, unknown);
      case 'added-load':
        outputs['addedMass'] = known(mass);
        final assembly = Quantity((tare! + mass.value).toString(), 'kg');
        outputs['assemblyMass'] = known(assembly);
        outputs['perImplementMass'] = _exactDivide(
          assembly,
          convention.implements,
          known,
          unknown,
        );
      default:
        outputs['nominalSetting'] = known(mass);
        outputs['perImplementMass'] = unknown(
          'A nominal setting has no physical mass interpretation.',
        );
        outputs['assemblyMass'] = unknown(
          'A nominal setting has no physical mass interpretation.',
        );
        outputs['addedMass'] = unknown(
          'A nominal setting has no physical mass interpretation.',
        );
    }
    return {
      'policy': policy,
      'convention': convention.toJson(),
      'enteredMass': mass.toJson(),
      'interpretation': outputs,
      'repetitions': repetitions == null
          ? null
          : _repetitions(convention, repetitions, known, unknown),
      'seriesContext': {
        'massBasis': convention.massBasis,
        'implements': convention.implements,
        'sides': convention.sides,
        'repCounting': convention.repCounting,
      },
    };
  }

  static Map<String, Object?> _repetitions(
    LoadConvention convention,
    Quantity entered,
    Map<String, Object?> Function(Quantity) known,
    Map<String, Object?> Function(String) unknown,
  ) {
    final workingSides = convention.sides == 'both' ? 2 : 1;
    if (convention.repCounting == 'per-side') {
      return {
        'entered': entered.toJson(),
        'workingSides': workingSides,
        'repetitionsPerSide': known(entered),
        'totalLimbRepetitions': known(
          Quantity(
            (entered.value * Decimal.parse('$workingSides')).toString(),
            entered.unit.name,
          ),
        ),
      };
    }
    return {
      'entered': entered.toJson(),
      'workingSides': workingSides,
      'repetitionsPerSide':
          entered.value.coefficient % BigInt.two == BigInt.zero
          ? _exactDivide(entered, 2, known, unknown)
          : unknown(
              'Combined repetitions do not divide exactly across two '
              'sides.',
            ),
      'totalLimbRepetitions': known(entered),
    };
  }

  static Map<String, Object?> _minus(
    Decimal minuend,
    Decimal subtrahend,
    Map<String, Object?> Function(Quantity) known,
    Map<String, Object?> Function(String) unknown,
  ) {
    final difference = minuend - subtrahend;
    if (difference.compareTo(Decimal.zero) < 0) {
      return unknown(
        'The entered mass is below the declared component mass; the '
        'interpretation is inconsistent.',
      );
    }
    return known(Quantity(difference.toString(), 'kg'));
  }

  static Map<String, Object?> _exactDivide(
    Quantity quantity,
    int divisor,
    Map<String, Object?> Function(Quantity) known,
    Map<String, Object?> Function(String) unknown,
  ) {
    final coefficient = quantity.value.coefficient;
    final divisorValue = BigInt.from(divisor);
    if (coefficient % divisorValue != BigInt.zero) {
      return unknown(
        'The mass does not divide exactly across the declared implements.',
      );
    }
    final quotient = coefficient ~/ divisorValue;
    final scale = quantity.value.scale;
    if (scale == 0)
      return known(Quantity(quotient.toString(), quantity.unit.name));
    final power = BigInt.from(10).pow(scale);
    final whole = quotient ~/ power;
    final fraction = (quotient % power)
        .toString()
        .padLeft(scale, '0')
        .replaceFirst(RegExp(r'0+$'), '');
    return known(
      Quantity(
        fraction.isEmpty ? '$whole' : '$whole.$fraction',
        quantity.unit.name,
      ),
    );
  }
}
