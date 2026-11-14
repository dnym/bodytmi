import 'double_progression.dart';
import 'errors.dart';
import 'ordinal_progression.dart';
import 'progression.dart';

/// Validate one stored progression rule payload for its declared type.
/// This is the single shared payload gate used by presets and stored rules.
void validateProgressionRulePayload(
  String ruleType,
  Map<String, Object?> rule,
) {
  if (ruleType == 'double') {
    DoubleProgressionRule.fromJson(rule);
  } else if (ruleType == 'threshold') {
    ThresholdRule.fromJson(rule);
  } else if (ruleType == 'ordinal') {
    OrdinalRule.fromJson(rule);
  } else {
    invalid('Unknown stored progression rule type.');
  }
}

/// Reusable named progression rule definition. A preset accelerates
/// consistent authoring; it prescribes nothing by itself and records no
/// application. Consumption always resolves an explicit revision.
final class ProgressionPreset {
  ProgressionPreset._(this.id, this.name, this.notes, this.ruleType, this.rule);

  factory ProgressionPreset.fromJson(Object? input) {
    final json = jsonObject(input, 'progression preset');
    checkKeys(json, {'id', 'name', 'notes', 'ruleType', 'rule'});
    final name = json['name'];
    if (name != null && (name is! String || name.trim().isEmpty))
      invalid('Progression preset name must be a nonempty string.');
    if (name is String && name.length > 200)
      invalid('Progression preset name exceeds 200 characters.');
    final notes = json['notes'];
    if (notes != null && (notes is! String || notes.trim().isEmpty))
      invalid('Progression preset notes must be a nonempty string.');
    if (notes is String && notes.length > 4000)
      invalid('Progression preset notes exceed 4000 characters.');
    final ruleType = requiredString(json, 'ruleType');
    final rule = jsonObject(json['rule'], 'progression preset rule');
    validateProgressionRulePayload(ruleType, rule);
    return ProgressionPreset._(
      identifier(json, 'id'),
      name as String?,
      notes as String?,
      ruleType,
      rule,
    );
  }

  final String id;
  final String? name;
  final String? notes;
  final String ruleType;
  final Map<String, Object?> rule;

  Map<String, Object?> toJson() => {
    'id': id,
    if (name != null) 'name': name,
    if (notes != null) 'notes': notes,
    'ruleType': ruleType,
    'rule': rule,
  };
}

final class ProgressionPresetRevision {
  ProgressionPresetRevision._(this.number, this.preset);

  factory ProgressionPresetRevision.publish(
    ProgressionPreset preset, {
    ProgressionPresetRevision? previous,
  }) {
    if (previous != null && previous.preset.id != preset.id)
      invalid('Progression preset revision must retain identity.');
    return ProgressionPresetRevision._((previous?.number ?? 0) + 1, preset);
  }

  factory ProgressionPresetRevision.fromJson(Object? input) {
    final json = jsonObject(input, 'progression preset revision');
    checkKeys(json, {'schemaVersion', 'revision', 'preset'});
    final revision = json['revision'];
    if (json['schemaVersion'] != 1 || revision is! int || revision < 1)
      invalid('Invalid progression preset revision.');
    return ProgressionPresetRevision._(
      revision,
      ProgressionPreset.fromJson(json['preset']),
    );
  }

  final int number;
  final ProgressionPreset preset;

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'revision': number,
    'preset': preset.toJson(),
  };
}

void validateProgressionPresetRevisions(
  List<ProgressionPresetRevision> revisions,
) {
  final numbers = <String, Set<int>>{};
  for (final revision in revisions)
    if (!numbers
        .putIfAbsent(revision.preset.id, () => <int>{})
        .add(revision.number))
      invalid('Duplicate progression preset revision.');
  for (final versions in numbers.values)
    if (versions.any((n) => n > versions.length))
      invalid('Progression preset revisions must start at one with no gaps.');
}
