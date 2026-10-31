import 'dart:convert';

/// Deterministic v1 encoding: object keys sorted by Dart String.compareTo,
/// arrays retain their order, and scalar encoding follows Dart jsonEncode.
/// TrainingArchive sorts its record collections; set/activity order is semantic.
String canonicalJson(Object? value) {
  Object? ordered(Object? item) {
    if (item is Map<String, Object?>) {
      final keys = item.keys.toList()..sort();
      return {for (final key in keys) key: ordered(item[key])};
    }
    if (item is List<Object?>)
      return [for (final child in item) ordered(child)];
    return item;
  }

  return jsonEncode(ordered(value));
}
