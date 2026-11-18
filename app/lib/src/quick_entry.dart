import 'dart:async';
import 'dart:io';

import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import 'format.dart';
import 'profile.dart';
import 'session.dart' show parseDecimal;
import 'widgets.dart';

/// Opens the quick-add menu (design A's "+" on Today).
Future<void> showQuickAdd(BuildContext context, {DateTime? clock}) =>
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (icon, label, open) in [
                (
                  Icons.monitor_weight_outlined,
                  'Weigh in',
                  () => showWeighIn(context, clock: clock),
                ),
                (
                  Icons.restaurant_outlined,
                  'Food',
                  () => openFoodEntry(context, clock: clock),
                ),
                (
                  Icons.bolt_outlined,
                  'Quick kcal',
                  () => showQuickEnergy(context, clock: clock),
                ),
                (
                  Icons.bedtime_outlined,
                  'Sleep',
                  () => showSleepEntry(context, clock: clock),
                ),
              ])
                ListTile(
                  leading: Icon(icon),
                  title: Text(label),
                  onTap: () {
                    Navigator.pop(sheet);
                    open();
                  },
                ),
            ],
          ),
        ),
      ),
    );

String _stamp(DateTime t) =>
    '${t.year}${_two(t.month)}${_two(t.day)}-'
    '${_two(t.hour)}${_two(t.minute)}${_two(t.second)}';
String _two(int v) => v.toString().padLeft(2, '0');

/// Runs [write]; on success closes the sheet and confirms, otherwise shows
/// the command's message and keeps the input.
Future<void> _save(
  BuildContext context,
  String done,
  Future<void> Function(ProfileClient profile) write,
) async {
  final profile = ProfileScope.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    await write(profile);
    if (context.mounted) Navigator.pop(context);
    messenger.showSnackBar(SnackBar(content: Text(done)));
  } on BodyTmiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

/// Common sheet frame with a title and a primary action.
final class _EntrySheet extends StatelessWidget {
  const _EntrySheet({
    required this.title,
    required this.children,
    required this.action,
    required this.onAction,
  });
  final String title;
  final List<Widget> children;
  final String action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      16,
      20,
      16 + MediaQuery.of(context).viewInsets.bottom,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          ...children,
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(onPressed: onAction, child: Text(action)),
          ),
        ],
      ),
    ),
  );
}

/// A time-of-day row that opens the platform time picker.
final class _TimeRow extends StatelessWidget {
  const _TimeRow({
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
    trailing: Text(
      '${_two(value.hour)}:${_two(value.minute)}',
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
    ),
    onTap: () async {
      final picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(value),
      );
      if (picked != null) {
        onChanged(
          DateTime(
            value.year,
            value.month,
            value.day,
            picked.hour,
            picked.minute,
          ),
        );
      }
    },
  );
}

final class _DecimalField extends StatelessWidget {
  const _DecimalField({
    required this.controller,
    required this.label,
    this.suffix,
    this.autofocus = false,
  });
  final TextEditingController controller;
  final String label;
  final String? suffix;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        border: const OutlineInputBorder(),
      ),
    ),
  );
}

// ---------------------------------------------------------------- weigh-in

Future<void> showWeighIn(BuildContext context, {DateTime? clock}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _WeighIn(now: clock ?? DateTime.now()),
    );

final class _WeighIn extends StatefulWidget {
  const _WeighIn({required this.now});
  final DateTime now;

  @override
  State<_WeighIn> createState() => _WeighInState();
}

final class _WeighInState extends State<_WeighIn> {
  final mass = TextEditingController();
  String unit = 'kg';
  late DateTime at = widget.now;
  String? problem;

  @override
  void dispose() {
    mass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _EntrySheet(
    title: 'Weigh in',
    action: 'Save',
    onAction: () {
      final value = parseDecimal(Fmt.of(context).locale, mass.text.trim());
      if (value == null) {
        setState(() => problem = 'Enter your weight.');
        return;
      }
      _save(
        context,
        'Weigh-in saved',
        (p) => p.write('mass record', {
          'measurement': {
            'id': 'mass-${_stamp(at)}',
            'context': 'health',
            'observedAt': isoInstant(at),
            'mass': {'value': value, 'unit': unit},
          },
        }),
      );
    },
    children: [
      _DecimalField(
        controller: mass,
        label: 'Weight',
        suffix: unit,
        autofocus: true,
      ),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'kg', label: Text('kg')),
          ButtonSegment(value: 'lb', label: Text('lb')),
        ],
        selected: {unit},
        showSelectedIcon: false,
        onSelectionChanged: (s) => setState(() => unit = s.single),
      ),
      _TimeRow(
        label: 'Time',
        value: at,
        onChanged: (t) => setState(() => at = t),
      ),
      const Muted('Body mass for health; training mass is kept separately.'),
      if (problem != null) _Problem(problem!),
    ],
  );
}

final class _Problem extends StatelessWidget {
  const _Problem(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      text,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );
}

// ------------------------------------------------------------------- sleep

Future<void> showSleepEntry(BuildContext context, {DateTime? clock}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SleepEntry(now: clock ?? DateTime.now()),
    );

final class _SleepEntry extends StatefulWidget {
  const _SleepEntry({required this.now});
  final DateTime now;

  @override
  State<_SleepEntry> createState() => _SleepEntryState();
}

final class _SleepEntryState extends State<_SleepEntry> {
  late DateTime wake = () {
    final n = widget.now;
    final seven = DateTime(n.year, n.month, n.day, 7);
    return n.isBefore(seven) ? n : seven;
  }();
  late DateTime asleep = DateTime(wake.year, wake.month, wake.day - 1, 23);
  int? quality;
  bool nap = false;

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

  @override
  Widget build(BuildContext context) {
    final minutes = wake.difference(onset).inMinutes;
    return _EntrySheet(
      title: nap ? 'Nap' : 'Last night',
      action: 'Save',
      onAction: () => _save(
        context,
        'Sleep saved',
        (p) => p.write('sleep record', {
          'sleep': {
            'id': 'sleep-${_stamp(wake)}',
            'kind': nap ? 'nap' : 'main',
            'asleepAt': isoInstant(onset),
            'wakeAt': isoInstant(wake),
            'quality': ?quality,
          },
        }),
      ),
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Nap'),
          value: nap,
          onChanged: (v) => setState(() => nap = v),
        ),
        _TimeRow(
          label: 'Fell asleep',
          value: asleep,
          onChanged: (t) => setState(() => asleep = t),
        ),
        _TimeRow(
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
      ],
    );
  }
}

// --------------------------------------------------------------- quick kcal

Future<void> showQuickEnergy(BuildContext context, {DateTime? clock}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _QuickEnergy(now: clock ?? DateTime.now()),
    );

/// A meal label suggested from the time of day; always editable.
String mealFor(DateTime t) {
  final m = t.hour * 60 + t.minute;
  if (m >= 4 * 60 && m < 10 * 60 + 30) return 'breakfast';
  if (m >= 11 * 60 && m < 14 * 60 + 30) return 'lunch';
  if (m >= 17 * 60 && m < 21 * 60) return 'dinner';
  return 'snack';
}

const _meals = ['breakfast', 'lunch', 'dinner', 'snack'];

final class _MealChips extends StatelessWidget {
  const _MealChips({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    children: [
      for (final m in _meals)
        ChoiceChip(
          label: Text('${m[0].toUpperCase()}${m.substring(1)}'),
          selected: value == m,
          onSelected: (_) => onChanged(m),
        ),
    ],
  );
}

final class _QuickEnergy extends StatefulWidget {
  const _QuickEnergy({required this.now});
  final DateTime now;

  @override
  State<_QuickEnergy> createState() => _QuickEnergyState();
}

final class _QuickEnergyState extends State<_QuickEnergy> {
  final fields = {
    for (final id in ['energy', 'protein', 'carbohydrate', 'fat'])
      id: TextEditingController(),
  };
  late DateTime at = widget.now;
  late String meal = mealFor(widget.now);
  String? problem;

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _EntrySheet(
    title: 'Quick kcal',
    action: 'Add',
    onAction: () {
      final locale = Fmt.of(context).locale;
      final quick = <String, Object?>{};
      for (final MapEntry(:key, :value) in fields.entries) {
        if (value.text.trim().isEmpty) continue;
        final parsed = parseDecimal(locale, value.text.trim());
        if (parsed == null) {
          setState(() => problem = '$key is not a number.');
          return;
        }
        quick[key] = {'value': parsed, 'unit': key == 'energy' ? 'kcal' : 'g'};
      }
      if (!quick.containsKey('energy')) {
        setState(() => problem = 'Enter the energy.');
        return;
      }
      _save(
        context,
        'Added to the diary',
        (p) => p.write('diary add', {
          'entry': {
            'id': 'food-${_stamp(at)}',
            'at': isoInstant(at),
            'meal': meal,
            'quick': quick,
          },
        }),
      );
    },
    children: [
      _DecimalField(
        controller: fields['energy']!,
        label: 'Energy',
        suffix: 'kcal',
        autofocus: true,
      ),
      Row(
        children: [
          for (final (id, label) in [
            ('protein', 'Protein'),
            ('carbohydrate', 'Carbs'),
            ('fat', 'Fat'),
          ]) ...[
            Expanded(
              child: _DecimalField(
                controller: fields[id]!,
                label: label,
                suffix: 'g',
              ),
            ),
            if (id != 'fat') const SizedBox(width: 8),
          ],
        ],
      ),
      const Muted('Leave a macro empty if you do not know it.'),
      const SizedBox(height: 8),
      _MealChips(value: meal, onChanged: (m) => setState(() => meal = m)),
      _TimeRow(
        label: 'Time',
        value: at,
        onChanged: (t) => setState(() => at = t),
      ),
      if (problem != null) _Problem(problem!),
    ],
  );
}

// --------------------------------------------------------------------- food

/// The shipped food dataset, copied from the app bundle on first use (the
/// commands read a file path).
Future<String> datasetPath() async {
  final dir = await getApplicationSupportDirectory();
  final file = File('${dir.path}/slv.json.gz');
  final bytes = await rootBundle.load('assets/slv-food-dataset.bin');
  if (!await file.exists() || await file.length() != bytes.lengthInBytes) {
    await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  }
  return file.path;
}

/// Where the food dataset file comes from; tests point it elsewhere.
Future<String> Function() foodDataset = datasetPath;

Future<void> openFoodEntry(BuildContext context, {DateTime? clock}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            FoodEntryScreen(now: clock ?? DateTime.now(), dataset: foodDataset),
      ),
    );

/// A found food: one of the profile's own, or a dataset food to adopt.
final class FoodChoice {
  FoodChoice.own(this.id, this.name) : number = null, english = null;
  FoodChoice.dataset(int this.number, this.name, this.english) : id = null;
  final String? id;
  final int? number;
  final String name;
  final String? english;
}

final class FoodEntryScreen extends StatefulWidget {
  const FoodEntryScreen({super.key, required this.now, required this.dataset});
  final DateTime now;
  final Future<String> Function() dataset;

  @override
  State<FoodEntryScreen> createState() => _FoodEntryScreenState();
}

final class _FoodEntryScreenState extends State<FoodEntryScreen> {
  final query = TextEditingController();
  List<Map<String, Object?>> own = const [];
  List<FoodChoice> found = const [];
  Timer? _debounce;
  int _search = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (own.isEmpty) _loadOwn();
  }

  Future<void> _loadOwn() async {
    final list = await ProfileScope.of(context)
        .call<List<Object?>>('food list');
    if (!mounted) return;
    setState(() => own = list.cast<Map<String, Object?>>());
    _run();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    query.dispose();
    super.dispose();
  }

  void _changed(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _run);
  }

  Future<void> _run() async {
    final text = query.text.trim();
    final search = ++_search;
    final lower = text.toLowerCase();
    final mine = [
      for (final f in own)
        if (lower.isEmpty ||
            foldDiacritics('${f['name']}'.toLowerCase())
                .contains(foldDiacritics(lower)))
          FoodChoice.own('${f['id']}', '${f['name']}'),
    ];
    var shipped = <FoodChoice>[];
    if (text.length >= 2) {
      final result = await ProfileScope.of(context).pure<Map<String, Object?>>(
        'food dataset-search',
        {'dataset': await widget.dataset(), 'query': text, 'limit': 30},
      );
      shipped = [
        for (final r in (result['results'] as List).cast<Map>())
          FoodChoice.dataset(
            r['number']! as int,
            '${r['name']}',
            r['english'] as String?,
          ),
      ];
    }
    if (mounted && search == _search) {
      setState(() => found = [...mine, ...shipped]);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Add food')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: query,
            autofocus: true,
            onChanged: _changed,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search your foods and the food database',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: found.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Muted(
                    query.text.trim().length < 2
                        ? 'Type at least two letters to search.'
                        : 'No matches. Try fewer or shorter words.',
                  ),
                )
              : ListView.builder(
                  itemCount: found.length,
                  itemBuilder: (context, i) {
                    final f = found[i];
                    return ListTile(
                      title: Text(f.name),
                      subtitle: Text(
                        f.id != null
                            ? 'Your food'
                            : '${f.english ?? ''}${f.english == null ? '' : ' · '}'
                                  'Livsmedelsverket #${f.number}',
                      ),
                      onTap: () => _choose(f),
                    );
                  },
                ),
        ),
        const Padding(
          padding: EdgeInsets.all(8),
          child: Muted(
            'Food database: Livsmedelsverket (Swedish Food Agency), CC BY 4.0.',
            align: TextAlign.center,
          ),
        ),
      ],
    ),
  );

  Future<void> _choose(FoodChoice choice) async {
    final profile = ProfileScope.of(context);
    final Map<String, Object?> food;
    if (choice.id != null) {
      food =
          (await profile.call<Map<String, Object?>>('food show', {
                'foodId': choice.id,
              }))['food']!
              as Map<String, Object?>;
    } else {
      food =
          (await profile.pure<Map<String, Object?>>('food dataset-show', {
                'dataset': await widget.dataset(),
                'number': choice.number,
              }))['food']!
              as Map<String, Object?>;
    }
    if (!mounted) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FoodAmount(
        choice: choice,
        food: food,
        now: widget.now,
        dataset: widget.dataset,
      ),
    );
    if (saved == true && mounted) Navigator.pop(context);
  }
}

final class _FoodAmount extends StatefulWidget {
  const _FoodAmount({
    required this.choice,
    required this.food,
    required this.now,
    required this.dataset,
  });
  final FoodChoice choice;
  final Map<String, Object?> food;
  final DateTime now;
  final Future<String> Function() dataset;

  @override
  State<_FoodAmount> createState() => _FoodAmountState();
}

final class _FoodAmountState extends State<_FoodAmount> {
  final amount = TextEditingController();
  String? portion;
  late DateTime time = widget.now;
  late String meal = mealFor(widget.now);
  String? problem;
  bool busy = false;

  String get _unit => widget.food['basis'] == '100ml' ? 'ml' : 'g';

  List<Map<String, Object?>> get _portions => [
    for (final p in (widget.food['portions'] as List?) ?? const [])
      p as Map<String, Object?>,
  ];

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final value = parseDecimal(Fmt.of(context).locale, amount.text.trim());
    if (value == null) {
      setState(() => problem = 'Enter an amount.');
      return;
    }
    setState(() => busy = true);
    final profile = ProfileScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      var foodId = widget.choice.id;
      if (foodId == null) {
        // Copy the dataset food into the profile; repeated adoption of an
        // unchanged food publishes nothing.
        final adopted = await profile.write<Map<String, Object?>>(
          'food adopt',
          {'dataset': await widget.dataset(), 'number': widget.choice.number},
        );
        foodId = at(adopted, ['food', 'id'])! as String;
      }
      await profile.write('diary add', {
        'entry': {
          'id': 'food-${_stamp(time)}',
          'at': isoInstant(time),
          'meal': meal,
          'food': {'id': foodId},
          'amount': portion == null
              ? {'value': value, 'unit': _unit}
              : {'portion': portion, 'count': value},
        },
      });
      if (mounted) Navigator.pop(context, true);
      messenger.showSnackBar(
        SnackBar(content: Text('${widget.choice.name} added')),
      );
    } on BodyTmiException catch (e) {
      setState(() {
        busy = false;
        problem = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) => _EntrySheet(
    title: widget.choice.name,
    action: 'Add',
    onAction: busy ? null : _add,
    children: [
      _DecimalField(
        controller: amount,
        label: portion == null ? 'Amount' : 'Portions',
        suffix: portion == null ? _unit : null,
        autofocus: true,
      ),
      if (_portions.isNotEmpty)
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: Text(_unit),
              selected: portion == null,
              onSelected: (_) => setState(() => portion = null),
            ),
            for (final p in _portions)
              ChoiceChip(
                label: Text('${p['name'] ?? p['id']}'),
                selected: portion == p['id'],
                onSelected: (_) => setState(() => portion = '${p['id']}'),
              ),
          ],
        ),
      const SizedBox(height: 8),
      _MealChips(value: meal, onChanged: (m) => setState(() => meal = m)),
      _TimeRow(
        label: 'Time',
        value: time,
        onChanged: (t) => setState(() => time = t),
      ),
      if (problem != null) _Problem(problem!),
    ],
  );
}
