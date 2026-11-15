import 'package:bodytmi_core/bodytmi_core.dart';

/// Read-only derived views over the pinned model, captured mass and raw sets.
/// Never feed estimates back into actuals, history or progression targets.
final class EffectiveMassService {
  const EffectiveMassService();
  Map<String, Object?> evaluate(TrainingSession session) => {
    'sessionId': session.id,
    'contentVersion': session.contentVersion,
    'estimates': [
      for (final set in session.sets)
        if (session.definition.slot(set.slotId).effectiveMass case final model?)
          {
            'setId': set.id,
            'slotId': set.slotId,
            'role': set.role,
            'ordinal': set.ordinal,
            'status': set.status.name,
            'suggested': _estimate(session, set, model, false),
            'actual': _estimate(session, set, model, true),
          },
    ],
  };

  Map<String, Object?> _estimate(
    TrainingSession session,
    TrainingSet set,
    EffectiveMassModel model,
    bool actual,
  ) {
    final metrics = actual ? set.actuals : set.suggested;
    final result = model.evaluate(
      metrics: metrics,
      bodyMass: session.bodyMassInputs[set.slotId],
      confirmed: !actual || set.status == SetStatus.completed,
    );
    return {
      ...result,
      'dependencyFingerprint': {
        'policy': EffectiveMassModel.policy,
        'sessionId': session.id,
        'sessionContentVersion': session.contentVersion,
        'setId': set.id,
        'setContentVersion': set.contentVersion,
        'basis': actual ? 'actual' : 'suggested',
        'model': model.toJson(),
        'inputs': result['inputs'],
      },
    };
  }
}
