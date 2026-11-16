import 'dart:math' as math;

import 'errors.dart';
import 'quantity.dart';

/// One named band of a reference policy: values below [below] (exclusive),
/// or every remaining value when null, carry [label].
typedef ReferenceBand = ({double? below, String label});

/// A named reference category policy: its source, the population it applies
/// to, and its boundaries (optionally per sex). It describes; it never
/// diagnoses.
final class ReferencePolicy {
  const ReferencePolicy({
    required this.id,
    required this.source,
    required this.population,
    this.bands = const [],
    this.male = const [],
    this.female = const [],
  });
  final String id, source, population;
  final List<ReferenceBand> bands, male, female;

  String? label(double value, String? sex) {
    final list = bands.isNotEmpty
        ? bands
        : sex == 'male'
        ? male
        : sex == 'female'
        ? female
        : const <ReferenceBand>[];
    for (final band in list) {
      if (band.below == null || value < band.below!) return band.label;
    }
    return null;
  }

  bool get bySex => bands.isEmpty;

  Map<String, Object?> toJson() {
    List<Object?> encode(List<ReferenceBand> list) => [
      for (final b in list) {'below': ?b.below, 'label': b.label},
    ];
    return {
      'id': id,
      'source': source,
      'population': population,
      if (bands.isNotEmpty) 'bands': encode(bands),
      if (male.isNotEmpty) 'male': encode(male),
      if (female.isNotEmpty) 'female': encode(female),
    };
  }
}

/// One input a calculation needs: a quantity of a dimension, or a profile
/// fact (`sex`: male or female; `age`: whole years).
typedef CalculationInput = ({
  String name,
  String kind,
  Dimension? dimension,
  String description,
});

/// A named, versioned formula (`bodytmi-calc/<name>/<version>`). Its
/// result lists every input used; a missing input makes it unavailable and
/// names what is missing. A changed formula is a new id.
final class CalculationDefinition {
  const CalculationDefinition({
    required this.id,
    required this.name,
    required this.formula,
    required this.source,
    required this.inputs,
    required this.unit,
    required this.compute,
    this.reference,
    this.requiresSex = false,
  });
  final String id, name, formula, source, unit;
  final List<CalculationInput> inputs;
  final ReferencePolicy? reference;

  /// Inputs needed for [sex] may differ (Navy, Jackson–Pollock).
  final bool requiresSex;
  final double Function(Map<String, Object> values) compute;

  /// The inputs this formula needs for [sex] (all, when sex is not needed).
  List<CalculationInput> inputsFor(String? sex) => [
    for (final i in inputs)
      if (!i.name.contains(':') || (sex != null && i.name.startsWith('$sex:')))
        i,
  ];

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'formula': formula,
    'source': source,
    'unit': unit,
    'inputs': [
      for (final i in inputs)
        {
          'name': i.name,
          'kind': i.kind,
          if (i.dimension != null) 'dimension': i.dimension!.name,
          'description': i.description,
        },
    ],
    if (reference != null) 'reference': reference!.toJson(),
  };

  /// Evaluates with [supplied] values: quantities as [Quantity], `sex` as
  /// a string, `age` as an int. [provenance] (per input name) is echoed
  /// unchanged so callers can show each input's age and source.
  Map<String, Object?> evaluate(
    Map<String, Object?> supplied, {
    Map<String, Object?> provenance = const {},
  }) {
    final sex = supplied['sex'] as String?;
    if (sex != null && sex != 'male' && sex != 'female')
      invalid('sex is male or female.');
    final needed = [
      if (requiresSex)
        (name: 'sex', kind: 'fact', dimension: null, description: ''),
      ...inputsFor(sex),
    ];
    final values = <String, Object>{};
    final missing = <String>[];
    for (final input in needed) {
      final value = supplied[input.name] ?? supplied[_plain(input.name)];
      if (value == null) {
        missing.add(_plain(input.name));
        continue;
      }
      if (input.kind == 'quantity') {
        if (value is! Quantity || value.dimension != input.dimension)
          invalid(
            '${_plain(input.name)} needs a ${input.dimension!.name} '
            'quantity.',
          );
      } else if (input.name == 'age' && (value is! int || value < 0)) {
        invalid('age is whole years.');
      }
      values[_plain(input.name)] = value;
    }
    final base = <String, Object?>{
      'calculation': id,
      'formula': formula,
      'source': source,
      'inputs': {
        for (final e in values.entries)
          e.key: {
            'value': e.value is Quantity
                ? {
                    'value': (e.value as Quantity).enteredValue,
                    'unit': (e.value as Quantity).enteredUnit.name,
                  }
                : e.value,
            if (provenance[e.key] != null) 'provenance': provenance[e.key],
          },
      },
    };
    if (missing.isNotEmpty)
      return {
        ...base,
        'status': 'unavailable',
        'missing': missing,
        'reason': 'Missing ${missing.join(', ')}.',
      };
    final result = compute(values);
    if (result.isNaN || result.isInfinite || result < 0)
      return {
        ...base,
        'status': 'unavailable',
        'reason': 'The inputs are outside the formula’s range.',
      };
    final label = reference?.label(result, sex);
    return {
      ...base,
      'status': 'resolved',
      'value': {'value': round9(result), 'unit': unit},
      if (reference != null)
        'category': {
          'policy': reference!.id,
          'source': reference!.source,
          'population': reference!.population,
          'label': label,
        },
    };
  }
}

String _plain(String name) =>
    name.contains(':') ? name.substring(name.indexOf(':') + 1) : name;

/// Rounds once to nine fractional digits, half away from zero.
String round9(double value) {
  final scaled = (value.abs() * 1e9).round();
  final text = Decimal.parse(
    BigInt.from(scaled).toString(),
  ).dividedByInt(1000000000).toString();
  return value < 0 && scaled != 0 ? '-$text' : text;
}

double _d(Object value) => double.parse((value as Quantity).value.toString());
double _metres(Object v) => _d(v);
double _cm(Object v) => _d(v) * 100;
double _mm(Object v) => _d(v) * 1000;

CalculationInput _q(String name, Dimension d, String description) =>
    (name: name, kind: 'quantity', dimension: d, description: description);
const CalculationInput _age = (
  name: 'age',
  kind: 'fact',
  dimension: null,
  description: 'Age in whole years at the measurement',
);

double _siri(double density) => 4.95 / density - 4.50;

/// The calculations that ship with the app.
final List<CalculationDefinition> calculations = List.unmodifiable([
  CalculationDefinition(
    id: 'bodytmi-calc/bmi/1',
    name: 'Body mass index',
    formula: 'mass (kg) / height (m)²',
    source: 'Quetelet index; WHO classification for adults',
    unit: 'kg/m2',
    inputs: [
      _q('mass', Dimension.mass, 'Body mass'),
      _q('height', Dimension.distance, 'Height'),
    ],
    compute: (v) => _d(v['mass']!) / math.pow(_metres(v['height']!), 2),
    reference: const ReferencePolicy(
      id: 'who-bmi-adult/1',
      source:
          'WHO (2000) Obesity: preventing and managing the global epidemic, '
          'Technical Report Series 894',
      population: 'Adults aged 18 and over',
      bands: [
        (below: 18.5, label: 'underweight'),
        (below: 25, label: 'normal'),
        (below: 30, label: 'overweight'),
        (below: 35, label: 'obese class I'),
        (below: 40, label: 'obese class II'),
        (below: null, label: 'obese class III'),
      ],
    ),
  ),
  CalculationDefinition(
    id: 'bodytmi-calc/waist-to-height/1',
    name: 'Waist-to-height ratio',
    formula: 'waist / height',
    source: 'Ashwell & Gibson (2016); NICE CG189 (2022 update) bands',
    unit: 'ratio',
    inputs: [
      _q('waist', Dimension.distance, 'Waist circumference'),
      _q('height', Dimension.distance, 'Height'),
    ],
    compute: (v) => _d(v['waist']!) / _d(v['height']!),
    reference: const ReferencePolicy(
      id: 'nice-waist-to-height/1',
      source:
          'NICE CG189 Obesity: identification, assessment and management, '
          '2022 update',
      population: 'Adults with a BMI under 35',
      bands: [
        (below: 0.4, label: 'below the healthy range'),
        (below: 0.5, label: 'healthy'),
        (below: 0.6, label: 'increased health risk'),
        (below: null, label: 'high health risk'),
      ],
    ),
  ),
  CalculationDefinition(
    id: 'bodytmi-calc/waist-to-hip/1',
    name: 'Waist-to-hip ratio',
    formula: 'waist / hip',
    source: 'WHO (2008) Waist circumference and waist–hip ratio',
    unit: 'ratio',
    requiresSex: true,
    inputs: [
      _q('waist', Dimension.distance, 'Waist circumference'),
      _q('hip', Dimension.distance, 'Hip circumference'),
    ],
    compute: (v) => _d(v['waist']!) / _d(v['hip']!),
    reference: const ReferencePolicy(
      id: 'who-waist-to-hip/1',
      source:
          'WHO (2008) Waist circumference and waist–hip ratio: report of a '
          'WHO expert consultation',
      population: 'Adults',
      male: [
        (below: 0.90, label: 'not substantially increased risk'),
        (below: null, label: 'substantially increased risk'),
      ],
      female: [
        (below: 0.85, label: 'not substantially increased risk'),
        (below: null, label: 'substantially increased risk'),
      ],
    ),
  ),
  CalculationDefinition(
    id: 'bodytmi-calc/waist-risk/1',
    name: 'Waist circumference risk',
    formula: 'waist (cm)',
    source: 'WHO (2008) Waist circumference and waist–hip ratio',
    unit: 'cm',
    requiresSex: true,
    inputs: [_q('waist', Dimension.distance, 'Waist circumference')],
    compute: (v) => _cm(v['waist']!),
    reference: const ReferencePolicy(
      id: 'who-waist-circumference/1',
      source:
          'WHO (2008) Waist circumference and waist–hip ratio: report of a '
          'WHO expert consultation (European cut-offs)',
      population: 'Adults of European descent',
      male: [
        (below: 94, label: 'not increased'),
        (below: 102, label: 'increased'),
        (below: null, label: 'substantially increased'),
      ],
      female: [
        (below: 80, label: 'not increased'),
        (below: 88, label: 'increased'),
        (below: null, label: 'substantially increased'),
      ],
    ),
  ),
  CalculationDefinition(
    id: 'bodytmi-calc/navy-body-fat/1',
    name: 'Navy body-fat estimate',
    formula:
        'men 495 / (1.0324 − 0.19077·log10(navel − neck) + 0.15456·log10(height)) − 450; '
        'women 495 / (1.29579 − 0.35004·log10(waist + hip − neck) + 0.22100·log10(height)) − 450 (cm, percent)',
    source:
        'Hodgdon & Beckett (1984), Naval Health Research Center reports '
        '84-11 and 84-29, metric form',
    unit: 'ratio',
    requiresSex: true,
    inputs: [
      _q('male:navel', Dimension.distance, 'Abdomen at the navel'),
      _q('female:waist', Dimension.distance, 'Waist at its narrowest'),
      _q('female:hip', Dimension.distance, 'Hip'),
      _q('neck', Dimension.distance, 'Neck'),
      _q('height', Dimension.distance, 'Height'),
    ],
    compute: (v) {
      final log10 = (double x) => math.log(x) / math.ln10;
      final percent = v.containsKey('navel')
          ? 495 /
                    (1.0324 -
                        0.19077 * log10(_cm(v['navel']!) - _cm(v['neck']!)) +
                        0.15456 * log10(_cm(v['height']!))) -
                450
          : 495 /
                    (1.29579 -
                        0.35004 *
                            log10(
                              _cm(v['waist']!) +
                                  _cm(v['hip']!) -
                                  _cm(v['neck']!),
                            ) +
                        0.22100 * log10(_cm(v['height']!))) -
                450;
      return percent / 100;
    },
  ),
  CalculationDefinition(
    id: 'bodytmi-calc/jackson-pollock-3/1',
    name: 'Jackson–Pollock 3-site body-fat estimate',
    formula:
        'men (chest, abdomen, thigh) D = 1.10938 − 0.0008267·S + 0.0000016·S² − 0.0002574·age; '
        'women (triceps, suprailiac, thigh) D = 1.0994921 − 0.0009929·S + 0.0000023·S² − 0.0001392·age; '
        'Siri: 4.95/D − 4.50 (S in mm)',
    source:
        'Jackson & Pollock (1978) Br J Nutr 40:497–504; Jackson, Pollock & '
        'Ward (1980) Med Sci Sports Exerc 12:175–182; Siri (1961)',
    unit: 'ratio',
    requiresSex: true,
    inputs: [
      _q('male:chest', Dimension.distance, 'Chest skinfold'),
      _q('male:abdomen', Dimension.distance, 'Abdomen skinfold'),
      _q('female:triceps', Dimension.distance, 'Triceps skinfold'),
      _q('female:suprailiac', Dimension.distance, 'Suprailiac skinfold'),
      _q('thigh', Dimension.distance, 'Thigh skinfold'),
      _age,
    ],
    compute: (v) {
      final age = v['age']! as int;
      if (v.containsKey('chest')) {
        final s = _mm(v['chest']!) + _mm(v['abdomen']!) + _mm(v['thigh']!);
        return _siri(
          1.10938 - 0.0008267 * s + 0.0000016 * s * s - 0.0002574 * age,
        );
      }
      final s = _mm(v['triceps']!) + _mm(v['suprailiac']!) + _mm(v['thigh']!);
      return _siri(
        1.0994921 - 0.0009929 * s + 0.0000023 * s * s - 0.0001392 * age,
      );
    },
  ),
  CalculationDefinition(
    id: 'bodytmi-calc/jackson-pollock-7/1',
    name: 'Jackson–Pollock 7-site body-fat estimate',
    formula:
        'S = chest + midaxillary + triceps + subscapular + abdomen + suprailiac + thigh (mm); '
        'men D = 1.112 − 0.00043499·S + 0.00000055·S² − 0.00028826·age; '
        'women D = 1.097 − 0.00046971·S + 0.00000056·S² − 0.00012828·age; Siri: 4.95/D − 4.50',
    source:
        'Jackson & Pollock (1978) Br J Nutr 40:497–504; Jackson, Pollock & '
        'Ward (1980) Med Sci Sports Exerc 12:175–182; Siri (1961)',
    unit: 'ratio',
    requiresSex: true,
    inputs: [
      for (final site in const [
        'chest',
        'midaxillary',
        'triceps',
        'subscapular',
        'abdomen',
        'suprailiac',
        'thigh',
      ])
        _q(site, Dimension.distance, '$site skinfold'),
      _age,
    ],
    compute: (v) {
      final age = v['age']! as int;
      final s = [
        'chest',
        'midaxillary',
        'triceps',
        'subscapular',
        'abdomen',
        'suprailiac',
        'thigh',
      ].fold<double>(0, (sum, site) => sum + _mm(v[site]!));
      final d = v['sex'] == 'male'
          ? 1.112 - 0.00043499 * s + 0.00000055 * s * s - 0.00028826 * age
          : 1.097 - 0.00046971 * s + 0.00000056 * s * s - 0.00012828 * age;
      return _siri(d);
    },
  ),
  CalculationDefinition(
    id: 'bodytmi-calc/fat-mass/1',
    name: 'Fat mass',
    formula: 'mass × body-fat fraction',
    source: 'Two-compartment model',
    unit: 'kg',
    inputs: [
      _q('mass', Dimension.mass, 'Body mass'),
      _q(
        'bodyFat',
        Dimension.ratio,
        'Body-fat fraction from the selected source',
      ),
    ],
    compute: (v) => _d(v['mass']!) * _d(v['bodyFat']!),
  ),
  CalculationDefinition(
    id: 'bodytmi-calc/fat-free-mass/1',
    name: 'Fat-free mass',
    formula: 'mass × (1 − body-fat fraction)',
    source: 'Two-compartment model; fat-free mass is not muscle mass',
    unit: 'kg',
    inputs: [
      _q('mass', Dimension.mass, 'Body mass'),
      _q(
        'bodyFat',
        Dimension.ratio,
        'Body-fat fraction from the selected source',
      ),
    ],
    compute: (v) => _d(v['mass']!) * (1 - _d(v['bodyFat']!)),
  ),
  CalculationDefinition(
    id: 'bodytmi-calc/ffmi/1',
    name: 'Fat-free mass index',
    formula: 'mass × (1 − body-fat fraction) / height (m)²',
    source: 'Kouri et al. (1995) Clin J Sport Med 5:223–228',
    unit: 'kg/m2',
    inputs: [
      _q('mass', Dimension.mass, 'Body mass'),
      _q(
        'bodyFat',
        Dimension.ratio,
        'Body-fat fraction from the selected source',
      ),
      _q('height', Dimension.distance, 'Height'),
    ],
    compute: (v) =>
        _d(v['mass']!) *
        (1 - _d(v['bodyFat']!)) /
        math.pow(_metres(v['height']!), 2),
  ),
  CalculationDefinition(
    id: 'bodytmi-calc/normalized-ffmi/1',
    name: 'Height-normalised fat-free mass index',
    formula: 'FFMI + 6.1 × (1.8 − height (m))',
    source: 'Kouri et al. (1995) Clin J Sport Med 5:223–228',
    unit: 'kg/m2',
    inputs: [
      _q('mass', Dimension.mass, 'Body mass'),
      _q(
        'bodyFat',
        Dimension.ratio,
        'Body-fat fraction from the selected source',
      ),
      _q('height', Dimension.distance, 'Height'),
    ],
    compute: (v) {
      final h = _metres(v['height']!);
      return _d(v['mass']!) * (1 - _d(v['bodyFat']!)) / (h * h) +
          6.1 * (1.8 - h);
    },
  ),
  CalculationDefinition(
    id: 'bodytmi-calc/target-mass/1',
    name: 'Mass at a goal body fat',
    formula: 'fat-free mass / (1 − goal body-fat fraction)',
    source:
        'McDonald, Intermittent Modified Fasting (2026); assumes fat-free '
        'mass is kept',
    unit: 'kg',
    inputs: [
      _q('mass', Dimension.mass, 'Body mass'),
      _q(
        'bodyFat',
        Dimension.ratio,
        'Body-fat fraction from the selected source',
      ),
      _q('goalBodyFat', Dimension.ratio, 'Goal body-fat fraction'),
    ],
    compute: (v) =>
        _d(v['mass']!) * (1 - _d(v['bodyFat']!)) / (1 - _d(v['goalBodyFat']!)),
  ),
  CalculationDefinition(
    id: 'bodytmi-calc/walking-energy/1',
    name: 'Walking energy from steps',
    formula: 'steps × step length × mass × 0.75 kcal per kg per km',
    source: 'The workbook’s walking estimate; labelled an estimate',
    unit: 'kcal',
    inputs: [
      _q('steps', Dimension.steps, 'Steps'),
      _q('stepLength', Dimension.distance, 'Step length'),
      _q('mass', Dimension.mass, 'Body mass'),
    ],
    compute: (v) =>
        _d(v['steps']!) *
        _metres(v['stepLength']!) /
        1000 *
        _d(v['mass']!) *
        0.75,
  ),
]);

CalculationDefinition calculation(String id) =>
    calculations.where((c) => c.id == id).firstOrNull ??
    (throw BodyTmiException('not_found', 'Unknown calculation $id.'));
