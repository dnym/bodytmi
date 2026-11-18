import 'dart:async';

import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_locale/bodytmi_locale.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'format.dart';
import 'gym_start.dart';
import 'profile.dart';
import 'theme.dart';
import 'widgets.dart';

/// Starts the next workout of [runId] and returns the new session id.
Future<String> startRunSession(
  ProfileClient profile,
  String runId, {
  DateTime? now,
  GymChoice? gym,
}) async {
  var run = await profile.call<Map<String, Object?>>('run show', {
    'runId': runId,
  });
  if (run['currentSessionId'] case final String id) return id;
  if (gym != null && gym.makeDefault) {
    run = await profile.write<Map<String, Object?>>('run gym', {
      'runId': runId,
      'expectedVersion': run['contentVersion'],
      'gym': gym.gym,
    });
  }
  final at = now ?? DateTime.now();
  final id =
      'session-${at.year}${_two(at.month)}${_two(at.day)}-'
      '${_two(at.hour)}${_two(at.minute)}${_two(at.second)}';
  final session = await profile.write<Map<String, Object?>>('run start', {
    'runId': runId,
    'expectedVersion': run['contentVersion'],
    'id': id,
    'startedAt': isoInstant(at),
    ...?gym?.fields,
  });
  return session['id']! as String;
}

String _two(int v) => v.toString().padLeft(2, '0');

/// Logs one training session: sets per exercise in plan order, one tap for
/// "as planned", a sheet to enter or correct actuals, skip, a rest cue and
/// finish. Every change is one stored command with the session version.
final class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

final class _SessionScreenState extends State<SessionScreen> {
  Map<String, Object?>? session;
  String? gymLabel;
  Object? error;
  bool busy = false;
  final rest = RestCue();
  Timer? _tick;

  ProfileClient get profile => ProfileScope.of(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (session == null && error == null) _reload();
    _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (rest.takeAlert()) HapticFeedback.heavyImpact();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final s = await profile.call<Map<String, Object?>>('store show', {
        'id': widget.sessionId,
      });
      final label = await gymName(profile, s['gym']);
      if (mounted) {
        setState(() {
          session = s;
          gymLabel = label;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  /// Runs one change; the response is the updated session.
  Future<void> _change(
    String command,
    Map<String, Object?> fields, {
    bool restAfter = false,
    String? slot,
  }) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final updated = await profile.write<Map<String, Object?>>(command, {
        'id': widget.sessionId,
        'expectedVersion': session!['contentVersion'],
        ...fields,
      });
      setState(() => session = updated);
      if (restAfter && slot != null) {
        final seconds = restSeconds(definition, slot);
        if (seconds != null && _planned.isNotEmpty) rest.start(seconds);
      }
    } on BodyTmiException catch (e) {
      _show(e.message);
      await _reload();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _show(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  Map<String, Object?> get definition =>
      at(session, ['revision', 'definition'])! as Map<String, Object?>;

  List<Map<String, Object?>> get _sets => [
    for (final s in (session!['sets'] as List?) ?? const [])
      s as Map<String, Object?>,
  ];

  List<Map<String, Object?>> get _planned =>
      _sets.where((s) => s['status'] == 'planned').toList();

  bool get _finished => session!['status'] == 'finalized';

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Text(
            error is BodyTmiException
                ? (error! as BodyTmiException).message
                : '$error',
          ),
        ),
      );
    }
    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final f = Fmt.of(context);
    final started = DateTime.tryParse('${session!['startedAt']}');
    final elapsed = started == null ? null : DateTime.now().difference(started);
    final current = _planned.firstOrNull;
    final slots = <String, List<Map<String, Object?>>>{};
    for (final s in _sets) {
      slots.putIfAbsent(s['slot']! as String, () => []).add(s);
    }
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${definition['name'] ?? definition['id']}'),
            Text(
              [
                _finished
                    ? 'Finished'
                    : elapsed == null
                    ? 'In progress'
                    : 'In progress · ${_clock(elapsed)} elapsed',
                if (gymLabel != null) gymLabel,
              ].join(' · '),
              style: TextStyle(
                fontSize: 13,
                color: AppColors.of(context).muted,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          for (final MapEntry(key: slotId, value: sets) in slots.entries)
            SectionCard(
              title: _slotTitle(slotId),
              trailing: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 170),
                child: Text(
                  _slotTag(slotId),
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.of(context).muted,
                  ),
                ),
              ),
              child: Column(
                children: [
                  for (final s in sets)
                    _SetRow(
                      set: s,
                      label: _setLabel(s),
                      current: identical(s, current),
                      fmt: f,
                      onDone: busy || s['status'] != 'planned'
                          ? null
                          : () => _change(
                              'store complete',
                              {'setId': s['id'], 'acceptSuggested': true},
                              restAfter: true,
                              slot: slotId,
                            ),
                      onTap: busy ? null : () => _openSet(s, slotId),
                    ),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: _finished
          ? null
          : _BottomBar(
              rest: rest,
              remaining: _planned.length,
              busy: busy,
              onFinish: _finish,
            ),
    );
  }

  Map<String, Object?>? _slot(String id) => [
    for (final s in (definition['slots'] as List?) ?? const [])
      s as Map<String, Object?>,
  ].where((s) => s['id'] == id).firstOrNull;

  String _slotTitle(String id) {
    final exercise = '${_slot(id)?['exercise'] ?? id}'.replaceAll('-', ' ');
    return exercise.isEmpty
        ? exercise
        : '${exercise[0].toUpperCase()}${exercise.substring(1)}';
  }

  String _slotTag(String id) {
    final slot = _slot(id);
    final instance = at(session, ['loadInputs', id, 'instance', 'snapshot']);
    return [
      slot?['implementation'],
      instance is Map
          ? '${instance['name'] ?? instance['id']}'
          : session?['gym'] != null && slot?['equipment'] != null
          ? 'no equipment recorded'
          : slot?['equipment'],
    ].whereType<String>().map((s) => s.replaceAll('-', ' ')).join(' · ');
  }

  String _setLabel(Map<String, Object?> s) {
    final ordinal = (s['ordinal'] as int? ?? 0) + 1;
    return switch (s['role']) {
      'warmup' => 'W$ordinal',
      'backoff' => 'B$ordinal',
      'drop' => 'D$ordinal',
      _ => '$ordinal',
    };
  }

  Future<void> _openSet(Map<String, Object?> set, String slotId) async {
    final result = await showModalBottomSheet<_SetResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _SetSheet(
        set: set,
        label: '${_slotTitle(slotId)} · set ${_setLabel(set)}',
        slot: _slot(slotId),
      ),
    );
    if (result == null) return;
    switch (result) {
      case _Skip():
        await _change('store skip', {'setId': set['id'], 'confirm': true});
      case _Actuals(:final actuals):
        await _change(
          'store complete',
          {'setId': set['id'], 'actuals': actuals},
          restAfter: set['status'] == 'planned',
          slot: slotId,
        );
    }
  }

  Future<void> _finish() async {
    final remaining = _planned.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finish workout?'),
        content: Text(
          remaining == 0
              ? 'Every set is logged.'
              : '$remaining planned ${remaining == 1 ? 'set is' : 'sets are'} '
                    'not logged and will be recorded as skipped.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep going'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Finish'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (remaining > 0) {
      await _change('store skip-remaining', {'confirm': true});
      if (_planned.isNotEmpty) return;
    }
    await _change('store finish', {'finishedAt': isoInstant(DateTime.now())});
    rest.stop();
    if (mounted && _finished) Navigator.pop(context);
  }

  static String _clock(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return m >= 60 ? '${m ~/ 60}:${_two(m % 60)}:${_two(s)}' : '$m:${_two(s)}';
  }
}

/// The authored rest after a set of [slotId]: the nearest enclosing
/// repeat's `restBetweenSeconds`, or a rest node right after its effort.
/// A display cue only: it records nothing.
int? restSeconds(Map<String, Object?> definition, String slotId) {
  int? found;
  bool mentions(Object? node) {
    if (node is! Map) return false;
    if (node['type'] == 'effort') return node['slot'] == slotId;
    return [
      node['child'],
      ...((node['children'] as List?) ?? const []),
    ].any(mentions);
  }

  void walk(Object? node) {
    if (node is! Map || found != null) return;
    if (node['type'] == 'repeat' &&
        node['restBetweenSeconds'] is int &&
        mentions(node['child'])) {
      found = node['restBetweenSeconds'] as int;
      return;
    }
    final children = (node['children'] as List?) ?? const [];
    for (var i = 0; i < children.length; i++) {
      final child = children[i];
      if (child is Map &&
          child['type'] == 'effort' &&
          child['slot'] == slotId &&
          i + 1 < children.length &&
          (children[i + 1] as Map)['type'] == 'rest' &&
          children[i + 1]['durationSeconds'] is int) {
        found = children[i + 1]['durationSeconds'] as int;
        return;
      }
      walk(child);
    }
    walk(node['child']);
  }

  walk(definition['plan']);
  return found;
}

/// A foreground rest countdown on a monotonic stopwatch. It is a cue, not a
/// record: nothing is stored and it ends with the screen.
final class RestCue {
  final _watch = Stopwatch();
  int _seconds = 0;
  bool _alerted = false;

  bool get active => _seconds > 0;
  int get total => _seconds;
  Duration get remaining {
    final left = Duration(seconds: _seconds) - _watch.elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  bool get done => _seconds > 0 && remaining == Duration.zero;

  void start(int seconds) {
    _seconds = seconds;
    _alerted = false;
    _watch
      ..reset()
      ..start();
  }

  void add(int seconds) => _seconds += seconds;

  void stop() {
    _watch
      ..stop()
      ..reset();
    _seconds = 0;
  }

  /// True once, when the countdown first reaches zero.
  bool takeAlert() {
    if (!done || _alerted) return false;
    _alerted = true;
    return true;
  }
}

final class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.rest,
    required this.remaining,
    required this.busy,
    required this.onFinish,
  });
  final RestCue rest;
  final int remaining;
  final bool busy;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final left = rest.remaining;
    return Material(
      color: scheme.surfaceContainer,
      elevation: 8,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              if (rest.active) ...[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        rest.done
                            ? 'Rest done'
                            : 'Rest ${left.inMinutes}:${_two(left.inSeconds % 60)}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Muted('of ${rest.total ~/ 60}:${_two(rest.total % 60)}'),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => rest.add(30),
                  child: const Text('+30 s'),
                ),
                IconButton(
                  tooltip: 'Stop rest',
                  onPressed: rest.stop,
                  icon: const Icon(Icons.close),
                ),
              ] else
                Expanded(
                  child: Muted(
                    remaining == 0
                        ? 'All sets logged'
                        : '$remaining ${remaining == 1 ? 'set' : 'sets'} to go',
                  ),
                ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: busy ? null : onFinish,
                child: const Text('Finish'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _SetRow extends StatelessWidget {
  const _SetRow({
    required this.set,
    required this.label,
    required this.current,
    required this.fmt,
    required this.onDone,
    required this.onTap,
  });
  final Map<String, Object?> set;
  final String label;
  final bool current;
  final Fmt fmt;
  final VoidCallback? onDone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final status = set['status'];
    final style = TextStyle(
      fontWeight: current ? FontWeight.w700 : FontWeight.normal,
    );
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: current
            ? BoxDecoration(
                color: c.accentSoft,
                borderRadius: BorderRadius.circular(10),
              )
            : null,
        child: Row(
          children: [
            SizedBox(width: 36, child: Text(label, style: style)),
            Expanded(
              child: Text(
                metricsText(fmt, set['suggested']),
                style: style.copyWith(color: c.muted),
              ),
            ),
            Expanded(
              child: Text(
                switch (status) {
                  'completed' => metricsText(fmt, set['actuals']),
                  'skipped' => 'skipped',
                  _ => '—',
                },
                style: style.copyWith(
                  color: status == 'skipped' ? c.muted : null,
                ),
              ),
            ),
            SizedBox(
              width: 48,
              height: 40,
              child: status == 'completed'
                  ? Icon(Icons.check, color: scheme.primary)
                  : status == 'planned'
                  ? IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Done as planned',
                      onPressed: onDone,
                      icon: Icon(
                        Icons.check_circle_outline,
                        color: current ? scheme.primary : c.muted,
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// `72.5 kg × 3`, or each metric in entered units.
String metricsText(Fmt f, Object? metrics) {
  if (metrics is! Map || metrics.isEmpty) return '—';
  Object? entered(Object? q) => q is Map ? q['entered'] ?? q : q;
  final mass = entered(metrics['mass']);
  final reps = entered(metrics['reps']);
  final rest = [
    for (final e in metrics.entries)
      if (e.key != 'mass' && e.key != 'reps')
        f.quantity(entered(e.value), digits: 2),
  ];
  return [
    if (mass != null && reps != null)
      '${f.quantity(mass, digits: 3)} × ${f.number((reps as Map)['value'])}'
    else ...[
      if (mass != null) f.quantity(mass, digits: 3),
      if (reps != null) '${f.number((reps as Map)['value'])} reps',
    ],
    ...rest,
  ].join(' · ');
}

sealed class _SetResult {}

final class _Skip extends _SetResult {}

final class _Actuals extends _SetResult {
  _Actuals(this.actuals);
  final Map<String, Object?> actuals;
}

/// Enter or correct a set's actuals, prefilled from the logged result or
/// the suggestion in their entered units.
final class _SetSheet extends StatefulWidget {
  const _SetSheet({required this.set, required this.label, this.slot});
  final Map<String, Object?> set;
  final String label;
  final Map<String, Object?>? slot;

  @override
  State<_SetSheet> createState() => _SetSheetState();
}

final class _SetSheetState extends State<_SetSheet> {
  late final Map<String, ({TextEditingController text, String unit})> fields;
  String? problem;

  @override
  void initState() {
    super.initState();
    final source = <String, Object?>{
      ...?(widget.slot?['targets'] as Map<String, Object?>?),
      ...?(widget.set['suggested'] as Map<String, Object?>?),
      ...?(widget.set['actuals'] as Map<String, Object?>?),
    };
    fields = {
      for (final e in source.entries)
        e.key: (
          text: TextEditingController(),
          unit: '${(_entered(e.value) as Map?)?['unit'] ?? ''}',
        ),
    };
  }

  bool _filled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_filled) return;
    _filled = true;
    final f = Fmt.of(context);
    final prefill = <String, Object?>{
      ...?(widget.set['suggested'] as Map<String, Object?>?),
      ...?(widget.set['actuals'] as Map<String, Object?>?),
    };
    for (final e in fields.entries) {
      final q = _entered(prefill[e.key]);
      if (q is Map && q['value'] != null) {
        e.value.text.text =
            formatNumber(f.locale, '${q['value']}', grouping: false)['text']!
                as String;
      }
    }
  }

  static Object? _entered(Object? q) => q is Map ? q['entered'] ?? q : q;

  @override
  void dispose() {
    for (final f in fields.values) {
      f.text.dispose();
    }
    super.dispose();
  }

  void _save() {
    final locale = Fmt.of(context).locale;
    final actuals = <String, Object?>{};
    for (final e in fields.entries) {
      final text = e.value.text.text.trim();
      if (text.isEmpty) {
        setState(
          () => problem =
              'Enter ${metricLabel(e.key).toLowerCase()}, or skip the set.',
        );
        return;
      }
      final value = parseDecimal(locale, text);
      if (value == null) {
        setState(() => problem = '${metricLabel(e.key)} is not a number.');
        return;
      }
      actuals[e.key] = {'value': value, 'unit': e.value.unit};
    }
    Navigator.pop(context, _Actuals(actuals));
  }

  @override
  Widget build(BuildContext context) {
    final planned = widget.set['status'] == 'planned';
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
          Text(
            widget.label,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Muted(
            planned
                ? 'Enter what you did.'
                : 'Correct the logged result. Nothing else changes.',
          ),
          const SizedBox(height: 12),
          if (fields.isEmpty) const Muted('This set has no numeric metrics.'),
          for (final MapEntry(key: metric, value: field) in fields.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: field.text,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: metricLabel(metric),
                  suffixText: field.unit,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          if (problem != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                problem!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Row(
            children: [
              if (planned)
                TextButton(
                  onPressed: () => Navigator.pop(context, _Skip()),
                  child: const Text('Skip set'),
                ),
              const Spacer(),
              FilledButton(
                onPressed: fields.isEmpty ? null : _save,
                child: Text(planned ? 'Log set' : 'Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Parses typed decimal text in the locale's format, also accepting the
/// other common decimal mark. Returns a canonical decimal string or null.
String? parseDecimal(PresentationLocale locale, String text) {
  for (final candidate in {
    text,
    text.replaceAll(',', '.'),
    text.replaceAll('.', ','),
  }) {
    try {
      return parseNumber(locale, candidate)['value']! as String;
    } on BodyTmiException {
      continue;
    } on FormatException {
      continue;
    }
  }
  return null;
}

/// A readable label for a metric id; custom metrics keep their id.
String metricLabel(String metric) => switch (metric) {
  'mass' => 'Weight',
  'reps' => 'Reps',
  'duration' => 'Duration',
  'distance' => 'Distance',
  _ => '${metric[0].toUpperCase()}${metric.substring(1).replaceAll('-', ' ')}',
};
