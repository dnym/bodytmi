import 'execution_runner.dart';
import 'timing_runner.dart';
import 'window_runner.dart';
import 'analytics_options.dart';
import 'session_window_clock_adapter.dart';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';

const storedCommandNames = [
  'execution start',
  'execution show',
  'execution list',
  'execution time',
  'execution advance',
  'execution complete',
  'execution confirm',
  'execution skip',
  'execution skip-group',
  'execution run',
  'timer rest',
  'timer start',
  'timer show',
  'timer list',
  'timer resume',
  'timer advance',
  'timer pause',
  'timer end-effort',
  'timer recover',
  'timer stop',
  'timer discard',
  'timer confirm',
  'timer run',
  'store publish',
  'store revision',
  'store start',
  'store show',
  'store summary',
  'store rounds',
  'store window-clock',
  'store window-review',
  'checkpoint save',
  'checkpoint review',
  'checkpoint complete-current',
  'checkpoint advance-boundary',
  'checkpoint advance-rest',
  'checkpoint skip-expired',
  'checkpoint review-expired',
  'checkpoint review-expired-batch',
  'checkpoint reserve',
  'checkpoint release',
  'checkpoint action',
  'checkpoint run',
  'checkpoint show',
  'checkpoint status',
  'checkpoint list',
  'checkpoint delete',
  'store progression-preview',
  'store assess-objectives',
  'store series',
  'store records',
  'family publish',
  'family show',
  'family list',
  'graph publish',
  'graph show',
  'graph list',
  'graph resolve',
  'graph status',
  'graph preview',
  'graph plan-preview',
  'graph plan-status',
  'graph preview-status',
  'store mass-status',
  'store mass-refresh',
  'store mass-rebind',
  'store plan-status',
  'store plan-refresh',
  'store effective-load',
  'store complete',
  'store annotate',
  'store skip',
  'store skip-remaining',
  'store skip-slot',
  'store edit-target',
  'store carry-actual',
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
  'progression track',
  'progression show',
  'progression accept',
  'progression decline',
  'program publish',
  'program show',
  'program list',
  'run create',
  'run list',
  'run show',
  'run schedule',
  'run start',
  'run skip',
  'run pause',
  'run resume',
  'mass record',
  'mass update',
  'mass delete',
  'mass show',
  'mass list',
  'mass trend',
  'mass resolve',
];

/// Filesystem/database construction belongs to the native adapter.
Future<Map<String, Object?>> executeStored(
  String command,
  Map<String, Object?> request,
) async {
  if (request['schemaVersion'] != 1)
    invalid('Request schemaVersion must be 1.');
  final fields = switch (command) {
    'execution start' => {'id', 'sessionId', 'at'},
    'execution show' => {'id'},
    'execution list' => <String>{},
    'execution time' => {'id', 'expectedVersion', 'at', 'metric', 'plan'},
    'execution advance' => {
      'id',
      'expectedVersion',
      'expectedSessionVersion',
      'requestId',
      'at',
    },
    'execution complete' => {
      'id',
      'expectedVersion',
      'expectedSessionVersion',
      'requestId',
      'at',
      'actuals',
      'acceptSuggested',
    },
    'execution confirm' => {
      'id',
      'expectedVersion',
      'expectedSessionVersion',
      'requestId',
      'at',
      'timerId',
      'timerVersion',
      'actuals',
      'acceptSuggested',
    },
    'execution skip' => {
      'id',
      'expectedVersion',
      'expectedSessionVersion',
      'requestId',
      'at',
      'confirm',
    },
    'execution skip-group' => {
      'id',
      'expectedVersion',
      'expectedSessionVersion',
      'requestId',
      'at',
      'groupPath',
      'confirm',
    },
    'execution run' => {
      'id',
      'expectedVersion',
      'expectedSessionVersion',
      'requestId',
      'at',
      'metric',
      'plan',
      'runForMilliseconds',
      'stream',
    },
    'timer rest' => {'id', 'sessionId', 'occurrenceId', 'at'},
    'timer start' => {'id', 'sessionId', 'setId', 'metric', 'plan', 'at'},
    'timer show' => {'id'},
    'timer list' => <String>{},
    'timer resume' => {'id', 'expectedVersion', 'ownerId', 'at'},
    'timer end-effort' => {'id', 'expectedVersion', 'at'},
    'timer advance' || 'timer pause' => {
      'id',
      'expectedVersion',
      'ownerId',
      'elapsedMilliseconds',
      'at',
    },
    'timer recover' => {
      'id',
      'expectedVersion',
      'mode',
      'adjustmentMilliseconds',
      'at',
    },
    'timer stop' ||
    'timer discard' => {'id', 'expectedVersion', 'at', 'confirm'},
    'timer confirm' => {
      'id',
      'expectedVersion',
      'expectedSessionVersion',
      'at',
      'actuals',
      'acceptSuggested',
    },
    'timer run' => {'id', 'expectedVersion', 'runForMilliseconds', 'stream'},
    'store publish' => {'definition', 'expectedRevision'},
    'store revision' => {'templateId', 'revision'},
    'store start' => {
      'id',
      'templateId',
      'revision',
      'startedAt',
      'bodyMassOverrides',
      'derivedPlan',
    },
    'store show' => {'id'},
    'store assess-objectives' => {'id', 'setId', 'objectives'},
    'store summary' => {'id', 'includeWarmups', 'sumMetrics', 'roles'},
    'store rounds' => {'id', 'groupPath'},
    'store window-clock' => {
      'id',
      'action',
      'clock',
      'expectedVersion',
      'ownerId',
      'ownerElapsedMilliseconds',
      'toOccurrence',
      'adjustmentMilliseconds',
    },
    'store window-review' => {
      'id',
      'clock',
      'expectedSessionVersion',
      'expectedClockVersion',
      'toOccurrence',
      'action',
      'actuals',
      'acceptSuggested',
      'observations',
      'confirm',
    },
    'checkpoint save' => {'id', 'sessionId', 'expectedVersion', 'clock'},
    'checkpoint reserve' => {'id', 'expectedVersion'},
    'checkpoint release' => {'id', 'expectedVersion', 'confirm'},
    'checkpoint skip-expired' => {
      'id',
      'expectedVersion',
      'expectedSessionVersion',
      'expectedClockVersion',
      'confirm',
    },
    'checkpoint complete-current' => {
      'id',
      'expectedVersion',
      'expectedSessionVersion',
      'expectedClockVersion',
      'actuals',
      'acceptSuggested',
      'observations',
    },
    'checkpoint advance-boundary' => {
      'id',
      'expectedVersion',
      'expectedSessionVersion',
      'expectedClockVersion',
    },
    'checkpoint advance-rest' => {
      'id',
      'expectedVersion',
      'expectedSessionVersion',
      'expectedClockVersion',
      'confirm',
    },
    'checkpoint review-expired' => {
      'id',
      'expectedVersion',
      'expectedSessionVersion',
      'expectedClockVersion',
      'confirm',
      'actuals',
      'acceptSuggested',
      'observations',
    },
    'checkpoint review-expired-batch' => {
      'id',
      'expectedVersion',
      'expectedSessionVersion',
      'expectedClockVersion',
      'confirm',
      'reviews',
    },
    'checkpoint run' => {
      'id',
      'expectedVersion',
      'expectedSessionVersion',
      'expectedClockVersion',
      'runForMilliseconds',
      'stream',
      'advanceReviewed',
      'stopAtRest',
      'advanceRest',
    },
    'checkpoint action' => {
      'id',
      'expectedVersion',
      'expectedSessionVersion',
      'expectedClockVersion',
      'action',
      'ownerId',
      'ownerElapsedMilliseconds',
      'toOccurrence',
      'adjustmentMilliseconds',
    },
    'checkpoint review' => {
      'id',
      'expectedVersion',
      'expectedSessionVersion',
      'expectedClockVersion',
      'toOccurrence',
      'action',
      'actuals',
      'acceptSuggested',
      'observations',
      'confirm',
    },
    'checkpoint show' => {'id'},
    'checkpoint status' => {'id'},
    'checkpoint list' => <String>{},
    'checkpoint delete' => {'id', 'expectedVersion', 'confirm'},
    'store progression-preview' => {
      'id',
      'slotId',
      'role',
      'ruleType',
      'rule',
      'state',
      'useTrack',
    },
    'store records' => {
      'context',
      'metric',
      'direction',
      'atActuals',
      'from',
      'until',
      'includeWarmups',
      'roles',
      'familyId',
      'familyRevision',
    },
    'store series' => {
      'context',
      'metric',
      'from',
      'until',
      'includeWarmups',
      'roles',
      'includeActive',
      'familyId',
      'familyRevision',
    },
    'family publish' => {'family', 'expectedRevision'},
    'family show' => {'familyId', 'revision'},
    'family list' => <String>{},
    'graph publish' => {'graph', 'expectedRevision'},
    'graph show' => {'graphId', 'revision'},
    'graph list' => <String>{},
    'graph resolve' => {'graphId', 'revision', 'asOf', 'runId', 'allRuns'},
    'graph status' => {'snapshot'},
    'graph preview-status' => {'preview'},
    'graph plan-status' => {'planPreview'},
    'graph plan-preview' => {
      'graphId',
      'graphRevision',
      'planId',
      'asOf',
      'runId',
    },
    'graph preview' => {
      'templateId',
      'revision',
      'graphId',
      'graphRevision',
      'asOf',
      'runId',
      'bindings',
    },
    'store mass-status' => {'id'},
    'store mass-refresh' => {'id', 'expectedVersion', 'confirm'},
    'store mass-rebind' => {
      'id',
      'expectedVersion',
      'bodyMassOverrides',
      'confirm',
    },
    'store plan-status' => {'id'},
    'store plan-refresh' => {
      'id',
      'expectedVersion',
      'expectedPreview',
      'confirm',
    },
    'store effective-load' => {'id'},
    'store complete' => {
      'id',
      'expectedVersion',
      'setId',
      'actuals',
      'acceptSuggested',
    },
    'store annotate' => {
      'id',
      'expectedVersion',
      'setId',
      'observations',
      'confirm',
    },
    'store skip' => {'id', 'expectedVersion', 'setId', 'confirm'},
    'store skip-remaining' => {'id', 'expectedVersion', 'confirm'},
    'store skip-slot' => {'id', 'expectedVersion', 'slotId', 'role', 'confirm'},
    'store edit-target' => {
      'id',
      'expectedVersion',
      'setId',
      'metric',
      'value',
      'applyToRemaining',
    },
    'store carry-actual' => {'id', 'expectedVersion', 'setId', 'metric'},
    'store finish' => {'id', 'expectedVersion', 'finishedAt'},
    'store history' => <String>{},
    'store snapshot' => {'destination'},
    'backup create' => {'destination'},
    'backup validate' => {'source'},
    'backup restore' => {'source', 'recoveryDestination', 'confirm'},
    'archive export' => {'destination'},
    'archive validate' => {'source'},
    'archive restore' => {'source', 'recoveryDestination', 'confirm'},
    'progression propose' => {
      'sessionId',
      'slotId',
      'role',
      'rule',
      'ruleType',
    },
    'progression track' => {
      'templateId',
      'revision',
      'slotId',
      'role',
      'runId',
      'asOf',
    },
    'progression show' => {'sessionId', 'slotId', 'role'},
    'progression accept' => {
      'sessionId',
      'slotId',
      'role',
      'expectedVersion',
      'acceptedAt',
    },
    'progression decline' => {
      'sessionId',
      'slotId',
      'role',
      'expectedVersion',
      'declinedAt',
    },
    'mass record' => {'measurement'},
    'mass update' => {'measurement', 'expectedVersion'},
    'mass delete' => {'id', 'expectedVersion', 'confirm'},
    'mass show' => {'id'},
    'mass list' => {'context', 'includeDeleted'},
    'mass trend' => {'context', 'asOf', 'dailyMode'},
    'mass resolve' => {
      'context',
      'asOf',
      'dailyMode',
      'override',
      'staleAfterDays',
      'warnIfStale',
    },
    'program publish' => {'definition', 'expectedRevision'},
    'program show' => {'programId', 'revision'},
    'program list' => <String>{},
    'run create' => {'id', 'programId', 'revision', 'startedAt', 'loop'},
    'run list' => {'status'},
    'run show' => {'runId'},
    'run schedule' => {'runId', 'count', 'includeScopes'},
    'run start' => {
      'runId',
      'expectedVersion',
      'id',
      'startedAt',
      'bodyMassOverrides',
      'derivedPlan',
    },
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
    final timing = TimingService(store);
    final checkpoints = WindowCheckpointService(store);
    final execution = ExecutionService(store);
    switch (command) {
      case 'checkpoint save':
        data = (await checkpoints.save(
          identifier(request, 'id'),
          identifier(request, 'sessionId'),
          integer('expectedVersion', min: 0),
          request['clock'],
        )).toJson();
      case 'checkpoint reserve':
        data = (await checkpoints.reserve(
          identifier(request, 'id'),
          integer('expectedVersion'),
        )).toJson();
      case 'checkpoint release':
        data = (await checkpoints.release(
          identifier(request, 'id'),
          integer('expectedVersion'),
          confirm: flag('confirm'),
        )).toJson();
      case 'checkpoint action':
        data = (await checkpoints.action(
          identifier(request, 'id'),
          expectedVersion: integer('expectedVersion'),
          expectedSessionVersion: integer('expectedSessionVersion'),
          expectedClockVersion: integer('expectedClockVersion'),
          action: requiredString(request, 'action'),
          ownerId: request.containsKey('ownerId')
              ? identifier(request, 'ownerId')
              : null,
          ownerElapsedMilliseconds:
              request.containsKey('ownerElapsedMilliseconds')
              ? integer('ownerElapsedMilliseconds', min: 0)
              : null,
          toOccurrence: request.containsKey('toOccurrence')
              ? integer('toOccurrence', min: 0)
              : null,
          adjustmentMilliseconds: request.containsKey('adjustmentMilliseconds')
              ? integer('adjustmentMilliseconds', min: 0)
              : null,
        )).toJson();
      case 'checkpoint run':
        final limit = request.containsKey('runForMilliseconds')
            ? integer('runForMilliseconds')
            : null;
        if (limit != null && limit > 86400000)
          invalid('Foreground run limit exceeds 24 hours.');
        data = await runWindowClock(
          store,
          identifier(request, 'id'),
          integer('expectedVersion'),
          integer('expectedSessionVersion'),
          integer('expectedClockVersion'),
          runForMilliseconds: limit,
          stream: flag('stream'),
          advanceReviewed: flag('advanceReviewed'),
          stopAtRest: flag('stopAtRest'),
          advanceRest: flag('advanceRest'),
        );
      case 'checkpoint advance-rest':
        data = (await checkpoints.advanceRest(
          identifier(request, 'id'),
          expectedVersion: integer('expectedVersion'),
          expectedSessionVersion: integer('expectedSessionVersion'),
          expectedClockVersion: integer('expectedClockVersion'),
          confirm: flag('confirm'),
        )).toJson();
      case 'checkpoint advance-boundary':
        final result = await checkpoints.advanceReviewedBoundary(
          identifier(request, 'id'),
          expectedVersion: integer('expectedVersion'),
          expectedSessionVersion: integer('expectedSessionVersion'),
          expectedClockVersion: integer('expectedClockVersion'),
        );
        if (result == null)
          invalid(
            'Review or explicitly skip all remaining efforts before advancing.',
          );
        data = result.toJson();
      case 'checkpoint complete-current':
        final result = await checkpoints.completeCurrent(
          identifier(request, 'id'),
          expectedVersion: integer('expectedVersion'),
          expectedSessionVersion: integer('expectedSessionVersion'),
          expectedClockVersion: integer('expectedClockVersion'),
          actuals: metricsFromJson(request['actuals'] ?? <String, Object?>{}),
          acceptSuggested: flag('acceptSuggested'),
          observations: request.containsKey('observations')
              ? SetObservations.fromJson(request['observations'])
              : null,
        );
        data = {
          'session': result.session.toJson(),
          'checkpoint': result.checkpoint.toJson(),
          'occurrenceId': result.occurrenceId,
        };
      case 'checkpoint review-expired-batch':
        final result = await checkpoints.reviewExpiredBatch(
          identifier(request, 'id'),
          expectedVersion: integer('expectedVersion'),
          expectedSessionVersion: integer('expectedSessionVersion'),
          expectedClockVersion: integer('expectedClockVersion'),
          confirm: flag('confirm'),
          reviews: [
            for (final review in jsonList(request, 'reviews'))
              WindowEffortReview.fromJson(review),
          ],
        );
        data = {
          'session': result.session.toJson(),
          'checkpoint': result.checkpoint.toJson(),
          'reviewed': result.reviewed,
          'skipped': result.skipped,
        };
      case 'checkpoint review-expired':
        final result = await checkpoints.reviewExpired(
          identifier(request, 'id'),
          expectedVersion: integer('expectedVersion'),
          expectedSessionVersion: integer('expectedSessionVersion'),
          expectedClockVersion: integer('expectedClockVersion'),
          confirm: flag('confirm'),
          actuals: metricsFromJson(request['actuals'] ?? <String, Object?>{}),
          acceptSuggested: flag('acceptSuggested'),
          observations: request.containsKey('observations')
              ? SetObservations.fromJson(request['observations'])
              : null,
        );
        data = {
          'session': result.session.toJson(),
          'checkpoint': result.checkpoint.toJson(),
          'occurrenceId': result.occurrenceId,
          'skipped': result.skipped,
        };
      case 'checkpoint skip-expired':
        final result = await checkpoints.skipExpired(
          identifier(request, 'id'),
          expectedVersion: integer('expectedVersion'),
          expectedSessionVersion: integer('expectedSessionVersion'),
          expectedClockVersion: integer('expectedClockVersion'),
          confirm: flag('confirm'),
        );
        data = {
          'session': result.session.toJson(),
          'checkpoint': result.checkpoint.toJson(),
          'skipped': result.skipped,
        };
      case 'checkpoint review':
        final result = await checkpoints.review(
          identifier(request, 'id'),
          expectedVersion: integer('expectedVersion'),
          expectedSessionVersion: integer('expectedSessionVersion'),
          expectedClockVersion: integer('expectedClockVersion'),
          toOccurrence: integer('toOccurrence', min: 0),
          action: requiredString(request, 'action'),
          actuals: metricsFromJson(request['actuals'] ?? <String, Object?>{}),
          acceptSuggested: flag('acceptSuggested'),
          confirm: flag('confirm'),
          observations: request.containsKey('observations')
              ? SetObservations.fromJson(request['observations'])
              : null,
        );
        data = {
          'session': result.session.toJson(),
          'checkpoint': result.checkpoint.toJson(),
          'occurrenceId': result.occurrenceId,
        };
      case 'checkpoint show':
        data = (await checkpoints.show(identifier(request, 'id'))).toJson();
      case 'checkpoint status':
        data = await checkpoints.status(identifier(request, 'id'));
      case 'checkpoint list':
        final all = await checkpoints.list();
        data = [for (final checkpoint in all) checkpoint.toJson()];
      case 'checkpoint delete':
        final id = identifier(request, 'id');
        await checkpoints.delete(
          id,
          integer('expectedVersion'),
          confirm: flag('confirm'),
        );
        data = {'id': id, 'deleted': true};
      case 'execution start':
        final e = await execution.start(
          identifier(request, 'id'),
          identifier(request, 'sessionId'),
          parseInstant(request['at'], 'at'),
        );
        data = await execution.view(e.id);
      case 'execution show':
        data = await execution.view(identifier(request, 'id'));
      case 'execution list':
        final all = await store.executions();
        all.sort((a, b) => a.id.compareTo(b.id));
        data = [for (final e in all) await execution.view(e.id)];
      case 'execution time':
        data = (await execution.time(
          identifier(request, 'id'),
          integer('expectedVersion'),
          parseInstant(request['at'], 'at'),
          metric: request.containsKey('metric')
              ? identifier(request, 'metric')
              : null,
          plan: request.containsKey('plan')
              ? TimingPlan.fromJson(request['plan'])
              : null,
        )).toViewJson();
      case 'execution advance':
      case 'execution complete':
      case 'execution confirm':
      case 'execution skip':
        final e = await execution.step(
          identifier(request, 'id'),
          integer('expectedVersion'),
          integer('expectedSessionVersion'),
          identifier(request, 'requestId'),
          parseInstant(request['at'], 'at'),
          action: command.substring(10),
          actuals: metricsFromJson(request['actuals'] ?? <String, Object?>{}),
          acceptSuggested: flag('acceptSuggested'),
          confirm: flag('confirm'),
          timerId: request.containsKey('timerId')
              ? identifier(request, 'timerId')
              : null,
          timerVersion: request.containsKey('timerVersion')
              ? integer('timerVersion')
              : null,
        );
        data = await execution.view(e.id);
      case 'execution run':
        final limit = request.containsKey('runForMilliseconds')
            ? integer('runForMilliseconds')
            : null;
        if (limit != null && limit > 86400000)
          invalid('Foreground run limit exceeds 24 hours.');
        data = await runExecution(
          store,
          identifier(request, 'id'),
          integer('expectedVersion'),
          integer('expectedSessionVersion'),
          identifier(request, 'requestId'),
          parseInstant(request['at'], 'at'),
          metric: request.containsKey('metric')
              ? identifier(request, 'metric')
              : null,
          plan: request.containsKey('plan')
              ? TimingPlan.fromJson(request['plan'])
              : null,
          runForMilliseconds: limit,
          stream: flag('stream'),
        );
      case 'execution skip-group':
        final e = await execution.skipGroup(
          identifier(request, 'id'),
          integer('expectedVersion'),
          integer('expectedSessionVersion'),
          identifier(request, 'requestId'),
          requiredString(request, 'groupPath'),
          parseInstant(request['at'], 'at'),
          confirm: flag('confirm'),
        );
        data = await execution.view(e.id);
      case 'timer rest':
        data = (await timing.startRest(
          identifier(request, 'id'),
          identifier(request, 'sessionId'),
          requiredString(request, 'occurrenceId'),
          parseInstant(request['at'], 'at'),
        )).toViewJson();
      case 'timer start':
        data = (await timing.start(
          identifier(request, 'id'),
          identifier(request, 'sessionId'),
          requiredString(request, 'setId'),
          request.containsKey('metric') ? identifier(request, 'metric') : null,
          request.containsKey('plan')
              ? TimingPlan.fromJson(request['plan'])
              : null,
          parseInstant(request['at'], 'at'),
        )).toViewJson();
      case 'timer list':
        final all = await store.timingActivities();
        all.sort((a, b) => a.id.compareTo(b.id));
        data = [
          for (final t in all)
            {...t.toViewJson(), 'requiresRecovery': t.status == 'running'},
        ];
      case 'timer show':
        final t = await timing.show(identifier(request, 'id'));
        data = {...t.toViewJson(), 'requiresRecovery': t.status == 'running'};
      case 'timer resume':
        data = (await timing.resume(
          identifier(request, 'id'),
          integer('expectedVersion'),
          identifier(request, 'ownerId'),
          parseInstant(request['at'], 'at'),
        )).toViewJson();
      case 'timer advance':
      case 'timer pause':
        final sample = integer('elapsedMilliseconds', min: 0);
        final step = await timing.advance(
          identifier(request, 'id'),
          integer('expectedVersion'),
          identifier(request, 'ownerId'),
          sample,
          parseInstant(request['at'], 'at'),
          action: command.substring(6),
        );
        data = {'timer': step.activity.toViewJson(), 'cues': step.cues};
      case 'timer end-effort':
        data = (await timing.endEffort(
          identifier(request, 'id'),
          integer('expectedVersion'),
          parseInstant(request['at'], 'at'),
        )).toViewJson();
      case 'timer recover':
        final mode = request['mode'];
        if (mode != 'freeze' && mode != 'adjust')
          invalid('Recovery mode must explicitly be freeze or adjust.');
        if (mode == 'freeze' && request.containsKey('adjustmentMilliseconds'))
          invalid('Freeze recovery does not take an adjustment.');
        data = (await timing.recover(
          identifier(request, 'id'),
          integer('expectedVersion'),
          parseInstant(request['at'], 'at'),
          adjustmentMilliseconds: mode == 'adjust'
              ? integer('adjustmentMilliseconds', min: 0)
              : null,
        )).toViewJson();
      case 'timer stop':
      case 'timer discard':
        data = (await timing.stop(
          identifier(request, 'id'),
          integer('expectedVersion'),
          parseInstant(request['at'], 'at'),
          confirm: flag('confirm'),
          discard: command == 'timer discard',
        )).toViewJson();
      case 'timer confirm':
        data = (await timing.confirm(
          identifier(request, 'id'),
          integer('expectedVersion'),
          integer('expectedSessionVersion'),
          parseInstant(request['at'], 'at'),
          metricsFromJson(request['actuals'] ?? <String, Object?>{}),
          acceptSuggested: flag('acceptSuggested'),
        )).toViewJson();
      case 'timer run':
        final limit = request.containsKey('runForMilliseconds')
            ? integer('runForMilliseconds')
            : null;
        if (limit != null && limit > 86400000)
          invalid('Foreground run limit exceeds 24 hours.');
        data = await runTiming(
          store,
          identifier(request, 'id'),
          integer('expectedVersion'),
          runForMilliseconds: limit,
          stream: flag('stream'),
        );
      case 'mass record':
      case 'mass update':
        data = (await StoredBodyMassService(store).save(
          jsonObject(request['measurement'], 'measurement'),
          command == 'mass record' ? 0 : integer('expectedVersion'),
        )).toJson();
      case 'mass delete':
        data = (await StoredBodyMassService(store).delete(
          identifier(request, 'id'),
          integer('expectedVersion'),
          confirm: flag('confirm'),
        )).toJson();
      case 'mass show':
        data = (await StoredBodyMassService(
          store,
        ).show(identifier(request, 'id'))).toJson();
      case 'mass list':
        data = [
          for (final r in await StoredBodyMassService(store).list(
            context: request.containsKey('context')
                ? identifier(request, 'context')
                : null,
            includeDeleted: flag('includeDeleted'),
          ))
            r.toJson(),
        ];
      case 'mass trend':
      case 'mass resolve':
        final input = {
          for (final e in request.entries)
            if (e.key != 'schemaVersion' && e.key != 'database') e.key: e.value,
        };
        final service = StoredBodyMassService(store);
        data = command == 'mass trend'
            ? (await service.trend(input)).toJson()
            : (await service.resolve(input)).toJson();
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
      case 'run schedule':
        data = await programs.schedule(
          identifier(request, 'runId'),
          count: request.containsKey('count') ? integer('count') : 10,
          includeScopes: flag('includeScopes'),
        );
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
          bodyMassOverrides: bodyMassOverridesFromJson(
            request['bodyMassOverrides'],
          ),
          derivedPlan: request['derivedPlan'] == null
              ? null
              : DerivedPlanRef.fromJson(request['derivedPlan']),
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
      case 'progression track':
        data = await StoredProgressionService(store).track(
          templateId: identifier(request, 'templateId'),
          revision: integer('revision'),
          slotId: identifier(request, 'slotId'),
          asOf: parseInstant(request['asOf'], 'asOf'),
          runId: request.containsKey('runId')
              ? identifier(request, 'runId')
              : null,
          role: request.containsKey('role')
              ? requiredString(request, 'role')
              : 'work',
        );
      case 'progression propose':
      case 'progression show':
      case 'progression accept':
      case 'progression decline':
        final progression = StoredProgressionService(store);
        final sessionId = identifier(request, 'sessionId');
        final slotId = identifier(request, 'slotId');
        final role = request.containsKey('role')
            ? requiredString(request, 'role')
            : 'work';
        final decision = switch (command) {
          'progression propose' => await progression.propose(
            sessionId,
            slotId,
            jsonObject(request['rule'], 'rule'),
            ruleType: request.containsKey('ruleType')
                ? requiredString(request, 'ruleType')
                : 'double',
            role: role,
          ),
          'progression accept' => await progression.accept(
            sessionId,
            slotId,
            integer('expectedVersion'),
            parseInstant(request['acceptedAt'], 'acceptedAt'),
            role: role,
          ),
          'progression decline' => await progression.decline(
            sessionId,
            slotId,
            integer('expectedVersion'),
            parseInstant(request['declinedAt'], 'declinedAt'),
            role: role,
          ),
          _ => await progression.decision(sessionId, slotId, role: role),
        };
        final changed = await progression.stale(decision);
        data = {
          'id': decision.id,
          'applied': decision.acceptedAt != null,
          'status': decision.status,
          'resolvedState': decision.resolvedAt == null
              ? null
              : {
                  'failedSessions': decision.failedSessions,
                  if (decision.ruleType == 'threshold')
                    'cursor': decision.cursor,
                  'nextSets': [
                    for (final set in decision.nextSets) metricsToJson(set),
                  ],
                },
          'sequence': decision.sequence,
          'inputsChanged': changed,
          'stale': decision.resolvedAt == null && changed,
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
          bodyMassOverrides: bodyMassOverridesFromJson(
            request['bodyMassOverrides'],
          ),
          derivedPlan: request['derivedPlan'] == null
              ? null
              : DerivedPlanRef.fromJson(request['derivedPlan']),
        )).toJson();
      case 'store effective-load':
        data = const EffectiveMassService().evaluate(
          await service.session(identifier(request, 'id')),
        );
      case 'store plan-refresh':
        data = (await service.refreshPlan(
          identifier(request, 'id'),
          integer('expectedVersion'),
          expectedPreview: request['expectedPreview'],
          confirm: flag('confirm'),
        )).toJson();
      case 'store plan-status':
        data = await DerivedWorkoutPreview(
          store,
        ).sessionStatus(identifier(request, 'id'));
      case 'store mass-rebind':
        data = (await service.rebindBodyMass(
          identifier(request, 'id'),
          integer('expectedVersion'),
          bodyMassRebindingsFromJson(request['bodyMassOverrides']),
          confirm: flag('confirm'),
        )).toJson();
      case 'store mass-refresh':
        data = (await service.refreshBodyMass(
          identifier(request, 'id'),
          integer('expectedVersion'),
          confirm: flag('confirm'),
        )).toJson();
      case 'store mass-status':
        data = await store.transaction(
          () async => const TrainingService().bodyMassStatus(
            await service.session(identifier(request, 'id')),
            [
              for (final r in await store.bodyMassRecords())
                if (!r.deleted) r.measurement,
            ],
          ),
        );
      case 'store show':
        data = (await service.session(identifier(request, 'id'))).toJson();
      case 'store window-clock':
        data = sessionWindowClockRequest(
          await service.session(identifier(request, 'id')),
          request,
        );
      case 'store window-review':
        data = await store.transaction(() async {
          final id = identifier(request, 'id');
          final result = sessionWindowReviewRequest(
            await service.session(id),
            request,
          );
          final saved = await service.edit(
            id,
            integer('expectedSessionVersion'),
            (_) => result.session,
          );
          return {
            'session': saved.toJson(),
            'clock': result.clock,
            'occurrenceId': result.occurrenceId,
          };
        });
      case 'store summary':
        data = const TrainingAnalytics().summary(
          await service.session(identifier(request, 'id')),
          includeWarmups: flag('includeWarmups'),
          sumMetrics: analyticsSums(request),
          roles: analyticsRoles(request),
        );
      case 'store rounds':
        data = const RoundProgress().evaluate(
          await service.session(identifier(request, 'id')),
          requiredString(request, 'groupPath'),
        );
      case 'store progression-preview':
        if (flag('useTrack')) {
          if (request.containsKey('state'))
            invalid('useTrack cannot be combined with state.');
          data = await StoredProgressionService(store).previewFromTrack(
            identifier(request, 'id'),
            identifier(request, 'slotId'),
            jsonObject(request['rule'], 'rule'),
            role: request.containsKey('role')
                ? requiredString(request, 'role')
                : 'work',
            ruleType: request.containsKey('ruleType')
                ? requiredString(request, 'ruleType')
                : 'double',
          );
        } else {
          data = roleProgressionPreview(
            await service.session(identifier(request, 'id')),
            request,
          );
        }
      case 'store records':
        if (request.containsKey('familyRevision') &&
            !request.containsKey('familyId'))
          invalid('familyRevision needs familyId.');
        data = await store.transaction(
          () async => const ContextualRecords().evaluate(
            await store.sessions(),
            metric: identifier(request, 'metric'),
            direction: requiredString(request, 'direction'),
            atActuals: metricsFromJson(
              request['atActuals'] ?? <String, Object?>{},
            ),
            runBySession: {
              for (final b in await store.sessionPrograms())
                b.sessionId: b.runId,
            },
            context: jsonObject(
              request['context'] ?? <String, Object?>{},
              'context',
            ),
            from: request.containsKey('from')
                ? parseInstant(request['from'], 'from')
                : null,
            until: request.containsKey('until')
                ? parseInstant(request['until'], 'until')
                : null,
            includeWarmups: flag('includeWarmups'),
            roles: analyticsRoles(request),
            family: request.containsKey('familyId')
                ? await FamilyService(store).revision(
                    identifier(request, 'familyId'),
                    request.containsKey('familyRevision')
                        ? integer('familyRevision')
                        : null,
                  )
                : null,
          ),
        );
      case 'store series':
        if (request.containsKey('familyRevision') &&
            !request.containsKey('familyId'))
          invalid('familyRevision needs familyId.');
        data = await store.transaction(
          () async => const TrainingAnalytics().series(
            await store.sessions(),
            runBySession: {
              for (final b in await store.sessionPrograms())
                b.sessionId: b.runId,
            },
            context: jsonObject(
              request['context'] ?? <String, Object?>{},
              'context',
            ),
            metric: request.containsKey('metric')
                ? identifier(request, 'metric')
                : null,
            from: request.containsKey('from')
                ? parseInstant(request['from'], 'from')
                : null,
            until: request.containsKey('until')
                ? parseInstant(request['until'], 'until')
                : null,
            includeWarmups: flag('includeWarmups'),
            roles: analyticsRoles(request),
            includeActive: flag('includeActive'),
            family: request.containsKey('familyId')
                ? await FamilyService(store).revision(
                    identifier(request, 'familyId'),
                    request.containsKey('familyRevision')
                        ? integer('familyRevision')
                        : null,
                  )
                : null,
          ),
        );
      case 'family publish':
        data = (await FamilyService(store).publish(
          ExerciseFamily.fromJson(request['family']),
          integer('expectedRevision', min: 0),
        )).toJson();
      case 'family show':
        data = (await FamilyService(store).revision(
          identifier(request, 'familyId'),
          request.containsKey('revision') ? integer('revision') : null,
        )).toJson();
      case 'family list':
        final all = await store.familyRevisions();
        all.sort((a, b) {
          final id = a.family.id.compareTo(b.family.id);
          return id == 0 ? a.number.compareTo(b.number) : id;
        });
        data = [for (final f in all) f.toJson()];
      case 'graph publish':
        data = (await DerivedTargetGraphService(store).publish(
          DerivedTargetGraph.fromJson(request['graph']),
          integer('expectedRevision', min: 0),
        )).toJson();
      case 'graph show':
        data = (await DerivedTargetGraphService(store).revision(
          identifier(request, 'graphId'),
          request.containsKey('revision') ? integer('revision') : null,
        )).toJson();
      case 'graph list':
        data = [
          for (final g in await DerivedTargetGraphService(store).list())
            g.toJson(),
        ];
      case 'graph resolve':
        data = await DerivedTargetGraphService(store).resolve(
          identifier(request, 'graphId'),
          request.containsKey('revision') ? integer('revision') : null,
          request.containsKey('asOf')
              ? parseInstant(request['asOf'], 'asOf')
              : null,
          request.containsKey('runId') ? identifier(request, 'runId') : null,
          flag('allRuns'),
        );
      case 'graph plan-status':
        data = await DerivedWorkoutPreview(
          store,
        ).planStatus(request['planPreview']);
      case 'graph plan-preview':
        data = await DerivedWorkoutPreview(store).previewPlan(
          graphId: identifier(request, 'graphId'),
          graphRevision: integer('graphRevision'),
          planId: identifier(request, 'planId'),
          asOf: parseInstant(request['asOf'], 'asOf'),
          runId: request.containsKey('runId')
              ? identifier(request, 'runId')
              : null,
        );
      case 'graph preview':
        data = await DerivedWorkoutPreview(store).preview(
          templateId: identifier(request, 'templateId'),
          revision: integer('revision'),
          graphId: identifier(request, 'graphId'),
          graphRevision: integer('graphRevision'),
          asOf: parseInstant(request['asOf'], 'asOf'),
          runId: request.containsKey('runId')
              ? identifier(request, 'runId')
              : null,
          bindings: request['bindings'],
        );
      case 'graph preview-status':
        data = await DerivedWorkoutPreview(store).status(request['preview']);
      case 'graph status':
        data = await DerivedTargetGraphService(
          store,
        ).status(request['snapshot']);
      case 'store assess-objectives':
        data = await store.transaction(
          () async => const TrainingService().assessObjectives(
            await service.session(identifier(request, 'id')),
            requiredString(request, 'setId'),
            request['objectives'],
          ),
        );
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
      case 'store annotate':
        final setId = requiredString(request, 'setId');
        final observations = SetObservations.fromJson(request['observations']);
        final confirm = flag('confirm');
        data = (await service.edit(
          identifier(request, 'id'),
          integer('expectedVersion'),
          (s) => const TrainingService().annotate(
            s,
            setId,
            observations,
            confirm: confirm,
          ),
        )).toJson();
      case 'store skip-remaining':
        data = (await service.skipRemaining(
          identifier(request, 'id'),
          integer('expectedVersion'),
          confirm: flag('confirm'),
        )).toJson();
      case 'store skip-slot':
        data = (await service.skipSlot(
          identifier(request, 'id'),
          integer('expectedVersion'),
          identifier(request, 'slotId'),
          role: request.containsKey('role')
              ? requiredString(request, 'role')
              : null,
          confirm: flag('confirm'),
        )).toJson();
      case 'store edit-target':
        data = (await service.editTarget(
          identifier(request, 'id'),
          integer('expectedVersion'),
          requiredString(request, 'setId'),
          identifier(request, 'metric'),
          Quantity.fromJson(request['value']),
          applyToRemaining: flag('applyToRemaining'),
        )).toJson();
      case 'store carry-actual':
        data = (await service.carryActual(
          identifier(request, 'id'),
          integer('expectedVersion'),
          requiredString(request, 'setId'),
          identifier(request, 'metric'),
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
