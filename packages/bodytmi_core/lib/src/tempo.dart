import 'errors.dart';

/// A repeating effort cue pattern, never an observation of performed reps.
final class TempoPlan {
  TempoPlan._(this.phases, this.cycleMilliseconds);
  factory TempoPlan.fromJson(Object? input) {
    final j = jsonObject(input, 'tempo');
    checkKeys(j, {'phases'});
    final rows = jsonList(j, 'phases');
    if (rows.isEmpty || rows.length > 16)
      invalid('Tempo requires 1–16 phases.');
    final phases = <TempoPhase>[];
    final ids = <String>{};
    var cycle = 0;
    for (final row in rows) {
      final phase = jsonObject(row, 'tempo phase');
      checkKeys(phase, {'id', 'milliseconds'});
      final id = identifier(phase, 'id');
      final ms = phase['milliseconds'];
      if (!ids.add(id) || ms is! int || ms < 1 || ms > 86400000)
        invalid(
          'Tempo phases need distinct IDs and positive whole milliseconds.',
        );
      cycle += ms;
      phases.add(TempoPhase._(id, ms));
    }
    if (cycle > 86400000) invalid('Tempo cycle exceeds 24 hours.');
    return TempoPlan._(List.unmodifiable(phases), cycle);
  }
  final List<TempoPhase> phases;
  final int cycleMilliseconds;

  /// Arithmetic lookup bounds work by phase count, even after a delayed sample.
  TempoPosition position(int effortMilliseconds) {
    if (effortMilliseconds < 0 || effortMilliseconds > 604800000)
      invalid('Tempo effort elapsed is outside the timing limit.');
    final cycle = effortMilliseconds ~/ cycleMilliseconds;
    var remaining = effortMilliseconds % cycleMilliseconds;
    for (var i = 0; i < phases.length; i++) {
      final phase = phases[i];
      if (remaining < phase.milliseconds)
        return TempoPosition._(
          cycle,
          i,
          phase.id,
          remaining,
          phase.milliseconds - remaining,
          effortMilliseconds - remaining,
        );
      remaining -= phase.milliseconds;
    }
    throw StateError('Tempo position exceeds its cycle.');
  }

  Map<String, Object?> toJson() => {
    'phases': [for (final phase in phases) phase.toJson()],
  };
}

final class TempoPhase {
  const TempoPhase._(this.id, this.milliseconds);
  final String id;
  final int milliseconds;
  Map<String, Object?> toJson() => {'id': id, 'milliseconds': milliseconds};
}

final class TempoPosition {
  const TempoPosition._(
    this.cycleIndex,
    this.phaseIndex,
    this.phaseId,
    this.phaseElapsedMilliseconds,
    this.phaseRemainingMilliseconds,
    this.boundaryEffortMilliseconds,
  );
  final String phaseId;
  final int cycleIndex,
      phaseIndex,
      phaseElapsedMilliseconds,
      phaseRemainingMilliseconds,
      boundaryEffortMilliseconds;
  Map<String, Object?> toJson() => {
    'cycleIndex': cycleIndex,
    'phaseIndex': phaseIndex,
    'phaseId': phaseId,
    'phaseElapsedMilliseconds': phaseElapsedMilliseconds,
    'phaseRemainingMilliseconds': phaseRemainingMilliseconds,
    'boundaryEffortMilliseconds': boundaryEffortMilliseconds,
  };
}
