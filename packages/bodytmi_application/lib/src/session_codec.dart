import 'package:bodytmi_core/bodytmi_core.dart';
import 'training_service.dart';

int _positive(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int || value < 1) invalid('$key must be a positive integer.');
  return value;
}

Map<String, BodyMassOverride> bodyMassOverridesFromJson(Object? input) => {
  for (final e in jsonObject(
    input ?? <String, Object?>{},
    'bodyMassOverrides',
  ).entries)
    e.key: BodyMassOverride.fromJson(e.value),
};

TrainingSession sessionFromJson(Object? input) {
  final json = jsonObject(input, 'session');
  checkKeys(json, {
    'schemaVersion',
    'id',
    'revision',
    'startedAt',
    'finishedAt',
    'status',
    'contentVersion',
    'sets',
    'bodyMassInputs',
  });
  if (json['schemaVersion'] != 1)
    invalid('Unsupported session schema version.');
  final id = identifier(json, 'id');
  final revision = WorkoutRevision.fromJson(json['revision']);
  final startedAt = parseInstant(json['startedAt'], 'startedAt');
  final status = switch (json['status']) {
    'active' => SessionStatus.active,
    'finalized' => SessionStatus.finalized,
    _ => invalid('Invalid session status.'),
  };
  final finishedAt = json['finishedAt'] == null
      ? null
      : parseInstant(json['finishedAt'], 'finishedAt');
  if ((status == SessionStatus.finalized) != (finishedAt != null) ||
      (finishedAt?.isBefore(startedAt) ?? false))
    invalid('Inconsistent session finish state/time.');
  final baseline = const TrainingService().start(
    sessionId: id,
    revision: revision,
    startedAt: startedAt,
  );
  final items = jsonList(json, 'sets');
  if (items.length != baseline.sets.length)
    invalid('Session efforts do not match its prescription.');
  final sets = <TrainingSet>[];
  for (var i = 0; i < items.length; i++) {
    final row = jsonObject(items[i], 'set');
    checkKeys(row, {
      'id',
      'slot',
      'role',
      'ordinal',
      'suggested',
      'sources',
      'status',
      'actuals',
      'timing',
      'observations',
      'contentVersion',
    });
    final expected = baseline.sets[i];
    if (row['id'] != expected.id ||
        row['slot'] != expected.slotId ||
        row['role'] != expected.role ||
        row['ordinal'] != expected.ordinal)
      invalid('Set identity does not match the activity plan.');
    final suggested = metricsFromJson(row['suggested']);
    if (suggested.keys
            .toSet()
            .difference(expected.suggested.keys.toSet())
            .isNotEmpty ||
        expected.suggested.keys.any(
          (k) => suggested[k]?.dimension != expected.suggested[k]!.dimension,
        ))
      invalid('Set suggestions have incompatible metrics.');
    final actuals = metricsFromJson(row['actuals']);
    final setStatus = switch (row['status']) {
      'planned' => SetStatus.planned,
      'completed' => SetStatus.completed,
      'skipped' => SetStatus.skipped,
      _ => invalid('Invalid set status.'),
    };
    if (setStatus == SetStatus.completed) {
      expected.complete(actuals);
    } else if (actuals.isNotEmpty) {
      invalid('Uncompleted sets cannot contain completed actuals.');
    }
    if (row['timing'] != null) {
      final timing = TimedResult.fromJson(row['timing']);
      if (setStatus != SetStatus.completed ||
          actuals[timing.metric]?.dimension != Dimension.duration)
        invalid('Timing provenance requires a completed duration result.');
      if (timing.mode == 'timer' &&
          actuals[timing.metric]!.compareTo(
                Quantity(timing.elapsedMilliseconds.toString(), 'ms'),
              ) !=
              0)
        invalid('Timed duration does not match clock provenance.');
    }
    final sources = <String, HistorySource>{};
    for (final entry in jsonObject(row['sources'], 'sources').entries) {
      if (!suggested.containsKey(entry.key))
        invalid('Source names an unknown metric.');
      final source = jsonObject(entry.value, 'history source');
      checkKeys(source, {'sessionId', 'setId', 'contentVersion'});
      sources[entry.key] = HistorySource(
        identifier(source, 'sessionId'),
        requiredString(source, 'setId'),
        _positive(source, 'contentVersion'),
      );
    }
    sets.add(
      TrainingSet(
        id: expected.id,
        slotId: expected.slotId,
        role: expected.role,
        ordinal: expected.ordinal,
        suggested: suggested,
        sources: sources,
        actuals: actuals,
        timing: row['timing'] == null
            ? null
            : TimedResult.fromJson(row['timing']),
        observations: row.containsKey('observations')
            ? SetObservations.fromJson(row['observations'])
            : null,
        status: setStatus,
        contentVersion: _positive(row, 'contentVersion'),
      ),
    );
  }
  if (status == SessionStatus.finalized &&
      sets.any((s) => s.status == SetStatus.planned))
    invalid('A finalized session cannot contain planned sets.');
  return TrainingSession(
    id: id,
    revision: revision,
    startedAt: startedAt,
    sets: sets,
    bodyMassInputs: {
      for (final e in jsonObject(
        json['bodyMassInputs'] ?? <String, Object?>{},
        'bodyMassInputs',
      ).entries)
        e.key: BodyMassInputSnapshot.fromJson(e.value),
    },
    status: status,
    finishedAt: finishedAt,
    contentVersion: _positive(json, 'contentVersion'),
  );
}
