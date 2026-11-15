import 'dart:convert';
import 'dart:io';
import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'cli_test.dart';
import 'fixtures.dart';
import 'support.dart';

const _analytics = TrainingAnalytics();
WorkoutDefinition _definition({
  String equipment = 'bar',
  String setup = 'narrow',
  String implementation = 'barbell',
  String name = 'Rows',
}) => WorkoutDefinition.fromJson({
  'id': 'rows',
  'name': name,
  'slots': [
    {
      'id': 'heavy',
      'exercise': 'row',
      'implementation': implementation,
      'equipment': equipment,
      'setupNote': setup,
      'targets': {
        'mass': {'value': '100', 'unit': 'lb'},
        'reps': {'value': '8', 'unit': 'rep'},
        'duration': {'value': '1500', 'unit': 'ms'},
        'distance': {'value': '150', 'unit': 'cm'},
      },
    },
    {
      'id': 'light',
      'exercise': 'row',
      'implementation': 'dumbbell',
      'equipment': 'pair',
      'targets': {
        'mass': {'value': '20', 'unit': 'kg'},
        'reps': {'value': '12', 'unit': 'rep'},
      },
    },
  ],
  'plan': {
    'id': 'workout',
    'type': 'sequence',
    'children': [
      {'id': 'warmup', 'type': 'effort', 'slot': 'heavy', 'role': 'warmup'},
      {
        'id': 'heavy-rounds',
        'type': 'repeat',
        'count': 2,
        'child': {'id': 'lift', 'type': 'effort', 'slot': 'heavy'},
      },
      {'id': 'light', 'type': 'effort', 'slot': 'light'},
    ],
  },
});
TrainingSession _start(String id, int day, {WorkoutRevision? revision}) =>
    const TrainingService().start(
      sessionId: id,
      revision: revision ?? WorkoutRevision.publish(_definition()),
      startedAt: instant(day),
    );
TrainingSession _complete(TrainingSession s) {
  for (final set in s.sets)
    s = const TrainingService().complete(s, set.id, {}, acceptSuggested: true);
  return s;
}

Map<String, Object?> _total(
  Map<String, Object?> summary,
  String metric, [
  String? unit,
]) => jsonList(summary, 'totals')
    .map((t) => jsonObject(t, 'total'))
    .singleWhere(
      (t) => t['metric'] == metric && (unit == null || t['unit'] == unit),
    );
List<Map<String, Object?>> _series(Map<String, Object?> report) =>
    jsonList(report, 'series').map((s) => jsonObject(s, 'series')).toList();

void analyticsTests() {
  test(
    'summary uses only confirmed observations, explicit sums and exact entered units, with warmups excluded by default',
    () {
      var s = _start('one', 1);
      s = const TrainingService().complete(
        s,
        s.sets[0].id,
        {},
        acceptSuggested: true,
      );
      s = const TrainingService().complete(s, s.sets[1].id, {
        'reps': Quantity('10', 'rep'),
        'duration': Quantity('2', 's'),
        'distance': Quantity('200', 'cm'),
      }, acceptSuggested: true);
      s = const TrainingService().skip(s, s.sets[2].id);
      final before = canonicalJson(s.toJson());
      final report = _analytics.summary(
        s,
        sumMetrics: ['reps', 'duration', 'distance'],
      );
      final counts = jsonObject(report['counts'], 'counts');
      equal(counts['completed'], 1);
      equal(counts['skipped'], 1);
      equal(counts['planned'], 1);
      equal(counts['excludedWarmups'], 1);
      equal(report['elapsed'], null);
      equal(_total(report, 'reps')['value'], '10');
      equal(_total(report, 'reps')['planned'], 1);
      equal(_total(report, 'reps')['skipped'], 1);
      equal(_total(report, 'duration')['value'], '2');
      equal(_total(report, 'distance')['value'], '2');
      final sets = jsonList(report, 'sets');
      final metrics = jsonObject(
        jsonObject(sets.first, 'set')['metrics'],
        'metrics',
      );
      equal(jsonObject(metrics['reps'], 'reps')['relation'], 'above');
      equal(jsonObject(metrics['mass'], 'mass')['relation'], 'equal');
      equal(
        jsonObject(
          jsonObject(
            jsonObject(metrics['mass'], 'mass')['actual'],
            'actual',
          )['entered'],
          'entered',
        )['unit'],
        'lb',
      );
      equal(
        _total(
          _analytics.summary(s, includeWarmups: true, sumMetrics: ['reps']),
          'reps',
        )['value'],
        '18',
      );
      equal(jsonList(_analytics.summary(s), 'totals').length, 0);
      equal(canonicalJson(s.toJson()), before);
    },
  );
  test(
    'summaries distinguish observed zero from omitted work and do not invent workload from raw masses',
    () {
      var s = _start('one', 1);
      var r = _analytics.summary(s, sumMetrics: ['reps']);
      equal(_total(r, 'reps')['value'], null);
      equal(_total(r, 'reps')['planned'], 3);
      for (final set in s.sets) s = const TrainingService().skip(s, set.id);
      r = _analytics.summary(s, sumMetrics: ['reps']);
      equal(_total(r, 'reps')['value'], null);
      equal(_total(r, 'reps')['skipped'], 3);
      s = const TrainingService().complete(s, s.sets.last.id, {
        'mass': Quantity('0', 'kg'),
        'reps': Quantity('0', 'rep'),
      });
      s = s.finish(
        s.startedAt.add(const Duration(seconds: 1, microseconds: 1)),
      );
      r = _analytics.summary(s, sumMetrics: ['reps', 'mass']);
      equal(_total(r, 'reps')['value'], '0');
      equal(_total(r, 'mass')['value'], '0');
      equal(jsonObject(r['elapsed'], 'elapsed')['value'], '1.000001');
      final all = _analytics.summary(
        _complete(_start('all', 1)),
        sumMetrics: ['mass'],
      );
      equal(
        _total(all, 'mass')['value'],
        '110.718474',
      ); // Raw 2×100 lb + 20 kg, never kg×reps.
      check(!all.containsKey('volume'));
    },
  );
  test(
    'same metric ID with different dimensions stays separate and unplanned observations are descriptive',
    () {
      var s = _complete(_start('one', 1));
      s = const TrainingService().complete(s, s.sets[1].id, {
        'custom': Quantity('2', 'm'),
      }, acceptSuggested: true);
      s = const TrainingService().complete(s, s.sets.last.id, {
        'custom': Quantity('3', 's'),
      }, acceptSuggested: true);
      final report = _analytics.summary(s, sumMetrics: ['custom']);
      equal(_total(report, 'custom', 'm')['value'], '2');
      equal(_total(report, 'custom', 's')['value'], '3');
      final first = jsonObject(jsonList(report, 'sets').first, 'set');
      equal(
        jsonObject(
          jsonObject(first['metrics'], 'metrics')['custom'],
          'custom',
        )['relation'],
        'unplanned',
      );
      final history = _analytics.series([
        s.finish(instant(2)),
      ], metric: 'custom');
      equal(_series(history).length, 2);
    },
  );
  test(
    'history preserves stable slot lineage across revisions and separates implementation, equipment, setup and run contexts',
    () {
      final revision = WorkoutRevision.publish(_definition());
      final renamed = WorkoutRevision.publish(
        _definition(name: 'Renamed rows'),
        previous: revision,
      );
      final changed = WorkoutRevision.publish(
        _definition(
          equipment: 'other',
          setup: 'wide',
          implementation: 'machine',
        ),
        previous: renamed,
      );
      final sessions = [
        _complete(_start('one', 1, revision: revision)).finish(instant(2)),
        _complete(_start('two', 2, revision: renamed)).finish(instant(3)),
        _complete(_start('three', 3, revision: changed)).finish(instant(4)),
      ];
      var history = _analytics.series(sessions, metric: 'mass');
      equal(history['pointCount'], 9);
      equal(_series(history).length, 3);
      final heavy = _series(history).singleWhere(
        (s) => jsonObject(s['context'], 'context')['equipment'] == 'bar',
      );
      equal(jsonList(heavy, 'points').length, 4);
      final first = jsonObject(jsonList(heavy, 'points').first, 'point');
      equal(first['revision'], 1);
      equal(first['setContentVersion'], 2);
      equal(first['sessionContentVersion'], 6);
      equal(jsonObject(first['actual'], 'actual')['value'], '45.359237');
      history = _analytics.series(
        sessions,
        metric: 'mass',
        runBySession: {'one': 'strength', 'two': 'cardio'},
      );
      equal(_series(history).length, 6);
      equal(
        canonicalJson(
          _analytics.series(sessions.reversed.toList(), metric: 'mass'),
        ),
        canonicalJson(_analytics.series(sessions, metric: 'mass')),
      );
    },
  );
  test(
    'series filters use start instants with inclusive from/exclusive until, exact null contexts and explicit active/warmup inclusion',
    () {
      final finalized = _complete(_start('one', 1)).finish(instant(2));
      final active = _complete(_start('two', 2));
      final sessions = [finalized, active];
      equal(_analytics.series(sessions, metric: 'reps')['pointCount'], 3);
      equal(
        _analytics.series(
          sessions,
          metric: 'reps',
          includeActive: true,
        )['pointCount'],
        6,
      );
      equal(
        _analytics.series(
          sessions,
          metric: 'reps',
          includeActive: true,
          includeWarmups: true,
        )['pointCount'],
        8,
      );
      final args = {'one': 'strength'};
      equal(
        _analytics.series(
          sessions,
          metric: 'reps',
          includeActive: true,
          runBySession: args,
          context: {'runId': null},
        )['pointCount'],
        3,
      );
      equal(
        _analytics.series(
          sessions,
          metric: 'reps',
          includeActive: true,
          runBySession: args,
          context: {'runId': 'strength', 'slotId': 'heavy'},
        )['pointCount'],
        2,
      );
      equal(
        _analytics.series(
          sessions,
          metric: 'reps',
          includeActive: true,
          from: instant(1),
          until: instant(2),
        )['pointCount'],
        3,
      );
      equal(
        _analytics.series(
          sessions,
          metric: 'reps',
          from: instant(2),
        )['pointCount'],
        0,
      );
      equal(
        _analytics.series(
          sessions,
          metric: 'reps',
          context: {'setupNote': null},
        )['pointCount'],
        1,
      );
      final emptyNote = _complete(
        _start(
          'empty',
          3,
          revision: WorkoutRevision.publish(_definition(setup: '')),
        ),
      ).finish(instant(4));
      equal(
        _analytics.series(
          [emptyNote],
          metric: 'reps',
          context: {'setupNote': ''},
        )['pointCount'],
        2,
      );
      equal(
        _analytics.series(
          sessions,
          metric: 'reps',
          context: {'equipment': null},
        )['pointCount'],
        0,
      );
    },
  );
  test(
    'analytics rejects ambiguous inputs and resource overflow rather than silently truncating history',
    () {
      final session = _complete(_start('one', 1)).finish(instant(2));
      rejects(() => _analytics.series([session, session]));
      rejects(
        () => _analytics.series([session], runBySession: {'missing': 'run'}),
      );
      rejects(() => _analytics.series([session], context: {'equipment': 12}));
      rejects(() => _analytics.series([session], context: {'role': 'unknown'}));
      rejects(() => _analytics.series([session], context: {'family': 'rows'}));
      rejects(
        () => _analytics.series([session], from: instant(2), until: instant(1)),
      );
      rejects(() => _analytics.summary(session, sumMetrics: ['reps', 'reps']));
      rejects(() => _analytics.summary(session, sumMetrics: ['bad id']));
      final many = [
        for (var i = 0; i < 3334; i++)
          TrainingSession(
            id: 's$i',
            extraSets: const [],
            revision: session.revision,
            variantSelections: session.variantSelections,
            startedAt: session.startedAt,
            sets: session.sets,
            status: session.status,
            finishedAt: session.finishedAt,
          ),
      ];
      rejects(() => _analytics.series(many, metric: 'reps'));
      equal(
        _analytics.series(
          many,
          metric: 'reps',
          context: {'slotId': 'light'},
        )['pointCount'],
        3334,
      );
    },
  );
  test(
    'native summaries/series match pure CLI, leave archives unchanged and reflect corrections after logical restoration',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-analytics-');
      final path = '${dir.path}/db.sqlite';
      final store = await TrainingStore.open(path);
      try {
        final training = StoredTrainingService(store),
            programs = ProgramService(store);
        await training.publish(_definition(), 0);
        await programs.publish(
          ProgramDefinition.fromJson({
            'id': 'shared',
            'name': 'Shared workout',
            'plan': {
              'id': 'day',
              'type': 'day',
              'templateId': 'rows',
              'revision': 1,
            },
          }),
          0,
        );
        for (final pair in [('strength', 'one', 1), ('cardio', 'two', 2)]) {
          await programs.create(pair.$1, 'shared', 1, instant(1), loop: true);
          final s = await programs.start(pair.$1, 1, pair.$2, instant(pair.$3));
          await training.edit(
            s.id,
            s.contentVersion,
            (s) => _complete(s).finish(instant(pair.$3 + 1)),
          );
        }
        final one = (await store.session('one'))!;
        final sessions = await store.sessions();
        await store.close();
        Future<Map<String, Object?>> cmd(
          String name,
          Map<String, Object?> input,
        ) async {
          final result = await invoke(
            name.split(' '),
            jsonEncode({'schemaVersion': 1, 'database': path, ...input}),
          );
          equal(result.code, 0);
          equal(result.error, '');
          return jsonObject(
            jsonObject(jsonDecode(result.output), 'response')['data'],
            'data',
          );
        }

        final before = await cmd('archive export', {
          'destination': '${dir.path}/before.json',
        });
        var summary = await cmd('store summary', {
          'id': 'one',
          'sumMetrics': ['reps', 'duration'],
        });
        final pureSummary = const Commands().execute('session summary', {
          'schemaVersion': 1,
          'session': one.toJson(),
          'sumMetrics': ['reps', 'duration'],
        })['data'];
        equal(canonicalJson(summary), canonicalJson(pureSummary));
        var series = await cmd('store series', {'metric': 'reps'});
        final pureSeries = const Commands().execute('history series', {
          'schemaVersion': 1,
          'sessions': [for (final s in sessions) s.toJson()],
          'metric': 'reps',
          'runBySession': {'one': 'strength', 'two': 'cardio'},
        })['data'];
        equal(canonicalJson(series), canonicalJson(pureSeries));
        equal(_series(series).length, 4);
        equal(series['pointCount'], 6);
        equal(
          (await cmd('store series', {
            'metric': 'reps',
            'context': {'runId': 'strength'},
          }))['pointCount'],
          3,
        );
        final after = await cmd('archive export', {
          'destination': '${dir.path}/after.json',
        });
        equal(before['sha256'], after['sha256']);
        await cmd('store complete', {
          'id': 'one',
          'expectedVersion': one.contentVersion,
          'setId': one.sets[1].id,
          'actuals': {
            'reps': {'value': '11', 'unit': 'rep'},
          },
          'acceptSuggested': true,
        });
        summary = await cmd('store summary', {
          'id': 'one',
          'sumMetrics': ['reps', 'duration'],
        });
        equal(_total(summary, 'reps')['value'], '31');
        series = await cmd('store series', {'metric': 'reps'});
        final points = _series(series)
            .expand((s) => jsonList(s, 'points'))
            .map((p) => jsonObject(p, 'point'));
        final corrected = points.singleWhere(
          (p) => p['sessionId'] == 'one' && p['setId'] == one.sets[1].id,
        );
        equal(corrected['setContentVersion'], 3);
        equal(corrected['sessionContentVersion'], one.contentVersion + 1);
        await cmd('archive export', {
          'destination': '${dir.path}/corrected.json',
        });
        final target = '${dir.path}/restored.sqlite';
        await cmd('archive restore', {
          'database': target,
          'source': '${dir.path}/corrected.json',
          'recoveryDestination': '${dir.path}/recovery',
          'confirm': true,
        });
        equal(
          canonicalJson(
            await cmd('store summary', {
              'database': target,
              'id': 'one',
              'sumMetrics': ['reps', 'duration'],
            }),
          ),
          canonicalJson(summary),
        );
        equal(
          canonicalJson(
            await cmd('store series', {'database': target, 'metric': 'reps'}),
          ),
          canonicalJson(series),
        );
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'analytics CLI rejects malformed options and never treats suggestions as actual history',
    () {
      final session = _start('one', 1);
      final commands = const Commands();
      final base = {'schemaVersion': 1, 'session': session.toJson()};
      rejects(
        () => commands.execute('session summary', {
          ...base,
          'sumMetrics': ['reps', 1],
        }),
      );
      rejects(
        () => commands.execute('session summary', {
          ...base,
          'includeWarmups': 'false',
        }),
      );
      rejects(
        () => commands.execute('history series', {
          'schemaVersion': 1,
          'sessions': [session.toJson()],
          'runBySession': {'one': null},
        }),
      );
      rejects(
        () => commands.execute('history series', {
          'schemaVersion': 1,
          'sessions': [session.toJson()],
          'from': '2026-10-31',
        }),
      );
      final r = commands.execute('history series', {
        'schemaVersion': 1,
        'sessions': [session.toJson()],
        'includeActive': true,
      });
      equal(jsonObject(r['data'], 'data')['pointCount'], 0);
    },
  );
}
