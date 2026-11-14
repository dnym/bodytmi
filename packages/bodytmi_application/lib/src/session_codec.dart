import 'package:bodytmi_core/bodytmi_core.dart';
import 'training_service.dart';
import 'canonical_json.dart';
import 'derived_plan_session.dart';

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

Map<String, BodyMassOverride?> bodyMassRebindingsFromJson(Object? input) => {
  for (final e in jsonObject(input, 'bodyMassOverrides').entries)
    identifier({'id': e.key}, 'id'): e.value == null
        ? null
        : BodyMassOverride.fromJson(e.value),
};

Map<String, LoadInstanceReference> loadInstancesFromJson(Object? input) => {
  for (final e in jsonObject(
    input ?? <String, Object?>{},
    'loadInstances',
  ).entries)
    identifier({'id': e.key}, 'id'): LoadInstanceReference.fromJson(e.value),
};

Map<String, LoadConvention> loadConventionsFromJson(Object? input) => {
  for (final e in jsonObject(
    input ?? <String, Object?>{},
    'loadConventions',
  ).entries)
    identifier({'id': e.key}, 'id'): LoadConvention.fromJson(e.value),
};

Map<String, String> loadBindingsFromJson(Object? input) => {
  for (final e in jsonObject(
    input ?? <String, Object?>{},
    'loadBindings',
  ).entries)
    identifier({'id': e.key}, 'id'): identifier({
      'instanceId': e.value,
    }, 'instanceId'),
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
    'loadInputs',
    'initialBodyMassOverrides',
    'derivedPlanInput',
    'prescriptionOverrides',
  });
  if (json['schemaVersion'] != 1)
    invalid('Unsupported session schema version.');
  if (json.containsKey('initialBodyMassOverrides') &&
      json['initialBodyMassOverrides'] == null)
    invalid('Initial body-mass overrides must be an object.');
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
  final derivedInput = json['derivedPlanInput'] == null
      ? null
      : DerivedPlanInput.fromJson(json['derivedPlanInput']);
  final mappedTargets = <String, Set<String>>{};
  if (derivedInput != null) {
    final plan = DerivedWorkoutPlan.fromJson(derivedInput.snapshot['plan']);
    for (final binding in plan.bindings) {
      mappedTargets
          .putIfAbsent(binding['occurrenceId']! as String, () => <String>{})
          .add(binding['metric']! as String);
    }
  }
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
      'manualTargets',
      'carriedTargets',
      'status',
      'actuals',
      'timing',
      'observations',
      'loadArrangement',
      'objectives',
      'contentVersion',
    });
    final expected = baseline.sets[i];
    if (row['id'] != expected.id ||
        row['slot'] != expected.slotId ||
        row['role'] != expected.role ||
        row['ordinal'] != expected.ordinal)
      invalid('Set identity does not match the activity plan.');
    final objectives = row.containsKey('objectives')
        ? numericObjectivesFromJson(row['objectives'])
        : <String, NumericObjective>{};
    if (canonicalJson(numericObjectivesToJson(objectives)) !=
        canonicalJson(expected.objectivesJson))
      invalid('Set objectives do not match the pinned activity.');
    final maxEffortMetrics = objectives.entries
        .where((e) => e.value.mode == 'maxEffort')
        .map((e) => e.key)
        .toSet();
    final criteria = Map<String, NumericObjective>.fromEntries(
      objectives.entries.where((e) => e.value.mode != 'maxEffort'),
    );
    final suggested = metricsFromJson(row['suggested']);
    final added = suggested.keys.toSet().difference(
      expected.suggested.keys.toSet(),
    );
    if (added.any((metric) {
          final criterion = expected.criteria[metric];
          return criterion == null ||
              criterion.mode == 'observe' ||
              suggested[metric]!.dimension != criterion.unit.dimension ||
              !(mappedTargets[expected.id]?.contains(metric) ?? false);
        }) ||
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
    final manualTargets = <String>{};
    if (row.containsKey('manualTargets')) {
      for (final value in jsonList(row, 'manualTargets')) {
        if (value is! String || !manualTargets.add(value)) {
          invalid('Invalid manual target metrics.');
        }
      }
      if (manualTargets.isEmpty) invalid('Manual targets cannot be empty.');
      if (_positive(row, 'contentVersion') < 2) {
        invalid('Manual targets require a later set version.');
      }
    }
    final carriedTargets = <String, CarriedTargetSource>{};
    if (row.containsKey('carriedTargets')) {
      final entries = jsonObject(row['carriedTargets'], 'carried targets');
      if (entries.isEmpty) invalid('Carried targets cannot be empty.');
      for (final entry in entries.entries) {
        final source = jsonObject(entry.value, 'carried target source');
        checkKeys(source, {'setId', 'contentVersion'});
        carriedTargets[entry.key] = CarriedTargetSource(
          requiredString(source, 'setId'),
          _positive(source, 'contentVersion'),
        );
      }
    }
    sets.add(
      TrainingSet(
        id: expected.id,
        slotId: expected.slotId,
        role: expected.role,
        ordinal: expected.ordinal,
        suggested: suggested,
        sources: sources,
        manualTargets: manualTargets,
        carriedTargets: carriedTargets,
        maxEffortMetrics: maxEffortMetrics,
        criteria: criteria,
        actuals: actuals,
        timing: row['timing'] == null
            ? null
            : TimedResult.fromJson(row['timing']),
        observations: row.containsKey('observations')
            ? SetObservations.fromJson(row['observations'])
            : null,
        loadArrangement: row['loadArrangement'] == null
            ? null
            : LoadArrangement.fromJson(row['loadArrangement']),
        status: setStatus,
        contentVersion: _positive(row, 'contentVersion'),
      ),
    );
  }
  final setIndices = {for (var i = 0; i < sets.length; i++) sets[i].id: i};
  for (var i = 0; i < sets.length; i++) {
    final set = sets[i];
    for (final entry in set.carriedTargets.entries) {
      final sourceIndex = setIndices[entry.value.setId];
      if (sourceIndex == null || sourceIndex >= i)
        invalid('Invalid carried target source.');
      final source = sets[sourceIndex];
      if (source.slotId != set.slotId ||
          source.role != set.role ||
          source.contentVersion < entry.value.contentVersion) {
        invalid('Carried target source context or version is inconsistent.');
      }
      if (source.contentVersion == entry.value.contentVersion &&
          (source.status != SetStatus.completed ||
              source.actuals[entry.key] == null ||
              canonicalJson(source.actuals[entry.key]!.toJson()) !=
                  canonicalJson(set.suggested[entry.key]!.toJson()))) {
        invalid('Carried target does not match its source actual.');
      }
    }
  }
  if (status == SessionStatus.finalized &&
      sets.any((s) => s.status == SetStatus.planned))
    invalid('A finalized session cannot contain planned sets.');
  final prescriptionOverrides = json['prescriptionOverrides'] == null
      ? const <PrescriptionOverrideRecord>[]
      : [
          for (final item in jsonList(json, 'prescriptionOverrides'))
            PrescriptionOverrideRecord.fromJson(item),
        ];
  if (json.containsKey('prescriptionOverrides') &&
      prescriptionOverrides.isEmpty)
    invalid('Prescription override records cannot be empty.');
  if (json.containsKey('loadInputs') &&
      jsonObject(json['loadInputs'], 'loadInputs').isEmpty)
    invalid('Session load inputs cannot be empty.');
  if (prescriptionOverrides.isNotEmpty) {
    if (derivedInput != null)
      invalid(
        'Sessions cannot combine derived plans and prescription overrides.',
      );
    final recomputed =
        applyPrescriptionOverrides(revision.definition, baseline.sets, [
          for (final record in prescriptionOverrides)
            ScopedProgramOverride(record.path, record.override),
        ]).records;
    if (canonicalJson([for (final record in recomputed) record.toJson()]) !=
        canonicalJson([
          for (final record in prescriptionOverrides) record.toJson(),
        ]))
      invalid(
        'Prescription override provenance does not match the pinned prescription.',
      );
    final overriddenAfter = <String, Map<String, Quantity>>{};
    for (final record in prescriptionOverrides) {
      for (final application in record.applied) {
        overriddenAfter.putIfAbsent(
          application.setId,
          () => {},
        )[record.metric] = application.after;
      }
    }
    for (final set in sets) {
      for (final entry
          in (overriddenAfter[set.id] ?? const <String, Quantity>{}).entries) {
        if (set.manualTargets.contains(entry.key) ||
            set.carriedTargets.containsKey(entry.key))
          continue;
        if (canonicalJson(set.suggested[entry.key]?.toJson()) !=
            canonicalJson(entry.value.toJson()))
          invalid(
            'Set suggestions do not match frozen prescription overrides.',
          );
      }
    }
  }
  final session = TrainingSession(
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
    loadInputs: {
      for (final e in jsonObject(
        json['loadInputs'] ?? <String, Object?>{},
        'loadInputs',
      ).entries)
        e.key: LoadInputSnapshot.fromJson(e.value),
    },
    initialBodyMassOverrides: json.containsKey('initialBodyMassOverrides')
        ? bodyMassOverridesFromJson(json['initialBodyMassOverrides'])
        : null,
    derivedPlanInput: derivedInput,
    prescriptionOverrides: prescriptionOverrides,
    status: status,
    finishedAt: finishedAt,
    contentVersion: _positive(json, 'contentVersion'),
  );
  validateDerivedPlanSession(session);
  return session;
}
