import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_locale/bodytmi_locale.dart';
import 'package:material_ui/material_ui.dart';

import 'format.dart';
import 'profile.dart';
import 'quick_entry.dart';
import 'session.dart' show parseDecimal;

/// Opens the editor for one diary entry (`entry` as `diary day` lists it).
Future<void> editDiaryEntry(
  BuildContext context,
  Map<String, Object?> listed,
) async {
  final entry = listed['entry']! as Map<String, Object?>;
  Map<String, Object?>? food;
  if (entry['food'] case final Map<String, Object?> ref) {
    // The pinned revision the entry uses, for its basis and portions.
    final shown = await ProfileScope.of(context).call<Map<String, Object?>>(
      'food show',
      {'foodId': ref['id'], 'revision': ref['revision']},
    );
    food = shown['food'] as Map<String, Object?>?;
  }
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => DiaryEntryEditor(
      entry: entry,
      name: '${listed['foodName'] ?? 'Quick entry'}',
      food: food,
    ),
  );
}

/// Edits an entry's amount (or quick nutrients), meal and time, or deletes
/// it. The pinned food revision never changes, so a newer version of the
/// food cannot alter what was logged.
final class DiaryEntryEditor extends StatefulWidget {
  const DiaryEntryEditor({
    super.key,
    required this.entry,
    required this.name,
    this.food,
  });

  final Map<String, Object?> entry;
  final String name;
  final Map<String, Object?>? food;

  @override
  State<DiaryEntryEditor> createState() => _DiaryEntryEditorState();
}

const _quickNutrients = [
  ('energy', 'Energy', 'kcal'),
  ('protein', 'Protein', 'g'),
  ('carbohydrate', 'Carbs', 'g'),
  ('fat', 'Fat', 'g'),
];

final class _DiaryEntryEditorState extends State<DiaryEntryEditor> {
  final amount = TextEditingController();
  final quick = {
    for (final (id, _, _) in _quickNutrients) id: TextEditingController(),
  };
  String? portion;
  late DateTime time;
  late String meal;
  String? problem;
  bool busy = false;
  bool _filled = false;

  bool get _isFood => widget.entry['food'] != null;

  String get _unit => widget.food?['basis'] == '100ml' ? 'ml' : 'g';

  List<Map<String, Object?>> get _portions =>
      widget.food == null ? const [] : foodPortions(widget.food!);

  @override
  void initState() {
    super.initState();
    time = DateTime.parse('${widget.entry['at']}').toLocal();
    meal = '${widget.entry['meal'] ?? mealFor(time)}';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_filled) return;
    _filled = true;
    final locale = Fmt.of(context).locale;
    String shown(Object? value) =>
        formatNumber(locale, '$value', grouping: false)['text']! as String;
    final a = widget.entry['amount'];
    if (a is Map && a['portion'] != null) {
      portion = '${a['portion']}';
      amount.text = shown(a['count']);
    } else if (a is Map) {
      final entered = (a['entered'] ?? a) as Map;
      amount.text = shown(entered['value']);
    }
    final q = widget.entry['quick'];
    if (q is Map) {
      for (final MapEntry(:key, :value) in quick.entries) {
        final v = q[key];
        if (v is Map) value.text = shown((v['entered'] ?? v)['value']);
      }
    }
  }

  @override
  void dispose() {
    amount.dispose();
    for (final c in quick.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final locale = Fmt.of(context).locale;
    final entry = <String, Object?>{
      'id': widget.entry['id'],
      'at': isoInstant(time),
      'meal': meal,
      if (widget.entry['notes'] != null) 'notes': widget.entry['notes'],
    };
    if (_isFood) {
      final value = parseDecimal(locale, amount.text.trim());
      if (value == null) {
        setState(() => problem = 'Enter an amount.');
        return;
      }
      entry['food'] = widget.entry['food'];
      entry['amount'] = portion == null
          ? {'value': value, 'unit': _unit}
          : {'portion': portion, 'count': value};
    } else {
      final nutrients = <String, Object?>{};
      for (final (id, label, unit) in _quickNutrients) {
        final text = quick[id]!.text.trim();
        if (text.isEmpty) continue;
        final value = parseDecimal(locale, text);
        if (value == null) {
          setState(() => problem = '$label is not a number.');
          return;
        }
        nutrients[id] = {'value': value, 'unit': unit};
      }
      if (!nutrients.containsKey('energy')) {
        setState(() => problem = 'Enter the energy.');
        return;
      }
      entry['quick'] = nutrients;
    }
    await _run('Entry updated', (p) {
      return p.write('diary update', {
        'id': widget.entry['id'],
        'expectedVersion': widget.entry['version'],
        'entry': entry,
      });
    });
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: Text('${widget.name} is removed from the diary.'),
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
    await _run('Entry deleted', (p) {
      return p.write('diary delete', {
        'id': widget.entry['id'],
        'expectedVersion': widget.entry['version'],
        'confirm': true,
      });
    });
  }

  Future<void> _run(
    String done,
    Future<Object?> Function(ProfileClient profile) write,
  ) async {
    final profile = ProfileScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      busy = true;
      problem = null;
    });
    try {
      await write(profile);
      if (mounted) Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } on BodyTmiException catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          problem = e.code == 'conflict'
              ? 'This entry changed elsewhere; close and open it again.'
              : e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => EntrySheet(
    title: widget.name,
    action: 'Save',
    onAction: busy ? null : _save,
    children: [
      if (_isFood) ...[
        DecimalField(
          controller: amount,
          label: portion == null ? 'Amount' : 'Portions',
          suffix: portion == null ? _unit : null,
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
      ] else ...[
        DecimalField(
          controller: quick['energy']!,
          label: 'Energy',
          suffix: 'kcal',
        ),
        Row(
          children: [
            for (final (id, label, unit) in _quickNutrients.skip(1)) ...[
              Expanded(
                child: DecimalField(
                  controller: quick[id]!,
                  label: label,
                  suffix: unit,
                ),
              ),
              if (id != 'fat') const SizedBox(width: 8),
            ],
          ],
        ),
      ],
      const SizedBox(height: 8),
      MealChips(value: meal, onChanged: (m) => setState(() => meal = m)),
      TimeRow(
        label: 'Time',
        value: time,
        onChanged: (t) => setState(() => time = t),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: busy ? null : _delete,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Delete entry'),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
        ),
      ),
      if (problem != null) ProblemText(problem!),
    ],
  );
}
