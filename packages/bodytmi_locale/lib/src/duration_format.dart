import 'package:bodytmi_core/bodytmi_core.dart';

import 'locale_service.dart';
import 'messages.dart';

/// Policy bodytmi-duration-format/1: an explicit small formatter, not a
/// general natural-language parser. Values are whole milliseconds.
const durationPolicy = 'bodytmi-duration-format/1';
const _maxMilliseconds = 7 * 24 * 3600 * 1000;

String _two(int n) => n.toString().padLeft(2, '0');

/// `clock` renders m:ss or h:mm:ss (fraction only when milliseconds are
/// nonzero, with the locale decimal separator); `units` renders localized
/// unit abbreviations, omitting zero components.
Map<String, Object?> formatDuration(
  PresentationLocale locale,
  int milliseconds, {
  String style = 'clock',
}) {
  if (milliseconds < 0 || milliseconds > _maxMilliseconds)
    invalid('Duration must be from 0 to 7 days in milliseconds.');
  if (!{'clock', 'units'}.contains(style))
    invalid('style must be clock or units.');
  final h = milliseconds ~/ 3600000;
  final m = milliseconds ~/ 60000 % 60;
  final s = milliseconds ~/ 1000 % 60;
  final ms = milliseconds % 1000;
  String text;
  if (style == 'clock') {
    final fraction = ms == 0
        ? ''
        : '${locale.numbers.DECIMAL_SEP}'
              '${ms.toString().padLeft(3, '0').replaceFirst(RegExp(r'0+$'), '')}';
    text = h > 0
        ? '$h:${_two(m)}:${_two(s)}$fraction'
        : '$m:${_two(s)}$fraction';
  } else {
    String unit(String key) =>
        renderMessage(locale.resolved, locale.language, key, {})['text']!
            as String;
    text = [
      if (h > 0) '$h ${unit('duration.hour')}',
      if (m > 0) '$m ${unit('duration.minute')}',
      if (s > 0) '$s ${unit('duration.second')}',
      if (ms > 0) '$ms ${unit('duration.millisecond')}',
      if (milliseconds == 0) '0 ${unit('duration.second')}',
    ].join(' ');
  }
  return {
    'policy': durationPolicy,
    'locale': locale.toJson(),
    'milliseconds': milliseconds,
    'style': style,
    'text': text,
  };
}

/// Accepts only unambiguous forms:
/// - clock `m:ss` or `h:mm:ss` (seconds/minutes below 60), optional fraction
///   of seconds with `.` or the locale decimal separator, at most 3 digits;
/// - unit components in descending order, e.g. `1h30m`, `1 h 30 min 15 s`,
///   `90s`, `500ms`, `2.5s` (only seconds may carry a fraction).
/// A bare number is rejected: it does not say whether it means seconds or
/// minutes.
Map<String, Object?> parseDuration(PresentationLocale locale, String text) {
  final input = text.trim();
  if (input.isEmpty || input.length > 64)
    invalid('Duration text is empty or too long.');
  final sep = RegExp.escape(locale.numbers.DECIMAL_SEP);
  int fractionMs(String? digits) {
    if (digits == null || digits.isEmpty) return 0;
    if (digits.length > 3)
      invalid('Duration precision is limited to milliseconds.');
    return int.parse(digits.padRight(3, '0'));
  }

  int total;
  final clock = RegExp(
    '^(?:(\\d+):([0-5]\\d):|(\\d+):)([0-5]\\d)(?:(?:\\.|$sep)(\\d+))?\$',
  ).firstMatch(input);
  if (clock != null) {
    final hours = clock[1] == null ? 0 : int.parse(clock[1]!);
    final minutes = int.parse(clock[2] ?? clock[3]!);
    if (clock[1] == null && minutes >= 60)
      invalid('Use h:mm:ss for durations of an hour or more.');
    total =
        ((hours * 60 + minutes) * 60 + int.parse(clock[4]!)) * 1000 +
        fractionMs(clock[5]);
  } else {
    final units = RegExp(
      '^(?:(\\d+)\\s*h\\s*)?(?:(\\d+)\\s*(?:min|m)(?!s)\\s*)?'
      '(?:(\\d+)(?:(?:\\.|$sep)(\\d+))?\\s*s\\s*)?(?:(\\d+)\\s*ms)?\$',
    ).firstMatch(input);
    if (units == null || [1, 2, 3, 5].every((i) => units[i] == null))
      invalid(
        'Duration must be m:ss, h:mm:ss or explicit units such as 1h30m or 90s.',
      );
    if (units[5] != null && units[4] != null)
      invalid('Use either fractional seconds or milliseconds, not both.');
    total =
        (int.parse(units[1] ?? '0') * 3600 +
                int.parse(units[2] ?? '0') * 60 +
                int.parse(units[3] ?? '0')) *
            1000 +
        fractionMs(units[4]) +
        int.parse(units[5] ?? '0');
  }
  if (total > _maxMilliseconds) invalid('Duration exceeds 7 days.');
  final fraction = (total % 1000).toString().padLeft(3, '0');
  final seconds = total % 1000 == 0
      ? '${total ~/ 1000}'
      : '${total ~/ 1000}.${fraction.replaceFirst(RegExp(r'0+$'), '')}';
  return {
    'policy': durationPolicy,
    'locale': locale.toJson(),
    'text': text,
    'milliseconds': total,
    'quantity': Quantity(seconds, 's').toJson(),
  };
}
