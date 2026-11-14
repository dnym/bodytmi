import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'cli_test.dart';
import 'fixtures.dart';
import 'support.dart';

Map<String, Object?> _json() => copyJson(
  jsonObject(example('categorical-practice')['definition'], 'definition'),
);

Map<String, Object?> _slot(Map<String, Object?> json) =>
    jsonObject(jsonList(json, 'slots').single, 'slot');

Future<BodyTmiException> _failure(Object? Function() action) async {
  try {
    await action();
  } on BodyTmiException catch (error) {
    return error;
  }
  throw StateError('Expected a BodyTmiException.');
}

const _one = 'workout/pull-1', _two = 'workout/pull-2';
Quantity _reps(String v) => Quantity.fromJson({'value': v, 'unit': 'rep'});

/// Completes both sets with explicit reps, optionally records the grip the
/// first set actually used, and finishes the session.
Future<TrainingSession> _session(
  StoredTrainingService training,
  String id,
  int day, {
  required String first,
  required String second,
  String? performedFirst,
}) async {
  var s = await training.start(id, 'pull-grips', 1, instant(day));
  s = await training.edit(id, s.contentVersion, (s) {
    s = const TrainingService().complete(s, _one, {'reps': _reps(first)});
    s = const TrainingService().complete(s, _two, {'reps': _reps(second)});
    if (performedFirst != null)
      s = const TrainingService().recordSettings(s, _one, {
        'grip': performedFirst,
      });
    return s.finish(instant(day).add(const Duration(hours: 1)));
  });
  return s;
}

void categoricalTests() {
  test('categorical levers validate values, defaults and effort settings', () {
    final definition = WorkoutDefinition.fromJson(_json());
    jsonEqual(
      WorkoutDefinition.fromJson(definition.toJson()).toJson(),
      definition.toJson(),
    );
    jsonEqual(definition.plannedSettings(_one), {'grip': 'overhand'});
    jsonEqual(definition.plannedSettings(_two), {'grip': 'underhand'});
    Map<String, Object?> withLever(Object? lever) {
      final json = _json();
      _slot(json)['categories'] = {'grip': lever};
      return json;
    }

    for (final lever in [
      {
        'values': ['overhand'],
        'default': 'overhand',
      },
      {
        'values': ['overhand', 'overhand'],
        'default': 'overhand',
      },
      {
        'values': ['overhand', 'underhand'],
        'default': 'mixed',
      },
      {
        'values': ['overhand', 'under hand'],
        'default': 'overhand',
      },
    ]) {
      rejects(() => WorkoutDefinition.fromJson(withLever(lever)));
    }
    Map<String, Object?> withEffortSettings(Object? settings) {
      final json = _json();
      final plan = jsonObject(json['plan'], 'plan');
      jsonObject(jsonList(plan, 'children')[1], 'effort')['settings'] =
          settings;
      return json;
    }

    rejects(
      () => WorkoutDefinition.fromJson(withEffortSettings({'grip': 'x'})),
    );
    rejects(
      () => WorkoutDefinition.fromJson(withEffortSettings({'hands': 'one'})),
    );
    rejects(() => WorkoutDefinition.fromJson(withEffortSettings({})));
    // Without declared levers an effort cannot set anything.
    final bare = _json();
    _slot(bare).remove('categories');
    rejects(() => WorkoutDefinition.fromJson(bare));
  });

  test('performed settings separate prefill, series and progression', () {
    return () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-categorical-');
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final training = StoredTrainingService(store);
        await training.publish(WorkoutDefinition.fromJson(_json()), 0);
        // Session 1 did its first set neutral instead of overhand.
        final first = await _session(
          training,
          'a',
          1,
          first: '10',
          second: '9',
          performedFirst: 'neutral',
        );
        jsonEqual(first.set(_one).actualSettings, {'grip': 'neutral'});
        jsonEqual(first.set(_one).performedSettings, {'grip': 'neutral'});
        // Prefill: overhand did not happen, underhand did.
        final next = await training.start('b', 'pull-grips', 1, instant(2));
        jsonEqual(next.set(_one).settings, {'grip': 'overhand'});
        equal(next.set(_one).suggested['reps']!.enteredValue, '8');
        equal(next.set(_one).sources.isEmpty, true);
        equal(next.set(_two).suggested['reps']!.enteredValue, '9');
        equal(next.set(_two).sources['reps']!.sessionId, 'a');

        // Series keep performed settings apart and can filter on them.
        final sessions = [await training.session('a')];
        final series = const TrainingAnalytics().series(
          sessions,
          metric: 'reps',
        );
        final contexts = [
          for (final row in jsonList(series, 'series'))
            jsonObject(
              jsonObject(row, 'row')['context'],
              'context',
            )['settings'],
        ];
        equal(contexts.length, 2);
        final neutral = const TrainingAnalytics().series(
          sessions,
          metric: 'reps',
          context: {
            'settings': {'grip': 'neutral'},
          },
        );
        equal(jsonList(neutral, 'series').length, 1);
        rejects(
          () => const TrainingAnalytics().series(
            sessions,
            context: {'settings': <String, Object?>{}},
          ),
        );

        // A changed setting is not an exposure of the planned prescription.
        final progression = StoredProgressionService(store);
        final threshold = {
          'metric': 'reps',
          'minimum': {'value': '6', 'unit': 'rep'},
          'threshold': {'value': '9', 'unit': 'rep'},
          'increments': {
            'reps': {'value': '1', 'unit': 'rep'},
          },
        };
        final held = await progression.propose(
          'a',
          'pull',
          threshold,
          ruleType: 'threshold',
        );
        equal(held.proposal.outcome, 'review');
        equal(
          (await _failure(
            () => progression.accept('a', 'pull', held.version, instant(3)),
          )).code,
          'validation',
        );
        // Clearing the record restores an ordinary exposure.
        await _session(training, 'c', 4, first: '9', second: '9');
        final ordinary = await progression.propose(
          'c',
          'pull',
          threshold,
          ruleType: 'threshold',
        );
        check(ordinary.proposal.outcome != 'review', ordinary.proposal.reason);

        // Recording validates status, levers and values; skip drops it.
        final c = await training.start('d', 'pull-grips', 1, instant(5));
        rejects(
          () => const TrainingService().recordSettings(c, _one, {
            'grip': 'neutral',
          }),
        );
        final done = const TrainingService().complete(c, _one, {
          'reps': _reps('8'),
        });
        rejects(
          () => const TrainingService().recordSettings(done, _one, {
            'grip': 'mixed',
          }),
        );
        rejects(
          () => const TrainingService().recordSettings(done, _one, {
            'hands': 'one',
          }),
        );
        final recorded = const TrainingService().recordSettings(done, _one, {
          'grip': 'neutral',
        });
        final same = const TrainingService().recordSettings(recorded, _one, {
          'grip': 'overhand',
        });
        equal(same.set(_one).actualSettings.isEmpty, true);
        equal(
          recorded.set(_one).skip(confirm: true).actualSettings.isEmpty,
          true,
        );

        // The codec rejects forged levers or values and round-trips records.
        final json = jsonObject(
          jsonDecode(jsonEncode((await training.session('a')).toJson())),
          's',
        );
        jsonEqual(sessionFromJson(json).toJson(), json);
        Map<String, Object?> forge(void Function(Map<String, Object?>) f) {
          final copy = jsonObject(jsonDecode(jsonEncode(json)), 'c');
          f(jsonObject(jsonList(copy, 'sets')[0], 'set'));
          return copy;
        }

        rejects(
          () => sessionFromJson(forge((s) => s['settings'] = {'grip': 'x'})),
        );
        rejects(() => sessionFromJson(forge((s) => s.remove('settings'))));
        rejects(
          () => sessionFromJson(
            forge((s) => s['actualSettings'] = {'grip': 'overhand'}),
          ),
        );
        // Archives and backups carry the records.
        TrainingArchive.fromJson((await store.archive()).toJson());
        await store.backup('${dir.path}/native');
        await NativeBackup.validateDatabase(
          '${dir.path}/native/database.sqlite',
        );
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    }();
  });

  test('CLI set-settings records performed categorical values', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-cat-cli-');
    try {
      final database = '${dir.path}/db.sqlite';
      Future<({int code, String output, String error})> cmd(
        String action,
        Map<String, Object?> input,
      ) => invoke(
        action.split(' '),
        jsonEncode({'schemaVersion': 1, 'database': database, ...input}),
      );
      Map<String, Object?> data(({int code, String output, String error}) r) {
        check(r.code == 0, r.error);
        return jsonObject(jsonObject(jsonDecode(r.output), 'r')['data'], 'd');
      }

      data(
        await cmd('store publish', {
          ...example('categorical-practice'),
          'database': database,
        }),
      );
      var s = data(
        await cmd('store start', {
          'id': 's1',
          'templateId': 'pull-grips',
          'revision': 1,
          'startedAt': '2026-11-14T10:00:00Z',
        }),
      );
      for (final setId in [_one, _two]) {
        s = data(
          await cmd('store complete', {
            'id': 's1',
            'expectedVersion': s['contentVersion'],
            'setId': setId,
            'acceptSuggested': true,
          }),
        );
      }
      equal(s['contentVersion'], 3);
      final recorded = data(
        await cmd('store set-settings', {
          ...example('set-settings'),
          'database': database,
        }),
      );
      final set = jsonObject(jsonList(recorded, 'sets')[0], 'set');
      jsonEqual(set['actualSettings'], {'grip': 'neutral'});
      equal(
        (await cmd('store set-settings', {
          'id': 's1',
          'expectedVersion': recorded['contentVersion'],
          'setId': _one,
          'settings': {'grip': 'mixed'},
        })).code,
        2,
      );
      equal(
        (await cmd('store set-settings', {
          'id': 's1',
          'expectedVersion': 1,
          'setId': _one,
          'settings': <String, Object?>{},
        })).code,
        5,
      );
      final pure = await invoke(
        ['session', 'set-settings'],
        jsonEncode({
          'schemaVersion': 1,
          'session': recorded,
          'setId': _one,
          'settings': <String, Object?>{},
        }),
      );
      final cleared = data(pure);
      check(
        !jsonObject(
          jsonList(cleared, 'sets')[0],
          'set',
        ).containsKey('actualSettings'),
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
