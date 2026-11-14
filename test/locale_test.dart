import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_locale/bodytmi_locale.dart';
import 'cli_test.dart';
import 'support.dart';

PresentationLocale _l(String tag) => PresentationLocale.resolve(tag);

String _number(String tag, String value, {bool grouping = true, int min = 0}) =>
    formatNumber(
          _l(tag),
          value,
          grouping: grouping,
          minimumFractionDigits: min,
        )['text']!
        as String;

String _parse(String tag, String text, {bool grouping = false}) =>
    parseNumber(_l(tag), text, allowGrouping: grouping)['value']! as String;

int _duration(String tag, String text) =>
    parseDuration(_l(tag), text)['milliseconds']! as int;

void localeTests() {
  test('locale resolution reports exact, language and root matches', () {
    equal(_l('en-US').resolved, 'en_US');
    equal(_l('en-US').match, 'exact');
    equal(_l('sv-SE').resolved, 'sv');
    equal(_l('sv-SE').match, 'language');
    equal(_l('xx').resolved, 'en');
    equal(_l('xx').match, 'root');
    rejects(() => _l('not a locale'));
    rejects(() => _l(''));
    // ISO weekdays: 1 = Monday ... 7 = Sunday, normalized from CLDR data.
    equal(_l('sv').firstWeekday, 1);
    equal(_l('en-US').firstWeekday, 7);
    equal(_l('en-GB').firstWeekday, 1);
    jsonEqual(_l('sv').weekendDays, [6, 7]);
    jsonEqual(_l('hi').weekendDays, [7]);
    equal(_l('sv').info()['hourCycle'], 'h24');
    equal(_l('en-US').info()['hourCycle'], 'h12');
  });

  test('numbers format exactly and parse under an explicit input policy', () {
    equal(_number('sv', '-12345.250'), '−12 345,250');
    equal(_number('en', '1234567.000001'), '1,234,567.000001');
    equal(_number('en', '1234567', grouping: false), '1234567');
    equal(_number('en', '2.5', min: 3), '2.500');
    equal(_number('en', '2.5678', min: 2), '2.5678');
    equal(_number('hi', '1234567.5'), '12,34,567.5');
    equal(_number('en', '999'), '999');
    equal(_number('ar-EG', '1234.5'), '١٬٢٣٤٫٥');
    rejects(() => _number('en', '1e5'));
    rejects(() => _number('en', '1.5', min: 41));

    equal(_parse('sv', '1,5'), '1.5');
    equal(_parse('sv', '-0,25'), '-0.25');
    equal(_parse('sv', '−0,25'), '-0.25');
    rejects(() => _parse('sv', '1.5'));
    rejects(() => _parse('en', '1,5'));
    rejects(() => _parse('sv', '12 345'));
    equal(_parse('sv', '12 345,5', grouping: true), '12345.5');
    equal(_parse('sv', '12 345', grouping: true), '12345');
    equal(_parse('en', '1,234,567.25', grouping: true), '1234567.25');
    rejects(() => _parse('en', '12,34', grouping: true));
    equal(_parse('hi', '12,34,567', grouping: true), '1234567');
    rejects(() => _parse('hi', '1,234,567', grouping: true));
    rejects(() => _parse('en', '1.'));
    rejects(() => _parse('en', '.5'));
    // Locale digits round-trip to canonical ASCII decimal strings.
    equal(
      _parse('ar-EG', _number('ar-EG', '1234.5', grouping: false)),
      '1234.5',
    );
    for (final value in ['0', '7', '1000', '-1000000.125', '0.001']) {
      for (final tag in [
        'en',
        'sv',
        'de',
        'hi',
        'fr',
        'ar-EG',
        'ja',
        'pt-BR',
      ]) {
        equal(_parse(tag, _number(tag, value), grouping: true), value);
      }
    }
  });

  test('dates use the recorded offset and never the process timezone', () {
    String date(
      String tag,
      String value, [
      String style = 'datetime',
      String cycle = 'locale',
    ]) =>
        formatDate(_l(tag), value, style: style, hourCycle: cycle)['text']!
            as String;
    equal(date('sv', '2026-01-12T18:30:00+01:00'), '2026-01-12 18:30');
    final us = date('en-US', '2026-01-12T18:30:00+01:00');
    check(us.startsWith('1/12/2026 6:30') && us.endsWith('PM'), us);
    // 23:30 at -05:00 is the next UTC day, but stays the 12th as recorded.
    equal(date('sv', '2026-01-12T23:30:00-05:00', 'date'), '2026-01-12');
    equal(
      date('sv', '2026-01-12T18:30:00Z', 'time', 'h12').contains('6:30'),
      true,
    );
    equal(date('en-US', '2026-01-12T18:30:00Z', 'time', 'h24'), '18:30');
    equal(date('en-US', '2026-01-12', 'date'), '1/12/2026');
    rejects(() => date('en', '2026-01-12', 'time'));
    rejects(() => date('en', '2026-01-12T18:30:00'));
    rejects(() => date('en', '2026-02-30', 'date'));
    rejects(() => date('en', '2026-01-12T18:30:00Z', 'weekday'));
  });

  test('durations format and parse only unambiguous explicit forms', () {
    String clock(String tag, int ms) =>
        formatDuration(_l(tag), ms)['text']! as String;
    String units(String tag, int ms) =>
        formatDuration(_l(tag), ms, style: 'units')['text']! as String;
    equal(clock('en', 0), '0:00');
    equal(clock('en', 90000), '1:30');
    equal(clock('en', 3725500), '1:02:05.5');
    equal(clock('sv', 3725500), '1:02:05,5');
    equal(clock('en', 1250), '0:01.25');
    equal(units('en', 5415000), '1 h 30 min 15 s');
    equal(units('en', 0), '0 s');
    equal(units('en', 1500), '1 s 500 ms');
    rejects(() => clock('en', -1));
    rejects(() => clock('en', 7 * 24 * 3600 * 1000 + 1));

    equal(_duration('en', '1:30'), 90000);
    equal(_duration('en', '1:02:05.5'), 3725500);
    equal(_duration('sv', '1:02:05,5'), 3725500);
    equal(_duration('en', '90s'), 90000);
    equal(_duration('en', '1h30m'), 5400000);
    equal(_duration('en', '1 h 30 min 15 s'), 5415000);
    equal(_duration('en', '2.5s'), 2500);
    equal(_duration('en', '500ms'), 500);
    equal(_duration('en', '1m 500ms'), 60500);
    for (final bad in [
      '90',
      '1:75',
      '75:00',
      '1:30.1234',
      '1.5s 20ms',
      '30s 1m',
      '1.5 min',
      '',
      '-1:00',
      '8 x',
    ]) {
      rejects(() => _duration('en', bad));
    }
    rejects(() => _duration('sv', '1:30.5,5'));
    for (final ms in [
      0,
      1,
      999,
      1000,
      59999,
      60000,
      3599999,
      3600000,
      86400123,
    ]) {
      for (final tag in ['en', 'sv']) {
        equal(_duration(tag, clock(tag, ms)), ms);
        equal(_duration(tag, units(tag, ms).replaceAll(' ', '')), ms);
      }
    }
    final parsed = parseDuration(_l('en'), '1:30.5');
    jsonEqual(parsed['quantity'], Quantity('90.5', 's').toJson());
  });

  test('messages use stable keys, plural rules and explicit fallbacks', () {
    String text(String tag, String key, Map<String, Object?> args) {
      final l = _l(tag);
      return renderMessage(l.resolved, l.language, key, args)['text']!
          as String;
    }

    equal(text('en', 'session.sets', {'count': 1}), '1 set');
    equal(text('en', 'session.sets', {'count': 0}), '0 sets');
    equal(text('sv', 'session.exercises', {'count': 2}), '2 övningar');
    equal(
      text('sv', 'massStale', {'count': 1}),
      'Kroppsvikten är 1 dag gammal.',
    );
    equal(
      text('en', 'timer.confirm', {'exercise': 'Row'}),
      'Confirm the actual result for Row.',
    );
    final german = _l('de');
    final fallback = renderMessage(
      german.resolved,
      german.language,
      'set.status.completed',
      {},
    );
    equal(fallback['catalog'], 'en');
    equal(fallback['fallback'], true);
    try {
      text('en', 'no.such.key', {});
      throw StateError('Expected not_found.');
    } on BodyTmiException catch (error) {
      equal(error.code, 'not_found');
    }
    rejects(() => text('en', 'session.sets', {}));
    rejects(() => text('en', 'session.sets', {'count': -1}));
    rejects(() => text('en', 'timer.confirm', {}));
    rejects(() => text('en', 'timer.confirm', {'exercise': 'Row', 'x': 1}));
    const needs = <String, Map<String, Object?>>{
      'timer.confirm': {'exercise': 'Row'},
      'timer.nearEnd': {'seconds': 5},
      'progression.proposal': {'metric': 'load', 'from': '1', 'to': '2'},
      'session.sets': {'count': 2},
      'session.exercises': {'count': 2},
      'session.repetitions': {'count': 2},
      'massStale': {'count': 2},
    };
    // Every key renders in every catalog with exactly its named arguments.
    for (final language in ['en', 'sv']) {
      for (final key in messageKeys) {
        final rendered = text(language, key, needs[key] ?? const {});
        check(rendered.isNotEmpty && !rendered.contains('{'), key);
      }
    }
  });

  test('locale presentation stays outside domain packages and JSON', () async {
    for (final package in [
      'bodytmi_core',
      'bodytmi_application',
      'bodytmi_storage',
    ]) {
      for (final file in Directory(
        'packages/$package/lib',
      ).listSync(recursive: true).whereType<File>()) {
        for (final line in file.readAsLinesSync().where(
          (line) => line.startsWith('import ') || line.startsWith('export '),
        )) {
          check(
            !line.contains('package:intl') && !line.contains('bodytmi_locale'),
            '${file.path}: $line',
          );
        }
      }
    }
    for (final file in Directory(
      'packages/bodytmi_locale/lib',
    ).listSync(recursive: true).whereType<File>()) {
      for (final line in file.readAsLinesSync().where(
        (line) => line.startsWith('import '),
      )) {
        check(
          !line.contains('dart:io') &&
              !line.contains('flutter') &&
              !line.contains('bodytmi_application') &&
              !line.contains('bodytmi_storage'),
          '${file.path}: $line',
        );
      }
    }
    final info = await invoke([
      'locale',
      'info',
    ], jsonEncode({'schemaVersion': 1, 'locale': 'sv-SE'}));
    equal(info.code, 0);
    check(info.output.contains('"firstWeekday":1'));
    final bad = await invoke([
      'locale',
      'parse-number',
    ], jsonEncode({'schemaVersion': 1, 'locale': 'sv', 'text': '1.5'}));
    equal(bad.code, 2);
    equal(bad.output, '');
    final missing = await invoke([
      'locale',
      'message',
    ], jsonEncode({'schemaVersion': 1, 'locale': 'sv', 'key': 'nope'}));
    equal(missing.code, 3);
    // Canonical JSON never changes with presentation locale.
    final quantity = await invoke(
      ['quantity', 'normalize'],
      jsonEncode({
        'schemaVersion': 1,
        'quantity': {'value': '2.5', 'unit': 'lb'},
      }),
    );
    check(quantity.output.contains('"value":"1.133980925"'));
  });
}
