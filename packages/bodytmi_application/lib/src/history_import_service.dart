import 'package:bodytmi_core/bodytmi_core.dart';

import 'canonical_json.dart';
import 'stored_body_mass_service.dart';
import 'training_repository.dart';

/// One imported past session, keyed by its source namespace and source ID.
/// It is deliberately separate from native sessions: it pins no workout
/// revision and never feeds prefill, progression, records or program cursors.
final class ImportedSessionRecord {
  ImportedSessionRecord({
    required this.namespace,
    required this.contentVersion,
    required this.importedAt,
    required this.updatedAt,
    required this.source,
    required this.session,
  }) {
    identifier({'namespace': namespace}, 'namespace');
    if (contentVersion < 1) invalid('contentVersion must be positive.');
    parseInstant(importedAt, 'importedAt');
    if (updatedAt != null &&
        parseInstant(
          updatedAt,
          'updatedAt',
        ).isBefore(parseInstant(importedAt, 'importedAt')))
      invalid('Imported session updatedAt cannot precede importedAt.');
    if ((contentVersion == 1) != (updatedAt == null))
      invalid('Only an updated imported session records updatedAt.');
    if (source['namespace'] != namespace)
      invalid('Imported session source namespace is inconsistent.');
  }

  factory ImportedSessionRecord.fromJson(Object? input) {
    final j = jsonObject(input, 'imported session record');
    checkKeys(j, {
      'schemaVersion',
      'namespace',
      'contentVersion',
      'importedAt',
      'updatedAt',
      'source',
      'session',
    });
    if (j['schemaVersion'] != 1)
      invalid('Unsupported imported session record version.');
    final version = j['contentVersion'];
    if (version is! int) invalid('contentVersion must be an integer.');
    final source = jsonObject(j['source'], 'source');
    checkKeys(source, {'namespace', 'app', 'version', 'exportedAt'});
    for (final key in ['app', 'version'])
      if (source.containsKey(key)) requiredString(source, key);
    if (source.containsKey('exportedAt'))
      parseInstant(source['exportedAt'], 'exportedAt');
    final session = ImportedSession.fromJson(j['session']);
    // Snapshots are stored normalized; anything else was not written by us.
    if (canonicalJson(session.toJson()) != canonicalJson(j['session']))
      invalid('Imported session snapshot is not normalized.');
    return ImportedSessionRecord(
      namespace: identifier(j, 'namespace'),
      contentVersion: version,
      importedAt: requiredString(j, 'importedAt'),
      updatedAt: j.containsKey('updatedAt')
          ? requiredString(j, 'updatedAt')
          : null,
      source: Map.unmodifiable(source),
      session: session,
    );
  }

  final String namespace, importedAt;
  final String? updatedAt;
  final int contentVersion;
  final Map<String, Object?> source;
  final ImportedSession session;
  String get sourceId => session.sourceId;

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'namespace': namespace,
    'contentVersion': contentVersion,
    'importedAt': importedAt,
    if (updatedAt != null) 'updatedAt': updatedAt,
    'source': source,
    'session': session.toJson(),
  };

  Map<String, Object?> get summary => {
    'namespace': namespace,
    'sourceId': sourceId,
    'contentVersion': contentVersion,
    'date': session.date,
    'startedAt': session.startedAtText,
    if (session.name != null) 'name': session.name,
    'exercises': session.exercises.length,
    'sets': session.setCount,
  };
}

/// Archive/backup validation: unique identities within each namespace.
void validateImportedSessions(List<ImportedSessionRecord> records) {
  final keys = <String>{};
  for (final record in records) {
    if (!keys.add('${record.namespace}\u0000${record.sourceId}'))
      invalid('Duplicate imported session identity.');
  }
}

/// Pure validation: the normalized document plus what it leaves unknown.
Map<String, Object?> validateHistoryImport(HistoryImportDocument document) => {
  'policy': historyImportFormat,
  'source': document.source,
  'unknowns': document.unknowns,
  'sessions': [for (final s in document.sessions) s.toJson()],
  'measurements': [for (final m in document.measurements) m.toJson()],
};

const _provenancePrefix = 'bodytmi-history-import:';

/// Policy bodytmi-history-import/1. Preview and apply evaluate the same plan;
/// apply writes it in one transaction or not at all.
final class HistoryImportService {
  const HistoryImportService(this.repository);
  final TrainingRepository repository;

  Future<Map<String, Object?>> preview(HistoryImportDocument document) =>
      repository.transaction(() async => (await _plan(document)).report(false));

  Future<Map<String, Object?>> apply(
    HistoryImportDocument document, {
    required DateTime at,
    required String atText,
    required String onChanged,
    required bool confirm,
  }) => repository.transaction(() async {
    if (!confirm) invalid('Applying a history import requires confirm:true.');
    if (!{'reject', 'update'}.contains(onChanged))
      invalid('onChanged must be reject or update.');
    final plan = await _plan(document);
    final conflicts = plan.measurements.where((m) => m.status == 'conflict');
    if (conflicts.isNotEmpty)
      throw BodyTmiException(
        'conflict',
        'Import conflicts with existing body-mass identities: '
            '${conflicts.map((m) => m.item.id).take(10).join(', ')}.',
      );
    final changed = plan.changedCount;
    if (changed > 0 && onChanged == 'reject')
      throw BodyTmiException(
        'conflict',
        '$changed previously imported records changed in the source; '
            'preview them and pass onChanged:update to replace them.',
      );
    for (final entry in plan.sessions) {
      final current = entry.current;
      if (entry.status == 'unchanged') continue;
      if (current != null &&
          parseInstant(current.importedAt, 'importedAt').isAfter(at))
        throw const BodyTmiException(
          'conflict',
          'Import time precedes the existing import of a changed session.',
        );
      final record = ImportedSessionRecord(
        namespace: document.namespace,
        contentVersion: (current?.contentVersion ?? 0) + 1,
        importedAt: current?.importedAt ?? atText,
        updatedAt: current == null ? null : atText,
        source: document.source,
        session: entry.item,
      );
      await repository.saveImportedSession(record);
      entry.written = record.contentVersion;
    }
    for (final entry in plan.measurements) {
      if (entry.status == 'unchanged') continue;
      final version = (entry.current?.measurement.contentVersion ?? 0) + 1;
      await repository.saveBodyMassRecord(
        BodyMassRecord(entry.item.measurement(document.namespace, version)),
      );
      entry.written = version;
    }
    return plan.report(true);
  });

  Future<List<ImportedSessionRecord>> list({String? namespace}) async {
    if (namespace != null) identifier({'namespace': namespace}, 'namespace');
    return [
      for (final r in await repository.importedSessions())
        if (namespace == null || r.namespace == namespace) r,
    ]..sort(_order);
  }

  Future<ImportedSessionRecord> show(String namespace, String sourceId) async =>
      (await repository.importedSessions())
          .where((r) => r.namespace == namespace && r.sourceId == sourceId)
          .firstOrNull ??
      (throw const BodyTmiException(
        'not_found',
        'Imported session not found.',
      ));

  /// Removing imported history is explicit; reimports never delete records
  /// that are absent from a later source export.
  Future<ImportedSessionRecord> delete(
    String namespace,
    String sourceId,
    int expectedVersion, {
    required bool confirm,
  }) => repository.transaction(() async {
    if (!confirm) invalid('Deleting imported history requires confirm:true.');
    final current = await show(namespace, sourceId);
    if (current.contentVersion != expectedVersion)
      throw const BodyTmiException(
        'conflict',
        'Imported session version has changed.',
      );
    await repository.deleteImportedSession(namespace, sourceId);
    return current;
  });

  /// Read-only observed points. Each context keeps its namespace, catalog
  /// mapping (or exact source name when unmapped), implementation, equipment,
  /// load convention, role and entered unit separate. Date-only sessions are
  /// ordered by calendar date only and are never given an invented time.
  Future<Map<String, Object?>> series({
    required String metric,
    String? namespace,
    String? exerciseId,
    String? exerciseName,
    Set<String>? roles,
    String? from,
    String? until,
  }) => repository.transaction(() async {
    identifier({'metric': metric}, 'metric');
    if (exerciseId != null)
      identifier({'exerciseId': exerciseId}, 'exerciseId');
    if (from != null) calendarDate(from, 'from');
    if (until != null) calendarDate(until, 'until');
    if (from != null && until != null && from.compareTo(until) >= 0)
      invalid('from must precede until.');
    final selectedRoles = roles ?? historyImportRoles.difference({'warmup'});
    if (selectedRoles.isEmpty || !historyImportRoles.containsAll(selectedRoles))
      invalid('roles must name ${historyImportRoles.join('/')}.');
    final selection = selectImportedSeries(
      await list(namespace: namespace),
      metric: metric,
      roles: selectedRoles,
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      fromDate: from,
      untilDate: until,
    );
    return {
      'policy': 'bodytmi-imported-series/1',
      'ordering': importedSeriesOrdering,
      'metric': metric,
      'roles': selectedRoles.toList()..sort(),
      'series': selection.series,
    };
  });

  Future<_Plan> _plan(HistoryImportDocument document) async {
    final stored = {
      for (final r in await repository.importedSessions())
        if (r.namespace == document.namespace) r.sourceId: r,
    };
    final sessions = <_Entry<ImportedSession, ImportedSessionRecord>>[];
    for (final session in document.sessions) {
      final current = stored.remove(session.sourceId);
      sessions.add(
        _Entry(
          session,
          current,
          current == null
              ? 'new'
              : canonicalJson(current.session.toJson()) ==
                    canonicalJson(session.toJson())
              ? 'unchanged'
              : 'changed',
        ),
      );
    }
    final mass = {
      for (final r in await repository.bodyMassRecords()) r.measurement.id: r,
    };
    final prefix = '$_provenancePrefix${document.namespace}:';
    final listed = {for (final m in document.measurements) m.id};
    final measurements = <_Entry<ImportedMeasurement, BodyMassRecord>>[];
    for (final item in document.measurements) {
      final current = mass[item.id];
      String status;
      String? reason;
      if (current == null) {
        status = 'new';
      } else if (current.deleted) {
        status = 'conflict';
        reason = 'A deleted observation identity cannot be reused.';
      } else if (current.measurement.source !=
          item.provenance(document.namespace)) {
        status = 'conflict';
        reason = 'The observation identity belongs to another source.';
      } else {
        final next = item.measurement(
          document.namespace,
          current.measurement.contentVersion,
        );
        status =
            canonicalJson(next.toJson()) ==
                canonicalJson(current.measurement.toJson())
            ? 'unchanged'
            : 'changed';
      }
      measurements.add(_Entry(item, current, status, reason));
    }
    return _Plan(
      document,
      sessions,
      measurements,
      (stored.keys.toList()..sort()),
      [
        for (final r in mass.values)
          if (!r.deleted &&
              (r.measurement.source?.startsWith(prefix) ?? false) &&
              !listed.contains(r.measurement.id))
            r.measurement.id,
      ]..sort(),
    );
  }
}

const importedSeriesOrdering =
    'calendar-date, then recorded instant where known';

/// The selected imported points plus what was excluded and why.
typedef ImportedSeriesSelection = ({
  List<Map<String, Object?>> series,
  int pointCount,
  int dateOnlyExcluded,
});

/// Pure selection shared by `import series` and the opt-in imported block of
/// native series. Every filter is an exact match; a null exerciseId never
/// matches a requested exerciseId or family member. Instant bounds apply only
/// to timestamped sessions: a date-only session cannot be placed against an
/// instant without inventing a time and timezone, so it is excluded and
/// counted instead.
ImportedSeriesSelection selectImportedSeries(
  List<ImportedSessionRecord> records, {
  String? metric,
  required Set<String> roles,
  String? exerciseId,
  String? exerciseName,
  String? implementationId,
  String? equipment,
  Set<String>? members,
  String? fromDate,
  String? untilDate,
  DateTime? fromInstant,
  DateTime? untilInstant,
  int maxPoints = 10000,
}) {
  final contexts = <String, Map<String, Object?>>{};
  final points = <String, List<_Point>>{};
  var count = 0;
  var dateOnlyExcluded = 0;
  final instantBounds = fromInstant != null || untilInstant != null;
  for (final record in [...records]..sort(_order)) {
    final session = record.session;
    if (fromDate != null && session.date.compareTo(fromDate) < 0) continue;
    if (untilDate != null && session.date.compareTo(untilDate) >= 0) continue;
    if (instantBounds) {
      final started = session.startedAt;
      if (started == null) {
        dateOnlyExcluded++;
        continue;
      }
      if (fromInstant != null && started.isBefore(fromInstant)) continue;
      if (untilInstant != null && !started.isBefore(untilInstant)) continue;
    }
    for (final exercise in session.exercises) {
      if (exerciseId != null && exercise.exerciseId != exerciseId) continue;
      if (exerciseName != null && exercise.name != exerciseName) continue;
      if (implementationId != null &&
          exercise.implementationId != implementationId)
        continue;
      if (equipment != null && exercise.equipment != equipment) continue;
      if (members != null && !members.contains(exercise.exerciseId)) continue;
      for (final set in exercise.sets) {
        if (!roles.contains(set.role)) continue;
        for (final entry in set.actuals.entries) {
          if (metric != null && entry.key != metric) continue;
          final value = entry.value;
          final context = {
            'namespace': record.namespace,
            'exerciseId': exercise.exerciseId,
            if (exercise.exerciseId == null) 'exerciseName': exercise.name,
            'implementationId': exercise.implementationId,
            'equipment': exercise.equipment,
            'convention': exercise.convention?.toJson(),
            'role': set.role,
            'metric': entry.key,
            'unit': value.enteredUnit.name,
          };
          final key = canonicalJson(context);
          contexts[key] = context;
          if (++count > maxPoints)
            invalid('Imported series selects more than $maxPoints points.');
          (points[key] ??= []).add(_Point(record, exercise, set, value));
        }
      }
    }
  }
  final keys = contexts.keys.toList()..sort();
  return (
    series: [
      for (final key in keys)
        {
          'context': contexts[key],
          'points': [
            for (final p in points[key]!..sort((a, b) => a.compareTo(b)))
              p.toJson(),
          ],
        },
    ],
    pointCount: count,
    dateOnlyExcluded: dateOnlyExcluded,
  );
}

int _order(ImportedSessionRecord a, ImportedSessionRecord b) {
  final ns = a.namespace.compareTo(b.namespace);
  if (ns != 0) return ns;
  final date = a.session.date.compareTo(b.session.date);
  if (date != 0) return date;
  final at = a.session.startedAt, bt = b.session.startedAt;
  if (at != null && bt != null && at != bt) return at.compareTo(bt);
  if ((at == null) != (bt == null)) return at == null ? -1 : 1;
  return a.sourceId.compareTo(b.sourceId);
}

final class _Point {
  _Point(this.record, this.exercise, this.set, this.value);
  final ImportedSessionRecord record;
  final ImportedExercise exercise;
  final ImportedSet set;
  final Quantity value;
  int compareTo(_Point other) {
    final session = _order(record, other.record);
    if (session != 0) return session;
    final order = exercise.order.compareTo(other.exercise.order);
    return order != 0 ? order : set.ordinal.compareTo(other.set.ordinal);
  }

  Map<String, Object?> toJson() => {
    'sessionSourceId': record.sourceId,
    'exerciseSourceId': exercise.sourceId,
    'setSourceId': set.sourceId,
    'date': record.session.date,
    'datePrecision': record.session.dateOnly ? 'date' : 'instant',
    'startedAt': record.session.startedAtText,
    'ordinal': set.ordinal,
    'status': set.status,
    'value': value.toJson(),
    'contentVersion': record.contentVersion,
  };
}

final class _Entry<T, C> {
  _Entry(this.item, this.current, this.status, [this.reason]);
  final T item;
  final C? current;
  final String status;
  final String? reason;
  int? written;
}

final class _Plan {
  _Plan(
    this.document,
    this.sessions,
    this.measurements,
    this.absentSessions,
    this.absentMeasurements,
  );
  final HistoryImportDocument document;
  final List<_Entry<ImportedSession, ImportedSessionRecord>> sessions;
  final List<_Entry<ImportedMeasurement, BodyMassRecord>> measurements;
  final List<String> absentSessions, absentMeasurements;

  int get changedCount =>
      sessions.where((s) => s.status == 'changed').length +
      measurements.where((m) => m.status == 'changed').length;

  Map<String, int> _counts(Iterable<String> statuses) {
    final counts = <String, int>{
      'new': 0,
      'unchanged': 0,
      'changed': 0,
      'conflict': 0,
    };
    for (final s in statuses) counts[s] = counts[s]! + 1;
    return counts;
  }

  Map<String, Object?> report(bool applied) => {
    'policy': historyImportFormat,
    'applied': applied,
    'source': document.source,
    'counts': {
      'sessions': _counts(sessions.map((s) => s.status)),
      'measurements': _counts(measurements.map((m) => m.status)),
    },
    'sessions': [
      for (final s in sessions)
        {
          'sourceId': s.item.sourceId,
          'status': s.status,
          'contentVersion': s.written ?? s.current?.contentVersion,
        },
    ],
    'measurements': [
      for (final m in measurements)
        {
          'id': m.item.id,
          'sourceId': m.item.sourceId,
          'status': m.status,
          if (m.reason != null) 'reason': m.reason,
          'contentVersion': m.written ?? m.current?.measurement.contentVersion,
        },
    ],
    // Records missing from this export are retained, never silently deleted.
    'absentSessions': absentSessions,
    'absentMeasurements': absentMeasurements,
    'unknowns': document.unknowns,
  };
}

/// Opt-in imported block for native series (policy bodytmi-imported-series/2).
/// It never merges into native contexts: imported history has no run,
/// template, slot or setup, so a filter on any of those excludes it, and
/// warmup selection follows the native flags while unknown roles stay
/// visible by default. The combined point budget is shared with native series.
Map<String, Object?> importedSeriesBlock(
  List<ImportedSessionRecord> records, {
  Map<String, Object?> context = const {},
  String? metric,
  DateTime? from,
  DateTime? until,
  bool includeWarmups = false,
  List<String>? roles,
  FamilyRevision? family,
  String? namespace,
  int nativePointCount = 0,
}) {
  if (namespace != null) identifier({'namespace': namespace}, 'namespace');
  final selectedRoles = roles != null
      ? roles.toSet()
      : includeWarmups
      ? historyImportRoles
      : historyImportRoles.difference({'warmup'});
  final unrepresented = [
    for (final key in ['runId', 'templateId', 'slotId', 'setupNote'])
      if (context.containsKey(key)) key,
  ];
  final policy = <String, Object?>{
    'id': 'bodytmi-imported-series/2',
    'origin': 'imported',
    'namespace': namespace,
    'roles': selectedRoles.toList()..sort(),
    'ordering': importedSeriesOrdering,
  };
  if (unrepresented.isNotEmpty)
    return {
      'policy': policy,
      'pointCount': 0,
      'excluded': {
        'all': true,
        'reason':
            'Imported history has no ${unrepresented.join('/')} context to match.',
      },
      'series': const <Object?>[],
    };
  String? text(String key) {
    final value = context[key];
    if (value != null && value is! String)
      invalid('Series context $key must be a string.');
    return value as String?;
  }

  final role = text('role');
  final selection = selectImportedSeries(
    [
      for (final r in records)
        if (namespace == null || r.namespace == namespace) r,
    ],
    metric: metric,
    roles: role == null ? selectedRoles : selectedRoles.intersection({role}),
    exerciseId: text('exercise'),
    implementationId: text('implementation'),
    equipment: text('equipment'),
    members: family?.family.exercises.toSet(),
    fromInstant: from,
    untilInstant: until,
    maxPoints: 10000 - nativePointCount,
  );
  return {
    'policy': policy,
    'pointCount': selection.pointCount,
    'excluded': {
      'all': false,
      'dateOnlySessions': selection.dateOnlyExcluded,
      if (selection.dateOnlyExcluded > 0)
        'reason':
            'Date-only imported sessions cannot be compared with instant bounds.',
    },
    'series': selection.series,
  };
}
