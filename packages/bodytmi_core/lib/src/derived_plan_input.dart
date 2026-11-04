import 'dart:convert';
import 'errors.dart';
import 'body_mass.dart';

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
  DerivedPlanInput._(this.reference, this.snapshot, this.bodyMassSources);
  factory DerivedPlanInput.fromJson(Object? input) {
    final json = jsonObject(input, 'derived plan input');
    checkKeys(json, {'reference', 'snapshot', 'bodyMassSources'});
    final reference = DerivedPlanRef.fromJson(json['reference']);
    // Copy recursively so subsequent caller mutation cannot rewrite the snapshot.
    final copy = jsonDecode(
      jsonEncode(jsonObject(json['snapshot'], 'plan snapshot')),
    );
    final rawSources = jsonObject(
      json['bodyMassSources'] ?? <String, Object?>{},
      'body mass sources',
    );
    final sources = <String, List<BodyMassMeasurement>>{};
    for (final entry in rawSources.entries) {
      final id = identifier({'sourceId': entry.key}, 'sourceId');
      if (entry.value is! List<Object?>)
        invalid('Body mass sources must be arrays.');
      final observations = [
        for (final value in entry.value as List<Object?>)
          BodyMassMeasurement.fromJson(value),
      ];
      if (observations.map((m) => m.id).toSet().length != observations.length)
        invalid('Duplicate captured body mass source.');
      sources[id] = List.unmodifiable(observations);
    }
    return DerivedPlanInput._(
      reference,
      _freeze(jsonObject(copy, 'plan snapshot')),
      Map.unmodifiable(sources),
    );
  }
  final DerivedPlanRef reference;
  final Map<String, Object?> snapshot;
  final Map<String, List<BodyMassMeasurement>> bodyMassSources;
  Map<String, Object?> toJson() => {
    'reference': reference.toJson(),
    'snapshot': snapshot,
    if (bodyMassSources.isNotEmpty)
      'bodyMassSources': {
        for (final entry in bodyMassSources.entries)
          entry.key: [for (final m in entry.value) m.toJson()],
      },
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
