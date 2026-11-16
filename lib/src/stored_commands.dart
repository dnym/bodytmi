import 'execution_runner.dart';
import 'timing_runner.dart';
import 'window_runner.dart';
import 'repeat_runner.dart';
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
  'execution move',
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
  'store load-status',
  'store summary',
  'store rounds',
  'store window-clock',
  'store window-review',
  'repeat-checkpoint save',
  'repeat-checkpoint start-block',
  'progression block-propose',
  'progression block-show',
  'progression block-accept',
  'progression block-decline',
  'progression block-track',
  'repeat-checkpoint action',
  'repeat-checkpoint run',
  'repeat-checkpoint reserve',
  'repeat-checkpoint release',
  'repeat-checkpoint show',
  'repeat-checkpoint list',
  'repeat-checkpoint series',
  'repeat-checkpoint rounds',
  'repeat-checkpoint delete',
  'checkpoint save',
  'checkpoint start',
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
  'exercise publish',
  'exercise show',
  'exercise list',
  'catalog search',
  'store save-back',
  'preset publish',
  'preset show',
  'preset list',
  'blueprint publish',
  'blueprint show',
  'blueprint list',
  'blueprint preview',
  'blueprint instantiate',
  'blueprint instances',
  'implementation publish',
  'implementation show',
  'implementation list',
  'equipment publish',
  'equipment show',
  'equipment list',
  'gym publish',
  'gym show',
  'gym list',
  'instance publish',
  'instance show',
  'instance list',
  'instance inventory',
  'store plate-plan',
  'store load-convention',
  'link create',
  'link show',
  'link list',
  'link status',
  'link state',
  'link advance',
  'link retire',
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
  'store set-settings',
  'store arrange',
  'store perform-on',
  'store add-set',
  'store remove-set',
  'store arrange-status',
  'store gym-check',
  'store skip',
  'store skip-remaining',
  'store skip-slot',
  'store substitute',
  'store revert-substitution',
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
  'progression reconcile',
  'progression retest',
  'progression reconcile-status',
  'progression reconcile-show',
  'progression reconcile-list',
  'progression show',
  'progression accept',
  'progression decline',
  'progression reopen',
  'program publish',
  'program show',
  'program list',
  'run create',
  'run gym',
  'run list',
  'run show',
  'run schedule',
  'run jump',
  'run start',
  'run skip',
  'run upgrade',
  'run upgrades',
  'run pause',
  'run resume',
  'import preview',
  'import apply',
  'import list',
  'import show',
  'import delete',
  'import series',
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
    'execution move' => {
      'id',
      'expectedVersion',
      'requestId',
      'at',
      'occurrenceId',
      'groupPath',
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
      'continuous',
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
    'store publish' => {'definition', 'expectedRevision', 'requireCatalog'},
    'store revision' => {'templateId', 'revision'},
    'store start' => {
      'id',
      'templateId',
      'revision',
      'startedAt',
      'bodyMassOverrides',
      'derivedPlan',
      'loadBindings',
      'loadConventions',
      'variants',
      'gym',
      'unboundSlots',
    },
    'store show' => {'id'},
    'store gym-check' => {
      'templateId',
      'revision',
      'gym',
      'loadBindings',
      'unboundSlots',
    },
    'store load-status' => {'id'},
    'store arrange-status' => {'id'},
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
    'repeat-checkpoint start-block' => {'id', 'sessionId', 'amrapId'},
    'progression block-propose' => {
      'sessionId',
      'amrapId',
      'roundSlotId',
      'rule',
    },
    'progression block-show' => {'sessionId', 'amrapId', 'roundSlotId'},
    'progression block-accept' => {
      'sessionId',
      'amrapId',
      'roundSlotId',
      'expectedVersion',
      'acceptedAt',
    },
    'progression block-decline' => {
      'sessionId',
      'amrapId',
      'roundSlotId',
      'expectedVersion',
      'declinedAt',
    },
    'progression block-track' => {
      'templateId',
      'amrapId',
      'roundSlotId',
      'runId',
      'asOf',
    },
    'repeat-checkpoint save' => {
      'id',
      'expectedVersion',
      'execution',
      'sessionId',
    },
    'repeat-checkpoint run' => {
      'id',
      'expectedVersion',
      'expectedExecutionVersion',
      'runForMilliseconds',
      'stream',
    },
    'repeat-checkpoint reserve' => {'id', 'expectedVersion'},
    'repeat-checkpoint release' => {'id', 'expectedVersion', 'confirm'},
    'repeat-checkpoint action' => {
      'id',
      'expectedVersion',
      'expectedExecutionVersion',
      'action',
      'review',
      'correction',
      'confirm',
      'elapsedMilliseconds',
      'ownerId',
      'ownerElapsedMilliseconds',
      'adjustmentMilliseconds',
    },
    'repeat-checkpoint show' => {'id'},
    'repeat-checkpoint list' => {'sessionId'},
    'repeat-checkpoint rounds' => {
      'sessionId',
      'runId',
      'from',
      'until',
      'includeActive',
    },
    'repeat-checkpoint series' => {
      'sessionId',
      'runId',
      'metric',
      'from',
      'until',
      'includeWarmups',
      'includeActive',
    },
    'repeat-checkpoint delete' => {'id', 'expectedVersion', 'confirm'},
    'checkpoint save' => {'id', 'sessionId', 'expectedVersion', 'clock'},
    'checkpoint start' => {'id', 'sessionId'},
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
      'includeImported',
      'importNamespace',
      'includeBlocks',
      'amrapId',
      'gym',
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
      'includeImported',
      'importNamespace',
      'includeBlocks',
      'gym',
    },
    'family publish' => {'family', 'expectedRevision', 'requireCatalog'},
    'family show' => {'familyId', 'revision'},
    'family list' => <String>{},
    'exercise publish' => {'exercise', 'expectedRevision'},
    'exercise show' => {'exerciseId', 'revision'},
    'exercise list' => <String>{},
    'catalog search' => {'query', 'locale', 'kinds', 'limit'},
    'store save-back' => {'id', 'mode', 'newTemplateId', 'confirm'},
    'preset publish' => {'preset', 'expectedRevision'},
    'preset show' => {'presetId', 'revision'},
    'preset list' => <String>{},
    'blueprint publish' => {'blueprint', 'expectedRevision'},
    'blueprint show' => {'blueprintId', 'revision'},
    'blueprint list' => <String>{},
    'blueprint preview' => {'blueprintId', 'revision', 'name', 'choices'},
    'blueprint instantiate' => {
      'blueprintId',
      'revision',
      'name',
      'choices',
      'expectedInstance',
      'requireCatalog',
    },
    'blueprint instances' => {'name'},
    'implementation publish' => {'implementation', 'expectedRevision'},
    'implementation show' => {'implementationId', 'revision'},
    'implementation list' => <String>{},
    'equipment publish' => {'equipment', 'expectedRevision'},
    'equipment show' => {'equipmentId', 'revision'},
    'equipment list' => <String>{},
    'gym publish' => {'gym', 'expectedRevision'},
    'gym show' => {'gymId', 'revision'},
    'gym list' => <String>{},
    'instance publish' => {'instance', 'expectedRevision'},
    'instance show' => {'instanceId', 'revision'},
    'instance list' => <String>{},
    'instance inventory' => {'gymId'},
    'store plate-plan' => {'instanceId', 'revision', 'target'},
    'store load-convention' => {
      'instanceId',
      'instanceRevision',
      'templateId',
      'templateRevision',
      'slotId',
      'convention',
      'mass',
      'repetitions',
    },
    'link create' => {'link', 'expectedRevision', 'createdAt', 'confirm'},
    'link show' => {'linkId', 'revision'},
    'link list' => <String>{},
    'link status' => {'link'},
    'link state' => {'linkId', 'asOf'},
    'link advance' => {
      'linkId',
      'nextSets',
      'failedSessions',
      'cursor',
      'expectedSequence',
      'at',
      'confirm',
    },
    'link retire' => {'linkId', 'memberAnchorId', 'retiredAt', 'confirm'},
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
      'variants',
    },
    'graph preview' => {
      'templateId',
      'revision',
      'graphId',
      'graphRevision',
      'asOf',
      'runId',
      'bindings',
      'variants',
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
    'store set-settings' => {'id', 'expectedVersion', 'setId', 'settings'},
    'store annotate' => {
      'id',
      'expectedVersion',
      'setId',
      'observations',
      'confirm',
    },
    'store arrange' => {
      'id',
      'expectedVersion',
      'setId',
      'arrangement',
      'confirm',
    },
    'store add-set' => {
      'id',
      'expectedVersion',
      'slotId',
      'role',
      'actuals',
      'observations',
      'settings',
    },
    'store remove-set' => {'id', 'expectedVersion', 'setId', 'confirm'},
    'store perform-on' => {
      'id',
      'expectedVersion',
      'setId',
      'instanceId',
      'unavailablePlates',
      'applyToRemaining',
      'confirm',
    },
    'store skip' => {'id', 'expectedVersion', 'setId', 'confirm'},
    'store skip-remaining' => {'id', 'expectedVersion', 'confirm'},
    'store skip-slot' => {'id', 'expectedVersion', 'slotId', 'role', 'confirm'},
    'store substitute' => {
      'id',
      'expectedVersion',
      'slotId',
      'scope',
      'setId',
      'composition',
      'targets',
    },
    'store revert-substitution' => {
      'id',
      'expectedVersion',
      'slotId',
      'scope',
      'setId',
    },
    'store edit-target' => {
      'id',
      'expectedVersion',
      'setId',
      'metric',
      'value',
      'applyToRemaining',
    },
    'store carry-actual' => {'id', 'expectedVersion', 'setId', 'metric'},
    'store finish' => {'id', 'expectedVersion', 'finishedAt', 'endedAt'},
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
      'preset',
      'countSubstitutes',
      'countOtherInstance',
    },
    'progression track' => {
      'templateId',
      'revision',
      'slotId',
      'role',
      'runId',
      'asOf',
    },
    'progression reconcile' => {
      'id',
      'templateId',
      'revision',
      'slotId',
      'role',
      'runId',
      'sessionId',
      'expectedSequence',
      'kinds',
      'reconciledAt',
      'rule',
      'ruleType',
      'resetFailures',
      'resetCursor',
      'confirm',
    },
    'progression retest' => {
      'id',
      'templateId',
      'revision',
      'slotId',
      'role',
      'runId',
      'sourceSessionId',
      'sourceSetId',
      'expectedSequence',
      'reseededAt',
      'confirm',
    },
    'progression reconcile-status' => {
      'templateId',
      'revision',
      'slotId',
      'role',
      'runId',
      'asOf',
      'sessionId',
      'rule',
      'ruleType',
    },
    'progression reconcile-show' => {'id'},
    'progression reconcile-list' => const <String>{},
    'progression show' => {'sessionId', 'slotId', 'role'},
    'progression accept' => {
      'sessionId',
      'slotId',
      'role',
      'expectedVersion',
      'acceptedAt',
      'selectedLevel',
    },
    'progression decline' => {
      'sessionId',
      'slotId',
      'role',
      'expectedVersion',
      'declinedAt',
    },
    'progression reopen' => {
      'sessionId',
      'slotId',
      'role',
      'expectedVersion',
      'confirm',
    },
    'import preview' => {'document'},
    'import apply' => {'document', 'importedAt', 'onChanged', 'confirm'},
    'import list' => {'namespace'},
    'import show' => {'namespace', 'sourceId'},
    'import delete' => {'namespace', 'sourceId', 'expectedVersion', 'confirm'},
    'import series' => {
      'metric',
      'namespace',
      'exerciseId',
      'exerciseName',
      'roles',
      'from',
      'until',
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
    'run create' => {'id', 'programId', 'revision', 'startedAt', 'loop', 'gym'},
    'run gym' => {'runId', 'expectedVersion', 'gym'},
    'run list' => {'status'},
    'run show' => {'runId'},
    'run schedule' => {'runId', 'count', 'includeScopes'},
    'run jump' => {
      'runId',
      'expectedVersion',
      'dayPath',
      'requestId',
      'at',
      'confirm',
    },
    'run start' => {
      'runId',
      'expectedVersion',
      'id',
      'startedAt',
      'bodyMassOverrides',
      'derivedPlan',
      'loadBindings',
      'loadConventions',
      'variants',
      'gym',
      'unboundSlots',
    },
    'run skip' => {'runId', 'expectedVersion', 'requestId', 'skippedAt'},
    'run upgrade' => {
      'runId',
      'expectedVersion',
      'revision',
      'requestId',
      'at',
      'confirm',
    },
    'run upgrades' => {'runId'},
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

  Set<String> unboundSlots() {
    if (request['unboundSlots'] == null) return const {};
    final ids = <String>{};
    for (final item in jsonList(request, 'unboundSlots')) {
      if (!ids.add(identifier({'unboundSlots': item}, 'unboundSlots')))
        invalid('unboundSlots names a slot twice.');
    }
    if (ids.isEmpty) invalid('unboundSlots, when given, names a slot.');
    return ids;
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

    /// Sessions for analytics: all, or only those started at `gym`.
    Future<List<TrainingSession>> analyticsSessions() async {
      final all = await store.sessions();
      if (!request.containsKey('gym')) return all;
      final gym = identifier(request, 'gym');
      await StoredTrainingService(store).latestGym(gym);
      return [
        for (final session in all)
          if (session.gymId == gym) session,
      ];
    }

    Future<Map<String, Object?>> runView(ProgramRun run) async {
      final bindings = await store.sessionPrograms();
      final current = run.current;
      final scoped =
          current == null || !run.program.definition.hasPrescriptionOverrides
          ? const <ScopedProgramOverride>[]
          : run.program.definition.effectiveOverrides(current.path);
      return {
        ...run.toJson(),
        'current': current?.toJson(),
        if (scoped.isNotEmpty)
          'effectiveOverrides': [
            for (final override in scoped) override.toJson(),
          ],
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
      case 'progression block-propose':
      case 'progression block-show':
      case 'progression block-accept':
      case 'progression block-decline':
        final blocks = BlockProgressionService(store);
        final sessionId = identifier(request, 'sessionId');
        final amrapId = identifier(request, 'amrapId');
        final roundSlotId = identifier(request, 'roundSlotId');
        final decision = switch (command) {
          'progression block-propose' => await blocks.propose(
            sessionId,
            amrapId,
            roundSlotId,
            BlockProgressionRule.fromJson(request['rule']),
          ),
          'progression block-accept' ||
          'progression block-decline' => await blocks.resolve(
            sessionId,
            amrapId,
            roundSlotId,
            expectedVersion: integer('expectedVersion'),
            at: command == 'progression block-accept'
                ? parseInstant(request['acceptedAt'], 'acceptedAt')
                : parseInstant(request['declinedAt'], 'declinedAt'),
            accept: command == 'progression block-accept',
          ),
          _ => await blocks.show(sessionId, amrapId, roundSlotId),
        };
        data = {
          'policy': blockProgressionPolicy,
          'applied': decision.status == 'accepted',
          'stale': decision.status == 'pending' && await blocks.stale(decision),
          ...decision.toJson(),
        };
      case 'progression block-track':
        data = await BlockProgressionService(store).track(
          templateId: identifier(request, 'templateId'),
          amrapId: identifier(request, 'amrapId'),
          roundSlotId: identifier(request, 'roundSlotId'),
          runId: request['runId'] == null ? null : identifier(request, 'runId'),
          asOf: parseInstant(request['asOf'], 'asOf'),
        );
      case 'repeat-checkpoint start-block':
        data = (await RepeatCheckpointService(store).startBlock(
          identifier(request, 'id'),
          identifier(request, 'sessionId'),
          identifier(request, 'amrapId'),
        )).toJson();
      case 'repeat-checkpoint save':
        data = (await RepeatCheckpointService(store).save(
          identifier(request, 'id'),
          integer('expectedVersion', min: 0),
          request['execution'],
          sessionId: request.containsKey('sessionId')
              ? identifier(request, 'sessionId')
              : null,
        )).toJson();
      case 'repeat-checkpoint action':
        data = (await RepeatCheckpointService(store).action(
          identifier(request, 'id'),
          expectedVersion: integer('expectedVersion'),
          expectedExecutionVersion: integer('expectedExecutionVersion'),
          action: requiredString(request, 'action'),
          review: request.containsKey('review')
              ? jsonObject(request['review'], 'review')
              : null,
          correction: request.containsKey('correction')
              ? jsonObject(request['correction'], 'correction')
              : null,
          elapsedMilliseconds: request.containsKey('elapsedMilliseconds')
              ? integer('elapsedMilliseconds')
              : null,
          ownerId: request.containsKey('ownerId')
              ? identifier(request, 'ownerId')
              : null,
          ownerElapsedMilliseconds:
              request.containsKey('ownerElapsedMilliseconds')
              ? integer('ownerElapsedMilliseconds', min: 0)
              : null,
          adjustmentMilliseconds: request.containsKey('adjustmentMilliseconds')
              ? integer('adjustmentMilliseconds', min: 0)
              : null,
          confirm: flag('confirm'),
        )).toJson();
      case 'repeat-checkpoint run':
        final limit = request.containsKey('runForMilliseconds')
            ? integer('runForMilliseconds')
            : null;
        if (limit != null && limit > 86400000)
          invalid('Foreground run limit exceeds 24 hours.');
        data = await runRepeatClock(
          store,
          identifier(request, 'id'),
          integer('expectedVersion'),
          integer('expectedExecutionVersion'),
          runForMilliseconds: limit,
          stream: flag('stream'),
        );
      case 'repeat-checkpoint reserve':
        data = (await RepeatCheckpointService(store).reserve(
          identifier(request, 'id'),
          integer('expectedVersion'),
        )).toJson();
      case 'repeat-checkpoint release':
        data = (await RepeatCheckpointService(store).release(
          identifier(request, 'id'),
          integer('expectedVersion'),
          confirm: flag('confirm'),
        )).toJson();
      case 'repeat-checkpoint show':
        data = (await RepeatCheckpointService(
          store,
        ).show(identifier(request, 'id'))).toJson();
      case 'repeat-checkpoint list':
        final sessionId = request.containsKey('sessionId')
            ? identifier(request, 'sessionId')
            : null;
        data = [
          for (final c in await RepeatCheckpointService(store).list())
            if (sessionId == null || c.sessionId == sessionId) c.toJson(),
        ];
      case 'repeat-checkpoint rounds':
        data = await store.transaction(
          () async => const RepeatHistory().rounds(
            await store.repeatCheckpoints(),
            await store.sessions(),
            runBySession: {
              for (final b in await store.sessionPrograms())
                b.sessionId: b.runId,
            },
            sessionId: request.containsKey('sessionId')
                ? identifier(request, 'sessionId')
                : null,
            runId: request.containsKey('runId')
                ? identifier(request, 'runId')
                : null,
            from: request.containsKey('from')
                ? parseInstant(request['from'], 'from')
                : null,
            until: request.containsKey('until')
                ? parseInstant(request['until'], 'until')
                : null,
            includeActive: flag('includeActive'),
          ),
        );
      case 'repeat-checkpoint series':
        data = await store.transaction(
          () async => const RepeatHistory().series(
            await store.repeatCheckpoints(),
            await store.sessions(),
            runBySession: {
              for (final b in await store.sessionPrograms())
                b.sessionId: b.runId,
            },
            sessionId: request.containsKey('sessionId')
                ? identifier(request, 'sessionId')
                : null,
            runId: request.containsKey('runId')
                ? identifier(request, 'runId')
                : null,
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
            includeActive: flag('includeActive'),
          ),
        );
      case 'repeat-checkpoint delete':
        final id = identifier(request, 'id');
        await RepeatCheckpointService(
          store,
        ).delete(id, integer('expectedVersion'), confirm: flag('confirm'));
        data = {'id': id, 'deleted': true};
      case 'checkpoint start':
        data = (await WindowCheckpointService(store).start(
          identifier(request, 'id'),
          identifier(request, 'sessionId'),
        )).toJson();
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
          continuous: flag('continuous'),
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
      case 'execution move':
        final e = await execution.move(
          identifier(request, 'id'),
          integer('expectedVersion'),
          identifier(request, 'requestId'),
          parseInstant(request['at'], 'at'),
          occurrenceId: request.containsKey('occurrenceId')
              ? requiredString(request, 'occurrenceId')
              : null,
          groupPath: request.containsKey('groupPath')
              ? requiredString(request, 'groupPath')
              : null,
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
      case 'import preview':
        data = await HistoryImportService(
          store,
        ).preview(HistoryImportDocument.fromJson(request['document']));
      case 'import apply':
        data = await HistoryImportService(store).apply(
          HistoryImportDocument.fromJson(request['document']),
          at: parseInstant(request['importedAt'], 'importedAt'),
          atText: requiredString(request, 'importedAt'),
          onChanged: request.containsKey('onChanged')
              ? requiredString(request, 'onChanged')
              : 'reject',
          confirm: flag('confirm'),
        );
      case 'import list':
        data = [
          for (final r in await HistoryImportService(store).list(
            namespace: request.containsKey('namespace')
                ? identifier(request, 'namespace')
                : null,
          ))
            r.summary,
        ];
      case 'import show':
        data = (await HistoryImportService(store).show(
          identifier(request, 'namespace'),
          sourceIdentifier(request, 'sourceId'),
        )).toJson();
      case 'import delete':
        data = (await HistoryImportService(store).delete(
          identifier(request, 'namespace'),
          sourceIdentifier(request, 'sourceId'),
          integer('expectedVersion'),
          confirm: flag('confirm'),
        )).toJson();
      case 'import series':
        Set<String>? roles;
        if (request.containsKey('roles')) {
          roles = {};
          for (final role in jsonList(request, 'roles')) {
            if (role is! String || !roles.add(role))
              invalid('roles must be distinct strings.');
          }
        }
        String? optional(String key) =>
            request.containsKey(key) ? requiredString(request, key) : null;
        data = await HistoryImportService(store).series(
          metric: identifier(request, 'metric'),
          namespace: request.containsKey('namespace')
              ? identifier(request, 'namespace')
              : null,
          exerciseId: optional('exerciseId'),
          exerciseName: optional('exerciseName'),
          roles: roles,
          from: optional('from'),
          until: optional('until'),
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
            offsetMinutes: parseOffsetMinutes(
              request['startedAt'],
              'startedAt',
            ),
            loop: request.containsKey('loop')
                ? flag('loop')
                : invalid(
                    'loop is required: true repeats the program, false ends '
                    'the run after its last day.',
                  ),
            gym: request['gym'] == null ? null : identifier(request, 'gym'),
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
          offsetMinutes: parseOffsetMinutes(request['startedAt'], 'startedAt'),
          bodyMassOverrides: bodyMassOverridesFromJson(
            request['bodyMassOverrides'],
          ),
          derivedPlan: request['derivedPlan'] == null
              ? null
              : DerivedPlanRef.fromJson(request['derivedPlan']),
          loadBindings: loadBindingsFromJson(request['loadBindings']),
          loadConventions: loadConventionsFromJson(request['loadConventions']),
          variantSettings: variantSettingsFromJson(request['variants']),
          gym: request['gym'] == null ? null : identifier(request, 'gym'),
          useRunGym: !request.containsKey('gym'),
          unboundSlots: unboundSlots(),
        )).toJson();
      case 'run gym':
        if (!request.containsKey('gym'))
          invalid('gym is required (null clears the run default).');
        data = await runView(
          await programs.setGym(
            identifier(request, 'runId'),
            integer('expectedVersion'),
            request['gym'] == null ? null : identifier(request, 'gym'),
          ),
        );
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
      case 'run upgrade':
        if (!flag('confirm')) invalid('Run upgrade requires confirm:true.');
        final runId = identifier(request, 'runId');
        final receipt = await programs.upgrade(
          runId,
          integer('expectedVersion'),
          integer('revision'),
          identifier(request, 'requestId'),
          parseInstant(request['at'], 'at'),
        );
        data = {
          'receipt': receipt.toJson(),
          'run': await runView(await programs.run(runId)),
        };
      case 'run jump':
        if (!flag('confirm')) invalid('Run jump requires confirm:true.');
        data = await runView(
          await programs.jump(
            identifier(request, 'runId'),
            integer('expectedVersion'),
            requiredString(request, 'dayPath'),
            identifier(request, 'requestId'),
            parseInstant(request['at'], 'at'),
          ),
        );
      case 'run upgrades':
        data = [
          for (final u in await programs.upgrades(identifier(request, 'runId')))
            u.toJson(),
        ];
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
      case 'progression reconcile-status':
        data = await StoredProgressionService(store).reconcileStatus(
          templateId: identifier(request, 'templateId'),
          revision: integer('revision'),
          slotId: identifier(request, 'slotId'),
          asOf: parseInstant(request['asOf'], 'asOf'),
          role: request.containsKey('role')
              ? requiredString(request, 'role')
              : 'work',
          runId: request.containsKey('runId')
              ? identifier(request, 'runId')
              : null,
          sessionId: request.containsKey('sessionId')
              ? identifier(request, 'sessionId')
              : null,
          rule: request.containsKey('rule')
              ? jsonObject(request['rule'], 'rule')
              : null,
          ruleType: request.containsKey('ruleType')
              ? requiredString(request, 'ruleType')
              : 'double',
        );
      case 'progression reconcile':
        {
          final kinds = [
            for (final value in jsonList(request, 'kinds'))
              value is String ? value : invalid('Invalid reconciliation kind.'),
          ];
          final receipt = await StoredProgressionService(store).reconcile(
            id: identifier(request, 'id'),
            templateId: identifier(request, 'templateId'),
            revision: integer('revision'),
            slotId: identifier(request, 'slotId'),
            expectedSequence: integer('expectedSequence', min: 0),
            kinds: kinds,
            reconciledAt: parseInstant(request['reconciledAt'], 'reconciledAt'),
            confirm: request['confirm'] == true,
            role: request.containsKey('role')
                ? requiredString(request, 'role')
                : 'work',
            runId: request.containsKey('runId')
                ? identifier(request, 'runId')
                : null,
            sessionId: request.containsKey('sessionId')
                ? identifier(request, 'sessionId')
                : null,
            rule: request.containsKey('rule')
                ? jsonObject(request['rule'], 'rule')
                : null,
            ruleType: request.containsKey('ruleType')
                ? requiredString(request, 'ruleType')
                : 'double',
            resetFailures: request['resetFailures'] == true,
            resetCursor: request['resetCursor'] == true,
          );
          data = reconciliationView(receipt);
        }
      case 'progression retest':
        data = reconciliationView(
          await StoredProgressionService(store).retest(
            id: identifier(request, 'id'),
            templateId: identifier(request, 'templateId'),
            revision: integer('revision'),
            slotId: identifier(request, 'slotId'),
            sourceSessionId: identifier(request, 'sourceSessionId'),
            sourceSetId: requiredString(request, 'sourceSetId'),
            expectedSequence: integer('expectedSequence', min: 0),
            reseededAt: parseInstant(request['reseededAt'], 'reseededAt'),
            confirm: request['confirm'] == true,
            role: request.containsKey('role')
                ? requiredString(request, 'role')
                : 'work',
            runId: request.containsKey('runId')
                ? identifier(request, 'runId')
                : null,
          ),
        );
      case 'progression reconcile-show':
        data = reconciliationView(
          await StoredProgressionService(
            store,
          ).reconciliation(identifier(request, 'id')),
        );
      case 'progression reconcile-list':
        data = {
          'reconciliations': [
            for (final receipt in await StoredProgressionService(
              store,
            ).reconciliations())
              reconciliationView(receipt),
          ],
        };
      case 'progression propose':
      case 'progression show':
      case 'progression accept':
      case 'progression decline':
      case 'progression reopen':
        final progression = StoredProgressionService(store);
        final sessionId = identifier(request, 'sessionId');
        final slotId = identifier(request, 'slotId');
        final role = request.containsKey('role')
            ? requiredString(request, 'role')
            : 'work';
        // A preset supplies the rule from one explicit published revision.
        ProgressionPresetRevision? preset;
        if (command == 'progression propose' && request.containsKey('preset')) {
          if (request.containsKey('rule') || request.containsKey('ruleType'))
            invalid('preset replaces rule and ruleType; supply only one.');
          final reference = presetReferenceFromJson(request['preset']);
          preset = await PresetService(
            store,
          ).revision(reference.id, reference.revision);
        }
        // One transaction, so the staleness check shares decoded records.
        final (decision, changed) = await store.transaction(() async {
          final decision = switch (command) {
            'progression propose' => await progression.propose(
              sessionId,
              slotId,
              preset?.preset.rule ?? jsonObject(request['rule'], 'rule'),
              ruleType:
                  preset?.preset.ruleType ??
                  (request.containsKey('ruleType')
                      ? requiredString(request, 'ruleType')
                      : 'double'),
              role: role,
              preset: preset == null
                  ? null
                  : (id: preset.preset.id, revision: preset.number),
              countSubstitutes: flag('countSubstitutes'),
              countOtherInstance: flag('countOtherInstance'),
            ),
            'progression accept' => await progression.accept(
              sessionId,
              slotId,
              integer('expectedVersion'),
              parseInstant(request['acceptedAt'], 'acceptedAt'),
              role: role,
              selectedLevel: request.containsKey('selectedLevel')
                  ? identifier(request, 'selectedLevel')
                  : null,
            ),
            'progression decline' => await progression.decline(
              sessionId,
              slotId,
              integer('expectedVersion'),
              parseInstant(request['declinedAt'], 'declinedAt'),
              role: role,
            ),
            'progression reopen' => await progression.reopen(
              sessionId,
              slotId,
              integer('expectedVersion'),
              role: role,
              confirm: flag('confirm'),
            ),
            _ => await progression.decision(sessionId, slotId, role: role),
          };
          return (decision, await progression.stale(decision));
        });
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
          if (decision.followed.isNotEmpty)
            'followedSettings': [for (final f in decision.followed) f.toJson()],
          if (decision.countedSubstitutes.isNotEmpty)
            'countedSubstitutes': decision.countedSubstitutes,
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
          requireCatalog: flag('requireCatalog'),
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
          startOffsetMinutes: parseOffsetMinutes(
            request['startedAt'],
            'startedAt',
          ),
          bodyMassOverrides: bodyMassOverridesFromJson(
            request['bodyMassOverrides'],
          ),
          derivedPlan: request['derivedPlan'] == null
              ? null
              : DerivedPlanRef.fromJson(request['derivedPlan']),
          loadBindings: loadBindingsFromJson(request['loadBindings']),
          loadConventions: loadConventionsFromJson(request['loadConventions']),
          variantSettings: variantSettingsFromJson(request['variants']),
          gym: request['gym'] == null ? null : identifier(request, 'gym'),
          unboundSlots: unboundSlots(),
        )).toJson();
      case 'store gym-check':
        data = (await service.gymCheck(
          identifier(request, 'templateId'),
          integer('revision'),
          identifier(request, 'gym'),
          loadBindings: loadBindingsFromJson(request['loadBindings']),
          unboundSlots: unboundSlots(),
        )).toJson();
      case 'store load-status':
        data = await store.transaction(() async {
          final session = await service.session(identifier(request, 'id'));
          final revisions = await store.equipmentInstanceRevisions();
          final equipment = await store.equipmentRevisions();
          final latest = <String, EquipmentInstanceRevision>{};
          for (final r in revisions) {
            final prior = latest[r.instance.id];
            if (prior == null || r.number > prior.number)
              latest[r.instance.id] = r;
          }
          return loadStatus(
            session.loadInputs,
            slotConventions: {
              for (final slot in session.definition.slots)
                slot.id: slot.convention,
            },
            instances: {
              for (final entry in session.loadInputs.entries)
                entry.key: (() {
                  final id = entry.value.instance?.instanceId;
                  final found = id == null ? null : latest[id];
                  return found == null
                      ? null
                      : instanceReference(found, equipment);
                })(),
            },
          );
        });
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
        final summarized = await service.session(identifier(request, 'id'));
        final rests = restTotals(
          await store.executions(sessionId: summarized.id),
        );
        data = {
          ...const TrainingAnalytics().summary(
            summarized,
            includeWarmups: flag('includeWarmups'),
            sumMetrics: analyticsSums(request),
            roles: analyticsRoles(request),
          ),
          // Guided traversals measure authored rests (walk intervals).
          'rests': ?rests,
        };
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
        if (request.containsKey('importNamespace') && !flag('includeImported'))
          invalid('importNamespace needs includeImported:true.');
        if (request.containsKey('amrapId') && !flag('includeBlocks'))
          invalid('amrapId needs includeBlocks:true.');
        if (request.containsKey('gym') && flag('includeImported'))
          invalid(
            'Imported history records no gym; drop gym or includeImported.',
          );
        data = await store.transaction(() async {
          final native = const ContextualRecords().evaluate(
            await analyticsSessions(),
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
          );
          final runBySession = {
            for (final b in await store.sessionPrograms()) b.sessionId: b.runId,
          };
          final context = jsonObject(
            request['context'] ?? <String, Object?>{},
            'context',
          );
          final from = request.containsKey('from')
              ? parseInstant(request['from'], 'from')
              : null;
          final until = request.containsKey('until')
              ? parseInstant(request['until'], 'until')
              : null;
          return {
            ...native,
            if (flag('includeBlocks'))
              'blocks': blockScoreRecords(
                await store.repeatCheckpoints(),
                await analyticsSessions(),
                runBySession: runBySession,
                context: context,
                amrapId: request.containsKey('amrapId')
                    ? identifier(request, 'amrapId')
                    : null,
                from: from,
                until: until,
              ),
            if (flag('includeImported'))
              'imported': importedRecordsBlock(
                await store.importedSessions(),
                metric: identifier(request, 'metric'),
                direction: requiredString(request, 'direction'),
                atActuals: metricsFromJson(
                  request['atActuals'] ?? <String, Object?>{},
                ),
                context: context,
                from: from,
                until: until,
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
                namespace: request.containsKey('importNamespace')
                    ? identifier(request, 'importNamespace')
                    : null,
                nativePointCount: native['pointCount']! as int,
              ),
          };
        });
      case 'store series':
        if (request.containsKey('familyRevision') &&
            !request.containsKey('familyId'))
          invalid('familyRevision needs familyId.');
        if (request.containsKey('importNamespace') && !flag('includeImported'))
          invalid('importNamespace needs includeImported:true.');
        if (request.containsKey('gym') && flag('includeImported'))
          invalid(
            'Imported history records no gym; drop gym or includeImported.',
          );
        data = await store.transaction(() async {
          final context = jsonObject(
            request['context'] ?? <String, Object?>{},
            'context',
          );
          final metric = request.containsKey('metric')
              ? identifier(request, 'metric')
              : null;
          final from = request.containsKey('from')
              ? parseInstant(request['from'], 'from')
              : null;
          final until = request.containsKey('until')
              ? parseInstant(request['until'], 'until')
              : null;
          final roles = analyticsRoles(request);
          final family = request.containsKey('familyId')
              ? await FamilyService(store).revision(
                  identifier(request, 'familyId'),
                  request.containsKey('familyRevision')
                      ? integer('familyRevision')
                      : null,
                )
              : null;
          final native = const TrainingAnalytics().series(
            await analyticsSessions(),
            runBySession: {
              for (final b in await store.sessionPrograms())
                b.sessionId: b.runId,
            },
            context: context,
            metric: metric,
            from: from,
            until: until,
            includeWarmups: flag('includeWarmups'),
            roles: roles,
            includeActive: flag('includeActive'),
            family: family,
          );
          final blocks = flag('includeBlocks')
              ? blockSeriesSection(
                  await store.repeatCheckpoints(),
                  await analyticsSessions(),
                  runBySession: {
                    for (final b in await store.sessionPrograms())
                      b.sessionId: b.runId,
                  },
                  context: context,
                  metric: metric,
                  from: from,
                  until: until,
                  includeWarmups: flag('includeWarmups'),
                  includeActive: flag('includeActive'),
                )
              : null;
          if (!flag('includeImported'))
            return blocks == null ? native : {...native, 'blocks': blocks};
          return {
            ...native,
            'blocks': ?blocks,
            'imported': importedSeriesBlock(
              await store.importedSessions(),
              context: context,
              metric: metric,
              from: from,
              until: until,
              includeWarmups: flag('includeWarmups'),
              roles: roles,
              family: family,
              namespace: request.containsKey('importNamespace')
                  ? identifier(request, 'importNamespace')
                  : null,
              nativePointCount: native['pointCount']! as int,
            ),
          };
        });
      case 'family publish':
        data = (await FamilyService(store).publish(
          ExerciseFamily.fromJson(request['family']),
          integer('expectedRevision', min: 0),
          requireCatalog: flag('requireCatalog'),
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
      case 'exercise publish':
        data = (await CatalogService(store).publishExercise(
          ExerciseDefinition.fromJson(request['exercise']),
          integer('expectedRevision', min: 0),
        )).toJson();
      case 'exercise show':
        data = (await CatalogService(store).exerciseRevision(
          identifier(request, 'exerciseId'),
          request.containsKey('revision') ? integer('revision') : null,
        )).toJson();
      case 'preset publish':
        data = (await PresetService(store).publish(
          ProgressionPreset.fromJson(request['preset']),
          integer('expectedRevision', min: 0),
        )).toJson();
      case 'preset show':
        data = (await PresetService(store).revision(
          identifier(request, 'presetId'),
          request.containsKey('revision') ? integer('revision') : null,
        )).toJson();
      case 'preset list':
        final presets = await store.progressionPresetRevisions();
        presets.sort((a, b) {
          final id = a.preset.id.compareTo(b.preset.id);
          return id == 0 ? a.number.compareTo(b.number) : id;
        });
        data = [for (final p in presets) p.toJson()];
      case 'blueprint publish':
        data = (await BlueprintService(store).publish(
          Blueprint.fromJson(request['blueprint']),
          integer('expectedRevision', min: 0),
        )).toJson();
      case 'blueprint show':
        data = (await BlueprintService(store).revision(
          identifier(request, 'blueprintId'),
          request.containsKey('revision') ? integer('revision') : null,
        )).toJson();
      case 'blueprint list':
        final all = await store.blueprintRevisions();
        all.sort((a, b) {
          final id = a.blueprint.id.compareTo(b.blueprint.id);
          return id == 0 ? a.number.compareTo(b.number) : id;
        });
        data = [for (final b in all) b.toJson()];
      case 'blueprint preview':
        data = await BlueprintService(store).preview(
          identifier(request, 'blueprintId'),
          integer('revision'),
          identifier(request, 'name'),
          jsonObject(request['choices'] ?? <String, Object?>{}, 'choices'),
        );
      case 'blueprint instantiate':
        data = (await BlueprintService(store).instantiate(
          identifier(request, 'blueprintId'),
          integer('revision'),
          identifier(request, 'name'),
          jsonObject(request['choices'] ?? <String, Object?>{}, 'choices'),
          expectedInstance: integer('expectedInstance', min: 0),
          requireCatalog: flag('requireCatalog'),
        )).toJson();
      case 'blueprint instances':
        final all =
            (await store.blueprintInstances())
                .where(
                  (i) =>
                      !request.containsKey('name') ||
                      i.id == identifier(request, 'name'),
                )
                .toList()
              ..sort((a, b) {
                final id = a.id.compareTo(b.id);
                return id == 0 ? a.number.compareTo(b.number) : id;
              });
        data = [for (final i in all) i.toJson()];
      case 'store save-back':
        data = await SaveBackService(store).saveBack(
          identifier(request, 'id'),
          mode: requiredString(request, 'mode'),
          newTemplateId: request.containsKey('newTemplateId')
              ? identifier(request, 'newTemplateId')
              : null,
          confirm: flag('confirm'),
        );
      case 'catalog search':
        data = searchCatalog(
          query: requiredString(request, 'query'),
          locale: request.containsKey('locale')
              ? requiredString(request, 'locale')
              : null,
          kinds: request.containsKey('kinds')
              ? [
                  for (final k in jsonList(request, 'kinds'))
                    k is String ? k : invalid('kinds must list strings.'),
                ]
              : catalogSearchKinds,
          limit: request.containsKey('limit') ? integer('limit') : 50,
          exercises: await store.exerciseRevisions(),
          implementations: await store.implementationRevisions(),
          equipment: await store.equipmentRevisions(),
        );
      case 'exercise list':
        final all = await store.exerciseRevisions();
        all.sort((a, b) {
          final id = a.exercise.id.compareTo(b.exercise.id);
          return id == 0 ? a.number.compareTo(b.number) : id;
        });
        data = [for (final e in all) e.toJson()];
      case 'implementation publish':
        data = (await CatalogService(store).publishImplementation(
          ExerciseImplementation.fromJson(request['implementation']),
          integer('expectedRevision', min: 0),
        )).toJson();
      case 'implementation show':
        data = (await CatalogService(store).implementationRevision(
          identifier(request, 'implementationId'),
          request.containsKey('revision') ? integer('revision') : null,
        )).toJson();
      case 'implementation list':
        final all = await store.implementationRevisions();
        all.sort((a, b) {
          final id = a.implementation.id.compareTo(b.implementation.id);
          return id == 0 ? a.number.compareTo(b.number) : id;
        });
        data = [for (final i in all) i.toJson()];
      case 'equipment publish':
        data = (await EquipmentService(store).publishEquipment(
          EquipmentDefinition.fromJson(request['equipment']),
          integer('expectedRevision', min: 0),
        )).toJson();
      case 'equipment show':
        data = (await EquipmentService(store).equipmentRevision(
          identifier(request, 'equipmentId'),
          request.containsKey('revision') ? integer('revision') : null,
        )).toJson();
      case 'equipment list':
        final all = await store.equipmentRevisions();
        all.sort((a, b) {
          final id = a.equipment.id.compareTo(b.equipment.id);
          return id == 0 ? a.number.compareTo(b.number) : id;
        });
        data = [for (final e in all) e.toJson()];
      case 'gym publish':
        data = (await EquipmentService(store).publishGym(
          GymDefinition.fromJson(request['gym']),
          integer('expectedRevision', min: 0),
        )).toJson();
      case 'gym show':
        data = (await EquipmentService(store).gymRevision(
          identifier(request, 'gymId'),
          request.containsKey('revision') ? integer('revision') : null,
        )).toJson();
      case 'gym list':
        final all = await store.gymRevisions();
        all.sort((a, b) {
          final id = a.gym.id.compareTo(b.gym.id);
          return id == 0 ? a.number.compareTo(b.number) : id;
        });
        data = [for (final g in all) g.toJson()];
      case 'instance publish':
        data = (await EquipmentService(store).publishInstance(
          EquipmentInstance.fromJson(request['instance']),
          integer('expectedRevision', min: 0),
        )).toJson();
      case 'instance show':
        data = (await EquipmentService(store).instanceRevision(
          identifier(request, 'instanceId'),
          request.containsKey('revision') ? integer('revision') : null,
        )).toJson();
      case 'instance list':
        final all = await store.equipmentInstanceRevisions();
        all.sort((a, b) {
          final id = a.instance.id.compareTo(b.instance.id);
          return id == 0 ? a.number.compareTo(b.number) : id;
        });
        data = [for (final i in all) i.toJson()];
      case 'instance inventory':
        data = [
          for (final revision in await EquipmentService(store).inventory(
            gymId: request.containsKey('gymId')
                ? identifier(request, 'gymId')
                : null,
          ))
            revision.toJson(),
        ];
      case 'store plate-plan':
        data = await EquipmentService(store).platePlan(
          identifier(request, 'instanceId'),
          Quantity.fromJson(request['target']),
          request.containsKey('revision') ? integer('revision') : null,
        );
      case 'store load-convention':
        data = await EquipmentService(store).loadConvention(
          instanceId: identifier(request, 'instanceId'),
          revision: request.containsKey('instanceRevision')
              ? integer('instanceRevision', min: 1)
              : null,
          templateId: request.containsKey('templateId')
              ? identifier(request, 'templateId')
              : null,
          templateRevision: request.containsKey('templateRevision')
              ? integer('templateRevision', min: 1)
              : null,
          slotId: request.containsKey('slotId')
              ? identifier(request, 'slotId')
              : null,
          explicit: request.containsKey('convention')
              ? LoadConvention.fromJson(request['convention'])
              : null,
          mass: request.containsKey('mass')
              ? Quantity.fromJson(request['mass'])
              : null,
          repetitions: request.containsKey('repetitions')
              ? Quantity.fromJson(request['repetitions'])
              : null,
        );
      case 'link create':
        data = (await LeverLinkService(store).create(
          input: jsonObject(request['link'], 'link'),
          createdAt: parseInstant(request['createdAt'], 'createdAt'),
          expectedRevision: integer('expectedRevision', min: 0),
          confirm: request['confirm'] == true,
        )).toJson();
      case 'link show':
        data = (await LeverLinkService(store).revision(
          identifier(request, 'linkId'),
          request.containsKey('revision') ? integer('revision') : null,
        )).toJson();
      case 'link list':
        data = [
          for (final l in await LeverLinkService(store).list()) l.toJson(),
        ];
      case 'link status':
        data = await LeverLinkService(
          store,
        ).status(jsonObject(request['link'], 'link'));
      case 'link state':
        data = await LeverLinkService(store).state(
          identifier(request, 'linkId'),
          request.containsKey('asOf')
              ? parseInstant(request['asOf'], 'asOf')
              : null,
        );
      case 'link advance':
        data = (await LeverLinkService(store).advance(
          linkId: identifier(request, 'linkId'),
          nextSets: jsonList(request, 'nextSets'),
          failedSessions: integer('failedSessions', min: 0),
          cursor: request.containsKey('cursor')
              ? integer('cursor', min: 0)
              : null,
          expectedSequence: integer('expectedSequence', min: 0),
          at: parseInstant(request['at'], 'at'),
          confirm: request['confirm'] == true,
        )).toJson();
      case 'link retire':
        data = (await LeverLinkService(store).retire(
          linkId: identifier(request, 'linkId'),
          memberAnchorId: anchorReference(
            request['memberAnchorId'],
            'memberAnchorId',
          ),
          retiredAt: parseInstant(request['retiredAt'], 'retiredAt'),
          confirm: request['confirm'] == true,
        )).toJson();
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
          variantSelections: request.containsKey('variants')
              ? variantSelectionsFromJson(request['variants'])
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
          variantSelections: request.containsKey('variants')
              ? variantSelectionsFromJson(request['variants'])
              : null,
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
      case 'store set-settings':
        final setId = requiredString(request, 'setId');
        final performed = performedSettingsFromJson(request['settings']);
        data = (await service.edit(
          identifier(request, 'id'),
          integer('expectedVersion'),
          (s) => const TrainingService().recordSettings(s, setId, performed),
        )).toJson();
      case 'store arrange':
        final setId = requiredString(request, 'setId');
        data = (await service.edit(
          identifier(request, 'id'),
          integer('expectedVersion'),
          (s) => const TrainingService().arrange(
            s,
            setId,
            request['arrangement'] == null
                ? null
                : LoadArrangement.fromJson(request['arrangement']),
            confirm: flag('confirm'),
          ),
        )).toJson();
      case 'store add-set':
        data = (await service.edit(
          identifier(request, 'id'),
          integer('expectedVersion'),
          (s) => const TrainingService().addSet(
            s,
            identifier(request, 'slotId'),
            role: request.containsKey('role')
                ? requiredString(request, 'role')
                : 'warmup',
            actuals: metricsFromJson(request['actuals']),
            observations: request['observations'] == null
                ? null
                : SetObservations.fromJson(request['observations']),
            settings: request['settings'] == null
                ? const {}
                : categoricalSettingsFromJson(request['settings'], 'settings'),
          ),
        )).toJson();
      case 'store remove-set':
        data = (await service.edit(
          identifier(request, 'id'),
          integer('expectedVersion'),
          (s) => const TrainingService().removeSet(
            s,
            requiredString(request, 'setId'),
            confirm: flag('confirm'),
          ),
        )).toJson();
      case 'store perform-on':
        final setId = requiredString(request, 'setId');
        if (!request.containsKey('instanceId'))
          invalid('instanceId is required (null clears it).');
        data = await store.transaction(() async {
          // The latest published revision is frozen on the set.
          final instance = request['instanceId'] == null
              ? null
              : await EquipmentService(
                  store,
                ).instanceRevision(identifier(request, 'instanceId'));
          final reference = instance == null
              ? null
              : instanceReference(instance, await store.equipmentRevisions());
          final session = await service.edit(
            identifier(request, 'id'),
            integer('expectedVersion'),
            (s) => const TrainingService().performOn(
              s,
              setId,
              reference,
              unavailablePlates: [
                for (final p
                    in request['unavailablePlates'] == null
                        ? const <Object?>[]
                        : jsonList(request, 'unavailablePlates'))
                  PlateUsage.fromJson(p),
              ],
              applyToRemaining: flag('applyToRemaining'),
              confirm: flag('confirm'),
            ),
          );
          return {
            'session': session.toJson(),
            // What to set on that instance to follow each target.
            if (reference != null)
              'settings': [
                for (final set in session.sets)
                  if (set.performedOn?.instanceId == reference.instanceId)
                    for (final entry in set.suggested.entries)
                      if (nearestSettings(
                            reference.snapshot,
                            entry.value,
                            loading: set.availableLoading,
                          )
                          case final settings when settings.isNotEmpty)
                        {
                          'setId': set.id,
                          'metric': entry.key,
                          'target': entry.value.toJson(),
                          'settings': [for (final q in settings) q.toJson()],
                        },
              ],
          };
        });
      case 'store arrange-status':
        data = await EquipmentService(
          store,
        ).arrangeStatus(identifier(request, 'id'));
      case 'store skip-remaining':
        data = (await service.skipRemaining(
          identifier(request, 'id'),
          integer('expectedVersion'),
          confirm: flag('confirm'),
        )).toJson();
      case 'store substitute':
        data = (await service.substitute(
          identifier(request, 'id'),
          integer('expectedVersion'),
          slotId: requiredString(request, 'slotId'),
          scope: requiredString(request, 'scope'),
          setId: request.containsKey('setId')
              ? requiredString(request, 'setId')
              : null,
          composition: SubstituteComposition.fromJson(request['composition']),
          targets: substitutionTargets(request['targets']),
        )).toJson();
      case 'store revert-substitution':
        data = (await service.revertSubstitution(
          identifier(request, 'id'),
          integer('expectedVersion'),
          slotId: requiredString(request, 'slotId'),
          scope: requiredString(request, 'scope'),
          setId: request.containsKey('setId')
              ? requiredString(request, 'setId')
              : null,
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
        final finishOffset = parseOffsetMinutes(
          request['finishedAt'],
          'finishedAt',
        );
        data = (await service.edit(
          identifier(request, 'id'),
          integer('expectedVersion'),
          (s) => s.finish(
            finishedAt,
            offsetMinutes: finishOffset,
            endedAt: request.containsKey('endedAt')
                ? parseInstant(request['endedAt'], 'endedAt')
                : null,
          ),
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
