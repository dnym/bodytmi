import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'cli_test.dart';
import 'fixtures.dart';
import 'support.dart';

Metrics _m(String mass, String reps) => {
  'mass': Quantity(mass, 'kg'),
  'reps': Quantity(reps, 'rep'),
};

Future<BodyTmiException> _failure(Object? Function() action) async {
  try {
    await action();
  } on BodyTmiException catch (error) {
    return error;
  }
  throw StateError('Expected a BodyTmiException.');
}

/// Sets logged outside the plan: counted in analytics, never in
/// progression, prefill or traversal.
void unplannedSetsTests() {
  test(
    'unplanned ramp and back-off sets count in analytics, not progression',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-unplanned-');
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final training = StoredTrainingService(store);
        await training.publish(definition(), 0);
        var s = await training.start('s1', 'upper-a', 1, instant(1));
        // The starting-weight ramp: empty bar, then 40 kg.
        for (final (mass, reps) in [('20', '5'), ('40', '5')]) {
          s = await training.edit(
            's1',
            s.contentVersion,
            (s) => const TrainingService().addSet(
              s,
              'bench-heavy',
              actuals: _m(mass, reps),
            ),
          );
        }
        s = await training.edit(
          's1',
          s.contentVersion,
          (s) => const TrainingService().addSet(
            s,
            'bench-heavy',
            role: 'backoff',
            actuals: _m('45', '10'),
          ),
        );
        jsonEqual(
          [for (final x in s.extraSets) x.id],
          ['extra-1', 'extra-2', 'extra-3'],
        );
        jsonEqual([for (final x in s.extraSets) x.ordinal], [0, 1, 0]);
        equal(s.sets.length, 4); // the planned sets are unchanged
        s = await training.edit('s1', s.contentVersion, (s) {
          for (final set in s.sets) {
            s = const TrainingService().complete(
              s,
              set.id,
              const {},
              acceptSuggested: true,
            );
          }
          return s.finish(instant(1).add(const Duration(hours: 1)));
        });
        // Corrections work on unplanned sets too; skipping them does not.
        s = await training.edit(
          's1',
          s.contentVersion,
          (s) =>
              const TrainingService().complete(s, 'extra-2', _m('42.5', '5')),
        );
        await _failure(
          () => training.edit(
            's1',
            s.contentVersion,
            (s) => const TrainingService().skip(s, 'extra-2', confirm: true),
          ),
        );

        // Progression sees the three planned heavy sets only.
        final decision = await StoredProgressionService(store).propose(
          's1',
          'bench-heavy',
          jsonObject(example('double-progression')['rule'], 'rule'),
        );
        equal(decision.sets.length, 3);

        // Summaries, series and records include them, flagged.
        final summary = const TrainingAnalytics().summary(
          s,
          includeWarmups: true,
        );
        final rows = [
          for (final row in jsonList(summary, 'sets')) jsonObject(row, 'row'),
        ];
        equal(rows.where((r) => r['unplanned'] == true).length, 3);
        equal(jsonObject(summary['counts'], 'counts')['included'], 7);
        final warmups = const TrainingAnalytics().series(
          [s],
          metric: 'mass',
          roles: ['warmup'],
        );
        final points = jsonList(
          jsonObject(jsonList(warmups, 'series').single, 's'),
          'points',
        );
        jsonEqual(
          [
            for (final p in points)
              jsonObject(jsonObject(p, 'p')['actual'], 'a')['value'],
          ],
          ['20', '42.5'],
        );

        // Prefill of the next session ignores unplanned results.
        final next = await training.start('s2', 'upper-a', 1, instant(2));
        check(
          next.sets.every(
            (set) => !set.sources.values.any(
              (source) => source.setId.startsWith('extra-'),
            ),
          ),
          'prefill never reads unplanned sets',
        );

        // Removal needs confirmation, keeps the other IDs, and later sets
        // continue the numbering; planned sets cannot be removed.
        await _failure(
          () => training.edit(
            's1',
            s.contentVersion,
            (s) => const TrainingService().removeSet(s, 'extra-2'),
          ),
        );
        s = await training.edit(
          's1',
          s.contentVersion,
          (s) => const TrainingService().removeSet(s, 'extra-2', confirm: true),
        );
        s = await training.edit(
          's1',
          s.contentVersion,
          (s) => const TrainingService().addSet(
            s,
            'bench-heavy',
            actuals: _m('30', '5'),
          ),
        );
        jsonEqual(
          [for (final x in s.extraSets) x.id],
          ['extra-1', 'extra-3', 'extra-4'],
        );
        await _failure(
          () => training.edit(
            's1',
            s.contentVersion,
            (s) => const TrainingService().removeSet(
              s,
              s.sets.first.id,
              confirm: true,
            ),
          ),
        );
        await _failure(
          () => training.edit(
            's1',
            s.contentVersion,
            (s) => const TrainingService().addSet(
              s,
              'no-such-slot',
              actuals: _m('20', '5'),
            ),
          ),
        );
        await _failure(
          () => training.edit(
            's1',
            s.contentVersion,
            (s) => const TrainingService().addSet(
              s,
              'bench-heavy',
              actuals: {'mass': Quantity('5', 'rep')},
            ),
          ),
        );

        // Archives round-trip; a renumbered unplanned set is rejected.
        final archive = await training.exportArchive();
        TrainingArchive.fromJson(archive.toJson());
        final forged = jsonDecode(jsonEncode(archive.toJson())) as Map;
        final session =
            (forged['sessions'] as List).firstWhere(
                  (x) => (x as Map)['id'] == 's1',
                )
                as Map;
        ((session['extraSets'] as List).last as Map)['id'] = 'extra-2';
        rejects(() => TrainingArchive.fromJson(forged.cast<String, Object?>()));
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test('CLI store add-set and remove-set', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-unplanned-cli');
    final db = '${dir.path}/db.sqlite';
    Future<({int code, Map<String, Object?>? data})> cli(
      String name,
      Map<String, Object?> fields,
    ) async {
      final r = await invoke(
        name.split(' '),
        jsonEncode({'schemaVersion': 1, 'database': db, ...fields}),
      );
      return (
        code: r.code,
        data: r.code == 0
            ? jsonObject(jsonObject(jsonDecode(r.output), 'r')['data'], 'd')
            : null,
      );
    }

    try {
      await cli('store publish', {
        'definition': definition().toJson(),
        'expectedRevision': 0,
      });
      final started = await cli('store start', {
        'id': 's',
        'templateId': 'upper-a',
        'revision': 1,
        'startedAt': instant(1).toIso8601String(),
      });
      final added = await cli('store add-set', {
        'id': 's',
        'expectedVersion': started.data!['contentVersion'],
        'slotId': 'bench-heavy',
        'actuals': {
          'mass': {'value': '20', 'unit': 'kg'},
          'reps': {'value': '5', 'unit': 'rep'},
        },
        'observations': {'notes': 'Empty bar to find the starting weight.'},
      });
      equal(added.code, 0);
      final extra = jsonObject(jsonList(added.data!, 'extraSets').single, 'x');
      equal(extra['id'], 'extra-1');
      equal(extra['role'], 'warmup');
      final unconfirmed = await cli('store remove-set', {
        'id': 's',
        'expectedVersion': added.data!['contentVersion'],
        'setId': 'extra-1',
      });
      equal(unconfirmed.code, 2);
      final removed = await cli('store remove-set', {
        'id': 's',
        'expectedVersion': added.data!['contentVersion'],
        'setId': 'extra-1',
        'confirm': true,
      });
      equal(removed.code, 0);
      check(!removed.data!.containsKey('extraSets'), 'omitted when empty');
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
