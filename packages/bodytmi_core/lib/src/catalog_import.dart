import 'blueprint.dart';
import 'catalog.dart';
import 'equipment.dart';
import 'errors.dart';

/// A neutral, documented catalog file (format `bodytmi-catalog-import/1`):
/// exercises, implementations, equipment definitions and blueprints in their
/// ordinary JSON shapes, plus the source that curated them. The shipped
/// starter catalog is one such file; anyone can write another.
final class CatalogImportDocument {
  CatalogImportDocument._(
    this.sourceName,
    this.sourceVersion,
    this.sourceNotes,
    this.exercises,
    this.implementations,
    this.equipment,
    this.blueprints,
  );

  static const format = 'bodytmi-catalog-import/1';

  factory CatalogImportDocument.fromJson(Object? input) {
    final j = jsonObject(input, 'catalog import');
    checkKeys(j, {
      'format',
      'source',
      'exercises',
      'implementations',
      'equipment',
      'blueprints',
    });
    if (j['format'] != format) invalid('Catalog imports use format $format.');
    final source = jsonObject(j['source'], 'source');
    checkKeys(source, {'name', 'version', 'notes'});
    String? text(String key, int max, {bool required = false}) {
      final value = source[key];
      if (value == null && !required) return null;
      if (value is! String || value.trim().isEmpty || value.length > max)
        invalid('Catalog source $key is a nonempty string up to $max.');
      return value;
    }

    List<T> entries<T>(
      String key,
      T Function(Object?) parse,
      String Function(T) id,
    ) {
      if (!j.containsKey(key)) return const [];
      final list = jsonList(j, key);
      if (list.length > 10000) invalid('Catalog $key list at most 10000.');
      final parsed = [for (final item in list) parse(item)];
      final ids = {for (final p in parsed) id(p)};
      if (ids.length != parsed.length)
        invalid('Catalog $key identities must be unique.');
      return List.unmodifiable(parsed);
    }

    final document = CatalogImportDocument._(
      text('name', 200, required: true)!,
      text('version', 64),
      text('notes', 4000),
      entries('exercises', ExerciseDefinition.fromJson, (e) => e.id),
      entries('implementations', ExerciseImplementation.fromJson, (i) => i.id),
      entries('equipment', EquipmentDefinition.fromJson, (e) => e.id),
      entries('blueprints', Blueprint.fromJson, (b) => b.id),
    );
    if (document.exercises.isEmpty &&
        document.implementations.isEmpty &&
        document.equipment.isEmpty &&
        document.blueprints.isEmpty)
      invalid('A catalog import contains at least one entry.');
    return document;
  }

  final String sourceName;
  final String? sourceVersion, sourceNotes;
  final List<ExerciseDefinition> exercises;
  final List<ExerciseImplementation> implementations;
  final List<EquipmentDefinition> equipment;
  final List<Blueprint> blueprints;

  Map<String, Object?> get summary => {
    'format': format,
    'source': {
      'name': sourceName,
      if (sourceVersion != null) 'version': sourceVersion,
    },
    'exercises': exercises.length,
    'implementations': implementations.length,
    'equipment': equipment.length,
    'blueprints': blueprints.length,
  };
}
