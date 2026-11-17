import 'dart:convert';
import 'dart:io';

import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';

import 'cli_test.dart';
import 'support.dart';

Map<String, Object?> _q(String value, String unit) => {
  'value': value,
  'unit': unit,
};

Food _base(
  String id,
  Map<String, Object?> nutrients, {
  String basis = '100g',
  Map<String, Object?>? density,
  List<Object?>? portions,
}) => Food.fromJson({
  'id': id,
  'name': id,
  'kind': 'base',
  'basis': basis,
  'nutrients': nutrients,
  'density': ?density,
  'portions': ?portions,
});

void foodTests() {
  test('fractions round half away from zero once', () {
    final third = Fraction.integer(1) / Fraction.integer(3);
    equal(third.round().toString(), '0.333333333');
    equal(
      (Fraction.integer(2) / Fraction.integer(3)).round().toString(),
      '0.666666667',
    );
    equal((Fraction.zero - third).round(fractionDigits: 2).toString(), '-0.33');
    equal(Fraction.parse('0.125').round(fractionDigits: 2).toString(), '0.13');
    check(Fraction.parse('0.125').isTerminating);
    check(!third.isTerminating);
  });

  test('base foods validate nutrients, portions and densities', () {
    rejects(() => _base('x', {'vitamin-q': _q('1', 'mg')}));
    rejects(() => _base('x', {'energy': _q('1', 'g')}));
    rejects(
      () => Food.fromJson({
        'id': 'x',
        'name': 'x',
        'kind': 'base',
        'basis': '100kg',
        'nutrients': <String, Object?>{},
      }),
    );
    // A volume portion of a per-100 g food needs a density.
    rejects(
      () => _base(
        'x',
        {},
        portions: [
          {'id': 'cup', 'amount': _q('2', 'dl')},
        ],
      ),
    );
    rejects(
      () => _base(
        'x',
        {},
        portions: [
          {'id': 'whole', 'amount': _q('2', 'g')},
        ],
      ),
    );
    final juice = _base(
      'juice',
      {'energy': _q('45', 'kcal'), 'carbohydrate': _q('10', 'g')},
      basis: '100ml',
      density: {'mass': _q('104', 'g'), 'volume': _q('100', 'ml')},
      portions: [
        {'id': 'glass', 'amount': _q('2', 'dl')},
      ],
    );
    final revision = FoodRevision.publish(juice);
    final math = FoodMath((_) => invalid('none'));
    // 100 g of a 1.04 g/ml drink is 100/1.04 ml: an exact fraction.
    final byMass = math.of(revision, QuantityAmount(Quantity('100', 'g')));
    equal(
      byMass.display('energy'),
      Fraction.integer(4500) / Fraction.integer(104),
    );
    final glass = math.of(revision, PortionAmount('glass', Decimal.parse('2')));
    equal(glass.display('energy'), Fraction.integer(180));
    equal(glass.grams, Fraction.integer(416));
    // Round trip keeps entered units.
    equal(
      jsonEncode(Food.fromJson(juice.toJson()).toJson()),
      jsonEncode(juice.toJson()),
    );
  });

  test('composites nest, pin revisions and state coverage', () {
    final bread = FoodRevision.publish(
      _base('bread', {
        'energy': _q('250', 'kcal'),
        'protein': _q('8', 'g'),
        'fibre': _q('6', 'g'),
      }),
    );
    final cheese = FoodRevision.publish(
      _base('cheese', {'energy': _q('350', 'kcal'), 'protein': _q('27', 'g')}),
    );
    final store = {
      for (final r in [bread, cheese]) foodRefKey(r.ref): r,
    };
    FoodRevision lookup(FoodRef ref) =>
        store[foodRefKey(ref)] ?? invalid('missing ${foodRefKey(ref)}');
    final sandwich = Food.fromJson({
      'id': 'sandwich',
      'name': 'Sandwich',
      'kind': 'composite',
      'components': [
        {
          'food': {'id': 'bread', 'revision': 1},
          'amount': _q('40', 'g'),
        },
        {
          'food': {'id': 'cheese', 'revision': 1},
          'amount': _q('20', 'g'),
        },
      ],
      'portions': [
        {'id': 'half', 'amount': _q('30', 'g')},
      ],
    });
    validateFoodComposition(sandwich, lookup);
    final rev = FoodRevision.publish(sandwich);
    store[foodRefKey(rev.ref)] = rev;
    final math = FoodMath(lookup);
    final whole = math.whole(rev);
    equal(whole.items, 2);
    equal(whole.display('energy'), Fraction.integer(170));
    equal(whole.status('energy'), 'known');
    equal(whole.status('fibre'), 'partial');
    equal(whole.known['fibre'], 1);
    equal(whole.status('fat'), 'unavailable');
    final json = whole.toJson();
    equal(
      jsonObject(jsonObject(json['nutrients'], 'n')['fat'], 'f')['value'],
      null,
    );
    final half = math.of(rev, PortionAmount('half', Decimal.parse('1')));
    equal(half.display('energy'), Fraction.integer(85));
    rejects(() => math.of(rev, QuantityAmount(Quantity('1', 'dl'))));
    rejects(() => math.of(rev, PortionAmount('portion', Decimal.parse('1'))));

    // Batch: nutrients per gram follow the cooked weight.
    final pot = FoodRevision.publish(
      Food.fromJson({
        'id': 'pot',
        'name': 'Pot',
        'kind': 'composite',
        'components': [
          {
            'food': {'id': 'sandwich', 'revision': 1},
            'amount': {'portion': 'whole', 'count': '3'},
          },
        ],
        'batch': {'finalMass': _q('150', 'g'), 'portions': 3},
      }),
    );
    store[foodRefKey(pot.ref)] = pot;
    final portion = math.of(pot, PortionAmount('portion', Decimal.parse('1')));
    final byMass = math.of(pot, QuantityAmount(Quantity('50', 'g')));
    equal(portion.display('energy'), Fraction.integer(170));
    equal(byMass.display('energy'), Fraction.integer(170));

    // Composite of a composite: an identity cycle is rejected.
    final loop = Food.fromJson({
      'id': 'bread',
      'name': 'Bread with a pot',
      'kind': 'composite',
      'components': [
        {
          'food': {'id': 'pot', 'revision': 1},
          'amount': {'portion': 'whole', 'count': '1'},
        },
      ],
    });
    rejects(() => validateFoodComposition(loop, lookup));
    // Every pinned revision must exist and revisions are contiguous.
    validateFoodRevisions(store.values.toList());
    rejects(() => validateFoodRevisions([rev]));
    rejects(
      () => validateFoodRevisions([
        bread,
        FoodRevision.fromJson({...bread.toJson(), 'revision': 3}),
      ]),
    );
  });

  test('diary dates follow the day start and the entered offset', () {
    equal(diaryDate('2026-11-17T03:59:00+01:00'), '2026-11-16');
    equal(diaryDate('2026-11-17T04:00:00+01:00'), '2026-11-17');
    equal(diaryDate('2026-11-17T02:30:00Z'), '2026-11-16');
    equal(diaryDate('2026-11-17T02:30:00Z', dayStart: 0), '2026-11-17');
    equal(parseDayStart('05:30'), 330);
    rejects(() => parseDayStart('13:00'));
    rejects(() => parseDayStart('4:00'));
    Map<String, Object?> quick(String at, [String? date]) => {
      'id': 'e',
      'at': at,
      'date': ?date,
      'quick': {'energy': _q('10', 'kcal')},
    };
    equal(
      DiaryEntry.fromJson(quick('2026-11-17T23:00:00+01:00')).date,
      '2026-11-17',
    );
    equal(
      DiaryEntry.fromJson(
        quick('2026-11-17T23:00:00+01:00', '2026-11-16'),
      ).date,
      '2026-11-16',
    );
    rejects(
      () =>
          DiaryEntry.fromJson(quick('2026-11-17T23:00:00+01:00', '2026-11-18')),
    );
    rejects(
      () => DiaryEntry.fromJson({
        'id': 'e',
        'at': '2026-11-17T08:00:00+01:00',
        'quick': {'energy': _q('10', 'kcal')},
        'food': {'id': 'x', 'revision': 1},
      }),
    );
    equal(diaryDayStatus(null, 0), 'unlogged');
    equal(diaryDayStatus(null, 2), 'partial');
    equal(
      diaryDayStatus(
        DiaryDayMark.fromJson({'date': '2026-11-17', 'status': 'complete'}),
        0,
      ),
      'complete',
    );
  });

  test('the shipped dataset converts every food exactly', () {
    final dataset = FoodDataset.fromJson(
      jsonDecode(
        utf8.decode(
          gzip.decode(File('data/food/slv.json.gz').readAsBytesSync()),
        ),
      ),
    );
    equal(dataset.id, 'slv');
    equal(dataset.foods.length, 2606);
    for (final f in dataset.foods) {
      dataset.toFood(f.number);
    }
    // Beef tallow, as published: 884 kcal and 100.0 g fat per 100 g.
    final tallow = dataset.toFood(1);
    equal(tallow.nutrients['energy']!.enteredValue, '884');
    equal(tallow.nutrients['fat']!.enteredValue, '100.0');
    equal(tallow.valueTypes['fat'], 'MN');
    equal(tallow.source!.json['release'], dataset.release);
    rejects(() => dataset.toFood(999999), 'not_found');
    equal(dataset.search('smör', 1).single.food.number, 29);
  });

  test('salt and sodium follow each other by the label definition', () {
    final math = FoodMath((_) => invalid('none'));
    Nutrition of(Map<String, Object?> nutrients) => math.of(
      FoodRevision.publish(_base('x', nutrients)),
      QuantityAmount(Quantity('100', 'g')),
    );
    // A Swedish label declares salt: sodium = salt / 2.5, marked derived.
    final label = of({'salt': _q('1.2', 'g')});
    equal(label.display('sodium'), Fraction.integer(480));
    equal(label.derived['sodium'], 1);
    equal(label.derived['salt'], null);
    final json = label.nutrientJson('sodium');
    equal(json['value'], '480');
    equal(json['derivedItems'], 1);
    // Sodium only: salt = sodium × 2.5.
    final sodiumOnly = of({'sodium': _q('400', 'mg')});
    equal(sodiumOnly.display('salt'), Fraction.integer(1));
    equal(sodiumOnly.derived['salt'], 1);
    // Both declared: both kept as printed, nothing derived.
    final both = of({'salt': _q('1', 'g'), 'sodium': _q('390', 'mg')});
    equal(both.display('sodium'), Fraction.integer(390));
    check(both.derived.isEmpty);
    // A mix of a label food and a database food is fully known.
    final sum = label + both;
    equal(sum.status('sodium'), 'known');
    equal(sum.derived['sodium'], 1);
    equal(sum.display('sodium'), Fraction.integer(870));
    // Quick entries derive the same way.
    final quick = DiaryEntry.fromJson({
      'id': 'q',
      'at': '2026-11-17T12:00:00+01:00',
      'quick': {'salt': _q('2.5', 'g')},
    }).nutrition(math);
    equal(quick.display('sodium'), Fraction.integer(1000));
  });

  test('Open Food Facts products map exactly or are refused', () {
    equal(plainDecimal('2e-05'), '0.00002');
    equal(plainDecimal('1.5E+2'), '150');
    equal(plainDecimal('0.0'), '0');
    equal(plainDecimal('678'), '678');
    final text = jsonNumbersAsText(
      '{"a":"x:1,","b":[1,-2.5e-3],"c":{"d":0.1}}',
    );
    equal(text, '{"a":"x:1,","b":["1","-2.5e-3"],"c":{"d":"0.1"}}');
    Map<String, Object?> product(String per) => jsonObject(
      jsonDecode(
        jsonNumbersAsText('''{
          "code": "7311870010970",
          "product_name": "Butter blend",
          "brands": "Brand",
          "quantity": "500 g",
          "nutrition_data_per": "$per",
          "nutriments": {
            "energy-kcal_100g": 678, "energy-kj_100g": 2789,
            "fat_100g": 75, "proteins_100g": 0.4,
            "salt_100g": 1.2, "sodium_100g": 0.48,
            "vitamin-d_100g": 2e-05, "vitamin-a_100g": 0.0009,
            "sugars_100g": 0.4, "sugars_modifier": "<",
            "alcohol_100g": 0
          },
          "nutriments_estimated": {"fiber_100g": 3}
        }'''),
      ),
      'p',
    );
    final result = foodFromOpenFoodFacts(product('100g'));
    final food = result.food;
    equal(food.id, 'off-7311870010970');
    check(!food.perVolume);
    equal(food.nutrients['energy']!.enteredValue, '678');
    equal(food.nutrients['energy']!.enteredUnit, Unit.kcal);
    equal(food.nutrients['vitamin-d']!.enteredValue, '0.00002');
    equal(food.valueTypes['sugars'], '<');
    // Vitamin A, alcohol (% vol) and Open Food Facts' estimates are not used.
    check(!food.nutrients.containsKey('vitamin-a'));
    check(!food.nutrients.containsKey('alcohol'));
    check(!food.nutrients.containsKey('fibre'));
    equal(food.source!.kind, 'lookup');
    check(foodFromOpenFoodFacts(product('100ml')).food.perVolume);
    rejects(() => foodFromOpenFoodFacts(product('serving')), 'not_found');
  });

  test('food lookup and search use only the endpoint asked', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final paths = <String>[];
    server.listen((request) async {
      paths.add(request.uri.toString());
      final response = request.response..headers.contentType = ContentType.json;
      if (request.uri.path == '/api/v2/product/7310070005250.json') {
        response.write(
          '{"code":"7310070005250","product":{"code":"7310070005250",'
          '"product_name":"Cola zero","nutrition_data_per":"100ml",'
          '"nutriments":{"energy-kcal_100g":1,"energy-kcal_modifier":"<",'
          '"salt_100g":0.01}}}',
        );
      } else if (request.uri.path == '/search') {
        response.write(
          '{"hits":[{"code":"7310070005250","product_name":"Cola zero",'
          '"brands":["Brand"]}]}',
        );
      } else {
        response.statusCode = 404;
        response.write('{"status":0}');
      }
      await response.close();
    });
    try {
      final endpoint = 'http://127.0.0.1:${server.port}';
      Future<({int code, Map<String, Object?> body})> run(
        String command,
        Map<String, Object?> fields,
      ) async {
        final r = await invoke(
          command.split(' '),
          jsonEncode({'schemaVersion': 1, 'endpoint': endpoint, ...fields}),
        );
        return (
          code: r.code,
          body: jsonObject(jsonDecode(r.code == 0 ? r.output : r.error), 'r'),
        );
      }

      final found = await run('food lookup', {'barcode': '7310070005250'});
      equal(found.code, 0);
      final food = jsonObject(
        jsonObject(found.body['data'], 'd')['food'],
        'food',
      );
      equal(food['basis'], '100ml');
      jsonEqual(food['valueTypes'], {'energy': '<'});
      final missing = await run('food lookup', {'barcode': '123456'});
      equal(missing.code, 3);
      final bad = await run('food lookup', {'barcode': 'abc'});
      equal(bad.code, 2);
      final search = await run('food search-online', {'query': 'cola'});
      equal(search.code, 0);
      jsonEqual(jsonObject(search.body['data'], 'd')['results'], [
        {'barcode': '7310070005250', 'name': 'Cola zero', 'brands': 'Brand'},
      ]);
      // Only the barcode and the query text left the machine.
      check(paths.every((p) => !p.contains('database')), '$paths');
      final down = await invoke(
        ['food', 'lookup'],
        jsonEncode({
          'schemaVersion': 1,
          'barcode': '7310070005250',
          'endpoint': 'http://127.0.0.1:1',
        }),
      );
      equal(down.code, 4);
    } finally {
      await server.close(force: true);
    }
  });

  test('NNR 2023 adult reference values match the published tables', () {
    String? v(List<ReferenceValue> refs, String id, String kind) =>
        refs.where((r) => r.nutrient == id && r.kind == kind).single.value;
    final woman30 = nnr2023References('female', 30);
    equal(v(woman30, 'iron', 'ri'), '15'); // Table 14
    equal(v(woman30, 'vitamin-a', 'ri'), '700'); // Table 12
    equal(v(woman30, 'zinc', 'ri'), '9.7');
    equal(v(woman30, 'calcium', 'ri'), '950');
    equal(v(woman30, 'selenium', 'ai'), '75'); // Table 15
    equal(v(woman30, 'vitamin-d', 'ri'), '10');
    equal(v(woman30, 'retinol', 'ul'), '3000'); // Table 21
    equal(v(nnr2023References('female', 60), 'iron', 'ri'), '8');
    equal(v(nnr2023References('female', 71), 'iron', 'ri'), '7');
    equal(v(nnr2023References('female', 20), 'calcium', 'ri'), '1000');
    equal(v(nnr2023References('male', 72), 'vitamin-d', 'ri'), '10');
    final man80 = nnr2023References('male', 80);
    equal(v(man80, 'vitamin-d', 'ri'), '20');
    equal(v(man80, 'vitamin-b6', 'ri'), '1.7');
    equal(v(man80, 'selenium', 'ai'), '85');
    equal(v(man80, 'zinc', 'ri'), '12.1');
    equal(v(man80, 'vitamin-c', 'ri'), '110');
    equal(v(man80, 'magnesium', 'ai'), '350');
    equal(v(man80, 'sodium', 'limit'), '2300'); // Table 16
    equal(v(man80, 'salt', 'limit'), '5.75');
    rejects(() => nnr2023References('male', 17));
    rejects(() => nnr2023References('other', 30));
  });

  test('NNR 2023 assessment computes E%, per-MJ and per-kg exactly', () {
    final means = {
      'energy': Fraction.integer(2000),
      'protein': Fraction.integer(100),
      'fat': Fraction.integer(70),
      'carbohydrate': Fraction.integer(250),
      'fibre': Fraction.integer(30),
      'sodium': Fraction.integer(2500),
      'salt': Fraction.parse('5.5'),
      'iron': Fraction.integer(8),
    };
    final rows = assessReferences(
      nnr2023References('female', 30),
      mean: (id) => (value: means[id], days: 7, partialDays: 0),
      joint: (parts) => parts.every(means.containsKey)
          ? (
              energyKcal: means['energy'],
              parts: {for (final p in parts) p: means[p]!},
              days: 7,
            )
          : (energyKcal: null, parts: const {}, days: 0),
      bodyMassKg: Fraction.integer(80),
    );
    Map<String, Object?> row(String id, String kind) =>
        rows.singleWhere((r) => r['nutrient'] == id && r['kind'] == kind);
    String intake(Map<String, Object?> r) =>
        jsonObject(r['intake'], 'i')['value']! as String;
    // 100 g × 17 kJ / (2000 kcal × 4.184) = 20.315 E%: above 10–20.
    equal(intake(row('protein', 'energyRange')), '20.315');
    equal(row('protein', 'energyRange')['relation'], 'above');
    equal(intake(row('fat', 'energyRange')), '30.951');
    // (250 × 17 + 30 × 8) / 8368 kJ, fibre energy included.
    equal(intake(row('carbohydrate', 'energyRange')), '53.657');
    // 3 g/MJ × 8.368 MJ = 25.104 g.
    equal(
      jsonObject(row('fibre', 'minimumPerMJ')['amount'], 'a')['value'],
      '25.104',
    );
    equal(row('fibre', 'minimumPerMJ')['relation'], 'meets');
    equal(
      jsonObject(row('protein', 'riPerKg')['amount'], 'a')['value'],
      '66.4',
    );
    equal(row('sodium', 'limit')['relation'], 'above');
    equal(row('salt', 'limit')['relation'], 'within');
    equal(row('iron', 'ri')['relation'], 'below');
    equal(row('iron', 'ul')['relation'], 'within');
    equal(row('zinc', 'ri')['relation'], 'unknown');
    equal(row('saturated-fat', 'energyBelow')['relation'], 'unknown');
  });

  test('stored foods and diary entries validate in archives', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-food-');
    try {
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      final foods = FoodService(store);
      final diary = DiaryService(store);
      await foods.publish(_base('oats', {'energy': _q('370', 'kcal')}), 0);
      try {
        await foods.publish(_base('oats', {}), 0);
        throw StateError('stale revision accepted');
      } on BodyTmiException catch (e) {
        equal(e.code, 'conflict');
      }
      await diary.add({
        'id': 'e1',
        'at': '2026-11-17T08:00:00+01:00',
        'food': {'id': 'oats'},
        'amount': _q('60', 'g'),
      });
      await foods.publish(_base('oats', {'energy': _q('380', 'kcal')}), 1);
      // The entry keeps revision 1.
      equal((await diary.entry('e1')).food!.revision, 1);
      final day = await diary.day('2026-11-17');
      equal(
        jsonObject(
          jsonObject(
            jsonObject(day['totals'], 't')['nutrients'],
            'n',
          )['energy'],
          'e',
        )['value'],
        '222',
      );
      final archive = await StoredTrainingService(store).exportArchive();
      equal(archive.foods.length, 2);
      equal(archive.diaryEntries.length, 1);
      final json = jsonObject(jsonDecode(jsonEncode(archive.toJson())), 'a');
      TrainingArchive.fromJson(json);
      // An entry pinning an unpublished revision is rejected.
      final forged = jsonObject(jsonDecode(jsonEncode(json)), 'f');
      final entry = jsonObject((forged['diaryEntries']! as List).single, 'e');
      entry['food'] = {'id': 'oats', 'revision': 9};
      rejects(() => TrainingArchive.fromJson(forged));
      final gap = jsonObject(jsonDecode(jsonEncode(json)), 'g');
      (gap['foods']! as List).removeAt(0);
      rejects(() => TrainingArchive.fromJson(gap));
      await store.close();
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
