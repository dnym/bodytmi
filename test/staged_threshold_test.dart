import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'fixtures.dart';
import 'support.dart';

Map<String, Object?> _q(String value, String unit) => {
  'value': value,
  'unit': unit,
};

Map<String, Object?> _stage(String value, String limit) => {
  'value': value,
  'failureLimit': _q(limit, 'rep'),
  'advancementLimit': _q(limit, 'rep'),
};

/// GZCLP-style T1: base volume per stage, fixed load across sets, one failed
/// exposure moves to the next scheme, the last scheme deloads to 85%.
Map<String, Object?> _rule({bool deload = true}) => {
  'metric': 'reps',
  'performance': {
    'direction': 'higher',
    'failureLimit': _q('15', 'rep'),
    'advancementLimit': _q('15', 'rep'),
  },
  'aggregation': {'mode': 'total'},
  'failureAggregation': {'mode': 'total'},
  'increments': {'load': _q('2.5', 'kg')},
  'deloadAfter': 1,
  if (deload) ...{
    'deloadMetrics': ['load'],
    'deloadPercent': '15',
  },
  'stages': {
    'lever': 'scheme',
    'order': [
      _stage('triples', '15'),
      _stage('doubles', '12'),
      _stage('singles', '10'),
    ],
  },
};

Future<BodyTmiException> _failure(Object? Function() action) async {
  try {
    await action();
  } on BodyTmiException catch (error) {
    return error;
  }
  throw StateError('Expected a BodyTmiException.');
}

void stagedThresholdTests() {
  test('staged threshold rules validate and move between stages', () {
    final rule = ThresholdRule.fromJson(_rule());
    equal(rule.stages!.lever, 'scheme');
    Metrics load(String v) => {'load': Quantity.fromJson(_q(v, 'kg'))};
    List<Metrics?> reps(List<String> values) => [
      for (final v in values) {'reps': Quantity.fromJson(_q(v, 'rep'))},
    ];
    ProgressionProposal run(
      String stage,
      List<String> results, {
      ThresholdRule? with_,
      int failures = 0,
    }) => (with_ ?? rule).evaluate(
      current: load('60'),
      results: reps(results),
      stage: stage,
      failedSessions: failures,
    );
    // Stage limits replace the rule's own: twelve reps advance doubles.
    final advance = run('doubles', ['2', '2', '2', '2', '2', '2']);
    equal(advance.outcome, 'advance');
    equal(advance.nextStage, 'doubles');
    equal(advance.nextValues['load']!.enteredValue, '62.5');
    final moved = run('triples', ['3', '3', '3', '3', '2']);
    equal(moved.outcome, 'stage');
    equal(moved.nextStage, 'doubles');
    equal(moved.failedSessions, 0);
    equal(moved.nextValues['load']!.enteredValue, '60');
    jsonEqual(moved.toJson()['nextStage'], 'doubles');
    final reset = run('singles', ['1', '1', '1', '1', '1', '1', '1', '1', '1']);
    equal(reset.outcome, 'deload');
    equal(reset.nextStage, 'triples');
    equal(reset.nextValues['load']!.enteredValue, '51');
    final plain = run('singles', [
      '1',
      '1',
      '1',
      '1',
      '1',
      '1',
      '1',
      '1',
      '1',
    ], with_: ThresholdRule.fromJson(_rule(deload: false)));
    equal(plain.outcome, 'stage');
    equal(plain.nextStage, 'triples');
    equal(plain.nextValues['load']!.enteredValue, '60');
    // Below deloadAfter, failure only counts; unknown holds the stage.
    final slow = ThresholdRule.fromJson({..._rule(), 'deloadAfter': 2});
    final first = run('triples', ['3', '3', '3', '3', '2'], with_: slow);
    equal(first.outcome, 'failed');
    equal(first.nextStage, 'triples');
    equal(first.failedSessions, 1);
    equal(
      run(
        'triples',
        ['3', '3', '3', '3', '2'],
        with_: slow,
        failures: 1,
      ).nextStage,
      'doubles',
    );
    final unknown = rule.evaluate(
      current: load('60'),
      results: [null],
      stage: 'triples',
    );
    equal(unknown.outcome, 'unknown');
    equal(unknown.nextStage, 'triples');

    rejects(() => rule.evaluate(current: load('60'), results: reps(['3'])));
    rejects(() => run('quads', ['3']));
    rejects(
      () => ThresholdRule.fromJson(
        _rule()..remove('stages'),
      ).evaluate(current: load('60'), results: reps(['3']), stage: 'triples'),
    );
    for (final stages in [
      {
        'lever': 'scheme',
        'order': [_stage('triples', '15')],
      },
      {
        'lever': 'scheme',
        'order': [_stage('triples', '15'), _stage('triples', '12')],
      },
      {
        'lever': 'scheme',
        'order': [
          _stage('triples', '15'),
          {
            'value': 'doubles',
            'failureLimit': _q('12', 'kg'),
            'advancementLimit': _q('12', 'kg'),
          },
        ],
      },
      {
        'lever': 'scheme',
        'order': [
          _stage('triples', '15'),
          {
            'value': 'doubles',
            'failureLimit': _q('13', 'rep'),
            'advancementLimit': _q('12', 'rep'),
          },
        ],
      },
    ]) {
      rejects(() => ThresholdRule.fromJson({..._rule(), 'stages': stages}));
    }
  });

  test('stored GZCLP-style tiers change set scheme on failure', () {
    return () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-staged-');
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final training = StoredTrainingService(store);
        final progression = StoredProgressionService(store);
        await training.publish(
          WorkoutDefinition.fromJson(
            jsonObject(
              example('set-scheme-practice')['definition'],
              'definition',
            ),
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
          final id = 's$day';
          var s = await training.start(id, 'squat-schemes', 1, instant(day));
          jsonEqual(s.variantSelections, {'scheme': scheme});
          equal(s.sets.length, reps.length);
          for (final set in s.sets) {
            equal(set.suggested['load']!.enteredValue, load);
            jsonEqual(set.settings, {'scheme': scheme});
          }
          s = await training.edit(id, s.contentVersion, (s) {
            for (var i = 0; i < s.sets.length; i++) {
              s = const TrainingService().complete(s, s.sets[i].id, {
                'load': s.sets[i].suggested['load']!,
                'reps': Quantity.fromJson(_q(reps[i], 'rep')),
              });
            }
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

        var d = await exposure(
          ['3', '3', '3', '3', '3'],
          scheme: 'triples',
          load: '60',
        );
        equal(d.proposal.outcome, 'advance');
        d = await exposure(
          ['3', '3', '3', '3', '2'],
          scheme: 'triples',
          load: '62.5',
        );
        equal(d.proposal.outcome, 'stage');
        jsonEqual(d.nextSettings.first, {'scheme': 'doubles'});
        d = await exposure(
          ['2', '2', '2', '2', '2', '2'],
          scheme: 'doubles',
          load: '62.5',
        );
        equal(d.proposal.outcome, 'advance');
        // Declining a stage change holds the scheme and keeps the failure.
        d = await exposure(
          ['2', '2', '2', '2', '2', '1'],
          scheme: 'doubles',
          load: '65',
          decline: true,
        );
        equal(d.proposal.outcome, 'stage');
        equal(d.failedSessions, 1);
        jsonEqual(d.nextSettings.first, {'scheme': 'doubles'});
        d = await exposure(
          ['2', '2', '2', '2', '2', '1'],
          scheme: 'doubles',
          load: '65',
        );
        equal(d.proposal.outcome, 'stage');
        d = await exposure(List.filled(10, '1'), scheme: 'singles', load: '65');
        equal(d.proposal.outcome, 'advance');
        d = await exposure(
          [...List.filled(9, '1'), '0'],
          scheme: 'singles',
          load: '67.5',
        );
        equal(d.proposal.outcome, 'deload');
        jsonEqual(d.nextSettings.first, {'scheme': 'triples'});
        final restart = await training.start(
          'restart',
          'squat-schemes',
          1,
          instant(day + 2),
        );
        equal(restart.sets.length, 5);
        equal(restart.sets.first.suggested['load']!.enteredValue, '57.375');
        // The stage lever is progression-controlled.
        equal(
          (await _failure(
            () => training.start(
              'manual',
              'squat-schemes',
              1,
              instant(day + 2),
              variantSettings: {
                'squat': {'scheme': 'singles'},
              },
            ),
          )).code,
          'conflict',
        );
        // Staged rules hold no shared lever links; archives round-trip.
        TrainingArchive.fromJson((await training.exportArchive()).toJson());
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    }();
  });
}
