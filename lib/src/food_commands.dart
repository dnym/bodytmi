import 'dart:convert';
import 'dart:io';

import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';

/// Food catalog and diary commands. Commands naming `dataset` read a packaged
/// `bodytmi-food-dataset/1` file (optionally gzip-compressed) read-only.
const foodCommandNames = [
  'food validate',
  'food publish',
  'food show',
  'food list',
  'food nutrition',
  'food dependents',
  'food follow',
  'food dataset-info',
  'food dataset-search',
  'food dataset-show',
  'food adopt',
  'diary add',
  'diary update',
  'diary delete',
  'diary show',
  'diary water',
  'diary repeat',
  'diary mark',
  'diary day',
  'diary report',
  'diary adherence',
  'diary settings',
  'diary set-day-start',
  'energy calibrate',
  'diary reference',
];

const _maxDatasetBytes = 64 * 1024 * 1024;

Future<FoodDataset> _dataset(String path) async {
  final file = File(path);
  if (await file.length() > _maxDatasetBytes)
    invalid('Food dataset exceeds the 64 MiB resource limit.');
  List<int> bytes = await file.readAsBytes();
  if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
    bytes = gzip.decode(bytes);
    if (bytes.length > 4 * _maxDatasetBytes)
      invalid('Food dataset exceeds the resource limit.');
  }
  return FoodDataset.fromJson(jsonDecode(utf8.decode(bytes)));
}

/// `null` is the primary nutrients; `"all"` every known one.
({List<String>? ids, bool all}) _nutrients(Map<String, Object?> request) {
  final value = request['nutrients'];
  if (value == null) return (ids: null, all: false);
  if (value == 'all') return (ids: null, all: true);
  final list = jsonList(request, 'nutrients');
  if (list.isEmpty || list.length > nutrients.length)
    invalid('nutrients is "all" or a nonempty list of nutrient ids.');
  final ids = <String>[];
  for (final id in list) {
    if (id is! String) invalid('nutrients lists nutrient ids.');
    nutrient(id);
    if (ids.contains(id)) invalid('nutrients repeats $id.');
    ids.add(id);
  }
  return (ids: ids, all: false);
}

Future<Map<String, Object?>> executeFood(
  String command,
  Map<String, Object?> request,
) async {
  final pure =
      !(command.startsWith('diary') ||
          command == 'energy calibrate' ||
          const {
            'food publish',
            'food show',
            'food list',
            'food nutrition',
            'food dependents',
            'food follow',
            'food adopt',
          }.contains(command));
  final fields = switch (command) {
    'food validate' => {'food'},
    'food publish' => {'food', 'expectedRevision'},
    'food show' => {'foodId', 'revision', 'nutrients'},
    'food list' => <String>{},
    'food nutrition' => {'food', 'amount', 'nutrients'},
    'food dependents' => {'foodId'},
    'food follow' => {'foodId', 'expectedRevision', 'components'},
    'food dataset-info' => {'dataset'},
    'food dataset-search' => {'dataset', 'query', 'limit'},
    'food dataset-show' => {'dataset', 'number', 'nutrients'},
    'food adopt' => {'dataset', 'number', 'foodId'},
    'diary add' => {'entry'},
    'diary update' => {'id', 'expectedVersion', 'entry'},
    'diary delete' => {'id', 'expectedVersion', 'confirm'},
    'diary show' => {'id'},
    'diary water' => {'id', 'at', 'amount', 'meal'},
    'diary repeat' => {'from', 'to', 'idPrefix', 'meal'},
    'diary mark' => {'date', 'status'},
    'diary day' => {'date', 'nutrients'},
    'diary report' => {'from', 'until', 'nutrients'},
    'diary adherence' => {'from', 'until', 'tolerancePercent'},
    'diary settings' => <String>{},
    'diary set-day-start' => {'dayStart', 'expectedRevision'},
    'diary reference' => {'from', 'until', 'context'},
    'energy calibrate' => {'from', 'until', 'context', 'minimumDays'},
    _ => invalid('Unknown food command.'),
  };
  checkKeys(request, {'schemaVersion', if (!pure) 'database', ...fields});
  int integer(String key, {int min = 1}) {
    final value = request[key];
    if (value is! int || value < min)
      invalid('$key must be an integer >= $min.');
    return value;
  }

  int? optionalInteger(String key, {int min = 1}) =>
      request[key] == null ? null : integer(key, min: min);

  Map<String, Object?> ok(Object? data) => {'schemaVersion': 1, 'data': data};
  final selected = _nutrients(request);

  switch (command) {
    case 'food validate':
      return ok(Food.fromJson(request['food']).toJson());
    case 'food dataset-info':
      return ok(
        (await _dataset(requiredString(request, 'dataset'))).describe(),
      );
    case 'food dataset-search':
      final dataset = await _dataset(requiredString(request, 'dataset'));
      final limit = optionalInteger('limit') ?? 20;
      if (limit > 1000) invalid('limit is at most 1000.');
      return ok({
        'dataset': dataset.id,
        'release': dataset.release,
        'results': [
          for (final r in dataset.search(
            requiredString(request, 'query'),
            limit,
          ))
            {
              'number': r.food.number,
              'name': r.food.name,
              'english': ?r.food.english,
              'match': r.match,
            },
        ],
      });
    case 'food dataset-show':
      final dataset = await _dataset(requiredString(request, 'dataset'));
      final number = integer('number', min: 0);
      final food = dataset.toFood(number);
      final revision = FoodRevision.publish(food);
      return ok({
        'dataset': dataset.id,
        'release': dataset.release,
        'number': number,
        'food': food.toJson(),
        'type': dataset.food(number).type,
        'version': dataset.food(number).version,
        'per100g': FoodMath((_) => invalid('A dataset food has no components.'))
            .of(revision, QuantityAmount(Quantity('100', 'g')))
            .toJson(ids: selected.ids, all: selected.all),
      });
  }

  final store = await TrainingStore.open(requiredString(request, 'database'));
  try {
    final foods = FoodService(store);
    final diary = DiaryService(store);
    switch (command) {
      case 'food publish':
        return ok(
          (await foods.publish(
            Food.fromJson(request['food']),
            integer('expectedRevision', min: 0),
          )).toJson(),
        );
      case 'food show':
        final revision = await foods.revision(
          identifier(request, 'foodId'),
          optionalInteger('revision'),
        );
        return ok({
          ...revision.toJson(),
          ...await foods.describe(
            revision,
            nutrients: selected.ids,
            all: selected.all,
          ),
        });
      case 'food list':
        return ok([
          for (final r in await foods.latest())
            {
              'id': r.food.id,
              'revision': r.number,
              'name': r.food.name,
              'kind': r.food.isComposite ? 'composite' : 'base',
              if (r.food.source != null) 'source': r.food.source!.toJson(),
            },
        ]);
      case 'food nutrition':
        final ref = jsonObject(request['food'], 'food');
        checkKeys(ref, {'id', 'revision'});
        final revision = await foods.revision(
          identifier(ref, 'id'),
          ref['revision'] == null
              ? null
              : foodRefFromJson(ref, 'food').revision,
        );
        final amount = FoodAmount.fromJson(request['amount'], 'amount');
        return ok({
          'food': foodRefToJson(revision.ref),
          'amount': amount.toJson(),
          ...(await foods.nutrition(
            revision.ref,
            amount,
          )).toJson(ids: selected.ids, all: selected.all),
        });
      case 'food dependents':
        return ok(await foods.dependents(identifier(request, 'foodId')));
      case 'food follow':
        List<String>? ids;
        if (request['components'] != null) {
          ids = [
            for (final c in jsonList(request, 'components'))
              identifier({'component': c}, 'component'),
          ];
          if (ids.isEmpty) invalid('components names at least one food.');
        }
        return ok(
          (await foods.follow(
            identifier(request, 'foodId'),
            integer('expectedRevision'),
            foodIds: ids,
          )).toJson(),
        );
      case 'food adopt':
        final dataset = await _dataset(requiredString(request, 'dataset'));
        final result = await foods.adopt(
          dataset,
          integer('number', min: 0),
          foodId: request['foodId'] == null
              ? null
              : identifier(request, 'foodId'),
        );
        return ok({'published': result.published, ...result.revision.toJson()});
      case 'diary add':
        return ok(
          (await diary.add(jsonObject(request['entry'], 'entry'))).toJson(),
        );
      case 'diary update':
        return ok(
          (await diary.update(
            identifier(request, 'id'),
            integer('expectedVersion'),
            jsonObject(request['entry'], 'entry'),
          )).toJson(),
        );
      case 'diary delete':
        if (request['confirm'] != true)
          invalid('Deleting a diary entry requires confirm:true.');
        await diary.delete(
          identifier(request, 'id'),
          integer('expectedVersion'),
        );
        return ok({'deleted': identifier(request, 'id')});
      case 'diary show':
        return ok((await diary.entry(identifier(request, 'id'))).toJson());
      case 'diary water':
        return ok(
          (await diary.water(
            id: identifier(request, 'id'),
            at: requiredString(request, 'at'),
            amount: Quantity.fromJson(request['amount']),
            meal: request['meal'] as String?,
          )).toJson(),
        );
      case 'diary repeat':
        return ok([
          for (final e in await diary.repeat(
            fromDate: checkDate(request['from'], 'from'),
            toDate: checkDate(request['to'], 'to'),
            idPrefix: identifier(request, 'idPrefix'),
            meal: request['meal'] as String?,
          ))
            e.toJson(),
        ]);
      case 'diary mark':
        return ok(
          (await diary.setMark(
            checkDate(request['date'], 'date'),
            requiredString(request, 'status'),
          )).toJson(),
        );
      case 'diary day':
        return ok(
          await diary.day(
            checkDate(request['date'], 'date'),
            nutrients: selected.ids,
            all: selected.all,
          ),
        );
      case 'diary report':
        if (selected.all) invalid('A report takes a list of nutrients.');
        return ok(
          await diary.report(
            checkDate(request['from'], 'from'),
            checkDate(request['until'], 'until'),
            nutrients: selected.ids,
          ),
        );
      case 'diary adherence':
        final tolerance = request['tolerancePercent'];
        if (tolerance != null && tolerance is! String)
          invalid('tolerancePercent is a decimal string.');
        return ok(
          await diary.adherenceReport(
            checkDate(request['from'], 'from'),
            checkDate(request['until'], 'until'),
            tolerancePercent: tolerance == null
                ? null
                : Decimal.parse(tolerance as String),
          ),
        );
      case 'diary reference':
        return ok(
          await ReferenceService(store).assess(
            checkDate(request['from'], 'from'),
            checkDate(request['until'], 'until'),
            context: request['context'] == null
                ? 'health'
                : identifier(request, 'context'),
          ),
        );
      case 'energy calibrate':
        return ok(
          await EnergyCalibrationService(store).calibrate(
            checkDate(request['from'], 'from'),
            checkDate(request['until'], 'until'),
            context: request['context'] == null
                ? 'health'
                : identifier(request, 'context'),
            minimumDays: optionalInteger('minimumDays', min: 3) ?? 14,
          ),
        );
      case 'diary settings':
        final s = await diary.settings();
        return ok({
          'dayStart': formatDayStart(s?.dayStart ?? defaultDiaryDayStart),
          'revision': s?.number ?? 0,
        });
      case 'diary set-day-start':
        return ok(
          (await diary.setDayStart(
            parseDayStart(request['dayStart']),
            integer('expectedRevision', min: 0),
          )).toJson(),
        );
    }
    invalid('Unknown food command.');
  } finally {
    await store.close();
  }
}
