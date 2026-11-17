import 'dart:math' as math;

import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'diet.dart' show addDays;
import 'errors.dart';

const solarPolicy = 'bodytmi-solar/1';

var _zonesLoaded = false;

/// An IANA zone from the embedded database (shipped with package:timezone).
tz.Location timeZone(String name) {
  if (!_zonesLoaded) {
    tzdata.initializeTimeZones();
    _zonesLoaded = true;
  }
  try {
    return tz.getLocation(name);
  } on tz.LocationNotFoundException {
    invalid('Unknown time zone: $name.');
  }
}

/// UTC instant of local wall-clock [date] [minutes] in [zone]. In a gap
/// (spring forward) the earlier offset applies; in an overlap (fall back)
/// the first occurrence.
DateTime zonedInstant(tz.Location zone, String date, int minutes) {
  final d = DateTime.parse('${date}T00:00:00Z');
  return tz.TZDateTime(
    zone,
    d.year,
    d.month,
    d.day,
    minutes ~/ 60,
    minutes % 60,
  ).toUtc();
}

/// Formats [utc] in [zone] with its offset, seconds precision.
String zonedText(tz.Location zone, DateTime utc) {
  final local = tz.TZDateTime.from(utc, zone);
  final offset = local.timeZoneOffset.inMinutes;
  String two(int v) => v.abs().toString().padLeft(2, '0');
  final sign = offset < 0 ? '-' : '+';
  return '${local.year.toString().padLeft(4, '0')}-${two(local.month)}-'
      '${two(local.day)}T${two(local.hour)}:${two(local.minute)}:'
      '${two(local.second)}$sign${two(offset ~/ 60)}:${two(offset % 60)}';
}

/// Minutes after local midnight of [utc] in [zone].
int zonedMinute(tz.Location zone, DateTime utc) {
  final local = tz.TZDateTime.from(utc, zone);
  return local.hour * 60 + local.minute;
}

/// The local calendar date of [utc] in [zone].
String zonedDate(tz.Location zone, DateTime utc) =>
    zonedText(zone, utc).substring(0, 10);

double _rad(double d) => d * math.pi / 180;
double _deg(double r) => r * 180 / math.pi;

/// Solar elevation in degrees (geometric, no refraction) at [utc] for
/// [latitude]/[longitude] (east positive), with the NOAA solar calculator
/// equations (after Meeus, Astronomical Algorithms).
double solarElevation(DateTime utc, double latitude, double longitude) {
  final jd = utc.millisecondsSinceEpoch / 86400000.0 + 2440587.5;
  final t = (jd - 2451545.0) / 36525.0;
  final l0 = (280.46646 + t * (36000.76983 + t * 0.0003032)) % 360;
  final m = 357.52911 + t * (35999.05029 - 0.0001537 * t);
  final e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t);
  final c =
      math.sin(_rad(m)) * (1.914602 - t * (0.004817 + 0.000014 * t)) +
      math.sin(_rad(2 * m)) * (0.019993 - 0.000101 * t) +
      math.sin(_rad(3 * m)) * 0.000289;
  final omega = 125.04 - 1934.136 * t;
  final lambda = l0 + c - 0.00569 - 0.00478 * math.sin(_rad(omega));
  final epsilon0 =
      23 +
      (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60;
  final epsilon = epsilon0 + 0.00256 * math.cos(_rad(omega));
  final declination = math.asin(
    math.sin(_rad(epsilon)) * math.sin(_rad(lambda)),
  );
  final y = math.pow(math.tan(_rad(epsilon / 2)), 2).toDouble();
  final eot =
      4 *
      _deg(
        y * math.sin(2 * _rad(l0)) -
            2 * e * math.sin(_rad(m)) +
            4 * e * y * math.sin(_rad(m)) * math.cos(2 * _rad(l0)) -
            0.5 * y * y * math.sin(4 * _rad(l0)) -
            1.25 * e * e * math.sin(2 * _rad(m)),
      );
  final minutes =
      utc.hour * 60 + utc.minute + utc.second / 60 + utc.millisecond / 60000;
  var trueSolar = (minutes + eot + 4 * longitude) % 1440;
  if (trueSolar < 0) trueSolar += 1440;
  final hourAngle = trueSolar / 4 - 180;
  final cosZenith =
      math.sin(_rad(latitude)) * math.sin(declination) +
      math.cos(_rad(latitude)) *
          math.cos(declination) *
          math.cos(_rad(hourAngle));
  return 90 - _deg(math.acos(cosZenith.clamp(-1.0, 1.0)));
}

/// Altitude thresholds (degrees) of the reported events. Sunrise and sunset
/// use −0.833° (refraction and the solar radius).
const solarThresholds = {
  'sun': -0.833,
  'civil': -6.0,
  'nautical': -12.0,
  'astronomical': -18.0,
};

void checkCoordinates(double latitude, double longitude) {
  if (latitude.isNaN || latitude < -90 || latitude > 90)
    invalid('latitude is from -90 to 90.');
  if (longitude.isNaN || longitude < -180 || longitude > 180)
    invalid('longitude is from -180 to 180.');
}

/// Sun events of one local calendar [date] in [zone]: for each threshold
/// the upward (`rise`) and downward (`set`) crossings within the local day,
/// in time order, or the polar state when there is none (`above` all day or
/// `below` all day). Accuracy is about a minute, more near the poles.
Map<String, Object?> sunDay(
  String date,
  double latitude,
  double longitude,
  tz.Location zone,
) {
  checkCoordinates(latitude, longitude);
  final start = zonedInstant(zone, date, 0);
  final end = zonedInstant(zone, addDays(date, 1), 0);
  final minutes = end.difference(start).inMinutes;
  final elevation = <double>[
    for (var i = 0; i <= minutes; i++)
      solarElevation(start.add(Duration(minutes: i)), latitude, longitude),
  ];
  var noon = 0;
  for (var i = 1; i < minutes; i++) {
    if (elevation[i] > elevation[noon]) noon = i;
  }
  final out = <String, Object?>{};
  for (final e in solarThresholds.entries) {
    final h = e.value;
    final events = <Map<String, Object?>>[];
    var above = 0;
    for (var i = 0; i < minutes; i++) {
      final a = elevation[i] - h, b = elevation[i + 1] - h;
      if (a >= 0) above++;
      if ((a < 0) == (b < 0)) continue;
      // Refine the crossing to the second by bisection.
      var lo = start.add(Duration(minutes: i)),
          hi = start.add(Duration(minutes: i + 1));
      for (var k = 0; k < 6; k++) {
        final mid = lo.add(
          Duration(microseconds: hi.difference(lo).inMicroseconds ~/ 2),
        );
        final v = solarElevation(mid, latitude, longitude) - h;
        if ((v < 0) == (a < 0)) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
      final at = DateTime.fromMillisecondsSinceEpoch(
        (lo.millisecondsSinceEpoch / 1000).round() * 1000,
        isUtc: true,
      );
      events.add({'event': a < 0 ? 'rise' : 'set', 'at': zonedText(zone, at)});
    }
    out[e.key] = {
      'thresholdDegrees': h,
      'events': events,
      'minutesAbove': above,
      if (events.isEmpty) 'state': above == 0 ? 'below' : 'above',
    };
  }
  return {
    'policy': solarPolicy,
    'date': date,
    'latitude': latitude,
    'longitude': longitude,
    'zone': zone.name,
    'dayMinutes': minutes,
    'solarNoon': zonedText(zone, start.add(Duration(minutes: noon))),
    'maximumElevationDegrees': (elevation[noon] * 1000).roundToDouble() / 1000,
    'thresholds': out,
  };
}
