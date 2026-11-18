import 'dart:io';

import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_app/src/app.dart';
import 'package:bodytmi_app/src/profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Real profiles on disk through the real commands; only time is fixed.
void main() {
  final clock = DateTime(2026, 11, 18, 9, 30);
  late Directory dir;
  late ProfileClient profile;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
  }

  tearDown(() async {
    await profile.close();
    await dir.delete(recursive: true);
  });

  testWidgets('demo profile: Today by area and by time, every tab', (
    tester,
  ) async {
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('bodytmi-app-');
      await buildDemoProfile('${dir.path}/p.sqlite', now: clock);
      profile = await ProfileClient.open('${dir.path}/p.sqlite');
    });
    await tester.binding.setSurfaceSize(const Size(400, 2400));
    await tester.pumpWidget(BodyTmiApp(profile: profile, clock: clock));
    await settle(tester);

    expect(find.text('Wednesday 18 November'), findsOneWidget);
    expect(find.text('BODY MASS TREND'), findsOneWidget);
    expect(find.text('Deficit day'), findsOneWidget);
    expect(find.text('Upper A'), findsOneWidget);
    expect(find.text('Weigh in'), findsOneWidget);
    expect(find.textContaining('kcal left'), findsOneWidget);

    await tester.tap(find.text('By time'));
    await settle(tester);
    expect(find.text('now'), findsOneWidget);
    expect(find.textContaining('Breakfast ·'), findsOneWidget);
    expect(find.textContaining('Slept'), findsOneWidget);
    expect(find.text('Last caffeine before 13:00'), findsOneWidget);

    await tester.tap(find.text('Train'));
    await settle(tester);
    expect(find.text('Upper/Lower'.toUpperCase()), findsOneWidget);
    expect(find.text('Lower A'), findsWidgets);

    await tester.tap(find.text('Food'));
    await settle(tester);
    expect(find.textContaining('Cottage cheese'), findsOneWidget);

    await tester.tap(find.text('Body'));
    await settle(tester);
    expect(find.text('COMPOSITION'), findsOneWidget);
    expect(find.text('FFMI'), findsOneWidget);

    await tester.tap(find.text('More'));
    await settle(tester);
    expect(find.text('Device unlock'), findsOneWidget);
  });

  testWidgets('an empty profile shows empty states, never zeros', (
    tester,
  ) async {
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('bodytmi-app-');
      profile = await ProfileClient.open('${dir.path}/p.sqlite');
    });
    await tester.binding.setSurfaceSize(const Size(400, 2400));
    await tester.pumpWidget(BodyTmiApp(profile: profile, clock: clock));
    await settle(tester);
    expect(find.text('No weigh-ins yet.'), findsOneWidget);
    expect(find.text('No active program.'), findsOneWidget);
    expect(find.text('No sleep logged for last night.'), findsOneWidget);
    expect(find.text('Nothing logged today.'), findsOneWidget);
    expect(find.textContaining('kcal'), findsNothing);
  });
}
