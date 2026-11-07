import 'dart:convert';
import 'dart:io';

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
    'caller-owned window clock freezes on recovery and waits at boundaries',
    () async {
      final input = definition().toJson();
      input['plan'] = {
        'id': 'rounds',
        'type': 'repeat',
        'count': 2,
        'child': {
          'id': 'minute',
          'type': 'window',
          'durationSeconds': 5,
          'child': {'id': 'set', 'type': 'effort', 'slot': 'bench-heavy'},
        },
      };
      final workout = WorkoutDefinition.fromJson(input);
      const clock = WindowClock();
      var state = clock.start(workout);
      equal(state['status'], 'paused');
      jsonEqual(state['windowStarts'], {'rounds[0]/minute': 0});
      state = clock.apply(
        workout,
        state,
        expectedVersion: 1,
        action: 'resume',
        ownerId: 'epoch',
      );
      rejects(
        () => clock.apply(
          workout,
          state,
          expectedVersion: 2,
          action: 'advance',
          ownerId: 'other',
          ownerElapsedMilliseconds: 1,
        ),
      );
      rejects(
        () =>
            clock.apply(workout, state, expectedVersion: 1, action: 'recover'),
        'conflict',
      );
      state = clock.apply(
        workout,
        state,
        expectedVersion: 2,
        action: 'advance',
        ownerId: 'epoch',
        ownerElapsedMilliseconds: 3000,
      );
      equal(state['elapsedMilliseconds'], 3000);
      rejects(
        () => clock.apply(
          workout,
          state,
          expectedVersion: 3,
          action: 'advance',
          ownerId: 'epoch',
          ownerElapsedMilliseconds: 2999,
        ),
      );
      state = clock.apply(
        workout,
        state,
        expectedVersion: 3,
        action: 'recover',
      );
      equal(state['elapsedMilliseconds'], 3000);
      equal(state['status'], 'paused');
      state = clock.apply(
        workout,
        state,
        expectedVersion: 4,
        action: 'resume',
        ownerId: 'new-epoch',
      );
      state = clock.apply(
        workout,
        state,
        expectedVersion: 5,
        action: 'advance',
        ownerId: 'new-epoch',
        ownerElapsedMilliseconds: 4000,
      );
      equal(state['status'], 'boundary');
      equal(state['elapsedMilliseconds'], 5000);
      rejects(
        () => clock.apply(
          workout,
          state,
          expectedVersion: 6,
          action: 'resume',
          ownerId: 'epoch',
        ),
      );
      state = clock.apply(
        workout,
        state,
        expectedVersion: 6,
        action: 'move',
        toOccurrence: 1,
      );
      jsonEqual(state['windowStarts'], {'rounds[1]/minute': 5000});
      state = clock.apply(
        workout,
        state,
        expectedVersion: 7,
        action: 'resume',
        ownerId: 'third',
      );
      state = clock.apply(
        workout,
        state,
        expectedVersion: 8,
        action: 'pause',
        ownerId: 'third',
        ownerElapsedMilliseconds: 1000,
      );
      equal(state['elapsedMilliseconds'], 6000);
      state = clock.apply(
        workout,
        state,
        expectedVersion: 9,
        action: 'move',
        toOccurrence: 2,
      );
      equal(state['status'], 'complete');
      check(!state.containsKey('results'));
      final forged = {...clock.start(workout), 'status': 'boundary'};
      final future = {
        ...clock.start(workout),
        'policy': 'bodytmi-window-clock/2',
      };
      rejects(
        () => clock.apply(
          workout,
          future,
          expectedVersion: 1,
          action: 'resume',
          ownerId: 'epoch',
        ),
      );
      rejects(
        () => clock.apply(
          workout,
          forged,
          expectedVersion: 1,
          action: 'move',
          toOccurrence: 1,
        ),
      );
      final badSample = {
        ...clock.start(workout),
        'status': 'running',
        'ownerId': 'owner',
        'ownerElapsedMilliseconds': 1,
      };
      rejects(
        () => clock.apply(
          workout,
          badSample,
          expectedVersion: 1,
          action: 'recover',
        ),
      );
      final changed = workout.toJson();
      changed['name'] = 'Different workout';
      rejects(
        () => clock.apply(
          WorkoutDefinition.fromJson(changed),
          clock.start(workout),
          expectedVersion: 1,
          action: 'resume',
          ownerId: 'epoch',
        ),
      );
      final request = {
        'schemaVersion': 1,
        'definition': input,
        'action': 'start',
      };
      final cli = await invoke([
        'activity',
        'window-clock',
      ], jsonEncode(request));
      equal(cli.code, 0);
      jsonEqual(
        jsonObject(jsonDecode(cli.output), 'response')['data'],
        clock.start(workout),
      );
      final resumeRequest = {
        'schemaVersion': 1,
        'definition': input,
        'action': 'resume',
        'clock': clock.start(workout),
        'expectedVersion': 1,
        'ownerId': 'cli-epoch',
      };
      final resumed = await invoke([
        'activity',
        'window-clock',
      ], jsonEncode(resumeRequest));
      equal(resumed.code, 0);
      equal(
        jsonObject(
          jsonObject(jsonDecode(resumed.output), 'response')['data'],
          'clock',
        )['status'],
        'running',
      );
    },
  );
  test(
    'window clock recovery applies only explicit bounded elapsed time',
    () async {
      final input = definition().toJson();
      input['plan'] = {
        'id': 'outer',
        'type': 'window',
        'durationSeconds': 5,
        'child': {
          'id': 'inner',
          'type': 'window',
          'durationSeconds': 10,
          'child': {'id': 'set', 'type': 'effort', 'slot': 'bench-heavy'},
        },
      };
      final workout = WorkoutDefinition.fromJson(input);
      const service = WindowClock();
      var clock = service.start(workout);
      clock = service.apply(
        workout,
        clock,
        expectedVersion: 1,
        action: 'resume',
        ownerId: 'epoch',
      );
      clock = service.apply(
        workout,
        clock,
        expectedVersion: 2,
        action: 'advance',
        ownerId: 'epoch',
        ownerElapsedMilliseconds: 3000,
      );
      final frozen = service.apply(
        workout,
        clock,
        expectedVersion: 3,
        action: 'recover',
      );
      equal(frozen['elapsedMilliseconds'], 3000);
      equal(frozen['status'], 'paused');
      final adjusted = service.apply(
        workout,
        clock,
        expectedVersion: 3,
        action: 'recover',
        adjustmentMilliseconds: 1500,
      );
      equal(adjusted['elapsedMilliseconds'], 4500);
      equal(adjusted['status'], 'paused');
      equal(adjusted['ownerId'], null);
      final boundary = service.apply(
        workout,
        clock,
        expectedVersion: 3,
        action: 'recover',
        adjustmentMilliseconds: 9000,
      );
      equal(boundary['status'], 'boundary');
      equal(boundary['elapsedMilliseconds'], 5000);
      equal(jsonObject(boundary['windowStarts'], 'starts')['outer/inner'], 0);
      check(!boundary.containsKey('results'));
      rejects(
        () => service.apply(
          workout,
          clock,
          expectedVersion: 3,
          action: 'recover',
          adjustmentMilliseconds: -1,
        ),
      );
      rejects(
        () => service.apply(
          workout,
          clock,
          expectedVersion: 3,
          action: 'recover',
          adjustmentMilliseconds: 2000000000,
        ),
      );
      rejects(
        () => service.apply(
          workout,
          clock,
          expectedVersion: 3,
          action: 'advance',
          ownerId: 'epoch',
          ownerElapsedMilliseconds: 3001,
          adjustmentMilliseconds: 1,
        ),
      );
      rejects(
        () => service.apply(
          workout,
          frozen,
          expectedVersion: 4,
          action: 'recover',
          adjustmentMilliseconds: 1,
        ),
      );
      final request = {
        'schemaVersion': 1,
        'definition': input,
        'action': 'recover',
        'clock': clock,
        'expectedVersion': 3,
        'adjustmentMilliseconds': 9000,
      };
      jsonEqual(
        const Commands().execute('activity window-clock', request)['data'],
        boundary,
      );
      final cli = await invoke([
        'activity',
        'window-clock',
      ], jsonEncode(request));
      equal(cli.code, 0);
      jsonEqual(
        jsonObject(jsonDecode(cli.output), 'response')['data'],
        boundary,
      );
      request['adjustmentMilliseconds'] = '1';
      final bad = await invoke([
        'activity',
        'window-clock',
      ], jsonEncode(request));
      equal(bad.code, 2);
      equal(bad.output, '');
    },
  );
  test(
    'session window clocks require explicit review before movement',
    () async {
      final input = definition().toJson();
      input['plan'] = {
        'id': 'rounds',
        'type': 'repeat',
        'count': 2,
        'child': {
          'id': 'minute',
          'type': 'window',
          'durationSeconds': 5,
          'child': {'id': 'set', 'type': 'effort', 'slot': 'bench-heavy'},
        },
      };
      final workout = WorkoutDefinition.fromJson(input);
      final revision = WorkoutRevision.publish(workout);
      const training = TrainingService();
      const windows = SessionWindowClock();
      var session = training.start(
        sessionId: 'session',
        revision: revision,
        startedAt: instant(1),
      );
      final original = session.toJson();
      var state = windows.start(session);
      state = windows.apply(
        session,
        state,
        expectedVersion: 1,
        action: 'resume',
        ownerId: 'epoch',
      );
      state = windows.apply(
        session,
        state,
        expectedVersion: 2,
        action: 'advance',
        ownerId: 'epoch',
        ownerElapsedMilliseconds: 6000,
      );
      equal(jsonObject(state['clock'], 'clock')['status'], 'boundary');
      rejects(
        () => windows.apply(
          session,
          state,
          expectedVersion: 3,
          action: 'move',
          toOccurrence: 1,
        ),
      );
      jsonEqual(session.toJson(), original);
      final old = session;
      session = training.complete(
        session,
        session.sets.first.id,
        session.sets.first.suggested,
      );
      state = windows.apply(
        session,
        state,
        expectedVersion: 3,
        action: 'move',
        toOccurrence: 1,
      );
      equal(state['sessionContentVersion'], session.contentVersion);
      rejects(
        () => windows.apply(
          old,
          state,
          expectedVersion: 4,
          action: 'resume',
          ownerId: 'next',
        ),
      );
      final other = training.start(
        sessionId: 'other',
        revision: revision,
        startedAt: instant(1),
      );
      rejects(
        () => windows.apply(
          other,
          state,
          expectedVersion: 4,
          action: 'resume',
          ownerId: 'next',
        ),
      );
      final newer = training.start(
        sessionId: 'session',
        revision: WorkoutRevision.publish(workout, previous: revision),
        startedAt: instant(1),
      );
      rejects(
        () => windows.apply(
          newer,
          windows.start(old),
          expectedVersion: 1,
          action: 'resume',
          ownerId: 'epoch',
        ),
      );
      session = training.skip(session, session.sets.last.id, confirm: true);
      state = windows.apply(
        session,
        state,
        expectedVersion: 4,
        action: 'move',
        toOccurrence: 2,
      );
      equal(jsonObject(state['clock'], 'clock')['status'], 'complete');
      equal(session.sets.last.status, SetStatus.skipped);
      rejects(() => windows.start(session.finish(instant(2))));

      final startRequest = {
        'schemaVersion': 1,
        'session': old.toJson(),
        'action': 'start',
      };
      final pure = const Commands().execute(
        'session window-clock',
        startRequest,
      );
      jsonEqual(pure['data'], windows.start(old));
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-session-window-',
      );
      try {
        final db = '${dir.path}/db.sqlite';
        Future<Map<String, Object?>> command(
          String name,
          Map<String, Object?> request,
        ) async {
          final result = await invoke(
            name.split(' '),
            jsonEncode({'schemaVersion': 1, 'database': db, ...request}),
          );
          equal(result.code, 0);
          return jsonObject(
            jsonObject(jsonDecode(result.output), 'response')['data'],
            'data',
          );
        }

        await command('store publish', {
          'definition': input,
          'expectedRevision': 0,
        });
        await command('store start', {
          'id': 'session',
          'templateId': workout.id,
          'revision': 1,
          'startedAt': instant(1).toIso8601String(),
        });
        final stored = await command('store window-clock', {
          'id': 'session',
          'action': 'start',
        });
        jsonEqual(stored, windows.start(old));
        final resumed = await command('store window-clock', {
          'id': 'session',
          'action': 'resume',
          'clock': stored,
          'expectedVersion': 1,
          'ownerId': 'cli',
        });
        equal(jsonObject(resumed['clock'], 'clock')['status'], 'running');
        final recovered = await command('store window-clock', {
          'id': 'session',
          'action': 'recover',
          'clock': resumed,
          'expectedVersion': 2,
          'adjustmentMilliseconds': 6000,
        });
        equal(jsonObject(recovered['clock'], 'clock')['status'], 'boundary');
        equal(
          jsonObject(recovered['clock'], 'clock')['elapsedMilliseconds'],
          5000,
        );
        final loaded = await command('store show', {'id': 'session'});
        jsonEqual(loaded, old.toJson());
      } finally {
        await dir.delete(recursive: true);
      }
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
