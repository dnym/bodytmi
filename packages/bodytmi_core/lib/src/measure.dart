import 'catalog_labels.dart';
import 'errors.dart';
import 'quantity.dart';

/// How a measure's value in force at a time is resolved by default.
///
/// * `latest` — the most recent observation, with its age;
/// * `trend` — the smoothed body-mass trend (daily representative, first
///   seven as-is, then previous + 10% of the difference);
/// * `extrapolated` — a line fitted to a recent window, evaluated at the
///   requested time within explicit limits, labelled an estimate.
///
/// [staleAfterDays] flags a resolved value as stale; null never does.
final class MeasurePolicy {
  MeasurePolicy._(
    this.policy,
    this.staleAfterDays,
    this.windowDays,
    this.minPoints,
    this.minSpanDays,
    this.maxAheadDays,
  );

  factory MeasurePolicy.fromJson(Object? input) {
    final j = jsonObject(input, 'measure policy');
    checkKeys(j, {
      'policy',
      'staleAfterDays',
      'windowDays',
      'minPoints',
      'minSpanDays',
      'maxAheadDays',
    });
    final policy = requiredString(j, 'policy');
    if (!policies.contains(policy))
      invalid('A measure policy is latest, trend or extrapolated.');
    int? days(String key, int min, int max) {
      final v = j[key];
      if (v == null) return null;
      if (v is! int || v < min || v > max)
        invalid('Measure policy $key is an integer from $min to $max.');
      return v;
    }

    final limits = ['windowDays', 'minPoints', 'minSpanDays', 'maxAheadDays'];
    if (policy != 'extrapolated' && limits.any(j.containsKey))
      invalid('Only an extrapolated policy has extrapolation limits.');
    final result = MeasurePolicy._(
      policy,
      days('staleAfterDays', 1, 3650),
      days('windowDays', 1, 3650) ?? 90,
      days('minPoints', 2, 10000) ?? 4,
      days('minSpanDays', 0, 3650) ?? 28,
      days('maxAheadDays', 0, 3650) ?? 30,
    );
    if (result.minSpanDays > result.windowDays)
      invalid('The extrapolation span cannot exceed its window.');
    return result;
  }

  static const policies = {'latest', 'trend', 'extrapolated'};

  final String policy;
  final int? staleAfterDays;

  /// Extrapolation limits (defaults 90, 4, 28 and 30 days or points).
  final int windowDays, minPoints, minSpanDays, maxAheadDays;

  Map<String, Object?> toJson() => {
    'policy': policy,
    if (staleAfterDays != null) 'staleAfterDays': staleAfterDays,
    if (policy == 'extrapolated') ...{
      'windowDays': windowDays,
      'minPoints': minPoints,
      'minSpanDays': minSpanDays,
      'maxAheadDays': maxAheadDays,
    },
  };
}

/// An anchored rating scale, e.g. 0–10 pain with labelled ends.
final class RatingScale {
  RatingScale._(this.minimum, this.maximum, this.anchors);
  factory RatingScale.fromJson(Object? input) {
    final j = jsonObject(input, 'rating scale');
    checkKeys(j, {'minimum', 'maximum', 'anchors'});
    final min = j['minimum'], max = j['maximum'];
    if (min is! int || max is! int || min < 0 || max <= min || max > 1000)
      invalid(
        'A rating scale has integer bounds 0 ≤ minimum < maximum ≤ 1000.',
      );
    final anchors = <int, String>{};
    for (final e in jsonObject(
      j['anchors'] ?? <String, Object?>{},
      'anchors',
    ).entries) {
      final at = int.tryParse(e.key);
      if (at == null || at < min || at > max)
        invalid('Rating anchors label values on the scale.');
      final label = e.value;
      if (label is! String || label.trim().isEmpty || label.length > 200)
        invalid('Rating anchor labels are nonempty, at most 200 characters.');
      anchors[at] = label;
    }
    return RatingScale._(min, max, Map.unmodifiable(anchors));
  }
  final int minimum, maximum;
  final Map<int, String> anchors;
  Map<String, Object?> toJson() => {
    'minimum': minimum,
    'maximum': maximum,
    if (anchors.isNotEmpty)
      'anchors': {
        for (final k in (anchors.keys.toList()..sort())) '$k': anchors[k],
      },
  };
}

/// A measure: what is recorded and how it may be summarised and resolved.
/// Built-in and custom measures behave identically. Kinds:
///
/// * `quantity` — a [Dimension] with a preferred [Unit] (counts such as
///   steps are quantities of a count dimension);
/// * `rating` — an integer on an anchored [RatingScale];
/// * `boolean`, `category` (declared [values]), `text`;
/// * `event` — something happened, no value;
/// * `interval` — a span with a start and an end.
///
/// [attributes] are the attributes observations may carry (site, side,
/// state, method, device, condition, context…), each optionally limited to
/// declared values. A series is one measure with one combination of
/// attribute values; different series never merge silently.
final class MeasureDefinition {
  MeasureDefinition._(
    this.id,
    this.name,
    this.notes,
    this.labels,
    this.kind,
    this.dimension,
    this.unit,
    this.scale,
    this.values,
    this.attributes,
    this.summaries,
    this.resolution,
  );

  factory MeasureDefinition.fromJson(Object? input) {
    final j = jsonObject(input, 'measure');
    checkKeys(j, {
      'id',
      'name',
      'notes',
      'labels',
      'kind',
      'dimension',
      'unit',
      'scale',
      'values',
      'attributes',
      'summaries',
      'resolution',
    });
    final name = j['name'];
    if (name is! String || name.trim().isEmpty || name.length > 200)
      invalid('A measure name is nonempty, at most 200 characters.');
    final notes = j['notes'];
    if (notes != null &&
        (notes is! String || notes.trim().isEmpty || notes.length > 4000))
      invalid('Measure notes are nonempty, at most 4000 characters.');
    final kind = requiredString(j, 'kind');
    if (!kinds.contains(kind)) invalid('Unknown measure kind $kind.');
    Dimension? dimension;
    Unit? unit;
    if (kind == 'quantity') {
      final d = requiredString(j, 'dimension');
      dimension = Dimension.values.where((x) => x.name == d).firstOrNull;
      if (dimension == null) invalid('Unknown measure dimension $d.');
      unit = Unit.parse(requiredString(j, 'unit'));
      if (unit.dimension != dimension)
        invalid('The preferred unit must have the measure dimension.');
    } else if (j.containsKey('dimension') || j.containsKey('unit')) {
      invalid('Only a quantity measure has a dimension and unit.');
    }
    final scale = j['scale'] == null ? null : RatingScale.fromJson(j['scale']);
    if ((kind == 'rating') != (scale != null))
      invalid('A rating measure, and only a rating, has a scale.');
    List<String>? values;
    if (j.containsKey('values')) {
      if (kind != 'category') invalid('Only a category measure has values.');
      values = _identifiers(jsonList(j, 'values'), 'values', 1000);
    } else if (kind == 'category') {
      invalid('A category measure declares its values.');
    }
    final attributes = <String, List<String>?>{};
    final attrInput = jsonObject(
      j['attributes'] ?? <String, Object?>{},
      'attributes',
    );
    if (attrInput.length > 16) invalid('A measure has at most 16 attributes.');
    for (final key in (attrInput.keys.toList()..sort())) {
      final spec = jsonObject(attrInput[key], 'attribute $key');
      checkKeys(spec, {'values'});
      attributes[identifier({
        'attribute': key,
      }, 'attribute')] = spec.containsKey('values')
          ? _identifiers(jsonList(spec, 'values'), key, 1000)
          : null;
    }
    final summaries = _identifiers(
      j['summaries'] == null
          ? const ['last', 'count']
          : jsonList(j, 'summaries'),
      'summaries',
      6,
    ).toSet();
    final allowed = switch (kind) {
      'quantity' => const {'mean', 'sum', 'min', 'max', 'last', 'count'},
      'rating' => const {'mean', 'min', 'max', 'last', 'count'},
      'interval' => const {'sum', 'last', 'count'},
      'event' => const {'count'},
      _ => const {'last', 'count'},
    };
    final extra = summaries.difference(allowed);
    if (extra.isNotEmpty)
      invalid('A $kind measure cannot summarise by ${extra.join(', ')}.');
    final resolution = j['resolution'] == null
        ? MeasurePolicy.fromJson({'policy': 'latest'})
        : MeasurePolicy.fromJson(j['resolution']);
    if (resolution.policy == 'trend' &&
        dimension != Dimension.mass &&
        dimension != Dimension.ratio)
      invalid('Trend resolution applies to mass and ratio quantities.');
    if (resolution.policy == 'extrapolated' && kind != 'quantity')
      invalid('Only quantity measures can be extrapolated.');
    return MeasureDefinition._(
      identifier(j, 'id'),
      name,
      notes as String?,
      j.containsKey('labels')
          ? CatalogLabels.fromJson(j['labels'])
          : CatalogLabels.empty,
      kind,
      dimension,
      unit,
      scale,
      values == null ? null : List.unmodifiable(values),
      Map.unmodifiable(attributes),
      Set.unmodifiable(summaries),
      resolution,
    );
  }

  static const kinds = {
    'quantity',
    'rating',
    'boolean',
    'category',
    'text',
    'event',
    'interval',
  };

  final String id, name, kind;
  final String? notes;
  final CatalogLabels labels;
  final Dimension? dimension;
  final Unit? unit;
  final RatingScale? scale;
  final List<String>? values;

  /// Attribute name → allowed values (null: any identifier).
  final Map<String, List<String>?> attributes;
  final Set<String> summaries;
  final MeasurePolicy resolution;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    if (notes != null) 'notes': notes,
    if (!labels.isEmpty) 'labels': labels.toJson(),
    'kind': kind,
    if (dimension != null) 'dimension': dimension!.name,
    if (unit != null) 'unit': unit!.name,
    if (scale != null) 'scale': scale!.toJson(),
    if (values != null) 'values': values,
    if (attributes.isNotEmpty)
      'attributes': {
        for (final e in attributes.entries)
          e.key: {if (e.value != null) 'values': e.value},
      },
    'summaries': [
      for (final s in const ['mean', 'sum', 'min', 'max', 'last', 'count'])
        if (summaries.contains(s)) s,
    ],
    'resolution': resolution.toJson(),
  };
}

List<String> _identifiers(List<Object?> list, String label, int max) {
  if (list.isEmpty || list.length > max)
    invalid('Measure $label lists 1 to $max identifiers.');
  final ids = [
    for (final item in list) identifier({label: item}, label),
  ];
  if (ids.toSet().length != ids.length)
    invalid('Measure $label must be distinct.');
  return ids;
}

/// The measures that ship with the app (revision [builtInMeasureRevision]).
/// Custom measures cannot reuse these identifiers.
const builtInMeasureRevision = 1;

final List<MeasureDefinition> builtInMeasures = List.unmodifiable([
  for (final json in _builtIns) MeasureDefinition.fromJson(json),
]);

const _circumferenceSites = [
  'waist',
  'navel',
  'hip',
  'neck',
  'chest',
  'shoulders',
  'upper-arm',
  'forearm',
  'thigh',
  'calf',
  'wrist',
  'ankle',
];

const _skinfoldSites = [
  'chest',
  'abdomen',
  'thigh',
  'triceps',
  'subscapular',
  'suprailiac',
  'midaxillary',
];

const _builtIns = <Map<String, Object?>>[
  {
    'id': 'body-mass',
    'name': 'Body mass',
    'labels': {
      'sv': {
        'name': 'Kroppsvikt',
        'aliases': ['Vikt'],
      },
    },
    'kind': 'quantity',
    'dimension': 'mass',
    'unit': 'kg',
    'attributes': <String, Object?>{'context': <String, Object?>{}},
    'summaries': ['mean', 'min', 'max', 'last', 'count'],
    'resolution': {'policy': 'trend', 'staleAfterDays': 7},
  },
  {
    'id': 'body-fat',
    'name': 'Body fat',
    'notes':
        'Recorded per method; methods are separate series and are never '
        'averaged unless a body-fat source names them explicitly.',
    'labels': {
      'sv': {
        'name': 'Kroppsfett',
        'aliases': ['Fettprocent'],
      },
    },
    'kind': 'quantity',
    'dimension': 'ratio',
    'unit': 'percent',
    'attributes': {
      'method': {
        'values': ['bio-impedance', 'navy', 'caliper', 'dexa', 'other'],
      },
      'device': <String, Object?>{},
    },
    'summaries': ['mean', 'min', 'max', 'last', 'count'],
    'resolution': {'policy': 'latest', 'staleAfterDays': 60},
  },
  {
    'id': 'height',
    'name': 'Height',
    'labels': {
      'sv': {'name': 'Längd'},
    },
    'kind': 'quantity',
    'dimension': 'distance',
    'unit': 'cm',
    'summaries': ['last', 'count'],
    'resolution': {'policy': 'latest'},
  },
  {
    'id': 'circumference',
    'name': 'Circumference',
    'notes': 'Tape measurements; each site, side and state is its own series.',
    'labels': {
      'sv': {
        'name': 'Omkrets',
        'aliases': ['Måttband'],
      },
    },
    'kind': 'quantity',
    'dimension': 'distance',
    'unit': 'cm',
    'attributes': {
      'site': {'values': _circumferenceSites},
      'side': {
        'values': ['left', 'right'],
      },
      'state': {
        'values': ['relaxed', 'flexed'],
      },
    },
    'summaries': ['mean', 'min', 'max', 'last', 'count'],
    'resolution': {'policy': 'latest', 'staleAfterDays': 60},
  },
  {
    'id': 'skinfold',
    'name': 'Skinfold',
    'notes': 'Caliper readings; repeated readings are kept individually.',
    'labels': {
      'sv': {'name': 'Hudveck'},
    },
    'kind': 'quantity',
    'dimension': 'distance',
    'unit': 'mm',
    'attributes': {
      'site': {'values': _skinfoldSites},
      'side': {
        'values': ['left', 'right'],
      },
    },
    'summaries': ['mean', 'min', 'max', 'last', 'count'],
    'resolution': {'policy': 'latest', 'staleAfterDays': 60},
  },
  {
    'id': 'steps',
    'name': 'Steps',
    'notes': 'A day\'s total step count.',
    'labels': {
      'sv': {
        'name': 'Steg',
        'aliases': ['Stegräkning'],
      },
    },
    'kind': 'quantity',
    'dimension': 'steps',
    'unit': 'step',
    'attributes': {'device': <String, Object?>{}},
    'summaries': ['mean', 'sum', 'min', 'max', 'last', 'count'],
    'resolution': {'policy': 'latest'},
  },
];
