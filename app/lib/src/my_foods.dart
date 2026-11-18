import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_locale/bodytmi_locale.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'format.dart';
import 'gyms.dart' show freeId;
import 'profile.dart';
import 'quick_entry.dart';
import 'session.dart' show parseDecimal;
import 'widgets.dart';

/// Opens My foods & recipes (from the Food tab).
Future<void> openMyFoods(BuildContext context) =>
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const MyFoodsScreen()));

/// The nutrients a food form asks for, with their label units.
const foodNutrients = [
  ('energy', 'Energy', 'kcal'),
  ('protein', 'Protein', 'g'),
  ('carbohydrate', 'Carbohydrate', 'g'),
  ('fat', 'Fat', 'g'),
  ('fibre', 'Fibre', 'g'),
  ('salt', 'Salt', 'g'),
];

/// Your foods (typed in, adopted from the dataset, looked up) and your
/// recipes. Every save is a new revision; logged entries keep theirs.
final class MyFoodsScreen extends StatelessWidget {
  const MyFoodsScreen({super.key});

  static Future<List<Map<String, Object?>>> _load(ProfileClient p) async => [
    for (final f in await p.call<List<Object?>>('food list'))
      f! as Map<String, Object?>,
  ]..sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));

  @override
  Widget build(BuildContext context) =>
      ProfileLoader<List<Map<String, Object?>>>(
        load: _load,
        builder: (context, foods) => Scaffold(
          appBar: AppBar(title: const Text('My foods & recipes')),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _add(context, foods),
            icon: const Icon(Icons.add),
            label: const Text('Add'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            children: [
              for (final (title, kind) in [
                ('Recipes', 'composite'),
                ('Foods', 'base'),
              ])
                SectionCard(
                  title: title,
                  child: () {
                    final list = foods.where((f) => f['kind'] == kind).toList();
                    if (list.isEmpty) {
                      return EmptyNote(
                        kind == 'composite'
                            ? 'No recipes yet. A recipe combines your foods, '
                                  'optionally as a batch split into portions.'
                            : 'No foods yet. Add one from a label, or log a '
                                  'dataset food to keep a copy here.',
                      );
                    }
                    return Column(
                      children: [
                        for (final f in list)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('${f['name']}'),
                            subtitle: Text(_source(f)),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _edit(context, f, foods),
                          ),
                      ],
                    );
                  }(),
                ),
            ],
          ),
        ),
      );

  static String _source(Map<String, Object?> f) => [
    'revision ${f['revision']}',
    switch (at(f, ['source', 'kind'])) {
      'label' => 'from a label',
      'dataset' => 'from the food database',
      'lookup' => 'looked up',
      _ => null,
    },
  ].whereType<String>().join(' · ');

  Future<void> _add(
    BuildContext context,
    List<Map<String, Object?>> foods,
  ) async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.label_outline),
              title: const Text('Food'),
              subtitle: const Text('nutrients from a label, per 100 g or ml'),
              onTap: () => Navigator.pop(context, 'base'),
            ),
            ListTile(
              leading: const Icon(Icons.restaurant_menu),
              title: const Text('Recipe'),
              subtitle: const Text('made from your foods'),
              onTap: () => Navigator.pop(context, 'composite'),
            ),
          ],
        ),
      ),
    );
    if (kind == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => kind == 'base'
            ? FoodFormScreen(foods: foods)
            : RecipeFormScreen(foods: foods),
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    Map<String, Object?> listed,
    List<Map<String, Object?>> foods,
  ) async {
    final shown = await ProfileScope.of(context)
        .call<Map<String, Object?>>('food show', {'foodId': listed['id']});
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => listed['kind'] == 'composite'
            ? RecipeFormScreen(foods: foods, existing: shown)
            : FoodFormScreen(foods: foods, existing: shown),
      ),
    );
  }
}

/// Text in the locale for an entered decimal, without grouping.
String _shown(PresentationLocale locale, Object? value) => value == null
    ? ''
    : formatNumber(locale, '$value', grouping: false)['text']! as String;

final class _PortionRow {
  _PortionRow([String name = '', String grams = ''])
    : name = TextEditingController(text: name),
      grams = TextEditingController(text: grams);
  final TextEditingController name, grams;
  void dispose() {
    name.dispose();
    grams.dispose();
  }
}

/// A base food: name, per 100 g or 100 ml, the label's nutrients (blank
/// means not declared, never zero) and named portions.
final class FoodFormScreen extends StatefulWidget {
  const FoodFormScreen({
    super.key,
    required this.foods,
    this.existing,
    this.draft,
  });
  final List<Map<String, Object?>> foods;
  final Map<String, Object?>? existing; // food show response

  /// An unsaved food to review, e.g. from a barcode lookup.
  final Map<String, Object?>? draft;

  @override
  State<FoodFormScreen> createState() => _FoodFormScreenState();
}

final class _FoodFormScreenState extends State<FoodFormScreen> {
  Map<String, Object?> get _old =>
      (widget.existing?['food'] as Map<String, Object?>?) ??
      widget.draft ??
      const {};
  late final name = TextEditingController(text: '${_old['name'] ?? ''}');
  late String basis = '${_old['basis'] ?? '100g'}';

  /// The prefilled text per nutrient: a value type such as "<" stays only
  /// while its value is unchanged.
  final _original = <String, String>{};
  final nutrients = {
    for (final (id, _, _) in foodNutrients) id: TextEditingController(),
  };
  final portions = <_PortionRow>[];
  String? problem;
  bool _filled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_filled) return;
    _filled = true;
    final locale = Fmt.of(context).locale;
    for (final MapEntry(:key, :value) in nutrients.entries) {
      final q = at(_old, ['nutrients', key]);
      value.text = _shown(
        locale,
        at(q, ['entered', 'value']) ?? at(q, ['value']),
      );
      _original[key] = value.text;
    }
    for (final p in (_old['portions'] as List?) ?? const []) {
      portions.add(
        _PortionRow(
          '${(p as Map)['name'] ?? p['id']}',
          _shown(locale, at(p, ['amount', 'entered', 'value'])),
        ),
      );
    }
  }

  @override
  void dispose() {
    name.dispose();
    for (final c in nutrients.values) {
      c.dispose();
    }
    for (final p in portions) {
      p.dispose();
    }
    super.dispose();
  }

  String get _unit => basis == '100ml' ? 'ml' : 'g';

  Future<void> _save() async {
    final locale = Fmt.of(context).locale;
    if (name.text.trim().isEmpty) {
      setState(() => problem = 'Give the food a name.');
      return;
    }
    final values = <String, Object?>{};
    for (final (id, label, unit) in foodNutrients) {
      final text = nutrients[id]!.text.trim();
      if (text.isEmpty) continue;
      final v = parseDecimal(locale, text);
      if (v == null) {
        setState(() => problem = '$label is not a number.');
        return;
      }
      values[id] = <String, Object?>{'value': v, 'unit': unit};
    }
    if (!values.containsKey('energy')) {
      setState(() => problem = 'Enter at least the energy.');
      return;
    }
    final portionList = <Object?>[];
    final ids = <String>{};
    for (final p in portions) {
      if (p.name.text.trim().isEmpty && p.grams.text.trim().isEmpty) continue;
      final v = parseDecimal(locale, p.grams.text.trim());
      if (p.name.text.trim().isEmpty || v == null) {
        setState(() => problem = 'Each portion needs a name and an amount.');
        return;
      }
      final id = freeId(p.name.text, ids, fallback: 'portion');
      ids.add(id);
      portionList.add(<String, Object?>{
        'id': id,
        'name': p.name.text.trim(),
        'amount': <String, Object?>{'value': v, 'unit': _unit},
      });
    }
    final food = <String, Object?>{
      ..._old,
      'id':
          _old['id'] ??
          freeId(name.text, [
            for (final f in widget.foods) '${f['id']}',
          ], fallback: 'food'),
      'name': name.text.trim(),
      'kind': 'base',
      'basis': basis,
      'source': _old['source'] ?? <String, Object?>{'kind': 'label'},
      'nutrients': values,
    }..remove('portions');
    if (portionList.isNotEmpty) food['portions'] = portionList;
    final types = <String, Object?>{
      for (final e in ((_old['valueTypes'] as Map?) ?? const {}).entries)
        if (values.containsKey(e.key) &&
            nutrients['${e.key}']?.text.trim() == _original['${e.key}'])
          '${e.key}': e.value,
    };
    food.remove('valueTypes');
    if (types.isNotEmpty) food['valueTypes'] = types;
    await _publish(context, food, widget.existing);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.existing != null
            ? 'Food'
            : widget.draft != null
            ? 'Review food'
            : 'New food',
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        TextField(
          controller: name,
          decoration: const InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        // The basis is fixed once a food exists or comes from a lookup;
        // a disabled toggle would hide which one it is, so say it.
        if (widget.existing == null && widget.draft == null)
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: '100g', label: Text('per 100 g')),
              ButtonSegment(value: '100ml', label: Text('per 100 ml')),
            ],
            selected: {basis},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => basis = s.single),
          )
        else
          Text(
            basis == '100ml' ? 'Values per 100 ml' : 'Values per 100 g',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        const SizedBox(height: 10),
        if (at(_old, ['source', 'kind']) == 'lookup')
          Muted(
            'From Open Food Facts'
            '${at(_old, ['source', 'url']) == null ? '' : ' (${at(_old, ['source', 'url'])})'}. '
            'Check it against the package before saving. '
            '${at(_old, ['source', 'notes']) ?? ''}',
          ),
        const Muted(
          'As printed on the label. Leave a value blank if the '
          'label does not give it; it is then unknown, not zero.',
        ),
        const SizedBox(height: 8),
        for (final (id, label, unit) in foodNutrients)
          DecimalField(controller: nutrients[id]!, label: label, suffix: unit),
        const Text('Portions'),
        for (final (i, p) in portions.indexed)
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: p.name,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: DecimalField(
                  controller: p.grams,
                  label: 'Amount',
                  suffix: _unit,
                ),
              ),
              IconButton(
                tooltip: 'Remove portion',
                onPressed: () => setState(() => portions.removeAt(i).dispose()),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => portions.add(_PortionRow())),
            icon: const Icon(Icons.add),
            label: const Text('Add portion'),
          ),
        ),
        if (problem != null) ProblemText(problem!),
        const SizedBox(height: 8),
        FilledButton(onPressed: _save, child: const Text('Save')),
        if (widget.existing != null)
          const Muted(
            'Saving makes a new revision; logged entries keep the '
            'one they used.',
          ),
      ],
    ),
  );
}

Future<void> _publish(
  BuildContext context,
  Map<String, Object?> food,
  Map<String, Object?>? existing,
) async {
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ProfileScope.of(context).write('food publish', {
      'food': food,
      'expectedRevision': existing?['revision'] ?? 0,
    });
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text('${food['name']} saved')));
  } on BodyTmiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

final class _Ingredient {
  _Ingredient(
    this.id,
    this.revision,
    this.name,
    this.unit, [
    String amount = '',
  ]) : amount = TextEditingController(text: amount);
  final String id;
  final int revision;
  final String name;
  String unit; // g or ml
  final TextEditingController amount;
}

/// A recipe: ingredients from your foods (each pinned to the revision
/// chosen), and optionally a batch with its cooked mass and portions.
final class RecipeFormScreen extends StatefulWidget {
  const RecipeFormScreen({super.key, required this.foods, this.existing});
  final List<Map<String, Object?>> foods;
  final Map<String, Object?>? existing; // food show response

  @override
  State<RecipeFormScreen> createState() => _RecipeFormScreenState();
}

final class _RecipeFormScreenState extends State<RecipeFormScreen> {
  Map<String, Object?> get _old =>
      (widget.existing?['food'] as Map<String, Object?>?) ?? const {};
  late final name = TextEditingController(text: '${_old['name'] ?? ''}');
  final ingredients = <_Ingredient>[];
  final finalMass = TextEditingController();
  final batchPortions = TextEditingController();
  String? problem;
  bool _filled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_filled) return;
    _filled = true;
    final locale = Fmt.of(context).locale;
    for (final c in (_old['components'] as List?) ?? const []) {
      final ref = (c as Map)['food'] as Map;
      final listed = widget.foods
          .where((f) => f['id'] == ref['id'])
          .firstOrNull;
      final entered = (at(c, ['amount', 'entered']) ?? c['amount']) as Map?;
      ingredients.add(
        _Ingredient(
          '${ref['id']}',
          ref['revision']! as int,
          '${listed?['name'] ?? ref['id']}',
          '${entered?['unit'] ?? 'g'}',
          _shown(locale, entered?['value']),
        ),
      );
    }
    final batch = _old['batch'] as Map?;
    if (batch != null) {
      finalMass.text = _shown(
        locale,
        at(batch, ['finalMass', 'entered', 'value']),
      );
      batchPortions.text = '${batch['portions'] ?? ''}';
    }
  }

  @override
  void dispose() {
    name.dispose();
    finalMass.dispose();
    batchPortions.dispose();
    for (final i in ingredients) {
      i.amount.dispose();
    }
    super.dispose();
  }

  Future<void> _addIngredient() async {
    final candidates = [
      for (final f in widget.foods)
        if (f['id'] != _old['id']) f,
    ];
    final chosen = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _FoodPicker(foods: candidates),
    );
    if (chosen == null || !mounted) return;
    final shown = await ProfileScope.of(context)
        .call<Map<String, Object?>>('food show', {'foodId': chosen['id']});
    setState(
      () => ingredients.add(
        _Ingredient(
          '${chosen['id']}',
          shown['revision']! as int,
          '${chosen['name']}',
          at(shown, ['food', 'basis']) == '100ml' ? 'ml' : 'g',
        ),
      ),
    );
  }

  Future<void> _save() async {
    final locale = Fmt.of(context).locale;
    if (name.text.trim().isEmpty) {
      setState(() => problem = 'Give the recipe a name.');
      return;
    }
    if (ingredients.isEmpty) {
      setState(() => problem = 'Add at least one ingredient.');
      return;
    }
    final components = <Object?>[];
    for (final i in ingredients) {
      final v = parseDecimal(locale, i.amount.text.trim());
      if (v == null) {
        setState(() => problem = 'Enter how much ${i.name} goes in.');
        return;
      }
      components.add(<String, Object?>{
        'food': <String, Object?>{'id': i.id, 'revision': i.revision},
        'amount': <String, Object?>{'value': v, 'unit': i.unit},
      });
    }
    final recipe = <String, Object?>{
      'id':
          _old['id'] ??
          freeId(name.text, [
            for (final f in widget.foods) '${f['id']}',
          ], fallback: 'recipe'),
      'name': name.text.trim(),
      'kind': 'composite',
      'components': components,
    };
    final mass = finalMass.text.trim();
    final count = batchPortions.text.trim();
    if (mass.isNotEmpty || count.isNotEmpty) {
      final m = parseDecimal(locale, mass);
      final n = count.isEmpty ? null : int.tryParse(count);
      if (m == null || (count.isNotEmpty && n == null)) {
        setState(
          () => problem =
              'The batch needs its cooked weight, and portions '
              'as a whole number.',
        );
        return;
      }
      recipe['batch'] = <String, Object?>{
        'finalMass': <String, Object?>{'value': m, 'unit': 'g'},
        'portions': ?n,
      };
    }
    await _publish(context, recipe, widget.existing);
  }

  @override
  Widget build(BuildContext context) {
    final f = Fmt.of(context);
    final whole = widget.existing?['whole'] as Map?;
    final portion = widget.existing?['perPortion'] as Map?;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New recipe' : 'Recipe'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          TextField(
            controller: name,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Ingredients'),
          for (final (k, i) in ingredients.indexed)
            Row(
              children: [
                Expanded(flex: 3, child: Text(i.name)),
                Expanded(
                  flex: 2,
                  child: DecimalField(
                    controller: i.amount,
                    label: 'Amount',
                    suffix: i.unit,
                  ),
                ),
                IconButton(
                  tooltip: 'Remove ingredient',
                  onPressed: () => setState(() => ingredients.removeAt(k)),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addIngredient,
              icon: const Icon(Icons.add),
              label: const Text('Add ingredient'),
            ),
          ),
          const SizedBox(height: 8),
          const Text('Batch (optional)'),
          const Muted(
            'Weigh the cooked dish to log it by weight, or split it '
            'into equal portions.',
          ),
          Row(
            children: [
              Expanded(
                child: DecimalField(
                  controller: finalMass,
                  label: 'Cooked weight',
                  suffix: 'g',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: batchPortions,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Portions'),
                ),
              ),
            ],
          ),
          if (whole != null)
            SectionCard(
              title: 'Nutrition',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Whole: ${_nutrition(f, whole)}'),
                  if (portion != null)
                    Text('Portion: ${_nutrition(f, portion)}'),
                  const Muted(
                    'From the saved revision; partial values '
                    'leave out ingredients that do not declare them.',
                  ),
                ],
              ),
            ),
          if (problem != null) ProblemText(problem!),
          const SizedBox(height: 8),
          FilledButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
    );
  }

  static String _nutrition(Fmt f, Map n) {
    final parts = <String>[];
    for (final (id, label, unit) in foodNutrients.take(4)) {
      final v = at(n, ['nutrients', id]) as Map?;
      if (v == null || v['value'] == null) continue;
      final partial = v['status'] == 'partial' ? ' (partial)' : '';
      parts.add(
        id == 'energy'
            ? '${f.number(v['value'], digits: 0)} kcal$partial'
            : '${label.toLowerCase()} ${f.number(v['value'])} $unit$partial',
      );
    }
    return parts.isEmpty ? 'unknown' : parts.join(' · ');
  }
}

final class _FoodPicker extends StatefulWidget {
  const _FoodPicker({required this.foods});
  final List<Map<String, Object?>> foods;

  @override
  State<_FoodPicker> createState() => _FoodPickerState();
}

final class _FoodPickerState extends State<_FoodPicker> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final q = query.trim().toLowerCase();
    final list = [
      for (final f in widget.foods)
        if (q.isEmpty || '${f['name']}'.toLowerCase().contains(q)) f,
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Find one of your foods',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => query = v),
          ),
          if (widget.foods.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: EmptyNote(
                'Add or log foods first; recipes use your own foods.',
              ),
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final f in list)
                  ListTile(
                    title: Text('${f['name']}'),
                    subtitle: Text(
                      f['kind'] == 'composite' ? 'recipe' : 'food',
                    ),
                    onTap: () => Navigator.pop(context, f),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Where barcode lookups go; tests point it at a local server.
String? openFoodFactsEndpoint;

/// Asks for a barcode, looks it up on Open Food Facts (sending only the
/// barcode) and opens the result for review before anything is saved. A
/// barcode already saved opens that food instead.
Future<void> lookUpBarcode(
  BuildContext context,
  List<Map<String, Object?>> foods,
) async {
  final profile = ProfileScope.of(context);
  final code = await showDialog<String>(
    context: context,
    builder: (_) => const _BarcodeDialog(),
  );
  if (code == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final saved = foods.where((f) => f['id'] == 'off-$code').firstOrNull;
  try {
    if (saved != null) {
      final shown = await profile.call<Map<String, Object?>>('food show', {
        'foodId': saved['id'],
      });
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => FoodFormScreen(foods: foods, existing: shown),
        ),
      );
      return;
    }
    final found = await profile.pure<Map<String, Object?>>('food lookup', {
      'barcode': code,
      'endpoint': ?openFoodFactsEndpoint,
    });
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => FoodFormScreen(
          foods: foods,
          draft: found['food'] as Map<String, Object?>?,
        ),
      ),
    );
  } on BodyTmiException catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          e.code == 'io' || e.code == 'storage'
              ? 'Open Food Facts could not be reached.'
              : e.message,
        ),
      ),
    );
  }
}

final class _BarcodeDialog extends StatefulWidget {
  const _BarcodeDialog();

  @override
  State<_BarcodeDialog> createState() => _BarcodeDialogState();
}

final class _BarcodeDialogState extends State<_BarcodeDialog> {
  final code = TextEditingController();
  String? problem;

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  void _done() {
    final digits = code.text.replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^[0-9]{6,14}$').hasMatch(digits)) {
      setState(() => problem = 'A barcode is 6 to 14 digits.');
      return;
    }
    Navigator.pop(context, digits);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Look up a barcode'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: code,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Barcode'),
          onSubmitted: (_) => _done(),
        ),
        if (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () async {
                final scanned = await Navigator.of(context).push<String>(
                  MaterialPageRoute(builder: (_) => const BarcodeScanScreen()),
                );
                if (scanned == null || !mounted) return;
                code.text = scanned;
                _done();
              },
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Scan with the camera'),
            ),
          ),
        const SizedBox(height: 8),
        const Muted(
          'Sends only this number to Open Food Facts (openfoodfacts.org). '
          'Nothing is saved until you review the result. Scanning reads '
          'the code on the phone (Google ML Kit, on-device); typing it '
          'needs no camera.',
        ),
        if (problem != null) ProblemText(problem!),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _done, child: const Text('Look up')),
    ],
  );
}

/// Reads one product barcode with the camera and returns its digits. The
/// camera runs only while this screen is open.
final class BarcodeScanScreen extends StatefulWidget {
  const BarcodeScanScreen({super.key});

  @override
  State<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

final class _BarcodeScanScreenState extends State<BarcodeScanScreen> {
  final controller = MobileScannerController(
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
    ],
  );
  bool done = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan a barcode')),
    body: Stack(
      children: [
        MobileScanner(
          controller: controller,
          onDetect: (capture) {
            if (done) return;
            for (final b in capture.barcodes) {
              final v = b.rawValue;
              if (v != null && RegExp(r'^[0-9]{6,14}$').hasMatch(v)) {
                done = true;
                Navigator.pop(context, v);
                return;
              }
            }
          },
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                error.errorCode == MobileScannerErrorCode.permissionDenied
                    ? 'Camera access was not allowed. Type the barcode '
                          'instead, or allow the camera in settings.'
                    : 'The camera could not start. Type the barcode instead.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        const Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Point the camera at the barcode.',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ),
      ],
    ),
  );
}
