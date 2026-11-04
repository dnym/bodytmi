import 'package:bodytmi_core/bodytmi_core.dart';

import 'derived_target_graph_service.dart';
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
      'workout': {'id': templateId, 'revision': revision},
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
  });

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
