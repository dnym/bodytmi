import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'fixtures.dart';
import 'support.dart';

Map<String, Object?> _rule() =>
    copyJson(jsonObject(example('wave-propose')['rule'], 'rule'));

Metrics _load(String v) => {'load': Quantity(v, 'kg')};
List<Metrics?> _reps(List<String> values) => [
  for (final v in values) {'reps': Quantity(v, 'rep')},
];

void waveTests() {
  test('success-driven stages shift by offsets and increment on wrap', () {
    final rule = ThresholdRule.fromJson(_rule());
    equal(rule.stages!.advanceOn, 'success');
    var p = rule.evaluate(
      current: _load('70'),
      results: _reps(['8', '8', '8']),
      stage: 'eights',
    );
    equal(p.outcome, 'stage');
    equal(p.nextStage, 'sixes');
    equal(p.nextValues['load']!.enteredValue, '75');
    p = rule.evaluate(
      current: _load('80'),
      results: _reps(['4', '4', '4']),
      stage: 'fours',
    );
    equal(p.outcome, 'advance');
    equal(p.nextStage, 'eights');
    equal(p.nextValues['load']!.enteredValue, '72.5');
    // Failure counts without moving; the stage and load hold.
    p = rule.evaluate(
      current: _load('75'),
      results: _reps(['6', '6', '5']),
      stage: 'sixes',
    );
    equal(p.outcome, 'failed');
    equal(p.nextStage, 'sixes');
    equal(p.nextValues['load']!.enteredValue, '75');
    // An offset that would go negative blocks the move.
    p = rule.evaluate(
      current: _load('8'),
      results: _reps(['4', '4', '4']),
      stage: 'fours',
    );
    equal(p.outcome, 'blocked');
    equal(p.nextStage, 'fours');

    Map<String, Object?> stagesOf(Map<String, Object?> r) =>
        jsonObject(r['stages'], 'stages');
    Map<String, Object?> stage(Map<String, Object?> r, int i) =>
        jsonObject(jsonList(stagesOf(r), 'order')[i], 'stage');
    final mismatched = _rule();
    stage(mismatched, 1).remove('offsets');
    rejects(() => ThresholdRule.fromJson(mismatched));
    final foreign = _rule();
    stage(foreign, 0)['offsets'] = {
      'reps': {'value': '1', 'unit': 'rep'},
    };
    rejects(() => ThresholdRule.fromJson(foreign));
    final mode = _rule();
    stagesOf(mode)['advanceOn'] = 'always';
    rejects(() => ThresholdRule.fromJson(mode));
  });

  test('stored wave cycles stages on success and raises the base on wrap', () {
    return () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-wave-');
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final training = StoredTrainingService(store);
        final progression = StoredProgressionService(store);
        await training.publish(
          WorkoutDefinition.fromJson(
            jsonObject(example('wave-practice')['definition'], 'definition'),
          ),
          0,
        );
        var day = 0;
        Future<ProgressionDecision> exposure(
          List<String> reps, {
          required String stage,
          required String load,
          bool decline = false,
        }) async {
          day += 2;
          final id = 'w$day';
          var s = await training.start(id, 'squat-wave', 1, instant(day));
          jsonEqual(s.variantSelections, {'wave': stage});
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
            'squat',
            _rule(),
            ruleType: 'threshold',
          );
          final at = instant(day).add(const Duration(hours: 2));
          return decline
              ? progression.decline(id, 'squat', p.version, at)
              : progression.accept(id, 'squat', p.version, at);
        }

        var d = await exposure(['8', '8', '8'], stage: 'eights', load: '70');
        equal(d.proposal.outcome, 'stage');
        // A declined success move holds the stage and still counts as success.
        d = await exposure(
          ['6', '6', '6'],
          stage: 'sixes',
          load: '75',
          decline: true,
        );
        equal(d.proposal.outcome, 'stage');
        equal(d.failedSessions, 0);
        jsonEqual(d.nextSettings.first, {'wave': 'sixes'});
        d = await exposure(['6', '6', '6'], stage: 'sixes', load: '75');
        jsonEqual(d.nextSettings.first, {'wave': 'fours'});
        d = await exposure(['4', '4', '4'], stage: 'fours', load: '80');
        equal(d.proposal.outcome, 'advance');
        jsonEqual(d.nextSettings.first, {'wave': 'eights'});
        d = await exposure(['8', '8', '7'], stage: 'eights', load: '72.5');
        equal(d.proposal.outcome, 'failed');
        equal(d.failedSessions, 1);
        final again = await training.start(
          'again',
          'squat-wave',
          1,
          instant(day + 2),
        );
        jsonEqual(again.variantSelections, {'wave': 'eights'});
        equal(again.sets.first.suggested['load']!.enteredValue, '72.5');
        equal(again.sets.first.suggested['reps']!.enteredValue, '8');
        TrainingArchive.fromJson((await training.exportArchive()).toJson());
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    }();
  });
}
