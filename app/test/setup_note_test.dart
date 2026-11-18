import 'dart:io';

import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_app/src/app.dart';
import 'package:bodytmi_app/src/gym_start.dart';
import 'package:bodytmi_app/src/gyms.dart';
import 'package:bodytmi_app/src/profile.dart';
import 'package:bodytmi_app/src/session.dart';
import 'package:bodytmi_app/src/train.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'gym_start_test.dart' show pumped;
import 'lock_test.dart' show FakeKeyStore, waitFor;

void main() {
  final clock = DateTime(2026, 11, 18, 9, 30);

  testWidgets('a gym setup note is frozen into a session started there', (
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

    Future<Map> home() async => [
      for (final r in await pumped(
        tester,
        profile.call<List<Object?>>('gym list'),
      ))
        r! as Map,
    ].lastWhere((r) => (r['gym'] as Map)['id'] == 'home');

    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('bodytmi-setupnote-');
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
      openGyms(tester.element(find.byType(Scaffold).first));
      await waitFor(tester, find.text('Home bar'));
      await settle();
      // City gym is listed first; Home's button is the last one.
      await tester.tap(find.text('Setup note').last);
      await waitFor(tester, find.text('Setup note at Home'));
      await settle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await settle();
      await tester.tap(find.text('Bench press').last);
      await settle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Note'),
        'Bench by the window, rack pins at 9',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await waitFor(tester, find.text('Setup note saved'));
      await settle();
      await waitFor(
        tester,
        find.textContaining('Bench press: Bench by', findRichText: true),
      );
      expect(((await home())['gym'] as Map)['setupNotes'], {
        'bench-press': 'Bench by the window, rack pins at 9',
      });

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
      await waitFor(tester, find.text('Bench by the window, rack pins at 9'));
      await tester.tap(find.byType(BackButton).last);
      await settle();

      // Removing the note keeps the session's frozen copy.
      await tester.tap(
        find.textContaining('Bench press: Bench by', findRichText: true),
      );
      await waitFor(tester, find.text('Remove note'));
      await settle();
      await tester.tap(find.text('Remove note'));
      await waitFor(tester, find.text('Setup note removed'));
      expect(((await home())['gym'] as Map).containsKey('setupNotes'), false);
      final session = await pumped(
        tester,
        profile.call<Map<String, Object?>>('store show', {'id': id}),
      );
      expect(session['gymSetupNotes'], {
        'bench': 'Bench by the window, rack pins at 9',
      });
    } finally {
      await pumped(tester, profile.close());
      await tester.runAsync(() => dir.delete(recursive: true));
    }
  });
}
