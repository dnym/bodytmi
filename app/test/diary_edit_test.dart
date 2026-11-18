import 'dart:io';

import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_app/src/app.dart';
import 'package:bodytmi_app/src/profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'lock_test.dart' show FakeKeyStore, waitFor;

void main() {
  final clock = DateTime(2026, 11, 18, 9, 30);
  late Directory dir;
  late ProfileClient profile;

  /// Runs app work outside runAsync, pumping until it completes.
  Future<T> pumped<T>(WidgetTester tester, Future<T> future) async {
    T? result;
    var done = false;
    Object? error;
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

  Future<List<Map<String, Object?>>> entries(WidgetTester tester) async {
    final day = await pumped(
      tester,
      profile.call<Map<String, Object?>>('diary day', {'date': '2026-11-18'}),
    );
    return [
      for (final e in day['entries']! as List)
        (e as Map)['entry'] as Map<String, Object?>,
    ];
  }

  Future<void> start(WidgetTester tester) async {
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('bodytmi-diary-edit-');
      await buildDemoProfile('${dir.path}/p.sqlite', now: clock);
      profile = await ProfileClient.open(
        '${dir.path}/p.sqlite',
        keyStore: FakeKeyStore(),
      );
    });
    await tester.binding.setSurfaceSize(const Size(420, 2600));
    await tester.pumpWidget(BodyTmiApp(profile: profile, clock: clock));
    await waitFor(tester, find.text('BODY MASS TREND'));
    await tester.tap(find.text('Food'));
    await waitFor(tester, find.text('Cottage cheese 1.5%'));
  }

  Future<void> finish(WidgetTester tester) async {
    await pumped(tester, profile.close());
    await tester.runAsync(() => dir.delete(recursive: true));
  }

  testWidgets('edit keeps the pinned revision; meal and delete', (
    tester,
  ) async {
    await start(tester);
    try {
      // A newer revision of the food must not change the logged entry.
      final shown = await pumped(
        tester,
        profile.call<Map<String, Object?>>('food show', {
          'foodId': 'cottage-cheese',
        }),
      );
      final food = Map<String, Object?>.of(
        shown['food']! as Map<String, Object?>,
      )..['name'] = 'Cottage cheese 1.5% (new label)';
      await pumped(
        tester,
        profile.write('food publish', {'food': food, 'expectedRevision': 1}),
      );

      await tester.tap(find.text('Cottage cheese 1.5%'));
      await waitFor(tester, find.text('Delete entry'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.enterText(find.widgetWithText(TextField, 'Amount'), '300');
      await tester.tap(find.text('Lunch'));
      await tester.tap(find.text('Save'));
      await waitFor(tester, find.text('Entry updated'));
      await tester.pump(const Duration(milliseconds: 600));
      var list = await entries(tester);
      final edited = list.firstWhere((e) => e['id'] == 'breakfast-1');
      expect(edited['version'], 2);
      expect(edited['meal'], 'lunch');
      expect((edited['food']! as Map)['revision'], 1);
      expect(((edited['amount']! as Map)['entered']! as Map)['value'], '300');

      await tester.tap(find.text('Egg'));
      await waitFor(tester, find.text('Delete entry'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('Delete entry'));
      await waitFor(tester, find.text('Delete this entry?'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await waitFor(tester, find.text('Entry deleted'));
      list = await entries(tester);
      expect(list.map((e) => e['id']), isNot(contains('breakfast-2')));
    } finally {
      await finish(tester);
    }
  });

  testWidgets('quick entries edit their nutrients; conflicts are named', (
    tester,
  ) async {
    await start(tester);
    try {
      await pumped(
        tester,
        profile.write('diary add', {
          'entry': {
            'id': 'snack-1',
            'at': '2026-11-18T09:00:00+01:00',
            'meal': 'snack',
            'quick': {
              'energy': {'value': '300', 'unit': 'kcal'},
            },
          },
        }),
      );
      await waitFor(tester, find.text('Quick entry'));
      await tester.tap(find.text('Quick entry').first);
      await waitFor(tester, find.text('Delete entry'));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.enterText(find.widgetWithText(TextField, 'Energy'), '350');
      await tester.enterText(find.widgetWithText(TextField, 'Protein'), '20');
      await tester.tap(find.text('Save'));
      await waitFor(tester, find.text('Entry updated'));
      await tester.pump(const Duration(milliseconds: 600));
      final snack = (await entries(tester))
          .firstWhere((e) => e['id'] == 'snack-1');
      final quick = snack['quick']! as Map;
      expect(((quick['energy']! as Map)['entered']! as Map)['value'], '350');
      expect(quick.containsKey('protein'), isTrue);

      // Changed elsewhere while the editor is open.
      await tester.tap(find.text('Quick entry').first);
      await waitFor(tester, find.text('Delete entry'));
      await tester.pump(const Duration(milliseconds: 600));
      await pumped(
        tester,
        profile.call('diary update', {
          'id': 'snack-1',
          'expectedVersion': 2,
          'entry': {
            'id': 'snack-1',
            'at': '2026-11-18T09:00:00+01:00',
            'quick': {
              'energy': {'value': '100', 'unit': 'kcal'},
            },
          },
        }),
      );
      await tester.tap(find.text('Save'));
      await waitFor(tester, find.textContaining('changed elsewhere'));
    } finally {
      await finish(tester);
    }
  });
}
