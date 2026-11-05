import 'package:bodytmi_core/bodytmi_core.dart';

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
