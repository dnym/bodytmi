import 'dart:io';

import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_app/src/app.dart';
import 'package:bodytmi_app/src/gyms.dart';
import 'package:bodytmi_app/src/profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'lock_test.dart' show FakeKeyStore, waitFor;

void main() {
  final clock = DateTime(2026, 11, 18, 9, 30);

  test('free identifiers avoid taken ones', () {
    expect(freeId('City gym', const []), 'city-gym');
    expect(freeId('City gym', const ['city-gym', 'city-gym-2']), 'city-gym-3');
    expect(freeId('!!', const [], fallback: 'gym'), 'gym');
  });

  testWidgets('plates, preference, new gym and kind, editing a bar', (
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

    Future<List<Map>> rows(String command) async => [
      for (final r in await pumped(profile.call<List<Object?>>(command)))
        r! as Map,
    ];

    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('bodytmi-gyms-');
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
      openGyms(tester.element(find.byType(Scaffold).first));
      await waitFor(tester, find.text('Home bar'));
      await settle();
      expect(find.text('CITY GYM'), findsOneWidget);
      expect(find.textContaining('2.5–30 kg in steps of 2.5'), findsOneWidget);

      await tester.tap(find.text('Home bar'));
      await waitFor(tester, find.text('PLATE CALCULATOR'));
      await settle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Target load'),
        '62.5',
      );
      await tester.tap(find.text('Calculate'));
      await waitFor(tester, find.text('Exactly 62.5 kg:'));
      expect(find.text('Each side: 1 × 20 kg, 1 × 1.25 kg'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Target load'),
        '101',
      );
      await tester.tap(find.text('Calculate'));
      await waitFor(
        tester,
        find.text('Not enough plates for 101 kg; nearest lower:'),
      );
      expect(find.text('97.5 kg (lower)'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Target load'),
        '81',
      );
      await tester.tap(find.text('Calculate'));
      await waitFor(tester, find.text('81 kg is not possible; nearest:'));
      expect(find.text('80 kg (lower)'), findsOneWidget);
      expect(find.text('82.5 kg (higher)'), findsOneWidget);

      // Edit: a 15 kg bar is a new revision.
      await tester.tap(find.byTooltip('Edit'));
      await waitFor(tester, find.text('Equipment'));
      await settle();
      await tester.enterText(find.widgetWithText(TextField, 'Mass'), '15');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await waitFor(tester, find.text('Revision 2'));
      final bar = (await rows('instance list'))
          .lastWhere((r) => (r['instance'] as Map)['id'] == 'home-bar');
      expect(bar['revision'], 2);
      expect(
        (((bar['instance'] as Map)['loading'] as Map)['components'] as List)
            .single,
        containsPair('mass', containsPair('value', '15')),
      );
      expect(
        (((bar['instance'] as Map)['loading'] as Map)['plates'] as List).length,
        5,
      );
      await tester.pageBack();
      await settle();

      await tester.tap(find.text('Bar 2'));
      await waitFor(tester, find.text('Prefer this one here'));
      await settle();
      await tester.tap(find.text('Prefer this one here'));
      await waitFor(tester, find.text('preferred here'));
      final city = (await rows('gym list'))
          .lastWhere((r) => (r['gym'] as Map)['id'] == 'city-gym');
      expect((city['gym'] as Map)['preferred'], {
        'olympic-barbell': 'city-bar-2',
      });
      await tester.pageBack();
      await settle();

      await tester.tap(find.text('Add'));
      await settle();
      await tester.tap(find.text('Gym'));
      await waitFor(tester, find.text('New gym'));
      await settle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'Work gym',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await waitFor(tester, find.text('WORK GYM'));
      await settle();

      await tester.tap(find.text('Add'));
      await settle();
      await tester.tap(find.text('Equipment'));
      await waitFor(tester, find.text('New equipment'));
      await settle();
      await tester.tap(find.text('Adjustable dumbbell').last);
      await settle();
      await tester.tap(find.text('New kind…').last);
      await settle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Kind of equipment'),
        'Kettlebell',
      );
      await tester.tap(find.text('Interchangeable'));
      await tester.tap(find.text('Neither'));
      await settle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await waitFor(tester, find.text('Equipment added'));
      await settle();
      final kinds = await rows('equipment list');
      expect(
        kinds
            .map((k) => k['equipment'] as Map)
            .firstWhere((e) => e['id'] == 'kettlebell'),
        {'id': 'kettlebell', 'name': 'Kettlebell', 'interchangeable': true},
      );
      final added = (await rows('instance list'))
          .map((r) => r['instance'] as Map)
          .firstWhere((i) => i['equipmentId'] == 'kettlebell');
      expect(added['equipmentId'], 'kettlebell');
      expect(added['gym'], 'city-gym');
      expect(added.containsKey('loading') || added.containsKey('scale'), false);
    } finally {
      await pumped(profile.close());
      await tester.runAsync(() => dir.delete(recursive: true));
    }
  });
}
