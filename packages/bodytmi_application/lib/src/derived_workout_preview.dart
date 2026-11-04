import 'package:bodytmi_core/bodytmi_core.dart';

import 'derived_target_graph_service.dart';
import 'canonical_json.dart';
import 'training_repository.dart';

/// Read-only projection of explicit graph nodes onto authored effort targets.
final class DerivedWorkoutPreview {
  const DerivedWorkoutPreview(this.repository);
  final TrainingRepository repository;

  Future<Map<String, Object?>> preview({
    required String templateId,
    required int revision,
    required String graphId,
    required int graphRevision,
    required DateTime asOf,
    required Object? bindings,
    String? runId,
  }) => repository.transaction(() async {
    identifier({'templateId': templateId}, 'templateId');
    identifier({'graphId': graphId}, 'graphId');
    if (revision < 1 || graphRevision < 1)
      invalid('Revisions must be positive.');
    if (bindings is! List<Object?> ||
        bindings.isEmpty ||
        bindings.length > 10000) {
      invalid('bindings must contain 1–10000 entries.');
    }
    final workout = await repository.revision(templateId, revision);
    if (workout == null)
      throw const BodyTmiException('not_found', 'Workout revision not found.');
    final graph = await DerivedTargetGraphService(
      repository,
    ).resolve(graphId, graphRevision, asOf, runId);
    return _project(workout, graph, bindings);
  });

  /// Compare a caller-supplied preview with the same pinned workout and graph.
  /// Source evidence is not authenticated and does not authorize session writes.
  Future<Map<String, Object?>> status(
    Object? input,
  ) => repository.transaction(() async {
    final captured = jsonObject(input, 'workout preview');
    checkKeys(captured, {
      'policy',
      'workout',
      'graphResolution',
      'occurrences',
    });
    if (captured['policy'] != 'bodytmi-derived-workout-preview/1') {
      invalid('Unsupported workout preview policy.');
    }
    final workoutInfo = jsonObject(captured['workout'], 'preview workout');
    checkKeys(workoutInfo, {'id', 'revision'});
    final id = identifier(workoutInfo, 'id');
    final revision = workoutInfo['revision'];
    if (revision is! int || revision < 1) invalid('Invalid workout revision.');
    final workout = await repository.revision(id, revision);
    if (workout == null)
      throw const BodyTmiException('not_found', 'Workout revision not found.');
    final graph = jsonObject(captured['graphResolution'], 'graph resolution');
    final graphInfo = jsonObject(graph['graph'], 'graph');
    final graphId = identifier(graphInfo, 'id');
    final graphRevision = graphInfo['number'];
    if (graphRevision is! int || graphRevision < 1)
      invalid('Invalid graph revision.');
    final scope = jsonObject(graph['historyScope'], 'history scope');
    final mode = requiredString(scope, 'mode');
    if (mode != 'adHoc' && mode != 'run')
      invalid('Invalid workout preview history scope.');
    final asOf = parseInstant(scope['asOf'], 'asOf');
    final runId = mode == 'run' ? identifier(scope, 'runId') : null;
    final bindings = <Map<String, Object?>>[];
    for (final item in jsonList(captured, 'occurrences')) {
      final row = jsonObject(item, 'preview occurrence');
      final occurrenceId = requiredString(row, 'id');
      final targets = jsonObject(row['targets'], 'preview targets');
      for (final entry in targets.entries) {
        final target = jsonObject(entry.value, 'preview target');
        if (target.containsKey('nodeId')) {
          bindings.add({
            'occurrenceId': occurrenceId,
            'metric': entry.key,
            'nodeId': target['nodeId'],
          });
        }
      }
    }
    if (bindings.isEmpty || bindings.length > 10000)
      invalid('Invalid preview bindings.');
    final graphStatus = await DerivedTargetGraphService(
      repository,
    ).status(graph);
    final expected = _project(workout, graph, bindings);
    if (canonicalJson(expected) != canonicalJson(captured)) {
      invalid(
        'Workout preview does not match the pinned workout and graph resolution.',
      );
    }
    final current = await preview(
      templateId: id,
      revision: revision,
      graphId: graphId,
      graphRevision: graphRevision,
      asOf: asOf,
      runId: runId,
      bindings: bindings,
    );
    final capturedRows = {
      for (final row in jsonList(captured, 'occurrences'))
        requiredString(jsonObject(row, 'occurrence'), 'id'): jsonObject(
          row,
          'occurrence',
        ),
    };
    final currentRows = {
      for (final row in jsonList(current, 'occurrences'))
        requiredString(jsonObject(row, 'occurrence'), 'id'): jsonObject(
          row,
          'occurrence',
        ),
    };
    final targetChanges = <Map<String, Object?>>[];
    for (final binding in bindings) {
      final occurrenceId = binding['occurrenceId']! as String;
      final metric = binding['metric']! as String;
      final before = jsonObject(
        capturedRows[occurrenceId]!['targets'],
        'targets',
      )[metric];
      final after = jsonObject(
        currentRows[occurrenceId]!['targets'],
        'targets',
      )[metric];
      targetChanges.add({
        'occurrenceId': occurrenceId,
        'metric': metric,
        'changed': canonicalJson(before) != canonicalJson(after),
        'captured': before,
        'current': after,
      });
    }
    return {
      'policy': 'bodytmi-derived-workout-preview-status/1',
      'changed':
          graphStatus['changed'] == true ||
          targetChanges.any((change) => change['changed'] == true),
      'sources': graphStatus['sources'],
      'targetChanges': targetChanges,
      'currentPreview': current,
    };
  });

  Map<String, Object?> _project(
    WorkoutRevision workout,
    Map<String, Object?> graph,
    Object? bindings,
  ) {
    if (bindings is! List<Object?> ||
        bindings.isEmpty ||
        bindings.length > 10000) {
      invalid('bindings must contain 1–10000 entries.');
    }
    final definition = workout.definition;
    final efforts = {
      for (final occurrence in definition.plan.occurrences())
        if (occurrence.activity is Effort)
          occurrence.id: occurrence.activity as Effort,
    };
    final graphNodes = {
      for (final item in jsonList(
        jsonObject(graph['resolution'], 'resolution'),
        'nodes',
      ))
        identifier(jsonObject(item, 'node'), 'id'): jsonObject(item, 'node'),
    };
    final selected = <String, Map<String, String>>{};
    for (final raw in bindings) {
      final binding = jsonObject(raw, 'preview binding');
      checkKeys(binding, {'occurrenceId', 'metric', 'nodeId'});
      final occurrenceId = requiredString(binding, 'occurrenceId');
      final metric = identifier(binding, 'metric');
      final nodeId = identifier(binding, 'nodeId');
      final effort = efforts[occurrenceId];
      if (effort == null) invalid('Unknown effort occurrence: $occurrenceId.');
      final node = graphNodes[nodeId];
      if (node == null) invalid('Unknown graph node: $nodeId.');
      final authored = effort.resolveTargets(
        definition.slot(effort.slotId).targets,
      );
      final criterion = effort.criteria[metric];
      final expected =
          authored[metric]?.dimension ??
          (criterion != null && criterion.mode != 'observe'
              ? criterion.unit.dimension
              : null);
      if (expected == null)
        invalid(
          'Metric has no compatible numeric target or bounded objective: $metric.',
        );
      if (Unit.parse(requiredString(node, 'unit')).dimension != expected) {
        invalid('Graph node dimension does not match effort metric: $metric.');
      }
      final mapping = selected.putIfAbsent(
        occurrenceId,
        () => <String, String>{},
      );
      if (mapping.containsKey(metric))
        invalid('Duplicate effort metric binding.');
      mapping[metric] = nodeId;
    }
    return {
      'policy': 'bodytmi-derived-workout-preview/1',
      'workout': {'id': workout.definition.id, 'revision': workout.number},
      'graphResolution': graph,
      'occurrences': [
        for (final entry in efforts.entries)
          _occurrence(
            entry.key,
            entry.value,
            definition,
            selected[entry.key] ?? {},
            graphNodes,
          ),
      ],
    };
  }

  Map<String, Object?> _occurrence(
    String id,
    Effort effort,
    WorkoutDefinition definition,
    Map<String, String> selected,
    Map<String, Map<String, Object?>> graphNodes,
  ) {
    final authored = metricsToJson(
      effort.resolveTargets(definition.slot(effort.slotId).targets),
    );
    final selectedMetrics = selected.keys.toList()..sort();
    return {
      'id': id,
      'slotId': effort.slotId,
      'role': effort.role,
      'authoredTargets': authored,
      'targets': {
        for (final entry in authored.entries)
          if (!selected.containsKey(entry.key))
            entry.key: {'status': 'authored', 'value': entry.value},
        for (final metric in selectedMetrics)
          metric: {
            'status': graphNodes[selected[metric]!]!['status'],
            'value': graphNodes[selected[metric]!]!['value'],
            'nodeId': selected[metric],
          },
      },
    };
  }
}
