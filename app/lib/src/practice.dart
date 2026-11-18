import 'dart:async';
import 'dart:math';

import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'format.dart';
import 'journal.dart' show RatingField;
import 'profile.dart';
import 'quick_entry.dart' show stamp;
import 'theme.dart';
import 'widgets.dart';

/// Opens the Practices screen (from More).
Future<void> openPractices(BuildContext context, {DateTime? clock}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PracticesScreen(clock: clock)),
    );

final class _PracticesData {
  _PracticesData(this.practices, this.sessions);
  final List<Map<String, Object?>> practices;
  final List<Map<String, Object?>> sessions;
}

String _phaseLabel(String id) => id.isEmpty
    ? id
    : '${id[0].toUpperCase()}${id.substring(1).replaceAll('-', ' ')}';

/// The ratings a practice asks at [moment] (`before` or `after`).
List<Map<String, Object?>> _ratings(
  Map<String, Object?> practice,
  String moment,
) => [
  for (final r in (practice['ratings'] as List?) ?? const [])
    if ((r as Map)['when'] == moment ||
        r['when'] == 'both' ||
        (r['when'] == null && moment == 'after'))
      r as Map<String, Object?>,
];

final class PracticesScreen extends StatelessWidget {
  const PracticesScreen({super.key, this.clock});
  final DateTime? clock;

  DateTime get _now => clock ?? DateTime.now();

  Future<_PracticesData> _load(ProfileClient p) async {
    final today = DateTime(_now.year, _now.month, _now.day);
    final practices = await p.call<List<Object?>>('practice list');
    final sessions = await p.call<List<Object?>>('practice sessions', {
      'from': isoDate(today.subtract(const Duration(days: 13))),
      'until': isoDate(today.add(const Duration(days: 1))),
    });
    return _PracticesData(
      practices.cast<Map<String, Object?>>(),
      sessions.cast<Map<String, Object?>>().reversed.toList(),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Practices')),
    body: ProfileLoader<_PracticesData>(
      load: _load,
      builder: (context, d) {
        final f = Fmt.of(context);
        final active = d.sessions.where((s) => s['status'] == 'active');
        final hasBox = d.practices.any(
          (p) => at(p, ['practice', 'id']) == 'box-breathing',
        );
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            for (final s in active)
              SectionCard(
                title: 'In progress',
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _name(d.practices, '${at(s, ['practice', 'id'])}'),
                      ),
                    ),
                    FilledButton(
                      onPressed: () => openPracticeRun(context, '${s['id']}'),
                      child: const Text('Continue'),
                    ),
                  ],
                ),
              ),
            for (final r in d.practices) _PracticeCard(revision: r, now: _now),
            if (!hasBox)
              SectionCard(
                title: 'Box breathing',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Muted(
                      'Equal inhale, hold, exhale and hold, five minutes a day '
                      '(Balban et al., Cell Reports Medicine 2023).',
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () => _addBox(context),
                      child: const Text('Add box breathing (4 s per side)'),
                    ),
                  ],
                ),
              ),
            SectionCard(
              title: 'Recent sessions',
              child: d.sessions.isEmpty
                  ? const EmptyNote('No practice sessions in two weeks.')
                  : Column(
                      children: [
                        for (final s in d.sessions)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _name(
                                          d.practices,
                                          '${at(s, ['practice', 'id'])}',
                                        ),
                                      ),
                                      Muted(
                                        '${f.shortDate('${s['startedAt']}'.substring(0, 10))}'
                                        ' · ${f.clock(s['startedAt'])} · ${s['status']}',
                                      ),
                                    ],
                                  ),
                                ),
                                if (at(s, ['actual', 'milliseconds'])
                                    case final int ms)
                                  Text(
                                    f.minutes((ms / 60000).round()),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                              ],
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

  static String _name(List<Map<String, Object?>> practices, String id) =>
      '${practices.where((p) => at(p, ['practice', 'id']) == id).map((p) => at(p, ['practice', 'name'])).firstOrNull ?? id}';

  Future<void> _addBox(BuildContext context) async {
    final profile = ProfileScope.of(context);
    try {
      await profile.write('practice box-breathing', {
        'secondsPerSide': 4,
        'expectedRevision': 0,
      });
    } on BodyTmiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }
}

final class _PracticeCard extends StatelessWidget {
  const _PracticeCard({required this.revision, required this.now});
  final Map<String, Object?> revision;
  final DateTime now;

  Map<String, Object?> get practice =>
      revision['practice']! as Map<String, Object?>;

  @override
  Widget build(BuildContext context) {
    final f = Fmt.of(context);
    final seconds = practice['durationSeconds'] as int?;
    final phases = [
      for (final p in (at(practice, ['phases', 'phases']) as List?) ?? const [])
        '${_phaseLabel('${(p as Map)['id']}')} ${Fmt.of(context).number((p['milliseconds'] as int) / 1000, digits: 1)} s',
    ];
    return SectionCard(
      title: '${practice['kind'] ?? 'practice'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${practice['name']}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          Muted(
            [
              seconds == null
                  ? 'open-ended'
                  : f.minutes((seconds / 60).round()),
              if (phases.isNotEmpty) phases.join(' · '),
            ].join(' · '),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _start(context),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => _log(context),
                child: const Text('Log without timer'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _start(BuildContext context) async {
    final profile = ProfileScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    Map<String, int>? before;
    final asked = _ratings(practice, 'before');
    if (asked.isNotEmpty) {
      before = await showDialog<Map<String, int>>(
        context: context,
        builder: (_) =>
            _RatingsDialog(title: 'Before you start', ratings: asked),
      );
      if (before == null) return;
    }
    try {
      final at = DateTime.now();
      final session = await profile.write<Map<String, Object?>>(
        'practice start',
        {
          'id': 'practice-${stamp(at)}',
          'practiceId': practice['id'],
          'revision': revision['revision'],
          'at': isoInstant(at),
          if (before != null && before.isNotEmpty) 'before': before,
        },
      );
      if (context.mounted) await openPracticeRun(context, '${session['id']}');
    } on BodyTmiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _log(BuildContext context) async {
    final profile = ProfileScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final minutes = await showDialog<int>(
      context: context,
      builder: (_) => _MinutesDialog(
        initial: ((practice['durationSeconds'] as int?) ?? 300) ~/ 60,
      ),
    );
    if (minutes == null) return;
    try {
      final at = DateTime.now();
      await profile.write('practice log', {
        'id': 'practice-${stamp(at)}',
        'practiceId': practice['id'],
        'revision': revision['revision'],
        'at': isoInstant(at.subtract(Duration(minutes: minutes))),
        'milliseconds': minutes * 60000,
      });
      messenger.showSnackBar(
        SnackBar(content: Text('Logged $minutes min of ${practice['name']}')),
      );
    } on BodyTmiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

final class _MinutesDialog extends StatefulWidget {
  const _MinutesDialog({required this.initial});
  final int initial;

  @override
  State<_MinutesDialog> createState() => _MinutesDialogState();
}

final class _MinutesDialogState extends State<_MinutesDialog> {
  late final text = TextEditingController(text: '${widget.initial}');

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Log without timer'),
    content: TextField(
      controller: text,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(
        labelText: 'Minutes, ending now',
        suffixText: 'min',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final n = int.tryParse(text.text.trim());
          if (n != null && n > 0 && n <= 24 * 60) Navigator.pop(context, n);
        },
        child: const Text('Log'),
      ),
    ],
  );
}

final class _RatingsDialog extends StatefulWidget {
  const _RatingsDialog({required this.title, required this.ratings});
  final String title;
  final List<Map<String, Object?>> ratings;

  @override
  State<_RatingsDialog> createState() => _RatingsDialogState();
}

final class _RatingsDialogState extends State<_RatingsDialog> {
  final values = <String, int>{};

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: _RatingInputs(
        ratings: widget.ratings,
        values: values,
        onChanged: () => setState(() {}),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, Map.of(values)),
        child: const Text('Continue'),
      ),
    ],
  );
}

/// Ratings as taps; unrated ones are left out, never defaulted.
final class _RatingInputs extends StatelessWidget {
  const _RatingInputs({
    required this.ratings,
    required this.values,
    required this.onChanged,
  });
  final List<Map<String, Object?>> ratings;
  final Map<String, int> values;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final r in ratings)
        if (r['minimum'] == 0 && r['maximum'] == 10)
          RatingField(
            label: '${r['label'] ?? r['id']}',
            anchors: ('low', 'high'),
            value: values['${r['id']}'],
            onChanged: (v) {
              values['${r['id']}'] = v;
              onChanged();
            },
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${r['label'] ?? r['id']}'),
              Wrap(
                spacing: 6,
                children: [
                  for (
                    var v = r['minimum']! as int;
                    v <= (r['maximum']! as int);
                    v++
                  )
                    ChoiceChip(
                      label: Text('$v'),
                      selected: values['${r['id']}'] == v,
                      onSelected: (_) {
                        values['${r['id']}'] = v;
                        onChanged();
                      },
                    ),
                ],
              ),
            ],
          ),
    ],
  );
}

Future<void> openPracticeRun(BuildContext context, String sessionId) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PracticeRunScreen(sessionId: sessionId),
      ),
    );

/// Runs one practice session in the foreground. The clock is the profile's
/// single timing clock: it is resumed with a fresh owner, sampled from a
/// monotonic stopwatch about once a second, and paused when the app leaves
/// the screen. Phases are shown from the clock's own tempo state, animated
/// between samples. Reaching the duration ends the clock; confirming records
/// the session with its after-ratings.
final class PracticeRunScreen extends StatefulWidget {
  const PracticeRunScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  State<PracticeRunScreen> createState() => _PracticeRunScreenState();
}

final class _PracticeRunScreenState extends State<PracticeRunScreen>
    with WidgetsBindingObserver {
  Map<String, Object?>? session;
  Map<String, Object?>? practice;
  Map<String, Object?>? clock;
  bool recover = false;
  Object? error;
  String? owner;
  final _watch = Stopwatch();
  int _sampledAt = 0;
  int _sampledElapsed = 0;
  Timer? _ticker;
  bool _sending = false;
  String? _lastPhase;
  final after = <String, int>{};
  final notes = TextEditingController();
  bool busy = false;

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
    if (session == null && error == null) _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    notes.dispose();
    if (_running) _pause();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      if (_running) _pause();
    }
  }

  bool get _running => clock?['status'] == 'running' && owner != null;

  Future<void> _load() async {
    try {
      final s = await profile.call<Map<String, Object?>>('practice session', {
        'id': widget.sessionId,
      });
      final p = await profile.call<Map<String, Object?>>('practice show', {
        'practiceId': at(s, ['practice', 'id']),
        'revision': at(s, ['practice', 'revision']),
      });
      if (!mounted) return;
      setState(() {
        session = s;
        practice = p['practice'] as Map<String, Object?>?;
        clock = s['clock'] as Map<String, Object?>?;
        // A clock found running belongs to an earlier, stopped app: its
        // owner is gone, so it needs explicit recovery.
        recover =
            s['requiresRecovery'] == true ||
            at(s, ['clock', 'status']) == 'running';
      });
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  Future<void> _resume() async {
    final c = clock!;
    owner =
        'app-${Random.secure().nextInt(1 << 32).toRadixString(16)}-'
        '${DateTime.now().microsecondsSinceEpoch}';
    try {
      final next = await profile.call<Map<String, Object?>>('timer resume', {
        'id': c['id'],
        'expectedVersion': c['version'],
        'ownerId': owner,
        'at': isoInstant(DateTime.now()),
      });
      _watch
        ..reset()
        ..start();
      _sampledAt = 0;
      _sampledElapsed = next['effortElapsedMilliseconds'] as int? ?? 0;
      setState(() => clock = next);
      _ticker ??= Timer.periodic(
        const Duration(milliseconds: 100),
        (_) => _tick(),
      );
    } on BodyTmiException catch (e) {
      owner = null;
      _show(e.message);
    }
  }

  void _tick() {
    if (!mounted) return;
    if (_running &&
        !_sending &&
        _watch.elapsedMilliseconds - _sampledAt >= 1000) {
      _sample('advance');
    }
    final phase = _phase()?.$1;
    if (phase != null && phase != _lastPhase) {
      if (_lastPhase != null) HapticFeedback.mediumImpact();
      _lastPhase = phase;
    }
    setState(() {});
  }

  Future<void> _sample(String action) async {
    final c = clock!;
    _sending = true;
    final elapsed = _watch.elapsedMilliseconds;
    try {
      final step = await profile.call<Map<String, Object?>>('timer $action', {
        'id': c['id'],
        'expectedVersion': c['version'],
        'ownerId': owner,
        'elapsedMilliseconds': elapsed,
        'at': isoInstant(DateTime.now()),
      });
      final next = (step['timer'] ?? step) as Map<String, Object?>;
      _sampledAt = elapsed;
      _sampledElapsed = next['effortElapsedMilliseconds'] as int? ?? 0;
      if (next['status'] != 'running') {
        _watch.stop();
        owner = null;
        if (next['status'] == 'awaitingConfirmation') {
          HapticFeedback.heavyImpact();
        }
      }
      if (mounted) setState(() => clock = next);
    } on BodyTmiException catch (e) {
      _show(e.message);
    } finally {
      _sending = false;
    }
    if (!mounted) return;
  }

  Future<void> _pause() async {
    while (_sending) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    if (_running) await _sample('pause');
    _watch.stop();
    owner = null;
  }

  Future<void> _endNow() async {
    await _pause();
    try {
      final next = await profile.call<Map<String, Object?>>('practice end', {
        'id': widget.sessionId,
        'at': isoInstant(DateTime.now()),
      });
      setState(() => clock = next);
    } on BodyTmiException catch (e) {
      _show(e.message);
    }
  }

  Future<void> _recover() async {
    try {
      final next = await profile.call<Map<String, Object?>>(
        'practice recover',
        {'id': widget.sessionId, 'at': isoInstant(DateTime.now())},
      );
      setState(() {
        clock = next;
        recover = false;
      });
    } on BodyTmiException catch (e) {
      _show(e.message);
    }
  }

  Future<void> _confirm() async {
    setState(() => busy = true);
    try {
      final s = await profile.call<Map<String, Object?>>('practice session', {
        'id': widget.sessionId,
      });
      await profile.write('practice confirm', {
        'id': widget.sessionId,
        'expectedVersion': s['version'],
        'at': isoInstant(DateTime.now()),
        if (after.isNotEmpty) 'after': after,
        if (notes.text.trim().isNotEmpty) 'notes': notes.text.trim(),
      });
      if (mounted) Navigator.pop(context);
    } on BodyTmiException catch (e) {
      _show(e.message);
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _abandon() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Abandon this practice?'),
        content: const Text('Nothing is recorded for it.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep going'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Abandon'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _pause();
    try {
      final s = await profile.call<Map<String, Object?>>('practice session', {
        'id': widget.sessionId,
      });
      await profile.write('practice abandon', {
        'id': widget.sessionId,
        'expectedVersion': s['version'],
        'confirm': true,
      });
      if (mounted) Navigator.pop(context);
    } on BodyTmiException catch (e) {
      _show(e.message);
    }
  }

  void _show(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// Effort time now: the last sample plus the stopwatch since it.
  int get _elapsed => _running
      ? _sampledElapsed + (_watch.elapsedMilliseconds - _sampledAt)
      : (clock?['effortElapsedMilliseconds'] as int? ?? 0);

  int? get _total => at(clock, ['plan', 'effortMilliseconds']) as int?;

  /// The current phase id and milliseconds left in it, from the clock's
  /// tempo plan.
  (String, int)? _phase() {
    final phases =
        (at(clock, ['plan', 'tempo', 'phases']) as List?) ?? const [];
    if (phases.isEmpty) return null;
    final lengths = [for (final p in phases) (p as Map)['milliseconds'] as int];
    final cycle = lengths.reduce((a, b) => a + b);
    var t = _elapsed % cycle;
    for (var i = 0; i < phases.length; i++) {
      if (t < lengths[i]) {
        return ('${(phases[i] as Map)['id']}', lengths[i] - t);
      }
      t -= lengths[i];
    }
    return null;
  }

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
    if (session == null || clock == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final status = '${clock!['status']}';
    final done = status == 'awaitingConfirmation';
    final total = _total;
    final elapsed = min(_elapsed, total ?? _elapsed);
    final phase = _phase();
    final scheme = Theme.of(context).colorScheme;
    String mmss(int ms) {
      final s = (ms / 1000).ceil();
      return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
    }

    return Scaffold(
      appBar: AppBar(title: Text('${practice?['name'] ?? 'Practice'}')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (recover)
            SectionCard(
              title: 'Interrupted',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Muted(
                    'The app stopped while this practice was running. Recover '
                    'it to keep the time recorded so far.',
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _recover,
                    child: const Text('Recover'),
                  ),
                ],
              ),
            ),
          SizedBox(
            height: 260,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 240,
                  height: 240,
                  child: CircularProgressIndicator(
                    value: total == null || total == 0 ? null : elapsed / total,
                    strokeWidth: 10,
                    backgroundColor: AppColors.of(context).line,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      done
                          ? 'Done'
                          : phase == null
                          ? mmss(elapsed)
                          : _phaseLabel(phase.$1),
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (phase != null && !done)
                      Text(
                        '${(phase.$2 / 1000).ceil()}',
                        style: TextStyle(fontSize: 48, color: scheme.primary),
                      ),
                    Muted(
                      total == null
                          ? '${mmss(elapsed)} so far'
                          : '${mmss(max(0, total - elapsed))} left',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (done) ...[
            _RatingInputs(
              ratings: practice == null
                  ? const []
                  : _ratings(practice!, 'after'),
              values: after,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: notes,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: busy ? null : _confirm,
              child: Text('Save ${mmss(elapsed)}'),
            ),
          ] else ...[
            FilledButton.icon(
              onPressed: recover
                  ? null
                  : _running
                  ? _pause
                  : _resume,
              icon: Icon(_running ? Icons.pause : Icons.play_arrow),
              label: Text(
                _running
                    ? 'Pause'
                    : elapsed == 0
                    ? 'Start'
                    : 'Resume',
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: recover || elapsed == 0 ? null : _endNow,
              child: const Text('End now'),
            ),
            TextButton(onPressed: _abandon, child: const Text('Abandon')),
            const Muted(
              'Timed in the foreground only: leaving the app pauses it.',
              align: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
