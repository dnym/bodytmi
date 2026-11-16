import 'dart:convert';
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

/// The shipped GZCLP blueprint, filled in and run through the ordinary
/// engine: T1 advances on base volume and drops 5x3+ to 6x2+ at the same
/// weight when it is missed; T3 waits for 25 reps on the last set.
void gzclpTests() {
  test('the shipped GZCLP blueprint runs its tier progressions', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-gzclp-');
    final store = await TrainingStore.open('${dir.path}/db.sqlite');
    try {
      await CatalogImportService(store).apply(
        CatalogImportDocument.fromJson(
          jsonDecode(File('data/starter-catalog.json').readAsStringSync()),
        ),
        onChanged: 'reject',
        confirm: true,
      );
      final gzclp = (await BlueprintService(store).revision('gzclp')).blueprint;
      check(gzclp.source!.contains('Lefever'), 'the source is cited');
      final receipt = await BlueprintService(store).instantiate(
        'gzclp',
        1,
        'gz',
        {
          'squat-t1': _q('60', 'kg'),
          'pulldown-start': _q('30', 'kg'),
          'row-start': _q('16', 'kg'),
        },
        expectedInstance: 0,
        requireCatalog: true,
      );
      jsonEqual(receipt.workouts, {'a1': 1, 'a2': 1, 'b1': 1, 'b2': 1});
      final training = StoredTrainingService(store);
      final programs = ProgramService(store);
      final progression = StoredProgressionService(store);
      Future<ProgressionDecision> propose(String session, String slot) async {
        final preset = (await PresetService(store).revision(
          'gz-${switch (slot) {
            't1' => 't1-lower',
            't2' => 't2-upper',
            _ => 't3',
          }}',
        ));
        return progression.propose(
          session,
          slot,
          preset.preset.rule,
          ruleType: preset.preset.ruleType,
          preset: (id: preset.preset.id, revision: preset.number),
        );
      }

      var run = await programs.create('r', 'gz', 1, instant(1), loop: true);
      Future<TrainingSession> a1(String id, int day, List<int> t1Reps) async {
        run = await programs.run('r');
        var s = await programs.start('r', run.contentVersion, id, instant(day));
        equal(s.definition.id, 'gz-a1');
        final t1 = s.sets.where((x) => x.slotId == 't1').toList();
        equal(t1.length, t1Reps.length);
        s = await training.edit(id, s.contentVersion, (s) {
          var i = 0;
          for (final set in s.sets) {
            final reps = switch (set.slotId) {
              't1' => t1Reps[i++],
              't3' => set.id.endsWith('last') ? 20 : 15,
              _ => 10,
            };
            s = const TrainingService().complete(s, set.id, {
              'load': set.suggested['load']!,
              'reps': Quantity.fromJson(_q('$reps', 'rep')),
            });
          }
          return s.finish(instant(day).add(const Duration(hours: 1)));
        });
        return s;
      }

      Future<void> skipThree(int day) async {
        for (var i = 0; i < 3; i++) {
          run = await programs.run('r');
          await programs.skip(
            'r',
            run.contentVersion,
            'skip-$day-$i',
            instant(day),
          );
        }
      }

      // A1: squat T1 at 60 kg, 5x3+ with the last set capped at ten.
      final first = await a1('a1-1', 2, [3, 3, 3, 3, 5]);
      final lastT1 = first.sets.lastWhere((x) => x.slotId == 't1');
      equal(lastT1.criteria['reps']!.toJson()['mode'], 'range');
      equal(first.sets.first.suggested['load']!.enteredValue, '60');
      final advance = await propose('a1-1', 't1');
      equal(advance.proposal.outcome, 'advance');
      await progression.accept('a1-1', 't1', advance.version, instant(3));
      final t3 = await propose('a1-1', 't3');
      equal(t3.proposal.outcome, 'hold');
      await progression.accept('a1-1', 't3', t3.version, instant(3));
      await skipThree(4);

      // Missing base volume (13 < 15) keeps 62.5 kg and moves to 6x2+.
      final second = await a1('a1-2', 6, [3, 3, 3, 2, 2]);
      equal(second.sets.first.suggested['load']!.enteredValue, '62.5');
      final stage = await propose('a1-2', 't1');
      equal(stage.proposal.outcome, 'stage');
      await progression.accept('a1-2', 't1', stage.version, instant(7));
      await skipThree(8);
      run = await programs.run('r');
      final third = await programs.start(
        'r',
        run.contentVersion,
        'a1-3',
        instant(10),
      );
      final doubles = third.sets.where((x) => x.slotId == 't1').toList();
      equal(doubles.length, 6);
      equal(doubles.first.suggested['load']!.enteredValue, '62.5');
      equal(doubles.first.suggested['reps']!.enteredValue, '2');
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });
}
