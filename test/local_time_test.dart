import 'dart:io';
import 'package:test/test.dart' show expectLater, throwsA, isA;
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'fixtures.dart';
import 'support.dart';

void localTimeTests() {
  test('timestamps format in the offset they were entered with', () {
    equal(parseOffsetMinutes('2026-09-07T18:00:00+02:00', 'at'), 120);
    equal(parseOffsetMinutes('2026-09-07T18:00:00-03:30', 'at'), -210);
    equal(parseOffsetMinutes('2026-09-07T18:00:00Z', 'at'), 0);
    final at = parseInstant('2026-09-07T18:00:00.250+02:00', 'at');
    equal(formatInstant(at, 120), '2026-09-07T18:00:00.250+02:00');
    equal(formatInstant(at, -210), '2026-09-07T12:30:00.250-03:30');
    // UTC entries keep exactly the previous serialization.
    equal(formatInstant(at, 0), at.toUtc().toIso8601String());
    rejects(() => checkOffsetMinutes(24 * 60, 'at'));
  });

  test('sessions and runs keep their local start and finish times', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-local-');
    final store = await TrainingStore.open('${dir.path}/db.sqlite');
    try {
      final service = StoredTrainingService(store);
      await service.publish(
        WorkoutDefinition.fromJson(example('upper-a')['definition']),
        0,
      );
      const start = '2026-09-07T18:00:00+02:00';
      final at = parseInstant(start, 'startedAt');
      final started = await service.start(
        'evening',
        'upper-a',
        1,
        at,
        startOffsetMinutes: 120,
      );
      equal(started.toJson()['startedAt'], '2026-09-07T18:00:00.000+02:00');
      // Finished the next morning in another zone; the instant governs the
      // elapsed time, the offset only the wall clock.
      final finished = await service.edit(
        'evening',
        started.contentVersion,
        (s) => const TrainingService()
            .skipRemaining(s, confirm: true)
            .finish(
              parseInstant('2026-09-08T07:00:00-04:00', 'finishedAt'),
              offsetMinutes: -240,
            ),
      );
      final stored = (await store.session('evening'))!;
      equal(stored.toJson()['finishedAt'], '2026-09-08T07:00:00.000-04:00');
      equal(stored.startOffsetMinutes, 120);
      equal(stored.finishOffsetMinutes, -240);
      jsonEqual(sessionFromJson(stored.toJson()).toJson(), stored.toJson());
      final summary = const TrainingAnalytics().summary(finished);
      equal(summary['startedAt'], '2026-09-07T18:00:00.000+02:00');
      equal((summary['elapsed'] as Map)['value'], '68400');

      // Retrying a start is the same request only with the same offset.
      equal(
        (await service.start(
          'evening',
          'upper-a',
          1,
          at,
          startOffsetMinutes: 120,
        )).contentVersion,
        stored.contentVersion,
      );
      await expectLater(
        service.start('evening', 'upper-a', 1, at),
        throwsA(isA<BodyTmiException>()),
      );

      final programs = ProgramService(store);
      await programs.publish(
        ProgramDefinition.fromJson({
          'id': 'p',
          'name': 'P',
          'plan': {
            'id': 'day',
            'type': 'day',
            'templateId': 'upper-a',
            'revision': 1,
          },
        }),
        0,
      );
      final run = await programs.create(
        'r',
        'p',
        1,
        at,
        loop: true,
        offsetMinutes: 120,
      );
      equal(run.toJson()['startedAt'], '2026-09-07T18:00:00.000+02:00');
      equal(
        ProgramRun.fromJson(run.toJson()).startOffsetMinutes,
        run.startOffsetMinutes,
      );
      await expectLater(
        programs.create('r', 'p', 1, at, loop: true),
        throwsA(isA<BodyTmiException>()),
      );
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });
}
