import 'package:bodytmi_core/bodytmi_core.dart';

import 'canonical_json.dart';
import 'diary_service.dart';
import 'training_repository.dart';

/// Policy bodytmi-food-import/1: preview and apply share one plan; apply
/// writes all or nothing. A food is `new`, `unchanged`, `changed` (a new
/// revision is published only with onChanged:update) or `conflict` (its id
/// belongs to a food not written by this namespace and source id, or a
/// component is in conflict). Composites pin the revision each document
/// component gets in this same import, so a changed component also changes
/// the composites that use it. Earlier revisions, and everything logged
/// with them, never change. Foods of this namespace missing from the
/// document are reported as absent and kept.
final class FoodImportService {
  const FoodImportService(this.repository);
  final TrainingRepository repository;

  Future<Map<String, Object?>> preview(FoodImportDocument document) =>
      repository.transaction(() async => (await _plan(document)).report(false));

  Future<Map<String, Object?>> apply(
    FoodImportDocument document, {
    required String onChanged,
    required bool confirm,
  }) => repository.transaction(() async {
    if (!confirm) invalid('Applying a food import requires confirm:true.');
    _checkOnChanged(onChanged);
    final plan = await _plan(document);
    _refuse(plan.entries.map((e) => (e.item.sourceId, e.status)), onChanged);
    for (final e in plan.entries) {
      if (e.status != 'new' && e.status != 'changed') continue;
      final next = FoodRevision.publish(e.food!, previous: e.current);
      await repository.insertFoodRevision(next);
      e.written = next.number;
    }
    return plan.report(true);
  });

  Future<_FoodPlan> _plan(FoodImportDocument document) async {
    final ns = document.namespace;
    final all = await repository.foodRevisions();
    final latest = <String, FoodRevision>{};
    final byKey = <String, FoodRevision>{};
    for (final r in all) {
      latest[r.food.id] = r;
      byKey[foodRefKey(r.ref)] = r;
    }
    final bySource = <String, FoodRevision>{
      for (final r in latest.values)
        if (r.food.origin?.namespace == ns) r.food.origin!.sourceId: r,
    };
    final planned = <String, _FoodEntry>{};
    FoodRevision lookup(FoodRef ref) =>
        byKey[foodRefKey(ref)] ??
        invalid('Food revision ${foodRefKey(ref)} is not published.');
    for (final item in document.foods) {
      final current = latest[item.id];
      final previous = bySource.remove(item.sourceId);
      final blocked = item.dependencies
          .where((d) => planned[d]!.status == 'conflict')
          .firstOrNull;
      String status;
      String? reason;
      Food? food;
      if (current != null &&
          current.food.origin != (namespace: ns, sourceId: item.sourceId)) {
        status = 'conflict';
        reason = 'Food id ${item.id} belongs to another food.';
      } else if (previous != null && previous.food.id != item.id) {
        status = 'conflict';
        reason = 'This source id was imported as ${previous.food.id}.';
      } else if (blocked != null) {
        status = 'conflict';
        reason = 'Component $blocked is in conflict.';
      } else {
        food = item.food(ns, (s) => planned[s]!.ref);
        if (current != null &&
            canonicalJson(food.toJson()) ==
                canonicalJson(current.food.toJson())) {
          status = 'unchanged';
        } else {
          status = current == null ? 'new' : 'changed';
          validateFoodComposition(food, lookup);
          final next = FoodRevision.publish(food, previous: current);
          byKey[foodRefKey(next.ref)] = next;
        }
      }
      planned[item.sourceId] = _FoodEntry(item, current, status, reason, food);
    }
    return _FoodPlan(document, [
      for (final item in document.foods) planned[item.sourceId]!,
    ], [for (final r in bySource.values) r.food.origin!.sourceId]..sort());
  }
}

void _checkOnChanged(String onChanged) {
  if (!{'reject', 'update'}.contains(onChanged))
    invalid('onChanged must be reject or update.');
}

void _refuse(Iterable<(String, String)> statuses, String onChanged) {
  final list = statuses.toList();
  final conflicts = [
    for (final (id, s) in list)
      if (s == 'conflict') id,
  ];
  if (conflicts.isNotEmpty)
    throw BodyTmiException(
      'conflict',
      'Import conflicts with existing records: '
          '${conflicts.take(10).join(', ')}.',
    );
  final changed = list.where((e) => e.$2 == 'changed').length;
  if (changed > 0 && onChanged == 'reject')
    throw BodyTmiException(
      'conflict',
      '$changed previously imported records changed in the source; preview '
          'them and pass onChanged:update to replace them.',
    );
}

final class _FoodEntry {
  _FoodEntry(this.item, this.current, this.status, this.reason, this.food);
  final ImportedFood item;
  final FoodRevision? current;
  final String status;
  final String? reason;
  final Food? food;
  int? written;

  /// The revision this food has once the import is applied.
  FoodRef get ref => (
    id: item.id,
    revision: switch (status) {
      'new' => 1,
      'changed' => current!.number + 1,
      _ => current!.number,
    },
  );
}

final class _FoodPlan {
  _FoodPlan(this.document, this.entries, this.absent);
  final FoodImportDocument document;
  final List<_FoodEntry> entries;
  final List<String> absent;

  Map<String, Object?> report(bool applied) => {
    'policy': foodImportFormat,
    'applied': applied,
    'source': document.source,
    'counts': _counts(entries.map((e) => e.status)),
    'foods': [
      for (final e in entries)
        {
          'sourceId': e.item.sourceId,
          'id': e.item.id,
          'status': e.status,
          if (e.reason != null) 'reason': e.reason,
          'revision': e.written ?? e.current?.number,
        },
    ],
    'absent': absent,
  };
}

Map<String, int> _counts(Iterable<String> statuses) {
  final list = statuses.toList();
  return {
    for (final s in ['new', 'unchanged', 'changed', 'conflict'])
      s: list.where((e) => e == s).length,
  };
}

/// Policy bodytmi-diary-import/1: like the food import. An entry naming its
/// food without a revision pins the latest on first import and keeps that
/// pin afterwards. Day marks are `new`, `unchanged` or `changed`. Entries of
/// this namespace missing from the document are reported as absent and
/// kept; day marks are never removed.
final class DiaryImportService {
  const DiaryImportService(this.repository);
  final TrainingRepository repository;

  Future<Map<String, Object?>> preview(DiaryImportDocument document) =>
      repository.transaction(() async => (await _plan(document)).report(false));

  Future<Map<String, Object?>> apply(
    DiaryImportDocument document, {
    required String onChanged,
    required bool confirm,
  }) => repository.transaction(() async {
    if (!confirm) invalid('Applying a diary import requires confirm:true.');
    _checkOnChanged(onChanged);
    final plan = await _plan(document);
    _refuse([
      for (final e in plan.entries) (e.item.sourceId, e.status),
      for (final d in plan.days) ('day ${d.mark.date}', d.status),
    ], onChanged);
    for (final e in plan.entries) {
      if (e.status != 'new' && e.status != 'changed') continue;
      await repository.saveDiaryEntry(e.entry!);
      e.written = e.entry!.version;
    }
    final diary = DiaryService(repository);
    for (final d in plan.days) {
      if (d.status == 'unchanged') continue;
      await diary.setMark(d.mark.date, d.mark.status);
    }
    return plan.report(true);
  });

  Future<_DiaryPlan> _plan(DiaryImportDocument document) async {
    final ns = document.namespace;
    final diary = DiaryService(repository);
    final dayStart = await diary.dayStart();
    final revisions = await repository.foodRevisions();
    final latest = <String, FoodRevision>{};
    final byKey = <String, FoodRevision>{};
    final imported = <String, String>{};
    for (final r in revisions) {
      latest[r.food.id] = r;
      byKey[foodRefKey(r.ref)] = r;
      if (r.food.origin case final o?)
        imported['${o.namespace}\u0000${o.sourceId}'] = r.food.id;
    }
    final math = FoodMath(
      (ref) =>
          byKey[foodRefKey(ref)] ??
          invalid('Food revision ${foodRefKey(ref)} is not published.'),
    );
    final all = await repository.diaryEntries();
    final byId = {for (final e in all) e.id: e};
    final bySource = {
      for (final e in all)
        if (e.origin?.namespace == ns) e.origin!.sourceId: e,
    };
    final entries = <_DiaryEntry>[];
    for (final item in document.entries) {
      final current = bySource.remove(item.sourceId);
      final occupant = byId[item.id];
      String? reason;
      ({String id, int revision})? pinned;
      if (item.food case final ref?) {
        final id = ref.id ?? imported['${ref.namespace}\u0000${ref.sourceId}'];
        if (id == null) {
          reason =
              'Food ${ref.namespace}/${ref.sourceId} has not been imported.';
        } else if (latest[id] == null) {
          reason = 'Food $id is not published.';
        } else {
          final kept = current?.food?.id == id ? current!.food!.revision : null;
          pinned = (
            id: id,
            revision: ref.revision ?? kept ?? latest[id]!.number,
          );
          if (byKey[foodRefKey(pinned)] == null)
            reason = 'Food revision ${foodRefKey(pinned)} is not published.';
        }
      }
      if (current == null && occupant != null) {
        reason = 'Diary entry id ${item.id} belongs to another entry.';
      } else if (current != null && current.id != item.id) {
        reason = 'This source id was imported as ${current.id}.';
      }
      if (reason != null) {
        entries.add(_DiaryEntry(item, current, 'conflict', reason, null));
        continue;
      }
      final probe = item.entry(
        ns,
        current?.version ?? 1,
        pinned,
        dayStart: dayStart,
      );
      probe.nutrition(math);
      if (current != null &&
          canonicalJson(probe.toJson()) == canonicalJson(current.toJson())) {
        entries.add(_DiaryEntry(item, current, 'unchanged', null, null));
      } else {
        final next = current == null
            ? probe
            : item.entry(ns, current.version + 1, pinned, dayStart: dayStart);
        entries.add(
          _DiaryEntry(
            item,
            current,
            current == null ? 'new' : 'changed',
            null,
            next,
          ),
        );
      }
    }
    final days = <_DayEntry>[];
    for (final mark in document.days) {
      final existing = await diary.mark(mark.date);
      final before = existing?.status ?? 'unmarked';
      days.add(
        _DayEntry(
          mark,
          before,
          before == mark.status
              ? 'unchanged'
              : existing == null || before == 'unmarked'
              ? 'new'
              : 'changed',
        ),
      );
    }
    return _DiaryPlan(
      document,
      entries,
      days,
      [for (final e in bySource.values) e.origin!.sourceId]..sort(),
    );
  }
}

final class _DiaryEntry {
  _DiaryEntry(this.item, this.current, this.status, this.reason, this.entry);
  final ImportedDiaryEntry item;
  final DiaryEntry? current;
  final String status;
  final String? reason;
  final DiaryEntry? entry;
  int? written;
}

final class _DayEntry {
  _DayEntry(this.mark, this.before, this.status);
  final DiaryDayMark mark;
  final String before;
  final String status;
}

final class _DiaryPlan {
  _DiaryPlan(this.document, this.entries, this.days, this.absent);
  final DiaryImportDocument document;
  final List<_DiaryEntry> entries;
  final List<_DayEntry> days;
  final List<String> absent;

  Map<String, Object?> report(bool applied) => {
    'policy': diaryImportFormat,
    'applied': applied,
    'source': document.source,
    'counts': _counts(entries.map((e) => e.status)),
    'dayCounts': _counts(days.map((d) => d.status)),
    'entries': [
      for (final e in entries)
        {
          'sourceId': e.item.sourceId,
          'id': e.item.id,
          'status': e.status,
          if (e.reason != null) 'reason': e.reason,
          if ((e.entry ?? e.current)?.food case final f?)
            'food': foodRefToJson(f),
          if ((e.entry ?? e.current)?.date case final d?) 'date': d,
          'version': e.written ?? e.current?.version,
        },
    ],
    'days': [
      for (final d in days)
        {
          'date': d.mark.date,
          'status': d.status,
          'before': d.before,
          'mark': d.mark.status,
        },
    ],
    'absent': absent,
  };
}
