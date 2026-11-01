import 'package:bodytmi_core/bodytmi_core.dart';
import 'session_codec.dart';
import 'canonical_json.dart';
import 'progression_evaluation.dart';

/// Stable exposure identity is session/slot, never a result content version.
final class ProgressionDecision {
  ProgressionDecision({
    required this.session,
    required this.slotId,
    required Map<String, Object?> rule,
    this.previousApplication,
    this.previousSequence = 0,
    this.previousFailures = 0,
    this.version = 1,
    this.acceptedAt,
    this.declinedAt,
    this.runId,
    this.ruleType = 'double',
    this.previousCursor = 0,
  }) : rule = _freeze(rule) as Map<String, Object?> {
    if (session.status != SessionStatus.finalized)
      invalid('Progression requires finalized confirmed work.');
    identifier({'id': slotId}, 'id');
    if (runId != null) identifier({'id': runId}, 'id');
    if (version < 1 ||
        !{'double', 'threshold'}.contains(ruleType) ||
        previousCursor < 0 ||
        (ruleType == 'double' && previousCursor != 0) ||
        previousSequence < 0 ||
        previousFailures < 0 ||
        ((previousApplication == null) != (previousSequence == 0)))
      invalid('Invalid progression decision state.');
    final slots = session.revision.definition.slots.where(
      (s) => s.id == slotId,
    );
    if (slots.isEmpty || sets.isEmpty)
      invalid('Progression needs a known slot with working sets.');
    if ((acceptedAt != null && declinedAt != null) ||
        (resolvedAt != null && resolvedAt!.isBefore(session.finishedAt!)))
      invalid('A decision needs one resolution, no earlier than finalization.');
    final outcome = proposal.outcome;
    if (acceptedAt != null && (outcome == 'unknown' || outcome == 'review'))
      invalid(
        'Unconfirmed or changed-load work requires review before application.',
      );
  }
  factory ProgressionDecision.fromJson(Object? input) {
    final j = jsonObject(input, 'progression decision');
    checkKeys(j, {
      'session',
      'slotId',
      'rule',
      'previousApplication',
      'previousSequence',
      'previousFailures',
      'version',
      'acceptedAt',
      'declinedAt',
      'proposal',
      'runId',
      'ruleType',
      'previousCursor',
    });
    int count(String key, int min) {
      final v = j[key];
      if (v is! int || v < min) invalid('Invalid $key.');
      return v;
    }

    final previous = j['previousApplication'];
    if (previous != null && previous is! String)
      invalid('Invalid previous application identity.');
    final kind = j['ruleType'] ?? 'double';
    if (kind is! String ||
        (kind != 'threshold' && j.containsKey('previousCursor')))
      invalid('Invalid stored rule type or coordinator state.');
    final decision = ProgressionDecision(
      session: sessionFromJson(j['session']),
      slotId: identifier(j, 'slotId'),
      rule: jsonObject(j['rule'], 'rule'),
      previousApplication: previous as String?,
      previousSequence: count('previousSequence', 0),
      previousFailures: count('previousFailures', 0),
      version: count('version', 1),
      acceptedAt: j['acceptedAt'] == null
          ? null
          : parseInstant(j['acceptedAt'], 'acceptedAt'),
      declinedAt: j.containsKey('declinedAt')
          ? parseInstant(j['declinedAt'], 'declinedAt')
          : null,
      runId: j['runId'] == null ? null : identifier(j, 'runId'),
      ruleType: kind,
      previousCursor: kind == 'threshold' ? count('previousCursor', 0) : 0,
    );
    if (canonicalJson(j['proposal']) !=
        canonicalJson(decision.proposal.toJson()))
      invalid('Progression proposal does not match its inputs.');
    return decision;
  }
  final TrainingSession session;
  final String slotId;
  final Map<String, Object?> rule;
  final String? previousApplication;
  final int previousSequence, previousFailures, version;
  final DateTime? acceptedAt, declinedAt;
  DateTime? get resolvedAt => acceptedAt ?? declinedAt;
  String get status => acceptedAt != null
      ? 'accepted'
      : declinedAt != null
      ? 'declined'
      : 'pending';
  final String? runId;
  final String ruleType;
  final int previousCursor;
  int get cursor => declinedAt != null ? previousCursor : proposal.cursor;
  late final Set<String> controlledMetrics = ruleType == 'double'
      ? {
          DoubleProgressionRule.fromJson(rule).objective,
          DoubleProgressionRule.fromJson(rule).lever,
        }
      : {
          ...ThresholdRule.fromJson(rule).increments.keys,
          ...ThresholdRule.fromJson(rule).resets.keys,
          ...ThresholdRule.fromJson(rule).deloadMetrics,
        };
  String get id => '${session.id}/$slotId';
  int get sequence => previousSequence + (resolvedAt == null ? 0 : 1);

  /// Decline holds targets, but the confirmed exposure's classification still
  /// resolves exactly once. Declining a deload never grants its counter reset.
  int get failedSessions => declinedAt != null && proposal.outcome == 'deload'
      ? previousFailures + 1
      : proposal.failedSessions;
  List<Metrics> get nextSets => declinedAt == null
      ? proposal.nextSets
      : List.unmodifiable([for (final set in sets) set.suggested]);
  late final ExerciseSlot slot = session.revision.definition.slot(slotId);
  late final String contextKey = canonicalJson([
    runId,
    session.revision.definition.id,
    slot.id,
    slot.exerciseId,
    slot.implementation,
    slot.equipmentId,
    slot.setupNote,
  ]);
  late final List<TrainingSet> sets = List.unmodifiable(
    session.sets.where((s) => s.slotId == slotId && s.role == 'work'),
  );
  late final ProgressionEvaluation proposal = ruleType == 'threshold'
      ? ProgressionEvaluation.threshold(
          ThresholdRule.fromJson(rule),
          sets,
          previousFailures,
          previousCursor,
        )
      : ProgressionEvaluation.double(
          DoubleProgressionRule.fromJson(rule).evaluate(
            currentSets: [for (final s in sets) s.suggested],
            results: [
              for (final s in sets) s.eligibleForPerformance ? s.actuals : null,
            ],
            failedSessions: previousFailures,
          ),
        );
  bool sameContext(ProgressionDecision other) =>
      runId == other.runId &&
      session.revision.definition.id == other.session.revision.definition.id &&
      slot.compatibleWith(other.slot);
  bool matches(String templateId, ExerciseSlot candidate) =>
      session.revision.definition.id == templateId &&
      slot.compatibleWith(candidate);
  ProgressionDecision accept(DateTime at) => ProgressionDecision(
    session: session,
    slotId: slotId,
    rule: rule,
    previousApplication: previousApplication,
    previousSequence: previousSequence,
    previousFailures: previousFailures,
    version: version,
    acceptedAt: at,
    declinedAt: declinedAt,
    runId: runId,
    ruleType: ruleType,
    previousCursor: previousCursor,
  );
  ProgressionDecision decline(DateTime at) => ProgressionDecision(
    session: session,
    slotId: slotId,
    rule: rule,
    previousApplication: previousApplication,
    previousSequence: previousSequence,
    previousFailures: previousFailures,
    version: version,
    acceptedAt: acceptedAt,
    declinedAt: at,
    runId: runId,
    ruleType: ruleType,
    previousCursor: previousCursor,
  );
  Map<String, Object?> toJson() => {
    'session': session.toJson(),
    'slotId': slotId,
    'rule': rule,
    'previousApplication': previousApplication,
    'previousSequence': previousSequence,
    'previousFailures': previousFailures,
    'version': version,
    'acceptedAt': acceptedAt?.toUtc().toIso8601String(),
    if (declinedAt != null) 'declinedAt': declinedAt!.toUtc().toIso8601String(),
    'proposal': proposal.toJson(),
    if (runId != null) 'runId': runId,
    if (ruleType == 'threshold') ...{
      'ruleType': ruleType,
      'previousCursor': previousCursor,
    },
  };
}

ProgressionDecision? latestApplication(
  Iterable<ProgressionDecision> decisions,
  String templateId,
  ExerciseSlot slot, {
  String? runId,
}) {
  ProgressionDecision? latest;
  for (final d in decisions) {
    if (d.runId == runId &&
        d.resolvedAt != null &&
        d.matches(templateId, slot) &&
        (latest == null || d.sequence > latest.sequence))
      latest = d;
  }
  return latest;
}

void validateProgressionDecisions(
  List<ProgressionDecision> decisions,
  List<TrainingSession> sessions, [
  Map<String, String> runBySession = const {},
]) {
  final byId = <String, ProgressionDecision>{};
  final sequences = <String, Set<int>>{};
  final current = {for (final s in sessions) s.id: s};
  for (final d in decisions) {
    if (byId.containsKey(d.id))
      invalid('Duplicate progression exposure identity.');
    byId[d.id] = d;
    if (d.runId != runBySession[d.session.id])
      invalid('Progression ownership does not match session program binding.');
    if (d.resolvedAt != null &&
        !(sequences.putIfAbsent(d.contextKey, () => <int>{}).add(d.sequence))) {
      invalid('Competing progression writers at one sequence.');
    }
    final s = current[d.session.id];
    if (s == null ||
        s.contentVersion < d.session.contentVersion ||
        s.revision.definition.id != d.session.revision.definition.id ||
        s.revision.number != d.session.revision.number ||
        canonicalJson({
              for (final e in s.bodyMassInputs.entries) e.key: e.value.toJson(),
            }) !=
            canonicalJson({
              for (final e in d.session.bodyMassInputs.entries)
                e.key: e.value.toJson(),
            }) ||
        canonicalJson(s.revision.toJson()) !=
            canonicalJson(d.session.revision.toJson()))
      invalid('Progression source snapshot is inconsistent.');
    if (s.contentVersion == d.session.contentVersion &&
        canonicalJson(s.toJson()) != canonicalJson(d.session.toJson()))
      invalid('Progression input content does not match its version.');
  }
  for (final d in decisions) {
    final before = d.previousApplication == null
        ? null
        : byId[d.previousApplication];
    if (before == null) {
      if (d.previousApplication != null ||
          d.previousSequence != 0 ||
          d.previousFailures != 0)
        invalid('Progression base application is missing.');
      if (d.previousCursor != 0)
        invalid('Initial coordinator cursor must be zero.');
    } else {
      if (before.resolvedAt == null ||
          !d.sameContext(before) ||
          d.previousSequence != before.sequence ||
          d.previousFailures != before.failedSessions ||
          d.ruleType != before.ruleType ||
          d.previousCursor != before.cursor ||
          canonicalJson(d.rule) != canonicalJson(before.rule))
        invalid('Progression lineage is inconsistent.');
      if (!matchesProgressionBaseline(d, before))
        invalid('Progression baseline is inconsistent.');
      if (d.resolvedAt != null && d.resolvedAt!.isBefore(before.resolvedAt!))
        invalid('Progression application chronology is inconsistent.');
    }
  }
}

Object? _freeze(Object? value) {
  if (value is Map<String, Object?>)
    return Map<String, Object?>.unmodifiable({
      for (final e in value.entries) e.key: _freeze(e.value),
    });
  if (value is List<Object?>)
    return List<Object?>.unmodifiable(value.map(_freeze));
  return value;
}

bool matchesProgressionBaseline(
  ProgressionDecision decision,
  ProgressionDecision before,
) {
  final expected = before.nextSets;
  if (expected.length != decision.sets.length) return false;
  for (var i = 0; i < expected.length; i++) {
    for (final metric in decision.controlledMetrics) {
      final actual = decision.sets[i].suggested[metric];
      if (actual == null || actual.compareTo(expected[i][metric]!) != 0)
        return false;
    }
  }
  return true;
}
