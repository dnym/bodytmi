import 'dart:convert';
import 'dart:io';
import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'fixtures.dart';
import 'support.dart';

Object? at(Object? json, List<Object> path) {
  var current = json;
  for (final key in path) {
    if (current is Map) {
      current = current[key];
    } else {
      return null;
    }
  }
  return current;
}

/// Workout slots that name their progression preset: publication checks
/// the pinned revision, propose needs no rule, blueprints fill revisions.
void slotPresetTests() {
  test('a slot-pinned preset is checked and used by propose', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-slotpreset-');
    final db = '${dir.path}/db.sqlite';
    Future<Object?> run(String command, Map<String, Object?> fields) async =>
        (await executeCommand(command, {
          'schemaVersion': 1,
          'database': db,
          ...fields,
        }))['data'];
    Future<BodyTmiException> fails(
      String command,
      Map<String, Object?> fields,
    ) async {
      try {
        await run(command, fields);
      } on BodyTmiException catch (e) {
        return e;
      }
      throw StateError('$command should fail');
    }

    try {
      final preset = example('progression-preset');
      await run('preset publish', {
        'preset': preset['preset'],
        'expectedRevision': 0,
      });
      Map<String, Object?> workout(int presetRevision) {
        final d = copyJson(
          jsonObject(example('upper-a')['definition'], 'definition'),
        );
        final slots = (d['slots']! as List).cast<Map<String, Object?>>();
        slots.first['progression'] = {
          'preset': {'id': 'double-8-12', 'revision': presetRevision},
        };
        return d;
      }

      final missing = await fails('store publish', {
        'definition': workout(2),
        'expectedRevision': 0,
      });
      equal(missing.code, 'not_found');
      check(
        missing.message.contains('double-8-12 revision 2'),
        missing.message,
      );
      rejects(
        () => WorkoutDefinition.fromJson({
          ...workout(1),
          'slots': [
            {
              ...(workout(1)['slots']! as List).first as Map<String, Object?>,
              'progression': {
                'preset': {'id': 'double-8-12', 'revision': 0},
              },
            },
          ],
        }),
      );
      await run('store publish', {
        'definition': workout(1),
        'expectedRevision': 0,
      });
      final shown = await run('store revision', {
        'templateId': 'upper-a',
        'revision': 1,
      });
      jsonEqual(
        ((at(shown, ['definition', 'slots']) as List).first
            as Map)['progression'],
        {
          'preset': {'id': 'double-8-12', 'revision': 1},
        },
      );

      var session =
          await run('store start', {
                'id': 's1',
                'templateId': 'upper-a',
                'revision': 1,
                'startedAt': '2026-10-01T12:00:00Z',
              })
              as Map<String, Object?>;
      for (final set
          in (session['sets']! as List).cast<Map<String, Object?>>()) {
        session =
            await run('store complete', {
                  'id': 's1',
                  'expectedVersion': session['contentVersion'],
                  'setId': set['id'],
                  'acceptSuggested': true,
                })
                as Map<String, Object?>;
      }
      await run('store finish', {
        'id': 's1',
        'expectedVersion': session['contentVersion'],
        'finishedAt': '2026-10-01T13:00:00Z',
      });
      final decision = await run('progression propose', {
        'sessionId': 's1',
        'slotId': 'bench-heavy',
      });
      jsonEqual(at(decision, ['preset']), {'id': 'double-8-12', 'revision': 1});
      final unbound = await fails('progression propose', {
        'sessionId': 's1',
        'slotId': 'bench-light',
      });
      equal(unbound.code, 'validation');
      check(
        unbound.message.contains('names no progression preset'),
        unbound.message,
      );

      // Portability keeps and checks the slot pins.
      await run('archive export', {'destination': '${dir.path}/a.json'});
      await executeCommand('archive validate', {
        'schemaVersion': 1,
        'source': '${dir.path}/a.json',
      });
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('GZCLP slots pin the tier presets of their instance', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-gzslots-');
    final db = '${dir.path}/db.sqlite';
    Future<Object?> run(String command, Map<String, Object?> fields) async =>
        (await executeCommand(command, {
          'schemaVersion': 1,
          'database': db,
          ...fields,
        }))['data'];
    try {
      await run('catalog apply', {
        'document': jsonDecode(
          File('data/starter-catalog.json').readAsStringSync(),
        ),
        'confirm': true,
      });
      await run('blueprint instantiate', {
        'blueprintId': 'gzclp',
        'revision': 1,
        'name': 'gz',
        'choices': {
          'pulldown-start': {'value': '30', 'unit': 'kg'},
          'row-start': {'value': '16', 'unit': 'kg'},
        },
        'expectedInstance': 0,
      });
      Future<Map<String, Object?>> pins(String workout) async {
        final r = await run('store revision', {
          'templateId': 'gz-$workout',
          'revision': 1,
        });
        return {
          for (final s
              in (at(r, ['definition', 'slots']) as List)
                  .cast<Map<String, Object?>>())
            '${s['id']}': at(s, ['progression', 'preset']),
        };
      }

      jsonEqual(await pins('a1'), {
        't1': {'id': 'gz-t1-lower', 'revision': 1},
        't2': {'id': 'gz-t2-upper', 'revision': 1},
        't3': {'id': 'gz-t3', 'revision': 1},
      });
      jsonEqual(await pins('b1'), {
        't1': {'id': 'gz-t1-upper', 'revision': 1},
        't2': {'id': 'gz-t2-lower', 'revision': 1},
        't3': {'id': 'gz-t3', 'revision': 1},
      });
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
