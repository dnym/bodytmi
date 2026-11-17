import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'dart:convert';

import 'errors.dart';
import 'instant.dart';
import 'quantity.dart';

const _maxTrackPoints = 50000;

/// A walk, run, outdoor time, sedentary stretch or other activity, entered
/// by hand or imported. [countsToward] names the categories (routines) it
/// counts for, each once. Activity never adds energy to the intake budget.
final class ActivityRecord {
  ActivityRecord._(this.json);
  factory ActivityRecord.fromJson(Object? input) {
    final j = jsonObject(input, 'activity');
    checkKeys(j, {
      'id',
      'version',
      'kind',
      'start',
      'end',
      'distance',
      'steps',
      'outdoor',
      'countsToward',
      'approximate',
      'notes',
      'track',
      'import',
    });
    identifier(j, 'id');
    identifier(j, 'kind');
    final version = j['version'] ?? 1;
    if (version is! int || version < 1) invalid('version must be positive.');
    final start = parseInstant(j['start'], 'start');
    final end = parseInstant(j['end'], 'end');
    if (!end.isAfter(start)) invalid('An activity ends after it starts.');
    if (end.difference(start).inHours >= 24)
      invalid('An activity lasts less than 24 hours.');
    if (j['distance'] != null &&
        Quantity.fromJson(j['distance']).dimension != Dimension.distance)
      invalid('distance is a distance.');
    final steps = j['steps'];
    if (steps != null && (steps is! int || steps < 0 || steps > 1000000))
      invalid('steps is a whole number from 0 to 1000000.');
    for (final key in ['outdoor', 'approximate']) {
      if (j[key] != null && j[key] is! bool) invalid('$key is a boolean.');
    }
    final seen = <String>{};
    for (final c in (j['countsToward'] as List?) ?? const []) {
      if (!seen.add(identifier({'countsToward': c}, 'countsToward')))
        invalid('countsToward names a category once.');
    }
    if (seen.length > 16) invalid('At most 16 categories.');
    final notes = j['notes'];
    if (notes != null &&
        (notes is! String || notes.trim().isEmpty || notes.length > 4000))
      invalid('Notes are nonempty text of at most 4000 characters.');
    if (j['track'] != null) {
      final points = jsonList(j, 'track');
      if (points.isEmpty || points.length > _maxTrackPoints)
        invalid('A track has 1–$_maxTrackPoints points.');
      DateTime? previous;
      for (final p in points) {
        final x = jsonObject(p, 'track point');
        checkKeys(x, {'at', 'latitude', 'longitude', 'elevation'});
        final at = parseInstant(x['at'], 'track at');
        if (at.isBefore(start) || at.isAfter(end))
          invalid('Track points lie within the activity.');
        if (previous != null && at.isBefore(previous))
          invalid('Track points are in time order.');
        previous = at;
        final lat = _number(x['latitude'], 'latitude');
        final lon = _number(x['longitude'], 'longitude');
        if (lat < -90 || lat > 90 || lon < -180 || lon > 180)
          invalid('Track coordinates are out of range.');
        if (x['elevation'] != null) _number(x['elevation'], 'elevation');
      }
    }
    if (j['import'] != null) {
      final imp = jsonObject(j['import'], 'import');
      checkKeys(imp, {'namespace', 'sourceId'});
      identifier(imp, 'namespace');
      if (requiredString(imp, 'sourceId').length > 256)
        invalid('An import source id is at most 256.');
    }
    return ActivityRecord._(Map.unmodifiable({...j, 'version': version}));
  }

  final Map<String, Object?> json;
  String get id => json['id']! as String;
  int get version => json['version']! as int;
  String get kind => json['kind']! as String;
  DateTime get start => parseInstant(json['start'], 'start');
  DateTime get end => parseInstant(json['end'], 'end');
  int get minutes => end.difference(start).inMinutes;
  bool get outdoor => json['outdoor'] == true;

  /// The local date of the start: the day the activity belongs to.
  String get date => (json['start']! as String).substring(0, 10);
  List<String> get countsToward => [
    for (final c in (json['countsToward'] as List?) ?? const []) c as String,
  ];
  String? get importNamespace =>
      (json['import'] as Map?)?['namespace'] as String?;
  String? get importSourceId =>
      (json['import'] as Map?)?['sourceId'] as String?;

  /// Great-circle length of the track in metres (haversine, mean Earth
  /// radius 6371 km), or null without a track.
  double? get trackMetres {
    final track = json['track'] as List?;
    if (track == null) return null;
    var sum = 0.0;
    for (var i = 1; i < track.length; i++) {
      final a = track[i - 1] as Map, b = track[i] as Map;
      sum += haversineMetres(
        _number(a['latitude'], 'latitude'),
        _number(a['longitude'], 'longitude'),
        _number(b['latitude'], 'latitude'),
        _number(b['longitude'], 'longitude'),
      );
    }
    return sum;
  }

  Map<String, Object?> toJson() => json;

  Map<String, Object?> describe() => {
    for (final e in json.entries)
      if (e.key != 'track') e.key: e.value,
    'date': date,
    'minutes': minutes,
    if (json['track'] != null) ...{
      'trackPoints': (json['track']! as List).length,
      'trackDistance': {
        'value': (trackMetres! / 1000).toStringAsFixed(3),
        'unit': 'km',
        'method': 'haversine over the track points',
      },
    },
  };
}

/// Coordinates and elevation are decimal strings or JSON numbers (from
/// GPS files); they are geometry, not exact quantities.
double _number(Object? v, String label) {
  if (v is num) return v.toDouble();
  if (v is String) {
    final d = double.tryParse(v);
    if (d != null && d.isFinite) return d;
  }
  invalid('$label is a number.');
}

double haversineMetres(double lat1, double lon1, double lat2, double lon2) {
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1), dLon = rad(lon2 - lon1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.pow(math.sin(dLon / 2), 2);
  return 2 * 6371000 * math.asin(math.min(1, math.sqrt(a)));
}

void validateActivityRecords(List<ActivityRecord> records) {
  final ids = <String>{};
  for (final r in records) {
    if (!ids.add(r.id)) invalid('Duplicate activity ${r.id}.');
  }
}

const activityImportFormat = 'bodytmi-activity-import/1';

/// One entry of a `bodytmi-activity-import/1` document.
final class ImportedActivity {
  ImportedActivity._(this.sourceId, this.json);
  factory ImportedActivity.fromJson(Object? input, String namespace) {
    final j = jsonObject(input, 'imported activity');
    if (j.containsKey('version') || j.containsKey('import'))
      invalid('An imported activity has no version or import field.');
    final sourceId = requiredString(j, 'sourceId');
    if (sourceId.length > 256)
      invalid('An import sourceId is 1 to 256 characters.');
    final item = ImportedActivity._(sourceId, Map.unmodifiable(j));
    item.record(namespace, 1);
    return item;
  }
  final String sourceId;
  final Map<String, Object?> json;
  String id(String namespace) =>
      json['id'] as String? ??
      '$namespace-${sha256.convert(utf8.encode('$namespace\u0000$sourceId')).toString().substring(0, 24)}';
  ActivityRecord record(String namespace, int version) =>
      ActivityRecord.fromJson({
        for (final e in json.entries)
          if (e.key != 'sourceId') e.key: e.value,
        'id': id(namespace),
        'version': version,
        'import': {'namespace': namespace, 'sourceId': sourceId},
      });
}

/// A neutral bulk import of walks and workouts with optional GPS tracks
/// (D16); converters for particular apps (TCX, GPX) are separate tools.
final class ActivityImportDocument {
  ActivityImportDocument._(this.namespace, this.source, this.activities);
  factory ActivityImportDocument.fromJson(Object? input) {
    final j = jsonObject(input, 'activity import');
    checkKeys(j, {'format', 'source', 'activities'});
    if (j['format'] != activityImportFormat)
      invalid(
        'Unsupported activity import format; expected $activityImportFormat.',
      );
    final source = jsonObject(j['source'], 'source');
    checkKeys(source, {'namespace', 'app', 'version', 'exportedAt'});
    final namespace = identifier(source, 'namespace');
    if (namespace.length > 64)
      invalid('source namespace must be at most 64 characters.');
    for (final key in ['app', 'version']) {
      final v = source[key];
      if (v != null && (v is! String || v.isEmpty || v.length > 200))
        invalid('source $key is nonempty text of at most 200.');
    }
    if (source['exportedAt'] != null)
      parseInstant(source['exportedAt'], 'exportedAt');
    final list = jsonList(j, 'activities');
    if (list.isEmpty || list.length > 100000)
      invalid('An activity import holds 1–100000 activities.');
    final items = [
      for (final a in list) ImportedActivity.fromJson(a, namespace),
    ];
    final sources = <String>{}, ids = <String>{};
    for (final i in items) {
      if (!sources.add(i.sourceId))
        invalid('Duplicate import sourceId: ${i.sourceId}.');
      if (!ids.add(i.id(namespace)))
        invalid('Duplicate activity id: ${i.id(namespace)}.');
    }
    return ActivityImportDocument._(
      namespace,
      Map.unmodifiable(source),
      List.unmodifiable(items),
    );
  }
  final String namespace;
  final Map<String, Object?> source;
  final List<ImportedActivity> activities;
}
