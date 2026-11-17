import 'package:bodytmi_core/bodytmi_core.dart';

import 'canonical_json.dart';
import 'training_repository.dart';

/// Policy bodytmi-sleep-import/1: preview and apply share one plan; apply
/// writes all or nothing. Each entry is `new`, `unchanged`, `changed` or
/// `conflict` (its id belongs to another record, or it overlaps a sleep
/// outside this import). Sleeps of this namespace missing from the document
/// are reported as absent and kept.
final class SleepImportService {
  const SleepImportService(this.repository);
  final TrainingRepository repository;

  Future<Map<String, Object?>> preview(SleepImportDocument document) =>
      repository.transaction(() async => (await _plan(document)).report(false));

  Future<Map<String, Object?>> apply(
    SleepImportDocument document, {
    required String onChanged,
    required bool confirm,
  }) => repository.transaction(() async {
    if (!confirm) invalid('Applying a sleep import requires confirm:true.');
    if (!{'reject', 'update'}.contains(onChanged))
      invalid('onChanged must be reject or update.');
    final plan = await _plan(document);
    final conflicts = plan.entries.where((e) => e.status == 'conflict');
    if (conflicts.isNotEmpty)
      throw BodyTmiException(
        'conflict',
        'Import conflicts with existing sleep: '
            '${conflicts.map((e) => e.item.sourceId).take(10).join(', ')}.',
      );
    final changed = plan.entries.where((e) => e.status == 'changed').length;
    if (changed > 0 && onChanged == 'reject')
      throw BodyTmiException(
        'conflict',
        '$changed previously imported sleeps changed in the source; preview '
            'them and pass onChanged:update to replace them.',
      );
    for (final e in plan.entries) {
      if (e.status != 'new' && e.status != 'changed') continue;
      final version = (e.current?.version ?? 0) + 1;
      await repository.saveSleepRecord(
        e.item.record(document.namespace, version),
      );
      e.written = version;
    }
    return plan.report(true);
  });

  Future<_Plan> _plan(SleepImportDocument document) async {
    final ns = document.namespace;
    final all = await repository.sleepRecords();
    final byId = {for (final r in all) r.id: r};
    final bySource = {
      for (final r in all)
        if (r.importNamespace == ns) r.importSourceId!: r,
    };
    final mine = {for (final i in document.sleeps) i.id(ns)};
    final others = [
      for (final r in all)
        if (!mine.contains(r.id)) r,
    ];
    final entries = <_Entry>[];
    for (final item in document.sleeps) {
      final probe = item.record(ns, 1);
      final current = bySource.remove(item.sourceId);
      final occupant = byId[probe.id];
      String status;
      String? reason;
      final overlap = others
          .where(
            (o) => probe.start.isBefore(o.end) && o.start.isBefore(probe.end),
          )
          .firstOrNull;
      if (current == null && occupant != null) {
        status = 'conflict';
        reason = 'Sleep id ${probe.id} belongs to another record.';
      } else if (current != null && current.id != probe.id) {
        status = 'conflict';
        reason = 'This source id was imported as ${current.id}.';
      } else if (overlap != null) {
        status = 'conflict';
        reason = 'It overlaps sleep ${overlap.id}.';
      } else if (current == null) {
        status = 'new';
      } else {
        status =
            canonicalJson(item.record(ns, current.version).toJson()) ==
                canonicalJson(current.toJson())
            ? 'unchanged'
            : 'changed';
      }
      entries.add(_Entry(item, probe.id, current, status, reason));
    }
    return _Plan(
      document,
      entries,
      [for (final r in bySource.values) r.importSourceId!]..sort(),
    );
  }
}

final class _Entry {
  _Entry(this.item, this.id, this.current, this.status, this.reason);
  final ImportedSleep item;
  final String id;
  final SleepRecord? current;
  final String status;
  final String? reason;
  int? written;
}

final class _Plan {
  _Plan(this.document, this.entries, this.absent);
  final SleepImportDocument document;
  final List<_Entry> entries;
  final List<String> absent;

  Map<String, Object?> report(bool applied) => {
    'policy': sleepImportFormat,
    'applied': applied,
    'source': document.source,
    'counts': {
      for (final s in ['new', 'unchanged', 'changed', 'conflict'])
        s: entries.where((e) => e.status == s).length,
    },
    'sleeps': [
      for (final e in entries)
        {
          'sourceId': e.item.sourceId,
          'id': e.id,
          'status': e.status,
          if (e.reason != null) 'reason': e.reason,
          'version': e.written ?? e.current?.version,
        },
    ],
    'absent': absent,
  };
}
