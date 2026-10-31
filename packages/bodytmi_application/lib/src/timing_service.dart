import 'package:bodytmi_core/bodytmi_core.dart';
import 'canonical_json.dart';
import 'execution_service.dart';
import 'training_repository.dart';

final class TimingService {
  const TimingService(this.repository);
  final TrainingRepository repository;
  Future<TimingActivity> show(String id) async =>
      await repository.timingActivity(id) ??
      (throw const BodyTmiException('not_found', 'Timing activity not found.'));
  Future<TimingActivity> start(
    String id,
    String sessionId,
    String setId,
    String metric,
    TimingPlan plan,
    DateTime at,
  ) => repository.transaction(() async {
    if (plan.restOnly)
      invalid('Use the rest timing operation for a rest occurrence.');
    final next = TimingActivity.create(
      id: id,
      sessionId: sessionId,
      setId: setId,
      metric: metric,
      plan: plan,
      at: at,
    );
    final all = await repository.timingActivities();
    final existing = all.where((t) => t.id == id).firstOrNull;
    if (existing != null) {
      if (existing.sessionId != sessionId ||
          existing.setId != setId ||
          existing.metric != metric ||
          existing.toJson()['createdAt'] != next.toJson()['createdAt'] ||
          canonicalJson(existing.plan.toJson()) != canonicalJson(plan.toJson()))
        _conflict();
      return existing;
    }
    if (all.any((t) => t.active))
      _conflict(
        'Another timing activity is active; explicitly stop/discard it first.',
      );
    final s = await StoredTrainingService(repository).session(sessionId);
    if (_insideWindow(s, setId))
      invalid('Per-set timing cannot execute scoped time windows yet.');
    if (s.status != SessionStatus.active ||
        s.set(setId).status != SetStatus.planned ||
        at.isBefore(s.startedAt) ||
        s.set(setId).suggested[metric]?.dimension != Dimension.duration)
      invalid(
        'Timing needs a planned duration metric in an active session and a valid start time.',
      );
    validateExecutionData(
      await repository.executions(),
      await repository.sessions(),
      [...all, next],
    );
    await repository.saveTimingActivity(next);
    return next;
  });
  Future<TimingActivity> startRest(
    String id,
    String sessionId,
    String occurrenceId,
    DateTime at,
  ) => repository.transaction(() async {
    final s = await StoredTrainingService(repository).session(sessionId);
    final occurrence = s.revision.definition.plan
        .occurrences()
        .where((o) => o.id == occurrenceId)
        .firstOrNull;
    if (occurrence?.activity is! Rest ||
        _insideWindow(s, occurrenceId) ||
        s.status != SessionStatus.active ||
        at.isBefore(s.startedAt))
      invalid(
        'Rest timing requires an unscoped rest occurrence in an active session.',
      );
    final rest = occurrence!.activity as Rest;
    final plan = TimingPlan.fromJson({
      'restOnly': true,
      'effortMilliseconds': 0,
      'restMilliseconds': rest.durationSeconds * 1000,
    });
    final all = await repository.timingActivities();
    final existing = all.where((t) => t.id == id).firstOrNull;
    if (existing != null) {
      if (existing.sessionId != sessionId ||
          existing.setId != occurrenceId ||
          !existing.plan.restOnly ||
          existing.toJson()['createdAt'] != at.toUtc().toIso8601String())
        _conflict();
      return existing;
    }
    if (all.any((t) => t.active))
      _conflict('Another timing activity is active.');
    final next = TimingActivity.create(
      id: id,
      sessionId: sessionId,
      setId: occurrenceId,
      metric: 'duration',
      plan: plan,
      at: at,
    );
    validateExecutionData(
      await repository.executions(),
      await repository.sessions(),
      [...all, next],
    );
    await repository.saveTimingActivity(next);
    return next;
  });
  Future<TimingActivity> resume(
    String id,
    int version,
    String owner,
    DateTime at,
  ) => _change(id, version, (t) => t.resume(owner, at));
  Future<TimingActivity> endEffort(String id, int version, DateTime at) =>
      _change(id, version, (t) {
        if (t.status != 'paused')
          invalid('Pause the clock before explicitly ending its effort.');
        return t.endEffort(at);
      });
  Future<TimingAdvance> advance(
    String id,
    int version,
    String owner,
    int elapsed,
    DateTime at, {
    String action = 'advance',
  }) => repository.transaction(() async {
    final current = await show(id);
    if (action == 'advance' &&
        current.ownerId == owner &&
        current.ownerElapsedMilliseconds == elapsed)
      return TimingAdvance(current, const []);
    if (current.version != version) _conflict();
    final step = current.advance(elapsed, owner, at);
    final next = switch (action) {
      'advance' => step.activity,
      'pause' =>
        step.activity.status == 'running'
            ? step.activity.pause(at)
            : step.activity,
      _ => invalid('Unknown clock action.'),
    };
    await repository.saveTimingActivity(next);
    return TimingAdvance(next, step.cues);
  });
  Future<TimingActivity> recover(
    String id,
    int version,
    DateTime at, {
    int? adjustmentMilliseconds,
  }) => _change(
    id,
    version,
    (t) => t.recover(at, adjustmentMilliseconds: adjustmentMilliseconds),
  );
  Future<TimingActivity> stop(
    String id,
    int version,
    DateTime at, {
    required bool confirm,
    bool discard = false,
  }) async {
    if (!confirm) invalid('Stopping/discarding timing requires confirm:true.');
    return _change(id, version, (t) => t.stop(at, discard: discard));
  }

  Future<TimingActivity> _change(
    String id,
    int version,
    TimingActivity Function(TimingActivity) update,
  ) => repository.transaction(() async {
    final current = await show(id);
    if (current.version != version) _conflict();
    final next = update(current);
    await repository.saveTimingActivity(next);
    return next;
  });
  Future<TimingActivity> confirm(
    String id,
    int version,
    int expectedSessionVersion,
    DateTime at,
    Metrics actuals, {
    bool acceptSuggested = false,
  }) => repository.transaction(() async {
    final current = await show(id);
    final request = {
      'expectedSessionVersion': expectedSessionVersion,
      'at': at.toUtc().toIso8601String(),
      'actuals': metricsToJson(actuals),
      'acceptSuggested': acceptSuggested,
    };
    if (current.confirmation != null) {
      if (current.confirmation!['sourceVersion'] != version ||
          canonicalJson(current.confirmation!['request']) !=
              canonicalJson(request))
        _conflict();
      return current;
    }
    if (current.version != version) _conflict();
    if (current.status != 'awaitingConfirmation' ||
        current.effortElapsedMilliseconds == 0)
      invalid('Clock has no completed effort timing to review.');
    final service = StoredTrainingService(repository);
    final session = await service.session(current.sessionId);
    if (session.status != SessionStatus.active ||
        at.isBefore(session.startedAt))
      invalid('Timing confirmation needs an active session and valid time.');
    final duration = Quantity(
      current.effortElapsedMilliseconds.toString(),
      'ms',
    );
    final observations = {current.metric: duration, ...actuals};
    final chosen = observations[current.metric]!;
    if (chosen.dimension != Dimension.duration)
      invalid('Timing observation must be duration.');
    final timing = TimedResult(
      current.id,
      current.metric,
      current.effortElapsedMilliseconds,
      current.termination!,
      mode: chosen.compareTo(duration) == 0 ? 'timer' : 'manual-override',
    );
    final updated = session.replaceSet(
      session
          .set(current.setId)
          .complete(
            observations,
            acceptSuggested: acceptSuggested,
            timingResult: timing,
          ),
    );
    final next = current.confirmed({
      'sourceVersion': current.version,
      'at': at.toUtc().toIso8601String(),
      'request': request,
      'setVersion': updated.set(current.setId).contentVersion,
      'sessionVersion': updated.contentVersion,
      'actuals': metricsToJson(updated.set(current.setId).actuals),
      'timing': timing.toJson(),
    }, at);
    await repository.saveTimingActivity(next);
    await service.edit(session.id, expectedSessionVersion, (_) => updated);
    return next;
  });
}

void validateTimingData(
  List<TimingActivity> timers,
  List<TrainingSession> sessions,
) {
  final bySession = {for (final s in sessions) s.id: s};
  final ids = <String>{};
  var active = 0;
  for (final t in timers) {
    if (!ids.add(t.id)) invalid('Duplicate timing identity.');
    if (t.active) active++;
    final s = bySession[t.sessionId];
    if (s == null) invalid('Timing session is missing.');
    if (t.plan.restOnly) {
      final occurrences = s.revision.definition.plan.occurrences().where(
        (o) => o.id == t.setId,
      );
      if (occurrences.length != 1 ||
          occurrences.single.activity is! Rest ||
          _insideWindow(s, t.setId) ||
          (occurrences.single.activity as Rest).durationSeconds * 1000 !=
              t.plan.restMilliseconds ||
          t.metric != 'duration' ||
          parseInstant(
            t.toJson()['createdAt'],
            'createdAt',
          ).isBefore(s.startedAt) ||
          (t.active && s.status != SessionStatus.active))
        invalid('Rest clock context is inconsistent.');
      continue;
    }
    final set = s.set(t.setId);
    if (_insideWindow(s, t.setId))
      invalid('Timing records for scoped windows are not supported yet.');
    if (set.suggested[t.metric]?.dimension != Dimension.duration ||
        parseInstant(
          t.toJson()['createdAt'],
          'createdAt',
        ).isBefore(s.startedAt) ||
        (t.active &&
            (s.status != SessionStatus.active ||
                set.status != SetStatus.planned)))
      invalid('Timing context is inconsistent.');
    final c = t.confirmation;
    if (c != null) {
      final request = jsonObject(c['request'], 'confirmation request');
      final expected = {
        if (request['acceptSuggested'] == true) ...set.suggested,
        t.metric: Quantity(t.effortElapsedMilliseconds.toString(), 'ms'),
        ...metricsFromJson(request['actuals']),
      };
      set.complete(metricsFromJson(c['actuals']));
      if (canonicalJson(metricsToJson(expected)) !=
              canonicalJson(c['actuals']) ||
          parseInstant(c['at'], 'at').isBefore(s.startedAt))
        invalid('Timing confirmation inputs are inconsistent.');
      if (set.contentVersion < (c['setVersion']! as int) ||
          s.contentVersion < (c['sessionVersion']! as int))
        invalid('Timing confirmation version is ahead of its session.');
      if (set.contentVersion == c['setVersion'] &&
          (set.status != SetStatus.completed ||
              canonicalJson(metricsToJson(set.actuals)) !=
                  canonicalJson(c['actuals']) ||
              canonicalJson(set.timing?.toJson()) !=
                  canonicalJson(c['timing'])))
        invalid('Timing confirmation does not match its result version.');
    }
  }
  if (active > 1) invalid('Only one logical timing activity may be active.');
  final byTimer = {for (final t in timers) t.id: t};
  for (final s in sessions)
    for (final set in s.sets)
      if (set.timing case final result?) {
        final timer = byTimer[result.timerId];
        if (timer == null ||
            timer.sessionId != s.id ||
            timer.setId != set.id ||
            timer.status != 'confirmed' ||
            timer.metric != result.metric ||
            timer.effortElapsedMilliseconds != result.elapsedMilliseconds ||
            timer.termination != result.termination)
          invalid('Timed result has no matching confirmation receipt.');
      }
}

bool _insideWindow(TrainingSession s, String setId) => s
    .revision
    .definition
    .plan
    .nodes
    .whereType<TimeWindow>()
    .any((w) => setId.split('/').contains(w.id));

Never _conflict([
  String message =
      'Timing or session content changed; refresh before retrying.',
]) => throw BodyTmiException('conflict', message);
