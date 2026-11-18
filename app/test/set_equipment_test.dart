import 'dart:io';

import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_app/src/app.dart';
import 'package:bodytmi_app/src/gym_start.dart';
import 'package:bodytmi_app/src/profile.dart';
import 'package:bodytmi_app/src/session.dart';
import 'package:bodytmi_app/src/train.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'gym_start_test.dart' show pumped;
import 'lock_test.dart' show FakeKeyStore, waitFor;

void main() {
  final clock = DateTime(2026, 11, 18, 9, 30);

  testWidgets('plate hint, recorded plates, other bar for the rest', (
    tester,
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

    Future<Map> stored(String id) => pumped(
      tester,
      profile.call<Map<String, Object?>>('store show', {'id': id}),
    );

    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('bodytmi-setequip-');
      await buildDemoProfile('${dir.path}/p.sqlite', now: clock);
      profile = await ProfileClient.open(
        '${dir.path}/p.sqlite',
        keyStore: FakeKeyStore(),
      );
    });
    try {
      await tester.binding.setSurfaceSize(const Size(480, 2800));
      await tester.pumpWidget(BodyTmiApp(profile: profile, clock: clock));
      await settle();
      final id = await pumped(
        tester,
        startRunSession(
          profile,
          'strength',
          now: clock,
          gym: const GymChoice(
            gym: 'city-gym',
            loadBindings: {'bench': 'city-bar-1'},
            unboundSlots: ['row'],
          ),
        ),
      );
      openSession(tester.element(find.byType(Scaffold).first), id);
      await waitFor(tester, find.text('Load 25 + 1.25 kg each side'));
      await settle();

      // Log set 1, then record its plates (prefilled from the plan).
      await tester.tap(find.byTooltip('Done as planned').first);
      await settle();
      await tester.tap(find.text('1').first);
      await waitFor(tester, find.text('Record plates'));
      await settle();
      await tester.tap(find.text('Record plates'));
      await waitFor(tester, find.text('Plates on Bar 1'));
      await waitFor(tester, find.text('Total 72.5 kg'));
      await tester.tap(find.byTooltip('More 2.5'));
      await settle();
      expect(find.text('Total 77.5 kg'), findsOneWidget);
      expect(
        find.textContaining('the stack is recorded as loaded'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Fewer 2.5'));
      await settle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await waitFor(tester, find.text('Plates: 25 + 1.25 kg each side'));
      var session = await stored(id);
      final first = (session['sets'] as List).first as Map;
      expect([
        for (final p in (first['loadArrangement'] as Map)['plates'] as List)
          ((p as Map)['mass'] as Map)['value'] + ':${p['count']}',
      ], unorderedEquals(['1.25:2', '25:2']));

      // Set 2 onwards on the other bar.
      await tester.tap(find.text('2').first);
      await waitFor(tester, find.text('Other equipment'));
      await settle();
      await tester.tap(find.text('Other equipment'));
      await waitFor(tester, find.text('Bar 2'));
      await settle();
      await tester.tap(find.text('Bar 2'));
      await waitFor(
        tester,
        find.textContaining('Nearest available: Weight 72.5 kg'),
      );
      await settle();
      expect(find.textContaining('On Bar 2'), findsWidgets);
      session = await stored(id);
      final bench = [
        for (final s in session['sets'] as List)
          if ((s as Map)['slot'] == 'bench') s,
      ];
      expect(bench.first['performedOn'], isNull);
      expect(
        bench
            .skip(1)
            .map((s) => (s['performedOn'] as Map)['instanceId'])
            .toSet(),
        {'city-bar-2'},
      );
    } finally {
      await pumped(tester, profile.close());
      await tester.runAsync(() => dir.delete(recursive: true));
    }
  });
}
