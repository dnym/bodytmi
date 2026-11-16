import 'body_mass.dart';
import 'errors.dart';
import 'instant.dart';
import 'measure.dart';
import 'quantity.dart';

/// One dated entry for a measure. Either [observedAtText] (an instant with
/// its entered offset, kept verbatim) or [date] (a date only, no invented
/// time) is set. The value's JSON shape depends on the measure kind:
/// quantity {value, unit}, rating integer, boolean, category or text string,
/// event none, interval {end: instant}.
final class Observation {
  Observation._(
    this.id,
    this.measureId,
    this.value,
    this.observedAtText,
    this.date,
    this.attributes,
    this.source,
    this.notes,
    this.contentVersion,
    this.importNamespace,
    this.importSourceId,
  );

  factory Observation.fromJson(Object? input) {
    final j = jsonObject(input, 'observation');
    checkKeys(j, {
      'id',
      'measure',
      'value',
      'observedAt',
      'date',
      'attributes',
      'source',
      'notes',
      'contentVersion',
      'import',
    });
    final observedAt = j['observedAt'];
    final date = j['date'];
    if ((observedAt == null) == (date == null))
      invalid('An observation has exactly one of observedAt and date.');
    if (observedAt != null) parseInstant(observedAt, 'observedAt');
    if (date != null &&
        (date is! String ||
            !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
            DateTime.tryParse(
                  '${date}T00:00:00Z',
                )?.toIso8601String().substring(0, 10) !=
                date))
      invalid('An observation date is a valid YYYY-MM-DD.');
    final attributes = <String, String>{};
    final attrInput = jsonObject(
      j['attributes'] ?? <String, Object?>{},
      'attributes',
    );
    if (j.containsKey('attributes') && attrInput.isEmpty)
      invalid('Empty observation attributes must be omitted.');
    for (final key in (attrInput.keys.toList()..sort())) {
      attributes[identifier({'attribute': key}, 'attribute')] = identifier(
        attrInput,
        key,
      );
    }
    String? text(String key, int max) {
      final v = j[key];
      if (v == null) return null;
      if (v is! String || v.trim().isEmpty || v.length > max)
        invalid('Observation $key is nonempty text of at most $max.');
      return v;
    }

    final version = j['contentVersion'] ?? 1;
    if (version is! int || version < 1)
      invalid('contentVersion must be positive.');
    String? namespace, sourceId;
    if (j['import'] != null) {
      final imp = jsonObject(j['import'], 'import');
      checkKeys(imp, {'namespace', 'sourceId'});
      namespace = identifier(imp, 'namespace');
      sourceId = requiredString(imp, 'sourceId');
      if (sourceId.isEmpty || sourceId.length > 256)
        invalid('An import source id is 1 to 256 characters.');
    }
    return Observation._(
      identifier(j, 'id'),
      identifier(j, 'measure'),
      j['value'],
      observedAt as String?,
      date as String?,
      Map.unmodifiable(attributes),
      text('source', 256),
      text('notes', 4000),
      version,
      namespace,
      sourceId,
    );
  }

  /// The body-mass measurement as an observation of measure `body-mass`
  /// with its context as an attribute. The conversion is exact both ways.
  factory Observation.fromBodyMass(BodyMassMeasurement m) =>
      Observation.fromJson({
        'id': m.id,
        'measure': 'body-mass',
        'value': {
          'value': m.mass.enteredValue,
          'unit': m.mass.enteredUnit.name,
        },
        'observedAt': m.observedAtText,
        'attributes': {'context': m.context},
        'source': ?m.source,
        'notes': ?m.notes,
        'contentVersion': m.contentVersion,
      });

  final String id, measureId;
  final Object? value;
  final String? observedAtText, date;
  final Map<String, String> attributes;
  final String? source, notes;
  final int contentVersion;
  final String? importNamespace, importSourceId;

  DateTime? get observedAt => observedAtText == null
      ? null
      : parseInstant(observedAtText, 'observedAt');

  /// The calendar date the entry belongs to: its own date, or the local
  /// date of the instant in its entered offset.
  String get localDate => date ?? observedAtText!.substring(0, 10);

  bool get isBodyMass => measureId == 'body-mass';

  /// This observation as a body-mass measurement (measure `body-mass`).
  BodyMassMeasurement toBodyMass() {
    if (!isBodyMass || observedAtText == null)
      invalid('Only timed body-mass observations are body-mass measurements.');
    final context = attributes['context'];
    if (context == null || attributes.length != 1)
      invalid('A body-mass observation carries exactly its context.');
    final mass = jsonObject(value, 'value');
    return BodyMassMeasurement.fromJson({
      'id': id,
      'context': context,
      'observedAt': observedAtText,
      'mass': {'value': mass['value'], 'unit': mass['unit']},
      'contentVersion': contentVersion,
      'source': ?source,
      'notes': ?notes,
    });
  }

  /// Checks the value and attributes against [measure].
  void validateAgainst(MeasureDefinition measure) {
    if (measure.id != measureId)
      invalid('Observation $id belongs to another measure.');
    for (final e in attributes.entries) {
      if (!measure.attributes.containsKey(e.key))
        invalid('Measure $measureId has no attribute ${e.key}.');
      final allowed = measure.attributes[e.key];
      if (allowed != null && !allowed.contains(e.value))
        invalid(
          'Attribute ${e.key} of $measureId is one of '
          '${allowed.join(', ')}.',
        );
    }
    switch (measure.kind) {
      case 'quantity':
        final q = Quantity.fromJson(value);
        if (q.dimension != measure.dimension)
          invalid(
            'A $measureId value needs a ${measure.dimension!.name} '
            'quantity.',
          );
      case 'rating':
        final v = value;
        if (v is! int ||
            v < measure.scale!.minimum ||
            v > measure.scale!.maximum)
          invalid('A $measureId rating is an integer on its scale.');
      case 'boolean':
        if (value is! bool) invalid('A $measureId value is true or false.');
      case 'category':
        if (value is! String || !measure.values!.contains(value))
          invalid(
            'A $measureId value is one of ${measure.values!.join(', ')}.',
          );
      case 'text':
        final v = value;
        if (v is! String || v.trim().isEmpty || v.length > 4000)
          invalid('A $measureId value is nonempty text of at most 4000.');
      case 'event':
        if (value != null) invalid('A $measureId event has no value.');
      case 'interval':
        final end = jsonObject(value, 'interval');
        checkKeys(end, {'end'});
        final finish = parseInstant(end['end'], 'end');
        if (observedAtText == null)
          invalid('An interval starts at an instant, not a date.');
        if (finish.isBefore(observedAt!))
          invalid('An interval cannot end before it starts.');
    }
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'measure': measureId,
    if (value != null) 'value': value,
    'observedAt': ?observedAtText,
    'date': ?date,
    if (attributes.isNotEmpty) 'attributes': attributes,
    'source': ?source,
    'notes': ?notes,
    'contentVersion': contentVersion,
    if (importNamespace != null)
      'import': {'namespace': importNamespace, 'sourceId': importSourceId},
  };
}

/// A stored observation with its deletion marker. A deleted observation
/// keeps its last content, has a later content version, and blocks reuse
/// of its identity.
final class ObservationRecord {
  ObservationRecord(this.observation, {this.deleted = false}) {
    if (deleted && observation.contentVersion < 2)
      invalid('Deleted observation must have a deletion content version.');
  }
  factory ObservationRecord.fromJson(Object? input) {
    final j = jsonObject(input, 'observation record');
    checkKeys(j, {'observation', 'deleted'});
    if (j['deleted'] is! bool) invalid('deleted must be boolean.');
    return ObservationRecord(
      Observation.fromJson(j['observation']),
      deleted: j['deleted'] as bool,
    );
  }
  final Observation observation;
  final bool deleted;
  Map<String, Object?> toJson() => {
    'observation': observation.toJson(),
    'deleted': deleted,
  };
}

/// Unique identities, and every observation valid for its built-in measure.
/// Body-mass observations must also be exact body-mass measurements.
void validateObservationRecords(
  List<ObservationRecord> records, {
  List<MeasureDefinition> measures = const [],
}) {
  final byId = {
    for (final m in [...builtInMeasures, ...measures]) m.id: m,
  };
  final ids = <String>{};
  for (final r in records) {
    final o = r.observation;
    if (!ids.add(o.id)) invalid('Duplicate observation identity ${o.id}.');
    final measure = byId[o.measureId];
    if (measure == null)
      invalid('Observation ${o.id} names an unknown measure ${o.measureId}.');
    o.validateAgainst(measure);
    if (o.isBodyMass) o.toBodyMass();
  }
}
