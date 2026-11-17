import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';

/// Goals, routines, today, trials and saved reviews (stage 6).
const planningCommandNames = [
  'metric evaluate',
  'goal save',
  'goal show',
  'goal list',
  'goal progress',
  'routine save',
  'routine list',
  'routine check',
  'today show',
  'trial save',
  'trial show',
  'trial list',
  'trial report',
  'trial conclude',
  'review save',
  'review list',
  'review run',
];

Future<Map<String, Object?>> executePlanning(
  String command,
  Map<String, Object?> request,
) async {
  final fields = switch (command) {
    'metric evaluate' => {'metric', 'from', 'until'},
    'goal save' => {'goal', 'expectedVersion'},
    'goal show' || 'trial show' || 'trial report' => {'id'},
    'goal list' ||
    'routine list' ||
    'trial list' ||
    'review list' => <String>{},
    'goal progress' => {'id', 'asOf'},
    'routine save' => {'routine', 'expectedVersion'},
    'routine check' => {'routineId', 'date', 'at', 'undo'},
    'today show' => {'date'},
    'trial save' => {'trial', 'expectedVersion'},
    'trial conclude' => {'id', 'expectedVersion', 'decision', 'at', 'notes'},
    'review save' => {'review', 'expectedVersion'},
    'review run' => {'id', 'from', 'until'},
    _ => invalid('Unknown command.'),
  };
  checkKeys(request, {'schemaVersion', 'database', ...fields});
  int integer(String key, {int min = 1}) {
    final value = request[key];
    if (value is! int || value < min)
      invalid('$key must be an integer >= $min.');
    return value;
  }

  Map<String, Object?> ok(Object? data) => {'schemaVersion': 1, 'data': data};
  final store = await TrainingStore.open(requiredString(request, 'database'));
  try {
    final planning = PlanningService(store);
    switch (command) {
      case 'metric evaluate':
        final metric = DailyMetric.fromJson(request['metric']);
        final days = await DailyMetricService(store).evaluate(
          metric,
          checkDate(request['from'], 'from'),
          checkDate(request['until'], 'until'),
        );
        return ok({
          'policy': 'bodytmi-daily-metric/1',
          'metric': metric.toJson(),
          'summary': describeValues(days),
          'days': [
            for (final d in days)
              {
                'date': d.date,
                'status': d.status,
                'value': ?(d.value == null ? null : round3(d.value!)),
              },
          ],
        });
      case 'goal save':
        return ok(
          (await planning.saveGoal(
            jsonObject(request['goal'], 'goal'),
            integer('expectedVersion', min: 0),
          )).toJson(),
        );
      case 'goal show':
        return ok((await planning.goal(identifier(request, 'id'))).toJson());
      case 'goal list':
        return ok({
          'goals': [for (final g in await planning.goals()) g.toJson()],
          'planGoals': await planning.planGoals(),
        });
      case 'goal progress':
        return ok(
          await planning.progress(
            await planning.goal(identifier(request, 'id')),
            checkDate(request['asOf'], 'asOf'),
          ),
        );
      case 'routine save':
        return ok(
          (await planning.saveRoutine(
            jsonObject(request['routine'], 'routine'),
            integer('expectedVersion', min: 0),
          )).toJson(),
        );
      case 'routine list':
        return ok([for (final r in await planning.routines()) r.toJson()]);
      case 'routine check':
        final undo = request['undo'] ?? false;
        if (undo is! bool) invalid('undo is a boolean.');
        return ok(
          await planning.check(
            identifier(request, 'routineId'),
            checkDate(request['date'], 'date'),
            requiredString(request, 'at'),
            undo: undo,
          ),
        );
      case 'today show':
        return ok(await planning.today(checkDate(request['date'], 'date')));
      case 'trial save':
        return ok(
          (await planning.saveTrial(
            jsonObject(request['trial'], 'trial'),
            integer('expectedVersion', min: 0),
          )).toJson(),
        );
      case 'trial show':
        return ok((await planning.trial(identifier(request, 'id'))).toJson());
      case 'trial list':
        return ok([for (final t in await planning.trials()) t.toJson()]);
      case 'trial report':
        return ok(await planning.report(identifier(request, 'id')));
      case 'trial conclude':
        final notes = request['notes'];
        if (notes != null && notes is! String) invalid('notes is text.');
        return ok(
          (await planning.conclude(
            identifier(request, 'id'),
            integer('expectedVersion'),
            requiredString(request, 'decision'),
            requiredString(request, 'at'),
            notes: notes as String?,
          )).toJson(),
        );
      case 'review save':
        return ok(
          (await planning.saveReview(
            jsonObject(request['review'], 'review'),
            integer('expectedVersion', min: 0),
          )).toJson(),
        );
      case 'review list':
        return ok([for (final r in await planning.reviews()) r.toJson()]);
      case 'review run':
        return ok(
          await planning.runReview(
            identifier(request, 'id'),
            checkDate(request['from'], 'from'),
            checkDate(request['until'], 'until'),
          ),
        );
    }
    invalid('Unknown command.');
  } finally {
    await store.close();
  }
}
