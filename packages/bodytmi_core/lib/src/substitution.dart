import 'errors.dart';
import 'quantity.dart';

/// The composition actually performed instead of a slot's authored one.
/// Placement, grouping, role and purpose stay with the slot.
final class SubstituteComposition {
  const SubstituteComposition._(
    this.exerciseId,
    this.implementation,
    this.equipmentId,
    this.setupNote,
  );

  factory SubstituteComposition.fromJson(Object? input) {
    final j = jsonObject(input, 'substitute composition');
    checkKeys(j, {'exercise', 'implementation', 'equipment', 'setupNote'});
    final note = j.containsKey('setupNote')
        ? requiredString(j, 'setupNote')
        : null;
    if (note != null && note.length > 4000)
      invalid('setupNote must be at most 4000 characters.');
    return SubstituteComposition._(
      identifier(j, 'exercise'),
      identifier(j, 'implementation'),
      j.containsKey('equipment') ? identifier(j, 'equipment') : null,
      note,
    );
  }

  final String exerciseId, implementation;
  final String? equipmentId, setupNote;

  bool sameAs({
    required String exerciseId,
    required String implementation,
    String? equipmentId,
    String? setupNote,
  }) =>
      this.exerciseId == exerciseId &&
      this.implementation == implementation &&
      this.equipmentId == equipmentId &&
      this.setupNote == setupNote;

  @override
  bool operator ==(Object other) =>
      other is SubstituteComposition &&
      other.sameAs(
        exerciseId: exerciseId,
        implementation: implementation,
        equipmentId: equipmentId,
        setupNote: setupNote,
      );

  @override
  int get hashCode =>
      Object.hash(exerciseId, implementation, equipmentId, setupNote);

  Map<String, Object?> toJson() => {
    'exercise': exerciseId,
    'implementation': implementation,
    if (equipmentId != null) 'equipment': equipmentId,
    if (setupNote != null) 'setupNote': setupNote,
  };
}

const substitutionTargetSources = {'keep', 'history', 'explicit', 'unresolved'};

/// How one target metric of a substituted set was resolved. A replacement
/// never inherits the original implementation's value unless `keep` was
/// explicitly chosen; with no history or explicit value it stays unresolved.
final class SubstitutionTarget {
  const SubstitutionTarget._(
    this.source,
    this.dimension,
    this.historySessionId,
    this.historySetId,
    this.historyContentVersion,
    this.reason,
  );

  factory SubstitutionTarget.fromJson(Object? input) {
    final j = jsonObject(input, 'substitution target');
    checkKeys(j, {'source', 'dimension', 'history', 'reason'});
    final source = requiredString(j, 'source');
    if (!substitutionTargetSources.contains(source))
      invalid('Unknown substitution target source.');
    final dimension = Dimension.values
        .where((d) => d.name == j['dimension'])
        .firstOrNull;
    if (dimension == null) invalid('Substitution target needs a dimension.');
    String? sessionId, setId, reason;
    int? version;
    if (source == 'history') {
      final h = jsonObject(j['history'], 'history');
      checkKeys(h, {'sessionId', 'setId', 'contentVersion'});
      sessionId = identifier(h, 'sessionId');
      setId = requiredString(h, 'setId');
      final v = h['contentVersion'];
      if (v is! int || v < 1) invalid('contentVersion must be positive.');
      version = v;
    } else if (j.containsKey('history')) {
      invalid('Only history targets carry history provenance.');
    }
    if (source == 'unresolved') {
      reason = requiredString(j, 'reason');
    } else if (j.containsKey('reason')) {
      invalid('Only unresolved targets carry a reason.');
    }
    return SubstitutionTarget._(
      source,
      dimension,
      sessionId,
      setId,
      version,
      reason,
    );
  }

  factory SubstitutionTarget.keep(Dimension d) =>
      SubstitutionTarget._('keep', d, null, null, null, null);
  factory SubstitutionTarget.explicit(Dimension d) =>
      SubstitutionTarget._('explicit', d, null, null, null, null);
  factory SubstitutionTarget.history(
    Dimension d,
    String sessionId,
    String setId,
    int contentVersion,
  ) => SubstitutionTarget._(
    'history',
    d,
    sessionId,
    setId,
    contentVersion,
    null,
  );
  factory SubstitutionTarget.unresolved(Dimension d, String reason) =>
      SubstitutionTarget._('unresolved', d, null, null, null, reason);

  final String source;
  final Dimension dimension;
  final String? historySessionId, historySetId, reason;
  final int? historyContentVersion;

  Map<String, Object?> toJson() => {
    'source': source,
    'dimension': dimension.name,
    if (source == 'history')
      'history': {
        'sessionId': historySessionId,
        'setId': historySetId,
        'contentVersion': historyContentVersion,
      },
    if (reason != null) 'reason': reason,
  };
}

/// A temporary substitution frozen on one planned set, with the set's prior
/// planned state so the original can be restored exactly.
final class SetSubstitution {
  SetSubstitution({
    required this.composition,
    required this.scope,
    required Map<String, SubstitutionTarget> targets,
    required Metrics originalSuggested,
    required Map<String, Object?> originalSources,
    required Set<String> originalManualTargets,
  }) : targets = Map.unmodifiable(targets),
       originalSuggested = Map.unmodifiable(originalSuggested),
       originalSources = Map.unmodifiable(originalSources),
       originalManualTargets = Set.unmodifiable(originalManualTargets) {
    if (!{'occurrence', 'remaining'}.contains(scope))
      invalid('Substitution scope must be occurrence or remaining.');
    if (this.targets.keys.toSet().difference(originalSuggested.keys.toSet())
        case final extra when extra.isNotEmpty)
      invalid('Substitution targets name metrics the set did not plan.');
    if (originalSuggested.keys.toSet().difference(this.targets.keys.toSet())
        case final missing when missing.isNotEmpty)
      invalid('Every planned target needs a substitution source.');
    for (final entry in this.targets.entries) {
      if (entry.value.dimension != originalSuggested[entry.key]!.dimension)
        invalid('Substitution target ${entry.key} changed dimension.');
    }
  }

  factory SetSubstitution.fromJson(Object? input) {
    final j = jsonObject(input, 'substitution');
    checkKeys(j, {'composition', 'scope', 'targets', 'original'});
    final original = jsonObject(j['original'], 'original');
    checkKeys(original, {'suggested', 'sources', 'manualTargets'});
    final manual = <String>{};
    for (final m in (original['manualTargets'] as List<Object?>? ?? const [])) {
      if (m is! String || !manual.add(m))
        invalid('Invalid original manual targets.');
    }
    return SetSubstitution(
      composition: SubstituteComposition.fromJson(j['composition']),
      scope: requiredString(j, 'scope'),
      targets: {
        for (final e in jsonObject(j['targets'], 'targets').entries)
          identifier({'metric': e.key}, 'metric'): SubstitutionTarget.fromJson(
            e.value,
          ),
      },
      originalSuggested: metricsFromJson(original['suggested']),
      originalSources: jsonObject(original['sources'] ?? {}, 'sources'),
      originalManualTargets: manual,
    );
  }

  final SubstituteComposition composition;
  final String scope;
  final Map<String, SubstitutionTarget> targets;
  final Metrics originalSuggested;
  final Map<String, Object?> originalSources;
  final Set<String> originalManualTargets;

  Set<String> get unresolved => {
    for (final e in targets.entries)
      if (e.value.source == 'unresolved') e.key,
  };

  Map<String, Object?> toJson() => {
    'composition': composition.toJson(),
    'scope': scope,
    'targets': {
      for (final key in (targets.keys.toList()..sort()))
        key: targets[key]!.toJson(),
    },
    'original': {
      'suggested': metricsToJson(originalSuggested),
      'sources': originalSources,
      if (originalManualTargets.isNotEmpty)
        'manualTargets': (originalManualTargets.toList()..sort()),
    },
  };
}
