import 'errors.dart';

DateTime parseInstant(Object? input, String label) {
  if (input is! String) invalid('$label must be an ISO-8601 timestamp.');
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$',
  ).firstMatch(input);
  if (match == null)
    invalid('$label must include date, time, seconds, and timezone.');
  final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
  final calendar = DateTime.utc(
    parts[0],
    parts[1],
    parts[2],
    parts[3],
    parts[4],
    parts[5],
  );
  final normalized = [
    calendar.year,
    calendar.month,
    calendar.day,
    calendar.hour,
    calendar.minute,
    calendar.second,
  ];
  for (var i = 0; i < parts.length; i++) {
    if (parts[i] != normalized[i])
      invalid('Invalid calendar date/time in $label.');
  }
  final zone = match.group(7)!;
  if (zone != 'Z' &&
      (int.parse(zone.substring(1, 3)) > 23 ||
          int.parse(zone.substring(4)) > 59)) {
    invalid('Invalid timezone offset in $label.');
  }
  final value = DateTime.tryParse(input);
  if (value == null) invalid('Invalid $label.');
  return value.toUtc();
}

/// The UTC offset an ISO-8601 timestamp was entered with, in minutes east of
/// UTC. `Z` and `+00:00` are both zero.
int parseOffsetMinutes(Object? input, String label) {
  parseInstant(input, label);
  final text = input as String;
  if (text.endsWith('Z')) return 0;
  final zone = text.substring(text.length - 6);
  final minutes =
      int.parse(zone.substring(1, 3)) * 60 + int.parse(zone.substring(4));
  return zone.startsWith('-') ? -minutes : minutes;
}

/// Validates an offset kept beside an instant (same range [parseInstant]
/// accepts).
int checkOffsetMinutes(int minutes, String label) {
  if (minutes.abs() > 23 * 60 + 59)
    invalid('Invalid timezone offset in $label.');
  return minutes;
}

/// Formats [instant] in the local time of [offsetMinutes]. Zero keeps the
/// UTC `Z` form, so UTC entries serialize exactly as before.
String formatInstant(DateTime instant, int offsetMinutes) {
  final utc = instant.toUtc();
  if (offsetMinutes == 0) return utc.toIso8601String();
  final local = utc.add(Duration(minutes: offsetMinutes)).toIso8601String();
  final abs = offsetMinutes.abs();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.substring(0, local.length - 1)}'
      '${offsetMinutes < 0 ? '-' : '+'}${two(abs ~/ 60)}:${two(abs % 60)}';
}
