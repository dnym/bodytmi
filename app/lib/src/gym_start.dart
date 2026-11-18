import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:material_ui/material_ui.dart';

import 'format.dart';
import 'profile.dart';
import 'quick_entry.dart' show ProblemText;
import 'widgets.dart';

/// Where a workout is done and which equipment each exercise uses, as
/// `run start` takes it. `gym` null starts without a gym.
final class GymChoice {
  const GymChoice({
    required this.gym,
    this.loadBindings = const {},
    this.unboundSlots = const [],
    this.makeDefault = false,
  });
  final String? gym;
  final Map<String, String> loadBindings;
  final List<String> unboundSlots;
  final bool makeDefault;

  Map<String, Object?> get fields => {
    'gym': gym,
    if (gym != null && loadBindings.isNotEmpty)
      'loadBindings': <String, Object?>{...loadBindings},
    if (gym != null && unboundSlots.isNotEmpty)
      'unboundSlots': <Object?>[...unboundSlots],
  };
}

/// Asks where the workout of [templateId]/[revision] is done. Returns null
/// when cancelled.
Future<GymChoice?> chooseGym(
  BuildContext context, {
  required String templateId,
  required int revision,
  required String? runGym,
  required Map<String, Object?> workout,
}) => showModalBottomSheet<GymChoice>(
  context: context,
  isScrollControlled: true,
  builder: (_) => GymStartSheet(
    templateId: templateId,
    revision: revision,
    runGym: runGym,
    workout: workout,
  ),
);

final class GymStartSheet extends StatefulWidget {
  const GymStartSheet({
    super.key,
    required this.templateId,
    required this.revision,
    required this.runGym,
    required this.workout,
  });
  final String templateId;
  final int revision;
  final String? runGym;
  final Map<String, Object?> workout;

  @override
  State<GymStartSheet> createState() => _GymStartSheetState();
}

final class _GymStartSheetState extends State<GymStartSheet> {
  List<Map<String, Object?>> gyms = const [];
  Map<String, String> names = const {}; // instance id → name
  late String? gym = widget.runGym;
  final bindings = <String, String>{};
  final unbound = <String>{};
  bool makeDefault = false;
  Map<String, Object?>? check;
  String? problem;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final profile = ProfileScope.of(context);
    () async {
      final latest = <String, Map<String, Object?>>{};
      for (final r in await profile.call<List<Object?>>('gym list')) {
        final g = (r! as Map)['gym']! as Map<String, Object?>;
        latest['${g['id']}'] = g;
      }
      final instances = <String, String>{};
      for (final r in await profile.call<List<Object?>>('instance list')) {
        final i = (r! as Map)['instance']! as Map;
        instances['${i['id']}'] = '${i['name'] ?? i['id']}';
      }
      if (!mounted) return;
      setState(() {
        gyms = latest.values.toList()
          ..sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
        names = instances;
        if (gym != null && !latest.containsKey(gym)) gym = null;
      });
      await _check();
    }();
  }

  Future<void> _check() async {
    if (gym == null) {
      setState(() => check = null);
      return;
    }
    try {
      final c = await ProfileScope.of(context)
          .call<Map<String, Object?>>('store gym-check', {
            'templateId': widget.templateId,
            'revision': widget.revision,
            'gym': gym,
            if (bindings.isNotEmpty)
              'loadBindings': <String, Object?>{...bindings},
            if (unbound.isNotEmpty) 'unboundSlots': <Object?>[...unbound],
          });
      if (mounted) {
        setState(() {
          check = c;
          problem = null;
        });
      }
    } on BodyTmiException catch (e) {
      if (mounted) setState(() => problem = e.message);
    }
  }

  String _exercise(String slotId) {
    final slot = [
      for (final s in (widget.workout['slots'] as List?) ?? const []) s as Map,
    ].where((s) => s['id'] == slotId).firstOrNull;
    final e = '${slot?['exercise'] ?? slotId}'.replaceAll('-', ' ');
    return e.isEmpty ? e : '${e[0].toUpperCase()}${e.substring(1)}';
  }

  bool get _ready => gym == null || check?['ready'] == true;

  @override
  Widget build(BuildContext context) {
    final slots = [
      for (final s in (check?['slots'] as List?) ?? const [])
        s as Map<String, Object?>,
    ];
    return Padding(
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
            const Text(
              'Where are you training?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final g in gyms)
                  ChoiceChip(
                    label: Text('${g['name'] ?? g['id']}'),
                    selected: gym == g['id'],
                    onSelected: (_) {
                      setState(() {
                        gym = '${g['id']}';
                        bindings.clear();
                        unbound.clear();
                        check = null;
                      });
                      _check();
                    },
                  ),
                ChoiceChip(
                  label: const Text('No gym'),
                  selected: gym == null,
                  onSelected: (_) => setState(() {
                    gym = null;
                    check = null;
                  }),
                ),
              ],
            ),
            if (gym == null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Muted(
                  'Without a gym no equipment is recorded; history and '
                  'progression treat the session as before.',
                ),
              ),
            for (final s in slots)
              if (s['status'] != 'none') _slotRow(s),
            if (gym != null && gym != widget.runGym)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Use this gym by default for this program'),
                value: makeDefault,
                onChanged: (v) => setState(() => makeDefault = v),
              ),
            if (problem != null) ProblemText(problem!),
            if (!_ready && check != null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Muted(
                  'Choose the equipment marked above, or train without it.',
                ),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _ready
                    ? () => Navigator.pop(
                        context,
                        GymChoice(
                          gym: gym,
                          loadBindings: {...bindings},
                          unboundSlots: [...unbound],
                          makeDefault: makeDefault,
                        ),
                      )
                    : null,
                child: const Text('Start workout'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slotRow(Map<String, Object?> s) {
    final slotId = '${s['slotId']}';
    final status = '${s['status']}';
    final title = _exercise(slotId);
    String name(Object? id) => names['$id'] ?? '$id';
    final Widget detail = switch (status) {
      'bound' || 'explicit' || 'preferred' => Muted(
        '${name(s['instanceId'])}'
        '${status == 'preferred' ? ' (preferred)' : ''}',
      ),
      'ambiguous' => Wrap(
        spacing: 6,
        children: [
          for (final c in (s['candidates'] as List?) ?? const [])
            ChoiceChip(
              label: Text(name(c)),
              selected: bindings[slotId] == c,
              onSelected: (_) {
                setState(() => bindings[slotId] = '$c');
                _check();
              },
            ),
        ],
      ),
      'missing' => Row(
        children: [
          const Expanded(child: Muted('None at this gym.')),
          TextButton(
            onPressed: () {
              setState(() => unbound.add(slotId));
              _check();
            },
            child: const Text('Train without it'),
          ),
        ],
      ),
      'unbound' => Row(
        children: [
          const Expanded(child: Muted('Without equipment')),
          TextButton(
            onPressed: () {
              setState(() => unbound.remove(slotId));
              _check();
            },
            child: const Text('Undo'),
          ),
        ],
      ),
      _ => Muted(status),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (status == 'ambiguous' && bindings[slotId] == null)
                const Pill('choose', warn: true),
              if (status == 'missing') const Pill('missing', warn: true),
            ],
          ),
          detail,
        ],
      ),
    );
  }
}

/// The gym's name for a session header, or null.
Future<String?> gymName(ProfileClient profile, Object? gymId) async {
  if (gymId == null) return null;
  try {
    final g = await profile.call<Map<String, Object?>>('gym show', {
      'gymId': gymId,
    });
    return '${at(g, ['gym', 'name']) ?? gymId}';
  } on BodyTmiException {
    return '$gymId';
  }
}
