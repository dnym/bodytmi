import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:material_ui/material_ui.dart';

import 'format.dart';
import 'profile.dart';
import 'widgets.dart';

/// The frozen equipment instance a set uses: its own performedOn, else the
/// session's binding for its slot.
final class InstanceRef {
  const InstanceRef(this.id, this.revision, this.snapshot);
  final String id;
  final int revision;
  final Map<String, Object?> snapshot;
}

InstanceRef? instanceOf(
  Map<String, Object?> session,
  Map<String, Object?> set,
) {
  final ref =
      set['performedOn'] ??
      at(session, ['loadInputs', '${set['slot']}', 'instance']);
  if (ref is! Map) return null;
  return InstanceRef(
    '${ref['instanceId']}',
    ref['revision']! as int,
    (ref['snapshot'] as Map<String, Object?>?) ?? const {},
  );
}

String _mass(Fmt f, Object? q) {
  final m = (q is Map ? q['entered'] ?? q : q) as Map?;
  return f.number(m?['value'], digits: 3);
}

/// `25 + 1.25 each side` for a recorded stack (counts are channel totals).
String plateText(Fmt f, Map arrangement, InstanceRef? instance) {
  final sides = at(instance?.snapshot, ['loading', 'channel', 'sides']) == 2
      ? 2
      : 1;
  final plates = (arrangement['plates'] as List?) ?? const [];
  if (plates.isEmpty) return 'bar only';
  final unit =
      at(plates.first, ['mass', 'entered', 'unit']) ??
      at(plates.first, ['mass', 'unit']);
  final parts = [
    for (final p in plates)
      for (var i = 0; i < ((p as Map)['count'] as int) ~/ sides; i++)
        _mass(f, p['mass']),
  ];
  return '${parts.join(' + ')} $unit${sides == 2 ? ' each side' : ''}';
}

/// A short loading hint from a `bodytmi-plate-plan/1` plan.
String? planHint(Fmt f, Object? plan) {
  if (plan is! Map) return null;
  String side(Map a) {
    final sides = (a['sides'] as List?) ?? const [];
    if (sides.isEmpty) return '';
    final plates = (sides.first as Map)['plates'] as List? ?? const [];
    final text = [
      for (final p in plates)
        for (var i = 0; i < ((p as Map)['count'] as int); i++)
          _mass(f, p['mass']),
    ];
    final unit =
        at(plan, ['target', 'entered', 'unit']) ?? at(plan, ['target', 'unit']);
    return text.isEmpty
        ? 'bar only'
        : '${text.join(' + ')} $unit${sides.length == 2 ? ' each side' : ''}';
  }

  final arrangements = [
    for (final a in (plan['arrangements'] as List?) ?? const []) a as Map,
  ];
  return switch (plan['status']) {
    'exact' when arrangements.isNotEmpty => 'Load ${side(arrangements.first)}',
    'nearest' =>
      'Not loadable exactly: ${arrangements.map((a) => f.quantity(a['totalMass'], digits: 3)).join(' or ')}',
    'missing-inventory' =>
      'Not enough plates; at most ${arrangements.map((a) => f.quantity(a['totalMass'], digits: 3)).join(', ')}',
    'below-components' => 'Below the bar or handle mass',
    _ => null,
  };
}

/// The stack chosen in [PlatesSheet]; json null clears it.
final class PlateArrangement {
  const PlateArrangement(this.json);
  final Map<String, Object?>? json;
}

/// Records which plates a completed set used on its instance: per-side
/// counts on a two-sided bar (pairs), totals on a one-sided one. Prefilled
/// from the recorded stack, else from the plate plan for the logged mass.
final class PlatesSheet extends StatefulWidget {
  const PlatesSheet({super.key, required this.set, required this.instance});
  final Map<String, Object?> set;
  final InstanceRef instance;

  @override
  State<PlatesSheet> createState() => _PlatesSheetState();
}

final class _PlatesSheetState extends State<PlatesSheet> {
  late final Map loading = widget.instance.snapshot['loading']! as Map;
  late final int sides = at(loading, ['channel', 'sides']) == 2 ? 2 : 1;
  late final List<Map> stock = [
    for (final p in (loading['plates'] as List?) ?? const []) p as Map,
  ];
  late final List<int> counts = List.filled(stock.length, 0); // per side
  bool _loaded = false;

  String _key(Object? q) => Decimal.parse('${(q as Map)['value']}').toString();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final recorded = widget.set['loadArrangement'] as Map?;
    if (recorded != null) {
      _fill((recorded['plates'] as List?) ?? const [], perSide: false);
      return;
    }
    final mass = at(widget.set, ['actuals', 'mass']);
    if (mass is! Map) return;
    final entered = (mass['entered'] ?? mass) as Map;
    ProfileScope.of(context)
        .call<Map<String, Object?>>('store plate-plan', {
          'instanceId': widget.instance.id,
          'revision': widget.instance.revision,
          'target': {'value': entered['value'], 'unit': entered['unit']},
        })
        .then((r) {
          final plan = r['plan'] as Map?;
          if (plan?['status'] != 'exact' || !mounted) return;
          final first = at(plan, ['arrangements', 0, 'sides', 0, 'plates']);
          setState(() => _fill((first as List?) ?? const [], perSide: true));
        }, onError: (_) {});
  }

  void _fill(List plates, {required bool perSide}) {
    for (final p in plates) {
      final i = stock.indexWhere(
        (s) => _key(s['mass']) == _key((p as Map)['mass']),
      );
      if (i >= 0) {
        final n = p['count'] as int;
        counts[i] = perSide ? n : n ~/ sides;
      }
    }
  }

  Decimal get _total {
    var total = Decimal.zero;
    for (final c in (loading['components'] as List?) ?? const []) {
      if ((c as Map)['include'] != false) {
        total += Decimal.parse('${at(c, ['mass', 'value'])}');
      }
    }
    for (var i = 0; i < stock.length; i++) {
      total +=
          Decimal.parse('${at(stock[i], ['mass', 'value'])}') *
          Decimal.parse('${counts[i] * sides}');
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final f = Fmt.of(context);
    final unit = '${at(stock.firstOrNull, ['mass', 'unit']) ?? 'kg'}';
    final logged = at(widget.set, ['actuals', 'mass', 'value']);
    final differs = logged != null && Decimal.parse('$logged') != _total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Plates on ${widget.instance.snapshot['name'] ?? widget.instance.id}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            Muted(sides == 2 ? 'Plates on each side.' : 'Plates loaded.'),
            for (final (i, p) in stock.indexed)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      f.quantity(
                        (p['mass'] as Map)['entered'] ?? p['mass'],
                        digits: 3,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fewer ${_mass(f, p['mass'])}',
                    onPressed: counts[i] == 0
                        ? null
                        : () => setState(() => counts[i]--),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  SizedBox(
                    width: 28,
                    child: Text('${counts[i]}', textAlign: TextAlign.center),
                  ),
                  IconButton(
                    tooltip: 'More ${_mass(f, p['mass'])}',
                    onPressed: (counts[i] + 1) * sides > (p['count'] as int)
                        ? null
                        : () => setState(() => counts[i]++),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
            const SizedBox(height: 6),
            Text(
              'Total ${f.number('$_total', digits: 3)} $unit',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (differs)
              Muted(
                'The logged weight is ${f.number(logged, digits: 3)} $unit; '
                'the stack is recorded as loaded.',
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (widget.set['loadArrangement'] != null)
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(context, const PlateArrangement(null)),
                    child: const Text('Clear'),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    PlateArrangement(<String, Object?>{
                      'instanceId': widget.instance.id,
                      'channel': at(loading, ['channel', 'id']),
                      'plates': <Object?>[
                        for (final (i, p) in stock.indexed)
                          if (counts[i] > 0)
                            <String, Object?>{
                              'mass': <String, Object?>{
                                ...((p['mass'] as Map)['entered'] ?? p['mass'])
                                    as Map<String, Object?>,
                              },
                              'count': counts[i] * sides,
                            },
                      ],
                    }),
                  ),
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Another instance chosen for a set; instanceId null returns to the
/// session's binding.
final class OtherChoice {
  const OtherChoice(this.instanceId, {this.remaining = false});
  final String? instanceId;
  final bool remaining;
}

/// Picks another published instance of the slot's equipment for a set
/// (and optionally the rest of that exercise), e.g. when a bar is taken.
final class OtherEquipmentSheet extends StatefulWidget {
  const OtherEquipmentSheet({
    super.key,
    required this.equipmentId,
    required this.current,
    required this.performedOn,
  });
  final String equipmentId;
  final String? current;
  final String? performedOn;

  @override
  State<OtherEquipmentSheet> createState() => _OtherEquipmentSheetState();
}

final class _OtherEquipmentSheetState extends State<OtherEquipmentSheet> {
  List<Map<String, Object?>>? options;
  Map<String, String> gyms = const {};
  bool remaining = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (options != null) return;
    final profile = ProfileScope.of(context);
    () async {
      final latest = <String, Map<String, Object?>>{};
      for (final r in await profile.call<List<Object?>>('instance list')) {
        final i = (r! as Map)['instance']! as Map<String, Object?>;
        if (i['equipmentId'] == widget.equipmentId) latest['${i['id']}'] = i;
      }
      final names = <String, String>{
        for (final r in await profile.call<List<Object?>>('gym list'))
          '${at(r, ['gym', 'id'])}':
              '${at(r, ['gym', 'name']) ?? at(r, ['gym', 'id'])}',
      };
      if (!mounted) return;
      setState(() {
        options = latest.values.where((i) => i['id'] != widget.current).toList()
          ..sort(
            (a, b) =>
                '${a['name'] ?? a['id']}'.compareTo('${b['name'] ?? b['id']}'),
          );
        gyms = names;
      });
    }();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Other equipment',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const Muted(
          'Record that this set is done on other equipment of the same '
          'kind. Targets keep their unit; the nearest settings on it count '
          'as following them.',
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Also the remaining sets of this exercise'),
          value: remaining,
          onChanged: (v) => setState(() => remaining = v),
        ),
        if (options == null)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (options!.isEmpty)
          const EmptyNote('No other equipment of this kind is published.')
        else
          for (final i in options!)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${i['name'] ?? i['id']}'),
              subtitle: Text(
                i['gym'] == null
                    ? 'Not at a gym'
                    : gyms['${i['gym']}'] ?? '${i['gym']}',
              ),
              onTap: () => Navigator.pop(
                context,
                OtherChoice('${i['id']}', remaining: remaining),
              ),
            ),
        if (widget.performedOn != null)
          TextButton(
            onPressed: () => Navigator.pop(context, const OtherChoice(null)),
            child: const Text('Back to the session equipment'),
          ),
      ],
    ),
  );
}
