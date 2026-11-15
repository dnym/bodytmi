import 'package:bodytmi_core/bodytmi_core.dart';
import 'canonical_json.dart';
import 'body_mass_service.dart';
import 'stored_body_mass_service.dart';
import 'derived_workout_preview.dart';

/// Validates the self-contained, manually bound plan snapshot of a session.
void validateDerivedPlanSession(
  TrainingSession session, {
  String? expectedRunId,
  bool checkRun = false,
}) {
  final input = session.derivedPlanInput;
  if (input == null) return;
  final snapshot = input.snapshot;
  checkKeys(snapshot, {'policy', 'plan', 'preview'});
  if (snapshot['policy'] != 'bodytmi-derived-workout-plan-preview/1')
    invalid('Invalid captured plan policy.');
  final plan = DerivedWorkoutPlan.fromJson(snapshot['plan']);
  final ref = input.reference;
  if (plan.id != ref.planId ||
      plan.templateId != session.definition.id ||
      plan.revision != session.revision.number) {
    invalid('Captured plan does not match the session.');
  }
  final preview = jsonObject(snapshot['preview'], 'captured preview');
  final graph = jsonObject(
    preview['graphResolution'],
    'captured graph resolution',
  );
  checkKeys(graph, {
    'policy',
    'historyScope',
    'graph',
    'bindings',
    'resolution',
  });
  if (graph['policy'] != 'bodytmi-derived-target-graph-resolution/3')
    invalid('Invalid captured graph policy.');
  final graphInfo = jsonObject(graph['graph'], 'captured graph');
  checkKeys(graphInfo, {'id', 'number', 'name', 'nodes'});
  if (graphInfo['id'] != ref.graphId ||
      graphInfo['number'] != ref.graphRevision)
    invalid('Captured graph identity mismatch.');
  final scope = jsonObject(graph['historyScope'], 'captured graph scope');
  checkKeys(scope, {'mode', 'runId', 'asOf'});
  if (scope['mode'] == 'run') {
    identifier(scope, 'runId');
  } else if (scope.containsKey('runId')) {
    invalid('Invalid captured graph run scope.');
  }
  final asOf = parseInstant(scope['asOf'], 'asOf');
  if (asOf != session.startedAt)
    invalid('Captured graph cutoff must match session start.');
  if (checkRun &&
      (scope['mode'] != (expectedRunId == null ? 'adHoc' : 'run') ||
          scope['runId'] != expectedRunId)) {
    invalid('Captured graph run scope does not match session ownership.');
  }
  if (scope['mode'] != 'adHoc' && scope['mode'] != 'run')
    invalid('Invalid captured graph scope.');
  final nodes = jsonList(graphInfo, 'nodes');
  final bindings = jsonObject(graph['bindings'], 'captured source bindings');
  final sourceIds = <String>{};
  for (final item in nodes) {
    final node = jsonObject(item, 'captured graph node');
    if (node['kind'] == 'source') sourceIds.add(identifier(node, 'sourceId'));
  }
  if (sourceIds.length != bindings.length ||
      !sourceIds.every(bindings.containsKey)) {
    invalid('Captured graph source membership mismatch.');
  }
  final bodyIds = <String>{};
  for (final entry in bindings.entries) {
    if (jsonObject(entry.value, 'source')['kind'] == 'bodyMass')
      bodyIds.add(entry.key);
  }
  if (bodyIds.length != input.bodyMassSources.length ||
      !bodyIds.every(input.bodyMassSources.containsKey)) {
    invalid('Captured body mass source membership mismatch.');
  }
  final resolverNodes = <Map<String, Object?>>[];
  for (final item in nodes) {
    final node = jsonObject(item, 'captured graph node');
    if (node['kind'] != 'source') {
      resolverNodes.add(node);
      continue;
    }
    final source = jsonObject(
      bindings[identifier(node, 'sourceId')],
      'captured source',
    );
    if (source['kind'] == 'manual') {
      checkKeys(source, {
        'kind',
        'version',
        'value',
        'status',
        'sourceVersion',
      });
      if (source['status'] != 'resolved' ||
          source['version'] != source['sourceVersion']) {
        invalid('Invalid captured manual source.');
      }
    } else if (source['kind'] == 'bodyMass') {
      _validateBodyMassSource(
        source,
        input.bodyMassSources[identifier(node, 'sourceId')],
        session.startedAt,
      );
    } else if (source['kind'] == 'history') {
      _validateHistorySource(source, session, scope['runId'] as String?);
    } else {
      invalid('Unsupported captured graph source.');
    }
    resolverNodes.add({
      ...node,
      'sourceVersion': source['sourceVersion'],
      'value': source['value'],
    });
  }
  if (canonicalJson(const DerivedTargets().resolve(resolverNodes)) !=
      canonicalJson(graph['resolution']))
    invalid('Captured graph arithmetic mismatch.');
  if (canonicalJson(
        DerivedWorkoutPreview.projectCaptured(
          session.revision,
          graph,
          plan.bindings,
          session.variantSelections,
        ),
      ) !=
      canonicalJson(preview)) {
    invalid('Captured plan preview does not match its mappings.');
  }
  final rows = {
    for (final item in jsonList(preview, 'occurrences'))
      requiredString(jsonObject(item, 'occurrence'), 'id'): jsonObject(
        item,
        'occurrence',
      ),
  };
  for (final binding in plan.bindings) {
    // Bindings into unselected variant branches are inactive.
    if (!rows.containsKey(binding['occurrenceId'])) continue;
    final set = session.set(binding['occurrenceId']! as String);
    final metric = binding['metric']! as String;
    final target = jsonObject(
      jsonObject(rows[set.id]!['targets'], 'targets')[metric],
      'target',
    );
    if (target['status'] != 'resolved' ||
        target['value'] == null ||
        set.suggested[metric] == null ||
        canonicalJson(set.suggested[metric]!.toJson()) !=
            canonicalJson(target['value']) ||
        set.sources.containsKey(metric) ||
        set.manualTargets.contains(metric)) {
      invalid('Session target does not match its captured plan.');
    }
  }
}

/// Checks that session snapshots name the published plan and manual graph inputs.
void validateDerivedPlanReferences(
  List<TrainingSession> sessions,
  List<DerivedTargetGraphRevision> graphs,
  Map<String, String> runs,
  List<BodyMassRecord> records,
) {
  final sessionsById = {for (final session in sessions) session.id: session};
  final recordsById = {
    for (final record in records) record.measurement.id: record,
  };
  final byId = {
    for (final graph in graphs) '${graph.graph.id}:${graph.number}': graph,
  };
  for (final session in sessions) {
    final input = session.derivedPlanInput;
    if (input == null) continue;
    validateDerivedPlanSession(
      session,
      expectedRunId: runs[session.id],
      checkRun: true,
    );
    final ref = input.reference;
    final graph = byId['${ref.graphId}:${ref.graphRevision}'];
    if (graph == null) invalid('Captured plan graph revision is missing.');
    final plans = graph.graph.plans.where((p) => p.id == ref.planId);
    if (plans.isEmpty ||
        canonicalJson(plans.single.toJson()) !=
            canonicalJson(input.snapshot['plan']))
      invalid('Captured plan does not match its published revision.');
    final resolution = jsonObject(
      jsonObject(input.snapshot['preview'], 'preview')['graphResolution'],
      'graph resolution',
    );
    final info = jsonObject(resolution['graph'], 'graph');
    final expectedGraph = {
      'id': graph.graph.id,
      'number': graph.number,
      if (graph.graph.name != null) 'name': graph.graph.name,
      'nodes': graph.graph.nodes,
    };
    if (canonicalJson(info) != canonicalJson(expectedGraph))
      invalid('Captured graph definition differs from published revision.');
    final sources = jsonObject(resolution['bindings'], 'source bindings');
    if (sources.length != graph.graph.bindings.length)
      invalid('Captured graph source membership mismatch.');
    for (final entry in graph.graph.bindings.entries) {
      final expected = entry.value;
      final actual = jsonObject(sources[entry.key], 'source');
      if (expected['kind'] == 'manual') {
        if (actual['kind'] != 'manual' ||
            actual['version'] != expected['version'] ||
            canonicalJson(actual['value']) !=
                canonicalJson(expected['value'])) {
          invalid('Captured manual source differs from published revision.');
        }
      } else if (expected['kind'] == 'bodyMass') {
        for (final key in expected.keys) {
          if (!actual.containsKey(key) ||
              canonicalJson(actual[key]) != canonicalJson(expected[key])) {
            invalid(
              'Captured body mass policy differs from published revision.',
            );
          }
        }
        for (final measurement in input.bodyMassSources[entry.key]!) {
          final current = recordsById[measurement.id];
          if (current == null ||
              current.measurement.contentVersion < measurement.contentVersion ||
              (current.measurement.contentVersion ==
                      measurement.contentVersion &&
                  (current.deleted ||
                      canonicalJson(current.measurement.toJson()) !=
                          canonicalJson(measurement.toJson())))) {
            invalid(
              'Captured body mass source identity, version or value is invalid.',
            );
          }
        }
      } else if (expected['kind'] == 'history') {
        for (final key in expected.keys) {
          if (!actual.containsKey(key) ||
              canonicalJson(actual[key]) != canonicalJson(expected[key])) {
            invalid('Captured history policy differs from published revision.');
          }
        }
        final fingerprint = jsonObject(
          jsonObject(actual['provenance'], 'provenance')['sourceFingerprint'],
          'fingerprint',
        );
        for (final item in jsonList(fingerprint, 'sources')) {
          final row = jsonObject(item, 'history source');
          final prior = sessionsById[row['sessionId']];
          if (prior == null ||
              prior.id == session.id ||
              prior.finishedAt == null ||
              prior.startedAt != parseInstant(row['startedAt'], 'startedAt') ||
              prior.finishedAt !=
                  parseInstant(row['finishedAt'], 'finishedAt') ||
              prior.contentVersion < (row['sessionVersion'] as int) ||
              runs[prior.id] != row['runId'])
            invalid('Invalid captured history session reference.');
          final matches = prior.sets.where((s) => s.id == row['setId']);
          if (matches.length != 1) invalid('Captured history set is missing.');
          final set = matches.single;
          final slot = prior.definition.slot(set.slotId);
          if (set.slotId != row['slotId'] ||
              set.role != row['role'] ||
              set.ordinal != row['ordinal'] ||
              set.contentVersion < (row['setVersion'] as int) ||
              (expected['templateId'] != null &&
                  expected['templateId'] != prior.definition.id) ||
              (expected['slotId'] != null &&
                  expected['slotId'] != set.slotId) ||
              (expected['exerciseId'] != null &&
                  expected['exerciseId'] != slot.exerciseId) ||
              (expected['implementationId'] != null &&
                  expected['implementationId'] != slot.implementation) ||
              (expected['equipment'] != null &&
                  expected['equipment'] != slot.equipmentId) ||
              (expected['setup'] != null &&
                  expected['setup'] != slot.setupNote))
            invalid('Invalid captured history context.');
          if (set.contentVersion == row['setVersion'] &&
              (set.status != SetStatus.completed ||
                  (set.observations?.interrupted ?? false) ||
                  canonicalJson(set.actuals[expected['metric']]?.toJson()) !=
                      canonicalJson(row['value']))) {
            invalid('Captured history value does not match its set version.');
          }
        }
      } else {
        invalid('Unsupported captured graph source.');
      }
    }
  }
}

void _validateBodyMassSource(
  Map<String, Object?> source,
  List<BodyMassMeasurement>? measurements,
  DateTime startedAt,
) {
  checkKeys(source, {
    'kind',
    'context',
    'asOf',
    'dailyMode',
    'staleAfterDays',
    'warnIfStale',
    'value',
    'status',
    'sourceVersion',
    'provenance',
  });
  if (measurements == null) invalid('Missing captured body mass sources.');
  final context = identifier(source, 'context');
  final cutoff = source['asOf'] == null
      ? startedAt
      : parseInstant(source['asOf'], 'asOf');
  if (cutoff.isAfter(startedAt))
    invalid('Body mass source cutoff is after session start.');
  for (final m in measurements) {
    if (m.context != context || m.observedAt.isAfter(cutoff))
      invalid('Captured body mass source is outside its context or cutoff.');
  }
  final resolved = const BodyMassService().resolve({
    'measurements': [for (final m in measurements) m.toJson()],
    'context': context,
    'asOf': cutoff.toUtc().toIso8601String(),
    'dailyMode': source['dailyMode'],
    if (source.containsKey('staleAfterDays'))
      'staleAfterDays': source['staleAfterDays'],
    if (source.containsKey('warnIfStale')) 'warnIfStale': source['warnIfStale'],
  });
  final version = measurements.isEmpty
      ? null
      : measurements
            .map((m) => m.contentVersion)
            .reduce((a, b) => a > b ? a : b);
  final provenance = {
    'context': context,
    'asOf': cutoff.toUtc().toIso8601String(),
    'source': resolved.source,
    if (resolved.sourceObservedAt != null)
      'observedAt': resolved.sourceObservedAt!.toUtc().toIso8601String(),
    'stale': resolved.stale,
    'sourceFingerprint': resolved.sourceFingerprint,
    'sourceVersionSemantics': 'maximumMeasurementVersionOnly',
  };
  if (source['status'] != (resolved.mass == null ? 'unresolved' : 'resolved') ||
      source.containsKey('sourceVersion') != (version != null) ||
      source['sourceVersion'] != version ||
      canonicalJson(source['value']) !=
          canonicalJson(resolved.mass?.toJson()) ||
      canonicalJson(source['provenance']) != canonicalJson(provenance)) {
    invalid('Captured body mass inputs do not match their resolution.');
  }
}

bool usesDerivedBodyMass(TrainingSession session) =>
    session.derivedPlanInput?.bodyMassSources.isNotEmpty ?? false;

void _validateHistorySource(
  Map<String, Object?> source,
  TrainingSession session,
  String? runId,
) {
  checkKeys(source, {
    'kind',
    'metric',
    'direction',
    'templateId',
    'slotId',
    'exerciseId',
    'implementationId',
    'equipment',
    'setup',
    'role',
    'ordinal',
    'from',
    'until',
    'includeWarmups',
    'value',
    'status',
    'sourceVersion',
    'provenance',
  });
  final provenance = jsonObject(source['provenance'], 'history provenance');
  checkKeys(provenance, {
    'metric',
    'direction',
    'session',
    'set',
    'sourceVersionSemantics',
    'sourceFingerprint',
  });
  final fingerprint = jsonObject(
    provenance['sourceFingerprint'],
    'history fingerprint',
  );
  checkKeys(fingerprint, {'policy', 'metric', 'direction', 'sources'});
  if (fingerprint['policy'] != 'bodytmi-history-source/1' ||
      fingerprint['metric'] != source['metric'] ||
      fingerprint['direction'] != source['direction'] ||
      provenance['metric'] != source['metric'] ||
      provenance['direction'] != source['direction'] ||
      provenance['sourceVersionSemantics'] != 'selectedSessionVersionOnly')
    invalid('Invalid history provenance.');
  final rows = jsonList(fingerprint, 'sources');
  if (rows.length > 10000) invalid('Too many history sources.');
  Map<String, Object?>? best;
  String? previous;
  for (final item in rows) {
    final row = jsonObject(item, 'history source');
    checkKeys(row, {
      'sessionId',
      'sessionVersion',
      'setId',
      'setVersion',
      'runId',
      'startedAt',
      'finishedAt',
      'slotId',
      'role',
      'ordinal',
      'value',
    });
    final id = identifier(row, 'sessionId');
    final setId = requiredString(row, 'setId');
    identifier(row, 'slotId');
    requiredString(row, 'role');
    final version = row['sessionVersion'];
    final setVersion = row['setVersion'];
    final ordinal = row['ordinal'];
    if (version is! int ||
        version < 1 ||
        setVersion is! int ||
        setVersion < 1 ||
        ordinal is! int ||
        ordinal < 0 ||
        !row.containsKey('runId') ||
        row['runId'] != runId)
      invalid('Invalid captured history identity.');
    final started = parseInstant(row['startedAt'], 'startedAt');
    final finished = parseInstant(row['finishedAt'], 'finishedAt');
    if (!started.isBefore(session.startedAt) ||
        finished.isBefore(started) ||
        finished.isAfter(session.startedAt) ||
        (source['from'] != null &&
            started.isBefore(parseInstant(source['from'], 'from'))) ||
        (source['until'] != null &&
            !started.isBefore(parseInstant(source['until'], 'until'))) ||
        (source['slotId'] != null && source['slotId'] != row['slotId']) ||
        (source['role'] != null && source['role'] != row['role']) ||
        (source['ordinal'] != null && source['ordinal'] != ordinal) ||
        (source['includeWarmups'] != true && row['role'] == 'warmup'))
      invalid('Captured history is outside its policy.');
    final key = '$id\u0000$setId';
    if (previous != null && previous.compareTo(key) >= 0)
      invalid('History sources must be unique and ordered.');
    previous = key;
    final value = Quantity.fromJson(row['value']);
    if (best == null) {
      best = row;
      continue;
    }
    final compare = value.compareTo(Quantity.fromJson(best['value']));
    final byTime = started.compareTo(
      parseInstant(best['startedAt'], 'startedAt'),
    );
    final byId = id.compareTo(best['sessionId'] as String);
    final byOrdinal = ordinal.compareTo(best['ordinal'] as int);
    if ((source['direction'] == 'highest' ? compare : -compare) > 0 ||
        (compare == 0 &&
            (byTime < 0 ||
                (byTime == 0 &&
                    (byId < 0 ||
                        (byId == 0 &&
                            (byOrdinal < 0 ||
                                (byOrdinal == 0 &&
                                    setId.compareTo(best['setId'] as String) <
                                        0))))))))
      best = row;
  }
  if ((source['direction'] != 'highest' && source['direction'] != 'lowest') ||
      source['status'] != (best == null ? 'unresolved' : 'resolved') ||
      canonicalJson(source['value']) != canonicalJson(best?['value']) ||
      source.containsKey('sourceVersion') != (best != null) ||
      source['sourceVersion'] != best?['sessionVersion'] ||
      provenance.containsKey('session') != (best != null) ||
      provenance.containsKey('set') != (best != null) ||
      provenance['session'] != best?['sessionId'] ||
      provenance['set'] != best?['setId'])
    invalid('Captured history selection is invalid.');
}

bool usesDerivedHistory(TrainingSession session) {
  final input = session.derivedPlanInput;
  if (input == null) return false;
  final preview = jsonObject(input.snapshot['preview'], 'preview');
  final graph = jsonObject(preview['graphResolution'], 'graph resolution');
  return jsonObject(
    graph['bindings'],
    'bindings',
  ).values.any((source) => jsonObject(source, 'source')['kind'] == 'history');
}

/// Whether a captured plan supplies a suggestion absent from the authored effort.
bool usesDerivedTargetlessObjective(TrainingSession session) {
  if (session.derivedPlanInput == null) return false;
  final authored = {
    for (final occurrence in session.definition.plan.occurrences())
      if (occurrence.activity is Effort)
        occurrence.id: (occurrence.activity as Effort).resolveTargets(
          session.definition
              .slot((occurrence.activity as Effort).slotId)
              .targets,
        ),
  };
  return session.sets.any(
    (set) =>
        set.suggested.keys.any((key) => !authored[set.id]!.containsKey(key)),
  );
}
