import 'catalog_labels.dart';
import 'errors.dart';
import 'fraction.dart';
import 'nutrient.dart';
import 'quantity.dart';

/// A pinned food revision.
typedef FoodRef = ({String id, int revision});

FoodRef foodRefFromJson(Object? input, String label) {
  final j = jsonObject(input, label);
  checkKeys(j, {'id', 'revision'});
  final revision = j['revision'];
  if (revision is! int || revision < 1)
    invalid('$label revision must be a positive integer.');
  return (id: identifier(j, 'id'), revision: revision);
}

Map<String, Object?> foodRefToJson(FoodRef ref) => {
  'id': ref.id,
  'revision': ref.revision,
};

String foodRefKey(FoodRef ref) => '${ref.id}/${ref.revision}';

/// Portion identifiers with a fixed meaning on composite foods: `whole` is
/// one of the composite; `portion` is one of a batch's declared portions.
const reservedPortions = {'whole', 'portion'};

/// How much of a food: a mass or volume, or a count of a named portion.
sealed class FoodAmount {
  const FoodAmount();
  factory FoodAmount.fromJson(Object? input, String label) {
    final j = jsonObject(input, label);
    if (j.containsKey('portion')) {
      checkKeys(j, {'portion', 'count'});
      final count = j['count'];
      if (count is! String) invalid('$label count must be a decimal string.');
      final parsed = Decimal.parse(count);
      if (parsed.compareTo(Decimal.zero) <= 0)
        invalid('$label count must be positive.');
      return PortionAmount(identifier(j, 'portion'), parsed);
    }
    final q = Quantity.fromJson(j);
    if (q.dimension != Dimension.mass && q.dimension != Dimension.volume)
      invalid('$label must be a mass, a volume or a portion.');
    if (q.value.compareTo(Decimal.zero) <= 0)
      invalid('$label must be positive.');
    return QuantityAmount(q);
  }
  Map<String, Object?> toJson();
}

final class QuantityAmount extends FoodAmount {
  const QuantityAmount(this.quantity);
  final Quantity quantity;
  @override
  Map<String, Object?> toJson() => quantity.toJson();
}

final class PortionAmount extends FoodAmount {
  const PortionAmount(this.portion, this.count);
  final String portion;
  final Decimal count;
  @override
  Map<String, Object?> toJson() => {
    'portion': portion,
    'count': count.toString(),
  };
}

/// A named portion with a real mass or volume ("1 slice" = 30 g).
final class FoodPortion {
  FoodPortion._(this.id, this.name, this.amount);
  factory FoodPortion.fromJson(Object? input) {
    final j = jsonObject(input, 'portion');
    checkKeys(j, {'id', 'name', 'amount'});
    final id = identifier(j, 'id');
    if (reservedPortions.contains(id))
      invalid('Portion id $id is reserved for composite foods.');
    final name = _optionalText(j, 'name', 200);
    final amount = FoodAmount.fromJson(j['amount'], 'portion $id amount');
    if (amount is! QuantityAmount)
      invalid('Portion $id needs a real mass or volume.');
    return FoodPortion._(id, name, amount.quantity);
  }
  final String id;
  final String? name;
  final Quantity amount;
  Map<String, Object?> toJson() => {
    'id': id,
    if (name != null) 'name': name,
    'amount': amount.toJson(),
  };
}

/// Declared density: [mass] of the food occupies [volume].
final class Density {
  Density._(this.mass, this.volume);
  factory Density.fromJson(Object? input) {
    final j = jsonObject(input, 'density');
    checkKeys(j, {'mass', 'volume'});
    final mass = Quantity.fromJson(j['mass']);
    final volume = Quantity.fromJson(j['volume']);
    if (mass.dimension != Dimension.mass ||
        volume.dimension != Dimension.volume ||
        mass.value.compareTo(Decimal.zero) <= 0 ||
        volume.value.compareTo(Decimal.zero) <= 0)
      invalid('A density is a positive mass per positive volume.');
    return Density._(mass, volume);
  }
  final Quantity mass;
  final Quantity volume;

  /// Grams per millilitre.
  Fraction get gramsPerMl =>
      _grams(mass) / (Fraction.decimal(volume.value) * Fraction.integer(1000));
  Map<String, Object?> toJson() => {
    'mass': mass.toJson(),
    'volume': volume.toJson(),
  };
}

/// A cooked batch: nutrients per gram follow from [finalMass]; [portions]
/// optionally splits the batch into equal portions.
final class Batch {
  Batch._(this.finalMass, this.portions);
  factory Batch.fromJson(Object? input) {
    final j = jsonObject(input, 'batch');
    checkKeys(j, {'finalMass', 'portions'});
    final mass = Quantity.fromJson(j['finalMass']);
    if (mass.dimension != Dimension.mass ||
        mass.value.compareTo(Decimal.zero) <= 0)
      invalid('A batch final mass must be a positive mass.');
    final portions = j['portions'];
    if (portions != null &&
        (portions is! int || portions < 1 || portions > 1000))
      invalid('Batch portions must be an integer from 1 to 1000.');
    return Batch._(mass, portions as int?);
  }
  final Quantity finalMass;
  final int? portions;
  Map<String, Object?> toJson() => {
    'finalMass': finalMass.toJson(),
    if (portions != null) 'portions': portions,
  };
}

final class FoodComponent {
  FoodComponent._(this.food, this.amount);
  factory FoodComponent.fromJson(Object? input) {
    final j = jsonObject(input, 'component');
    checkKeys(j, {'food', 'amount'});
    return FoodComponent._(
      foodRefFromJson(j['food'], 'component food'),
      FoodAmount.fromJson(j['amount'], 'component amount'),
    );
  }
  final FoodRef food;
  final FoodAmount amount;
  Map<String, Object?> toJson() => {
    'food': foodRefToJson(food),
    'amount': amount.toJson(),
  };
}

/// Where a food's numbers came from. `dataset` names a packaged database
/// food; `label` a nutrition label; `lookup` an online product lookup.
final class FoodSource {
  FoodSource._(this.json);
  factory FoodSource.fromJson(Object? input) {
    final j = jsonObject(input, 'source');
    checkKeys(j, {'kind', 'dataset', 'release', 'number', 'url', 'notes'});
    final kind = j['kind'];
    if (kind is! String ||
        !const {'label', 'dataset', 'lookup', 'other'}.contains(kind))
      invalid('Source kind is label, dataset, lookup or other.');
    if (kind == 'dataset') {
      identifier(j, 'dataset');
      requiredString(j, 'release');
      final n = j['number'];
      if (n is! int || n < 0) invalid('A dataset source names a food number.');
    } else if (j.containsKey('dataset') ||
        j.containsKey('release') ||
        j.containsKey('number')) {
      invalid('Only a dataset source has dataset, release and number.');
    }
    _optionalText(j, 'url', 2000);
    _optionalText(j, 'notes', 4000);
    return FoodSource._(Map.unmodifiable(j));
  }
  final Map<String, Object?> json;
  String get kind => json['kind']! as String;
  Map<String, Object?> toJson() => json;
}

/// A base food (nutrients per 100 g or per 100 ml, as printed) or a composite
/// of other pinned food revisions.
final class Food {
  Food._({
    required this.id,
    required this.name,
    required this.labels,
    required this.notes,
    required this.source,
    required this.perVolume,
    required this.nutrients,
    required this.valueTypes,
    required this.density,
    required this.portions,
    required this.components,
    required this.batch,
  });

  factory Food.fromJson(Object? input) {
    final j = jsonObject(input, 'food');
    final kind = j['kind'];
    const common = {
      'id',
      'name',
      'labels',
      'notes',
      'source',
      'kind',
      'portions',
    };
    final id = identifier(j, 'id');
    final name = _optionalText(j, 'name', 200) ?? invalid('A food has a name.');
    final labels = j.containsKey('labels')
        ? CatalogLabels.fromJson(j['labels'])
        : CatalogLabels.empty;
    final notes = _optionalText(j, 'notes', 4000);
    final source = j.containsKey('source')
        ? FoodSource.fromJson(j['source'])
        : null;
    final portions = <FoodPortion>[];
    if (j.containsKey('portions')) {
      final raw = jsonList(j, 'portions');
      if (raw.isEmpty || raw.length > 64)
        invalid('A food declares 1–64 portions.');
      final seen = <String>{};
      for (final p in raw) {
        final portion = FoodPortion.fromJson(p);
        if (!seen.add(portion.id)) invalid('Duplicate portion ${portion.id}.');
        portions.add(portion);
      }
    }
    if (kind == 'base') {
      checkKeys(j, {...common, 'basis', 'nutrients', 'valueTypes', 'density'});
      final basis = j['basis'];
      if (basis != '100g' && basis != '100ml')
        invalid('A base food basis is 100g or 100ml.');
      final values = <String, Quantity>{};
      final nj = jsonObject(j['nutrients'], 'nutrients');
      for (final e in nj.entries) {
        final def = nutrient(e.key);
        final q = Quantity.fromJson(e.value);
        if (q.dimension != def.unit.dimension)
          invalid('Nutrient ${e.key} must be ${def.unit.dimension.name}.');
        values[e.key] = q;
      }
      final types = <String, String>{};
      if (j.containsKey('valueTypes')) {
        final tj = jsonObject(j['valueTypes'], 'valueTypes');
        for (final e in tj.entries) {
          if (!values.containsKey(e.key))
            invalid('valueTypes names a nutrient without a value: ${e.key}.');
          final v = e.value;
          if (v is! String || v.isEmpty || v.length > 16)
            invalid('A value type is a short code.');
          types[e.key] = v;
        }
      }
      final density = j.containsKey('density')
          ? Density.fromJson(j['density'])
          : null;
      final food = Food._(
        id: id,
        name: name,
        labels: labels,
        notes: notes,
        source: source,
        perVolume: basis == '100ml',
        nutrients: Map.unmodifiable(values),
        valueTypes: Map.unmodifiable(types),
        density: density,
        portions: List.unmodifiable(portions),
        components: const [],
        batch: null,
      );
      for (final p in portions) {
        food._basisUnits(QuantityAmount(p.amount));
      }
      return food;
    }
    if (kind == 'composite') {
      checkKeys(j, {...common, 'components', 'batch'});
      final raw = jsonList(j, 'components');
      if (raw.isEmpty || raw.length > 200)
        invalid('A composite food has 1–200 components.');
      final batch = j.containsKey('batch') ? Batch.fromJson(j['batch']) : null;
      for (final p in portions) {
        if (p.amount.dimension != Dimension.mass)
          invalid('A composite portion is a mass.');
      }
      return Food._(
        id: id,
        name: name,
        labels: labels,
        notes: notes,
        source: source,
        perVolume: false,
        nutrients: const {},
        valueTypes: const {},
        density: null,
        portions: List.unmodifiable(portions),
        components: List.unmodifiable(raw.map(FoodComponent.fromJson)),
        batch: batch,
      );
    }
    invalid('A food kind is base or composite.');
  }

  final String id;
  final String name;
  final CatalogLabels labels;
  final String? notes;
  final FoodSource? source;
  final bool perVolume;
  final Map<String, Quantity> nutrients;
  final Map<String, String> valueTypes;
  final Density? density;
  final List<FoodPortion> portions;
  final List<FoodComponent> components;
  final Batch? batch;

  bool get isComposite => components.isNotEmpty;

  FoodPortion? portion(String id) {
    for (final p in portions) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Grams (per-100 g foods) or millilitres (per-100 ml foods) in [amount].
  Fraction _basisUnits(FoodAmount amount) {
    switch (amount) {
      case PortionAmount(:final portion, :final count):
        final p =
            this.portion(portion) ??
            invalid('Food $id has no portion $portion.');
        return _basisUnits(QuantityAmount(p.amount)) * Fraction.decimal(count);
      case QuantityAmount(:final quantity):
        final isMass = quantity.dimension == Dimension.mass;
        final units = isMass ? _grams(quantity) : _ml(quantity);
        if (isMass != perVolume) return units;
        final d =
            density ??
            invalid(
              'Food $id is per 100 ${perVolume ? 'ml' : 'g'}; logging it by '
              '${isMass ? 'mass' : 'volume'} needs a declared density.',
            );
        return isMass ? units / d.gramsPerMl : units * d.gramsPerMl;
    }
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    if (!labels.isEmpty) 'labels': labels.toJson(),
    if (notes != null) 'notes': notes,
    if (source != null) 'source': source!.toJson(),
    if (isComposite) ...{
      'kind': 'composite',
      'components': [for (final c in components) c.toJson()],
      if (batch != null) 'batch': batch!.toJson(),
    } else ...{
      'kind': 'base',
      'basis': perVolume ? '100ml' : '100g',
      'nutrients': {
        for (final id
            in (nutrients.keys.toList()
              ..sort((a, b) => nutrientOrder[a]!.compareTo(nutrientOrder[b]!))))
          id: nutrients[id]!.toJson(),
      },
      if (valueTypes.isNotEmpty) 'valueTypes': valueTypes,
      if (density != null) 'density': density!.toJson(),
    },
    if (portions.isNotEmpty) 'portions': [for (final p in portions) p.toJson()],
  };
}

/// An immutable numbered revision of a food.
final class FoodRevision {
  FoodRevision._(this.number, this.food);
  factory FoodRevision.publish(Food food, {FoodRevision? previous}) {
    if (previous != null && previous.food.id != food.id)
      invalid('A revision continues the same food.');
    return FoodRevision._((previous?.number ?? 0) + 1, food);
  }
  factory FoodRevision.fromJson(Object? input) {
    final j = jsonObject(input, 'food revision');
    checkKeys(j, {'schemaVersion', 'revision', 'food'});
    final revision = j['revision'];
    if (j['schemaVersion'] != 1 || revision is! int || revision < 1)
      invalid('Invalid food revision.');
    return FoodRevision._(revision, Food.fromJson(j['food']));
  }
  final int number;
  final Food food;
  FoodRef get ref => (id: food.id, revision: number);
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'revision': number,
    'food': food.toJson(),
  };
}

/// Nutrients of an amount of food. Each base food (or quick entry) reached
/// is one *item*; a nutrient's [known] count says how many items declared
/// it. A nutrient no item declares is absent, never zero.
final class Nutrition {
  Nutrition(this.items, this.values, this.known, this.grams);
  static final empty = Nutrition(0, const {}, const {}, Fraction.zero);

  final int items;

  /// Canonical quantity values (kg for masses, kJ for energy).
  final Map<String, Fraction> values;
  final Map<String, int> known;

  /// Mass eaten, when every part has a known mass.
  final Fraction? grams;

  Nutrition operator +(Nutrition o) {
    final values = {...this.values};
    final known = {...this.known};
    for (final e in o.values.entries) {
      values[e.key] = (values[e.key] ?? Fraction.zero) + e.value;
      known[e.key] = (known[e.key] ?? 0) + o.known[e.key]!;
    }
    return Nutrition(
      items + o.items,
      values,
      known,
      grams == null || o.grams == null ? null : grams! + o.grams!,
    );
  }

  Nutrition scaled(Fraction factor) => Nutrition(
    items,
    {for (final e in values.entries) e.key: e.value * factor},
    known,
    grams == null ? null : grams! * factor,
  );

  /// Value in the nutrient's display unit.
  Fraction? display(String id) {
    final v = values[id];
    if (v == null) return null;
    return v / Fraction.parse(nutrient(id).unit.factor);
  }

  /// `known` (every item), `partial` or `unavailable`.
  String status(String id) {
    final k = known[id] ?? 0;
    if (k == 0) return 'unavailable';
    return k == items ? 'known' : 'partial';
  }

  /// [ids] null means the primary nutrients; `all` every nutrient known in
  /// at least one item, in vocabulary order.
  Map<String, Object?> toJson({List<String>? ids, bool all = false}) {
    final selected = all
        ? (values.keys.toList()
            ..sort((a, b) => nutrientOrder[a]!.compareTo(nutrientOrder[b]!)))
        : (ids ?? primaryNutrients);
    return {
      'items': items,
      'mass': grams == null
          ? null
          : {'value': grams!.round().toString(), 'unit': 'g'},
      'nutrients': {for (final id in selected) id: nutrientJson(id)},
    };
  }

  Map<String, Object?> nutrientJson(String id) {
    final def = nutrient(id);
    final status = this.status(id);
    return {
      'status': status,
      'value': status == 'unavailable' ? null : display(id)!.round().toString(),
      'unit': def.unit.name,
      'knownItems': known[id] ?? 0,
    };
  }
}

typedef FoodLookup = FoodRevision Function(FoodRef ref);

/// Computes nutrition through pinned revisions, memoizing composites.
final class FoodMath {
  FoodMath(this.lookup);
  final FoodLookup lookup;
  final _wholes = <String, Nutrition>{};
  final _active = <String>{};

  Nutrition of(FoodRevision revision, FoodAmount amount) {
    final food = revision.food;
    if (!food.isComposite) {
      final units = food._basisUnits(amount);
      final factor = units / Fraction.integer(100);
      Fraction? grams;
      if (!food.perVolume) {
        grams = units;
      } else if (food.density != null) {
        grams = units * food.density!.gramsPerMl;
      }
      return Nutrition(
        1,
        {
          for (final e in food.nutrients.entries)
            e.key: Fraction.decimal(e.value.value) * factor,
        },
        {for (final k in food.nutrients.keys) k: 1},
        grams,
      );
    }
    final whole = this.whole(revision);
    return whole.scaled(_compositeFactor(revision, whole, amount));
  }

  /// Nutrition of one whole composite, its mass the batch's final mass when
  /// declared.
  Nutrition whole(FoodRevision revision) {
    final key = foodRefKey(revision.ref);
    final cached = _wholes[key];
    if (cached != null) return cached;
    if (!_active.add(key)) invalid('Food ${revision.food.id} contains itself.');
    try {
      var sum = Nutrition.empty;
      for (final c in revision.food.components) {
        sum += of(lookup(c.food), c.amount);
      }
      final batch = revision.food.batch;
      final result = batch == null
          ? sum
          : Nutrition(
              sum.items,
              sum.values,
              sum.known,
              _grams(batch.finalMass),
            );
      _wholes[key] = result;
      return result;
    } finally {
      _active.remove(key);
    }
  }

  Fraction _compositeFactor(
    FoodRevision revision,
    Nutrition whole,
    FoodAmount amount,
  ) {
    final food = revision.food;
    Fraction byMass(Fraction grams) {
      final total =
          whole.grams ??
          invalid(
            'Composite ${food.id} has no known total mass; log it by whole '
            'or declare a batch final mass.',
          );
      return grams / total;
    }

    switch (amount) {
      case PortionAmount(portion: 'whole', :final count):
        return Fraction.decimal(count);
      case PortionAmount(portion: 'portion', :final count):
        final n =
            food.batch?.portions ??
            invalid('Composite ${food.id} declares no batch portions.');
        return Fraction.decimal(count) / Fraction.integer(n);
      case PortionAmount(:final portion, :final count):
        final p =
            food.portion(portion) ??
            invalid('Food ${food.id} has no portion $portion.');
        return byMass(_grams(p.amount)) * Fraction.decimal(count);
      case QuantityAmount(:final quantity):
        if (quantity.dimension != Dimension.mass)
          invalid('Composite ${food.id} is logged by mass, whole or portion.');
        return byMass(_grams(quantity));
    }
  }
}

/// Food IDs reachable from [food]'s components, through pinned revisions.
Set<String> containedFoodIds(Food food, FoodLookup lookup) {
  final seen = <String>{};
  final ids = <String>{};
  void walk(Food f) {
    for (final c in f.components) {
      ids.add(c.food.id);
      if (seen.add(foodRefKey(c.food))) walk(lookup(c.food).food);
    }
  }

  walk(food);
  return ids;
}

/// Checks a food against the revisions it pins: references exist, no food
/// contains itself, amounts are loggable and named portions have a mass.
void validateFoodComposition(Food food, FoodLookup lookup) {
  if (!food.isComposite) return;
  if (containedFoodIds(food, lookup).contains(food.id))
    invalid('Food ${food.id} would contain itself through its components.');
  final math = FoodMath(lookup);
  final revision = FoodRevision._(1, food);
  final whole = math.whole(revision);
  for (final p in food.portions) {
    math.of(revision, PortionAmount(p.id, Decimal.parse('1')));
  }
  if (food.portions.isNotEmpty && whole.grams == null)
    invalid('Composite ${food.id} portions need a known total mass.');
}

/// Every revision is contiguous per food and every composite's pins resolve
/// to earlier-published revisions without cycles.
void validateFoodRevisions(List<FoodRevision> revisions) {
  final byKey = <String, FoodRevision>{};
  final numbers = <String, List<int>>{};
  for (final r in revisions) {
    if (byKey.putIfAbsent(foodRefKey(r.ref), () => r) != r)
      invalid('Duplicate food revision ${foodRefKey(r.ref)}.');
    numbers.putIfAbsent(r.food.id, () => []).add(r.number);
  }
  for (final e in numbers.entries) {
    final sorted = [...e.value]..sort();
    for (var i = 0; i < sorted.length; i++) {
      if (sorted[i] != i + 1) invalid('Food ${e.key} revisions have a gap.');
    }
  }
  FoodRevision lookup(FoodRef ref) =>
      byKey[foodRefKey(ref)] ??
      invalid('Food revision ${foodRefKey(ref)} is not published.');
  for (final r in revisions) {
    validateFoodComposition(r.food, lookup);
  }
}

Fraction _grams(Quantity q) =>
    Fraction.decimal(q.value) * Fraction.integer(1000);
Fraction _ml(Quantity q) => Fraction.decimal(q.value) * Fraction.integer(1000);

String? _optionalText(Map<String, Object?> j, String key, int max) {
  final v = j[key];
  if (v == null) return null;
  if (v is! String || v.trim().isEmpty || v.length > max)
    invalid('$key must be nonempty text of at most $max characters.');
  return v;
}
