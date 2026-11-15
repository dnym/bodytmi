import 'package:bodytmi_core/bodytmi_core.dart';
import 'followed_settings.dart';
import 'session_codec.dart';
import 'canonical_json.dart';
import 'lever_link.dart';
import 'progression_anchor.dart';
import 'progression_evaluation.dart';
import 'shared_lever_application.dart';
import 'shared_track_view.dart';

/// Stable exposure identity includes role, never a result content version.
final class ProgressionDecision implements ProgressionAnchor {
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
    this.role = 'work',
    this.selectedLevel,
    this.preset,
    Metrics? previousReference,
  }) : rule = _freeze(rule) as Map<String, Object?>,
       previousReference = previousReference == null
           ? null
           : Map.unmodifiable(previousReference) {
    if (preset case (:final id, :final revision)) {
      identifier({'id': id}, 'id');
      if (revision < 1) invalid('Invalid progression preset reference.');
    }
    if (session.status != SessionStatus.finalized)
      invalid('Progression requires finalized confirmed work.');
    identifier({'id': slotId}, 'id');
    if (runId != null) identifier({'id': runId}, 'id');
    if (version < 1 ||
        !{'double', 'threshold', 'ordinal'}.contains(ruleType) ||
        !{'work', 'warmup', 'backoff', 'drop'}.contains(role) ||
        previousCursor < 0 ||
        (ruleType != 'threshold' && previousCursor != 0) ||
        previousSequence < 0 ||
        previousFailures < 0 ||
        ((previousApplication == null) != (previousSequence == 0)))
      invalid('Invalid progression decision state.');
    final slots = session.definition.slots.where((s) => s.id == slotId);
    if (slots.isEmpty || sets.isEmpty)
      invalid('Progression needs a known slot with sets in the selected role.');
    if ((acceptedAt != null && declinedAt != null) ||
        (resolvedAt != null && resolvedAt!.isBefore(session.finishedAt!)))
      invalid('A decision needs one resolution, no earlier than finalization.');
    final outcome = proposal.outcome;
    if (acceptedAt != null && (outcome == 'unknown' || outcome == 'review'))
      invalid(
        'Unconfirmed or changed-load work requires review before application.',
      );
    // Incomparable branches move only by an explicit declared successor.
    if (acceptedAt != null &&
        outcome == 'choice' &&
        !proposal.candidates.contains(selectedLevel))
      invalid(
        'Accepting a branch choice needs selectedLevel among '
        '${proposal.candidates.join(', ')}.',
      );
    if (selectedLevel != null && (acceptedAt == null || outcome != 'choice'))
      invalid('selectedLevel only resolves an accepted branch choice.');
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
      'role',
      'selectedLevel',
      'preset',
      'previousReference',
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
    if (j.containsKey('role') && j['role'] == 'work')
      invalid('The default work role must be omitted in stored decisions.');
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
      role: j.containsKey('role') ? requiredString(j, 'role') : 'work',
      selectedLevel: j.containsKey('selectedLevel')
          ? identifier(j, 'selectedLevel')
          : null,
      preset: j.containsKey('preset')
          ? presetReferenceFromJson(j['preset'])
          : null,
      previousReference: j.containsKey('previousReference')
          ? metricsFromJson(j['previousReference'])
          : null,
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
  final String role;
  final int previousCursor;

  /// The cycle reference this exposure started from (cycle-restart rules).
  final Metrics? previousReference;
  @override
  Metrics? get cycleReference =>
      declinedAt != null ? previousReference : proposal.nextReference;

  /// The declared successor chosen when accepting an ordinal branch choice.
  final String? selectedLevel;

  /// Provenance only: the published preset revision whose rule this decision
  /// froze. The decision's own [rule] stays authoritative.
  final PresetReference? preset;
  int get cursor => declinedAt != null ? previousCursor : proposal.cursor;
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
  String get storageSlotKey => role == 'work' ? slotId : '$slotId/$role';
  String get id => '${session.id}/$storageSlotKey';
  int get sequence => previousSequence + (resolvedAt == null ? 0 : 1);

  /// Decline holds targets, but the confirmed exposure's classification still
  /// resolves exactly once. Declining a deload never grants its counter reset.
  int get failedSessions =>
      declinedAt != null &&
          (proposal.outcome == 'deload' ||
              proposal.outcome == 'retest' ||
              (proposal.outcome == 'stage' &&
                  ThresholdRule.fromJson(rule).stages?.advanceOn == 'failure'))
      ? previousFailures + 1
      : proposal.failedSessions;
  List<Metrics> get nextSets => selectedLevel != null
      ? List.unmodifiable([
          for (final _ in sets)
            OrdinalRule.fromJson(rule).levelTargets(selectedLevel!),
        ])
      : declinedAt == null
      ? proposal.nextSets
      : List.unmodifiable([for (final set in sets) set.suggested]);
  @override
  late final Set<String> controlledSettings = ruleType == 'ordinal'
      ? OrdinalRule.fromJson(rule).controlledSettings
      : ruleType == 'threshold'
      ? {?ThresholdRule.fromJson(rule).stages?.lever}
      : const {};

  /// Settings move only with an applied ordinal level change.
  @override
  late final List<Map<String, String>> nextSettings = () {
    String? level;
    if (controlledSettings.isNotEmpty && declinedAt == null) {
      level =
          selectedLevel ??
          (const {'advance', 'deload'}.contains(proposal.outcome)
              ? proposal.nextLevel
              : null);
    }
    final settings = ruleType == 'threshold'
        ? (declinedAt == null && proposal.nextStage != null
              ? {
                  ThresholdRule.fromJson(rule).stages!.lever:
                      proposal.nextStage!,
                }
              : null)
        : level == null
        ? null
        : OrdinalRule.fromJson(rule).levelSettings(level);
    return List<Map<String, String>>.unmodifiable([
      for (final set in sets)
        Map<String, String>.unmodifiable({
          for (final lever in controlledSettings)
            lever: settings?[lever] ?? set.settings[lever]!,
        }),
    ]);
  }();
  late final ExerciseSlot slot = session.definition.slot(slotId);
  @override
  String get templateId => session.definition.id;
  @override
  int get revisionNumber => session.revision.number;
  @override
  WorkoutRevision get pinnedRevision => session.revision;
  @override
  String get contextKey => anchorContextKey(runId, templateId, slot, role);
  late final List<TrainingSet> sets = List.unmodifiable(
    session.sets.where((s) => s.slotId == slotId && s.role == role),
  );
  late final ProgressionEvaluation proposal =
      sets.any((s) => s.actualSettings.isNotEmpty)
      ? ProgressionEvaluation.categoricalReview(
          sets,
          previousFailures,
          previousCursor,
          withCursor: ruleType == 'threshold',
          reference: previousReference,
        )
      : _evaluated;

  /// Controlled actuals that followed their target on the instance used.
  late final List<FollowedSetting> followed = followedSettings(
    session,
    sets,
    leverMetrics(ruleType, rule),
  );
  late final List<TrainingSet> _evaluatedSets = asFollowed(sets, followed);
  late final ProgressionEvaluation _evaluated = switch (ruleType) {
    'threshold' => ProgressionEvaluation.threshold(
      ThresholdRule.fromJson(rule),
      _evaluatedSets,
      previousFailures,
      previousCursor,
      previousReference,
    ),
    'ordinal' => ProgressionEvaluation.ordinal(
      OrdinalRule.fromJson(rule),
      _evaluatedSets,
      previousFailures,
    ),
    _ => ProgressionEvaluation.double(
      DoubleProgressionRule.fromJson(rule).evaluate(
        currentSets: [for (final s in _evaluatedSets) s.suggested],
        results: [
          for (final s in _evaluatedSets)
            s.eligibleForPerformance ? s.actuals : null,
        ],
        failedSessions: previousFailures,
      ),
    ),
  };
  bool sameContext(ProgressionDecision other) =>
      runId == other.runId &&
      role == other.role &&
      session.definition.id == other.session.definition.id &&
      slot.compatibleWith(other.slot);
  bool matches(String templateId, ExerciseSlot candidate) =>
      session.definition.id == templateId && slot.compatibleWith(candidate);
  ProgressionDecision accept(DateTime at, {String? selectedLevel}) =>
      ProgressionDecision(
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
        role: role,
        selectedLevel: selectedLevel,
        preset: preset,
        previousReference: previousReference,
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
    role: role,
    preset: preset,
    previousReference: previousReference,
  );
  Map<String, Object?> toJson() => {
    'session': session.toJson(),
    'slotId': slotId,
    if (role != 'work') 'role': role,
    'rule': rule,
    'previousApplication': previousApplication,
    'previousSequence': previousSequence,
    'previousFailures': previousFailures,
    'version': version,
    'acceptedAt': acceptedAt?.toUtc().toIso8601String(),
    if (declinedAt != null) 'declinedAt': declinedAt!.toUtc().toIso8601String(),
    'proposal': proposal.toJson(),
    if (runId != null) 'runId': runId,
    if (ruleType != 'double') 'ruleType': ruleType,
    if (ruleType == 'threshold') 'previousCursor': previousCursor,
    if (previousReference != null)
      'previousReference': metricsToJson(previousReference!),
    if (selectedLevel != null) 'selectedLevel': selectedLevel,
    if (preset case (:final id, :final revision))
      'preset': {'id': id, 'revision': revision},
  };
}

typedef PresetReference = ({String id, int revision});

PresetReference presetReferenceFromJson(Object? input) {
  final j = jsonObject(input, 'preset');
  checkKeys(j, {'id', 'revision'});
  final revision = j['revision'];
  if (revision is! int || revision < 1)
    invalid('preset.revision must be a positive integer.');
  return (id: identifier(j, 'id'), revision: revision);
}

/// Every decision naming a preset must name a published revision whose rule
/// and rule type it froze verbatim.
void validatePresetProvenance(
  Iterable<ProgressionDecision> decisions,
  Iterable<ProgressionPresetRevision> presets,
) {
  for (final decision in decisions) {
    final reference = decision.preset;
    if (reference == null) continue;
    final match = presets.where(
      (p) => p.preset.id == reference.id && p.number == reference.revision,
    );
    if (match.isEmpty)
      invalid('Progression decision names an unpublished preset revision.');
    if (match.single.preset.ruleType != decision.ruleType ||
        canonicalJson(match.single.preset.rule) != canonicalJson(decision.rule))
      invalid('Progression decision rule does not match its preset revision.');
  }
}

ProgressionDecision? latestApplication(
  Iterable<ProgressionDecision> decisions,
  String templateId,
  ExerciseSlot slot, {
  String? runId,
  String role = 'work',
}) =>
    latestAnchor(decisions, templateId, slot, runId: runId, role: role)
        as ProgressionDecision?;

/// The current baseline for a context across resolved decisions and explicit
/// reconciliations. Sequences are unique per context in a valid store.
/// The metrics a rule moves as levers (not its performance metric): only
/// these can follow their target on another instance's nearest setting.
Set<String> leverMetrics(String ruleType, Map<String, Object?> rule) =>
    switch (ruleType) {
      'threshold' => () {
        final r = ThresholdRule.fromJson(rule);
        return {...r.increments.keys, ...r.resets.keys, ...r.deloadMetrics}
          ..remove(r.metric);
      }(),
      'ordinal' => () {
        final r = OrdinalRule.fromJson(rule);
        return {...r.controlledMetrics}..remove(r.metric);
      }(),
      _ => {DoubleProgressionRule.fromJson(rule).lever},
    };

ProgressionAnchor? latestTrack(
  Iterable<ProgressionDecision> decisions,
  Iterable<ProgressionAnchor> anchors,
  String templateId,
  ExerciseSlot slot, {
  String? runId,
  String role = 'work',
}) => latestAnchor(
  <ProgressionAnchor>[...decisions, ...anchors],
  templateId,
  slot,
  runId: runId,
  role: role,
);

void validateProgressionDecisions(
  List<ProgressionDecision> decisions,
  List<TrainingSession> sessions, [
  Map<String, String> runBySession = const {},
  List<ProgressionAnchor> anchors = const [],
  SharedLinkIndex? links,
]) {
  final byId = <String, ProgressionDecision>{};
  final byAnchor = <String, ProgressionAnchor>{
    for (final anchor in anchors) anchor.id: anchor,
  };
  final sequences = <String, Set<int>>{};
  final current = {for (final s in sessions) s.id: s};
  for (final d in decisions) {
    if (byId.containsKey(d.id) || byAnchor.containsKey(d.id))
      invalid('Duplicate progression exposure identity.');
    byId[d.id] = d;
    byAnchor[d.id] = d;
    if (d.runId != runBySession[d.session.id])
      invalid('Progression ownership does not match session program binding.');
    if (d.resolvedAt != null &&
        !(sequences.putIfAbsent(d.contextKey, () => <int>{}).add(d.sequence))) {
      invalid('Competing progression writers at one sequence.');
    }
    final s = current[d.session.id];
    if (s == null ||
        s.contentVersion < d.session.contentVersion ||
        s.definition.id != d.session.definition.id ||
        s.revision.number != d.session.revision.number ||
        canonicalJson(
              s.initialBodyMassOverrides?.map(
                (k, v) => MapEntry(k, v.toJson()),
              ),
            ) !=
            canonicalJson(
              d.session.initialBodyMassOverrides?.map(
                (k, v) => MapEntry(k, v.toJson()),
              ),
            ) ||
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
        : byAnchor[d.previousApplication];
    final link = links == null ? null : _activeLinkFor(links, d);
    if (before == null) {
      if (d.previousApplication != null ||
          d.previousSequence != 0 ||
          d.previousFailures != 0)
        invalid('Progression base application is missing.');
      if (d.previousCursor != 0 || d.previousReference != null)
        invalid(
          'Initial coordinator cursor and cycle reference must be empty.',
        );
    } else {
      final shared = link == null
          ? null
          : links!.stateAt(link.id, d.session.startedAt);
      if (link != null && shared == null)
        invalid('Linked progression lacks its shared chain state.');
      if (before.resolvedAt == null ||
          !sameAnchorContext(d, before) ||
          d.previousSequence != before.sequence ||
          d.ruleType != before.ruleType ||
          canonicalJson(d.rule) != canonicalJson(before.rule))
        invalid('Progression lineage is inconsistent.');
      if (link == null) {
        if (d.previousFailures != before.failedSessions ||
            d.previousCursor != before.cursor ||
            canonicalJson(_referenceJson(d.previousReference)) !=
                canonicalJson(_referenceJson(before.cycleReference)))
          invalid('Progression lineage is inconsistent.');
        if (!matchesProgressionBaseline(d, before))
          invalid('Progression baseline is inconsistent.');
      } else {
        final state = shared!;
        if (d.previousFailures != state.failedSessions ||
            d.previousCursor != state.cursor)
          invalid('Linked progression counters differ from the shared track.');
        if (state.vector.length != before.nextSets.length)
          invalid('Linked shared vector conflicts with the local track.');
        if (!matchesProgressionBaseline(
          d,
          SharedTrackView(local: before, link: link, shared: state),
        ))
          invalid('Linked progression baseline is inconsistent.');
        if (d.resolvedAt != null && link.cadence == 'each-exposure') {
          final row = links!.rowForOrigin(d.id);
          if (row == null ||
              row.linkId != link.id ||
              row.originSessionId != d.session.id ||
              row.previousFailures != d.previousFailures ||
              row.previousCursor != d.previousCursor ||
              row.failedSessions != d.failedSessions ||
              row.cursor != d.cursor ||
              row.occurredAt != d.resolvedAt)
            invalid('Linked exposure lacks its shared application step.');
        }
      }
      if (d.resolvedAt != null && d.resolvedAt!.isBefore(before.resolvedAt!))
        invalid('Progression application chronology is inconsistent.');
    }
  }
}

/// The published link [d]'s context actively backs, using the same predicate
/// the consumption path wraps with: not retired before the session started,
/// and the session started no earlier than the link.
LeverLink? _activeLinkFor(SharedLinkIndex links, ProgressionDecision d) =>
    linkedContextFor(links, d, d.session.startedAt);

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
  ProgressionAnchor before,
) => matchesSessionProgressionBaseline(
  decision.session,
  decision.slotId,
  decision.role,
  decision.controlledMetrics,
  before,
);

/// Apply the same baseline checks to an active session for a read-only preview.
bool matchesSessionProgressionBaseline(
  TrainingSession session,
  String slotId,
  String role,
  Set<String> controlledMetrics,
  ProgressionAnchor before,
) {
  final sets = session.sets
      .where((s) => s.slotId == slotId && s.role == role)
      .toList();
  final currentPlan = session.definition;
  // The anchor's revision under this session's variant structure; a uniform
  // vector may resize across a structural (set scheme) change.
  final priorPlan = resolveAlike(
    before.pinnedRevision.definition,
    session.variantSelections,
  );
  if (priorPlan == null || sets.isEmpty) return false;
  final broadcast = broadcastsVector(
    before,
    session.revision.definition,
    slotId,
    sets.first.settings,
    sets.length,
  );
  if (sets.length != before.sets.length && !broadcast) return false;
  final priorEfforts = broadcast
      ? priorPlan.roleEfforts(before.slotId, before.role)
      : null;
  if (priorEfforts != null && priorEfforts.length != sets.length) return false;
  for (var i = 0; i < sets.length; i++) {
    final currentObjectives = sets[i].maxEffortMetrics;
    final previousObjectives =
        priorEfforts?[i].maxEffortMetrics ?? before.sets[i].maxEffortMetrics;
    if (currentObjectives.length != previousObjectives.length ||
        !currentObjectives.containsAll(previousObjectives))
      return false;
    if (canonicalJson({
          for (final e in sets[i].criteria.entries)
            e.key: e.value.semanticJson(),
        }) !=
        canonicalJson({
          for (final e
              in (priorEfforts?[i].criteria ?? before.sets[i].criteria).entries)
            e.key: e.value.semanticJson(),
        }))
      return false;
  }
  if (currentPlan.hasEffortTargets || priorPlan.hasEffortTargets) {
    final authored = currentPlan.roleTargets(slotId, role);
    final prior = priorPlan.roleTargets(before.slotId, before.role);
    if (authored.length != prior.length) return false;
    for (var i = 0; i < authored.length; i++) {
      for (final metric in controlledMetrics) {
        final value = authored[i][metric], old = prior[i][metric];
        if (value == null ||
            old == null ||
            value.dimension != old.dimension ||
            value.compareTo(old) != 0)
          return false;
      }
    }
  }
  final expected = broadcast
      ? List.filled(sets.length, before.nextSets.first)
      : before.nextSets;
  if (expected.length != sets.length) return false;
  for (var i = 0; i < expected.length; i++) {
    for (final metric in controlledMetrics) {
      final actual = sets[i].suggested[metric];
      if (actual == null || actual.compareTo(expected[i][metric]!) != 0)
        return false;
    }
  }
  return true;
}

Object? _referenceJson(Metrics? reference) =>
    reference == null ? null : metricsToJson(reference);
