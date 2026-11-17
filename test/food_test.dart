import 'dart:convert';
import 'dart:io';

import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';

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
