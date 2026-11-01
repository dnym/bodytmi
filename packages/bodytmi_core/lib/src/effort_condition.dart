import 'errors.dart';
import 'quantity.dart';
import 'set_observations.dart';

/// An explicitly authored range for a reported rating, never a unit conversion.
final class EffortRange {
  EffortRange._(this.minimum, this.maximum, this.scale);
  factory EffortRange.fromJson(Object? input, {required bool rpe}) {
    final j = jsonObject(input, 'effort range');
    checkKeys(j, {'minimum', 'maximum', if (rpe) 'scale'});
    if (!j.containsKey('minimum') && !j.containsKey('maximum'))
      invalid('An effort range needs a minimum or maximum.');
    final scale = rpe ? requiredString(j, 'scale') : null;
    if (rpe && !{'0-10', '6-20'}.contains(scale))
      invalid('An RPE condition needs an explicit 0-10 or 6-20 scale.');
    final minimum = j.containsKey('minimum')
        ? Decimal.parse(requiredString(j, 'minimum'))
        : null;
    final maximum = j.containsKey('maximum')
        ? Decimal.parse(requiredString(j, 'maximum'))
        : null;
    for (final bound in [minimum, maximum]) {
      if (bound == null) continue;
      if (bound.compareTo(Decimal.parse(scale == '6-20' ? '6' : '0')) < 0 ||
          (rpe &&
              bound.compareTo(Decimal.parse(scale == '6-20' ? '20' : '10')) >
                  0))
        invalid('An effort bound is outside its declared range.');
    }
    if (minimum != null && maximum != null && minimum.compareTo(maximum) > 0)
      invalid('Effort minimum cannot exceed maximum.');
    return EffortRange._(minimum, maximum, scale);
  }
  final Decimal? minimum, maximum;
  final String? scale;
  bool contains(Decimal value) =>
      (minimum == null || value.compareTo(minimum!) >= 0) &&
      (maximum == null || value.compareTo(maximum!) <= 0);
  Map<String, Object?> toJson() => {
    if (scale != null) 'scale': scale,
    if (minimum != null) 'minimum': minimum.toString(),
    if (maximum != null) 'maximum': maximum.toString(),
  };
}

/// All configured ratings on every required result must qualify to advance.
/// This is an advancement gate; it never creates a failed exposure or deload.
final class AdvancementEffort {
  AdvancementEffort._(this.rpe, this.rir);
  factory AdvancementEffort.fromJson(Object? input) {
    final j = jsonObject(input, 'advancementEffort');
    checkKeys(j, {'rpe', 'rir'});
    if (j.isEmpty) invalid('advancementEffort needs RPE or RIR bounds.');
    return AdvancementEffort._(
      j.containsKey('rpe') ? EffortRange.fromJson(j['rpe'], rpe: true) : null,
      j.containsKey('rir') ? EffortRange.fromJson(j['rir'], rpe: false) : null,
    );
  }
  final EffortRange? rpe, rir;
  Map<String, Object?> toJson() => {
    if (rpe != null) 'rpe': rpe!.toJson(),
    if (rir != null) 'rir': rir!.toJson(),
  };

  EffortAssessment assess(
    List<SetObservations?> observations,
    List<bool> confirmed,
  ) {
    if (observations.length != confirmed.length || observations.length > 10000)
      invalid('Effort observations must match the required result vector.');
    final results = <Map<String, Object?>>[];
    var unknown = observations.isEmpty;
    var meets = true;
    for (var i = 0; i < observations.length; i++) {
      final observation = observations[i];
      final row = <String, Object?>{'ordinal': i};
      for (final key in ['rpe', 'rir']) {
        final range = key == 'rpe' ? rpe : rir;
        if (range == null) continue;
        final value = key == 'rpe' ? observation?.rpe : observation?.rir;
        final reason = !confirmed[i] || (observation?.interrupted ?? false)
            ? 'unconfirmed-or-interrupted'
            : value == null
            ? 'missing-rating'
            : key == 'rpe' && observation!.rpeScale != range.scale
            ? 'rpe-scale-mismatch'
            : null;
        final qualifies = reason == null ? range.contains(value!) : null;
        if (qualifies == null) unknown = true;
        if (qualifies == false) meets = false;
        row[key] = Map<String, Object?>.unmodifiable({
          'value': value?.toString(),
          if (key == 'rpe') 'scale': observation?.rpeScale,
          'qualifies': qualifies,
          if (reason != null) 'reason': reason,
        });
      }
      results.add(Map.unmodifiable(row));
    }
    return EffortAssessment._(
      this,
      results,
      unknown
          ? 'unknown'
          : meets
          ? 'met'
          : 'not-met',
    );
  }
}

final class EffortAssessment {
  EffortAssessment._(
    this.condition,
    List<Map<String, Object?>> results,
    this.status,
  ) : results = List.unmodifiable(results);
  final AdvancementEffort condition;
  final List<Map<String, Object?>> results;
  final String status;
  Map<String, Object?> toJson() => {
    'scope': 'all-required-results',
    'purpose': 'advancement-only',
    'condition': condition.toJson(),
    'results': results,
    'status': status,
  };
}
