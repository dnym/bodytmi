// Packages a cache written by tool/fetch_slv.dart as the shipped
// `bodytmi-food-dataset/1` file (gzip-compressed JSON).
//
// Usage: dart run tool/package_slv.dart CACHE_DIR OUT.json.gz RETRIEVED_DATE
//
// Values are copied as published, as decimal text: the API's JSON numbers are
// read as text before decoding, so no value passes through a double. Every
// kept value is per 100 g edible part. Energy keeps the published kcal value
// (the kJ value is the same energy and is dropped); waste (% of purchased
// weight) is not a nutrient and is dropped.
import 'dart:convert';
import 'dart:io';

import 'package:bodytmi_core/bodytmi_core.dart';

const units = {
  'g': 'g',
  'mg': 'mg',
  'µg': 'mcg',
  'RE/µg': 'mcg',
  'NE/mg': 'mg',
  'kcal': 'kcal',
};

Object? decodeExact(String text) => jsonDecode(
  text.replaceAllMapped(
    RegExp(r'"varde":(-?\d+(?:\.\d+)?)'),
    (m) => '"varde":"${m[1]}"',
  ),
);

void main(List<String> args) {
  if (args.length != 3) {
    stderr.writeln(
      'Usage: dart run tool/package_slv.dart CACHE_DIR OUT.json.gz DATE',
    );
    exit(2);
  }
  final dir = args[0];
  final byCode = {for (final n in nutrients) n.euroFir: n};
  List<Map<String, Object?>> list(int language) => [
    for (final f
        in ((jsonDecode(File('$dir/foods-$language.json').readAsStringSync())
                as Map<String, Object?>)['livsmedel']!
            as List<Object?>))
      f! as Map<String, Object?>,
  ];
  final english = {for (final f in list(2)) f['nummer']: f['namn']};
  final foods = <Map<String, Object?>>[];
  var release = '';
  for (final f in list(
    1,
  )..sort((a, b) => (a['nummer']! as int).compareTo(b['nummer']! as int))) {
    final number = f['nummer']! as int;
    final version = f['version']! as String;
    if (version.compareTo(release) > 0) release = version;
    final values = <String, Object?>{};
    final raw =
        decodeExact(File('$dir/nutrients/$number.json').readAsStringSync())!
            as List<Object?>;
    for (final r in raw.cast<Map<String, Object?>>()) {
      final code = r['euroFIRkod']! as String;
      final unit = r['enhet']! as String;
      if (code == 'WASTE' || (code == 'ENERC' && unit == 'kJ')) continue;
      final def = byCode[code] ?? (throw StateError('Unmapped $code'));
      if (units[unit] != def.unit.name) {
        throw StateError('Food $number $code unit $unit is not ${def.unit}.');
      }
      if (r['viktGram'] != 100 || r['matrisenhetkod'] == 'T') {
        throw StateError('Food $number $code is not per 100 g edible part.');
      }
      if (values.containsKey(def.id)) throw StateError('Duplicate $code.');
      final type = r['vardetypkod'] as String?;
      values[def.id] = [r['varde']! as String, ?type];
    }
    final scientific = (f['vetenskapligtNamn'] as String?)?.trim() ?? '';
    foods.add({
      'number': number,
      'name': (f['namn']! as String).trim(),
      if (english[number] case final String en when en.trim().isNotEmpty)
        'english': en.trim(),
      if (scientific.isNotEmpty) 'scientificName': scientific,
      'type': f['livsmedelsTypId'] == 1 ? 'analysed' : 'calculated',
      'version': version,
      'values': {
        for (final n in nutrients)
          if (values.containsKey(n.id)) n.id: values[n.id],
      },
    });
  }
  final dataset = {
    'format': 'bodytmi-food-dataset/1',
    'id': 'slv',
    'name': 'Livsmedelsverkets livsmedelsdatabas',
    'publisher': 'Livsmedelsverket (Swedish Food Agency)',
    'licence': {
      'name': 'CC BY 4.0',
      'url': 'https://creativecommons.org/licenses/by/4.0/',
    },
    'attribution':
        'Contains data from the Swedish Food Agency food composition database '
        '(Livsmedelsverket, Livsmedelsdatabasen), licensed under CC BY 4.0. '
        'Values are copied as published per 100 g edible part; the kJ energy '
        'and waste columns are omitted.',
    'source': 'https://dataportal.livsmedelsverket.se/livsmedel/api/v1',
    'release': release.substring(0, 10),
    'retrieved': args[2],
    'basis': '100g',
    'nutrients': {for (final n in nutrients) n.id: n.unit.name},
    'foods': foods,
  };
  final bytes = gzip.encode(utf8.encode(jsonEncode(dataset)));
  File(args[1])
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(bytes);
  stderr.writeln(
    'Wrote ${foods.length} foods, release ${dataset['release']}, '
    '${bytes.length} bytes.',
  );
}
