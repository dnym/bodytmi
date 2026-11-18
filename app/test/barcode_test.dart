import 'dart:io';

import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_app/src/app.dart';
import 'package:bodytmi_app/src/my_foods.dart';
import 'package:bodytmi_app/src/profile.dart';
import 'package:bodytmi_app/src/quick_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'gym_start_test.dart' show pumped;
import 'lock_test.dart' show FakeKeyStore, waitFor;

void main() {
  final clock = DateTime(2026, 11, 18, 9, 30);

  testWidgets('a barcode is looked up, reviewed, saved, and found again', (
    tester,
  ) async {
    foodDataset = () async => File('../data/food/slv.json.gz').absolute.path;
    // flutter_test answers every HttpClient request with 400; this test
    // talks to its own local server instead.
    HttpOverrides.global = null;
    late Directory dir;
    late ProfileClient profile;
    late HttpServer server;
    final paths = <String>[];
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await tester.runAsync(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        paths.add(request.uri.path);
        final response = request.response
          ..headers.contentType = ContentType.json;
        if (request.uri.path == '/api/v2/product/7310070005250.json') {
          response.write(
            '{"code":"7310070005250","product":{"code":"7310070005250",'
            '"product_name":"Cola zero","nutrition_data_per":"100ml",'
            '"nutriments":{"energy-kcal_100g":1,"energy-kcal_modifier":"<",'
            '"salt_100g":0.01}}}',
          );
        } else {
          response.statusCode = 404;
          response.write('{"status":0}');
        }
        await response.close();
      });
      openFoodFactsEndpoint = 'http://127.0.0.1:${server.port}';
      dir = await Directory.systemTemp.createTemp('bodytmi-barcode-');
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
      await tester.tap(find.text('Food'));
      await waitFor(tester, find.text('Add food'));
      await settle();
      await tester.tap(find.text('Add food'));
      await waitFor(tester, find.byTooltip('Look up a barcode'));
      await settle();

      await tester.tap(find.byTooltip('Look up a barcode'));
      await waitFor(tester, find.text('Look up'));
      await settle();
      await tester.enterText(find.widgetWithText(TextField, 'Barcode'), '123');
      await tester.tap(find.text('Look up'));
      await settle();
      expect(find.text('A barcode is 6 to 14 digits.'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Barcode'),
        '7310070005250',
      );
      await tester.tap(find.text('Look up'));
      await waitFor(tester, find.text('Review food'));
      await settle();
      expect(find.textContaining('From Open Food Facts'), findsOneWidget);
      expect(paths, ['/api/v2/product/7310070005250.json']);
      // Nothing is saved yet.
      var foods = await pumped(
        tester,
        profile.call<List<Object?>>('food list'),
      );
      expect(foods.any((f) => (f! as Map)['id'] == 'off-7310070005250'), false);

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await waitFor(tester, find.text('Cola zero saved'));
      await settle();
      final saved = await pumped(
        tester,
        profile.call<Map<String, Object?>>('food show', {
          'foodId': 'off-7310070005250',
        }),
      );
      final food = saved['food']! as Map;
      expect(food['basis'], '100ml');
      expect(food['valueTypes'], {'energy': '<'});
      expect((food['source'] as Map)['kind'], 'lookup');
      // Listed in the entry screen at once.
      await waitFor(tester, find.text('Cola zero'));

      // The same barcode again opens the saved food, without a request.
      await tester.tap(find.byTooltip('Look up a barcode'));
      await waitFor(tester, find.text('Look up'));
      await settle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Barcode'),
        '7310070005250',
      );
      await tester.tap(find.text('Look up'));
      await waitFor(tester, find.text('Food'));
      expect(paths, hasLength(1));
      foods = await pumped(tester, profile.call<List<Object?>>('food list'));
      expect(
        foods.where((f) => (f! as Map)['id'] == 'off-7310070005250'),
        hasLength(1),
      );
    } finally {
      openFoodFactsEndpoint = null;
      await pumped(tester, profile.close());
      await tester.runAsync(() async {
        await server.close(force: true);
        await dir.delete(recursive: true);
      });
    }
  });
}
