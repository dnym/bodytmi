import 'errors.dart';

/// One stored row of the energy and diet domain: a [kind] (for example
/// `maintenance-method`, `day-type`, `diet-cycle`), an [id] within it and a
/// revision or row [number]. The snapshot is decoded and validated per kind
/// by the application layer, so new record kinds need no new table.
final class DietRecord {
  DietRecord(this.kind, this.id, this.number, Map<String, Object?> snapshot)
    : snapshot = Map.unmodifiable(snapshot) {
    if (!RegExp(r'^[a-z][a-z0-9-]{0,63}$').hasMatch(kind))
      invalid('Invalid diet record kind.');
    identifier({'id': id}, 'id');
    if (number < 1) invalid('A diet record number is positive.');
  }
  factory DietRecord.fromJson(Object? input) {
    final j = jsonObject(input, 'diet record');
    checkKeys(j, {'kind', 'id', 'number', 'snapshot'});
    final number = j['number'];
    if (number is! int) invalid('number must be an integer.');
    return DietRecord(
      requiredString(j, 'kind'),
      requiredString(j, 'id'),
      number,
      jsonObject(j['snapshot'], 'snapshot'),
    );
  }
  final String kind, id;
  final int number;
  final Map<String, Object?> snapshot;
  String get key => '$kind\u0000$id\u0000$number';
  Map<String, Object?> toJson() => {
    'kind': kind,
    'id': id,
    'number': number,
    'snapshot': snapshot,
  };
}
