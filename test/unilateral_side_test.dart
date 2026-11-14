import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'cli_test.dart';
import 'fixtures.dart';
import 'support.dart';

Map<String, Object?> _definition({bool flipped = false}) {
  final json = jsonDecode(jsonEncode(example('unilateral-row')['definition']));
  if (flipped) {
    final children =
        (((json as Map)['plan'] as Map)['child'] as Map)['children'] as List;
    json['plan']['child']['children'] = children.reversed.toList();
  }
  return json as Map<String, Object?>;
}

/// Starts a session and completes left sets with [left] and right with [right].
Future<TrainingSession> _finished(
  TrainingStore store,
  String id,
  int day, {
  int revision = 1,
  String left = '12',
  String right = '8',
}) async {
  final service = StoredTrainingService(store);
  final session = await service.start(
    id,
    'unilateral-row',
    revision,
    instant(day),
  );
  return service.edit(id, session.contentVersion, (s) {
    for (final set in s.sets) {
      final side = s.revision.definition.effortSide(set.id);
      s = const TrainingService().complete(s, set.id, {
        'reps': Quantity(side == 'left' ? left : right, 'rep'),
      }, acceptSuggested: true);
    }
    return s.finish(instant(day).add(const Duration(hours: 1)));
  });
}

void unilateralSideTests() {
  test('efforts declare an optional left or right side', () {
    final definition = WorkoutDefinition.fromJson(_definition());
    check(definition.hasEffortSides);
    equal(definition.effortSide('sets[0]/pair/left'), 'left');
    equal(definition.effortSide('sets[1]/pair/right'), 'right');
    equal(definition.effortSide('sets[1]/pair/missing'), null);
    jsonEqual(
      WorkoutDefinition.fromJson(definition.toJson()).toJson(),
      definition.toJson(),
    );
    check(jsonEncode(definition.toJson()).contains('"side":"left"'));
    check(
      !WorkoutDefinition.fromJson(
        example('ordinal-practice')['definition'],
      ).hasEffortSides,
    );
    final both = _definition();
    ((((both['plan'] as Map)['child'] as Map)['children'] as List).first
            as Map)['side'] =
        'both';
    rejects(() => WorkoutDefinition.fromJson(both));
  });

  test('sides keep separate prefill, series, records and summaries', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-side-');
    final store = await TrainingStore.open('${dir.path}/db.sqlite');
    try {
      final service = StoredTrainingService(store);
      await service.publish(WorkoutDefinition.fromJson(_definition()), 0);
      final first = await _finished(store, 's1', 1);
      final second = await service.start('s2', 'unilateral-row', 1, instant(2));
      for (final set in second.sets) {
        final side = second.revision.definition.effortSide(set.id);
        equal(set.suggested['reps']!.enteredValue, side == 'left' ? '12' : '8');
      }
      // Reordering sides keeps each ordinal from borrowing the other side.
      await service.publish(
        WorkoutDefinition.fromJson(_definition(flipped: true)),
        1,
      );
      final flipped = await service.start(
        's3',
        'unilateral-row',
        2,
        instant(3),
      );
      final firstSet = flipped.sets.first;
      equal(flipped.revision.definition.effortSide(firstSet.id), 'right');
      equal(firstSet.suggested['reps']!.enteredValue, '10');
      check(!firstSet.sources.containsKey('reps'));

      final series = const TrainingAnalytics().series([first], metric: 'reps');
      final rows = jsonList(series, 'series');
      equal(rows.length, 2);
      final sides = [
        for (final row in rows)
          jsonObject(jsonObject(row, 'row')['context'], 'context')['side'],
      ]..sort();
      jsonEqual(sides, ['left', 'right']);
      final left = const TrainingAnalytics().series(
        [first],
        metric: 'reps',
        context: {'side': 'left'},
      );
      equal(jsonList(left, 'series').length, 1);
      rejects(
        () => const TrainingAnalytics().series(
          [first],
          context: {'side': 'both'},
        ),
      );
      final records = const ContextualRecords().evaluate(
        [first],
        metric: 'reps',
        direction: 'higher',
        atActuals: {'mass': Quantity('30', 'kg')},
      );
      equal(jsonList(records, 'groups').length, 2);
      final summary = const TrainingAnalytics().summary(first);
      final setSides = [
        for (final set in jsonList(summary, 'sets'))
          jsonObject(set, 'set')['side'],
      ];
      jsonEqual(setSides, ['left', 'right', 'left', 'right']);
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });

  test('sided revisions survive native and logical round trips', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-side-port-');
    var store = await TrainingStore.open('${dir.path}/db.sqlite');
    try {
      await StoredTrainingService(
        store,
      ).publish(WorkoutDefinition.fromJson(_definition()), 0);
      await _finished(store, 'p1', 1);
      final original = canonicalJson((await store.archive()).toJson());
      equal(
        (await store.backup('${dir.path}/native'))['databaseSchemaVersion'],
        1,
      );
      await LogicalArchiveFiles.export(
        await store.archive(),
        '${dir.path}/logical.json',
      );
      final logical = await LogicalArchiveFiles.prepare(
        '${dir.path}/logical.json',
      );
      try {
        await store.restore(
          logical.backup,
          recoveryDestination: '${dir.path}/recovery',
          confirm: true,
        );
      } finally {
        await logical.close();
      }
      await store.close();
      store = await TrainingStore.open('${dir.path}/db.sqlite');
      equal(canonicalJson((await store.archive()).toJson()), original);
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });

  test('CLI series filters one side', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-side-cli-');
    try {
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      await StoredTrainingService(
        store,
      ).publish(WorkoutDefinition.fromJson(_definition()), 0);
      await _finished(store, 'c1', 1);
      await store.close();
      Future<({int code, String output, String error})> series(
        Map<String, Object?> context,
      ) => invoke(
        ['store', 'series'],
        jsonEncode({
          'schemaVersion': 1,
          'database': '${dir.path}/db.sqlite',
          'metric': 'reps',
          'context': context,
        }),
      );
      final ok = await series({'side': 'right'});
      check(ok.code == 0, ok.error);
      check(ok.output.contains('"side":"right"'));
      check(!ok.output.contains('"side":"left"'));
      equal((await series({'side': 'both'})).code, 2);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
