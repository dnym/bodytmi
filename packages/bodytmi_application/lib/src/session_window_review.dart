import 'package:bodytmi_core/bodytmi_core.dart';
import 'session_window_clock.dart';
import 'training_service.dart';

/// Explicit review and clock movement; no measured value is inferred.
final class SessionWindowReview {
  const SessionWindowReview();

  ({TrainingSession session, Map<String, Object?> clock, String occurrenceId})
  review(
    TrainingSession session,
    Object? wrapper, {
    required int expectedSessionVersion,
    required int expectedClockVersion,
    required int toOccurrence,
    required String action,
    Metrics actuals = const {},
    bool acceptSuggested = false,
    bool confirm = false,
  }) {
    if (session.contentVersion != expectedSessionVersion)
      throw const BodyTmiException(
        'conflict',
        'Session content version changed.',
      );
    if (session.status != SessionStatus.active)
      invalid('Window review requires an active session.');
    if (!{'complete', 'skip'}.contains(action))
      invalid('Window review action must be complete or skip.');
    if (action == 'skip' && (!confirm || actuals.isNotEmpty || acceptSuggested))
      invalid('Skipping requires confirmation and no actuals.');
    if (action == 'complete' && confirm)
      invalid('Confirmation is only used for skipping.');
    final wrapped = jsonObject(wrapper, 'session window clock');
    final clock = jsonObject(wrapped['clock'], 'window clock');
    final occurrence = clock['occurrence'];
    final plan = session.revision.definition.plan.occurrences().toList();
    if (occurrence is! int ||
        occurrence < 0 ||
        occurrence >= plan.length ||
        plan[occurrence].activity is! Effort ||
        !{'paused', 'boundary'}.contains(clock['status']))
      invalid(
        'Review requires the current effort and a paused or boundary clock.',
      );
    final id = plan[occurrence].id;
    if (session.set(id).status != SetStatus.planned)
      invalid(
        'Review requires a planned effort; move past reviewed work explicitly.',
      );
    final updated = action == 'complete'
        ? const TrainingService().complete(
            session,
            id,
            actuals,
            acceptSuggested: acceptSuggested,
          )
        : const TrainingService().skip(session, id, confirm: true);
    final next = const SessionWindowClock().apply(
      updated,
      wrapper,
      expectedVersion: expectedClockVersion,
      action: 'move',
      toOccurrence: toOccurrence,
    );
    return (session: updated, clock: next, occurrenceId: id);
  }
}
