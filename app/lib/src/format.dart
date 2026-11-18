import 'package:bodytmi_flutter/bodytmi_flutter.dart';
import 'package:bodytmi_locale/bodytmi_locale.dart';
import 'package:material_ui/material_ui.dart';

/// Display formatting. Stored values stay exact decimal strings; rounding
/// here is for display only, and separators follow the shared locale
/// service so the GUI and CLI agree.
final class Fmt {
  Fmt._(this.locale);

  factory Fmt.of(BuildContext context) =>
      Fmt._(BodyTmiLocaleAdapter.of(context));

  final PresentationLocale locale;

  /// [value] rounded to at most [digits] fraction digits, localized.
  String number(Object? value, {int digits = 1, bool pad = false}) {
    if (value == null) return '—';
    final parsed = double.tryParse('$value');
    if (parsed == null) return '$value';
    var text = parsed.toStringAsFixed(digits);
    if (!pad && text.contains('.')) {
      text = text.replaceFirst(RegExp(r'\.?0+$'), '');
    }
    return formatNumber(locale, text)['text']! as String;
  }

  /// A `{value, unit}` quantity, or a dash when unknown.
  String quantity(Object? quantity, {int digits = 1, bool unit = true}) {
    if (quantity is! Map) return '—';
    final value = number(quantity['value'], digits: digits);
    return unit ? '$value ${quantity['unit']}' : value;
  }

  /// `HH:MM` of an instant in its own recorded offset.
  String clock(Object? instant) {
    if (instant is! String || instant.length < 16) return '—';
    return instant.substring(11, 16);
  }

  /// Minutes as `7 h 12` or `45 min`.
  String minutes(Object? minutes) {
    if (minutes is! int) return '—';
    if (minutes < 60) return '$minutes min';
    return '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')}';
  }

  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  /// `Wednesday 18 November`.
  String longDate(DateTime day) =>
      '${_weekdays[day.weekday - 1]} ${day.day} ${_months[day.month - 1]}';

  /// `18 Nov`.
  String shortDate(String date) {
    final d = DateTime.parse(date);
    return '${d.day} ${_months[d.month - 1].substring(0, 3)}';
  }
}

/// Local calendar date `YYYY-MM-DD`.
String isoDate(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// An instant with this device's current offset, as the commands require.
String isoInstant(DateTime local) {
  final offset = local.timeZoneOffset;
  final m = offset.inMinutes.abs();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${isoDate(local)}T${two(local.hour)}:${two(local.minute)}:'
      '${two(local.second)}${offset.isNegative ? '-' : '+'}'
      '${two(m ~/ 60)}:${two(m % 60)}';
}

/// Reads `json[path...]` without throwing; `null` when absent.
Object? at(Object? json, List<Object> path) {
  var current = json;
  for (final key in path) {
    if (key is int) {
      if (current is! List || key >= current.length) return null;
      current = current[key];
    } else {
      if (current is! Map) return null;
      current = current[key];
    }
  }
  return current;
}
