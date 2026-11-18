import 'dart:convert';
import 'dart:io';

import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_app/src/app.dart';
import 'package:bodytmi_app/src/profile.dart';
import 'package:bodytmi_app/src/program_start.dart';
import 'package:bodytmi_app/src/session.dart';
import 'package:bodytmi_app/src/train.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'gym_start_test.dart' show pumped;
import 'lock_test.dart' show FakeKeyStore, waitFor;

void main() {
  final clock = DateTime(2026, 11, 18, 9, 30);
  late Directory dir;
  late ProfileClient profile;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester tester, {required bool demo}) async {
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('bodytmi-progression-');
      if (demo) await buildDemoProfile('${dir.path}/p.sqlite', now: clock);
      profile = await ProfileClient.open(
        '${dir.path}/p.sqlite',
        keyStore: FakeKeyStore(),
      );
    });
    await tester.binding.setSurfaceSize(const Size(480, 3000));
    await tester.pumpWidget(BodyTmiApp(profile: profile, clock: clock));
    await settle(tester);
  }

  Future<void> close(WidgetTester tester) async {
    await pumped(tester, profile.close());
    await tester.runAsync(() => dir.delete(recursive: true));
  }

  testWidgets('a finished workout proposes per slot; accept and decline', (
    tester,
  ) async {
    await open(tester, demo: true);
    try {
      final id = await pumped(tester, startRunSession(profile, 'strength'));
      var session = await pumped(
        tester,
        profile.call<Map<String, Object?>>('store show', {'id': id}),
      );
      for (final set in (session['sets']! as List).cast<Map>()) {
        session = await pumped(
          tester,
          profile.write<Map<String, Object?>>('store complete', {
            'id': id,
            'expectedVersion': session['contentVersion'],
            'setId': set['id'],
            'acceptSuggested': true,
          }),
        );
      }
      await pumped(
        tester,
        profile.write('store finish', {
          'id': id,
          'expectedVersion': session['contentVersion'],
          'finishedAt': isoInstantForTest(DateTime.now()),
        }),
      );
      openSession(tester.element(find.byType(Scaffold).first), id);
      await waitFor(tester, find.text('PROGRESSION'));
      await waitFor(tester, find.text('Next: 75 kg × 4 · 5 sets'));
      expect(find.text('Add reps'), findsNWidgets(3));
      expect(find.text('Next: 24.5 kg × 13 · 3 sets'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Accept').first);
      await waitFor(tester, find.text('accepted'));
      await settle(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Decline').last);
      await waitFor(tester, find.text('declined'));
      Future<String> status(String slot) async =>
          '${(await pumped(tester, profile.call<Map<String, Object?>>('progression show', {'sessionId': id, 'slotId': slot})))['status']}';
      expect(await status('bench'), 'accepted');
      expect(await status('row'), 'declined');
      expect(await status('pulldown'), 'pending');
    } finally {
      await close(tester);
    }
  });

  testWidgets('an empty profile adds the starter catalog and starts GZCLP', (
    tester,
  ) async {
    starterCatalog = () async =>
        jsonDecode(await File('../data/starter-catalog.json').readAsString())
            as Map<String, Object?>;
    await open(tester, demo: false);
    try {
      await tester.tap(find.text('Train'));
      await settle(tester);
      await tester.tap(find.text('Start a program'));
      await waitFor(tester, find.text('Add the starter catalog'));
      await settle(tester);
      await tester.tap(find.text('Add the starter catalog'));
      await waitFor(tester, find.text('GZCLP'));
      await settle(tester);
      await tester.tap(find.text('GZCLP'));
      await waitFor(tester, find.text('YOUR CHOICES'));
      await settle(tester);
      final scroller = find
          .descendant(
            of: find.byType(BlueprintScreen),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('Create the program'),
        400,
        scrollable: scroller,
      );
      await tester.tap(find.text('Create the program'));
      await waitFor(tester, find.textContaining('Enter Lat pulldown'));
      Finder field(String id) => find.byKey(ValueKey('choice-$id'));
      Future<void> enter(String hint, String value, double delta) async {
        await tester.scrollUntilVisible(
          field(hint),
          delta,
          scrollable: scroller,
        );
        await tester.enterText(field(hint), value);
      }

      await enter('squat-t1', '60', -400);
      await enter('pulldown-start', '30', 400);
      await enter('row-start', '16', 400);
      await tester.scrollUntilVisible(
        find.text('Create the program'),
        400,
        scrollable: scroller,
      );
      await tester.tap(find.text('Create the program'));
      await waitFor(tester, find.text('Start GZCLP'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Start'));
      await waitFor(tester, find.text('GZCLP started'));
      await settle(tester);
      await waitFor(tester, find.text('GZCLP A1'));
      expect(find.text('Start workout'), findsOneWidget);
      final runs = await pumped(
        tester,
        profile.call<List<Object?>>('run list'),
      );
      final run = runs.single! as Map;
      expect(run['id'], 'gzclp');
      expect(at(run, ['program', 'definition', 'id']), 'gzclp');
      final a1 = await pumped(
        tester,
        profile.call<Map<String, Object?>>('store revision', {
          'templateId': 'gzclp-a1',
          'revision': 1,
        }),
      );
      final t1 = (at(a1, ['definition', 'slots']) as List).first as Map;
      expect(at(t1, ['targets', 'load', 'value']), '60');
      expect(at(t1, ['progression', 'preset', 'id']), 'gzclp-t1-lower');
    } finally {
      await close(tester);
    }
  });
}

String isoInstantForTest(DateTime t) {
  final o = t.timeZoneOffset;
  String two(int v) => v.abs().toString().padLeft(2, '0');
  return '${t.toIso8601String().split('.').first}'
      '${o.isNegative ? '-' : '+'}${two(o.inHours)}:${two(o.inMinutes % 60)}';
}

Object? at(Object? json, List<Object> path) {
  var c = json;
  for (final k in path) {
    c = c is Map ? c[k] : (c is List && k is int ? c[k] : null);
  }
  return c;
}
