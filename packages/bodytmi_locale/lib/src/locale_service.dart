import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/date_symbols.dart';
import 'package:intl/intl.dart';
import 'package:intl/number_symbols.dart';
import 'package:intl/number_symbols_data.dart';

import 'messages.dart';

/// Presentation policy bodytmi-locale/1. Locale only changes human-facing
/// text: canonical records and CLI JSON stay locale independent, and a locale
/// never implies a unit preference.
const localePolicy = 'bodytmi-locale/1';

final Map<String, DateSymbols> _dateSymbols = () {
  // The local data set is synchronous; the returned future is already done.
  initializeDateFormatting();
  return dateTimeSymbolMap();
}();

/// A resolved presentation locale with its explicit fallback chain.
final class PresentationLocale {
  PresentationLocale._(
    this.requested,
    this.resolved,
    this.match,
    this.numbers,
    this.dates,
  );

  /// Resolves exact, then language-only, then the `en` root. A fallback is
  /// always reported rather than silently substituted.
  factory PresentationLocale.resolve(String requested) {
    if (requested.length > 35 ||
        !RegExp(r'^[A-Za-z]{2,8}([-_][A-Za-z0-9]{1,8})*$').hasMatch(requested))
      invalid('locale must be a BCP 47 language tag such as sv-SE.');
    final canonical = Intl.canonicalizedLocale(requested.replaceAll('-', '_'));
    final language = canonical.split('_').first;
    for (final candidate in [canonical, language, 'en']) {
      final numbers = numberFormatSymbols[candidate];
      final dates = _dateSymbols[candidate];
      if (numbers is NumberSymbols && dates != null)
        return PresentationLocale._(
          requested,
          candidate,
          candidate == canonical
              ? 'exact'
              : candidate == language
              ? 'language'
              : 'root',
          numbers,
          dates,
        );
    }
    throw StateError('The en locale data is missing.');
  }

  final String requested, resolved;

  /// exact, language (region data unavailable) or root (`en` fallback).
  final String match;
  final NumberSymbols numbers;
  final DateSymbols dates;

  String get language => resolved.split('_').first;

  /// ISO 8601 weekday numbers: 1 = Monday ... 7 = Sunday.
  int get firstWeekday => dates.FIRSTDAYOFWEEK + 1;
  List<int> get weekendDays => _weekend(dates.WEEKENDRANGE);

  Map<String, Object?> toJson() => {
    'policy': localePolicy,
    'requested': requested,
    'resolved': resolved,
    'match': match,
  };

  Map<String, Object?> info() => {
    ...toJson(),
    'decimalSeparator': numbers.DECIMAL_SEP,
    'groupSeparator': numbers.GROUP_SEP,
    'minusSign': numbers.MINUS_SIGN,
    'zeroDigit': numbers.ZERO_DIGIT,
    'grouping': _grouping(numbers.DECIMAL_PATTERN),
    'firstWeekday': firstWeekday,
    'weekendDays': weekendDays,
    'hourCycle': _localeHourCycle(this),
    'messageCatalog': messageCatalogLocale(language),
  };
}

List<int> _weekend(List<int> range) {
  final days = <int>[];
  for (var d = range[0]; ; d = (d + 1) % 7) {
    days.add(d + 1);
    if (d == range[1]) break;
  }
  return days;
}

/// Primary and secondary integer grouping sizes from the CLDR decimal
/// pattern, e.g. `#,##0.###` is 3/3 and `#,##,##0.###` is 3/2.
Map<String, int> _grouping(String pattern) {
  final integer = pattern.split(';').first.split('.').first;
  final groups = integer.split(',');
  if (groups.length < 2) return {'primary': 0, 'secondary': 0};
  final primary = groups.last.length;
  final secondary = groups.length > 2
      ? groups[groups.length - 2].length
      : primary;
  return {'primary': primary, 'secondary': secondary};
}

String _localeHourCycle(PresentationLocale locale) =>
    DateFormat.jm(locale.resolved).pattern!.contains('h') ? 'h12' : 'h24';

String _digits(String ascii, String zero) {
  if (zero == '0') return ascii;
  final base = zero.codeUnitAt(0);
  return String.fromCharCodes([
    for (final c in ascii.codeUnits)
      c >= 0x30 && c <= 0x39 ? base + c - 0x30 : c,
  ]);
}

String _group(String digits, Map<String, int> grouping, String separator) {
  final primary = grouping['primary']!, secondary = grouping['secondary']!;
  if (primary == 0 || digits.length <= primary) return digits;
  final parts = <String>[digits.substring(digits.length - primary)];
  var rest = digits.substring(0, digits.length - primary);
  while (rest.length > secondary) {
    parts.insert(0, rest.substring(rest.length - secondary));
    rest = rest.substring(0, rest.length - secondary);
  }
  parts.insert(0, rest);
  return parts.join(separator);
}

/// Exact decimal formatting: digits are never rounded or dropped. Optional
/// minimumFractionDigits only pads with zeros.
Map<String, Object?> formatNumber(
  PresentationLocale locale,
  String value, {
  bool grouping = true,
  int minimumFractionDigits = 0,
}) {
  Decimal.parse(value);
  if (minimumFractionDigits < 0 || minimumFractionDigits > 40)
    invalid('minimumFractionDigits must be from 0 to 40.');
  final negative = value.startsWith('-');
  final unsigned = negative ? value.substring(1) : value;
  final parts = unsigned.split('.');
  var fraction = parts.length == 2 ? parts[1] : '';
  if (fraction.length < minimumFractionDigits)
    fraction = fraction.padRight(minimumFractionDigits, '0');
  final symbols = locale.numbers;
  final integer = grouping
      ? _group(parts[0], _grouping(symbols.DECIMAL_PATTERN), symbols.GROUP_SEP)
      : parts[0];
  final text =
      '${negative ? symbols.MINUS_SIGN : ''}'
      '${_digits(integer, symbols.ZERO_DIGIT)}'
      '${fraction.isEmpty ? '' : symbols.DECIMAL_SEP + _digits(fraction, symbols.ZERO_DIGIT)}';
  return {'locale': locale.toJson(), 'value': value, 'text': text};
}

const _spaceSeparators = {' ', ' ', ' '};

/// Documented human-input policy: the locale's own digits or ASCII digits,
/// the locale minus sign or `-`, and exactly the locale decimal separator.
/// Group separators are rejected unless allowGrouping is true, and then only
/// at the locale's grouping positions; ordinary, no-break and narrow no-break
/// spaces are interchangeable when the locale groups with a space. The other
/// common separator is never reinterpreted, so `1.5` is rejected in `sv`.
Map<String, Object?> parseNumber(
  PresentationLocale locale,
  String text, {
  bool allowGrouping = false,
}) {
  if (text.isEmpty || text.length > 120)
    invalid('Number text is empty or too long.');
  final symbols = locale.numbers;
  final zero = symbols.ZERO_DIGIT.codeUnitAt(0);
  final buffer = StringBuffer();
  var rest = text.trim();
  if (rest.startsWith(symbols.MINUS_SIGN)) {
    buffer.write('-');
    rest = rest.substring(symbols.MINUS_SIGN.length);
  } else if (rest.startsWith('-')) {
    buffer.write('-');
    rest = rest.substring(1);
  }
  final decimal = rest.indexOf(symbols.DECIMAL_SEP);
  final integerText = decimal < 0 ? rest : rest.substring(0, decimal);
  final fractionText = decimal < 0
      ? ''
      : rest.substring(decimal + symbols.DECIMAL_SEP.length);
  String ascii(String part, String label) {
    final out = StringBuffer();
    for (final c in part.codeUnits) {
      if (c >= 0x30 && c <= 0x39) {
        out.writeCharCode(c);
      } else if (c >= zero && c <= zero + 9) {
        out.writeCharCode(0x30 + c - zero);
      } else {
        invalid(
          'Unexpected character in $label for locale ${locale.resolved}: '
          '"${String.fromCharCode(c)}".',
        );
      }
    }
    return out.toString();
  }

  final group = symbols.GROUP_SEP;
  final spaceGroup = _spaceSeparators.contains(group);
  var integer = integerText;
  final grouped =
      _spaceSeparators.any(integer.contains) || integer.contains(group);
  if (grouped) {
    if (!allowGrouping) invalid('Group separators need allowGrouping:true.');
    final normalized = spaceGroup
        ? integer.replaceAll(RegExp('[   ]'), group)
        : integer;
    final digits = ascii(normalized.replaceAll(group, ''), 'integer');
    if (_group(digits, _grouping(symbols.DECIMAL_PATTERN), group) != normalized)
      invalid('Group separators are not at locale grouping positions.');
    integer = digits;
  } else {
    integer = ascii(integer, 'integer');
  }
  if (integer.isEmpty) invalid('Number needs integer digits.');
  if (decimal >= 0 && fractionText.isEmpty)
    invalid('A decimal separator needs fraction digits.');
  buffer.write(integer);
  if (fractionText.isNotEmpty)
    buffer.write('.${ascii(fractionText, 'fraction')}');
  final canonical = buffer.toString();
  Decimal.parse(canonical);
  return {'locale': locale.toJson(), 'text': text, 'value': canonical};
}

/// Formats a timestamp's wall-clock fields in its own recorded offset (never
/// this process's timezone), or a calendar date for the date style.
Map<String, Object?> formatDate(
  PresentationLocale locale,
  String value, {
  String style = 'datetime',
  String hourCycle = 'locale',
}) {
  if (!{'date', 'time', 'datetime'}.contains(style))
    invalid('style must be date, time or datetime.');
  if (!{'locale', 'h12', 'h24'}.contains(hourCycle))
    invalid('hourCycle must be locale, h12 or h24.');
  DateTime wall;
  String? offset;
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    if (style != 'date') invalid('A calendar date only supports style date.');
    calendarDate(value, 'value');
    final p = value.split('-').map(int.parse).toList();
    wall = DateTime.utc(p[0], p[1], p[2]);
  } else {
    parseInstant(value, 'value');
    final p = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})',
    ).firstMatch(value)!;
    wall = DateTime.utc(
      int.parse(p[1]!),
      int.parse(p[2]!),
      int.parse(p[3]!),
      int.parse(p[4]!),
      int.parse(p[5]!),
      int.parse(p[6]!),
    );
    offset = value.endsWith('Z') ? 'Z' : value.substring(value.length - 6);
  }
  final cycle = hourCycle == 'locale' ? _localeHourCycle(locale) : hourCycle;
  DateFormat time() => (cycle == 'h12'
      ? DateFormat('h:mm a', locale.resolved)
      : DateFormat.Hm(locale.resolved));
  final date = DateFormat.yMd(locale.resolved);
  final text = switch (style) {
    'date' => date.format(wall),
    'time' => time().format(wall),
    _ => '${date.format(wall)} ${time().format(wall)}',
  };
  return {
    'locale': locale.toJson(),
    'value': value,
    'style': style,
    'hourCycle': cycle,
    'offset': offset,
    'text': text,
  };
}
