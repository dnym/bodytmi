import 'dart:convert';

import 'body_mass.dart';
import 'errors.dart';
import 'instant.dart';
import 'load_convention.dart';
import 'quantity.dart';
import 'set_observations.dart';

/// The limited source-neutral training-history interchange. It carries
/// observed past sessions and raw body-mass observations only: it never
/// encodes workout revisions, progression state, program runs, timing records
/// or setups, and it does not claim full-domain fidelity.
const historyImportFormat = 'bodytmi-history-import/1';

/// Concepts the interchange cannot represent. Imports report these so nothing
/// pretends imported history has pinned prescriptions or progression lineage.
const historyImportNotRepresented = [
  'workout-revision',
  'program-run',
  'progression-state',
  'timing-records',
  'setup-notes',
  'equipment-instance',
];

const historyImportRoles = {'work', 'warmup', 'backoff', 'drop', 'unknown'};
const historyImportStatuses = {
  'completed',
  'skipped',
  'interrupted',
  'unknown',
};

const _maxSessions = 10000;
const _maxExercises = 100;
const _maxSets = 100;
const _maxTotalSets = 100000;
const _maxMeasurements = 10000;
const _maxRawBytes = 16 * 1024;

String sourceIdentifier(Map<String, Object?> json, String key) {
  final value = requiredString(json, key);
  if (value.length > 256 || RegExp(r'[\x00-\x1f\x7f]').hasMatch(value))
    invalid('$key must be at most 256 characters without control characters.');
  return value;
}

String? _optionalText(Map<String, Object?> json, String key, int max) {
  if (!json.containsKey(key)) return null;
  final value = requiredString(json, key);
  if (value.length > max) invalid('$key must be at most $max characters.');
  return value;
}

/// Validates a local calendar date. Date-only history stays date-only: no
/// midnight, timezone or ordering precision is invented for it.
String calendarDate(Object? input, String label) {
  if (input is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(input))
    invalid('$label must be a YYYY-MM-DD calendar date.');
  final parts = input.split('-').map(int.parse).toList();
  final date = DateTime.utc(parts[0], parts[1], parts[2]);
  if (date.year != parts[0] || date.month != parts[1] || date.day != parts[2])
    invalid('Invalid calendar date in $label.');
  return input;
}

/// Source fields whose meaning is unresolved are preserved verbatim. Numbers
/// must be integers: fractional source values travel as strings so that no
/// binary floating-point rendering becomes part of an import identity.
Map<String, Object?>? _raw(Map<String, Object?> json) {
  if (!json.containsKey('raw')) return null;
  final raw = jsonObject(json['raw'], 'raw');
  void check(Object? value, int depth) {
    if (depth > 16) invalid('raw nesting is too deep.');
    switch (value) {
      case null || bool() || String() || int():
        return;
      case List<Object?>():
        for (final item in value) check(item, depth + 1);
      case Map<String, Object?>():
        for (final item in value.values) check(item, depth + 1);
      default:
        invalid('raw numbers must be integers; encode fractions as strings.');
    }
  }

  check(raw, 0);
  if (utf8.encode(jsonEncode(raw)).length > _maxRawBytes)
    invalid('raw must encode to at most $_maxRawBytes bytes.');
  return raw;
}

final class ImportedSet {
  ImportedSet._(
    this.sourceId,
    this.ordinal,
    this.role,
    this.status,
    this.actuals,
    this.targets,
    this.observations,
    this.raw,
  );

  factory ImportedSet.fromJson(Object? input) {
    final j = jsonObject(input, 'imported set');
    checkKeys(j, {
      'sourceId',
      'ordinal',
      'role',
      'status',
      'actuals',
      'targets',
      'observations',
      'raw',
    });
    final ordinal = j['ordinal'];
    if (ordinal is! int || ordinal < 1 || ordinal > _maxSets)
      invalid('Imported set ordinal must be an integer from 1 to $_maxSets.');
    final role = requiredString(j, 'role');
    if (!historyImportRoles.contains(role))
      invalid('Imported set role must be ${historyImportRoles.join('/')}.');
    final status = requiredString(j, 'status');
    if (!historyImportStatuses.contains(status))
      invalid(
        'Imported set status must be ${historyImportStatuses.join('/')}.',
      );
    final actuals = j.containsKey('actuals')
        ? metricsFromJson(j['actuals'])
        : const <String, Quantity>{};
    final targets = j.containsKey('targets')
        ? metricsFromJson(j['targets'])
        : const <String, Quantity>{};
    if (status == 'completed' && actuals.isEmpty)
      invalid('A completed imported set needs explicit actuals.');
    if (status == 'skipped' && actuals.isNotEmpty)
      invalid('A skipped imported set cannot carry actuals.');
    for (final entry in targets.entries) {
      final actual = actuals[entry.key];
      if (actual != null && actual.dimension != entry.value.dimension)
        invalid('Imported target ${entry.key} has a different dimension.');
    }
    SetObservations? observations;
    if (j.containsKey('observations')) {
      observations = SetObservations.fromJson(j['observations']);
      if (observations.isEmpty) invalid('observations cannot be empty.');
      if ((observations.rpe != null || observations.rir != null) &&
          status != 'completed' &&
          status != 'interrupted')
        invalid('RPE and RIR need completed or interrupted imported work.');
      if (observations.interrupted && status != 'interrupted')
        invalid('An interrupted termination needs status interrupted.');
    }
    return ImportedSet._(
      sourceIdentifier(j, 'sourceId'),
      ordinal,
      role,
      status,
      actuals,
      targets,
      observations,
      _raw(j),
    );
  }

  final String sourceId, role, status;
  final int ordinal;
  final Metrics actuals, targets;
  final SetObservations? observations;
  final Map<String, Object?>? raw;

  Map<String, Object?> toJson() => {
    'sourceId': sourceId,
    'ordinal': ordinal,
    'role': role,
    'status': status,
    if (actuals.isNotEmpty) 'actuals': metricsToJson(actuals),
    if (targets.isNotEmpty) 'targets': metricsToJson(targets),
    if (observations != null) 'observations': observations!.toJson(),
    if (raw != null) 'raw': raw,
  };
}

final class ImportedExercise {
  ImportedExercise._(
    this.sourceId,
    this.order,
    this.name,
    this.exerciseId,
    this.implementationId,
    this.equipment,
    this.convention,
    this.notes,
    this.raw,
    List<ImportedSet> sets,
  ) : sets = List.unmodifiable(sets);

  factory ImportedExercise.fromJson(Object? input) {
    final j = jsonObject(input, 'imported exercise');
    checkKeys(j, {
      'sourceId',
      'order',
      'name',
      'exerciseId',
      'implementationId',
      'equipment',
      'convention',
      'notes',
      'raw',
      'sets',
    });
    final order = j['order'];
    if (order is! int || order < 1 || order > _maxExercises)
      invalid(
        'Imported exercise order must be an integer from 1 to $_maxExercises.',
      );
    final name = requiredString(j, 'name');
    if (name.length > 200)
      invalid('Imported exercise name must be at most 200 characters.');
    final setsJson = jsonList(j, 'sets');
    if (setsJson.isEmpty || setsJson.length > _maxSets)
      invalid('An imported exercise needs 1–$_maxSets sets.');
    final sets = [for (final s in setsJson) ImportedSet.fromJson(s)];
    final ordinals = <int>{};
    final ids = <String>{};
    for (final set in sets) {
      if (!ordinals.add(set.ordinal))
        invalid('Imported set ordinals must be distinct within an exercise.');
      if (!ids.add(set.sourceId))
        invalid('Imported set sourceIds must be distinct within an exercise.');
    }
    sets.sort((a, b) => a.ordinal.compareTo(b.ordinal));
    final implementationId = j.containsKey('implementationId')
        ? identifier(j, 'implementationId')
        : null;
    final exerciseId = j.containsKey('exerciseId')
        ? identifier(j, 'exerciseId')
        : null;
    if (implementationId != null && exerciseId == null)
      invalid('An imported implementationId needs an explicit exerciseId.');
    return ImportedExercise._(
      sourceIdentifier(j, 'sourceId'),
      order,
      name,
      exerciseId,
      implementationId,
      j.containsKey('equipment') ? identifier(j, 'equipment') : null,
      j.containsKey('convention')
          ? LoadConvention.fromJson(j['convention'])
          : null,
      _optionalText(j, 'notes', 4000),
      _raw(j),
      sets,
    );
  }

  final String sourceId, name;
  final int order;
  final String? exerciseId, implementationId, equipment, notes;
  final LoadConvention? convention;
  final Map<String, Object?>? raw;
  final List<ImportedSet> sets;

  /// Mass entered without a declared convention is retained as entered, and
  /// its gross/net/per-implement meaning is reported as unknown.
  bool get hasMassWithoutConvention =>
      convention == null &&
      sets.any(
        (s) => [
          ...s.actuals.values,
          ...s.targets.values,
        ].any((q) => q.dimension == Dimension.mass),
      );

  Map<String, Object?> toJson() => {
    'sourceId': sourceId,
    'order': order,
    'name': name,
    if (exerciseId != null) 'exerciseId': exerciseId,
    if (implementationId != null) 'implementationId': implementationId,
    if (equipment != null) 'equipment': equipment,
    if (convention != null) 'convention': convention!.toJson(),
    if (notes != null) 'notes': notes,
    if (raw != null) 'raw': raw,
    'sets': [for (final s in sets) s.toJson()],
  };
}

final class ImportedSession {
  ImportedSession._(
    this.sourceId,
    this.date,
    this.startedAtText,
    this.startedAt,
    this.finishedAtText,
    this.timezone,
    this.name,
    this.notes,
    this.raw,
    List<ImportedExercise> exercises,
  ) : exercises = List.unmodifiable(exercises);

  factory ImportedSession.fromJson(Object? input) {
    final j = jsonObject(input, 'imported session');
    checkKeys(j, {
      'sourceId',
      'date',
      'startedAt',
      'finishedAt',
      'timezone',
      'name',
      'notes',
      'raw',
      'exercises',
    });
    if (j.containsKey('date') == j.containsKey('startedAt'))
      invalid('An imported session needs exactly one of date or startedAt.');
    String date;
    String? startedText, finishedText;
    DateTime? started;
    if (j.containsKey('date')) {
      date = calendarDate(j['date'], 'date');
      if (j.containsKey('finishedAt'))
        invalid('A date-only imported session cannot have finishedAt.');
    } else {
      startedText = requiredString(j, 'startedAt');
      started = parseInstant(startedText, 'startedAt');
      // The calendar date in the recorded offset, never this process's zone.
      date = startedText.substring(0, 10);
      if (j.containsKey('finishedAt')) {
        finishedText = requiredString(j, 'finishedAt');
        if (parseInstant(finishedText, 'finishedAt').isBefore(started))
          invalid('Imported finishedAt cannot precede startedAt.');
      }
    }
    final exercisesJson = jsonList(j, 'exercises');
    if (exercisesJson.isEmpty || exercisesJson.length > _maxExercises)
      invalid('An imported session needs 1–$_maxExercises exercises.');
    final exercises = [
      for (final e in exercisesJson) ImportedExercise.fromJson(e),
    ];
    final orders = <int>{};
    final ids = <String>{};
    for (final exercise in exercises) {
      if (!orders.add(exercise.order))
        invalid('Imported exercise orders must be distinct within a session.');
      if (!ids.add(exercise.sourceId))
        invalid(
          'Imported exercise sourceIds must be distinct within a session.',
        );
    }
    exercises.sort((a, b) => a.order.compareTo(b.order));
    return ImportedSession._(
      sourceIdentifier(j, 'sourceId'),
      date,
      startedText,
      started,
      finishedText,
      _optionalText(j, 'timezone', 64),
      _optionalText(j, 'name', 200),
      _optionalText(j, 'notes', 4000),
      _raw(j),
      exercises,
    );
  }

  final String sourceId, date;
  final String? startedAtText, finishedAtText, timezone, name, notes;
  final DateTime? startedAt;
  final Map<String, Object?>? raw;
  final List<ImportedExercise> exercises;
  bool get dateOnly => startedAt == null;
  int get setCount => exercises.fold(0, (n, e) => n + e.sets.length);

  Map<String, Object?> toJson() => {
    'sourceId': sourceId,
    if (startedAtText == null) 'date': date,
    if (startedAtText != null) 'startedAt': startedAtText,
    if (finishedAtText != null) 'finishedAt': finishedAtText,
    if (timezone != null) 'timezone': timezone,
    if (name != null) 'name': name,
    if (notes != null) 'notes': notes,
    if (raw != null) 'raw': raw,
    'exercises': [for (final e in exercises) e.toJson()],
  };
}

/// A raw body-mass observation with an explicit BodyTMI identity and context.
/// Unclassified mass never joins a health or clothed-training series by default.
final class ImportedMeasurement {
  ImportedMeasurement._(
    this.id,
    this.sourceId,
    this.context,
    this.observedAt,
    this.mass,
    this.notes,
  );

  factory ImportedMeasurement.fromJson(Object? input) {
    final j = jsonObject(input, 'imported measurement');
    checkKeys(j, {'id', 'sourceId', 'context', 'observedAt', 'mass', 'notes'});
    final sourceId = sourceIdentifier(j, 'sourceId');
    if (sourceId.length > 160)
      invalid(
        'An imported measurement sourceId must be at most 160 characters.',
      );
    final observedAt = requiredString(j, 'observedAt');
    parseInstant(observedAt, 'observedAt');
    return ImportedMeasurement._(
      identifier(j, 'id'),
      sourceId,
      identifier(j, 'context'),
      observedAt,
      Quantity.fromJson(j['mass']),
      _optionalText(j, 'notes', 4000),
    );
  }

  final String id, sourceId, context, observedAt;
  final Quantity mass;
  final String? notes;

  /// The provenance stored on the observation, binding it to this source.
  String provenance(String namespace) =>
      'bodytmi-history-import:$namespace:$sourceId';

  BodyMassMeasurement measurement(String namespace, int contentVersion) =>
      BodyMassMeasurement.fromJson({
        'id': id,
        'context': context,
        'observedAt': observedAt,
        'mass': mass.toJson(),
        'contentVersion': contentVersion,
        'source': provenance(namespace),
        if (notes != null) 'notes': notes,
      });

  Map<String, Object?> toJson() => {
    'id': id,
    'sourceId': sourceId,
    'context': context,
    'observedAt': observedAt,
    'mass': mass.toJson(),
    if (notes != null) 'notes': notes,
  };
}

final class HistoryImportDocument {
  HistoryImportDocument._(
    this.namespace,
    this.app,
    this.version,
    this.exportedAt,
    List<ImportedSession> sessions,
    List<ImportedMeasurement> measurements,
  ) : sessions = List.unmodifiable(sessions),
      measurements = List.unmodifiable(measurements);

  factory HistoryImportDocument.fromJson(Object? input) {
    final j = jsonObject(input, 'history import');
    checkKeys(j, {'format', 'source', 'sessions', 'measurements'});
    if (j['format'] != historyImportFormat)
      invalid(
        'Unsupported history import format; expected $historyImportFormat.',
      );
    final source = jsonObject(j['source'], 'source');
    checkKeys(source, {'namespace', 'app', 'version', 'exportedAt'});
    final namespace = identifier(source, 'namespace');
    if (namespace.length > 64)
      invalid('source namespace must be at most 64 characters.');
    final exportedAt = source.containsKey('exportedAt')
        ? requiredString(source, 'exportedAt')
        : null;
    if (exportedAt != null) parseInstant(exportedAt, 'exportedAt');
    final sessionsJson = j.containsKey('sessions')
        ? jsonList(j, 'sessions')
        : const <Object?>[];
    final measurementsJson = j.containsKey('measurements')
        ? jsonList(j, 'measurements')
        : const <Object?>[];
    if (sessionsJson.length > _maxSessions)
      invalid('A history import holds at most $_maxSessions sessions.');
    if (measurementsJson.length > _maxMeasurements)
      invalid('A history import holds at most $_maxMeasurements measurements.');
    if (sessionsJson.isEmpty && measurementsJson.isEmpty)
      invalid('A history import needs sessions or measurements.');
    final sessions = [
      for (final s in sessionsJson) ImportedSession.fromJson(s),
    ];
    final sessionIds = <String>{};
    var total = 0;
    for (final session in sessions) {
      if (!sessionIds.add(session.sourceId))
        invalid('Duplicate imported session sourceId: ${session.sourceId}.');
      total += session.setCount;
    }
    if (total > _maxTotalSets)
      invalid('A history import holds at most $_maxTotalSets sets.');
    final measurements = [
      for (final m in measurementsJson) ImportedMeasurement.fromJson(m),
    ];
    final measurementIds = <String>{};
    final measurementSources = <String>{};
    for (final m in measurements) {
      if (!measurementIds.add(m.id))
        invalid('Duplicate imported measurement id: ${m.id}.');
      if (!measurementSources.add(m.sourceId))
        invalid('Duplicate imported measurement sourceId: ${m.sourceId}.');
    }
    sessions.sort((a, b) => a.sourceId.compareTo(b.sourceId));
    measurements.sort((a, b) => a.id.compareTo(b.id));
    return HistoryImportDocument._(
      namespace,
      _optionalText(source, 'app', 200),
      _optionalText(source, 'version', 200),
      exportedAt,
      sessions,
      measurements,
    );
  }

  final String namespace;
  final String? app, version, exportedAt;
  final List<ImportedSession> sessions;
  final List<ImportedMeasurement> measurements;

  Map<String, Object?> get source => {
    'namespace': namespace,
    if (app != null) 'app': app,
    if (version != null) 'version': version,
    if (exportedAt != null) 'exportedAt': exportedAt,
  };

  /// Counts of what the source left unknown, plus concepts never represented.
  Map<String, Object?> get unknowns {
    var dateOnly = 0, noFinish = 0, unmapped = 0, noConvention = 0;
    var unknownRole = 0, unknownStatus = 0, sets = 0;
    for (final session in sessions) {
      if (session.dateOnly) dateOnly++;
      if (!session.dateOnly && session.finishedAtText == null) noFinish++;
      for (final exercise in session.exercises) {
        if (exercise.exerciseId == null) unmapped++;
        if (exercise.hasMassWithoutConvention) noConvention++;
        for (final set in exercise.sets) {
          sets++;
          if (set.role == 'unknown') unknownRole++;
          if (set.status == 'unknown') unknownStatus++;
        }
      }
    }
    return {
      'sessions': sessions.length,
      'sets': sets,
      'measurements': measurements.length,
      'dateOnlySessions': dateOnly,
      'sessionsWithoutFinish': noFinish,
      'exercisesWithoutCatalogMapping': unmapped,
      'exercisesWithMassButNoConvention': noConvention,
      'setsWithUnknownRole': unknownRole,
      'setsWithUnknownStatus': unknownStatus,
      'notRepresented': historyImportNotRepresented,
    };
  }
}
