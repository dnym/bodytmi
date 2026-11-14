import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'analytics_options.dart';
import 'session_window_clock_adapter.dart';

const commandNames = [
  'quantity normalize',
  'target resolve',
  'target capture',
  'target status',
  'graph validate',
  'objective evaluate',
  'session assess-objectives',
  'scale validate',
  'scale resolve',
  'plate plan',
  'convention validate',
  'import validate',
  'convention interpret',
  'template validate',
  'template publish',
  'activity expand',
  'activity groups',
  'activity window-status',
  'activity window-crossing',
  'activity window-transition',
  'activity window-clock',
  'activity window-repeat-page',
  'activity window-repeat-cursor',
  'activity window-repeat-execution',
  'tempo sample',
  'session start',
  'session show',
  'session load-status',
  'session summary',
  'session rounds',
  'session window-clock',
  'session window-review',
  'session progression-preview',
  'history series',
  'history repeat-series',
  'history repeat-rounds',
  'history records',
  'family validate',
  'session mass-status',
  'session mass-refresh',
  'session mass-rebind',
  'session effective-load',
  'session complete',
  'session annotate',
  'session arrange',
  'session arrange-status',
  'session edit-target',
  'session carry-actual',
  'session skip',
  'session skip-remaining',
  'session skip-slot',
  'session finish',
  'progression evaluate',
  'progression double',
  'progression ordinal',
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
      case 'target resolve':
        keys({'nodes'});
        data = const DerivedTargets().resolve(request['nodes']);
      case 'target capture':
        keys({'graph', 'bindings'});
        data = const DerivedTargetSnapshot().capture(
          request['graph'],
          request['bindings'],
        );
      case 'target status':
        keys({'snapshot', 'bindings'});
        data = const DerivedTargetSnapshot().status(
          request['snapshot'],
          request['bindings'],
        );
      case 'graph validate':
        keys({'graph'});
        data = DerivedTargetGraph.fromJson(request['graph']).toJson();
      case 'objective evaluate':
        keys({'objectives', 'actuals'});
        data = const ObjectiveAssessment().evaluate(
          request['objectives'],
          metricsFromJson(request['actuals'] ?? <String, Object?>{}),
        );
      case 'session assess-objectives':
        keys({'session', 'setId', 'objectives'});
        data = const TrainingService().assessObjectives(
          sessionFromJson(request['session']),
          requiredString(request, 'setId'),
          request['objectives'],
        );
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
      case 'activity groups':
        keys({'definition', 'containing'});
        final definition = WorkoutDefinition.fromJson(request['definition']);
        final containing = request['containing'];
        if (request.containsKey('containing') &&
            (containing is! int || containing < 0))
          invalid('containing must be a nonnegative occurrence index.');
        final occurrences = definition.plan.occurrences().toList();
        if (containing is int && containing >= occurrences.length)
          invalid('containing must refer to an occurrence.');
        data = {
          'policy': 'bodytmi-activity-groups/1',
          'occurrenceCount': occurrences.length,
          'containing': containing,
          'groups': [
            for (final group in activityGroups(
              definition.plan,
              containing: containing as int?,
            ))
              group.toJson(),
          ],
        };
      case 'activity window-repeat-execution':
        keys({
          'action',
          'loop',
          'execution',
          'expectedVersion',
          'ownerId',
          'ownerElapsedMilliseconds',
          'adjustmentMilliseconds',
          'confirm',
          'review',
          'correction',
        });
        final action = requiredString(request, 'action');
        const repeatExecution = WindowRepeatExecution();
        if (action == 'start') {
          if (request.keys.any(
            (key) => !{'schemaVersion', 'action', 'loop'}.contains(key),
          ))
            invalid('Starting a repeat execution takes only loop.');
          data = repeatExecution.view(
            repeatExecution.start(WindowRepeatSpec.fromJson(request['loop'])),
          );
        } else if (action == 'show') {
          if (request.keys.any(
            (key) => !{'schemaVersion', 'action', 'execution'}.contains(key),
          ))
            invalid('Showing a repeat execution takes only execution.');
          data = repeatExecution.view(request['execution']);
        } else {
          if (request.containsKey('loop'))
            invalid('Loop is pinned inside the execution.');
          final version = request['expectedVersion'];
          final sample = request['ownerElapsedMilliseconds'];
          final adjustment = request['adjustmentMilliseconds'];
          if (version is! int ||
              version < 1 ||
              (request.containsKey('ownerElapsedMilliseconds') &&
                  sample is! int) ||
              (request.containsKey('adjustmentMilliseconds') &&
                  adjustment is! int))
            invalid(
              'Execution version, samples and adjustments must be integers.',
            );
          data = repeatExecution.view(
            repeatExecution.apply(
              request['execution'],
              expectedVersion: version,
              action: action,
              ownerId: request.containsKey('ownerId')
                  ? identifier(request, 'ownerId')
                  : null,
              ownerElapsedMilliseconds: sample as int?,
              adjustmentMilliseconds: adjustment as int?,
              confirm: _bool(request, 'confirm'),
              review: request.containsKey('review')
                  ? jsonObject(request['review'], 'review')
                  : null,
              correction: request.containsKey('correction')
                  ? jsonObject(request['correction'], 'correction')
                  : null,
            ),
          );
        }
      case 'activity window-repeat-cursor':
        keys({
          'action',
          'loop',
          'cursor',
          'expectedVersion',
          'ownerId',
          'ownerElapsedMilliseconds',
          'adjustmentMilliseconds',
          'confirm',
        });
        final action = requiredString(request, 'action');
        const repeatCursor = WindowRepeatCursor();
        if (action == 'start') {
          if (request.keys.any(
            (key) => !{'schemaVersion', 'action', 'loop'}.contains(key),
          ))
            invalid('Starting a repeat cursor takes only loop.');
          data = repeatCursor.view(
            repeatCursor.start(WindowRepeatSpec.fromJson(request['loop'])),
          );
        } else if (action == 'show') {
          if (request.keys.any(
            (key) => !{'schemaVersion', 'action', 'cursor'}.contains(key),
          ))
            invalid('Showing a repeat cursor takes only cursor.');
          data = repeatCursor.view(request['cursor']);
        } else {
          if (request.containsKey('loop'))
            invalid('Loop is pinned inside the cursor.');
          final version = request['expectedVersion'];
          final sample = request['ownerElapsedMilliseconds'];
          final adjustment = request['adjustmentMilliseconds'];
          if (version is! int ||
              version < 1 ||
              (request.containsKey('ownerElapsedMilliseconds') &&
                  sample is! int) ||
              (request.containsKey('adjustmentMilliseconds') &&
                  adjustment is! int))
            invalid(
              'Cursor version, samples and adjustments must be integers.',
            );
          data = repeatCursor.view(
            repeatCursor.apply(
              request['cursor'],
              expectedVersion: version,
              action: action,
              ownerId: request.containsKey('ownerId')
                  ? identifier(request, 'ownerId')
                  : null,
              ownerElapsedMilliseconds: sample as int?,
              adjustmentMilliseconds: adjustment as int?,
              confirm: _bool(request, 'confirm'),
            ),
          );
        }
      case 'activity window-repeat-page':
        keys({'loop', 'round', 'elapsedMilliseconds', 'offset', 'limit'});
        int number(String key, {required int defaultValue}) {
          final value = request.containsKey(key) ? request[key] : defaultValue;
          if (value is! int) invalid('$key must be an integer.');
          return value;
        }
        if (!request.containsKey('round') ||
            !request.containsKey('elapsedMilliseconds'))
          invalid('round and elapsedMilliseconds are required.');
        data = const WindowRepeatPreview().page(
          WindowRepeatSpec.fromJson(request['loop']),
          round: number('round', defaultValue: 0),
          elapsedMilliseconds: number('elapsedMilliseconds', defaultValue: 0),
          offset: number('offset', defaultValue: 0),
          limit: number('limit', defaultValue: 100),
        );
      case 'activity window-status':
        keys({
          'definition',
          'occurrence',
          'elapsedMilliseconds',
          'windowStarts',
        });
        final occurrence = request['occurrence'];
        final elapsed = request['elapsedMilliseconds'];
        if (occurrence is! int || elapsed is! int)
          invalid('occurrence and elapsedMilliseconds must be integers.');
        data = const WindowDeadlines().evaluate(
          definition: WorkoutDefinition.fromJson(request['definition']),
          occurrence: occurrence,
          elapsedMilliseconds: elapsed,
          windowStarts: jsonObject(request['windowStarts'], 'windowStarts'),
        );
      case 'activity window-crossing':
        keys({
          'definition',
          'occurrence',
          'previousElapsedMilliseconds',
          'elapsedMilliseconds',
          'windowStarts',
        });
        final occurrence = request['occurrence'];
        final previous = request['previousElapsedMilliseconds'];
        final elapsed = request['elapsedMilliseconds'];
        if (occurrence is! int || previous is! int || elapsed is! int)
          invalid('occurrence and elapsed samples must be integers.');
        data = const WindowDeadlines().crossing(
          definition: WorkoutDefinition.fromJson(request['definition']),
          occurrence: occurrence,
          previousElapsedMilliseconds: previous,
          elapsedMilliseconds: elapsed,
          windowStarts: jsonObject(request['windowStarts'], 'windowStarts'),
        );
      case 'activity window-transition':
        keys({
          'definition',
          'fromOccurrence',
          'toOccurrence',
          'elapsedMilliseconds',
          'windowStarts',
        });
        final from = request['fromOccurrence'];
        final to = request['toOccurrence'];
        final elapsed = request['elapsedMilliseconds'];
        if (from is! int || to is! int || elapsed is! int)
          invalid(
            'Occurrence indices and elapsedMilliseconds must be integers.',
          );
        data = const WindowDeadlines().transition(
          definition: WorkoutDefinition.fromJson(request['definition']),
          fromOccurrence: from,
          toOccurrence: to,
          elapsedMilliseconds: elapsed,
          windowStarts: jsonObject(request['windowStarts'], 'windowStarts'),
        );
      case 'activity window-clock':
        keys({
          'definition',
          'action',
          'clock',
          'expectedVersion',
          'ownerId',
          'ownerElapsedMilliseconds',
          'toOccurrence',
          'adjustmentMilliseconds',
        });
        final definition = WorkoutDefinition.fromJson(request['definition']);
        final action = requiredString(request, 'action');
        if (action == 'start') {
          if (request.keys.any(
            (key) => !{'schemaVersion', 'definition', 'action'}.contains(key),
          ))
            invalid('Starting a window clock takes only a definition.');
          data = const WindowClock().start(definition);
        } else {
          final version = request['expectedVersion'];
          final ownerElapsed = request['ownerElapsedMilliseconds'];
          final to = request['toOccurrence'];
          final adjustment = request['adjustmentMilliseconds'];
          if (version is! int ||
              version < 1 ||
              (request.containsKey('ownerElapsedMilliseconds') &&
                  ownerElapsed is! int) ||
              (request.containsKey('toOccurrence') && to is! int) ||
              (request.containsKey('adjustmentMilliseconds') &&
                  adjustment is! int))
            invalid(
              'Clock versions, samples and occurrence indices must be integers.',
            );
          data = const WindowClock().apply(
            definition,
            request['clock'],
            expectedVersion: version,
            action: action,
            ownerId: request.containsKey('ownerId')
                ? identifier(request, 'ownerId')
                : null,
            ownerElapsedMilliseconds: ownerElapsed as int?,
            toOccurrence: to as int?,
            adjustmentMilliseconds: adjustment as int?,
          );
        }
      case 'tempo sample':
        keys({
          'tempo',
          'previousElapsedMilliseconds',
          'elapsedMilliseconds',
          'includeInitial',
        });
        final plan = TempoPlan.fromJson(request['tempo']);
        final previous = request['previousElapsedMilliseconds'];
        final elapsed = request['elapsedMilliseconds'];
        if (previous is! int || elapsed is! int)
          invalid('Tempo samples must use integer milliseconds.');
        final position = plan.position(elapsed);
        final cue = plan.cueAt(
          previous,
          elapsed,
          includeInitial: _bool(request, 'includeInitial'),
        );
        data = {
          'policy': 'bodytmi-tempo-sample/1',
          'previousElapsedMilliseconds': previous,
          'elapsedMilliseconds': elapsed,
          'includeInitial': _bool(request, 'includeInitial'),
          'position': position.toJson(),
          'cue': cue?.toJson(),
        };
      case 'session start':
        keys({
          'id',
          'revision',
          'startedAt',
          'history',
          'bodyMassMeasurements',
          'bodyMassOverrides',
          'loadInstances',
          'loadConventions',
        });
        final history = request['history'] ?? <Object?>[];
        if (history is! List<Object?>) invalid('history must be an array.');
        data = const TrainingService()
            .start(
              sessionId: identifier(request, 'id'),
              revision: WorkoutRevision.fromJson(request['revision']),
              startedAt: parseInstant(request['startedAt'], 'startedAt'),
              history: [for (final item in history) sessionFromJson(item)],
              bodyMassMeasurements: [
                for (final m
                    in (request.containsKey('bodyMassMeasurements')
                        ? jsonList(request, 'bodyMassMeasurements')
                        : <Object?>[]))
                  BodyMassMeasurement.fromJson(m),
              ],
              bodyMassOverrides: bodyMassOverridesFromJson(
                request['bodyMassOverrides'],
              ),
              loadInstances: loadInstancesFromJson(request['loadInstances']),
              loadConventions: loadConventionsFromJson(
                request['loadConventions'],
              ),
            )
            .toJson();
      case 'session load-status':
        keys({'session', 'instances'});
        final session = sessionFromJson(request['session']);
        data = loadStatus(
          session.loadInputs,
          slotConventions: {
            for (final slot in session.revision.definition.slots)
              slot.id: slot.convention,
          },
          instances: loadInstancesFromJson(request['instances']),
        );
      case 'session window-clock':
        keys({
          'session',
          'action',
          'clock',
          'expectedVersion',
          'ownerId',
          'ownerElapsedMilliseconds',
          'toOccurrence',
          'adjustmentMilliseconds',
        });
        data = sessionWindowClockRequest(
          sessionFromJson(request['session']),
          request,
        );
      case 'session window-review':
        keys({
          'session',
          'clock',
          'expectedSessionVersion',
          'expectedClockVersion',
          'toOccurrence',
          'action',
          'actuals',
          'acceptSuggested',
          'observations',
          'confirm',
        });
        final result = sessionWindowReviewRequest(
          sessionFromJson(request['session']),
          request,
        );
        data = {
          'session': result.session.toJson(),
          'clock': result.clock,
          'occurrenceId': result.occurrenceId,
        };
      case 'session effective-load':
        keys({'session'});
        data = const EffectiveMassService().evaluate(
          sessionFromJson(request['session']),
        );
      case 'session mass-rebind':
        keys({'session', 'measurements', 'bodyMassOverrides', 'confirm'});
        data = const TrainingService()
            .rebindBodyMass(
              sessionFromJson(request['session']),
              [
                for (final m in jsonList(request, 'measurements'))
                  BodyMassMeasurement.fromJson(m),
              ],
              bodyMassRebindingsFromJson(request['bodyMassOverrides']),
              confirm: _bool(request, 'confirm'),
            )
            .toJson();
      case 'session mass-refresh':
        keys({'session', 'measurements', 'confirm'});
        data = const TrainingService().refreshBodyMass(
          sessionFromJson(request['session']),
          [
            for (final m in jsonList(request, 'measurements'))
              BodyMassMeasurement.fromJson(m),
          ],
          confirm: _bool(request, 'confirm'),
        ).toJson();
      case 'session mass-status':
        keys({'session', 'measurements'});
        data = const TrainingService()
            .bodyMassStatus(sessionFromJson(request['session']), [
              for (final m in jsonList(request, 'measurements'))
                BodyMassMeasurement.fromJson(m),
            ]);
      case 'session show':
        keys({'session'});
        data = sessionFromJson(request['session']).toJson();
      case 'session summary':
        keys({'session', 'includeWarmups', 'sumMetrics', 'roles'});
        data = const TrainingAnalytics().summary(
          sessionFromJson(request['session']),
          includeWarmups: _bool(request, 'includeWarmups'),
          sumMetrics: analyticsSums(request),
          roles: analyticsRoles(request),
        );
      case 'session rounds':
        keys({'session', 'groupPath'});
        data = const RoundProgress().evaluate(
          sessionFromJson(request['session']),
          requiredString(request, 'groupPath'),
        );
      case 'session progression-preview':
        keys({'session', 'slotId', 'role', 'ruleType', 'rule', 'state'});
        data = roleProgressionPreview(
          sessionFromJson(request['session']),
          request,
        );
      case 'history records':
        keys({
          'sessions',
          'runBySession',
          'context',
          'metric',
          'direction',
          'atActuals',
          'from',
          'until',
          'includeWarmups',
          'roles',
          'family',
        });
        data = const ContextualRecords().evaluate(
          [for (final s in jsonList(request, 'sessions')) sessionFromJson(s)],
          metric: identifier(request, 'metric'),
          direction: requiredString(request, 'direction'),
          atActuals: metricsFromJson(
            request['atActuals'] ?? <String, Object?>{},
          ),
          runBySession: analyticsBindings(request),
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
          includeWarmups: _bool(request, 'includeWarmups'),
          roles: analyticsRoles(request),
          family: request.containsKey('family')
              ? FamilyRevision.fromJson(request['family'])
              : null,
        );
      case 'history repeat-rounds':
        keys({
          'checkpoints',
          'sessions',
          'runBySession',
          'sessionId',
          'runId',
          'from',
          'until',
          'includeActive',
        });
        data = const RepeatHistory().rounds(
          [
            for (final c in jsonList(request, 'checkpoints'))
              RepeatCheckpoint.fromJson(c),
          ],
          [for (final s in jsonList(request, 'sessions')) sessionFromJson(s)],
          runBySession: analyticsBindings(request),
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
          includeActive: _bool(request, 'includeActive'),
        );
      case 'history repeat-series':
        keys({
          'checkpoints',
          'sessions',
          'runBySession',
          'sessionId',
          'runId',
          'metric',
          'from',
          'until',
          'includeWarmups',
          'includeActive',
        });
        data = const RepeatHistory().series(
          [
            for (final c in jsonList(request, 'checkpoints'))
              RepeatCheckpoint.fromJson(c),
          ],
          [for (final s in jsonList(request, 'sessions')) sessionFromJson(s)],
          runBySession: analyticsBindings(request),
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
          includeWarmups: _bool(request, 'includeWarmups'),
          includeActive: _bool(request, 'includeActive'),
        );
      case 'history series':
        keys({
          'sessions',
          'runBySession',
          'context',
          'metric',
          'from',
          'until',
          'includeWarmups',
          'roles',
          'includeActive',
          'family',
        });
        data = const TrainingAnalytics().series(
          [for (final s in jsonList(request, 'sessions')) sessionFromJson(s)],
          runBySession: analyticsBindings(request),
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
          includeWarmups: _bool(request, 'includeWarmups'),
          roles: analyticsRoles(request),
          includeActive: _bool(request, 'includeActive'),
          family: request.containsKey('family')
              ? FamilyRevision.fromJson(request['family'])
              : null,
        );
      case 'scale validate':
        keys({'scale'});
        data = NumericScale.fromJson(request['scale']).toJson();
      case 'scale resolve':
        keys({'scale', 'target', 'rounding', 'beyond', 'direction'});
        final scale = NumericScale.fromJson(request['scale']);
        data = {
          'scale': scale.toJson(),
          'resolution': scale
              .resolve(
                Quantity.fromJson(request['target']),
                NumericScale.roundingPolicy(request['rounding']),
                beyond: request.containsKey('beyond')
                    ? Quantity.fromJson(request['beyond'])
                    : null,
                direction: request.containsKey('direction')
                    ? requiredString(request, 'direction')
                    : null,
              )
              .toJson(),
        };
      case 'plate plan':
        keys({'loading', 'target'});
        final loading = LoadingSpec.fromJson(request['loading']);
        final target = Quantity.fromJson(request['target']);
        data = PlatePlan.evaluate(loading, target);
      case 'import validate':
        keys({'document'});
        data = validateHistoryImport(
          HistoryImportDocument.fromJson(request['document']),
        );
      case 'convention validate':
        keys({'convention'});
        data = LoadConvention.fromJson(request['convention']).toJson();
      case 'convention interpret':
        keys({'convention', 'mass', 'repetitions', 'loading'});
        data = LoadInterpretation.interpret(
          LoadConvention.fromJson(request['convention']),
          Quantity.fromJson(request['mass']),
          repetitions: request['repetitions'] == null
              ? null
              : Quantity.fromJson(request['repetitions']),
          loading: request['loading'] == null
              ? null
              : LoadingSpec.fromJson(request['loading']),
        );
      case 'family validate':
        keys({'family'});
        data = ExerciseFamily.fromJson(request['family']).toJson();
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
      case 'session annotate':
        keys({'session', 'setId', 'observations', 'confirm'});
        data = const TrainingService()
            .annotate(
              sessionFromJson(request['session']),
              requiredString(request, 'setId'),
              SetObservations.fromJson(request['observations']),
              confirm: _bool(request, 'confirm'),
            )
            .toJson();
      case 'session arrange':
        keys({'session', 'setId', 'arrangement', 'confirm'});
        data = const TrainingService()
            .arrange(
              sessionFromJson(request['session']),
              requiredString(request, 'setId'),
              request['arrangement'] == null
                  ? null
                  : LoadArrangement.fromJson(request['arrangement']),
              confirm: _bool(request, 'confirm'),
            )
            .toJson();
      case 'session arrange-status':
        keys({'session', 'instances'});
        data = arrangementStatus(
          sessionFromJson(request['session']),
          currentInstances: loadInstancesFromJson(request['instances']),
        );
      case 'session edit-target':
        keys({'session', 'setId', 'metric', 'value', 'applyToRemaining'});
        data = const TrainingService()
            .editTarget(
              sessionFromJson(request['session']),
              requiredString(request, 'setId'),
              identifier(request, 'metric'),
              Quantity.fromJson(request['value']),
              applyToRemaining: _bool(request, 'applyToRemaining'),
            )
            .toJson();
      case 'session carry-actual':
        keys({'session', 'setId', 'metric'});
        data = const TrainingService()
            .carryActual(
              sessionFromJson(request['session']),
              requiredString(request, 'setId'),
              identifier(request, 'metric'),
            )
            .toJson();
      case 'session skip-remaining':
        keys({'session', 'confirm'});
        data = const TrainingService()
            .skipRemaining(
              sessionFromJson(request['session']),
              confirm: _bool(request, 'confirm'),
            )
            .toJson();
      case 'session skip-slot':
        keys({'session', 'slotId', 'role', 'confirm'});
        data = const TrainingService()
            .skipSlot(
              sessionFromJson(request['session']),
              requiredString(request, 'slotId'),
              role: request.containsKey('role')
                  ? requiredString(request, 'role')
                  : null,
              confirm: _bool(request, 'confirm'),
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
        keys({'rule', 'current', 'results', 'state', 'observations'});
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
              observations: request.containsKey('observations')
                  ? [
                      for (final o in jsonList(request, 'observations'))
                        o == null ? null : SetObservations.fromJson(o),
                    ]
                  : null,
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
      case 'progression ordinal':
        keys({'rule', 'currentSets', 'results', 'state', 'observations'});
        final state = jsonObject(
          request['state'] ?? <String, Object?>{},
          'state',
        );
        checkKeys(state, {'failedSessions'});
        final failures = state['failedSessions'] ?? 0;
        if (failures is! int) invalid('failedSessions must be an integer.');
        data = OrdinalRule.fromJson(request['rule'])
            .evaluate(
              currentSets: [
                for (final set in jsonList(request, 'currentSets'))
                  metricsFromJson(set),
              ],
              results: [
                for (final result in jsonList(request, 'results'))
                  result == null ? null : metricsFromJson(result),
              ],
              observations: request.containsKey('observations')
                  ? [
                      for (final o in jsonList(request, 'observations'))
                        o == null ? null : SetObservations.fromJson(o),
                    ]
                  : null,
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
