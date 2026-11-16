import 'dart:convert';
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

/// Parses a start request's `variants` as slot → lever → value (possibly
/// empty): explicit choices for variant levers no progression controls.
Map<String, Map<String, String>> variantSettingsFromJson(Object? input) => {
  for (final e in jsonObject(input ?? <String, Object?>{}, 'variants').entries)
    identifier({'slot': e.key}, 'slot'): categoricalSettingsFromJson(
      e.value,
      'variants.${e.key}',
    ),
};

/// Whether an existing session's frozen variant selections agree with a
/// retried start's explicit variant settings.
bool sameVariantRequest(
  TrainingSession existing,
  Map<String, Map<String, String>> requested,
) {
  for (final slot in requested.entries) {
    for (final setting in slot.value.entries) {
      for (final v in existing.revision.definition.variants) {
        final selected = existing.variantSelections[v.id];
        if (v.slotId == slot.key &&
            v.lever == setting.key &&
            selected != null &&
            selected != setting.value)
          return false;
      }
    }
  }
  return true;
}

/// Parses `{variantId: branchValue}` selections (possibly empty).
Map<String, String> variantSelectionsFromJson(Object? input) {
  final j = jsonObject(input ?? <String, Object?>{}, 'variantSelections');
  return {
    for (final key in (j.keys.toList()..sort()))
      identifier({'variant': key}, 'variant'): identifier(j, key),
  };
}

/// Decoded sessions by their exact JSON. A session snapshot is decoded and
/// fully validated (including re-expanding its prescription) every time it
/// is read, and the same snapshot recurs: in the sessions table and frozen
/// inside each progression decision of that exposure. Sessions are
/// immutable, so identical input can share one decoded value; failures are
/// never cached. Bounded so a long-lived process does not grow without end.
final _decodedSessions = <String, TrainingSession>{};
const _decodedSessionLimit = 256;

TrainingSession sessionFromJson(Object? input) {
  final String key;
  try {
    key = jsonEncode(input);
  } on JsonUnsupportedObjectError {
    return _sessionFromJson(input);
  }
  final hit = _decodedSessions[key];
  if (hit != null) return hit;
  final session = _sessionFromJson(input);
  if (_decodedSessions.length >= _decodedSessionLimit) _decodedSessions.clear();
  return _decodedSessions[key] = session;
}

TrainingSession _sessionFromJson(Object? input) {
  final json = jsonObject(input, 'session');
  checkKeys(json, {
    'schemaVersion',
    'id',
    'revision',
    'startedAt',
    'finishedAt',
    'endedAt',
    'status',
    'contentVersion',
    'sets',
    'bodyMassInputs',
    'loadInputs',
    'initialBodyMassOverrides',
    'derivedPlanInput',
    'prescriptionOverrides',
    'variantSelections',
    'gym',
    'gymSetupNotes',
    'extraSets',
  });
  if (json['schemaVersion'] != 1)
    invalid('Unsupported session schema version.');
  if (json.containsKey('initialBodyMassOverrides') &&
      json['initialBodyMassOverrides'] == null)
    invalid('Initial body-mass overrides must be an object.');
  final id = identifier(json, 'id');
  final revision = WorkoutRevision.fromJson(json['revision']);
  final startedAt = parseInstant(json['startedAt'], 'startedAt');
  final startOffset = parseOffsetMinutes(json['startedAt'], 'startedAt');
  final status = switch (json['status']) {
    'active' => SessionStatus.active,
    'finalized' => SessionStatus.finalized,
    _ => invalid('Invalid session status.'),
  };
  final finishedAt = json['finishedAt'] == null
      ? null
      : parseInstant(json['finishedAt'], 'finishedAt');
  final finishOffset = finishedAt == null
      ? 0
      : parseOffsetMinutes(json['finishedAt'], 'finishedAt');
  if ((status == SessionStatus.finalized) != (finishedAt != null) ||
      (finishedAt?.isBefore(startedAt) ?? false))
    invalid('Inconsistent session finish state/time.');
  final gymId = json['gym'] == null ? null : identifier(json, 'gym');
  if (json.containsKey('gym') && json['gym'] == null)
    invalid('A session without a gym omits gym.');
  final gymSetupNotes = <String, String>{
    if (json.containsKey('gymSetupNotes'))
      for (final e in jsonObject(
        json['gymSetupNotes'],
        'gymSetupNotes',
      ).entries)
        e.key: e.value is String
            ? e.value as String
            : invalid('Gym setup notes are strings.'),
  };
  if (json.containsKey('gymSetupNotes') && gymSetupNotes.isEmpty)
    invalid('Empty gym setup notes must be omitted.');
  final variantSelections = json.containsKey('variantSelections')
      ? variantSelectionsFromJson(json['variantSelections'])
      : const <String, String>{};
  if (json.containsKey('variantSelections') && variantSelections.isEmpty)
    invalid('Empty variant selections must be omitted.');
  final baseline = const TrainingService().start(
    sessionId: id,
    revision: revision,
    startedAt: startedAt,
    variantSelections: variantSelections,
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
      'performedOn',
      'unavailablePlates',
      'objectives',
      'substitution',
      'settings',
      'actualSettings',
      'contentVersion',
      'side',
    });
    final expected = baseline.sets[i];
    // The side is derived from the resolved plan, shown for readers only.
    if (row['side'] != baseline.definition.effortSide(expected.id))
      invalid('Set side does not match its authored effort.');
    // Categorical settings keep the planned levers and declared values.
    final levers = revision.definition.slot(expected.slotId).categories;
    final settings = row.containsKey('settings')
        ? categoricalSettingsFromJson(row['settings'], 'settings')
        : const <String, String>{};
    final actualSettings = row.containsKey('actualSettings')
        ? categoricalSettingsFromJson(row['actualSettings'], 'actualSettings')
        : const <String, String>{};
    if (canonicalJson(settings.keys.toList()) !=
        canonicalJson(expected.settings.keys.toList()))
      invalid('Set categorical settings do not match the slot levers.');
    validateCategoricalSettings(settings, levers, 'Set ${expected.id}');
    validateCategoricalSettings(actualSettings, levers, 'Set ${expected.id}');
    final substitution = row.containsKey('substitution')
        ? SetSubstitution.fromJson(row['substitution'])
        : null;
    if (substitution != null && _positive(row, 'contentVersion') < 2)
      invalid('A substitution requires a later set version.');
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
          (k) =>
              !(substitution?.unresolved.contains(k) == true &&
                  !suggested.containsKey(k)) &&
              suggested[k]?.dimension != expected.suggested[k]!.dimension,
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
        performedOn: row['performedOn'] == null
            ? null
            : LoadInstanceReference.fromJson(row['performedOn']),
        unavailablePlates: row.containsKey('unavailablePlates')
            ? [
                for (final p in jsonList(row, 'unavailablePlates'))
                  PlateUsage.fromJson(p),
              ]
            : const [],
        status: setStatus,
        substitution: substitution,
        settings: settings,
        actualSettings: actualSettings,
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
        applyPrescriptionOverrides(baseline.definition, baseline.sets, [
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
            set.carriedTargets.containsKey(entry.key) ||
            (set.substitution != null &&
                set.substitution!.targets[entry.key]?.source != 'keep'))
          continue;
        if (canonicalJson(set.suggested[entry.key]?.toJson()) !=
            canonicalJson(entry.value.toJson()))
          invalid(
            'Set suggestions do not match frozen prescription overrides.',
          );
      }
    }
  }
  if (json.containsKey('extraSets') && jsonList(json, 'extraSets').isEmpty)
    invalid('Empty unplanned sets must be omitted.');
  final session = TrainingSession(
    id: id,
    revision: revision,
    variantSelections: variantSelections,
    gymId: gymId,
    gymSetupNotes: gymSetupNotes,
    startedAt: startedAt,
    startOffsetMinutes: startOffset,
    sets: sets,
    extraSets: [
      if (json.containsKey('extraSets'))
        for (final item in jsonList(json, 'extraSets')) _extraSet(item),
    ],
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
    finishOffsetMinutes: finishOffset,
    endedAt: json.containsKey('endedAt')
        ? parseInstant(json['endedAt'], 'endedAt')
        : null,
    contentVersion: _positive(json, 'contentVersion'),
  );
  validateDerivedPlanSession(session);
  return session;
}

/// An unplanned set: identity, slot, role, ordinal, completed actuals and
/// optional settings/observations. The session validates the rest.
TrainingSet _extraSet(Object? input) {
  final row = jsonObject(input, 'unplanned set');
  checkKeys(row, {
    'id',
    'slot',
    'role',
    'ordinal',
    'suggested',
    'sources',
    'status',
    'actuals',
    'observations',
    'settings',
    'contentVersion',
  });
  if (jsonObject(row['suggested'], 'suggested').isNotEmpty ||
      jsonObject(row['sources'], 'sources').isNotEmpty ||
      row['status'] != 'completed')
    invalid('An unplanned set records completed actuals only.');
  final ordinal = row['ordinal'];
  if (ordinal is! int || ordinal < 0) invalid('Invalid unplanned ordinal.');
  return TrainingSet(
    id: requiredString(row, 'id'),
    slotId: identifier(row, 'slot'),
    role: requiredString(row, 'role'),
    ordinal: ordinal,
    suggested: const {},
    status: SetStatus.completed,
    actuals: metricsFromJson(row['actuals']),
    observations: row.containsKey('observations')
        ? SetObservations.fromJson(row['observations'])
        : null,
    settings: row.containsKey('settings')
        ? categoricalSettingsFromJson(row['settings'], 'settings')
        : const {},
    actualSettings: const {},
    contentVersion: _positive(row, 'contentVersion'),
  );
}
