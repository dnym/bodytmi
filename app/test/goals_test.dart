import 'dart:io';

import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_app/src/app.dart';
import 'package:bodytmi_app/src/goals.dart';
import 'package:bodytmi_app/src/profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'lock_test.dart' show FakeKeyStore, waitFor;

void main() {
  final clock = DateTime(2026, 11, 18, 9, 30);

  test('metrics are named from the presets, by value', () {
    expect(
      metricName({
        'summary': 'sum',
        'measure': 'steps',
        'source': 'observation',
      }),
      ('Steps per day', 'steps'),
    );
    expect(
      metricName({'source': 'sleep', 'field': 'awakenings'}).$1,
      'sleep awakenings',
    );
  });

  testWidgets('goal add and edit, routine check, trial add and conclude', (
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

    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('bodytmi-goals-');
      await buildDemoProfile('${dir.path}/p.sqlite', now: clock);
      profile = await ProfileClient.open(
        '${dir.path}/p.sqlite',
        keyStore: FakeKeyStore(),
      );
    });
    try {
      await tester.binding.setSurfaceSize(const Size(640, 2600));
      await tester.pumpWidget(BodyTmiApp(profile: profile, clock: clock));
      await tester.pump(const Duration(milliseconds: 300));
      openGoals(tester.element(find.byType(Scaffold).first), clock: clock);
      await waitFor(tester, find.textContaining('No goals yet'));
      await settle();

      await tester.tap(find.text('Add goal'));
      await waitFor(tester, find.text('New goal'));
      await settle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        '8000 steps',
      );
      await tester.enterText(find.widgetWithText(TextField, 'Target'), '8000');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await waitFor(tester, find.textContaining('known days met'));
      await settle();
      expect(find.text('Steps per day'.toUpperCase()), findsOneWidget);

      await tester.tap(find.text('8000 steps'));
      await waitFor(tester, find.text('achieved'));
      await settle();
      await tester.tap(find.text('achieved'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await waitFor(tester, find.text('Goal updated'));
      await settle();
      final goals = await pumped(
        profile.call<Map<String, Object?>>('goal list'),
      );
      expect(((goals['goals']! as List).single as Map)['status'], 'achieved');

      await tester.tap(find.text('Routines'));
      await waitFor(tester, find.text('Last caffeine before 13:00'));
      await settle();
      await tester.tap(find.text('Done'));
      await waitFor(tester, find.text('Undo'));
      final today = await pumped(
        profile.call<Map<String, Object?>>('today show', {
          'date': '2026-11-18',
        }),
      );
      final caffeine = (today['routines']! as List).cast<Map>().firstWhere(
        (r) => (r['routine'] as Map)['id'] == 'caffeine-cutoff',
      );
      expect(caffeine['status'], 'done');
      await tester.tap(find.text('Undo'));
      await waitFor(tester, find.text('Done'));

      await tester.tap(find.text('Trials'));
      await waitFor(tester, find.textContaining('No trials yet'));
      await settle();
      await tester.tap(find.text('Add trial'));
      await waitFor(tester, find.text('New trial'));
      await settle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Question'),
        'Does an earlier coffee help my sleep?',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'What you change during the trial'),
        'Last coffee before 13:00',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await waitFor(tester, find.text('Trial added'));
      await settle();
      await waitFor(tester, find.textContaining('baseline 4'));
      expect(
        find.text('Does an earlier coffee help my sleep?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Conclude…'));
      await waitFor(tester, find.text('Conclude the trial'));
      await settle();
      await tester.tap(find.widgetWithText(FilledButton, 'Conclude'));
      await settle();
      expect(find.text('Choose what you decided.'), findsOneWidget);
      await tester.tap(find.text('unclear'));
      await tester.tap(find.widgetWithText(FilledButton, 'Conclude'));
      await waitFor(tester, find.text('CONCLUDED · UNCLEAR'));
    } finally {
      await pumped(profile.close());
      await tester.runAsync(() => dir.delete(recursive: true));
    }
  });
}
