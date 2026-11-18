import 'dart:math';

import 'package:bodytmi_core/bodytmi_core.dart';

import 'dispatch.dart';

/// Builds an invented demonstration profile at [database] through the
/// ordinary JSON commands: six weeks of body mass, tape measurements, a
/// looping two-day strength program with finished sessions, foods and a
/// diary, a diet run, sleep, a walk, a practice and routines. Dates are
/// relative to [now] (local time and offset), so the profile always looks
/// current. Nothing is real user data.
Future<void> buildDemoProfile(String database, {DateTime? now}) async {
  final clock = now ?? DateTime.now();
  final offset = clock.timeZoneOffset;
  final today = DateTime(clock.year, clock.month, clock.day);
  final random = Random(42);

  String two(int v) => v.toString().padLeft(2, '0');
  String date(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
  String zone() {
    final m = offset.inMinutes.abs();
    return '${offset.isNegative ? '-' : '+'}${two(m ~/ 60)}:${two(m % 60)}';
  }

  String at(int dayOffset, int hour, [int minute = 0]) {
    final d = today.add(Duration(days: dayOffset));
    return '${date(d)}T${two(hour)}:${two(minute)}:00${zone()}';
  }

  Map<String, Object?> q(String value, String unit) => {
    'value': value,
    'unit': unit,
  };

  Future<Map<String, Object?>> run(
    String command,
    Map<String, Object?> fields,
  ) async {
    try {
      return await executeCommand(command, {
        'schemaVersion': 1,
        'database': database,
        ...fields,
      });
    } on BodyTmiException catch (e) {
      throw BodyTmiException(e.code, '$command: ${e.message}');
    }
  }

  // Profile and body.
  await run('profile set', {
    'profile': {
      'sex': 'male',
      'birthDate': '1988-04-02',
      'location': {
        'latitude': '59.3293',
        'longitude': '18.0686',
        'timeZone': 'Europe/Stockholm',
      },
    },
    'expectedRevision': 0,
  });
  await run('observation record', {
    'observation': {
      'id': 'height',
      'measure': 'height',
      'date': date(today.subtract(const Duration(days: 300))),
      'value': q('181', 'cm'),
    },
  });
  for (var d = -42; d <= 0; d++) {
    if (d != 0 && random.nextInt(7) == 0) continue; // some days unweighed
    // About −0.43 kg a week with ±0.55 kg of day-to-day noise.
    final value = (86.2 - (d + 42) * 0.062 + (random.nextDouble() - 0.5) * 1.1)
        .toStringAsFixed(1);
    await run('mass record', {
      'measurement': {
        'id': 'mass-${date(today.add(Duration(days: d)))}',
        'context': 'health',
        'observedAt': at(d, 6, 58),
        'mass': q(value, 'kg'),
      },
    });
  }
  for (final (id, measure, value, ago) in [
    ('waist-1', 'waist', '92.5', 36),
    ('neck-0', 'neck', '39.5', 36),
    ('navel-0', 'navel', '93.0', 36),
    ('waist-2', 'waist', '90.0', 8),
    ('neck-1', 'neck', '39.5', 8),
    ('navel-1', 'navel', '91.0', 8),
  ]) {
    await run('observation record', {
      'observation': {
        'id': id,
        'measure': 'circumference',
        'attributes': {'site': measure},
        'date': date(today.subtract(Duration(days: ago))),
        'value': q(value, 'cm'),
      },
    });
  }

  for (var d = -6; d <= 0; d++) {
    await run('observation record', {
      'observation': {
        'id': 'steps-${date(today.add(Duration(days: d)))}',
        'measure': 'steps',
        'date': date(today.add(Duration(days: d))),
        'value': q(d == 0 ? '2140' : '${6200 + random.nextInt(5200)}', 'step'),
      },
    });
  }

  // Training: a looping upper/lower program with two finished sessions.
  Map<String, Object?> slot(
    String id,
    String exercise,
    String implementation,
    String mass,
    String reps,
  ) => {
    'id': id,
    'exercise': exercise,
    'implementation': implementation,
    'targets': {'mass': q(mass, 'kg'), 'reps': q(reps, 'rep')},
    'prefill': ['mass'],
  };
  Map<String, Object?> sets(String id, String slotId, int count) => {
    'id': id,
    'type': 'repeat',
    'count': count,
    'restBetweenSeconds': 120,
    'child': {'id': '$id-set', 'type': 'effort', 'slot': slotId},
  };
  await run('store publish', {
    'expectedRevision': 0,
    'definition': {
      'id': 'upper-a',
      'name': 'Upper A',
      'slots': [
        slot('bench', 'bench-press', 'barbell', '72.5', '3'),
        slot('pulldown', 'lat-pulldown', 'cable', '52', '10'),
        slot('row', 'one-arm-row', 'dumbbell', '22', '15'),
      ],
      'plan': {
        'id': 'workout',
        'type': 'sequence',
        'children': [
          sets('bench-sets', 'bench', 5),
          sets('pulldown-sets', 'pulldown', 3),
          sets('row-sets', 'row', 3),
        ],
      },
    },
  });
  await run('store publish', {
    'expectedRevision': 0,
    'definition': {
      'id': 'lower-a',
      'name': 'Lower A',
      'slots': [
        slot('squat', 'back-squat', 'barbell', '95', '3'),
        slot('rdl', 'romanian-deadlift', 'barbell', '70', '10'),
      ],
      'plan': {
        'id': 'workout',
        'type': 'sequence',
        'children': [
          sets('squat-sets', 'squat', 5),
          sets('rdl-sets', 'rdl', 3),
        ],
      },
    },
  });
  await run('program publish', {
    'expectedRevision': 0,
    'definition': {
      'id': 'strength',
      'name': 'Upper/Lower',
      'plan': {
        'id': 'week',
        'type': 'group',
        'children': [
          {
            'id': 'upper',
            'type': 'day',
            'label': 'Upper A',
            'templateId': 'upper-a',
            'revision': 1,
          },
          {
            'id': 'lower',
            'type': 'day',
            'label': 'Lower A',
            'templateId': 'lower-a',
            'revision': 1,
          },
        ],
      },
    },
  });
  await run('run create', {
    'id': 'strength',
    'programId': 'strength',
    'revision': 1,
    'startedAt': at(-5, 17),
    'loop': true,
  });
  for (final (n, day) in [(1, -4), (2, -2)]) {
    final runView = await run('run show', {'runId': 'strength'});
    final started = await run('run start', {
      'runId': 'strength',
      'expectedVersion': _data(runView)['contentVersion'],
      'id': 'session-$n',
      'startedAt': at(day, 17, 30),
    });
    var session =
        _data(started)['session'] as Map<String, Object?>? ?? _data(started);
    for (final set in session['sets']! as List<Object?>) {
      final id = (set! as Map<String, Object?>)['id'];
      final done = await run('store complete', {
        'id': 'session-$n',
        'expectedVersion': session['contentVersion'],
        'setId': id,
        'acceptSuggested': true,
      });
      session = _data(done);
    }
    await run('store finish', {
      'id': 'session-$n',
      'expectedVersion': session['contentVersion'],
      'finishedAt': at(day, 18, 25),
    });
  }

  // Foods, a diet run and today's diary.
  Future<void> food(String id, String name, Map<String, String> per100g) =>
      run('food publish', {
        'expectedRevision': 0,
        'food': {
          'id': id,
          'name': name,
          'source': {'kind': 'label'},
          'kind': 'base',
          'basis': '100g',
          'nutrients': {
            for (final e in per100g.entries)
              e.key: q(e.value, e.key == 'energy' ? 'kcal' : 'g'),
          },
        },
      });
  await food('cottage-cheese', 'Cottage cheese 1.5%', {
    'energy': '76',
    'protein': '12.5',
    'carbohydrate': '3',
    'fat': '1.5',
  });
  await food('egg', 'Egg', {
    'energy': '135',
    'protein': '12.5',
    'carbohydrate': '0.5',
    'fat': '9.5',
  });
  await food('chicken-breast', 'Chicken breast, grilled', {
    'energy': '113',
    'protein': '24',
    'carbohydrate': '0',
    'fat': '1.8',
  });
  // A Normal programme plan, started long enough ago to be reviewed.
  await run('energy method', {
    'from': date(today.subtract(const Duration(days: 60))),
    'method': {'formula': 'mifflin-st-jeor', 'pal': '1.55'},
    'expectedRevision': 0,
  });
  await run('plan activate', {
    'planId': 'cut',
    'programme': 'normal',
    'choices': <String, Object?>{},
    'startDate': date(today.subtract(const Duration(days: 24))),
    'asOf': at(-25, 20),
    'requestId': 'demo-plan',
  });
  for (final (id, time, meal, foodId, grams) in [
    ('breakfast-1', (7, 15), 'breakfast', 'cottage-cheese', '250'),
    ('breakfast-2', (7, 15), 'breakfast', 'egg', '110'),
    ('lunch-1', (12, 5), 'lunch', 'chicken-breast', '150'),
  ]) {
    if (DateTime(
      today.year,
      today.month,
      today.day,
      time.$1,
      time.$2,
    ).isAfter(clock)) {
      continue; // never log the future
    }
    await run('diary add', {
      'entry': {
        'id': id,
        'at': at(0, time.$1, time.$2),
        'meal': meal,
        'food': {'id': foodId},
        'amount': q(grams, 'g'),
      },
    });
  }

  // Sleep, a walk, a practice and routines.
  await run('sleep schedule', {
    'expectedRevision': 0,
    'schedule': {
      'from': date(today.subtract(const Duration(days: 30))),
      'sleepAt': '23:00',
      'wakeAt': '06:45',
    },
  });
  for (var d = -6; d <= 0; d++) {
    final onset = 8 + random.nextInt(35);
    await run('sleep record', {
      'sleep': {
        'id': 'night-${date(today.add(Duration(days: d)))}',
        'kind': 'main',
        'asleepAt': at(d - 1, 23, onset),
        'wakeAt': at(d, 6, 30 + random.nextInt(20)),
        'quality': 3 + random.nextInt(2),
      },
    });
  }
  if (DateTime(today.year, today.month, today.day, 7, 42).isAfter(clock)) {
    return _routines(run, today, date);
  }
  await run('activity record', {
    'activity': {
      'id': 'walk-today',
      'kind': 'walk',
      'start': at(0, 7, 20),
      'end': at(0, 7, 42),
      'outdoor': true,
      'steps': 2140,
      'countsToward': ['movement', 'outdoor-light'],
    },
  });
  await _routines(run, today, date);
}

Future<void> _routines(
  Future<Map<String, Object?>> Function(String, Map<String, Object?>) run,
  DateTime today,
  String Function(DateTime) date,
) async {
  await run('practice box-breathing', {
    'secondsPerSide': 4,
    'expectedRevision': 0,
  });
  for (final routine in [
    {
      'id': 'weigh-in',
      'name': 'Weigh in',
      'action': {'kind': 'observation', 'measure': 'body-mass'},
      'schedule': {
        'relative': {'anchor': 'wake', 'offsetMinutes': 15},
      },
    },
    {
      'id': 'daylight-walk',
      'name': 'Morning daylight walk',
      'action': {'kind': 'activity', 'category': 'outdoor-light'},
      'schedule': {
        'relative': {'anchor': 'wake', 'offsetMinutes': 45},
      },
    },
    {
      'id': 'breathing',
      'name': 'Box breathing',
      'action': {'kind': 'practice', 'practiceId': 'box-breathing'},
      'schedule': {'at': '07:45'},
    },
    {
      'id': 'caffeine-cutoff',
      'name': 'Last caffeine before 13:00',
      'action': {'kind': 'check'},
      'schedule': {'at': '13:00'},
    },
  ]) {
    await run('routine save', {
      'expectedVersion': 0,
      'routine': {
        ...routine,
        'from': date(today.subtract(const Duration(days: 14))),
      },
    });
  }
}

Map<String, Object?> _data(Map<String, Object?> response) =>
    jsonObject(response['data'], 'data');
