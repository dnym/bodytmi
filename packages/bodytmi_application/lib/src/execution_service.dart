import 'package:bodytmi_core/bodytmi_core.dart';
import 'canonical_json.dart';
import 'timing_service.dart';
import 'training_repository.dart';
import 'training_service.dart';

final class ExecutionService {
  const ExecutionService(this.repository);
  final TrainingRepository repository;
  Future<WorkoutExecution> show(String id) async =>
      await repository.execution(id) ??
      (throw const BodyTmiException(
        'not_found',
        'Workout execution not found.',
      ));
  Future<WorkoutExecution> start(
    String id,
    String sessionId,
    DateTime at,
  ) => repository.transaction(() async {
    final s = await StoredTrainingService(repository).session(sessionId);
    final plan = executionPlan(s);
    final candidate = WorkoutExecution.create(id, sessionId, at, plan.length);
    final all = await repository.executions();
    final old = all.where((e) => e.id == id).firstOrNull;
    if (old != null) {
      if (old.sessionId != sessionId || old.createdAt != at) _conflict();
      return old;
    }
    if (all.any((e) => e.sessionId == sessionId))
      _conflict('This session already has a traversal.');
    if (s.status != SessionStatus.active || at.isBefore(s.startedAt))
      invalid('Execution needs an active session and valid start time.');
    _validateManagedClocks(candidate, s, await repository.timingActivities());
    await repository.saveExecution(candidate);
    await _prepareRest(candidate, s, at);
    return candidate;
  });

  Future<Map<String, Object?>> view(String id) =>
      repository.transaction(() async {
        final e = await show(id);
        final s = await StoredTrainingService(repository).session(e.sessionId);
        final plan = executionPlan(s);
        final current = e.complete ? null : plan[e.cursor];
        final kind = current?.activity is Rest ? 'rest' : 'effort';
        final clock = e.complete
            ? null
            : await repository.timingActivity(e.clockId(kind));
        if (clock != null &&
            (clock.sessionId != s.id ||
                clock.setId != current!.id ||
                clock.plan.restOnly != (kind == 'rest')))
          invalid(
            'Managed execution clock identity belongs to another occurrence.',
          );
        return {
          ...e.toJson(),
          'version': e.version,
          'cursor': e.cursor,
          'status': e.complete ? 'completed' : 'active',
          'sessionContentVersion': s.contentVersion,
          'groups': [
            for (final group in activityGroups(
              s.revision.definition.plan,
              containing: e.cursor,
            ))
              group.toJson(),
          ],
          'current': current == null
              ? null
              : {
                  'id': current.id,
                  'activity': current.activity.toJson(),
                  if (current.activity is Effort)
                    'set': s.set(current.id).toJson(),
                },
          'timer': clock == null
              ? null
              : {
                  ...clock.toViewJson(),
                  'requiresRecovery': clock.status == 'running',
                },
        };
      });
  Future<TimingActivity> time(
    String id,
    int version,
    DateTime at, {
    String? metric,
    TimingPlan? plan,
  }) => repository.transaction(() async {
    final e = await show(id);
    if (e.version != version || e.complete) _conflict();
    final s = await StoredTrainingService(repository).session(e.sessionId);
    if (s.status != SessionStatus.active) invalid('Session is finalized.');
    final occurrence = executionPlan(s)[e.cursor];
    final rest = occurrence.activity is Rest;
    if (rest && (occurrence.activity as Rest).isManual) {
      invalid('Manual rest has no duration clock; use execution advance.');
    }
    final clockId = e.clockId(rest ? 'rest' : 'effort');
    final old = await repository.timingActivity(clockId);
    if (old != null &&
        (old.sessionId != s.id ||
            old.setId != occurrence.id ||
            old.plan.restOnly != rest ||
            (!rest && old.plan.restMilliseconds != 0)))
      _conflict('Managed clock identity is already used by another context.');
    if (rest) {
      if (metric != null || plan != null)
        invalid(
          'Authored rest duration cannot be replaced by an effort timing plan.',
        );
      if (old != null) return old;
      return TimingService(
        repository,
      ).startRest(clockId, s.id, occurrence.id, at);
    }
    if (old != null) {
      if ((metric != null && old.metric != metric) ||
          (plan != null &&
              canonicalJson(old.plan.toJson()) != canonicalJson(plan.toJson())))
        _conflict();
      return old;
    }
    final set = s.set(occurrence.id);
    final selected =
        metric ??
        s.revision.definition.slot(set.slotId).timing?.metric ??
        (set.suggested.entries
                    .where((v) => v.value.dimension == Dimension.duration)
                    .length ==
                1
            ? set.suggested.entries
                  .singleWhere((v) => v.value.dimension == Dimension.duration)
                  .key
            : null);
    if (selected == null)
      invalid(
        'Select exactly one configured duration metric to time this effort.',
      );
    final chosen = plan ?? timingPlanFor(s, set.id, selected);
    if (!supportsTimingMetric(set, selected, chosen))
      invalid('Timing metric is incompatible with the selected plan.');
    if (chosen.restOnly || chosen.restMilliseconds != 0)
      invalid(
        'Traversal effort clocks cannot add rest outside the authored rest occurrences.',
      );
    return TimingService(
      repository,
    ).start(clockId, s.id, set.id, selected, chosen, at);
  });

  /// One explicit operation acknowledges the current occurrence and prepares any
  /// following rest. Request identity makes retries independent of later edits.
  Future<WorkoutExecution> step(
    String id,
    int version,
    int sessionVersion,
    String requestId,
    DateTime at, {
    String action = 'advance',
    Metrics actuals = const {},
    bool acceptSuggested = false,
    bool confirm = false,
    String? timerId,
    int? timerVersion,
  }) => repository.transaction(() async {
    identifier({'id': requestId}, 'id');
    if (!{'advance', 'complete', 'confirm', 'skip'}.contains(action))
      invalid('Invalid execution operation.');
    final request = <String, Object?>{
      'action': action,
      'version': version,
      'sessionVersion': sessionVersion,
      'at': at.toUtc().toIso8601String(),
      if (action == 'complete' || action == 'confirm')
        'actuals': metricsToJson(actuals),
      if (action == 'complete' || action == 'confirm')
        'acceptSuggested': acceptSuggested,
      if (action == 'skip') 'confirm': confirm,
      if (action == 'confirm') ...{
        'timerId': timerId,
        'timerVersion': timerVersion,
      },
    };
    var e = await show(id);
    final receipt = e.receipts
        .where((r) => r['requestId'] == requestId)
        .firstOrNull;
    if (receipt != null) {
      if (canonicalJson(receipt['request']) != canonicalJson(request))
        _conflict();
      return e;
    }
    if (e.version != version || e.complete) _conflict();
    final training = StoredTrainingService(repository);
    var s = await training.session(e.sessionId);
    if (s.contentVersion != sessionVersion) _conflict();
    if (s.status != SessionStatus.active || at.isBefore(s.startedAt))
      invalid('Invalid execution session/time.');
    final occurrence = executionPlan(s)[e.cursor];
    final rest = occurrence.activity is Rest;
    String? sourceTimer;
    if (action == 'skip') {
      if (!confirm)
        invalid('Skipping an execution occurrence requires confirm:true.');
      final clocks = (await repository.timingActivities())
          .where(
            (t) => t.sessionId == s.id && t.setId == occurrence.id && t.active,
          )
          .toList();
      for (final t in clocks)
        await TimingService(
          repository,
        ).stop(t.id, t.version, at, confirm: true, discard: true);
      if (!rest)
        s = await training.edit(
          s.id,
          s.contentVersion,
          (s) => const TrainingService().skip(s, occurrence.id, confirm: true),
        );
      if (rest)
        sourceTimer = (await repository.timingActivities())
            .where((t) => t.id == e.clockId('rest'))
            .firstOrNull
            ?.id;
    } else if (rest) {
      if (action != 'advance')
        invalid('Rest does not contain effort results to complete.');
      if (!(occurrence.activity as Rest).isManual) {
        final clock = (await repository.timingActivities())
            .where((t) => t.id == e.clockId('rest'))
            .firstOrNull;
        if (clock?.status != 'completed')
          invalid('Run the rest clock to its boundary or explicitly skip it.');
        sourceTimer = clock!.id;
      }
    } else {
      if (action == 'complete')
        s = await training.edit(
          s.id,
          s.contentVersion,
          (s) => const TrainingService().complete(
            s,
            occurrence.id,
            actuals,
            acceptSuggested: acceptSuggested,
          ),
        );
      if (action == 'confirm') {
        if (timerId == null || timerVersion == null)
          invalid('Timing confirmation requires timerId and timerVersion.');
        final t = await TimingService(repository).show(timerId);
        if (t.sessionId != s.id || t.setId != occurrence.id || t.plan.restOnly)
          invalid('Timer belongs to another occurrence.');
        await TimingService(repository).confirm(
          timerId,
          timerVersion,
          s.contentVersion,
          at,
          actuals,
          acceptSuggested: acceptSuggested,
        );
        s = await training.session(s.id);
      }
      if (s.set(occurrence.id).status == SetStatus.planned)
        invalid('Confirm or explicitly skip effort before advancing.');
      sourceTimer = s.set(occurrence.id).timing?.timerId;
    }
    e = e.append({
      'ordinal': e.cursor,
      'path': occurrence.id,
      'kind': rest ? 'rest' : 'effort',
      'requestId': requestId,
      'request': request,
      'at': at.toUtc().toIso8601String(),
      if (!rest) 'setVersion': s.set(occurrence.id).contentVersion,
      if (!rest) 'resultStatus': s.set(occurrence.id).status.name,
      if (sourceTimer != null) 'timerId': sourceTimer,
    });
    await repository.saveExecution(e);
    await _prepareRest(e, s, at);
    return e;
  });
  Future<void> _prepareRest(
    WorkoutExecution e,
    TrainingSession s,
    DateTime at,
  ) async {
    if (!e.complete) {
      final current = executionPlan(s)[e.cursor].activity;
      if (current is Rest && !current.isManual) await time(e.id, e.version, at);
    }
  }

  /// Skip only the unacknowledged remainder of a structural occurrence. Existing
  /// results are preserved; one transaction records every boundary and next rest.
  Future<WorkoutExecution> skipGroup(
    String id,
    int version,
    int sessionVersion,
    String requestId,
    String groupPath,
    DateTime at, {
    required bool confirm,
  }) => repository.transaction(() async {
    identifier({'id': requestId}, 'id');
    if (requestId.length > 64)
      invalid('Group request ID exceeds 64 characters.');
    if (!confirm) invalid('Skipping a group requires confirm:true.');
    final e = await show(id);
    final training = StoredTrainingService(repository);
    var s = await training.session(e.sessionId);
    final group = activityGroups(
      s.revision.definition.plan,
      paths: {groupPath},
    ).where((g) => g.path == groupPath).firstOrNull;
    if (group == null) invalid('Unknown structural group occurrence.');
    final request = <String, Object?>{
      'action': 'skip-group',
      'version': version,
      'sessionVersion': sessionVersion,
      'at': at.toUtc().toIso8601String(),
      'confirm': true,
      'groupPath': groupPath,
      'groupStart': version - 1,
      'groupEnd': group.end,
      'groupRequestId': requestId,
    };
    final old = e.receipts
        .where((r) => r['requestId'] == requestId)
        .firstOrNull;
    if (old != null) {
      if (canonicalJson(old['request']) != canonicalJson(request)) _conflict();
      return e;
    }
    if (e.version != version ||
        e.complete ||
        s.contentVersion != sessionVersion)
      _conflict();
    if (s.status != SessionStatus.active ||
        at.isBefore(s.startedAt) ||
        !group.contains(e.cursor))
      invalid('Group does not contain the active cursor.');
    final plan = executionPlan(s);
    final remaining = plan.sublist(e.cursor, group.end);
    final paths = remaining.map((o) => o.id).toSet();
    final usedRequests = e.receipts.map((r) => r['requestId']).toSet();
    for (var i = e.cursor; i < group.end; i++) {
      if (usedRequests.contains(_groupRequestId(requestId, e.cursor, i)))
        _conflict('A group child request ID is already used.');
    }
    final timers = await repository.timingActivities();
    for (final t in timers) {
      if (t.sessionId == s.id &&
          paths.contains(t.setId) &&
          (t.active || t.status == 'awaitingConfirmation')) {
        await TimingService(
          repository,
        ).stop(t.id, t.version, at, confirm: true, discard: true);
      }
    }
    final planned = s.sets
        .where(
          (set) => paths.contains(set.id) && set.status == SetStatus.planned,
        )
        .map((set) => set.id)
        .toSet();
    if (planned.isNotEmpty) {
      s = await training.edit(
        s.id,
        s.contentVersion,
        (current) => TrainingSession(
          id: current.id,
          revision: current.revision,
          startedAt: current.startedAt,
          sets: [
            for (final set in current.sets)
              planned.contains(set.id) ? set.skip(confirm: true) : set,
          ],
          status: current.status,
          finishedAt: current.finishedAt,
          contentVersion: current.contentVersion + 1,
          bodyMassInputs: current.bodyMassInputs,
          initialBodyMassOverrides: current.initialBodyMassOverrides,
          derivedPlanInput: current.derivedPlanInput,
        ),
      );
    }
    final receipts = <Map<String, Object?>>[...e.receipts];
    for (var i = e.cursor; i < group.end; i++) {
      final o = plan[i];
      final set = o.activity is Effort ? s.set(o.id) : null;
      receipts.add({
        'ordinal': i,
        'path': o.id,
        'kind': set == null ? 'rest' : 'effort',
        'requestId': _groupRequestId(requestId, e.cursor, i),
        'request': {...request, 'version': i + 1},
        'at': request['at'],
        if (set != null) ...{
          'setVersion': set.contentVersion,
          'resultStatus': set.status.name,
          if (set.timing != null) 'timerId': set.timing!.timerId,
        },
      });
    }
    final next = WorkoutExecution.fromJson({
      ...e.toJson(),
      'receipts': receipts,
    });
    await repository.saveExecution(next);
    await _prepareRest(next, s, at);
    return next;
  });
}

String _groupRequestId(String id, int start, int ordinal) =>
    ordinal == start ? id : '$id-group-$ordinal';

void _validateManagedClocks(
  WorkoutExecution e,
  TrainingSession s,
  List<TimingActivity> timers,
) {
  final byId = {for (final t in timers) t.id: t};
  final plan = executionPlan(s);
  for (var i = 0; i < plan.length; i++) {
    final rest = plan[i].activity is Rest;
    final t = byId['execution-${e.id}-${rest ? 'rest' : 'effort'}-$i'];
    if (t != null &&
        ((plan[i].activity is Rest && (plan[i].activity as Rest).isManual) ||
            t.sessionId != s.id ||
            t.setId != plan[i].id ||
            t.plan.restOnly != rest ||
            (!rest && t.plan.restMilliseconds != 0)))
      invalid('Managed execution clock identity belongs to another context.');
  }
}

List<ActivityOccurrence> executionPlan(TrainingSession s) {
  if (s.revision.definition.plan.nodes.any((n) => n is TimeWindow))
    invalid('Scoped window traversal is not implemented yet.');
  final plan = s.revision.definition.plan.occurrences().toList();
  if (plan.length > 10000 ||
      plan.map((o) => o.id).toSet().length != plan.length)
    invalid(
      'Execution requires at most 10000 uniquely identified occurrences.',
    );
  for (final o in plan)
    if (o.activity case Rest(:final durationSeconds, :final isManual)) {
      if (!isManual && (durationSeconds! < 1 || durationSeconds > 86400))
        invalid('Execution rest duration exceeds the 24-hour clock limit.');
    }
  return plan;
}

void validateExecutionData(
  List<WorkoutExecution> executions,
  List<TrainingSession> sessions,
  List<TimingActivity> timers,
) {
  final sessionMap = {for (final s in sessions) s.id: s},
      timerMap = {for (final t in timers) t.id: t};
  final ids = <String>{}, owners = <String>{};
  for (final e in executions) {
    final s = sessionMap[e.sessionId];
    if (s == null || !ids.add(e.id) || !owners.add(e.sessionId))
      invalid('Duplicate or orphan workout execution.');
    final plan = executionPlan(s);
    _validateManagedClocks(e, s, timers);
    final groups = {
      for (final g in activityGroups(
        s.revision.definition.plan,
        paths: {
          for (final r in e.receipts)
            if (jsonObject(r['request'], 'execution request')['action'] ==
                'skip-group')
              requiredString(
                jsonObject(r['request'], 'execution request'),
                'groupPath',
              ),
        },
      ))
        g.path: g,
    };
    if (plan.length != e.occurrenceCount ||
        e.createdAt.isBefore(s.startedAt) ||
        (s.status == SessionStatus.finalized && !e.complete))
      invalid('Execution plan/context mismatch.');
    for (final r in e.receipts) {
      final ordinal = r['ordinal']! as int;
      final o = plan[ordinal];
      final rest = o.activity is Rest;
      final request = jsonObject(r['request'], 'execution request');
      final action = request['action'];
      final groupSkip = action == 'skip-group';
      final keys = {
        'action',
        'version',
        'sessionVersion',
        'at',
        if (action == 'skip' || groupSkip) 'confirm',
        if (groupSkip) ...{
          'groupPath',
          'groupStart',
          'groupEnd',
          'groupRequestId',
        },
        if (action == 'complete' || action == 'confirm') ...{
          'actuals',
          'acceptSuggested',
        },
        if (action == 'confirm') ...{'timerId', 'timerVersion'},
      };
      checkKeys(request, keys);
      if (!{
            'advance',
            'complete',
            'confirm',
            'skip',
            'skip-group',
          }.contains(action) ||
          request['version'] != ordinal + 1 ||
          request['at'] != r['at'] ||
          request['sessionVersion'] is! int ||
          (request['sessionVersion']! as int) < 1 ||
          (request['sessionVersion']! as int) > s.contentVersion ||
          parseInstant(r['at'], 'at').isBefore(s.startedAt) ||
          r['path'] != o.id ||
          r['kind'] != (rest ? 'rest' : 'effort') ||
          ((action == 'skip' || groupSkip) && request['confirm'] != true))
        invalid('Execution receipt context is inconsistent.');
      if (groupSkip) {
        final start = request['groupStart'], end = request['groupEnd'];
        final group = groups[request['groupPath']];
        final batchId = identifier(request, 'groupRequestId');
        if (batchId.length > 64 ||
            start is! int ||
            end is! int ||
            start < 0 ||
            start > ordinal ||
            ordinal >= end ||
            end > e.cursor ||
            group == null ||
            !group.contains(start) ||
            end != group.end ||
            r['requestId'] != _groupRequestId(batchId, start, ordinal))
          invalid('Group skip bounds or request identity are inconsistent.');
        final first = jsonObject(e.receipts[start]['request'], 'group request');
        if (canonicalJson({...first, 'version': ordinal + 1}) !=
            canonicalJson(request))
          invalid(
            'Group skip must retain one request across its entire range.',
          );
        if (ordinal == start) {
          for (var i = start; i < end; i++) {
            final child = jsonObject(
              e.receipts[i]['request'],
              'group child request',
            );
            if (canonicalJson({...request, 'version': i + 1}) !=
                canonicalJson(child))
              invalid(
                'Group skip receipts must cover the entire remainder atomically.',
              );
          }
        }
      }
      if (rest) {
        if (action != 'skip' && action != 'advance' && !groupSkip)
          invalid('Rest receipt cannot certify effort.');
        final timer = r['timerId'] == null ? null : timerMap[r['timerId']];
        if ((o.activity as Rest).isManual
            ? r.containsKey('timerId')
            : groupSkip
            ? r.containsKey('timerId')
            : (timer == null ||
                  !timer.plan.restOnly ||
                  timer.id != 'execution-${e.id}-rest-$ordinal' ||
                  timer.sessionId != s.id ||
                  timer.setId != o.id ||
                  (action == 'advance'
                      ? timer.status != 'completed'
                      : timer.active)))
          invalid('Rest advancement lacks a completed clock.');
      } else {
        final set = s.set(o.id);
        if (set.status == SetStatus.planned ||
            set.contentVersion < (r['setVersion']! as int) ||
            (set.contentVersion == r['setVersion'] &&
                set.status.name != r['resultStatus']))
          invalid('Execution result acknowledgment is inconsistent.');
        if ((action == 'complete' || action == 'confirm') &&
            r['resultStatus'] != 'completed')
          invalid('Completion receipt requires confirmed results.');
        if (action == 'skip' && r['resultStatus'] != 'skipped')
          invalid('Skip receipt requires a skipped occurrence.');
        if (r['timerId'] != null) {
          final timer = timerMap[r['timerId']];
          if (timer == null ||
              timer.sessionId != s.id ||
              timer.setId != o.id ||
              timer.status != 'confirmed' ||
              timer.plan.restOnly)
            invalid('Effort acknowledgment has an unrelated timing source.');
        }
        if (action == 'complete' || action == 'confirm') {
          if (request['acceptSuggested'] is! bool)
            invalid('Completion request requires acceptSuggested.');
          final actuals = metricsFromJson(request['actuals']);
          if (action == 'complete' && set.contentVersion == r['setVersion']) {
            final expected = {
              if (request['acceptSuggested'] == true) ...set.suggested,
              ...actuals,
            };
            if (canonicalJson(metricsToJson(expected)) !=
                canonicalJson(metricsToJson(set.actuals)))
              invalid(
                'Completion receipt inputs do not match their result version.',
              );
          }
        }
        if (action == 'confirm') {
          final t = timerMap[request['timerId']];
          if (t == null ||
              t.confirmation == null ||
              t.sessionId != s.id ||
              t.setId != o.id ||
              t.confirmation!['sourceVersion'] != request['timerVersion'] ||
              t.confirmation!['setVersion'] != r['setVersion'] ||
              r['timerId'] != t.id ||
              canonicalJson(t.confirmation!['request']) !=
                  canonicalJson({
                    'expectedSessionVersion': request['sessionVersion'],
                    'at': request['at'],
                    'actuals': request['actuals'],
                    'acceptSuggested': request['acceptSuggested'],
                  }))
            invalid('Execution timing receipt is inconsistent.');
        }
      }
    }
    if (!e.complete &&
        plan[e.cursor].activity is Rest &&
        !(plan[e.cursor].activity as Rest).isManual) {
      final t = timerMap[e.clockId('rest')];
      if (t == null ||
          !t.plan.restOnly ||
          t.sessionId != s.id ||
          t.setId != plan[e.cursor].id)
        invalid('Current execution rest has no matching clock.');
    }
  }
}

Never _conflict([
  String message = 'Execution or session changed; refresh before retrying.',
]) => throw BodyTmiException('conflict', message);
