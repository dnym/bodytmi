import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'cli_test.dart';
import 'fixtures.dart';
import 'support.dart';

Map<String, Object?> _q(String value, String unit) => {
  'value': value,
  'unit': unit,
};

const _catalog = [
  ('push-up', [('floor-push-up', 'Floor push-up')]),
  (
    'row',
    [
      ('barbell-row', 'Barbell row'),
      ('cable-row', 'Seated cable row'),
      ('dumbbell-row', 'One-arm dumbbell row'),
    ],
  ),
  ('dead-hang', [('bar-hang', 'Bar hang')]),
  ('farmer-carry', [('dumbbell-carry', 'Dumbbell carry')]),
  ('hip-mobility', [('floor-flow', 'Floor hip flow')]),
  // Ungrouped custom exercise with a custom metric: in no family.
  ('sled-drag', [('backward-drag', 'Backward sled drag')]),
];

Map<String, Object?> _slot(
  String id,
  String exercise,
  String implementation,
  Map<String, Object?> targets,
) => {
  'id': id,
  'exercise': exercise,
  'implementation': implementation,
  'targets': targets,
};

Map<String, Object?> _workout() => {
  'id': 'catalog-day',
  'name': 'Catalog acceptance day',
  'slots': [
    _slot('pushups', 'push-up', 'floor-push-up', {'reps': _q('15', 'rep')}),
    _slot('barbell', 'row', 'barbell-row', {
      'load': _q('60', 'kg'),
      'reps': _q('8', 'rep'),
    }),
    _slot('cable', 'row', 'cable-row', {
      'load': _q('40', 'kg'),
      'reps': _q('12', 'rep'),
    }),
    _slot('dumbbell', 'row', 'dumbbell-row', {
      'load': _q('25', 'kg'),
      'reps': _q('10', 'rep'),
    }),
    _slot('hang', 'dead-hang', 'bar-hang', {'duration': _q('30', 's')}),
    _slot('carry', 'farmer-carry', 'dumbbell-carry', {
      'load': _q('24', 'kg'),
      'distance': _q('40', 'm'),
    }),
    _slot('mobility', 'hip-mobility', 'floor-flow', <String, Object?>{}),
    _slot('sled', 'sled-drag', 'backward-drag', {
      'load': _q('80', 'kg'),
      'laps': _q('4', 'rep'),
    }),
  ],
  'plan': {
    'id': 'day',
    'type': 'sequence',
    'children': [
      for (final slot in [
        'pushups',
        'barbell',
        'cable',
        'dumbbell',
        'hang',
        'carry',
        'sled',
      ])
        {'id': slot, 'type': 'effort', 'slot': slot},
      {
        'id': 'mobility',
        'type': 'effort',
        'slot': 'mobility',
        'objectives': {
          'duration': {'mode': 'observe', 'unit': 's'},
        },
      },
    ],
  },
};

/// Section 24 catalog/composition acceptance.
void catalogAcceptanceTests() {
  test('domain and adapter code holds no exercise-name special cases', () {
    final names = RegExp(
      "'(bench(-press)?|squat|deadlift|push-?up|pull-?up|chin-?up|plank|"
      "curl|overhead-press|dip|lunge|(farmer-)?carry|(dead-)?hang|rowing|"
      "barbell-row|cable-row|dumbbell-row)'",
    );
    for (final root in [
      'packages/bodytmi_core/lib',
      'packages/bodytmi_application/lib',
      'packages/bodytmi_storage/lib',
      'lib',
      'bin',
    ]) {
      for (final file in Directory(
        root,
      ).listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        // Invented sample content for the GUI, like examples/: data, not
        // behaviour keyed on a name.
        if (file.path.endsWith('demo_profile.dart')) continue;
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          check(
            !names.hasMatch(lines[i]),
            '${file.path}:${i + 1} names an exercise: ${lines[i].trim()}',
          );
        }
      }
    }
  });

  test('native CLI authors push-ups, three rows, a hang, a carry, a '
      'mobility drill and an ungrouped custom exercise', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-catalog-');
    final path = '${dir.path}/db.sqlite';
    try {
      Future<({int code, Map<String, Object?>? data})> cli(
        String name,
        Map<String, Object?> fields,
      ) async {
        final response = await invoke(
          name.split(' '),
          jsonEncode({'schemaVersion': 1, 'database': path, ...fields}),
        );
        return (
          code: response.code,
          data: response.code == 0
              ? jsonObject(
                  jsonObject(jsonDecode(response.output), 'response')['data'],
                  'data',
                )
              : null,
        );
      }

      Future<Map<String, Object?>> ok(
        String name,
        Map<String, Object?> fields,
      ) async {
        final result = await cli(name, fields);
        equal(result.code, 0);
        return result.data!;
      }

      // Before the catalog exists, strict adoption names the missing entry.
      equal(
        (await cli('store publish', {
          'definition': _workout(),
          'expectedRevision': 0,
          'requireCatalog': true,
        })).code,
        3,
      );
      for (final (exercise, implementations) in _catalog) {
        await ok('exercise publish', {
          'exercise': {'id': exercise, 'name': exercise},
          'expectedRevision': 0,
        });
        for (final (id, name) in implementations) {
          await ok('implementation publish', {
            'implementation': {'id': id, 'exerciseId': exercise, 'name': name},
            'expectedRevision': 0,
          });
        }
      }
      await ok('family publish', {
        'family': {
          'id': 'pulling',
          'name': 'Horizontal pulling',
          'exercises': ['row'],
        },
        'expectedRevision': 0,
      });
      await ok('store publish', {
        'definition': _workout(),
        'expectedRevision': 0,
        'requireCatalog': true,
      });
      var session = await ok('store start', {
        'id': 'day-1',
        'templateId': 'catalog-day',
        'revision': 1,
        'startedAt': instant(1).toIso8601String(),
      });
      final actuals = <String, Map<String, Object?>>{
        'day/pushups': {'reps': _q('14', 'rep')},
        'day/barbell': {'load': _q('60', 'kg'), 'reps': _q('8', 'rep')},
        'day/cable': {'load': _q('40', 'kg'), 'reps': _q('12', 'rep')},
        'day/dumbbell': {'load': _q('25', 'kg'), 'reps': _q('10', 'rep')},
        'day/hang': {'duration': _q('34', 's')},
        'day/carry': {'load': _q('24', 'kg'), 'distance': _q('40', 'm')},
        'day/sled': {'load': _q('80', 'kg'), 'laps': _q('5', 'rep')},
        'day/mobility': {'duration': _q('95', 's')},
      };
      var version = session['contentVersion'];
      for (final entry in actuals.entries) {
        final done = await ok('store complete', {
          'id': 'day-1',
          'expectedVersion': version,
          'setId': entry.key,
          'actuals': entry.value,
        });
        version = done['sessionContentVersion'] ?? done['contentVersion'];
      }
      await ok('store finish', {
        'id': 'day-1',
        'expectedVersion': version,
        'finishedAt': instant(
          1,
        ).add(const Duration(hours: 1)).toIso8601String(),
      });

      // The family groups three row implementations as separate series;
      // the ungrouped custom exercise keeps its own custom-metric series.
      final family = await ok('store series', {
        'metric': 'load',
        'familyId': 'pulling',
      });
      final implementations = [
        for (final row in jsonList(family, 'series'))
          jsonObject(
            jsonObject(row, 'row')['context'],
            'context',
          )['implementation'],
      ]..sort();
      jsonEqual(implementations, ['barbell-row', 'cable-row', 'dumbbell-row']);
      final laps = await ok('store series', {'metric': 'laps'});
      final lapRows = jsonList(laps, 'series');
      equal(lapRows.length, 1);
      equal(
        jsonObject(
          jsonObject(lapRows.single, 'row')['context'],
          'context',
        )['exercise'],
        'sled-drag',
      );
      final summary = await ok('store summary', {
        'id': 'day-1',
        'sumMetrics': ['distance', 'duration', 'laps'],
      });
      final totals = {
        for (final t in jsonList(summary, 'totals'))
          jsonObject(t, 't')['metric']: jsonObject(t, 't')['value'],
      };
      equal(totals['distance'], '40');
      equal(totals['duration'], '129');
      equal(totals['laps'], '5');
      final search = await ok('catalog search', {'query': 'row'});
      check(
        jsonList(search, 'results').length >= 4,
        'Row search should find the exercise and its implementations.',
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
