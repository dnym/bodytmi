import 'calculation.dart' show round9;
import 'errors.dart';
import 'quantity.dart';

/// Exactly 1 lb in kg (F14: book factors are stored as printed per lb).
const kgPerLb = 0.45359237;

/// McDonald's diet category from body fat (a ratio) and sex. Both books use
/// men ≤15 / 16–25 / ≥26 % and women ≤24 / 25–34 / ≥35 %; the workbook's
/// half-point cut-offs (15.5 / 25.5, 24.5 / 34.5) close the gaps between
/// the integer bands.
int dietCategory(Decimal bodyFat, String sex) {
  final percent = double.parse(bodyFat.toString()) * 100;
  final (one, two) = switch (sex) {
    'male' => (15.5, 25.5),
    'female' => (24.5, 34.5),
    _ => invalid('sex is male or female.'),
  };
  return percent < one
      ? 1
      : percent < two
      ? 2
      : 3;
}

const dietCategoryPolicy = {
  'id': 'bodytmi-diet-category/1',
  'source':
      'McDonald, The Rapid Fat Loss Handbook (2008), ch. 6 table 1; '
      'Intermittent Modified Fasting (2026), ch. 6',
  'bands': {
    'male': ['< 15.5 %: 1', '< 25.5 %: 2', 'otherwise 3'],
    'female': ['< 24.5 %: 1', '< 34.5 %: 2', 'otherwise 3'],
  },
};

/// Inputs a maintenance method may need, already resolved by the caller.
typedef EnergyInputs = ({
  double? massKg,
  double? heightCm,
  double? fatFreeMassKg,
  int? age,
  String? sex,
  int? category,
});

/// How maintenance energy is estimated (F4): one named formula, or a
/// manual value. Where a book gives a range or a choice, the method names
/// the chosen value; nothing is defaulted silently.
///
/// * `mifflin-st-jeor` / `katch-mcardle` {pal, adjustment?} — resting
///   energy × physical activity level × (1 + adjustment), the workbook's
///   TDEE;
/// * `mcdonald-rfl-maintenance` {activity, calPerLb} — body mass (lb) ×
///   cal/lb within the handbook's range for the activity level;
/// * `mcdonald-imf-tdee` {activity, exercise?} — body mass (lb) × BMR
///   cal/lb by category (10 / 9 / 8) × (activity multiplier + exercise
///   hours × per-hour multiplier) for the day described;
/// * `manual` {energy}.
final class MaintenanceMethod {
  MaintenanceMethod._(this.json);
  factory MaintenanceMethod.fromJson(Object? input) {
    final j = jsonObject(input, 'maintenance method');
    final formula = requiredString(j, 'formula');
    Decimal decimal(String key, double min, double max) {
      final d = Decimal.parse(requiredString(j, key));
      final v = double.parse(d.toString());
      if (v < min || v > max) invalid('$key is from $min to $max.');
      return d;
    }

    switch (formula) {
      case 'mifflin-st-jeor' || 'katch-mcardle':
        checkKeys(j, {'formula', 'pal', 'adjustment'});
        decimal('pal', 1, 3);
        if (j['adjustment'] != null) decimal('adjustment', -0.5, 0.5);
      case 'mcdonald-rfl-maintenance':
        checkKeys(j, {'formula', 'activity', 'calPerLb'});
        final range = rflMaintenanceRanges[j['activity']];
        if (range == null)
          invalid(
            'activity is one of ${rflMaintenanceRanges.keys.join(', ')}.',
          );
        decimal('calPerLb', range.$1, range.$2);
      case 'mcdonald-imf-tdee':
        checkKeys(j, {'formula', 'activity', 'exercise'});
        if (!imfActivity.containsKey(j['activity']))
          invalid('activity is one of ${imfActivity.keys.join(', ')}.');
        final exercise = j['exercise'] == null
            ? const <Object?>[]
            : jsonList(j, 'exercise');
        if (exercise.length > 16) invalid('At most 16 exercise entries.');
        for (final e in exercise) {
          final x = jsonObject(e, 'exercise');
          checkKeys(x, {'kind', 'hours'});
          if (!imfExercise.containsKey(x['kind']))
            invalid('exercise kind is one of ${imfExercise.keys.join(', ')}.');
          final hours = Decimal.parse(requiredString(x, 'hours'));
          final h = double.parse(hours.toString());
          if (h <= 0 || h > 24) invalid('exercise hours are from 0 to 24.');
        }
      case 'manual':
        checkKeys(j, {'formula', 'energy'});
        final q = Quantity.fromJson(j['energy']);
        if (q.dimension != Dimension.energy)
          invalid('A manual maintenance value is an energy.');
      default:
        invalid(
          'formula is mifflin-st-jeor, katch-mcardle, '
          'mcdonald-rfl-maintenance, mcdonald-imf-tdee or manual.',
        );
    }
    return MaintenanceMethod._(Map.unmodifiable(j));
  }

  /// Handbook ch. 14: cal/lb by activity (already ~10 % below raw).
  static const rflMaintenanceRanges = {
    'sedentary': (10.0, 11.0),
    'light': (11.0, 12.0),
    'moderate': (12.0, 13.0),
    'very': (14.0, 15.0),
    'extreme': (18.0, 19.0),
  };

  /// IMF ch. 14: daily activity multipliers (excluding formal exercise).
  static const imfActivity = {
    'inactive': 1.1,
    'light': 1.2,
    'moderate': 1.3,
    'high': 1.5,
  };

  /// IMF ch. 14: exercise multipliers per hour.
  static const imfExercise = {
    'low-aerobic': 0.2,
    'medium-aerobic': 0.3,
    'high-aerobic': 0.4,
    'hiit': 0.3,
    'moderate-weights': 0.1,
    'high-weights': 0.2,
  };

  /// IMF ch. 14: BMR cal/lb by category.
  static const imfBmrPerLb = {1: 10.0, 2: 9.0, 3: 8.0};

  final Map<String, Object?> json;
  String get formula => json['formula']! as String;
  String get id => switch (formula) {
    'mifflin-st-jeor' => 'bodytmi-energy/mifflin-st-jeor/1',
    'katch-mcardle' => 'bodytmi-energy/katch-mcardle/1',
    'mcdonald-rfl-maintenance' => 'bodytmi-energy/mcdonald-rfl-maintenance/1',
    'mcdonald-imf-tdee' => 'bodytmi-energy/mcdonald-imf-tdee/1',
    _ => 'bodytmi-energy/manual/1',
  };

  String get source => switch (formula) {
    'mifflin-st-jeor' =>
      'Mifflin et al. 1990 (resting energy) × physical activity level',
    'katch-mcardle' =>
      'Katch–McArdle (resting energy) × physical activity level',
    'mcdonald-rfl-maintenance' =>
      'McDonald, The Rapid Fat Loss Handbook (2008), ch. 14',
    'mcdonald-imf-tdee' =>
      'McDonald, Intermittent Modified Fasting (2026), ch. 14',
    _ => 'Entered value',
  };

  double _d(String key) => double.parse(json[key]! as String);

  /// The inputs this method needs.
  List<String> get needs => switch (formula) {
    'mifflin-st-jeor' => ['mass', 'height', 'age', 'sex'],
    'katch-mcardle' => ['fatFreeMass'],
    'mcdonald-rfl-maintenance' => ['mass'],
    'mcdonald-imf-tdee' => ['mass', 'category'],
    _ => const [],
  };

  /// The total IMF multiplier (activity + exercise), or null otherwise.
  double? get imfMultiplier {
    if (formula != 'mcdonald-imf-tdee') return null;
    var total = imfActivity[json['activity']]!;
    for (final e in (json['exercise'] as List?) ?? const []) {
      final x = e as Map<String, Object?>;
      total += imfExercise[x['kind']]! * double.parse(x['hours']! as String);
    }
    return total;
  }

  /// Maintenance energy (kcal/day) with the factors used, or unavailable
  /// naming what is missing.
  Map<String, Object?> evaluate(EnergyInputs inputs) {
    final missing = [
      for (final n in needs)
        if (switch (n) {
              'mass' => inputs.massKg,
              'height' => inputs.heightCm,
              'age' => inputs.age,
              'sex' => inputs.sex,
              'fatFreeMass' => inputs.fatFreeMassKg,
              _ => inputs.category,
            } ==
            null)
          n,
    ];
    final base = <String, Object?>{
      'method': json,
      'formula': id,
      'source': source,
    };
    if (missing.isNotEmpty)
      return {
        ...base,
        'status': 'unavailable',
        'missing': missing,
        'reason': 'Missing ${missing.join(', ')}.',
      };
    final factors = <String, Object?>{};
    late final double kcal;
    switch (formula) {
      case 'mifflin-st-jeor' || 'katch-mcardle':
        final resting = formula == 'katch-mcardle'
            ? 370 + 21.6 * inputs.fatFreeMassKg!
            : 10 * inputs.massKg! +
                  6.25 * inputs.heightCm! -
                  5 * inputs.age! +
                  (inputs.sex == 'male' ? 5 : -161);
        final adjustment = json['adjustment'] == null ? 0.0 : _d('adjustment');
        factors['restingEnergy'] = {'value': round9(resting), 'unit': 'kcal'};
        factors['pal'] = json['pal'];
        factors['adjustment'] = json['adjustment'] ?? '0';
        kcal = resting * _d('pal') * (1 + adjustment);
      case 'mcdonald-rfl-maintenance':
        final lb = inputs.massKg! / kgPerLb;
        factors['massLb'] = round9(lb);
        factors['calPerLb'] = json['calPerLb'];
        kcal = lb * _d('calPerLb');
      case 'mcdonald-imf-tdee':
        final lb = inputs.massKg! / kgPerLb;
        final bmr = imfBmrPerLb[inputs.category]!;
        factors['massLb'] = round9(lb);
        factors['category'] = inputs.category;
        factors['bmrCalPerLb'] = round9(bmr);
        factors['multiplier'] = round9(imfMultiplier!);
        kcal = lb * bmr * imfMultiplier!;
      default:
        final q = Quantity.fromJson(json['energy']);
        kcal = double.parse(q.value.toString()) / 4.184;
    }
    return {
      ...base,
      'status': 'resolved',
      'factors': factors,
      'value': {'value': round9(kcal), 'unit': 'kcal'},
    };
  }

  Map<String, Object?> toJson() => json;
}

/// A dated maintenance-method selection; the one in force on a date is the
/// latest whose [from] is on or before it (later revision first on a day).
final class MaintenanceMethodRevision {
  MaintenanceMethodRevision._(this.number, this.from, this.method);
  factory MaintenanceMethodRevision.publish(
    String from,
    MaintenanceMethod method, {
    MaintenanceMethodRevision? previous,
  }) {
    requireDate(from, 'from');
    return MaintenanceMethodRevision._(
      (previous?.number ?? 0) + 1,
      from,
      method,
    );
  }
  factory MaintenanceMethodRevision.fromJson(Object? input) {
    final j = jsonObject(input, 'maintenance method revision');
    checkKeys(j, {'schemaVersion', 'revision', 'from', 'method'});
    final revision = j['revision'];
    if (j['schemaVersion'] != 1 || revision is! int || revision < 1)
      invalid('Invalid maintenance method revision.');
    return MaintenanceMethodRevision._(
      revision,
      requireDate(j['from'], 'from'),
      MaintenanceMethod.fromJson(j['method']),
    );
  }
  final int number;
  final String from;
  final MaintenanceMethod method;
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'revision': number,
    'from': from,
    'method': method.toJson(),
  };
}

/// The method in force on [date], or null.
MaintenanceMethodRevision? maintenanceMethodOn(
  String date,
  List<MaintenanceMethodRevision> revisions,
) {
  MaintenanceMethodRevision? best;
  for (final r in revisions) {
    if (r.from.compareTo(date) > 0) continue;
    if (best == null ||
        r.from.compareTo(best.from) > 0 ||
        (r.from == best.from && r.number > best.number))
      best = r;
  }
  return best;
}

/// A valid YYYY-MM-DD date string.
String requireDate(Object? value, String name) {
  if (value is! String ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
      DateTime.tryParse(
            '${value}T00:00:00Z',
          )?.toIso8601String().substring(0, 10) !=
          value)
    invalid('$name is a valid YYYY-MM-DD date.');
  return value;
}
