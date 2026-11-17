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
    String? metric,
    TimingPlan? plan,
    DateTime at,
  ) => repository.transaction(() async {
    final s = await StoredTrainingService(repository).session(sessionId);
    final selected = timingMetricFor(s, setId, metric);
    final resolved = plan ?? timingPlanFor(s, setId, selected);
    if (resolved.restOnly)
      invalid('Use the rest timing operation for a rest occurrence.');
    final next = TimingActivity.create(
      id: id,
      sessionId: sessionId,
      setId: setId,
      metric: selected,
      plan: resolved,
      at: at,
    );
    final existing = await repository.timingActivity(id);
    if (existing != null) {
      if (existing.sessionId != sessionId ||
          existing.setId != setId ||
          existing.metric != selected ||
          existing.toJson()['createdAt'] != next.toJson()['createdAt'] ||
          canonicalJson(existing.plan.toJson()) !=
              canonicalJson(resolved.toJson()))
        _conflict();
      return existing;
    }
    if ((await repository.activeTimingActivities()).isNotEmpty ||
        (await repository.windowCheckpoints()).any((c) => c.reserved) ||
        (await repository.repeatCheckpoints()).any((c) => c.reserved))
      _conflict(
        'Another timing activity is active; explicitly stop/discard it first.',
      );
    if (_insideWindow(s, setId))
      invalid('Per-set timing cannot execute scoped time windows yet.');
    if (s.status != SessionStatus.active ||
        s.set(setId).status != SetStatus.planned ||
        at.isBefore(s.startedAt) ||
        !supportsTimingMetric(s.set(setId), selected, resolved))
      invalid(
        'Timing needs a compatible duration metric in an active planned set and a valid start time.',
      );
    await _validateAgainstExecutions(next, s);
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
    final occurrence = s.definition.plan
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
    if (rest.isManual)
      invalid('Manual rest has no duration clock; use execution advance.');
    final plan = TimingPlan.fromJson({
      'restOnly': true,
      'effortMilliseconds': 0,
      'restMilliseconds': rest.durationSeconds! * 1000,
      if (rest.maxDurationSeconds != null)
        'restMaximumMilliseconds': rest.maxDurationSeconds! * 1000,
    });
    final existing = await repository.timingActivity(id);
    if (existing != null) {
      if (existing.sessionId != sessionId ||
          existing.setId != occurrenceId ||
          !existing.plan.restOnly ||
          existing.toJson()['createdAt'] != at.toUtc().toIso8601String())
        _conflict();
      return existing;
    }
    if ((await repository.activeTimingActivities()).isNotEmpty ||
        (await repository.windowCheckpoints()).any((c) => c.reserved) ||
        (await repository.repeatCheckpoints()).any((c) => c.reserved))
      _conflict('Another timing activity is active.');
    final next = TimingActivity.create(
      id: id,
      sessionId: sessionId,
      setId: occurrenceId,
      metric: 'duration',
      plan: plan,
      at: at,
    );
    await _validateAgainstExecutions(next, s);
    await repository.saveTimingActivity(next);
    return next;
  });

  /// A new clock can only conflict with its own session's traversal or with
  /// the execution its ID names as a managed clock (possibly of another
  /// session); the rest of history is unaffected.
  Future<void> _validateAgainstExecutions(
    TimingActivity next,
    TrainingSession s,
  ) async {
    final executions = {
      for (final e in await repository.executions(sessionId: s.id)) e.id: e,
    };
    final sessions = {s.id: s};
    final owner = managedClockExecution(next.id);
    if (owner != null && !executions.containsKey(owner)) {
      final e = await repository.execution(owner);
      if (e != null) {
        executions[e.id] = e;
        sessions[e.sessionId] ??= await StoredTrainingService(
          repository,
        ).session(e.sessionId);
      }
    }
    final clocks = {
      for (final sessionId in sessions.keys)
        for (final t in await sessionClocks(repository, sessionId, [
          for (final e in executions.values)
            if (e.sessionId == sessionId) e.id,
        ]))
          t.id: t,
    };
    validateExecutionData(
      executions.values.toList(),
      sessions.values.toList(),
      [...clocks.values, next],
    );
  }

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
    return TimingAdvance(
      next,
      action == 'pause' && next.plan.tempo != null ? const [] : step.cues,
    );
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
    final duration = measuredDuration(
      session,
      session.set(current.setId),
      current.metric,
      current.effortElapsedMilliseconds,
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

String timingMetricFor(TrainingSession session, String setId, String? metric) {
  if (metric != null) return metric;
  final set = session.set(setId);
  final declared = session.definition.slot(set.slotId).timing?.metric;
  if (declared != null) return declared;
  final durationMetrics = set.suggested.entries
      .where((entry) => entry.value.dimension == Dimension.duration)
      .map((entry) => entry.key)
      .toList();
  if (durationMetrics.length != 1)
    invalid(
      'Select exactly one configured duration metric to time this effort.',
    );
  return durationMetrics.single;
}

TimingPlan timingPlanFor(TrainingSession session, String setId, String metric) {
  final set = session.set(setId);
  final slot = session.definition.slot(set.slotId);
  final defaults = slot.timing;
  final TimingPlan plan;
  if (defaults?.metric == metric) {
    plan = defaults!.resolve(set.suggested);
  } else {
    final duration = set.suggested[metric];
    if (duration == null) invalid('Timing metric is not configured.');
    plan = TimingPlan.fromDuration(duration);
  }
  // A tempo lever prescribes the planned setting's tempo for this set.
  if (slot.tempoLever == null) return plan;
  return TimingPlan.fromJson({
    ...plan.toJson(),
    'tempo': slot.tempoFor(set.settings)!.toJson(),
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
    if (t.isPractice) continue; // validated with practice sessions
    final s = bySession[t.sessionId];
    if (s == null) invalid('Timing session is missing.');
    if (t.plan.restOnly) {
      final occurrences = s.definition.plan.occurrences().where(
        (o) => o.id == t.setId,
      );
      if (occurrences.length != 1 ||
          occurrences.single.activity is! Rest ||
          _insideWindow(s, t.setId) ||
          (occurrences.single.activity as Rest).isManual ||
          (occurrences.single.activity as Rest).durationSeconds! * 1000 !=
              t.plan.restMilliseconds ||
          switch ((occurrences.single.activity as Rest).maxDurationSeconds) {
                final max? => max * 1000,
                null => null,
              } !=
              t.plan.restMaximumMilliseconds ||
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
    if (!supportsTimingMetric(set, t.metric, t.plan) ||
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
        t.metric: measuredDuration(
          s,
          set,
          t.metric,
          t.effortElapsedMilliseconds,
        ),
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

/// Unplanned timing must be explicit and cannot collide with another metric.
/// A clock-measured duration, written in the unit the set's target (or the
/// slot target) for [metric] uses, so a 300 s interval reads in seconds.
/// Minutes are used only when exact; otherwise, and without a target,
/// seconds. The canonical value is always the exact measured milliseconds.
Quantity measuredDuration(
  TrainingSession session,
  TrainingSet set,
  String metric,
  int milliseconds,
) {
  final unit =
      (set.suggested[metric] ??
              session.definition.slot(set.slotId).targets[metric])
          ?.enteredUnit;
  if (unit == Unit.ms) return Quantity('$milliseconds', 'ms');
  if (unit == Unit.min && milliseconds % 60000 == 0)
    return Quantity('${milliseconds ~/ 60000}', 'min');
  final whole = milliseconds ~/ 1000;
  final fraction = (milliseconds % 1000)
      .toString()
      .padLeft(3, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return Quantity(fraction.isEmpty ? '$whole' : '$whole.$fraction', 's');
}

bool supportsTimingMetric(TrainingSet set, String metric, TimingPlan plan) {
  final target = set.suggested[metric];
  if (!plan.unplannedDuration) return target?.dimension == Dimension.duration;
  return target == null &&
      !set.maxEffortMetrics.contains(metric) &&
      (set.criteria[metric] == null ||
          set.criteria[metric]!.unit.dimension == Dimension.duration);
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
