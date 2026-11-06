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
    'window deadlines use one explicit logical timeline and never certify effort',
    () async {
      final input = definition().toJson();
      input['plan'] = {
        'id': 'outer',
        'type': 'window',
        'durationSeconds': 10,
        'child': {
          'id': 'inner',
          'type': 'window',
          'durationSeconds': 3,
          'child': {'id': 'set', 'type': 'effort', 'slot': 'bench-heavy'},
        },
      };
      final workout = WorkoutDefinition.fromJson(input);
      const resolver = WindowDeadlines();
      final starts = <String, Object?>{'outer': 0, 'outer/inner': 9000};
      Map<String, Object?> resolve(
        int elapsed, [
        Map<String, Object?>? windows,
      ]) => resolver.evaluate(
        definition: workout,
        occurrence: 0,
        elapsedMilliseconds: elapsed,
        windowStarts: windows ?? starts,
      );
      final before = resolve(9999);
      equal(before['expired'], false);
      equal(before['earliestDeadlineMilliseconds'], 10000);
      final after = resolve(11000);
      final rows = jsonList(
        after,
        'windows',
      ).map((r) => jsonObject(r, 'window')).toList();
      equal(after['expired'], true);
      equal(rows[0]['expired'], true);
      equal(rows[0]['overrunMilliseconds'], 1000);
      equal(rows[1]['expired'], false);
      equal(rows[1]['remainingMilliseconds'], 1000);
      equal(resolve(12000)['expired'], true);
      equal(
        jsonObject(jsonList(resolve(12000), 'windows')[1], 'inner')['expired'],
        true,
      );
      final tied = resolve(10000, {'outer': 0, 'outer/inner': 7000});
      check(
        jsonList(
          tied,
          'windows',
        ).every((row) => jsonObject(row, 'window')['expired'] == true),
      );
      jsonEqual(resolve(11000), after);
      check(!after.containsKey('results') && !after.containsKey('completed'));
      rejects(() => resolve(11000, {'outer': 0}));
      rejects(() => resolve(11000, {'outer': 0, 'outer/inner': 10000}));
      rejects(() => resolve(11000, {'outer': 5000, 'outer/inner': 4000}));
      rejects(() => resolve(8000));
      rejects(() => resolve(2000000001));
      final request = {
        'schemaVersion': 1,
        'definition': input,
        'occurrence': 0,
        'elapsedMilliseconds': 11000,
        'windowStarts': starts,
      };
      final result = const Commands().execute(
        'activity window-status',
        request,
      );
      jsonEqual(result['data'], after);
      final cli = await invoke([
        'activity',
        'window-status',
      ], jsonEncode(request));
      equal(cli.code, 0);
      jsonEqual(jsonObject(jsonDecode(cli.output), 'response')['data'], after);
    },
  );
  test(
    'window crossing reports the first nested boundary without claiming work',
    () async {
      final input = definition().toJson();
      input['plan'] = {
        'id': 'outer',
        'type': 'window',
        'durationSeconds': 10,
        'child': {
          'id': 'sequence',
          'type': 'sequence',
          'children': [
            {'id': 'before', 'type': 'effort', 'slot': 'bench-heavy'},
            {
              'id': 'inner',
              'type': 'window',
              'durationSeconds': 3,
              'child': {
                'id': 'during',
                'type': 'effort',
                'slot': 'bench-heavy',
              },
            },
            {'id': 'after', 'type': 'effort', 'slot': 'bench-light'},
          ],
        },
      };
      final workout = WorkoutDefinition.fromJson(input);
      const resolver = WindowDeadlines();
      Map<String, Object?> crossing(int before, int after, int innerStart) =>
          resolver.crossing(
            definition: workout,
            occurrence: 1,
            previousElapsedMilliseconds: before,
            elapsedMilliseconds: after,
            windowStarts: {'outer': 0, 'outer/sequence/inner': innerStart},
          );
      equal(crossing(8000, 9999, 8000)['status'], 'within');
      final parent = crossing(8000, 12000, 8000);
      equal(parent['status'], 'crossed');
      final parentBoundary = jsonObject(parent['boundary'], 'boundary');
      equal(parentBoundary['elapsedMilliseconds'], 10000);
      jsonEqual(parentBoundary['paths'], ['outer']);
      equal(parentBoundary['scopeStart'], 0);
      equal(parentBoundary['scopeEnd'], 3);
      final child = jsonObject(
        crossing(1000, 11000, 1000)['boundary'],
        'boundary',
      );
      equal(child['elapsedMilliseconds'], 4000);
      jsonEqual(child['paths'], ['outer/sequence/inner']);
      equal(child['scopeStart'], 1);
      equal(child['scopeEnd'], 2);
      final tied = jsonObject(
        crossing(7000, 10000, 7000)['boundary'],
        'boundary',
      );
      jsonEqual(tied['paths'], ['outer', 'outer/sequence/inner']);
      equal(tied['scopeEnd'], 3);
      equal(crossing(10000, 11000, 8000)['status'], 'alreadyExpired');
      equal(crossing(10000, 10000, 8000)['boundary'], null);
      final unscoped = resolver.crossing(
        definition: definition(),
        occurrence: 0,
        previousElapsedMilliseconds: 0,
        elapsedMilliseconds: 10000,
        windowStarts: {},
      );
      equal(unscoped['status'], 'within');
      equal(unscoped['boundary'], null);
      rejects(() => crossing(9000, 8999, 8000));
      rejects(() => crossing(7999, 9000, 8000));
      check(!parent.containsKey('results') && !parent.containsKey('completed'));
      final request = {
        'schemaVersion': 1,
        'definition': input,
        'occurrence': 1,
        'previousElapsedMilliseconds': 8000,
        'elapsedMilliseconds': 12000,
        'windowStarts': {'outer': 0, 'outer/sequence/inner': 8000},
      };
      jsonEqual(
        const Commands().execute('activity window-crossing', request)['data'],
        parent,
      );
      final result = await invoke([
        'activity',
        'window-crossing',
      ], jsonEncode(request));
      equal(result.code, 0);
      jsonEqual(
        jsonObject(jsonDecode(result.output), 'response')['data'],
        parent,
      );
    },
  );
  test(
    'window transitions retain enclosing starts and validate scope entries',
    () async {
      final input = definition().toJson();
      input['plan'] = {
        'id': 'workout',
        'type': 'sequence',
        'children': [
          {
            'id': 'outer',
            'type': 'window',
            'durationSeconds': 10,
            'child': {
              'id': 'rounds',
              'type': 'repeat',
              'count': 2,
              'child': {
                'id': 'inner',
                'type': 'window',
                'durationSeconds': 5,
                'child': {
                  'id': 'pair',
                  'type': 'sequence',
                  'children': [
                    {'id': 'first', 'type': 'effort', 'slot': 'bench-heavy'},
                    {'id': 'second', 'type': 'effort', 'slot': 'bench-light'},
                  ],
                },
              },
            },
          },
          {'id': 'outside', 'type': 'effort', 'slot': 'bench-light'},
        ],
      };
      final workout = WorkoutDefinition.fromJson(input);
      const resolver = WindowDeadlines();
      const outer = 'workout/outer';
      const first = 'workout/outer/rounds[0]/inner';
      const second = 'workout/outer/rounds[1]/inner';
      Map<String, Object?> move(
        int from,
        int to,
        int time,
        Map<String, Object?> starts,
      ) => resolver.transition(
        definition: workout,
        fromOccurrence: from,
        toOccurrence: to,
        elapsedMilliseconds: time,
        windowStarts: starts,
      );
      final within = move(0, 1, 2000, {outer: 0, first: 0});
      jsonEqual(within['windowStarts'], {outer: 0, first: 0});
      jsonEqual(within['entered'], []);
      jsonEqual(within['exited'], []);
      final next = move(1, 2, 5000, {outer: 0, first: 0});
      jsonEqual(next['exited'], [first]);
      jsonEqual(next['entered'], [second]);
      jsonEqual(next['windowStarts'], {outer: 0, second: 5000});
      final exit = move(1, 4, 10000, {outer: 0, first: 0});
      jsonEqual(exit['exited'], [first, outer]);
      jsonEqual(exit['windowStarts'], {});
      final end = move(4, 5, 10000, {});
      equal(end['toOccurrenceId'], null);
      rejects(() => move(0, 1, 5000, {outer: 0, first: 0}));
      rejects(() => move(1, 2, 10000, {outer: 0, first: 0}));
      rejects(() => move(0, 3, 2000, {outer: 0, first: 0}));
      rejects(() => move(0, 0, 2000, {outer: 0, first: 0}));
      rejects(() => move(0, 6, 2000, {outer: 0, first: 0}));
      rejects(() => move(1, 2, 5000, {outer: 0}));
      check(!next.containsKey('results') && !next.containsKey('completed'));
      final request = {
        'schemaVersion': 1,
        'definition': input,
        'fromOccurrence': 1,
        'toOccurrence': 2,
        'elapsedMilliseconds': 5000,
        'windowStarts': {outer: 0, first: 0},
      };
      jsonEqual(
        const Commands().execute('activity window-transition', request)['data'],
        next,
      );
      final cli = await invoke([
        'activity',
        'window-transition',
      ], jsonEncode(request));
      equal(cli.code, 0);
      jsonEqual(jsonObject(jsonDecode(cli.output), 'response')['data'], next);
    },
  );
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
