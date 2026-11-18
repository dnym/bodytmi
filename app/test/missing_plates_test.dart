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

  testWidgets('missing micro plates change hints for the remaining sets', (
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

    Future<List<Map>> bench(String id) async => [
      for (final s
          in (await pumped(
                tester,
                profile.call<Map<String, Object?>>('store show', {'id': id}),
              ))['sets']!
              as List)
        if ((s as Map)['slot'] == 'bench') s,
    ];

    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('bodytmi-missing-');
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
          gym: const GymChoice(gym: 'home', unboundSlots: ['pulldown']),
        ),
      );
      openSession(tester.element(find.byType(Scaffold).first), id);
      await waitFor(tester, find.text('Load 20 + 5 + 1.25 kg each side'));
      await settle();

      await tester.tap(find.text('1').first);
      await waitFor(tester, find.text('Missing plates'));
      await settle();
      await tester.tap(find.text('Missing plates'));
      await waitFor(tester, find.textContaining('Missing plates · Home bar'));
      await settle();
      await tester.tap(find.byTooltip('More missing 1.25'));
      await tester.pump();
      await tester.tap(find.byTooltip('More missing 1.25'));
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.add_circle_outline).last,
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await waitFor(
        tester,
        find.textContaining('Nearest available: Weight 70 kg or 75 kg'),
      );
      await waitFor(
        tester,
        find.text('Missing 2 × 1.25 kg · Not loadable exactly: 70 kg or 75 kg'),
      );
      var sets = await bench(id);
      expect(sets.every((s) => s['unavailablePlates'] != null), isTrue);
      expect(sets.map((s) => (s['performedOn'] as Map)['instanceId']).toSet(), {
        'home-bar',
      });

      // Back to the full stock for set 1 clears its record.
      await tester.tap(find.text('1').first);
      await waitFor(tester, find.text('Missing plates'));
      await settle();
      await tester.tap(find.text('Missing plates'));
      await waitFor(tester, find.textContaining('Missing plates · Home bar'));
      await settle();
      await tester.tap(find.byTooltip('Fewer missing 1.25'));
      await tester.tap(find.byTooltip('Fewer missing 1.25'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await waitFor(tester, find.text('Load 20 + 5 + 1.25 kg each side'));
      sets = await bench(id);
      expect(sets.first['performedOn'], isNull);
      expect(sets.first['unavailablePlates'], isNull);
      expect(sets[1]['unavailablePlates'], isNotNull);
    } finally {
      await pumped(tester, profile.close());
      await tester.runAsync(() => dir.delete(recursive: true));
    }
  });
}
