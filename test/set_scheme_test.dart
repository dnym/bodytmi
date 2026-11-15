import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'cli_test.dart';
import 'fixtures.dart';
import 'support.dart';

Map<String, Object?> _json() => copyJson(
  jsonObject(example('set-scheme-practice')['definition'], 'definition'),
);

Map<String, Object?> _variant(Map<String, Object?> json) => jsonObject(
  jsonList(jsonObject(json['plan'], 'plan'), 'children').single,
  'variant',
);

Quantity _q(String value, String unit) =>
    Quantity.fromJson({'value': value, 'unit': unit});

Future<BodyTmiException> _failure(Object? Function() action) async {
  try {
    await action();
  } on BodyTmiException catch (error) {
    return error;
  }
  throw StateError('Expected a BodyTmiException.');
}

/// Completes every set at its suggested load with [reps] and finishes.
Future<TrainingSession> _finish(
  StoredTrainingService training,
  TrainingSession s,
  String reps,
  int day,
) => training.edit(s.id, s.contentVersion, (s) {
  for (final set in s.sets) {
    s = const TrainingService().complete(s, set.id, {
      'load': set.suggested['load']!,
      'reps': _q(reps, 'rep'),
    });
  }
  return s.finish(instant(day).add(const Duration(hours: 1)));
});

Map<String, Object?> _threshold(String reps) => {
  'metric': 'reps',
  'minimum': {'value': reps, 'unit': 'rep'},
  'threshold': {'value': reps, 'unit': 'rep'},
  'increments': {
    'load': {'value': '2.5', 'unit': 'kg'},
  },
};

const _ladder = {
  'metric': 'reps',
  'performance': {
    'direction': 'higher',
    'failureLimit': {'value': '0', 'unit': 'rep'},
    'advancementLimit': {'value': '1', 'unit': 'rep'},
  },
  'levels': [
    {
      'id': 'five-triples',
      'settings': {'scheme': 'triples'},
    },
    {
      'id': 'six-doubles',
      'settings': {'scheme': 'doubles'},
    },
    {
      'id': 'ten-singles',
      'settings': {'scheme': 'singles'},
    },
  ],
};

void setSchemeTests() {
  test('variants validate branches and resolve one set structure', () {
    final definition = WorkoutDefinition.fromJson(_json());
    jsonEqual(
      WorkoutDefinition.fromJson(definition.toJson()).toJson(),
      definition.toJson(),
    );
    equal(definition.hasVariants, true);
    jsonEqual(definition.variantLevers('squat').toList(), ['scheme']);
    jsonEqual(definition.variantSelections(), {'scheme': 'triples'});
    // Structural lookups see every branch with the branch value imposed.
    jsonEqual(definition.plannedSettings('workout/doubles[5]/double'), {
      'scheme': 'doubles',
    });
    rejects(() => definition.plan.occurrences().toList());
    rejects(() => definition.roleTargets('squat', 'work'));
    for (final (scheme, count, reps) in [
      ('triples', 5, '3'),
      ('doubles', 6, '2'),
      ('singles', 10, '1'),
    ]) {
      final resolved = definition.resolveVariants({'scheme': scheme});
      final targets = resolved.workingTargets('squat');
      equal(targets.length, count);
      equal(targets.first['reps']!.enteredValue, reps);
      equal(targets.first['load']!.enteredValue, '60');
      final first = resolved.plan.occurrences().first.id;
      jsonEqual(resolved.plannedSettings(first), {'scheme': scheme});
    }
    rejects(() => definition.resolveVariants({}));
    rejects(() => definition.resolveVariants({'scheme': 'quads'}));
    rejects(
      () => definition.resolveVariants({'scheme': 'triples', 'other': 'x'}),
    );

    // Branches cover exactly the lever's values.
    final missing = _json();
    jsonObject(_variant(missing)['branches'], 'branches').remove('singles');
    rejects(() => WorkoutDefinition.fromJson(missing));
    final undeclared = _json();
    _variant(undeclared)['lever'] = 'grip';
    rejects(() => WorkoutDefinition.fromJson(undeclared));
    final unknownSlot = _json();
    _variant(unknownSlot)['slot'] = 'bench';
    rejects(() => WorkoutDefinition.fromJson(unknownSlot));
    // An effort cannot contradict its enclosing branch.
    final contradicting = _json();
    final triples = jsonObject(
      jsonObject(_variant(contradicting)['branches'], 'branches')['triples'],
      'triples',
    );
    jsonObject(triples['child'], 'child')['settings'] = {'scheme': 'doubles'};
    rejects(() => WorkoutDefinition.fromJson(contradicting));
    final restOnly = _json();
    jsonObject(_variant(restOnly)['branches'], 'branches')['singles'] = {
      'id': 'nothing',
      'type': 'rest',
      'durationSeconds': 60,
    };
    rejects(() => WorkoutDefinition.fromJson(restOnly));

    // A session freezes its selection; the codec rejects forged choices.
    final revision = WorkoutRevision.publish(definition);
    final session = const TrainingService().start(
      sessionId: 'pure',
      revision: revision,
      startedAt: instant(1),
      variantSelections: {'scheme': 'doubles'},
    );
    equal(session.sets.length, 6);
    jsonEqual(session.toJson()['variantSelections'], {'scheme': 'doubles'});
    jsonEqual(sessionFromJson(session.toJson()).toJson(), session.toJson());
    final forged = copyJson(session.toJson());
    forged['variantSelections'] = {'scheme': 'triples'};
    rejects(() => sessionFromJson(forged));
    final dropped = copyJson(session.toJson())..remove('variantSelections');
    rejects(() => sessionFromJson(dropped));
  });

  test('a uniform controlled load follows a manual structure change', () {
    return () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-scheme-');
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final training = StoredTrainingService(store);
        final progression = StoredProgressionService(store);
        await training.publish(WorkoutDefinition.fromJson(_json()), 0);
        var s1 = await training.start('s1', 'squat-schemes', 1, instant(1));
        equal(s1.sets.length, 5);
        jsonEqual(s1.variantSelections, {'scheme': 'triples'});
        s1 = await _finish(training, s1, '3', 1);
        final p1 = await progression.propose(
          's1',
          'squat',
          _threshold('1'),
          ruleType: 'threshold',
        );
        equal(p1.proposal.outcome, 'advance');
        await progression.accept('s1', 'squat', p1.version, instant(2));

        // The scheme lever is not progression-controlled here: an explicit
        // choice selects six doubles and the uniform load broadcasts.
        final request = {
          'squat': {'scheme': 'doubles'},
        };
        var s2 = await training.start(
          's2',
          'squat-schemes',
          1,
          instant(3),
          variantSettings: request,
        );
        equal(s2.sets.length, 6);
        jsonEqual(s2.variantSelections, {'scheme': 'doubles'});
        for (final set in s2.sets) {
          equal(set.suggested['load']!.enteredValue, '62.5');
          equal(set.suggested['reps']!.enteredValue, '2');
          jsonEqual(set.settings, {'scheme': 'doubles'});
        }
        // Retries keep identity; a different structure conflicts.
        jsonEqual(
          (await training.start(
            's2',
            'squat-schemes',
            1,
            instant(3),
            variantSettings: request,
          )).toJson(),
          s2.toJson(),
        );
        equal(
          (await _failure(
            () => training.start(
              's2',
              'squat-schemes',
              1,
              instant(3),
              variantSettings: {
                'squat': {'scheme': 'singles'},
              },
            ),
          )).code,
          'conflict',
        );
        equal(
          (await _failure(
            () => training.start(
              'bad',
              'squat-schemes',
              1,
              instant(3),
              variantSettings: {
                'squat': {'grip': 'wide'},
              },
            ),
          )).code,
          'validation',
        );
        // The six-set exposure is a valid baseline for the five-set anchor.
        s2 = await _finish(training, s2, '2', 3);
        final p2 = await progression.propose(
          's2',
          'squat',
          _threshold('1'),
          ruleType: 'threshold',
        );
        equal(p2.proposal.outcome, 'advance');
        equal(p2.proposal.nextSets.length, 6);
        await progression.accept('s2', 'squat', p2.version, instant(4));
        final s3 = await training.start('s3', 'squat-schemes', 1, instant(5));
        equal(s3.sets.length, 5);
        for (final set in s3.sets)
          equal(set.suggested['load']!.enteredValue, '65');
        jsonEqual((await training.session('s2')).toJson(), s2.toJson());
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    }();
  });

  test('ordinal levels move between set schemes', () {
    return () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-scheme-');
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final training = StoredTrainingService(store);
        final progression = StoredProgressionService(store);
        await training.publish(WorkoutDefinition.fromJson(_json()), 0);
        var s = await training.start('o1', 'squat-schemes', 1, instant(1));
        s = await _finish(training, s, '3', 1);
        final p1 = await progression.propose(
          'o1',
          'squat',
          _ladder,
          ruleType: 'ordinal',
        );
        equal(p1.proposal.outcome, 'advance');
        equal(p1.proposal.nextLevel, 'six-doubles');
        await progression.accept('o1', 'squat', p1.version, instant(2));

        var next = await training.start('o2', 'squat-schemes', 1, instant(3));
        equal(next.sets.length, 6);
        jsonEqual(next.variantSelections, {'scheme': 'doubles'});
        equal(next.sets.first.suggested['reps']!.enteredValue, '2');
        // A progression-controlled variant lever cannot be chosen manually.
        equal(
          (await _failure(
            () => training.start(
              'o-manual',
              'squat-schemes',
              1,
              instant(3),
              variantSettings: {
                'squat': {'scheme': 'singles'},
              },
            ),
          )).code,
          'conflict',
        );
        next = await _finish(training, next, '2', 3);
        final p2 = await progression.propose(
          'o2',
          'squat',
          _ladder,
          ruleType: 'ordinal',
        );
        equal(p2.proposal.outcome, 'advance');
        equal(p2.proposal.nextLevel, 'ten-singles');
        await progression.accept('o2', 'squat', p2.version, instant(4));
        final third = await training.start(
          'o3',
          'squat-schemes',
          1,
          instant(5),
        );
        equal(third.sets.length, 10);
        jsonEqual(third.variantSelections, {'scheme': 'singles'});
        for (final set in third.sets)
          jsonEqual(set.settings, {'scheme': 'singles'});
        final status = await progression.reconcileStatus(
          templateId: 'squat-schemes',
          revision: 1,
          slotId: 'squat',
          asOf: instant(5),
          ruleType: 'ordinal',
        );
        equal(status['reconciliationRequired'], false);
        // Full archives revalidate the frozen structures and lineage.
        final archive = await training.exportArchive();
        TrainingArchive.fromJson(archive.toJson());
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    }();
  });

  test('CLI starts select explicit variants and reject unknown levers', () {
    return () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-scheme-');
      final path = '${dir.path}/db.sqlite';
      try {
        Future<({int code, String output, String error})> cli(
          String name,
          Map<String, Object?> input,
        ) => invoke(
          name.split(' '),
          jsonEncode({'schemaVersion': 1, 'database': path, ...input}),
        );
        equal(
          (await cli('store publish', {
            'definition': _json(),
            'expectedRevision': 0,
          })).code,
          0,
        );
        final start = copyJson(example('set-scheme-start'))
          ..remove('schemaVersion')
          ..remove('database');
        final started = await cli('store start', start);
        equal(started.code, 0);
        final data = jsonObject(
          jsonObject(jsonDecode(started.output), 'response')['data'],
          'data',
        );
        jsonEqual(data['variantSelections'], {'scheme': 'doubles'});
        equal(jsonList(data, 'sets').length, 6);
        final unknown = await cli('store start', {
          ...start,
          'id': 'other',
          'variants': {
            'squat': {'grip': 'wide'},
          },
        });
        equal(unknown.code, 2);
        equal(unknown.output, '');
        final pure = await invoke(
          ['activity', 'expand'],
          jsonEncode({
            'schemaVersion': 1,
            'definition': _json(),
            'variants': {'scheme': 'singles'},
          }),
        );
        equal(pure.code, 0);
        equal(
          jsonList(jsonObject(jsonDecode(pure.output), 'response'), 'data')
              .where(
                (o) => jsonObject(o, 'o')['id'].toString().endsWith('single'),
              )
              .length,
          10,
        );
      } finally {
        await dir.delete(recursive: true);
      }
    }();
  });
}
