import 'dart:convert';

import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'fixtures.dart';
import 'cli_test.dart';
import 'support.dart';

void activityTests() {
  test('manual rest is explicit and cannot imply a duration', () {
    final rest =
        Activity.fromJson({'id': 'recover', 'type': 'rest', 'manual': true})
            as Rest;
    check(rest.isManual);
    equal(rest.durationSeconds, null);
    jsonEqual(rest.toJson(), {'type': 'rest', 'id': 'recover', 'manual': true});
    for (final fields in [
      {'manual': false},
      {'manual': null},
      {'manual': true, 'durationSeconds': 10},
      {'durationSeconds': 0},
      <String, Object?>{},
    ]) {
      rejects(
        () => Activity.fromJson({'id': 'recover', 'type': 'rest', ...fields}),
      );
    }
    final timed =
        Activity.fromJson({
              'id': 'recover',
              'type': 'rest',
              'durationSeconds': 10,
            })
            as Rest;
    check(!timed.isManual);
    equal(timed.durationSeconds, 10);
  });
  test(
    'requested nested walk/run plan has 72 efforts and only two outer rests',
    () {
      final plan = Activity.fromJson({
        'id': 'blocks',
        'type': 'repeat',
        'count': 3,
        'restBetweenSeconds': 120,
        'child': {
          'id': 'rounds',
          'type': 'repeat',
          'count': 12,
          'child': {
            'id': 'pair',
            'type': 'sequence',
            'children': [
              {'id': 'walk', 'type': 'effort', 'slot': 'walk'},
              {'id': 'run', 'type': 'effort', 'slot': 'run'},
            ],
          },
        },
      });
      final occurrences = plan.occurrences().toList();
      equal(occurrences.where((o) => o.activity is Effort).length, 72);
      final rests = occurrences.map((o) => o.activity).whereType<Rest>();
      equal(rests.length, 2);
      equal(
        rests.fold<int>(0, (sum, rest) => sum + rest.durationSeconds!),
        240,
      );
      equal(occurrences.map((o) => o.id).toSet().length, 74);
      equal(72 * 30 + 240, 40 * 60);
      jsonEqual(Activity.fromJson(plan.toJson()).toJson(), plan.toJson());
    },
  );
  test('window structure preserves deadlines without claiming execution', () {
    final plan = Activity.fromJson({
      'id': 'minute',
      'type': 'window',
      'durationSeconds': 60,
      'child': {'id': 'set', 'type': 'effort', 'slot': 'clean'},
    });
    check(plan is TimeWindow);
    equal((plan as TimeWindow).durationSeconds, 60);
    equal(plan.occurrences().single.id, 'minute/set');
  });
  test(
    'nested repeated windows expose structural bounds without claiming timing or results',
    () async {
      final input = definition().toJson();
      input['plan'] = {
        'id': 'outer',
        'type': 'window',
        'durationSeconds': 600,
        'child': {
          'id': 'rounds',
          'type': 'repeat',
          'count': 2,
          'restBetweenSeconds': 30,
          'child': {
            'id': 'minute',
            'type': 'window',
            'durationSeconds': 60,
            'child': {
              'id': 'pair',
              'type': 'sequence',
              'children': [
                {'id': 'a', 'type': 'effort', 'slot': 'bench-heavy'},
                {'id': 'rest', 'type': 'rest', 'manual': true},
                {'id': 'b', 'type': 'effort', 'slot': 'bench-light'},
              ],
            },
          },
        },
      };
      final workout = WorkoutDefinition.fromJson(input);
      final groups = activityGroups(workout.plan);
      final byPath = {for (final group in groups) group.path: group};
      final first = byPath['outer/rounds[0]/minute']!;
      final second = byPath['outer/rounds[1]/minute']!;
      equal(first.start, 0);
      equal(first.end, 3);
      equal(first.windowDurationSeconds, 60);
      equal(second.start, 4);
      equal(second.end, 7);
      equal(byPath['outer']!.windowDurationSeconds, 600);
      equal(byPath['outer']!.end, 7);
      final between = activityGroups(workout.plan, containing: 3);
      check(between.any((g) => g.path == 'outer'));
      check(between.any((g) => g.path == 'outer/rounds'));
      check(between.every((g) => g.windowDurationSeconds != 60));
      final report = jsonObject(
        const Commands().execute('activity groups', {
          'schemaVersion': 1,
          'definition': input,
          'containing': 4,
        })['data'],
        'groups',
      );
      final cli = await invoke(
        ['activity', 'groups'],
        jsonEncode({'schemaVersion': 1, 'definition': input, 'containing': 4}),
      );
      equal(cli.code, 0);
      jsonEqual(jsonObject(jsonDecode(cli.output), 'response')['data'], report);
      equal(report['occurrenceCount'], 7);
      equal(report['containing'], 4);
      final visible = jsonList(
        report,
        'groups',
      ).map((g) => jsonObject(g, 'group')).toList();
      check(
        visible.any(
          (g) =>
              g['path'] == 'outer/rounds[1]/minute' &&
              g['windowDurationSeconds'] == 60,
        ),
      );
      check(
        visible.every(
          (g) => !g.containsKey('elapsed') && !g.containsKey('completed'),
        ),
      );
      final session = const TrainingService().start(
        sessionId: 'window-session',
        revision: WorkoutRevision.publish(workout),
        startedAt: instant(1),
      );
      rejects(() => executionPlan(session));
      rejects(
        () => const Commands().execute('activity groups', {
          'schemaVersion': 1,
          'definition': input,
          'containing': 7,
        }),
      );
      rejects(
        () => const Commands().execute('activity groups', {
          'schemaVersion': 1,
          'definition': input,
          'containing': -1,
        }),
      );
    },
  );
  test('duplicate IDs and unknown slots fail before a session is created', () {
    final input = definition().toJson();
    input['plan'] = {
      'id': 'dup',
      'type': 'sequence',
      'children': [
        {'id': 'same', 'type': 'effort', 'slot': 'bench-heavy'},
        {'id': 'same', 'type': 'effort', 'slot': 'bench-light'},
      ],
    };
    rejects(() => WorkoutDefinition.fromJson(input));
    input['plan'] = {'id': 'bad', 'type': 'effort', 'slot': 'missing'};
    rejects(() => WorkoutDefinition.fromJson(input));
  });
  test(
    'group queries bound their output and allow a narrow occurrence filter',
    () {
      final plan = Repeat(
        'rounds',
        5001,
        const TimeWindow('minute', 60, Effort('set', 'lift')),
        0,
      );
      rejects(() => activityGroups(plan));
      final selected = activityGroups(plan, containing: 0);
      equal(selected.length, 3);
      check(selected.any((g) => g.windowDurationSeconds == 60));
    },
  );
  test('invalid/empty/oversized plans fail with resource errors', () {
    rejects(
      () => Activity.fromJson({
        'id': 'bad',
        'type': 'sequence',
        'children': <Object?>[],
      }),
    );
    rejects(
      () => Activity.fromJson({
        'id': 'bad',
        'type': 'repeat',
        'count': -1,
        'child': <String, Object?>{},
      }),
    );
    final input = definition().toJson();
    input['plan'] = {
      'id': 'many',
      'type': 'repeat',
      'count': 10001,
      'child': {'id': 'set', 'type': 'effort', 'slot': 'bench-heavy'},
    };
    rejects(() => WorkoutDefinition.fromJson(input));
  });
}
