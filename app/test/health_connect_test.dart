import 'dart:io';

import 'package:bodytmi_app/src/app.dart';
import 'package:bodytmi_app/src/health_connect.dart';
import 'package:bodytmi_app/src/profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'gym_start_test.dart' show pumped;
import 'lock_test.dart' show FakeKeyStore, waitFor;

final class FakeSteps implements StepsSource {
  bool allowed = false;
  final totals = <String, int>{};
  int asked = 0;

  @override
  Future<bool> available() async => true;
  @override
  Future<bool> permitted() async => allowed;
  @override
  Future<bool> authorize() async {
    asked++;
    return allowed = true;
  }

  @override
  Future<int?> total(DateTime start, DateTime end) async {
    final key =
        '${start.year}-${start.month.toString().padLeft(2, '0')}-'
        '${start.day.toString().padLeft(2, '0')}';
    return totals[key];
  }
}

void main() {
  testWidgets('connect, import daily totals, update a growing day', (
    tester,
  ) async {
    final today = DateTime.now();
    String day(int back) {
      final d = DateTime(today.year, today.month, today.day - back);
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
    }

    final fake = FakeSteps()
      ..totals.addAll({day(0): 3200, day(1): 9000, day(3): 12000});
    stepsSource = fake;
    late Directory dir;
    late ProfileClient profile;
    Future<List<Map>> steps() async => [
      for (final r in await pumped(
        tester,
        profile.call<List<Object?>>('observation list', {'measure': 'steps'}),
      ))
        (r! as Map)['observation'] as Map,
    ];

    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('bodytmi-hc-');
      profile = await ProfileClient.open(
        '${dir.path}/p.sqlite',
        keyStore: FakeKeyStore(),
      );
    });
    try {
      await tester.binding.setSurfaceSize(const Size(480, 2400));
      await tester.pumpWidget(BodyTmiApp(profile: profile));
      await tester.pump(const Duration(milliseconds: 300));
      openHealthConnect(tester.element(find.byType(Scaffold).first));
      await waitFor(tester, find.text('Connect Health Connect'));
      await tester.tap(find.text('Connect Health Connect'));
      await waitFor(tester, find.text('Imported 3 days of steps.'));
      expect(fake.asked, 1);
      var list = await steps();
      expect(
        {for (final o in list) '${o['date']}': o['value']},
        {
          day(0): {'unit': 'step', 'value': '3200'},
          day(1): {'unit': 'step', 'value': '9000'},
          day(3): {'unit': 'step', 'value': '12000'},
        },
      );
      expect(list.map((o) => o['source']).toSet(), {'Health Connect'});

      // Later the same day: only today's total changed.
      fake.totals[day(0)] = 6100;
      await tester.tap(find.text('Import the last 30 days'));
      await waitFor(tester, find.text('Imported 1 day of steps.'));
      list = await steps();
      expect(list, hasLength(3));
      expect(list.firstWhere((o) => o['date'] == day(0))['value'], {
        'unit': 'step',
        'value': '6100',
      });
      await tester.tap(find.text('Import the last 30 days'));
      await waitFor(tester, find.text('Up to date.'));
      expect(find.text('6,100'), findsOneWidget);
    } finally {
      await pumped(tester, profile.close());
      await tester.runAsync(() => dir.delete(recursive: true));
    }
  });
}
