import 'dart:io';

import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_app/src/app.dart';
import 'package:bodytmi_app/src/diet_plan.dart';
import 'package:bodytmi_app/src/profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'lock_test.dart' show FakeKeyStore, waitFor;

void main() {
  final clock = DateTime(2026, 11, 18, 9, 30);

  test('category-specific programme choices are shown only for it', () {
    const descriptions = {
      'dietDays': 'category 1: 11–12 days before the break',
      'dietWeeks': 'category 2: 2–6 weeks; category 3: 6–12 weeks',
      'activity': 'inactive, aerobic or weights',
    };
    List<String> keys(int? c) => [
      for (final f in fieldsFor('rfl', descriptions, c)) f.key,
    ];
    expect(keys(1), containsAll(['dietDays', 'activity']));
    expect(keys(1), isNot(contains('dietWeeks')));
    expect(keys(3), contains('dietWeeks'));
    expect(keys(2), isNot(contains('dietDays')));
    expect(keys(2), containsAll(['dietWeeks', 'activity']));
    expect(keys(null), contains('dietDays'));
  });

  testWidgets('review, target, end, then build and start a Normal plan', (
    tester,
  ) async {
    late Directory dir;
    late ProfileClient profile;
    Future<T> pumped<T>(Future<T> future) async {
      T? result;
      Object? error;
      var done = false;
      future.then(
        (v) {
          result = v;
          done = true;
        },
        onError: (Object e) {
          error = e;
          done = true;
        },
      );
      for (var i = 0; i < 200 && !done; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      if (error != null) throw error!;
      return result as T;
    }

    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<List<Map>> plans() async => [
      for (final p in await pumped(profile.call<List<Object?>>('plan list')))
        p! as Map,
    ];

    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('bodytmi-diet-');
      await buildDemoProfile('${dir.path}/p.sqlite', now: clock);
      profile = await ProfileClient.open(
        '${dir.path}/p.sqlite',
        keyStore: FakeKeyStore(),
      );
    });
    try {
      await tester.binding.setSurfaceSize(const Size(640, 3000));
      await tester.pumpWidget(BodyTmiApp(profile: profile, clock: clock));
      await tester.pump(const Duration(milliseconds: 300));
      openDietPlan(tester.element(find.byType(Scaffold).first), clock: clock);
      await waitFor(tester, find.text('Normal'));
      await settle();
      expect(
        find.textContaining('kcal a day', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('Mifflin-St Jeor'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Deficit day'), findsWidgets);

      await tester.tap(find.text('Review'));
      await waitFor(tester, find.textContaining('the plan expected'));
      expect(find.text('No new changes proposed.'), findsOneWidget);

      await tester.tap(find.text('Set target'));
      await waitFor(tester, find.text('Plan target'));
      await settle();
      await tester.enterText(find.widgetWithText(TextField, 'Target'), '80');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await waitFor(tester, find.textContaining('Target: mass ≤ 80'));
      expect(((await plans()).single['target'] as Map)['relation'], 'atMost');

      await tester.tap(find.text('End plan'));
      await waitFor(tester, find.text('End the plan?'));
      await settle();
      await tester.tap(find.widgetWithText(FilledButton, 'End'));
      await waitFor(tester, find.text('Start a plan'));
      await settle();
      expect((await plans()).single['status'], isNot('active'));

      await tester.tap(find.text('Start a plan'));
      await waitFor(tester, find.text('Deficit below maintenance'));
      await settle();
      await tester.tap(find.text('Intermittent Modified Fasting'));
      await settle();
      await tester.tap(find.text('Preview'));
      await waitFor(tester, find.text('NOT READY'));
      expect(find.textContaining('Choose'), findsWidgets);

      await tester.tap(find.text('Normal').first);
      await settle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Deficit below maintenance'),
        '400',
      );
      await tester.tap(find.text('Preview'));
      await waitFor(tester, find.text('intake: 400 kcal below maintenance'));
      await settle();
      expect(find.textContaining('Over '), findsOneWidget);
      await tester.ensureVisible(find.text('Start plan'));
      await tester.tap(find.text('Start plan'));
      await waitFor(tester, find.text('Plan started'));
      await settle();
      final active = (await plans()).where((p) => p['status'] == 'active');
      expect(active.single['programme'], {
        'id': 'normal',
        'choices': {
          'deficit': {'kcal': '400'},
        },
        'category': 2,
      });
      expect(active.single['startDate'], '2026-11-19');
    } finally {
      await pumped(profile.close());
      await tester.runAsync(() => dir.delete(recursive: true));
    }
  });
}
