import 'package:bodytmi_core/bodytmi_core.dart';
import 'progression_evaluation.dart';

/// Evaluates one role without creating a decision or finalizing the session.
final class RoleProgressionPreview {
  const RoleProgressionPreview();

  Map<String, Object?> evaluate({
    required TrainingSession session,
    required String slotId,
    required Map<String, Object?> rule,
    String role = 'work',
    String ruleType = 'double',
    int failedSessions = 0,
    int cursor = 0,
  }) {
    identifier({'id': slotId}, 'id');
    if (!{'work', 'warmup', 'backoff', 'drop'}.contains(role)) {
      invalid('Unknown effort role.');
    }
    if (failedSessions < 0 ||
        cursor < 0 ||
        !{'double', 'threshold', 'ordinal'}.contains(ruleType) ||
        (ruleType != 'threshold' && cursor != 0)) {
      invalid('Invalid progression preview state or rule type.');
    }
    final sets = session.sets
        .where((s) => s.slotId == slotId && s.role == role)
        .toList();
    if (sets.isEmpty)
      invalid('Progression preview needs sets in the selected slot and role.');
    final ProgressionEvaluation proposal;
    if (ruleType == 'threshold') {
      proposal = ProgressionEvaluation.threshold(
        ThresholdRule.fromJson(rule),
        sets,
        failedSessions,
        cursor,
      );
    } else if (ruleType == 'ordinal') {
      proposal = ProgressionEvaluation.ordinal(
        OrdinalRule.fromJson(rule),
        sets,
        failedSessions,
      );
    } else {
      proposal = ProgressionEvaluation.double(
        DoubleProgressionRule.fromJson(rule).evaluate(
          currentSets: [for (final set in sets) set.suggested],
          results: [
            for (final set in sets)
              set.eligibleForPerformance ? set.actuals : null,
          ],
          failedSessions: failedSessions,
        ),
      );
    }
    return {
      'policy': session.status == SessionStatus.active
          ? 'bodytmi-role-progression-preview/2'
          : 'bodytmi-role-progression-preview/1',
      'sessionId': session.id,
      'sessionContentVersion': session.contentVersion,
      if (session.status == SessionStatus.active) ...{
        'sessionStatus': 'active',
        'finalizationRequired': true,
      },
      'slotId': slotId,
      'role': role,
      'setIds': [for (final set in sets) set.id],
      'ruleType': ruleType,
      'rule': rule,
      'state': {
        'failedSessions': failedSessions,
        if (ruleType == 'threshold') 'cursor': cursor,
      },
      'proposal': proposal.toJson(),
    };
  }
}
