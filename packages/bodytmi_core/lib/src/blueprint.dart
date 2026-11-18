import 'equipment.dart';
import 'errors.dart';
import 'quantity.dart';

/// One open choice of a [Blueprint]: what the person fills in before the
/// blueprint becomes ordinary workouts and a programme.
///
/// Kinds: `exercise`, `implementation` and `equipment` take an identifier
/// (optionally limited to `options`, and an exercise to a `family`);
/// `setting` takes one of its `options`; `quantity` takes a quantity of its
/// `dimension`, optionally within inclusive `minimum`/`maximum`. A choice
/// with a `default` may be left out when instantiating.
final class BlueprintChoice {
  BlueprintChoice._(
    this.id,
    this.kind,
    this.label,
    this.notes,
    this.options,
    this.family,
    this.dimension,
    this.minimum,
    this.maximum,
    this.defaultValue,
  );

  factory BlueprintChoice.fromJson(Object? input) {
    final j = jsonObject(input, 'blueprint choice');
    checkKeys(j, {
      'id',
      'kind',
      'label',
      'notes',
      'options',
      'family',
      'dimension',
      'minimum',
      'maximum',
      'default',
    });
    final kind = requiredString(j, 'kind');
    if (!_kinds.contains(kind))
      invalid('A blueprint choice kind is ${_kinds.join(', ')}.');
    final label = _text(j, 'label', 200);
    final notes = _text(j, 'notes', 4000);
    List<String>? options;
    if (j.containsKey('options')) {
      final list = jsonList(j, 'options');
      if (list.isEmpty || list.length > 1000)
        invalid('Blueprint choice options list 1 to 1000 values.');
      options = [
        for (final item in list) identifier({'option': item}, 'option'),
      ];
      if (options.toSet().length != options.length)
        invalid('Blueprint choice options must be distinct.');
    }
    final family = j['family'] == null ? null : identifier(j, 'family');
    final quantity = kind == 'quantity';
    final numeric = kind == 'number' || kind == 'integer';
    if (kind == 'setting' && options == null)
      invalid('A setting choice lists its options.');
    if (!_identifierKinds.contains(kind) && options != null)
      invalid('Only identifier choices have options.');
    if (family != null && kind != 'exercise')
      invalid('Only an exercise choice can be limited to a family.');
    Dimension? dimension;
    if (quantity) {
      final name = requiredString(j, 'dimension');
      dimension = Dimension.values.where((d) => d.name == name).firstOrNull;
      if (dimension == null) invalid('Unknown choice dimension $name.');
    } else if (j.containsKey('dimension')) {
      invalid('Only a quantity choice has a dimension.');
    }
    if (!quantity &&
        !numeric &&
        (j.containsKey('minimum') || j.containsKey('maximum')))
      invalid('Only quantity, number and integer choices have bounds.');
    Object? bound(String key) {
      if (!j.containsKey(key)) return null;
      if (kind == 'number') return Decimal.parse(requiredString(j, key));
      if (kind == 'integer') {
        final v = j[key];
        return v is int ? v : invalid('Integer choice $key is an integer.');
      }
      final q = Quantity.fromJson(j[key]);
      if (q.dimension != dimension)
        invalid('Choice $key must have the choice dimension.');
      return q;
    }

    final minimum = bound('minimum');
    final maximum = bound('maximum');
    if (minimum != null &&
        maximum != null &&
        (minimum as Comparable).compareTo(maximum) > 0)
      invalid('Choice minimum exceeds its maximum.');
    final choice = BlueprintChoice._(
      identifier(j, 'id'),
      kind,
      label,
      notes,
      options,
      family,
      dimension,
      minimum,
      maximum,
      null,
    );
    if (!j.containsKey('default')) return choice;
    return BlueprintChoice._(
      choice.id,
      kind,
      label,
      notes,
      options,
      family,
      dimension,
      minimum,
      maximum,
      choice.resolve(j['default']),
    );
  }

  static const _identifierKinds = {
    'exercise',
    'implementation',
    'equipment',
    'gym',
    'setting',
  };
  static const _kinds = {
    ..._identifierKinds,
    'quantity',
    'number',
    'integer',
    'plates',
  };

  final String id, kind;
  final String? label, notes, family;
  final List<String>? options;
  final Dimension? dimension;

  /// A [Quantity] for quantity choices, a [Decimal] for number choices, an
  /// int for integer choices.
  final Object? minimum, maximum;

  bool _outside(Comparable<Object?> value) =>
      (minimum != null && value.compareTo(minimum) < 0) ||
      (maximum != null && value.compareTo(maximum) > 0);

  /// The validated default (an identifier string or a quantity JSON map).
  final Object? defaultValue;

  /// Validates a supplied value, returning its JSON form. Family membership
  /// needs stored families and is checked by the caller.
  Object resolve(Object? value) {
    switch (kind) {
      case 'quantity':
        final q = Quantity.fromJson(value);
        if (q.dimension != dimension)
          invalid('Choice $id needs a ${dimension!.name} quantity.');
        if (_outside(q)) invalid('Choice $id is outside its bounds.');
        return {'value': q.enteredValue, 'unit': q.enteredUnit.name};
      case 'number':
        if (value is! String) invalid('Choice $id is a decimal string.');
        if (_outside(Decimal.parse(value)))
          invalid('Choice $id is outside its bounds.');
        return value;
      case 'integer':
        if (value is! int) invalid('Choice $id is an integer.');
        if (_outside(value)) invalid('Choice $id is outside its bounds.');
        return value;
      case 'plates':
        if (value is! List || value.isEmpty || value.length > 64)
          invalid('Choice $id lists 1 to 64 plate denominations.');
        final stock = [for (final p in value) PlateStock.fromJson(p)];
        if (stock.map((p) => p.mass.value.toString()).toSet().length !=
            stock.length)
          invalid('Choice $id plate denominations must be distinct.');
        return [
          for (final p in stock)
            {
              'mass': {
                'value': p.mass.enteredValue,
                'unit': p.mass.enteredUnit.name,
              },
              'count': p.count,
            },
        ];
      default:
        final text = identifier({id: value}, id);
        if (options != null && !options!.contains(text))
          invalid('Choice $id must be one of ${options!.join(', ')}.');
        return text;
    }
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind,
    if (label != null) 'label': label,
    if (notes != null) 'notes': notes,
    if (options != null) 'options': options,
    if (family != null) 'family': family,
    if (dimension != null) 'dimension': dimension!.name,
    if (minimum != null) 'minimum': _boundJson(minimum!),
    if (maximum != null) 'maximum': _boundJson(maximum!),
    if (defaultValue != null) 'default': defaultValue,
  };
}

Object _boundJson(Object bound) => switch (bound) {
  Quantity q => {'value': q.enteredValue, 'unit': q.enteredUnit.name},
  Decimal d => d.toString(),
  _ => bound,
};

String? _text(Map<String, Object?> j, String key, int max) {
  final value = j[key];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty || value.length > max)
    invalid(
      'Blueprint $key must be a nonempty string of at most $max characters.',
    );
  return value;
}

/// A versioned programme or workout definition with declared open choices.
///
/// `workouts` maps local keys to workout definition JSON without `id`;
/// `program` is optional programme definition JSON without `id`; `presets`
/// maps local keys to progression preset JSON without `id`. Anywhere in them
/// a single-key object is a placeholder:
///
/// * `{"$choice": id}` — the filled choice value;
/// * `{"$scale": {"choice", "factor", "step"?, "rounding"?}}` — a quantity
///   choice times an exact factor, rounded to a multiple of `step` (in the
///   choice's entered unit) `down`, `up` or `nearest` (half up);
/// * `{"$workoutId": key}` / `{"$workoutRevision": key}` — the identity and
///   revision a workout of this blueprint is published as;
/// * `{"$presetId": key}` — a preset's published identity;
/// * `{"$presetRevision": key}` — the revision it is published as;
/// * `{"$value": choice}` / `{"$unit": choice}` — the entered value string or
///   unit name of a quantity choice (e.g. a scale range start and unit).
///
/// `instances` maps local keys to equipment instance JSON without `id`
/// (equipment blueprints: an Olympic barbell with its bar mass and plates
/// left open), published as `<name>-<key>`.
///
/// An unfilled blueprint can never be started: it is a separate record, and
/// instantiation parses every document with the ordinary validators.
final class Blueprint {
  Blueprint._(
    this.id,
    this.name,
    this.notes,
    this.source,
    this.choices,
    this.workouts,
    this.program,
    this.presets,
    this.instances,
  );

  factory Blueprint.fromJson(Object? input) {
    final j = jsonObject(input, 'blueprint');
    checkKeys(j, {
      'id',
      'name',
      'notes',
      'source',
      'choices',
      'workouts',
      'program',
      'presets',
      'instances',
    });
    final choiceList = j['choices'] == null
        ? const <Object?>[]
        : jsonList(j, 'choices');
    if (choiceList.length > 100)
      invalid('A blueprint has at most 100 choices.');
    final choices = [for (final c in choiceList) BlueprintChoice.fromJson(c)];
    final choiceIds = {for (final c in choices) c.id};
    if (choiceIds.length != choices.length)
      invalid('Blueprint choice identities must be unique.');
    Map<String, Map<String, Object?>> documents(String key, int max) {
      if (!j.containsKey(key)) return const {};
      final map = jsonObject(j[key], key);
      if (map.isEmpty || map.length > max)
        invalid('Blueprint $key, when given, has 1 to $max entries.');
      final keys = map.keys.toList()..sort();
      return Map.unmodifiable({
        for (final k in keys)
          identifier({key: k}, key): (() {
            final doc = jsonObject(map[k], '$key $k');
            if (doc.containsKey('id'))
              invalid('Blueprint $key templates get their id when filled in.');
            return doc;
          })(),
      });
    }

    final workouts = documents('workouts', 32);
    final presets = documents('presets', 64);
    final instances = documents('instances', 64);
    if (workouts.isEmpty && instances.isEmpty)
      invalid('A blueprint defines a workout or an equipment instance.');
    final program = j['program'] == null
        ? null
        : jsonObject(j['program'], 'program');
    if (program != null && program.containsKey('id'))
      invalid('Blueprint program templates get their id when filled in.');
    final blueprint = Blueprint._(
      identifier(j, 'id'),
      _requiredText(j, 'name', 200),
      _text(j, 'notes', 4000),
      _text(j, 'source', 4000),
      List.unmodifiable(choices),
      workouts,
      program,
      presets,
      instances,
    );
    final used = <String>{};
    for (final doc in [
      ...workouts.values,
      ...presets.values,
      ...instances.values,
      ?program,
    ]) {
      blueprint._walk(doc, (kind, argument) {
        switch (kind) {
          case r'$choice':
            final id = identifier({'choice': argument}, 'choice');
            if (!choiceIds.contains(id))
              invalid('Placeholder names undeclared choice $id.');
            used.add(id);
          case r'$scale':
            final s = jsonObject(argument, r'$scale');
            checkKeys(s, {'choice', 'factor', 'step', 'rounding'});
            final id = identifier(s, 'choice');
            final choice = choices.where((c) => c.id == id).firstOrNull;
            if (choice == null || choice.kind != 'quantity')
              invalid(r'$scale needs a declared quantity choice.');
            used.add(id);
            _scaleArguments(s);
          case r'$value' || r'$unit':
            final id = identifier({'choice': argument}, 'choice');
            final choice = choices.where((c) => c.id == id).firstOrNull;
            if (choice == null || choice.kind != 'quantity')
              invalid('$kind needs a declared quantity choice.');
            used.add(id);
          case r'$workoutId' || r'$workoutRevision':
            if (!workouts.containsKey(argument))
              invalid('Placeholder names undeclared workout $argument.');
          case r'$presetId' || r'$presetRevision':
            if (!presets.containsKey(argument))
              invalid('Placeholder names undeclared preset $argument.');
          default:
            invalid('Unknown blueprint placeholder $kind.');
        }
        return null;
      });
    }
    final unused = choiceIds.difference(used);
    if (unused.isNotEmpty)
      invalid('Blueprint choices are never used: ${unused.join(', ')}.');
    return blueprint;
  }

  final String id, name;
  final String? notes, source;
  final List<BlueprintChoice> choices;
  final Map<String, Map<String, Object?>> workouts, presets, instances;
  final Map<String, Object?>? program;

  /// Every choice value: supplied, else its default. Missing required
  /// choices and unknown names are validation errors.
  Map<String, Object> resolveChoices(Map<String, Object?> supplied) {
    final known = {for (final c in choices) c.id};
    final unknown = supplied.keys.where((k) => !known.contains(k)).toList();
    if (unknown.isNotEmpty)
      invalid('Unknown blueprint choices: ${unknown.join(', ')}.');
    final missing = [
      for (final c in choices)
        if (!supplied.containsKey(c.id) && c.defaultValue == null) c.id,
    ];
    if (missing.isNotEmpty)
      invalid('Blueprint choices still open: ${missing.join(', ')}.');
    return {
      for (final c in choices)
        c.id: supplied.containsKey(c.id)
            ? c.resolve(supplied[c.id])
            : c.defaultValue!,
    };
  }

  /// The filled documents for instance [name]: workout and preset JSON with
  /// ids `<name>-<key>`, and the programme with id [name], every
  /// placeholder replaced. [workoutRevisions] gives the revision each
  /// workout is published as. Nothing is parsed here; callers parse each
  /// document with its ordinary validator.
  ({
    Map<String, Map<String, Object?>> workouts,
    Map<String, Map<String, Object?>> presets,
    Map<String, Map<String, Object?>> instances,
    Map<String, Object?>? program,
  })
  fill(
    String name,
    Map<String, Object> resolved,
    Map<String, int> workoutRevisions, [
    Map<String, int> presetRevisions = const {},
  ]) {
    identifier({'name': name}, 'name');
    Object? replace(String kind, Object? argument) => switch (kind) {
      r'$choice' => resolved[argument]!,
      r'$scale' => _scale(jsonObject(argument, r'$scale'), resolved),
      r'$workoutId' => '$name-$argument',
      r'$workoutRevision' =>
        workoutRevisions[argument] ??
            invalid('No revision for workout $argument.'),
      r'$presetId' => '$name-$argument',
      r'$presetRevision' =>
        presetRevisions[argument] ??
            invalid('No revision for preset $argument.'),
      r'$value' => (resolved[argument]! as Map<String, Object?>)['value'],
      r'$unit' => (resolved[argument]! as Map<String, Object?>)['unit'],
      _ => invalid('Unknown blueprint placeholder $kind.'),
    };
    Map<String, Object?> fillDoc(Map<String, Object?> doc, String id) => {
      'id': id,
      ...(_walk(doc, replace) as Map<String, Object?>),
    };
    return (
      workouts: {
        for (final e in workouts.entries)
          e.key: fillDoc(e.value, '$name-${e.key}'),
      },
      presets: {
        for (final e in presets.entries)
          e.key: fillDoc(e.value, '$name-${e.key}'),
      },
      instances: {
        for (final e in instances.entries)
          e.key: fillDoc(e.value, '$name-${e.key}'),
      },
      program: program == null ? null : fillDoc(program!, name),
    );
  }

  /// Copies [value], replacing each placeholder object by [replace].
  Object? _walk(
    Object? value,
    Object? Function(String kind, Object? argument) replace,
  ) {
    if (value is Map) {
      final map = value.cast<String, Object?>();
      if (map.length == 1 && map.keys.single.startsWith(r'$'))
        return replace(map.keys.single, map.values.single);
      return {for (final e in map.entries) e.key: _walk(e.value, replace)};
    }
    if (value is List) return [for (final item in value) _walk(item, replace)];
    return value;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    if (notes != null) 'notes': notes,
    if (source != null) 'source': source,
    if (choices.isNotEmpty) 'choices': [for (final c in choices) c.toJson()],
    if (workouts.isNotEmpty) 'workouts': workouts,
    if (program != null) 'program': program,
    if (presets.isNotEmpty) 'presets': presets,
    if (instances.isNotEmpty) 'instances': instances,
  };
}

String _requiredText(Map<String, Object?> j, String key, int max) =>
    _text(j, key, max) ?? invalid('Blueprint $key is required.');

({Decimal factor, Decimal? step, String rounding}) _scaleArguments(
  Map<String, Object?> s,
) {
  final factor = Decimal.parse(requiredString(s, 'factor'));
  if (factor.compareTo(Decimal.zero) <= 0)
    invalid(r'A $scale factor is positive.');
  final step = s['step'] == null
      ? null
      : Decimal.parse(requiredString(s, 'step'));
  if (step != null && step.compareTo(Decimal.zero) <= 0)
    invalid(r'A $scale step is positive.');
  final rounding = s['rounding'] == null
      ? 'nearest'
      : requiredString(s, 'rounding');
  if (!{'down', 'up', 'nearest'}.contains(rounding))
    invalid(r'$scale rounding is down, up or nearest.');
  if (s.containsKey('rounding') && step == null)
    invalid(r'$scale rounding needs a step.');
  return (factor: factor, step: step, rounding: rounding);
}

Map<String, Object?> _scale(
  Map<String, Object?> s,
  Map<String, Object> resolved,
) {
  final args = _scaleArguments(s);
  final input = resolved[identifier(s, 'choice')]! as Map<String, Object?>;
  var value = Decimal.parse(input['value']! as String) * args.factor;
  if (args.step case final step?) {
    final floor = value.floorToMultiple(step);
    final remainder = value - floor;
    final up =
        remainder.compareTo(Decimal.zero) > 0 &&
        (args.rounding == 'up' ||
            (args.rounding == 'nearest' &&
                (remainder + remainder).compareTo(step) >= 0));
    value = up ? floor + step : floor;
  }
  return {'value': value.toString(), 'unit': input['unit']};
}

/// A blueprint's immutable numbered revision.
final class BlueprintRevision {
  BlueprintRevision._(this.number, this.blueprint);
  factory BlueprintRevision.publish(
    Blueprint blueprint, {
    BlueprintRevision? previous,
  }) {
    if (previous != null && previous.blueprint.id != blueprint.id)
      invalid('Blueprint revision must retain identity.');
    return BlueprintRevision._((previous?.number ?? 0) + 1, blueprint);
  }
  factory BlueprintRevision.fromJson(Object? input) {
    final j = jsonObject(input, 'blueprint revision');
    checkKeys(j, {'schemaVersion', 'revision', 'blueprint'});
    final revision = j['revision'];
    if (j['schemaVersion'] != 1 || revision is! int || revision < 1)
      invalid('Invalid blueprint revision.');
    return BlueprintRevision._(revision, Blueprint.fromJson(j['blueprint']));
  }
  final int number;
  final Blueprint blueprint;
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'revision': number,
    'blueprint': blueprint.toJson(),
  };
}

/// Lineage of one filled-in blueprint: which blueprint revision and choices
/// produced which published workout, programme and preset revisions. Filling
/// it in again (with the same or new choices, or a newer blueprint revision)
/// is the next numbered receipt of the same instance.
final class BlueprintInstance {
  BlueprintInstance({
    required this.id,
    required this.number,
    required this.blueprintId,
    required this.blueprintRevision,
    required Map<String, Object> choices,
    required Map<String, int> workouts,
    required this.programRevision,
    required Map<String, int> presets,
    Map<String, int> instances = const {},
  }) : choices = Map.unmodifiable(choices),
       workouts = Map.unmodifiable(workouts),
       presets = Map.unmodifiable(presets),
       instances = Map.unmodifiable(instances) {
    identifier({'id': id}, 'id');
    identifier({'id': blueprintId}, 'id');
    if (number < 1 || blueprintRevision < 1 || (programRevision ?? 1) < 1)
      invalid('Invalid blueprint instance numbering.');
    if ([
      ...workouts.values,
      ...presets.values,
      ...instances.values,
    ].any((n) => n < 1))
      invalid('Invalid blueprint instance revision.');
    if (workouts.isEmpty && instances.isEmpty)
      invalid('A blueprint instance publishes a workout or an instance.');
  }

  factory BlueprintInstance.fromJson(Object? input) {
    final j = jsonObject(input, 'blueprint instance');
    checkKeys(j, {
      'schemaVersion',
      'id',
      'number',
      'blueprint',
      'blueprintRevision',
      'choices',
      'workouts',
      'programRevision',
      'presets',
      'instances',
    });
    if (j['schemaVersion'] != 1) invalid('Invalid blueprint instance.');
    int count(Object? v) =>
        v is int ? v : invalid('Blueprint instance revisions are integers.');
    Map<String, int> revisions(String key) => {
      for (final e in jsonObject(j[key] ?? <String, Object?>{}, key).entries)
        identifier({key: e.key}, key): count(e.value),
    };
    return BlueprintInstance(
      id: identifier(j, 'id'),
      number: count(j['number']),
      blueprintId: identifier(j, 'blueprint'),
      blueprintRevision: count(j['blueprintRevision']),
      choices: {
        for (final e in jsonObject(
          j['choices'] ?? <String, Object?>{},
          'choices',
        ).entries)
          e.key: e.value ?? invalid('Blueprint instance choices are filled.'),
      },
      workouts: revisions('workouts'),
      programRevision: j['programRevision'] == null
          ? null
          : count(j['programRevision']),
      presets: revisions('presets'),
      instances: revisions('instances'),
    );
  }

  final String id, blueprintId;
  final int number, blueprintRevision;
  final int? programRevision;
  final Map<String, Object> choices;

  /// Local key → published revision (identity `<id>-<key>`).
  final Map<String, int> workouts, presets, instances;

  String workoutId(String key) => '$id-$key';
  String instanceId(String key) => '$id-$key';
  String presetId(String key) => '$id-$key';

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'id': id,
    'number': number,
    'blueprint': blueprintId,
    'blueprintRevision': blueprintRevision,
    if (choices.isNotEmpty) 'choices': choices,
    if (workouts.isNotEmpty) 'workouts': workouts,
    if (programRevision != null) 'programRevision': programRevision,
    if (presets.isNotEmpty) 'presets': presets,
    if (instances.isNotEmpty) 'instances': instances,
  };
}

void validateBlueprintRevisions(List<BlueprintRevision> revisions) {
  final numbers = <String, Set<int>>{};
  for (final r in revisions)
    if (!numbers.putIfAbsent(r.blueprint.id, () => <int>{}).add(r.number))
      invalid('Duplicate blueprint revision.');
  for (final versions in numbers.values)
    if (versions.any((n) => n > versions.length))
      invalid('Blueprint revisions must start at one with no gaps.');
}

void validateBlueprintInstances(
  List<BlueprintInstance> instances,
  List<BlueprintRevision> blueprints,
) {
  final numbers = <String, Set<int>>{};
  final published = {
    for (final r in blueprints) '${r.blueprint.id}/${r.number}': r.blueprint,
  };
  for (final i in instances) {
    if (!numbers.putIfAbsent(i.id, () => <int>{}).add(i.number))
      invalid('Duplicate blueprint instance receipt.');
    final blueprint = published['${i.blueprintId}/${i.blueprintRevision}'];
    if (blueprint == null)
      invalid('Blueprint instance ${i.id} names an unpublished blueprint.');
    if (blueprint.workouts.keys
            .toSet()
            .difference(i.workouts.keys.toSet())
            .isNotEmpty ||
        i.workouts.keys
            .toSet()
            .difference(blueprint.workouts.keys.toSet())
            .isNotEmpty ||
        (blueprint.program == null) != (i.programRevision == null) ||
        blueprint.presets.length != i.presets.length ||
        !blueprint.presets.keys.every(i.presets.containsKey) ||
        blueprint.instances.length != i.instances.length ||
        !blueprint.instances.keys.every(i.instances.containsKey))
      invalid('Blueprint instance ${i.id} does not match its blueprint.');
    blueprint.resolveChoices(i.choices);
  }
  for (final versions in numbers.values)
    if (versions.any((n) => n > versions.length))
      invalid('Blueprint instance receipts must start at one with no gaps.');
}
