import 'errors.dart';
import 'quantity.dart';
import 'solar.dart' as solar;

/// Where you live: decimal-degree coordinates (as decimal strings) and the
/// IANA time zone used for daylight and schedule times.
final class ProfileLocation {
  ProfileLocation._(this.latitudeText, this.longitudeText, this.timeZone);
  factory ProfileLocation.fromJson(Object? input) {
    final j = jsonObject(input, 'location');
    checkKeys(j, {'latitude', 'longitude', 'timeZone'});
    final lat = requiredString(j, 'latitude');
    final lon = requiredString(j, 'longitude');
    for (final v in [lat, lon]) {
      if (!RegExp(r'^-?\d{1,3}(\.\d{1,8})?$').hasMatch(v))
        invalid('Coordinates are decimal strings with at most 8 decimals.');
    }
    solar.checkCoordinates(double.parse(lat), double.parse(lon));
    final zone = requiredString(j, 'timeZone');
    solar.timeZone(zone);
    return ProfileLocation._(lat, lon, zone);
  }
  final String latitudeText, longitudeText, timeZone;
  double get latitude => double.parse(latitudeText);
  double get longitude => double.parse(longitudeText);
  Map<String, Object?> toJson() => {
    'latitude': latitudeText,
    'longitude': longitudeText,
    'timeZone': timeZone,
  };
}

/// Profile facts used only as formula inputs: sex, birth date and step
/// length. Every fact is optional; a formula needing a missing one is
/// unavailable and says so.
final class Profile {
  Profile._(this.sex, this.birthDate, this.stepLength, [this.location]);
  factory Profile.fromJson(Object? input) {
    final j = jsonObject(input, 'profile');
    checkKeys(j, {'sex', 'birthDate', 'stepLength', 'location'});
    final sex = j['sex'];
    if (sex != null && sex != 'male' && sex != 'female')
      invalid('Profile sex is male or female.');
    final birth = j['birthDate'];
    if (birth != null && !_isDate(birth))
      invalid('Profile birthDate is a valid YYYY-MM-DD.');
    final step = j['stepLength'] == null
        ? null
        : Quantity.fromJson(j['stepLength']);
    if (step != null && step.dimension != Dimension.distance)
      invalid('Profile stepLength is a distance.');
    return Profile._(
      sex as String?,
      birth as String?,
      step,
      j['location'] == null ? null : ProfileLocation.fromJson(j['location']),
    );
  }
  static final empty = Profile._(null, null, null);
  final String? sex, birthDate;
  final Quantity? stepLength;
  final ProfileLocation? location;

  /// Whole years of age on [date] (YYYY-MM-DD), or null without a birth date.
  int? ageOn(String date) {
    if (birthDate == null) return null;
    final b = DateTime.parse(birthDate!), d = DateTime.parse(date);
    var years = d.year - b.year;
    if (d.month < b.month || (d.month == b.month && d.day < b.day)) years--;
    return years < 0 ? null : years;
  }

  Map<String, Object?> toJson() => {
    'sex': ?sex,
    'birthDate': ?birthDate,
    if (stepLength != null)
      'stepLength': {
        'value': stepLength!.enteredValue,
        'unit': stepLength!.enteredUnit.name,
      },
    if (location != null) 'location': location!.toJson(),
  };
}

bool _isDate(Object? value) =>
    value is String &&
    RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) &&
    DateTime.tryParse(
          '${value}T00:00:00Z',
        )?.toIso8601String().substring(0, 10) ==
        value;

/// The profile's immutable numbered revision.
final class ProfileRevision {
  ProfileRevision._(this.number, this.profile);
  factory ProfileRevision.publish(
    Profile profile, {
    ProfileRevision? previous,
  }) => ProfileRevision._((previous?.number ?? 0) + 1, profile);
  factory ProfileRevision.fromJson(Object? input) {
    final j = jsonObject(input, 'profile revision');
    checkKeys(j, {'schemaVersion', 'revision', 'profile'});
    final revision = j['revision'];
    if (j['schemaVersion'] != 1 || revision is! int || revision < 1)
      invalid('Invalid profile revision.');
    return ProfileRevision._(revision, Profile.fromJson(j['profile']));
  }
  final int number;
  final Profile profile;
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'revision': number,
    'profile': profile.toJson(),
  };
}

/// Where body fat comes from (D8):
///
/// * `{kind: calculation, calculation: navy-body-fat | jackson-pollock-3 |
///   jackson-pollock-7}`;
/// * `{kind: series, method, device?}` — recorded body-fat observations of
///   one method (bio-impedance, dexa, caliper, other), resolved under that
///   series' policy;
/// * `{kind: mean, components: [...]}` — an explicit mean of 2–8 calculation
///   or series sources, unavailable unless every component is.
final class BodyFatSource {
  BodyFatSource._(this.json);
  factory BodyFatSource.fromJson(Object? input, {bool nested = false}) {
    final j = jsonObject(input, 'body-fat source');
    final kind = requiredString(j, 'kind');
    switch (kind) {
      case 'calculation':
        checkKeys(j, {'kind', 'calculation'});
        if (!calculationSources.contains(j['calculation']))
          invalid(
            'A calculation source is one of ${calculationSources.join(', ')}.',
          );
      case 'series':
        checkKeys(j, {'kind', 'method', 'device'});
        if (!seriesMethods.contains(j['method']))
          invalid('A series source method is ${seriesMethods.join(', ')}.');
        if (j['device'] != null) identifier(j, 'device');
      case 'mean':
        if (nested) invalid('A mean cannot contain another mean.');
        checkKeys(j, {'kind', 'components'});
        final parts = jsonList(j, 'components');
        if (parts.length < 2 || parts.length > 8)
          invalid('A mean source names 2 to 8 components.');
        final seen = <String>{};
        for (final part in parts) {
          final s = BodyFatSource.fromJson(part, nested: true);
          if (!seen.add(s.key)) invalid('Mean components must be distinct.');
        }
      default:
        invalid('A body-fat source is a calculation, series or mean.');
    }
    return BodyFatSource._(Map.unmodifiable(j));
  }

  static const calculationSources = {
    'navy-body-fat',
    'jackson-pollock-3',
    'jackson-pollock-7',
  };
  static const seriesMethods = {'bio-impedance', 'dexa', 'caliper', 'other'};
  static final navy = BodyFatSource.fromJson({
    'kind': 'calculation',
    'calculation': 'navy-body-fat',
  });

  final Map<String, Object?> json;
  String get kind => json['kind']! as String;
  List<BodyFatSource> get components => [
    if (kind == 'mean')
      for (final c in json['components']! as List)
        BodyFatSource.fromJson(c, nested: true),
  ];
  String get key => switch (kind) {
    'calculation' => 'calculation:${json['calculation']}',
    'series' => 'series:${json['method']}:${json['device'] ?? ''}',
    _ => 'mean',
  };
  Map<String, Object?> toJson() => json;
}

/// A dated body-fat source selection. The one in force on a date is the
/// latest whose [from] is on or before it; selecting a DEXA value today
/// leaves earlier reports unchanged.
final class BodyFatSourceRevision {
  BodyFatSourceRevision._(this.number, this.from, this.source);
  factory BodyFatSourceRevision.publish(
    String from,
    BodyFatSource source, {
    BodyFatSourceRevision? previous,
  }) {
    if (!_isDate(from)) invalid('from is a valid YYYY-MM-DD.');
    return BodyFatSourceRevision._((previous?.number ?? 0) + 1, from, source);
  }
  factory BodyFatSourceRevision.fromJson(Object? input) {
    final j = jsonObject(input, 'body-fat source revision');
    checkKeys(j, {'schemaVersion', 'revision', 'from', 'source'});
    final revision = j['revision'];
    if (j['schemaVersion'] != 1 || revision is! int || revision < 1)
      invalid('Invalid body-fat source revision.');
    if (!_isDate(j['from'])) invalid('from is a valid YYYY-MM-DD.');
    return BodyFatSourceRevision._(
      revision,
      j['from']! as String,
      BodyFatSource.fromJson(j['source']),
    );
  }
  final int number;
  final String from;
  final BodyFatSource source;
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'revision': number,
    'from': from,
    'source': source.toJson(),
  };
}

/// The source in force on [date]: the latest selection from on or before
/// it (later revision first on the same day), else the Navy default.
({BodyFatSource source, String origin, int? revision}) bodyFatSourceOn(
  String date,
  List<BodyFatSourceRevision> revisions,
) {
  BodyFatSourceRevision? best;
  for (final r in revisions) {
    if (r.from.compareTo(date) > 0) continue;
    if (best == null ||
        r.from.compareTo(best.from) > 0 ||
        (r.from == best.from && r.number > best.number))
      best = r;
  }
  return best == null
      ? (source: BodyFatSource.navy, origin: 'default', revision: null)
      : (source: best.source, origin: 'selected', revision: best.number);
}

/// Contiguous numbering for profile and body-fat source revisions.
void validateNumbered(List<int> numbers, String what) {
  final sorted = [...numbers]..sort();
  for (var i = 0; i < sorted.length; i++) {
    if (sorted[i] != i + 1)
      invalid('$what revisions must start at one with no gaps.');
  }
}
