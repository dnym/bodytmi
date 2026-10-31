/// Vector-wide candidate explanation. Ordinals refer to the target set vector,
/// excluding warmups in stored progression.
final class BlockedLeverSet {
  const BlockedLeverSet(this.ordinal, this.reason);
  final int ordinal;
  final String reason;
  Map<String, Object?> toJson() => {'ordinal': ordinal, 'reason': reason};
}

final class LeverCandidate {
  LeverCandidate(this.metric, List<BlockedLeverSet> blockedSets)
    : blockedSets = List.unmodifiable(blockedSets);
  final String metric;
  final List<BlockedLeverSet> blockedSets;
  Map<String, Object?> toJson() => {
    'metric': metric,
    'outcome': blockedSets.isEmpty ? 'applicable' : 'blocked',
    'blockedSets': [for (final set in blockedSets) set.toJson()],
  };
}

final class LeverSelection {
  LeverSelection(
    this.mode,
    this.selectedMetric,
    List<LeverCandidate> candidates,
  ) : candidates = List.unmodifiable(candidates);
  final String mode;
  final String? selectedMetric;
  final List<LeverCandidate> candidates;
  Map<String, Object?> toJson() => {
    'mode': mode,
    'selectedMetric': selectedMetric,
    'candidates': [for (final candidate in candidates) candidate.toJson()],
  };
}
