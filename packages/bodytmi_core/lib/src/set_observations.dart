import 'errors.dart';
import 'quantity.dart';

/// Optional reports about a set, separate from numeric exercise metrics.
/// RPE's declared scale is retained; RIR is never inferred from RPE or vice versa.
final class SetObservations {
  SetObservations._(
    this.rpe,
    this.rpeScale,
    this.rir,
    this.notes,
    this.terminationReason,
  );

  factory SetObservations.fromJson(Object? input) {
    final j = jsonObject(input, 'observations');
    checkKeys(j, {'rpe', 'rir', 'notes', 'terminationReason'});
    Decimal? rpe;
    String? scale;
    if (j.containsKey('rpe')) {
      final rating = jsonObject(j['rpe'], 'rpe');
      checkKeys(rating, {'value', 'scale'});
      scale = requiredString(rating, 'scale');
      if (!{'0-10', '6-20'}.contains(scale))
        invalid('RPE needs an explicit 0-10 or 6-20 scale.');
      rpe = Decimal.parse(requiredString(rating, 'value'));
      final minimum = Decimal.parse(scale == '0-10' ? '0' : '6');
      final maximum = Decimal.parse(scale == '0-10' ? '10' : '20');
      if (rpe.compareTo(minimum) < 0 || rpe.compareTo(maximum) > 0)
        invalid('RPE must be within its declared scale.');
    }
    final rir = j.containsKey('rir')
        ? Decimal.parse(requiredString(j, 'rir'))
        : null;
    if (rir != null && rir.compareTo(Decimal.zero) < 0)
      invalid('RIR cannot be negative.');
    final notes = j.containsKey('notes') ? requiredString(j, 'notes') : null;
    if (notes != null && notes.length > 4000)
      invalid('Set notes must be at most 4000 characters.');
    final reason = j.containsKey('terminationReason')
        ? requiredString(j, 'terminationReason')
        : null;
    if (reason != null &&
        !{
          'target-reached',
          'max-effort',
          'grip-failure',
          'pain-discomfort',
          'interrupted',
          'other',
        }.contains(reason))
      invalid('Invalid termination reason.');
    return SetObservations._(rpe, scale, rir, notes, reason);
  }

  final Decimal? rpe, rir;
  final String? rpeScale, notes, terminationReason;
  bool get isEmpty =>
      rpe == null && rir == null && notes == null && terminationReason == null;
  bool get interrupted => terminationReason == 'interrupted';

  void validateStatus(String status) {
    if (status != 'completed' && (rpe != null || rir != null))
      invalid('RPE and RIR require confirmed completed actuals.');
    if (status == 'planned' && terminationReason != null)
      invalid('A planned set cannot have a termination reason.');
  }

  /// Skipping removes reports of performed effort, retaining the execution note.
  SetObservations get notesOnly =>
      SetObservations._(null, null, null, notes, null);

  Map<String, Object?> toJson() => {
    if (rpe != null) 'rpe': {'value': rpe.toString(), 'scale': rpeScale},
    if (rir != null) 'rir': rir.toString(),
    if (notes != null) 'notes': notes,
    if (terminationReason != null) 'terminationReason': terminationReason,
  };
}
