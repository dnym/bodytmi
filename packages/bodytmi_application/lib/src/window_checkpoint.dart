import 'dart:convert';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'canonical_json.dart';
import 'session_window_clock.dart';
import 'session_window_review.dart';
import 'training_repository.dart';

/// An inert, user-saved scoped-clock snapshot. It does not own a timer.
final class WindowCheckpoint {
  WindowCheckpoint._(this.id, this.sessionId, this.version, this._clockJson);
  factory WindowCheckpoint.fromJson(Object? input) {
    final j = jsonObject(input, 'window checkpoint');
    checkKeys(j, {'id', 'sessionId', 'version', 'clock'});
    final id = identifier(j, 'id');
    final sessionId = identifier(j, 'sessionId');
    final version = j['version'];
    if (version is! int || version < 1) invalid('Invalid checkpoint version.');
    final clock = jsonObject(j['clock'], 'session window clock');
    if (clock['sessionId'] != sessionId)
      invalid('Checkpoint session identity mismatch.');
    return WindowCheckpoint._(id, sessionId, version, canonicalJson(clock));
  }
  final String id, sessionId, _clockJson;
  final int version;
  Map<String, Object?> get clock =>
      jsonObject(jsonDecode(_clockJson), 'session window clock');
  Map<String, Object?> toJson() => {
    'id': id,
    'sessionId': sessionId,
    'version': version,
    'clock': clock,
  };
}

void validateWindowCheckpoints(
  List<WindowCheckpoint> checkpoints,
  List<TrainingSession> sessions,
) {
  final bySession = {for (final s in sessions) s.id: s};
  final ids = <String>{};
  for (final checkpoint in checkpoints) {
    if (!ids.add(checkpoint.id))
      invalid('Duplicate window checkpoint identity.');
    final session = bySession[checkpoint.sessionId];
    if (session == null) invalid('Window checkpoint session is missing.');
    const SessionWindowClock().validateSnapshot(session, checkpoint.clock);
  }
}

final class WindowCheckpointService {
  const WindowCheckpointService(this.repository);
  final TrainingRepository repository;

  Future<WindowCheckpoint> save(
    String id,
    String sessionId,
    int expectedVersion,
    Object? snapshot,
  ) => repository.transaction(() async {
    identifier({'id': id}, 'id');
    if (expectedVersion < 0) invalid('expectedVersion must be nonnegative.');
    final session = await repository.session(sessionId);
    if (session == null)
      throw const BodyTmiException('not_found', 'Session not found.');
    final current = await repository.windowCheckpoint(id);
    if ((current?.version ?? 0) != expectedVersion)
      throw const BodyTmiException('conflict', 'Checkpoint version changed.');
    if (current != null && current.sessionId != sessionId)
      invalid('A checkpoint cannot change sessions.');
    if (current != null)
      const SessionWindowClock().validateSnapshot(session, current.clock);
    final clock = const SessionWindowClock().validateSnapshot(
      session,
      snapshot,
    );
    final next = WindowCheckpoint.fromJson({
      'id': id,
      'sessionId': sessionId,
      'version': expectedVersion + 1,
      'clock': clock,
    });
    await repository.saveWindowCheckpoint(next);
    return next;
  });

  Future<WindowCheckpoint> show(String id) => repository.transaction(() async {
    final checkpoint =
        await repository.windowCheckpoint(id) ??
        (throw const BodyTmiException(
          'not_found',
          'Window checkpoint not found.',
        ));
    final session = await repository.session(checkpoint.sessionId);
    if (session == null) invalid('Window checkpoint session is missing.');
    const SessionWindowClock().validateSnapshot(session, checkpoint.clock);
    return checkpoint;
  });

  Future<List<WindowCheckpoint>> list() => repository.transaction(() async {
    final checkpoints = await repository.windowCheckpoints();
    validateWindowCheckpoints(checkpoints, await repository.sessions());
    return checkpoints..sort((a, b) => a.id.compareTo(b.id));
  });

  /// Explicitly review an effort and save its moved checkpoint atomically.
  Future<
    ({
      TrainingSession session,
      WindowCheckpoint checkpoint,
      String occurrenceId,
    })
  >
  review(
    String id, {
    required int expectedVersion,
    required int expectedSessionVersion,
    required int expectedClockVersion,
    required int toOccurrence,
    required String action,
    Metrics actuals = const {},
    bool acceptSuggested = false,
    bool confirm = false,
  }) => repository.transaction(() async {
    final current = await show(id);
    if (current.version != expectedVersion)
      throw const BodyTmiException('conflict', 'Checkpoint version changed.');
    final training = StoredTrainingService(repository);
    final session = await training.session(current.sessionId);
    final result = const SessionWindowReview().review(
      session,
      current.clock,
      expectedSessionVersion: expectedSessionVersion,
      expectedClockVersion: expectedClockVersion,
      toOccurrence: toOccurrence,
      action: action,
      actuals: actuals,
      acceptSuggested: acceptSuggested,
      confirm: confirm,
    );
    final saved = await training.edit(
      session.id,
      expectedSessionVersion,
      (_) => result.session,
    );
    final checkpoint = await save(
      id,
      session.id,
      expectedVersion,
      result.clock,
    );
    return (
      session: saved,
      checkpoint: checkpoint,
      occurrenceId: result.occurrenceId,
    );
  });

  Future<void> delete(
    String id,
    int expectedVersion, {
    required bool confirm,
  }) => repository.transaction(() async {
    if (!confirm) invalid('Deleting a checkpoint requires confirm:true.');
    final current = await show(id);
    if (current.version != expectedVersion)
      throw const BodyTmiException('conflict', 'Checkpoint version changed.');
    await repository.deleteWindowCheckpoint(id);
  });
}
