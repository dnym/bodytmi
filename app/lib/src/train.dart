import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:material_ui/material_ui.dart';

import 'format.dart';
import 'gym_start.dart';
import 'history.dart';
import 'program_start.dart';
import 'profile.dart';
import 'session.dart';
import 'widgets.dart';

final class _TrainData {
  _TrainData(this.next, this.history, this.gymNames);
  final Map<String, String> gymNames;
  final List<
    ({
      Map<String, Object?> run,
      Map<String, Object?> day,
      Map<String, Object?>? workout,
    })
  >
  next;
  final List<Map<String, Object?>> history;
}

/// The Train tab: the next workout of each active program and recent
/// finished sessions. Logging a session comes in the next increment.
final class TrainScreen extends StatelessWidget {
  const TrainScreen({super.key});

  static Future<_TrainData> _load(ProfileClient p) async {
    final next =
        <
          ({
            Map<String, Object?> run,
            Map<String, Object?> day,
            Map<String, Object?>? workout,
          })
        >[];
    for (final run in await p.call<List<Object?>>('run list', {
      'status': 'active',
    })) {
      final r = run! as Map<String, Object?>;
      final schedule = await p.call<Map<String, Object?>>('run schedule', {
        'runId': r['id'],
        'count': 1,
      });
      final day = at(schedule, ['days', 0, 'day']) as Map<String, Object?>?;
      if (day == null) continue;
      final revision = await p.call<Map<String, Object?>>('store revision', {
        'templateId': day['templateId'],
        'revision': day['revision'],
      });
      next.add((
        run: r,
        day: day,
        workout: await _progressed(
          p,
          revision['definition'] as Map<String, Object?>?,
          day,
          '${r['id']}',
        ),
      ));
    }
    final history = [
      for (final s in await p.call<List<Object?>>('store history'))
        if ((s! as Map)['status'] == 'finalized') s as Map<String, Object?>,
    ]..sort((a, b) => '${b['startedAt']}'.compareTo('${a['startedAt']}'));
    final gymNames = <String, String>{
      for (final r in await p.call<List<Object?>>('gym list'))
        '${at(r, ['gym', 'id'])}':
            '${at(r, ['gym', 'name']) ?? at(r, ['gym', 'id'])}',
    };
    return _TrainData(next, history.take(20).toList(), gymNames);
  }

  /// The workout with each progressing slot's targets replaced by what its
  /// accepted progression prescribes next (the first working set).
  static Future<Map<String, Object?>?> _progressed(
    ProfileClient p,
    Map<String, Object?>? workout,
    Map<String, Object?> day,
    String runId,
  ) async {
    if (workout == null) return null;
    final slots = <Object?>[];
    for (final slot in (workout['slots'] as List?) ?? const []) {
      final s = slot as Map<String, Object?>;
      Map<String, Object?>? next;
      if (s['progression'] != null) {
        try {
          final track = await p.call<Map<String, Object?>>(
            'progression track',
            {
              'templateId': day['templateId'],
              'revision': day['revision'],
              'slotId': s['id'],
              'runId': runId,
              'asOf': isoInstant(DateTime.now()),
            },
          );
          if (track['resolved'] == true) {
            next = at(track, ['state', 'nextSets', 0]) as Map<String, Object?>?;
          }
        } on BodyTmiException {
          next = null;
        }
      }
      slots.add(
        next == null
            ? s
            : {
                ...s,
                'targets': {
                  ...((s['targets'] as Map<String, Object?>?) ?? const {}),
                  ...next,
                },
              },
      );
    }
    return {...workout, 'slots': slots};
  }

  @override
  Widget build(BuildContext context) => ProfileLoader<_TrainData>(
    load: _load,
    builder: (context, data) {
      final f = Fmt.of(context);
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (data.next.isEmpty)
            const SectionCard(
              title: 'Next workout',
              child: EmptyNote('No active program.'),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: data.next.isEmpty
                  ? FilledButton.icon(
                      onPressed: () => openProgramStart(context),
                      icon: const Icon(Icons.add),
                      label: const Text('Start a program'),
                    )
                  : TextButton.icon(
                      onPressed: () => openProgramStart(context),
                      icon: const Icon(Icons.add),
                      label: const Text('Start another program'),
                    ),
            ),
          ),
          for (final n in data.next)
            SectionCard(
              title: at(n.run, ['program', 'definition', 'name']) as String?,
              trailing: n.run['gym'] == null
                  ? null
                  : Pill(data.gymNames['${n.run['gym']}'] ?? '${n.run['gym']}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    n.day['label'] as String? ??
                        at(n.workout, ['name']) as String? ??
                        '',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final slot
                      in (at(n.workout, ['slots']) as List?) ?? const [])
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(_title('${(slot as Map)['exercise']}')),
                          ),
                          Muted(_targets(f, slot['targets'])),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => openRunSession(
                      context,
                      '${n.run['id']}',
                      day: n.day,
                      workout: n.workout,
                    ),
                    child: Text(
                      n.run['currentSessionId'] != null
                          ? 'Resume workout'
                          : 'Start workout',
                    ),
                  ),
                ],
              ),
            ),
          const ProgressCard(),
          SectionCard(
            title: 'History',
            child: data.history.isEmpty
                ? const EmptyNote('No finished workouts yet.')
                : Column(
                    children: [
                      for (final s in data.history)
                        InkWell(
                          onTap: () => openSession(context, '${s['id']}'),
                          child: _HistoryRow(s),
                        ),
                    ],
                  ),
          ),
        ],
      );
    },
  );

  static String _title(String id) => id.isEmpty
      ? id
      : '${id[0].toUpperCase()}${id.substring(1).replaceAll('-', ' ')}';

  static String _targets(Fmt f, Object? targets) {
    if (targets is! Map) return '';
    final mass = targets['mass'] ?? targets['load'];
    final reps = targets['reps'];
    if (mass != null && reps != null) {
      return '${f.quantity(mass, digits: 2)} × ${f.number((reps as Map)['value'])}';
    }
    return targets.values.map((q) => f.quantity(q, digits: 2)).join(' · ');
  }
}

final class _HistoryRow extends StatelessWidget {
  const _HistoryRow(this.s);
  final Map<String, Object?> s;

  @override
  Widget build(BuildContext context) {
    final f = Fmt.of(context);
    final sets = (s['sets'] as List?) ?? const [];
    final done = sets.where((x) => (x as Map)['status'] == 'completed').length;
    final started = DateTime.tryParse('${s['startedAt']}');
    final finished = DateTime.tryParse('${s['finishedAt']}');
    final minutes = started != null && finished != null
        ? finished.difference(started).inMinutes
        : null;
    final date = '${s['startedAt']}'.length >= 10
        ? f.shortDate('${s['startedAt']}'.substring(0, 10))
        : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  at(s, ['revision', 'definition', 'name']) as String? ??
                      '${s['id']}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Muted('$done of ${sets.length} sets · ${f.minutes(minutes)}'),
              ],
            ),
          ),
          Muted(date),
        ],
      ),
    );
  }
}

/// Starts (or resumes) the next workout of [runId] and opens it.
///
/// A new workout first asks where it is done when the profile has gyms and
/// the workout uses equipment; the chosen gym binds each exercise's
/// equipment for the session.
Future<void> openRunSession(
  BuildContext context,
  String runId, {
  Map<String, Object?>? day,
  Map<String, Object?>? workout,
}) async {
  final profile = ProfileScope.of(context);
  try {
    final run = await profile.call<Map<String, Object?>>('run show', {
      'runId': runId,
    });
    GymChoice? gym;
    final usesEquipment = ((workout?['slots'] as List?) ?? const []).any(
      (s) => (s as Map)['equipment'] != null,
    );
    if (run['currentSessionId'] == null && day != null && usesEquipment) {
      final gyms = await profile.call<List<Object?>>('gym list');
      if (gyms.isNotEmpty) {
        if (!context.mounted) return;
        gym = await chooseGym(
          context,
          templateId: '${day['templateId']}',
          revision: day['revision']! as int,
          runGym: run['gym'] as String?,
          workout: workout!,
        );
        if (gym == null) return;
      }
    }
    final id = await startRunSession(profile, runId, gym: gym);
    if (context.mounted) await openSession(context, id);
  } on BodyTmiException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

Future<void> openSession(BuildContext context, String id) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => SessionScreen(sessionId: id)));
