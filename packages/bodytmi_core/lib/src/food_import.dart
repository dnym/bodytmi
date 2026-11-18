import 'errors.dart';
import 'food.dart';
import 'import_origin.dart';

const foodImportFormat = 'bodytmi-food-import/1';
const _maxFoods = 100000;

/// One food of a `bodytmi-food-import/1` document: ordinary food fields
/// plus `sourceId`, an optional explicit `id`, and components that name
/// either a food of the same document (`{sourceId}`) or a published food
/// revision (`{id, revision}`).
final class ImportedFood {
  ImportedFood._(this.sourceId, this.id, this.json, this.dependencies);

  factory ImportedFood.fromJson(Object? input, String namespace) {
    final j = jsonObject(input, 'imported food');
    if (j.containsKey('import'))
      invalid('An imported food has no import field; the document sets it.');
    final sourceId = importSourceId(j);
    final id = j.containsKey('id')
        ? identifier(j, 'id')
        : importedId(namespace, sourceId);
    final dependencies = <String>{};
    if (j['components'] case final List<Object?> components) {
      for (final c in components) {
        final cj = jsonObject(c, 'component');
        final food = jsonObject(cj['food'], 'component food');
        if (food.containsKey('sourceId')) {
          checkKeys(food, {'sourceId'});
          dependencies.add(importSourceId(food));
        }
      }
    }
    return ImportedFood._(
      sourceId,
      id,
      Map.unmodifiable(j),
      Set.unmodifiable(dependencies),
    );
  }

  final String sourceId;
  final String id;
  final Map<String, Object?> json;

  /// Source ids of foods in the same document this food is composed of.
  final Set<String> dependencies;

  /// The food with document references resolved to pinned revisions.
  Food food(String namespace, FoodRef Function(String sourceId) resolve) {
    final out = <String, Object?>{
      for (final e in json.entries)
        if (e.key != 'sourceId') e.key: e.value,
      'id': id,
      'import': {'namespace': namespace, 'sourceId': sourceId},
    };
    if (json['components'] case final List<Object?> components) {
      out['components'] = [
        for (final c in components)
          if ((c as Map<String, Object?>)['food'] case {
            'sourceId': final String s,
          })
            {...c, 'food': foodRefToJson(resolve(s))}
          else
            c,
      ];
    }
    return Food.fromJson(out);
  }
}

/// A neutral, documented bulk import of base and composite foods (D16).
/// [foods] are in dependency order: components before the composites that
/// use them.
final class FoodImportDocument {
  FoodImportDocument._(this.namespace, this.source, this.foods);

  factory FoodImportDocument.fromJson(Object? input) {
    final j = jsonObject(input, 'food import');
    checkKeys(j, {'format', 'source', 'foods'});
    final header = importHeader(j, foodImportFormat, 'food import');
    final ns = header.namespace;
    final list = jsonList(j, 'foods');
    if (list.isEmpty) invalid('A food import needs foods.');
    if (list.length > _maxFoods)
      invalid('A food import holds at most $_maxFoods foods.');
    final items = [for (final o in list) ImportedFood.fromJson(o, ns)];
    final bySource = <String, ImportedFood>{};
    final ids = <String>{};
    for (final item in items) {
      if (bySource.putIfAbsent(item.sourceId, () => item) != item)
        invalid('Duplicate import sourceId: ${item.sourceId}.');
      if (!ids.add(item.id)) invalid('Duplicate food id: ${item.id}.');
    }
    // Depth-first topological order; a cycle is a validation error.
    final ordered = <ImportedFood>[];
    final state = <String, int>{};
    void visit(ImportedFood item) {
      final s = state[item.sourceId];
      if (s == 2) return;
      if (s == 1) invalid('Imported food ${item.sourceId} contains itself.');
      state[item.sourceId] = 1;
      for (final d in item.dependencies) {
        visit(
          bySource[d] ??
              invalid('Food ${item.sourceId} names unknown sourceId $d.'),
        );
      }
      state[item.sourceId] = 2;
      ordered.add(item);
    }

    items.forEach(visit);
    for (final item in ordered) {
      item.food(ns, (s) => (id: bySource[s]!.id, revision: 1));
    }
    return FoodImportDocument._(ns, header.source, List.unmodifiable(ordered));
  }

  final String namespace;
  final Map<String, Object?> source;
  final List<ImportedFood> foods;
}
