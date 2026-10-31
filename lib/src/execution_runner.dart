import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'timing_runner.dart';

/// Run the current managed clock, then acknowledge a rest boundary only.
/// Effort completion still requires explicit review through an application action.
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
}) async {
  final service = ExecutionService(store);
  var e = await service.show(id);
  if (e.receipts.any((r) => r['requestId'] == requestId)) {
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
  final current = executionPlan(session)[e.cursor];
  final rest = current.activity is Rest;
  if (!rest && session.set(current.id).status != SetStatus.planned) {
    await service.step(id, version, sessionVersion, requestId, at);
    return {
      'execution': await service.view(id),
      'run': null,
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
  if (rest && timer.status == 'completed')
    e = await service.step(id, version, sessionVersion, requestId, at);
  return {
    'execution': await service.view(id),
    'run': result,
    'requiresReview': !rest && timer.status == 'awaitingConfirmation',
    'alreadyApplied': false,
  };
}
