import 'dart:convert';

import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:material_ui/material_ui.dart';

import 'format.dart';
import 'gyms.dart' show freeId;
import 'profile.dart';
import 'quick_entry.dart' show ProblemText;
import 'session.dart' show parseDecimal;
import 'widgets.dart';

/// Opens "Start a program" (from the Train tab).
Future<void> openProgramStart(BuildContext context, {DateTime? clock}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ProgramStartScreen(clock: clock)),
    );

/// The shipped starter catalog (exercises, equipment and blueprints such as
/// GZCLP); tests point it at the repository copy.
Future<Map<String, Object?>> Function() starterCatalog = () async =>
    jsonDecode(await rootBundle.loadString('assets/starter-catalog.json'))
        as Map<String, Object?>;

Map<String, Map<String, Object?>> _latest(List<Object?> rows, String key) {
  final out = <String, Map<String, Object?>>{};
  for (final r in rows) {
    final row = r! as Map<String, Object?>;
    final id = '${(row[key]! as Map)['id']}';
    if ((out[id]?['revision'] as int? ?? 0) < (row['revision']! as int)) {
      out[id] = row;
    }
  }
  return out;
}

final class _StartData {
  _StartData(this.programs, this.blueprints, this.gyms, this.runs);
  final List<Map<String, Object?>> programs; // latest program revisions
  final List<Map<String, Object?>> blueprints; // latest, with a programme
  final List<Map<String, Object?>> gyms;
  final Set<String> runs; // run ids in use
}

/// Starts a run of a published program, or fills in a blueprint (e.g.
/// GZCLP) into a new program first. Nothing is chosen for you.
final class ProgramStartScreen extends StatelessWidget {
  const ProgramStartScreen({super.key, this.clock});
  final DateTime? clock;

  static Future<_StartData> _load(ProfileClient p) async {
    final programs = _latest(
      await p.call<List<Object?>>('program list'),
      'definition',
    );
    final blueprints = _latest(
      await p.call<List<Object?>>('blueprint list'),
      'blueprint',
    );
    return _StartData(
      programs.values.toList()..sort(
        (a, b) => '${at(a, ['definition', 'name'])}'.compareTo(
          '${at(b, ['definition', 'name'])}',
        ),
      ),
      blueprints.values
          .where((b) => at(b, ['blueprint', 'program']) != null)
          .toList(),
      _latest(await p.call<List<Object?>>('gym list'), 'gym').values.toList(),
      {
        for (final r in await p.call<List<Object?>>('run list'))
          '${(r! as Map)['id']}',
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Start a program')),
    body: ProfileLoader<_StartData>(
      load: _load,
      builder: (context, d) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          SectionCard(
            title: 'Your programs',
            child: d.programs.isEmpty
                ? const EmptyNote(
                    'No programs yet. Fill in a blueprint below, or publish '
                    'one with the CLI.',
                  )
                : Column(
                    children: [
                      for (final p in d.programs)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${at(p, ['definition', 'name']) ?? at(p, ['definition', 'id'])}',
                          ),
                          subtitle: Text('Revision ${p['revision']}'),
                          trailing: FilledButton.tonal(
                            onPressed: () => showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              builder: (_) => StartRunSheet(
                                programId: '${at(p, ['definition', 'id'])}',
                                revision: p['revision']! as int,
                                name: '${at(p, ['definition', 'name']) ?? ''}',
                                gyms: d.gyms,
                                takenRuns: d.runs,
                                clock: clock,
                              ),
                            ),
                            child: const Text('Start'),
                          ),
                        ),
                    ],
                  ),
          ),
          SectionCard(
            title: 'Blueprints',
            child: d.blueprints.isEmpty
                ? _CatalogImport()
                : Column(
                    children: [
                      for (final b in d.blueprints)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('${at(b, ['blueprint', 'name'])}'),
                          subtitle: Text(
                            '${at(b, ['blueprint', 'source']) ?? ''}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => BlueprintScreen(
                                blueprint: b,
                                gyms: d.gyms,
                                takenRuns: d.runs,
                                clock: clock,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    ),
  );
}

final class _CatalogImport extends StatefulWidget {
  @override
  State<_CatalogImport> createState() => _CatalogImportState();
}

final class _CatalogImportState extends State<_CatalogImport> {
  bool busy = false;
  String? problem;

  Future<void> _import() async {
    setState(() {
      busy = true;
      problem = null;
    });
    try {
      await ProfileScope.of(context).write('catalog apply', {
        'document': await starterCatalog(),
        'confirm': true,
      });
    } on BodyTmiException catch (e) {
      if (mounted) setState(() => problem = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Muted(
        'The starter catalog adds well-established exercises and gym '
        'equipment, and blueprints such as GZCLP, with their sources. '
        'Nothing in your profile is changed or removed.',
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.tonal(
          onPressed: busy ? null : _import,
          child: const Text('Add the starter catalog'),
        ),
      ),
      if (problem != null) ProblemText(problem!),
    ],
  );
}

/// Starts a run: repeat or not, and an optional default gym.
final class StartRunSheet extends StatefulWidget {
  const StartRunSheet({
    super.key,
    required this.programId,
    required this.revision,
    required this.name,
    required this.gyms,
    required this.takenRuns,
    this.clock,
    this.popScreen = false,
  });
  final String programId;
  final int revision;
  final String name;
  final List<Map<String, Object?>> gyms;
  final Set<String> takenRuns;
  final DateTime? clock;

  /// Also closes the screen under the sheet once started.
  final bool popScreen;

  @override
  State<StartRunSheet> createState() => _StartRunSheetState();
}

final class _StartRunSheetState extends State<StartRunSheet> {
  bool loop = true;
  String? gym;
  String? problem;

  Future<void> _start() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ProfileScope.of(context).write('run create', {
        'id': freeId(widget.programId, widget.takenRuns, fallback: 'run'),
        'programId': widget.programId,
        'revision': widget.revision,
        'startedAt': isoInstant(widget.clock ?? DateTime.now()),
        'loop': loop,
        'gym': ?gym,
      });
      navigator.pop();
      if (widget.popScreen) navigator.pop();
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text('${widget.name} started')));
    } on BodyTmiException catch (e) {
      setState(() => problem = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Start ${widget.name}',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Start over when it ends'),
          value: loop,
          onChanged: (v) => setState(() => loop = v),
        ),
        if (widget.gyms.isNotEmpty)
          DropdownButtonFormField<String?>(
            initialValue: gym,
            decoration: const InputDecoration(labelText: 'Usual gym'),
            items: [
              const DropdownMenuItem(value: null, child: Text('None')),
              for (final g in widget.gyms)
                DropdownMenuItem(
                  value: '${at(g, ['gym', 'id'])}',
                  child: Text(
                    '${at(g, ['gym', 'name']) ?? at(g, ['gym', 'id'])}',
                  ),
                ),
            ],
            onChanged: (v) => setState(() => gym = v),
          ),
        if (problem != null) ProblemText(problem!),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(onPressed: _start, child: const Text('Start')),
        ),
      ],
    ),
  );
}

/// Fills in a blueprint's open choices, publishes it as your own program
/// (workouts, progression presets and the programme), then starts it.
final class BlueprintScreen extends StatefulWidget {
  const BlueprintScreen({
    super.key,
    required this.blueprint,
    required this.gyms,
    required this.takenRuns,
    this.clock,
  });
  final Map<String, Object?> blueprint; // latest revision record
  final List<Map<String, Object?>> gyms;
  final Set<String> takenRuns;
  final DateTime? clock;

  @override
  State<BlueprintScreen> createState() => _BlueprintScreenState();
}

final class _BlueprintScreenState extends State<BlueprintScreen> {
  Map<String, Object?> get _bp =>
      widget.blueprint['blueprint']! as Map<String, Object?>;
  List<Map<String, Object?>> get _choices => [
    for (final c in (_bp['choices'] as List?) ?? const [])
      c as Map<String, Object?>,
  ];

  final text = <String, TextEditingController>{};
  final units = <String, String>{};
  final picked = <String, String>{};
  Map<String, String> catalogNames = const {};
  Set<String> takenNames = const {};
  String? problem;
  bool busy = false;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final f = Fmt.of(context);
    for (final c in _choices) {
      final id = '${c['id']}';
      final d = c['default'];
      if (c['kind'] == 'quantity' ||
          c['kind'] == 'number' ||
          c['kind'] == 'integer') {
        text[id] = TextEditingController(
          text: d is Map
              ? f.number(d['value'], digits: 3)
              : d == null
              ? ''
              : '$d',
        );
        units[id] = d is Map ? '${d['unit']}' : _units(c).first;
      } else if (d != null) {
        picked[id] = '$d';
      }
    }
    final profile = ProfileScope.of(context);
    () async {
      final names = <String, String>{};
      for (final (command, key) in [
        ('equipment list', 'equipment'),
        ('exercise list', 'exercise'),
        ('implementation list', 'implementation'),
      ]) {
        for (final r in await profile.call<List<Object?>>(command)) {
          final e = (r! as Map)[key] as Map;
          names['${e['id']}'] = '${e['name'] ?? e['id']}';
        }
      }
      final instances = {
        for (final r in await profile.call<List<Object?>>(
          'blueprint instances',
        ))
          '${(r! as Map)['id']}',
        for (final r in await profile.call<List<Object?>>('program list'))
          '${at(r, ['definition', 'id'])}',
      };
      if (mounted) {
        setState(() {
          catalogNames = names;
          takenNames = instances;
        });
      }
    }();
  }

  @override
  void dispose() {
    for (final c in text.values) {
      c.dispose();
    }
    super.dispose();
  }

  static List<String> _units(Map<String, Object?> c) =>
      switch (c['dimension']) {
        'mass' => const ['kg', 'lb'],
        'length' => const ['cm', 'm'],
        'duration' => const ['s', 'min'],
        'count' => const ['rep'],
        _ => [
          if (at(c, ['default', 'unit']) case final String u) u else 'kg',
        ],
      };

  bool get _unsupported => _choices.any((c) => c['kind'] == 'plates');

  Future<void> _create() async {
    final locale = Fmt.of(context).locale;
    final choices = <String, Object?>{};
    for (final c in _choices) {
      final id = '${c['id']}';
      final label = '${c['label'] ?? id}';
      switch (c['kind']) {
        case 'quantity' || 'number' || 'integer':
          final t = text[id]!.text.trim();
          if (t.isEmpty) {
            if (c['default'] == null) {
              setState(() => problem = 'Enter $label.');
              return;
            }
            continue;
          }
          if (c['kind'] == 'integer') {
            final n = int.tryParse(t);
            if (n == null) {
              setState(() => problem = '$label is a whole number.');
              return;
            }
            choices[id] = n;
            continue;
          }
          final v = parseDecimal(locale, t);
          if (v == null) {
            setState(() => problem = '$label is not a number.');
            return;
          }
          choices[id] = c['kind'] == 'number'
              ? v
              : <String, Object?>{'value': v, 'unit': units[id]};
        default:
          if (picked[id] case final v?) {
            choices[id] = v;
          } else if (c['default'] == null) {
            setState(() => problem = 'Choose $label.');
            return;
          }
      }
    }
    final name = freeId('${_bp['id']}', takenNames, fallback: 'program');
    setState(() {
      busy = true;
      problem = null;
    });
    try {
      final receipt = await ProfileScope.of(context)
          .write<Map<String, Object?>>('blueprint instantiate', {
            'blueprintId': _bp['id'],
            'revision': widget.blueprint['revision'],
            'name': name,
            'choices': choices,
            'expectedInstance': 0,
          });
      if (!mounted) return;
      setState(() => busy = false);
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => StartRunSheet(
          programId: name,
          revision: receipt['programRevision']! as int,
          name: '${_bp['name']}',
          gyms: widget.gyms,
          takenRuns: widget.takenRuns,
          clock: widget.clock,
          popScreen: true,
        ),
      );
    } on BodyTmiException catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          problem = e.message;
        });
      }
    }
  }

  Widget _choice(Map<String, Object?> c) {
    final id = '${c['id']}';
    final label = '${c['label'] ?? id}';
    final notes = c['notes'] as String?;
    final Widget input = switch (c['kind']) {
      'quantity' || 'number' || 'integer' => Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                key: ValueKey('choice-$id'),
                controller: text[id]!,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  hintText: c['default'] == null ? 'Required' : null,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ),
          if (c['kind'] == 'quantity' && _units(c).length > 1) ...[
            const SizedBox(width: 8),
            SegmentedButton<String>(
              segments: [
                for (final u in _units(c))
                  ButtonSegment(value: u, label: Text(u)),
              ],
              selected: {units[id]!},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => units[id] = s.single),
            ),
          ] else if (c['kind'] == 'quantity')
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(units[id]!),
            ),
        ],
      ),
      'plates' => Muted('$label: set this in the CLI.'),
      _ => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          Wrap(
            spacing: 6,
            children: [
              for (final o in _options(c))
                ChoiceChip(
                  label: Text(catalogNames[o] ?? o),
                  selected: picked[id] == o,
                  onSelected: (_) => setState(() => picked[id] = o),
                ),
            ],
          ),
        ],
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (c['kind'] case 'quantity' || 'number' || 'integer')
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(label),
            ),
          input,
          if (notes != null) Muted(notes),
        ],
      ),
    );
  }

  List<String> _options(Map<String, Object?> c) {
    final options = [for (final o in (c['options'] as List?) ?? const []) '$o'];
    if (options.isNotEmpty) return options;
    if (c['kind'] == 'gym') {
      return [
        for (final g in widget.gyms) '${at(g, ['gym', 'id'])}',
      ];
    }
    return catalogNames.keys.toList()..sort();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('${_bp['name']}')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_bp['notes'] != null) Text('${_bp['notes']}'),
              if (_bp['source'] != null) ...[
                const SizedBox(height: 6),
                Muted('Source: ${_bp['source']}'),
              ],
            ],
          ),
        ),
        SectionCard(
          title: 'Your choices',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Muted(
                'Starting weights and steps are yours to choose; defaults '
                'come from the blueprint.',
              ),
              for (final c in _choices) _choice(c),
            ],
          ),
        ),
        if (problem != null) ProblemText(problem!),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: busy || _unsupported ? null : _create,
          child: const Text('Create the program'),
        ),
        const SizedBox(height: 4),
        const Muted(
          'Creates its workouts and progression rules in your profile, then '
          'asks how to start it.',
        ),
      ],
    ),
  );
}
