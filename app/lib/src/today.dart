import 'package:material_ui/material_ui.dart';

import 'format.dart';
import 'profile.dart';
import 'theme.dart';
import 'train.dart' show openRunSession;
import 'widgets.dart';

/// Everything the Today screen shows, read through the JSON commands.
final class TodayData {
  TodayData({
    required this.date,
    required this.now,
    required this.massDays,
    required this.weighIns,
    required this.diary,
    required this.routines,
    required this.runs,
    required this.sleeps,
    required this.activities,
    required this.practices,
  });

  final String date;
  final DateTime now;
  final List<Map<String, Object?>> massDays;
  final List<Map<String, Object?>> weighIns;
  final Map<String, Object?> diary;
  final List<Map<String, Object?>> routines;
  final List<NextWorkout> runs;
  final List<Map<String, Object?>> sleeps;
  final List<Map<String, Object?>> activities;
  final List<Map<String, Object?>> practices;

  static Future<TodayData> load(ProfileClient p, {DateTime? clock}) async {
    final now = clock ?? DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final date = isoDate(day);
    final next = isoDate(day.add(const Duration(days: 1)));
    List<Map<String, Object?>> maps(Object? list) => [
      for (final e in (list as List?) ?? const []) e as Map<String, Object?>,
    ];

    final trend = await p.call<Map<String, Object?>>('mass trend', {
      'context': 'health',
      'asOf': isoInstant(now),
    });
    final weighIns = await p.call<List<Object?>>('observation list', {
      'measure': 'body-mass',
      'from': date,
      'until': next,
      'attributes': {'context': 'health'},
    });
    final runs = <NextWorkout>[];
    for (final run in maps(
      await p.call<List<Object?>>('run list', {'status': 'active'}),
    )) {
      final schedule = await p.call<Map<String, Object?>>('run schedule', {
        'runId': run['id'],
        'count': 1,
      });
      final day = at(schedule, ['days', 0, 'day']) as Map<String, Object?>?;
      if (day == null) continue;
      runs.add(
        NextWorkout(
          runId: run['id']! as String,
          program:
              at(run, ['program', 'definition', 'name']) as String? ??
              run['id']! as String,
          label: day['label'] as String? ?? day['templateId'] as String? ?? '',
          gym: run['gym'] as String?,
          inProgress: run['currentSessionId'] as String?,
          ordinal: at(schedule, ['days', 0, 'ordinal']) as int?,
        ),
      );
    }
    return TodayData(
      date: date,
      now: now,
      massDays: maps(trend['days']),
      weighIns: [
        for (final o in maps(weighIns))
          if (o['deleted'] != true) o['observation']! as Map<String, Object?>,
      ],
      diary: await p.call<Map<String, Object?>>('diary day', {'date': date}),
      routines: maps(
        (await p.call<Map<String, Object?>>('today show', {
          'date': date,
        }))['routines'],
      ),
      runs: runs,
      sleeps: maps(
        await p.call<List<Object?>>('sleep list', {
          'from': date,
          'until': next,
        }),
      ),
      activities: maps(
        await p.call<List<Object?>>('activity list', {
          'from': date,
          'until': next,
        }),
      ),
      practices: maps(
        await p.call<List<Object?>>('practice sessions', {
          'from': date,
          'until': next,
        }),
      ),
    );
  }

  /// Trend values (kg) of the last [days] trend days, oldest first.
  List<double> trendValues({int days = 42}) => [
    for (final d
        in massDays.length > days
            ? massDays.sublist(massDays.length - days)
            : massDays)
      double.parse(at(d, ['trend', 'value'])! as String),
  ];

  List<double> rawValues({int days = 42}) => [
    for (final d
        in massDays.length > days
            ? massDays.sublist(massDays.length - days)
            : massDays)
      if (at(d, ['mass', 'value']) case final String v) double.parse(v),
  ];

  /// Trend change over the last seven calendar days, kg per week.
  double? weeklyRate() {
    if (massDays.length < 2) return null;
    final last = massDays.last;
    final lastDate = DateTime.parse(last['date']! as String);
    Map<String, Object?>? earlier;
    for (final d in massDays.reversed) {
      if (!DateTime.parse(d['date']! as String)
          .isAfter(lastDate.subtract(const Duration(days: 7)))) {
        earlier = d;
        break;
      }
    }
    if (earlier == null) return null;
    final span = lastDate
        .difference(DateTime.parse(earlier['date']! as String))
        .inDays;
    if (span == 0) return null;
    return (double.parse(at(last, ['trend', 'value'])! as String) -
            double.parse(at(earlier, ['trend', 'value'])! as String)) *
        7 /
        span;
  }

  Map<String, Object?>? get mainSleep =>
      sleeps.where((s) => s['kind'] == 'main').lastOrNull;
}

final class NextWorkout {
  NextWorkout({
    required this.runId,
    required this.program,
    required this.label,
    required this.gym,
    required this.inProgress,
    required this.ordinal,
  });
  final String runId;
  final String program;
  final String label;
  final String? gym;
  final String? inProgress;
  final int? ordinal;
}

/// One timeline row.
final class TimelineEvent {
  TimelineEvent(this.time, this.title, this.meta, {this.planned = false});
  final String time; // HH:MM
  final String title;
  final String meta;
  final bool planned;
}

/// The Today tab: "By area" cards or "By time" timeline.
final class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key, this.clock});

  /// Fixed time for tests and screenshots.
  final DateTime? clock;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

enum TodayView { byArea, byTime }

final class _TodayScreenState extends State<TodayScreen> {
  TodayView view = TodayView.byArea;

  @override
  Widget build(BuildContext context) => ProfileLoader<TodayData>(
    load: (p) => TodayData.load(p, clock: widget.clock),
    builder: (context, data) => ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SegmentedButton<TodayView>(
            segments: const [
              ButtonSegment(value: TodayView.byArea, label: Text('By area')),
              ButtonSegment(value: TodayView.byTime, label: Text('By time')),
            ],
            selected: {view},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => view = s.single),
          ),
        ),
        if (view == TodayView.byArea)
          ..._byArea(context, data)
        else
          ..._byTime(context, data),
      ],
    ),
  );

  List<Widget> _byArea(BuildContext context, TodayData d) {
    final f = Fmt.of(context);
    final rate = d.weeklyRate();
    final trend = d.trendValues();
    final latest = d.weighIns.lastOrNull;
    final budget = at(d.diary, ['budget']) as Map<String, Object?>?;
    final energy = at(budget, ['goals', 'energy']) as Map<String, Object?>?;
    final sleep = d.mainSleep;
    return [
      SectionCard(
        title: 'Body mass trend',
        trailing: rate == null
            ? null
            : Pill(
                '${rate > 0
                    ? '+'
                    : rate < 0
                    ? '−'
                    : ''}'
                '${f.number(rate.abs(), digits: 2)} kg / wk',
              ),
        child: trend.isEmpty
            ? const EmptyNote('No weigh-ins yet.')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: BigFigure(f.number(trend.last), unit: 'kg'),
                      ),
                      if (latest != null)
                        Muted(
                          'Weighed ${f.quantity(latest['value'])}\n'
                          '${f.clock(latest['observedAt'])}',
                          align: TextAlign.right,
                        )
                      else
                        const Muted(
                          'Not weighed today',
                          align: TextAlign.right,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LineChart(values: trend, raw: d.rawValues(), height: 64),
                ],
              ),
      ),
      SectionCard(
        title: 'Food budget',
        trailing: budget == null
            ? null
            : Pill(
                at(budget, ['dayType', 'name']) as String? ?? 'Plan day',
                warn: true,
              ),
        child: FoodSummary(diary: d.diary, energy: energy),
      ),
      SectionCard(
        title: 'Next workout',
        child: d.runs.isEmpty
            ? const EmptyNote('No active program.')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final run in d.runs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  run.label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                                Muted(
                                  run.inProgress != null
                                      ? '${run.program} · in progress'
                                      : run.program,
                                ),
                              ],
                            ),
                          ),
                          if (run.gym != null) Pill(run.gym!),
                        ],
                      ),
                    ),
                  for (final run in d.runs)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: FilledButton(
                        onPressed: () => openRunSession(context, run.runId),
                        child: Text(
                          run.inProgress != null
                              ? 'Resume ${run.label}'
                              : 'Start ${run.label}',
                        ),
                      ),
                    ),
                ],
              ),
      ),
      SectionCard(
        title: 'Routines',
        child: d.routines.isEmpty
            ? const EmptyNote('No routines.')
            : Column(children: [for (final r in d.routines) _RoutineRow(r)]),
      ),
      SectionCard(
        title: 'Last night',
        child: sleep == null
            ? const EmptyNote('No sleep logged for last night.')
            : Row(
                children: [
                  Expanded(
                    child: BigFigure(f.minutes(sleep['sleepPeriodMinutes'])),
                  ),
                  Muted(
                    '${f.clock(sleep['onset'])} → ${f.clock(sleep['wakeAt'])}'
                    '${sleep['quality'] != null ? '\nquality ${sleep['quality']}/5' : ''}',
                    align: TextAlign.right,
                  ),
                ],
              ),
      ),
    ];
  }

  List<Widget> _byTime(BuildContext context, TodayData d) {
    final f = Fmt.of(context);
    final events = <TimelineEvent>[];
    final sleep = d.mainSleep;
    if (sleep != null) {
      events.add(
        TimelineEvent(
          f.clock(sleep['onset']),
          'Slept ${f.minutes(sleep['sleepPeriodMinutes'])}',
          'woke ${f.clock(sleep['wakeAt'])}'
              '${sleep['quality'] != null ? ' · quality ${sleep['quality']}/5' : ''}',
        ),
      );
    }
    for (final o in d.weighIns) {
      events.add(
        TimelineEvent(
          f.clock(o['observedAt']),
          'Weighed ${f.quantity(o['value'])}',
          'body mass',
        ),
      );
    }
    final meals = <String, List<Map<String, Object?>>>{};
    for (final e in (d.diary['entries'] as List?) ?? const []) {
      final entry = (e as Map)['entry'] as Map;
      final key = '${f.clock(entry['at'])}|${entry['meal'] ?? 'Food'}';
      meals.putIfAbsent(key, () => []).add(e as Map<String, Object?>);
    }
    for (final MapEntry(:key, :value) in meals.entries) {
      final (time, meal) = (key.split('|').first, key.split('|').last);
      var kcal = 0.0;
      for (final e in value) {
        kcal +=
            double.tryParse(
              '${at(e, ['nutrition', 'nutrients', 'energy', 'value'])}',
            ) ??
            0;
      }
      events.add(
        TimelineEvent(
          time,
          '${meal[0].toUpperCase()}${meal.substring(1)} · '
          '${f.number(kcal, digits: 0)} kcal',
          value.map((e) => e['foodName'] ?? 'Quick entry').join(', '),
        ),
      );
    }
    for (final a in d.activities) {
      events.add(
        TimelineEvent(
          f.clock(a['start']),
          '${_capital('${a['kind']}')} · ${f.minutes(a['minutes'])}',
          [
            if (a['steps'] != null) '${f.number(a['steps'])} steps',
            if (a['countsToward'] case final List c when c.isNotEmpty)
              c.join(', '),
          ].join(' · '),
        ),
      );
    }
    for (final s in d.practices) {
      events.add(
        TimelineEvent(
          f.clock(s['startedAt']),
          '${s['practiceId'] ?? 'Practice'}',
          '${s['status'] ?? ''}',
        ),
      );
    }
    final anytime = <String>[];
    for (final r in d.routines) {
      if (r['status'] == 'done') continue;
      final name = at(r, ['routine', 'name'])! as String;
      final clock = at(r, ['due', 'clock']) as String?;
      if (clock == null) {
        anytime.add(name);
      } else {
        events.add(TimelineEvent(clock, name, 'routine', planned: true));
      }
    }
    for (final run in d.runs) {
      anytime.add('${run.label} · ${run.program}');
    }
    // Sleep onset belongs to the previous evening: keep it first.
    events.sort((a, b) {
      if (a.title.startsWith('Slept')) return -1;
      if (b.title.startsWith('Slept')) return 1;
      return a.time.compareTo(b.time);
    });
    final now =
        '${d.now.hour.toString().padLeft(2, '0')}:'
        '${d.now.minute.toString().padLeft(2, '0')}';
    final rows = <Widget>[];
    var nowShown = false;
    for (final e in events) {
      if (!nowShown &&
          !e.title.startsWith('Slept') &&
          e.time.compareTo(now) > 0) {
        rows.add(_NowMarker(now));
        nowShown = true;
      }
      rows.add(_TimelineRow(e));
    }
    if (!nowShown) rows.add(_NowMarker(now));
    return [
      if (events.isEmpty)
        const EmptyNote('Nothing logged or planned yet today.'),
      ...rows,
      if (anytime.isNotEmpty) ...[
        const SizedBox(height: 8),
        const SectionLabel('Any time today'),
        const SizedBox(height: 6),
        for (final a in anytime) Muted('• $a'),
      ],
    ];
  }
}

final class FoodSummary extends StatelessWidget {
  const FoodSummary({super.key, required this.diary, required this.energy});
  final Map<String, Object?> diary;
  final Map<String, Object?>? energy;

  @override
  Widget build(BuildContext context) {
    final f = Fmt.of(context);
    final eaten = at(diary, ['totals', 'nutrients', 'energy', 'value']);
    final target = at(energy, ['target', 'value']);
    final remaining = at(energy, ['remaining', 'value']);
    final over = at(energy, ['remaining', 'over']);
    String macro(String id) {
      final total = at(diary, ['totals', 'nutrients', id, 'value']);
      final goal =
          at(diary, ['budget', 'goals', id, 'target', 'value']) ??
          at(diary, ['budget', 'goals', id, 'maximum', 'value']);
      return goal == null
          ? '${f.number(total, digits: 0)} g'
          : '${f.number(total, digits: 0)} / ${f.number(goal, digits: 0)} g';
    }

    final logged = ((diary['entries'] as List?) ?? const []).isNotEmpty;
    if (!logged && target == null) {
      return const EmptyNote('Nothing logged today.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: target == null
                  ? BigFigure(
                      f.number(eaten ?? 0, digits: 0),
                      unit: 'kcal eaten',
                    )
                  : over != null
                  ? BigFigure(f.number(over, digits: 0), unit: 'kcal over')
                  : BigFigure(
                      f.number(remaining, digits: 0),
                      unit: 'kcal left',
                    ),
            ),
            if (target != null) Muted('of ${f.number(target, digits: 0)}'),
          ],
        ),
        if (target != null)
          Meter(
            (double.tryParse('${eaten ?? 0}') ?? 0) /
                (double.tryParse('$target') ?? 1),
          ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final (id, label) in [
              ('protein', 'protein'),
              ('carbohydrate', 'carbs'),
              ('fat', 'fat'),
            ])
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      macro(id),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Muted(label),
                  ],
                ),
              ),
          ],
        ),
        if (diary['status'] == 'partial')
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Muted('Partial day: totals count what is logged so far.'),
          ),
      ],
    );
  }
}

final class _RoutineRow extends StatelessWidget {
  const _RoutineRow(this.r);
  final Map<String, Object?> r;

  @override
  Widget build(BuildContext context) {
    final done = r['status'] == 'done';
    final clock = at(r, ['due', 'clock']) as String?;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            color: done ? scheme.primary : AppColors.of(context).line,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(at(r, ['routine', 'name'])! as String),
                Muted(
                  done
                      ? 'done'
                      : clock == null
                      ? 'any time'
                      : 'due $clock',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _TimelineRow extends StatelessWidget {
  const _TimelineRow(this.e);
  final TimelineEvent e;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 44,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                e.time,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
            ),
          ),
          SizedBox(
            width: 28,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                Container(width: 2, color: c.line),
                Padding(
                  padding: const EdgeInsets.only(top: 15),
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: e.planned ? scheme.surface : scheme.primary,
                      border: Border.all(
                        color: e.planned ? c.muted : scheme.primary,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: e.planned ? null : scheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: c.line),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (e.meta.isNotEmpty) Muted(e.meta),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _NowMarker extends StatelessWidget {
  const _NowMarker(this.time);
  final String time;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              'now',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Divider(color: color, thickness: 1.5)),
          const SizedBox(width: 6),
          Text(time, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}

String _capital(String s) => s.isEmpty
    ? s
    : '${s[0].toUpperCase()}${s.substring(1).replaceAll('-', ' ')}';
