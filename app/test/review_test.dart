import 'dart:io';

import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_app/src/app.dart';
import 'package:bodytmi_app/src/goals.dart';
import 'package:bodytmi_app/src/profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'gym_start_test.dart' show pumped;
import 'lock_test.dart' show FakeKeyStore, waitFor;

void main() {
  final clock = DateTime(2026, 11, 18, 9, 30);

  testWidgets('add, run over periods and edit a saved review', (tester) async {
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

    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('bodytmi-review-');
      await buildDemoProfile('${dir.path}/p.sqlite', now: clock);
      profile = await ProfileClient.open(
        '${dir.path}/p.sqlite',
        keyStore: FakeKeyStore(),
      );
    });
    try {
      await tester.binding.setSurfaceSize(const Size(640, 2600));
      await tester.pumpWidget(BodyTmiApp(profile: profile, clock: clock));
      await settle();
      openGoals(tester.element(find.byType(Scaffold).first), clock: clock);
      await waitFor(tester, find.text('Reviews'));
      await settle();
      await tester.tap(find.text('Reviews'));
      await waitFor(tester, find.textContaining('No reviews yet'));
      await tester.tap(find.text('Add review'));
      await waitFor(tester, find.text('New review'));
      await settle();
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Weekly');
      await tester.tap(find.text('Sleep, asleep to awake'));
      await tester.tap(find.text('Training sessions'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await waitFor(tester, find.text('WEEKLY'));
      await waitFor(tester, find.textContaining('of 7 days known'));
      expect(
        find.text('Mean 428.6 min · 414–448 min · 7 of 7 days known'),
        findsOneWidget,
      );
      expect(find.text('Mean 1 sessions · 2 of 7 days known'), findsOneWidget);
      await tester.tap(find.text('28 days'));
      await waitFor(tester, find.textContaining('of 28 days known'));

      await tester.tap(find.byTooltip('Edit review'));
      await waitFor(tester, find.text('Review'));
      await settle();
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Sunday');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await waitFor(tester, find.text('SUNDAY'));
      final reviews = await pumped(
        tester,
        profile.call<List<Object?>>('review list'),
      );
      final r = reviews.single! as Map;
      expect(r['version'], 2);
      expect((r['metrics'] as List).length, 2);
    } finally {
      await pumped(tester, profile.close());
      await tester.runAsync(() => dir.delete(recursive: true));
    }
  });
}
