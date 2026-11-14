import 'dart:convert';

import 'package:bodytmi_core/bodytmi_core.dart';

import 'canonical_json.dart';
import 'repeat_checkpoint.dart';
import 'window_repeat_execution.dart';

/// Policy bodytmi-block-progression/1: an authored AMRAP block's score
/// (explicitly confirmed rounds) drives one round slot's controlled targets.
/// Only explicit reviews contribute; a stopped or limited block is neutral.
const blockProgressionPolicy = 'bodytmi-block-progression/1';

Metrics _metrics(Object? input, String label) {
  final metrics = metricsFromJson(jsonObject(input, label));
  if (metrics.isEmpty) invalid('$label must name at least one metric.');
  return metrics;
}

int _count(Map<String, Object?> json, String key, {int min = 0}) {
  final value = json[key];
  if (value is! int || value < min || value > 10000)
    invalid('$key must be an integer from $min through 10000.');
  return value;
}

/// Exact step that keeps the entered unit when both share it.
Quantity? _step(Quantity target, Quantity delta, {required bool up}) {
  if (target.dimension != delta.dimension)
    invalid('A block step has a different dimension from its target.');
  if (target.enteredUnit == delta.enteredUnit) {
    final a = Decimal.parse(target.enteredValue);
    final b = Decimal.parse(delta.enteredValue);
    final next = up ? a + b : a - b;
    if (next.compareTo(Decimal.zero) < 0) return null;
    return Quantity(next.toString(), target.enteredUnit.name);
  }
  final next = up ? target.value + delta.value : target.value - delta.value;
  if (next.compareTo(Decimal.zero) < 0) return null;
  return Quantity(next.toString(), target.unit.name);
}

final class BlockProgressionRule {
  BlockProgressionRule._(
    this.failureLimit,
    this.advancementLimit,
    this.increments,
    this.maximums,
    this.deloadAfter,
    this.deloadDecrements,
  );

  factory BlockProgressionRule.fromJson(Object? input) {
    final j = jsonObject(input, 'block progression rule');
    checkKeys(j, {
      'performance',
      'increments',
      'maximums',
      'deloadAfter',
      'deloadDecrements',
    });
    final performance = jsonObject(j['performance'], 'performance');
    checkKeys(performance, {'score', 'failureLimit', 'advancementLimit'});
    if (performance['score'] != 'confirmedRounds')
      invalid('Block performance score must be confirmedRounds.');
    final failure = _count(performance, 'failureLimit');
    final advancement = _count(performance, 'advancementLimit', min: 1);
    if (failure > advancement)
      invalid('failureLimit cannot exceed advancementLimit.');
    final increments = _metrics(j['increments'], 'increments');
    for (final step in increments.values) {
      if (step.value.compareTo(Decimal.zero) <= 0)
        invalid('Block increments must be positive.');
    }
    final maximums = j.containsKey('maximums')
        ? _metrics(j['maximums'], 'maximums')
        : const <String, Quantity>{};
    final decrements = j.containsKey('deloadDecrements')
        ? _metrics(j['deloadDecrements'], 'deloadDecrements')
        : const <String, Quantity>{};
    for (final entry in {...maximums, ...decrements}.entries) {
      final step = increments[entry.key];
      if (step == null)
        invalid('Block bound or deload ${entry.key} needs an increment.');
      if (step.dimension != entry.value.dimension)
        invalid('Block bound or deload ${entry.key} has another dimension.');
    }
    for (final step in decrements.values) {
      if (step.value.compareTo(Decimal.zero) <= 0)
        invalid('Block deload decrements must be positive.');
    }
    final deloadAfter = j.containsKey('deloadAfter')
        ? _count(j, 'deloadAfter', min: 1)
        : null;
    if ((deloadAfter == null) != decrements.isEmpty)
      invalid('deloadAfter and deloadDecrements must be declared together.');
    return BlockProgressionRule._(
      failure,
      advancement,
      increments,
      maximums,
      deloadAfter,
      decrements,
    );
  }

  final int failureLimit, advancementLimit;
  final Metrics increments, maximums, deloadDecrements;
  final int? deloadAfter;

  /// The rule may only move slot-level targets of one round slot that no
  /// round effort overrides per occurrence.
  void validateFor(WindowRepeatSpec loop, String roundSlotId) {
    final round = loop.roundDefinition;
    if (!round.slots.any((s) => s.id == roundSlotId))
      throw BodyTmiException(
        'not_found',
        'The AMRAP round has no slot $roundSlotId.',
      );
    final slot = round.slot(roundSlotId);
    for (final entry in increments.entries) {
      final target = slot.targets[entry.key];
      if (target == null)
        invalid('Round slot $roundSlotId has no ${entry.key} target to move.');
      if (target.dimension != entry.value.dimension)
        invalid('Increment ${entry.key} has another dimension.');
    }
    for (final effort in round.plan.nodes.whereType<Effort>()) {
      if (effort.slotId == roundSlotId &&
          effort.targets.keys.any(increments.containsKey))
        invalid('A round effort overrides a controlled block target.');
    }
  }

  Map<String, Object?> toJson() => {
    'performance': {
      'score': 'confirmedRounds',
      'failureLimit': failureLimit,
      'advancementLimit': advancementLimit,
    },
    'increments': metricsToJson(increments),
    if (maximums.isNotEmpty) 'maximums': metricsToJson(maximums),
    if (deloadAfter != null) 'deloadAfter': deloadAfter,
    if (deloadDecrements.isNotEmpty)
      'deloadDecrements': metricsToJson(deloadDecrements),
  };
}

/// One classification of one finished block exposure. Pure and repeatable.
({
  String outcome,
  String reason,
  int confirmedRounds,
  int partialRounds,
  Metrics proposedTargets,
  int proposedFailures,
})
evaluateBlockExposure(
  RepeatCheckpoint checkpoint,
  String roundSlotId,
  BlockProgressionRule rule,
  Metrics targets,
  int previousFailures,
) {
  final execution = checkpoint.execution;
  final cursor = jsonObject(execution['cursor'], 'cursor');
  final view = const WindowRepeatExecution().view(execution);
  final confirmed = view['confirmedRounds']! as int;
  final partial = view['partialRounds']! as int;
  ({
    String outcome,
    String reason,
    int confirmedRounds,
    int partialRounds,
    Metrics proposedTargets,
    int proposedFailures,
  })
  result(String outcome, String reason, Metrics next, int failures) => (
    outcome: outcome,
    reason: reason,
    confirmedRounds: confirmed,
    partialRounds: partial,
    proposedTargets: Map.unmodifiable(next),
    proposedFailures: failures,
  );
  if (cursor['status'] != 'finished' ||
      cursor['terminalReason'] != 'windowExpired')
    return result(
      'unknown',
      'Only a block that ran to its deadline is a scored exposure.',
      targets,
      previousFailures,
    );
  // Changed controlled actuals mean the score was not earned at the target.
  final loop = WindowRepeatSpec.fromJson(cursor['loop']);
  final plan = loop.roundDefinition.plan.occurrences().toList();
  final entries = jsonList(execution, 'entries');
  for (var i = 0; i < entries.length; i++) {
    final entry = jsonObject(entries[i], 'entry');
    if (entry['outcome'] != 'completed') continue;
    final effort = plan[i % plan.length].activity as Effort;
    if (effort.slotId != roundSlotId) continue;
    final actuals = metricsFromJson(entry['actuals']);
    for (final metric in rule.increments.keys) {
      final actual = actuals[metric];
      if (actual != null && actual.compareTo(targets[metric]!) != 0)
        return result(
          'review',
          'A reviewed effort changed controlled $metric; reconcile first.',
          targets,
          previousFailures,
        );
    }
  }
  if (confirmed < rule.failureLimit) {
    final failures = previousFailures + 1;
    final deloadAfter = rule.deloadAfter;
    if (deloadAfter != null && failures >= deloadAfter) {
      final next = {...targets};
      for (final entry in rule.deloadDecrements.entries) {
        final value = _step(targets[entry.key]!, entry.value, up: false);
        if (value == null)
          return result(
            'blocked',
            'The deload of ${entry.key} would go below zero.',
            targets,
            failures,
          );
        next[entry.key] = value;
      }
      return result('deload', 'Repeated failed exposures.', next, 0);
    }
    return result(
      'failed',
      'Confirmed rounds are below the failure limit.',
      targets,
      failures,
    );
  }
  if (confirmed < rule.advancementLimit)
    return result(
      'hold',
      'Confirmed rounds are below advancement.',
      targets,
      0,
    );
  final next = {...targets};
  for (final entry in rule.increments.entries) {
    final value = _step(targets[entry.key]!, entry.value, up: true)!;
    final maximum = rule.maximums[entry.key];
    if (maximum != null && value.compareTo(maximum) > 0)
      return result(
        'blocked',
        'Advancing ${entry.key} would exceed its maximum.',
        targets,
        0,
      );
    next[entry.key] = value;
  }
  return result('advance', 'Confirmed rounds reached advancement.', next, 0);
}

/// A durable proposal and, once resolved, its immutable receipt. Its
/// identity is the session's single exposure of one block round slot.
final class BlockProgressionDecision {
  BlockProgressionDecision._(this._json);

  factory BlockProgressionDecision.fromJson(Object? input) {
    final j = jsonObject(input, 'block progression decision');
    checkKeys(j, {
      'schemaVersion',
      'id',
      'version',
      'sessionId',
      'runId',
      'templateId',
      'revision',
      'amrapId',
      'roundSlotId',
      'sessionStartedAt',
      'rule',
      'source',
      'score',
      'base',
      'outcome',
      'reason',
      'proposed',
      'status',
      'resolvedAt',
      'resolved',
      'sequence',
    });
    if (j['schemaVersion'] != 1)
      invalid('Unsupported block progression decision version.');
    final sessionId = identifier(j, 'sessionId');
    final amrapId = identifier(j, 'amrapId');
    final roundSlotId = identifier(j, 'roundSlotId');
    if (j['id'] != blockDecisionId(sessionId, amrapId, roundSlotId))
      invalid('Block progression decision identity is inconsistent.');
    if (j['runId'] != null) identifier(j, 'runId');
    identifier(j, 'templateId');
    _count(j, 'revision', min: 1);
    _count(j, 'version', min: 1);
    _count(j, 'sequence', min: 1);
    parseInstant(j['sessionStartedAt'], 'sessionStartedAt');
    BlockProgressionRule.fromJson(j['rule']);
    final source = jsonObject(j['source'], 'source');
    checkKeys(source, {
      'checkpointId',
      'checkpointVersion',
      'executionVersion',
    });
    identifier(source, 'checkpointId');
    _count(source, 'checkpointVersion', min: 1);
    _count(source, 'executionVersion', min: 1);
    final score = jsonObject(j['score'], 'score');
    checkKeys(score, {'confirmedRounds', 'partialRounds'});
    _count(score, 'confirmedRounds');
    _count(score, 'partialRounds');
    final base = jsonObject(j['base'], 'base');
    checkKeys(base, {'anchorId', 'targets', 'failedSessions'});
    if (base['anchorId'] != null) requiredString(base, 'anchorId');
    _metrics(base['targets'], 'base targets');
    _count(base, 'failedSessions');
    const outcomes = {
      'advance',
      'hold',
      'failed',
      'deload',
      'blocked',
      'unknown',
      'review',
    };
    if (!outcomes.contains(j['outcome'])) invalid('Unknown block outcome.');
    requiredString(j, 'reason');
    final proposed = jsonObject(j['proposed'], 'proposed');
    checkKeys(proposed, {'targets', 'failedSessions'});
    _metrics(proposed['targets'], 'proposed targets');
    _count(proposed, 'failedSessions');
    final status = j['status'];
    if (!{'pending', 'accepted', 'declined'}.contains(status))
      invalid('Unknown block decision status.');
    if ((status == 'pending') != (j['resolvedAt'] == null) ||
        (status == 'pending') != (j['resolved'] == null))
      invalid('Only resolved block decisions carry a resolution.');
    if (status != 'pending') {
      parseInstant(j['resolvedAt'], 'resolvedAt');
      final resolved = jsonObject(j['resolved'], 'resolved');
      checkKeys(resolved, {'targets', 'failedSessions'});
      _metrics(resolved['targets'], 'resolved targets');
      _count(resolved, 'failedSessions');
    }
    if (status == 'accepted' && {'unknown', 'review'}.contains(j['outcome']))
      invalid('Unknown or review outcomes cannot be accepted.');
    return BlockProgressionDecision._(canonicalJson(j));
  }

  final String _json;
  Map<String, Object?> toJson() =>
      jsonObject(jsonDecode(_json), 'block progression decision');
  Map<String, Object?> get _j => toJson();
  String get id => _j['id']! as String;
  int get version => _j['version']! as int;
  int get sequence => _j['sequence']! as int;
  String get sessionId => _j['sessionId']! as String;
  String? get runId => _j['runId'] as String?;
  String get templateId => _j['templateId']! as String;
  String get amrapId => _j['amrapId']! as String;
  String get roundSlotId => _j['roundSlotId']! as String;
  String get status => _j['status']! as String;
  String get outcome => _j['outcome']! as String;
  DateTime? get resolvedAt => _j['resolvedAt'] == null
      ? null
      : parseInstant(_j['resolvedAt'], 'resolvedAt');
  Map<String, Object?> get source => jsonObject(_j['source'], 'source');
  String? get anchorId => jsonObject(_j['base'], 'base')['anchorId'] as String?;
  Metrics get resolvedTargets => metricsFromJson(
    jsonObject(jsonObject(_j['resolved'], 'resolved')['targets'], 'targets'),
  );
  int get resolvedFailures =>
      jsonObject(_j['resolved'], 'resolved')['failedSessions']! as int;
  String get trackKey => blockTrackKey(runId, templateId, amrapId, roundSlotId);
}

String blockDecisionId(String sessionId, String amrapId, String roundSlotId) =>
    '$sessionId/$amrapId/$roundSlotId';

String blockTrackKey(
  String? runId,
  String templateId,
  String amrapId,
  String roundSlotId,
) => canonicalJson([runId, templateId, amrapId, roundSlotId]);

/// The latest resolved decision of one track whose resolution is not after
/// [asOf]. Run, template, block and round slot scope it; nothing else does.
BlockProgressionDecision? latestBlockDecision(
  Iterable<BlockProgressionDecision> decisions,
  String trackKey, {
  DateTime? asOf,
}) {
  BlockProgressionDecision? best;
  for (final d in decisions) {
    final at = d.resolvedAt;
    if (at == null || d.trackKey != trackKey) continue;
    if (asOf != null && at.isAfter(asOf)) continue;
    if (best == null || d.sequence > best.sequence) best = d;
  }
  return best;
}
