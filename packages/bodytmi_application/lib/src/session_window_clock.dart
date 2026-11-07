import 'package:bodytmi_core/bodytmi_core.dart';
import 'window_clock.dart';

/// Caller-owned clock tied to a session; movement never records results.
final class SessionWindowClock {
  const SessionWindowClock();
  static const _clock = WindowClock();

  Map<String, Object?> start(TrainingSession session) {
    if (session.status != SessionStatus.active)
      invalid('A window clock requires an active session.');
    return _wrap(session, _clock.start(session.revision.definition));
  }

  Map<String, Object?> apply(
    TrainingSession session,
    Object? input, {
    required int expectedVersion,
    required String action,
    String? ownerId,
    int? ownerElapsedMilliseconds,
    int? toOccurrence,
    int? adjustmentMilliseconds,
  }) {
    if (session.status != SessionStatus.active)
      invalid('A window clock requires an active session.');
    final wrapper = jsonObject(input, 'session window clock');
    checkKeys(wrapper, {
      'policy',
      'sessionId',
      'sessionStartedAt',
      'revision',
      'sessionContentVersion',
      'clock',
    });
    if (wrapper['policy'] != 'bodytmi-session-window-clock/1' ||
        wrapper['sessionId'] != session.id ||
        wrapper['revision'] != session.revision.number ||
        wrapper['sessionStartedAt'] !=
            session.startedAt.toUtc().toIso8601String())
      invalid('Window clock belongs to a different session.');
    final sourceVersion = wrapper['sessionContentVersion'];
    if (sourceVersion is! int ||
        sourceVersion < 1 ||
        sourceVersion > session.contentVersion)
      invalid('Window clock requires a current or newer session snapshot.');
    final clock = jsonObject(wrapper['clock'], 'window clock');
    // Validate the clock before using its cursor, including its pinned workout.
    if (action == 'move' && toOccurrence != null) {
      final occurrence = clock['occurrence'];
      final plan = session.revision.definition.plan.occurrences().toList();
      if (occurrence is! int ||
          occurrence < 0 ||
          occurrence >= plan.length ||
          toOccurrence <= occurrence ||
          toOccurrence > plan.length)
        invalid(
          'The destination must be a later occurrence or the end of the plan.',
        );
      for (var i = occurrence; i < toOccurrence; i++) {
        if (plan[i].activity is Effort &&
            session.set(plan[i].id).status == SetStatus.planned)
          invalid('Complete or skip each effort before moving past it.');
      }
    }
    final next = _clock.apply(
      session.revision.definition,
      clock,
      expectedVersion: expectedVersion,
      action: action,
      ownerId: ownerId,
      ownerElapsedMilliseconds: ownerElapsedMilliseconds,
      toOccurrence: toOccurrence,
      adjustmentMilliseconds: adjustmentMilliseconds,
    );
    return _wrap(session, next);
  }

  Map<String, Object?> _wrap(
    TrainingSession session,
    Map<String, Object?> clock,
  ) => {
    'policy': 'bodytmi-session-window-clock/1',
    'sessionId': session.id,
    'sessionStartedAt': session.startedAt.toUtc().toIso8601String(),
    'revision': session.revision.number,
    'sessionContentVersion': session.contentVersion,
    'clock': clock,
  };
}
