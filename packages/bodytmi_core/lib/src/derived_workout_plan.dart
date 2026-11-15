import 'activity.dart';
import 'errors.dart';
import 'quantity.dart';
import 'workout.dart';

/// An immutable, explicitly pinned mapping from graph nodes to workout efforts.
final class DerivedWorkoutPlan {
  DerivedWorkoutPlan._(this.id, this.templateId, this.revision, this.bindings);

  factory DerivedWorkoutPlan.fromJson(Object? input) {
    final json = jsonObject(input, 'derived workout plan');
    checkKeys(json, {'id', 'templateId', 'revision', 'bindings'});
    final revision = json['revision'];
    if (revision is! int || revision < 1)
      invalid('Workout plan revision must be positive.');
    final rawBindings = jsonList(json, 'bindings');
    if (rawBindings.isEmpty || rawBindings.length > 10000)
      invalid('Workout plan needs 1–10000 bindings.');
    final seen = <String>{};
    final bindings = <Map<String, Object?>>[];
    for (final item in rawBindings) {
      final binding = jsonObject(item, 'workout plan binding');
      checkKeys(binding, {'occurrenceId', 'metric', 'nodeId'});
      final occurrence = requiredString(binding, 'occurrenceId');
      if (occurrence.length > 4096)
        invalid('Workout occurrence ID is too long.');
      final metric = identifier(binding, 'metric');
      final node = identifier(binding, 'nodeId');
      if (!seen.add('$occurrence\u0000$metric'))
        invalid('Duplicate workout plan binding.');
      bindings.add(
        Map.unmodifiable({
          'occurrenceId': occurrence,
          'metric': metric,
          'nodeId': node,
        }),
      );
    }
    bindings.sort((a, b) {
      final order = (a['occurrenceId']! as String).compareTo(
        b['occurrenceId']! as String,
      );
      return order != 0
          ? order
          : (a['metric']! as String).compareTo(b['metric']! as String);
    });
    return DerivedWorkoutPlan._(
      identifier(json, 'id'),
      identifier(json, 'templateId'),
      revision,
      List.unmodifiable(bindings),
    );
  }

  final String id;
  final String templateId;
  final int revision;
  final List<Map<String, Object?>> bindings;

  Map<String, Object?> toJson() => {
    'id': id,
    'templateId': templateId,
    'revision': revision,
    'bindings': bindings,
  };

  /// Validates the pinned workout and node dimensions without evaluating sources.
  void validate(WorkoutRevision workout, List<Map<String, Object?>> nodes) {
    if (workout.definition.id != templateId || workout.number != revision) {
      invalid('Derived workout plan references a different workout revision.');
    }
    // Bindings may target efforts of any variant branch; a session expands
    // only its selected branches, so other bindings are inactive there.
    final efforts = {
      for (final occurrence in workout.definition.plan.structuralOccurrences())
        if (occurrence.activity is Effort)
          occurrence.id: occurrence.activity as Effort,
    };
    final byNode = {for (final node in nodes) requiredString(node, 'id'): node};
    for (final binding in bindings) {
      final effort = efforts[binding['occurrenceId']];
      if (effort == null)
        invalid('Derived workout plan references an unknown effort.');
      final node = byNode[binding['nodeId']];
      if (node == null)
        invalid('Derived workout plan references an unknown graph node.');
      final metric = binding['metric']! as String;
      final targets = effort.resolveTargets(
        workout.definition.slot(effort.slotId).targets,
      );
      final criterion = effort.criteria[metric];
      final dimension =
          targets[metric]?.dimension ??
          (criterion != null && criterion.mode != 'observe'
              ? criterion.unit.dimension
              : null);
      if (dimension == null ||
          Unit.parse(requiredString(node, 'unit')).dimension != dimension) {
        invalid(
          'Derived workout plan has an incompatible target metric or dimension.',
        );
      }
    }
  }
}
