import 'calculation.dart' show round9;
import 'energy.dart';
import 'errors.dart';
import 'quantity.dart';

/// Resolved inputs day-type goals may use (D20). Values are kg and kcal.
typedef DietInputs = ({
  double? maintenanceKcal,
  double? massKg,
  double? fatFreeMassKg,
});

const dietGoalNames = ['energy', 'protein', 'carbohydrate', 'fat', 'fibre'];

/// One daily goal of a day type:
/// * `{fixed: quantity}`;
/// * `{minimum, maximum}` — an inclusive range;
/// * `{basis, factor? | perLb? | perKg?, add?, subtract?}` — basis
///   `maintenance` (energy × factor), `mass` or `fat-free-mass` (amount per
///   lb or per kg of it), then plus/minus fixed amounts;
/// * `{remainder: true}` — carbohydrate or fat: what energy leaves after the
///   other macros (4 / 4 / 9 kcal per g);
/// * `{sum: true}` — energy: the sum of the three macros.
final class GoalSpec {
  GoalSpec._(this.name, this.json);
  factory GoalSpec.fromJson(String name, Object? input) {
    final j = jsonObject(input, name);
    final dimension = name == 'energy' ? Dimension.energy : Dimension.mass;
    void quantity(String key) {
      final q = Quantity.fromJson(j[key]);
      if (q.dimension != dimension)
        invalid('$name $key needs a ${dimension.name} quantity.');
    }

    Decimal positive(String key) {
      final d = Decimal.parse(requiredString(j, key));
      if (d.compareTo(Decimal.zero) <= 0) invalid('$name $key is positive.');
      return d;
    }

    if (j.containsKey('fixed')) {
      checkKeys(j, {'fixed'});
      quantity('fixed');
    } else if (j.containsKey('minimum') || j.containsKey('maximum')) {
      checkKeys(j, {'minimum', 'maximum'});
      quantity('minimum');
      quantity('maximum');
      if (Quantity.fromJson(
            j['minimum'],
          ).value.compareTo(Quantity.fromJson(j['maximum']).value) >
          0)
        invalid('$name minimum exceeds its maximum.');
    } else if (j.containsKey('remainder')) {
      checkKeys(j, {'remainder'});
      if (j['remainder'] != true) invalid('remainder must be true.');
      if (name != 'carbohydrate' && name != 'fat')
        invalid('Only carbohydrate or fat can be the remainder.');
    } else if (j.containsKey('sum')) {
      checkKeys(j, {'sum'});
      if (j['sum'] != true) invalid('sum must be true.');
      if (name != 'energy') invalid('Only energy can be the macro sum.');
    } else {
      checkKeys(j, {'basis', 'factor', 'perLb', 'perKg', 'add', 'subtract'});
      final basis = requiredString(j, 'basis');
      if (basis == 'maintenance') {
        if (name != 'energy') invalid('Only energy uses maintenance.');
        if (j.containsKey('perLb') || j.containsKey('perKg'))
          invalid('A maintenance basis takes a factor.');
        if (j.containsKey('factor')) positive('factor');
      } else if (basis == 'mass' || basis == 'fat-free-mass') {
        if (j.containsKey('factor'))
          invalid('A mass basis takes perLb or perKg.');
        if (j.containsKey('perLb') == j.containsKey('perKg'))
          invalid('$name needs exactly one of perLb and perKg.');
        positive(j.containsKey('perLb') ? 'perLb' : 'perKg');
      } else {
        invalid('basis is maintenance, mass or fat-free-mass.');
      }
      if (j.containsKey('add')) quantity('add');
      if (j.containsKey('subtract')) quantity('subtract');
    }
    return GoalSpec._(name, Map.unmodifiable(j));
  }

  final String name;
  final Map<String, Object?> json;
  String get unit => name == 'energy' ? 'kcal' : 'g';
  bool get isRemainder => json['remainder'] == true;
  bool get isSum => json['sum'] == true;

  /// In the goal's unit (kcal or g).
  static double amount(Object? quantity) {
    final q = Quantity.fromJson(quantity);
    final canonical = double.parse(q.value.toString());
    return q.dimension == Dimension.energy
        ? canonical / 4.184
        : canonical * 1000;
  }

  double? _direct(DietInputs inputs, List<String> missing) {
    if (json.containsKey('fixed')) return amount(json['fixed']);
    final basis = json['basis']! as String;
    final double? base = switch (basis) {
      'maintenance' => inputs.maintenanceKcal,
      'mass' => inputs.massKg,
      _ => inputs.fatFreeMassKg,
    };
    if (base == null) {
      missing.add(basis);
      return null;
    }
    double d(String key) => double.parse(json[key]! as String);
    var value = basis == 'maintenance'
        ? base * (json.containsKey('factor') ? d('factor') : 1)
        : json.containsKey('perKg')
        ? base * d('perKg')
        : base / kgPerLb * d('perLb');
    if (json.containsKey('add')) value += amount(json['add']);
    if (json.containsKey('subtract')) value -= amount(json['subtract']);
    return value;
  }
}

/// A named set of daily goals (D20) with an optional step goal and note.
final class DayType {
  DayType._(this.json, this.goals);
  factory DayType.fromJson(Object? input) {
    final j = jsonObject(input, 'day type');
    checkKeys(j, {'id', 'name', 'notes', 'goals', 'steps'});
    identifier(j, 'id');
    final name = j['name'];
    if (name is! String || name.trim().isEmpty || name.length > 200)
      invalid('A day type name is nonempty, at most 200 characters.');
    final notes = j['notes'];
    if (notes != null &&
        (notes is! String || notes.trim().isEmpty || notes.length > 4000))
      invalid('Day type notes are nonempty, at most 4000 characters.');
    final goalsJson = jsonObject(j['goals'], 'goals');
    if (goalsJson.isEmpty) invalid('A day type has at least one goal.');
    checkKeys(goalsJson, dietGoalNames.toSet());
    final goals = {
      for (final e in goalsJson.entries)
        e.key: GoalSpec.fromJson(e.key, e.value),
    };
    final remainders = goals.values.where((g) => g.isRemainder).length;
    if (remainders > 1) invalid('At most one macro is the remainder.');
    if (remainders == 1) {
      final energy = goals['energy'];
      if (energy == null || energy.isSum || energy.json.containsKey('minimum'))
        invalid('A remainder needs a single-valued energy goal.');
      for (final m in ['protein', 'carbohydrate', 'fat']) {
        if (!goals.containsKey(m))
          invalid('A remainder needs all three macros.');
      }
    }
    if (goals['energy']?.isSum ?? false) {
      for (final m in ['protein', 'carbohydrate', 'fat']) {
        final g = goals[m];
        if (g == null || g.json.containsKey('minimum'))
          invalid(
            'A macro-sum energy needs single-valued protein, '
            'carbohydrate and fat.',
          );
      }
    }
    final steps = j['steps'];
    if (steps != null && (steps is! int || steps < 1 || steps > 200000))
      invalid('steps is a whole number from 1 to 200000.');
    return DayType._(Map.unmodifiable(j), Map.unmodifiable(goals));
  }

  final Map<String, Object?> json;
  final Map<String, GoalSpec> goals;
  String get id => json['id']! as String;
  String get name => json['name']! as String;

  /// Inputs this day type needs: maintenance, mass, fat-free-mass.
  Set<String> get needs => {
    for (final g in goals.values)
      if (g.json['basis'] is String) g.json['basis']! as String,
  };

  /// Every goal resolved against [inputs], in kcal or g, rounded once to
  /// nine fractional digits; unavailable goals name what is missing.
  Map<String, Object?> resolve(DietInputs inputs) {
    final values = <String, double>{};
    final out = <String, Map<String, Object?>>{};
    for (final e in goals.entries) {
      final g = e.value;
      if (g.isRemainder || g.isSum) continue;
      if (g.json.containsKey('minimum')) {
        out[e.key] = {
          'status': 'resolved',
          'minimum': {
            'value': round9(GoalSpec.amount(g.json['minimum'])),
            'unit': g.unit,
          },
          'maximum': {
            'value': round9(GoalSpec.amount(g.json['maximum'])),
            'unit': g.unit,
          },
        };
        continue;
      }
      final missing = <String>[];
      final v = g._direct(inputs, missing);
      if (v == null) {
        out[e.key] = {
          'status': 'unavailable',
          'reason': 'Missing ${missing.join(', ')}.',
        };
      } else if (v < 0) {
        out[e.key] = {
          'status': 'unavailable',
          'reason': 'The goal is negative.',
        };
      } else {
        values[e.key] = v;
      }
    }
    const kcalPerGram = {'protein': 4.0, 'carbohydrate': 4.0, 'fat': 9.0};
    for (final e in goals.entries) {
      if (!e.value.isRemainder) continue;
      final others = [
        for (final m in kcalPerGram.keys)
          if (m != e.key) m,
      ];
      if (!values.containsKey('energy') ||
          others.any((m) => !values.containsKey(m))) {
        out[e.key] = {
          'status': 'unavailable',
          'reason': 'The remainder needs energy and the other macros.',
        };
        continue;
      }
      final rest =
          (values['energy']! -
              others.fold(0.0, (s, m) => s + values[m]! * kcalPerGram[m]!)) /
          kcalPerGram[e.key]!;
      if (rest < 0) {
        out[e.key] = {
          'status': 'unavailable',
          'reason': 'The other macros exceed the energy goal.',
        };
      } else {
        values[e.key] = rest;
      }
    }
    if (goals['energy']?.isSum ?? false) {
      if (kcalPerGram.keys.every(values.containsKey)) {
        values['energy'] = kcalPerGram.entries.fold(
          0.0,
          (s, e) => s + values[e.key]! * e.value,
        );
      } else {
        out['energy'] = {
          'status': 'unavailable',
          'reason': 'The macro sum needs protein, carbohydrate and fat.',
        };
      }
    }
    for (final e in values.entries) {
      out[e.key] = {
        'status': 'resolved',
        'value': {'value': round9(e.value), 'unit': goals[e.key]!.unit},
      };
    }
    return {
      for (final name in dietGoalNames)
        if (out.containsKey(name))
          name: {...out[name]!, 'spec': goals[name]!.json},
    };
  }

  Map<String, Object?> toJson() => json;
}

/// A day type's immutable numbered revision.
final class DayTypeRevision {
  DayTypeRevision._(this.number, this.dayType);
  factory DayTypeRevision.publish(
    DayType dayType, {
    DayTypeRevision? previous,
  }) => DayTypeRevision._((previous?.number ?? 0) + 1, dayType);
  factory DayTypeRevision.fromJson(Object? input) {
    final j = jsonObject(input, 'day type revision');
    checkKeys(j, {'schemaVersion', 'revision', 'dayType'});
    final revision = j['revision'];
    if (j['schemaVersion'] != 1 || revision is! int || revision < 1)
      invalid('Invalid day type revision.');
    return DayTypeRevision._(revision, DayType.fromJson(j['dayType']));
  }
  final int number;
  final DayType dayType;
  String get key => '${dayType.id}/$number';
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'revision': number,
    'dayType': dayType.toJson(),
  };
}

/// A pinned day-type revision.
typedef DayTypeRef = ({String id, int revision});

DayTypeRef dayTypeRefFromJson(Object? input, String label) {
  final j = jsonObject(input, label);
  checkKeys(j, {'id', 'revision'});
  final revision = j['revision'];
  if (revision is! int || revision < 1) invalid('$label revision is positive.');
  return (id: identifier(j, 'id'), revision: revision);
}

Map<String, Object?> dayTypeRefToJson(DayTypeRef ref) => {
  'id': ref.id,
  'revision': ref.revision,
};

/// One day of a flattened cycle, with the path of labels that led to it.
typedef CycleDay = ({DayTypeRef dayType, String? label, List<String> path});

const _maxCycleDays = 3660;

/// Day types arranged with ordered days, groups and repeats (D20), finite
/// or looping. Day *n* of a run is fixed by the calendar (F21).
final class DietCycle {
  DietCycle._(this.json, this.days);
  factory DietCycle.fromJson(Object? input) {
    final j = jsonObject(input, 'diet cycle');
    checkKeys(j, {'id', 'name', 'notes', 'loop', 'days'});
    identifier(j, 'id');
    final name = j['name'];
    if (name is! String || name.trim().isEmpty || name.length > 200)
      invalid('A diet cycle name is nonempty, at most 200 characters.');
    final notes = j['notes'];
    if (notes != null &&
        (notes is! String || notes.trim().isEmpty || notes.length > 4000))
      invalid('Diet cycle notes are nonempty, at most 4000 characters.');
    if (j['loop'] is! bool) invalid('loop must be true or false.');
    final days = <CycleDay>[];
    void walk(List<Object?> nodes, List<String> path, int depth) {
      if (depth > 8) invalid('Cycle nodes nest at most 8 deep.');
      if (nodes.isEmpty) invalid('A cycle group is not empty.');
      for (final n in nodes) {
        final node = jsonObject(n, 'cycle node');
        final label = node['label'];
        if (label != null &&
            (label is! String || label.trim().isEmpty || label.length > 200))
          invalid('A cycle label is nonempty, at most 200 characters.');
        switch (node['type']) {
          case 'day':
            checkKeys(node, {'type', 'dayType', 'label'});
            days.add((
              dayType: dayTypeRefFromJson(node['dayType'], 'dayType'),
              label: label as String?,
              path: List.unmodifiable(path),
            ));
          case 'group':
            checkKeys(node, {'type', 'label', 'days'});
            walk(jsonList(node, 'days'), [
              ...path,
              ?label as String?,
            ], depth + 1);
          case 'repeat':
            checkKeys(node, {'type', 'label', 'count', 'days'});
            final count = node['count'];
            if (count is! int || count < 1 || count > _maxCycleDays)
              invalid('A repeat count is from 1 to $_maxCycleDays.');
            for (var i = 0; i < count; i++) {
              walk(jsonList(node, 'days'), [
                ...path,
                '${label ?? 'repeat'} ${i + 1}/$count',
              ], depth + 1);
              if (days.length > _maxCycleDays)
                invalid('A cycle has at most $_maxCycleDays days.');
            }
          default:
            invalid('A cycle node is a day, group or repeat.');
        }
        if (days.length > _maxCycleDays)
          invalid('A cycle has at most $_maxCycleDays days.');
      }
    }

    walk(jsonList(j, 'days'), const [], 0);
    return DietCycle._(Map.unmodifiable(j), List.unmodifiable(days));
  }

  final Map<String, Object?> json;
  final List<CycleDay> days;
  String get id => json['id']! as String;
  bool get loop => json['loop']! as bool;
  Set<DayTypeRef> get dayTypes => {for (final d in days) d.dayType};
  Map<String, Object?> toJson() => json;
}

final class DietCycleRevision {
  DietCycleRevision._(this.number, this.cycle);
  factory DietCycleRevision.publish(
    DietCycle cycle, {
    DietCycleRevision? previous,
  }) => DietCycleRevision._((previous?.number ?? 0) + 1, cycle);
  factory DietCycleRevision.fromJson(Object? input) {
    final j = jsonObject(input, 'diet cycle revision');
    checkKeys(j, {'schemaVersion', 'revision', 'cycle'});
    final revision = j['revision'];
    if (j['schemaVersion'] != 1 || revision is! int || revision < 1)
      invalid('Invalid diet cycle revision.');
    return DietCycleRevision._(revision, DietCycle.fromJson(j['cycle']));
  }
  final int number;
  final DietCycle cycle;
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'revision': number,
    'cycle': cycle.toJson(),
  };
}

/// One per-date replacement of the cycle's day type, with its reason.
typedef DietOverride = ({String date, DayTypeRef dayType, String reason});

/// A cycle started on a date (F21): the calendar fixes every later day.
/// Inputs and the resulting targets of every day type it may use are frozen
/// when it starts; overrides replace single dates and never shift the
/// rest. [endDate] (exclusive) ends it.
final class DietRun {
  DietRun._(this.json);
  factory DietRun.fromJson(Object? input) {
    final j = jsonObject(input, 'diet run');
    checkKeys(j, {
      'schemaVersion',
      'id',
      'cycle',
      'startDate',
      'endDate',
      'requestId',
      'inputs',
      'targets',
      'overrides',
      'contentVersion',
    });
    if (j['schemaVersion'] != 1) invalid('Unsupported diet run schemaVersion.');
    identifier(j, 'id');
    identifier(j, 'requestId');
    final cycle = jsonObject(j['cycle'], 'cycle');
    checkKeys(cycle, {'id', 'revision'});
    identifier(cycle, 'id');
    if (cycle['revision'] is! int || (cycle['revision']! as int) < 1)
      invalid('cycle revision is positive.');
    final start = requireDate(j['startDate'], 'startDate');
    if (j['endDate'] != null &&
        requireDate(j['endDate'], 'endDate').compareTo(start) <= 0)
      invalid('endDate is after startDate.');
    jsonObject(j['inputs'], 'inputs');
    jsonObject(j['targets'], 'targets');
    final dates = <String>{};
    for (final o in jsonList(j, 'overrides')) {
      final x = jsonObject(o, 'override');
      checkKeys(x, {'date', 'dayType', 'reason'});
      final date = requireDate(x['date'], 'override date');
      if (date.compareTo(start) < 0)
        invalid('An override is on or after startDate.');
      if (!dates.add(date)) invalid('One override per date.');
      dayTypeRefFromJson(x['dayType'], 'override dayType');
      final reason = x['reason'];
      if (reason is! String || reason.trim().isEmpty || reason.length > 1000)
        invalid('An override reason is nonempty, at most 1000 characters.');
    }
    final version = j['contentVersion'];
    if (version is! int || version < 1) invalid('contentVersion is positive.');
    return DietRun._(Map.unmodifiable(j));
  }

  final Map<String, Object?> json;
  String get id => json['id']! as String;
  String get cycleId => (json['cycle']! as Map)['id']! as String;
  int get cycleRevision => (json['cycle']! as Map)['revision']! as int;
  String get startDate => json['startDate']! as String;
  String? get endDate => json['endDate'] as String?;
  int get contentVersion => json['contentVersion']! as int;
  Map<String, Object?> get inputs => json['inputs']! as Map<String, Object?>;
  Map<String, Object?> get targets => json['targets']! as Map<String, Object?>;
  List<DietOverride> get overrides => [
    for (final o in json['overrides']! as List)
      (
        date: (o as Map)['date']! as String,
        dayType: dayTypeRefFromJson(o['dayType'], 'dayType'),
        reason: o['reason']! as String,
      ),
  ];

  /// The frozen numbers the targets were computed from.
  DietInputs get frozenInputs {
    double? v(String key) {
      final x = inputs[key];
      return x == null ? null : double.parse((x as Map)['value']! as String);
    }

    return (
      maintenanceKcal: v('maintenance'),
      massKg: v('mass'),
      fatFreeMassKg: v('fatFreeMass'),
    );
  }

  bool covers(String date) =>
      date.compareTo(startDate) >= 0 &&
      (endDate == null || date.compareTo(endDate!) < 0);

  Map<String, Object?> toJson() => json;
  DietRun copyWith(Map<String, Object?> changes) =>
      DietRun.fromJson({...json, ...changes});
}

/// Whole days from [from] to [to].
int daysBetween(String from, String to) => DateTime.parse(
  '${to}T00:00:00Z',
).difference(DateTime.parse('${from}T00:00:00Z')).inDays;

String addDays(String date, int days) => DateTime.parse(
  '${date}T00:00:00Z',
).add(Duration(days: days)).toIso8601String().substring(0, 10);

/// What a run prescribes on [date]: the override, or cycle day
/// (days since start) mod length, or null outside the run or after a
/// finite cycle ends.
({
  DayTypeRef dayType,
  String source,
  int? index,
  CycleDay? day,
  String? reason,
})?
dietDayOn(DietRun run, DietCycle cycle, String date) {
  if (!run.covers(date)) return null;
  for (final o in run.overrides) {
    if (o.date == date) {
      final index = daysBetween(run.startDate, date);
      final inCycle = cycle.loop || index < cycle.days.length;
      return (
        dayType: o.dayType,
        source: 'override',
        index: inCycle ? index % cycle.days.length : null,
        day: inCycle ? cycle.days[index % cycle.days.length] : null,
        reason: o.reason,
      );
    }
  }
  final index = daysBetween(run.startDate, date);
  if (!cycle.loop && index >= cycle.days.length) return null;
  final day = cycle.days[index % cycle.days.length];
  return (
    dayType: day.dayType,
    source: 'cycle',
    index: index % cycle.days.length,
    day: day,
    reason: null,
  );
}
