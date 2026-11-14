import 'package:bodytmi_flutter/bodytmi_flutter.dart';
import 'package:bodytmi_locale/bodytmi_locale.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

const _locales = [
  Locale('en', 'US'),
  Locale('en', 'GB'),
  Locale('sv', 'SE'),
  Locale('de', 'DE'),
  Locale('fr', 'FR'),
  Locale('hi', 'IN'),
  Locale('ar', 'EG'),
  Locale('ja', 'JP'),
  Locale('pt', 'BR'),
];

Future<BuildContext> _context(WidgetTester tester, Locale locale) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: _locales,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox();
        },
      ),
    ),
  );
  return captured;
}

void main() {
  for (final locale in _locales) {
    testWidgets('$locale agrees with Material localizations', (tester) async {
      final context = await _context(tester, locale);
      final material = MaterialLocalizations.of(context);
      final shared = BodyTmiLocaleAdapter.of(context);

      expect(
        BodyTmiLocaleAdapter.materialFirstDayOfWeekIndex(shared),
        material.firstDayOfWeekIndex,
      );
      final format = material.timeOfDayFormat();
      expect(
        BodyTmiLocaleAdapter.uses24HourClock(shared),
        hourFormat(of: format) != HourFormat.h,
      );
      // Number symbols come from the same CLDR data Flutter's intl uses.
      final symbols = NumberFormat.decimalPattern(shared.resolved).symbols;
      expect(shared.info()['decimalSeparator'], symbols.DECIMAL_SEP);
      expect(shared.info()['groupSeparator'], symbols.GROUP_SEP);
    });
  }

  testWidgets('presentation round-trips never change canonical values', (
    tester,
  ) async {
    for (final locale in _locales) {
      final context = await _context(tester, locale);
      final shared = BodyTmiLocaleAdapter.of(context);
      for (final value in ['0', '82.5', '-1234567.125']) {
        final text = formatNumber(shared, value)['text']! as String;
        expect(
          parseNumber(shared, text, allowGrouping: true)['value'],
          value,
          reason: '$locale $text',
        );
      }
      final clock = formatDuration(shared, 3725500)['text']! as String;
      expect(parseDuration(shared, clock)['milliseconds'], 3725500);
    }
  });

  test('unsupported Flutter locales report the shared root fallback', () {
    final shared = BodyTmiLocaleAdapter.resolve(const Locale('xx'));
    expect(shared.resolved, 'en');
    expect(shared.match, 'root');
  });
}
