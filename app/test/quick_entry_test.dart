import 'dart:io';

import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_app/src/app.dart';
import 'package:bodytmi_app/src/profile.dart';
import 'package:bodytmi_app/src/quick_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  final clock = DateTime(2026, 11, 18, 9, 30);
  late Directory dir;
  late ProfileClient profile;

  setUp(() {
    // The repository copy; the app copies its bundled asset instead.
    foodDataset = () async => File('../data/food/slv.json.gz').absolute.path;
  });

  Future<void> start(WidgetTester tester, {bool demo = false}) async {
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('bodytmi-quick-');
      if (demo) await buildDemoProfile('${dir.path}/p.sqlite', now: clock);
      profile = await ProfileClient.open('${dir.path}/p.sqlite');
    });
    await tester.binding.setSurfaceSize(const Size(420, 2400));
    await tester.pumpWidget(BodyTmiApp(profile: profile, clock: clock));
    await settle(tester);
  }

  Future<void> finish(WidgetTester tester) => tester.runAsync(() async {
    await profile.close();
    await dir.delete(recursive: true);
  });

  test('meals follow the time of day', () {
    expect(mealFor(DateTime(2026, 1, 1, 7)), 'breakfast');
    expect(mealFor(DateTime(2026, 1, 1, 12, 30)), 'lunch');
    expect(mealFor(DateTime(2026, 1, 1, 18)), 'dinner');
    expect(mealFor(DateTime(2026, 1, 1, 23)), 'snack');
  });

  testWidgets('weigh in, quick kcal and sleep from Today', (tester) async {
    await start(tester);
    try {
      await tester.tap(find.byTooltip('Quick add'));
      await settle(tester);
      await tester.tap(find.text('Weigh in'));
      await settle(tester);
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(find.text('Enter your weight.'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Weight'), '81,4');
      await tester.tap(find.text('Save'));
      await waitFor(tester, find.textContaining('Weighed 81.4'));

      await tester.tap(find.byTooltip('Quick add'));
      await settle(tester);
      await tester.tap(find.text('Quick kcal'));
      await settle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Energy'), '420');
      await tester.enterText(find.widgetWithText(TextField, 'Protein'), '30');
      await tester.tap(find.text('Add'));
      await waitFor(tester, find.text('Added to the diary'));
      await settle(tester);
      expect(find.textContaining('420'), findsOneWidget); // eaten, no budget

      await tester.tap(find.byTooltip('Quick add'));
      await settle(tester);
      await tester.tap(find.text('Sleep'));
      await settle(tester);
      await tester.tap(find.text('4'));
      await tester.tap(find.text('Save'));
      await waitFor(tester, find.text('Sleep saved'));
      await settle(tester);
      // Default 23:00 to 07:00.
      expect(find.text('8 h 00'), findsOneWidget);

      final day = await tester.runAsync(
        () => profile.call<Map<String, Object?>>('diary day', {
          'date': '2026-11-18',
        }),
      );
      final entry = ((day!['entries']! as List).single as Map)['entry'] as Map;
      expect(entry['meal'], 'breakfast');
      expect(
        (((entry['quick'] as Map)['protein'] as Map)['entered']
            as Map)['value'],
        '30',
      );
    } finally {
      await finish(tester);
    }
  });

  testWidgets('food from the dataset is adopted and logged', (tester) async {
    await start(tester, demo: true);
    try {
      await tester.tap(find.text('Food'));
      await settle(tester);
      await tester.tap(find.text('Add food'));
      await settle(tester);
      expect(find.text('Egg'), findsOneWidget); // own foods listed first
      await tester.enterText(find.byType(TextField), 'mjölk fett 3');
      await waitFor(tester, find.text('Mjölk fett 3% berikad'));
      await tester.tap(find.text('Mjölk fett 3% berikad'));
      await settle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Amount'), '200');
      await tester.tap(find.text('Add'));
      await waitFor(tester, find.text('Mjölk fett 3% berikad added'));
      await settle(tester);
      expect(find.text('Mjölk fett 3% berikad'), findsOneWidget); // diary
      final foods = await tester.runAsync(
        () => profile.call<List<Object?>>('food list'),
      );
      expect(
        foods!.cast<Map>().where((f) => f['id'] == 'slv-123'),
        hasLength(1),
      );
    } finally {
      await finish(tester);
    }
  });
}

Future<void> settle(WidgetTester tester, {int rounds = 40}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Pumps until [finder] matches, failing after about ten seconds.
Future<void> waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 200; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsWidgets);
}
