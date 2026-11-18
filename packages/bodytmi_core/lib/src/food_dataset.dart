import 'catalog_labels.dart';
import 'errors.dart';
import 'food.dart';
import 'nutrient.dart';

const foodDatasetFormat = 'bodytmi-food-dataset/1';

/// One food of a packaged dataset, values per 100 g as published.
final class DatasetFood {
  DatasetFood._(this.json, this.number, this.name, this.english);
  final Map<String, Object?> json;
  final int number;
  final String name;
  final String? english;
  String? get scientificName => json['scientificName'] as String?;
  String get type => json['type']! as String;
  String get version => json['version']! as String;
}

/// A packaged, read-only food composition dataset (`bodytmi-food-dataset/1`),
/// pinned by [release]. Foods are copied into the profile when used, so a
/// diary never depends on the file staying available.
final class FoodDataset {
  FoodDataset._(this.header, this.foods, this._byNumber);

  factory FoodDataset.fromJson(Object? input) {
    final j = jsonObject(input, 'food dataset');
    checkKeys(j, {
      'format',
      'id',
      'name',
      'publisher',
      'licence',
      'attribution',
      'source',
      'release',
      'retrieved',
      'basis',
      'nutrients',
      'foods',
    });
    if (j['format'] != foodDatasetFormat)
      invalid('Unsupported food dataset format.');
    identifier(j, 'id');
    for (final k in ['name', 'publisher', 'attribution', 'source', 'release']) {
      requiredString(j, k);
    }
    final licence = jsonObject(j['licence'], 'licence');
    requiredString(licence, 'name');
    if (j['basis'] != '100g') invalid('Dataset values must be per 100 g.');
    final units = jsonObject(j['nutrients'], 'dataset nutrients');
    for (final e in units.entries) {
      if (nutrient(e.key).unit.name != e.value)
        invalid('Dataset nutrient ${e.key} is not in ${nutrient(e.key).unit}.');
    }
    final foods = <DatasetFood>[];
    final byNumber = <int, DatasetFood>{};
    for (final raw in jsonList(j, 'foods')) {
      final f = jsonObject(raw, 'dataset food');
      final number = f['number'];
      if (number is! int || number < 0) invalid('A dataset food has a number.');
      final food = DatasetFood._(
        f,
        number,
        requiredString(f, 'name'),
        f['english'] as String?,
      );
      if (byNumber.putIfAbsent(number, () => food) != food)
        invalid('Duplicate dataset food $number.');
      foods.add(food);
    }
    final header = Map<String, Object?>.of(j)..remove('foods');
    return FoodDataset._(Map.unmodifiable(header), foods, byNumber);
  }

  final Map<String, Object?> header;
  final List<DatasetFood> foods;
  final Map<int, DatasetFood> _byNumber;

  String get id => header['id']! as String;
  String get release => header['release']! as String;

  DatasetFood food(int number) =>
      _byNumber[number] ??
      (throw BodyTmiException('not_found', 'Dataset $id has no food $number.'));

  Map<String, Object?> describe() => {
    for (final e in header.entries)
      if (e.key != 'nutrients') e.key: e.value,
    'foods': foods.length,
  };

  /// The dataset food as a base food of the profile, with [foodId] (default
  /// `<dataset>-<number>`). The Swedish name is the root name; the English
  /// name is a label.
  Food toFood(int number, {String? foodId}) {
    final f = food(number);
    final units = jsonObject(header['nutrients'], 'nutrients');
    final values = jsonObject(f.json['values'], 'values');
    final nutrients = <String, Object?>{};
    final types = <String, Object?>{};
    for (final e in values.entries) {
      final v = e.value;
      if (v is! List<Object?> || v.isEmpty || v.length > 2)
        invalid('Dataset food $number value ${e.key} is malformed.');
      nutrients[e.key] = {'value': v[0], 'unit': units[e.key]};
      if (v.length == 2) types[e.key] = v[1];
    }
    final name = f.name.length > 200 ? f.name.substring(0, 200) : f.name;
    return Food.fromJson({
      'id': foodId ?? '$id-$number',
      'name': name,
      if (f.english != null && f.english!.trim().isNotEmpty)
        'labels': {
          'en': {'name': f.english},
          'sv': {'name': name},
        },
      'source': {
        'kind': 'dataset',
        'dataset': id,
        'release': release,
        'number': number,
      },
      'kind': 'base',
      'basis': '100g',
      'nutrients': nutrients,
      if (types.isNotEmpty) 'valueTypes': types,
    });
  }

  /// Plain search over Swedish and English names: exact, prefix, word
  /// prefix, substring, then every query word somewhere in the name; ties
  /// by number. Diacritics are significant
  /// (å, ä and ö are letters of their own in Swedish), so letter-exact
  /// matches always rank first; a query that only matches once accents are
  /// folded (`mjolk` for Mjölk) is ranked after them as `folded`.
  List<({DatasetFood food, String match})> search(String query, int limit) {
    final key = catalogSearchKey(query);
    if (key.isEmpty) invalid('A search needs a query.');
    final folded = foldDiacritics(key);
    int rankOf(String n, String k) => n == k
        ? 0
        : n.startsWith(k)
        ? 1
        : n.split(RegExp(r'[\s,()/-]+')).any((w) => w.startsWith(k))
        ? 2
        : n.contains(k)
        ? 3
        : k.contains(' ') &&
              k.split(' ').where((w) => w.isNotEmpty).every(n.contains)
        ? 4
        : 99;
    final ranked = <({DatasetFood food, String match, int rank})>[];
    for (final f in foods) {
      var best = 99;
      for (final name in [f.name, ?f.english]) {
        final n = catalogSearchKey(name);
        var rank = rankOf(n, key);
        if (rank == 99) {
          final r = rankOf(foldDiacritics(n), folded);
          if (r < 99) rank = 5 + r;
        }
        if (rank < best) best = rank;
      }
      if (best < 99) {
        ranked.add((
          food: f,
          match: best < 5
              ? const [
                  'exact',
                  'prefix',
                  'word-prefix',
                  'substring',
                  'words',
                ][best]
              : 'folded',
          rank: best,
        ));
      }
    }
    ranked.sort((a, b) {
      final r = a.rank.compareTo(b.rank);
      return r != 0 ? r : a.food.number.compareTo(b.food.number);
    });
    return [for (final r in ranked.take(limit)) (food: r.food, match: r.match)];
  }
}

const _folds = {
  'a': 'àáâãäåā',
  'c': 'çč',
  'e': 'èéêëē',
  'i': 'ìíîïī',
  'n': 'ñ',
  'o': 'òóôõöøō',
  's': 'š',
  'u': 'ùúûüū',
  'y': 'ýÿ',
  'z': 'ž',
};

final _foldMap = {
  for (final e in _folds.entries)
    for (final c in e.value.split('')) c: e.key,
};

/// Lowercase text with common Latin diacritics removed (search only).
String foldDiacritics(String text) =>
    text.split('').map((c) => _foldMap[c] ?? c).join();
