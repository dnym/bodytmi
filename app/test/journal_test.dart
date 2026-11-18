import 'dart:io';

import 'package:bodytmi_app/src/app.dart';
import 'package:bodytmi_app/src/journal.dart';
import 'package:bodytmi_app/src/profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'lock_test.dart' show FakeKeyStore, waitFor;

void main() {
  final clock = DateTime(2026, 11, 18, 9, 30);

  test('typed names become attribute identifiers', () {
    expect(journalSlug('Lower back'), 'lower-back');
    expect(journalSlug('  Huvudvärk! '), 'huvudvark');
    expect(journalSlug('   '), '');
  });

  testWidgets('right now, pain, illness edit and delete', (tester) async {
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

    Future<List<Map<String, Object?>>> list(String measure) async => [
      for (final o in (await pumped(
        profile.call<List<Object?>>('observation list', {'measure': measure}),
      )).cast<Map>())
        if (o['deleted'] != true) o['observation'] as Map<String, Object?>,
    ];

    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('bodytmi-journal-');
      profile = await ProfileClient.open(
        '${dir.path}/p.sqlite',
        keyStore: FakeKeyStore(),
      );
      await profile.call('observation record', {
        'observation': {
          'id': 'cold-1',
          'measure': 'illness',
          'observedAt': '2026-11-15T08:00:00+01:00',
          'value': {'end': '2026-11-17T20:00:00+01:00'},
          'attributes': {'name': 'cold'},
        },
      });
    });
    try {
      await tester.binding.setSurfaceSize(const Size(640, 3000));
      await tester.pumpWidget(BodyTmiApp(profile: profile, clock: clock));
      await tester.pump(const Duration(milliseconds: 300));
      openJournal(tester.element(find.byType(Scaffold).first), clock: clock);
      await waitFor(tester, find.text('RIGHT NOW'));
      await settle();
      expect(find.text('Illness · cold until 2026-11-17'), findsOneWidget);

      // Only the slider that was moved is recorded; nothing defaults to 0.
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(RatingField, 'Mood'),
          matching: find.text('5'),
        ),
      );
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
      await settle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await waitFor(tester, find.text('Saved to the journal'));
      final moods = await list('mood');
      expect(moods, hasLength(1));
      expect(moods.single['value'], 5);
      expect(await list('energy-level'), isEmpty);

      await tester.tap(find.text('Pain'));
      await waitFor(tester, find.text('How bad'));
      await settle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
      await settle();
      expect(find.text('Choose a rating.'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Where'),
        'Lower back',
      );
      await tester.tap(
        find.descendant(
          of: find.widgetWithText(RatingField, 'How bad'),
          matching: find.text('6'),
        ),
      );
      await tester.tap(find.text('left'));
      await tester.tap(find.text('minor'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
      await waitFor(tester, find.text('Saved to the journal'));
      await settle();
      final pain = (await list('pain')).single;
      expect(pain['attributes'], {
        'impact': 'minor',
        'side': 'left',
        'site': 'lower-back',
      });

      // A new illness ending at its start is refused.
      await tester.tap(find.text('Illness').first);
      await waitFor(tester, find.text('Started'));
      await settle();
      await tester.enterText(find.widgetWithText(TextField, 'What'), 'flu');
      await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
      await settle();
      expect(find.text('The end is after the start.'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await settle();

      // Edit the existing illness, then delete the pain entry.
      await tester.tap(find.text('Illness · cold until 2026-11-17'));
      await waitFor(tester, find.text('Delete'));
      await settle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
      await waitFor(tester, find.text('Entry updated'));
      await settle();
      final cold = (await list('illness')).single;
      expect(cold['contentVersion'], 2);
      expect((cold['value']! as Map)['end'], '2026-11-17T20:00:00+01:00');

      await tester.tap(find.text('Pain · lower back · left · minor'));
      await waitFor(tester, find.text('Delete'));
      await settle();
      await tester.tap(find.text('Delete'));
      await waitFor(tester, find.text('Delete this entry?'));
      await settle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await waitFor(tester, find.text('Entry deleted'));
      expect(await list('pain'), isEmpty);
    } finally {
      await pumped(profile.close());
      await tester.runAsync(() => dir.delete(recursive: true));
    }
  });
}
