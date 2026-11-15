import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'cli_test.dart';
import 'fixtures.dart';
import 'support.dart';

Map<String, Object?> _definition() => copyJson(
  jsonObject(example('structures-practice')['definition'], 'definition'),
);

/// Section 24 activity acceptance: one workout with a superset, a drop set, a
/// circuit, a cluster and rest-pause, walked through the native CLI with
/// explicit results, neutral rest skips, bout counting and role-separated
/// progression.
void structuresTraceTests() {
  test('validates parent bouts and keeps them single-counted', () {
    final definition = WorkoutDefinition.fromJson(_definition());
    jsonEqual(
      WorkoutDefinition.fromJson(definition.toJson()).toJson(),
      definition.toJson(),
    );
    final bouts = boutGroups(definition.plan);
    jsonEqual(
      [for (final b in bouts) b.path],
      ['workout/drop-set', 'workout/cluster', 'workout/rest-pause'],
    );
    jsonEqual(bouts[1].efforts, [
      'workout/cluster[0]/cluster-pull',
      'workout/cluster[1]/cluster-pull',
      'workout/cluster[2]/cluster-pull',
    ]);
    Map<String, Object?> child(Map<String, Object?> json, int index) =>
        jsonObject(
          jsonList(jsonObject(json['plan'], 'plan'), 'children')[index],
          'child',
        );
    final nested = _definition();
    jsonObject(jsonList(child(nested, 1), 'children')[0], 'top').addAll({
      'type': 'sequence',
      'bout': true,
      'children': [
        {'id': 'x', 'type': 'effort', 'slot': 'bench'},
        {'id': 'y', 'type': 'effort', 'slot': 'bench'},
      ],
    });
    jsonObject(jsonList(child(nested, 1), 'children')[0], 'top')
      ..remove('slot');
    rejects(() => WorkoutDefinition.fromJson(nested));
    final single = _definition();
    final rest = child(single, 4);
    rest['children'] = [jsonList(rest, 'children').first];
    rejects(() => WorkoutDefinition.fromJson(single));
    final notTrue = _definition();
    child(notTrue, 3)['bout'] = false;
    rejects(() => WorkoutDefinition.fromJson(notTrue));
  });

  test('native CLI walks superset, drop set, circuit, cluster and '
      'rest-pause with bout counts and role-separated progression', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-structures-');
    final path = '${dir.path}/db.sqlite';
    try {
      Future<Map<String, Object?>> call(
        String name,
        Map<String, Object?> fields,
      ) async {
        final response = await invoke(
          name.split(' '),
          jsonEncode({'schemaVersion': 1, 'database': path, ...fields}),
        );
        if (response.code != 0)
          throw StateError('$name failed: ${response.error}');
        return jsonObject(
          jsonObject(jsonDecode(response.output), 'response')['data'],
          'data',
        );
      }

      await call('store publish', {
        'definition': _definition(),
        'expectedRevision': 0,
      });
      Future<void> walk(String sessionId, int day) async {
        await call('store start', {
          'id': sessionId,
          'templateId': 'structures',
          'revision': 1,
          'startedAt': instant(day).toIso8601String(),
        });
        var view = await call('execution start', {
          'id': 'ex-$sessionId',
          'sessionId': sessionId,
          'at': instant(day).toIso8601String(),
        });
        final dips = ['9', '4', '2'];
        var step = 0;
        while (view['status'] != 'completed') {
          final current = jsonObject(view['current'], 'current');
          final id = current['id'] as String;
          final request = {
            'id': 'ex-$sessionId',
            'expectedVersion': view['version'],
            'expectedSessionVersion': view['sessionContentVersion'],
            'requestId': 'r${step++}',
            'at': instant(day).toIso8601String(),
          };
          if (current['kind'] == 'rest') {
            view = await call('execution skip', {...request, 'confirm': true});
          } else if (id == 'workout/cluster[2]/cluster-pull') {
            // Grip gave out: the last cluster segment is skipped.
            view = await call('execution skip', {...request, 'confirm': true});
          } else if (id.startsWith('workout/rest-pause/')) {
            view = await call('execution complete', {
              ...request,
              'actuals': {
                'reps': {'value': dips.removeAt(0), 'unit': 'rep'},
              },
            });
          } else {
            view = await call('execution complete', {
              ...request,
              'acceptSuggested': true,
            });
          }
        }
        final session = await call('store show', {'id': sessionId});
        await call('store finish', {
          'id': sessionId,
          'expectedVersion': session['contentVersion'],
          'finishedAt': instant(
            day,
          ).add(const Duration(hours: 1)).toIso8601String(),
        });
      }

      await walk('w1', 1);
      final summary = await call('store summary', {'id': 'w1'});
      final counts = jsonObject(summary['counts'], 'counts');
      // 19 efforts are sets; bouts are a separate metric, never extra sets.
      equal(counts['included'], 19);
      equal(counts['completed'], 18);
      equal(counts['skipped'], 1);
      jsonEqual(counts['bouts'], {
        'total': 3,
        'planned': 0,
        'completed': 2,
        'skipped': 0,
        'partial': 1,
      });
      final bouts = jsonList(summary, 'bouts');
      equal(jsonObject(bouts[1], 'cluster')['status'], 'partial');
      equal(jsonList(jsonObject(bouts[0], 'drop'), 'sets').length, 3);
      equal(
        jsonObject(summary['policy'], 'policy')['boutPolicy'],
        'bodytmi-bout-count/1',
      );

      // Work and drop segments of the bench stay separate series contexts.
      final series = await call('store series', {
        'metric': 'load',
        'roles': ['work', 'drop'],
        'context': {'slotId': 'bench'},
      });
      final roles = {
        for (final row in jsonList(series, 'series'))
          jsonObject(jsonObject(row, 'row')['context'], 'c')['role'],
      };
      jsonEqual(roles.toList()..sort(), ['drop', 'work']);

      // Progression sees the four bench work sets only (three superset
      // presses and the drop-set top set), never the drop segments.
      final proposal = await call('progression propose', {
        'sessionId': 'w1',
        'slotId': 'bench',
        'ruleType': 'threshold',
        'rule': {
          'metric': 'reps',
          'minimum': {'value': '8', 'unit': 'rep'},
          'threshold': {'value': '8', 'unit': 'rep'},
          'increments': {
            'load': {'value': '2.5', 'unit': 'kg'},
          },
        },
      });
      final decision = jsonObject(proposal['decision'] ?? proposal, 'd');
      final evaluated = jsonObject(decision['proposal'], 'proposal');
      equal(evaluated['outcome'], 'advance');
      equal(jsonList(evaluated, 'nextSets').length, 4);
      await call('progression accept', {
        'sessionId': 'w1',
        'slotId': 'bench',
        'expectedVersion': decision['version'],
        'acceptedAt': instant(
          1,
        ).add(const Duration(hours: 2)).toIso8601String(),
      });
      final next = await call('store start', {
        'id': 'w2',
        'templateId': 'structures',
        'revision': 1,
        'startedAt': instant(3).toIso8601String(),
      });
      final bench = {
        for (final set in jsonList(next, 'sets'))
          if (jsonObject(set, 's')['slot'] == 'bench')
            jsonObject(set, 's')['id']: jsonObject(
              jsonObject(jsonObject(set, 's')['suggested'], 'sg')['load'],
              'l',
            )['value'],
      };
      jsonEqual(bench, {
        'workout/superset[0]/pair/press': '62.5',
        'workout/superset[1]/pair/press': '62.5',
        'workout/superset[2]/pair/press': '62.5',
        'workout/drop-set/top': '62.5',
        'workout/drop-set/drop-1': '45',
        'workout/drop-set/drop-2': '30',
      });
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
