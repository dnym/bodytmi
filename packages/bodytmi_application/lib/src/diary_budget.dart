import 'package:bodytmi_core/bodytmi_core.dart';

/// Policy bodytmi-diary-budget/1: one day's eaten amounts against the goals
/// of the diet-run day in force. Goals and nutrients share names (energy,
/// protein, carbohydrate, fat, fibre). A partly known intake makes eaten a
/// lower bound, so remaining is an upper bound (`atMost`).
Map<String, Object?> dayBudget(
  Map<String, Object?> scheduleDay,
  Nutrition eaten,
) {
  final goals = jsonObject(scheduleDay['goals'], 'goals');
  final out = <String, Object?>{};
  for (final e in goals.entries) {
    final goal = jsonObject(e.value, e.key);
    out[e.key] = _goalBudget(e.key, goal, eaten);
  }
  return {
    'policy': 'bodytmi-diary-budget/1',
    'run': scheduleDay['run'],
    'dayType': scheduleDay['dayType'],
    'goals': out,
  };
}

Fraction _amount(Object? q) {
  final quantity = Quantity.fromJson(q);
  return Fraction.decimal(quantity.value);
}

String _show(Fraction canonical, String unit) =>
    (canonical / Fraction.parse(Unit.parse(unit).factor)).round().toString();

Map<String, Object?> _goalBudget(
  String name,
  Map<String, Object?> goal,
  Nutrition eaten,
) {
  if (goal['status'] != 'resolved')
    return {'status': 'unavailable', 'reason': goal['reason']};
  final unit = name == 'energy' ? 'kcal' : 'g';
  final status = eaten.status(name);
  final value = eaten.values[name] ?? Fraction.zero;
  final eatenJson = {
    'status': eaten.items == 0 ? 'known' : status,
    'value': eaten.items > 0 && status == 'unavailable'
        ? null
        : _show(value, unit),
    'unit': unit,
  };
  if (eaten.items > 0 && status == 'unavailable')
    return {
      'status': 'unknown',
      'eaten': eatenJson,
      'reason': 'No logged item declares $name.',
    };
  final bound = eaten.items > 0 && status == 'partial';
  Map<String, Object?> remaining(Fraction target) {
    final diff = target - value;
    return {
      'value': _show(
        diff.compareTo(Fraction.zero) < 0 ? Fraction.zero : diff,
        unit,
      ),
      'over': diff.compareTo(Fraction.zero) < 0
          ? _show(Fraction.zero - diff, unit)
          : null,
      'unit': unit,
      if (bound) 'bound': 'atMost',
    };
  }

  if (goal.containsKey('value')) {
    final target = _amount(goal['value']);
    return {
      'status': 'resolved',
      'target': goal['value'],
      'eaten': eatenJson,
      'remaining': remaining(target),
    };
  }
  final min = _amount(goal['minimum']);
  final max = _amount(goal['maximum']);
  final relation = value.compareTo(min) < 0
      ? (bound ? 'below-or-unknown' : 'below')
      : value.compareTo(max) > 0
      ? 'above'
      : (bound ? 'within-or-above' : 'within');
  return {
    'status': 'resolved',
    'minimum': goal['minimum'],
    'maximum': goal['maximum'],
    'eaten': eatenJson,
    'relation': relation,
    'toMinimum': remaining(min),
    'toMaximum': remaining(max),
  };
}

/// Policy bodytmi-diary-adherence/1: over complete diary days with a
/// diet-run day, each goal's mean eaten against mean target, the mean
/// signed deviation, and for ranges the days below, within and above. With
/// [tolerancePercent] a single-valued goal also counts days within that
/// percentage of its target. Days whose intake of a goal's nutrient is only
/// partly known are left out of that goal and counted as such.
Map<String, Object?> adherence(
  List<
    ({
      String date,
      String status,
      Map<String, Object?>? schedule,
      Nutrition eaten,
    })
  >
  days, {
  Decimal? tolerancePercent,
}) {
  final perGoal = <String, Map<String, Object?>>{};
  final sums = <String, ({Fraction eaten, Fraction target, int n})>{};
  final counts = <String, Map<String, int>>{};
  var complete = 0, withoutPlan = 0, notComplete = 0;
  for (final d in days) {
    if (d.schedule == null || d.schedule!['goals'] == null) {
      withoutPlan++;
      continue;
    }
    if (d.status != 'complete') {
      notComplete++;
      continue;
    }
    complete++;
    final goals = jsonObject(d.schedule!['goals'], 'goals');
    for (final e in goals.entries) {
      final goal = jsonObject(e.value, e.key);
      final c = counts.putIfAbsent(
        e.key,
        () => {
          'evaluated': 0,
          'partial': 0,
          'unresolved': 0,
          'below': 0,
          'within': 0,
          'above': 0,
        },
      );
      if (goal['status'] != 'resolved') {
        c['unresolved'] = c['unresolved']! + 1;
        continue;
      }
      final status = d.eaten.status(e.key);
      if (d.eaten.items > 0 && status != 'known') {
        c['partial'] = c['partial']! + 1;
        continue;
      }
      final eaten = d.eaten.values[e.key] ?? Fraction.zero;
      c['evaluated'] = c['evaluated']! + 1;
      Fraction target;
      if (goal.containsKey('value')) {
        target = _amount(goal['value']);
        if (tolerancePercent != null) {
          final band =
              target *
              Fraction.decimal(tolerancePercent) /
              Fraction.integer(100);
          final key = eaten.compareTo(target - band) < 0
              ? 'below'
              : eaten.compareTo(target + band) > 0
              ? 'above'
              : 'within';
          c[key] = c[key]! + 1;
        }
      } else {
        final min = _amount(goal['minimum']);
        final max = _amount(goal['maximum']);
        target = (min + max) / Fraction.integer(2);
        final key = eaten.compareTo(min) < 0
            ? 'below'
            : eaten.compareTo(max) > 0
            ? 'above'
            : 'within';
        c[key] = c[key]! + 1;
      }
      final s = sums[e.key];
      sums[e.key] = (
        eaten: (s?.eaten ?? Fraction.zero) + eaten,
        target: (s?.target ?? Fraction.zero) + target,
        n: (s?.n ?? 0) + 1,
      );
    }
  }
  for (final e in counts.entries) {
    final unit = e.key == 'energy' ? 'kcal' : 'g';
    final s = sums[e.key];
    Object? mean(
      Fraction Function(({Fraction eaten, Fraction target, int n})) f,
    ) => s == null
        ? null
        : {'value': _show(f(s) / Fraction.integer(s.n), unit), 'unit': unit};
    perGoal[e.key] = {
      'days': e.value,
      'meanEaten': mean((s) => s.eaten),
      'meanTarget': mean((s) => s.target),
      'meanDeviation': s == null
          ? null
          : {
              'value': (() {
                final d = (s.eaten - s.target) / Fraction.integer(s.n);
                final shown = _show(
                  d.compareTo(Fraction.zero) < 0 ? Fraction.zero - d : d,
                  unit,
                );
                return d.compareTo(Fraction.zero) < 0 && shown != '0'
                    ? '-$shown'
                    : shown;
              })(),
              'unit': unit,
            },
    };
  }
  return {
    'policy': 'bodytmi-diary-adherence/1',
    'tolerancePercent': tolerancePercent?.toString(),
    'days': {
      'total': days.length,
      'evaluated': complete,
      'notComplete': notComplete,
      'withoutPlan': withoutPlan,
    },
    'goals': perGoal,
  };
}
