import 'errors.dart';
import 'quantity.dart';

/// Resolves an explicitly supplied scalar dependency graph without history access.
final class DerivedTargets {
  const DerivedTargets();

  Map<String, Object?> resolve(Object? input) {
    if (input is! List<Object?> || input.isEmpty || input.length > 256) {
      invalid('nodes must contain 1–256 entries.');
    }
    final nodes = <String, Map<String, Object?>>{};
    for (final value in input) {
      final node = jsonObject(value, 'node');
      final id = identifier(node, 'id');
      if (nodes.containsKey(id)) invalid('Duplicate node: $id.');
      final kind = requiredString(node, 'kind');
      if (kind == 'source') {
        checkKeys(node, {
          'id',
          'kind',
          'unit',
          'sourceId',
          'sourceVersion',
          'value',
        });
        identifier(node, 'sourceId');
        final unit = Unit.parse(requiredString(node, 'unit'));
        final version = node['sourceVersion'];
        final value = node['value'];
        if (value == null) {
          if (version != null) invalid('Missing source cannot have a version.');
        } else {
          if (version is! int || version < 1)
            invalid('Source version must be a positive integer.');
          if (Quantity.fromJson(value).dimension != unit.dimension) {
            invalid(
              'Source quantity dimension does not match its declared unit.',
            );
          }
        }
      } else if (kind == 'scale') {
        checkKeys(node, {'id', 'kind', 'unit', 'input', 'factor'});
        Unit.parse(requiredString(node, 'unit'));
        identifier(node, 'input');
        final factor = Decimal.parse(requiredString(node, 'factor'));
        if (factor.compareTo(Decimal.zero) < 0)
          invalid('Scale factor cannot be negative.');
      } else {
        invalid('Unknown derived target node kind: $kind.');
      }
      nodes[id] = node;
    }
    final state = <String, int>{};
    final resolved = <String, Quantity?>{};
    final normalized = <Map<String, Object?>>[];
    void visit(String id) {
      if (!nodes.containsKey(id)) invalid('Unknown dependency: $id.');
      if (state[id] == 1)
        invalid('Derived target graph contains a cycle at $id.');
      if (state[id] == 2) return;
      state[id] = 1;
      final node = nodes[id]!;
      final unit = Unit.parse(requiredString(node, 'unit'));
      Quantity? result;
      if (node['kind'] == 'source') {
        if (node['value'] != null) result = Quantity.fromJson(node['value']);
        normalized.add({
          'id': id,
          'kind': 'source',
          'unit': unit.name,
          'sourceId': node['sourceId'],
          'sourceVersion': node['sourceVersion'],
          'value': result?.toJson(),
          'status': result == null ? 'unresolved' : 'resolved',
        });
      } else {
        final dependency = requiredString(node, 'input');
        visit(dependency);
        final upstream = nodes[dependency]!;
        if (Unit.parse(requiredString(upstream, 'unit')).dimension !=
            unit.dimension) {
          invalid('Derived target dependency dimension mismatch at $id.');
        }
        final factor = Decimal.parse(requiredString(node, 'factor'));
        final source = resolved[dependency];
        if (source != null) {
          result = Quantity(
            (source.value * factor).toString(),
            unit.canonical.name,
          );
        }
        normalized.add({
          'id': id,
          'kind': 'scale',
          'unit': unit.name,
          'input': dependency,
          'factor': factor.toString(),
          'value': result?.toJson(),
          'status': result == null ? 'unresolved' : 'resolved',
        });
      }
      resolved[id] = result;
      state[id] = 2;
    }

    final ids = nodes.keys.toList()..sort();
    for (final id in ids) {
      visit(id);
    }
    return {'policy': 'bodytmi-derived-targets/1', 'nodes': normalized};
  }
}
