import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
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
  'food lookup',
  'food search-online',
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
  'food import-validate',
  'food import-preview',
  'food import-apply',
  'diary import-validate',
  'diary import-preview',
  'diary import-apply',
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

String _endpoint(Map<String, Object?> request, String fallback) {
  final value = request['endpoint'] ?? fallback;
  if (value is! String || !RegExp(r'^https?://[^\s?#]+$').hasMatch(value))
    invalid('endpoint is an http(s) base URL.');
  return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
}

/// Online lookups send only the barcode or search text, with a generic
/// client name and no profile data.
Future<String> _getText(Uri uri, {bool allowNotFound = false}) async {
  final client = HttpClient()
    ..userAgent = 'BodyTMI/0.1 (open source health app)'
    ..connectionTimeout = const Duration(seconds: 20);
  try {
    final request = await client.getUrl(uri);
    request.headers.set('accept', 'application/json');
    final response = await request.close().timeout(const Duration(seconds: 30));
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(const Duration(seconds: 30))) {
      if (bytes.length + chunk.length > 8 * 1024 * 1024)
        invalid('The online response exceeds 8 MiB.');
      bytes.add(chunk);
    }
    final text = utf8.decode(bytes.takeBytes(), allowMalformed: true);
    if (response.statusCode == 404 && allowNotFound) return text;
    if (response.statusCode != 200)
      throw BodyTmiException(
        'io',
        'Open Food Facts answered HTTP ${response.statusCode}.',
      );
    return text;
  } on SocketException catch (e) {
    throw BodyTmiException(
      'io',
      'Open Food Facts is unreachable: ${e.message}',
    );
  } on TimeoutException {
    throw const BodyTmiException('io', 'Open Food Facts did not answer.');
  } finally {
    client.close(force: true);
  }
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
      command.endsWith('import-validate') ||
      !(command.startsWith('diary') ||
          command.endsWith('import-preview') ||
          command.endsWith('import-apply') ||
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
    'food lookup' => {'barcode', 'foodId', 'endpoint'},
    'food search-online' => {'query', 'limit', 'endpoint'},
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
    'food import-validate' ||
    'food import-preview' ||
    'diary import-validate' ||
    'diary import-preview' => {'document'},
    'food import-apply' ||
    'diary import-apply' => {'document', 'onChanged', 'confirm'},
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
    case 'food import-validate':
      final doc = FoodImportDocument.fromJson(request['document']);
      return ok({
        'format': foodImportFormat,
        'namespace': doc.namespace,
        'foods': doc.foods.length,
      });
    case 'diary import-validate':
      final doc = DiaryImportDocument.fromJson(request['document']);
      return ok({
        'format': diaryImportFormat,
        'namespace': doc.namespace,
        'entries': doc.entries.length,
        'days': doc.days.length,
      });
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
    case 'food lookup':
      final barcode = requiredString(request, 'barcode');
      if (!RegExp(r'^\d{4,20}$').hasMatch(barcode))
        invalid('barcode is 4–20 digits.');
      final base = _endpoint(request, 'https://world.openfoodfacts.org');
      final body = await _getText(
        Uri.parse(
          '$base/api/v2/product/$barcode.json?fields=code,product_name,'
          'product_name_sv,brands,quantity,nutrition_data_per,nutriments',
        ),
        allowNotFound: true,
      );
      final json = jsonObject(jsonDecode(jsonNumbersAsText(body)), 'response');
      final product = json['product'];
      if (product is! Map<String, Object?>)
        throw BodyTmiException(
          'not_found',
          'Open Food Facts has no product $barcode.',
        );
      final result = foodFromOpenFoodFacts(
        product,
        foodId: request['foodId'] == null
            ? null
            : identifier(request, 'foodId'),
      );
      return ok({
        'food': result.food.toJson(),
        'skipped': result.skipped,
        'licence': openFoodFactsLicence,
        'saved': false,
        'next': 'Review the food, then save it with food publish.',
      });
    case 'food search-online':
      final query = requiredString(request, 'query');
      if (query.length > 200) invalid('query is at most 200 characters.');
      final limit = optionalInteger('limit') ?? 10;
      if (limit > 50) invalid('limit is at most 50.');
      final base = _endpoint(request, 'https://search.openfoodfacts.org');
      final body = await _getText(
        Uri.parse(base).replace(
          path: '${Uri.parse(base).path}/search',
          queryParameters: {
            'q': query,
            'page_size': '$limit',
            'fields': 'code,product_name,brands',
          },
        ),
      );
      final json = jsonObject(jsonDecode(body), 'response');
      return ok({
        'licence': openFoodFactsLicence,
        'results': [
          for (final hit in (json['hits'] as List?) ?? const [])
            if (hit is Map<String, Object?> && hit['code'] is String)
              {
                'barcode': hit['code'],
                'name': ?hit['product_name'],
                'brands': ?switch (hit['brands']) {
                  final List<Object?> b when b.isNotEmpty => b.join(', '),
                  final String b when b.isNotEmpty => b,
                  _ => null,
                },
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
    String onChanged() {
      final v = request['onChanged'] ?? 'reject';
      if (v is! String) invalid('onChanged must be reject or update.');
      return v;
    }

    switch (command) {
      case 'food import-preview':
        return ok(
          await FoodImportService(
            store,
          ).preview(FoodImportDocument.fromJson(request['document'])),
        );
      case 'food import-apply':
        return ok(
          await FoodImportService(store).apply(
            FoodImportDocument.fromJson(request['document']),
            onChanged: onChanged(),
            confirm: request['confirm'] == true,
          ),
        );
      case 'diary import-preview':
        return ok(
          await DiaryImportService(
            store,
          ).preview(DiaryImportDocument.fromJson(request['document'])),
        );
      case 'diary import-apply':
        return ok(
          await DiaryImportService(store).apply(
            DiaryImportDocument.fromJson(request['document']),
            onChanged: onChanged(),
            confirm: request['confirm'] == true,
          ),
        );
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
