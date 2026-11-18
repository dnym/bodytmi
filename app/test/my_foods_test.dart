import 'dart:io';

import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_app/src/app.dart';
import 'package:bodytmi_app/src/profile.dart';
import 'package:bodytmi_app/src/quick_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'gym_start_test.dart' show pumped;
import 'lock_test.dart' show FakeKeyStore, waitFor;

void main() {
  final clock = DateTime(2026, 11, 18, 9, 30);

  testWidgets('a label food, a recipe from it, a logged portion, an edit', (
    tester,
  ) async {
    foodDataset = () async => File('../data/food/slv.json.gz').absolute.path;
    late Directory dir;
    late ProfileClient profile;
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<Map<String, Object?>> show(String id) => pumped(
      tester,
      profile.call<Map<String, Object?>>('food show', {'foodId': id}),
    );

    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('bodytmi-myfoods-');
      await buildDemoProfile('${dir.path}/p.sqlite', now: clock);
      profile = await ProfileClient.open(
        '${dir.path}/p.sqlite',
        keyStore: FakeKeyStore(),
      );
    });
    try {
      await tester.binding.setSurfaceSize(const Size(480, 2600));
      await tester.pumpWidget(BodyTmiApp(profile: profile, clock: clock));
      await settle();
      await tester.tap(find.text('Food'));
      await waitFor(tester, find.text('My foods & recipes'));
      await tester.tap(find.text('My foods & recipes'));
      await waitFor(tester, find.text('Cottage cheese 1.5%'));
      await settle();

      // A food from its label, with a portion; fibre and salt left unknown.
      await tester.tap(find.text('Add'));
      await settle();
      await tester.tap(find.text('Food'));
      await waitFor(tester, find.text('New food'));
      await settle();
      Finder field(String label) => find.widgetWithText(TextField, label);
      await tester.enterText(field('Name'), 'Oats');
      await tester.enterText(field('Energy'), '370');
      await tester.enterText(field('Protein'), '13');
      await tester.enterText(field('Carbohydrate'), '59');
      await tester.enterText(field('Fat'), '7');
      await tester.tap(find.text('Add portion'));
      await settle();
      await tester.enterText(field('Name').last, 'Cup');
      await tester.enterText(field('Amount').last, '40');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await waitFor(tester, find.text('Oats saved'));
      await settle();
      final oats = await show('oats');
      expect(at(oats, ['food', 'nutrients']), isNot(contains('fibre')));
      expect(at(oats, ['food', 'portions', 0, 'id']), 'cup');

      // A recipe: oats and an egg, cooked to 400 g in two portions.
      await tester.tap(find.text('Add'));
      await settle();
      await tester.tap(find.text('Recipe'));
      await waitFor(tester, find.text('New recipe'));
      await settle();
      await tester.enterText(field('Name'), 'Porridge');
      for (final (name, grams) in [('Oats', '80'), ('Egg', '110')]) {
        await tester.tap(find.text('Add ingredient'));
        await waitFor(tester, find.text('Find one of your foods'));
        await settle();
        await tester.tap(find.text(name).last);
        await waitFor(tester, find.widgetWithText(TextField, 'Amount'));
        await settle();
        await tester.enterText(field('Amount').last, grams);
      }
      await tester.enterText(field('Cooked weight'), '400');
      await tester.enterText(field('Portions'), '2');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await waitFor(tester, find.text('Porridge saved'));
      await settle();
      var porridge = await show('porridge');
      // 370 × 0.8 + 135 × 1.1 = 444.5 kcal in the whole batch.
      expect(at(porridge, ['whole', 'nutrients', 'energy', 'value']), '444.5');
      expect(at(porridge, ['food', 'components', 0, 'food']), {
        'id': 'oats',
        'revision': 1,
      });

      // Log one portion from the food entry.
      await tester.tap(find.byType(BackButton));
      await settle();
      await waitFor(tester, find.text('Add food'));
      await tester.tap(find.text('Add food'));
      await waitFor(tester, find.byType(TextField));
      await settle();
      await waitFor(tester, find.text('Porridge'));
      // Own foods are listed before any search.
      await tester.tap(find.text('Porridge'));
      await waitFor(tester, find.text('Portion (1/2)'));
      await settle();
      await tester.tap(find.text('Portion (1/2)'));
      await settle();
      await tester.enterText(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(TextField),
        ),
        '1',
      );
      await tester.tap(find.text('Add'));
      await waitFor(tester, find.text('Porridge added'));
      final day = await pumped(
        tester,
        profile.call<Map<String, Object?>>('diary day', {'date': '2026-11-18'}),
      );
      final entry = (day['entries']! as List)
          .cast<Map>()
          .map((e) => e['entry'] as Map)
          .firstWhere((e) => at(e, ['food', 'id']) == 'porridge');
      expect(entry['amount'], {'portion': 'portion', 'count': '1'});

      // Editing the food is a new revision; the recipe keeps revision 1.
      await settle();
      await tester.tap(find.text('My foods & recipes'));
      await waitFor(tester, find.text('Oats'));
      await settle();
      await tester.tap(find.text('Oats'));
      await waitFor(tester, find.text('Food'));
      await settle();
      await tester.enterText(field('Energy'), '380');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await waitFor(tester, find.text('Oats saved'));
      expect((await show('oats'))['revision'], 2);
      porridge = await show('porridge');
      expect(at(porridge, ['food', 'components', 0, 'food', 'revision']), 1);
    } finally {
      await pumped(tester, profile.close());
      await tester.runAsync(() => dir.delete(recursive: true));
    }
  });
}

Object? at(Object? json, List<Object> path) {
  var c = json;
  for (final k in path) {
    c = c is Map ? c[k] : (c is List && k is int ? c[k] : null);
  }
  return c;
}
