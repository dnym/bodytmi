import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';

Map<String, Object?> sessionWindowClockRequest(
  TrainingSession session,
  Map<String, Object?> request,
) {
  final action = requiredString(request, 'action');
  const service = SessionWindowClock();
  if (action == 'start') {
    if ([
      'clock',
      'expectedVersion',
      'ownerId',
      'ownerElapsedMilliseconds',
      'toOccurrence',
      'adjustmentMilliseconds',
    ].any(request.containsKey))
      invalid(
        'Starting a session window clock does not take clock action fields.',
      );
    return service.start(session);
  }
  final version = request['expectedVersion'];
  final elapsed = request['ownerElapsedMilliseconds'];
  final destination = request['toOccurrence'];
  final adjustment = request['adjustmentMilliseconds'];
  if (version is! int ||
      version < 1 ||
      (request.containsKey('ownerElapsedMilliseconds') && elapsed is! int) ||
      (request.containsKey('toOccurrence') && destination is! int) ||
      (request.containsKey('adjustmentMilliseconds') && adjustment is! int))
    invalid('Clock versions, samples and occurrence indices must be integers.');
  return service.apply(
    session,
    request['clock'],
    expectedVersion: version,
    action: action,
    ownerId: request.containsKey('ownerId')
        ? identifier(request, 'ownerId')
        : null,
    ownerElapsedMilliseconds: elapsed as int?,
    toOccurrence: destination as int?,
    adjustmentMilliseconds: adjustment as int?,
  );
}
