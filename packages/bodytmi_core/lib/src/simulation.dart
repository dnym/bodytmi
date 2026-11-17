import 'dart:math' as math;

import 'calculation.dart' show round9;
import 'diet.dart' show addDays;
import 'errors.dart';

const simulationPolicy = 'bodytmi-energy-balance-simulation/1';

/// Forbes' constant (kg): the lean share of a small change is
/// C / (C + fat mass) (Forbes 2000; Hall 2008).
const forbesC = 10.4;

/// Energy densities (MJ/kg) of fat and lean tissue (Hall 2008).
const fatMJPerKg = 39.5, leanMJPerKg = 7.6;
const _mjPerKcal = 0.004184;

/// A daily energy-balance model (section 4.2): each day the deficit is
/// expenditure (recomputed from the projected body by [expenditure]) minus
/// [intake]; the change splits into fat and lean by the Forbes curve at the
/// current fat mass, with separate energy densities. Labelled an estimate.
Map<String, Object?> simulateEnergyBalance({
  required String startDate,
  required int days,
  required double massKg,
  required double fatFreeMassKg,
  required double? Function(int day, String date) intake,
  required double? Function(int day, double massKg, double fatFreeMassKg)
  expenditure,
  int every = 1,
}) {
  if (days < 1 || days > 730) invalid('A simulation runs 1 to 730 days.');
  if (every < 1 || every > 28) invalid('every is 1 to 28 days.');
  if (fatFreeMassKg <= 0 || fatFreeMassKg >= massKg)
    invalid('The simulation needs fat mass and fat-free mass above zero.');
  var fat = massKg - fatFreeMassKg, lean = fatFreeMassKg;
  final points = <Map<String, Object?>>[];
  Map<String, Object?> point(int day, double? inKcal, double? outKcal) => {
    'day': day,
    'date': addDays(startDate, day),
    'mass': round9(fat + lean),
    'fatMass': round9(fat),
    'fatFreeMass': round9(lean),
    'bodyFat': round9(fat / (fat + lean)),
    'intake': ?(inKcal == null ? null : round9(inKcal)),
    'expenditure': ?(outKcal == null ? null : round9(outKcal)),
  };
  var totalDeficit = 0.0;
  for (var day = 0; day < days; day++) {
    final date = addDays(startDate, day);
    final eat = intake(day, date);
    final burn = expenditure(day, fat + lean, lean);
    if (eat == null || burn == null)
      return {
        'policy': simulationPolicy,
        'status': 'unavailable',
        'reason': eat == null
            ? 'Day $date has no energy goal.'
            : 'Expenditure is unavailable on $date.',
      };
    if (day % every == 0) points.add(point(day, eat, burn));
    final change = (eat - burn) * _mjPerKcal; // MJ, negative when losing
    totalDeficit += burn - eat;
    // The lean share at the day's midpoint keeps the path on the Forbes
    // curve (ΔL = C ln(F1/F0)) far better than the share at its start.
    final p0 = forbesC / (forbesC + fat);
    final half = change / 2 / (fatMJPerKg * (1 - p0) + leanMJPerKg * p0);
    final p = forbesC / (forbesC + math.max(0.001, fat + (1 - p0) * half));
    final mass = change / (fatMJPerKg * (1 - p) + leanMJPerKg * p);
    fat = math.max(0.001, fat + (1 - p) * mass);
    lean += p * mass;
  }
  points.add(point(days, null, null));
  final first = points.first, last = points.last;
  double d(Map<String, Object?> p, String key) =>
      double.parse(p[key]! as String);
  return {
    'policy': simulationPolicy,
    'status': 'resolved',
    'estimate': true,
    'model':
        'Daily energy balance; lean share C/(C + fat) with C = $forbesC kg '
        '(Forbes); fat $fatMJPerKg MJ/kg, lean $leanMJPerKg MJ/kg (Hall 2008).',
    'limits': [
      'The first days of a low-carbohydrate diet lose water and glycogen, '
          'which the model ignores.',
      'High protein with strength training usually loses less lean mass '
          'than the curve predicts.',
      'No finish date is promised.',
    ],
    'days': days,
    'totalDeficit': {'value': round9(totalDeficit), 'unit': 'kcal'},
    'change': {
      'mass': round9(d(last, 'mass') - d(first, 'mass')),
      'fatMass': round9(d(last, 'fatMass') - d(first, 'fatMass')),
      'fatFreeMass': round9(d(last, 'fatFreeMass') - d(first, 'fatFreeMass')),
      'unit': 'kg',
    },
    'points': points,
  };
}
