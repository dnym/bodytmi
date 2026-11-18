import 'dart:io';

import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_app/src/app.dart';
import 'package:bodytmi_app/src/gym_start.dart';
import 'package:bodytmi_app/src/profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'lock_test.dart' show FakeKeyStore, waitFor;

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

void main() {
  final clock = DateTime(2026, 11, 18, 9, 30);

  Future<void> run(
    WidgetTester tester,
    Future<void> Function(ProfileClient profile, Future<void> Function() settle)
    body,
  ) async {
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
      dir = await Directory.systemTemp.createTemp('bodytmi-gymstart-');
      await buildDemoProfile('${dir.path}/p.sqlite', now: clock);
      profile = await ProfileClient.open(
        '${dir.path}/p.sqlite',
        keyStore: FakeKeyStore(),
      );
    });
    try {
      await tester.binding.setSurfaceSize(const Size(480, 2600));
      await tester.pumpWidget(BodyTmiApp(profile: profile, clock: clock));
      await settle();
      await tester.tap(find.text('Train'));
      await settle();
      await tester.tap(find.text('Start workout'));
      await waitFor(tester, find.text('Where are you training?'));
      await settle();
      await body(profile, settle);
    } finally {
      await pumped(tester, profile.close());
      await tester.runAsync(() => dir.delete(recursive: true));
    }
  }

  Future<Map> current(WidgetTester tester, ProfileClient profile) async {
    final run = await tester.runAsync(
      () =>
          profile.call<Map<String, Object?>>('run show', {'runId': 'strength'}),
    );
    final session = await tester.runAsync(
      () => profile.call<Map<String, Object?>>('store show', {
        'id': run!['currentSessionId'],
      }),
    );
    return {'run': run, 'session': session};
  }

  testWidgets('at home: missing cable trained without, others bound', (
    tester,
  ) async {
    await run(tester, (profile, settle) async {
      await tester.tap(find.text('Home'));
      await waitFor(tester, find.text('None at this gym.'));
      await settle();
      expect(find.text('Home bar'), findsOneWidget);
      expect(find.text('Home dumbbells'), findsOneWidget);
      final start = find.descendant(
        of: find.byType(GymStartSheet),
        matching: find.widgetWithText(FilledButton, 'Start workout'),
      );
      expect(tester.widget<FilledButton>(start).onPressed, isNull);
      await tester.tap(find.text('Train without it'));
      await waitFor(tester, find.text('Without equipment'));
      expect(tester.widget<FilledButton>(start).onPressed, isNotNull);
      await tester.tap(start);
      await waitFor(tester, find.textContaining('· Home'));
      await settle();
      expect(find.textContaining('Home bar'), findsOneWidget);
      final d = await current(tester, profile);
      final session = d['session'] as Map;
      expect(session['gym'], 'home');
      final inputs = session['loadInputs'] as Map;
      expect(inputs.keys, unorderedEquals(['bench', 'row']));
      expect(
        (inputs['bench'] as Map)['instance'],
        containsPair('instanceId', 'home-bar'),
      );
      expect((d['run'] as Map)['gym'], isNull);
    });
  });

  testWidgets('at the city gym: choose a bar and make it the default', (
    tester,
  ) async {
    await run(tester, (profile, settle) async {
      await tester.tap(find.text('City gym'));
      await waitFor(tester, find.text('Bar 2'));
      await settle();
      expect(find.text('choose'), findsOneWidget);
      expect(find.text('Cable tower'), findsOneWidget);
      await tester.tap(find.text('Bar 2'));
      await waitFor(tester, find.text('Train without it'));
      await settle();
      await tester.tap(find.text('Train without it'));
      await settle();
      await tester.tap(find.text('Use this gym by default for this program'));
      await settle();
      await tester.tap(
        find.descendant(
          of: find.byType(GymStartSheet),
          matching: find.widgetWithText(FilledButton, 'Start workout'),
        ),
      );
      await waitFor(tester, find.textContaining('· City gym'));
      await settle();
      final d = await current(tester, profile);
      final session = d['session'] as Map;
      expect(session['gym'], 'city-gym');
      final inputs = session['loadInputs'] as Map;
      expect(
        (inputs['bench'] as Map)['instance'],
        containsPair('instanceId', 'city-bar-2'),
      );
      expect(
        (inputs['pulldown'] as Map)['instance'],
        containsPair('instanceId', 'city-cable'),
      );
      expect(inputs.containsKey('row'), false);
      expect((d['run'] as Map)['gym'], 'city-gym');
    });
  });
}
