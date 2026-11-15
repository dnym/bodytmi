import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'fixtures.dart';
import 'support.dart';

Future<String> _code(Future<Object?> Function() action) async {
  try {
    await action();
  } on BodyTmiException catch (error) {
    return error.code;
  }
  throw StateError('Expected a BodyTmiException.');
}

void countSubstitutesTests() {
  test(
    'a substitute counts toward the original lift only when asked',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-count-sub-');
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final training = StoredTrainingService(store);
        final progression = StoredProgressionService(store);
        final rule = jsonObject(
          jsonObject(example('progression-preset')['preset'], 'preset')['rule'],
          'rule',
        );
        await training.publish(definition(), 0);
        var s = await training.start('s1', definition().id, 1, instant(1));
        // The benches are taken: dumbbells at 22 kg for every heavy set.
        s = await training.substitute(
          's1',
          s.contentVersion,
          slotId: 'bench-heavy',
          scope: 'remaining',
          composition: SubstituteComposition.fromJson({
            'exercise': 'bench-press',
            'implementation': 'dumbbell',
          }),
          targets: {
            'mass': {
              'source': 'explicit',
              'value': {'value': '22', 'unit': 'kg'},
            },
            'reps': {'source': 'keep'},
          },
        );
        s = await training.edit('s1', s.contentVersion, (s) {
          for (final set in s.sets)
            s = const TrainingService().complete(s, set.id, {
              if (set.slotId == 'bench-heavy') 'reps': Quantity('10', 'rep'),
            }, acceptSuggested: true);
          return s.finish(instant(1).add(const Duration(hours: 1)));
        });
        // Without the opt-in the exposure is neutral, as before.
        equal(
          await _code(() => progression.propose('s1', 'bench-heavy', rule)),
          'validation',
        );
        final counted = await progression.propose(
          's1',
          'bench-heavy',
          rule,
          countSubstitutes: true,
        );
        equal(counted.countSubstitutes, true);
        equal(counted.countedSubstitutes.length, 3);
        // 10 reps at the planned 60 kg: one more rep next time, still 60 kg.
        equal(counted.proposal.outcome, 'increaseObjective');
        for (final next in counted.proposal.nextSets) {
          equal(next['mass']!.value.toString(), '60');
          equal(next['reps']!.value.toString(), '9');
        }
        jsonEqual(
          ProgressionDecision.fromJson(counted.toJson()).toJson(),
          counted.toJson(),
        );
        final accepted = await progression.accept(
          's1',
          'bench-heavy',
          counted.version,
          instant(1).add(const Duration(hours: 2)),
        );
        final next = await training.start('s2', definition().id, 1, instant(3));
        for (final set in next.sets.where((s) => s.slotId == 'bench-heavy')) {
          equal(set.suggested['mass']!.value.toString(), '60');
          equal(set.suggested['reps']!.value.toString(), '9');
        }
        equal(accepted.countSubstitutes, true);
        // A decision cannot claim to count substitutes that are not there.
        final plain = await training.edit('s2', next.contentVersion, (s) {
          for (final set in s.sets)
            s = const TrainingService().complete(
              s,
              set.id,
              const {},
              acceptSuggested: true,
            );
          return s.finish(instant(3).add(const Duration(hours: 1)));
        });
        rejects(
          () => ProgressionDecision.fromJson({
            ...counted.toJson(),
            'session': plain.toJson(),
          }),
        );
        await store.backup('${dir.path}/native');
        await LogicalArchiveFiles.export(
          await store.archive(),
          '${dir.path}/logical.json',
        );
        await LogicalArchiveFiles.prepare('${dir.path}/logical.json');
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
