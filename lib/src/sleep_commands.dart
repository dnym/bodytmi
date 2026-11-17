import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';

/// Sleep diary, daylight, schedule and statistics commands.
const sleepCommandNames = [
  'sleep record',
  'sleep update',
  'sleep delete',
  'sleep show',
  'sleep list',
  'sleep mark',
  'sleep schedule',
  'sleep schedules',
  'sleep sun',
  'sleep stats',
  'sleep plan-view',
  'sleep import-validate',
  'sleep import-preview',
  'sleep import-apply',
  'sun times',
];

Future<Map<String, Object?>> executeSleep(
  String command,
  Map<String, Object?> request,
) async {
  const pure = {'sleep import-validate', 'sun times'};
  final fields = switch (command) {
    'sleep record' => {'sleep'},
    'sleep update' => {'id', 'expectedVersion', 'sleep'},
    'sleep delete' => {'id', 'expectedVersion', 'confirm'},
    'sleep show' => {'id'},
    'sleep list' => {'from', 'until'},
    'sleep mark' => {'date', 'status'},
    'sleep schedule' => {'schedule', 'expectedRevision'},
    'sleep schedules' => <String>{},
    'sleep sun' => {'from', 'days'},
    'sleep stats' => {'from', 'until'},
    'sleep plan-view' => {'from', 'until'},
    'sleep import-validate' => {'document'},
    'sleep import-preview' => {'document'},
    'sleep import-apply' => {'document', 'onChanged', 'confirm'},
    'sun times' => {'location', 'from', 'days'},
    _ => invalid('Unknown sleep command.'),
  };
  checkKeys(request, {
    'schemaVersion',
    if (!pure.contains(command)) 'database',
    ...fields,
  });
  int integer(String key, {int min = 1}) {
    final value = request[key];
    if (value is! int || value < min)
      invalid('$key must be an integer >= $min.');
    return value;
  }

  int days() => request['days'] == null ? 1 : integer('days');
  Map<String, Object?> ok(Object? data) => {'schemaVersion': 1, 'data': data};

  switch (command) {
    case 'sleep import-validate':
      final doc = SleepImportDocument.fromJson(request['document']);
      return ok({
        'format': sleepImportFormat,
        'namespace': doc.namespace,
        'sleeps': doc.sleeps.length,
      });
    case 'sun times':
      final loc = ProfileLocation.fromJson(request['location']);
      final from = checkDate(request['from'], 'from');
      final n = days();
      if (n > 366) invalid('days is from 1 to 366.');
      final zone = timeZone(loc.timeZone);
      return ok({
        'policy': solarPolicy,
        'location': loc.toJson(),
        'days': [
          for (var i = 0; i < n; i++)
            sunDay(addDays(from, i), loc.latitude, loc.longitude, zone),
        ],
      });
  }

  final store = await TrainingStore.open(requiredString(request, 'database'));
  try {
    final sleep = SleepService(store);
    switch (command) {
      case 'sleep record':
        return ok(
          (await sleep.add(jsonObject(request['sleep'], 'sleep'))).describe(),
        );
      case 'sleep update':
        return ok(
          (await sleep.update(
            identifier(request, 'id'),
            integer('expectedVersion'),
            jsonObject(request['sleep'], 'sleep'),
          )).describe(),
        );
      case 'sleep delete':
        if (request['confirm'] != true)
          invalid('Deleting a sleep record requires confirm:true.');
        await sleep.delete(
          identifier(request, 'id'),
          integer('expectedVersion'),
        );
        return ok({'deleted': identifier(request, 'id')});
      case 'sleep show':
        return ok((await sleep.record(identifier(request, 'id'))).describe());
      case 'sleep list':
        return ok([
          for (final r in await store.sleepRecords(
            fromDate: request['from'] == null
                ? null
                : checkDate(request['from'], 'from'),
            untilDate: request['until'] == null
                ? null
                : checkDate(request['until'], 'until'),
          ))
            r.describe(),
        ]);
      case 'sleep mark':
        return ok(
          (await sleep.mark(
            checkDate(request['date'], 'date'),
            requiredString(request, 'status'),
          )).toJson(),
        );
      case 'sleep schedule':
        return ok(
          (await sleep.setSchedule(
            jsonObject(request['schedule'], 'schedule'),
            integer('expectedRevision', min: 0),
          )).toJson(),
        );
      case 'sleep schedules':
        return ok([for (final s in await sleep.schedules()) s.toJson()]);
      case 'sleep sun':
        return ok(await sleep.sun(checkDate(request['from'], 'from'), days()));
      case 'sleep stats':
        return ok(
          await sleep.stats(
            checkDate(request['from'], 'from'),
            checkDate(request['until'], 'until'),
          ),
        );
      case 'sleep plan-view':
        return ok(
          await sleep.planView(
            checkDate(request['from'], 'from'),
            checkDate(request['until'], 'until'),
          ),
        );
      case 'sleep import-preview':
        return ok(
          await SleepImportService(
            store,
          ).preview(SleepImportDocument.fromJson(request['document'])),
        );
      case 'sleep import-apply':
        return ok(
          await SleepImportService(store).apply(
            SleepImportDocument.fromJson(request['document']),
            onChanged: (request['onChanged'] ?? 'reject') as String,
            confirm: request['confirm'] == true,
          ),
        );
    }
    invalid('Unknown sleep command.');
  } finally {
    await store.close();
  }
}
