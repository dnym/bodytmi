import 'errors.dart';

final _tag = RegExp(r'^[a-z]{2,3}(-[A-Za-z]{4})?(-([A-Z]{2}|[0-9]{3}))?$');

/// Validates a canonical BCP 47 language tag of language, optional script and
/// optional region (e.g. `sv`, `sv-SE`, `sr-Latn-RS`). Private-use and
/// extension subtags are not accepted for catalog labels.
String catalogLocaleTag(Object? value, String field) {
  if (value is! String || !_tag.hasMatch(value))
    invalid('$field must be a canonical language tag such as sv or sv-SE.');
  final parts = value.split('-');
  if (parts.length > 1 && parts[1].length == 4) {
    final script = parts[1];
    if (script != script[0].toUpperCase() + script.substring(1).toLowerCase())
      invalid('$field script subtag must be title case, e.g. Latn.');
  }
  return value;
}

/// Normalizes text for catalog search: lower case and collapsed whitespace.
/// Letters with diacritics stay distinct letters (Swedish å/ä/ö are not a, o),
/// so no accent folding is applied.
String catalogSearchKey(String text) =>
    text.toLowerCase().trim().split(RegExp(r'\s+')).join(' ');

/// One locale's display name and search aliases.
final class CatalogLabel {
  CatalogLabel._(this.name, this.aliases);
  factory CatalogLabel.fromJson(Object? input, String locale) {
    final j = jsonObject(input, 'label $locale');
    checkKeys(j, {'name', 'aliases'});
    final name = j['name'];
    if (name != null && !_text(name))
      invalid(
        'Label $locale name must be a nonempty string of at most 200 characters.',
      );
    final aliases = <String>[];
    if (j.containsKey('aliases')) {
      final raw = jsonList(j, 'aliases');
      if (raw.isEmpty || raw.length > 32)
        invalid('Label $locale aliases must list 1–32 entries.');
      final seen = <String>{};
      for (final alias in raw) {
        if (!_text(alias))
          invalid(
            'Label $locale aliases must be nonempty strings of at most 200 characters.',
          );
        if (!seen.add(catalogSearchKey(alias as String)))
          invalid('Label $locale repeats an alias.');
        aliases.add(alias);
      }
    }
    if (name == null && aliases.isEmpty)
      invalid('Label $locale needs a name or aliases.');
    return CatalogLabel._(name as String?, List.unmodifiable(aliases));
  }
  final String? name;
  final List<String> aliases;
  Map<String, Object?> toJson() => {
    if (name != null) 'name': name,
    if (aliases.isNotEmpty) 'aliases': aliases,
  };
}

bool _text(Object? v) => v is String && v.trim().isNotEmpty && v.length <= 200;

/// Optional per-locale labels of one catalog entry. The root `name` stays the
/// locale-neutral fallback; labels are presentation data and never identity.
final class CatalogLabels {
  const CatalogLabels._(this.entries);
  static const empty = CatalogLabels._({});

  factory CatalogLabels.fromJson(Object? input) {
    final j = jsonObject(input, 'labels');
    if (j.isEmpty || j.length > 64)
      invalid('labels must declare 1–64 locales.');
    final lowered = <String>{};
    final entries = <String, CatalogLabel>{};
    for (final key in (j.keys.toList()..sort())) {
      catalogLocaleTag(key, 'labels locale');
      if (!lowered.add(key.toLowerCase()))
        invalid('labels repeats locale $key.');
      entries[key] = CatalogLabel.fromJson(j[key], key);
    }
    return CatalogLabels._(Map.unmodifiable(entries));
  }

  final Map<String, CatalogLabel> entries;
  bool get isEmpty => entries.isEmpty;

  /// The label locales consulted for [locale]: exact, then language only.
  List<String> chain(String locale) {
    final language = locale.split('-').first;
    return [
      if (entries.containsKey(locale)) locale,
      if (language != locale && entries.containsKey(language)) language,
    ];
  }

  /// Display name for [locale]: exact label, then language-only label, then
  /// [rootName]. `match` is exact, language, root or none.
  ({String? name, String match, String? locale}) display(
    String locale,
    String? rootName,
  ) {
    for (final candidate in chain(locale)) {
      final name = entries[candidate]!.name;
      if (name != null)
        return (
          name: name,
          match: candidate == locale ? 'exact' : 'language',
          locale: candidate,
        );
    }
    return rootName == null
        ? (name: null, match: 'none', locale: null)
        : (name: rootName, match: 'root', locale: null);
  }

  Map<String, Object?> toJson() => {
    for (final e in entries.entries) e.key: e.value.toJson(),
  };
}
