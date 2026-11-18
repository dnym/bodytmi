import 'dart:io';

import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_app/src/app.dart';
import 'package:bodytmi_app/src/practice.dart';
import 'package:bodytmi_app/src/profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'lock_test.dart' show FakeKeyStore, waitFor;

void main() {
  final clock = DateTime(2026, 11, 18, 9, 30);

  testWidgets('run, pause, end and save; recover; log without timer', (
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

    /// Real time passes (the stopwatch) while fake timers tick.
    Future<void> realTime(int milliseconds) async {
      for (var t = 0; t < milliseconds; t += 100) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<Map<String, Object?>> sessionOf(String id) => pumped(
      profile.call<Map<String, Object?>>('practice session', {'id': id}),
    );

    Future<List<Map<String, Object?>>> sessions() async =>
        (await pumped(profile.call<List<Object?>>('practice sessions')))
            .cast<Map<String, Object?>>();

    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('bodytmi-practice-');
      await buildDemoProfile('${dir.path}/p.sqlite', now: clock);
      profile = await ProfileClient.open(
        '${dir.path}/p.sqlite',
        keyStore: FakeKeyStore(),
      );
    });
    try {
      await tester.binding.setSurfaceSize(const Size(640, 2400));
      await tester.pumpWidget(BodyTmiApp(profile: profile, clock: clock));
      await tester.pump(const Duration(milliseconds: 300));
      openPractices(tester.element(find.byType(Scaffold).first), clock: clock);
      await waitFor(tester, find.text('Box breathing (4 s per side)'));
      await realTime(500);
      await tester.tap(find.text('Start').first);
      await waitFor(tester, find.text('Abandon'));
      await realTime(500);
      final id = (await sessions()).single['id']! as String;

      await tester.tap(find.widgetWithText(FilledButton, 'Start'));
      await realTime(2600);
      expect(find.text('Inhale'), findsOneWidget);
      var s = await sessionOf(id);
      expect((s['clock']! as Map)['status'], 'running');
      expect(
        (s['clock']! as Map)['effortElapsedMilliseconds'] as int,
        greaterThanOrEqualTo(1000),
      );

      await tester.tap(find.text('Pause'));
      await realTime(500);
      s = await sessionOf(id);
      expect((s['clock']! as Map)['status'], 'paused');
      final paused = (s['clock']! as Map)['effortElapsedMilliseconds'] as int;
      expect(paused, greaterThanOrEqualTo(2000));

      await tester.tap(find.text('End now'));
      await waitFor(tester, find.text('Done'));
      await tester.tap(find.textContaining('Save '));
      await waitFor(tester, find.text('Box breathing (4 s per side)'));
      await realTime(300);
      s = await sessionOf(id);
      expect(s['status'], 'confirmed');
      expect((s['actual']! as Map)['milliseconds'], paused);

      // A practice whose clock was left running by another owner.
      await pumped(
        profile.write('practice start', {
          'id': 'stale',
          'practiceId': 'box-breathing',
          'at': '2026-11-18T09:00:00+01:00',
        }),
      );
      final stale = await sessionOf('stale');
      await pumped(
        profile.call('timer resume', {
          'id': (stale['clock']! as Map)['id'],
          'expectedVersion': (stale['clock']! as Map)['version'],
          'ownerId': 'killed-process',
          'at': '2026-11-18T09:00:01+01:00',
        }),
      );
      await waitFor(tester, find.text('Continue'));
      await realTime(300);
      await tester.tap(find.text('Continue'));
      await waitFor(tester, find.text('Recover'));
      await realTime(300);
      await tester.tap(find.text('Recover'));
      await realTime(500);
      expect(((await sessionOf('stale'))['clock']! as Map)['status'], 'paused');
      await tester.tap(find.text('Abandon'));
      await waitFor(tester, find.text('Abandon this practice?'));
      await realTime(300);
      await tester.tap(find.widgetWithText(FilledButton, 'Abandon'));
      await realTime(600);
      expect((await sessionOf('stale'))['status'], 'abandoned');

      await tester.tap(find.text('Log without timer'));
      await waitFor(tester, find.text('Minutes, ending now'));
      await realTime(300);
      await tester.enterText(find.byType(TextField), '10');
      await tester.tap(find.text('Log'));
      await waitFor(tester, find.textContaining('Logged 10 min'));
      final logged = (await sessions()).where(
        (s) => (s['actual'] as Map?)?['source'] == 'manual',
      );
      expect(logged.single['actual'], {
        'milliseconds': 600000,
        'source': 'manual',
      });
    } finally {
      await pumped(profile.close());
      await tester.runAsync(() => dir.delete(recursive: true));
    }
  });
}
