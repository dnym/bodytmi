import 'package:bodytmi_core/bodytmi_core.dart';
import 'canonical_json.dart';
import 'history_import_service.dart';
import 'repeat_checkpoint.dart';
import 'repeat_history.dart';

/// Neutral initial/record/tie/none markers over one ordered comparable group.
final class _Track<T extends Comparable<Object>> {
  _Track(this.header, this.higher);
  final Map<String, Object?> header;
  final bool higher;
  final List<Map<String, Object?>> points = [];
  final List<Map<String, Object?>> sources = [];
  T? best;

  void add(Map<String, Object?> point, T value) {
    final comparison = best == null ? null : value.compareTo(best!);
    final improves =
        comparison != null && (higher ? comparison > 0 : comparison < 0);
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
}

Map<String, Object?> _held(Metrics actuals, String metric) => {
  for (final key in (actuals.keys.where((k) => k != metric).toList()..sort()))
    key: {
      'value': actuals[key]!.value.toString(),
      'unit': actuals[key]!.unit.name,
    },
};

/// Opt-in imported records (policy bodytmi-imported-records/1). Imported
/// history keeps its own exact contexts (namespace, mapped exercise or source
/// name, implementation, equipment, convention, role, entered unit) and every
/// other observed metric of the set is held fixed, as for native contextual
/// records. Only sets imported with status completed qualify. Imported points
/// never merge with native records, and no cross-source ranking is implied.
Map<String, Object?> importedRecordsBlock(
  List<ImportedSessionRecord> records, {
  required String metric,
  required String direction,
  Metrics atActuals = const {},
  Map<String, Object?> context = const {},
  DateTime? from,
  DateTime? until,
  bool includeWarmups = false,
  List<String>? roles,
  FamilyRevision? family,
  String? namespace,
  int nativePointCount = 0,
}) {
  if (!{'higher', 'lower'}.contains(direction))
    invalid('Record direction must be higher or lower.');
  final series = importedSeriesBlock(
    records,
    context: context,
    metric: metric,
    from: from,
    until: until,
    includeWarmups: includeWarmups,
    roles: roles,
    family: family,
    namespace: namespace,
    nativePointCount: nativePointCount,
  );
  final sets = <String, ImportedSet>{};
  for (final record in records) {
    for (final exercise in record.session.exercises) {
      for (final set in exercise.sets) {
        sets[canonicalJson([
              record.namespace,
              record.sourceId,
              exercise.sourceId,
              set.sourceId,
            ])] =
            set;
      }
    }
  }
  final groups = <String, _Track<Quantity>>{};
  final excluded = <Map<String, Object?>>[];
  var eligible = 0;
  for (final inputRow in jsonList(series, 'series')) {
    final row = jsonObject(inputRow, 'series');
    final rowContext = jsonObject(row['context'], 'context');
    for (final inputPoint in jsonList(row, 'points')) {
      final point = jsonObject(inputPoint, 'point');
      final set =
          sets[canonicalJson([
            rowContext['namespace'],
            point['sessionSourceId'],
            point['exerciseSourceId'],
            point['setSourceId'],
          ])]!;
      final value = set.actuals[metric]!;
      String? reason;
      if (set.status != 'completed') {
        reason = 'status-${set.status}';
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
          'namespace': rowContext['namespace'],
          'sessionSourceId': point['sessionSourceId'],
          'setSourceId': point['setSourceId'],
          'reason': reason,
        });
        continue;
      }
      eligible++;
      final held = _held(set.actuals, metric);
      final key = canonicalJson([rowContext, held]);
      groups
          .putIfAbsent(
            key,
            () => _Track({
              'key': key,
              'context': rowContext,
              'heldActuals': held,
            }, direction == 'higher'),
          )
          .add(point, value);
    }
  }
  excluded.sort((a, b) => canonicalJson(a).compareTo(canonicalJson(b)));
  final keys = groups.keys.toList()..sort();
  return {
    'policy': {
      'id': 'bodytmi-imported-records/1',
      'origin': 'imported',
      'metric': metric,
      'direction': direction,
      'comparison': 'single-set-all-other-observed-metrics-fixed',
      'order': importedSeriesOrdering,
      'eligibleStatus': 'completed',
      'atActuals': metricsToJson(atActuals),
      'series': series['policy'],
    },
    'pointCount': series['pointCount'],
    'eligibleCount': eligible,
    'excludedCount': excluded.length,
    'excluded': excluded,
    'selectionExcluded': series['excluded'],
    'groups': [
      for (final key in keys)
        () {
          final group = groups[key]!;
          return {
            ...group.header,
            'best': {
              'value': group.best!.value.toString(),
              'unit': group.best!.unit.name,
            },
            'bestSources': group.sources,
            'points': group.points,
          };
        }(),
    ],
  };
}

/// Opt-in AMRAP block score records (policy bodytmi-block-records/1). The
/// score is the explicitly confirmed round count of a finalized session's
/// block that ran to its deadline; partial rounds are reported, never turned
/// into a fractional score. Scores compare only within one run, template,
/// block and frozen loop (round targets and duration), so a block whose
/// targets progressed starts a new group.
Map<String, Object?> blockScoreRecords(
  List<RepeatCheckpoint> checkpoints,
  List<TrainingSession> sessions, {
  Map<String, String> runBySession = const {},
  Map<String, Object?> context = const {},
  String? amrapId,
  DateTime? from,
  DateTime? until,
}) {
  if (amrapId != null) identifier({'amrapId': amrapId}, 'amrapId');
  final rounds = const RepeatHistory().rounds(
    [
      for (final c in checkpoints)
        if (c.amrapId != null && (amrapId == null || c.amrapId == amrapId)) c,
    ],
    sessions,
    runBySession: runBySession,
    runId: context['runId'] as String?,
    from: from,
    until: until,
  );
  final unrepresented = [
    for (final key in context.keys)
      if (!{'runId', 'templateId'}.contains(key)) key,
  ];
  final groups = <String, _Track<num>>{};
  final excluded = <Map<String, Object?>>[];
  var selected = 0;
  if (unrepresented.isEmpty) {
    for (final item in jsonList(rounds, 'attempts')) {
      final attempt = jsonObject(item, 'attempt');
      if (context.containsKey('runId') && attempt['runId'] != context['runId'])
        continue;
      if (context.containsKey('templateId') &&
          attempt['templateId'] != context['templateId'])
        continue;
      selected++;
      final point = {
        'sessionId': attempt['sessionId'],
        'sessionContentVersion': attempt['sessionContentVersion'],
        'sessionStartedAt': attempt['sessionStartedAt'],
        'checkpointId': attempt['checkpointId'],
        'checkpointVersion': attempt['checkpointVersion'],
        'confirmedRounds': attempt['confirmedRounds'],
        'partialRounds': attempt['partialRounds'],
      };
      if (attempt['executionStatus'] != 'finished' ||
          attempt['terminalReason'] != 'windowExpired') {
        excluded.add({...point, 'reason': 'not-run-to-deadline'});
        continue;
      }
      final header = {
        'runId': attempt['runId'],
        'templateId': attempt['templateId'],
        'amrapId': attempt['amrapId'],
        'loop': attempt['loop'],
      };
      final key = canonicalJson(header);
      groups
          .putIfAbsent(key, () => _Track({'key': key, ...header}, true))
          .add(point, attempt['confirmedRounds']! as int);
    }
  }
  final keys = groups.keys.toList()..sort();
  return {
    'policy': {
      'id': 'bodytmi-block-records/1',
      'origin': 'amrapBlock',
      'score': 'confirmedRounds',
      'direction': 'higher',
      'eligible': 'finalized session, block finished at windowExpired',
      'partialRounds': 'reported-not-scored',
      'scope': 'run/template/block/frozen-loop',
      'amrapId': amrapId,
      'context': context,
    },
    if (unrepresented.isNotEmpty)
      'excludedAll':
          'Block scores have no ${unrepresented.join('/')} context to match.',
    'selectedCount': selected,
    'eligibleCount': selected - excluded.length,
    'excludedCount': excluded.length,
    'excluded': excluded,
    'groups': [
      for (final key in keys)
        {
          ...groups[key]!.header,
          'best': groups[key]!.best,
          'bestSources': groups[key]!.sources,
          'points': groups[key]!.points,
        },
    ],
  };
}
