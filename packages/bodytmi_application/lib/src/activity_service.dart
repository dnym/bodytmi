import 'package:bodytmi_core/bodytmi_core.dart';

import 'canonical_json.dart';
import 'training_repository.dart';

/// Walks, outdoor time, sedentary time and other activities (APP-PLAN 4.5).
final class ActivityService {
  const ActivityService(this.repository);
  final TrainingRepository repository;

  Future<ActivityRecord> record(String id) async =>
      await repository.activityRecord(id) ??
      (throw BodyTmiException('not_found', 'Activity $id not found.'));

  Future<ActivityRecord> add(Map<String, Object?> input) =>
      repository.transaction(() async {
        if (input.containsKey('version'))
          invalid('The service assigns the version.');
        final r = ActivityRecord.fromJson({...input, 'version': 1});
        if (await repository.activityRecord(r.id) != null)
          throw BodyTmiException('conflict', 'Activity ${r.id} exists.');
        await repository.saveActivityRecord(r);
        return r;
      });

  Future<ActivityRecord> update(
    String id,
    int expectedVersion,
    Map<String, Object?> input,
  ) => repository.transaction(() async {
    final before = await record(id);
    if (before.version != expectedVersion)
      throw const BodyTmiException('conflict', 'Activity changed.');
    if (input['id'] != id) invalid('An update keeps the activity id.');
    if (input.containsKey('version'))
      invalid('The service assigns the version.');
    final r = ActivityRecord.fromJson({
      ...input,
      'version': before.version + 1,
      'import': ?before.json['import'],
    });
    await repository.saveActivityRecord(r);
    return r;
  });

  Future<void> delete(String id, int expectedVersion) =>
      repository.transaction(() async {
        final before = await record(id);
        if (before.version != expectedVersion)
          throw const BodyTmiException('conflict', 'Activity changed.');
        await repository.deleteActivityRecord(id);
      });

  /// Policy bodytmi-activity-summary/1: per day, minutes and count per kind,
  /// per category (each activity counts once toward each category it
  /// names), outdoor minutes and sedentary minutes, from the activities
  /// that start on that day. Days without activities are listed as such,
  /// not as zero activity.
  Future<Map<String, Object?>> summary(String from, String until) async {
    checkDate(from, 'from');
    checkDate(until, 'until');
    final count = daysBetween(from, until);
    if (count < 1 || count > 366) invalid('A summary spans 1–366 days.');
    final records = await repository.activityRecords(
      fromDate: from,
      untilDate: until,
    );
    final days = <Map<String, Object?>>[];
    for (var i = 0; i < count; i++) {
      final date = addDays(from, i);
      final todays = [
        for (final r in records)
          if (r.date == date) r,
      ];
      Map<String, Object?> tally(Iterable<ActivityRecord> rs) => {
        'count': rs.length,
        'minutes': rs.fold<int>(0, (s, r) => s + r.minutes),
      };
      final kinds = {for (final r in todays) r.kind};
      final categories = {for (final r in todays) ...r.countsToward};
      days.add({
        'date': date,
        'activities': todays.length,
        'kinds': {
          for (final k in kinds.toList()..sort())
            k: tally(todays.where((r) => r.kind == k)),
        },
        'categories': {
          for (final c in categories.toList()..sort())
            c: {
              ...tally(todays.where((r) => r.countsToward.contains(c))),
              'activities': [
                for (final r in todays)
                  if (r.countsToward.contains(c)) r.id,
              ],
            },
        },
        'outdoorMinutes': todays
            .where((r) => r.outdoor)
            .fold<int>(0, (s, r) => s + r.minutes),
        'sedentaryMinutes': todays
            .where((r) => r.kind == 'sedentary')
            .fold<int>(0, (s, r) => s + r.minutes),
      });
    }
    return {
      'policy': 'bodytmi-activity-summary/1',
      'from': from,
      'until': until,
      'note':
          'Activity energy is never added to the intake budget. A day with '
          'no activities logged is not a day without activity.',
      'days': days,
    };
  }
}

/// Policy bodytmi-activity-import/1: preview and apply share one plan; apply
/// writes all or nothing; new, unchanged, changed or conflict (an id held
/// by another record). Activities of the namespace missing from the
/// document are reported as absent and kept.
final class ActivityImportService {
  const ActivityImportService(this.repository);
  final TrainingRepository repository;

  Future<Map<String, Object?>> preview(ActivityImportDocument d) =>
      repository.transaction(() async => _report(d, await _plan(d), false));

  Future<Map<String, Object?>> apply(
    ActivityImportDocument d, {
    required String onChanged,
    required bool confirm,
  }) => repository.transaction(() async {
    if (!confirm) invalid('Applying an activity import requires confirm:true.');
    if (!{'reject', 'update'}.contains(onChanged))
      invalid('onChanged must be reject or update.');
    final plan = await _plan(d);
    final conflicts = plan.where((e) => e.status == 'conflict');
    if (conflicts.isNotEmpty)
      throw BodyTmiException(
        'conflict',
        'Import conflicts with existing activities: '
            '${conflicts.map((e) => e.item.sourceId).take(10).join(', ')}.',
      );
    final changed = plan.where((e) => e.status == 'changed').length;
    if (changed > 0 && onChanged == 'reject')
      throw BodyTmiException(
        'conflict',
        '$changed previously imported activities changed in the source; '
            'preview them and pass onChanged:update to replace them.',
      );
    for (final e in plan) {
      if (e.status != 'new' && e.status != 'changed') continue;
      e.written = (e.current?.version ?? 0) + 1;
      await repository.saveActivityRecord(
        e.item.record(d.namespace, e.written!),
      );
    }
    return _report(d, plan, true);
  });

  Future<List<_Entry>> _plan(ActivityImportDocument d) async {
    final ns = d.namespace;
    final all = await repository.activityRecords();
    final byId = {for (final r in all) r.id: r};
    final bySource = {
      for (final r in all)
        if (r.importNamespace == ns) r.importSourceId!: r,
    };
    return [
      for (final item in d.activities)
        () {
          final probe = item.record(ns, 1);
          final current = bySource[item.sourceId];
          final occupant = byId[probe.id];
          if (current == null && occupant != null)
            return _Entry(item, probe.id, null, 'conflict');
          if (current != null && current.id != probe.id)
            return _Entry(item, probe.id, current, 'conflict');
          if (current == null) return _Entry(item, probe.id, null, 'new');
          return _Entry(
            item,
            probe.id,
            current,
            canonicalJson(item.record(ns, current.version).toJson()) ==
                    canonicalJson(current.toJson())
                ? 'unchanged'
                : 'changed',
          );
        }(),
    ];
  }

  Future<Map<String, Object?>> _report(
    ActivityImportDocument d,
    List<_Entry> plan,
    bool applied,
  ) async {
    final present = {for (final i in d.activities) i.sourceId};
    final absent = [
      for (final r in await repository.activityRecords())
        if (r.importNamespace == d.namespace &&
            !present.contains(r.importSourceId))
          r.importSourceId!,
    ]..sort();
    return {
      'policy': activityImportFormat,
      'applied': applied,
      'source': d.source,
      'counts': {
        for (final s in ['new', 'unchanged', 'changed', 'conflict'])
          s: plan.where((e) => e.status == s).length,
      },
      'activities': [
        for (final e in plan)
          {
            'sourceId': e.item.sourceId,
            'id': e.id,
            'status': e.status,
            'version': e.written ?? e.current?.version,
          },
      ],
      'absent': absent,
    };
  }
}

final class _Entry {
  _Entry(this.item, this.id, this.current, this.status);
  final ImportedActivity item;
  final String id;
  final ActivityRecord? current;
  final String status;
  int? written;
}
