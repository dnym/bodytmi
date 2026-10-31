class BodyTmiException implements Exception {
  const BodyTmiException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => '$code: $message';
}

Never invalid(String message) => throw BodyTmiException('validation', message);

Map<String, Object?> jsonObject(Object? value, String label) {
  if (value is! Map<String, Object?>) invalid('$label must be an object.');
  return value;
}

String requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    invalid('$key must be a nonempty string.');
  }
  return value;
}

String identifier(Map<String, Object?> json, String key) {
  final value = requiredString(json, key);
  if (!RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(value)) {
    invalid('$key must contain 1–100 letters, digits, underscores or hyphens.');
  }
  return value;
}

List<Object?> jsonList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List<Object?>) invalid('$key must be an array.');
  return value;
}

void checkKeys(Map<String, Object?> json, Set<String> allowed) {
  final unknown = json.keys.toSet().difference(allowed);
  if (unknown.isNotEmpty) invalid('Unknown fields: ${unknown.join(', ')}.');
}
