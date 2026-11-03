import 'derived_targets.dart';
import 'errors.dart';
import 'quantity.dart';

/// Reproducible caller-supplied source bindings for an authored scalar graph.
final class DerivedTargetSnapshot {
  const DerivedTargetSnapshot();

  Map<String, Object?> capture(Object? graphInput, Object? bindingsInput) {
    if (graphInput is! List<Object?> ||
        graphInput.isEmpty ||
        graphInput.length > 256) {
      invalid('graph must contain 1–256 nodes.');
    }
    final bindings = jsonObject(bindingsInput, 'bindings');
    final graph = <Map<String, Object?>>[];
    final sourceDimensions = <String, Dimension>{};
    for (final raw in graphInput) {
      final node = jsonObject(raw, 'graph node');
      final kind = requiredString(node, 'kind');
      if (kind == 'source') {
        checkKeys(node, {'id', 'kind', 'unit', 'sourceId'});
        final id = identifier(node, 'id');
        final sourceId = identifier(node, 'sourceId');
        final unit = Unit.parse(requiredString(node, 'unit'));
        final previous = sourceDimensions[sourceId];
        if (previous != null && previous != unit.dimension) {
          invalid('A source cannot have multiple dimensions.');
        }
        sourceDimensions[sourceId] = unit.dimension;
        graph.add({
          'id': id,
          'kind': kind,
          'unit': unit.name,
          'sourceId': sourceId,
        });
      } else if (kind == 'scale') {
        checkKeys(node, {'id', 'kind', 'unit', 'input', 'factor'});
        final factor = Decimal.parse(requiredString(node, 'factor'));
        graph.add({
          'id': identifier(node, 'id'),
          'kind': kind,
          'unit': Unit.parse(requiredString(node, 'unit')).name,
          'input': identifier(node, 'input'),
          'factor': factor.toString(),
        });
      } else {
        invalid('Unknown derived target node kind: $kind.');
      }
    }
    final unknown = bindings.keys.toSet().difference(
      sourceDimensions.keys.toSet(),
    );
    if (unknown.isNotEmpty)
      invalid('Unknown source bindings: ${unknown.join(', ')}.');
    final sourceIds = sourceDimensions.keys.toList()..sort();
    final normalizedBindings = <String, Object?>{};
    for (final id in sourceIds) {
      final raw = bindings[id];
      if (raw == null) {
        normalizedBindings[id] = null;
        continue;
      }
      final binding = jsonObject(raw, 'source binding');
      checkKeys(binding, {'version', 'value'});
      final version = binding['version'];
      if (version is! int || version < 1)
        invalid('Source version must be a positive integer.');
      final quantity = Quantity.fromJson(binding['value']);
      if (quantity.dimension != sourceDimensions[id])
        invalid('Source binding dimension mismatch: $id.');
      normalizedBindings[id] = {'version': version, 'value': quantity.toJson()};
    }
    graph.sort((a, b) => (a['id']! as String).compareTo(b['id']! as String));
    final resolverNodes = <Map<String, Object?>>[];
    for (final node in graph) {
      if (node['kind'] == 'source') {
        final binding = normalizedBindings[node['sourceId']];
        final source = binding == null ? null : jsonObject(binding, 'binding');
        resolverNodes.add({
          ...node,
          'sourceVersion': source?['version'],
          'value': source?['value'],
        });
      } else {
        resolverNodes.add(node);
      }
    }
    final resolution = const DerivedTargets().resolve(resolverNodes);
    return {
      'policy': 'bodytmi-derived-target-snapshot/1',
      'graph': graph,
      'bindings': normalizedBindings,
      'resolution': resolution,
    };
  }

  Map<String, Object?> status(Object? snapshotInput, Object? currentBindings) {
    final snapshot = jsonObject(snapshotInput, 'snapshot');
    checkKeys(snapshot, {'policy', 'graph', 'bindings', 'resolution'});
    if (snapshot['policy'] != 'bodytmi-derived-target-snapshot/1') {
      invalid('Unsupported derived target snapshot policy.');
    }
    final verified = capture(snapshot['graph'], snapshot['bindings']);
    if (!_same(verified, snapshot))
      invalid('Derived target snapshot does not match its inputs.');
    final current = capture(snapshot['graph'], currentBindings);
    final previous = jsonObject(verified['bindings'], 'bindings');
    final latest = jsonObject(current['bindings'], 'bindings');
    final sources = <String, Object?>{};
    for (final id in previous.keys) {
      sources[id] = {
        'changed': !_same(previous[id], latest[id]),
        'captured': previous[id],
        'current': latest[id],
      };
    }
    return {
      'policy': 'bodytmi-derived-target-status/1',
      'changed': sources.values.any(
        (value) => (value as Map<String, Object?>)['changed'] == true,
      ),
      'sources': sources,
      'captured': verified['resolution'],
      'current': current['resolution'],
    };
  }
}

bool _same(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((key) => b.containsKey(key) && _same(a[key], b[key]));
  }
  if (a is List && b is List) {
    return a.length == b.length &&
        List.generate(a.length, (i) => i).every((i) => _same(a[i], b[i]));
  }
  return a == b;
}
