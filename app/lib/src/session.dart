import 'dart:async';

import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_locale/bodytmi_locale.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'format.dart';
import 'gym_start.dart';
import 'progression_review.dart';
import 'set_clock.dart';
import 'set_equipment.dart';
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

final class _SessionScreenState extends State<SessionScreen>
    with WidgetsBindingObserver {
  Map<String, Object?>? session;

  /// The guided traversal of this open workout (`execution show`).
  Map<String, Object?>? execution;
  SetClock? clock;
  String? gymLabel;
  Object? error;
  bool busy = false;
  Timer? _tick;
  int _requests = 0;

  /// Captured once: dispose must still reach the profile to pause.
  late ProfileClient profile;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    profile = ProfileScope.of(context);
    if (session == null && error == null) _reload();
    _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    clock?.pause();
    clock?.dispose();
    super.dispose();
  }

  /// A timed set pauses when the app is not shown; a rest keeps going, so
  /// the phone can be put away between sets.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused) &&
        clock != null &&
        clock!.plan['restOnly'] != true) {
      clock!.pause();
    }
  }

  Future<void> _reload() async {
    try {
      final s = await profile.call<Map<String, Object?>>('store show', {
        'id': widget.sessionId,
      });
      final label = await gymName(profile, s['gym']);
      Map<String, Object?>? e;
      if (s['status'] != 'finalized') e = await _execution(s);
      if (mounted) {
        setState(() {
          session = s;
          execution = e;
          gymLabel = label;
        });
        await _settle();
      }
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  /// This session's traversal, started on first open.
  Future<Map<String, Object?>?> _execution(Map<String, Object?> s) async {
    for (final e in await profile.call<List<Object?>>('execution list')) {
      final row = e! as Map;
      if (row['sessionId'] == s['id']) {
        return profile.call<Map<String, Object?>>('execution show', {
          'id': row['id'],
        });
      }
    }
    try {
      return await profile.write<Map<String, Object?>>('execution start', {
        'id': 'execution-${s['id']}',
        'sessionId': s['id'],
        'at': isoInstant(DateTime.now()),
      });
    } on BodyTmiException {
      return null; // e.g. a plan the traversal does not support
    }
  }

  Map<String, Object?>? get _current =>
      execution?['current'] as Map<String, Object?>?;

  /// The effort the traversal is on, or null during a rest.
  String? get _currentEffort =>
      _current?['kind'] == 'effort' ? '${_current!['id']}' : null;

  /// One traversal step; the response is the execution view.
  Future<void> _exec(String action, Map<String, Object?> fields) async {
    final e = execution;
    if (e == null) return;
    final next = await profile.write<Map<String, Object?>>(
      'execution $action',
      {
        'id': e['id'],
        'expectedVersion': e['version'],
        'expectedSessionVersion': session!['contentVersion'],
        'requestId':
            'app-${DateTime.now().microsecondsSinceEpoch}-${_requests++}',
        'at': isoInstant(DateTime.now()),
        ...fields,
      },
    );
    final s = await profile.call<Map<String, Object?>>('store show', {
      'id': widget.sessionId,
    });
    if (!mounted) return;
    setState(() {
      execution = (next['execution'] ?? next) as Map<String, Object?>;
      session = s;
    });
  }

  /// Acknowledges what needs no input (sets logged ahead, finished rests)
  /// and starts a prepared rest, so the traversal follows the log.
  Future<void> _settle() async {
    for (var i = 0; i < 50 && mounted; i++) {
      final cur = _current;
      final timer = execution?['timer'] as Map<String, Object?>?;
      if (cur == null) break;
      if (cur['kind'] == 'effort' && at(cur, ['set', 'status']) != 'planned') {
        await _exec('advance', const {});
        continue;
      }
      if (cur['kind'] == 'rest' && timer?['status'] == 'completed') {
        await _exec('advance', const {});
        continue;
      }
      _attach(timer);
      if (cur['kind'] == 'rest' && clock != null && !clock!.running) {
        await clock!.start();
      }
      break;
    }
    if (_current?['kind'] != 'rest' &&
        (execution?['timer'] as Map?)?['status'] != 'running' &&
        clock?.plan['restOnly'] == true) {
      _attach(null);
    }
  }

  void _attach(Map<String, Object?>? timer) {
    if (timer == null || timer['status'] == 'completed') {
      if (timer == null && clock != null && clock!.running) return;
      clock?.dispose();
      clock = null;
      return;
    }
    if (clock?.id == timer['id']) return;
    clock?.dispose();
    clock = SetClock(profile, timer)
      ..onStopped = (c) async {
        HapticFeedback.heavyImpact();
        if (!mounted) return;
        if (c['status'] == 'completed') {
          await _exec('advance', const {});
          await _settle();
        } else if (c['status'] == 'awaitingConfirmation') {
          setState(() {});
          await _review();
        }
      }
      ..addListener(() {
        if (mounted) setState(() {});
      });
  }

  Future<void> _skipRest() async {
    await clock?.pause();
    await _guard(() => _exec('skip', {'confirm': true}));
    await _settle();
  }

  Future<void> _continueRest() async {
    await clock?.pause();
    await _guard(() => _exec('advance', const {}));
    await _settle();
  }

  /// Starts the clock of the current timed set.
  Future<void> _startTimer() async {
    await _guard(() async {
      // `execution time` answers with the prepared clock itself.
      await profile.write('execution time', {
        'id': execution!['id'],
        'expectedVersion': execution!['version'],
        'at': isoInstant(DateTime.now()),
      });
      final e = await profile.call<Map<String, Object?>>('execution show', {
        'id': execution!['id'],
      });
      if (mounted) setState(() => execution = e);
    });
    _attach(execution?['timer'] as Map<String, Object?>?);
    await clock?.start();
  }

  /// Review after a timed set: as planned, or entered (the measured time
  /// is recorded by the clock either way).
  Future<void> _review() async {
    final c = clock;
    final cur = _current;
    if (c == null || cur == null) return;
    final asPlanned = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Time's up"),
        content: const Text(
          'The measured time is recorded. Log the rest of the set as '
          'planned, or enter what you did?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Enter result'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('As planned'),
          ),
        ],
      ),
    );
    if (!mounted || asPlanned == null) return;
    Map<String, Object?>? actuals;
    if (!asPlanned) {
      final slotId = '${at(cur, ['set', 'slot'])}';
      final result = await showModalBottomSheet<_SetResult>(
        context: context,
        isScrollControlled: true,
        builder: (context) => _SetSheet(
          set: {...(cur['set']! as Map<String, Object?>), 'status': 'review'},
          label: '${_slotTitle(slotId)} · review',
          slot: _slot(slotId),
          omit: {'${c.clock['metric']}'},
        ),
      );
      if (result is! _Actuals) return;
      actuals = result.actuals;
    }
    await _guard(
      () => _exec('confirm', {
        'timerId': c.id,
        'timerVersion': c.clock['version'],
        if (actuals == null) 'acceptSuggested': true else 'actuals': actuals,
      }),
    );
    await _settle();
  }

  Future<void> _guard(Future<void> Function() step) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await step();
    } on BodyTmiException catch (e) {
      _show(e.message);
      await _reload();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// A planned set with a duration suggestion can be timed.
  static bool _timed(Map<String, Object?>? set) {
    for (final q in ((set?['suggested'] as Map?) ?? const {}).values) {
      final unit = at(q, ['entered', 'unit']) ?? at(q, ['unit']);
      if (const {'ms', 's', 'min', 'h'}.contains(unit)) return true;
    }
    return false;
  }

  /// Runs one change; the response is the updated session.
  Future<void> _change(String command, Map<String, Object?> fields) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final updated = await profile.write<Map<String, Object?>>(command, {
        'id': widget.sessionId,
        'expectedVersion': session!['contentVersion'],
        ...fields,
      });
      setState(() => session = updated);
      if (execution != null) {
        execution = await profile.call<Map<String, Object?>>('execution show', {
          'id': execution!['id'],
        });
        await _settle();
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
    final current = _currentEffort == null
        ? _planned.firstOrNull
        : _sets.where((s) => s['id'] == _currentEffort).firstOrNull;
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
          if (_finished && _pinnedSlots.isNotEmpty)
            ProgressionReview(
              sessionId: widget.sessionId,
              slots: _pinnedSlots,
              titleOf: _slotTitle,
            ),
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
                  if (at(session, ['gymSetupNotes', slotId])
                      case final String note)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.sticky_note_2_outlined,
                            size: 18,
                            color: AppColors.of(context).muted,
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Muted(note)),
                        ],
                      ),
                    ),
                  for (final s in sets)
                    _SetRow(
                      set: s,
                      label: _setLabel(s),
                      current: identical(s, current),
                      fmt: f,
                      onDone: busy || s['status'] != 'planned'
                          ? null
                          : () => _logSet(s, const {'acceptSuggested': true}),
                      onTap: busy ? null : () => _openSet(s, slotId),
                      note: _setNote(f, s, current: identical(s, current)),
                    ),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: _finished
          ? null
          : _BottomBar(status: _status(), busy: busy, onFinish: _finish),
    );
  }

  /// Slots whose workout names a progression preset.
  List<Map<String, Object?>> get _pinnedSlots => [
    for (final s in (definition['slots'] as List?) ?? const [])
      if ((s as Map)['progression'] != null) s as Map<String, Object?>,
  ];

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
    final instance = instanceOf(session!, set);
    final result = await showModalBottomSheet<_SetResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _SetSheet(
        set: set,
        label: '${_slotTitle(slotId)} · set ${_setLabel(set)}',
        slot: _slot(slotId),
        plates:
            set['status'] == 'completed' &&
            instance?.snapshot['loading'] != null,
        otherEquipment:
            set['status'] == 'planned' && _slot(slotId)?['equipment'] != null,
        missingPlates:
            set['status'] == 'planned' && instance?.snapshot['loading'] != null,
      ),
    );
    if (result == null || !mounted) return;
    switch (result) {
      case _Plates():
        final arrangement = await showModalBottomSheet<PlateArrangement>(
          context: context,
          isScrollControlled: true,
          builder: (_) => PlatesSheet(set: set, instance: instance!),
        );
        if (arrangement == null) return;
        await _change('store arrange', {
          'setId': set['id'],
          'arrangement': arrangement.json,
          if (arrangement.json == null) 'confirm': true,
        });
      case _Other():
        final choice = await showModalBottomSheet<OtherChoice>(
          context: context,
          isScrollControlled: true,
          builder: (_) => OtherEquipmentSheet(
            equipmentId: '${_slot(slotId)!['equipment']}',
            current: instance?.id,
            performedOn: at(set, ['performedOn', 'instanceId']) as String?,
          ),
        );
        if (choice == null) return;
        await _performOn(set, choice);
      case _Missing():
        final missing = await showModalBottomSheet<MissingChoice>(
          context: context,
          isScrollControlled: true,
          builder: (_) => MissingPlatesSheet(
            instance: instance!,
            current: set['unavailablePlates'],
          ),
        );
        if (missing == null) return;
        final binding = at(session, [
          'loadInputs',
          slotId,
          'instance',
          'instanceId',
        ]);
        await _performOn(
          set,
          missing.unavailable.isEmpty && instance!.id == binding
              ? const OtherChoice(null)
              : OtherChoice(
                  instance!.id,
                  remaining: missing.remaining,
                  unavailable: missing.unavailable,
                ),
        );
      case _Skip():
        if (set['id'] == _currentEffort) {
          await _guard(() => _exec('skip', {'confirm': true}));
          await _settle();
        } else {
          await _change('store skip', {'setId': set['id'], 'confirm': true});
        }
      case _Actuals(:final actuals):
        await _logSet(set, {'actuals': actuals});
    }
  }

  /// The current set goes through the traversal (which prepares the next
  /// rest); any other set is logged ahead or corrected directly.
  Future<void> _logSet(
    Map<String, Object?> set,
    Map<String, Object?> what,
  ) async {
    if (set['id'] == _currentEffort &&
        set['status'] == 'planned' &&
        clock == null) {
      await _guard(() => _exec('complete', what));
      await _settle();
    } else {
      await _change('store complete', {'setId': set['id'], ...what});
    }
  }

  /// Plate hints for (instance revision, target) pairs; null while loading
  /// or when the instance has no plate loading.
  final _plateHints = <String, String?>{};

  String? _setNote(Fmt f, Map<String, Object?> set, {required bool current}) {
    if (set['loadArrangement'] case final Map arrangement) {
      return 'Plates: ${plateText(f, arrangement, instanceOf(session!, set))}';
    }
    final instance = instanceOf(session!, set);
    final binding = at(session, [
      'loadInputs',
      '${set['slot']}',
      'instance',
      'instanceId',
    ]);
    final missing = set['unavailablePlates'];
    final other = [
      if (set['performedOn'] != null && instance?.id != binding)
        'On ${instance?.snapshot['name'] ?? instance?.id}',
      if (missing is List && missing.isNotEmpty)
        'Missing ${missingText(f, missing)}',
    ].join(' · ');
    if (!current || set['status'] != 'planned') {
      return other.isEmpty ? null : other;
    }
    final mass = at(set, ['suggested', 'mass']);
    if (instance == null ||
        instance.snapshot['loading'] == null ||
        mass is! Map) {
      return other.isEmpty ? null : other;
    }
    final entered = (mass['entered'] ?? mass) as Map;
    final key =
        '${instance.id}@${instance.revision}:${entered['value']}${entered['unit']}'
        '-${missingText(f, missing)}';
    final target = <String, Object?>{
      'value': entered['value'],
      'unit': entered['unit'],
    };
    if (!_plateHints.containsKey(key)) {
      _plateHints[key] = null;
      // With missing plates, plan on what is there (pure plate plan).
      (missing is List && missing.isNotEmpty
              ? profile
                    .pure<Map<String, Object?>>('plate plan', {
                      'loading': availableLoading(
                        instance.snapshot['loading']! as Map,
                        missing,
                      ),
                      'target': target,
                    })
                    .then((plan) => <String, Object?>{'plan': plan})
              : profile.call<Map<String, Object?>>('store plate-plan', {
                  'instanceId': instance.id,
                  'revision': instance.revision,
                  'target': target,
                }))
          .then((r) {
            if (mounted) {
              setState(() => _plateHints[key] = planHint(f, r['plan']));
            }
          }, onError: (_) {});
    }
    final parts = [if (other.isNotEmpty) other, ?_plateHints[key]];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Future<void> _performOn(Map<String, Object?> set, OtherChoice choice) async {
    if (busy) return;
    final f = Fmt.of(context);
    setState(() => busy = true);
    try {
      final r = await profile.write<Map<String, Object?>>('store perform-on', {
        'id': widget.sessionId,
        'expectedVersion': session!['contentVersion'],
        'setId': set['id'],
        'instanceId': choice.instanceId,
        if (choice.instanceId == null) 'confirm': true,
        if (choice.instanceId != null) 'applyToRemaining': choice.remaining,
        if (choice.unavailable.isNotEmpty)
          'unavailablePlates': <Object?>[...choice.unavailable],
      });
      if (!mounted) return;
      setState(() => session = r['session'] as Map<String, Object?>);
      final nearest = [
        for (final x in (r['settings'] as List?) ?? const [])
          if ((x as Map)['setId'] == set['id'])
            '${metricLabel('${x['metric']}')} '
                '${((x['settings'] as List?) ?? const []).map((q) => f.quantity((q as Map)['entered'] ?? q, digits: 3)).join(' or ')}',
      ];
      if (nearest.isNotEmpty) _show('Nearest available: ${nearest.join(', ')}');
    } on BodyTmiException catch (e) {
      _show(e.message);
      await _reload();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// The bottom bar's left side: the rest or set clock, a manual rest,
  /// a timer to start, or what is left.
  Widget _status() {
    final cur = _current;
    final c = clock;
    Widget big(String text, String sub) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        Muted(sub),
      ],
    );
    if (cur?['kind'] == 'rest') {
      if (c == null) {
        return Row(
          children: [
            Expanded(child: big('Rest', 'continue when ready')),
            TextButton(
              onPressed: busy ? null : _continueRest,
              child: const Text('Continue'),
            ),
          ],
        );
      }
      final max = c.plan['restMaximumMilliseconds'] as int?;
      final min = c.plan['restMilliseconds'] as int? ?? 0;
      final ready = max != null && c.elapsed >= min;
      return Row(
        children: [
          Expanded(
            child: big(
              ready ? 'Rest ready' : 'Rest ${countdown(c.remaining ?? 0)}',
              'of ${countdown(min)}${c.running ? '' : ' · paused'}',
            ),
          ),
          if (!c.running)
            IconButton(
              tooltip: 'Resume rest',
              onPressed: busy ? null : () => c.start(),
              icon: const Icon(Icons.play_arrow),
            ),
          TextButton(
            onPressed: busy ? null : (ready ? _continueRest : _skipRest),
            child: Text(ready ? 'Continue' : 'Skip rest'),
          ),
        ],
      );
    }
    if (c != null && cur?['kind'] == 'effort') {
      if (c.status == 'awaitingConfirmation') {
        return Row(
          children: [
            Expanded(child: big("Time's up", 'review the set')),
            TextButton(
              onPressed: busy ? null : _review,
              child: const Text('Review'),
            ),
          ],
        );
      }
      final label = switch (c.phase) {
        'preparation' => 'Get ready',
        _ => 'Effort',
      };
      return Row(
        children: [
          Expanded(
            child: big(
              '$label ${countdown(c.remaining ?? c.elapsed)}',
              c.running ? 'timing' : 'paused',
            ),
          ),
          IconButton(
            tooltip: c.running ? 'Pause' : 'Resume',
            onPressed: busy ? null : () => c.running ? c.pause() : c.start(),
            icon: Icon(c.running ? Icons.pause : Icons.play_arrow),
          ),
        ],
      );
    }
    final left = _planned.length;
    final timed =
        cur?['kind'] == 'effort' &&
        _timed(cur?['set'] as Map<String, Object?>?);
    return Row(
      children: [
        Expanded(
          child: Muted(
            left == 0
                ? 'All sets logged'
                : '$left ${left == 1 ? 'set' : 'sets'} to go',
          ),
        ),
        if (timed)
          FilledButton.tonalIcon(
            onPressed: busy ? null : _startTimer,
            icon: const Icon(Icons.timer_outlined),
            label: const Text('Start timer'),
          ),
      ],
    );
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
    await clock?.pause();
    if (execution != null && execution!['status'] != 'completed') {
      // Skip what is left of the walk in one step (its outermost group).
      final groups = (execution!['groups'] as List?) ?? const [];
      if (groups.isNotEmpty) {
        await _guard(
          () => _exec('skip-group', {
            'groupPath': (groups.last as Map)['path'],
            'confirm': true,
          }),
        );
      }
      _attach(null);
    }
    if (_planned.isNotEmpty) {
      await _change('store skip-remaining', {'confirm': true});
      if (_planned.isNotEmpty) return;
    }
    await _change('store finish', {'finishedAt': isoInstant(DateTime.now())});
    // Stay to review progression proposals when the workout has any.
    if (mounted && _finished && _pinnedSlots.isEmpty) Navigator.pop(context);
  }

  static String _clock(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return m >= 60 ? '${m ~/ 60}:${_two(m % 60)}:${_two(s)}' : '$m:${_two(s)}';
  }
}

final class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.status,
    required this.busy,
    required this.onFinish,
  });
  final Widget status;
  final bool busy;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainer,
    elevation: 8,
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Expanded(child: status),
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

final class _SetRow extends StatelessWidget {
  const _SetRow({
    required this.set,
    required this.label,
    required this.current,
    required this.fmt,
    required this.onDone,
    required this.onTap,
    this.note,
  });
  final Map<String, Object?> set;
  final String label;
  final bool current;
  final Fmt fmt;
  final VoidCallback? onDone;
  final VoidCallback? onTap;
  final String? note;

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(left: 36, bottom: 4),
                child: Text(
                  note!,
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
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
  // Weight is `mass` in most workouts and `load` in some blueprints.
  final massKey = metrics.containsKey('mass') ? 'mass' : 'load';
  final mass = entered(metrics[massKey]);
  final reps = entered(metrics['reps']);
  final rest = [
    for (final e in metrics.entries)
      if (e.key != massKey && e.key != 'reps')
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

final class _Plates extends _SetResult {}

final class _Other extends _SetResult {}

final class _Missing extends _SetResult {}

final class _Actuals extends _SetResult {
  _Actuals(this.actuals);
  final Map<String, Object?> actuals;
}

/// Enter or correct a set's actuals, prefilled from the logged result or
/// the suggestion in their entered units.
final class _SetSheet extends StatefulWidget {
  const _SetSheet({
    required this.set,
    required this.label,
    this.slot,
    this.plates = false,
    this.otherEquipment = false,
    this.missingPlates = false,
    this.omit = const {},
  });

  /// Metrics measured elsewhere (a timed set's clock metric).
  final Set<String> omit;
  final bool missingPlates;
  final Map<String, Object?> set;
  final String label;
  final Map<String, Object?>? slot;
  final bool plates;
  final bool otherEquipment;

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
        if (!widget.omit.contains(e.key))
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
          if (widget.plates || widget.otherEquipment || widget.missingPlates)
            Wrap(
              spacing: 8,
              children: [
                if (widget.plates)
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context, _Plates()),
                    icon: const Icon(Icons.album_outlined),
                    label: Text(
                      widget.set['loadArrangement'] == null
                          ? 'Record plates'
                          : 'Plates',
                    ),
                  ),
                if (widget.missingPlates)
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context, _Missing()),
                    icon: const Icon(Icons.remove_circle_outline),
                    label: const Text('Missing plates'),
                  ),
                if (widget.otherEquipment)
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context, _Other()),
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Other equipment'),
                  ),
              ],
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
