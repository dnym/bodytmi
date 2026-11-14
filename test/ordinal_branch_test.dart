import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'cli_test.dart';
import 'fixtures.dart';
import 'support.dart';

Map<String, Object?> _level(String id, String mass) => {
  'id': id,
  'targets': {
    'mass': {'value': mass, 'unit': 'kg'},
    'reps': {'value': '8', 'unit': 'rep'},
  },
};

/// A skill ladder with incomparable branches: base → wide | narrow → top.
Map<String, Object?> _rule({Map<String, Object?>? successors}) => {
  'metric': 'reps',
  'performance': {
    'direction': 'higher',
    'failureLimit': {'value': '4', 'unit': 'rep'},
    'advancementLimit': {'value': '8', 'unit': 'rep'},
  },
  'levels': [
    _level('base', '20'),
    _level('wide', '22.5'),
    _level('narrow', '21'),
    _level('top', '25'),
    _level('isolated', '30'),
  ],
  'deloadAfter': 2,
  'deloadLevel': 'base',
  'successors':
      successors ??
      {
        'base': ['wide', 'narrow'],
        'wide': ['top'],
        'narrow': ['top'],
      },
};

List<Metrics> _at(String mass, [int sets = 2]) => [
  for (var i = 0; i < sets; i++)
    metrics({'mass': (mass, 'kg'), 'reps': ('8', 'rep')}),
];

List<Metrics?> _reps(String reps, [int sets = 2]) => [
  for (var i = 0; i < sets; i++) metrics({'reps': (reps, 'rep')}),
];

Future<BodyTmiException> _failure(Object? Function() action) async {
  try {
    await action();
  } on BodyTmiException catch (error) {
    return error;
  }
  throw StateError('Expected a BodyTmiException.');
}

/// Starts and finishes one session at the current suggestions with [reps].
Future<TrainingSession> _finished(
  TrainingStore store,
  String id,
  int day, {
  String reps = '8',
}) async {
  final service = StoredTrainingService(store);
  final session = await service.start(id, 'ordinal-practice', 1, instant(day));
  return service.edit(id, session.contentVersion, (s) {
    for (final set in s.sets) {
      s = const TrainingService().complete(s, set.id, {
        'reps': Quantity(reps, 'rep'),
      }, acceptSuggested: true);
    }
    return s.finish(instant(day).add(const Duration(hours: 1)));
  });
}

DateTime _approval(int day) => instant(day).add(const Duration(hours: 2));

void ordinalBranchTests() {
  test('successor graphs validate as acyclic declared edges', () {
    final rule = OrdinalRule.fromJson(_rule());
    check(rule.reaches('base', 'top'));
    check(!rule.reaches('wide', 'narrow'), 'siblings are incomparable');
    check(!rule.reaches('top', 'base'));
    jsonEqual(rule.successorsOf(0), ['wide', 'narrow']);
    void bad(Map<String, Object?> successors) =>
        rejects(() => OrdinalRule.fromJson(_rule(successors: successors)));
    bad({});
    bad({
      'base': ['ghost'],
    });
    bad({
      'ghost': ['base'],
    });
    bad({
      'base': ['base'],
    });
    bad({
      'base': ['wide', 'wide'],
    });
    bad({'base': <Object?>[]});
    bad({
      'base': ['wide'],
      'wide': ['narrow'],
      'narrow': ['base'],
    });
    // A branched deload level must itself lead somewhere.
    rejects(() => OrdinalRule.fromJson({..._rule(), 'deloadLevel': 'top'}));
  });

  test(
    'branches hold for an explicit choice and only follow declared edges',
    () {
      final rule = OrdinalRule.fromJson(_rule());
      final choice = rule.evaluate(currentSets: _at('20'), results: _reps('8'));
      equal(choice.outcome, 'choice');
      jsonEqual(choice.candidates, ['wide', 'narrow']);
      equal(choice.nextSets.first['mass']!.enteredValue, '20');
      equal(choice.failedSessions, 0);
      final single = rule.evaluate(currentSets: _at('21'), results: _reps('8'));
      equal(single.outcome, 'advance');
      equal(single.nextSets.first['mass']!.enteredValue, '25');
      equal(
        rule.evaluate(currentSets: _at('25'), results: _reps('8')).outcome,
        'blocked',
      );
      // Deload reaches back only to a declared ancestor.
      final deload = rule.evaluate(
        currentSets: _at('22.5'),
        results: _reps('2'),
        failedSessions: 1,
      );
      equal(deload.outcome, 'deload');
      equal(deload.nextSets.first['mass']!.enteredValue, '20');
      final unreachable = rule.evaluate(
        currentSets: _at('30'),
        results: _reps('2'),
        failedSessions: 1,
      );
      equal(unreachable.outcome, 'blocked');
      equal(unreachable.failedSessions, 2);
      // Without a graph, array order still applies.
      final linear = OrdinalRule.fromJson({..._rule()}..remove('successors'));
      equal(
        linear
            .evaluate(currentSets: _at('20'), results: _reps('8'))
            .nextSets
            .first['mass']!
            .enteredValue,
        '22.5',
      );
    },
  );

  test('stored branch choices need an explicit declared successor', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-branch-');
    var store = await TrainingStore.open('${dir.path}/db.sqlite');
    try {
      await StoredTrainingService(store).publish(
        WorkoutDefinition.fromJson(example('ordinal-practice')['definition']),
        0,
      );
      final progression = StoredProgressionService(store);
      final rule = _rule();
      final first = await _finished(store, 'b1', 1);
      final pending = await progression.propose(
        first.id,
        'row',
        rule,
        ruleType: 'ordinal',
      );
      equal(pending.proposal.outcome, 'choice');
      jsonEqual(pending.proposal.toJson()['candidates'], ['wide', 'narrow']);
      Future<ProgressionDecision> accept([String? level]) => progression.accept(
        first.id,
        'row',
        pending.version,
        _approval(1),
        selectedLevel: level,
      );
      equal((await _failure(() => accept())).code, 'validation');
      equal((await _failure(() => accept('top'))).code, 'validation');
      final accepted = await accept('narrow');
      equal(accepted.selectedLevel, 'narrow');
      equal(accepted.nextSets.first['mass']!.enteredValue, '21');
      // A lost-response retry returns the receipt; another choice conflicts.
      equal((await accept('narrow')).version, accepted.version);
      equal((await _failure(() => accept('wide'))).code, 'conflict');

      final second = await _finished(store, 'b2', 2);
      equal(second.sets.last.suggested['mass']!.enteredValue, '21');
      final next = await progression.propose(
        second.id,
        'row',
        rule,
        ruleType: 'ordinal',
      );
      equal(next.proposal.outcome, 'advance');
      equal(next.proposal.nextSets.first['mass']!.enteredValue, '25');
      // selectedLevel cannot resolve an ordinary advance.
      equal(
        (await _failure(
          () => progression.accept(
            second.id,
            'row',
            next.version,
            _approval(2),
            selectedLevel: 'top',
          ),
        )).code,
        'validation',
      );
      await progression.decline(second.id, 'row', next.version, _approval(2));

      // Portability: v68 round-trips; older labels reject branches.
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

  test('CLI accept takes an explicit successor choice', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-branch-cli-');
    try {
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      await StoredTrainingService(store).publish(
        WorkoutDefinition.fromJson(example('ordinal-practice')['definition']),
        0,
      );
      await _finished(store, 'c1', 1);
      await StoredProgressionService(
        store,
      ).propose('c1', 'row', _rule(), ruleType: 'ordinal');
      await store.close();
      Future<({int code, String output, String error})> cmd(
        Map<String, Object?> input,
      ) => invoke(
        ['progression', 'accept'],
        jsonEncode({
          'schemaVersion': 1,
          'database': '${dir.path}/db.sqlite',
          'sessionId': 'c1',
          'slotId': 'row',
          'expectedVersion': 1,
          'acceptedAt': _approval(1).toIso8601String(),
          ...input,
        }),
      );
      equal((await cmd({})).code, 2);
      final ok = await cmd({'selectedLevel': 'wide'});
      equal(ok.code, 0);
      check(ok.output.contains('"selectedLevel":"wide"'));
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
