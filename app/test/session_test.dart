import 'dart:io';

import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_app/src/app.dart';
import 'package:bodytmi_app/src/gym_start.dart';
import 'package:bodytmi_app/src/profile.dart';
import 'package:bodytmi_app/src/session.dart';
import 'package:bodytmi_locale/bodytmi_locale.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  final clock = DateTime(2026, 11, 18, 9, 30);

  test('typed decimals accept either decimal mark', () {
    final sv = PresentationLocale.resolve('sv');
    expect(parseDecimal(sv, '72,5'), '72.5');
    expect(parseDecimal(sv, '72.5'), '72.5');
    expect(parseDecimal(PresentationLocale.resolve('en'), '80'), '80');
    expect(parseDecimal(sv, 'abc'), isNull);
  });

  testWidgets('start, log as planned, enter, skip, finish', (tester) async {
    late Directory dir;
    late ProfileClient profile;
    Future<void> settle() async {
      for (var i = 0; i < 15; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('bodytmi-session-');
      await buildDemoProfile('${dir.path}/p.sqlite', now: clock);
      profile = await ProfileClient.open('${dir.path}/p.sqlite');
    });
    try {
      await tester.binding.setSurfaceSize(const Size(420, 2600));
      await tester.pumpWidget(BodyTmiApp(profile: profile, clock: clock));
      await settle();
      await tester.tap(find.text('Train'));
      await settle();
      await tester.tap(find.text('Start workout'));
      await settle();
      // The profile has gyms: start without one.
      expect(find.text('Where are you training?'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(GymStartSheet),
          matching: find.widgetWithText(FilledButton, 'Start workout'),
        ),
      );
      await settle();
      expect(find.text('bench press'.toUpperCase()), findsOneWidget);
      expect(find.text('11 sets to go'), findsOneWidget);

      // Set 1 as planned: the rest cue starts from the authored 120 s.
      await tester.tap(find.byTooltip('Done as planned').first);
      await settle();
      expect(find.textContaining('Rest '), findsOneWidget);
      expect(find.text('of 2:00'), findsOneWidget);

      // Set 2 entered differently.
      await tester.tap(find.text('2').first);
      await settle();
      await tester.enterText(find.widgetWithText(TextField, 'Reps'), '2');
      await tester.tap(find.text('Log set'));
      await settle();
      // Set 3 skipped.
      await tester.tap(find.text('3').first);
      await settle();
      await tester.tap(find.text('Skip set'));
      await settle();

      // Finish skips the rest after confirmation.
      await tester.tap(find.text('Finish'));
      await settle();
      expect(
        find.textContaining('8 planned sets are not logged'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Finish').last);
      await settle();

      final history = await tester.runAsync(
        () => profile.call<List<Object?>>('store history'),
      );
      final session = history!.cast<Map<String, Object?>>().firstWhere(
        (s) => '${s['id']}'.startsWith('session-2026'),
      );
      expect(session['status'], 'finalized');
      final sets = (session['sets']! as List).cast<Map<String, Object?>>();
      expect(sets[0]['status'], 'completed');
      expect(((sets[1]['actuals']! as Map)['reps']! as Map)['value'], '2');
      expect(sets[2]['status'], 'skipped');
      expect(sets.where((s) => s['status'] == 'skipped').length, 9);
      // The finished workout stays open with its progression proposals.
      await settle();
      expect(find.text('PROGRESSION'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await settle();
      // The run moved on to the next day.
      expect(find.text('Lower A'), findsWidgets);
    } finally {
      await tester.runAsync(() async {
        await profile.close();
        await dir.delete(recursive: true);
      });
    }
  });
}
