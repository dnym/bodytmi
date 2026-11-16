import 'package:bodytmi_core/bodytmi_core.dart';
import 'blueprint_service.dart';
import 'canonical_json.dart';
import 'catalog_service.dart';
import 'equipment_service.dart';
import 'training_repository.dart';

/// One planned catalog entry: `new` (published as revision 1), `unchanged`
/// (identical to the latest revision) or `changed` (differs from it).
typedef CatalogImportEntry = ({
  String kind,
  String id,
  String status,
  int? current,
});

/// Previews and applies a [CatalogImportDocument]. Applying is atomic and
/// idempotent: unchanged entries do nothing, new ones are published, and
/// changed ones are refused unless `onChanged: update` publishes their next
/// revision. Nothing is ever deleted; entries missing from the file stay.
final class CatalogImportService {
  const CatalogImportService(this.repository);
  final TrainingRepository repository;

  Future<List<CatalogImportEntry>> _plan(CatalogImportDocument document) async {
    final plan = <CatalogImportEntry>[];
    void add<T>(
      String kind,
      Iterable<T> entries,
      String Function(T) id,
      Map<String, Object?> Function(T) json,
      Map<String, (int, Map<String, Object?>)> latest,
    ) {
      for (final entry in entries) {
        final head = latest[id(entry)];
        plan.add((
          kind: kind,
          id: id(entry),
          status: head == null
              ? 'new'
              : canonicalJson(head.$2) == canonicalJson(json(entry))
              ? 'unchanged'
              : 'changed',
          current: head?.$1,
        ));
      }
    }

    Map<String, (int, Map<String, Object?>)> heads<R>(
      List<R> rows,
      String Function(R) id,
      int Function(R) number,
      Map<String, Object?> Function(R) json,
    ) {
      final out = <String, (int, Map<String, Object?>)>{};
      for (final r in rows) {
        final prior = out[id(r)];
        if (prior == null || number(r) > prior.$1)
          out[id(r)] = (number(r), json(r));
      }
      return out;
    }

    add(
      'exercise',
      document.exercises,
      (e) => e.id,
      (e) => e.toJson(),
      heads(
        await repository.exerciseRevisions(),
        (r) => r.exercise.id,
        (r) => r.number,
        (r) => r.exercise.toJson(),
      ),
    );
    add(
      'implementation',
      document.implementations,
      (i) => i.id,
      (i) => i.toJson(),
      heads(
        await repository.implementationRevisions(),
        (r) => r.implementation.id,
        (r) => r.number,
        (r) => r.implementation.toJson(),
      ),
    );
    add(
      'equipment',
      document.equipment,
      (e) => e.id,
      (e) => e.toJson(),
      heads(
        await repository.equipmentRevisions(),
        (r) => r.equipment.id,
        (r) => r.number,
        (r) => r.equipment.toJson(),
      ),
    );
    add(
      'blueprint',
      document.blueprints,
      (b) => b.id,
      (b) => b.toJson(),
      heads(
        await repository.blueprintRevisions(),
        (r) => r.blueprint.id,
        (r) => r.number,
        (r) => r.blueprint.toJson(),
      ),
    );
    return plan;
  }

  Map<String, Object?> _report(
    CatalogImportDocument document,
    List<CatalogImportEntry> plan,
    bool applied,
  ) => {
    'policy': 'bodytmi-catalog-import-plan/1',
    ...document.summary,
    'applied': applied,
    'counts': {
      for (final status in ['new', 'unchanged', 'changed'])
        status: plan.where((e) => e.status == status).length,
    },
    'entries': [
      for (final e in plan)
        if (e.status != 'unchanged')
          {
            'kind': e.kind,
            'id': e.id,
            'status': e.status,
            if (e.current != null) 'currentRevision': e.current,
          },
    ],
  };

  Future<Map<String, Object?>> preview(CatalogImportDocument document) =>
      repository.transaction(
        () async => _report(document, await _plan(document), false),
      );

  Future<Map<String, Object?>> apply(
    CatalogImportDocument document, {
    required String onChanged,
    required bool confirm,
  }) => repository.transaction(() async {
    if (!confirm) invalid('Applying a catalog import requires confirm:true.');
    if (!{'reject', 'update'}.contains(onChanged))
      invalid('onChanged must be reject or update.');
    final plan = await _plan(document);
    final changed = plan.where((e) => e.status == 'changed').toList();
    if (changed.isNotEmpty && onChanged == 'reject')
      throw BodyTmiException(
        'conflict',
        'Catalog entries differ from their published revisions: '
            '${[for (final e in changed) '${e.kind} ${e.id}'].join(', ')}. '
            'Use onChanged:update to publish new revisions.',
      );
    final byKey = {for (final e in plan) '${e.kind}/${e.id}': e};
    bool publishes(String kind, String id) =>
        byKey['$kind/$id']!.status != 'unchanged';
    int expected(String kind, String id) => byKey['$kind/$id']!.current ?? 0;
    final catalog = CatalogService(repository);
    final equipment = EquipmentService(repository);
    final blueprints = BlueprintService(repository);
    // Exercises before the implementations that name them.
    for (final e in document.exercises) {
      if (publishes('exercise', e.id))
        await catalog.publishExercise(e, expected('exercise', e.id));
    }
    for (final i in document.implementations) {
      if (publishes('implementation', i.id))
        await catalog.publishImplementation(
          i,
          expected('implementation', i.id),
        );
    }
    for (final e in document.equipment) {
      if (publishes('equipment', e.id))
        await equipment.publishEquipment(e, expected('equipment', e.id));
    }
    for (final b in document.blueprints) {
      if (publishes('blueprint', b.id))
        await blueprints.publish(b, expected('blueprint', b.id));
    }
    return _report(document, plan, true);
  });
}
