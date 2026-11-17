import 'errors.dart';
import 'fraction.dart';
import 'nutrient.dart';

const nnr2023Policy = 'bodytmi-reference/nnr-2023/1';

/// What a reference value says:
/// * `ri`, `ai` — recommended / adequate intake per day (a minimum);
/// * `riPerMJ`, `minimumPerMJ` — per MJ of energy eaten;
/// * `riPerKg` — per kg of body mass;
/// * `ul` — tolerable upper intake level; `limit` — chronic disease risk
///   reduction intake (sodium);
/// * `energyRange` — share of energy eaten (E%) within [minimum, maximum];
///   `energyBelow` — E% strictly below a maximum.
final class ReferenceValue {
  const ReferenceValue(
    this.nutrient,
    this.kind,
    this.source, {
    this.value,
    this.minimum,
    this.maximum,
    this.unit,
    this.note,
  });
  final String nutrient;
  final String kind;
  final String source;
  final String? value, minimum, maximum, unit, note;

  bool get isUpper => kind == 'ul' || kind == 'limit';
  bool get isEnergyShare => kind == 'energyRange' || kind == 'energyBelow';

  Map<String, Object?> toJson() => {
    'nutrient': nutrient,
    'kind': kind,
    'value': ?value,
    'minimum': ?minimum,
    'maximum': ?maximum,
    'unit': ?unit,
    'source': source,
    'note': ?note,
  };
}

/// Age groups of the adult tables: 18–24, 25–50, 51–70, >70.
int _group(int age) => age <= 24
    ? 0
    : age <= 50
    ? 1
    : age <= 70
    ? 2
    : 3;

const _t11 = 'NNR 2023, Table 11 (protein)';
const _t12 = 'NNR 2023, Table 12 (RI, vitamins)';
const _t13 = 'NNR 2023, Table 13 (AI, vitamins)';
const _t14 = 'NNR 2023, Table 14 (RI, minerals)';
const _t15 = 'NNR 2023, Table 15 (AI, minerals)';
const _t16 = 'NNR 2023, Table 16 (sodium, chronic disease risk reduction)';
const _t21 = 'NNR 2023, Table 21 (upper intake levels, adults)';
const _box2 = 'NNR 2023, Box 2 (intake ranges of macronutrients, adults)';
const _fibre = 'NNR 2023, Box 2 and the fibre summary (at least 3 g/MJ)';

/// Per-sex values by adult age group (female, then male).
const _bySex = <String, (String, String, List<String>, List<String>)>{
  'vitamin-a': (
    _t12,
    'mcg',
    ['700', '700', '700', '650'],
    ['800', '800', '800', '750'],
  ),
  'riboflavin': (
    _t12,
    'mg',
    ['1.6', '1.6', '1.6', '1.6'],
    ['1.6', '1.6', '1.6', '1.6'],
  ),
  'vitamin-b6': (
    _t12,
    'mg',
    ['1.6', '1.6', '1.6', '1.6'],
    ['1.8', '1.8', '1.8', '1.7'],
  ),
  'folate': (
    _t12,
    'mcg',
    ['330', '330', '330', '330'],
    ['330', '330', '330', '330'],
  ),
  'vitamin-c': (
    _t12,
    'mg',
    ['95', '95', '95', '95'],
    ['110', '110', '110', '110'],
  ),
  'calcium': (
    _t14,
    'mg',
    ['1000', '950', '950', '950'],
    ['1000', '950', '950', '950'],
  ),
  'iron': (_t14, 'mg', ['15', '15', '8', '7'], ['9', '9', '9', '9']),
  'zinc': (
    _t14,
    'mg',
    ['9.7', '9.7', '9.5', '9.3'],
    ['12.7', '12.7', '12.4', '12.1'],
  ),
};

const _aiBySex = <String, (String, String, List<String>, List<String>)>{
  'vitamin-e': (_t13, 'mg', ['10', '10', '9', '9'], ['11', '11', '11', '11']),
  'vitamin-b12': (_t13, 'mcg', ['4', '4', '4', '4'], ['4', '4', '4', '4']),
  'phosphorus': (
    _t15,
    'mg',
    ['550', '520', '520', '520'],
    ['550', '520', '520', '520'],
  ),
  'potassium': (
    _t15,
    'mg',
    ['3500', '3500', '3500', '3500'],
    ['3500', '3500', '3500', '3500'],
  ),
  'magnesium': (
    _t15,
    'mg',
    ['300', '300', '300', '300'],
    ['350', '350', '350', '350'],
  ),
  'iodine': (
    _t15,
    'mcg',
    ['150', '150', '150', '150'],
    ['150', '150', '150', '150'],
  ),
  'selenium': (_t15, 'mcg', ['75', '75', '75', '75'], ['90', '90', '90', '85']),
};

const _notes = <String, String>{
  'iron':
      'Women 11–50: if large menstrual bleedings, screening of iron status. '
      'Women over 50 still menstruating should use the 25–50 value (15 mg).',
  'zinc': 'Assumes a mixed diet with about 600 mg/d phytic acid.',
  'vitamin-a': 'Retinol equivalents.',
  'vitamin-e': 'α-tocopherol equivalents; assumes PUFA about 5 E%.',
  'phosphorus': 'Assumes the calcium RI is eaten.',
};

/// The NNR 2023 reference values for an adult of [sex] (`female`/`male`)
/// and [age] in whole years. Pregnancy and lactation are not modelled;
/// children have other tables and are refused rather than guessed.
List<ReferenceValue> nnr2023References(String sex, int age) {
  if (sex != 'female' && sex != 'male')
    invalid('NNR 2023 reference values need sex female or male.');
  if (age < 18)
    invalid(
      'Only the adult NNR 2023 reference values (18 years and older) '
      'are included.',
    );
  final g = _group(age);
  final female = sex == 'female';
  final out = <ReferenceValue>[
    ReferenceValue(
      'energy',
      'info',
      _box2,
      note: 'Energy has no NNR intake target here; your plan sets it.',
    ),
    ReferenceValue(
      'protein',
      'riPerKg',
      _t11,
      value: '0.83',
      unit: 'g/kg',
      note: 'Per kg of body mass (the trend mass is used).',
    ),
    ReferenceValue(
      'protein',
      'energyRange',
      _box2,
      minimum: '10',
      maximum: '20',
      unit: 'E%',
      note: 'Below 8 MJ/d the protein E% should be increased.',
    ),
    ReferenceValue(
      'fat',
      'energyRange',
      _box2,
      minimum: '25',
      maximum: '40',
      unit: 'E%',
    ),
    ReferenceValue(
      'monounsaturated-fat',
      'energyRange',
      _box2,
      minimum: '10',
      maximum: '20',
      unit: 'E%',
      note: 'NNR names cis-monounsaturated fatty acids.',
    ),
    ReferenceValue(
      'polyunsaturated-fat',
      'energyRange',
      _box2,
      minimum: '5',
      maximum: '10',
      unit: 'E%',
      note: 'NNR names cis-polyunsaturated fatty acids.',
    ),
    ReferenceValue(
      'saturated-fat',
      'energyBelow',
      _box2,
      maximum: '10',
      unit: 'E%',
    ),
    ReferenceValue(
      'carbohydrate',
      'energyRange',
      _box2,
      minimum: '45',
      maximum: '60',
      unit: 'E%',
      note: 'Including energy from dietary fibre (8 kJ/g).',
    ),
    ReferenceValue(
      'free-sugars',
      'energyBelow',
      _box2,
      maximum: '10',
      unit: 'E%',
      note: 'Added and free sugars; free sugars include added sugars.',
    ),
    ReferenceValue(
      'fibre',
      'minimumPerMJ',
      _fibre,
      value: '3',
      unit: 'g/MJ',
      note:
          'At reference energy intakes about 25 g/d (women) and '
          '35 g/d (men).',
    ),
    ReferenceValue(
      'alcohol',
      'info',
      'NNR 2023, alcohol summary',
      note: 'NNR 2023 recommends avoiding alcohol; no safe lower limit.',
    ),
    ReferenceValue('thiamin', 'riPerMJ', _t12, value: '0.1', unit: 'mg/MJ'),
    ReferenceValue(
      'niacin-equivalents',
      'riPerMJ',
      _t12,
      value: '1.6',
      unit: 'mg/MJ',
      note: 'Niacin equivalents (NE).',
    ),
    ReferenceValue(
      'vitamin-d',
      'ri',
      _t12,
      value: age >= 75 ? '20' : '10',
      unit: 'mcg',
      note: age >= 75
          ? '20 µg applies from 75 years.'
          : 'With little or no sun exposure, 20 µg/d is recommended.',
    ),
    for (final e in _bySex.entries)
      ReferenceValue(
        e.key,
        'ri',
        e.value.$1,
        value: (female ? e.value.$3 : e.value.$4)[g],
        unit: e.value.$2,
        note: _notes[e.key],
      ),
    for (final e in _aiBySex.entries)
      ReferenceValue(
        e.key,
        'ai',
        e.value.$1,
        value: (female ? e.value.$3 : e.value.$4)[g],
        unit: e.value.$2,
        note: _notes[e.key],
      ),
    ReferenceValue(
      'sodium',
      'limit',
      _t16,
      value: '2300',
      unit: 'mg',
      note: 'Limit to 2.3 g/d sodium, about 5.75 g salt.',
    ),
    for (final (id, value, unit, note) in const [
      ('calcium', '2500', 'mg', null),
      ('iodine', '600', 'mcg', null),
      ('iron', '60', 'mg', null),
      ('phosphorus', '3000', 'mg', null),
      ('selenium', '255', 'mcg', null),
      ('zinc', '25', 'mg', null),
      (
        'retinol',
        '3000',
        'mcg',
        'Retinol and retinyl esters (preformed vitamin A).',
      ),
      ('vitamin-b6', '12', 'mg', null),
      ('vitamin-d', '100', 'mcg', null),
      ('vitamin-e', '300', 'mg', null),
    ])
      ReferenceValue(id, 'ul', _t21, value: value, unit: unit, note: note),
  ];
  for (final r in out) {
    nutrient(r.nutrient);
  }
  return out;
}

/// Upper levels in Table 21 that apply only to a form the food vocabulary
/// does not separate, so they are listed and never compared.
const nnr2023NotCompared = [
  {
    'nutrient': 'magnesium',
    'ul': '250 mg/d',
    'reason':
        'Applies to readily dissociable magnesium salts and magnesium '
        'oxide in supplements, water or added to foods, not to magnesium '
        'naturally present in food.',
  },
  {
    'nutrient': 'folate',
    'ul': '1000 µg/d',
    'reason': 'Applies to synthetic folic acid only.',
  },
  {
    'nutrient': 'niacin',
    'ul': 'nicotinamide 900 mg/d, nicotinic acid 10 mg/d',
    'reason': 'Applies to those forms only.',
  },
];

/// kJ per gram used for energy shares (NNR 2023: protein and carbohydrate
/// 17, fat 37, fibre 8).
const _kjPerGram = <String, int>{
  'protein': 17,
  'carbohydrate': 17,
  'fat': 37,
  'saturated-fat': 37,
  'monounsaturated-fat': 37,
  'polyunsaturated-fat': 37,
  'free-sugars': 17,
  'fibre': 8,
};

typedef MeanIntake = ({Fraction? value, int days, int partialDays});

/// Means of [parts] and of energy (kcal) over the complete days where all of
/// them are known; [energyKcal] is null when there is no such day.
typedef JointMean = ({
  Fraction? energyKcal,
  Map<String, Fraction> parts,
  int days,
});

/// Compares mean daily intakes (display units) with [references]. A mean is
/// null when no day contributes. [energyKcal] is the mean energy over the
/// same days for per-MJ and E% references; [bodyMassKg] scales per-kg ones.
List<Map<String, Object?>> assessReferences(
  List<ReferenceValue> references, {
  required MeanIntake Function(String nutrient) mean,
  required JointMean Function(List<String> nutrients) joint,
  Fraction? bodyMassKg,
}) {
  String show(Fraction f) => f.round(fractionDigits: 3).toString();
  final out = <Map<String, Object?>>[];
  for (final r in references) {
    final base = r.toJson();
    if (r.kind == 'info') {
      out.add({...base, 'relation': 'information'});
      continue;
    }
    final def = nutrient(r.nutrient);
    if (r.isEnergyShare) {
      final parts = r.nutrient == 'carbohydrate'
          ? ['carbohydrate', 'fibre']
          : [r.nutrient];
      final energy = joint(parts);
      if (energy.energyKcal == null || energy.energyKcal!.isZero) {
        out.add({
          ...base,
          'relation': 'unknown',
          'reason':
              'No complete day declares ${parts.join(' and ')} and energy.',
        });
        continue;
      }
      var kj = Fraction.zero;
      for (final p in parts) {
        kj += energy.parts[p]! * Fraction.integer(_kjPerGram[p]!);
      }
      final energyKj = energy.energyKcal! * Fraction.parse('4.184');
      final percent = kj / energyKj * Fraction.integer(100);
      final max = Fraction.parse(r.maximum!);
      final relation = r.kind == 'energyBelow'
          ? (percent.compareTo(max) < 0 ? 'within' : 'above')
          : percent.compareTo(Fraction.parse(r.minimum!)) < 0
          ? 'below'
          : percent.compareTo(max) > 0
          ? 'above'
          : 'within';
      out.add({
        ...base,
        'intake': {'value': show(percent), 'unit': 'E%', 'days': energy.days},
        'relation': relation,
      });
      continue;
    }
    var m = mean(r.nutrient);
    Fraction? amount;
    String? reason;
    switch (r.kind) {
      case 'riPerMJ' || 'minimumPerMJ':
        final energy = joint([r.nutrient]);
        if (energy.energyKcal == null) {
          reason = 'The energy eaten on the same days is unknown.';
        } else {
          m = (
            value: energy.parts[r.nutrient],
            days: energy.days,
            partialDays: m.partialDays,
          );
          amount =
              Fraction.parse(r.value!) *
              energy.energyKcal! *
              Fraction.parse('4.184') /
              Fraction.integer(1000);
        }
      case 'riPerKg':
        if (bodyMassKg == null) {
          reason = 'Body mass is unavailable.';
        } else {
          amount = Fraction.parse(r.value!) * bodyMassKg;
        }
      default:
        amount = Fraction.parse(r.value!);
    }
    final unit = def.unit.name;
    final row = <String, Object?>{
      ...base,
      if (amount != null) 'amount': {'value': show(amount), 'unit': unit},
      'intake': m.value == null
          ? null
          : {
              'value': show(m.value!),
              'unit': unit,
              'days': m.days,
              if (m.partialDays > 0) 'partialDaysExcluded': m.partialDays,
            },
    };
    if (amount == null || m.value == null) {
      out.add({
        ...row,
        'relation': 'unknown',
        'reason':
            reason ??
            (m.partialDays > 0
                ? 'Every complete day has items without ${r.nutrient}.'
                : 'No complete day declares ${r.nutrient}.'),
      });
      continue;
    }
    final c = m.value!.compareTo(amount);
    out.add({
      ...row,
      'relation': r.isUpper
          ? (c > 0 ? 'above' : 'within')
          : (c >= 0 ? 'meets' : 'below'),
    });
  }
  return out;
}
