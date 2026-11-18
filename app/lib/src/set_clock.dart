import 'dart:async';
import 'dart:math';

import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:material_ui/material_ui.dart';

import 'format.dart';
import 'profile.dart';

/// Drives one persisted timing clock (a rest or a timed set) from the app,
/// as `timer run` does in the CLI: a fresh owner per resume, cumulative
/// monotonic stopwatch samples about once a second, and an explicit pause
/// whenever the app stops showing it. Wall-clock time is never elapsed
/// input. A clock found running without this app owning it (an earlier app
/// stopped) is recovered by freezing at its last checkpoint.
final class SetClock extends ChangeNotifier {
  SetClock(this.profile, Map<String, Object?> clock) : _clock = clock;

  final ProfileClient profile;
  Map<String, Object?> _clock;
  String? _owner;
  final _watch = Stopwatch();
  int _sampledAt = 0;
  int _sampledElapsed = 0;
  bool _sending = false;
  Timer? _ticker;
  bool _disposed = false;

  /// Called once the clock stops by itself (rest done, effort awaiting
  /// confirmation) or was stopped by a sample.
  void Function(Map<String, Object?> clock)? onStopped;

  Map<String, Object?> get clock => _clock;
  String get id => '${_clock['id']}';
  String get status => '${_clock['status']}';
  bool get running => status == 'running' && _owner != null;

  /// Running in storage but not owned here: needs recovery first.
  bool get orphaned => status == 'running' && _owner == null;

  Map<String, Object?> get plan =>
      (_clock['plan'] as Map<String, Object?>?) ?? const {};

  /// Total planned milliseconds (preparation, effort and rest), or null for
  /// an open-ended effort.
  int? get total {
    if (plan['openEnded'] == true) return null;
    return (plan['preparationMilliseconds'] as int? ?? 0) +
        (plan['effortMilliseconds'] as int? ?? 0) +
        (plan['restMilliseconds'] as int? ?? 0);
  }

  /// Clock time now: the last sample plus the stopwatch since it.
  int get elapsed => running
      ? _sampledElapsed + (_watch.elapsedMilliseconds - _sampledAt)
      : (_clock['elapsedMilliseconds'] as int? ?? 0);

  int? get remaining {
    final t = total;
    if (t == null) return null;
    return max(0, t - elapsed);
  }

  /// The phase now (preparation, effort, rest), from the plan and elapsed.
  String get phase {
    if (status != 'running' && status != 'paused') return status;
    final prep = plan['preparationMilliseconds'] as int? ?? 0;
    final effort = plan['effortMilliseconds'] as int? ?? 0;
    final e = elapsed;
    if (plan['restOnly'] == true) return 'rest';
    if (e < prep) return 'preparation';
    if (plan['openEnded'] == true || e < prep + effort) return 'effort';
    return 'rest';
  }

  String _at() => isoInstant(DateTime.now());

  Future<void> start() async {
    if (orphaned) {
      _clock = await profile.call<Map<String, Object?>>('timer recover', {
        'id': id,
        'expectedVersion': _clock['version'],
        'mode': 'freeze',
        'at': _at(),
      });
    }
    if (status != 'paused') return;
    final owner =
        'app-${Random.secure().nextInt(1 << 32).toRadixString(16)}-'
        '${DateTime.now().microsecondsSinceEpoch}';
    _clock = await profile.call<Map<String, Object?>>('timer resume', {
      'id': id,
      'expectedVersion': _clock['version'],
      'ownerId': owner,
      'at': _at(),
    });
    _owner = owner;
    _watch
      ..reset()
      ..start();
    _sampledAt = 0;
    _sampledElapsed = _clock['elapsedMilliseconds'] as int? ?? 0;
    _ticker ??= Timer.periodic(const Duration(milliseconds: 200), (_) {
      _tick();
    });
    _notify();
  }

  void _tick() {
    if (!running) return;
    final due =
        _watch.elapsedMilliseconds - _sampledAt >= 1000 ||
        (remaining != null && remaining == 0);
    if (due && !_sending) _sample('advance');
    _notify();
  }

  Future<void> _sample(String action) async {
    if (_owner == null) return;
    _sending = true;
    final ms = _watch.elapsedMilliseconds;
    try {
      final step = await profile.call<Map<String, Object?>>('timer $action', {
        'id': id,
        'expectedVersion': _clock['version'],
        'ownerId': _owner,
        'elapsedMilliseconds': ms,
        'at': _at(),
      });
      _clock = (step['timer'] ?? step) as Map<String, Object?>;
      _sampledAt = ms;
      _sampledElapsed = _clock['elapsedMilliseconds'] as int? ?? 0;
      if (status != 'running') {
        _watch.stop();
        _owner = null;
        if (action == 'advance') onStopped?.call(_clock);
      }
    } on BodyTmiException {
      // A conflict means another owner or a newer state: stop driving.
      _watch.stop();
      _owner = null;
    } finally {
      _sending = false;
      _notify();
    }
  }

  /// Pauses and saves the elapsed time; a no-op when not running here.
  Future<void> pause() async {
    while (_sending) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    if (running) await _sample('pause');
    _watch.stop();
    _owner = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    super.dispose();
  }
}

/// `1:05` from milliseconds.
String countdown(int ms) {
  final s = (ms / 1000).ceil();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}
