import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'fixtures.dart';
import 'support.dart';

Map<String, Object?> _rule({String basis = 'cycleStart'}) {
  final rule = copyJson(jsonObject(example('t2-propose')['rule'], 'rule'));
  jsonObject(
    jsonObject(rule['stages'], 'stages')['cycleRestart'],
    'cycleRestart',
  )['basis'] = basis;
  return rule;
}

List<Metrics?> _reps(List<String> values) => [
  for (final v in values) {'reps': Quantity(v, 'rep')},
];

void cycleRestartTests() {
  test('cycle restarts go heavier than an explicit reference', () {
    final start = ThresholdRule.fromJson(_rule());
    Metrics load(String v) => {'load': Quantity(v, 'kg')};
    // The first exposure at the first stage records the cycle start.
    var p = start.evaluate(
      current: load('40'),
      results: _reps(['10', '10', '10']),
      stage: 'tens',
    );
    equal(p.outcome, 'advance');
    equal(p.nextReference!['load']!.enteredValue, '40');
    jsonEqual(
      jsonObject(p.toJson()['nextState'], 'state')['reference'],
      metricsToJson(load('40')),
    );
    // Exhausting the last stage restarts at reference + 5 kg.
    p = start.evaluate(
      current: load('42.5'),
      results: _reps(['6', '6', '5']),
      stage: 'sixes',
      reference: load('40'),
    );
    equal(p.outcome, 'stage');
    equal(p.nextStage, 'tens');
    equal(p.nextValues['load']!.enteredValue, '45');
    equal(p.nextReference!['load']!.enteredValue, '45');
    // firstStageExit remembers where the first stage was left instead.
    final exit = ThresholdRule.fromJson(_rule(basis: 'firstStageExit'));
    p = exit.evaluate(
      current: load('42.5'),
      results: _reps(['10', '10', '9']),
      stage: 'tens',
    );
    equal(p.outcome, 'stage');
    equal(p.nextReference!['load']!.enteredValue, '42.5');
    p = exit.evaluate(
      current: load('42.5'),
      results: _reps(['6', '6', '5']),
      stage: 'sixes',
      reference: load('42.5'),
    );
    equal(p.nextValues['load']!.enteredValue, '47.5');
    rejects(
      () => ThresholdRule.fromJson({
        ..._rule(),
        'stages': {
          ...jsonObject(_rule()['stages'], 'stages'),
          'advanceOn': 'success',
        },
      }),
    );
    final foreign = _rule();
    jsonObject(
      jsonObject(foreign['stages'], 'stages')['cycleRestart'],
      'cycleRestart',
    )['increments'] = {
      'reps': {'value': '1', 'unit': 'rep'},
    };
    rejects(() => ThresholdRule.fromJson(foreign));
    rejects(
      () =>
          ThresholdRule.fromJson({
            ..._rule(),
            'stages': {
              'lever': 'scheme',
              'order': jsonList(
                jsonObject(_rule()['stages'], 'stages'),
                'order',
              ),
            },
          }).evaluate(
            current: load('40'),
            results: _reps(['10']),
            stage: 'tens',
            reference: load('40'),
          ),
    );
  });

  test('stored GZCLP T2 cycles restart heavier than the last cycle', () {
    return () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-t2-');
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final training = StoredTrainingService(store);
        final progression = StoredProgressionService(store);
        await training.publish(
          WorkoutDefinition.fromJson(
            jsonObject(example('t2-practice')['definition'], 'definition'),
          ),
          0,
        );
        var day = 0;
        Future<ProgressionDecision> exposure(
          List<String> reps, {
          required String scheme,
          required String load,
          bool decline = false,
        }) async {
          day += 2;
          final id = 'b$day';
          var s = await training.start(id, 'bench-t2', 1, instant(day));
          jsonEqual(s.variantSelections, {'scheme': scheme});
          for (final set in s.sets)
            equal(set.suggested['load']!.enteredValue, load);
          s = await training.edit(id, s.contentVersion, (s) {
            for (var i = 0; i < s.sets.length; i++)
              s = const TrainingService().complete(s, s.sets[i].id, {
                'load': s.sets[i].suggested['load']!,
                'reps': Quantity(reps[i], 'rep'),
              });
            return s.finish(instant(day).add(const Duration(hours: 1)));
          });
          final p = await progression.propose(
            id,
            'bench',
            _rule(),
            ruleType: 'threshold',
          );
          final at = instant(day).add(const Duration(hours: 2));
          return decline
              ? progression.decline(id, 'bench', p.version, at)
              : progression.accept(id, 'bench', p.version, at);
        }

        var d = await exposure(['10', '10', '10'], scheme: 'tens', load: '40');
        equal(d.cycleReference!['load']!.enteredValue, '40');
        d = await exposure(['10', '10', '9'], scheme: 'tens', load: '42.5');
        equal(d.proposal.outcome, 'stage');
        d = await exposure(['8', '8', '7'], scheme: 'eights', load: '42.5');
        equal(d.proposal.outcome, 'stage');
        // A declined restart keeps the reference and counts the failure.
        d = await exposure(
          ['6', '6', '5'],
          scheme: 'sixes',
          load: '42.5',
          decline: true,
        );
        equal(d.cycleReference!['load']!.enteredValue, '40');
        equal(d.failedSessions, 1);
        d = await exposure(['6', '6', '5'], scheme: 'sixes', load: '42.5');
        equal(d.proposal.outcome, 'stage');
        equal(d.cycleReference!['load']!.enteredValue, '45');
        jsonEqual(d.nextSettings.first, {'scheme': 'tens'});
        // The new cycle starts at 45 kg (40 + 5), above the last start.
        d = await exposure(['10', '10', '10'], scheme: 'tens', load: '45');
        equal(d.proposal.outcome, 'advance');
        equal(d.cycleReference!['load']!.enteredValue, '45');
        final archive = await training.exportArchive();
        TrainingArchive.fromJson(archive.toJson());
        // A forged reference breaks the decision lineage.
        final json = copyJson(archive.toJson());
        final last = jsonObject(jsonList(json, 'progressions').last, 'last');
        last['previousReference'] = {
          'load': {'value': '30', 'unit': 'kg'},
        };
        rejects(() => TrainingArchive.fromJson(json));
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    }();
  });
}
