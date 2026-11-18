import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:material_ui/material_ui.dart';

import 'format.dart';
import 'journal.dart' show journalSlug;
import 'profile.dart';
import 'quick_entry.dart';
import 'session.dart' show parseDecimal;
import 'widgets.dart';

/// Opens Gyms & equipment (from More).
Future<void> openGyms(BuildContext context) =>
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const GymsScreen()));

/// A free identifier from [name]: its slug, with `-2`, `-3`… when taken.
String freeId(String name, Iterable<String> taken, {String fallback = 'item'}) {
  final base = journalSlug(name).isEmpty ? fallback : journalSlug(name);
  final used = taken.toSet();
  if (!used.contains(base)) return base;
  for (var n = 2; ; n++) {
    if (!used.contains('$base-$n')) return '$base-$n';
  }
}

String _m(Fmt f, Object? q, {bool unit = true}) =>
    f.quantity(q, digits: 3, unit: unit);

/// Exercises to attach setup notes to: the catalog plus every exercise in
/// the workouts of published programs (id → display name).
Future<Map<String, String>> knownExercises(ProfileClient p) async {
  String pretty(String id) {
    final t = id.replaceAll('-', ' ');
    return t.isEmpty ? t : '${t[0].toUpperCase()}${t.substring(1)}';
  }

  final out = <String, String>{};
  final workouts = <String>{};
  void days(Object? node) {
    if (node is Map) {
      if (node['templateId'] != null && node['revision'] is int) {
        workouts.add('${node['templateId']}@${node['revision']}');
      }
      node.values.forEach(days);
    } else if (node is List) {
      node.forEach(days);
    }
  }

  for (final r in await p.call<List<Object?>>('program list')) {
    days(r);
  }
  for (final w in workouts) {
    final [id, revision] = w.split('@');
    final rev = await p.call<Map<String, Object?>>('store revision', {
      'templateId': id,
      'revision': int.parse(revision),
    });
    for (final slot
        in (at(rev, ['definition', 'slots']) as List?) ?? const []) {
      final e = '${(slot as Map)['exercise']}';
      out[e] = pretty(e);
    }
  }
  for (final r in await p.call<List<Object?>>('exercise list')) {
    final e = (r! as Map)['exercise'] as Map;
    out['${e['id']}'] = '${e['name'] ?? pretty('${e['id']}')}';
  }
  return out;
}

/// One line describing how an instance is loaded or set.
String loadingSummary(Fmt f, Map<String, Object?> instance) {
  final loading = instance['loading'] as Map?;
  if (loading != null) {
    final components = [
      for (final c in (loading['components'] as List?) ?? const [])
        if ((c as Map)['include'] != false) c,
    ];
    final tare = components.isEmpty
        ? ''
        : '${components.map((c) => _m(f, c['mass'])).join(' + ')} · ';
    final plates = [
      for (final p in (loading['plates'] as List?) ?? const [])
        '${(p as Map)['count']}×${_m(f, p['mass'], unit: false)}',
    ];
    final sides = at(loading, ['channel', 'sides']) == 1 ? 'one side' : '';
    return [
      '$tare${plates.join(', ')} ${at(loading, ['plates', 0, 'mass', 'unit']) ?? ''}'
          .trim(),
      if (sides.isNotEmpty) sides,
    ].join(' · ');
  }
  final scale = instance['scale'] as Map?;
  if (scale != null) {
    final range = scale['range'] as Map?;
    if (range != null) {
      final start = Decimal.parse('${range['start']}');
      final step = Decimal.parse('${range['step']}');
      final last =
          start + step * Decimal.parse('${(range['count'] as int) - 1}');
      return '${f.number(range['start'], digits: 3)}–${f.number('$last', digits: 3)} ${scale['unit']} '
          'in steps of ${f.number(range['step'], digits: 3)}';
    }
    return '${(scale['ticks'] as List?)?.length ?? 0} settings (${scale['unit']})';
  }
  return 'no load settings';
}

final class _GymData {
  _GymData(this.gyms, this.equipment, this.instances, this.exercises);
  final Map<String, String> exercises; // id → display name
  final List<Map<String, Object?>> gyms; // latest revision records
  final Map<String, Map<String, Object?>> equipment; // id → latest record
  final List<Map<String, Object?>> instances; // latest revision records
}

Map<String, Map<String, Object?>> _latest(List<Object?> rows, String key) {
  final out = <String, Map<String, Object?>>{};
  for (final r in rows) {
    final row = r! as Map<String, Object?>;
    final id = '${(row[key]! as Map)['id']}';
    final prev = out[id];
    if (prev == null ||
        (row['revision']! as int) > (prev['revision']! as int)) {
      out[id] = row;
    }
  }
  return out;
}

final class GymsScreen extends StatelessWidget {
  const GymsScreen({super.key});

  static Future<_GymData> _load(ProfileClient p) async => _GymData(
    (_latest(await p.call<List<Object?>>('gym list'), 'gym').values.toList())
      ..sort(
        (a, b) =>
            '${at(a, ['gym', 'name'])}'.compareTo('${at(b, ['gym', 'name'])}'),
      ),
    _latest(await p.call<List<Object?>>('equipment list'), 'equipment'),
    _latest(
      await p.call<List<Object?>>('instance list'),
      'instance',
    ).values.toList(),
    await knownExercises(p),
  );

  @override
  Widget build(BuildContext context) => ProfileLoader<_GymData>(
    load: _load,
    builder: (context, d) => Scaffold(
      appBar: AppBar(title: const Text('Gyms & equipment')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, d),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        children: [
          if (d.gyms.isEmpty && d.instances.isEmpty)
            const SectionCard(
              child: EmptyNote(
                'No gyms or equipment yet. Add the places you train and the '
                'bars, dumbbells and machines there; the plate calculator and '
                'sessions then use what is actually available.',
              ),
            ),
          for (final g in d.gyms) _gymCard(context, d, g),
          if (d.instances.any((i) => at(i, ['instance', 'gym']) == null))
            _instances(
              context,
              d,
              'Not at a gym',
              d.instances.where((i) => at(i, ['instance', 'gym']) == null),
              null,
            ),
        ],
      ),
    ),
  );

  Widget _gymCard(BuildContext context, _GymData d, Map<String, Object?> g) {
    final gym = g['gym']! as Map<String, Object?>;
    return _instances(
      context,
      d,
      '${gym['name'] ?? gym['id']}',
      d.instances.where((i) => at(i, ['instance', 'gym']) == gym['id']),
      g,
    );
  }

  Widget _instances(
    BuildContext context,
    _GymData d,
    String title,
    Iterable<Map<String, Object?>> rows,
    Map<String, Object?>? gym,
  ) {
    final f = Fmt.of(context);
    final preferred = (at(gym, ['gym', 'preferred']) as Map?) ?? const {};
    final list = rows.toList()
      ..sort(
        (a, b) => '${at(a, ['instance', 'name']) ?? at(a, ['instance', 'id'])}'
            .compareTo(
              '${at(b, ['instance', 'name']) ?? at(b, ['instance', 'id'])}',
            ),
      );
    return SectionCard(
      title: title,
      trailing: gym == null
          ? null
          : IconButton(
              tooltip: 'Edit gym',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => GymSheet(
                  existing: gym,
                  taken: [
                    for (final x in d.gyms) '${at(x, ['gym', 'id'])}',
                  ],
                ),
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (gym != null && at(gym, ['gym', 'notes']) != null)
            Muted('${at(gym, ['gym', 'notes'])}'),
          if (list.isEmpty) const EmptyNote('No equipment here yet.'),
          for (final row in list)
            () {
              final i = row['instance']! as Map<String, Object?>;
              final eq =
                  d.equipment['${i['equipmentId']}']?['equipment'] as Map?;
              final isPreferred = preferred[i['equipmentId']] == i['id'];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${i['name'] ?? eq?['name'] ?? i['id']}'),
                subtitle: Text(
                  [
                    '${eq?['name'] ?? i['equipmentId']}',
                    loadingSummary(f, i),
                  ].join(' · '),
                ),
                trailing: isPreferred ? const Pill('preferred') : null,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => InstanceScreen(instanceId: '${i['id']}'),
                  ),
                ),
              );
            }(),
          if (gym != null) _setupNotes(context, d, gym),
        ],
      ),
    );
  }

  Widget _setupNotes(
    BuildContext context,
    _GymData d,
    Map<String, Object?> gym,
  ) {
    final notes = (at(gym, ['gym', 'setupNotes']) as Map?) ?? const {};
    Future<void> edit([String? exercise]) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          SetupNoteSheet(gym: gym, exercises: d.exercises, exercise: exercise),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in notes.entries)
          InkWell(
            onTap: () => edit('${e.key}'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.sticky_note_2_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${d.exercises[e.key] ?? e.key}: ',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          TextSpan(text: '${e.value}'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => edit(),
            icon: const Icon(Icons.add),
            label: const Text('Setup note'),
          ),
        ),
      ],
    );
  }

  Future<void> _add(BuildContext context, _GymData d) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: const Text('Gym'),
              onTap: () => Navigator.pop(context, 'gym'),
            ),
            ListTile(
              leading: const Icon(Icons.fitness_center),
              title: const Text('Equipment'),
              subtitle: const Text('a bar, a pair of dumbbells, a machine…'),
              onTap: () => Navigator.pop(context, 'instance'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => choice == 'gym'
          ? GymSheet(
              taken: [
                for (final x in d.gyms) '${at(x, ['gym', 'id'])}',
              ],
            )
          : InstanceSheet(
              gyms: d.gyms,
              equipment: d.equipment,
              takenIds: [
                for (final x in d.instances) '${at(x, ['instance', 'id'])}',
              ],
            ),
    );
  }
}

/// Adds or renames a gym; preferences and setup notes are kept.
final class GymSheet extends StatefulWidget {
  const GymSheet({super.key, this.existing, required this.taken});
  final Map<String, Object?>? existing;
  final List<String> taken;

  @override
  State<GymSheet> createState() => _GymSheetState();
}

final class _GymSheetState extends State<GymSheet> {
  late final name = TextEditingController(
    text: '${at(widget.existing, ['gym', 'name']) ?? ''}',
  );
  late final notes = TextEditingController(
    text: '${at(widget.existing, ['gym', 'notes']) ?? ''}',
  );
  String? problem;

  @override
  void dispose() {
    name.dispose();
    notes.dispose();
    super.dispose();
  }

  void _save() {
    if (name.text.trim().isEmpty) {
      setState(() => problem = 'Give the gym a name.');
      return;
    }
    final old = (widget.existing?['gym'] as Map<String, Object?>?) ?? const {};
    final gym = {
      ...old,
      'id': old['id'] ?? freeId(name.text, widget.taken, fallback: 'gym'),
      'name': name.text.trim(),
      'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
    }..removeWhere((_, v) => v == null);
    saveAndClose(
      context,
      widget.existing == null ? 'Gym added' : 'Gym updated',
      (p) => p.write('gym publish', {
        'gym': gym,
        'expectedRevision': widget.existing?['revision'] ?? 0,
      }),
    );
  }

  @override
  Widget build(BuildContext context) => EntrySheet(
    title: widget.existing == null ? 'New gym' : 'Gym',
    action: 'Save',
    onAction: _save,
    children: [
      TextField(
        controller: name,
        decoration: const InputDecoration(
          labelText: 'Name',
          hintText: 'e.g. Home, City gym',
          border: OutlineInputBorder(),
        ),
      ),
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

final class _PlateRow {
  _PlateRow([String mass = '', String count = ''])
    : mass = TextEditingController(text: mass),
      count = TextEditingController(text: count);
  final TextEditingController mass, count;
  void dispose() {
    mass.dispose();
    count.dispose();
  }
}

/// Adds or edits an equipment instance: what it is, where it is, and how
/// its load is set (plates on a bar or handle, or a selector's settings).
/// Each save is a new revision; sessions keep the revision they used.
final class InstanceSheet extends StatefulWidget {
  const InstanceSheet({
    super.key,
    this.existing,
    required this.gyms,
    required this.equipment,
    required this.takenIds,
  });
  final Map<String, Object?>? existing;
  final List<Map<String, Object?>> gyms;
  final Map<String, Map<String, Object?>> equipment;
  final List<String> takenIds;

  @override
  State<InstanceSheet> createState() => _InstanceSheetState();
}

final class _InstanceSheetState extends State<InstanceSheet> {
  Map<String, Object?> get _old =>
      (widget.existing?['instance'] as Map<String, Object?>?) ?? const {};

  late final name = TextEditingController(text: '${_old['name'] ?? ''}');
  final newEquipment = TextEditingController();
  bool interchangeable = false;
  late String? equipmentId =
      _old['equipmentId'] as String? ?? widget.equipment.keys.firstOrNull;
  late String? gym =
      _old['gym'] as String? ??
      (widget.gyms.isEmpty ? null : '${at(widget.gyms.first, ['gym', 'id'])}');
  late String mode = _old['loading'] != null
      ? 'plates'
      : _old['scale'] != null
      ? 'selector'
      : 'none';
  // Plates.
  final tare = TextEditingController();
  String tareKind = 'bar';
  int sides = 2;
  String unit = 'kg';
  final plates = <_PlateRow>[];
  // Selector range.
  final start = TextEditingController();
  final step = TextEditingController();
  final count = TextEditingController();
  bool _keepTicks = false;
  String? problem;
  bool _filled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_filled) return;
    _filled = true;
    final f = Fmt.of(context);
    String shown(Object? v) => v == null ? '' : f.number(v, digits: 3);
    final loading = _old['loading'] as Map?;
    if (loading != null) {
      final first = (loading['components'] as List?)?.firstOrNull as Map?;
      tare.text = shown(
        at(first, ['mass', 'entered', 'value']) ?? at(first, ['mass', 'value']),
      );
      tareKind = '${first?['kind'] ?? 'bar'}' == 'handle' ? 'handle' : 'bar';
      sides = at(loading, ['channel', 'sides']) == 1 ? 1 : 2;
      for (final p in (loading['plates'] as List?) ?? const []) {
        final m = (p as Map)['mass'] as Map;
        final entered = (m['entered'] ?? m) as Map;
        unit = '${entered['unit']}';
        plates.add(_PlateRow(shown(entered['value']), '${p['count']}'));
      }
    } else {
      for (final (m, c) in [
        ('25', '2'),
        ('20', '2'),
        ('15', '2'),
        ('10', '2'),
        ('5', '2'),
        ('2.5', '2'),
        ('1.25', '2'),
      ]) {
        plates.add(_PlateRow(shown(m), c));
      }
      tare.text = shown('20');
    }
    final scale = _old['scale'] as Map?;
    if (scale != null) {
      unit = '${scale['unit']}';
      final range = scale['range'] as Map?;
      if (range == null) {
        _keepTicks = true;
      } else {
        start.text = shown(range['start']);
        step.text = shown(range['step']);
        count.text = '${range['count']}';
      }
    }
  }

  @override
  void dispose() {
    for (final c in [name, newEquipment, tare, start, step, count]) {
      c.dispose();
    }
    for (final p in plates) {
      p.dispose();
    }
    super.dispose();
  }

  Map<String, Object?> _q(String v) => {'value': v, 'unit': unit};

  Future<void> _save() async {
    final locale = Fmt.of(context).locale;
    String? dec(TextEditingController c) => parseDecimal(locale, c.text.trim());
    final profile = ProfileScope.of(context);
    var eqId = equipmentId;
    final creating = eqId == null || eqId == '_new';
    if (creating && newEquipment.text.trim().isEmpty) {
      setState(() => problem = 'Name the kind of equipment.');
      return;
    }
    if (creating) {
      eqId = freeId(
        newEquipment.text,
        widget.equipment.keys,
        fallback: 'equipment',
      );
    }
    final instance = <String, Object?>{
      'id':
          _old['id'] ??
          freeId(
            name.text.trim().isEmpty ? '${gym ?? ''} $eqId' : name.text,
            widget.takenIds,
            fallback: 'instance',
          ),
      'equipmentId': eqId,
      'gym': ?gym,
      if (name.text.trim().isNotEmpty) 'name': name.text.trim(),
      'notes': ?_old['notes'],
      'convention': ?_old['convention'],
    };
    if (mode == 'plates') {
      final t = dec(tare);
      if (t == null) {
        setState(() => problem = 'Enter the bar or handle mass (0 if none).');
        return;
      }
      final stock = <Map<String, Object?>>[];
      for (final p in plates) {
        if (p.mass.text.trim().isEmpty && p.count.text.trim().isEmpty) continue;
        final m = dec(p.mass);
        final n = int.tryParse(p.count.text.trim());
        if (m == null || n == null || n < 1) {
          setState(() => problem = 'Each plate needs a mass and a count.');
          return;
        }
        stock.add({'mass': _q(m), 'count': n});
      }
      if (stock.isEmpty) {
        setState(() => problem = 'Add at least one plate.');
        return;
      }
      final oldLoading = (_old['loading'] as Map?) ?? const {};
      final others = [
        ...((oldLoading['components'] as List?) ?? const []).skip(1),
      ];
      instance['loading'] = {
        'components': [
          {'id': tareKind, 'kind': tareKind, 'mass': _q(t)},
          ...others,
        ],
        'channel': {
          'id': at(oldLoading, ['channel', 'id']) ?? 'load',
          'sides': sides,
          'symmetry': 'required',
        },
        'plates': stock,
      };
    } else if (mode == 'selector') {
      if (_keepTicks) {
        instance['scale'] = _old['scale'];
      } else {
        final s = dec(start), st = dec(step);
        final n = int.tryParse(count.text.trim());
        if (s == null || st == null || n == null) {
          setState(() => problem = 'Enter the lowest setting, step and count.');
          return;
        }
        instance['scale'] = {
          'id': '${instance['id']}-settings',
          'unit': unit,
          'range': {'start': s, 'step': st, 'count': n},
        };
      }
    }
    try {
      if (creating) {
        await profile.write('equipment publish', {
          'equipment': {
            'id': eqId,
            'name': newEquipment.text.trim(),
            if (interchangeable) 'interchangeable': true,
          },
          'expectedRevision': 0,
        });
      }
      if (!mounted) return;
      await saveAndClose(
        context,
        widget.existing == null ? 'Equipment added' : 'Equipment updated',
        (p) => p.write('instance publish', {
          'instance': instance,
          'expectedRevision': widget.existing?['revision'] ?? 0,
        }),
      );
    } on BodyTmiException catch (e) {
      setState(() => problem = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return EntrySheet(
      title: editing ? 'Equipment' : 'New equipment',
      action: 'Save',
      onAction: _save,
      children: [
        DropdownButtonFormField<String>(
          initialValue: equipmentId ?? '_new',
          decoration: const InputDecoration(labelText: 'Kind'),
          items: [
            for (final e in widget.equipment.entries)
              DropdownMenuItem(
                value: e.key,
                child: Text('${at(e.value, ['equipment', 'name']) ?? e.key}'),
              ),
            if (!editing)
              const DropdownMenuItem(value: '_new', child: Text('New kind…')),
          ],
          onChanged: editing ? null : (v) => setState(() => equipmentId = v),
        ),
        if ((equipmentId ?? '_new') == '_new') ...[
          TextField(
            controller: newEquipment,
            decoration: const InputDecoration(
              labelText: 'Kind of equipment',
              hintText: 'e.g. Olympic barbell, Adjustable dumbbell',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Interchangeable'),
            subtitle: const Text(
              'Any one of these counts as the same for history and '
              'progression, e.g. standard plates or kettlebells.',
            ),
            value: interchangeable,
            onChanged: (v) => setState(() => interchangeable = v),
          ),
        ],
        TextField(
          controller: name,
          decoration: const InputDecoration(
            labelText: 'Name (optional)',
            hintText: 'e.g. Garage bar',
          ),
        ),
        DropdownButtonFormField<String?>(
          initialValue: gym,
          decoration: const InputDecoration(labelText: 'Where'),
          items: [
            for (final g in widget.gyms)
              DropdownMenuItem(
                value: '${at(g, ['gym', 'id'])}',
                child: Text(
                  '${at(g, ['gym', 'name']) ?? at(g, ['gym', 'id'])}',
                ),
              ),
            const DropdownMenuItem(value: null, child: Text('Not at a gym')),
          ],
          onChanged: (v) => setState(() => gym = v),
        ),
        const SizedBox(height: 10),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'plates', label: Text('Plates')),
            ButtonSegment(value: 'selector', label: Text('Settings')),
            ButtonSegment(value: 'none', label: Text('Neither')),
          ],
          selected: {mode},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => mode = s.single),
        ),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'kg', label: Text('kg')),
            ButtonSegment(value: 'lb', label: Text('lb')),
          ],
          selected: {unit},
          showSelectedIcon: false,
          onSelectionChanged: mode == 'none'
              ? null
              : (s) => setState(() => unit = s.single),
        ),
        if (mode == 'plates') ..._platesFields(),
        if (mode == 'selector') ..._selectorFields(),
        if (problem != null) ProblemText(problem!),
      ],
    );
  }

  List<Widget> _platesFields() => [
    Row(
      children: [
        DropdownButton<String>(
          value: tareKind,
          items: const [
            DropdownMenuItem(value: 'bar', child: Text('Bar')),
            DropdownMenuItem(value: 'handle', child: Text('Handle')),
          ],
          onChanged: (v) => setState(() => tareKind = v ?? 'bar'),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DecimalField(controller: tare, label: 'Mass', suffix: unit),
        ),
      ],
    ),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Loaded on two sides'),
      subtitle: const Text('Plates go on in matching pairs.'),
      value: sides == 2,
      onChanged: (v) => setState(() => sides = v ? 2 : 1),
    ),
    const Text('Plates (total count, both sides together)'),
    for (final (i, p) in plates.indexed)
      Row(
        children: [
          Expanded(
            child: DecimalField(
              controller: p.mass,
              label: 'Plate',
              suffix: unit,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: TextField(
              controller: p.count,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Count'),
            ),
          ),
          IconButton(
            tooltip: 'Remove plate',
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => plates.removeAt(i).dispose()),
          ),
        ],
      ),
    Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => setState(() => plates.add(_PlateRow())),
        icon: const Icon(Icons.add),
        label: const Text('Add plate'),
      ),
    ),
  ];

  List<Widget> _selectorFields() => _keepTicks
      ? [
          Muted(
            'This has ${(at(_old, ['scale', 'ticks']) as List?)?.length ?? 0} '
            'individually marked settings; they are kept as they are.',
          ),
        ]
      : [
          Row(
            children: [
              Expanded(
                child: DecimalField(
                  controller: start,
                  label: 'Lowest',
                  suffix: unit,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DecimalField(
                  controller: step,
                  label: 'Step',
                  suffix: unit,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: TextField(
                  controller: count,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Settings'),
                ),
              ),
            ],
          ),
          const Muted(
            'Evenly spaced settings, e.g. a dumbbell set from 2 kg in steps '
            'of 2 kg, or a pin-selected stack.',
          ),
        ];
}

/// One instance: details, the plate calculator, editing and the gym
/// preference.
final class InstanceScreen extends StatefulWidget {
  const InstanceScreen({super.key, required this.instanceId});
  final String instanceId;

  @override
  State<InstanceScreen> createState() => _InstanceScreenState();
}

final class _InstanceScreenState extends State<InstanceScreen> {
  final target = TextEditingController();
  Map<String, Object?>? plan;
  String? problem;

  @override
  void dispose() {
    target.dispose();
    super.dispose();
  }

  Future<(_GymData, Map<String, Object?>)> _load(ProfileClient p) async {
    final d = await GymsScreen._load(p);
    return (
      d,
      d.instances.firstWhere(
        (i) => at(i, ['instance', 'id']) == widget.instanceId,
      ),
    );
  }

  Future<void> _calculate(String unit) async {
    final v = parseDecimal(Fmt.of(context).locale, target.text.trim());
    if (v == null) {
      setState(() => problem = 'Enter a target load.');
      return;
    }
    try {
      final r = await ProfileScope.of(context)
          .call<Map<String, Object?>>('store plate-plan', {
            'instanceId': widget.instanceId,
            'target': {'value': v, 'unit': unit},
          });
      setState(() {
        plan = r['plan'] as Map<String, Object?>?;
        problem = null;
      });
    } on BodyTmiException catch (e) {
      setState(() => problem = e.message);
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => ProfileLoader<(_GymData, Map<String, Object?>)>(
    load: _load,
    builder: (context, data) {
      final (d, row) = data;
      final i = row['instance']! as Map<String, Object?>;
      final f = Fmt.of(context);
      final eq = d.equipment['${i['equipmentId']}']?['equipment'] as Map?;
      final gymRow = d.gyms
          .where((g) => at(g, ['gym', 'id']) == i['gym'])
          .firstOrNull;
      final siblings = d.instances.where(
        (x) =>
            at(x, ['instance', 'gym']) == i['gym'] &&
            at(x, ['instance', 'equipmentId']) == i['equipmentId'],
      );
      final preferred =
          at(gymRow, ['gym', 'preferred', '${i['equipmentId']}']) == i['id'];
      final unit =
          '${at(i, ['loading', 'plates', 0, 'mass', 'entered', 'unit']) ?? at(i, ['loading', 'plates', 0, 'mass', 'unit']) ?? 'kg'}';
      return Scaffold(
        appBar: AppBar(
          title: Text('${i['name'] ?? eq?['name'] ?? i['id']}'),
          actions: [
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => InstanceSheet(
                  existing: row,
                  gyms: d.gyms,
                  equipment: d.equipment,
                  takenIds: [
                    for (final x in d.instances) '${at(x, ['instance', 'id'])}',
                  ],
                ),
              ),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${eq?['name'] ?? i['equipmentId']}'
                    '${eq?['interchangeable'] == true ? ' (interchangeable)' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Muted(
                    gymRow == null
                        ? 'Not at a gym'
                        : 'At ${at(gymRow, ['gym', 'name'])}',
                  ),
                  Text(loadingSummary(f, i)),
                  Muted('Revision ${row['revision']}'),
                  if (gymRow != null && siblings.length > 1)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: preferred
                          ? const Pill('preferred here')
                          : TextButton(
                              onPressed: () => _prefer(gymRow, i),
                              child: const Text('Prefer this one here'),
                            ),
                    ),
                ],
              ),
            ),
            if (i['loading'] != null)
              SectionCard(
                title: 'Plate calculator',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DecimalField(
                            controller: target,
                            label: 'Target load',
                            suffix: unit,
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () => _calculate(unit),
                          child: const Text('Calculate'),
                        ),
                      ],
                    ),
                    if (problem != null) ProblemText(problem!),
                    if (plan != null) ..._planLines(f, plan!),
                  ],
                ),
              ),
          ],
        ),
      );
    },
  );

  List<Widget> _planLines(Fmt f, Map<String, Object?> plan) {
    final status = '${plan['status']}';
    final arrangements = [
      for (final a in (plan['arrangements'] as List?) ?? const [])
        a as Map<String, Object?>,
    ];
    return [
      const SizedBox(height: 8),
      Text(switch (status) {
        'exact' => 'Exactly ${_m(f, plan['target'])}:',
        'nearest' => '${_m(f, plan['target'])} is not possible; nearest:',
        'missing-inventory' =>
          'Not enough plates for ${_m(f, plan['target'])}; nearest lower:',
        'below-components' =>
          '${_m(f, plan['target'])} is below the ${_m(f, plan['tareMass'])} '
              'bar or handle:',
        _ => status,
      }),
      for (final a in arrangements)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (a['relation'] != 'exact')
                Text(
                  '${_m(f, a['totalMass'])}'
                  '${a['relation'] == 'nearest-lower'
                      ? ' (lower)'
                      : a['relation'] == 'nearest-higher'
                      ? ' (higher)'
                      : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ..._sideLines(f, (a['sides'] as List?) ?? const []),
            ],
          ),
        ),
    ];
  }

  static List<Widget> _sideLines(Fmt f, List sides) {
    if (sides.length == 1) {
      return [Text('Load: ${_plates(f, (sides.single as Map)['plates'])}')];
    }
    if (_sameSides(sides)) {
      return [Text('Each side: ${_plates(f, (sides.first as Map)['plates'])}')];
    }
    return [
      for (final s in sides)
        Text('Side ${(s as Map)['side']}: ${_plates(f, s['plates'])}'),
    ];
  }

  static bool _sameSides(List sides) =>
      sides.map((s) => '${(s as Map)['plates']}').toSet().length == 1;

  static String _plates(Fmt f, Object? plates) {
    final list = (plates as List?) ?? const [];
    if (list.isEmpty) return 'no plates';
    return [
      for (final p in list) '${(p as Map)['count']} × ${_m(f, p['mass'])}',
    ].join(', ');
  }

  Future<void> _prefer(
    Map<String, Object?> gymRow,
    Map<String, Object?> instance,
  ) async {
    final gym = Map<String, Object?>.of(gymRow['gym']! as Map<String, Object?>);
    gym['preferred'] = <String, Object?>{
      ...((gym['preferred'] as Map?) ?? const {}),
      '${instance['equipmentId']}': instance['id'],
    };
    try {
      await ProfileScope.of(context).write('gym publish', {
        'gym': gym,
        'expectedRevision': gymRow['revision'],
      });
    } on BodyTmiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

/// Adds, edits or removes one gym's setup note for an exercise ("rack pins
/// at 9"). A session started at the gym freezes the note for that
/// exercise's slots; later edits never change past sessions.
final class SetupNoteSheet extends StatefulWidget {
  const SetupNoteSheet({
    super.key,
    required this.gym,
    required this.exercises,
    this.exercise,
  });
  final Map<String, Object?> gym; // latest revision record
  final Map<String, String> exercises;
  final String? exercise;

  @override
  State<SetupNoteSheet> createState() => _SetupNoteSheetState();
}

final class _SetupNoteSheetState extends State<SetupNoteSheet> {
  Map<String, Object?> get _notes =>
      (at(widget.gym, ['gym', 'setupNotes']) as Map<String, Object?>?) ??
      const {};
  late String? exercise = widget.exercise;
  late final note = TextEditingController(
    text: '${_notes[widget.exercise] ?? ''}',
  );
  String? problem;

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  void _save({bool remove = false}) {
    if (exercise == null) {
      setState(() => problem = 'Choose the exercise.');
      return;
    }
    if (!remove && note.text.trim().isEmpty) {
      setState(() => problem = 'Write the note, or remove it.');
      return;
    }
    final notes = <String, Object?>{..._notes};
    if (widget.exercise != null && widget.exercise != exercise) {
      notes.remove(widget.exercise);
    }
    if (remove) {
      notes.remove(exercise);
    } else {
      notes[exercise!] = note.text.trim();
    }
    final gym = <String, Object?>{
      ...(widget.gym['gym']! as Map<String, Object?>),
    }..remove('setupNotes');
    if (notes.isNotEmpty) gym['setupNotes'] = notes;
    saveAndClose(
      context,
      remove ? 'Setup note removed' : 'Setup note saved',
      (p) => p.write('gym publish', {
        'gym': gym,
        'expectedRevision': widget.gym['revision'],
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final choices = {
      ...widget.exercises,
      ?exercise: ?widget.exercises[exercise] ?? exercise,
    };
    final sorted = choices.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return EntrySheet(
      title:
          'Setup note at ${at(widget.gym, ['gym', 'name']) ?? at(widget.gym, ['gym', 'id'])}',
      action: 'Save',
      onAction: _save,
      children: [
        if (sorted.isEmpty)
          const Muted('No exercises yet: publish a workout or catalog entry.')
        else
          DropdownButtonFormField<String>(
            initialValue: exercise,
            decoration: const InputDecoration(labelText: 'Exercise'),
            items: [
              for (final e in sorted)
                DropdownMenuItem(value: e.key, child: Text(e.value)),
            ],
            onChanged: (v) => setState(() => exercise = v),
          ),
        const SizedBox(height: 10),
        TextField(
          controller: note,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Note',
            hintText: 'e.g. Rack pins at 9, bench on the third mark',
            border: OutlineInputBorder(),
          ),
        ),
        const Muted(
          'Shown with that exercise when a workout starts at this gym.',
        ),
        if (widget.exercise != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => _save(remove: true),
              child: const Text('Remove note'),
            ),
          ),
        if (problem != null) ProblemText(problem!),
      ],
    );
  }
}
