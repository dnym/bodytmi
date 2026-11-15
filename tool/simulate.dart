// Twelve-week usage simulation driving the native CLI as a black box.
//
// A beginner runs three programs at once: the r/Fitness Basic Beginner
// Routine (Mon/Wed/Fri), Couch to 5K (Tue/Thu/Sat) and Starting to Stretch
// (Sun), with Saturday weigh-ins. The gym mixes kilogram barbells with pound
// machines. Setbacks: a squat stall and deload, a forgotten micro-plate bag, a
// busy squat rack and bench station, a lb machine taken, a killed process
// during rest, a week of travel, an interrupted session, a side stitch and a
// typo corrected after acceptance.
//
// Usage: dart run tool/simulate.dart [--bin build/bodytmi] [--out DIR] [--quick]
// Writes DIR/journal.md (readable training log), DIR/observations.md (facts
// the run collected for findings) and DIR/calls.ndjson (every request and
// response). Exits non-zero when an oracle expectation fails.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

late String bin;
late String db;
late Directory out;
late IOSink calls;
final journal = StringBuffer();
final observations = <String>[];
final failures = <String>[];
var callCount = 0;
final timings = <String, List<int>>{};
var quick = false;
var weeks = 12;
var finalOnly = false;

// ---------------------------------------------------------------- CLI access

class Res {
  Res(this.code, this.data, this.error);
  final int code;
  final dynamic data;
  final String error;
  bool get ok => code == 0;
}

const pureCommands = {
  'plate plan',
  'scale resolve',
  'convention interpret',
  'archive validate',
  'backup validate',
};

Future<Res> call(String command, Map<String, Object?> fields) async {
  final request = {
    'schemaVersion': 1,
    if (!pureCommands.contains(command)) 'database': db,
    ...fields,
  };
  final watch = Stopwatch()..start();
  final process = await Process.start(bin, command.split(' '));
  final stdoutText = process.stdout.transform(utf8.decoder).join();
  final stderrText = process.stderr.transform(utf8.decoder).join();
  process.stdin.write(jsonEncode(request));
  await process.stdin.close();
  final code = await process.exitCode;
  final output = await stdoutText;
  final error = await stderrText;
  watch.stop();
  callCount++;
  timings.putIfAbsent(command, () => []).add(watch.elapsedMilliseconds);
  dynamic data;
  if (code == 0 && output.isNotEmpty) {
    data = (jsonDecode(output) as Map<String, dynamic>)['data'];
  }
  calls.writeln(
    jsonEncode({
      'n': callCount,
      'command': command,
      'request': request,
      'code': code,
      'ms': watch.elapsedMilliseconds,
      if (code == 0) 'data': data else 'error': error.trim(),
    }),
  );
  return Res(code, data, error.trim());
}

class SimFailure implements Exception {
  SimFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

Future<dynamic> ok(String command, Map<String, Object?> fields) async {
  final r = await call(command, fields);
  if (!r.ok) {
    throw SimFailure('$command failed (rc ${r.code}): ${r.error}');
  }
  return r.data;
}

void expect(bool condition, String message) {
  if (!condition) {
    failures.add(message);
    log('  - **ORACLE MISMATCH:** $message');
  }
}

void note(String text) {
  observations.add(text);
  log('  - _observation:_ $text');
}

void log(String line) {
  journal.writeln(line);
  if (!quick) stdout.writeln(line);
}

// ------------------------------------------------------------ JSON helpers

Map<String, Object?> q(String value, String unit) => {
  'value': value,
  'unit': unit,
};

String fmt(num v) {
  final s = v.toStringAsFixed(3);
  return s.contains('.')
      ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
      : s;
}

double qv(dynamic quantity) => double.parse(quantity['value'] as String);

/// Mass in kilograms from a quantity in kg or lb (canonical or entered).
double kg(dynamic quantity) {
  final v = double.parse(quantity['value'] as String);
  return switch (quantity['unit']) {
    'kg' => v,
    'g' => v / 1000,
    'lb' => v * 0.45359237,
    final u => throw SimFailure('Unexpected mass unit $u'),
  };
}

String entered(dynamic quantity) {
  final e = quantity['entered'] ?? quantity;
  return '${e['value']} ${e['unit']}';
}

// ------------------------------------------------------------ Time

final start = DateTime(2026, 9, 7); // Monday of week 1.
final dstEnd = DateTime(2026, 10, 25, 3);

DateTime at(int week, int weekday, int hour, [int minute = 0]) {
  // Calendar arithmetic, not 24 h steps: the clocks change on 25 October.
  return DateTime(
    start.year,
    start.month,
    start.day + (week - 1) * 7 + weekday - 1,
    hour,
    minute,
  );
}

String iso(DateTime local) {
  final offset = local.isBefore(dstEnd) ? '+02:00' : '+01:00';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}T'
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}$offset';
}

String day(DateTime t) =>
    '${['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][t.weekday - 1]} '
    '${t.year}-${t.month.toString().padLeft(2, '0')}-'
    '${t.day.toString().padLeft(2, '0')}';

// ------------------------------------------------------------ The person

class Person {
  double bodyMass = 84.0;
  final strength = <String, double>{
    'row': 56,
    'bench': 60,
    'squat': 78,
    'ohp': 40,
    'deadlift': 95,
    'chinup': 74,
  };
  final gain = <String, double>{
    'row': 0.8,
    'bench': 0.7,
    'squat': 1.6,
    'ohp': 0.45,
    'deadlift': 2.3,
    'chinup': 1.6,
  };

  /// Reps the person reaches on set [index] (0-based) of a 3×5+ lift.
  int reps(String lift, double load, int index, {bool amrap = false}) {
    final capacity = 30 * (strength[lift]! / load - 1) - 0.9 * index;
    final possible = capacity.floor();
    if (!amrap) return math.max(0, math.min(5, possible));
    // Stops with one rep in reserve, but always tries to reach five.
    return math.max(0, possible >= 6 ? possible - 1 : possible);
  }

  void train(String lift, {double factor = 1}) =>
      strength[lift] = strength[lift]! + gain[lift]! * factor;
}

final person = Person();
const lbToKg = 0.45359237;

// ------------------------------------------------------------ Definitions

Map<String, Object?> barSlot(String id, String exercise) => {
  'id': id,
  'exercise': exercise,
  'implementation': 'barbell',
  'equipment': 'barbell',
  'targets': {'load': q('20', 'kg'), 'reps': q('5', 'rep')},
};

Map<String, Object?> chinSlot() => {
  'id': 'chinup',
  'exercise': 'chin-up',
  'implementation': 'assisted-machine',
  'equipment': 'assist-machine',
  'setupNote': 'Knee pad; assistance on the selector pin.',
  'targets': {'assistance': q('60', 'lb'), 'reps': q('5', 'rep')},
  'bodyMass': {'context': 'health'},
  'effectiveMass': {
    'id': 'assisted-chin',
    'version': 1,
    'bodyMassFraction': '1',
    'addedMass': {'mass': q('0', 'kg')},
    'assistance': {'metric': 'assistance', 'multiplier': '1'},
  },
};

List<Map<String, Object?>> liftBlock(
  String slot, {
  required int restSeconds,
  bool last = false,
}) => [
  {
    'id': slot,
    'type': 'sequence',
    'children': [
      {'id': '$slot-1', 'type': 'effort', 'slot': slot},
      {'id': '$slot-r1', 'type': 'rest', 'durationSeconds': restSeconds},
      {'id': '$slot-2', 'type': 'effort', 'slot': slot},
      {'id': '$slot-r2', 'type': 'rest', 'durationSeconds': restSeconds},
      {
        'id': '$slot-3',
        'type': 'effort',
        'slot': slot,
        'objectives': {
          'reps': {'mode': 'maxEffort', 'unit': 'rep'},
        },
      },
    ],
  },
  if (!last) {'id': '$slot-next', 'type': 'rest', 'manual': true},
];

Map<String, Object?> workoutA({String id = 'bbr-a', int rest = 120}) => {
  'id': id,
  'name': 'BBR Workout A',
  'slots': [
    barSlot('row', 'barbell-row'),
    barSlot('bench', 'bench-press'),
    barSlot('squat', 'back-squat'),
  ],
  'plan': {
    'id': 'a',
    'type': 'sequence',
    'children': [
      ...liftBlock('row', restSeconds: rest),
      ...liftBlock('bench', restSeconds: rest),
      ...liftBlock('squat', restSeconds: rest, last: true),
    ],
  },
};

Map<String, Object?> workoutB({Map<String, Object?>? chin}) => {
  'id': 'bbr-b',
  'name': 'BBR Workout B',
  'slots': [
    chin ?? chinSlot(),
    barSlot('ohp', 'overhead-press'),
    barSlot('deadlift', 'deadlift'),
  ],
  'plan': {
    'id': 'b',
    'type': 'sequence',
    'children': [
      ...liftBlock('chinup', restSeconds: 120),
      ...liftBlock('ohp', restSeconds: 120),
      ...liftBlock('deadlift', restSeconds: 120, last: true),
    ],
  },
};

const upper = {'row', 'bench', 'ohp'};

Map<String, Object?> barRule(String lift) {
  final lower = !upper.contains(lift);
  return {
    'metric': 'reps',
    'performance': {
      'direction': 'higher',
      'failureLimit': q('15', 'rep'),
      'advancementLimit': q('15', 'rep'),
    },
    'aggregation': {'mode': 'total'},
    'failureAggregation': {'mode': 'total'},
    'increments': {'load': q(lower ? '2' : '1', 'kg')},
    'deloadAfter': 1,
    'deloadMetrics': ['load'],
    'deloadPercent': '10',
    'incrementBands': {
      'aggregation': {'mode': 'last'},
      'bands': [
        {
          'id': 'amrap-over-10',
          'threshold': q('11', 'rep'),
          'increments': {'load': q(lower ? '4' : '2', 'kg')},
        },
      ],
    },
    // Round to the totals the bound bar's declared plates can make.
    'scales': {
      'load': {
        'instance': true,
        'rounding': 'nearest',
        'deloadRounding': 'atMost',
      },
    },
  };
}

Map<String, Object?> chinRule() => {
  'metric': 'reps',
  'performance': {
    'direction': 'higher',
    'failureLimit': q('15', 'rep'),
    'advancementLimit': q('15', 'rep'),
  },
  'aggregation': {'mode': 'total'},
  'failureAggregation': {'mode': 'total'},
  'increments': {'assistance': q('5', 'lb')},
  'directions': {'assistance': 'decrease'},
  'minimums': {'assistance': q('10', 'lb')},
  'deloadAfter': 1,
  'deloadMetrics': ['assistance'],
  'deloadPercent': '10',
  'incrementBands': {
    'aggregation': {'mode': 'last'},
    'bands': [
      {
        'id': 'amrap-over-10',
        'threshold': q('11', 'rep'),
        'increments': {'assistance': q('10', 'lb')},
      },
    ],
  },
  // Round to the bound machine's selector markings.
  'scales': {
    'assistance': {
      'instance': true,
      'rounding': 'nearest',
      'deloadRounding': 'nearest',
    },
  },
};

// Couch to 5K: (run, walk) seconds per day, exactly as the source tables.
List<List<int>> c25kDay(int week, int dayInWeek) {
  List<List<int>> times(int n, List<int> pair) => List.filled(n, pair);
  switch (week) {
    case 1:
      return times(8, [60, 90]);
    case 2:
      return times(6, [90, 120]);
    case 3:
      return times(2, [90, 90])
          .expand(
            (p) => [
              p,
              const [180, 180],
            ],
          )
          .toList();
    case 4:
      return const [
        [180, 90],
        [300, 150],
        [180, 90],
        [300, 0],
      ];
    case 5:
      return [
        const [
          [300, 180],
          [300, 180],
          [300, 0],
        ],
        const [
          [480, 300],
          [480, 0],
        ],
        const [
          [1200, 0],
        ],
      ][dayInWeek];
    case 6:
      return [
        const [
          [300, 180],
          [480, 180],
          [300, 0],
        ],
        const [
          [600, 180],
          [600, 0],
        ],
        const [
          [1500, 0],
        ],
      ][dayInWeek];
    case 7:
      return const [
        [1500, 0],
      ];
    case 8:
      return const [
        [1680, 0],
      ];
    default:
      return const [
        [1800, 0],
      ];
  }
}

String c25kTemplate(int week, int dayInWeek) =>
    week == 5 || week == 6 ? 'c25k-w$week-d${dayInWeek + 1}' : 'c25k-w$week';

Map<String, Object?> c25kWorkout(int week, int dayInWeek) {
  final intervals = c25kDay(week, dayInWeek);
  final durations = {for (final i in intervals) i[0]}.toList()..sort();
  return {
    'id': c25kTemplate(week, dayInWeek),
    'name':
        'C25K week $week${week == 5 || week == 6 ? ' day ${dayInWeek + 1}' : ''}',
    'slots': [
      for (final d in durations)
        {
          'id': 'run-$d',
          'exercise': 'running',
          'implementation': 'outdoors',
          'targets': {'duration': q('$d', 's')},
          'timing': {'metric': 'duration'},
        },
    ],
    'plan': {
      'id': 'c25k',
      'type': 'sequence',
      'children': [
        for (var i = 0; i < intervals.length; i++) ...[
          {'id': 'run$i', 'type': 'effort', 'slot': 'run-${intervals[i][0]}'},
          if (intervals[i][1] > 0)
            {
              'id': 'walk$i',
              'type': 'rest',
              'durationSeconds': intervals[i][1],
            },
        ],
      ],
    },
  };
}

const stretches = [
  ('shoulder-backbend', 'upper', false),
  ('spine-backbend', 'upper', false),
  ('rear-hand-clasp', 'upper', true),
  ('lying-cross', 'upper', true),
  ('wrist-biceps', 'upper', true),
  ('one-leg-pike', 'lower', true),
  ('kneeling-lunge', 'lower', true),
  ('pancake', 'lower', false),
  ('butterfly', 'lower', false),
  ('calf-stretch', 'lower', true),
];

Map<String, Object?> stretchWorkout({String pikeSupport = 'chair'}) {
  List<Map<String, Object?>> protocol(String stretch, String? side) {
    final suffix = side == null ? '' : '-$side';
    return [
      for (final (i, hold) in const [10, 20, 30].indexed) ...[
        {
          'id': '$stretch$suffix-bump${i + 1}',
          'type': 'effort',
          'slot': '$stretch-bumps',
          'side': ?side,
        },
        {
          'id': '$stretch$suffix-hold$hold',
          'type': 'effort',
          'slot': '$stretch-hold',
          'side': ?side,
          'targets': {'duration': q('$hold', 's')},
        },
      ],
    ];
  }

  return {
    'id': 'starting-to-stretch',
    'name': 'Starting To Stretch',
    'slots': [
      for (final (s, _, _) in stretches) ...[
        {
          'id': '$s-bumps',
          'exercise': s,
          'implementation': 'bumping',
          'targets': {'reps': q('10', 'rep')},
          if (s == 'one-leg-pike') 'setupNote': 'Support: $pikeSupport',
        },
        {
          'id': '$s-hold',
          'exercise': s,
          'implementation': 'static-hold',
          'targets': {'duration': q('10', 's')},
          'timing': {'metric': 'duration'},
          if (s == 'one-leg-pike') 'setupNote': 'Support: $pikeSupport',
        },
      ],
    ],
    'plan': {
      'id': 'sts',
      'type': 'sequence',
      'children': [
        for (final (s, _, sided) in stretches)
          {
            'id': s,
            'type': 'sequence',
            'children': sided
                ? [...protocol(s, 'left'), ...protocol(s, 'right')]
                : protocol(s, null),
          },
      ],
    },
  };
}

// ------------------------------------------------------------ Execution

/// What the person does at one effort occurrence.
sealed class Act {}

class Complete extends Act {
  Complete(this.actuals);
  final Map<String, Object?> actuals;
}

class Timed extends Act {
  Timed(this.milliseconds);
  final int milliseconds;
}

class Skip extends Act {}

class Abandon extends Act {}

class Walk {
  Walk(this.exId, this.sessionId);
  final String exId;
  final String sessionId;
  late dynamic view;
  var step = 0;
  var loggedAhead = 0;
  late DateTime now;

  Map<String, Object?> request() => {
    'id': exId,
    'expectedVersion': view['version'],
    'expectedSessionVersion': view['sessionContentVersion'],
    'requestId': 'r${step++}',
    'at': iso(now),
  };

  Future<void> begin(DateTime t) async {
    now = t;
    view = await ok('execution start', {
      'id': exId,
      'sessionId': sessionId,
      'at': iso(now),
    });
  }

  Future<void> refresh() async {
    view = await ok('execution show', {'id': exId});
  }

  /// Runs a timer [ms] long with explicit samples, ending in its expiry.
  Future<dynamic> runClock(
    String timerId,
    int ms, {
    String owner = 'app',
  }) async {
    var timer = await ok('timer show', {'id': timerId});
    timer = await ok('timer resume', {
      'id': timerId,
      'expectedVersion': timer['version'],
      'ownerId': owner,
      'at': iso(now),
    });
    now = now.add(Duration(milliseconds: ms));
    final advanced = await ok('timer advance', {
      'id': timerId,
      'expectedVersion': timer['version'],
      'ownerId': owner,
      'elapsedMilliseconds': ms,
      'at': iso(now),
    });
    return advanced['timer'];
  }

  /// Walks until completion or until [act] returns [Abandon].
  Future<bool> walk(
    Future<Act> Function(dynamic current) act, {
    int Function(dynamic current)? restMs,
    Future<bool> Function(dynamic current)? beforeOccurrence,
  }) async {
    while (view['status'] != 'completed') {
      final current = view['current'];
      if (beforeOccurrence != null) {
        if (await beforeOccurrence(current)) return false;
        if (view['status'] == 'completed') break;
      }
      final c = view['current'];
      if (c['kind'] == 'rest') {
        final activity = c['activity'];
        if (activity['manual'] == true) {
          now = now.add(const Duration(minutes: 3));
          view = await ok('execution advance', request());
          continue;
        }
        final planned = (activity['durationSeconds'] as int) * 1000;
        final taken = restMs?.call(c) ?? planned;
        if (taken < planned) {
          now = now.add(Duration(milliseconds: taken));
          view = await ok('execution skip', {...request(), 'confirm': true});
          continue;
        }
        await runClock(view['timer']['id'] as String, taken);
        view = await ok('execution advance', request());
        continue;
      }
      if (c['set']['status'] != 'planned') {
        // Logged ahead of the cursor: acknowledge, do not log it again.
        loggedAhead++;
        view = await ok('execution advance', request());
        continue;
      }
      final a = await act(c);
      switch (a) {
        case Abandon():
          return false;
        case Skip():
          view = await ok('execution skip', {...request(), 'confirm': true});
        case Complete(:final actuals):
          now = now.add(const Duration(seconds: 40));
          view = await ok('execution complete', {
            ...request(),
            'actuals': actuals,
          });
        case Timed(:final milliseconds):
          if (view['timer'] == null || view['timer']['phase'] != 'effort') {
            await ok('execution time', {
              'id': exId,
              'expectedVersion': view['version'],
              'at': iso(now),
            });
            await refresh();
          }
          final timer = await runClock(
            view['timer']['id'] as String,
            milliseconds,
          );
          view = await ok('execution confirm', {
            ...request(),
            'timerId': timer['id'],
            'timerVersion': timer['version'],
            'acceptSuggested': true,
          });
      }
    }
    return true;
  }
}

// ------------------------------------------------------------ Runs

Future<dynamic> runShow(String runId) async => ok('run show', {'runId': runId});

Future<dynamic> startRun(
  String runId,
  String sessionId,
  DateTime t, {
  Map<String, Object?> extra = const {},
}) async {
  final run = await runShow(runId);
  return ok('run start', {
    'runId': runId,
    'expectedVersion': run['contentVersion'],
    'id': sessionId,
    'startedAt': iso(t),
    ...extra,
  });
}

dynamic sessionOf(dynamic started) => started['session'] ?? started;

Future<void> finish(String sessionId, DateTime t) async {
  final s = await ok('store show', {'id': sessionId});
  await ok('store finish', {
    'id': sessionId,
    'expectedVersion': s['contentVersion'],
    'finishedAt': iso(t),
  });
}

// ------------------------------------------------------------ BBR

/// Independent oracle for the BBR rules as configured (kg adaptation).
({String outcome, double? next}) bbrOracle(
  String lift,
  double current,
  List<int> reps,
) {
  final total = reps.fold<int>(0, (a, b) => a + b);
  if (lift == 'chinup' && !chinGraduated) {
    if (total < 15) {
      final up = current * 1.1;
      // Nearest 5 lb tick.
      return (outcome: 'deload', next: math.min(100, (up / 5).round() * 5));
    }
    final step = reps.last >= 11 ? 10 : 5;
    final next = current - step;
    return next < 10
        ? (outcome: 'blocked', next: current)
        : (outcome: 'advance', next: next);
  }
  if (total < 15) {
    // The largest total the bar can load (0.5 kg steps with the micro
    // plates) at or below 90 %.
    final next = (current * 0.9 / 0.5).floorToDouble() * 0.5;
    // A deload that cannot move (0 kg added load) holds as blocked.
    return next == current
        ? (outcome: 'blocked', next: current)
        : (outcome: 'deload', next: next);
  }
  final lower = !upper.contains(lift) && lift != 'chinup';
  final step = reps.last >= 11 ? (lower ? 4 : 2) : (lower ? 2 : 1);
  return (outcome: 'advance', next: current + step);
}

const startingLoads = {
  'row': '40',
  'bench': '45',
  'squat': '60',
  'ohp': '30',
  'deadlift': '70',
};

var bbrCount = 0;
final pendingDecisions = <String>[];

class LiftDay {
  LiftDay(this.week, this.weekday);
  final int week;
  final int weekday;
  final notes = <String>[];
  bool forgotMicroPlates = false;
  bool rackBusy = false;
  bool benchBusy = false;
  bool lbMachineBusy = false;
  bool killDuringRest = false;
  bool phoneCall = false;
  bool declineBench = false;
  bool typoSquat = false;
  bool firstTime = false;
  double decay = 1;
}

String metricOf(String slot) =>
    slot == 'chinup' && !chinGraduated ? 'assistance' : 'load';
String unitOf(String slot) => slot == 'chinup' ? 'lb' : 'kg';

Future<void> bbrSession(LiftDay d) async {
  bbrCount++;
  final id = 'bbr-${bbrCount.toString().padLeft(2, '0')}';
  var t = at(d.week, d.weekday, 18);
  final bindings = <String, Object?>{
    'row': 'main-bar',
    'bench': 'main-bar',
    'squat': 'main-bar',
    'ohp': 'main-bar',
    'deadlift': 'main-bar',
    'chinup': 'assist-lb',
  };
  final runBefore = await runShow('bbr');
  final dayLabel = runBefore['current']?['day']?['label'] ?? '?';
  final daySlots = dayLabel == 'A'
      ? const {'row', 'bench', 'squat'}
      : const {'chinup', 'ohp', 'deadlift'};
  bindings.removeWhere((k, _) => !daySlots.contains(k));
  bool take(String event, Set<String> needs) {
    if (!pendingEvents.contains(event) || !needs.every(daySlots.contains)) {
      return false;
    }
    pendingEvents.remove(event);
    return true;
  }

  d.rackBusy = take('rackBusy', {'bench'});
  d.forgotMicroPlates = take('microPlates', {'bench'});
  d.killDuringRest = take('killDuringRest', {});
  d.lbMachineBusy = take('lbMachineBusy', {'chinup'});
  d.benchBusy = take('benchBusy', {'bench'});
  d.declineBench = take('declineBench', {'bench'});
  d.phoneCall = take('phoneCall', {'deadlift'});
  d.typoSquat = take('typoSquat', {'squat'});
  final fixTypo = !d.typoSquat && take('typoFix', {'squat'});
  if (take('graduateChin', {'chinup'}))
    await graduateChin(at(d.week, d.weekday, 17));
  if (d.rackBusy) {
    d.notes.add('Bench station busy at the start; the squat rack is free.');
  }
  if (d.lbMachineBusy) {
    d.notes.add(
      'The lb assisted chin-up machine is taken; using the kg one instead.',
    );
  }
  if (d.benchBusy) {
    d.notes.add('Every bench is taken; dumbbell bench on a step instead.');
  }
  if (chinGraduated) bindings.remove('chinup');
  var started = await startRun('bbr', id, t, extra: {'loadBindings': bindings});
  // Only bind slots the day actually has.
  var session = sessionOf(started);
  final slots = <String>[
    for (final s in session['sets'] as List) s['slot'] as String,
  ].toSet().toList();
  log('');
  log(
    '### ${day(t)} — BBR ${dayLabel == '?' ? slots.join('/') : dayLabel} ($id)',
  );
  for (final n in d.notes) {
    log('  - $n');
  }

  // Lost response on start: the retry must return the same session.
  if (bbrCount == 2) {
    final run = await runShow('bbr');
    final retry = await call('run start', {
      'runId': 'bbr',
      'expectedVersion': (run['contentVersion'] as int) - 1,
      'id': id,
      'startedAt': iso(t),
      'loadBindings': bindings,
    });
    note(
      'Retried `run start` after a lost response: rc ${retry.code}'
      '${retry.ok ? ', same session ${sessionOf(retry.data)['id'] == id}' : ': ${retry.error}'}.',
    );
  }

  // First exposure: find the starting weight, edit the planned work sets.
  if (d.firstTime) {
    for (final slot in slots) {
      if (slot == 'chinup') continue;
      final first = (session['sets'] as List).firstWhere(
        (s) => s['slot'] == slot,
      );
      final edited = await ok('store edit-target', {
        'id': id,
        'expectedVersion': session['contentVersion'],
        'setId': first['id'],
        'metric': 'load',
        'value': q(startingLoads[slot]!, 'kg'),
        'applyToRemaining': true,
      });
      session = edited['session'] ?? edited;
    }
    log(
      '  - Ramped up from the empty bar to find starting weights and edited '
      'the planned work sets (${[for (final s in slots)
        if (s != 'chinup') '$s ${startingLoads[s]} kg'].join(', ')}).',
    );
  }

  if (fixTypo) {
    final squat = (session['sets'] as List).firstWhere(
      (s) => s['slot'] == 'squat',
    );
    final wrong = qv(squat['suggested']['load']);
    final right = typoCorrectNext!;
    final edited = await call('store edit-target', {
      'id': id,
      'expectedVersion': session['contentVersion'],
      'setId': squat['id'],
      'metric': 'load',
      'value': q(fmt(right), 'kg'),
      'applyToRemaining': true,
    });
    log(
      '  - The squat target is ${fmt(wrong)} kg because of the typo bonus; '
      'edited the planned sets to ${fmt(right)} kg: rc ${edited.code}'
      '${edited.ok ? '' : ' (${edited.error})'}.',
    );
    if (edited.ok) session = edited.data['session'] ?? edited.data;
  }
  // Every barbell target should be exactly loadable on the bar used.
  for (final slot in slots) {
    if (slot == 'chinup') continue;
    final target = (session['sets'] as List).firstWhere(
      (x) => x['slot'] == slot,
    )['suggested']['load'];
    final plan = await ok('store plate-plan', {
      'instanceId': 'main-bar',
      'target': {'value': target['value'], 'unit': target['unit']},
    });
    final status = (plan['plan'] ?? plan)['status'];
    if (status != 'exact') {
      note(
        '$id $slot target ${entered(target)} is not exactly loadable on '
        'main-bar (plate plan: $status).',
      );
    }
  }
  var benchSubstituted = false;
  dynamic kgSetting;
  dynamic microSetting;
  final planned = <String, String>{};
  for (final s in session['sets'] as List) {
    final m = metricOf(s['slot'] as String);
    planned[s['slot'] as String] = entered(s['suggested'][m]);
  }
  for (final slot in slots) {
    person.strength[slot] = person.strength[slot]! * d.decay;
  }

  if (d.benchBusy) {
    final s = await ok('store show', {'id': id});
    final sub = await call('store substitute', {
      'id': id,
      'expectedVersion': s['contentVersion'],
      'slotId': 'bench',
      'scope': 'remaining',
      'composition': {
        'exercise': 'bench-press',
        'implementation': 'dumbbell',
        'equipment': 'dumbbells',
      },
      'targets': {
        'load': {'source': 'explicit', 'value': q('60', 'lb')},
        'reps': {'source': 'keep'},
      },
    });
    log(
      '  - Substituted dumbbell bench (2 × 30 lb, entered as 60 lb) for '
      'the bench sets before starting traversal: rc ${sub.code}'
      '${sub.ok ? '' : ' (${sub.error})'}.',
    );
    if (sub.ok) benchSubstituted = true;
  }
  final ex = Walk('ex-$id', id);
  await ex.begin(t);
  final done = <String, List<int>>{};
  final interruptedSet = <String>{};
  var killed = false;
  var abandoned = false;

  double loadKg(dynamic set) {
    final slot = set['slot'] as String;
    if (slot == 'chinup' && chinGraduated) {
      return person.bodyMass + kg(set['suggested']['load']);
    }
    if (slot == 'chinup') {
      final assist = kg(set['suggested']['assistance']);
      return person.bodyMass - assist;
    }
    return qv(set['suggested']['load']);
  }

  Future<Act> act(dynamic current) async {
    final set = current['set'];
    final slot = set['slot'] as String;
    final ordinal = set['ordinal'] as int;
    final amrap = ordinal == 2;
    var load = loadKg(set);
    final m = metricOf(slot);
    var actualControlled = set['suggested'][m];
    if (d.forgotMicroPlates && slot == 'bench') {
      final target = set['suggested']['load'];
      if (ordinal == 0) {
        // The micro plates are at home: say so, and get the setting to use.
        final shown = await ok('store show', {'id': id});
        final marked = await ok('store perform-on', {
          'id': id,
          'expectedVersion': shown['contentVersion'],
          'setId': set['id'],
          'instanceId': 'main-bar',
          'unavailablePlates': [
            {'mass': q('0.5', 'kg'), 'count': 4},
            {'mass': q('0.25', 'kg'), 'count': 4},
          ],
          'applyToRemaining': true,
        });
        microSetting = (marked['settings'] as List).firstWhere(
          (x) => x['metric'] == 'load',
        )['settings'][0];
        log(
          '  - Forgot the micro-plate bag: `store perform-on main-bar` with '
          'the 0.5 and 0.25 kg plates unavailable says to load '
          '${entered(microSetting)} for ${entered(target)}.',
        );
        await ex.refresh();
        // The stack actually used, from the planner without micro plates.
        final plan = await ok('plate plan', {
          'loading': microlessLoading(),
          'target': {
            'value': microSetting['value'],
            'unit': microSetting['unit'],
          },
        });
        final exact = (plan['arrangements'] as List).firstWhere(
          (a) => a['relation'] == 'exact',
        );
        usedPlates = [
          for (final plate in exact['sides'][0]['plates'] as List)
            {
              'mass': {
                'value': plate['mass']['value'],
                'unit': plate['mass']['unit'],
              },
              'count': (plate['count'] as int) * 2,
            },
        ];
      }
      actualControlled = microSetting;
      load = qv(microSetting);
    }
    if (d.lbMachineBusy && slot == 'chinup') {
      if (ordinal == 0) {
        // At the machine: record that the chin-ups happen on the kg one.
        final shown = await ok('store show', {'id': id});
        final marked = await ok('store perform-on', {
          'id': id,
          'expectedVersion': shown['contentVersion'],
          'setId': set['id'],
          'instanceId': 'assist-kg',
          'applyToRemaining': true,
        });
        kgSetting = (marked['settings'] as List).firstWhere(
          (x) => x['metric'] == 'assistance',
        )['settings'][0];
        log(
          '  - `store perform-on assist-kg` for the chin-up sets: follow '
          '${entered(set['suggested']['assistance'])} with '
          '${entered(kgSetting)} on the kg stack.',
        );
        await ex.refresh();
      }
      actualControlled = kgSetting;
      load = person.bodyMass - kg(kgSetting);
    }
    if (benchSubstituted && slot == 'bench') {
      // Dumbbells: two 30 lb bells, entered as the pair total.
      load = kg(set['suggested']['load']) / 0.6;
      actualControlled = set['suggested']['load'];
    }
    var r = person.reps(slot, load, ordinal, amrap: amrap);
    if (d.typoSquat && slot == 'squat' && amrap) {
      log('  - Typed ${r}5 instead of $r on the squat AMRAP set.');
      typoTrueReps = r;
      r = int.parse('${r}5');
    }
    if (d.phoneCall && slot == 'deadlift' && ordinal == 1) {
      log('  - Phone rang during deadlift set 2: racked it after 3 reps.');
      interruptedSet.add(set['id'] as String);
      done.putIfAbsent(slot, () => []).add(3);
      return Complete({
        'load': {'value': actualControlled['value'], 'unit': 'kg'},
        'reps': q('3', 'rep'),
      });
    }
    done.putIfAbsent(slot, () => []).add(r);
    return Complete({
      m: {
        'value': (actualControlled['entered'] ?? actualControlled)['value'],
        'unit': (actualControlled['entered'] ?? actualControlled)['unit'],
      },
      'reps': q('$r', 'rep'),
    });
  }

  var restIndex = 0;
  Future<void> before(dynamic current) async {
    final cid = current['id'] as String;
    if (d.killDuringRest && current['kind'] == 'rest' && !killed) {
      killed = true;
      final timerId = ex.view['timer']['id'] as String;
      var timer = await ok('timer show', {'id': timerId});
      timer = await ok('timer resume', {
        'id': timerId,
        'expectedVersion': timer['version'],
        'ownerId': 'app-1',
        'at': iso(ex.now),
      });
      final mid = await ok('timer advance', {
        'id': timerId,
        'expectedVersion': timer['version'],
        'ownerId': 'app-1',
        'elapsedMilliseconds': 45000,
        'at': iso(ex.now.add(const Duration(seconds: 45))),
      });
      ex.now = ex.now.add(const Duration(seconds: 70));
      final steal = await call('timer resume', {
        'id': timerId,
        'expectedVersion': mid['timer']['version'],
        'ownerId': 'app-2',
        'at': iso(ex.now),
      });
      final shown = await ok('timer show', {'id': timerId});
      final recovered = await ok('timer recover', {
        'id': timerId,
        'expectedVersion': shown['version'],
        'mode': 'adjust',
        'adjustmentMilliseconds': 25000,
        'at': iso(ex.now),
      });
      log(
        '  - Phone died 45 s into a rest. The restarted app could not take '
        'over the running clock (rc ${steal.code}); recovered it with a '
        '25 s adjustment (${recovered['elapsedMilliseconds'] ?? recovered['timer']?['elapsedMilliseconds']} ms elapsed).',
      );
      await ex.runClock(timerId, 50000, owner: 'app-2');
      ex.view = await ok('execution advance', ex.request());
    }
    if (d.rackBusy && cid.endsWith('/bench-1') && ex.view['cursor'] != null) {
      // The squat rack is free while the bench is busy: try squats first.
      final squat = (session['sets'] as List).firstWhere(
        (s) => s['slot'] == 'squat',
      );
      final s = await ok('store show', {'id': id});
      final attempt = await call('store complete', {
        'id': id,
        'expectedVersion': s['contentVersion'],
        'setId': squat['id'],
        'actuals': {
          'load': {'value': squat['suggested']['load']['value'], 'unit': 'kg'},
          'reps': q('5', 'rep'),
        },
      });
      log(
        '  - Logged squat set 1 first, out of order, during the guided '
        'workout: rc ${attempt.code}${attempt.ok ? '' : ' (${attempt.error})'}.',
      );
      if (attempt.ok) {
        done.putIfAbsent('squat', () => []).add(5);
        await ex.refresh();
      }
      d.rackBusy = false;
    }
    if (d.phoneCall &&
        current['kind'] == 'rest' &&
        cid.endsWith('deadlift-r2')) {
      abandoned = true;
    }
  }

  int restMs(dynamic current) {
    restIndex++;
    // Rests 2–3 minutes depending on how the set felt.
    return 120000 + (restIndex * 17000) % 60000;
  }

  final stillGoing = await ex.walk(
    (c) async => abandoned ? Abandon() : act(c),
    restMs: restMs,
    beforeOccurrence: (c) async {
      await before(c);
      return abandoned;
    },
  );
  if (abandoned || !stillGoing) {
    log('  - Left the gym; the deadlift rest clock is still pending.');
    pendingInterruption = (id, ex, t);
    return;
  }
  if (ex.loggedAhead > 0) {
    log(
      '  - When the guide reached the squat, it acknowledged the '
      '${ex.loggedAhead} set(s) already logged with `execution advance`.',
    );
  }
  t = ex.now.add(const Duration(minutes: 5));
  if (interruptedSet.isNotEmpty) {
    for (final setId in interruptedSet) {
      final s = await ok('store show', {'id': id});
      await ok('store annotate', {
        'id': id,
        'expectedVersion': s['contentVersion'],
        'setId': setId,
        'observations': {
          'terminationReason': 'interrupted',
          'notes': 'Phone call',
        },
      });
    }
  }
  if (d.forgotMicroPlates) {
    final s = await ok('store show', {'id': id});
    final bench = (s['sets'] as List).firstWhere((x) => x['slot'] == 'bench');
    final arr = await call('store arrange', {
      'id': id,
      'expectedVersion': s['contentVersion'],
      'setId': bench['id'],
      'arrangement': {
        'instanceId': 'main-bar',
        'channel': 'barbell',
        'plates': usedPlates,
      },
    });
    note(
      'Recording the plate stack actually used on bench set 1: rc ${arr.code}'
      '${arr.ok ? '' : ' (${arr.error})'}.',
    );
  }
  await finish(id, t);
  await resolveProgression(id, d, slots, done, planned, t);
}

(String, Walk, DateTime)? pendingInterruption;
String? chinBinding;
final pendingEvents = <String>{};
double? typoCorrectNext;
int? typoTrueReps;
var chinGraduated = false;
List<Map<String, Object?>> usedPlates = const [];

Map<String, Object?> microlessLoading() => {
  'components': [
    {'id': 'bar', 'kind': 'bar', 'mass': q('20', 'kg')},
  ],
  'channel': {'id': 'barbell', 'sides': 2, 'symmetry': 'required'},
  'plates': [
    {'mass': q('20', 'kg'), 'count': 6},
    {'mass': q('10', 'kg'), 'count': 4},
    {'mass': q('5', 'kg'), 'count': 4},
    {'mass': q('2.5', 'kg'), 'count': 4},
    {'mass': q('1.25', 'kg'), 'count': 4},
  ],
};

Map<String, Object?> barLoading() => {
  ...microlessLoading(),
  'plates': [
    ...(microlessLoading()['plates'] as List),
    {'mass': q('0.5', 'kg'), 'count': 4},
    {'mass': q('0.25', 'kg'), 'count': 4},
  ],
};

final ruleOverride = <String, Map<String, Object?>>{};

Future<void> resolveProgression(
  String id,
  LiftDay d,
  List<String> slots,
  Map<String, List<int>> done,
  Map<String, String> planned,
  DateTime t,
) async {
  for (final slot in slots) {
    final rule =
        ruleOverride[slot] ?? (slot == 'chinup' ? chinRule() : barRule(slot));
    var res = await call('progression propose', {
      'sessionId': id,
      'slotId': slot,
      'ruleType': 'threshold',
      'rule': rule,
    });
    final reps = done[slot] ?? const [];
    final line = '  - ${slot.padRight(8)} ${planned[slot]} × ${reps.join('/')}';
    if (!res.ok && res.error.contains('needs explicit reconciliation')) {
      final shown = await ok('store show', {'id': id});
      final templateId = shown['revision']['definition']['id'];
      final revision = shown['revision']['revision'];
      final status = await ok('progression reconcile-status', {
        'templateId': templateId,
        'revision': revision,
        'slotId': slot,
        'runId': 'bbr',
        'asOf': iso(t),
        'sessionId': id,
        'rule': rule,
        'ruleType': 'threshold',
      });
      final reconciled = await call('progression reconcile', {
        'id': 'reconcile-$id-$slot',
        'templateId': templateId,
        'revision': revision,
        'slotId': slot,
        'runId': 'bbr',
        'sessionId': id,
        'expectedSequence': status['track']?['sequence'],
        'kinds': status['blockerKinds'],
        'reconciledAt': iso(t),
        'rule': rule,
        'ruleType': 'threshold',
        'confirm': true,
      });
      final again = await call('progression propose', {
        'sessionId': id,
        'slotId': slot,
        'ruleType': 'threshold',
        'rule': rule,
      });
      note(
        'The manual fix of the typo-inflated squat target blocked '
        '`progression propose` (${status['blockerKinds']}); '
        '`progression reconcile` with the session gave rc ${reconciled.code}'
        '${reconciled.ok ? '' : ' (${reconciled.error})'}, re-propose rc '
        '${again.code}${again.ok ? '' : ' (${again.error})'}.',
      );
      res = again;
    }
    if (!res.ok) {
      log('$line → propose failed: ${res.error}');
      note('`progression propose` for $slot in $id failed: ${res.error}');
      continue;
    }
    final decision = res.data['decision'] ?? res.data;
    final proposal = decision['proposal'];
    final outcome = proposal['outcome'] as String;
    final nextSets = proposal['nextSets'] as List? ?? const [];
    String? next;
    if (nextSets.isNotEmpty) {
      final first = nextSets.first;
      final values = first['values'] ?? first['targets'] ?? first;
      final v = values[metricOf(slot)];
      if (v != null) next = entered(v);
    }
    // Oracle.
    if (reps.length == 3 && !d.phoneCall ||
        reps.length == 3 && slot != 'bench' && slot != 'deadlift') {
      final current = double.parse(planned[slot]!.split(' ').first);
      final o = bbrOracle(slot, current, reps);
      if (d.lbMachineBusy && slot == 'chinup') {
        // The kg setting follows the lb target, so the normal rule applies.
        final o = bbrOracle(
          slot,
          double.parse(planned[slot]!.split(' ').first),
          reps,
        );
        expect(
          outcome == o.outcome,
          '$id chinup on the kg machine: oracle ${o.outcome}, app $outcome',
        );
      } else if (!(d.typoSquat && slot == 'squat')) {
        expect(
          outcome == o.outcome ||
              (o.outcome == 'blocked' && outcome == 'blocked'),
          '$id $slot: oracle $o.outcome, app $outcome',
        );
        if (o.outcome == 'advance' || o.outcome == 'deload') {
          expect(
            next != null && double.parse(next.split(' ').first) == o.next,
            '$id $slot: oracle next ${o.next}, app $next',
          );
        }
      }
    }
    var verb = 'accepted';
    final at2 = t.add(const Duration(minutes: 1));
    if (outcome == 'review' || outcome == 'unknown') {
      verb = 'declined (cannot accept $outcome)';
      await ok('progression decline', {
        'sessionId': id,
        'slotId': slot,
        'expectedVersion': decision['version'],
        'declinedAt': iso(at2),
      });
    } else if (d.declineBench && slot == 'bench') {
      verb = 'declined (repeat the weight after the break)';
      await ok('progression decline', {
        'sessionId': id,
        'slotId': slot,
        'expectedVersion': decision['version'],
        'declinedAt': iso(at2),
      });
    } else if (outcome == 'deload' && !declinedDeloadOnce && slot == 'squat') {
      declinedDeloadOnce = true;
      verb = 'declined (one more try at this weight)';
      await ok('progression decline', {
        'sessionId': id,
        'slotId': slot,
        'expectedVersion': decision['version'],
        'declinedAt': iso(at2),
      });
    } else {
      final accepted = await ok('progression accept', {
        'sessionId': id,
        'slotId': slot,
        'expectedVersion': decision['version'],
        'acceptedAt': iso(at2),
      });
      if (bbrCount == 3 && slot == slots.first) {
        final again = await call('progression accept', {
          'sessionId': id,
          'slotId': slot,
          'expectedVersion': decision['version'],
          'acceptedAt': iso(at2),
        });
        note(
          'Repeated `progression accept` (lost response) gave rc '
          '${again.code}, identical: ${again.ok && jsonEncode(again.data) == jsonEncode(accepted)}.',
        );
      }
    }
    if (d.typoSquat && slot == 'squat') {
      final current = double.parse(planned[slot]!.split(' ').first);
      final trueReps = [...reps.take(2), typoTrueReps!];
      typoCorrectNext = bbrOracle('squat', current, trueReps).next;
      // Next morning: notice the typo and correct the finished set.
      final fixAt = t.add(const Duration(hours: 14));
      final s = await ok('store show', {'id': id});
      final amrapSet = (s['sets'] as List).lastWhere(
        (x) => x['slot'] == 'squat',
      );
      final fixed = await call('store complete', {
        'id': id,
        'expectedVersion': s['contentVersion'],
        'setId': amrapSet['id'],
        'actuals': {
          'load': {
            'value': amrapSet['actuals']['load']['entered']['value'],
            'unit': 'kg',
          },
          'reps': q('$typoTrueReps', 'rep'),
        },
      });
      final shown = await ok('progression show', {
        'sessionId': id,
        'slotId': 'squat',
      });
      final status = await call('progression reconcile-status', {
        'templateId': 'bbr-a',
        'revision': 1,
        'slotId': 'squat',
        'runId': 'bbr',
        'asOf': iso(fixAt),
      });
      log(
        '  - ${day(fixAt)}: corrected the AMRAP to $typoTrueReps after '
        'finishing (rc ${fixed.code}); `progression show` reports '
        'inputsChanged ${shown['inputsChanged'] ?? shown['decision']?['inputsChanged']}, '
        'the accepted bonus stays. reconcile-status: '
        '${status.ok ? 'required ${status.data['reconciliationRequired']}' : status.error}.',
      );
      pendingEvents.add('typoFix');
    }
    final followedOn = res.data['followedSettings'] as List?;
    if (followedOn != null && followedOn.isNotEmpty) {
      log(
        '  - ${followedOn.length} $slot set(s) counted as following the '
        'target on ${followedOn.first['instanceId']}.',
      );
    }
    final band = proposal['incrementBandAssessment']?['status'];
    final failed = decision['failedSessions'] ?? proposal['failedSessions'];
    log(
      '$line → $outcome${band == 'band' ? ' (AMRAP bonus)' : ''}'
      '${next != null ? ' next $next' : ''}, $verb'
      '${failed != null && failed != 0 ? ', failures $failed' : ''}',
    );
    if (d.typoSquat && slot == 'squat') {
      // The oracle check above was skipped; nothing else to train.
    }
    if (outcome != 'unknown' && outcome != 'review') {
      final f = d.phoneCall && slot == 'deadlift' ? 0.0 : 1.0;
      person.train(slot, factor: f);
    }
  }
}

var declinedDeloadOnce = false;

// ------------------------------------------------------------ C25K

var c25kCount = 0;

Future<void> c25kSession(
  int week,
  int weekday, {
  bool sideStitch = false,
  bool adHoc = false,
  String? template,
}) async {
  c25kCount++;
  final id =
      'c25k-${c25kCount.toString().padLeft(2, '0')}${adHoc ? '-repeat' : ''}';
  final t = at(week, weekday, 7);
  dynamic session;
  String label;
  if (adHoc) {
    session = await ok('store start', {
      'id': id,
      'templateId': template,
      'revision': 1,
      'startedAt': iso(t),
    });
    label = '$template (ad hoc repeat, outside the run)';
  } else {
    final run = await runShow('c25k');
    label =
        '${run['currentDay']?['label'] ?? run['currentDay']?['templateId'] ?? '?'}';
    final started = await startRun('c25k', id, t);
    session = sessionOf(started);
    label = '${session['revision']['definition']['name']}';
  }
  log('');
  log('### ${day(t)} — $label ($id)');
  final ex = Walk('ex-$id', id);
  final clash = pendingInterruption;
  if (clash != null) {
    final (sid, _, _) = clash;
    await ex.begin(t);
    final timed = await call('execution time', {
      'id': ex.exId,
      'expectedVersion': ex.view['version'],
      'at': iso(t),
    });
    log(
      '  - Starting the first run interval while yesterday\'s lifting '
      'session ($sid) still holds its rest clock: rc ${timed.code}'
      '${timed.ok ? '' : ' (${timed.error})'}.',
    );
    await resumeInterruption(t);
    await ex.refresh();
  } else {
    await ex.begin(t);
  }
  var interval = 0;
  var stitched = false;
  final ok2 = await ex.walk((current) async {
    final set = current['set'];
    final target = qv(set['suggested']['duration']).round();
    interval++;
    if (sideStitch && interval == 2 && !stitched) {
      stitched = true;
      return Abandon();
    }
    return Timed(target * 1000);
  });
  if (!ok2) {
    // Side stitch: stop the clock 2 minutes into the run, then walk home.
    final timerResult = await ok('execution time', {
      'id': ex.exId,
      'expectedVersion': ex.view['version'],
      'at': iso(ex.now),
    });
    await ex.refresh();
    final timerId = ex.view['timer']['id'] as String;
    var timer = await ok('timer show', {'id': timerId});
    timer = await ok('timer resume', {
      'id': timerId,
      'expectedVersion': timer['version'],
      'ownerId': 'app',
      'at': iso(ex.now),
    });
    final paused = await ok('timer pause', {
      'id': timerId,
      'expectedVersion': timer['version'],
      'ownerId': 'app',
      'elapsedMilliseconds': 120000,
      'at': iso(ex.now.add(const Duration(minutes: 2))),
    });
    ex.now = ex.now.add(const Duration(minutes: 2));
    final stopped = await ok('timer stop', {
      'id': timerId,
      'expectedVersion': paused['version'] ?? paused['timer']?['version'],
      'at': iso(ex.now),
      'confirm': true,
    });
    final confirm = await call('execution confirm', {
      ...ex.request(),
      'timerId': timerId,
      'timerVersion': stopped['version'] ?? stopped['timer']?['version'],
      'acceptSuggested': true,
    });
    log(
      '  - Side stitch 2 min into interval 2 (${timerResult == null ? '' : ''}'
      'stopped the clock). Confirming the partial interval: rc ${confirm.code}'
      '${confirm.ok ? '' : ' (${confirm.error})'}.',
    );
    if (confirm.ok) {
      ex.view = confirm.data;
    } else {
      await ex.refresh();
    }
    final s = await ok('store show', {'id': id});
    final setId =
        ex.view['current']?['set']?['id'] ?? (s['sets'] as List)[1]['id'];
    if (!confirm.ok) {
      final completed = await call('execution complete', {
        ...ex.request(),
        'actuals': {'duration': q('120', 's')},
      });
      if (completed.ok) ex.view = completed.data;
      log(
        '  - Logged the 120 s actually run instead: rc ${completed.code}'
        '${completed.ok ? '' : ' (${completed.error})'}.',
      );
    }
    final s2 = await ok('store show', {'id': id});
    final ann = await call('store annotate', {
      'id': id,
      'expectedVersion': s2['contentVersion'],
      'setId': setId,
      'observations': {
        'terminationReason': 'pain-discomfort',
        'notes': 'Side stitch',
      },
    });
    log('  - Annotated the interval (pain-discomfort): rc ${ann.code}.');
    await ex.refresh();
    final group = await call('execution skip-group', {
      ...ex.request(),
      'groupPath': 'c25k',
      'confirm': true,
    });
    log(
      '  - Walked home, skipping the rest of the session with '
      '`execution skip-group`: rc ${group.code}'
      '${group.ok ? '' : ' (${group.error})'}.',
    );
    if (!group.ok) {
      final s3 = await ok('store show', {'id': id});
      final timers = await ok('timer list', {});
      for (final tm in timers as List) {
        if (tm['sessionId'] == id && tm['status'] != 'completed') {
          await call('timer discard', {
            'id': tm['id'],
            'expectedVersion': tm['version'],
            'at': iso(ex.now),
            'confirm': true,
          });
        }
      }
      final rem = await call('store skip-remaining', {
        'id': id,
        'expectedVersion': s3['contentVersion'],
        'confirm': true,
      });
      log(
        '  - Fallback `store skip-remaining`: rc ${rem.code} ${rem.ok ? '' : rem.error}',
      );
    }
  }
  await finish(id, ex.now.add(const Duration(minutes: 5)));
  final summary = await ok('store summary', {'id': id});
  final counts = summary['counts'];
  log(
    '  - ${counts['completed']} of ${counts['included']} run intervals '
    'completed, ${counts['skipped']} skipped; elapsed '
    '${summary['elapsed'] ?? summary['elapsedSeconds'] ?? '?'}.',
  );
}

Future<void> resumeInterruption(DateTime t) async {
  final pending = pendingInterruption;
  if (pending == null) return;
  pendingInterruption = null;
  final (id, ex, _) = pending;
  ex.now = t;
  await ex.refresh();
  final skipped = await call('execution skip-group', {
    ...ex.request(),
    'groupPath': 'b/deadlift',
    'confirm': true,
  });
  log(
    '  - Closed out $id: skipped the remaining deadlift work with '
    '`execution skip-group b/deadlift`: rc ${skipped.code}'
    '${skipped.ok ? '' : ' (${skipped.error})'}.',
  );
  if (!skipped.ok) {
    note('skip-group on the interrupted session failed: ${skipped.error}');
    return;
  }
  ex.view = skipped.data;
  final s = await ok('store show', {'id': id});
  // Annotate the interrupted set.
  final interrupted = (s['sets'] as List).firstWhere(
    (x) => x['slot'] == 'deadlift' && x['ordinal'] == 1,
  );
  await ok('store annotate', {
    'id': id,
    'expectedVersion': s['contentVersion'],
    'setId': interrupted['id'],
    'observations': {'terminationReason': 'interrupted', 'notes': 'Phone call'},
  });
  final finishedAt = t.subtract(const Duration(minutes: 1));
  await finish(id, finishedAt);
  log(
    '  - Finished $id the next morning (finishedAt ${iso(finishedAt)}), '
    'about 13 hours after it started.',
  );
  final slots = ['chinup', 'ohp', 'deadlift'];
  final done = <String, List<int>>{};
  final planned = <String, String>{};
  for (final set in s['sets'] as List) {
    final slot = set['slot'] as String;
    planned[slot] = entered(set['suggested'][metricOf(slot)]);
    final reps = set['actuals']?['reps'];
    if (reps != null) {
      done.putIfAbsent(slot, () => []).add(qv(reps).round());
    }
  }
  final d = LiftDay(0, 0)..phoneCall = true;
  await resolveProgression(id, d, slots, done, planned, finishedAt);
}

// ------------------------------------------------------------ Stretching

var stretchCount = 0;

Future<void> stretchSession(int week, {bool pain = false}) async {
  stretchCount++;
  final id = 'sts-${stretchCount.toString().padLeft(2, '0')}';
  final t = at(week, 7, 10);
  await startRun('stretch', id, t);
  log('');
  log('### ${day(t)} — Starting To Stretch ($id)');
  final ex = Walk('ex-$id', id);
  await ex.begin(t);
  await ex.walk((current) async {
    final set = current['set'];
    final d = set['suggested']['duration'];
    if (d != null) return Timed(qv(d).round() * 1000);
    return Complete({'reps': q('10', 'rep')});
  });
  if (pain) {
    final s = await ok('store show', {'id': id});
    final pancake = (s['sets'] as List).lastWhere(
      (x) => x['slot'] == 'pancake-hold',
    );
    final r = await call('store annotate', {
      'id': id,
      'expectedVersion': s['contentVersion'],
      'setId': pancake['id'],
      'observations': {
        'terminationReason': 'pain-discomfort',
        'notes': 'Inner knee twinge at the 30 s hold.',
      },
    });
    log('  - Twinge in the pancake 30 s hold, annotated: rc ${r.code}.');
  }
  await finish(id, ex.now.add(const Duration(minutes: 2)));
  final summary = await ok('store summary', {'id': id});
  final counts = summary['counts'];
  final sided = (summary['sets'] as List)
      .where((s) => s['side'] != null)
      .length;
  log(
    '  - ${counts['completed']} efforts completed (${sided} one-sided), '
    'elapsed ${summary['elapsed'] ?? '?'}.',
  );
}

// ------------------------------------------------------------ Body mass

var weighIns = 0;

Future<void> weighIn(
  int week, {
  String context = 'health',
  int weekday = 6,
}) async {
  weighIns++;
  final t = at(week, weekday, 6, 45);
  // Slow cut with water noise.
  final noise = [0.3, -0.2, 0.1, -0.4, 0.2, 0.0, 0.3, -0.1][weighIns % 8];
  final mass = person.bodyMass + noise + (context == 'health' ? 0 : 1.1);
  final value = (mass * 10).round() / 10;
  await ok('mass record', {
    'measurement': {
      'id': 'mass-${t.toIso8601String().substring(0, 10)}-$context',
      'context': context,
      'observedAt': iso(t),
      'mass': q(fmt(value), 'kg'),
      'source': context == 'health' ? 'bathroom scale' : 'gym scale, clothed',
    },
  });
  final trend = await ok('mass resolve', {
    'context': context,
    'asOf': iso(t.add(const Duration(minutes: 1))),
  });
  final resolved = trend['resolved'] ?? trend['mass'] ?? trend;
  log(
    '  - ${day(t)} weigh-in ($context): ${fmt(value)} kg, trend '
    '${resolved is Map ? entered(resolved['mass'] ?? resolved) : resolved}.',
  );
  if (context == 'health') person.bodyMass -= 0.15;
}

Map<String, Object?> weightedChinRule() {
  final rule = barRule('row');
  rule['scales'] = {
    'load': {
      'scale': {
        'id': 'added-load-1kg',
        'unit': 'kg',
        'range': {'start': '0', 'step': '1', 'count': 60},
      },
      'rounding': 'nearest',
      'deloadRounding': 'atMost',
    },
  };
  return rule;
}

/// Assistance is nearly gone: switch to bodyweight chin-ups with a belt,
/// which is a new workout revision, a program revision, a run upgrade and a
/// reconciliation of the chin-up track.
Future<void> graduateChin(DateTime t) async {
  log(
    '  - Chin-ups now feel solid with little assistance: switching to '
    'bodyweight chin-ups with added load from a belt.',
  );
  final chin = {
    'id': 'chinup',
    'exercise': 'chin-up',
    'implementation': 'bodyweight',
    'setupNote': 'Dip belt for added load.',
    'targets': {'load': q('0', 'kg'), 'reps': q('5', 'rep')},
    'bodyMass': {'context': 'health'},
    'effectiveMass': {
      'id': 'weighted-chin',
      'version': 1,
      'bodyMassFraction': '1',
      'addedMass': {'metric': 'load', 'multiplier': '1'},
      'assistance': {'mass': q('0', 'kg')},
    },
  };
  final published = await call('store publish', {
    'definition': workoutB(chin: chin),
    'expectedRevision': 1,
  });
  log(
    '  - Published BBR Workout B revision 2: rc ${published.code}'
    '${published.ok ? '' : ' (${published.error})'}.',
  );
  final program = await ok('program show', {'programId': 'bbr'});
  final definition =
      program['definition'] ?? program['revision']?['definition'];
  final plan = jsonDecode(jsonEncode(definition['plan']));
  for (final day in plan['children'] as List) {
    if (day['templateId'] == 'bbr-b') day['revision'] = 2;
  }
  final programRev = await call('program publish', {
    'definition': {
      ...(definition as Map).cast<String, Object?>(),
      'plan': plan,
    },
    'expectedRevision': 1,
  });
  final run = await runShow('bbr');
  final upgraded = await call('run upgrade', {
    'runId': 'bbr',
    'expectedVersion': run['contentVersion'],
    'revision': 2,
    'requestId': 'graduate-chin',
    'at': iso(t),
    'confirm': true,
  });
  log(
    '  - Program revision 2: rc ${programRev.code}; `run upgrade`: rc '
    '${upgraded.code}${upgraded.ok ? '' : ' (${upgraded.error})'}.',
  );
  if (!upgraded.ok) {
    note(
      'A looping run cannot be re-pinned after its first full cycle: '
      '`run upgrade` said "${upgraded.error}". Starting a new run would '
      'drop every lift\'s progression track (tracks are scoped per run), '
      'so the person stays on assisted chin-ups.',
    );
    return;
  }
  final rule = weightedChinRule();
  final status = await call('progression reconcile-status', {
    'templateId': 'bbr-b',
    'revision': 2,
    'slotId': 'chinup',
    'runId': 'bbr',
    'asOf': iso(t),
    'rule': rule,
    'ruleType': 'threshold',
  });
  if (!status.ok) {
    note(
      'reconcile-status for the new chin-up revision failed: ${status.error}',
    );
    return;
  }
  final kinds = status.data['blockerKinds'] as List;
  if (kinds.isEmpty) {
    log(
      '  - reconcile-status: nothing to reconcile; bodyweight chin-ups are '
      'a new implementation, so they start their own track.',
    );
    chinGraduated = true;
    ruleOverride['chinup'] = rule;
    return;
  }
  final sequence = status.data['track']?['sequence'];
  final reconciled = await call('progression reconcile', {
    'id': 'chin-to-bodyweight',
    'templateId': 'bbr-b',
    'revision': 2,
    'slotId': 'chinup',
    'runId': 'bbr',
    'expectedSequence': sequence,
    'kinds': kinds,
    'reconciledAt': iso(t),
    'rule': rule,
    'ruleType': 'threshold',
    'resetFailures': true,
    'confirm': true,
  });
  log(
    '  - reconcile-status named $kinds; `progression reconcile`: rc '
    '${reconciled.code}${reconciled.ok ? '' : ' (${reconciled.error})'}.',
  );
  chinGraduated = true;
  ruleOverride['chinup'] = rule;
}

/// Week 10: the one-leg pike moves from the chair to standing.
Future<void> upgradeStretch(DateTime t) async {
  final published = await call('store publish', {
    'definition': stretchWorkout(pikeSupport: 'standing'),
    'expectedRevision': 1,
  });
  final programRev = await call('program publish', {
    'definition': {
      'id': 'stretch',
      'name': 'Starting To Stretch, weekly',
      'plan': {
        'id': 'weekly',
        'type': 'day',
        'label': 'Full routine',
        'templateId': 'starting-to-stretch',
        'revision': 2,
      },
    },
    'expectedRevision': 1,
  });
  final run = await runShow('stretch');
  final upgraded = await call('run upgrade', {
    'runId': 'stretch',
    'expectedVersion': run['contentVersion'],
    'revision': 2,
    'requestId': 'standing-pike',
    'at': iso(t),
    'confirm': true,
  });
  log(
    '  - Touching the toes with a straight back on the chair: the one-leg '
    'pike moves to the standing version (workout rev 2 rc ${published.code}, '
    'program rev 2 rc ${programRev.code}, run upgrade rc ${upgraded.code}'
    '${upgraded.ok ? '' : ': ${upgraded.error}'}).',
  );
}

// ------------------------------------------------------------ Setup

Future<void> setup() async {
  log('## Setup');
  await ok('equipment publish', {
    'equipment': {'id': 'barbell', 'name': 'Olympic barbell'},
    'expectedRevision': 0,
  });
  await ok('equipment publish', {
    'equipment': {'id': 'assist-machine', 'name': 'Assisted chin-up machine'},
    'expectedRevision': 0,
  });
  await ok('gym publish', {
    'gym': {'id': 'local', 'name': 'Local gym'},
    'expectedRevision': 0,
  });
  await ok('instance publish', {
    'instance': {
      'id': 'main-bar',
      'equipmentId': 'barbell',
      'gym': 'local',
      'name': '20 kg bar, kg plates + own 0.5/0.25 kg micro plates',
      'loading': barLoading(),
    },
    'expectedRevision': 0,
  });
  await ok('instance publish', {
    'instance': {
      'id': 'assist-lb',
      'equipmentId': 'assist-machine',
      'gym': 'local',
      'name': 'Assisted chin-up machine (lb stack)',
      'scale': {
        'id': 'assist-lb-stack',
        'unit': 'lb',
        'range': {'start': '10', 'step': '5', 'count': 19},
      },
    },
    'expectedRevision': 0,
  });
  await ok('instance publish', {
    'instance': {
      'id': 'assist-kg',
      'equipmentId': 'assist-machine',
      'gym': 'local',
      'name': 'Assisted chin-up machine (kg stack)',
      'scale': {
        'id': 'assist-kg-stack',
        'unit': 'kg',
        'range': {'start': '5', 'step': '2.5', 'count': 24},
      },
    },
    'expectedRevision': 0,
  });
  for (final w in [
    workoutA(),
    workoutB(),
    workoutA(id: 'bbr-a-rehearsal', rest: 2),
  ]) {
    await ok('store publish', {'definition': w, 'expectedRevision': 0});
  }
  await ok('program publish', {
    'definition': {
      'id': 'bbr',
      'name': 'r/Fitness Basic Beginner Routine',
      'plan': {
        'id': 'ab',
        'type': 'group',
        'children': [
          {
            'id': 'a',
            'type': 'day',
            'label': 'A',
            'templateId': 'bbr-a',
            'revision': 1,
          },
          {
            'id': 'b',
            'type': 'day',
            'label': 'B',
            'templateId': 'bbr-b',
            'revision': 1,
          },
        ],
      },
    },
    'expectedRevision': 0,
  });
  final published = <String>{};
  final weeks = <Map<String, Object?>>[];
  for (var w = 1; w <= 9; w++) {
    final days = <Map<String, Object?>>[];
    for (var d = 0; d < 3; d++) {
      final template = c25kTemplate(w, d);
      if (published.add(template)) {
        await ok('store publish', {
          'definition': c25kWorkout(w, d),
          'expectedRevision': 0,
        });
      }
      days.add({
        'id': 'w$w-d${d + 1}',
        'type': 'day',
        'label': 'Week $w day ${(w - 1) * 3 + d + 1}',
        'templateId': template,
        'revision': 1,
      });
    }
    weeks.add({
      'id': 'week$w',
      'type': 'group',
      'label': 'Week $w',
      'children': days,
    });
  }
  await ok('program publish', {
    'definition': {
      'id': 'c25k',
      'name': 'Couch to 5K',
      'plan': {'id': 'nine-weeks', 'type': 'group', 'children': weeks},
    },
    'expectedRevision': 0,
  });
  await ok('store publish', {
    'definition': stretchWorkout(),
    'expectedRevision': 0,
  });
  await ok('program publish', {
    'definition': {
      'id': 'stretch',
      'name': 'Starting To Stretch, weekly',
      'plan': {
        'id': 'weekly',
        'type': 'day',
        'label': 'Full routine',
        'templateId': 'starting-to-stretch',
        'revision': 1,
      },
    },
    'expectedRevision': 0,
  });
  final t0 = iso(at(1, 1, 6));
  await ok('run create', {
    'id': 'bbr',
    'programId': 'bbr',
    'revision': 1,
    'startedAt': t0,
    'loop': true,
  });
  await ok('run create', {
    'id': 'c25k',
    'programId': 'c25k',
    'revision': 1,
    'startedAt': t0,
    // C25K is a finite program: the run ends after day 27.
    'loop': false,
  });
  await ok('run create', {
    'id': 'stretch',
    'programId': 'stretch',
    'revision': 1,
    'startedAt': t0,
    'loop': true,
  });
  log(
    '- Published 3 programs (BBR A/B looping; C25K 27 days, '
    '${published.length} workouts; Starting To Stretch weekly), a kg barbell '
    'with declared plates, and two assisted chin-up machines (lb and kg '
    'stacks).',
  );
}

Future<void> rehearsal() async {
  // Sunday before week 1: a dry run of workout A at home with 2 s rests,
  // using the real foreground stopwatch for every rest.
  final t = at(0, 7, 15);
  final id = 'rehearsal';
  await ok('store start', {
    'id': id,
    'templateId': 'bbr-a-rehearsal',
    'revision': 1,
    'startedAt': iso(t),
  });
  final ex = Walk('ex-$id', id);
  await ex.begin(t);
  var foreground = 0;
  final watch = Stopwatch()..start();
  while (ex.view['status'] != 'completed') {
    final c = ex.view['current'];
    if (c['kind'] == 'rest' && c['activity']['manual'] != true) {
      final r = await ok('execution run', {...ex.request()});
      ex.view = r['execution'] ?? r;
      foreground++;
      continue;
    }
    if (c['kind'] == 'rest') {
      ex.view = await ok('execution advance', ex.request());
      continue;
    }
    final amrap = c['set']['ordinal'] == 2;
    ex.view = await ok('execution complete', {
      ...ex.request(),
      if (amrap) 'actuals': {'load': q('20', 'kg'), 'reps': q('8', 'rep')},
      if (!amrap) 'acceptSuggested': true,
    });
  }
  watch.stop();
  await finish(id, t.add(const Duration(minutes: 10)));
  log('');
  log('### ${day(t)} — Rehearsal of workout A with the empty bar (ad hoc)');
  log(
    '  - $foreground timed 2 s rests run on the real foreground stopwatch; '
    'whole walk took ${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1)} s '
    'of wall time.',
  );
}

// ------------------------------------------------------------ Main

Future<void> main(List<String> args) async {
  var outPath = 'build/simulation';
  bin = 'build/bodytmi';
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--bin':
        bin = args[++i];
      case '--out':
        outPath = args[++i];
      case '--quick':
        quick = true;
      case '--final-only':
        finalOnly = true;
      case '--weeks':
        weeks = int.parse(args[++i]);
    }
  }
  bin = File(bin).absolute.path;
  out = Directory(outPath)..createSync(recursive: true);
  db = '${out.absolute.path}/profile.sqlite';
  if (finalOnly) {
    for (final name in [
      'archive.json',
      'restored.sqlite',
      'recovery',
      'backup',
    ]) {
      final entity = File('${out.path}/$name').existsSync()
          ? File('${out.path}/$name') as FileSystemEntity
          : Directory('${out.path}/$name');
      if (entity.existsSync()) entity.deleteSync(recursive: true);
    }
    calls = File('${out.path}/final-calls.ndjson').openWrite();
    try {
      await finalChecks();
    } finally {
      await calls.close();
      File('${out.path}/final.md').writeAsStringSync(journal.toString());
    }
    return;
  }
  for (final f in out.listSync()) {
    f.deleteSync(recursive: true);
  }
  calls = File('${out.path}/calls.ndjson').openWrite();
  final status = await simulate().then(
    (_) => 0,
    onError: (Object e, StackTrace s) {
      log('');
      log('**SIMULATION STOPPED:** $e');
      stderr.writeln(s);
      return 2;
    },
  );
  await calls.close();
  log('');
  log('---');
  log(
    '$callCount CLI calls, ${failures.length} oracle mismatches, '
    '${observations.length} observations.',
  );
  File('${out.path}/journal.md').writeAsStringSync(journal.toString());
  File('${out.path}/observations.md').writeAsStringSync(
    [
      for (final o in observations) '- $o',
      for (final f in failures) '- MISMATCH: $f',
    ].join('\n'),
  );
  exitCode = status != 0 ? status : (failures.isEmpty ? 0 : 1);
}

Future<void> simulate() async {
  journal.writeln('# Twelve weeks with BodyTMI\n');
  await setup();
  await rehearsal();
  for (var week = 1; week <= (quick ? 1 : weeks); week++) {
    log('');
    log('## Week $week (${day(at(week, 1, 0)).substring(4)})');
    await weekOf(week);
  }
  if (!quick && weeks == 12) await finalChecks();
}

Future<void> weekOf(int week) async {
  if (week == 7) {
    log('- Travel week: all three runs paused, nothing logged, no weigh-in.');
    for (final run in ['bbr', 'c25k', 'stretch']) {
      final r = await runShow(run);
      await ok('run pause', {
        'runId': run,
        'expectedVersion': r['contentVersion'],
      });
    }
    return;
  }
  if (week == 8) {
    for (final run in ['bbr', 'c25k', 'stretch']) {
      final r = await runShow(run);
      await ok('run resume', {
        'runId': run,
        'expectedVersion': r['contentVersion'],
      });
    }
    log('- Back from travel; runs resumed. Strength down about 3 %.');
    person.strength.updateAll((_, v) => v * 0.97);
  }
  // Mon / Wed / Fri lifting, Tue / Thu / Sat running, Sun stretching.
  for (final weekday in [1, 2, 3, 4, 5, 6, 7]) {
    switch (weekday) {
      case 1 || 3 || 5:
        final d = LiftDay(week, weekday);
        if (week == 1 && weekday != 5) d.firstTime = true;
        if (weekday == 1) {
          pendingEvents.addAll(switch (week) {
            2 => ['rackBusy'],
            3 => ['microPlates'],
            5 => ['killDuringRest', 'lbMachineBusy'],
            6 => ['benchBusy'],
            8 => ['declineBench', 'phoneCall'],
            9 => ['typoSquat'],
            10 => ['graduateChin'],
            _ => <String>[],
          });
        }
        if (week >= 4 && week <= 5) person.gain['squat'] = -0.4;
        if (week == 6) person.gain['squat'] = 1.2;
        if (week == 4 && weekday == 1) {
          await weighIn(week, context: 'clothed-training', weekday: 1);
        }
        await bbrSession(d);
      case 2 || 4 || 6:
        if (weekday == 6) await weighIn(week);
        if (c25kDone) continue;
        if (week == 8 && weekday == 2) {
          // C25K: repeat the last completed week after a break.
          final run = await runShow('c25k');
          final before = run['current']?['path'];
          final moved = await ok('run jump', {
            'runId': 'c25k',
            'expectedVersion': run['contentVersion'],
            'dayPath': 'nine-weeks/week6/w6-d1',
            'requestId': 'repeat-week-6',
            'at': iso(at(week, weekday, 6, 30)),
            'confirm': true,
          });
          log('');
          log(
            '  - Back from travel: `run jump` moves Couch to 5K from '
            '$before back to ${moved['current']['path']} to repeat week 6.',
          );
        }
        await c25kSession(week, weekday, sideStitch: week == 4 && weekday == 4);
        final run = await runShow('c25k');
        if (run['status'] == 'completed') {
          c25kDone = true;
          log('  - Couch to 5K run completed.');
        }
      case 7:
        if (week == 10) await upgradeStretch(at(week, 7, 9));
        await stretchSession(week, pain: week == 6);
    }
  }
}

var c25kDone = false;

Future<void> finalChecks() async {
  log('');
  log('## After twelve weeks');
  final asOf = iso(at(12, 7, 22));
  // Progress series per lift: how many separate lines does each lift get?
  for (final slot in ['squat', 'bench', 'chinup']) {
    for (final metric in ['load', 'assistance']) {
      final r = await call('store series', {
        'metric': metric,
        'context': {'slotId': slot},
      });
      if (!r.ok) {
        log('- series $slot/$metric: rc ${r.code} ${r.error}');
        continue;
      }
      final series = r.data['series'] as List;
      if (series.isEmpty) continue;
      final parts = <String>[];
      for (final row in series) {
        final points = row['points'] as List;
        final c = row['context'];
        final units = {for (final p in points) p['actual']['entered']['unit']};
        parts.add(
          '${points.length} points [${c['implementation']}'
          '${c['equipment'] == null ? '' : ', ${c['equipment']}'}'
          '${c['substituted'] == true ? ', substituted' : ''}, '
          'canonical ${row['unit']}, entered as ${units.join(' and ')}]',
        );
      }
      log(
        '- `store series` $slot $metric: ${series.length} line(s): '
        '${parts.join('; ')}.',
      );
    }
  }
  final records = await call('store records', {
    'metric': 'reps',
    'direction': 'higher',
    'context': {'slotId': 'squat'},
  });
  if (records.ok) {
    final rows = records.data['groups'] as List?;
    log(
      '- `store records` squat reps: ${rows?.length ?? 0} record contexts '
      '(policy ${records.data['policy']?['id'] ?? records.data['policy']}).',
    );
  } else {
    log('- `store records` failed: ${records.error}');
  }
  // Body mass: trend and the stale warning right after travel.
  final afterTravel = await ok('mass resolve', {
    'context': 'health',
    'asOf': iso(at(8, 1, 6)),
    'staleAfterDays': 7,
    'warnIfStale': true,
  });
  log(
    '- Body mass resolved on the Monday after travel: '
    '${jsonEncode(afterTravel['warnings'] ?? afterTravel['stale'] ?? afterTravel['status'])}.',
  );
  final trend = await ok('mass trend', {'context': 'health', 'asOf': asOf});
  final points = (trend['trend'] ?? trend['points'] ?? trend['days']) as List?;
  log(
    '- Health trend: ${points?.length ?? '?'} daily points, latest '
    '${points == null || points.isEmpty ? '?' : jsonEncode(points.last)}.',
  );
  final clothed = await ok('mass resolve', {
    'context': 'clothed-training',
    'asOf': asOf,
  });
  log(
    '- Clothed-training context stays separate: '
    '${jsonEncode(clothed['resolved'] ?? clothed['mass'] ?? clothed['status'])}.',
  );
  // Effective load on an assisted and a weighted chin-up session.
  for (final id in ['bbr-02', 'bbr-32']) {
    final e = await call('store effective-load', {'id': id});
    final est = e.ok ? (e.data['estimates'] as List).first : null;
    log(
      '- Effective load $id chin-up set 1: rc ${e.code}'
      '${est == null
          ? ' ${e.error}'
          : est['actual']['status'] != 'available'
          ? ', ${est['actual']['status']} (missing ${est['actual']['missingInputs']})'
          : ', ${entered(est['actual']['mass'])} '
                '(body ${entered(est['actual']['inputs']['bodyMass']['mass'])} − '
                'assistance ${entered(est['actual']['inputs']['assistance']['mass'])}); '
                '${jsonEncode(est).length} bytes of JSON for one set'}.',
    );
  }
  for (final run in ['bbr', 'c25k', 'stretch']) {
    final r = await runShow(run);
    final sched = await ok('run schedule', {'runId': run, 'count': 3});
    log(
      '- Run $run: status ${r['status']}, cursor ${r['cursor']}, next '
      '${[for (final d in sched['days'] as List) d['day']?['label'] ?? d['label']].join(', ')}.',
    );
  }
  // Portability: logical export, validate, restore; native backup.
  final archive = '${out.absolute.path}/archive.json';
  final exported = await ok('archive export', {'destination': archive});
  final validated = await call('archive validate', {'source': archive});
  final restoredDb = '${out.absolute.path}/restored.sqlite';
  final before = await ok('store series', {
    'metric': 'load',
    'context': {'slotId': 'squat'},
  });
  final savedDb = db;
  db = restoredDb;
  final restored = await call('archive restore', {
    'source': archive,
    'recoveryDestination': '${out.absolute.path}/recovery',
    'confirm': true,
  });
  final after = restored.ok
      ? await ok('store series', {
          'metric': 'load',
          'context': {'slotId': 'squat'},
        })
      : null;
  db = savedDb;
  final backup = await call('backup create', {
    'destination': '${out.absolute.path}/backup',
  });
  final backupValid = await call('backup validate', {
    'source': '${out.absolute.path}/backup',
  });
  log(
    '- Archive export (${(File(archive).lengthSync() / 1024).round()} KiB, '
    'sha ${(exported['sha256'] as String).substring(0, 12)}…): validate rc '
    '${validated.code}, restore into a new profile rc ${restored.code}'
    '${restored.ok ? '' : ' (${restored.error})'}, squat series identical after '
    'restore: ${after != null && jsonEncode(after) == jsonEncode(before)}. Native backup rc '
    '${backup.code}, validate rc ${backupValid.code}.',
  );
  final dbSize = File(db).lengthSync();
  log('- Profile size ${(dbSize / 1024).round()} KiB.');
  log('');
  log('### CLI latency by command (ms)');
  log('');
  log('| command | calls | median | p95 | max |');
  log('|---|---:|---:|---:|---:|');
  final rows = timings.entries.toList()
    ..sort(
      (a, b) => b.value
          .fold<int>(0, (x, y) => x + y)
          .compareTo(a.value.fold<int>(0, (x, y) => x + y)),
    );
  for (final e in rows.take(20)) {
    final v = [...e.value]..sort();
    log(
      '| `${e.key}` | ${v.length} | ${v[v.length ~/ 2]} | '
      '${v[(v.length * 0.95).floor().clamp(0, v.length - 1)]} | ${v.last} |',
    );
  }
}
