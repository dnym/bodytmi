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
    final contexts = <String, Map<String, Object?>>{};
    final points = <String, List<_Point>>{};
    var count = 0;
    for (final record in await list(namespace: namespace)) {
      final session = record.session;
      if (from != null && session.date.compareTo(from) < 0) continue;
      if (until != null && session.date.compareTo(until) >= 0) continue;
      for (final exercise in session.exercises) {
        if (exerciseId != null && exercise.exerciseId != exerciseId) continue;
        if (exerciseName != null && exercise.name != exerciseName) continue;
        for (final set in exercise.sets) {
          final value = set.actuals[metric];
          if (value == null || !selectedRoles.contains(set.role)) continue;
          final context = {
            'namespace': record.namespace,
            'exerciseId': exercise.exerciseId,
            if (exercise.exerciseId == null) 'exerciseName': exercise.name,
            'implementationId': exercise.implementationId,
            'equipment': exercise.equipment,
            'convention': exercise.convention?.toJson(),
            'role': set.role,
            'metric': metric,
            'unit': value.enteredUnit.name,
          };
          final key = canonicalJson(context);
          contexts[key] = context;
          if (++count > 10000)
            invalid('Imported series selects more than 10000 points.');
          (points[key] ??= []).add(_Point(record, exercise, set, value));
        }
      }
    }
    final keys = contexts.keys.toList()..sort();
    return {
      'policy': 'bodytmi-imported-series/1',
      'ordering': 'calendar-date, then recorded instant where known',
      'metric': metric,
      'roles': selectedRoles.toList()..sort(),
      'series': [
        for (final key in keys)
          {
            'context': contexts[key],
            'points': [
              for (final p in points[key]!..sort((a, b) => a.compareTo(b)))
                p.toJson(),
            ],
          },
      ],
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
