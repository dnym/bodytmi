import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:material_ui/material_ui.dart';

import 'format.dart';
import 'profile.dart';
import 'quick_entry.dart';
import 'session.dart' show parseDecimal;
import 'widgets.dart';

/// Opens the diet plan (from More).
Future<void> openDietPlan(BuildContext context, {DateTime? clock}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => DietPlanScreen(clock: clock)),
    );

String _iso(DateTime d) => isoDate(d);
DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

/// A choice field of a programme: what to ask and how to send it. Whole
/// numbers go as JSON integers, decimals as exact decimal strings.
final class ChoiceField {
  const ChoiceField(this.key, this.label, this.kind, [this.values = const []]);
  final String key;
  final String label;
  final String kind; // decimal | integer | choice | text | deficit | steps
  final List<String> values;
}

const programmeFields = <String, List<ChoiceField>>{
  'normal': [
    ChoiceField('deficit', 'Deficit below maintenance', 'deficit'),
    ChoiceField('proteinPerKg', 'Protein, g per kg body mass', 'decimal'),
  ],
  'rfl': [
    ChoiceField('activity', 'Activity', 'choice', [
      'inactive',
      'aerobic',
      'weights',
    ]),
    ChoiceField('carbohydrate', 'Carbohydrate per RFL day', 'decimal'),
    ChoiceField('fat', 'Fat per RFL day', 'decimal'),
    ChoiceField('breakActivity', 'Activity during breaks', 'choice', [
      'sedentary',
      'light',
      'moderate',
      'very',
      'extreme',
    ]),
    ChoiceField('breakDays', 'Diet break days (7–14)', 'integer'),
    ChoiceField('dietDays', 'Diet days before the break (11–12)', 'integer'),
    ChoiceField('refeedDays', 'Refeed days (2–3)', 'integer'),
    ChoiceField(
      'refeedCarbohydratePerKg',
      'Refeed carbohydrate, g per kg fat-free mass (12–16)',
      'decimal',
    ),
    ChoiceField('dietWeeks', 'Diet weeks', 'integer'),
    ChoiceField(
      'refeedCarbohydratePerLb',
      'Weekly refeed carbohydrate, g per lb fat-free mass (1.5–3)',
      'decimal',
    ),
  ],
  'erfl': [
    ChoiceField('walking', 'Walking per ERFL day', 'steps'),
    ChoiceField('carbohydrate', 'Carbohydrate per ERFL day', 'decimal'),
    ChoiceField('fat', 'Fat per ERFL day', 'decimal'),
    ChoiceField('afterDays', 'Days of normal eating after (1–28)', 'integer'),
  ],
  'imf': [
    ChoiceField('activity', 'Activity', 'choice', [
      'none',
      'aerobic',
      'weights',
    ]),
    ChoiceField('pattern', 'Pattern (maintenance:RFL days)', 'choice', [
      '6:1',
      '5:2',
      '4:3',
      '3:4',
      '2:5',
      '1:6',
      '3:11',
      '1:13',
    ]),
    ChoiceField('arrangement', 'Days in order, M and R', 'text'),
    ChoiceField(
      'fatPerLb',
      'Maintenance-day fat, g per lb (0.25–0.5)',
      'decimal',
    ),
    ChoiceField(
      'maintenanceAdjustment',
      'Maintenance-day energy change (−0.1 to 0.1)',
      'decimal',
    ),
    ChoiceField('carbohydrate', 'Carbohydrate per RFL day', 'decimal'),
    ChoiceField('fat', 'Fat per RFL day', 'decimal'),
    ChoiceField(
      'fullVolumeTrainingDays',
      'Full-volume training days a week',
      'integer',
    ),
  ],
};

/// Only the fields for the current diet category: a programme choice
/// described as "category N: …" applies to that category alone.
List<ChoiceField> fieldsFor(
  String programme,
  Map<String, Object?> descriptions,
  int? category,
) => [
  for (final f in programmeFields[programme] ?? const <ChoiceField>[])
    if (_appliesTo('${descriptions[f.key] ?? ''}', category)) f,
];

bool _appliesTo(String description, int? category) {
  final listed = {
    for (final m in RegExp(r'category ([123]):').allMatches(description))
      int.parse(m.group(1)!),
  };
  return listed.isEmpty || category == null || listed.contains(category);
}

String _goalText(Fmt f, Map<String, Object?> goals) {
  final parts = <String>[];
  for (final (key, label, unit) in [
    ('energy', '', 'kcal'),
    ('protein', 'protein ', 'g'),
    ('carbohydrate', 'carbs ', 'g'),
    ('fat', 'fat ', 'g'),
  ]) {
    final g = goals[key];
    if (g is! Map || g['status'] != 'resolved') continue;
    final v = g['value'];
    if (v is Map) {
      parts.add('$label${f.number(v['value'], digits: 0)} $unit');
    } else if (g['minimum'] is Map || g['maximum'] is Map) {
      final lo = (g['minimum'] as Map?)?['value'];
      final hi = (g['maximum'] as Map?)?['value'];
      parts.add(
        '$label${lo == null ? '' : f.number(lo, digits: 0)}–'
        '${hi == null ? '' : f.number(hi, digits: 0)} $unit',
      );
    }
  }
  return parts.isEmpty ? 'no goals' : parts.join(' · ');
}

const _programmeNames = {
  'normal': 'Normal',
  'rfl': 'Rapid Fat Loss',
  'erfl': 'Extreme Rapid Fat Loss',
  'imf': 'Intermittent Modified Fasting',
};

final class _PlanData {
  _PlanData({
    required this.methods,
    required this.estimate,
    required this.plan,
    required this.openRun,
    required this.schedule,
    required this.proposals,
  });
  final List<Object?> methods;
  final Map<String, Object?> estimate;
  final Map<String, Object?>? plan;
  final Map<String, Object?>? openRun;
  final List<Map<String, Object?>> schedule;
  final List<Map<String, Object?>> proposals;
}

final class DietPlanScreen extends StatefulWidget {
  const DietPlanScreen({super.key, this.clock});
  final DateTime? clock;

  @override
  State<DietPlanScreen> createState() => _DietPlanScreenState();
}

final class _DietPlanScreenState extends State<DietPlanScreen> {
  Map<String, Object?>? review;

  DateTime get _now => widget.clock ?? DateTime.now();
  String get _today => _iso(_now);
  String get _tomorrow => _iso(_day(_now).add(const Duration(days: 1)));

  Future<_PlanData> _load(ProfileClient p) async {
    final plans = [
      for (final x in await p.call<List<Object?>>('plan list'))
        x! as Map<String, Object?>,
    ];
    final plan = plans.where((x) => x['status'] == 'active').firstOrNull;
    Map<String, Object?>? openRun;
    for (final r in await p.call<List<Object?>>('diet list')) {
      final run = r! as Map<String, Object?>;
      final end = run['endDate'];
      if (end == null || '$end'.compareTo(_today) > 0) openRun = run;
    }
    final schedule = openRun == null
        ? <Map<String, Object?>>[]
        : [
            for (final d
                in ((await p.call<Map<String, Object?>>('diet schedule', {
                          'from': _today,
                          'days': 7,
                        }))['days']
                        as List?) ??
                    const [])
              d as Map<String, Object?>,
          ];
    final proposals = plan == null
        ? <Map<String, Object?>>[]
        : [
            for (final x in await p.call<List<Object?>>('plan proposals', {
              'planId': plan['id'],
            }))
              if ((x! as Map)['status'] == 'pending') x as Map<String, Object?>,
          ];
    return _PlanData(
      methods: await p.call<List<Object?>>('energy methods'),
      estimate: await p.call<Map<String, Object?>>('energy estimate', {
        'asOf': isoInstant(_now),
      }),
      plan: plan,
      openRun: openRun,
      schedule: schedule,
      proposals: proposals,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Diet plan')),
    body: ProfileLoader<_PlanData>(
      load: _load,
      builder: (context, d) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          _maintenance(context, d),
          if (d.plan != null)
            _planCard(context, d)
          else if (d.openRun != null)
            _runCard(context, d.openRun!),
          if (d.plan == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PlanBuilderScreen(
                      clock: _now,
                      openRun: d.openRun?['id'] as String?,
                    ),
                  ),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Start a plan'),
              ),
            ),
          if (review != null) _reviewCard(context),
          for (final p in d.proposals) _proposalCard(context, p),
          if (d.schedule.isNotEmpty) _scheduleCard(context, d.schedule),
        ],
      ),
    ),
  );

  Widget _maintenance(BuildContext context, _PlanData d) {
    final f = Fmt.of(context);
    final m = d.estimate['maintenance'] as Map?;
    final method = d.methods.isEmpty
        ? null
        : (d.methods.last! as Map)['method'] as Map?;
    return SectionCard(
      title: 'Maintenance energy',
      trailing: TextButton(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => MethodSheet(today: _now),
        ),
        child: Text(method == null ? 'Choose method' : 'Change'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (m?['status'] == 'resolved')
            BigFigure(
              f.number(at(m, ['value', 'value']), digits: 0),
              unit: 'kcal a day',
            )
          else
            Muted(
              method == null
                  ? 'Choose how to estimate the energy you burn in a day; '
                        'programmes and reviews use it.'
                  : '${m?['reason'] ?? d.estimate['reason'] ?? 'Not available.'}',
            ),
          if (method != null) Muted(methodName(method)),
        ],
      ),
    );
  }

  Widget _planCard(BuildContext context, _PlanData d) {
    final f = Fmt.of(context);
    final plan = d.plan!;
    final programme = '${at(plan, ['programme', 'id']) ?? ''}';
    final target = plan['target'] as Map?;
    return SectionCard(
      title: 'Plan',
      trailing: Pill('category ${at(plan, ['programme', 'category']) ?? '?'}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _programmeNames[programme] ?? 'Your own cycle',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          Muted('since ${f.shortDate('${plan['startDate']}')}'),
          if (target != null)
            Text(
              'Target: ${target['measure'] == 'mass' ? 'mass' : 'body fat'} '
              '${target['relation'] == 'atMost' ? '≤' : '≥'} '
              '${f.number(at(target, ['value', 'value']))} '
              '${at(target, ['value', 'unit']) == 'percent' ? '%' : at(target, ['value', 'unit'])}',
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: () => _review(context, plan),
                child: const Text('Review'),
              ),
              OutlinedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => _TargetDialog(plan: plan),
                ),
                child: Text(target == null ? 'Set target' : 'Target'),
              ),
              TextButton(
                onPressed: () => _end(
                  context,
                  'End the plan?',
                  'plan end',
                  plan['id'],
                  plan['contentVersion'],
                ),
                child: const Text('End plan'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _runCard(BuildContext context, Map<String, Object?> run) {
    final f = Fmt.of(context);
    return SectionCard(
      title: 'Diet run',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Own cycle: ${at(run, ['cycle', 'id'])}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          Muted(
            'since ${f.shortDate('${run['startDate']}')}. '
            'End it before starting a programme plan.',
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => _end(
                context,
                'End the diet run?',
                'diet end',
                run['id'],
                run['contentVersion'],
              ),
              child: const Text('End run'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _end(
    BuildContext context,
    String title,
    String command,
    Object? id,
    Object? version,
  ) async {
    final profile = ProfileScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: const Text(
          'It ends after today. Today and earlier days keep their targets.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('End'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await profile.write(command, {
        command == 'plan end' ? 'planId' : 'runId': id,
        'date': _tomorrow,
        'expectedVersion': version,
        'confirm': true,
      });
      setState(() => review = null);
    } on BodyTmiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _review(BuildContext context, Map<String, Object?> plan) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await ProfileScope.of(context).write<Map<String, Object?>>(
        'plan review',
        {'planId': plan['id'], 'asOf': isoInstant(_now)},
      );
      if (mounted) setState(() => review = r);
    } on BodyTmiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Widget _reviewCard(BuildContext context) {
    final f = Fmt.of(context);
    final findings = [
      for (final x in (review!['findings'] as List?) ?? const [])
        x as Map<String, Object?>,
    ];
    String line(Map<String, Object?> x) => switch (x['kind']) {
      'trend' when x['status'] == 'resolved' =>
        'Trend ${f.number(x['trendFrom'])} → ${f.number(x['trendTo'])} kg '
            '(${f.shortDate('${x['from']}')}–${f.shortDate('${x['to']}')}): '
            'lost ${f.number(x['actualLossKg'])} kg, the plan expected '
            '${f.number(x['plannedLossKg'])} kg.',
      'target' => 'Target ${x['status']}.',
      _ =>
        '${x['kind']}: ${x['status'] ?? ''} ${x['reason'] ?? x['explanation'] ?? ''}'
            .trim(),
    };
    final created = (review!['created'] as List?)?.length ?? 0;
    return SectionCard(
      title: 'Review',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final x in findings)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(line(x)),
            ),
          Muted(
            created == 0
                ? 'No new changes proposed.'
                : '$created new change${created == 1 ? '' : 's'} proposed below.',
          ),
        ],
      ),
    );
  }

  Widget _proposalCard(BuildContext context, Map<String, Object?> p) {
    Future<void> act(String command, Map<String, Object?> body) async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await ProfileScope.of(context).write(command, body);
      } on BodyTmiException catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    }

    return SectionCard(
      title: 'Proposed: ${p['kind']}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${p['explanation'] ?? ''}'),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => act('plan decline', {'proposalId': p['id']}),
                child: const Text('Decline'),
              ),
              FilledButton(
                onPressed: () =>
                    act('plan accept', {'proposalId': p['id'], 'from': _today}),
                child: const Text('Accept from today'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _scheduleCard(BuildContext context, List<Map<String, Object?>> days) {
    final f = Fmt.of(context);
    return SectionCard(
      title: 'Next 7 days',
      child: Column(
        children: [
          for (final d in days)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(
                      d['date'] == _today
                          ? 'Today'
                          : f.shortDate('${d['date']}'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${at(d, ['dayType', 'name']) ?? 'No day type'}'),
                        Muted(
                          _goalText(
                            f,
                            (d['goals'] as Map<String, Object?>?) ?? const {},
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A short description of a maintenance method.
String methodName(Map<Object?, Object?> m) => switch (m['formula']) {
  'mifflin-st-jeor' =>
    'Mifflin-St Jeor × activity ${m['pal']}'
        '${m['adjustment'] == null ? '' : ', adjusted ${m['adjustment']}'}',
  'katch-mcardle' =>
    'Katch-McArdle × activity ${m['pal']}'
        '${m['adjustment'] == null ? '' : ', adjusted ${m['adjustment']}'}',
  'manual' => 'Entered: ${at(m, ['energy', 'value'])} kcal',
  final other => '$other',
};

/// Chooses the maintenance method from today on.
final class MethodSheet extends StatefulWidget {
  const MethodSheet({super.key, required this.today});
  final DateTime today;

  @override
  State<MethodSheet> createState() => _MethodSheetState();
}

final class _MethodSheetState extends State<MethodSheet> {
  String formula = 'mifflin-st-jeor';
  final pal = TextEditingController(text: '1.5');
  final energy = TextEditingController();
  String? problem;

  @override
  void dispose() {
    pal.dispose();
    energy.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final locale = Fmt.of(context).locale;
    final Map<String, Object?> method;
    if (formula == 'manual') {
      final e = parseDecimal(locale, energy.text.trim());
      if (e == null) {
        setState(() => problem = 'Enter your maintenance energy.');
        return;
      }
      method = {
        'formula': 'manual',
        'energy': {'value': e, 'unit': 'kcal'},
      };
    } else {
      final p = parseDecimal(locale, pal.text.trim());
      if (p == null) {
        setState(() => problem = 'Enter an activity factor from 1 to 3.');
        return;
      }
      method = {'formula': formula, 'pal': p};
    }
    final profile = ProfileScope.of(context);
    try {
      final methods = await profile.call<List<Object?>>('energy methods');
      final revision = methods.isEmpty ? 0 : (methods.last! as Map)['revision'];
      if (!mounted) return;
      await saveAndClose(
        context,
        'Maintenance method saved',
        (p) => p.write('energy method', {
          'from': isoDate(widget.today),
          'method': method,
          'expectedRevision': revision,
        }),
      );
    } on BodyTmiException catch (e) {
      setState(() => problem = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => EntrySheet(
    title: 'Maintenance energy',
    action: 'Save',
    onAction: _save,
    children: [
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'mifflin-st-jeor', label: Text('Mifflin')),
          ButtonSegment(value: 'katch-mcardle', label: Text('Katch')),
          ButtonSegment(value: 'manual', label: Text('Enter')),
        ],
        selected: {formula},
        showSelectedIcon: false,
        onSelectionChanged: (s) => setState(() => formula = s.single),
      ),
      const SizedBox(height: 10),
      if (formula == 'manual')
        DecimalField(controller: energy, label: 'Energy', suffix: 'kcal')
      else ...[
        DecimalField(controller: pal, label: 'Activity factor (1–3)'),
        Muted(
          formula == 'mifflin-st-jeor'
              ? 'Resting energy from mass, height, age and sex, times the '
                    'activity factor (about 1.4 desk work, 1.6 active).'
              : 'Resting energy from fat-free mass (needs a body-fat '
                    'source), times the activity factor.',
        ),
      ],
      const Muted('Applies from today; earlier days keep the method they had.'),
      if (problem != null) ProblemText(problem!),
    ],
  );
}

final class _TargetDialog extends StatefulWidget {
  const _TargetDialog({required this.plan});
  final Map<String, Object?> plan;

  @override
  State<_TargetDialog> createState() => _TargetDialogState();
}

final class _TargetDialogState extends State<_TargetDialog> {
  late String measure = '${at(widget.plan, ['target', 'measure']) ?? 'mass'}';
  late String relation =
      '${at(widget.plan, ['target', 'relation']) ?? 'atMost'}';
  final value = TextEditingController();
  String? problem;

  @override
  void dispose() {
    value.dispose();
    super.dispose();
  }

  Future<void> _save({bool clear = false}) async {
    final v = parseDecimal(Fmt.of(context).locale, value.text.trim());
    if (!clear && v == null) {
      setState(() => problem = 'Enter a value.');
      return;
    }
    try {
      await ProfileScope.of(context).write('plan target', {
        'planId': widget.plan['id'],
        'expectedVersion': widget.plan['contentVersion'],
        'target': clear
            ? null
            : {
                'measure': measure,
                'relation': relation,
                'value': {
                  'value': v,
                  'unit': measure == 'mass' ? 'kg' : 'percent',
                },
              },
      });
      if (mounted) Navigator.pop(context);
    } on BodyTmiException catch (e) {
      setState(() => problem = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Plan target'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'mass', label: Text('Mass')),
            ButtonSegment(value: 'bodyFat', label: Text('Body fat')),
          ],
          selected: {measure},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => measure = s.single),
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'atMost', label: Text('at most')),
            ButtonSegment(value: 'atLeast', label: Text('at least')),
          ],
          selected: {relation},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => relation = s.single),
        ),
        DecimalField(
          controller: value,
          label: 'Target',
          suffix: measure == 'mass' ? 'kg' : '%',
        ),
        const Muted(
          'A review proposes ending the plan once the trend reaches it; '
          'nothing ends on its own.',
        ),
        if (problem != null) ProblemText(problem!),
      ],
    ),
    actions: [
      if (widget.plan['target'] != null)
        TextButton(
          onPressed: () => _save(clear: true),
          child: const Text('Clear'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );
}

/// Chooses a programme and its choices, previews the guide from current
/// inputs, and starts the plan.
final class PlanBuilderScreen extends StatefulWidget {
  const PlanBuilderScreen({super.key, required this.clock, this.openRun});
  final DateTime clock;
  final String? openRun;

  @override
  State<PlanBuilderScreen> createState() => _PlanBuilderScreenState();
}

final class _PlanBuilderScreenState extends State<PlanBuilderScreen> {
  String programme = 'normal';
  List<Map<String, Object?>> programmes = const [];
  int? category;
  final controllers = <String, TextEditingController>{};
  final choiceValues = <String, String>{};
  bool percent = false;
  late DateTime start = _day(widget.clock).add(const Duration(days: 1));
  Map<String, Object?>? preview;
  final companions = <String, bool>{};
  String? problem;
  bool busy = false;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final profile = ProfileScope.of(context);
    () async {
      final list = await profile.pure<List<Object?>>(
        'programme list',
        const {},
      );
      final estimate = await profile.call<Map<String, Object?>>(
        'energy estimate',
        {'asOf': isoInstant(widget.clock)},
      );
      if (!mounted) return;
      setState(() {
        programmes = [for (final p in list) p! as Map<String, Object?>];
        final c = at(estimate, ['inputs', 'category', 'value']);
        category = c is int ? c : null;
      });
    }();
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _c(String key) =>
      controllers.putIfAbsent('$programme.$key', TextEditingController.new);

  Map<String, Object?> get _descriptions =>
      (programmes.where((p) => p['id'] == programme).firstOrNull?['choices']
          as Map<String, Object?>?) ??
      const {};

  /// The entered choices, or a message naming the one that is not a number.
  (Map<String, Object?>, String?) _choices() {
    final locale = Fmt.of(context).locale;
    final out = <String, Object?>{};
    for (final f in fieldsFor(programme, _descriptions, category)) {
      if (f.kind == 'choice') {
        final v = choiceValues['$programme.${f.key}'];
        if (v != null) out[f.key] = v;
        continue;
      }
      final text = _c(f.key).text.trim();
      if (text.isEmpty) continue;
      switch (f.kind) {
        case 'text':
          out[f.key] = text.toUpperCase();
        case 'integer' || 'steps':
          final n = int.tryParse(text);
          if (n == null) return (out, '${f.label} is a whole number.');
          out[f.key] = f.kind == 'steps' ? {'steps': n} : n;
        default:
          final d = parseDecimal(locale, text);
          if (d == null) return (out, '${f.label} is not a number.');
          out[f.key] = f.kind == 'deficit'
              ? {percent ? 'percent' : 'kcal': d}
              : d;
      }
    }
    return (out, null);
  }

  Future<void> _preview() async {
    final (choices, error) = _choices();
    if (error != null) {
      setState(() => problem = error);
      return;
    }
    setState(() {
      busy = true;
      problem = null;
    });
    try {
      final profile = ProfileScope.of(context);
      final p = await profile.call<Map<String, Object?>>('plan preview', {
        'programme': programme,
        'choices': choices,
        'startDate': _iso(start),
        'asOf': isoInstant(widget.clock),
      });
      if (at(p, ['guide', 'status']) == 'resolved') {
        // The plan preview has no simulation; take twelve weeks from the
        // guide of the same programme and choices.
        final guide = await profile.call<Map<String, Object?>>(
          'programme guide',
          {
            'programme': programme,
            'choices': choices,
            'asOf': isoInstant(widget.clock),
            'simulateDays': 84,
          },
        );
        p['guide'] = <String, Object?>{
          ...p['guide']! as Map<String, Object?>,
          'simulation': guide['simulation'],
        };
      }
      if (!mounted) return;
      setState(() {
        preview = p;
        busy = false;
        companions.clear();
      });
    } on BodyTmiException catch (e) {
      setState(() {
        preview = null;
        busy = false;
        problem = e.message;
      });
    }
  }

  Future<void> _start() async {
    final (choices, error) = _choices();
    if (error != null) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => busy = true);
    try {
      final id = 'plan-${stamp(DateTime.now())}';
      await ProfileScope.of(context).write('plan activate', {
        'planId': id,
        'programme': programme,
        'choices': choices,
        'startDate': _iso(start),
        'asOf': isoInstant(widget.clock),
        'requestId': id,
        'companions': {
          'steps': companions['steps'] ?? false,
          'pauseRuns': [
            for (final e in companions.entries)
              if (e.key != 'steps' && e.value) e.key,
          ],
        },
      });
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Plan started')));
    } on BodyTmiException catch (e) {
      setState(() {
        busy = false;
        problem = e.message;
      });
    }
  }

  Widget _field(ChoiceField f) {
    final description = '${_descriptions[f.key] ?? ''}';
    if (f.kind == 'choice') {
      final key = '$programme.${f.key}';
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(f.label),
            Wrap(
              spacing: 6,
              children: [
                for (final v in f.values)
                  ChoiceChip(
                    label: Text(v),
                    selected: choiceValues[key] == v,
                    onSelected: (on) => setState(() {
                      if (on) {
                        choiceValues[key] = v;
                      } else {
                        choiceValues.remove(key);
                      }
                      preview = null;
                    }),
                  ),
              ],
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (f.kind == 'deficit')
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('kcal')),
                ButtonSegment(value: true, label: Text('%')),
              ],
              selected: {percent},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() {
                percent = s.single;
                preview = null;
              }),
            ),
          TextField(
            controller: _c(f.key),
            keyboardType: f.kind == 'text'
                ? TextInputType.text
                : const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() => preview = null),
            decoration: InputDecoration(
              labelText: f.label,
              helperText: description.isEmpty || f.kind == 'deficit'
                  ? null
                  : description,
              helperMaxLines: 3,
              suffixText: switch (f.kind) {
                'deficit' => percent ? '%' : 'kcal',
                'steps' => 'steps',
                _ when f.key == 'carbohydrate' || f.key == 'fat' => 'g',
                _ => null,
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = programmes.where((p) => p['id'] == programme).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Start a plan')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          if (widget.openRun != null)
            SectionCard(
              child: Muted(
                'Diet run ${widget.openRun} is still open; only one runs at '
                'a time. End it on the Diet plan screen first.',
              ),
            ),
          Wrap(
            spacing: 6,
            children: [
              for (final e in _programmeNames.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: programme == e.key,
                  onSelected: (_) => setState(() {
                    programme = e.key;
                    preview = null;
                    problem = null;
                  }),
                ),
            ],
          ),
          if (current != null) ...[
            const SizedBox(height: 8),
            Muted('${current['source']}'),
            Text('${current['notes']}'),
          ],
          if (category != null)
            Muted('Your diet category now: $category (by body fat).'),
          for (final f in fieldsFor(programme, _descriptions, category))
            _field(f),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Start date'),
            trailing: Text(Fmt.of(context).longDate(start)),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: start,
                firstDate: _day(widget.clock),
                lastDate: _day(widget.clock).add(const Duration(days: 365)),
              );
              if (picked != null) {
                setState(() {
                  start = picked;
                  preview = null;
                });
              }
            },
          ),
          if (problem != null) ProblemText(problem!),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: busy ? null : _preview,
            child: const Text('Preview'),
          ),
          if (preview != null) ..._previewCards(context, preview!),
        ],
      ),
    );
  }

  List<Widget> _previewCards(BuildContext context, Map<String, Object?> p) {
    final f = Fmt.of(context);
    final guide = (p['guide'] as Map<String, Object?>?) ?? const {};
    if (guide['status'] != 'resolved') {
      return [
        SectionCard(
          title: 'Not ready',
          child: Text('${guide['reason'] ?? 'Some inputs are missing.'}'),
        ),
      ];
    }
    final schedule = (guide['schedule'] as Map?) ?? const {};
    final sim = (guide['simulation'] as Map?) ?? const {};
    final book = (guide['bookEstimate'] as Map?) ?? const {};
    final offers = [
      for (final c in (p['companions'] as List?) ?? const [])
        c as Map<String, Object?>,
    ];
    return [
      SectionCard(
        title: 'Plan',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final e in schedule.entries)
              if (e.key != 'category') Text('${e.key}: ${e.value}'),
            for (final w in (guide['warnings'] as List?) ?? const [])
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '⚠ ${w is Map ? w['message'] ?? w : w}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      SectionCard(
        title: 'Day types',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final t in (guide['dayTypes'] as List?) ?? const [])
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${(t as Map)['name']}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Muted(
                      [
                        _goalText(
                          f,
                          (t['goals'] as Map<String, Object?>?) ?? const {},
                        ),
                        if (t['steps'] != null) '${t['steps']} steps',
                      ].join(' · '),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      SectionCard(
        title: 'Estimate',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (sim['status'] == 'resolved')
              Text(
                'Over ${sim['days']} days: '
                '${f.number(at(sim, ['change', 'mass']))} kg '
                '(fat ${f.number(at(sim, ['change', 'fatMass']))}, '
                'lean ${f.number(at(sim, ['change', 'fatFreeMass']))}).',
              )
            else
              Muted('${sim['reason'] ?? 'No simulation.'}'),
            if (book['status'] == 'resolved')
              Muted(
                '${book['label']} '
                '${f.number(at(book, ['fatPerWeek', 'value']))} lb fat a week.',
              ),
            for (final l in (sim['limits'] as List?) ?? const []) Muted('• $l'),
          ],
        ),
      ),
      if (offers.isNotEmpty)
        SectionCard(
          title: 'Also',
          child: Column(
            children: [
              for (final o in offers)
                if (o['kind'] != 'recommendedTraining')
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      o['kind'] == 'steps'
                          ? 'Use the plan step goals'
                          : 'Pause training run ${o['runId']}',
                    ),
                    subtitle: Text('${o['description'] ?? ''}'),
                    value: companions[_offerKey(o)] ?? false,
                    onChanged: (v) =>
                        setState(() => companions[_offerKey(o)] = v),
                  )
                else
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Training'),
                    subtitle: Text('${o['description'] ?? ''}'),
                  ),
            ],
          ),
        ),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: busy ? null : _start,
        child: const Text('Start plan'),
      ),
    ];
  }

  static String _offerKey(Map<String, Object?> o) =>
      o['kind'] == 'steps' ? 'steps' : '${o['runId']}';
}
