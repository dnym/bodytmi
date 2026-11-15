import 'package:bodytmi_core/bodytmi_core.dart';
import 'canonical_json.dart';

/// Read-only calculations over current result snapshots. No totals are inferred
/// from suggestions, and compatible-looking raw loads are never made equivalent.
final class TrainingAnalytics {
  const TrainingAnalytics();

  Map<String, Object?> summary(
    TrainingSession session, {
    bool includeWarmups = false,
    List<String> sumMetrics = const [],
    List<String>? roles,
  }) {
    final metrics = _sumMetrics(sumMetrics);
    final selectedRoles = _roles(roles, includeWarmups);
    bool included(TrainingSet set) =>
        selectedRoles?.contains(set.role) ??
        (includeWarmups || set.role != 'warmup');
    // Unplanned sets count like any other result of their slot and role.
    final sets = session.allSets.where(included).toList();
    final totals = <String, _MetricTotal>{};
    for (final set in sets) {
      for (final metric in metrics) {
        final actual = set.actuals[metric], target = set.suggested[metric];
        final unit =
            actual?.unit ??
            target?.unit ??
            (set.maxEffortMetrics.contains(metric) ? Unit.rep : null) ??
            set.criteria[metric]?.unit.canonical;
        if (unit == null) continue;
        final key = '$metric/${unit.name}';
        final total = totals.putIfAbsent(key, () => _MetricTotal(metric, unit));
        switch (set.status) {
          case SetStatus.completed:
            if (actual == null) {
              total.missing++;
            } else {
              total.observations++;
              total.value += actual.value;
            }
          case SetStatus.planned:
            total.planned++;
          case SetStatus.skipped:
            total.skipped++;
        }
      }
    }
    final keys = totals.keys.toList()..sort();
    // Parent bouts (drop sets, clusters, rest-pause) count once, separately
    // from their child efforts; never as additional sets.
    final byId = {for (final set in sets) set.id: set};
    final bouts = [
      for (final group in boutGroups(session.definition.plan))
        if (group.efforts.any(byId.containsKey))
          (
            path: group.path,
            sets: [
              for (final id in group.efforts)
                if (byId[id] case final set?) set,
            ],
          ),
    ];
    String boutStatus(List<TrainingSet> members) {
      final statuses = {for (final m in members) m.status};
      if (statuses.length > 1) return 'partial';
      return statuses.single.name;
    }

    final boutRows = [
      for (final b in bouts)
        {
          'path': b.path,
          'sets': [for (final set in b.sets) set.id],
          'status': boutStatus(b.sets),
        },
    ];
    return {
      'policy': {
        'id': selectedRoles != null
            ? 'bodytmi-session-summary/4'
            : sets.any((s) => s.criteria.isNotEmpty)
            ? 'bodytmi-session-summary/3'
            : sets.any((s) => s.maxEffortMetrics.isNotEmpty)
            ? 'bodytmi-session-summary/2'
            : 'bodytmi-session-summary/1',
        'includeWarmups': includeWarmups,
        if (selectedRoles != null) 'roles': selectedRoles,
        'sumMetrics': metrics,
        if (bouts.isNotEmpty) 'boutPolicy': 'bodytmi-bout-count/1',
      },
      'source': {
        'sessionId': session.id,
        'sessionContentVersion': session.contentVersion,
        'templateId': session.definition.id,
        'revision': session.revision.number,
      },
      'status': session.status.name,
      'startedAt': session.startedAt.toUtc().toIso8601String(),
      'finishedAt': session.finishedAt?.toUtc().toIso8601String(),
      'elapsed': session.finishedAt == null
          ? null
          : Quantity(
              (Decimal.parse(
                        session.finishedAt!
                            .difference(session.startedAt)
                            .inMicroseconds
                            .toString(),
                      ) *
                      Decimal.parse('0.000001'))
                  .toString(),
              's',
            ).toJson(),
      'counts': {
        'included': sets.length,
        'excludedWarmups': session.allSets
            .where((s) => s.role == 'warmup' && !included(s))
            .length,
        if (selectedRoles != null)
          'excludedRoles': session.allSets
              .where((s) => s.role != 'warmup' && !included(s))
              .length,
        for (final status in SetStatus.values)
          status.name: sets.where((s) => s.status == status).length,
        if (bouts.isNotEmpty)
          'bouts': {
            'total': bouts.length,
            for (final status in [
              ...SetStatus.values.map((s) => s.name),
              'partial',
            ])
              status: boutRows.where((r) => r['status'] == status).length,
          },
      },
      if (bouts.isNotEmpty) 'bouts': boutRows,
      'totals': [for (final key in keys) totals[key]!.toJson()],
      'sets': [
        for (final set in sets)
          {
            'id': set.id,
            'slot': set.slotId,
            'role': set.role,
            if (session.extraSets.contains(set)) 'unplanned': true,
            if (session.definition.effortSide(set.id) case final side?)
              'side': side,
            if (set.settings.isNotEmpty) 'settings': set.settings,
            if (set.actualSettings.isNotEmpty)
              'actualSettings': set.actualSettings,
            'ordinal': set.ordinal,
            'status': set.status.name,
            'contentVersion': set.contentVersion,
            'metrics': {
              for (final metric in ({
                ...set.suggested.keys,
                ...set.actuals.keys,
                ...set.maxEffortMetrics,
                ...set.criteria.keys,
              }.toList()..sort()))
                metric: {
                  'target': set.suggested[metric]?.toJson(),
                  if (set.maxEffortMetrics.contains(metric))
                    'objective': {'mode': 'maxEffort', 'unit': 'rep'},
                  if (set.criteria.containsKey(metric))
                    'objective': set.criteria[metric]!.toJson(),
                  if (set.criteria[metric]?.upperMeaning != null)
                    'upperReached': set.criteria[metric]!.assess(
                      set.actuals[metric],
                    )['upperReached'],
                  'actual': set.actuals[metric]?.toJson(),
                  'relation': set.status == SetStatus.completed
                      ? set.criteria.containsKey(metric)
                            ? set.criteria[metric]!.assess(
                                set.actuals[metric],
                              )['relation']
                            : set.maxEffortMetrics.contains(metric) &&
                                  set.actuals[metric] != null
                            ? 'observed'
                            : _relation(
                                set.suggested[metric],
                                set.actuals[metric],
                              )
                      : 'unobserved',
                },
            },
            if (set.timing != null) 'timing': set.timing!.toJson(),
            // Tempo-lever slots: the planned and (if it differed) performed
            // tempo pattern of this set.
            if (session.definition.slot(set.slotId).tempoLever != null) ...{
              'plannedTempo': session.definition
                  .slot(set.slotId)
                  .tempoFor(set.settings)!
                  .toJson(),
              if (set.actualSettings.containsKey(
                session.definition.slot(set.slotId).tempoLever,
              ))
                'performedTempo': session.definition
                    .slot(set.slotId)
                    .tempoFor(set.performedSettings)!
                    .toJson(),
            },
            if (set.observations != null)
              'observations': set.observations!.toJson(),
          },
      ],
    };
  }

  Map<String, Object?> series(
    List<TrainingSession> sessions, {
    Map<String, String> runBySession = const {},
    Map<String, Object?> context = const {},
    String? metric,
    DateTime? from,
    DateTime? until,
    bool includeWarmups = false,
    bool includeActive = false,
    FamilyRevision? family,
    List<String>? roles,
  }) {
    _context(context);
    final selectedRoles = _roles(roles, includeWarmups);
    if (metric != null) identifier({'metric': metric}, 'metric');
    if (from != null && until != null && !from.isBefore(until))
      invalid('Series from must precede exclusive until.');
    final ids = sessions.map((s) => s.id).toSet();
    if (ids.length != sessions.length ||
        runBySession.keys.any((id) => !ids.contains(id)))
      invalid('Series sources need unique sessions and known run bindings.');
    for (final entry in runBySession.entries)
      identifier({'id': entry.value}, 'id');
    final grouped = <String, Map<String, Object?>>{};
    final ordered = [...sessions]
      ..sort((a, b) {
        final date = a.startedAt.compareTo(b.startedAt);
        return date == 0 ? a.id.compareTo(b.id) : date;
      });
    var points = 0;
    var includesMaxEffort = false;
    var includesTypedObjective = false;
    final members = family?.family.exercises.toSet();
    for (final session in ordered) {
      if ((!includeActive && session.status != SessionStatus.finalized) ||
          (from != null && session.startedAt.isBefore(from)) ||
          (until != null && !session.startedAt.isBefore(until)))
        continue;
      final sets = [...session.allSets]
        ..sort((a, b) {
          final ordinal = a.ordinal.compareTo(b.ordinal);
          return ordinal == 0 ? a.id.compareTo(b.id) : ordinal;
        });
      for (final set in sets) {
        if (set.status != SetStatus.completed ||
            !(selectedRoles?.contains(set.role) ??
                (includeWarmups || set.role != 'warmup')))
          continue;
        final slot = session.definition.slot(set.slotId);
        // Substituted sets stay in their own slot + replacement context.
        final performed = effectiveComposition(slot, set);
        if (members != null && !members.contains(performed.exercise)) continue;
        final sourceContext = <String, Object?>{
          'runId': runBySession[session.id],
          'templateId': session.definition.id,
          'slotId': slot.id,
          'exercise': performed.exercise,
          'implementation': performed.implementation,
          'equipment': performed.equipment,
          'setupNote': performed.setupNote,
          'role': set.role,
          if (session.definition.effortSide(set.id) case final side?)
            'side': side,
          if (set.performedSettings.isNotEmpty)
            'settings': set.performedSettings,
          if (performed.substituted) 'substituted': true,
        };
        if (context.entries.any(
          (e) => e.key == 'settings'
              ? canonicalJson(sourceContext['settings']) !=
                    canonicalJson(e.value)
              : sourceContext[e.key] != e.value,
        ))
          continue;
        for (final entry in set.actuals.entries) {
          if (metric != null && entry.key != metric) continue;
          if (set.criteria.containsKey(entry.key))
            includesTypedObjective = true;
          if (set.maxEffortMetrics.contains(entry.key))
            includesMaxEffort = true;
          if (++points > 10000)
            invalid(
              'Series exceeds 10000 points; narrow its date/context/metric filters.',
            );
          final key = canonicalJson([
            sourceContext,
            entry.key,
            entry.value.unit.name,
          ]);
          final row = grouped.putIfAbsent(
            key,
            () => {
              'key': key,
              'context': sourceContext,
              'metric': entry.key,
              'dimension': entry.value.dimension.name,
              'unit': entry.value.unit.name,
              'points': <Object?>[],
            },
          );
          (row['points']! as List<Object?>).add({
            'sessionId': session.id,
            'sessionContentVersion': session.contentVersion,
            'setId': set.id,
            'setContentVersion': set.contentVersion,
            'ordinal': set.ordinal,
            'revision': session.revision.number,
            'sessionStatus': session.status.name,
            'startedAt': session.startedAt.toUtc().toIso8601String(),
            'finishedAt': session.finishedAt?.toUtc().toIso8601String(),
            if (set.observations != null)
              'observations': set.observations!.toJson(),
            'actual': entry.value.toJson(),
            'target': set.suggested[entry.key]?.toJson(),
            if (set.maxEffortMetrics.contains(entry.key))
              'objective': {'mode': 'maxEffort', 'unit': 'rep'},
            if (set.criteria.containsKey(entry.key))
              'objective': set.criteria[entry.key]!.toJson(),
            if (set.criteria[entry.key]?.upperMeaning != null)
              'upperReached': set.criteria[entry.key]!.assess(
                entry.value,
              )['upperReached'],
            'relation': set.criteria.containsKey(entry.key)
                ? set.criteria[entry.key]!.assess(entry.value)['relation']
                : set.maxEffortMetrics.contains(entry.key)
                ? 'observed'
                : _relation(set.suggested[entry.key], entry.value),
          });
        }
      }
    }
    final keys = grouped.keys.toList()..sort();
    return {
      'policy': {
        'id': selectedRoles != null
            ? (family == null
                  ? 'bodytmi-history-series/4'
                  : 'bodytmi-family-series/4')
            : family == null
            ? (includesTypedObjective
                  ? 'bodytmi-history-series/3'
                  : includesMaxEffort
                  ? 'bodytmi-history-series/2'
                  : 'bodytmi-history-series/1')
            : (includesTypedObjective
                  ? 'bodytmi-family-series/3'
                  : includesMaxEffort
                  ? 'bodytmi-family-series/2'
                  : 'bodytmi-family-series/1'),
        if (family != null) 'family': family.toJson(),
        'includeWarmups': includeWarmups,
        if (selectedRoles != null) 'roles': selectedRoles,
        'includeActive': includeActive,
        'context': context,
        'metric': metric,
        'from': from?.toUtc().toIso8601String(),
        'until': until?.toUtc().toIso8601String(),
      },
      'pointCount': points,
      'series': [for (final key in keys) grouped[key]],
    };
  }
}

List<String>? _roles(List<String>? roles, bool includeWarmups) {
  if (roles != null &&
      (roles.isEmpty ||
          roles.toSet().length != roles.length ||
          roles.any((role) => !effortRoles.contains(role)) ||
          includeWarmups)) {
    invalid(
      'roles needs distinct known effort roles and cannot be combined with includeWarmups.',
    );
  }
  return roles == null ? null : ([...roles]..sort());
}

List<String> _sumMetrics(List<String> input) {
  if (input.length > 100 || input.toSet().length != input.length)
    invalid('sumMetrics requires at most 100 distinct metric IDs.');
  for (final metric in input) identifier({'metric': metric}, 'metric');
  return [...input]..sort();
}

void _context(Map<String, Object?> context) {
  checkKeys(context, {
    'runId',
    'templateId',
    'slotId',
    'exercise',
    'implementation',
    'equipment',
    'setupNote',
    'role',
    'side',
    'settings',
    'substituted',
  });
  if (context.containsKey('substituted') && context['substituted'] != true)
    invalid('The substituted filter selects substitutes with true only.');
  for (final e in context.entries) {
    if (e.key == 'substituted') continue;
    if (e.value == null && {'runId', 'equipment', 'setupNote'}.contains(e.key))
      continue;
    if (e.key == 'setupNote') {
      if (e.value is! String)
        invalid('setupNote filter must be a string or null.');
    } else if (e.key == 'role') {
      if (!effortRoles.contains(e.value)) invalid('Unknown series role.');
    } else if (e.key == 'side') {
      if (!effortSides.contains(e.value))
        invalid('The side filter selects left or right.');
    } else if (e.key == 'settings') {
      categoricalSettingsFromJson(e.value, 'settings filter');
    } else {
      identifier(context, e.key);
    }
  }
}

String _relation(Quantity? target, Quantity? actual) {
  if (actual == null) return 'missing';
  if (target == null) return 'unplanned';
  return switch (actual.compareTo(target)) {
    < 0 => 'below',
    0 => 'equal',
    _ => 'above',
  };
}

final class _MetricTotal {
  _MetricTotal(this.metric, this.unit);
  final String metric;
  final Unit unit;
  Decimal value = Decimal.zero;
  int observations = 0, missing = 0, planned = 0, skipped = 0;
  Map<String, Object?> toJson() => {
    'metric': metric,
    'dimension': unit.dimension.name,
    'unit': unit.name,
    'value': observations == 0 ? null : value.toString(),
    'observations': observations,
    'missingCompleted': missing,
    'planned': planned,
    'skipped': skipped,
  };
}
