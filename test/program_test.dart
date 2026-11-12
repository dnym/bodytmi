import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:bodytmi_storage/src/schema.dart';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart' show expectLater, throwsA, isA;
import 'cli_test.dart';
import 'fixtures.dart';
import 'support.dart';

ProgramDefinition _program(String id, {int revision = 1}) =>
    ProgramDefinition.fromJson({
      'id': id,
      'name': id,
      'plan': {
        'id': 'cycle',
        'type': 'group',
        'label': 'Cycle',
        'children': [
          {
            'id': 'a',
            'type': 'day',
            'label': 'First day',
            'templateId': definition().id,
            'revision': revision,
          },
          {
            'id': 'b',
            'type': 'day',
            'label': 'Second day',
            'templateId': definition().id,
            'revision': revision,
          },
        ],
      },
    });
Map<String, Object?> _rule() =>
    jsonObject(example('double-progression')['rule'], 'rule');
DateTime _finish(int day) => instant(day).add(const Duration(hours: 1));
DateTime _accept(int day) => instant(day).add(const Duration(hours: 2));
Future<void> _setup(TrainingStore store) async {
  await StoredTrainingService(store).publish(definition(), 0);
  await ProgramService(store).publish(_program('strength'), 0);
  await ProgramService(store).publish(_program('cardio'), 0);
  await ProgramService(store).create('strength-run', 'strength', 1, instant(1));
  await ProgramService(store).create('cardio-run', 'cardio', 1, instant(1));
}

Future<TrainingSession> _start(
  TrainingStore store,
  String run,
  String id,
  int day,
) async {
  final service = ProgramService(store);
  final state = await service.run(run);
  return service.start(run, state.contentVersion, id, instant(day));
}

Future<TrainingSession> _done(TrainingStore store, TrainingSession session) =>
    StoredTrainingService(
      store,
    ).edit(session.id, session.contentVersion, finished);

void programTests() {
  test(
    'associated repeat finalization and program cursor commit together on process death',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-run-repeat-crash-',
      );
      final path = '${dir.path}/db.sqlite';
      try {
        final store = await TrainingStore.open(path);
        try {
          await _setup(store);
          final session = await _start(store, 'strength-run', 'session', 1);
          final service = RepeatCheckpointService(store);
          final loop = WindowRepeatSpec.fromJson(
            example('window-repeat-page')['loop'],
          );
          await service.save(
            'repeat',
            0,
            const WindowRepeatExecution().start(loop),
            sessionId: session.id,
          );
          await service.action(
            'repeat',
            expectedVersion: 1,
            expectedExecutionVersion: 1,
            action: 'stop',
            confirm: true,
          );
        } finally {
          await store.close();
        }
        final binary = await compileNative(
          'test/helpers/store_owner.dart',
          '${dir.path}/owner',
        );
        for (final mode in ['finish-rollback', 'finish-commit']) {
          final child = await Process.start(binary, [
            path,
            mode,
            'session',
            instant(1).add(const Duration(hours: 1)).toIso8601String(),
          ]);
          final errors = child.stderr.transform(utf8.decoder).join();
          try {
            equal(
              await child.stdout
                  .transform(utf8.decoder)
                  .transform(const LineSplitter())
                  .first
                  .timeout(const Duration(seconds: 15)),
              'ready',
            );
            child.kill(ProcessSignal.sigkill);
            await child.exitCode;
            equal(await errors, '');
            final recovered = await TrainingStore.open(path);
            try {
              final committed = mode.endsWith('commit');
              equal(
                (await StoredTrainingService(
                  recovered,
                ).session('session')).status,
                committed ? SessionStatus.finalized : SessionStatus.active,
              );
              equal(
                (await ProgramService(recovered).run('strength-run')).cursor,
                committed ? 1 : 0,
              );
              equal(
                (await ProgramService(recovered).run('cardio-run')).cursor,
                0,
              );
              equal(
                (await RepeatCheckpointService(
                  recovered,
                ).show('repeat')).sessionId,
                'session',
              );
            } finally {
              await recovered.close();
            }
          } finally {
            child.kill(ProcessSignal.sigkill);
            await child.exitCode;
          }
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'associated repeats block only their session finalization and do not replay program advancement',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-run-repeat-binding-',
      );
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        await _setup(store);
        final strength = await _start(
          store,
          'strength-run',
          'strength-session',
          1,
        );
        final cardio = await _start(store, 'cardio-run', 'cardio-session', 1);
        final service = RepeatCheckpointService(store);
        final loop = WindowRepeatSpec.fromJson(
          example('window-repeat-page')['loop'],
        );
        final start = const WindowRepeatExecution().start(loop);
        var repeat = await service.save(
          'strength-repeat',
          0,
          start,
          sessionId: strength.id,
        );
        equal(repeat.sessionId, strength.id);
        await expectLater(
          _done(store, strength),
          throwsA(isA<BodyTmiException>()),
        );
        equal((await ProgramService(store).run('strength-run')).cursor, 0);
        final cardioDone = await _done(store, cardio);
        equal((await ProgramService(store).run('cardio-run')).cursor, 1);
        equal((await ProgramService(store).run('strength-run')).cursor, 0);
        await expectLater(
          service.save('bad', 0, start, sessionId: cardioDone.id),
          throwsA(isA<BodyTmiException>()),
        );
        await expectLater(
          service.save('missing', 0, start, sessionId: 'unknown'),
          throwsA(isA<BodyTmiException>()),
        );
        await expectLater(
          service.save('strength-repeat', 1, start, sessionId: cardio.id),
          throwsA(isA<BodyTmiException>()),
        );
        repeat = await service.action(
          'strength-repeat',
          expectedVersion: 1,
          expectedExecutionVersion: 1,
          action: 'review',
          review: {'outcome': 'completed', 'acceptSuggested': true},
        );
        repeat = await service.action(
          'strength-repeat',
          expectedVersion: 2,
          expectedExecutionVersion: 2,
          action: 'stop',
          confirm: true,
        );
        equal(repeat.sessionId, strength.id);
        final finishedStrength = await _done(store, strength);
        equal((await ProgramService(store).run('strength-run')).cursor, 1);
        repeat = await service.action(
          'strength-repeat',
          expectedVersion: 3,
          expectedExecutionVersion: 3,
          action: 'correct',
          correction: {
            'occurrenceId': 'amrap[0]/round/push-set',
            'actuals': {
              'reps': {'value': '3', 'unit': 'rep'},
            },
          },
        );
        equal(repeat.sessionId, strength.id);
        await StoredTrainingService(store).edit(
          finishedStrength.id,
          finishedStrength.contentVersion,
          (session) => session.finish(session.finishedAt!),
        );
        equal((await ProgramService(store).run('strength-run')).cursor, 1);
        final reopened = {...start, 'version': 5};
        await expectLater(
          service.save('strength-repeat', 4, reopened),
          throwsA(isA<BodyTmiException>()),
        );
        final forged = copyJson((await store.archive()).toJson());
        jsonObject(
          jsonList(forged, 'repeatCheckpoints').single,
          'repeat',
        )['sessionId'] = 'missing';
        rejects(() => TrainingArchive.fromJson(forged));
        final unfinished = copyJson((await store.archive()).toJson());
        jsonObject(
          jsonList(unfinished, 'repeatCheckpoints').single,
          'repeat',
        )['execution'] = start;
        rejects(() => TrainingArchive.fromJson(unfinished));
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'guided target edits stay within the selected active program run',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-run-target-');
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        await _setup(store);
        final strength = await _start(
          store,
          'strength-run',
          'strength-edit',
          1,
        );
        final cardio = await _start(store, 'cardio-run', 'cardio-edit', 1);
        final programs = ProgramService(store);
        final cardioRun = canonicalJson(
          (await programs.run('cardio-run')).toJson(),
        );
        final beforeCardio = canonicalJson(cardio.toJson());
        final execution = await ExecutionService(
          store,
        ).start('strength-execution', strength.id, instant(1));
        final edited = await StoredTrainingService(store).editTarget(
          strength.id,
          strength.contentVersion,
          strength.sets.first.id,
          'mass',
          Quantity('70', 'kg'),
          applyToRemaining: true,
        );
        check(edited.sets.first.manualTargets.contains('mass'));
        equal(
          canonicalJson(
            (await StoredTrainingService(store).session(cardio.id)).toJson(),
          ),
          beforeCardio,
        );
        equal(
          canonicalJson((await programs.run('cardio-run')).toJson()),
          cardioRun,
        );
        equal((await programs.run('strength-run')).cursor, 0);
        equal((await ExecutionService(store).show(execution.id)).cursor, 0);
        equal((await store.progressionDecisions()).length, 0);
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'program groups and repeats have stable finite paths and reject invalid or unbounded definitions',
    () {
      final j = _program('nested').toJson();
      j['plan'] = {
        'id': 'block',
        'type': 'repeat',
        'count': 3,
        'child': j['plan'],
      };
      final p = ProgramDefinition.fromJson(j);
      equal(p.dayCount, 6);
      final days = p.plan.occurrences().toList();
      equal(days.map((d) => d.path).toSet().length, 6);
      equal(days.first.path, 'block[0]/cycle/a');
      equal(days.last.path, 'block[2]/cycle/b');
      equal(p.dayAt(7).path, 'block[0]/cycle/b');
      jsonEqual(ProgramDefinition.fromJson(p.toJson()).toJson(), p.toJson());
      final duplicate = copyJson(j);
      jsonObject(
        jsonObject(duplicate['plan'], 'repeat')['child'],
        'group',
      )['id'] = 'a';
      rejects(() => ProgramDefinition.fromJson(duplicate));
      final huge = copyJson(j);
      jsonObject(huge['plan'], 'repeat')['count'] = 10000;
      rejects(() => ProgramDefinition.fromJson(huge));
      final unbounded = copyJson(j);
      jsonObject(unbounded['plan'], 'repeat').remove('count');
      rejects(() => ProgramDefinition.fromJson(unbounded));
      final bad = copyJson(j);
      jsonObject(bad['plan'], 'plan')['overrides'] = {};
      rejects(() => ProgramDefinition.fromJson(bad));
    },
  );

  test(
    'run schedules show bounded authored days and independent run state without mutation',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-schedule-');
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        await _setup(store);
        final programs = ProgramService(store);
        final nested = _program('nested').toJson();
        nested['plan'] = {
          'id': 'block',
          'type': 'repeat',
          'label': 'Strength phase',
          'count': 2,
          'child': nested['plan'],
        };
        await programs.publish(ProgramDefinition.fromJson(nested), 0);
        await programs.create('nested-run', 'nested', 1, instant(1));
        final before = canonicalJson((await store.archive()).toJson());
        final schedule = await programs.schedule('nested-run', count: 6);
        equal(schedule['policy'], 'bodytmi-program-run-schedule/1');
        equal(schedule['cycleLength'], 4);
        equal(schedule['remaining'], null);
        equal(schedule['hasMore'], true);
        final days = jsonList(schedule, 'days');
        equal(jsonObject(days[0], 'day')['path'], 'block[0]/cycle/a');
        equal(jsonObject(days[3], 'day')['path'], 'block[1]/cycle/b');
        equal(jsonObject(days[4], 'day')['path'], 'block[0]/cycle/a');
        equal(jsonObject(days[4], 'day')['cycle'], 1);
        equal(jsonObject(days[4], 'day')['ordinal'], 4);
        check(!jsonObject(days[0], 'day').containsKey('scopes'));
        final scoped = await programs.schedule(
          'nested-run',
          count: 6,
          includeScopes: true,
        );
        equal(scoped['policy'], 'bodytmi-program-run-schedule/2');
        final scopedDays = jsonList(scoped, 'days');
        final firstScopes = jsonList(
          jsonObject(scopedDays[0], 'day'),
          'scopes',
        );
        equal(firstScopes.length, 2);
        final repeat = jsonObject(firstScopes[0], 'repeat');
        equal(repeat['path'], 'block[0]');
        equal(repeat['label'], 'Strength phase');
        equal(repeat['iteration'], 0);
        equal(repeat['count'], 2);
        final group = jsonObject(firstScopes[1], 'group');
        equal(group['path'], 'block[0]/cycle');
        equal(group['label'], 'Cycle');
        final secondScopes = jsonList(
          jsonObject(scopedDays[3], 'day'),
          'scopes',
        );
        equal(jsonObject(secondScopes.first, 'scope')['iteration'], 1);
        final repeatedCycle = jsonObject(scopedDays[4], 'day');
        equal(repeatedCycle['cycle'], 1);
        equal(
          jsonObject(
            jsonList(repeatedCycle, 'scopes').first,
            'scope',
          )['iteration'],
          0,
        );
        equal(canonicalJson((await store.archive()).toJson()), before);
        final revised = copyJson(nested);
        jsonObject(revised['plan'], 'repeat')['label'] = 'New phase';
        await programs.publish(ProgramDefinition.fromJson(revised), 1);
        final pinned = await programs.schedule(
          'nested-run',
          count: 1,
          includeScopes: true,
        );
        final pinnedScopes = jsonList(
          jsonObject(jsonList(pinned, 'days').single, 'day'),
          'scopes',
        );
        equal(
          jsonObject(pinnedScopes.first, 'scope')['label'],
          'Strength phase',
        );
        await _start(store, 'strength-run', 'strength-session', 1);
        final strength = await programs.schedule('strength-run', count: 1);
        equal(
          jsonObject(jsonList(strength, 'days').first, 'day')['sessionId'],
          'strength-session',
        );
        final cardio = await programs.schedule('cardio-run', count: 1);
        check(
          !jsonObject(
            jsonList(cardio, 'days').first,
            'day',
          ).containsKey('sessionId'),
        );
        final paused = await programs.status(
          'strength-run',
          (await programs.run('strength-run')).contentVersion,
          'paused',
        );
        final view = await programs.schedule('strength-run', count: 1);
        equal(view['status'], 'paused');
        equal(view['runVersion'], paused.contentVersion);
        await expectLater(
          programs.schedule('strength-run', count: 0),
          throwsA(isA<BodyTmiException>()),
        );
        await expectLater(
          programs.schedule('strength-run', count: 1001),
          throwsA(isA<BodyTmiException>()),
        );
        await expectLater(
          programs.schedule('missing'),
          throwsA(isA<BodyTmiException>()),
        );
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'finite run schedules shrink after skips and become empty when complete',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-schedule-finite-',
      );
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        await StoredTrainingService(store).publish(definition(), 0);
        final programs = ProgramService(store);
        await programs.publish(_program('finite'), 0);
        await programs.create(
          'finite-run',
          'finite',
          1,
          instant(1),
          loop: false,
        );
        final partial = await programs.schedule('finite-run', count: 1);
        equal(partial['hasMore'], true);
        equal(jsonList(partial, 'days').length, 1);
        final before = await programs.schedule('finite-run', count: 10);
        equal(before['remaining'], 2);
        equal(before['hasMore'], false);
        equal(jsonList(before, 'days').length, 2);
        await programs.skip('finite-run', 1, 'skip-1', instant(1));
        final after = await programs.schedule('finite-run', count: 1);
        equal(after['remaining'], 1);
        equal(
          jsonObject(jsonList(after, 'days').single, 'day')['path'],
          'cycle/b',
        );
        await programs.skip('finite-run', 2, 'skip-2', instant(1));
        final done = await programs.schedule('finite-run');
        equal(done['status'], 'completed');
        equal(done['remaining'], 0);
        equal(done['hasMore'], false);
        check(jsonList(done, 'days').isEmpty);
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'skip remaining is neutral, atomic and advances only on explicit finish',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-skip-remaining-',
      );
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        await _setup(store);
        final programs = ProgramService(store);
        final training = StoredTrainingService(store);
        var session = await _start(store, 'strength-run', 'partial-session', 1);
        final original = session;
        final previousProfile = '${dir.path}/v35.sqlite';
        await store.snapshot(previousProfile);
        final oldDb = sqlite3.open(previousProfile);
        oldDb.execute('DROP TABLE IF EXISTS repeat_checkpoints');
        oldDb.execute('DROP TABLE IF EXISTS window_checkpoints');
        oldDb.userVersion = 35;
        oldDb.close();
        equal(NativeBackup.validateDatabase(previousProfile), 35);
        final migrated = await TrainingStore.open(previousProfile);
        equal(
          canonicalJson(
            (await StoredTrainingService(
              migrated,
            ).session(session.id)).toJson(),
          ),
          canonicalJson(session.toJson()),
        );
        await migrated.close();
        session = await training.editTarget(
          session.id,
          session.contentVersion,
          session.sets.first.id,
          'mass',
          Quantity('67.5', 'kg'),
          applyToRemaining: true,
        );
        check(
          session.sets
              .where((s) => s.slotId == session.sets.first.slotId)
              .every((s) => s.manualTargets.contains('mass')),
        );
        await expectLater(
          training.editTarget(
            session.id,
            original.contentVersion,
            session.sets.first.id,
            'mass',
            Quantity('70', 'kg'),
          ),
          throwsA(isA<BodyTmiException>()),
        );
        equal((await programs.run('strength-run')).cursor, 0);
        equal((await programs.run('cardio-run')).cursor, 0);
        await store.backup('${dir.path}/manual-backup');
        final export = '${dir.path}/manual.json';
        await LogicalArchiveFiles.export(await store.archive(), export);
        final editedArchive = await LogicalArchiveFiles.prepare(export);
        await editedArchive.close();
        final envelope =
            jsonDecode(await File(export).readAsString())
                as Map<String, Object?>;
        envelope['format'] = 'bodytmi-logical-export/35';
        envelope['sha256'] = sha256
            .convert(
              utf8.encode(
                canonicalJson({
                  for (final entry in envelope.entries)
                    if (entry.key != 'sha256') entry.key: entry.value,
                }),
              ),
            )
            .toString();
        final oldExport = '${dir.path}/old-manual.json';
        await File(oldExport).writeAsString(jsonEncode(envelope));
        await expectLater(
          LogicalArchiveFiles.prepare(oldExport),
          throwsA(isA<BodyTmiException>()),
        );
        final snapshot = '${dir.path}/manual.sqlite';
        await store.snapshot(snapshot);
        equal(NativeBackup.validateDatabase(snapshot), 51);
        final oldLabel = sqlite3.open(snapshot);
        oldLabel.execute('DROP TABLE IF EXISTS repeat_checkpoints');
        oldLabel.execute('DROP TABLE IF EXISTS window_checkpoints');
        oldLabel.userVersion = 35;
        oldLabel.close();
        rejects(() => NativeBackup.validateDatabase(snapshot));
        session = await training.edit(
          session.id,
          session.contentVersion,
          (s) => const TrainingService().complete(s, s.sets.first.id, {
            'mass': Quantity('65', 'kg'),
          }, acceptSuggested: true),
        );
        final completed = canonicalJson(session.sets.first.toJson());
        final cardioBefore = canonicalJson(
          (await programs.run('cardio-run')).toJson(),
        );
        await expectLater(
          training.skipRemaining(
            session.id,
            session.contentVersion,
            confirm: false,
          ),
          throwsA(isA<BodyTmiException>()),
        );
        await expectLater(
          training.skipRemaining(
            session.id,
            session.contentVersion + 1,
            confirm: true,
          ),
          throwsA(isA<BodyTmiException>()),
        );
        final skipped = await training.skipRemaining(
          session.id,
          session.contentVersion,
          confirm: true,
        );
        equal(skipped.contentVersion, session.contentVersion + 1);
        equal(canonicalJson(skipped.sets.first.toJson()), completed);
        check(skipped.sets.skip(1).every((s) => s.status == SetStatus.skipped));
        equal((await programs.run('strength-run')).cursor, 0);
        equal(
          canonicalJson((await programs.run('cardio-run')).toJson()),
          cardioBefore,
        );
        equal((await store.progressionDecisions()).length, 0);
        final noop = await training.skipRemaining(
          skipped.id,
          skipped.contentVersion,
          confirm: true,
        );
        equal(noop.contentVersion, skipped.contentVersion);
        final done = await training.edit(
          skipped.id,
          skipped.contentVersion,
          (s) => s.finish(_finish(1)),
        );
        await training.edit(
          done.id,
          done.contentVersion,
          (s) => s.finish(_finish(1)),
        );
        equal((await programs.run('strength-run')).cursor, 1);
        equal((await programs.run('cardio-run')).cursor, 0);
        equal(
          (await store.programReceipts())
              .where((r) => r.runId == 'strength-run')
              .length,
          1,
        );
        equal((await store.progressionDecisions()).length, 0);
        await LogicalArchiveFiles.export(
          await store.archive(),
          '${dir.path}/archive.json',
        );
        final prepared = await LogicalArchiveFiles.prepare(
          '${dir.path}/archive.json',
        );
        try {
          equal(
            prepared.archive.sessions.single.sets.first.actuals['mass']!.value
                .toString(),
            '65',
          );
        } finally {
          await prepared.close();
        }
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'two active runs isolate cursor, raw history and accepted targets despite sharing one workout template',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-multi-program-',
      );
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        await _setup(store);
        equal(
          (await store.programRuns()).where((r) => r.status == 'active').length,
          2,
        );
        var strength = await _done(
          store,
          await _start(store, 'strength-run', 'strength-1', 1),
        );
        strength = await StoredTrainingService(store).edit(
          strength.id,
          strength.contentVersion,
          (s) => const TrainingService().complete(s, s.sets.first.id, {
            ...s.sets.first.actuals,
            'mass': Quantity('70', 'kg'),
          }),
        );
        final cardio = await _start(store, 'cardio-run', 'cardio-1', 2);
        equal(cardio.sets.first.suggested['mass']!.value.toString(), '60');
        check(cardio.sets.first.sources.isEmpty);
        equal((await ProgramService(store).run('strength-run')).cursor, 1);
        equal((await ProgramService(store).run('cardio-run')).cursor, 0);
        strength = await StoredTrainingService(store).edit(
          strength.id,
          strength.contentVersion,
          (s) => const TrainingService().complete(s, s.sets.first.id, {
            ...s.sets.first.actuals,
            'mass': Quantity('60', 'kg'),
          }),
        );
        final progression = StoredProgressionService(store);
        final proposal = await progression.propose(
          strength.id,
          'bench-heavy',
          _rule(),
        );
        equal(proposal.runId, 'strength-run');
        await progression.accept(
          strength.id,
          'bench-heavy',
          proposal.version,
          _accept(2),
        );
        final next = await _start(store, 'strength-run', 'strength-2', 3);
        equal(next.sets.first.suggested['reps']!.value.toString(), '9');
        equal(cardio.sets.first.suggested['reps']!.value.toString(), '8');
        await _done(store, cardio);
        final cardioProposal = await progression.propose(
          cardio.id,
          'bench-heavy',
          _rule(),
        );
        equal(cardioProposal.previousApplication, null);
        equal(cardioProposal.previousFailures, 0);
        await progression.accept(
          cardio.id,
          'bench-heavy',
          cardioProposal.version,
          _accept(3),
        );
        equal(
          (await progression.decision(strength.id, 'bench-heavy')).sequence,
          1,
        );
        equal(
          (await progression.decision(cardio.id, 'bench-heavy')).sequence,
          1,
        );
        final adhoc = await StoredTrainingService(
          store,
        ).start('adhoc', definition().id, 1, instant(4));
        equal(adhoc.sets.first.suggested['reps']!.value.toString(), '8');
        check(adhoc.sets.first.sources.isEmpty);
        await store.archive();
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'skips are neutral and retry-safe, finite runs finish and rotating runs keep separate occurrence identities',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-program-skips-',
      );
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        await StoredTrainingService(store).publish(definition(), 0);
        final service = ProgramService(store);
        await service.publish(_program('p'), 0);
        final run = await service.create(
          'finite',
          'p',
          1,
          instant(1),
          loop: false,
        );
        final first = await service.skip(
          run.id,
          run.contentVersion,
          'request-1',
          _finish(1),
        );
        jsonEqual(
          (await service.skip(
            run.id,
            run.contentVersion,
            'request-1',
            _finish(1),
          )).toJson(),
          first.toJson(),
        );
        equal((await service.run(run.id)).cursor, 1);
        await expectLater(
          service.skip(run.id, run.contentVersion, 'new-request', _finish(2)),
          throwsA(isA<BodyTmiException>()),
        );
        final current = await service.run(run.id);
        await service.skip(
          run.id,
          current.contentVersion,
          'request-2',
          _finish(2),
        );
        final complete = await service.run(run.id);
        equal(complete.status, 'completed');
        equal(complete.current, null);
        await expectLater(
          service.status(run.id, complete.contentVersion, 'active'),
          throwsA(isA<BodyTmiException>()),
        );
        final rotating = await service.create('rotation', 'p', 1, instant(1));
        for (var n = 0; n < 5; n++) {
          final r = await service.run(rotating.id);
          await service.skip(
            r.id,
            r.contentVersion,
            'rotation-$n',
            _finish(n + 1),
          );
        }
        final fifth = await service.run(rotating.id);
        equal(fifth.cursor, 5);
        equal(fifth.current!.path, 'cycle/b');
        equal((await store.sessions()).length, 0);
        equal((await store.progressionDecisions()).length, 0);
        await store.archive();
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'pause blocks new occurrences, existing sessions resume and finalization advances once even after corrections',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-program-resume-',
      );
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        await _setup(store);
        final service = ProgramService(store);
        final initial = await service.run('strength-run');
        var session = await service.start(
          initial.id,
          initial.contentVersion,
          'attached',
          instant(1),
        );
        await expectLater(
          service.start(
            initial.id,
            initial.contentVersion,
            'duplicate',
            instant(1),
          ),
          throwsA(isA<BodyTmiException>()),
        );
        final afterStart = await service.run(initial.id);
        await expectLater(
          StoredTrainingService(store).start(
            'stale-direct-start',
            definition().id,
            1,
            instant(1),
            programRun: initial,
          ),
          throwsA(isA<BodyTmiException>()),
        );
        await expectLater(
          StoredTrainingService(store).edit(
            session.id,
            session.contentVersion,
            (s) => TrainingSession(
              id: 'replacement',
              revision: s.revision,
              startedAt: s.startedAt,
              sets: s.sets,
            ),
          ),
          throwsA(isA<BodyTmiException>()),
        );
        equal(await store.session('stale-direct-start'), null);
        equal(
          (await service.run(initial.id)).contentVersion,
          afterStart.contentVersion,
        );
        final paused = await service.status(
          initial.id,
          afterStart.contentVersion,
          'paused',
        );
        jsonEqual(
          (await service.start(
            initial.id,
            initial.contentVersion,
            'attached',
            instant(1),
          )).toJson(),
          session.toJson(),
        );
        await expectLater(
          service.start(initial.id, paused.contentVersion, 'new', instant(2)),
          throwsA(isA<BodyTmiException>()),
        );
        await expectLater(
          service.skip(initial.id, paused.contentVersion, 'skip', _finish(2)),
          throwsA(isA<BodyTmiException>()),
        );
        await expectLater(
          StoredTrainingService(
            store,
          ).start('attached', definition().id, 1, instant(1)),
          throwsA(isA<BodyTmiException>()),
        );
        session = await _done(store, session);
        equal((await service.run(initial.id)).cursor, 1);
        equal((await service.run(initial.id)).status, 'paused');
        session = await StoredTrainingService(store).edit(
          session.id,
          session.contentVersion,
          (s) => const TrainingService().complete(s, s.sets.first.id, {
            ...s.sets.first.actuals,
            'reps': Quantity('10', 'rep'),
          }),
        );
        await StoredTrainingService(
          store,
        ).edit(session.id, session.contentVersion, (s) => s.finish(_finish(2)));
        equal((await store.programReceipts()).length, 1);
        equal((await service.run(initial.id)).cursor, 1);
        final state = await service.run(initial.id);
        await service.status(initial.id, state.contentVersion, 'active');
        final active = await service.run(initial.id);
        await _start(store, initial.id, 'next', 3);
        await expectLater(
          service.skip(
            initial.id,
            active.contentVersion + 1,
            'occupied',
            _finish(3),
          ),
          throwsA(isA<BodyTmiException>()),
        );
        equal((await service.run('cardio-run')).cursor, 0);
        await store.archive();
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'published programs pin workout revisions and existing runs ignore later library edits',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-program-pins-',
      );
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        await _setup(store);
        final service = ProgramService(store);
        final raw = definition().toJson();
        final slot = jsonObject((raw['slots']! as List<Object?>).first, 'slot');
        jsonObject(slot['targets'], 'targets')['mass'] = {
          'value': '80',
          'unit': 'kg',
        };
        await StoredTrainingService(
          store,
        ).publish(WorkoutDefinition.fromJson(raw), 1);
        await service.publish(_program('strength', revision: 2), 1);
        final old = await _start(store, 'strength-run', 'old-pin', 1);
        equal(old.revision.number, 1);
        equal(old.sets.first.suggested['mass']!.value.toString(), '60');
        await service.create('new-run', 'strength', 2, instant(1));
        final newer = await _start(store, 'new-run', 'new-pin', 2);
        equal(newer.revision.number, 2);
        equal(newer.sets.first.suggested['mass']!.value.toString(), '80');
        await expectLater(
          service.publish(_program('missing', revision: 99), 0),
          throwsA(isA<BodyTmiException>()),
        );
        check(
          !(await store.programRevisions()).any(
            (p) => p.definition.id == 'missing',
          ),
        );
        await store.archive();
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'program definitions, active bindings, receipts and isolated progression survive both portability formats',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-program-backup-',
      );
      var store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        await _setup(store);
        final done = await _done(
          store,
          await _start(store, 'strength-run', 'done', 1),
        );
        final progression = StoredProgressionService(store);
        final p = await progression.propose(done.id, 'bench-heavy', _rule());
        await progression.accept(done.id, 'bench-heavy', p.version, _accept(1));
        await _start(store, 'cardio-run', 'pending', 2);
        final original = canonicalJson((await store.archive()).toJson());
        equal(
          (await store.backup('${dir.path}/native'))['databaseSchemaVersion'],
          51,
        );
        equal(
          (await LogicalArchiveFiles.export(
            await store.archive(),
            '${dir.path}/logical.json',
          ))['format'],
          'bodytmi-logical-export/51',
        );
        final prepared = await LogicalArchiveFiles.prepare(
          '${dir.path}/logical.json',
        );
        try {
          equal(canonicalJson(prepared.archive.toJson()), original);
          await store.restore(
            prepared.backup,
            recoveryDestination: '${dir.path}/recovery',
            confirm: true,
          );
        } finally {
          await prepared.close();
        }
        await store.close();
        store = await TrainingStore.open('${dir.path}/db.sqlite');
        equal(canonicalJson((await store.archive()).toJson()), original);
        final native = await NativeBackup.prepare('${dir.path}/native');
        try {
          await store.restore(
            native,
            recoveryDestination: '${dir.path}/second-recovery',
            confirm: true,
          );
        } finally {
          await native.close();
        }
        await store.close();
        store = await TrainingStore.open('${dir.path}/db.sqlite');
        equal(canonicalJson((await store.archive()).toJson()), original);
        final next = await _start(store, 'strength-run', 'next', 3);
        equal(next.sets.first.suggested['reps']!.value.toString(), '9');
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'logical validation rejects forged run ownership, cursor paths, missing and duplicate receipts',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-program-invalid-',
      );
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        await _setup(store);
        final done = await _done(
          store,
          await _start(store, 'strength-run', 'done', 1),
        );
        final progression = StoredProgressionService(store);
        final p = await progression.propose(done.id, 'bench-heavy', _rule());
        await progression.accept(done.id, 'bench-heavy', p.version, _accept(1));
        await _start(store, 'cardio-run', 'pending', 2);
        final base = (await store.archive()).toJson();
        final mutations = <void Function(Map<String, Object?>)>[
          (j) => jsonObject(
            (j['programRuns']! as List<Object?>).first,
            'run',
          )['cursor'] = 99,
          (j) => (j['programReceipts']! as List<Object?>).clear(),
          (j) => (j['programReceipts']! as List<Object?>).add(
            (j['programReceipts']! as List<Object?>).first,
          ),
          (j) => jsonObject(
            (j['sessionPrograms']! as List<Object?>).first,
            'binding',
          )['path'] = 'forged',
          (j) => jsonObject(
            (j['progressions']! as List<Object?>).first,
            'decision',
          )['runId'] = 'cardio-run',
          (j) => jsonObject(
            (j['progressions']! as List<Object?>).first,
            'decision',
          ).remove('runId'),
          (j) => jsonObject(
            (j['sessionPrograms']! as List<Object?>).first,
            'binding',
          )['runId'] = 'missing-run',
          (j) => jsonObject(
            jsonObject(
              jsonObject(
                (j['programRuns']! as List<Object?>).first,
                'run',
              )['program'],
              'program',
            )['definition'],
            'definition',
          )['name'] = 'forged',
        ];
        for (final mutate in mutations) {
          final j = copyJson(base);
          mutate(j);
          rejects(() => TrainingArchive.fromJson(j));
        }
        await LogicalArchiveFiles.export(
          await store.archive(),
          '${dir.path}/new.json',
        );
        final file = File('${dir.path}/new.json');
        final doc = jsonObject(
          jsonDecode(await file.readAsString()),
          'document',
        );
        jsonObject(doc['data'], 'data').remove('families');
        doc['format'] = 'bodytmi-logical-export/2';
        doc.remove('sha256');
        doc['sha256'] = sha256
            .convert(utf8.encode(canonicalJson(doc)))
            .toString();
        await file.writeAsString(jsonEncode(doc));
        await expectLater(
          LogicalArchiveFiles.prepare(file.path),
          throwsA(isA<BodyTmiException>()),
        );
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'native program CLI selects runs and exposes cursor/resume state without a global active program',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-program-cli-');
      try {
        final path = '${dir.path}/db.sqlite';
        Future<Object?> call(String action, Map<String, Object?> fields) async {
          final r = await invoke(
            action.split(' '),
            jsonEncode({'schemaVersion': 1, 'database': path, ...fields}),
          );
          equal(r.code, 0);
          equal(r.error, '');
          return jsonObject(jsonDecode(r.output), 'response')['data'];
        }

        await call('store publish', {
          'definition': definition().toJson(),
          'expectedRevision': 0,
        });
        for (final p in ['strength', 'cardio']) {
          await call('program publish', {
            'definition': _program(p).toJson(),
            'expectedRevision': 0,
          });
          await call('run create', {
            'id': '$p-run',
            'programId': p,
            'revision': 1,
            'startedAt': instant(1).toIso8601String(),
          });
        }
        equal(
          (await call('run list', {'status': 'active'}) as List<Object?>)
              .length,
          2,
        );
        final upcoming = jsonObject(
          await call('run schedule', {'runId': 'strength-run', 'count': 3}),
          'schedule',
        );
        equal(jsonList(upcoming, 'days').length, 3);
        equal(jsonObject(jsonList(upcoming, 'days')[2], 'day')['cycle'], 1);
        final scoped = jsonObject(
          await call('run schedule', {
            'runId': 'strength-run',
            'count': 1,
            'includeScopes': true,
          }),
          'schedule',
        );
        final ancestry = jsonList(
          jsonObject(jsonList(scoped, 'days').single, 'day'),
          'scopes',
        );
        equal(jsonObject(ancestry.single, 'group')['label'], 'Cycle');
        var s = sessionFromJson(
          await call('run start', {
            'runId': 'strength-run',
            'expectedVersion': 1,
            'id': 'cli',
            'startedAt': instant(1).toIso8601String(),
          }),
        );
        equal(
          jsonObject(
            await call('run show', {'runId': 'strength-run'}),
            'run',
          )['currentSessionId'],
          'cli',
        );
        final bound = jsonObject(
          await call('run schedule', {'runId': 'strength-run', 'count': 1}),
          'schedule',
        );
        equal(
          jsonObject(jsonList(bound, 'days').single, 'day')['sessionId'],
          'cli',
        );
        s = sessionFromJson(
          await call('store complete', {
            'id': s.id,
            'setId': s.sets.first.id,
            'expectedVersion': s.contentVersion,
            'actuals': {
              'mass': {'value': '140', 'unit': 'lb'},
            },
            'acceptSuggested': true,
          }),
        );
        final pureCarry = await invoke(
          ['session', 'carry-actual'],
          jsonEncode({
            'schemaVersion': 1,
            'session': s.toJson(),
            'setId': s.sets.first.id,
            'metric': 'mass',
          }),
        );
        equal(pureCarry.code, 0);
        final storedCarry = await call('store carry-actual', {
          'id': s.id,
          'expectedVersion': s.contentVersion,
          'setId': s.sets.first.id,
          'metric': 'mass',
        });
        jsonEqual(
          jsonObject(jsonDecode(pureCarry.output), 'response')['data'],
          storedCarry,
        );
        s = sessionFromJson(storedCarry);
        equal(s.sets[1].carriedTargets['mass']!.setId, s.sets.first.id);
        for (final set in s.sets.skip(1))
          s = sessionFromJson(
            await call('store complete', {
              'id': s.id,
              'setId': set.id,
              'expectedVersion': s.contentVersion,
              'acceptSuggested': true,
            }),
          );
        s = sessionFromJson(
          await call('store finish', {
            'id': s.id,
            'expectedVersion': s.contentVersion,
            'finishedAt': _finish(1).toIso8601String(),
          }),
        );
        equal(
          jsonObject(
            await call('run show', {'runId': 'strength-run'}),
            'run',
          )['cursor'],
          1,
        );
        equal(
          jsonObject(
            await call('run show', {'runId': 'cardio-run'}),
            'run',
          )['cursor'],
          0,
        );
        await call('store finish', {
          'id': s.id,
          'expectedVersion': s.contentVersion,
          'finishedAt': _finish(1).toIso8601String(),
        });
        equal(
          jsonObject(
            await call('run show', {'runId': 'strength-run'}),
            'run',
          )['cursor'],
          1,
        );
        final cardioSession = await call('run start', {
          'runId': 'cardio-run',
          'expectedVersion': 1,
          'id': 'cardio-cli',
          'startedAt': instant(1).toIso8601String(),
        });
        final cardio = sessionFromJson(cardioSession);
        final firstMetric = cardio.sets.first.suggested.keys.first;
        final firstValue = cardio.sets.first.suggested[firstMetric]!.toJson();
        final pureEdit = await invoke(
          ['session', 'edit-target'],
          jsonEncode({
            'schemaVersion': 1,
            'session': cardioSession,
            'setId': cardio.sets.first.id,
            'metric': firstMetric,
            'value': firstValue,
            'applyToRemaining': true,
          }),
        );
        equal(pureEdit.code, 0);
        final storedEdit = await call('store edit-target', {
          'id': 'cardio-cli',
          'expectedVersion': cardio.contentVersion,
          'setId': cardio.sets.first.id,
          'metric': firstMetric,
          'value': firstValue,
          'applyToRemaining': true,
        });
        jsonEqual(
          jsonObject(jsonDecode(pureEdit.output), 'response')['data'],
          storedEdit,
        );
        final editedCardio = sessionFromJson(storedEdit);
        final pureSlot = await invoke(
          ['session', 'skip-slot'],
          jsonEncode({
            'schemaVersion': 1,
            'session': storedEdit,
            'slotId': cardio.sets.first.slotId,
            'role': 'work',
            'confirm': true,
          }),
        );
        equal(pureSlot.code, 0);
        final storedSlot = await call('store skip-slot', {
          'id': 'cardio-cli',
          'expectedVersion': editedCardio.contentVersion,
          'slotId': cardio.sets.first.slotId,
          'role': 'work',
          'confirm': true,
        });
        jsonEqual(
          jsonObject(jsonDecode(pureSlot.output), 'response')['data'],
          storedSlot,
        );
        final afterSlot = sessionFromJson(storedSlot);
        final refused = await invoke(
          ['store', 'skip-remaining'],
          jsonEncode({
            'schemaVersion': 1,
            'database': path,
            'id': 'cardio-cli',
            'expectedVersion': afterSlot.contentVersion,
          }),
        );
        equal(refused.code, 2);
        equal(refused.output, '');
        final pure = await invoke(
          ['session', 'skip-remaining'],
          jsonEncode({
            'schemaVersion': 1,
            'session': storedSlot,
            'confirm': true,
          }),
        );
        equal(pure.code, 0);
        final stored = await call('store skip-remaining', {
          'id': 'cardio-cli',
          'expectedVersion': afterSlot.contentVersion,
          'confirm': true,
        });
        jsonEqual(
          jsonObject(jsonDecode(pure.output), 'response')['data'],
          stored,
        );
        equal(
          jsonObject(
            await call('run show', {'runId': 'cardio-run'}),
            'run',
          )['cursor'],
          0,
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'program finalization crashes roll back or commit results, receipt and cursor together',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-program-crash-',
      );
      try {
        final path = '${dir.path}/db.sqlite';
        final store = await TrainingStore.open(path);
        try {
          await _setup(store);
          await _start(store, 'strength-run', 'crash', 1);
        } finally {
          await store.close();
        }
        final binary = await compileNative(
          'test/helpers/store_owner.dart',
          '${dir.path}/owner',
        );
        for (final mode in ['finish-rollback', 'finish-commit']) {
          final child = await Process.start(binary, [
            path,
            mode,
            'crash',
            _finish(1).toIso8601String(),
          ]);
          final errors = child.stderr.transform(utf8.decoder).join();
          try {
            equal(
              await child.stdout
                  .transform(utf8.decoder)
                  .transform(const LineSplitter())
                  .first
                  .timeout(const Duration(seconds: 15)),
              'ready',
            );
            child.kill(ProcessSignal.sigkill);
            await child.exitCode;
            equal(await errors, '');
            final recovered = await TrainingStore.open(path);
            try {
              final committed = mode == 'finish-commit';
              final s = (await recovered.session('crash'))!;
              equal(
                s.status,
                committed ? SessionStatus.finalized : SessionStatus.active,
              );
              equal(
                (await ProgramService(recovered).run('strength-run')).cursor,
                committed ? 1 : 0,
              );
              equal(
                (await recovered.programReceipts()).length,
                committed ? 1 : 0,
              );
              equal(await recovered.finalizationCount(), committed ? 1 : 0);
              if (committed) {
                await StoredTrainingService(
                  recovered,
                ).edit(s.id, s.contentVersion, (s) => s.finish(_finish(2)));
                equal((await recovered.programReceipts()).length, 1);
              }
              await recovered.archive();
            } finally {
              await recovered.close();
            }
          } finally {
            child.kill(ProcessSignal.sigkill);
            await child.exitCode;
          }
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'v2 schema and logical exports migrate ad hoc receipts without inheriting them into new runs',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-program-v2-');
      try {
        final path = '${dir.path}/v2.sqlite';
        final rev = revision();
        final session = finished(start(id: 'legacy', from: rev));
        final decision = ProgressionDecision(
          session: session,
          slotId: 'bench-heavy',
          rule: _rule(),
        ).accept(_accept(1));
        final db = sqlite3.open(path);
        try {
          for (final ddl in schemaV2.values) db.execute(ddl);
          db.execute('PRAGMA application_id = 1112821065');
          db.execute('DROP TABLE IF EXISTS repeat_checkpoints');
          db.execute('DROP TABLE IF EXISTS window_checkpoints');
          db.execute('PRAGMA user_version = 2');
          db.execute('INSERT INTO revisions VALUES (?,?,?)', [
            rev.definition.id,
            1,
            jsonEncode(rev.toJson()),
          ]);
          db.execute('INSERT INTO sessions VALUES (?,?)', [
            session.id,
            jsonEncode(session.toJson()),
          ]);
          db.execute('INSERT INTO finalizations VALUES (?)', [session.id]);
          db.execute('INSERT INTO progression_decisions VALUES (?,?,?)', [
            session.id,
            'bench-heavy',
            canonicalJson(decision.toJson()),
          ]);
        } finally {
          db.close();
        }
        equal(
          (await NativeBackup.create(
            path,
            '${dir.path}/v2-native',
          ))['databaseSchemaVersion'],
          2,
        );
        final data = TrainingArchive(
          revisions: [rev],
          sessions: [session],
          finalizations: [session.id],
          progressions: [decision],
        ).toJson();
        for (final key in [
          'programRevisions',
          'programRuns',
          'sessionPrograms',
          'programReceipts',
          'bodyMass',
          'timers',
          'executions',
          'families',
        ])
          data.remove(key);
        final envelope = <String, Object?>{
          'format': 'bodytmi-logical-export/2',
          'applicationVersion': '0.1.0',
          'data': data,
        };
        envelope['sha256'] = sha256
            .convert(utf8.encode(canonicalJson(envelope)))
            .toString();
        await File('${dir.path}/v2.json').writeAsString(jsonEncode(envelope));
        final old = await LogicalArchiveFiles.prepare('${dir.path}/v2.json');
        try {
          equal(old.archive.progressions.single.runId, null);
          equal(old.archive.programRuns.length, 0);
        } finally {
          await old.close();
        }
        final store = await TrainingStore.open(path);
        try {
          equal((await store.progressionDecisions()).single.sequence, 1);
          await ProgramService(store).publish(_program('fresh'), 0);
          await ProgramService(store).create('new', 'fresh', 1, instant(2));
          final fresh = await _start(store, 'new', 'fresh', 3);
          equal(fresh.sets.first.suggested['reps']!.value.toString(), '8');
          final adhoc = await StoredTrainingService(
            store,
          ).start('adhoc', definition().id, 1, instant(3));
          equal(adhoc.sets.first.suggested['reps']!.value.toString(), '9');
          await store.archive();
        } finally {
          await store.close();
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
