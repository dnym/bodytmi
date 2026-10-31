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
  'backup create',
  'backup validate',
  'backup restore',
  'archive export',
  'archive validate',
  'archive restore',
  'progression propose',
  'progression show',
  'progression accept',
  'program publish',
  'program show',
  'program list',
  'run create',
  'run list',
  'run show',
  'run start',
  'run skip',
  'run pause',
  'run resume',
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
    'backup create' => {'destination'},
    'backup validate' => {'source'},
    'backup restore' => {'source', 'recoveryDestination', 'confirm'},
    'archive export' => {'destination'},
    'archive validate' => {'source'},
    'archive restore' => {'source', 'recoveryDestination', 'confirm'},
    'progression propose' => {'sessionId', 'slotId', 'rule'},
    'progression show' => {'sessionId', 'slotId'},
    'progression accept' => {
      'sessionId',
      'slotId',
      'expectedVersion',
      'acceptedAt',
    },
    'program publish' => {'definition', 'expectedRevision'},
    'program show' => {'programId', 'revision'},
    'program list' => <String>{},
    'run create' => {'id', 'programId', 'revision', 'startedAt', 'loop'},
    'run list' => {'status'},
    'run show' => {'runId'},
    'run start' => {'runId', 'expectedVersion', 'id', 'startedAt'},
    'run skip' => {'runId', 'expectedVersion', 'requestId', 'skippedAt'},
    'run pause' || 'run resume' => {'runId', 'expectedVersion'},
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

  if (command == 'archive validate') {
    checkKeys(request, {'schemaVersion', 'source'});
    final prepared = await LogicalArchiveFiles.prepare(
      requiredString(request, 'source'),
    );
    try {
      return {'schemaVersion': 1, 'data': prepared.summary};
    } finally {
      await prepared.close();
    }
  }
  if (command == 'archive restore') {
    if (!flag('confirm'))
      invalid('Restore replaces the profile and requires confirm:true.');
    final recovery = requiredString(request, 'recoveryDestination');
    final database = requiredString(request, 'database');
    final prepared = await LogicalArchiveFiles.prepare(
      requiredString(request, 'source'),
    );
    try {
      await prepared.checkDestination(database);
      await prepared.checkDestination(recovery);
      final store = await TrainingStore.open(database);
      try {
        await store.restore(
          prepared.backup,
          recoveryDestination: recovery,
          confirm: true,
        );
        return {
          'schemaVersion': 1,
          'data': {
            'restored': true,
            'recoveryDestination': recovery,
            ...prepared.summary,
          },
        };
      } finally {
        await store.close();
      }
    } finally {
      await prepared.close();
    }
  }
  if (command == 'backup validate') {
    checkKeys(request, {'schemaVersion', 'source'});
    final prepared = await NativeBackup.prepare(
      requiredString(request, 'source'),
    );
    try {
      return {'schemaVersion': 1, 'data': prepared.manifest};
    } finally {
      await prepared.close();
    }
  }
  if (command == 'backup restore') {
    if (!flag('confirm'))
      invalid('Restore replaces the profile and requires confirm:true.');
    final recovery = requiredString(request, 'recoveryDestination');
    final prepared = await NativeBackup.prepare(
      requiredString(request, 'source'),
    );
    try {
      await prepared.checkDestination(requiredString(request, 'database'));
      await prepared.checkDestination(recovery);
      final store = await TrainingStore.open(
        requiredString(request, 'database'),
      );
      try {
        await store.restore(
          prepared,
          recoveryDestination: recovery,
          confirm: true,
        );
        return {
          'schemaVersion': 1,
          'data': {'restored': true, 'recoveryDestination': recovery},
        };
      } finally {
        await store.close();
      }
    } finally {
      await prepared.close();
    }
  }

  final store = await TrainingStore.open(requiredString(request, 'database'));
  try {
    final service = StoredTrainingService(store);
    final programs = ProgramService(store);
    Future<Map<String, Object?>> runView(ProgramRun run) async {
      final bindings = await store.sessionPrograms();
      return {
        ...run.toJson(),
        'current': run.current?.toJson(),
        'currentSessionId': bindings
            .where((b) => b.runId == run.id && b.ordinal == run.cursor)
            .firstOrNull
            ?.sessionId,
      };
    }

    Object? data;
    switch (command) {
      case 'program publish':
        data = (await programs.publish(
          ProgramDefinition.fromJson(request['definition']),
          integer('expectedRevision', min: 0),
        )).toJson();
      case 'program show':
        data = (await programs.revision(
          identifier(request, 'programId'),
          request['revision'] == null ? null : integer('revision'),
        )).toJson();
      case 'program list':
        final all = await store.programRevisions();
        all.sort((a, b) {
          final c = a.definition.id.compareTo(b.definition.id);
          return c == 0 ? a.number.compareTo(b.number) : c;
        });
        data = [for (final p in all) p.toJson()];
      case 'run create':
        data = await runView(
          await programs.create(
            identifier(request, 'id'),
            identifier(request, 'programId'),
            integer('revision'),
            parseInstant(request['startedAt'], 'startedAt'),
            loop: request.containsKey('loop') ? flag('loop') : true,
          ),
        );
      case 'run list':
        final status = request['status'];
        if (status != null &&
            !{'active', 'paused', 'completed'}.contains(status))
          invalid('Unknown run status filter.');
        final runs = await store.programRuns();
        runs.sort((a, b) => a.id.compareTo(b.id));
        data = [
          for (final r in runs)
            if (status == null || r.status == status) await runView(r),
        ];
      case 'run show':
        data = await runView(await programs.run(identifier(request, 'runId')));
      case 'run pause':
      case 'run resume':
        data = await runView(
          await programs.status(
            identifier(request, 'runId'),
            integer('expectedVersion'),
            command == 'run pause' ? 'paused' : 'active',
          ),
        );
      case 'run start':
        data = (await programs.start(
          identifier(request, 'runId'),
          integer('expectedVersion'),
          identifier(request, 'id'),
          parseInstant(request['startedAt'], 'startedAt'),
        )).toJson();
      case 'run skip':
        final runId = identifier(request, 'runId');
        final receipt = await programs.skip(
          runId,
          integer('expectedVersion'),
          identifier(request, 'requestId'),
          parseInstant(request['skippedAt'], 'skippedAt'),
        );
        data = {
          'receipt': receipt.toJson(),
          'run': await runView(await programs.run(runId)),
        };
      case 'progression propose':
      case 'progression show':
      case 'progression accept':
        final progression = StoredProgressionService(store);
        final sessionId = identifier(request, 'sessionId');
        final slotId = identifier(request, 'slotId');
        final decision = switch (command) {
          'progression propose' => await progression.propose(
            sessionId,
            slotId,
            jsonObject(request['rule'], 'rule'),
          ),
          'progression accept' => await progression.accept(
            sessionId,
            slotId,
            integer('expectedVersion'),
            parseInstant(request['acceptedAt'], 'acceptedAt'),
          ),
          _ => await progression.decision(sessionId, slotId),
        };
        final changed = await progression.stale(decision);
        data = {
          'id': decision.id,
          'applied': decision.acceptedAt != null,
          'sequence': decision.sequence,
          'inputsChanged': changed,
          'stale': decision.acceptedAt == null && changed,
          ...decision.toJson(),
        };
      case 'archive export':
        data = await LogicalArchiveFiles.export(
          await store.archive(),
          requiredString(request, 'destination'),
        );
      case 'backup create':
        data = await store.backup(requiredString(request, 'destination'));
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
