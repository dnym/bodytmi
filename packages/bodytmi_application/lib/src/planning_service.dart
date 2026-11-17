import 'package:bodytmi_core/bodytmi_core.dart';

import 'daily_metrics.dart';
import 'plan_service.dart';
import 'practice_service.dart';
import 'sleep_service.dart';
import 'training_repository.dart';

const goalKind = 'goal';
const routineKind = 'routine';
const routineCheckKind = 'routine-check';
const trialKind = 'trial';
const savedReviewKind = 'saved-review';

String routineCheckId(String routineId, String date) =>
    '$routineId-${date.replaceAll('-', '')}';

/// Goals, routines, trials and saved reviews (APP-PLAN 4.6). A missing log
/// is not a missed goal; there are no streaks.
final class PlanningService {
  const PlanningService(this.repository);
  final TrainingRepository repository;

  DailyMetricService get _metrics => DailyMetricService(repository);

  Future<List<Map<String, Object?>>> _records(String kind) async => [
    for (final r in await repository.dietRecords(kind: kind)) r.snapshot,
  ];

  /// Saves a versioned record: version 1 creates (id must be new), later
  /// versions replace when [expectedVersion] matches.
  Future<Map<String, Object?>> _save(
    String kind,
    Map<String, Object?> input,
    int expectedVersion,
    Map<String, Object?> Function(Map<String, Object?>) parse,
  ) => repository.transaction(() async {
    if (input.containsKey('version'))
      invalid('The service assigns the version.');
    final id = identifier(input, 'id');
    final before = (await _records(
      kind,
    )).where((r) => r['id'] == id).firstOrNull;
    if (((before?['version'] as int?) ?? 0) != expectedVersion)
      throw BodyTmiException('conflict', 'The $kind $id changed or exists.');
    final next = parse({...input, 'version': expectedVersion + 1});
    await repository.saveDietRecord(DietRecord(kind, id, 1, next));
    return next;
  });

  Future<Map<String, Object?>> _one(String kind, String id) async =>
      (await _records(kind)).where((r) => r['id'] == id).firstOrNull ??
      (throw BodyTmiException('not_found', 'No $kind $id.'));

  // Goals.

  Future<Goal> saveGoal(Map<String, Object?> goal, int expectedVersion) async =>
      Goal.fromJson(
        await _save(
          goalKind,
          {'status': 'active', ...goal},
          expectedVersion,
          (j) => Goal.fromJson(j).toJson(),
        ),
      );

  Future<Goal> goal(String id) async => Goal.fromJson(await _one(goalKind, id));

  Future<List<Goal>> goals() async => [
    for (final r in await _records(goalKind)) Goal.fromJson(r),
  ];

  /// Policy bodytmi-goal-progress/1: the goal metric from its start to
  /// [asOfDate] (inclusive, or the goal end), aggregated and compared with
  /// the target. Unknown days are left out, never counted against it.
  Future<Map<String, Object?>> progress(Goal g, String asOfDate) async {
    final end = addDays(asOfDate, 1);
    final until = g.until != null && g.until!.compareTo(end) < 0
        ? g.until!
        : end;
    if (until.compareTo(g.from) <= 0)
      return {
        'goal': g.toJson(),
        'status': 'not-started',
        'policy': 'bodytmi-goal-progress/1',
      };
    final days = await _metrics.evaluate(g.metric, g.from, until);
    final known = [
      for (final d in days)
        if (d.value != null) d.value!,
    ];
    final base = {
      'policy': 'bodytmi-goal-progress/1',
      'goal': g.toJson(),
      'from': g.from,
      'until': until,
      'days': days.length,
      'knownDays': known.length,
    };
    if (g.aggregate == 'daysMet') {
      final met = known.where(g.target.met).length;
      return {
        ...base,
        'daysMet': met,
        'status': known.isEmpty ? 'unknown' : 'tracked',
      };
    }
    if (known.isEmpty) return {...base, 'status': 'unknown', 'value': null};
    final value = switch (g.aggregate) {
      'sum' => known.reduce((a, b) => a + b),
      'min' => known.reduce((a, b) => a < b ? a : b),
      'max' => known.reduce((a, b) => a > b ? a : b),
      'latest' => known.last,
      _ => known.reduce((a, b) => a + b) / known.length,
    };
    return {
      ...base,
      'value': round3(value),
      'status': g.target.met(value) ? 'met' : 'not-met',
    };
  }

  /// Body plans with a target are goals with a programme attached: the
  /// plan record holds the target, shown here without a copy.
  Future<List<Map<String, Object?>>> planGoals() async => [
    for (final p in await PlanService(repository).plans())
      if (p.target != null)
        {
          'kind': 'body-plan',
          'planId': p.id,
          'status': p.status,
          'target': p.target!.toJson(),
          'from': p.startDate,
          'until': ?p.endDate,
        },
  ];

  // Routines.

  Future<Routine> saveRoutine(
    Map<String, Object?> routine,
    int expectedVersion,
  ) async => Routine.fromJson(
    await _save(
      routineKind,
      routine,
      expectedVersion,
      (j) => Routine.fromJson(j).toJson(),
    ),
  );

  Future<List<Routine>> routines() async => [
    for (final r in await _records(routineKind)) Routine.fromJson(r),
  ];

  Future<Map<String, Object?>> check(
    String routineId,
    String date,
    String at, {
    bool undo = false,
  }) => repository.transaction(() async {
    final routine = Routine.fromJson(await _one(routineKind, routineId));
    if (routine.action['kind'] != 'check')
      invalid('Routine $routineId is completed by its evidence, not checked.');
    checkDate(date, 'date');
    parseInstant(at, 'at');
    final record = {
      'routineId': routineId,
      'date': date,
      'at': at,
      'status': undo ? 'unchecked' : 'checked',
    };
    await repository.saveDietRecord(
      DietRecord(routineCheckKind, routineCheckId(routineId, date), 1, record),
    );
    return record;
  });

  /// Policy bodytmi-today/1: routines due on [date] with their due time and
  /// evidence, and active goals with progress. A routine without evidence
  /// is `not-logged`, never missed.
  Future<Map<String, Object?>> today(String date) async {
    checkDate(date, 'date');
    final routines = <Map<String, Object?>>[];
    for (final r in await this.routines()) {
      if (!r.activeOn(date)) continue;
      final evidence = await _evidence(r, date);
      routines.add({
        'routine': r.toJson(),
        'due': await _due(r, date),
        'status': evidence.isEmpty ? 'not-logged' : 'done',
        'evidence': evidence,
      });
    }
    final goals = [
      for (final g in await this.goals())
        if (g.json['status'] == 'active' && g.from.compareTo(date) <= 0)
          await progress(g, date),
    ];
    return {
      'policy': 'bodytmi-today/1',
      'date': date,
      'routines': routines,
      'goals': goals,
      'planGoals': await planGoals(),
      'note': 'A missing log is not a missed goal; there are no streaks.',
    };
  }

  Future<List<Map<String, Object?>>> _evidence(Routine r, String date) async {
    final a = r.action;
    final next = addDays(date, 1);
    switch (a['kind']) {
      case 'activity':
        return [
          for (final x in await repository.activityRecords(
            fromDate: date,
            untilDate: next,
          ))
            if (x.countsToward.contains(a['category']))
              {'activity': x.id, 'start': x.json['start']},
        ];
      case 'practice':
        return [
          for (final s in await PracticeService(repository).sessions())
            if (s.date == date &&
                s.status == 'confirmed' &&
                s.practiceId == a['practiceId'])
              {'practiceSession': s.id, 'startedAt': s.json['startedAt']},
        ];
      case 'observation':
        return [
          for (final o in await repository.observationRecords(
            measureId: a['measure']! as String,
            fromDate: date,
            untilDate: next,
          ))
            if (!o.deleted) {'observation': o.observation.id},
        ];
      default:
        final checks = await _records(routineCheckKind);
        final c = checks
            .where((x) => x['routineId'] == r.id && x['date'] == date)
            .firstOrNull;
        return c == null || c['status'] != 'checked'
            ? const []
            : [
                {'checkedAt': c['at']},
              ];
    }
  }

  /// When the routine is due: a clock time, or an anchor (actual if logged,
  /// else planned from the sleep schedule) plus offset.
  Future<Map<String, Object?>> _due(Routine r, String date) async {
    final s = r.schedule;
    final window = s['windowMinutes'];
    if (s['at'] != null)
      return {'clock': s['at'], 'basis': 'clock', 'windowMinutes': ?window};
    if (s['relative'] == null) return {'basis': 'any-time'};
    final rel = s['relative']! as Map<String, Object?>;
    final offset = (rel['offsetMinutes'] as int?) ?? 0;
    ({int minutes, String basis, String? at})? anchor;
    final sleep = SleepService(repository);
    switch (rel['anchor']) {
      case 'wake':
        final night = (await repository.sleepRecords(
          fromDate: date,
          untilDate: addDays(date, 1),
        )).where((x) => x.isMain).firstOrNull;
        if (night != null) {
          anchor = (
            minutes: DailyMetricService.clockOn(
              date,
              night.wakeAt,
              night.wakeOffset,
            ),
            basis: 'actual',
            at: night.json['wakeAt'] as String,
          );
        } else {
          final sched = sleep.scheduleOn(date, await sleep.schedules());
          if (sched != null)
            anchor = (
              minutes: sched
                  .desiredFor(DateTime.parse('${date}T00:00:00Z').weekday)
                  .wake,
              basis: 'planned',
              at: null,
            );
        }
      case 'bedtime':
        final next = addDays(date, 1);
        final night = (await repository.sleepRecords(
          fromDate: next,
          untilDate: addDays(next, 1),
        )).where((x) => x.isMain).firstOrNull;
        if (night != null) {
          anchor = (
            minutes: DailyMetricService.clockOn(
              date,
              night.start,
              night.onsetOffset,
            ),
            basis: 'actual',
            at: (night.json['bedAt'] ?? night.json['asleepAt']) as String?,
          );
        } else {
          final sched = sleep.scheduleOn(next, await sleep.schedules());
          if (sched != null) {
            final d = sched.desiredFor(
              DateTime.parse('${next}T00:00:00Z').weekday,
            );
            anchor = (
              minutes: d.sleep > d.wake ? d.sleep : d.sleep + 1440,
              basis: 'planned',
              at: null,
            );
          }
        }
      case 'meal':
        final meal = (await repository.diaryEntries(
          fromDate: date,
          untilDate: addDays(date, 1),
        )).where((e) => e.meal == rel['meal']).firstOrNull;
        if (meal != null)
          anchor = (
            minutes: DailyMetricService.clockOn(
              date,
              meal.instant,
              parseOffsetMinutes(meal.at, 'at'),
            ),
            basis: 'actual',
            at: meal.at,
          );
      default:
        final sessions = [
          for (final x in await repository.sessions())
            if (formatInstant(
                  x.startedAt,
                  x.startOffsetMinutes,
                ).substring(0, 10) ==
                date)
              x,
        ]..sort((a, b) => a.startedAt.compareTo(b.startedAt));
        if (sessions.isNotEmpty)
          anchor = (
            minutes: DailyMetricService.clockOn(
              date,
              sessions.first.startedAt,
              sessions.first.startOffsetMinutes,
            ),
            basis: 'actual',
            at: formatInstant(
              sessions.first.startedAt,
              sessions.first.startOffsetMinutes,
            ),
          );
    }
    if (anchor == null)
      return {
        'basis': 'unknown',
        'anchor': rel['anchor'],
        'reason': 'The ${rel['anchor']} time is not logged or planned.',
      };
    final minutes = anchor.minutes + offset;
    return {
      'clock': clockText(minutes),
      if (minutes < 0 || minutes >= 1440) 'dayOffset': (minutes / 1440).floor(),
      'basis': anchor.basis,
      'anchor': rel['anchor'],
      'anchorAt': ?anchor.at,
      'offsetMinutes': offset,
      'windowMinutes': ?window,
    };
  }

  // Trials.

  Future<Trial> saveTrial(
    Map<String, Object?> trial,
    int expectedVersion,
  ) async {
    if (trial.containsKey('conclusion'))
      invalid('Record the conclusion with trial conclude.');
    return Trial.fromJson(
      await _save(
        trialKind,
        trial,
        expectedVersion,
        (j) => Trial.fromJson(j).toJson(),
      ),
    );
  }

  Future<Trial> trial(String id) async =>
      Trial.fromJson(await _one(trialKind, id));

  Future<List<Trial>> trials() async => [
    for (final r in await _records(trialKind)) Trial.fromJson(r),
  ];

  /// Policy bodytmi-trial-report/1: each outcome described over the
  /// baseline and the trial period, the differences of means and medians,
  /// and how often the action was done. Descriptive only.
  Future<Map<String, Object?>> report(String id) async {
    final t = await trial(id);
    final j = t.json;
    (String, String) period(String k) =>
        ((j[k]! as Map)['from']! as String, (j[k]! as Map)['until']! as String);
    final b = period('baseline'), p = period('trial');
    final outcomes = <Map<String, Object?>>[];
    for (final o in (j['outcomes']! as List)) {
      final metric = DailyMetric.fromJson(o);
      final base = describeValues(await _metrics.evaluate(metric, b.$1, b.$2));
      final trial = describeValues(await _metrics.evaluate(metric, p.$1, p.$2));
      double? diff(String k) => base[k] == null || trial[k] == null
          ? null
          : round3((trial[k]! as double) - (base[k]! as double));
      outcomes.add({
        'metric': metric.toJson(),
        'baseline': base,
        'trial': trial,
        'meanDifference': diff('mean'),
        'medianDifference': diff('median'),
      });
    }
    final action = j['action']! as Map<String, Object?>;
    Map<String, Object?>? adherence;
    if (action['metric'] != null) {
      final metric = DailyMetric.fromJson(action['metric']);
      final target = Target.fromJson(action['target']);
      final atMost = target.json['relation'] == 'atMost';
      Future<Map<String, Object?>> count((String, String) period) async {
        var met = 0, notMet = 0, unknown = 0;
        for (final d in await _metrics.evaluate(metric, period.$1, period.$2)) {
          if (d.status == 'none') {
            atMost ? met++ : notMet++;
          } else if (d.value == null) {
            unknown++;
          } else if (target.met(d.value!)) {
            met++;
          } else {
            notMet++;
          }
        }
        return {'met': met, 'notMet': notMet, 'unknown': unknown};
      }

      adherence = {
        'target': target.toJson(),
        'baseline': await count(b),
        'trial': await count(p),
      };
    }
    return {
      'policy': 'bodytmi-trial-report/1',
      'trial': j,
      'outcomes': outcomes,
      'actionAdherence': adherence,
      'note':
          'Descriptive: the periods differ in more than the action (season, '
          'routine, expectation), so a difference is not proof of an effect. '
          'Unknown days are left out.',
    };
  }

  Future<Trial> conclude(
    String id,
    int expectedVersion,
    String decision,
    String at, {
    String? notes,
  }) => repository.transaction(() async {
    final t = await trial(id);
    if (t.version != expectedVersion)
      throw const BodyTmiException('conflict', 'The trial changed.');
    final next = Trial.fromJson({
      ...t.json,
      'version': t.version + 1,
      'conclusion': {'decision': decision, 'at': at, 'notes': ?notes},
    });
    await repository.saveDietRecord(
      DietRecord(trialKind, id, 1, next.toJson()),
    );
    return next;
  });

  // Saved reviews.

  Future<SavedReview> saveReview(
    Map<String, Object?> review,
    int expectedVersion,
  ) async => SavedReview.fromJson(
    await _save(
      savedReviewKind,
      review,
      expectedVersion,
      (j) => SavedReview.fromJson(j).toJson(),
    ),
  );

  Future<List<SavedReview>> reviews() async => [
    for (final r in await _records(savedReviewKind)) SavedReview.fromJson(r),
  ];

  /// Policy bodytmi-saved-review/1: each metric's days and summary.
  Future<Map<String, Object?>> runReview(
    String id,
    String from,
    String until,
  ) async {
    final review = SavedReview.fromJson(await _one(savedReviewKind, id));
    return {
      'policy': 'bodytmi-saved-review/1',
      'review': review.toJson(),
      'from': from,
      'until': until,
      'metrics': [
        for (final m in (review.json['metrics']! as List))
          await () async {
            final metric = DailyMetric.fromJson(m);
            final days = await _metrics.evaluate(metric, from, until);
            return {
              'metric': metric.toJson(),
              'summary': describeValues(days),
              'days': [
                for (final d in days)
                  {
                    'date': d.date,
                    'status': d.status,
                    'value': ?(d.value == null ? null : round3(d.value!)),
                  },
              ],
            };
          }(),
      ],
    };
  }
}

/// Archive check: every planning record decodes and checks reference a
/// routine.
void validatePlanningRecords(List<DietRecord> records) {
  final routines = {
    for (final r in records)
      if (r.kind == routineKind) Routine.fromJson(r.snapshot).id,
  };
  for (final r in records) {
    if (r.kind == routineCheckKind &&
        !routines.contains(r.snapshot['routineId']))
      invalid('A routine check names an unknown routine.');
  }
}
