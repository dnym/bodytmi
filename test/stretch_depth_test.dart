import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'fixtures.dart';
import 'support.dart';

void stretchDepthTests() {
  test('stretch depth is recorded in degrees and moves the stretch to its '
      'next position', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-stretch-');
    final store = await TrainingStore.open('${dir.path}/db.sqlite');
    try {
      equal(Quantity('90', 'deg').dimension, Dimension.angle);
      final training = StoredTrainingService(store);
      final progression = StoredProgressionService(store);
      final rule = jsonObject(example('stretch-depth-rule')['rule'], 'rule');
      await training.publish(
        WorkoutDefinition.fromJson(
          example('stretch-depth-practice')['definition'],
        ),
        0,
      );
      Future<TrainingSession> sunday(
        String id,
        int day,
        List<String> depths,
      ) async {
        var s = await training.start(id, 'pike-stretch', 1, instant(day));
        return training.edit(id, s.contentVersion, (s) {
          for (var i = 0; i < s.sets.length; i++)
            s = const TrainingService().complete(s, s.sets[i].id, {
              'depth': Quantity(depths[i], 'deg'),
            }, acceptSuggested: true);
          return s.finish(instant(day).add(const Duration(minutes: 20)));
        });
      }

      Future<ProgressionDecision> resolve(String id, int day) async {
        final p = await progression.propose(
          id,
          'pike',
          rule,
          ruleType: 'ordinal',
        );
        return progression.accept(
          id,
          'pike',
          p.version,
          instant(day).add(const Duration(hours: 1)),
        );
      }

      await sunday('s1', 1, ['70', '75']);
      equal((await resolve('s1', 1)).proposal.outcome, 'hold');
      final second = await sunday('s2', 8, ['88', '91']);
      equal((await resolve('s2', 8)).proposal.outcome, 'hold');
      for (final set in second.sets)
        jsonEqual(set.settings, {'position': 'seated'});
      await sunday('s3', 15, ['92', '95']);
      final moved = await resolve('s3', 15);
      equal(moved.proposal.outcome, 'advance');
      // The next Sunday plans the standing pike; depth series keep the two
      // positions apart.
      final next = await training.start('s4', 'pike-stretch', 1, instant(22));
      for (final set in next.sets)
        jsonEqual(set.settings, {'position': 'standing'});
      final series = const TrainingAnalytics().series([
        for (final id in ['s1', 's2', 's3']) await training.session(id),
      ], metric: 'depth');
      final points = [
        for (final row in jsonList(series, 'series'))
          for (final p in jsonList(jsonObject(row, 'row'), 'points'))
            jsonObject(jsonObject(p, 'p')['actual'], 'a')['value'],
      ];
      equal(points.length, 6);
      check(points.contains('95'));
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });
}
