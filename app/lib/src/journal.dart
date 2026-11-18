import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:material_ui/material_ui.dart';

import 'format.dart';
import 'profile.dart';
import 'quick_entry.dart';
import 'widgets.dart';

/// Opens the Journal screen (from More).
Future<void> openJournal(BuildContext context, {DateTime? clock}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => JournalScreen(clock: clock)),
    );

/// The built-in journal measures (plain 0–10 self-ratings, not validated
/// questionnaires) and illness periods.
const journalMeasures = ['mood', 'energy-level', 'symptom', 'pain', 'illness'];

const _labels = {
  'mood': 'Mood',
  'energy-level': 'Energy',
  'symptom': 'Symptom',
  'pain': 'Pain',
  'illness': 'Illness',
};

const _anchors = {
  'mood': ('very bad', 'very good'),
  'energy-level': ('exhausted', 'full of energy'),
  'symptom': ('none', 'worst imaginable'),
  'pain': ('no pain', 'worst imaginable'),
};

/// Typed text as an attribute value: lowercase letters, digits and hyphens.
String journalSlug(String text) =>
    foldDiacritics(text.trim().toLowerCase())
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');

String _words(Object? slug) => '${slug ?? ''}'.replaceAll('-', ' ');

final class JournalScreen extends StatelessWidget {
  const JournalScreen({super.key, this.clock});
  final DateTime? clock;

  DateTime get _now => clock ?? DateTime.now();

  Future<List<Map<String, Object?>>> _load(ProfileClient p) async {
    final today = DateTime(_now.year, _now.month, _now.day);
    final from = isoDate(today.subtract(const Duration(days: 13)));
    final until = isoDate(today.add(const Duration(days: 1)));
    final all = <Map<String, Object?>>[];
    for (final measure in journalMeasures) {
      final list = await p.call<List<Object?>>('observation list', {
        'measure': measure,
        'from': from,
        'until': until,
      });
      for (final o in list.cast<Map<String, Object?>>()) {
        if (o['deleted'] == true) continue;
        all.add(o['observation']! as Map<String, Object?>);
      }
    }
    all.sort((a, b) => '${b['observedAt']}'.compareTo('${a['observedAt']}'));
    return all;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Journal')),
    body: ProfileLoader<List<Map<String, Object?>>>(
      load: _load,
      builder: (context, entries) {
        final f = Fmt.of(context);
        final today = DateTime(_now.year, _now.month, _now.day);
        List<double> daily(String measure) {
          final out = <double>[];
          for (var i = 13; i >= 0; i--) {
            final date = isoDate(today.subtract(Duration(days: i)));
            final values = [
              for (final e in entries)
                if (e['measure'] == measure &&
                    '${e['observedAt']}'.startsWith(date))
                  (e['value']! as int).toDouble(),
            ];
            if (values.isNotEmpty) {
              out.add(values.reduce((a, b) => a + b) / values.length);
            }
          }
          return out;
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            _RightNow(now: _now),
            SectionCard(
              title: 'Last 14 days',
              trailing: const Muted('daily mean, 0–10'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final measure in ['mood', 'energy-level'])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          SizedBox(width: 64, child: Text(_labels[measure]!)),
                          Expanded(
                            child: daily(measure).length < 2
                                ? const Muted('Log on two days to see a line.')
                                : LineChart(values: daily(measure), height: 36),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            SectionCard(
              title: 'Add',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final measure in ['symptom', 'pain', 'illness'])
                    OutlinedButton.icon(
                      onPressed: () => _edit(context, measure, null),
                      icon: const Icon(Icons.add),
                      label: Text(_labels[measure]!),
                    ),
                ],
              ),
            ),
            SectionCard(
              title: 'Entries',
              child: entries.isEmpty
                  ? const EmptyNote('Nothing in the journal in two weeks.')
                  : Column(
                      children: [
                        for (final e in entries)
                          InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => _edit(context, '${e['measure']}', e),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(describe(e)),
                                        Muted(
                                          '${f.shortDate('${e['observedAt']}'.substring(0, 10))}'
                                          ' · ${f.clock(e['observedAt'])}',
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (e['value'] is int)
                                    Text(
                                      '${e['value']}',
                                      style: const TextStyle(
                                        fontSize: 18,
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

  Future<void> _edit(
    BuildContext context,
    String measure,
    Map<String, Object?>? existing,
  ) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) =>
        JournalSheet(measure: measure, now: _now, existing: existing),
  );

  /// One line describing an entry.
  static String describe(Map<String, Object?> e) {
    final a = (e['attributes'] as Map?) ?? const {};
    return switch (e['measure']) {
      'pain' => [
        'Pain',
        _words(a['site']),
        if (a['side'] != null) _words(a['side']),
        if (a['impact'] != null) _words(a['impact']),
      ].join(' · '),
      'symptom' => 'Symptom · ${_words(a['name'])}',
      'illness' =>
        'Illness · ${_words(a['name'])} until '
            '${'${(e['value'] as Map?)?['end']}'.substring(0, 10)}',
      final m => _labels[m] ?? '$m',
    };
  }
}

/// Mood and energy as two sliders, recorded together.
final class _RightNow extends StatefulWidget {
  const _RightNow({required this.now});
  final DateTime now;

  @override
  State<_RightNow> createState() => _RightNowState();
}

final class _RightNowState extends State<_RightNow> {
  final values = <String, int?>{'mood': null, 'energy-level': null};
  bool busy = false;

  Future<void> _save() async {
    final profile = ProfileScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final at = DateTime.now().isBefore(widget.now)
        ? widget.now
        : DateTime.now();
    setState(() => busy = true);
    try {
      for (final MapEntry(:key, :value) in values.entries) {
        if (value == null) continue;
        await profile.write('observation record', {
          'observation': {
            'id': 'journal-$key-${stamp(at)}',
            'measure': key,
            'observedAt': isoInstant(at),
            'value': value,
          },
        });
      }
      setState(() => values.updateAll((_, _) => null));
      messenger.showSnackBar(
        const SnackBar(content: Text('Saved to the journal')),
      );
    } on BodyTmiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SectionCard(
    title: 'Right now',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final measure in ['mood', 'energy-level'])
          RatingField(
            label: _labels[measure]!,
            anchors: _anchors[measure]!,
            value: values[measure],
            onChanged: (v) => setState(() => values[measure] = v),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: busy || values.values.every((v) => v == null)
                ? null
                : _save,
            child: const Text('Save'),
          ),
        ),
      ],
    ),
  );
}

/// A 0–10 rating as eleven tappable values; unset until one is tapped
/// (never a default, so nothing is recorded by accident).
final class RatingField extends StatelessWidget {
  const RatingField({
    super.key,
    required this.label,
    required this.anchors,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final (String, String) anchors;
  final int? value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value == null ? 'not set' : '$value',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Row(
        children: [
          for (var v = 0; v <= 10; v++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Semantics(
                  button: true,
                  selected: value == v,
                  label: '$label $v',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => onChanged(v),
                    child: Container(
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: value == v
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.surface,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: Text(
                        '$v',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: value == v
                              ? Theme.of(context).colorScheme.onPrimary
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 4),
      Row(
        children: [
          Expanded(child: Muted('0 ${anchors.$1}')),
          Muted('${anchors.$2} 10'),
        ],
      ),
    ],
  );
}

/// Adds or edits one journal observation; existing ones can be deleted.
final class JournalSheet extends StatefulWidget {
  const JournalSheet({
    super.key,
    required this.measure,
    required this.now,
    this.existing,
  });
  final String measure;
  final DateTime now;
  final Map<String, Object?>? existing;

  @override
  State<JournalSheet> createState() => _JournalSheetState();
}

final class _JournalSheetState extends State<JournalSheet> {
  late DateTime at;
  late DateTime end;
  int? rating;
  final name = TextEditingController();
  String? side;
  String? impact;
  String? problem;

  Map<String, Object?> get _attributes =>
      (widget.existing?['attributes'] as Map<String, Object?>?) ?? const {};

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    at = e == null
        ? widget.now
        : DateTime.parse('${e['observedAt']}').toLocal();
    end = e?['value'] is Map
        ? DateTime.parse('${(e!['value']! as Map)['end']}').toLocal()
        : widget.now;
    if (e?['value'] is int) rating = e!['value']! as int;
    name.text = _words(
      widget.measure == 'pain' ? _attributes['site'] : _attributes['name'],
    );
    side = _attributes['side'] as String?;
    impact = _attributes['impact'] as String?;
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  bool get _rated => widget.measure != 'illness';
  bool get _named =>
      widget.measure != 'mood' && widget.measure != 'energy-level';

  Future<void> _pickDate(bool isEnd) async {
    final current = isEnd ? end : at;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: widget.now.add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() {
      final next = DateTime(
        picked.year,
        picked.month,
        picked.day,
        current.hour,
        current.minute,
      );
      isEnd ? end = next : at = next;
    });
  }

  void _save() {
    if (_rated && rating == null) {
      setState(() => problem = 'Choose a rating.');
      return;
    }
    final slug = journalSlug(name.text);
    if (_named && (slug.isEmpty || slug.length > 100)) {
      setState(
        () => problem = widget.measure == 'pain'
            ? 'Name the site, e.g. lower back.'
            : 'Give it a name, e.g. headache.',
      );
      return;
    }
    if (widget.measure == 'illness' && !end.isAfter(at)) {
      setState(() => problem = 'The end is after the start.');
      return;
    }
    final observation = <String, Object?>{
      'id':
          widget.existing?['id'] ??
          'journal-${widget.measure}-${stamp(DateTime.now())}',
      'measure': widget.measure,
      'observedAt': isoInstant(at),
      'value': widget.measure == 'illness' ? {'end': isoInstant(end)} : rating,
      if (_named)
        'attributes': {
          if (widget.measure == 'pain') ...{
            'site': slug,
            'side': ?side,
            'impact': ?impact,
          } else
            'name': slug,
        },
    };
    final e = widget.existing;
    saveAndClose(
      context,
      e == null ? 'Saved to the journal' : 'Entry updated',
      (p) => e == null
          ? p.write('observation record', {'observation': observation})
          : p.write('observation update', {
              'observation': observation,
              'expectedVersion': e['contentVersion'],
            }),
    );
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this entry?'),
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
      'Entry deleted',
      (p) => p.write('observation delete', {
        'id': widget.existing!['id'],
        'expectedVersion': widget.existing!['contentVersion'],
        'confirm': true,
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final f = Fmt.of(context);
    Widget chips(
      List<String> options,
      String? selected,
      ValueChanged<String?> pick,
    ) => Wrap(
      spacing: 8,
      children: [
        for (final o in options)
          ChoiceChip(
            label: Text(_words(o)),
            selected: selected == o,
            onSelected: (on) => pick(on ? o : null),
          ),
      ],
    );

    return EntrySheet(
      title: _labels[widget.measure] ?? widget.measure,
      action: 'Save',
      onAction: _save,
      children: [
        if (_named)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextField(
              controller: name,
              decoration: InputDecoration(
                labelText: widget.measure == 'pain' ? 'Where' : 'What',
                hintText: widget.measure == 'pain'
                    ? 'lower back, left knee…'
                    : widget.measure == 'illness'
                    ? 'cold, flu…'
                    : 'headache, nausea…',
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        if (_rated)
          RatingField(
            label: widget.measure == 'pain' ? 'How bad' : 'Rating',
            anchors: _anchors[widget.measure] ?? ('low', 'high'),
            value: rating,
            onChanged: (v) => setState(() => rating = v),
          ),
        if (widget.measure == 'pain') ...[
          const SizedBox(height: 8),
          const Text('Side'),
          chips(
            ['left', 'right', 'both'],
            side,
            (v) => setState(() => side = v),
          ),
          const SizedBox(height: 8),
          const Text('How much it limits you'),
          chips(
            ['none', 'minor', 'limits-activity', 'prevents-activity'],
            impact,
            (v) => setState(() => impact = v),
          ),
        ],
        if (widget.measure == 'illness') ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Started'),
            trailing: Text(f.longDate(at)),
            onTap: () => _pickDate(false),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Ended'),
            subtitle: const Muted('Still ill? Use today and extend it later.'),
            trailing: Text(f.longDate(end)),
            onTap: () => _pickDate(true),
          ),
        ] else
          TimeRow(
            label: 'Time',
            value: at,
            onChanged: (t) => setState(() => at = t),
          ),
        if (widget.existing != null)
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
