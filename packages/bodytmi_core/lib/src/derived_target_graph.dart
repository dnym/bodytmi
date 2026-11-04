import 'derived_targets.dart';
import 'derived_workout_plan.dart';
import 'errors.dart';
import 'instant.dart';
import 'quantity.dart';

/// Reusable scalar dependency graph with explicit per-source binding policies.
///
/// Nodes are the same scalar graph as [DerivedTargets]; bindings decide
/// how each source is supplied at resolution time (manual value, stored
/// body-mass record, or stored session history). Publishing a graph never
/// fetches or asserts the currency of any source.
final class DerivedTargetGraph {
  DerivedTargetGraph._(
    this.id,
    this.name,
    this.nodes,
    this.bindings,
    this.plans,
  );
  factory DerivedTargetGraph.fromJson(Object? input) {
    final json = jsonObject(input, 'derived target graph');
    checkKeys(json, {'id', 'name', 'nodes', 'bindings', 'plans'});
    final id = identifier(json, 'id');
    final name = json['name'];
    if (name != null && name is! String)
      invalid('Graph name must be a string.');
    final nodesInput = jsonList(json, 'nodes');
    if (nodesInput.isEmpty || nodesInput.length > 256)
      invalid('Graph nodes must contain 1–256 entries.');
    final nodes = <Map<String, Object?>>[];
    final nodeIds = <String>{};
    final sourceDimensions = <String, Dimension>{};
    for (final raw in nodesInput) {
      final node = jsonObject(raw, 'graph node');
      final kind = requiredString(node, 'kind');
      if (kind == 'source') {
        checkKeys(node, {'id', 'kind', 'unit', 'sourceId'});
        final nodeId = identifier(node, 'id');
        if (!nodeIds.add(nodeId)) invalid('Duplicate node: $nodeId.');
        final sourceId = identifier(node, 'sourceId');
        final unit = Unit.parse(requiredString(node, 'unit'));
        final previous = sourceDimensions[sourceId];
        if (previous != null && previous != unit.dimension) {
          invalid('A source cannot have multiple dimensions.');
        }
        sourceDimensions[sourceId] = unit.dimension;
        nodes.add({
          'id': nodeId,
          'kind': kind,
          'unit': unit.name,
          'sourceId': sourceId,
        });
      } else if (kind == 'scale') {
        checkKeys(node, {'id', 'kind', 'unit', 'input', 'factor'});
        final nodeId = identifier(node, 'id');
        if (!nodeIds.add(nodeId)) invalid('Duplicate node: $nodeId.');
        final factor = Decimal.parse(requiredString(node, 'factor'));
        if (factor.compareTo(Decimal.zero) < 0)
          invalid('Scale factor cannot be negative.');
        nodes.add({
          'id': nodeId,
          'kind': kind,
          'unit': Unit.parse(requiredString(node, 'unit')).name,
          'input': identifier(node, 'input'),
          'factor': factor.toString(),
        });
      } else if (kind == 'add' || kind == 'subtract') {
        checkKeys(node, {'id', 'kind', 'unit', 'left', 'right'});
        final nodeId = identifier(node, 'id');
        if (!nodeIds.add(nodeId)) invalid('Duplicate node: $nodeId.');
        nodes.add({
          'id': nodeId,
          'kind': kind,
          'unit': Unit.parse(requiredString(node, 'unit')).name,
          'left': identifier(node, 'left'),
          'right': identifier(node, 'right'),
        });
      } else {
        invalid('Unknown derived target node kind: $kind.');
      }
    }
    // References and acyclicity are checked with every source unresolved.
    const DerivedTargets().resolve([
      for (final node in nodes)
        if (node['kind'] == 'source')
          {...node, 'sourceVersion': null, 'value': null}
        else
          node,
    ]);
    final bindingsInput = jsonObject(json['bindings'], 'bindings');
    final unknown = bindingsInput.keys.toSet().difference(
      sourceDimensions.keys.toSet(),
    );
    if (unknown.isNotEmpty)
      invalid('Unknown source bindings: ${unknown.join(', ')}.');
    final missing = sourceDimensions.keys.toSet().difference(
      bindingsInput.keys.toSet(),
    );
    if (missing.isNotEmpty)
      invalid('Missing source bindings: ${missing.join(', ')}.');
    final bindings = <String, Map<String, Object?>>{};
    for (final entry in bindingsInput.entries) {
      bindings[entry.key] = _binding(
        jsonObject(entry.value, 'source binding'),
        sourceDimensions[entry.key]!,
      );
    }
    final rawPlans = json.containsKey('plans')
        ? jsonList(json, 'plans')
        : <Object?>[];
    if (rawPlans.length > 1000)
      invalid('Graph cannot have more than 1000 workout plans.');
    final plans = [
      for (final raw in rawPlans) DerivedWorkoutPlan.fromJson(raw),
    ];
    if (plans.map((p) => p.id).toSet().length != plans.length)
      invalid('Duplicate derived workout plan ID.');
    if (plans.fold<int>(0, (n, p) => n + p.bindings.length) > 10000)
      invalid('Graph workout plans exceed 10000 bindings.');
    for (final plan in plans) {
      if (plan.bindings.any((b) => !nodeIds.contains(b['nodeId'])))
        invalid('Workout plan references an unknown graph node.');
    }
    plans.sort((a, b) => a.id.compareTo(b.id));
    nodes.sort((a, b) => (a['id']! as String).compareTo(b['id']! as String));
    return DerivedTargetGraph._(
      id,
      name as String?,
      List.unmodifiable(nodes),
      Map.unmodifiable(bindings),
      List.unmodifiable(plans),
    );
  }

  static Map<String, Object?> _binding(
    Map<String, Object?> binding,
    Dimension dimension,
  ) {
    final kind = requiredString(binding, 'kind');
    switch (kind) {
      case 'manual':
        checkKeys(binding, {'kind', 'version', 'value'});
        final version = binding['version'];
        if (version is! int || version < 1)
          invalid('Manual source version must be a positive integer.');
        final quantity = Quantity.fromJson(binding['value']);
        if (quantity.dimension != dimension)
          invalid('Manual binding dimension mismatch.');
        return {'kind': kind, 'version': version, 'value': quantity.toJson()};
      case 'bodyMass':
        checkKeys(binding, {
          'kind',
          'context',
          'asOf',
          'dailyMode',
          'staleAfterDays',
          'warnIfStale',
        });
        if (dimension != Dimension.mass)
          invalid('Body-mass bindings require a mass source.');
        identifier(binding, 'context');
        final asOf = binding['asOf'];
        if (asOf != null) parseInstant(asOf, 'asOf');
        final mode = binding['dailyMode'] ?? 'mean';
        if (mode != 'mean' && mode != 'replace')
          invalid('dailyMode must be mean or replace.');
        final stale = binding['staleAfterDays'];
        if (stale != null && (stale is! int || stale < 0 || stale > 36500)) {
          invalid('Invalid staleAfterDays.');
        }
        final warn = binding['warnIfStale'];
        if (warn != null && warn is! bool)
          invalid('warnIfStale must be a boolean.');
        return {
          'kind': kind,
          'context': binding['context'],
          if (asOf != null) 'asOf': asOf,
          'dailyMode': mode,
          if (stale != null) 'staleAfterDays': stale,
          if (warn != null) 'warnIfStale': warn,
        };
      case 'history':
        checkKeys(binding, {
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
        });
        identifier(binding, 'metric');
        final direction = binding['direction'] ?? 'highest';
        if (direction != 'highest' && direction != 'lowest')
          invalid('direction must be highest or lowest.');
        final ordinal = binding['ordinal'];
        if (ordinal != null && (ordinal is! int || ordinal < 0)) {
          invalid('ordinal must be a nonnegative integer.');
        }
        if (binding['from'] != null) parseInstant(binding['from'], 'from');
        if (binding['until'] != null) parseInstant(binding['until'], 'until');
        final warmups = binding['includeWarmups'];
        if (warmups != null && warmups is! bool)
          invalid('includeWarmups must be a boolean.');
        final setup = binding['setup'];
        if (setup != null && setup is! String)
          invalid('setup must be a string.');
        return {
          'kind': kind,
          'metric': binding['metric'],
          'direction': direction,
          for (final key in [
            'templateId',
            'slotId',
            'exerciseId',
            'implementationId',
            'equipment',
            'role',
          ])
            if (binding[key] != null)
              key: identifier({'$key': binding[key]}, key),
          if (setup != null) 'setup': setup,
          if (ordinal != null) 'ordinal': ordinal,
          if (binding['from'] != null) 'from': binding['from'],
          if (binding['until'] != null) 'until': binding['until'],
          if (warmups != null) 'includeWarmups': warmups,
        };
      default:
        invalid('Unknown source binding kind: $kind.');
    }
  }

  final String id;
  final String? name;
  final List<Map<String, Object?>> nodes;
  final Map<String, Map<String, Object?>> bindings;
  final List<DerivedWorkoutPlan> plans;

  List<String> get sourceIds => bindings.keys.toList()..sort();

  Map<String, Object?> toJson() => {
    'id': id,
    if (name != null) 'name': name,
    'nodes': nodes,
    'bindings': bindings,
    if (plans.isNotEmpty) 'plans': [for (final plan in plans) plan.toJson()],
  };
}

final class DerivedTargetGraphRevision {
  DerivedTargetGraphRevision._(this.number, this.graph);
  factory DerivedTargetGraphRevision.publish(
    DerivedTargetGraph graph, {
    DerivedTargetGraphRevision? previous,
  }) {
    if (previous != null && previous.graph.id != graph.id)
      invalid('Graph revision must retain identity.');
    return DerivedTargetGraphRevision._((previous?.number ?? 0) + 1, graph);
  }
  factory DerivedTargetGraphRevision.fromJson(Object? input) {
    final json = jsonObject(input, 'derived target graph revision');
    checkKeys(json, {'schemaVersion', 'revision', 'graph'});
    final revision = json['revision'];
    if (json['schemaVersion'] != 1 || revision is! int || revision < 1) {
      invalid('Invalid derived target graph revision.');
    }
    return DerivedTargetGraphRevision._(
      revision,
      DerivedTargetGraph.fromJson(json['graph']),
    );
  }
  final int number;
  final DerivedTargetGraph graph;
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'revision': number,
    'graph': graph.toJson(),
  };
}

void validateDerivedTargetGraphRevisions(
  List<DerivedTargetGraphRevision> revisions,
) {
  final numbers = <String, Set<int>>{};
  for (final revision in revisions)
    if (!numbers
        .putIfAbsent(revision.graph.id, () => <int>{})
        .add(revision.number))
      invalid('Duplicate derived target graph revision.');
  for (final versions in numbers.values)
    if (versions.any((n) => n > versions.length))
      invalid('Graph revisions must start at one with no gaps.');
}
