import 'dart:io';

import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_app/src/app.dart';
import 'package:bodytmi_app/src/goals.dart';
import 'package:bodytmi_app/src/profile.dart';
import 'package:bodytmi_app/src/reminders.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'gym_start_test.dart' show pumped;
import 'lock_test.dart' show FakeKeyStore, waitFor;

final class FakeNotifier implements Notifier {
  bool allowed = true;
  int permits = 0;
  int cancels = 0;
  final scheduled = <(DateTime, String, String)>[];

  @override
  Future<bool> permit() async {
    permits++;
    return allowed;
  }

  @override
  Future<void> cancelAll() async {
    cancels++;
    scheduled.clear();
  }

  @override
  Future<void> schedule(int id, DateTime at, String title, String body) async =>
      scheduled.add((at, title, body));
}

void main() {
  final clock = DateTime(2026, 11, 18, 9, 30);

  testWidgets('due, not done routines of the next week are reminded', (
    tester,
  ) async {
    late Directory dir;
    late ProfileClient profile;
    final fake = FakeNotifier();
    notifier = fake;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('bodytmi-remind-');
      await buildDemoProfile('${dir.path}/p.sqlite', now: clock);
      profile = await ProfileClient.open(
        '${dir.path}/p.sqlite',
        keyStore: FakeKeyStore(),
      );
    });
    try {
      // Off: nothing is scheduled, and earlier reminders are cleared.
      expect(await pumped(tester, rescheduleReminders(profile, now: clock)), 0);
      expect(fake.cancels, 1);

      await tester.runAsync(
        () => ReminderSettings.setEnabled(profile.path, true),
      );
      final n = await pumped(tester, rescheduleReminders(profile, now: clock));
      // Today at 09:30: box breathing (07:45) is past, the walk and the
      // weigh-in are done, so only the 13:00 caffeine cutoff remains; the
      // next six days have all four routines at their planned times.
      expect(n, 1 + 6 * 4);
      expect(fake.scheduled.first, (
        DateTime(2026, 11, 18, 13),
        'Last caffeine before 13:00',
        'Due 13:00',
      ));
      expect(
        fake.scheduled
            .where((s) => s.$1.day == 19)
            .map((s) => s.$1.hour)
            .toSet(),
        {7, 13},
      );

      // The switch asks to post notifications and reports the schedule.
      await tester.runAsync(
        () => ReminderSettings.setEnabled(profile.path, false),
      );
      await tester.binding.setSurfaceSize(const Size(480, 2400));
      await tester.pumpWidget(BodyTmiApp(profile: profile, clock: clock));
      await tester.pump(const Duration(milliseconds: 300));
      openGoals(tester.element(find.byType(Scaffold).first), clock: clock);
      await waitFor(tester, find.text('Routines'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Routines'));
      await waitFor(tester, find.text('Remind me when routines are due'));
      // Let the switch read its setting before it can be tapped.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Remind me when routines are due'));
      await waitFor(tester, find.textContaining('in the next 7 days'));
      expect(fake.permits, 1);
      expect(
        await tester.runAsync(() => ReminderSettings.enabled(profile.path)),
        isTrue,
      );
    } finally {
      await pumped(tester, profile.close());
      await tester.runAsync(() => dir.delete(recursive: true));
    }
  });
}
