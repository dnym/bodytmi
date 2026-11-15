import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'timing_runner.dart';

/// Run the current managed clock, then acknowledge a rest boundary. Effort
/// completion still requires explicit review, unless the slot opted into
/// `confirmOnTarget` and the full target duration was reached.
///
/// With [continuous], keep walking: each acknowledged occurrence starts the
/// next one, until something needs input (a review, an untimed effort, a
/// manual rest, an AMRAP block), Ctrl-C, the optional time budget, or the end
/// of the workout. Later steps use derived request IDs `<requestId>-<n>`.
Future<Map<String, Object?>> runExecution(
  TrainingStore store,
  String id,
  int version,
  int sessionVersion,
  String requestId,
  DateTime at, {
  String? metric,
  TimingPlan? plan,
  int? runForMilliseconds,
  bool stream = false,
  bool continuous = false,
}) async {
  if (!continuous)
    return _runOnce(
      store,
      id,
      version,
      sessionVersion,
      requestId,
      at,
      metric: metric,
      plan: plan,
      runForMilliseconds: runForMilliseconds,
      stream: stream,
    );
  final service = ExecutionService(store);
  final budget = Stopwatch()..start();
  final runs = <Map<String, Object?>>[];
  Map<String, Object?> last;
  var n = 0;
  while (true) {
    final remaining = runForMilliseconds == null
        ? null
        : runForMilliseconds - budget.elapsedMilliseconds;
    final before = await service.show(id);
    final session = (await store.session(before.sessionId))!;
    last = await _runOnce(
      store,
      id,
      n == 0 ? version : before.version,
      n == 0 ? sessionVersion : session.contentVersion,
      n == 0 ? requestId : '$requestId-$n',
      n == 0 ? at : DateTime.now().toUtc(),
      metric: n == 0 ? metric : null,
      plan: n == 0 ? plan : null,
      runForMilliseconds: remaining,
      stream: stream,
      stopIfInputNeeded: n > 0,
    );
    n++;
    if (last['run'] != null) runs.add(last['run']! as Map<String, Object?>);
    final after = await service.show(id);
    final interrupted =
        (last['run'] as Map<String, Object?>?)?['interrupted'] == true;
    if (after.complete ||
        after.cursor == before.cursor ||
        interrupted ||
        last['needsInput'] == true ||
        (remaining != null &&
            budget.elapsedMilliseconds >= runForMilliseconds!))
      break;
  }
  return {...last, 'continuous': true, 'steps': n, 'runs': runs};
}

Future<Map<String, Object?>> _runOnce(
  TrainingStore store,
  String id,
  int version,
  int sessionVersion,
  String requestId,
  DateTime at, {
  String? metric,
  TimingPlan? plan,
  int? runForMilliseconds,
  bool stream = false,
  bool stopIfInputNeeded = false,
}) async {
  final service = ExecutionService(store);
  var e = await service.show(id);
  final applied = e.receipts
      .where((r) => r['requestId'] == requestId)
      .firstOrNull;
  if (applied != null) {
    // A retried rest acknowledgment is checked as the same request; an
    // automatic confirmation is identified by its request ID alone.
    if (jsonObject(applied['request'], 'request')['action'] == 'advance')
      await service.step(id, version, sessionVersion, requestId, at);
    return {
      'execution': await service.view(id),
      'run': null,
      'alreadyApplied': true,
    };
  }
  final session = (await store.session(e.sessionId))!;
  if (e.version != version || session.contentVersion != sessionVersion)
    throw const BodyTmiException('conflict', 'Execution or session changed.');
  if (e.complete) invalid('Workout traversal is complete.');
  final current = orderedPlan(session, e)[e.cursor];
  final rest = current.activity is Rest;
  if (!rest &&
      current.activity is Effort &&
      session.set(current.id).status != SetStatus.planned) {
    await service.step(id, version, sessionVersion, requestId, at);
    return {
      'execution': await service.view(id),
      'run': null,
      'alreadyApplied': false,
    };
  }
  if (stopIfInputNeeded && _needsInput(session, current)) {
    return {
      'execution': await service.view(id),
      'run': null,
      'needsInput': true,
      'alreadyApplied': false,
    };
  }
  var timer = await service.time(id, version, at, metric: metric, plan: plan);
  Map<String, Object?>? result;
  if (timer.active) {
    result = await runTiming(
      store,
      timer.id,
      timer.version,
      runForMilliseconds: runForMilliseconds,
      stream: stream,
    );
    timer = await TimingService(store).show(timer.id);
  } else if (timer.status == 'discarded')
    invalid(
      'This clock was discarded; explicitly skip the occurrence or review another timing attempt.',
    );
  var confirmed = false;
  if (rest && timer.status == 'completed') {
    e = await service.step(id, version, sessionVersion, requestId, at);
  } else if (!rest &&
      timer.status == 'awaitingConfirmation' &&
      timer.termination == 'target' &&
      _confirmsOnTarget(session, current.id, timer.metric)) {
    e = await service.step(
      id,
      version,
      sessionVersion,
      requestId,
      at,
      action: 'confirm',
      acceptSuggested: true,
      timerId: timer.id,
      timerVersion: timer.version,
    );
    confirmed = true;
  }
  return {
    'execution': await service.view(id),
    'run': result,
    'requiresReview':
        !rest && !confirmed && timer.status == 'awaitingConfirmation',
    if (confirmed) 'confirmedOnTarget': true,
    'alreadyApplied': false,
  };
}

bool _confirmsOnTarget(TrainingSession session, String setId, String metric) {
  final timing = session.definition.slot(session.set(setId).slotId).timing;
  return timing != null && timing.confirmOnTarget && timing.metric == metric;
}

/// Whether continuing would need the person: anything but a timed rest or
/// an effort whose slot confirms on reaching its target.
bool _needsInput(TrainingSession session, ActivityOccurrence occurrence) =>
    switch (occurrence.activity) {
      Rest(:final isManual) => isManual,
      Effort() => () {
        final timing = session.definition
            .slot(session.set(occurrence.id).slotId)
            .timing;
        return timing == null || !timing.confirmOnTarget;
      }(),
      _ => true,
    };
