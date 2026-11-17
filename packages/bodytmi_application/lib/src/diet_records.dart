import 'package:bodytmi_core/bodytmi_core.dart';

/// Record kinds of the energy and diet domain and how each is decoded.
/// A decoder checks the snapshot and returns the identity it carries, which
/// must equal the row's (id, number).
typedef _Decoder = (String, int) Function(Map<String, Object?> snapshot);

final Map<String, _Decoder> _decoders = {
  'maintenance-method': (s) {
    final r = MaintenanceMethodRevision.fromJson(s);
    return ('maintenance', r.number);
  },
};

/// Known kinds, for error messages and tests.
Iterable<String> get dietRecordKinds => _decoders.keys;

/// Every row decodes under its kind with a consistent identity; numbered
/// kinds count from one without gaps per id.
void validateDietRecords(List<DietRecord> records) {
  final numbers = <String, List<int>>{};
  final seen = <String>{};
  for (final r in records) {
    if (!seen.add(r.key)) invalid('Duplicate diet record ${r.kind}/${r.id}.');
    final decode =
        _decoders[r.kind] ?? invalid('Unknown diet record kind ${r.kind}.');
    final (id, number) = decode(r.snapshot);
    if (id != r.id || number != r.number)
      invalid('Diet record ${r.kind}/${r.id} identity is inconsistent.');
    numbers.putIfAbsent('${r.kind}/${r.id}', () => []).add(r.number);
  }
  for (final e in numbers.entries) {
    validateNumbered(e.value, e.key);
  }
}
