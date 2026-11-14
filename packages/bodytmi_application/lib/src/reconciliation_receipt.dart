import 'package:bodytmi_core/bodytmi_core.dart';
import 'canonical_json.dart';
import 'link_retirement.dart';
import 'progression_anchor.dart';
import 'progression_decision.dart';
import 'progression_reconciliation.dart';
import 'shared_lever_application.dart';
import 'shared_track_view.dart';
import 'training_service.dart';

/// An explicit, durable authorization that re-anchors one run/slot/role
/// progression track onto a different prescription. It adopts that candidate's
/// planned targets and optionally resets failure and coordinator state. It
/// never records work, evaluates performance, or advances a program.
///
/// The later [ProgressionDecision] lineage continues from this receipt, so the
/// break in prescription context is provably authorized rather than silent.
final class ReconciliationReceipt implements ProgressionAnchor {
  ReconciliationReceipt({
    required this.id,
    required this.runId,
    required this.revision,
    required this.slotId,
    required this.role,
    required List<TrainingSet> sets,
    required Map<String, Object?> rule,
    required this.ruleType,
    required this.previousApplication,
    required this.previousSequence,
    required this.previousFailures,
    required this.reconciledAt,
    required List<String> acknowledgedKinds,
    this.previousCursor = 0,
    this.resetFailures = false,
    this.resetCursor = false,
    this.sourceSessionId,
  }) : rule = _freeze(rule) as Map<String, Object?>,
       sets = List.unmodifiable(sets),
       acknowledgedKinds = List.unmodifiable(acknowledgedKinds) {
    identifier({'id': id}, 'id');
    if (runId != null) identifier({'id': runId}, 'id');
    if (sourceSessionId != null) identifier({'id': sourceSessionId}, 'id');
    identifier({'id': slotId}, 'id');
    if (!effortRoles.contains(role) ||
        !{'double', 'threshold', 'ordinal'}.contains(ruleType) ||
        (ruleType != 'threshold' && (previousCursor != 0 || resetCursor)) ||
        previousSequence < 1 ||
        previousFailures < 0 ||
        previousCursor < 0 ||
        previousApplication == null)
      invalid('Invalid progression reconciliation state.');
    if (acknowledgedKinds.isEmpty ||
        acknowledgedKinds.toSet().length != acknowledgedKinds.length ||
        !reconciliationKinds.containsAll(acknowledgedKinds))
      invalid('Reconciliation must acknowledge every blocker kind once.');
    if (!revision.definition.slots.any((slot) => slot.id == slotId) ||
        this.sets.isEmpty)
      invalid('Reconciliation needs a known slot with sets in the role.');
    if (ruleType == 'double') {
      DoubleProgressionRule.fromJson(this.rule);
    } else if (ruleType == 'threshold') {
      ThresholdRule.fromJson(this.rule);
    } else {
      OrdinalRule.fromJson(this.rule);
    }
    final baseline = baselineSets(revision, slotId, role);
    if (baseline.length != this.sets.length)
      invalid('Reconciliation sets do not match the pinned prescription.');
    final metrics = controlledMetrics;
    for (var i = 0; i < baseline.length; i++) {
      final expected = baseline[i], adopted = this.sets[i];
      if (adopted.id != expected.id ||
          adopted.slotId != slotId ||
          adopted.role != role ||
          adopted.ordinal != expected.ordinal ||
          adopted.status != SetStatus.planned ||
          adopted.actuals.isNotEmpty ||
          adopted.contentVersion != 1 ||
          canonicalJson(adopted.objectivesJson) !=
              canonicalJson(expected.objectivesJson))
        invalid('Reconciliation set identity does not match the prescription.');
      for (final metric in metrics) {
        final value = adopted.suggested[metric],
            planned = expected.suggested[metric];
        if (value == null)
          invalid('Reconciliation is missing a controlled target.');
        if (planned != null) {
          if (value.dimension != planned.dimension)
            invalid('Reconciliation target dimension is inconsistent.');
          continue;
        }
        final criterion = expected.criteria[metric];
        if (criterion == null ||
            criterion.mode == 'observe' ||
            value.dimension != criterion.unit.dimension)
          invalid('Reconciliation adopts an unexplained target.');
      }
      for (final metric in adopted.suggested.keys) {
        if (expected.suggested.containsKey(metric)) continue;
        final criterion = expected.criteria[metric];
        if (criterion == null ||
            criterion.mode == 'observe' ||
            adopted.suggested[metric]!.dimension != criterion.unit.dimension)
          invalid('Reconciliation adopts an unexplained target.');
      }
    }
  }

  factory ReconciliationReceipt.fromJson(Object? input) {
    final json = jsonObject(input, 'progression reconciliation');
    checkKeys(json, {
      'id',
      'runId',
      'revision',
      'slotId',
      'role',
      'sets',
      'rule',
      'ruleType',
      'previousApplication',
      'previousSequence',
      'previousFailures',
      'previousCursor',
      'failedSessions',
      'cursor',
      'acknowledgedKinds',
      'resetFailures',
      'resetCursor',
      'sourceSessionId',
      'reconciledAt',
    });
    int count(String key, int min) {
      final value = json[key];
      if (value is! int || value < min) invalid('Invalid $key.');
      return value;
    }

    final kind = json['ruleType'] ?? 'double';
    if (json.containsKey('role') && json['role'] == 'work')
      invalid(
        'The default work role must be omitted in stored reconciliations.',
      );
    if (kind is! String ||
        (kind != 'threshold' &&
            (json.containsKey('previousCursor') || json.containsKey('cursor'))))
      invalid('Invalid stored rule type or coordinator state.');
    final kinds = [
      for (final value in jsonList(json, 'acknowledgedKinds'))
        value is String ? value : invalid('Invalid acknowledged kinds.'),
    ];
    final previous = json['previousApplication'];
    if (previous is! String || previous.trim().isEmpty)
      invalid('Reconciliation needs the application it supersedes.');
    final resetFailures = json['resetFailures'] ?? false,
        resetCursor = json['resetCursor'] ?? false;
    if (resetFailures is! bool || resetCursor is! bool)
      invalid('Invalid reconciliation reset flags.');
    final receipt = ReconciliationReceipt(
      id: identifier(json, 'id'),
      runId: json['runId'] == null ? null : identifier(json, 'runId'),
      revision: WorkoutRevision.fromJson(json['revision']),
      slotId: identifier(json, 'slotId'),
      role: json.containsKey('role') ? requiredString(json, 'role') : 'work',
      sets: _setsFromJson(json['sets']),
      rule: jsonObject(json['rule'], 'rule'),
      ruleType: kind,
      previousApplication: previous,
      previousSequence: count('previousSequence', 1),
      previousFailures: count('previousFailures', 0),
      previousCursor: kind == 'threshold' ? count('previousCursor', 0) : 0,
      reconciledAt: parseInstant(json['reconciledAt'], 'reconciledAt'),
      acknowledgedKinds: kinds,
      resetFailures: resetFailures,
      resetCursor: resetCursor,
      sourceSessionId: json['sourceSessionId'] == null
          ? null
          : identifier(json, 'sourceSessionId'),
    );
    if (count('failedSessions', 0) != receipt.failedSessions ||
        (kind == 'threshold' && count('cursor', 0) != receipt.cursor))
      invalid('Reconciliation state does not match its explicit resets.');
    return receipt;
  }

  final String id;
  final String? runId;
  final WorkoutRevision revision;
  final String slotId;
  final String role;
  @override
  final List<TrainingSet> sets;
  @override
  final Map<String, Object?> rule;
  @override
  final String ruleType;
  @override
  final String? previousApplication;
  @override
  final int previousSequence, previousFailures, previousCursor;
  final DateTime reconciledAt;
  final List<String> acknowledgedKinds;
  final bool resetFailures, resetCursor;

  /// The session whose frozen suggestions supplied the adopted vector, when the
  /// reconciliation adopted an existing session rather than only a revision.
  final String? sourceSessionId;

  @override
  late final Set<String> controlledMetrics = ruleType == 'double'
      ? {
          DoubleProgressionRule.fromJson(rule).objective,
          DoubleProgressionRule.fromJson(rule).lever,
        }
      : ruleType == 'threshold'
      ? {
          ...ThresholdRule.fromJson(rule).increments.keys,
          ...ThresholdRule.fromJson(rule).resets.keys,
          ...ThresholdRule.fromJson(rule).deloadMetrics,
        }
      : OrdinalRule.fromJson(rule).controlledMetrics;
  @override
  late final ExerciseSlot slot = revision.definition.slot(slotId);
  @override
  late final String contextKey = anchorContextKey(
    runId,
    templateId,
    slot,
    role,
  );
  @override
  int get sequence => previousSequence + 1;
  @override
  int get failedSessions => resetFailures ? 0 : previousFailures;
  @override
  int get cursor => resetCursor ? 0 : previousCursor;
  @override
  List<Metrics> get nextSets => [for (final set in sets) set.suggested];
  @override
  String get templateId => revision.definition.id;
  @override
  int get revisionNumber => revision.number;
  @override
  WorkoutRevision get pinnedRevision => revision;
  @override
  DateTime? get resolvedAt => reconciledAt;
  @override
  String get status => 'reconciled';

  @override
  bool matches(String templateId, ExerciseSlot candidate) =>
      this.templateId == templateId && slot.compatibleWith(candidate);

  Map<String, Object?> toJson() => {
    'id': id,
    if (runId != null) 'runId': runId,
    'revision': revision.toJson(),
    'slotId': slotId,
    if (role != 'work') 'role': role,
    'sets': [
      for (final set in sets)
        {
          'id': set.id,
          'slot': set.slotId,
          'role': set.role,
          'ordinal': set.ordinal,
          'suggested': metricsToJson(set.suggested),
          if (set.objectivesJson.isNotEmpty) 'objectives': set.objectivesJson,
        },
    ],
    'rule': rule,
    if (ruleType != 'double') 'ruleType': ruleType,
    if (ruleType == 'threshold') ...{
      'previousCursor': previousCursor,
      'cursor': cursor,
    },
    'previousApplication': previousApplication,
    'previousSequence': previousSequence,
    'previousFailures': previousFailures,
    'failedSessions': failedSessions,
    'acknowledgedKinds': acknowledgedKinds,
    if (resetFailures) 'resetFailures': true,
    if (resetCursor) 'resetCursor': true,
    if (sourceSessionId != null) 'sourceSessionId': sourceSessionId,
    'reconciledAt': reconciledAt.toUtc().toIso8601String(),
  };
}

/// Planned sets for one slot and role exactly as [revision] prescribes them.
List<TrainingSet> baselineSets(
  WorkoutRevision revision,
  String slotId,
  String role,
) {
  final view = const TrainingService().start(
    sessionId: 'reconciliation-baseline',
    revision: revision,
    startedAt: DateTime.utc(1970),
  );
  return List.unmodifiable(
    view.sets.where((set) => set.slotId == slotId && set.role == role),
  );
}

List<TrainingSet> _setsFromJson(Object? input) {
  if (input is! List<Object?>) invalid('Reconciliation sets must be an array.');
  final sets = <TrainingSet>[];
  for (final item in input) {
    final row = jsonObject(item, 'reconciliation set');
    checkKeys(row, {
      'id',
      'slot',
      'role',
      'ordinal',
      'suggested',
      'objectives',
    });
    final ordinal = row['ordinal'];
    if (ordinal is! int || ordinal < 0) invalid('Invalid set ordinal.');
    final objectives = row.containsKey('objectives')
        ? numericObjectivesFromJson(row['objectives'])
        : <String, NumericObjective>{};
    final maxEffortMetrics = objectives.entries
        .where((entry) => entry.value.mode == 'maxEffort')
        .map((entry) => entry.key)
        .toSet();
    sets.add(
      TrainingSet(
        id: requiredString(row, 'id'),
        slotId: identifier(row, 'slot'),
        role: requiredString(row, 'role'),
        ordinal: ordinal,
        suggested: metricsFromJson(row['suggested']),
        maxEffortMetrics: maxEffortMetrics,
        criteria: Map.fromEntries(
          objectives.entries.where((entry) => entry.value.mode != 'maxEffort'),
        ),
        settings: const {},
        actualSettings: const {},
      ),
    );
  }
  return List.unmodifiable(sets);
}

/// Checks receipt identity, lineage and adoption against the surrounding
/// archive. Receipts authorize a prescription break; they never re-decide an
/// exposure and never carry training results.
void validateProgressionReconciliations(
  List<ReconciliationReceipt> reconciliations,
  List<ProgressionDecision> decisions,
  List<WorkoutRevision> revisions,
  List<TrainingSession> sessions, [
  List<LinkRetirementAnchor> retirements = const [],
  SharedLinkIndex? links,
]) {
  final anchors = <String, ProgressionAnchor>{
    for (final decision in decisions) decision.id: decision,
    for (final retirement in retirements) retirement.id: retirement,
  };
  for (final receipt in reconciliations) {
    if (anchors.containsKey(receipt.id))
      invalid('Progression reconciliation identity is already used.');
    anchors[receipt.id] = receipt;
  }
  final sequences = <String, Set<int>>{};
  for (final anchor in anchors.values) {
    if (anchor.resolvedAt == null) continue;
    if (!sequences
        .putIfAbsent(anchor.contextKey, () => <int>{})
        .add(anchor.sequence))
      invalid('Competing progression writers at one sequence.');
  }
  final published = {
    for (final revision in revisions)
      '${revision.definition.id}\u0000${revision.number}': revision,
  };
  final bySession = {for (final session in sessions) session.id: session};
  for (final receipt in reconciliations) {
    final pinned =
        published['${receipt.revision.definition.id}\u0000${receipt.revision.number}'];
    if (pinned == null ||
        canonicalJson(pinned.toJson()) !=
            canonicalJson(receipt.revision.toJson()))
      invalid('Reconciliation pins an unpublished workout revision.');
    final source = receipt.sourceSessionId;
    if (source != null) {
      final session = bySession[source];
      if (session == null ||
          session.revision.definition.id != receipt.revision.definition.id ||
          session.revision.number != receipt.revision.number)
        invalid('Reconciliation source session is inconsistent.');
    }
    final before = anchors[receipt.previousApplication];
    if (before == null ||
        before.resolvedAt == null ||
        !sameAnchorContext(receipt, before) ||
        receipt.previousSequence != before.sequence ||
        receipt.reconciledAt.isBefore(before.resolvedAt!))
      invalid('Reconciliation lineage is inconsistent.');
    final link = links == null
        ? null
        : linkedContextFor(links, receipt, receipt.reconciledAt);
    if (link != null) {
      final state = links!.stateAt(link.id, receipt.reconciledAt);
      if (state == null ||
          receipt.previousFailures != state.failedSessions ||
          receipt.previousCursor != state.cursor)
        invalid('Linked reconciliation counters differ from the shared track.');
    } else if (receipt.previousFailures != before.failedSessions ||
        receipt.previousCursor != before.cursor)
      invalid('Reconciliation lineage is inconsistent.');
    if (canonicalJson(receipt.rule) != canonicalJson(before.rule) &&
        !receipt.acknowledgedKinds.contains('rule'))
      invalid('Reconciliation changes a rule without acknowledging it.');
    if (receipt.ruleType != before.ruleType &&
        !receipt.acknowledgedKinds.contains('rule'))
      invalid('Reconciliation changes a rule type without acknowledging it.');
  }
}

/// Shared CLI and test view of one durable reconciliation. It exposes the
/// effective state the reconciliation leaves behind, not a training decision.
Map<String, Object?> reconciliationView(ReconciliationReceipt receipt) => {
  'id': receipt.id,
  'applied': true,
  'status': receipt.status,
  'sequence': receipt.sequence,
  'resolvedState': {
    'failedSessions': receipt.failedSessions,
    if (receipt.ruleType == 'threshold') 'cursor': receipt.cursor,
    'nextSets': [for (final set in receipt.sets) metricsToJson(set.suggested)],
  },
  ...receipt.toJson(),
};

Object? _freeze(Object? value) {
  if (value is Map<String, Object?>)
    return Map<String, Object?>.unmodifiable({
      for (final e in value.entries) e.key: _freeze(e.value),
    });
  if (value is List<Object?>)
    return List<Object?>.unmodifiable(value.map(_freeze));
  return value;
}
