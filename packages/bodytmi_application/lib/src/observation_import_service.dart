import 'package:bodytmi_core/bodytmi_core.dart';
import 'canonical_json.dart';
import 'observation_service.dart';
import 'training_repository.dart';

/// Policy bodytmi-observation-import/1. Preview and apply evaluate the same
/// plan; apply writes it in one transaction or not at all. Each entry is
/// `new`, `unchanged`, `changed` (the source edited a previously imported
/// entry), `deleted` (imported earlier, then deleted here: kept deleted and
/// never resurrected) or `conflict` (its observation id belongs to another
/// record). Observations of this namespace missing from the document are
/// reported as absent and kept.
final class ObservationImportService {
  const ObservationImportService(this.repository);
  final TrainingRepository repository;

  Future<Map<String, Object?>> preview(ObservationImportDocument document) =>
      repository.transaction(() async => (await _plan(document)).report(false));

  Future<Map<String, Object?>> apply(
    ObservationImportDocument document, {
    required String onChanged,
    required bool confirm,
  }) => repository.transaction(() async {
    if (!confirm)
      invalid('Applying an observation import requires confirm:true.');
    if (!{'reject', 'update'}.contains(onChanged))
      invalid('onChanged must be reject or update.');
    final plan = await _plan(document);
    final conflicts = plan.entries.where((e) => e.status == 'conflict');
    if (conflicts.isNotEmpty)
      throw BodyTmiException(
        'conflict',
        'Import conflicts with existing observations: '
            '${conflicts.map((e) => e.item.sourceId).take(10).join(', ')}.',
      );
    final changed = plan.count('changed');
    if (changed > 0 && onChanged == 'reject')
      throw BodyTmiException(
        'conflict',
        '$changed previously imported observations changed in the source; '
            'preview them and pass onChanged:update to replace them.',
      );
    for (final e in plan.entries) {
      if (e.status != 'new' && e.status != 'changed') continue;
      final version = (e.current?.observation.contentVersion ?? 0) + 1;
      await repository.saveObservationRecord(
        ObservationRecord(e.item.observation(document.namespace, version)),
      );
      e.written = version;
    }
    return plan.report(true);
  });

  Future<_Plan> _plan(ObservationImportDocument document) async {
    final ns = document.namespace;
    final measures = {
      for (final m in await ObservationService(repository).measures()) m.id: m,
    };
    final all = await repository.observationRecords();
    final byId = {for (final r in all) r.observation.id: r};
    final bySource = {
      for (final r in all)
        if (r.observation.importNamespace == ns)
          r.observation.importSourceId!: r,
    };
    final entries = <_Entry>[];
    for (final item in document.observations) {
      final probe = item.observation(ns, 1);
      final measure =
          measures[probe.measureId] ??
          (throw BodyTmiException(
            'not_found',
            'Measure not found: ${probe.measureId} (sourceId '
                '${item.sourceId}).',
          ));
      probe.validateAgainst(measure);
      if (probe.isBodyMass) probe.toBodyMass();
      final current = bySource.remove(item.sourceId);
      final occupant = byId[probe.id];
      String status;
      String? reason;
      if (current == null) {
        if (occupant != null) {
          status = 'conflict';
          reason = 'Observation id ${probe.id} belongs to another record.';
        } else {
          status = 'new';
        }
      } else if (current.observation.id != probe.id) {
        status = 'conflict';
        reason =
            'This source id was imported as ${current.observation.id}, '
            'not ${probe.id}.';
      } else if (current.deleted) {
        status = 'deleted';
      } else if (current.observation.measureId != probe.measureId) {
        status = 'conflict';
        reason = 'An observation cannot change its measure.';
      } else {
        status =
            canonicalJson(
                  item
                      .observation(ns, current.observation.contentVersion)
                      .toJson(),
                ) ==
                canonicalJson(current.observation.toJson())
            ? 'unchanged'
            : 'changed';
      }
      entries.add(_Entry(item, probe.id, current, status, reason));
    }
    return _Plan(
      document,
      entries,
      [
        for (final r in bySource.values)
          if (!r.deleted) r.observation.importSourceId!,
      ]..sort(),
    );
  }
}

final class _Entry {
  _Entry(this.item, this.id, this.current, this.status, this.reason);
  final ImportedObservation item;
  final String id;
  final ObservationRecord? current;
  final String status;
  final String? reason;
  int? written;
}

final class _Plan {
  _Plan(this.document, this.entries, this.absent);
  final ObservationImportDocument document;
  final List<_Entry> entries;
  final List<String> absent;

  int count(String status) => entries.where((e) => e.status == status).length;

  Map<String, Object?> report(bool applied) => {
    'policy': observationImportFormat,
    'applied': applied,
    'source': document.source,
    'counts': {
      for (final s in ['new', 'unchanged', 'changed', 'deleted', 'conflict'])
        s: count(s),
    },
    'observations': [
      for (final e in entries)
        {
          'sourceId': e.item.sourceId,
          'id': e.id,
          'status': e.status,
          if (e.reason != null) 'reason': e.reason,
          'contentVersion': e.written ?? e.current?.observation.contentVersion,
        },
    ],
    // Earlier imports missing from this document are kept, never deleted.
    'absent': absent,
  };
}
