import 'dart:convert';
import 'dart:io';
import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'cli_test.dart';
import 'fixtures.dart';
import 'support.dart';

const _records = ContextualRecords();
WorkoutDefinition _definition({
  String equipment = 'bar',
  String implementation = 'barbell',
  String? setup,
  Map<String, Object?>? timing,
  bool bodyMass = false,
  bool effectiveMass = false,
  int count = 1,
}) => WorkoutDefinition.fromJson({
  'id': 'records',
  'name': 'Contextual numeric records',
  'slots': [
    {
      'id': 'movement',
      'exercise': 'row',
      'implementation': implementation,
      'equipment': equipment,
      if (setup != null) 'setupNote': setup,
      if (timing != null) 'timing': timing,
      if (bodyMass) 'bodyMass': {'context': 'clothed'},
      if (effectiveMass)
        'effectiveMass': {
          'id': 'model',
          'version': 1,
          'bodyMassFraction': '0',
          'addedMass': {'metric': 'mass', 'multiplier': '1'},
          'assistance': {
            'mass': {'value': '0', 'unit': 'kg'},
          },
        },
      'targets': {
        'mass': {'value': '10', 'unit': 'kg'},
        'reps': {'value': '8', 'unit': 'rep'},
        'duration': {'value': '5', 'unit': 's'},
      },
    },
  ],
  'plan': {
    'id': 'practice',
    'type': 'sequence',
    'children': [
      {'id': 'warmup', 'type': 'effort', 'slot': 'movement', 'role': 'warmup'},
      {
        'id': 'work',
        'type': 'repeat',
        'count': count,
        'child': {'id': 'set', 'type': 'effort', 'slot': 'movement'},
      },
    ],
  },
});
TrainingSession _session(
  String id,
  int day, {
  String mass = '10',
  String unit = 'kg',
  String reps = '8',
  String duration = '5',
  Map<String, Quantity> extra = const {},
  WorkoutRevision? revision,
  bool active = false,
  bool skip = false,
}) {
  var s = const TrainingService().start(
    sessionId: id,
    revision: revision ?? WorkoutRevision.publish(_definition()),
    startedAt: instant(day),
  );
  for (final set in s.sets) {
    s = skip && set.role == 'work'
        ? const TrainingService().skip(s, set.id, confirm: true)
        : const TrainingService().complete(s, set.id, {
            'mass': Quantity(set.role == 'warmup' ? '100' : mass, unit),
            'reps': Quantity(reps, 'rep'),
            'duration': Quantity(duration, 's'),
            ...extra,
          }, acceptSuggested: true);
  }
  return active ? s : s.finish(instant(day).add(const Duration(hours: 1)));
}

Map<String, Object?> _report(
  List<TrainingSession> sessions, {
  String metric = 'mass',
  String direction = 'higher',
  Metrics at = const {},
  Map<String, String> runs = const {},
  Map<String, Object?> context = const {},
  DateTime? from,
  DateTime? until,
  bool warmups = false,
  FamilyRevision? family,
}) => _records.evaluate(
  sessions,
  metric: metric,
  direction: direction,
  atActuals: at,
  runBySession: runs,
  context: context,
  from: from,
  until: until,
  includeWarmups: warmups,
  family: family,
);
List<Map<String, Object?>> _groups(Map<String, Object?> report) =>
    jsonList(report, 'groups').map((g) => jsonObject(g, 'group')).toList();
List<Map<String, Object?>> _points(Map<String, Object?> group) =>
    jsonList(group, 'points').map((p) => jsonObject(p, 'point')).toList();

void recordsTests() {
  test(
    'contextual records retain neutral baseline, improvements, ties and all current best sources in deterministic selected-history order',
    () {
      final sessions = [
        for (var i = 0; i < 5; i++)
          _session('s$i', i + 1, mass: ['10', '12', '12', '11', '14'][i]),
      ];
      final report = _report(sessions.reversed.toList());
      equal(report['eligibleCount'], 5);
      equal(report['excludedCount'], 0);
      final group = _groups(report).single;
      equal(jsonObject(group['best'], 'best')['value'], '14');
      equal(
        _points(group).map((p) => p['marker']).join(','),
        'initial,record,tie,none,record',
      );
      equal(jsonList(group, 'bestSources').length, 1);
      equal(
        jsonObject(
          jsonList(group, 'bestSources').single,
          'source',
        )['sessionId'],
        's4',
      );
      final tied = _groups(_report(sessions.take(4).toList())).single;
      equal(jsonList(tied, 'bestSources').length, 2);
      final a = _session('a', 1, mass: '10');
      final b = _session('b', 1, mass: '12');
      equal(canonicalJson(_report([b, a])), canonicalJson(_report([a, b])));
    },
  );
  test(
    'lower records and exact unit ties preserve original actuals while canonical held quantities share a comparison group',
    () {
      final lower = _groups(
        _report(
          [
            _session('a', 1, duration: '5'),
            _session('b', 2, duration: '4'),
            _session('c', 3, duration: '4'),
          ],
          metric: 'duration',
          direction: 'lower',
        ),
      ).single;
      equal(jsonObject(lower['best'], 'best')['value'], '4');
      equal(
        _points(lower).map((p) => p['marker']).join(','),
        'initial,record,tie',
      );
      final s1 = _session('pounds', 1, mass: '10', unit: 'lb');
      final s2 = _session('kg', 2, mass: '4.5359237');
      final group = _groups(_report([s1, s2])).single;
      equal(jsonList(group, 'bestSources').length, 2);
      final first = jsonObject(_points(group).first['actual'], 'actual');
      equal(jsonObject(first['entered'], 'entered')['unit'], 'lb');
      final zero = _groups(_report([_session('zero', 1, mass: '0')])).single;
      equal(jsonObject(zero['best'], 'best')['value'], '0');
    },
  );
  test(
    'every other observed numeric condition is held exactly and explicit actual filters report excluded points instead of assuming equivalence',
    () {
      final sessions = [
        _session('eight', 1),
        _session('six', 2, mass: '20', reps: '6'),
        _session(
          'extra',
          3,
          mass: '30',
          extra: {'angle': Quantity('1', 'deg')},
        ),
      ];
      equal(_groups(_report(sessions)).length, 3);
      final report = _report(sessions, at: metrics({'reps': ('8', 'rep')}));
      equal(report['eligibleCount'], 2);
      equal(report['excludedCount'], 1);
      equal(
        jsonObject(jsonList(report, 'excluded').single, 'excluded')['reason'],
        'actual-conditions-not-met',
      );
      final wrongUnit = _report(sessions, at: metrics({'reps': ('8', 'kg')}));
      equal(wrongUnit['eligibleCount'], 0);
      equal(wrongUnit['excludedCount'], 3);
      final noValue = _report(
        sessions,
        at: metrics({'unobserved': ('0', 'kg')}),
      );
      equal(noValue['eligibleCount'], 0);
    },
  );
  test(
    'records preserve implementation, equipment, setup, role, run and timing guidance boundaries with explicit pinned family membership',
    () {
      WorkoutRevision revision(WorkoutDefinition d) =>
          WorkoutRevision.publish(d);
      final sessions = [
        _session('base', 1),
        _session(
          'equipment',
          2,
          revision: revision(_definition(equipment: 'other')),
        ),
        _session(
          'implementation',
          3,
          revision: revision(_definition(implementation: 'machine')),
        ),
        _session('setup', 4, revision: revision(_definition(setup: 'wide'))),
        _session(
          'timed',
          5,
          revision: revision(
            _definition(
              timing: {'metric': 'duration', 'preparationMilliseconds': 1000},
            ),
          ),
        ),
        _session('run', 6),
      ];
      final report = _report(sessions, runs: {'run': 'strength'});
      equal(_groups(report).length, 6);
      equal(
        _groups(
          _report(sessions, runs: {'run': 'strength'}, warmups: true),
        ).length,
        12,
      );
      final family = FamilyRevision.publish(
        ExerciseFamily.fromJson({
          'id': 'pull',
          'name': 'Pull',
          'exercises': ['row'],
        }),
      );
      final filtered = _report(sessions, family: family);
      equal(filtered['eligibleCount'], 6);
      equal(
        canonicalJson(jsonObject(filtered['policy'], 'policy')['family']),
        canonicalJson(family.toJson()),
      );
      final empty = FamilyRevision.publish(
        ExerciseFamily.fromJson({
          'id': 'none',
          'name': 'None',
          'exercises': <Object?>[],
        }),
      );
      equal(_report(sessions, family: empty)['eligibleCount'], 0);
    },
  );
  test(
    'active/skipped/absent observations never become records and tracked/derived mass contexts remain explicitly excluded',
    () {
      final active = _session('active', 1, mass: '1000', active: true);
      final skipped = _session('skipped', 2, skip: true);
      final body = _session(
        'body',
        3,
        revision: WorkoutRevision.publish(_definition(bodyMass: true)),
      );
      final derived = _session(
        'derived',
        4,
        revision: WorkoutRevision.publish(_definition(effectiveMass: true)),
      );
      final report = _report([active, skipped, body, derived]);
      equal(report['pointCount'], 2);
      equal(report['eligibleCount'], 0);
      equal(report['excludedCount'], 2);
      for (final input in jsonList(report, 'excluded'))
        equal(
          jsonObject(input, 'excluded')['reason'],
          'body-mass-or-derived-load-policy-required',
        );
      equal(
        _report([_session('ordinary', 5)], metric: 'unobserved')['pointCount'],
        0,
      );
      equal(_report([])['pointCount'], 0);
      equal(_groups(_report([])).length, 0);
    },
  );
  test(
    'corrections and confirmed result removal recompute records and input versions without changing source data',
    () {
      final a = _session('a', 1, mass: '10');
      var b = _session('b', 2, mass: '12');
      final before = canonicalJson(a.toJson());
      final set = b.sets.last;
      b = const TrainingService().complete(b, set.id, {
        'mass': Quantity('8', 'kg'),
      }, acceptSuggested: true);
      final group = _groups(_report([a, b])).single;
      equal(jsonObject(group['best'], 'best')['value'], '10');
      equal(
        _points(group).last['setContentVersion'],
        b.sets.last.contentVersion,
      );
      b = const TrainingService().skip(b, set.id, confirm: true);
      equal(_report([a, b])['pointCount'], 1);
      equal(canonicalJson(a.toJson()), before);
      equal(
        _report([a], from: instant(1), until: instant(2))['eligibleCount'],
        1,
      );
      equal(_report([a], from: instant(2))['eligibleCount'], 0);
    },
  );
  test(
    'record queries reject ambiguous policy, duplicate sources, invalid filters and resource overflow instead of truncating',
    () {
      final s = _session('one', 1);
      rejects(() => _report([s], direction: 'best'));
      rejects(() => _report([s], at: metrics({'mass': ('10', 'kg')})));
      rejects(() => _report([s, s]));
      rejects(() => _report([s], runs: {'absent': 'run'}));
      rejects(() => _report([s], context: {'unknown': 'value'}));
      rejects(() => _report([s], from: instant(2), until: instant(1)));
      final huge = WorkoutRevision.publish(_definition(count: 9999));
      final a = _session('many', 1, revision: huge);
      final b = _session(
        'extra',
        2,
        revision: WorkoutRevision.publish(_definition(count: 2)),
      );
      rejects(() => _report([a, b]));
      final malformed = const Commands();
      rejects(
        () => malformed.execute('history records', {
          'schemaVersion': 1,
          'sessions': <Object?>[],
          'metric': 'mass',
          'direction': 'higher',
          'includeActive': true,
        }),
      );
    },
  );
  test(
    'stored and pure native record queries agree, do not change archives and retain correction behavior after both restore formats',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-records-');
      var store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final training = StoredTrainingService(store);
        await training.publish(_definition(), 0);
        for (var day = 1; day <= 3; day++) {
          final s = await training.start('s$day', 'records', 1, instant(day));
          await training.edit(s.id, s.contentVersion, (s) {
            for (final set in s.sets)
              s = const TrainingService().complete(s, set.id, {
                'mass': Quantity(
                  set.role == 'warmup'
                      ? '100'
                      : day == 1
                      ? '10'
                      : '12',
                  'kg',
                ),
              }, acceptSuggested: true);
            return s.finish(instant(day).add(const Duration(hours: 1)));
          });
        }
        final family = await FamilyService(store).publish(
          ExerciseFamily.fromJson({
            'id': 'pull',
            'name': 'Pull',
            'exercises': ['row'],
          }),
          0,
        );
        final sessions = await store.sessions();
        final expected = _report(
          sessions,
          family: family,
          at: metrics({'reps': ('8', 'rep')}),
        );
        final before = canonicalJson((await store.archive()).toJson());
        await store.backup('${dir.path}/native');
        await LogicalArchiveFiles.export(
          await store.archive(),
          '${dir.path}/logical.json',
        );
        await store.close();
        Future<Map<String, Object?>> cmd(
          String action,
          Map<String, Object?> request,
        ) async {
          final r = await invoke(
            action.split(' '),
            jsonEncode({'schemaVersion': 1, ...request}),
          );
          equal(r.code, 0);
          equal(r.error, '');
          return jsonObject(
            jsonObject(jsonDecode(r.output), 'response')['data'],
            'data',
          );
        }

        final query = {
          'database': '${dir.path}/db.sqlite',
          'metric': 'mass',
          'direction': 'higher',
          'atActuals': {
            'reps': {'value': '8', 'unit': 'rep'},
          },
          'familyId': 'pull',
        };
        equal(
          canonicalJson(await cmd('store records', query)),
          canonicalJson(expected),
        );
        equal(
          canonicalJson(
            await cmd('history records', {
              'sessions': [for (final s in sessions) s.toJson()],
              'metric': 'mass',
              'direction': 'higher',
              'atActuals': {
                'reps': {'value': '8', 'unit': 'rep'},
              },
              'family': family.toJson(),
            }),
          ),
          canonicalJson(expected),
        );
        for (final kind in ['native', 'logical']) {
          store = await TrainingStore.open('${dir.path}/db.sqlite');
          final prepared = kind == 'native'
              ? await NativeBackup.prepare('${dir.path}/native')
              : (await LogicalArchiveFiles.prepare(
                  '${dir.path}/logical.json',
                )).backup;
          try {
            await store.restore(
              prepared,
              recoveryDestination: '${dir.path}/$kind-recovery',
              confirm: true,
            );
          } finally {
            await store.close();
            await prepared.close();
          }
          equal(
            canonicalJson(await cmd('store records', query)),
            canonicalJson(expected),
          );
        }
        store = await TrainingStore.open('${dir.path}/db.sqlite');
        equal(canonicalJson((await store.archive()).toJson()), before);
        final s = await StoredTrainingService(store).session('s2');
        await StoredTrainingService(store).edit(
          s.id,
          s.contentVersion,
          (s) => const TrainingService().skip(s, s.sets.last.id, confirm: true),
        );
        await store.close();
        final corrected = await cmd('store records', query);
        equal(jsonList(_groups(corrected).single, 'bestSources').length, 1);
        final bad = await invoke([
          'store',
          'records',
        ], jsonEncode({'schemaVersion': 1, ...query, 'familyRevision': 0}));
        check(bad.code != 0);
        equal(bad.output, '');
        check(!bad.error.contains('internal'));
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
