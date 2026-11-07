import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';

({TrainingSession session, Map<String, Object?> clock, String occurrenceId})
sessionWindowReviewRequest(
  TrainingSession session,
  Map<String, Object?> request,
) {
  int integer(String key, {int min = 1}) {
    final value = request[key];
    if (value is! int || value < min)
      invalid('$key must be an integer >= $min.');
    return value;
  }

  bool flag(String key) {
    final value = request[key] ?? false;
    if (value is! bool) invalid('$key must be a boolean.');
    return value;
  }

  return const SessionWindowReview().review(
    session,
    request['clock'],
    expectedSessionVersion: integer('expectedSessionVersion'),
    expectedClockVersion: integer('expectedClockVersion'),
    toOccurrence: integer('toOccurrence', min: 0),
    action: requiredString(request, 'action'),
    actuals: metricsFromJson(request['actuals'] ?? <String, Object?>{}),
    acceptSuggested: flag('acceptSuggested'),
    confirm: flag('confirm'),
  );
}

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
