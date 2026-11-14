import 'package:bodytmi_core/bodytmi_core.dart';
import 'canonical_json.dart';
import 'progression_anchor.dart';
import 'training_repository.dart';

const saveBackModes = {'session', 'save', 'increment'};

/// Explicit save-back of a session's intended prescription edits (policy
/// bodytmi-save-back/1, the Q35 choices). Only explicit target edits on
/// planned prescriptions (`manualTargets`, including explicitly carried
/// targets) are candidates; actual results are never copied. A candidate is
/// written as a per-effort target on its authored effort node, which requires
/// every occurrence of that node to agree. Progression-controlled metrics,
/// program prescription overrides and substituted sets stay session-only, so
/// a tracked source is never converted into a fixed value.
///
/// Modes: `session` keeps every change session-only and only reports the
/// diff; `save` publishes one revision when the prescription changed; and
/// `increment` always publishes a visible revision boundary. Publishing
/// requires the session's pinned revision to still be the template head,
/// unless `newTemplateId` explicitly saves a separate template.
final class SaveBackService {
  const SaveBackService(this.repository);
  final TrainingRepository repository;

  Future<Map<String, Object?>> saveBack(
    String sessionId, {
    required String mode,
    String? newTemplateId,
    bool confirm = false,
  }) => repository.transaction(() async {
    if (!saveBackModes.contains(mode))
      invalid('mode must be session, save or increment.');
    if (mode != 'session' && !confirm)
      invalid('Saving back to a template requires confirm:true.');
    if (newTemplateId != null) {
      identifier({'newTemplateId': newTemplateId}, 'newTemplateId');
      if (mode == 'session')
        invalid('newTemplateId only applies when saving back.');
    }
    final training = StoredTrainingService(repository);
    final session = await training.session(sessionId);
    final source = session.revision;
    final anchors = <ProgressionAnchor>[
      ...await repository.progressionDecisions(),
      ...await repository.progressionReconciliations(),
      ...await repository.linkRetirements(),
    ];
    bool controlled(String slotId, String role, String metric) => anchors.any(
      (a) =>
          a.templateId == source.definition.id &&
          a.slotId == slotId &&
          a.role == role &&
          a.controlledMetrics.contains(metric),
    );
    final plan = saveBackPlan(session, controlled: controlled);
    final head = await repository.revision(source.definition.id);
    final changed = plan.changed;
    final publish = mode == 'increment' || (mode == 'save' && changed);
    WorkoutRevision? published;
    if (publish) {
      if (newTemplateId != null) {
        if (await repository.revision(newTemplateId) != null)
          throw const BodyTmiException(
            'conflict',
            'newTemplateId already names a template.',
          );
        published = await training.publish(
          WorkoutDefinition.fromJson({
            ...plan.definition.toJson(),
            'id': newTemplateId,
          }),
          0,
        );
      } else {
        if (head!.number != source.number)
          throw BodyTmiException(
            'conflict',
            'Template ${source.definition.id} changed since this session\'s '
                'revision ${source.number} (head ${head.number}); reconcile '
                'by editing the template, or pass newTemplateId to save a '
                'separate template.',
          );
        published = await training.publish(plan.definition, source.number);
      }
    }
    return {
      'policy': 'bodytmi-save-back/1',
      'mode': mode,
      'sessionId': session.id,
      'source': {
        'templateId': source.definition.id,
        'revision': source.number,
        'headRevision': head?.number,
      },
      'changed': changed,
      'saved': plan.saved,
      'notSaved': plan.notSaved,
      'published': published == null
          ? null
          : {
              'templateId': published.definition.id,
              'revision': published.number,
            },
    };
  });
}

/// The pure save-back diff for one session.
({
  WorkoutDefinition definition,
  bool changed,
  List<Map<String, Object?>> saved,
  List<Map<String, Object?>> notSaved,
})
saveBackPlan(
  TrainingSession session, {
  bool Function(String slotId, String role, String metric)? controlled,
}) {
  final definition = session.revision.definition;
  final occurrences = [
    for (final o in definition.plan.occurrences())
      if (o.activity is Effort) o,
  ];
  // Effort node path → its occurrence IDs. A node path is its occurrence ID
  // with repeat iteration indices removed.
  String nodeKey(String occurrenceId) =>
      occurrenceId.replaceAll(RegExp(r'\[\d+\]'), '');
  final byNode = <String, List<ActivityOccurrence>>{};
  for (final o in occurrences)
    byNode.putIfAbsent(nodeKey(o.id), () => []).add(o);
  final overridden = {
    for (final record in session.prescriptionOverrides)
      for (final applied in record.applied) (applied.setId, record.metric),
  };
  final saved = <Map<String, Object?>>[];
  final notSaved = <Map<String, Object?>>[];
  // node key → metric → quantity
  final writes = <String, Map<String, Quantity>>{};
  for (final o in occurrences) {
    final set = session.set(o.id);
    for (final metric in (set.manualTargets.toList()..sort())) {
      final value = set.suggested[metric]!;
      String? reason;
      if (set.substitution != null) {
        reason = 'substituted';
      } else if (!definition.slot(set.slotId).targets.containsKey(metric)) {
        reason = 'no-authored-target';
      } else if (overridden.contains((set.id, metric))) {
        reason = 'program-override';
      } else if (controlled?.call(set.slotId, set.role, metric) ?? false) {
        reason = 'progression-controlled';
      } else {
        final siblings = byNode[nodeKey(o.id)]!;
        if (siblings.any(
          (s) =>
              session.set(s.id).suggested[metric]?.compareTo(value) != 0 ||
              session.set(s.id).suggested[metric]?.dimension != value.dimension,
        ))
          reason = 'repeated-occurrences-differ';
      }
      final entry = {
        'setId': set.id,
        'slotId': set.slotId,
        'role': set.role,
        'metric': metric,
        'value': value.toJson(),
      };
      if (reason != null) {
        notSaved.add({...entry, 'reason': reason});
        continue;
      }
      saved.add(entry);
      (writes[nodeKey(o.id)] ??= {})[metric] = value;
    }
  }
  final json = copyActivityJson(definition.toJson());
  void rewrite(Map<String, Object?> node, String prefix) {
    final path = prefix.isEmpty
        ? node['id']! as String
        : '$prefix/${node['id']}';
    if (node['type'] == 'effort') {
      final update = writes[path];
      if (update != null) {
        final targets = {
          ...(node['targets'] as Map<String, Object?>? ?? const {}),
          for (final e in update.entries)
            e.key: {
              'value': e.value.enteredValue,
              'unit': e.value.enteredUnit.name,
            },
        };
        node['targets'] = targets;
      }
      return;
    }
    if (node['children'] case final List<Object?> children) {
      for (final child in children)
        rewrite(child! as Map<String, Object?>, path);
    }
    if (node['child'] case final Map<String, Object?> child)
      rewrite(child, path);
  }

  rewrite(json['plan']! as Map<String, Object?>, '');
  final next = WorkoutDefinition.fromJson(json);
  return (
    definition: next,
    changed: canonicalJson(next.toJson()) != canonicalJson(definition.toJson()),
    saved: saved,
    notSaved: notSaved,
  );
}

Map<String, Object?> copyActivityJson(Map<String, Object?> json) =>
    _copy(json)! as Map<String, Object?>;

Object? _copy(Object? value) => switch (value) {
  Map<String, Object?> m => {for (final e in m.entries) e.key: _copy(e.value)},
  List<Object?> l => [for (final v in l) _copy(v)],
  _ => value,
};
