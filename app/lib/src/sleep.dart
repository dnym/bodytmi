import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:material_ui/material_ui.dart';

import 'format.dart';
import 'profile.dart';
import 'quick_entry.dart';
import 'session.dart' show parseDecimal;
import 'theme.dart';
import 'widgets.dart';

/// Opens the Sleep screen (from More).
Future<void> openSleep(BuildContext context, {DateTime? clock}) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => SleepScreen(clock: clock)));

final class _SleepData {
  _SleepData(
    this.nights,
    this.stats,
    this.schedule,
    this.sun,
    this.location,
    this.marked,
  );
  final Set<String> marked;
  final List<Map<String, Object?>> nights;
  final Map<String, Object?> stats;
  final Map<String, Object?>? schedule;
  final Map<String, Object?>? sun;
  final Map<String, Object?>? location;
}

/// Sleep diary, schedule, four-week statistics and today's daylight.
final class SleepScreen extends StatelessWidget {
  const SleepScreen({super.key, this.clock});
  final DateTime? clock;

  DateTime get _now => clock ?? DateTime.now();

  Future<_SleepData> _load(ProfileClient p) async {
    final today = DateTime(_now.year, _now.month, _now.day);
    final until = isoDate(today.add(const Duration(days: 1)));
    final nights = await p.call<List<Object?>>('sleep list', {
      'from': isoDate(today.subtract(const Duration(days: 13))),
      'until': until,
    });
    final stats = await p.call<Map<String, Object?>>('sleep stats', {
      'from': isoDate(today.subtract(const Duration(days: 27))),
      'until': until,
    });
    final schedules = await p.call<List<Object?>>('sleep schedules');
    final profile = await p.call<Map<String, Object?>?>('profile show');
    final location =
        at(profile, ['profile', 'location']) as Map<String, Object?>?;
    Map<String, Object?>? sun;
    if (location != null) {
      sun = at(
        await p.call<Map<String, Object?>>('sleep sun', {
          'from': isoDate(today),
        }),
        ['days', 0],
      ) as Map<String, Object?>?;
    }
    Map<String, Object?>? schedule;
    for (final s in schedules.cast<Map<String, Object?>>()) {
      final from = '${at(s, ['schedule', 'from'])}';
      if (from.compareTo(isoDate(today)) <= 0) {
        schedule = s['schedule'] as Map<String, Object?>?;
      }
    }
    final marks = await p.call<List<Object?>>('sleep marks', {
      'from': isoDate(today.subtract(const Duration(days: 27))),
      'until': isoDate(today),
    });
    return _SleepData(
      nights.cast<Map<String, Object?>>(),
      stats,
      schedule,
      sun,
      location,
      {for (final m in marks) '${(m! as Map)['date']}'},
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sleep')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => showSleepEntry(context, clock: clock),
      icon: const Icon(Icons.add),
      label: const Text('Log sleep'),
    ),
    body: ProfileLoader<_SleepData>(
      load: _load,
      builder: (context, d) {
        final f = Fmt.of(context);
        final today = DateTime(_now.year, _now.month, _now.day);
        final main = at(d.stats, ['main']) as Map?;
        final regularity = at(d.stats, ['regularity']) as Map?;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          children: [
            SectionCard(
              title: 'Last 14 nights',
              trailing: d.schedule == null
                  ? null
                  : Muted(
                      'plan ${d.schedule!['sleepAt']}–${d.schedule!['wakeAt']}',
                    ),
              child: _NightChart(
                today: today,
                nights: d.nights,
                schedule: d.schedule,
              ),
            ),
            SectionCard(
              title: 'Averages · 4 weeks',
              trailing: Muted(
                '${d.stats['nightsLogged']} of ${d.stats['nights']} nights',
              ),
              child: main == null || d.stats['nightsLogged'] == 0
                  ? const EmptyNote('No nights logged in the last four weeks.')
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        BigFigure(
                          f.minutes(
                            double.tryParse(
                              '${at(main, ['sleepPeriod', 'value'])}',
                            )?.round(),
                          ),
                        ),
                        const Muted('asleep to awake, logged nights only'),
                        const SizedBox(height: 8),
                        for (final (key, label) in [
                          ('onset', 'Fell asleep'),
                          ('wake', 'Woke up'),
                          ('midpoint', 'Midpoint'),
                        ])
                          if (main[key] case final Map m)
                            _StatRow(
                              label,
                              '${m['mean']}  ±${m['spreadMinutes']} min',
                            ),
                        if (at(main, ['quality', 'value']) case final Object q)
                          _StatRow('Quality', '${f.number(q)} / 5'),
                        _StatRow(
                          'Regularity',
                          regularity?['status'] == 'resolved'
                              ? f.number(regularity!['value'], digits: 0)
                              : 'unavailable',
                          note: regularity?['status'] == 'resolved'
                              ? null
                              : '${regularity?['reason'] ?? ''} Mark consecutive '
                                    'days complete below.',
                        ),
                      ],
                    ),
            ),
            CompleteDaysCard(
              today: today,
              marked: d.marked,
              logged: {for (final n in d.nights) '${n['date']}'},
            ),
            _DaylightCard(sun: d.sun, location: d.location),
            _ScheduleCard(schedule: d.schedule, today: today),
            SectionCard(
              title: 'Nights',
              child: d.nights.isEmpty
                  ? const EmptyNote('No sleep logged in the last two weeks.')
                  : Column(
                      children: [
                        for (final n in d.nights.reversed)
                          InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              builder: (_) =>
                                  SleepSheet(now: _now, existing: n),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${n['kind'] == 'nap' ? 'Nap · ' : ''}'
                                          '${f.longDate(DateTime.parse('${n['date']}'))}',
                                        ),
                                        Muted(
                                          '${f.clock(n['onset'])} → ${f.clock(n['wakeAt'])}'
                                          '${n['quality'] == null ? '' : ' · quality ${n['quality']}/5'}',
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    f.minutes(n['sleepPeriodMinutes']),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    ),
  );
}

final class _StatRow extends StatelessWidget {
  const _StatRow(this.label, this.value, {this.note});
  final String label;
  final String value;
  final String? note;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
        if (note != null) Muted(note!.trim()),
      ],
    ),
  );
}

/// One row per night on an 18:00–14:00 axis: a bar from onset to wake,
/// dashed lines at the planned times. Missing nights stay empty, never zero.
final class _NightChart extends StatelessWidget {
  const _NightChart({
    required this.today,
    required this.nights,
    required this.schedule,
  });
  final DateTime today;
  final List<Map<String, Object?>> nights;
  final Map<String, Object?>? schedule;

  @override
  Widget build(BuildContext context) {
    final f = Fmt.of(context);
    final byDate = <String, List<Map<String, Object?>>>{};
    for (final n in nights) {
      byDate.putIfAbsent('${n['date']}', () => []).add(n);
    }
    int? planned(String key) {
      final v = schedule?[key];
      if (v is! String) return null;
      final m = int.parse(v.substring(0, 2)) * 60 + int.parse(v.substring(3));
      return m < 18 * 60 ? m + 24 * 60 : m;
    }

    return Column(
      children: [
        for (var i = 13; i >= 0; i--)
          () {
            final day = today.subtract(Duration(days: i));
            final list = byDate[isoDate(day)] ?? const [];
            return SizedBox(
              height: 18,
              child: Row(
                children: [
                  SizedBox(
                    width: 52,
                    child: Text(
                      f.shortDate(isoDate(day)),
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.of(context).muted,
                      ),
                    ),
                  ),
                  Expanded(
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _NightPainter(
                        spans: [
                          for (final n in list)
                            (
                              _axis('${n['onset']}', day, previous: true),
                              _axis('${n['wakeAt']}', day),
                              n['kind'] == 'nap',
                            ),
                        ],
                        plan: (planned('sleepAt'), planned('wakeAt')),
                        color: Theme.of(context).colorScheme.primary,
                        faint: AppColors.of(context).line,
                        muted: AppColors.of(context).muted,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }(),
        const SizedBox(height: 4),
        Row(
          children: [
            const SizedBox(width: 52),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) => SizedBox(
                  height: 14,
                  child: Stack(
                    children: [
                      // Hours after 18:00 on the 20-hour axis.
                      for (final (label, hours) in [
                        ('18', 0),
                        ('00', 6),
                        ('06', 12),
                        ('12', 18),
                      ])
                        Positioned(
                          left: box.maxWidth * hours / 20,
                          child: Text(
                            label,
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.of(context).muted,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Minutes after 18:00 the evening before the wake day.
  static int _axis(String instant, DateTime wakeDay, {bool previous = false}) {
    final local = instant.length >= 16
        ? DateTime(
            int.parse(instant.substring(0, 4)),
            int.parse(instant.substring(5, 7)),
            int.parse(instant.substring(8, 10)),
            int.parse(instant.substring(11, 13)),
            int.parse(instant.substring(14, 16)),
          )
        : wakeDay;
    final origin = DateTime(wakeDay.year, wakeDay.month, wakeDay.day - 1, 18);
    return local.difference(origin).inMinutes;
  }
}

final class _NightPainter extends CustomPainter {
  _NightPainter({
    required this.spans,
    required this.plan,
    required this.color,
    required this.faint,
    required this.muted,
  });
  final List<(int, int, bool)> spans;
  final (int?, int?) plan;
  final Color color;
  final Color faint;
  final Color muted;
  static const _range = 20 * 60;

  @override
  void paint(Canvas canvas, Size size) {
    double x(int minutes) => size.width * (minutes.clamp(0, _range) / _range);
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      Paint()
        ..color = faint
        ..strokeWidth = 1,
    );
    for (final (from, to, nap) in spans) {
      canvas.drawRRect(
        RRect.fromLTRBR(
          x(from),
          3,
          x(to),
          size.height - 3,
          const Radius.circular(4),
        ),
        Paint()..color = nap ? color.withValues(alpha: 0.5) : color,
      );
    }
    final dash = Paint()
      ..color = muted
      ..strokeWidth = 1;
    for (final p in [plan.$1, plan.$2]) {
      if (p == null) continue;
      final px = x(p - 18 * 60 + (p < 18 * 60 ? 24 * 60 : 0));
      for (var y = 0.0; y < size.height; y += 4) {
        canvas.drawLine(Offset(px, y), Offset(px, y + 2), dash);
      }
    }
  }

  @override
  bool shouldRepaint(_NightPainter old) => true;
}

final class _DaylightCard extends StatelessWidget {
  const _DaylightCard({required this.sun, required this.location});
  final Map<String, Object?>? sun;
  final Map<String, Object?>? location;

  @override
  Widget build(BuildContext context) {
    final f = Fmt.of(context);
    String event(String threshold, String kind) {
      final events =
          (at(sun, ['thresholds', threshold, 'events']) as List?) ?? [];
      for (final e in events.cast<Map>()) {
        if (e['event'] == kind) return f.clock(e['at']);
      }
      return '—';
    }

    return SectionCard(
      title: 'Daylight today',
      trailing: TextButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => _LocationDialog(location: location),
        ),
        child: Text(location == null ? 'Set location' : 'Change'),
      ),
      child: sun == null
          ? const EmptyNote(
              'Set your location to see sunrise, sunset and twilight.',
            )
          : Column(
              children: [
                _StatRow(
                  'Sunrise → sunset',
                  '${event('sun', 'rise')} → ${event('sun', 'set')}',
                ),
                _StatRow(
                  'Civil twilight',
                  '${event('civil', 'rise')} → ${event('civil', 'set')}',
                ),
                _StatRow(
                  'Sun above the horizon',
                  f.minutes(at(sun, ['thresholds', 'sun', 'minutesAbove'])),
                ),
              ],
            ),
    );
  }
}

final class _LocationDialog extends StatefulWidget {
  const _LocationDialog({required this.location});
  final Map<String, Object?>? location;

  @override
  State<_LocationDialog> createState() => _LocationDialogState();
}

final class _LocationDialogState extends State<_LocationDialog> {
  late final latitude = TextEditingController(
    text: '${widget.location?['latitude'] ?? ''}',
  );
  late final longitude = TextEditingController(
    text: '${widget.location?['longitude'] ?? ''}',
  );
  late final zone = TextEditingController(
    text: '${widget.location?['timeZone'] ?? ''}',
  );
  String? problem;

  @override
  void dispose() {
    latitude.dispose();
    longitude.dispose();
    zone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final locale = Fmt.of(context).locale;
    final lat = parseDecimal(locale, latitude.text.trim());
    final lon = parseDecimal(locale, longitude.text.trim());
    if (lat == null || lon == null || zone.text.trim().isEmpty) {
      setState(() => problem = 'Enter latitude, longitude and time zone.');
      return;
    }
    final profile = ProfileScope.of(context);
    try {
      final current = await profile.call<Map<String, Object?>?>('profile show');
      await profile.write('profile set', {
        'profile': {
          ...?(current?['profile'] as Map<String, Object?>?),
          'location': {
            'latitude': lat,
            'longitude': lon,
            'timeZone': zone.text.trim(),
          },
        },
        'expectedRevision': current?['revision'] ?? 0,
      });
      if (mounted) Navigator.pop(context);
    } on BodyTmiException catch (e) {
      setState(() => problem = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Location'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Muted(
            'Used only on this phone for daylight and sleep regularity. '
            'Decimal degrees; time zone as an IANA name such as '
            'Europe/Stockholm.',
          ),
          TextField(
            controller: latitude,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            decoration: const InputDecoration(labelText: 'Latitude'),
          ),
          TextField(
            controller: longitude,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            decoration: const InputDecoration(labelText: 'Longitude'),
          ),
          TextField(
            controller: zone,
            decoration: const InputDecoration(labelText: 'Time zone'),
          ),
          if (problem != null) ProblemText(problem!),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );
}

final class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({required this.schedule, required this.today});
  final Map<String, Object?>? schedule;
  final DateTime today;

  @override
  Widget build(BuildContext context) => SectionCard(
    title: 'Schedule',
    trailing: TextButton(
      onPressed: () => _edit(context),
      child: Text(schedule == null ? 'Set' : 'Change'),
    ),
    child: schedule == null
        ? const EmptyNote('No planned sleep and wake times yet.')
        : _StatRow(
            'Sleep → wake',
            '${schedule!['sleepAt']} → ${schedule!['wakeAt']}',
          ),
  );

  Future<void> _edit(BuildContext context) async {
    TimeOfDay parse(Object? v, int h) => v is String
        ? TimeOfDay(
            hour: int.parse(v.substring(0, 2)),
            minute: int.parse(v.substring(3)),
          )
        : TimeOfDay(hour: h, minute: 0);
    final sleep = await showTimePicker(
      context: context,
      helpText: 'Planned sleep time',
      initialTime: parse(schedule?['sleepAt'], 23),
    );
    if (sleep == null || !context.mounted) return;
    final wake = await showTimePicker(
      context: context,
      helpText: 'Planned wake time',
      initialTime: parse(schedule?['wakeAt'], 7),
    );
    if (wake == null || !context.mounted) return;
    String hm(TimeOfDay t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final profile = ProfileScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final revisions = await profile.call<List<Object?>>('sleep schedules');
      await profile.write('sleep schedule', {
        'schedule': {
          'from': isoDate(today),
          'sleepAt': hm(sleep),
          'wakeAt': hm(wake),
        },
        'expectedRevision': revisions.length,
      });
      messenger.showSnackBar(
        SnackBar(content: Text('Schedule ${hm(sleep)}–${hm(wake)} from today')),
      );
    } on BodyTmiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// Logs a sleep, or edits or deletes [existing] (as `sleep list` returns
/// it). Fields the sheet does not show are kept while they stay consistent
/// with the edited times.
final class SleepSheet extends StatefulWidget {
  const SleepSheet({super.key, required this.now, this.existing});
  final DateTime now;
  final Map<String, Object?>? existing;

  @override
  State<SleepSheet> createState() => _SleepSheetState();
}

final class _SleepSheetState extends State<SleepSheet> {
  late DateTime wake;
  late DateTime asleep;
  int? quality;
  bool nap = false;
  String? problem;

  static DateTime _local(Object? instant) =>
      DateTime.parse('$instant').toLocal();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      wake = _local(e['wakeAt']);
      asleep = _local(e['onset']);
      quality = e['quality'] as int?;
      nap = e['kind'] == 'nap';
      return;
    }
    final n = widget.now;
    final seven = DateTime(n.year, n.month, n.day, 7);
    wake = n.isBefore(seven) ? n : seven;
    asleep = DateTime(wake.year, wake.month, wake.day - 1, 23);
  }

  /// Onset on the wake day when it is before the wake time, else the day
  /// before; a night belongs to the day you woke.
  DateTime get onset {
    final same = DateTime(
      wake.year,
      wake.month,
      wake.day,
      asleep.hour,
      asleep.minute,
    );
    return same.isBefore(wake) ? same : same.subtract(const Duration(days: 1));
  }

  Map<String, Object?> _record() {
    final e = widget.existing;
    final start = onset;
    final record = <String, Object?>{
      'id': e?['id'] ?? 'sleep-${stamp(wake)}',
      'kind': nap ? 'nap' : 'main',
      'asleepAt': isoInstant(start),
      'wakeAt': isoInstant(wake),
      'quality': ?quality,
    };
    if (e == null) return record;
    if (e['bedAt'] case final String bed
        when !DateTime.parse(bed).isAfter(start)) {
      record['bedAt'] = bed;
    }
    if (e['outOfBedAt'] case final String out
        when !DateTime.parse(out).isBefore(wake)) {
      record['outOfBedAt'] = out;
    }
    final period = wake.difference(start).inMinutes;
    if (e['awakeMinutes'] case final int awake when awake < period) {
      record['awakeMinutes'] = awake;
    }
    for (final key in ['awakenings', 'approximate', 'notes']) {
      if (e[key] != null) record[key] = e[key];
    }
    return record;
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this sleep?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await saveAndClose(
      context,
      'Sleep deleted',
      (p) => p.write('sleep delete', {
        'id': widget.existing!['id'],
        'expectedVersion': widget.existing!['version'],
        'confirm': true,
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final minutes = wake.difference(onset).inMinutes;
    final editing = widget.existing != null;
    return EntrySheet(
      title: editing ? (nap ? 'Nap' : 'Night') : (nap ? 'Nap' : 'Last night'),
      action: 'Save',
      onAction: () => saveAndClose(
        context,
        editing ? 'Sleep updated' : 'Sleep saved',
        (p) => editing
            ? p.write('sleep update', {
                'id': widget.existing!['id'],
                'expectedVersion': widget.existing!['version'],
                'sleep': _record(),
              })
            : p.write('sleep record', {'sleep': _record()}),
      ),
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Nap'),
          value: nap,
          onChanged: (v) => setState(() => nap = v),
        ),
        TimeRow(
          label: 'Fell asleep',
          value: asleep,
          onChanged: (t) => setState(() => asleep = t),
        ),
        TimeRow(
          label: 'Woke up',
          value: wake,
          onChanged: (t) => setState(() => wake = t),
        ),
        Muted(Fmt.of(context).minutes(minutes)),
        const SizedBox(height: 12),
        const Text('Quality'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            for (var q = 1; q <= 5; q++)
              ChoiceChip(
                label: Text('$q'),
                selected: quality == q,
                onSelected: (on) => setState(() => quality = on ? q : null),
              ),
          ],
        ),
        if (editing)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        if (problem != null) ProblemText(problem!),
      ],
    );
  }
}

/// Marks days on which every sleep and nap is logged, so the time outside
/// logged sleep was awake; the regularity score compares consecutive
/// marked days. Today is not offered: its night has not happened yet.
final class CompleteDaysCard extends StatefulWidget {
  const CompleteDaysCard({
    super.key,
    required this.today,
    required this.marked,
    required this.logged,
  });
  final DateTime today;
  final Set<String> marked;
  final Set<String> logged;

  @override
  State<CompleteDaysCard> createState() => _CompleteDaysCardState();
}

final class _CompleteDaysCardState extends State<CompleteDaysCard> {
  bool busy = false;

  List<DateTime> get _days => [
    for (var i = 14; i >= 1; i--) widget.today.subtract(Duration(days: i)),
  ];

  Future<void> _mark(List<String> dates, bool complete) async {
    if (busy || dates.isEmpty) return;
    final profile = ProfileScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => busy = true);
    try {
      for (final d in dates) {
        await profile.write('sleep mark', {
          'date': d,
          'status': complete ? 'complete' : 'unmarked',
        });
      }
    } on BodyTmiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = Fmt.of(context);
    final unmarkedLogged = [
      for (final d in _days)
        // A day touches the night ending that morning and the one starting
        // that evening (logged under the next date).
        if (widget.logged.contains(isoDate(d)) &&
            widget.logged.contains(isoDate(d.add(const Duration(days: 1)))) &&
            !widget.marked.contains(isoDate(d)))
          isoDate(d),
    ];
    return SectionCard(
      title: 'Complete days',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Muted(
            'Mark a day when every sleep and nap touching it is logged; time '
            'outside them then counts as awake. Unmarked days stay unknown.',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final d in _days)
                FilterChip(
                  label: Text('${f.longDate(d).substring(0, 3)} ${d.day}'),
                  selected: widget.marked.contains(isoDate(d)),
                  onSelected: busy ? null : (on) => _mark([isoDate(d)], on),
                ),
            ],
          ),
          if (unmarkedLogged.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: busy ? null : () => _mark(unmarkedLogged, true),
                child: Text(
                  'Mark the ${unmarkedLogged.length} '
                  'day${unmarkedLogged.length == 1 ? '' : 's'} with both nights logged',
                ),
              ),
            ),
        ],
      ),
    );
  }
}
