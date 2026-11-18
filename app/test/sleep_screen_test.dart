import 'dart:io';

import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_app/src/app.dart';
import 'package:bodytmi_app/src/profile.dart';
import 'package:bodytmi_app/src/sleep.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'lock_test.dart' show FakeKeyStore, waitFor;

void main() {
  final clock = DateTime(2026, 11, 18, 9, 30);
  late Directory dir;
  late ProfileClient profile;

  Future<T> pumped<T>(WidgetTester tester, Future<T> future) async {
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

  Future<void> settleSheet(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester tester, {bool demo = true}) async {
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('bodytmi-sleep-');
      if (demo) await buildDemoProfile('${dir.path}/p.sqlite', now: clock);
      profile = await ProfileClient.open(
        '${dir.path}/p.sqlite',
        keyStore: FakeKeyStore(),
      );
    });
    await tester.binding.setSurfaceSize(const Size(640, 3200));
    await tester.pumpWidget(BodyTmiApp(profile: profile, clock: clock));
    await tester.pump(const Duration(milliseconds: 300));
    final ctx = tester.element(find.byType(Scaffold).first);
    openSleep(ctx, clock: clock);
    await waitFor(tester, find.text('NIGHTS'));
    await settleSheet(tester);
  }

  Future<void> close(WidgetTester tester) async {
    await pumped(tester, profile.close());
    await tester.runAsync(() => dir.delete(recursive: true));
  }

  Future<List<Map<String, Object?>>> nights(WidgetTester tester) async =>
      (await pumped(
        tester,
        profile.call<List<Object?>>('sleep list', {
          'from': '2026-11-01',
          'until': '2026-11-19',
        }),
      )).cast<Map<String, Object?>>();

  testWidgets('averages, daylight, schedule; edit and delete a night', (
    tester,
  ) async {
    await open(tester);
    try {
      expect(find.text('LAST 14 NIGHTS'), findsOneWidget);
      expect(find.text('plan 23:00–06:45'), findsOneWidget);
      expect(find.text('7 of 28 nights'), findsOneWidget);
      // NOAA for Stockholm on 18 November: sunrise 07:48, sunset 15:16.
      expect(find.text('07:48 → 15:16'), findsOneWidget);
      expect(find.text('23:00 → 06:45'), findsOneWidget);

      final before = (await nights(tester))
          .firstWhere((n) => n['date'] == '2026-11-18');
      await tester.tap(find.text('Wednesday 18 November'));
      await waitFor(tester, find.text('Fell asleep'));
      await settleSheet(tester);
      await tester.tap(find.text('5'));
      await tester.tap(find.text('Save'));
      await waitFor(tester, find.text('Sleep updated'));
      await settleSheet(tester);
      final after = (await nights(tester))
          .firstWhere((n) => n['date'] == '2026-11-18');
      expect(after['quality'], 5);
      expect(after['version'], (before['version']! as int) + 1);
      expect(after['onset'], before['onset']);

      await tester.tap(find.text('Tuesday 17 November'));
      await waitFor(tester, find.text('Delete'));
      await settleSheet(tester);
      await tester.tap(find.text('Delete'));
      await waitFor(tester, find.text('Delete this sleep?'));
      await settleSheet(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await waitFor(tester, find.text('Sleep deleted'));
      await settleSheet(tester);
      expect(
        (await nights(tester)).where((n) => n['date'] == '2026-11-17'),
        isEmpty,
      );

      // Accepting both pickers re-publishes the schedule from today.
      await tester.tap(find.text('Change').last);
      await waitFor(tester, find.text('OK'));
      await settleSheet(tester);
      await tester.tap(find.text('OK'));
      await settleSheet(tester);
      await waitFor(tester, find.text('OK'));
      await settleSheet(tester);
      await tester.tap(find.text('OK'));
      await waitFor(tester, find.textContaining('from today'));
      final schedules = await pumped(
        tester,
        profile.call<List<Object?>>('sleep schedules'),
      );
      expect(schedules, hasLength(2));
    } finally {
      await close(tester);
    }
  });

  testWidgets('a profile without location can set one', (tester) async {
    await open(tester, demo: false);
    try {
      expect(
        find.text('Set your location to see sunrise, sunset and twilight.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Set location'));
      await waitFor(tester, find.text('Latitude'));
      await settleSheet(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Latitude'),
        '59,3293',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Longitude'),
        '18.0686',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Time zone'),
        'Europe/Stockholm',
      );
      await tester.tap(find.text('Save'));
      await waitFor(tester, find.text('07:48 → 15:16'));
    } finally {
      await close(tester);
    }
  });
}
