import 'errors.dart';
import 'food.dart';
import 'quantity.dart';

/// Rewrites every JSON number token outside strings as a string holding its
/// exact text, so decoding never passes a value through a double.
String jsonNumbersAsText(String json) {
  final out = StringBuffer();
  var inString = false;
  var i = 0;
  while (i < json.length) {
    final c = json[i];
    if (inString) {
      out.write(c);
      if (c == r'\') {
        if (i + 1 < json.length) out.write(json[i + 1]);
        i += 2;
        continue;
      }
      if (c == '"') inString = false;
      i++;
      continue;
    }
    if (c == '"') {
      inString = true;
      out.write(c);
      i++;
      continue;
    }
    if (c == '-' || (c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57)) {
      var j = i + 1;
      while (j < json.length && '0123456789.eE+-'.contains(json[j])) {
        j++;
      }
      out.write('"${json.substring(i, j)}"');
      i = j;
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

/// Exact plain decimal text of a JSON number (`2e-05` → `0.00002`).
String plainDecimal(String text) {
  final m = RegExp(
    r'^(-?)(\d+)(?:\.(\d+))?(?:[eE]([+-]?\d+))?$',
  ).firstMatch(text);
  if (m == null) invalid('Not a number: $text.');
  final sign = m[1]!;
  var digits = m[2]! + (m[3] ?? '');
  var point = m[2]!.length + int.parse(m[4] ?? '0');
  if (point.abs() > 60) invalid('Number out of range: $text.');
  if (point <= 0) {
    digits = '${'0' * (1 - point)}$digits';
    point = 1;
  } else if (point > digits.length) {
    digits = digits.padRight(point, '0');
  }
  final whole = digits.substring(0, point);
  final fraction = digits.substring(point);
  final text0 = fraction.isEmpty ? whole : '$whole.$fraction';
  return Decimal.parse('$sign$text0').toString();
}

/// Open Food Facts nutriment keys with the same meaning as the vocabulary.
/// `_100g` values are normalized by Open Food Facts to grams (kcal or kJ
/// for energy). Alcohol (% vol), vitamin A, E, folate and niacin (forms
/// and equivalents differ) are left out, as are its own estimates.
const openFoodFactsNutrients = {
  'proteins': 'protein',
  'carbohydrates': 'carbohydrate',
  'fat': 'fat',
  'fiber': 'fibre',
  'sugars': 'sugars',
  'added-sugars': 'added-sugars',
  'saturated-fat': 'saturated-fat',
  'monounsaturated-fat': 'monounsaturated-fat',
  'polyunsaturated-fat': 'polyunsaturated-fat',
  'cholesterol': 'cholesterol',
  'salt': 'salt',
  'sodium': 'sodium',
  'vitamin-d': 'vitamin-d',
  'vitamin-c': 'vitamin-c',
  'vitamin-b1': 'thiamin',
  'vitamin-b2': 'riboflavin',
  'vitamin-b6': 'vitamin-b6',
  'vitamin-b12': 'vitamin-b12',
  'calcium': 'calcium',
  'iron': 'iron',
  'potassium': 'potassium',
  'magnesium': 'magnesium',
  'zinc': 'zinc',
  'iodine': 'iodine',
  'selenium': 'selenium',
  'phosphorus': 'phosphorus',
};

const openFoodFactsLicence =
    'Open Food Facts (openfoodfacts.org), Open Database License 1.0; '
    'contributed product data, not verified.';

/// A looked-up product as an unsaved base food (F16). The product JSON must
/// have its numbers as text ([jsonNumbersAsText]). Values come from the
/// declared per-100 g or per-100 ml nutrition only; a modifier ("<", "~",
/// ">") is kept as the value type. Returns the food and what was skipped.
({Food food, List<Map<String, Object?>> skipped}) foodFromOpenFoodFacts(
  Map<String, Object?> product, {
  String? foodId,
}) {
  final code = requiredString(product, 'code');
  if (!RegExp(r'^\d{4,20}$').hasMatch(code))
    invalid('An Open Food Facts code is 4–20 digits.');
  final per = product['nutrition_data_per'];
  if (per != '100g' && per != '100ml')
    throw BodyTmiException(
      'not_found',
      'Product $code has no per-100 g or per-100 ml nutrition '
          '(${per ?? 'none'}); enter it from the label.',
    );
  final nutriments = jsonObject(
    product['nutriments'] ?? <String, Object?>{},
    'nutriments',
  );
  final skipped = <Map<String, Object?>>[];
  final nutrients = <String, Object?>{};
  final types = <String, Object?>{};
  void take(String key, String id, String unit) {
    final raw = nutriments['${key}_100g'];
    if (raw == null) return;
    if (raw is! String) {
      skipped.add({'nutriment': key, 'reason': 'Not a number.'});
      return;
    }
    final value = plainDecimal(raw);
    if (value.startsWith('-')) {
      skipped.add({'nutriment': key, 'reason': 'Negative value.'});
      return;
    }
    nutrients[id] = {'value': value, 'unit': unit};
    final modifier = nutriments['${key}_modifier'];
    if (modifier is String && modifier.isNotEmpty) types[id] = modifier;
  }

  if (nutriments.containsKey('energy-kcal_100g')) {
    take('energy-kcal', 'energy', 'kcal');
  } else {
    take('energy-kj', 'energy', 'kJ');
  }
  for (final e in openFoodFactsNutrients.entries) {
    take(e.key, e.value, 'g');
  }
  String? text(String key) {
    final v = product[key];
    return v is String && v.trim().isNotEmpty ? v.trim() : null;
  }

  var name = text('product_name') ?? 'Product $code';
  if (name.length > 200) name = name.substring(0, 200);
  final swedish = text('product_name_sv');
  final details = [?text('brands'), ?text('quantity')].join(', ');
  final food = Food.fromJson({
    'id': foodId ?? 'off-$code',
    'name': name,
    if (swedish != null && swedish.length <= 200)
      'labels': {
        'sv': {'name': swedish},
      },
    if (details.isNotEmpty && details.length <= 4000) 'notes': details,
    'source': {
      'kind': 'lookup',
      'url': 'https://world.openfoodfacts.org/product/$code',
      'notes': openFoodFactsLicence,
    },
    'kind': 'base',
    'basis': per,
    'nutrients': nutrients,
    if (types.isNotEmpty) 'valueTypes': types,
  });
  return (food: food, skipped: skipped);
}
