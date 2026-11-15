import 'package:bodytmi_core/bodytmi_core.dart';
import 'canonical_json.dart';
import 'training_analytics.dart';

/// Strict, descriptive single-set records. Holding every other observed metric
/// avoids turning multi-lever observations into an inferred scalar score.
final class ContextualRecords {
  const ContextualRecords();
  Map<String, Object?> evaluate(
    List<TrainingSession> sessions, {
    required String metric,
    required String direction,
    Metrics atActuals = const {},
    Map<String, String> runBySession = const {},
    Map<String, Object?> context = const {},
    DateTime? from,
    DateTime? until,
    bool includeWarmups = false,
    FamilyRevision? family,
    List<String>? roles,
  }) {
    if (!{'higher', 'lower'}.contains(direction))
      invalid('Record direction must be higher or lower.');
    if (atActuals.length > 100 || atActuals.containsKey(metric))
      invalid('Record conditions need at most 100 other metric IDs.');
    for (final key in atActuals.keys) identifier({'id': key}, 'id');
    final series = const TrainingAnalytics().series(
      sessions,
      metric: metric,
      runBySession: runBySession,
      context: context,
      from: from,
      until: until,
      includeWarmups: includeWarmups,
      family: family,
      roles: roles,
    );
    final sources = {for (final s in sessions) s.id: s};
    final setSources = {
      for (final s in sessions) s.id: {for (final set in s.sets) set.id: set},
    };
    final groups = <String, _Records>{};
    final excluded = <Map<String, Object?>>[];
    var eligible = 0;
    for (final inputRow in jsonList(series, 'series')) {
      final row = jsonObject(inputRow, 'series');
      for (final inputPoint in jsonList(row, 'points')) {
        final point = jsonObject(inputPoint, 'point');
        final sessionId = requiredString(point, 'sessionId');
        final session = sources[sessionId]!;
        final set = setSources[sessionId]![requiredString(point, 'setId')]!;
        final slot = session.definition.slot(set.slotId);
        final missing =
            slot.targets.keys
                .where((key) => !set.actuals.containsKey(key))
                .toList()
              ..sort();
        String? reason;
        if (!set.eligibleForPerformance) {
          reason = 'interrupted-set';
        } else if (slot.bodyMass != null || slot.effectiveMass != null) {
          reason = 'body-mass-or-derived-load-policy-required';
        } else if (missing.isNotEmpty) {
          reason = 'configured-actuals-missing';
        } else if (atActuals.entries.any(
          (e) =>
              set.actuals[e.key] == null ||
              set.actuals[e.key]!.dimension != e.value.dimension ||
              set.actuals[e.key]!.compareTo(e.value) != 0,
        )) {
          reason = 'actual-conditions-not-met';
        }
        if (reason != null) {
          excluded.add({
            'sessionId': sessionId,
            'sessionContentVersion': session.contentVersion,
            'setId': set.id,
            'setContentVersion': set.contentVersion,
            'reason': reason,
            if (reason == 'configured-actuals-missing') 'metrics': missing,
          });
          continue;
        }
        eligible++;
        final held = {
          for (final key
              in (set.actuals.keys.where((key) => key != metric).toList()
                ..sort()))
            key: {
              'value': set.actuals[key]!.value.toString(),
              'unit': set.actuals[key]!.unit.name,
            },
        };
        final guidance = slot.timing?.toJson();
        final key = canonicalJson([
          row['context'],
          metric,
          row['unit'],
          held,
          guidance,
        ]);
        final group = groups.putIfAbsent(
          key,
          () => _Records({
            'key': key,
            'context': row['context'],
            'metric': metric,
            'dimension': row['dimension'],
            'unit': row['unit'],
            'heldActuals': held,
            'timingGuidance': guidance,
          }, direction),
        );
        group.add(point, set.actuals[metric]!);
      }
    }
    excluded.sort((a, b) => canonicalJson(a).compareTo(canonicalJson(b)));
    final keys = groups.keys.toList()..sort();
    return {
      'policy': {
        'id': roles != null
            ? 'bodytmi-contextual-records/5'
            : requiredString(
                jsonObject(series['policy'], 'policy'),
                'id',
              ).endsWith('/3')
            ? 'bodytmi-contextual-records/4'
            : requiredString(
                jsonObject(series['policy'], 'policy'),
                'id',
              ).endsWith('/2')
            ? 'bodytmi-contextual-records/3'
            : 'bodytmi-contextual-records/2',
        'metric': metric,
        'direction': direction,
        'comparison': 'single-set-all-other-observed-metrics-fixed',
        'scope': 'selected-finalized-history',
        'order': 'session-start/session-id/set-ordinal/set-id',
        'requiresAllConfiguredActuals': true,
        'interruptedSets': 'excluded',
        'bodyMassAndDerivedLoads': 'excluded',
        'atActuals': metricsToJson(atActuals),
        'includeWarmups': includeWarmups,
        if (roles != null)
          'roles': jsonList(jsonObject(series['policy'], 'policy'), 'roles'),
        'includeActive': false,
        'context': context,
        'from': from?.toUtc().toIso8601String(),
        'until': until?.toUtc().toIso8601String(),
        if (family != null) 'family': family.toJson(),
      },
      'pointCount': series['pointCount'],
      'eligibleCount': eligible,
      'excludedCount': excluded.length,
      'excluded': excluded,
      'groups': [for (final key in keys) groups[key]!.toJson()],
    };
  }
}

final class _Records {
  _Records(this.header, this.direction);
  final Map<String, Object?> header;
  final String direction;
  final List<Map<String, Object?>> points = [];
  Quantity? best;
  final List<Map<String, Object?>> sources = [];
  void add(Map<String, Object?> point, Quantity value) {
    final comparison = best == null ? null : value.compareTo(best!);
    final improves =
        comparison != null &&
        (direction == 'higher' ? comparison > 0 : comparison < 0);
    final marker = best == null
        ? 'initial'
        : improves
        ? 'record'
        : comparison == 0
        ? 'tie'
        : 'none';
    if (best == null || improves) {
      best = value;
      sources.clear();
    }
    final marked = {...point, 'marker': marker};
    points.add(marked);
    if (value.compareTo(best!) == 0) sources.add(marked);
  }

  Map<String, Object?> toJson() => {
    ...header,
    'best': {'value': best!.value.toString(), 'unit': best!.unit.name},
    'bestSources': sources,
    'points': points,
  };
}
