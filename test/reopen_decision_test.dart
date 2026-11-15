import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'fixtures.dart';
import 'support.dart';

Map<String, Object?> get _rule => jsonObject(
  jsonObject(example('progression-preset')['preset'], 'preset')['rule'],
  'rule',
);

Future<String> _code(Future<Object?> Function() action) async {
  try {
    await action();
  } on BodyTmiException catch (error) {
    return error.code;
  }
  throw StateError('Expected a BodyTmiException.');
}

/// Finishes [id] with every heavy set at [reps] repetitions.
Future<TrainingSession> _finished(
  TrainingStore store,
  String id,
  int day,
  String reps,
) async {
  final service = StoredTrainingService(store);
  final session = await service.start(id, definition().id, 1, instant(day));
  return service.edit(id, session.contentVersion, (s) {
    for (final set in s.sets) {
      s = const TrainingService().complete(s, set.id, {
        if (set.slotId == 'bench-heavy') 'reps': Quantity(reps, 'rep'),
      }, acceptSuggested: true);
    }
    return s.finish(instant(day).add(const Duration(hours: 1)));
  });
}

Future<TrainingSession> _correct(
  TrainingStore store,
  String id,
  String reps,
) async {
  final service = StoredTrainingService(store);
  final current = await service.session(id);
  return service.edit(id, current.contentVersion, (s) {
    for (final set in s.sets.where((s) => s.slotId == 'bench-heavy'))
      s = const TrainingService().complete(s, set.id, {
        'reps': Quantity(reps, 'rep'),
      }, acceptSuggested: true);
    return s;
  });
}

void reopenDecisionTests() {
  test('a corrected exposure reopens and is decided again', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-reopen-');
    final store = await TrainingStore.open('${dir.path}/db.sqlite');
    try {
      final service = StoredTrainingService(store);
      final progression = StoredProgressionService(store);
      await service.publish(definition(), 0);
      await _finished(store, 's1', 1, '10');
      final first = await progression.propose('s1', 'bench-heavy', _rule);
      final base = await progression.accept(
        's1',
        'bench-heavy',
        first.version,
        instant(1).add(const Duration(hours: 2)),
      );
      // Typo: 5 instead of 9 reps fails the exposure.
      await _finished(store, 's2', 3, '5');
      final typo = await progression.propose('s2', 'bench-heavy', _rule);
      final failed = await progression.accept(
        's2',
        'bench-heavy',
        typo.version,
        instant(3).add(const Duration(hours: 2)),
      );
      equal(failed.failedSessions, 1);

      // Unchanged inputs and unconfirmed requests reopen nothing.
      equal(
        await _code(
          () => progression.reopen(
            's2',
            'bench-heavy',
            failed.version,
            confirm: true,
          ),
        ),
        'conflict',
      );
      await _correct(store, 's2', '9');
      equal(
        await _code(
          () => progression.reopen(
            's2',
            'bench-heavy',
            failed.version,
            confirm: false,
          ),
        ),
        'validation',
      );
      equal(
        await _code(
          () => progression.reopen('s2', 'bench-heavy', 99, confirm: true),
        ),
        'conflict',
      );
      // The earlier exposure is no longer the head of the track.
      await _correct(store, 's1', '11');
      equal(
        await _code(
          () => progression.reopen(
            's1',
            'bench-heavy',
            base.version,
            confirm: true,
          ),
        ),
        'conflict',
      );
      await _correct(store, 's1', '10');

      final reopened = await progression.reopen(
        's2',
        'bench-heavy',
        failed.version,
        confirm: true,
      );
      equal(reopened.resolvedAt, null);
      equal(reopened.version, failed.version + 1);
      equal(reopened.previousApplication, base.id);
      equal(reopened.previousFailures, base.failedSessions);
      check(!await progression.stale(reopened));
      final fixed = await progression.accept(
        's2',
        'bench-heavy',
        reopened.version,
        instant(3).add(const Duration(hours: 3)),
      );
      equal(fixed.failedSessions, 0);
      equal(fixed.sequence, failed.sequence);
      final next = await service.start('s3', definition().id, 1, instant(5));
      final heavy = next.sets.firstWhere((s) => s.slotId == 'bench-heavy');
      equal(
        heavy.suggested['reps']!.value,
        fixed.nextSets.first['reps']!.value,
      );
      check(
        heavy.suggested['reps']!.compareTo(base.nextSets.first['reps']!) > 0,
      );

      // A later session may already have used the result: reconcile instead.
      await _correct(store, 's2', '8');
      equal(
        await _code(
          () => progression.reopen(
            's2',
            'bench-heavy',
            fixed.version,
            confirm: true,
          ),
        ),
        'conflict',
      );
      // The reopened history survives both portability formats.
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
  });
}
