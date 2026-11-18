import 'dart:io';

import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_app/src/app.dart';
import 'package:bodytmi_app/src/format.dart' show isoInstant;
import 'package:bodytmi_app/src/profile.dart';
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

  Future<void> open(WidgetTester tester, {required bool demo}) async {
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('bodytmi-guided-');
      if (demo) await buildDemoProfile('${dir.path}/p.sqlite', now: clock);
      profile = await ProfileClient.open(
        '${dir.path}/p.sqlite',
        keyStore: FakeKeyStore(),
      );
    });
    await tester.binding.setSurfaceSize(const Size(480, 2800));
    await tester.pumpWidget(BodyTmiApp(profile: profile, clock: clock));
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> close(WidgetTester tester) async {
    await tester.tap(find.byType(BackButton).last);
    await tester.pump(const Duration(milliseconds: 500));
    await pumped(tester, profile.close());
    await tester.runAsync(() => dir.delete(recursive: true));
  }

  Future<Map<String, Object?>> execution(
    WidgetTester tester,
    String id,
  ) async => pumped(
    tester,
    profile.call<Map<String, Object?>>('execution show', {
      'id': 'execution-$id',
    }),
  );

  testWidgets('a logged set starts its rest clock; skipping moves on', (
    tester,
  ) async {
    await open(tester, demo: true);
    try {
      final id = await pumped(tester, startRunSession(profile, 'strength'));
      openSession(tester.element(find.byType(Scaffold).first), id);
      await waitFor(tester, find.text('11 sets to go'));
      var e = await execution(tester, id);
      expect(at(e, ['current', 'kind']), 'effort');

      await tester.tap(find.byTooltip('Done as planned').first);
      await waitFor(tester, find.textContaining('Rest 1:'));
      expect(find.text('of 2:00'), findsOneWidget);
      e = await execution(tester, id);
      expect(at(e, ['current', 'kind']), 'rest');
      expect(at(e, ['timer', 'status']), 'running');

      await tester.tap(find.text('Skip rest'));
      await waitFor(tester, find.text('10 sets to go'));
      e = await execution(tester, id);
      expect(at(e, ['current', 'kind']), 'effort');
      expect(at(e, ['current', 'id']), contains('bench-sets[1]'));
      expect(e['timer'], isNull);
    } finally {
      await close(tester);
    }
  });

  testWidgets('a timed set runs its clock, is reviewed, and rests', (
    tester,
  ) async {
    await open(tester, demo: false);
    try {
      Map<String, Object?> q(String v, String u) => {'value': v, 'unit': u};
      await pumped(
        tester,
        profile.write('store publish', {
          'expectedRevision': 0,
          'definition': {
            'id': 'core',
            'name': 'Core',
            'slots': [
              {
                'id': 'plank',
                'exercise': 'plank',
                'implementation': 'front-plank',
                'targets': {'duration': q('2', 's')},
              },
            ],
            'plan': {
              'id': 'workout',
              'type': 'sequence',
              'children': [
                {'id': 'p1', 'type': 'effort', 'slot': 'plank'},
                {'id': 'r1', 'type': 'rest', 'durationSeconds': 2},
                {'id': 'p2', 'type': 'effort', 'slot': 'plank'},
              ],
            },
          },
        }),
      );
      await pumped(
        tester,
        profile.write('store start', {
          'id': 's1',
          'templateId': 'core',
          'revision': 1,
          'startedAt': isoInstant(DateTime.now()),
        }),
      );
      openSession(tester.element(find.byType(Scaffold).first), 's1');
      await waitFor(tester, find.text('Start timer'));
      await tester.tap(find.text('Start timer'));
      await tester.pump(const Duration(seconds: 1));
      // ignore: avoid_print
      print([
        for (final t in tester.widgetList<Text>(find.byType(Text))) t.data,
      ]);
      await waitFor(tester, find.textContaining('Effort 0:'));
      // Real time passes; the review appears when the clock reaches 2 s.
      await waitFor(tester, find.text("Time's up"));
      await tester.tap(find.text('As planned'));
      // The authored 2 s rest runs and moves on by itself.
      await waitFor(tester, find.textContaining('Rest 0:'));
      await waitFor(tester, find.text('Start timer'));
      final session = await pumped(
        tester,
        profile.call<Map<String, Object?>>('store show', {'id': 's1'}),
      );
      final first = (session['sets']! as List).first as Map;
      expect(first['status'], 'completed');
      final ms = double.parse('${at(first, ['actuals', 'duration', 'value'])}');
      expect(ms, greaterThanOrEqualTo(2));
      final e = await execution(tester, 's1');
      expect(at(e, ['current', 'id']), 'workout/p2');
      final rest = (e['receipts']! as List).cast<Map>().firstWhere(
        (r) => r['kind'] == 'rest',
      );
      expect(rest['restElapsedMilliseconds'], 2000);
    } finally {
      await close(tester);
    }
  });
}

Object? at(Object? json, List<Object> path) {
  var c = json;
  for (final k in path) {
    c = c is Map ? c[k] : (c is List && k is int ? c[k] : null);
  }
  return c;
}
