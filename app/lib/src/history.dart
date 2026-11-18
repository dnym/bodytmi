import 'package:material_ui/material_ui.dart';

import 'format.dart';
import 'profile.dart';
import 'widgets.dart';

/// One exercise as done (exercise, implementation and equipment), with its
/// separate series: a heavy and a light slot, or two programs, never merge.
final class ExerciseHistory {
  ExerciseHistory(this.key, this.context);
  final String key;
  final Map<String, Object?> context;
  final weight = <Map<String, Object?>>[]; // series of mass or load
  final reps = <Map<String, Object?>>[];

  String get exercise => '${context['exercise']}';

  /// The newest session's top weight, or its best reps without weight.
  Map<String, Object?>? get latestTop {
    final points = [
      for (final s in weight.isNotEmpty ? weight : reps)
        ...((s['points'] as List?) ?? const []).cast<Map<String, Object?>>(),
    ]..sort((a, b) => '${a['startedAt']}'.compareTo('${b['startedAt']}'));
    if (points.isEmpty) return null;
    final last = points.last['sessionId'];
    Map<String, Object?>? top;
    for (final p in points.where((p) => p['sessionId'] == last)) {
      if (top == null || _value(p) > _value(top)) top = p;
    }
    return top;
  }
}

double _value(Map<String, Object?> point) =>
    double.parse('${at(point, ['actual', 'value'])}');

String _pretty(String id) {
  final t = id.replaceAll('-', ' ');
  return t.isEmpty ? t : '${t[0].toUpperCase()}${t.substring(1)}';
}

/// Everything with finished history, grouped per exercise as done.
Future<List<ExerciseHistory>> exerciseHistories(ProfileClient p) async {
  final out = <String, ExerciseHistory>{};
  for (final metric in ['mass', 'load', 'reps']) {
    final r = await p.call<Map<String, Object?>>('store series', {
      'metric': metric,
    });
    for (final s in (r['series'] as List?) ?? const []) {
      final series = s as Map<String, Object?>;
      final c = (series['context'] as Map<String, Object?>?) ?? const {};
      final key = '${c['exercise']}|${c['implementation']}|${c['equipment']}';
      final h = out.putIfAbsent(key, () => ExerciseHistory(key, c));
      (metric == 'reps' ? h.reps : h.weight).add(series);
    }
  }
  final list = out.values.toList()
    ..sort((a, b) => a.exercise.compareTo(b.exercise));
  return list;
}

/// The exercise names from the catalog, else the id made readable.
Future<Map<String, String>> exerciseNames(ProfileClient p) async => {
  for (final r in await p.call<List<Object?>>('exercise list'))
    '${at(r, ['exercise', 'id'])}':
        '${at(r, ['exercise', 'name']) ?? _pretty('${at(r, ['exercise', 'id'])}')}',
};

/// The Train tab's list of exercises with history.
final class ProgressCard extends StatelessWidget {
  const ProgressCard({super.key});

  static Future<(List<ExerciseHistory>, Map<String, String>)> _load(
    ProfileClient p,
  ) async => (await exerciseHistories(p), await exerciseNames(p));

  @override
  Widget build(BuildContext context) =>
      ProfileLoader<(List<ExerciseHistory>, Map<String, String>)>(
        load: _load,
        builder: (context, data) {
          final (list, names) = data;
          final f = Fmt.of(context);
          return SectionCard(
            title: 'Progress',
            child: list.isEmpty
                ? const EmptyNote(
                    'Finished workouts show up here per exercise.',
                  )
                : Column(
                    children: [
                      for (final h in list)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(names[h.exercise] ?? _pretty(h.exercise)),
                          subtitle: Text(
                            [
                              _pretty('${h.context['implementation']}'),
                              if (h.context['equipment'] != null)
                                _pretty('${h.context['equipment']}'),
                            ].join(' · '),
                          ),
                          trailing: h.latestTop == null
                              ? null
                              : Text(
                                  f.quantity(
                                    at(h.latestTop, ['actual', 'entered']) ??
                                        h.latestTop!['actual'],
                                    digits: 3,
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ExerciseHistoryScreen(
                                history: h,
                                name: names[h.exercise] ?? _pretty(h.exercise),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          );
        },
      );
}

/// One exercise: a chart of the top weight (or reps) per workout for each
/// separate series, its recent workouts, and contextual records per rep
/// count. Records compare only sets with the other metrics equal.
final class ExerciseHistoryScreen extends StatelessWidget {
  const ExerciseHistoryScreen({
    super.key,
    required this.history,
    required this.name,
  });
  final ExerciseHistory history;
  final String name;

  bool _same(Object? context) {
    final c = (context as Map?) ?? const {};
    return c['exercise'] == history.context['exercise'] &&
        c['implementation'] == history.context['implementation'] &&
        c['equipment'] == history.context['equipment'];
  }

  Future<List<Map<String, Object?>>> _records(ProfileClient p) async {
    final out = <Map<String, Object?>>[];
    final metrics = {
      for (final s in history.weight.isNotEmpty ? history.weight : history.reps)
        '${s['metric']}',
    };
    for (final metric in metrics) {
      final r = await p.call<Map<String, Object?>>('store records', {
        'metric': metric,
        'direction': 'higher',
      });
      for (final g in (r['groups'] as List?) ?? const []) {
        if (_same((g as Map)['context'])) out.add(g as Map<String, Object?>);
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final f = Fmt.of(context);
    final main = history.weight.isNotEmpty ? history.weight : history.reps;
    // Reps per set, to describe a top weight set as "72.5 kg × 3".
    final repsBySet = <String, Object?>{
      for (final s in history.reps)
        for (final p in ((s['points'] as List?) ?? const []).cast<Map>())
          '${p['sessionId']}/${p['setId']}': at(p, ['actual', 'value']),
    };
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          for (final series in main) _seriesCard(f, series, repsBySet),
          ProfileLoader<List<Map<String, Object?>>>(
            load: _records,
            builder: (context, groups) => SectionCard(
              title: 'Records',
              child: groups.isEmpty
                  ? const EmptyNote('No records yet.')
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final g in _sorted(groups))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Expanded(child: Text(_heldText(f, g))),
                                Text(
                                  f.quantity(g['best'], digits: 3),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Muted(
                                  f.shortDate(
                                    _localDate(
                                      at(g, ['bestSources', 0, 'startedAt']),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 4),
                        const Muted(
                          'Best within this exercise as done, compared only '
                          'with sets at the same reps.',
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  static List<Map<String, Object?>> _sorted(
    List<Map<String, Object?>> g,
  ) => [...g]
    ..sort((a, b) {
      final ra = double.tryParse('${at(a, ['heldActuals', 'reps', 'value'])}');
      final rb = double.tryParse('${at(b, ['heldActuals', 'reps', 'value'])}');
      return (ra ?? 0).compareTo(rb ?? 0);
    });

  static String _heldText(Fmt f, Map<String, Object?> g) {
    final held = (g['heldActuals'] as Map?) ?? const {};
    final reps = at(held, ['reps', 'value']);
    final role = at(g, ['context', 'role']);
    final roleText = role == null || role == 'work' ? '' : ' ($role)';
    if (reps != null) return 'Best at ${f.number(reps)} reps$roleText';
    if (held.isEmpty) return 'Best$roleText';
    return 'Best at ${held.entries.map((e) => f.quantity(e.value, digits: 3)).join(', ')}$roleText';
  }

  static String _localDate(Object? instant) {
    final t = DateTime.tryParse('$instant')?.toLocal();
    return t == null ? '' : isoDate(t);
  }

  Widget _seriesCard(
    Fmt f,
    Map<String, Object?> series,
    Map<String, Object?> repsBySet,
  ) {
    final c = (series['context'] as Map?) ?? const {};
    final points = ((series['points'] as List?) ?? const [])
        .cast<Map<String, Object?>>();
    // The top set of each workout, oldest first.
    final top = <String, Map<String, Object?>>{};
    final count = <String, int>{};
    for (final p in points) {
      final id = '${p['sessionId']}';
      count[id] = (count[id] ?? 0) + 1;
      if (top[id] == null || _value(p) > _value(top[id]!)) top[id] = p;
    }
    final sessions = top.values.toList()
      ..sort((a, b) => '${a['startedAt']}'.compareTo('${b['startedAt']}'));
    final role = c['role'] == null || c['role'] == 'work'
        ? ''
        : ' · ${c['role']}';
    return SectionCard(
      title:
          '${_pretty('${c['templateId']}')} · ${_pretty('${c['slotId']}')}$role',
      trailing: Muted('${series['unit']}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (sessions.length > 1)
            LineChart(values: [for (final p in sessions) _value(p)], height: 90)
          else
            const Muted('One workout so far; a chart needs two.'),
          const SizedBox(height: 8),
          for (final p in sessions.reversed.take(10))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 72,
                    child: Muted(f.shortDate(_localDate(p['startedAt']))),
                  ),
                  Expanded(
                    child: Text(
                      [
                        f.quantity(
                          at(p, ['actual', 'entered']) ?? p['actual'],
                          digits: 3,
                        ),
                        if (series['metric'] != 'reps' &&
                            repsBySet['${p['sessionId']}/${p['setId']}'] !=
                                null)
                          '× ${f.number(repsBySet['${p['sessionId']}/${p['setId']}'])}',
                      ].join(' '),
                    ),
                  ),
                  Muted('${count['${p['sessionId']}']} sets'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
