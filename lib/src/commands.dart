import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';

const commandNames = [
  'quantity normalize',
  'template validate',
  'template publish',
  'activity expand',
  'session start',
  'session show',
  'session complete',
  'session skip',
  'session finish',
  'progression evaluate',
  'progression double',
  'measurement trend',
  'measurement resolve',
];

/// JSON adapter only. All training behavior lives in the shared packages.
final class Commands {
  const Commands();

  Map<String, Object?> execute(String command, Map<String, Object?> request) {
    if (request['schemaVersion'] != 1)
      invalid('Request schemaVersion must be 1.');
    void keys(Set<String> keys) =>
        checkKeys(request, {'schemaVersion', ...keys});
    Object? data;
    switch (command) {
      case 'quantity normalize':
        keys({'quantity'});
        data = Quantity.fromJson(request['quantity']).toJson();
      case 'template validate':
        keys({'definition'});
        data = WorkoutDefinition.fromJson(request['definition']).toJson();
      case 'template publish':
        keys({'definition', 'previous'});
        data = WorkoutRevision.publish(
          WorkoutDefinition.fromJson(request['definition']),
          previous: request['previous'] == null
              ? null
              : WorkoutRevision.fromJson(request['previous']),
        ).toJson();
      case 'activity expand':
        keys({'definition'});
        final definition = WorkoutDefinition.fromJson(request['definition']);
        data = [
          for (final occurrence in definition.plan.occurrences())
            {'id': occurrence.id, 'activity': occurrence.activity.toJson()},
        ];
      case 'session start':
        keys({'id', 'revision', 'startedAt', 'history'});
        final history = request['history'] ?? <Object?>[];
        if (history is! List<Object?>) invalid('history must be an array.');
        data = const TrainingService()
            .start(
              sessionId: identifier(request, 'id'),
              revision: WorkoutRevision.fromJson(request['revision']),
              startedAt: parseInstant(request['startedAt'], 'startedAt'),
              history: [for (final item in history) sessionFromJson(item)],
            )
            .toJson();
      case 'session show':
        keys({'session'});
        data = sessionFromJson(request['session']).toJson();
      case 'session complete':
        keys({'session', 'setId', 'actuals', 'acceptSuggested'});
        data = const TrainingService()
            .complete(
              sessionFromJson(request['session']),
              requiredString(request, 'setId'),
              metricsFromJson(request['actuals'] ?? <String, Object?>{}),
              acceptSuggested: _bool(request, 'acceptSuggested'),
            )
            .toJson();
      case 'session skip':
        keys({'session', 'setId', 'confirm'});
        data = const TrainingService()
            .skip(
              sessionFromJson(request['session']),
              requiredString(request, 'setId'),
              confirm: _bool(request, 'confirm'),
            )
            .toJson();
      case 'session finish':
        keys({'session', 'finishedAt'});
        data = sessionFromJson(
          request['session'],
        ).finish(parseInstant(request['finishedAt'], 'finishedAt')).toJson();
      case 'progression evaluate':
        keys({'rule', 'current', 'results', 'state'});
        final state = jsonObject(
          request['state'] ?? <String, Object?>{},
          'state',
        );
        checkKeys(state, {'failedSessions', 'cursor'});
        final failures = state['failedSessions'] ?? 0;
        final cursor = state['cursor'] ?? 0;
        if (failures is! int || cursor is! int)
          invalid('Progression state must use integer counts.');
        data = ThresholdRule.fromJson(request['rule'])
            .evaluate(
              current: metricsFromJson(request['current']),
              results: [
                for (final r in jsonList(request, 'results'))
                  r == null ? null : metricsFromJson(r),
              ],
              failedSessions: failures,
              cursor: cursor,
            )
            .toJson();
      case 'progression double':
        keys({'rule', 'currentSets', 'results', 'state'});
        final state = jsonObject(
          request['state'] ?? <String, Object?>{},
          'state',
        );
        checkKeys(state, {'failedSessions'});
        final failures = state['failedSessions'] ?? 0;
        if (failures is! int) invalid('failedSessions must be an integer.');
        data = DoubleProgressionRule.fromJson(request['rule'])
            .evaluate(
              currentSets: [
                for (final set in jsonList(request, 'currentSets'))
                  metricsFromJson(set),
              ],
              results: [
                for (final result in jsonList(request, 'results'))
                  result == null ? null : metricsFromJson(result),
              ],
              failedSessions: failures,
            )
            .toJson();
      case 'measurement trend':
        keys({'measurements', 'context', 'asOf', 'dailyMode'});
        data = const BodyMassService().trend({
          for (final entry in request.entries)
            if (entry.key != 'schemaVersion') entry.key: entry.value,
        }).toJson();
      case 'measurement resolve':
        keys({
          'measurements',
          'context',
          'asOf',
          'dailyMode',
          'override',
          'staleAfterDays',
          'warnIfStale',
        });
        data = const BodyMassService().resolve({
          for (final entry in request.entries)
            if (entry.key != 'schemaVersion') entry.key: entry.value,
        }).toJson();
      default:
        throw const BodyTmiException('usage', 'Unknown command. Use --help.');
    }
    return {'schemaVersion': 1, 'data': data};
  }

  static bool _bool(Map<String, Object?> json, String key) {
    final value = json[key] ?? false;
    if (value is! bool) invalid('$key must be a boolean.');
    return value;
  }
}
