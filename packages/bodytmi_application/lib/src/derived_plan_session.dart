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
      plan.templateId != session.revision.definition.id ||
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
    } else {
      invalid('Stored plan sessions do not yet support history graph sources.');
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
        set.sources.containsKey(metric)) {
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
