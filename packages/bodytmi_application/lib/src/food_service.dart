import 'package:bodytmi_core/bodytmi_core.dart';

import 'canonical_json.dart';
import 'training_repository.dart';

/// Authoring of base and composite foods. Every change publishes a new
/// immutable revision; a composite pins its component revisions, so nothing
/// already logged or composed changes.
final class FoodService {
  const FoodService(this.repository);
  final TrainingRepository repository;

  Future<FoodLookup> lookup() async {
    final all = await repository.foodRevisions();
    final byKey = {for (final r in all) foodRefKey(r.ref): r};
    return (FoodRef ref) =>
        byKey[foodRefKey(ref)] ??
        (throw BodyTmiException(
          'not_found',
          'Food revision ${foodRefKey(ref)} is not published.',
        ));
  }

  Future<FoodRevision> revision(String id, [int? number]) async {
    final all = await repository.foodRevisions(foodId: id);
    if (all.isEmpty)
      throw BodyTmiException('not_found', 'Food $id is not published.');
    if (number == null) return all.last;
    return all.where((r) => r.number == number).firstOrNull ??
        (throw BodyTmiException(
          'not_found',
          'Food $id has no revision $number.',
        ));
  }

  /// The latest revision of every food.
  Future<List<FoodRevision>> latest() async {
    final latest = <String, FoodRevision>{};
    for (final r in await repository.foodRevisions()) {
      latest[r.food.id] = r;
    }
    return latest.values.toList();
  }

  Future<FoodRevision> publish(Food food, int expectedRevision) =>
      repository.transaction(() async {
        final history = await repository.foodRevisions(foodId: food.id);
        final before = history.lastOrNull;
        if ((before?.number ?? 0) != expectedRevision)
          throw const BodyTmiException('conflict', 'Food revision changed.');
        validateFoodComposition(food, await lookup());
        final next = FoodRevision.publish(food, previous: before);
        await repository.insertFoodRevision(next);
        return next;
      });

  /// Nutrition of an amount of a pinned revision.
  Future<Nutrition> nutrition(FoodRef ref, FoodAmount amount) async {
    final find = await lookup();
    return FoodMath(find).of(find(ref), amount);
  }

  /// Per 100 g or 100 ml of a base food; one whole (and per 100 g when its
  /// mass is known) of a composite.
  Future<Map<String, Object?>> describe(
    FoodRevision revision, {
    List<String>? nutrients,
    bool all = false,
  }) async {
    final math = FoodMath(await lookup());
    final food = revision.food;
    if (!food.isComposite) {
      final per100 = QuantityAmount(
        food.perVolume ? Quantity('100', 'ml') : Quantity('100', 'g'),
      );
      return {
        'per': food.perVolume ? '100ml' : '100g',
        'nutrition': math.of(revision, per100).toJson(ids: nutrients, all: all),
      };
    }
    final whole = math.whole(revision);
    return {
      'whole': whole.toJson(ids: nutrients, all: all),
      if (whole.grams != null)
        'per100g': math
            .of(revision, QuantityAmount(Quantity('100', 'g')))
            .toJson(ids: nutrients, all: all),
      if (food.batch?.portions case final int n)
        'perPortion': whole
            .scaled(Fraction.one / Fraction.integer(n))
            .toJson(ids: nutrients, all: all),
    };
  }

  /// Composites whose latest revision pins an older revision of [foodId]:
  /// candidates for a new version (F15). Nothing follows automatically.
  Future<List<Map<String, Object?>>> dependents(String foodId) async {
    final target = await revision(foodId);
    return [
      for (final r in await latest())
        if (r.food.isComposite)
          for (final c in r.food.components)
            if (c.food.id == foodId && c.food.revision != target.number)
              {
                'food': foodRefToJson(r.ref),
                'name': r.food.name,
                'pins': c.food.revision,
                'latest': target.number,
              },
    ];
  }

  /// Publishes a new revision of composite [id] whose components on
  /// [foodIds] (all outdated ones when null) pin those foods' latest
  /// revisions.
  Future<FoodRevision> follow(
    String id,
    int expectedRevision, {
    List<String>? foodIds,
  }) => repository.transaction(() async {
    final current = await revision(id);
    if (current.number != expectedRevision)
      throw const BodyTmiException('conflict', 'Food revision changed.');
    if (!current.food.isComposite)
      invalid('Only a composite food follows its components.');
    final json = current.food.toJson();
    var changed = false;
    final components = <Object?>[];
    for (final c in current.food.components) {
      final cj = c.toJson();
      if (foodIds == null || foodIds.contains(c.food.id)) {
        final head = await revision(c.food.id);
        if (head.number != c.food.revision) {
          cj['food'] = foodRefToJson(head.ref);
          changed = true;
        }
      }
      components.add(cj);
    }
    if (foodIds != null) {
      for (final f in foodIds) {
        if (!current.food.components.any((c) => c.food.id == f))
          invalid('Composite $id has no component $f.');
      }
    }
    if (!changed) invalid('Composite $id already pins the latest revisions.');
    json['components'] = components;
    final food = Food.fromJson(json);
    validateFoodComposition(food, await lookup());
    final next = FoodRevision.publish(food, previous: current);
    await repository.insertFoodRevision(next);
    return next;
  });

  /// Copies dataset food [number] into the profile as a base food,
  /// publishing a revision only when it differs from the latest one. A
  /// later revision keeps the profile's own portions and density.
  Future<({FoodRevision revision, bool published})> adopt(
    FoodDataset dataset,
    int number, {
    String? foodId,
  }) => repository.transaction(() async {
    var food = dataset.toFood(number, foodId: foodId);
    final history = await repository.foodRevisions(foodId: food.id);
    final before = history.lastOrNull;
    if (before != null) {
      final prior = before.food;
      final source = prior.source;
      if (prior.isComposite ||
          source == null ||
          source.kind != 'dataset' ||
          source.json['dataset'] != dataset.id ||
          source.json['number'] != number)
        throw BodyTmiException(
          'conflict',
          'Food ${food.id} exists and is not dataset ${dataset.id} food $number.',
        );
      final json = food.toJson();
      if (prior.portions.isNotEmpty)
        json['portions'] = [for (final p in prior.portions) p.toJson()];
      if (prior.density != null) json['density'] = prior.density!.toJson();
      food = Food.fromJson(json);
      if (canonicalJson(food.toJson()) == canonicalJson(prior.toJson()))
        return (revision: before, published: false);
    }
    final next = FoodRevision.publish(food, previous: before);
    await repository.insertFoodRevision(next);
    return (revision: next, published: true);
  });
}
