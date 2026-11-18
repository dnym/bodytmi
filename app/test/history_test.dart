import 'dart:io';

import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_app/src/app.dart';
import 'package:bodytmi_app/src/history.dart';
import 'package:bodytmi_app/src/profile.dart';
import 'package:bodytmi_app/src/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'gym_start_test.dart' show pumped;
import 'lock_test.dart' show FakeKeyStore, waitFor;

void main() {
  final clock = DateTime(2026, 11, 18, 9, 30);

  testWidgets('progress per exercise, its workouts and records', (
    tester,
  ) async {
    late Directory dir;
    late ProfileClient profile;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('bodytmi-history-');
      await buildDemoProfile('${dir.path}/p.sqlite', now: clock);
      profile = await ProfileClient.open(
        '${dir.path}/p.sqlite',
        keyStore: FakeKeyStore(),
      );
    });
    try {
      await tester.binding.setSurfaceSize(const Size(480, 3200));
      await tester.pumpWidget(BodyTmiApp(profile: profile, clock: clock));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Train'));
      // The next workout shows what progression prescribes, not the
      // authored starting targets.
      await waitFor(tester, find.text('75 kg × 3'));
      await waitFor(tester, find.text('PROGRESS'));
      await waitFor(tester, find.text('One arm row'));
      // The row moved from 22 to 24.5 kg through its double progression.
      expect(
        find.descendant(
          of: find.widgetWithText(ListTile, 'One arm row'),
          matching: find.text('24.5 kg'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Bench press').last);
      await waitFor(tester, find.text('UPPER A · BENCH'));
      Finder here(String text) => find.descendant(
        of: find.byType(ExerciseHistoryScreen),
        matching: find.text(text),
      );
      expect(here('72.5 kg × 5'), findsOneWidget);
      expect(here('72.5 kg × 4'), findsOneWidget);
      expect(here('72.5 kg × 3'), findsOneWidget);
      expect(find.byType(LineChart), findsOneWidget);
      await waitFor(tester, find.text('Best at 5 reps'));
      expect(find.text('Best at 3 reps'), findsOneWidget);
      expect(find.text('Best at 4 reps'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.ensureVisible(find.widgetWithText(ListTile, 'One arm row'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.widgetWithText(ListTile, 'One arm row'));
      await waitFor(tester, find.text('UPPER A · ROW'));
      expect(here('24.5 kg × 11'), findsOneWidget);
      expect(here('22 kg × 15'), findsOneWidget);
    } finally {
      await pumped(tester, profile.close());
      await tester.runAsync(() => dir.delete(recursive: true));
    }
  });
}
