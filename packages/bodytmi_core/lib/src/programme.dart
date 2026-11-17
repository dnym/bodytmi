import 'diet.dart';
import 'errors.dart';
import 'quantity.dart';

/// What a programme produces for a category and choices: ordinary day
/// types and a cycle over them (by day-type id), its schedule facts,
/// warnings, and choices it still needs.
typedef ProgrammeBuild = ({
  List<DayType> dayTypes,
  List<Object?> cycleDays,
  bool loop,
  Map<String, Object?> schedule,
  List<String> warnings,

  /// Day-type id → goal → where its number comes from.
  Map<String, Map<String, String>> sources,
});

Map<String, Object?> _g(String value) => {'value': value, 'unit': 'g'};
Map<String, Object?> _kcal(String value) => {'value': value, 'unit': 'kcal'};
Map<String, Object?> _ref(String id) => {'type': 'day', 'dayType': id};
Map<String, Object?> _repeat(int count, List<Object?> days, [String? label]) =>
    {'type': 'repeat', 'count': count, 'label': ?label, 'days': days};

/// A built-in diet blueprint (F22): Normal, Rapid Fat Loss, Extreme Rapid
/// Fat Loss and Intermittent Modified Fasting. It names its source, its
/// open choices and its movement and training recommendation, and builds
/// day types and a cycle from your choices and diet category; everything
/// after that is the ordinary diet machinery.
final class DietProgramme {
  const DietProgramme._({
    required this.id,
    required this.name,
    required this.source,
    required this.choices,
    required this.recommendation,
    required this.notes,
  });

  final String id, name, source, notes;

  /// Choice name → description (required unless it says a default).
  final Map<String, String> choices;
  final Map<String, String> recommendation;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'source': source,
    'notes': notes,
    'choices': choices,
    'recommendation': recommendation,
  };

  /// Choices a build for [category] still needs.
  List<String> missingChoices(Map<String, Object?> chosen, int category) => [
    for (final c in _required(category))
      if (!chosen.containsKey(c)) c,
  ];

  List<String> _required(int category) => switch (id) {
    'normal' => const [],
    'rfl' => [
      'activity',
      'breakActivity',
      'breakDays',
      ...switch (category) {
        1 => ['dietDays', 'refeedDays', 'refeedCarbohydratePerKg'],
        2 => ['dietWeeks', 'refeedCarbohydratePerLb'],
        _ => ['dietWeeks'],
      },
    ],
    'erfl' => const ['walking', 'afterDays'],
    _ => const ['activity', 'pattern', 'arrangement', 'fatPerLb'],
  };

  /// Builds day types (ids prefixed with [prefix]) and a cycle.
  ProgrammeBuild build(
    Map<String, Object?> chosen,
    int category,
    String prefix,
  ) {
    if (category < 1 || category > 3) invalid('category is 1, 2 or 3.');
    final allowed = choices.keys.toSet();
    final unknown = chosen.keys.toSet().difference(allowed);
    if (unknown.isNotEmpty)
      invalid('Unknown $id choices: ${unknown.join(', ')}.');
    final missing = missingChoices(chosen, category);
    if (missing.isNotEmpty)
      invalid('Programme $id needs choices: ${missing.join(', ')}.');
    String id_(String suffix) => '$prefix-$suffix';
    String decimal(String key, double min, double max) {
      final text = requiredString(chosen, key);
      final v = double.parse(Decimal.parse(text).toString());
      if (v < min || v > max) invalid('$key is from $min to $max.');
      return text;
    }

    int whole(String key, int min, int max) {
      final v = chosen[key];
      if (v is! int || v < min || v > max)
        invalid('$key is a whole number from $min to $max.');
      return v;
    }

    String option(String key, List<String> values) {
      final v = chosen[key];
      if (v is! String || !values.contains(v))
        invalid('$key is one of ${values.join(', ')}.');
      return v;
    }

    String grams(String key, String fallback) =>
        chosen.containsKey(key) ? decimal(key, 0, 1000) : fallback;

    DayType day(
      String suffix,
      String name,
      Map<String, Object?> goals, {
      int? steps,
      String? notes,
    }) => DayType.fromJson({
      'id': id_(suffix),
      'name': name,
      'notes': ?notes,
      'goals': goals,
      'steps': ?steps,
    });

    switch (id) {
      case 'normal':
        final deficit = chosen['deficit'];
        Map<String, Object?> energy;
        String described;
        if (deficit == null) {
          energy = {'basis': 'maintenance', 'subtract': _kcal('500')};
          described = '500 kcal below maintenance';
        } else {
          final d = jsonObject(deficit, 'deficit');
          if (d.containsKey('kcal') == d.containsKey('percent'))
            invalid('deficit is {kcal} or {percent}.');
          if (d.containsKey('kcal')) {
            checkKeys(d, {'kcal'});
            final v = Decimal.parse(requiredString(d, 'kcal'));
            if (double.parse(v.toString()) <= 0 ||
                double.parse(v.toString()) > 2000)
              invalid('deficit kcal is from 0 to 2000.');
            energy = {'basis': 'maintenance', 'subtract': _kcal(v.toString())};
            described = '$v kcal below maintenance';
          } else {
            checkKeys(d, {'percent'});
            final p = double.parse(
              Decimal.parse(requiredString(d, 'percent')).toString(),
            );
            if (p <= 0 || p > 50) invalid('deficit percent is from 0 to 50.');
            energy = {
              'basis': 'maintenance',
              'factor':
                  (Decimal.parse('100') -
                          Decimal.parse(requiredString(d, 'percent')))
                      .dividedByInt(100, fractionDigits: 20)
                      .toString(),
            };
            described = '${d['percent']} % below maintenance';
          }
        }
        final protein = chosen.containsKey('proteinPerKg')
            ? decimal('proteinPerKg', 0.5, 4)
            : '1.8';
        return (
          dayTypes: [
            day('day', 'Deficit day', {
              'energy': energy,
              'protein': {'basis': 'mass', 'perKg': protein},
            }),
            // Not in the cycle: used when a review proposes a diet break.
            day('break', 'Diet break day', {
              'energy': {'basis': 'maintenance'},
              'protein': {'basis': 'mass', 'perKg': protein},
            }, notes: 'Two weeks at maintenance (handbook ch. 15).'),
          ],
          cycleDays: [_ref(id_('day'))],
          loop: true,
          sources: {
            id_('day'): {
              'energy':
                  '$described (D4; maintenance by your chosen method, F4)',
              'protein': '$protein g per kg body mass (F6)',
            },
            id_('break'): {
              'energy': 'maintenance by your chosen method (handbook ch. 15)',
              'protein': '$protein g per kg body mass (F6)',
            },
          },
          schedule: {
            'intake': described,
            'protein': '$protein g per kg body mass',
            'length': 'open-ended; breaks optional',
          },
          warnings: const [],
        );

      case 'rfl':
        final activity = option('activity', ['inactive', 'aerobic', 'weights']);
        final column = ['inactive', 'aerobic', 'weights'].indexOf(activity);
        const protein = [
          ['1.25', '1.5', '2.0'],
          ['0.9', '1.1', '1.25'],
          ['0.8', '0.9', '1.0'],
        ];
        final perLb = protein[category - 1][column];
        final carbs = grams('carbohydrate', '20'), fat = grams('fat', '20');
        final breakActivity = option('breakActivity', [
          'sedentary',
          'light',
          'moderate',
          'very',
          'extreme',
        ]);
        const breakCarbs = {
          'sedentary': '0',
          'light': '0.5',
          'moderate': '1.0',
          'very': '1.25',
          'extreme': '1.5',
        };
        const breakProtein = {
          'inactive': '0.75',
          'aerobic': '1.0',
          'weights': '1.5',
        };
        final breakDays = whole('breakDays', 7, 14);
        final rflGoals = {
          'energy': {'sum': true},
          'protein': {'basis': 'fat-free-mass', 'perLb': perLb},
          'carbohydrate': {'fixed': _g(carbs)},
          'fat': {'fixed': _g(fat)},
        };
        final types = <DayType>[
          day(
            'rfl',
            'RFL day',
            rflGoals,
            notes:
                'Lean protein, fibrous vegetables, 10 g fish oil, '
                'electrolytes and a multivitamin.',
          ),
          day('break', 'Diet break day', {
            'energy': {'basis': 'maintenance'},
            'protein': {
              'basis': 'fat-free-mass',
              'perLb': breakProtein[activity]!,
            },
            'carbohydrate': breakCarbs[breakActivity] == '0'
                ? {'fixed': _g('100')}
                : {
                    'basis': 'fat-free-mass',
                    'perLb': breakCarbs[breakActivity]!,
                    'add': _g('100'),
                  },
            'fat': {'remainder': true},
          }, notes: 'Full diet break at maintenance (handbook ch. 14 macros).'),
        ];
        final days = <Object?>[];
        final schedule = <String, Object?>{
          'category': category,
          'protein': '$perLb g per lb fat-free mass',
          'breakDays': breakDays,
        };
        if (category == 1) {
          final dietDays = whole('dietDays', 11, 12);
          final refeedDays = whole('refeedDays', 2, 3);
          final perKg = decimal('refeedCarbohydratePerKg', 12, 16);
          var amount = Decimal.parse(perKg);
          for (var i = 1; i <= refeedDays; i++) {
            types.add(
              day('refeed-$i', 'Refeed day $i', {
                'protein': {'basis': 'fat-free-mass', 'perLb': perLb},
                'carbohydrate': {
                  'basis': 'fat-free-mass',
                  'perKg': amount.toString(),
                },
              }, notes: 'Carbohydrate refeed at the end of the diet.'),
            );
            amount = amount.dividedByInt(2);
          }
          days
            ..add(_repeat(dietDays, [_ref(id_('rfl'))], 'RFL'))
            ..addAll([
              for (var i = 1; i <= refeedDays; i++) _ref(id_('refeed-$i')),
            ]);
          schedule.addAll({
            'dietDays': dietDays,
            'freeMeals': 'none',
            'refeeds':
                '$refeedDays days at the end: $perKg g carbohydrate per kg '
                'fat-free mass, then about half, then half again',
          });
        } else {
          final weeks = whole(
            'dietWeeks',
            category == 2 ? 2 : 6,
            category == 2 ? 6 : 12,
          );
          types.add(
            day(
              'free-meal',
              'Free-meal day',
              rflGoals,
              notes:
                  'RFL day with one normal meal (not a gorge), preferably '
                  'dinner out.',
            ),
          );
          if (category == 2) {
            final perLbCarbs = decimal('refeedCarbohydratePerLb', 1.5, 3);
            types.add(
              day('refeed', 'Refeed day', {
                'protein': {'basis': 'fat-free-mass', 'perLb': perLb},
                'carbohydrate': {'basis': 'fat-free-mass', 'perLb': perLbCarbs},
                'fat': {'minimum': _g('0'), 'maximum': _g('50')},
              }, notes: 'A five-hour carbohydrate refeed, at most 50 g fat.'),
            );
            days.add(
              _repeat(weeks, [
                _repeat(5, [_ref(id_('rfl'))]),
                _ref(id_('free-meal')),
                _ref(id_('refeed')),
              ], 'Week'),
            );
            schedule.addAll({
              'dietWeeks': weeks,
              'freeMeals': '1 a week',
              'refeeds':
                  '5 hours a week: $perLbCarbs g carbohydrate per lb '
                  'fat-free mass, at most 50 g fat',
            });
          } else {
            days.add(
              _repeat(weeks, [
                _repeat(3, [_ref(id_('rfl'))]),
                _ref(id_('free-meal')),
                _repeat(2, [_ref(id_('rfl'))]),
                _ref(id_('free-meal')),
              ], 'Week'),
            );
            schedule.addAll({
              'dietWeeks': weeks,
              'freeMeals': '2 a week',
              'refeeds': 'none',
            });
          }
        }
        days.add(_repeat(breakDays, [_ref(id_('break'))], 'Diet break'));
        final rflProtein =
            'Rapid Fat Loss Handbook ch. 8 table 1: category $category, '
            '$activity: $perLb g per lb fat-free mass';
        final rflSources = {
          'protein': rflProtein,
          'carbohydrate': '$carbs g (F13: about 20 g a day, tunable)',
          'fat': '$fat g including fish oil (F13: about 20 g a day, tunable)',
          'energy': 'protein × 4 + carbohydrate × 4 + fat × 9',
        };
        return (
          dayTypes: types,
          cycleDays: days,
          loop: true,
          schedule: schedule,
          warnings: const [],
          sources: {
            id_('rfl'): rflSources,
            if (category > 1) id_('free-meal'): rflSources,
            id_('break'): {
              'energy': 'maintenance by your chosen method (F4)',
              'protein':
                  'Handbook ch. 14: ${breakProtein[activity]} g per lb '
                  'fat-free mass ($activity)',
              'carbohydrate':
                  'Handbook ch. 14: 100 g + ${breakCarbs[breakActivity]} g '
                  'per lb fat-free mass ($breakActivity)',
              'fat': 'Handbook ch. 14: the remainder of maintenance energy',
            },
            for (final t in types)
              if (t.id.contains('refeed'))
                t.id: {
                  'protein': rflProtein,
                  'carbohydrate': category == 1
                      ? 'Handbook ch. 10 table 1: category 1 end refeed, '
                            'day 1 12–16 g per kg fat-free mass, then about '
                            'half, then half again'
                      : 'Handbook ch. 10: category 2 refeed, 1.5–3 g per lb '
                            'fat-free mass in 5 hours, at most 50 g fat',
                  if (category == 2) 'fat': 'Handbook ch. 10: at most 50 g',
                },
          },
        );

      case 'erfl':
        final walking = jsonObject(chosen['walking'], 'walking');
        int? steps;
        final String walkingText;
        if (walking.containsKey('steps')) {
          checkKeys(walking, {'steps'});
          final s = walking['steps'];
          if (s is! int || s < 1 || s > 200000)
            invalid('walking steps are from 1 to 200000.');
          steps = s;
          walkingText = '$s steps';
        } else if (walking.containsKey('distanceKm')) {
          checkKeys(walking, {'distanceKm'});
          final km = Decimal.parse(requiredString(walking, 'distanceKm'));
          final v = double.parse(km.toString());
          if (v <= 0 || v > 100)
            invalid('walking distanceKm is from 0 to 100.');
          walkingText = '$km km';
        } else {
          checkKeys(walking, {'hours', 'speedKmh'});
          final h = double.parse(
            Decimal.parse(requiredString(walking, 'hours')).toString(),
          );
          final s = double.parse(
            Decimal.parse(requiredString(walking, 'speedKmh')).toString(),
          );
          if (h <= 0 || h > 16) invalid('walking hours are from 0 to 16.');
          if (s < 2 || s > 8) invalid('walking speedKmh is from 2 to 8.');
          walkingText = '${walking['hours']} h at ${walking['speedKmh']} km/h';
        }
        final afterDays = whole('afterDays', 1, 28);
        const aerobic = ['1.5', '1.1', '0.9'];
        return (
          dayTypes: [
            day(
              'day',
              'ERFL day',
              {
                'energy': {'sum': true},
                'protein': {
                  'basis': 'fat-free-mass',
                  'perLb': aerobic[category - 1],
                },
                'carbohydrate': {'fixed': _g(grams('carbohydrate', '0'))},
                'fat': {'fixed': _g(grams('fat', '0'))},
              },
              steps: steps,
              notes:
                  'Walk $walkingText. Leanest protein only (skinless chicken '
                  'breast, egg whites, tuna); no fish oil; vegetables none or '
                  'at most ½ cup cooked; light salt.',
            ),
            day(
              'after',
              'After ERFL',
              {
                'energy': {'basis': 'maintenance'},
              },
              steps: 10000,
              notes:
                  'Normal eating and 10,000 steps a day. Body weight often '
                  'rises 3–7 lb when carbohydrate returns; that is water '
                  'and glycogen, not fat regain.',
            ),
          ],
          cycleDays: [
            _repeat(4, [_ref(id_('day'))], 'ERFL'),
            _repeat(afterDays, [_ref(id_('after'))], 'After'),
          ],
          loop: false,
          sources: {
            id_('day'): {
              'protein':
                  'Extreme Rapid Fat Loss: the aerobic-only column of the RFL '
                  'handbook ch. 8 table 1, category $category: '
                  '${aerobic[category - 1]} g per lb fat-free mass',
              'carbohydrate': 'ERFL: leanest protein only (default 0 g)',
              'fat': 'ERFL: no fish oil (default 0 g)',
              'energy': 'protein × 4 + carbohydrate × 4 + fat × 9',
            },
            id_('after'): {
              'energy': 'normal eating at maintenance by your chosen method',
            },
          },
          schedule: {
            'category': category,
            'protein':
                '${aerobic[category - 1]} g per lb fat-free mass '
                '(aerobic-only column)',
            'days': '4 days straight, no refeeds or free meals',
            'walking': walkingText,
            'afterDays': afterDays,
          },
          warnings: const [],
        );

      default: // imf
        final activity = option('activity', ['none', 'aerobic', 'weights']);
        const protein = [
          ['1.0', '1.25', '1.5'],
          ['0.8', '0.9', '1.1'],
          ['0.7', '0.8', '0.9'],
        ];
        final perLb =
            protein[category - 1][[
              'none',
              'aerobic',
              'weights',
            ].indexOf(activity)];
        final pattern = option('pattern', imfPatterns.keys.toList());
        final (maintenanceDays, rflDays) = imfPatterns[pattern]!;
        final arrangement = requiredString(chosen, 'arrangement');
        if (!RegExp(r'^[MR]+$').hasMatch(arrangement) ||
            arrangement.length != maintenanceDays + rflDays ||
            'M'.allMatches(arrangement).length != maintenanceDays)
          invalid(
            'arrangement is ${maintenanceDays + rflDays} letters M and R '
            'with $maintenanceDays M ($pattern).',
          );
        final fatPerLb = decimal('fatPerLb', 0.25, 0.5);
        final adjustment = chosen.containsKey('maintenanceAdjustment')
            ? decimal('maintenanceAdjustment', -0.1, 0.1)
            : '0';
        final warnings = <String>[];
        final training = chosen['fullVolumeTrainingDays'];
        if (training != null) {
          final t = whole('fullVolumeTrainingDays', 0, 7);
          final perWeek = rflDays * 7 / arrangement.length;
          if (t >= 4 && perWeek >= 4)
            warnings.add(
              'Four or more full-volume training days a week rule out '
              'patterns with four or more RFL days a week.',
            );
        }
        return (
          dayTypes: [
            day(
              'rfl',
              'RFL day',
              {
                'energy': {'sum': true},
                'protein': {'basis': 'fat-free-mass', 'perLb': perLb},
                'carbohydrate': {'fixed': _g(grams('carbohydrate', '20'))},
                'fat': {'fixed': _g(grams('fat', '20'))},
              },
              notes:
                  'Lean protein, fibrous vegetables, EFAs and electrolytes; '
                  'low-intensity training only.',
            ),
            day('maintenance', 'Maintenance day', {
              'energy': {
                'basis': 'maintenance',
                if (adjustment != '0')
                  'factor': (Decimal.parse('1') + Decimal.parse(adjustment))
                      .toString(),
              },
              'protein': {'basis': 'fat-free-mass', 'perLb': perLb},
              'fat': {'basis': 'mass', 'perLb': fatPerLb},
              'carbohydrate': {'remainder': true},
            }, notes: 'Hard training belongs on maintenance days.'),
          ],
          cycleDays: [
            for (final c in arrangement.split(''))
              _ref(id_(c == 'M' ? 'maintenance' : 'rfl')),
          ],
          loop: true,
          sources: {
            id_('rfl'): {
              'protein':
                  'Intermittent Modified Fasting ch. 15 table: category '
                  '$category, $activity: $perLb g per lb fat-free mass',
              'carbohydrate': 'IMF ch. 15: tag-along carbohydrate about 20 g',
              'fat': 'IMF ch. 15: tag-along fat about 20 g',
              'energy': 'protein × 4 + carbohydrate × 4 + fat × 9',
            },
            id_('maintenance'): {
              'energy':
                  'maintenance by your chosen method (IMF ch. 14)'
                  '${adjustment == '0' ? '' : ' × (1 + $adjustment)'}',
              'protein': 'IMF ch. 16: the same as the RFL day ($perLb g/lb)',
              'fat': 'IMF ch. 16: $fatPerLb g per lb body mass (0.25–0.5)',
              'carbohydrate': 'IMF ch. 16: the rest of maintenance energy',
            },
          },
          schedule: {
            'category': category,
            'pattern': pattern,
            'arrangement': arrangement,
            'protein': '$perLb g per lb fat-free mass, every day',
            'maintenanceFat': '$fatPerLb g per lb body mass',
          },
          warnings: warnings,
        );
    }
  }

  /// maintenance:RFL days per cycle (IMF ch. 19–22).
  static const imfPatterns = {
    '6:1': (6, 1),
    '5:2': (5, 2),
    '4:3': (4, 3),
    '3:4': (3, 4),
    '2:5': (2, 5),
    '1:6': (1, 6),
    '3:11': (3, 11),
    '1:13': (1, 13),
  };
}

/// The four shipped programmes (F12, D22).
final List<DietProgramme> dietProgrammes = List.unmodifiable([
  const DietProgramme._(
    id: 'normal',
    name: 'Normal',
    source:
        'Moderate deficit: about 500 kcal below maintenance (D4); McDonald, '
        'The Rapid Fat Loss Handbook (2008), ch. 15 gives 10–20 %.',
    notes: 'Open-ended; breaks optional.',
    choices: {
      'deficit': '{kcal} or {percent} below maintenance (default 500 kcal)',
      'proteinPerKg': 'protein g per kg body mass (default 1.8, F6)',
    },
    recommendation: {'steps': 'none', 'training': 'none'},
  ),
  const DietProgramme._(
    id: 'rfl',
    name: 'Rapid Fat Loss',
    source: 'McDonald, The Rapid Fat Loss Handbook (2008), ch. 6–10, 14',
    notes:
        'Protein from fat-free mass by category and activity, plus fixed '
        'carbohydrate and fat (F13) and vegetables; diet length, free meals, '
        'refeeds and full breaks by category.',
    choices: {
      'activity': 'inactive, aerobic or weights (protein table column)',
      'carbohydrate': 'g per RFL day (default 20, F13)',
      'fat': 'g per RFL day, including ~10 g fish oil (default 20, F13)',
      'breakActivity':
          'sedentary, light, moderate, very or extreme (break carbohydrate)',
      'breakDays': 'full diet break, 7–14 days',
      'dietDays': 'category 1: 11–12 days before the break',
      'refeedDays': 'category 1: 2–3 refeed days at the end',
      'refeedCarbohydratePerKg':
          'category 1: refeed day 1 carbohydrate, 12–16 g per kg fat-free mass',
      'dietWeeks': 'category 2: 2–6 weeks; category 3: 6–12 weeks',
      'refeedCarbohydratePerLb':
          'category 2: weekly refeed, 1.5–3 g per lb fat-free mass (3 if lifting)',
    },
    recommendation: {
      'steps': 'optional: 20–40 min brisk walking',
      'training':
          'weights 2–3 times a week, 2–3 heavy sets of 6–8 reps (category 1: '
          '2 full-body sessions); no intervals',
    },
  ),
  const DietProgramme._(
    id: 'erfl',
    name: 'Extreme Rapid Fat Loss',
    source: 'McDonald, Extreme Rapid Fat Loss (2014), after Calbet et al. 2014',
    notes:
        'A last-resort 4-day protocol: protein only from the leanest '
        'sources, a large daily walking goal, then normal eating with '
        '10,000 steps a day.',
    choices: {
      'walking': '{steps}, {distanceKm} or {hours, speedKmh} per ERFL day',
      'carbohydrate': 'g per ERFL day (default 0)',
      'fat': 'g per ERFL day (default 0)',
      'afterDays': 'days of normal eating with 10,000 steps, 1–28',
    },
    recommendation: {
      'steps': 'the chosen walking goal for 4 days, then 10,000 a day',
      'training': 'pause training, or light lifting only if already lifting',
    },
  ),
  const DietProgramme._(
    id: 'imf',
    name: 'Intermittent Modified Fasting',
    source: 'McDonald, Intermittent Modified Fasting (2026), ch. 14–22',
    notes:
        'RFL days and maintenance days in a weekly or 14-day pattern; '
        'protein is the same every day.',
    choices: {
      'activity': 'none, aerobic or weights (protein table column)',
      'pattern':
          '6:1, 5:2, 4:3, 3:4, 2:5, 1:6 (weekly), 3:11 or 1:13 (14 days)',
      'arrangement': 'the days in order as M and R letters, e.g. MMRMMRR',
      'fatPerLb': 'maintenance-day fat, 0.25–0.5 g per lb body mass (0.38 mid)',
      'maintenanceAdjustment':
          'maintenance-day energy change, −0.1 to 0.1 (default 0)',
      'carbohydrate': 'g per RFL day (default 20)',
      'fat': 'g per RFL day (default 20)',
      'fullVolumeTrainingDays': 'per week, for the pattern warning',
    },
    recommendation: {
      'steps': 'none',
      'training':
          'hard sessions on maintenance days; volume and frequency may drop '
          'by up to ⅔ if load is held',
    },
  ),
]);

DietProgramme dietProgramme(String id) =>
    dietProgrammes.where((p) => p.id == id).firstOrNull ??
    (throw BodyTmiException('not_found', 'Programme not found: $id.'));
