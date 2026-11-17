import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';

import 'timing_runner.dart';

/// Practice and activity commands (stage 5).
const dailyCommandNames = [
  'practice define',
  'practice show',
  'practice list',
  'practice start',
  'practice run',
  'practice recover',
  'practice end',
  'practice confirm',
  'practice abandon',
  'practice log',
  'practice session',
  'practice sessions',
  'activity record',
  'activity update',
  'activity delete',
  'activity show',
  'activity list',
  'activity summary',
  'activity import-validate',
  'activity import-preview',
  'activity import-apply',
];

Future<Map<String, Object?>> executeDaily(
  String command,
  Map<String, Object?> request,
) async {
  const pure = {'activity import-validate'};
  final fields = switch (command) {
    'practice define' => {'practice', 'expectedRevision'},
    'practice show' => {'practiceId', 'revision'},
    'practice list' => <String>{},
    'practice start' => {'id', 'practiceId', 'revision', 'at', 'before'},
    'practice run' => {'id', 'runForMilliseconds', 'stream'},
    'practice recover' => {'id', 'at', 'adjustmentMilliseconds'},
    'practice end' => {'id', 'at'},
    'practice confirm' => {'id', 'expectedVersion', 'at', 'after', 'notes'},
    'practice abandon' => {'id', 'expectedVersion', 'confirm'},
    'practice log' => {
      'id',
      'practiceId',
      'revision',
      'at',
      'milliseconds',
      'before',
      'after',
      'notes',
    },
    'practice session' => {'id'},
    'practice sessions' => {'from', 'until'},
    'activity record' => {'activity'},
    'activity update' => {'id', 'expectedVersion', 'activity'},
    'activity delete' => {'id', 'expectedVersion', 'confirm'},
    'activity show' => {'id'},
    'activity list' => {'from', 'until'},
    'activity summary' => {'from', 'until'},
    'activity import-validate' => {'document'},
    'activity import-preview' => {'document'},
    'activity import-apply' => {'document', 'onChanged', 'confirm'},
    _ => invalid('Unknown command.'),
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

  int? optionalInt(String key, {int min = 1}) =>
      request[key] == null ? null : integer(key, min: min);
  String? date(String key) =>
      request[key] == null ? null : checkDate(request[key], key);
  Map<String, Object?> ok(Object? data) => {'schemaVersion': 1, 'data': data};

  if (command == 'activity import-validate') {
    final d = ActivityImportDocument.fromJson(request['document']);
    return ok({
      'format': activityImportFormat,
      'namespace': d.namespace,
      'activities': d.activities.length,
    });
  }

  final store = await TrainingStore.open(requiredString(request, 'database'));
  try {
    final practices = PracticeService(store);
    final activities = ActivityService(store);
    final timing = TimingService(store);
    Future<Map<String, Object?>> sessionView(String id) async {
      final s = await practices.session(id);
      return {
        ...s.toJson(),
        if (s.clockId != null)
          'clock': {
            ...(await timing.show(s.clockId!)).toViewJson(),
            'requiresRecovery':
                (await timing.show(s.clockId!)).status == 'running',
          },
      };
    }

    switch (command) {
      case 'practice define':
        return ok(
          (await practices.define(
            PracticeDefinition.fromJson(request['practice']),
            integer('expectedRevision', min: 0),
          )).toJson(),
        );
      case 'practice show':
        return ok(
          (await practices.revision(
            identifier(request, 'practiceId'),
            optionalInt('revision'),
          )).toJson(),
        );
      case 'practice list':
        final latest = <String, PracticeRevision>{};
        for (final r in await practices.revisions()) {
          if ((latest[r.practice.id]?.number ?? 0) < r.number)
            latest[r.practice.id] = r;
        }
        return ok([for (final r in latest.values) r.toJson()]);
      case 'practice start':
        final started = await practices.start(
          id: identifier(request, 'id'),
          practiceId: identifier(request, 'practiceId'),
          revision: optionalInt('revision'),
          at: requiredString(request, 'at'),
          before: request['before'],
        );
        return ok({
          ...started.session.toJson(),
          'clock': started.clock.toViewJson(),
        });
      case 'practice run':
        final s = await practices.session(identifier(request, 'id'));
        if (s.status != 'active')
          invalid('The practice session is not active.');
        final clock = await timing.show(s.clockId!);
        final stream = request['stream'] ?? false;
        if (stream is! bool) invalid('stream is a boolean.');
        return ok(
          await runTiming(
            store,
            clock.id,
            clock.version,
            runForMilliseconds: optionalInt('runForMilliseconds'),
            stream: stream,
          ),
        );
      case 'practice recover':
        final s = await practices.session(identifier(request, 'id'));
        final clock = await timing.show(s.clockId!);
        return ok(
          (await timing.recover(
            clock.id,
            clock.version,
            parseInstant(request['at'], 'at'),
            adjustmentMilliseconds: optionalInt(
              'adjustmentMilliseconds',
              min: 0,
            ),
          )).toViewJson(),
        );
      case 'practice end':
        final s = await practices.session(identifier(request, 'id'));
        final clock = await timing.show(s.clockId!);
        if (clock.status == 'awaitingConfirmation')
          return ok(clock.toViewJson());
        if (clock.status == 'running')
          invalid('The clock is running; pause it or recover it first.');
        return ok(
          (await practices.end(
            s.id,
            clock.version,
            parseInstant(request['at'], 'at'),
          )).toViewJson(),
        );
      case 'practice confirm':
        final notes = request['notes'];
        if (notes != null && notes is! String) invalid('notes is text.');
        await practices.confirm(
          identifier(request, 'id'),
          integer('expectedVersion'),
          requiredString(request, 'at'),
          after: request['after'],
          notes: notes as String?,
        );
        return ok(await sessionView(identifier(request, 'id')));
      case 'practice abandon':
        if (request['confirm'] != true)
          invalid('Abandoning a practice session requires confirm:true.');
        await practices.abandon(
          identifier(request, 'id'),
          integer('expectedVersion'),
        );
        return ok(await sessionView(identifier(request, 'id')));
      case 'practice log':
        final notes = request['notes'];
        if (notes != null && notes is! String) invalid('notes is text.');
        return ok(
          (await practices.log(
            id: identifier(request, 'id'),
            practiceId: identifier(request, 'practiceId'),
            revision: optionalInt('revision'),
            at: requiredString(request, 'at'),
            milliseconds: integer('milliseconds', min: 0),
            before: request['before'],
            after: request['after'],
            notes: notes as String?,
          )).toJson(),
        );
      case 'practice session':
        return ok(await sessionView(identifier(request, 'id')));
      case 'practice sessions':
        final from = date('from'), until = date('until');
        return ok([
          for (final s in await practices.sessions())
            if ((from == null || s.date.compareTo(from) >= 0) &&
                (until == null || s.date.compareTo(until) < 0))
              s.toJson(),
        ]);
      case 'activity record':
        return ok(
          (await activities.add(
            jsonObject(request['activity'], 'activity'),
          )).describe(),
        );
      case 'activity update':
        return ok(
          (await activities.update(
            identifier(request, 'id'),
            integer('expectedVersion'),
            jsonObject(request['activity'], 'activity'),
          )).describe(),
        );
      case 'activity delete':
        if (request['confirm'] != true)
          invalid('Deleting an activity requires confirm:true.');
        await activities.delete(
          identifier(request, 'id'),
          integer('expectedVersion'),
        );
        return ok({'deleted': identifier(request, 'id')});
      case 'activity show':
        return ok(
          (await activities.record(identifier(request, 'id'))).toJson(),
        );
      case 'activity list':
        return ok([
          for (final r in await store.activityRecords(
            fromDate: date('from'),
            untilDate: date('until'),
          ))
            r.describe(),
        ]);
      case 'activity summary':
        return ok(
          await activities.summary(
            checkDate(request['from'], 'from'),
            checkDate(request['until'], 'until'),
          ),
        );
      case 'activity import-preview':
        return ok(
          await ActivityImportService(
            store,
          ).preview(ActivityImportDocument.fromJson(request['document'])),
        );
      case 'activity import-apply':
        return ok(
          await ActivityImportService(store).apply(
            ActivityImportDocument.fromJson(request['document']),
            onChanged: (request['onChanged'] ?? 'reject') as String,
            confirm: request['confirm'] == true,
          ),
        );
    }
    invalid('Unknown command.');
  } finally {
    await store.close();
  }
}
