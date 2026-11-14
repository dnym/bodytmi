import 'errors.dart';

/// One categorical lever of a slot, such as grip or hand count: a declared
/// set of identifier values and a default. Values have no implied harder
/// order; only declared progression edges may move between them.
final class CategoricalLever {
  CategoricalLever._(this.values, this.defaultValue);
  factory CategoricalLever.fromJson(Object? input, String lever) {
    final j = jsonObject(input, 'categorical lever $lever');
    checkKeys(j, {'values', 'default'});
    final raw = jsonList(j, 'values');
    if (raw.length < 2 || raw.length > 64)
      invalid('Categorical lever $lever needs 2–64 values.');
    final values = <String>[];
    for (final value in raw) {
      if (value is! String) invalid('Categorical values must be identifiers.');
      identifier({'value': value}, 'value');
      if (values.contains(value))
        invalid('Categorical lever $lever repeats value $value.');
      values.add(value);
    }
    final fallback = requiredString(j, 'default');
    if (!values.contains(fallback))
      invalid('Categorical lever $lever default must be one of its values.');
    return CategoricalLever._(List.unmodifiable(values), fallback);
  }
  final List<String> values;
  final String defaultValue;
  Map<String, Object?> toJson() => {'values': values, 'default': defaultValue};
}

/// Parses a slot's `categories` map (1–16 levers).
Map<String, CategoricalLever> categoricalLeversFromJson(Object? input) {
  final j = jsonObject(input, 'categories');
  if (j.isEmpty || j.length > 16)
    invalid('categories must declare 1–16 categorical levers.');
  return Map.unmodifiable({
    for (final key in (j.keys.toList()..sort()))
      identifier({'lever': key}, 'lever'): CategoricalLever.fromJson(
        j[key],
        key,
      ),
  });
}

/// Parses a nonempty `{lever: value}` settings map without slot context.
Map<String, String> categoricalSettingsFromJson(Object? input, String field) {
  final j = jsonObject(input, field);
  if (j.isEmpty || j.length > 16) invalid('$field must set 1–16 levers.');
  return Map.unmodifiable({
    for (final key in (j.keys.toList()..sort()))
      identifier({'lever': key}, 'lever'): identifier(j, key),
  });
}

/// Parses performed settings for recording; an empty map clears the record.
Map<String, String> performedSettingsFromJson(Object? input) {
  final j = jsonObject(input, 'settings');
  return j.isEmpty ? const {} : categoricalSettingsFromJson(j, 'settings');
}

/// Checks settings name declared levers and values of [levers].
void validateCategoricalSettings(
  Map<String, String> settings,
  Map<String, CategoricalLever> levers,
  String context,
) {
  for (final e in settings.entries) {
    final lever = levers[e.key];
    if (lever == null)
      invalid('$context sets undeclared categorical lever ${e.key}.');
    if (!lever.values.contains(e.value))
      invalid('$context sets ${e.key} to undeclared value ${e.value}.');
  }
}

Map<String, String> sortedSettings(Map<String, String> settings) =>
    Map.unmodifiable({
      for (final key in (settings.keys.toList()..sort())) key: settings[key]!,
    });
