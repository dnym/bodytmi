import 'dart:convert';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'canonical_json.dart';
import 'session_window_clock.dart';
import 'session_window_review.dart';
import 'training_repository.dart';
import 'training_service.dart';
import 'window_deadlines.dart';

/// A saved scoped clock, optionally reserving the profile's timing slot.
final class WindowCheckpoint {
  WindowCheckpoint._(
    this.id,
    this.sessionId,
    this.version,
    this._clockJson,
    this.reserved,
  );
  factory WindowCheckpoint.fromJson(Object? input) {
    final j = jsonObject(input, 'window checkpoint');
    checkKeys(j, {'id', 'sessionId', 'version', 'clock', 'reserved'});
    final id = identifier(j, 'id');
    final sessionId = identifier(j, 'sessionId');
    final version = j['version'];
    if (version is! int || version < 1) invalid('Invalid checkpoint version.');
    final clock = jsonObject(j['clock'], 'session window clock');
    if (clock['sessionId'] != sessionId)
      invalid('Checkpoint session identity mismatch.');
    if (j.containsKey('reserved') && j['reserved'] != true)
      invalid('reserved must be true when specified.');
    return WindowCheckpoint._(
      id,
      sessionId,
      version,
      canonicalJson(clock),
      j['reserved'] == true,
    );
  }
  final String id, sessionId, _clockJson;
  final int version;
  final bool reserved;
  Map<String, Object?> get clock =>
      jsonObject(jsonDecode(_clockJson), 'session window clock');
  Map<String, Object?> toJson() => {
    'id': id,
    'sessionId': sessionId,
    'version': version,
    'clock': clock,
    if (reserved) 'reserved': true,
  };
}

void validateWindowCheckpoints(
  List<WindowCheckpoint> checkpoints,
  List<TrainingSession> sessions, {
  List<TimingActivity> timers = const [],
  List<WorkoutExecution> executions = const [],
}) {
  final bySession = {for (final s in sessions) s.id: s};
  final ids = <String>{};
  var reservations = 0;
  for (final checkpoint in checkpoints) {
    if (!ids.add(checkpoint.id))
      invalid('Duplicate window checkpoint identity.');
    final session = bySession[checkpoint.sessionId];
    if (session == null) invalid('Window checkpoint session is missing.');
    final wrapper = const SessionWindowClock().validateSnapshot(
      session,
      checkpoint.clock,
    );
    if (checkpoint.reserved) {
      reservations++;
      final status = jsonObject(wrapper['clock'], 'clock')['status'];
      if (session.status != SessionStatus.active || status == 'complete')
        invalid(
          'A reserved window clock requires an active session and unfinished clock.',
        );
      if (executions.any(
        (execution) => execution.sessionId == session.id && !execution.complete,
      ))
        invalid(
          'A session cannot have both a reserved window clock and an active traversal.',
        );
    }
  }
  if (reservations > 1 ||
      (reservations > 0 && timers.any((timer) => timer.active)))
    invalid('Only one logical timing activity may be active.');
}

final class WindowCheckpointService {
  const WindowCheckpointService(this.repository);
  final TrainingRepository repository;

  int _expiredDestination(TrainingSession session, Map<String, Object?> clock) {
    if (clock['status'] != 'boundary')
      invalid('A window boundary is required.');
    final occurrence = clock['occurrence'] as int;
    final definition = session.revision.definition;
    final deadline = const WindowDeadlines().evaluate(
      definition: definition,
      occurrence: occurrence,
      elapsedMilliseconds: clock['elapsedMilliseconds'] as int,
      windowStarts: jsonObject(clock['windowStarts'], 'windowStarts'),
    );
    final expired = (deadline['windows'] as List<Map<String, Object?>>)
        .where((row) => row['expired'] == true)
        .map((row) => row['path'] as String)
        .toSet();
    final scopes = activityGroups(
      definition.plan,
      containing: occurrence,
    ).where((scope) => expired.contains(scope.path)).toList();
    if (scopes.isEmpty) invalid('No expired window contains the occurrence.');
    return scopes.map((scope) => scope.end).reduce((a, b) => a > b ? a : b);
  }

  /// Move past a boundary only when every crossed effort was already reviewed.
  /// Null means planned work remains; no state is changed in that case.
  Future<WindowCheckpoint?> advanceReviewedBoundary(
    String id, {
    required int expectedVersion,
    required int expectedSessionVersion,
    required int expectedClockVersion,
  }) => repository.transaction(() async {
    final current = await show(id);
    if (current.version != expectedVersion)
      throw const BodyTmiException('conflict', 'Checkpoint version changed.');
    if (!current.reserved)
      invalid('Reserve the checkpoint before clock actions.');
    final session = await StoredTrainingService(
      repository,
    ).session(current.sessionId);
    if (session.contentVersion != expectedSessionVersion)
      throw const BodyTmiException(
        'conflict',
        'Session content version changed.',
      );
    if (session.status != SessionStatus.active)
      invalid('An active session is required.');
    final wrapper = const SessionWindowClock().validateSnapshot(
      session,
      current.clock,
    );
    final clock = jsonObject(wrapper['clock'], 'window clock');
    if (clock['version'] != expectedClockVersion)
      throw const BodyTmiException('conflict', 'Window clock version changed.');
    final destination = _expiredDestination(session, clock);
    final occurrence = clock['occurrence'] as int;
    final plan = session.revision.definition.plan.occurrences().toList();
    final sets = {for (final set in session.sets) set.id: set};
    for (var i = occurrence; i < destination; i++) {
      if (plan[i].activity is Effort &&
          sets[plan[i].id]!.status == SetStatus.planned)
        return null;
    }
    final next = const SessionWindowClock().apply(
      session,
      wrapper,
      expectedVersion: expectedClockVersion,
      action: 'move',
      toOccurrence: destination,
    );
    final complete = jsonObject(next['clock'], 'clock')['status'] == 'complete';
    return _replace(current, next, reserved: !complete);
  });

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
    if (current?.reserved == true)
      invalid('Release the reserved clock before replacing its snapshot.');
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
    validateWindowCheckpoints([checkpoint], [session]);
    if (checkpoint.reserved)
      validateWindowCheckpoints(
        await repository.windowCheckpoints(),
        await repository.sessions(),
        timers: await repository.timingActivities(),
        executions: await repository.executions(),
      );
    return checkpoint;
  });

  Future<List<WindowCheckpoint>> list() => repository.transaction(() async {
    final checkpoints = await repository.windowCheckpoints();
    validateWindowCheckpoints(
      checkpoints,
      await repository.sessions(),
      timers: await repository.timingActivities(),
      executions: await repository.executions(),
    );
    return checkpoints..sort((a, b) => a.id.compareTo(b.id));
  });

  Future<WindowCheckpoint> reserve(
    String id,
    int expectedVersion,
  ) => repository.transaction(() async {
    final current = await show(id);
    if (current.version != expectedVersion)
      throw const BodyTmiException('conflict', 'Checkpoint version changed.');
    if (current.reserved)
      invalid('This checkpoint already reserves the clock.');
    final session = await StoredTrainingService(
      repository,
    ).session(current.sessionId);
    final state = jsonObject(current.clock['clock'], 'window clock');
    if (session.status != SessionStatus.active ||
        !{'paused', 'boundary'}.contains(state['status']))
      invalid(
        'Reserve requires an active session and a paused or boundary clock.',
      );
    if ((await repository.executions()).any(
      (execution) => execution.sessionId == session.id && !execution.complete,
    ))
      invalid('Finish the session traversal before reserving a scoped clock.');
    if ((await repository.timingActivities()).any((timer) => timer.active) ||
        (await repository.windowCheckpoints()).any(
          (checkpoint) => checkpoint.reserved,
        ))
      throw const BodyTmiException(
        'conflict',
        'Another timing activity is active.',
      );
    return _replace(current, current.clock, reserved: true);
  });

  Future<WindowCheckpoint> release(
    String id,
    int expectedVersion, {
    required bool confirm,
  }) => repository.transaction(() async {
    if (!confirm) invalid('Releasing the clock requires confirm:true.');
    final current = await show(id);
    if (current.version != expectedVersion)
      throw const BodyTmiException('conflict', 'Checkpoint version changed.');
    if (!current.reserved ||
        jsonObject(current.clock['clock'], 'clock')['status'] == 'running')
      invalid('Pause or recover the reserved clock before releasing it.');
    return _replace(current, current.clock, reserved: false);
  });

  Future<WindowCheckpoint> action(
    String id, {
    required int expectedVersion,
    required int expectedSessionVersion,
    required int expectedClockVersion,
    required String action,
    String? ownerId,
    int? ownerElapsedMilliseconds,
    int? toOccurrence,
    int? adjustmentMilliseconds,
  }) => repository.transaction(() async {
    final current = await show(id);
    if (current.version != expectedVersion)
      throw const BodyTmiException('conflict', 'Checkpoint version changed.');
    if (!current.reserved)
      invalid('Reserve the checkpoint before clock actions.');
    final session = await StoredTrainingService(
      repository,
    ).session(current.sessionId);
    if (session.contentVersion != expectedSessionVersion)
      throw const BodyTmiException(
        'conflict',
        'Session content version changed.',
      );
    final next = const SessionWindowClock().apply(
      session,
      current.clock,
      expectedVersion: expectedClockVersion,
      action: action,
      ownerId: ownerId,
      ownerElapsedMilliseconds: ownerElapsedMilliseconds,
      toOccurrence: toOccurrence,
      adjustmentMilliseconds: adjustmentMilliseconds,
    );
    final complete = jsonObject(next['clock'], 'clock')['status'] == 'complete';
    return _replace(current, next, reserved: !complete);
  });

  Future<WindowCheckpoint> _replace(
    WindowCheckpoint current,
    Object? snapshot, {
    required bool reserved,
  }) async {
    final session = await StoredTrainingService(
      repository,
    ).session(current.sessionId);
    final clock = const SessionWindowClock().validateSnapshot(
      session,
      snapshot,
    );
    final next = WindowCheckpoint.fromJson({
      'id': current.id,
      'sessionId': current.sessionId,
      'version': current.version + 1,
      'clock': clock,
      if (reserved) 'reserved': true,
    });
    validateWindowCheckpoints([next], [session]);
    await repository.saveWindowCheckpoint(next);
    return next;
  }

  /// Record the current effort without moving its scoped clock.
  Future<
    ({
      TrainingSession session,
      WindowCheckpoint checkpoint,
      String occurrenceId,
    })
  >
  completeCurrent(
    String id, {
    required int expectedVersion,
    required int expectedSessionVersion,
    required int expectedClockVersion,
    Metrics actuals = const {},
    bool acceptSuggested = false,
  }) => repository.transaction(() async {
    final current = await show(id);
    if (current.version != expectedVersion)
      throw const BodyTmiException('conflict', 'Checkpoint version changed.');
    final training = StoredTrainingService(repository);
    final session = await training.session(current.sessionId);
    if (session.contentVersion != expectedSessionVersion)
      throw const BodyTmiException(
        'conflict',
        'Session content version changed.',
      );
    if (session.status != SessionStatus.active)
      invalid('Review requires an active session.');
    final wrapper = const SessionWindowClock().validateSnapshot(
      session,
      current.clock,
    );
    final clock = jsonObject(wrapper['clock'], 'window clock');
    if (clock['version'] != expectedClockVersion)
      throw const BodyTmiException('conflict', 'Window clock version changed.');
    if (!{'paused', 'boundary'}.contains(clock['status']))
      invalid('Review requires a paused or boundary clock.');
    final occurrence = clock['occurrence'] as int;
    final occurrences = session.revision.definition.plan.occurrences().toList();
    if (occurrence >= occurrences.length ||
        occurrences[occurrence].activity is! Effort)
      invalid('Review requires a current effort.');
    final occurrenceId = occurrences[occurrence].id;
    if (session.set(occurrenceId).status != SetStatus.planned)
      invalid('Review requires a planned current effort.');
    final updated = const TrainingService().complete(
      session,
      occurrenceId,
      actuals,
      acceptSuggested: acceptSuggested,
    );
    final saved = await training.edit(
      session.id,
      expectedSessionVersion,
      (_) => updated,
    );
    final checkpoint = await _replace(current, {
      ...wrapper,
      'sessionContentVersion': saved.contentVersion,
    }, reserved: current.reserved);
    return (session: saved, checkpoint: checkpoint, occurrenceId: occurrenceId);
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
    final complete =
        jsonObject(result.clock['clock'], 'clock')['status'] == 'complete';
    final checkpoint = await _replace(
      current,
      result.clock,
      reserved: current.reserved && !complete,
    );
    return (
      session: saved,
      checkpoint: checkpoint,
      occurrenceId: result.occurrenceId,
    );
  });

  /// Explicitly abandon planned work in the expired scope and move past it.
  Future<
    ({
      TrainingSession session,
      WindowCheckpoint checkpoint,
      List<String> skipped,
    })
  >
  skipExpired(
    String id, {
    required int expectedVersion,
    required int expectedSessionVersion,
    required int expectedClockVersion,
    required bool confirm,
  }) async {
    final result = await _resolveExpired(
      id,
      expectedVersion: expectedVersion,
      expectedSessionVersion: expectedSessionVersion,
      expectedClockVersion: expectedClockVersion,
      confirm: confirm,
    );
    return (
      session: result.session,
      checkpoint: result.checkpoint,
      skipped: result.skipped,
    );
  }

  /// Complete the current effort and explicitly abandon remaining expired work.
  Future<
    ({
      TrainingSession session,
      WindowCheckpoint checkpoint,
      List<String> skipped,
      String occurrenceId,
    })
  >
  reviewExpired(
    String id, {
    required int expectedVersion,
    required int expectedSessionVersion,
    required int expectedClockVersion,
    required bool confirm,
    Metrics actuals = const {},
    bool acceptSuggested = false,
  }) async {
    final result = await _resolveExpired(
      id,
      expectedVersion: expectedVersion,
      expectedSessionVersion: expectedSessionVersion,
      expectedClockVersion: expectedClockVersion,
      confirm: confirm,
      reviewCurrent: true,
      actuals: actuals,
      acceptSuggested: acceptSuggested,
    );
    return (
      session: result.session,
      checkpoint: result.checkpoint,
      skipped: result.skipped,
      occurrenceId: result.occurrenceId!,
    );
  }

  Future<
    ({
      TrainingSession session,
      WindowCheckpoint checkpoint,
      List<String> skipped,
      String? occurrenceId,
    })
  >
  _resolveExpired(
    String id, {
    required int expectedVersion,
    required int expectedSessionVersion,
    required int expectedClockVersion,
    required bool confirm,
    bool reviewCurrent = false,
    Metrics actuals = const {},
    bool acceptSuggested = false,
  }) => repository.transaction(() async {
    if (!confirm) invalid('Skipping expired work requires confirm:true.');
    final current = await show(id);
    if (current.version != expectedVersion)
      throw const BodyTmiException('conflict', 'Checkpoint version changed.');
    final training = StoredTrainingService(repository);
    final session = await training.session(current.sessionId);
    if (session.contentVersion != expectedSessionVersion)
      throw const BodyTmiException(
        'conflict',
        'Session content version changed.',
      );
    if (session.status != SessionStatus.active)
      invalid('Skipping expired work requires an active session.');
    final wrapper = const SessionWindowClock().validateSnapshot(
      session,
      current.clock,
    );
    final clock = jsonObject(wrapper['clock'], 'window clock');
    if (clock['version'] != expectedClockVersion)
      throw const BodyTmiException('conflict', 'Window clock version changed.');
    if (clock['status'] != 'boundary')
      invalid('Skipping expired work requires a window boundary.');
    final occurrence = clock['occurrence'] as int;
    final definition = session.revision.definition;
    final destination = _expiredDestination(session, clock);
    final occurrences = definition.plan.occurrences().toList();
    String? reviewed;
    var updated = session;
    if (reviewCurrent) {
      if (occurrences[occurrence].activity is! Effort)
        invalid('Review requires a current effort.');
      reviewed = occurrences[occurrence].id;
      if (session.set(reviewed).status != SetStatus.planned)
        invalid('Review requires a planned current effort.');
      updated = const TrainingService().complete(
        session,
        reviewed,
        actuals,
        acceptSuggested: acceptSuggested,
      );
    }
    final ids = <String>{
      for (var i = occurrence; i < destination; i++)
        if (occurrences[i].activity is Effort) occurrences[i].id,
    };
    final skipped = [
      for (final set in updated.sets)
        if (ids.contains(set.id) && set.status == SetStatus.planned) set.id,
    ];
    updated = const TrainingService().skipOccurrences(
      updated,
      ids,
      confirm: true,
    );
    final next = const SessionWindowClock().apply(
      updated,
      wrapper,
      expectedVersion: expectedClockVersion,
      action: 'move',
      toOccurrence: destination,
    );
    final saved = skipped.isEmpty && !reviewCurrent
        ? session
        : await training.edit(
            session.id,
            expectedSessionVersion,
            (_) => updated,
          );
    final complete = jsonObject(next['clock'], 'clock')['status'] == 'complete';
    final checkpoint = await _replace(
      current,
      next,
      reserved: current.reserved && !complete,
    );
    return (
      session: saved,
      checkpoint: checkpoint,
      skipped: skipped,
      occurrenceId: reviewed,
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
    if (current.reserved)
      invalid('Release the reserved clock before deleting its checkpoint.');
    await repository.deleteWindowCheckpoint(id);
  });
}
