import 'package:bodytmi_application/bodytmi_application.dart'
    show canonicalJson;
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:material_ui/material_ui.dart';

import 'format.dart';
import 'profile.dart';
import 'quick_entry.dart';
import 'session.dart' show parseDecimal;
import 'widgets.dart';

/// Opens Goals & trials (from More).
Future<void> openGoals(BuildContext context, {DateTime? clock}) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => GoalsScreen(clock: clock)));

/// Daily metrics offered when making goals and trials. Each is an ordinary
/// `bodytmi-daily-metric/1`: a day without data is unknown, never zero.
const metricPresets = <(String, Map<String, Object?>, String)>[
  (
    'Steps per day',
    {'source': 'observation', 'measure': 'steps', 'summary': 'sum'},
    'steps',
  ),
  (
    'Body mass (trend)',
    {
      'source': 'observation',
      'measure': 'body-mass',
      'attributes': {'context': 'health'},
      'resolved': true,
    },
    'kg',
  ),
  (
    'Sleep, asleep to awake',
    {'source': 'sleep', 'field': 'sleepPeriodMinutes'},
    'min',
  ),
  ('Sleep quality', {'source': 'sleep', 'field': 'quality'}, '1–5'),
  (
    'Energy eaten',
    {'source': 'diary', 'nutrient': 'energy', 'field': 'total'},
    'kcal',
  ),
  (
    'Protein eaten',
    {'source': 'diary', 'nutrient': 'protein', 'field': 'total'},
    'g',
  ),
  ('Practice minutes', {'source': 'practice', 'field': 'minutes'}, 'min'),
  (
    'Training sessions',
    {'source': 'training', 'field': 'sessions'},
    'sessions',
  ),
  (
    'Mood',
    {'source': 'observation', 'measure': 'mood', 'summary': 'mean'},
    '0–10',
  ),
  (
    'Energy level',
    {'source': 'observation', 'measure': 'energy-level', 'summary': 'mean'},
    '0–10',
  ),
];

String _key(Object? json) => canonicalJson(json);

/// A readable name and unit for a metric, from the presets when it is one.
(String, String) metricName(Object? metric) {
  for (final (name, m, unit) in metricPresets) {
    if (_key(m) == _key(metric)) return (name, unit);
  }
  final m = (metric as Map?) ?? const {};
  return (
    '${m['source']} ${m['measure'] ?? m['field'] ?? m['nutrient'] ?? ''}'
        .trim(),
    '',
  );
}

const _aggregates = {
  'daysMet': 'Days the target is met',
  'mean': 'Average over the period',
  'latest': 'Latest value',
  'sum': 'Total over the period',
  'min': 'Lowest day',
  'max': 'Highest day',
};

final class _GoalsData {
  _GoalsData(
    this.goals,
    this.planGoals,
    this.progress,
    this.today,
    this.trials,
    this.reviews,
  );
  final List<Map<String, Object?>> reviews;
  final List<Map<String, Object?>> goals;
  final List<Object?> planGoals;
  final Map<String, Map<String, Object?>> progress;
  final Map<String, Object?> today;
  final List<(Map<String, Object?>, Map<String, Object?>)> trials;
}

final class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key, this.clock});
  final DateTime? clock;

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

enum _Tab { goals, routines, trials, reviews }

final class _GoalsScreenState extends State<GoalsScreen> {
  _Tab tab = _Tab.goals;

  DateTime get _now => widget.clock ?? DateTime.now();
  String get _today => isoDate(_now);

  Future<_GoalsData> _load(ProfileClient p) async {
    final list = await p.call<Map<String, Object?>>('goal list');
    final goals = [
      for (final g in (list['goals'] as List?) ?? const [])
        g as Map<String, Object?>,
    ];
    final progress = <String, Map<String, Object?>>{};
    for (final g in goals) {
      if (g['status'] != 'active') continue;
      progress['${g['id']}'] = await p.call<Map<String, Object?>>(
        'goal progress',
        {'id': g['id'], 'asOf': _today},
      );
    }
    final trials = <(Map<String, Object?>, Map<String, Object?>)>[];
    for (final t in await p.call<List<Object?>>('trial list')) {
      final trial = t! as Map<String, Object?>;
      trials.add((
        trial,
        await p.call<Map<String, Object?>>('trial report', {'id': trial['id']}),
      ));
    }
    return _GoalsData(
      goals,
      (list['planGoals'] as List?) ?? const [],
      progress,
      await p.call<Map<String, Object?>>('today show', {'date': _today}),
      trials,
      [
        for (final r in await p.call<List<Object?>>('review list'))
          r! as Map<String, Object?>,
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Goals & trials')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _add(context),
      icon: const Icon(Icons.add),
      label: Text(switch (tab) {
        _Tab.goals => 'Add goal',
        _Tab.routines => 'Add routine',
        _Tab.trials => 'Add trial',
        _Tab.reviews => 'Add review',
      }),
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: SegmentedButton<_Tab>(
            segments: const [
              ButtonSegment(value: _Tab.goals, label: Text('Goals')),
              ButtonSegment(value: _Tab.routines, label: Text('Routines')),
              ButtonSegment(value: _Tab.trials, label: Text('Trials')),
              ButtonSegment(value: _Tab.reviews, label: Text('Reviews')),
            ],
            selected: {tab},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => tab = s.single),
          ),
        ),
        Expanded(
          child: ProfileLoader<_GoalsData>(
            load: _load,
            builder: (context, d) => ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
              children: switch (tab) {
                _Tab.goals => _goals(context, d),
                _Tab.routines => _routines(context, d),
                _Tab.trials => _trials(context, d),
                _Tab.reviews => [
                  if (d.reviews.isEmpty)
                    const SectionCard(
                      child: EmptyNote(
                        'No reviews yet. A review is a named set of daily '
                        'measures you look at together, e.g. every Sunday.',
                      ),
                    ),
                  for (final r in d.reviews)
                    ReviewCard(
                      key: ValueKey('${r['id']}#${r['version']}'),
                      review: r,
                      today: _now,
                    ),
                ],
              },
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> _add(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => switch (tab) {
      _Tab.goals => GoalSheet(today: _now),
      _Tab.routines => RoutineSheet(today: _now),
      _Tab.trials => TrialSheet(today: _now),
      _Tab.reviews => const ReviewSheet(),
    },
  );

  // ------------------------------------------------------------- goals

  List<Widget> _goals(BuildContext context, _GoalsData d) {
    final f = Fmt.of(context);
    String target(Map<String, Object?> goal, String unit) {
      final t = (goal['target'] as Map?) ?? const {};
      final u = unit.isEmpty ? '' : ' $unit';
      return switch (t['relation']) {
        'atLeast' => '≥ ${f.number(t['value'])}$u',
        'atMost' => '≤ ${f.number(t['value'])}$u',
        'within' => '${f.number(t['minimum'])}–${f.number(t['maximum'])}$u',
        _ => '',
      };
    }

    return [
      for (final g in d.planGoals.cast<Map>())
        SectionCard(
          title: 'From your diet plan',
          child: Text(
            [
              '${g['name'] ?? g['planId'] ?? 'Plan target'}',
              if (at(g, ['target', 'measure']) case final Object m) '$m',
              if (at(g, ['target', 'relation']) case final Object r)
                '${r == 'atMost' ? '≤' : '≥'} ${at(g, ['target', 'value', 'value']) ?? at(g, ['target', 'value'])}',
            ].join(' · '),
          ),
        ),
      if (d.goals.isEmpty)
        const SectionCard(
          child: EmptyNote(
            'No goals yet. A goal follows one daily measure over a period; '
            'days without data are unknown, not failures.',
          ),
        ),
      for (final g in d.goals)
        () {
          final (name, unit) = metricName(g['metric']);
          final p = d.progress['${g['id']}'];
          final status = '${p?['status'] ?? g['status']}';
          return SectionCard(
            title: name,
            trailing: Pill(
              status,
              warn: status == 'not-met' || status == 'unknown',
            ),
            child: InkWell(
              onTap: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => GoalSheet(today: _now, existing: g),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${g['name']}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Muted(
                    '${_aggregates[g['aggregate']] ?? g['aggregate']}: '
                    '${target(g, unit)} · from ${f.shortDate('${g['from']}')}',
                  ),
                  if (p != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      g['aggregate'] == 'daysMet'
                          ? '${p['daysMet'] ?? 0} of ${p['knownDays']} known days met'
                                ' (${p['days']} days)'
                          : p['value'] == null
                          ? 'No data yet (${p['knownDays']} known days)'
                          : 'Now ${f.number(p['value'])}${unit.isEmpty ? '' : ' $unit'}'
                                ' over ${p['knownDays']} known days',
                    ),
                  ],
                ],
              ),
            ),
          );
        }(),
    ];
  }

  // ---------------------------------------------------------- routines

  List<Widget> _routines(BuildContext context, _GoalsData d) {
    final routines = [
      for (final r in (d.today['routines'] as List?) ?? const [])
        r as Map<String, Object?>,
    ];
    return [
      if (routines.isEmpty)
        const SectionCard(child: EmptyNote('No routines yet.')),
      for (final r in routines)
        SectionCard(
          child: Row(
            children: [
              Icon(
                r['status'] == 'done'
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                color: r['status'] == 'done'
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${at(r, ['routine', 'name'])}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Muted(_routineLine(r)),
                  ],
                ),
              ),
              if (at(r, ['routine', 'action', 'kind']) == 'check')
                TextButton(
                  onPressed: () => _check(context, r),
                  child: Text(r['status'] == 'done' ? 'Undo' : 'Done'),
                ),
            ],
          ),
        ),
      const Muted(
        'Routines are done when their evidence is logged (a walk, a '
        'practice, a weigh-in) or, for checks, when you tick them. A day '
        'not logged is not a missed day; there are no streaks.',
      ),
    ];
  }

  static String _routineLine(Map<String, Object?> r) {
    final action = (at(r, ['routine', 'action']) as Map?) ?? const {};
    final what = switch (action['kind']) {
      'practice' => 'practice ${action['practiceId']}',
      'activity' => 'activity: ${action['category']}',
      'observation' => 'log ${action['measure']}',
      _ => 'tick when done',
    };
    final due = at(r, ['due', 'clock']);
    return [
      what,
      if (due != null) 'due $due',
      if (r['status'] == 'done') 'done',
    ].join(' · ');
  }

  Future<void> _check(BuildContext context, Map<String, Object?> r) async {
    final profile = ProfileScope.of(context);
    try {
      await profile.write('routine check', {
        'routineId': at(r, ['routine', 'id']),
        'date': _today,
        'at': isoInstant(DateTime.now()),
        if (r['status'] == 'done') 'undo': true,
      });
    } on BodyTmiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  // ------------------------------------------------------------ trials

  List<Widget> _trials(BuildContext context, _GoalsData d) {
    final f = Fmt.of(context);
    return [
      if (d.trials.isEmpty)
        const SectionCard(
          child: EmptyNote(
            'No trials yet. A trial compares a baseline period with a period '
            'of doing something differently.',
          ),
        ),
      for (final (trial, report) in d.trials)
        SectionCard(
          title: trial['conclusion'] == null
              ? 'Trial'
              : 'Concluded · ${at(trial, ['conclusion', 'decision'])}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${trial['question']}',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Muted(
                '${at(trial, ['action', 'description'])} · baseline '
                '${f.shortDate('${at(trial, ['baseline', 'from'])}')}–'
                '${f.shortDate('${at(trial, ['baseline', 'until'])}')}, trial '
                '${f.shortDate('${at(trial, ['trial', 'from'])}')}–'
                '${f.shortDate('${at(trial, ['trial', 'until'])}')}',
              ),
              const SizedBox(height: 8),
              for (final o in (report['outcomes'] as List?) ?? const [])
                () {
                  final (name, unit) = metricName((o as Map)['metric']);
                  String side(String key) {
                    final s = (o[key] as Map?) ?? const {};
                    return s['mean'] == null
                        ? 'no data (${s['known']}/${s['days']} days)'
                        : '${f.number(s['mean'])} (${s['known']}/${s['days']} days)';
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$name${unit.isEmpty ? '' : ' ($unit)'}'),
                        Muted(
                          'baseline ${side('baseline')} → trial ${side('trial')}'
                          '${o['meanDifference'] == null ? '' : ' · difference ${f.number(o['meanDifference'])}'}',
                        ),
                      ],
                    ),
                  );
                }(),
              Muted('${report['note'] ?? ''}'),
              if (trial['conclusion'] == null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => _ConcludeDialog(trial: trial),
                    ),
                    child: const Text('Conclude…'),
                  ),
                ),
            ],
          ),
        ),
    ];
  }
}

final class _ConcludeDialog extends StatefulWidget {
  const _ConcludeDialog({required this.trial});
  final Map<String, Object?> trial;

  @override
  State<_ConcludeDialog> createState() => _ConcludeDialogState();
}

final class _ConcludeDialogState extends State<_ConcludeDialog> {
  String? decision;
  final notes = TextEditingController();
  String? problem;

  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (decision == null) {
      setState(() => problem = 'Choose what you decided.');
      return;
    }
    try {
      await ProfileScope.of(context).write('trial conclude', {
        'id': widget.trial['id'],
        'expectedVersion': widget.trial['version'],
        'decision': decision,
        'at': isoInstant(DateTime.now()),
        if (notes.text.trim().isNotEmpty) 'notes': notes.text.trim(),
      });
      if (mounted) Navigator.pop(context);
    } on BodyTmiException catch (e) {
      setState(() => problem = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Conclude the trial'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final d in ['keep', 'adjust', 'stop', 'unclear'])
                ChoiceChip(
                  label: Text(d),
                  selected: decision == d,
                  onSelected: (_) => setState(() => decision = d),
                ),
            ],
          ),
          TextField(
            controller: notes,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
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
      FilledButton(onPressed: _save, child: const Text('Conclude')),
    ],
  );
}

/// A date row that opens the date picker.
final class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    trailing: Text(Fmt.of(context).longDate(value)),
    onTap: () async {
      final picked = await showDatePicker(
        context: context,
        initialDate: value,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (picked != null) onChanged(picked);
    },
  );
}

/// Adds a goal, or edits one (name, target, status).
final class GoalSheet extends StatefulWidget {
  const GoalSheet({super.key, required this.today, this.existing});
  final DateTime today;
  final Map<String, Object?>? existing;

  @override
  State<GoalSheet> createState() => _GoalSheetState();
}

final class _GoalSheetState extends State<GoalSheet> {
  final name = TextEditingController();
  final value = TextEditingController();
  int preset = 0;
  String aggregate = 'daysMet';
  String relation = 'atLeast';
  String status = 'active';
  late DateTime from = widget.today;
  String? problem;

  @override
  void initState() {
    super.initState();
    final g = widget.existing;
    if (g == null) return;
    name.text = '${g['name']}';
    final i = metricPresets.indexWhere((p) => _key(p.$2) == _key(g['metric']));
    preset = i < 0 ? 0 : i;
    aggregate = '${g['aggregate']}';
    relation = '${at(g, ['target', 'relation'])}';
    value.text = '${at(g, ['target', 'value']) ?? ''}';
    status = '${g['status']}';
    from = DateTime.parse('${g['from']}');
  }

  @override
  void dispose() {
    name.dispose();
    value.dispose();
    super.dispose();
  }

  void _save() {
    final v = parseDecimal(Fmt.of(context).locale, value.text.trim());
    if (name.text.trim().isEmpty || v == null) {
      setState(() => problem = 'Give the goal a name and a target value.');
      return;
    }
    final g = widget.existing;
    final goal = {
      'id': g?['id'] ?? 'goal-${stamp(DateTime.now())}',
      'name': name.text.trim(),
      'metric': g?['metric'] ?? metricPresets[preset].$2,
      'aggregate': aggregate,
      'target': {'relation': relation, 'value': v},
      'from': isoDate(from),
      'status': status,
    };
    saveAndClose(
      context,
      g == null ? 'Goal added' : 'Goal updated',
      (p) => p.write('goal save', {
        'goal': goal,
        'expectedVersion': g?['version'] ?? 0,
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return EntrySheet(
      title: editing ? 'Goal' : 'New goal',
      action: 'Save',
      onAction: _save,
      children: [
        TextField(
          controller: name,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'e.g. 8 000 steps',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<int>(
          initialValue: preset,
          decoration: const InputDecoration(labelText: 'Measure'),
          items: [
            for (var i = 0; i < metricPresets.length; i++)
              DropdownMenuItem(value: i, child: Text(metricPresets[i].$1)),
          ],
          onChanged: editing ? null : (i) => setState(() => preset = i ?? 0),
        ),
        DropdownButtonFormField<String>(
          initialValue: aggregate,
          decoration: const InputDecoration(labelText: 'Judged by'),
          items: [
            for (final e in _aggregates.entries)
              DropdownMenuItem(value: e.key, child: Text(e.value)),
          ],
          onChanged: (a) => setState(() => aggregate = a ?? 'daysMet'),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'atLeast', label: Text('at least')),
                ButtonSegment(value: 'atMost', label: Text('at most')),
              ],
              selected: {relation == 'atMost' ? 'atMost' : 'atLeast'},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => relation = s.single),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DecimalField(
                controller: value,
                label: 'Target',
                suffix: metricPresets[preset].$3,
              ),
            ),
          ],
        ),
        _DateRow(
          label: 'From',
          value: from,
          onChanged: (d) => setState(() => from = d),
        ),
        if (editing)
          Wrap(
            spacing: 8,
            children: [
              for (final s in ['active', 'achieved', 'abandoned'])
                ChoiceChip(
                  label: Text(s),
                  selected: status == s,
                  onSelected: (_) => setState(() => status = s),
                ),
            ],
          ),
        if (problem != null) ProblemText(problem!),
      ],
    );
  }
}

/// Adds a routine: a check, a practice or an activity category, due at a
/// clock time or a number of minutes after waking.
final class RoutineSheet extends StatefulWidget {
  const RoutineSheet({super.key, required this.today});
  final DateTime today;

  @override
  State<RoutineSheet> createState() => _RoutineSheetState();
}

final class _RoutineSheetState extends State<RoutineSheet> {
  final name = TextEditingController();
  final detail = TextEditingController();
  final offset = TextEditingController(text: '30');
  String kind = 'check';
  bool afterWaking = false;
  late DateTime time = DateTime(
    widget.today.year,
    widget.today.month,
    widget.today.day,
    8,
  );
  String? problem;

  @override
  void dispose() {
    name.dispose();
    detail.dispose();
    offset.dispose();
    super.dispose();
  }

  void _save() {
    if (name.text.trim().isEmpty) {
      setState(() => problem = 'Give the routine a name.');
      return;
    }
    final slug = detail.text.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]+'),
      '-',
    );
    if (kind != 'check' && slug.isEmpty) {
      setState(
        () => problem = kind == 'practice'
            ? 'Name the practice id, e.g. box-breathing.'
            : 'Name the activity category, e.g. outdoor-light.',
      );
      return;
    }
    final minutes = int.tryParse(offset.text.trim());
    if (afterWaking && minutes == null) {
      setState(() => problem = 'Minutes after waking is a whole number.');
      return;
    }
    String two(int v) => v.toString().padLeft(2, '0');
    final routine = {
      'id': 'routine-${stamp(DateTime.now())}',
      'name': name.text.trim(),
      'action': switch (kind) {
        'practice' => {'kind': 'practice', 'practiceId': slug},
        'activity' => {'kind': 'activity', 'category': slug},
        _ => {'kind': 'check'},
      },
      'schedule': afterWaking
          ? {
              'relative': {'anchor': 'wake', 'offsetMinutes': minutes},
            }
          : {'at': '${two(time.hour)}:${two(time.minute)}'},
      'from': isoDate(widget.today),
    };
    saveAndClose(
      context,
      'Routine added',
      (p) =>
          p.write('routine save', {'routine': routine, 'expectedVersion': 0}),
    );
  }

  @override
  Widget build(BuildContext context) => EntrySheet(
    title: 'New routine',
    action: 'Save',
    onAction: _save,
    children: [
      TextField(
        controller: name,
        decoration: const InputDecoration(
          labelText: 'Name',
          hintText: 'e.g. Morning daylight walk',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 10),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'check', label: Text('Tick')),
          ButtonSegment(value: 'practice', label: Text('Practice')),
          ButtonSegment(value: 'activity', label: Text('Activity')),
        ],
        selected: {kind},
        showSelectedIcon: false,
        onSelectionChanged: (s) => setState(() => kind = s.single),
      ),
      if (kind != 'check')
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: TextField(
            controller: detail,
            decoration: InputDecoration(
              labelText: kind == 'practice'
                  ? 'Practice id'
                  : 'Activity category',
              hintText: kind == 'practice' ? 'box-breathing' : 'outdoor-light',
              border: const OutlineInputBorder(),
            ),
          ),
        ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Relative to waking up'),
        value: afterWaking,
        onChanged: (v) => setState(() => afterWaking = v),
      ),
      if (afterWaking)
        TextField(
          controller: offset,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Minutes after waking',
            suffixText: 'min',
          ),
        )
      else
        TimeRow(
          label: 'Due at',
          value: time,
          onChanged: (t) => setState(() => time = t),
        ),
      if (problem != null) ProblemText(problem!),
    ],
  );
}

/// Adds a trial: a question, an action, a baseline and a trial period, and
/// the measures compared. The report stays descriptive.
final class TrialSheet extends StatefulWidget {
  const TrialSheet({super.key, required this.today});
  final DateTime today;

  @override
  State<TrialSheet> createState() => _TrialSheetState();
}

final class _TrialSheetState extends State<TrialSheet> {
  final question = TextEditingController();
  final action = TextEditingController();
  late DateTime baselineFrom = widget.today.subtract(const Duration(days: 14));
  late DateTime trialFrom = widget.today;
  late DateTime trialUntil = widget.today.add(const Duration(days: 14));
  final outcomes = <int>{2};
  String? problem;

  @override
  void dispose() {
    question.dispose();
    action.dispose();
    super.dispose();
  }

  void _save() {
    if (question.text.trim().isEmpty || action.text.trim().isEmpty) {
      setState(() => problem = 'Write the question and what you will change.');
      return;
    }
    if (outcomes.isEmpty) {
      setState(() => problem = 'Choose at least one measure to compare.');
      return;
    }
    if (!baselineFrom.isBefore(trialFrom) || !trialFrom.isBefore(trialUntil)) {
      setState(() => problem = 'The baseline comes before the trial period.');
      return;
    }
    final trial = {
      'id': 'trial-${stamp(DateTime.now())}',
      'question': question.text.trim(),
      'action': {'description': action.text.trim()},
      'baseline': {'from': isoDate(baselineFrom), 'until': isoDate(trialFrom)},
      'trial': {'from': isoDate(trialFrom), 'until': isoDate(trialUntil)},
      'outcomes': [for (final i in outcomes) metricPresets[i].$2],
    };
    saveAndClose(
      context,
      'Trial added',
      (p) => p.write('trial save', {'trial': trial, 'expectedVersion': 0}),
    );
  }

  @override
  Widget build(BuildContext context) => EntrySheet(
    title: 'New trial',
    action: 'Save',
    onAction: _save,
    children: [
      TextField(
        controller: question,
        decoration: const InputDecoration(
          labelText: 'Question',
          hintText: 'Does an earlier last coffee help my sleep?',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: action,
        decoration: const InputDecoration(
          labelText: 'What you change during the trial',
          hintText: 'Last coffee before 13:00',
          border: OutlineInputBorder(),
        ),
      ),
      _DateRow(
        label: 'Baseline from',
        value: baselineFrom,
        onChanged: (d) => setState(() => baselineFrom = d),
      ),
      _DateRow(
        label: 'Trial from',
        value: trialFrom,
        onChanged: (d) => setState(() => trialFrom = d),
      ),
      _DateRow(
        label: 'Trial until',
        value: trialUntil,
        onChanged: (d) => setState(() => trialUntil = d),
      ),
      const Text('Compare'),
      Wrap(
        spacing: 6,
        children: [
          for (var i = 0; i < metricPresets.length; i++)
            FilterChip(
              label: Text(metricPresets[i].$1),
              selected: outcomes.contains(i),
              onSelected: (on) =>
                  setState(() => on ? outcomes.add(i) : outcomes.remove(i)),
            ),
        ],
      ),
      const Muted(
        'A trial describes what happened in each period. Seasons, routines '
        'and expectations also differ, so it is not proof of an effect.',
      ),
      if (problem != null) ProblemText(problem!),
    ],
  );
}

/// One saved review run over the last 7, 28 or 90 days: per measure the
/// known days, mean and range, and a line of the daily values.
final class ReviewCard extends StatefulWidget {
  const ReviewCard({super.key, required this.review, required this.today});
  final Map<String, Object?> review;
  final DateTime today;

  @override
  State<ReviewCard> createState() => _ReviewCardState();
}

final class _ReviewCardState extends State<ReviewCard> {
  int days = 7;
  Map<String, Object?>? result;
  String? problem;
  int? _revision;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final profile = ProfileScope.of(context);
    if (_revision != profile.revision) {
      _revision = profile.revision;
      _run();
    }
  }

  Future<void> _run() async {
    final end = DateTime(
      widget.today.year,
      widget.today.month,
      widget.today.day + 1,
    );
    try {
      final r = await ProfileScope.of(context)
          .call<Map<String, Object?>>('review run', {
            'id': widget.review['id'],
            'from': isoDate(end.subtract(Duration(days: days))),
            'until': isoDate(end),
          });
      if (mounted) {
        setState(() {
          result = r;
          problem = null;
        });
      }
    } on BodyTmiException catch (e) {
      if (mounted) setState(() => problem = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = Fmt.of(context);
    return SectionCard(
      title: '${widget.review['name']}',
      trailing: IconButton(
        tooltip: 'Edit review',
        icon: const Icon(Icons.edit_outlined),
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => ReviewSheet(existing: widget.review),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.review['notes'] != null)
            Muted('${widget.review['notes']}'),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 7, label: Text('7 days')),
              ButtonSegment(value: 28, label: Text('28 days')),
              ButtonSegment(value: 90, label: Text('90 days')),
            ],
            selected: {days},
            showSelectedIcon: false,
            onSelectionChanged: (s) {
              setState(() => days = s.single);
              _run();
            },
          ),
          if (problem != null) ProblemText(problem!),
          for (final m in (result?['metrics'] as List?) ?? const [])
            () {
              final metric = m as Map;
              final (name, unit) = metricName(metric['metric']);
              final sum = (metric['summary'] as Map?) ?? const {};
              final u = unit.isEmpty ? '' : ' $unit';
              final values = [
                for (final d in (metric['days'] as List?) ?? const [])
                  if ((d as Map)['status'] == 'value')
                    double.parse('${d['value']}'),
              ];
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Muted(
                      sum['known'] == 0
                          ? 'No data on any of ${sum['days']} days'
                          : [
                              'Mean ${f.number(sum['mean'])}$u',
                              if (sum['min'] != sum['max'])
                                '${f.number(sum['min'])}–${f.number(sum['max'])}$u',
                              '${sum['known']} of ${sum['days']} days known',
                            ].join(' · '),
                    ),
                    if (values.length > 1 && sum['min'] != sum['max'])
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: LineChart(values: values, height: 40),
                      ),
                  ],
                ),
              );
            }(),
        ],
      ),
    );
  }
}

/// Adds or edits a saved review: a name, measures and notes.
final class ReviewSheet extends StatefulWidget {
  const ReviewSheet({super.key, this.existing});
  final Map<String, Object?>? existing;

  @override
  State<ReviewSheet> createState() => _ReviewSheetState();
}

final class _ReviewSheetState extends State<ReviewSheet> {
  late final name = TextEditingController(
    text: '${widget.existing?['name'] ?? ''}',
  );
  late final notes = TextEditingController(
    text: '${widget.existing?['notes'] ?? ''}',
  );
  late final List<Object?> kept = [
    for (final m in (widget.existing?['metrics'] as List?) ?? const [])
      if (!metricPresets.any((p) => _key(p.$2) == _key(m))) m,
  ];
  late final selected = <int>{
    for (final m in (widget.existing?['metrics'] as List?) ?? const [])
      for (var i = 0; i < metricPresets.length; i++)
        if (_key(metricPresets[i].$2) == _key(m)) i,
  };
  String? problem;

  @override
  void dispose() {
    name.dispose();
    notes.dispose();
    super.dispose();
  }

  void _save() {
    if (name.text.trim().isEmpty) {
      setState(() => problem = 'Give the review a name.');
      return;
    }
    if (selected.isEmpty && kept.isEmpty) {
      setState(() => problem = 'Choose at least one measure.');
      return;
    }
    final old = widget.existing;
    final review = <String, Object?>{
      'id': old?['id'] ?? 'review-${stamp(DateTime.now())}',
      'name': name.text.trim(),
      'metrics': <Object?>[
        for (final i in selected.toList()..sort()) metricPresets[i].$2,
        ...kept,
      ],
      if (notes.text.trim().isNotEmpty) 'notes': notes.text.trim(),
    };
    saveAndClose(
      context,
      old == null ? 'Review added' : 'Review updated',
      (p) => p.write('review save', {
        'review': review,
        'expectedVersion': old?['version'] ?? 0,
      }),
    );
  }

  @override
  Widget build(BuildContext context) => EntrySheet(
    title: widget.existing == null ? 'New review' : 'Review',
    action: 'Save',
    onAction: _save,
    children: [
      TextField(
        controller: name,
        decoration: const InputDecoration(
          labelText: 'Name',
          hintText: 'e.g. Weekly check-in',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 10),
      const Text('Measures'),
      Wrap(
        spacing: 6,
        children: [
          for (var i = 0; i < metricPresets.length; i++)
            FilterChip(
              label: Text(metricPresets[i].$1),
              selected: selected.contains(i),
              onSelected: (on) =>
                  setState(() => on ? selected.add(i) : selected.remove(i)),
            ),
        ],
      ),
      if (kept.isNotEmpty)
        Muted('Also kept: ${kept.map((m) => metricName(m).$1).join(', ')}'),
      const SizedBox(height: 10),
      TextField(
        controller: notes,
        maxLines: 2,
        decoration: const InputDecoration(
          labelText: 'Notes (optional)',
          border: OutlineInputBorder(),
        ),
      ),
      if (problem != null) ProblemText(problem!),
    ],
  );
}
