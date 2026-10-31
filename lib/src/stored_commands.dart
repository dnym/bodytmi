import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';

const storedCommandNames = [
  'store publish',
  'store revision',
  'store start',
  'store show',
  'store complete',
  'store skip',
  'store finish',
  'store history',
  'store snapshot',
];

/// Filesystem/database construction belongs to the native adapter.
Future<Map<String, Object?>> executeStored(
  String command,
  Map<String, Object?> request,
) async {
  if (request['schemaVersion'] != 1)
    invalid('Request schemaVersion must be 1.');
  final fields = switch (command) {
    'store publish' => {'definition', 'expectedRevision'},
    'store revision' => {'templateId', 'revision'},
    'store start' => {'id', 'templateId', 'revision', 'startedAt'},
    'store show' => {'id'},
    'store complete' => {
      'id',
      'expectedVersion',
      'setId',
      'actuals',
      'acceptSuggested',
    },
    'store skip' => {'id', 'expectedVersion', 'setId', 'confirm'},
    'store finish' => {'id', 'expectedVersion', 'finishedAt'},
    'store history' => <String>{},
    'store snapshot' => {'destination'},
    _ => invalid('Unknown stored command.'),
  };
  checkKeys(request, {'schemaVersion', 'database', ...fields});
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

  final store = await TrainingStore.open(requiredString(request, 'database'));
  try {
    final service = StoredTrainingService(store);
    Object? data;
    switch (command) {
      case 'store publish':
        data = (await service.publish(
          WorkoutDefinition.fromJson(request['definition']),
          integer('expectedRevision', min: 0),
        )).toJson();
      case 'store revision':
        data = (await service.revision(
          identifier(request, 'templateId'),
          request['revision'] == null ? null : integer('revision'),
        )).toJson();
      case 'store start':
        data = (await service.start(
          identifier(request, 'id'),
          identifier(request, 'templateId'),
          integer('revision'),
          parseInstant(request['startedAt'], 'startedAt'),
        )).toJson();
      case 'store show':
        data = (await service.session(identifier(request, 'id'))).toJson();
      case 'store history':
        data = [for (final session in await store.sessions()) session.toJson()];
      case 'store complete':
        final actuals = metricsFromJson(
          request['actuals'] ?? <String, Object?>{},
        );
        final accept = flag('acceptSuggested');
        final setId = requiredString(request, 'setId');
        data = (await service.edit(
          identifier(request, 'id'),
          integer('expectedVersion'),
          (s) => const TrainingService().complete(
            s,
            setId,
            actuals,
            acceptSuggested: accept,
          ),
        )).toJson();
      case 'store skip':
        final setId = requiredString(request, 'setId');
        final confirm = flag('confirm');
        data = (await service.edit(
          identifier(request, 'id'),
          integer('expectedVersion'),
          (s) => const TrainingService().skip(s, setId, confirm: confirm),
        )).toJson();
      case 'store finish':
        final finishedAt = parseInstant(request['finishedAt'], 'finishedAt');
        data = (await service.edit(
          identifier(request, 'id'),
          integer('expectedVersion'),
          (s) => s.finish(finishedAt),
        )).toJson();
      case 'store snapshot':
        final destination = requiredString(request, 'destination');
        await store.snapshot(destination);
        data = {'destination': destination, 'format': 'sqlite-snapshot/1'};
    }
    return {'schemaVersion': 1, 'data': data};
  } finally {
    await store.close();
  }
}
