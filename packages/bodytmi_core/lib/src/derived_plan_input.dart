import 'dart:convert';
import 'errors.dart';

final class DerivedPlanRef {
  const DerivedPlanRef(this.graphId, this.graphRevision, this.planId);
  factory DerivedPlanRef.fromJson(Object? input) {
    final json = jsonObject(input, 'derived plan reference');
    checkKeys(json, {'graphId', 'graphRevision', 'planId'});
    final revision = json['graphRevision'];
    if (revision is! int || revision < 1)
      invalid('Graph revision must be positive.');
    return DerivedPlanRef(
      identifier(json, 'graphId'),
      revision,
      identifier(json, 'planId'),
    );
  }
  final String graphId;
  final int graphRevision;
  final String planId;
  Map<String, Object?> toJson() => {
    'graphId': graphId,
    'graphRevision': graphRevision,
    'planId': planId,
  };
}

/// Frozen JSON inputs captured when a stored session starts.
final class DerivedPlanInput {
  DerivedPlanInput._(this.reference, this.snapshot);
  factory DerivedPlanInput.fromJson(Object? input) {
    final json = jsonObject(input, 'derived plan input');
    checkKeys(json, {'reference', 'snapshot'});
    final reference = DerivedPlanRef.fromJson(json['reference']);
    // Copy recursively so subsequent caller mutation cannot rewrite the snapshot.
    final copy = jsonDecode(
      jsonEncode(jsonObject(json['snapshot'], 'plan snapshot')),
    );
    return DerivedPlanInput._(
      reference,
      _freeze(jsonObject(copy, 'plan snapshot')),
    );
  }
  final DerivedPlanRef reference;
  final Map<String, Object?> snapshot;
  Map<String, Object?> toJson() => {
    'reference': reference.toJson(),
    'snapshot': snapshot,
  };
}

Map<String, Object?> _freeze(Map<String, Object?> value) => Map.unmodifiable({
  for (final entry in value.entries) entry.key: _freezeValue(entry.value),
});
Object? _freezeValue(Object? value) => switch (value) {
  Map<String, Object?>() => _freeze(value),
  List<Object?>() => List<Object?>.unmodifiable(value.map(_freezeValue)),
  _ => value,
};
