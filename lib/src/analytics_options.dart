import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_application/bodytmi_application.dart';

Map<String, Object?> roleProgressionPreview(
  TrainingSession session,
  Map<String, Object?> request,
) {
  final state = jsonObject(request['state'] ?? <String, Object?>{}, 'state');
  checkKeys(state, {'failedSessions', 'cursor'});
  final failures = state['failedSessions'] ?? 0;
  final cursor = state['cursor'] ?? 0;
  if (failures is! int || cursor is! int)
    invalid('Progression state must use integer counts.');
  final kind = request.containsKey('ruleType')
      ? requiredString(request, 'ruleType')
      : 'double';
  if (kind == 'double' && state.containsKey('cursor'))
    invalid('Double progression has no cursor.');
  return const RoleProgressionPreview().evaluate(
    session: session,
    slotId: identifier(request, 'slotId'),
    role: request.containsKey('role')
        ? requiredString(request, 'role')
        : 'work',
    ruleType: kind,
    rule: jsonObject(request['rule'], 'rule'),
    failedSessions: failures,
    cursor: cursor,
  );
}

List<String>? analyticsRoles(Map<String, Object?> request) =>
    !request.containsKey('roles')
    ? null
    : [
        for (final role in jsonList(request, 'roles'))
          if (role is String)
            role
          else
            invalid('roles must contain effort roles.'),
      ];

List<String> analyticsSums(Map<String, Object?> request) => [
  for (final metric
      in request.containsKey('sumMetrics')
          ? jsonList(request, 'sumMetrics')
          : const <Object?>[])
    if (metric is String)
      metric
    else
      invalid('sumMetrics must contain metric IDs.'),
];

Map<String, String> analyticsBindings(Map<String, Object?> request) => {
  for (final entry in jsonObject(
    request['runBySession'] ?? <String, Object?>{},
    'runBySession',
  ).entries)
    identifier({'id': entry.key}, 'id'): identifier({'id': entry.value}, 'id'),
};

/// Parses `targets: {metric: {source, value?}}` for substitution requests.
Map<String, Map<String, Object?>> substitutionTargets(Object? input) {
  if (input == null) return const {};
  final json = jsonObject(input, 'targets');
  return {
    for (final e in json.entries)
      identifier({'metric': e.key}, 'metric'): jsonObject(e.value, 'target'),
  };
}
