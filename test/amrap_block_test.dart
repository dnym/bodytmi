import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'cli_test.dart';
import 'fixtures.dart';
import 'support.dart';

Map<String, Object?> _definitionJson() =>
    copyJson(jsonObject(example('amrap-block-workout')['definition'], 'def'));

WorkoutDefinition _definition() =>
    WorkoutDefinition.fromJson(_definitionJson());

Future<BodyTmiException> _failure(Object? Function() action) async {
  try {
    await action();
  } on BodyTmiException catch (error) {
    return error;
  }
  throw StateError('Expected a BodyTmiException.');
}

Future<void> _withStore(
  Future<void> Function(TrainingStore, String) action,
) async {
  final dir = await Directory.systemTemp.createTemp('bodytmi-amrap-');
  final store = await TrainingStore.open('${dir.path}/db.sqlite');
  try {
    await action(store, dir.path);
  } finally {
    await store.close();
    await dir.delete(recursive: true);
  }
}

Future<Map<String, Object?>> _resign(Map<String, Object?> envelope) async {
  envelope.remove('sha256');
  envelope['sha256'] = sha256
      .convert(utf8.encode(canonicalJson(envelope)))
      .toString();
  return envelope;
}

/// Publishes the example workout and starts a session with all finite sets
/// completed, so only the authored block stands between it and finishing.
Future<TrainingSession> _ready(TrainingStore store) async {
  final service = StoredTrainingService(store);
  await service.publish(_definition(), 0);
  var session = await service.start(
    'amrap-session',
    'upper-amrap',
    1,
    DateTime.utc(2026, 11, 14, 17),
  );
  for (final set in session.sets) {
    session = await service.edit(
      session.id,
      session.contentVersion,
      (s) => const TrainingService().complete(
        s,
        set.id,
        const {},
        acceptSuggested: true,
      ),
    );
  }
  return session;
}

Future<TrainingSession> _finish(TrainingStore store, TrainingSession s) =>
    StoredTrainingService(store).edit(
      s.id,
      s.contentVersion,
      (current) => current.finish(DateTime.utc(2026, 11, 14, 18)),
    );

void amrapBlockTests() {
  test('workout definitions author validated AMRAP blocks', () {
    final definition = _definition();
    check(definition.hasAmraps);
    equal(definition.amrap('finisher')!.durationMilliseconds, 600000);
    equal(definition.amrap('missing'), null);
    // Normalized authoring round-trips exactly.
    jsonEqual(
      WorkoutDefinition.fromJson(definition.toJson()).toJson(),
      definition.toJson(),
    );
    final plain = _definitionJson()..remove('amraps');
    check(!WorkoutDefinition.fromJson(plain).hasAmraps);
    check(!WorkoutDefinition.fromJson(plain).toJson().containsKey('amraps'));

    final amrap = jsonObject((_definitionJson()['amraps'] as List).single, 'a');
    void bad(Object? amraps) => rejects(
      () =>
          WorkoutDefinition.fromJson({..._definitionJson(), 'amraps': amraps}),
    );
    bad(<Object?>[]);
    bad([amrap, amrap]);
    bad([
      {...amrap, 'durationMilliseconds': 0},
    ]);
    bad([
      {
        ...amrap,
        'roundDefinition': {
          ...jsonObject(amrap['roundDefinition'], 'round'),
          'amraps': [amrap],
        },
      },
    ]);
    bad([
      for (var i = 0; i < 17; i++) {...amrap, 'id': 'a$i'},
    ]);
  });

  test(
    'authored blocks start from the pinned revision and gate finishing',
    () => _withStore((store, dir) async {
      final session = await _ready(store);
      final repeats = RepeatCheckpointService(store);
      equal(
        (await _failure(
          () => repeats.startBlock('x', 'amrap-session', 'nope'),
        )).code,
        'not_found',
      );
      equal(
        (await _failure(
          () => repeats.startBlock('x', 'ghost', 'finisher'),
        )).code,
        'not_found',
      );
      // Finishing without starting the block names it.
      final missing = await _failure(() => _finish(store, session));
      check(missing.message.contains('finisher'), missing.message);

      final started = await repeats.startBlock(
        'finisher-1',
        'amrap-session',
        'finisher',
      );
      equal(started.amrapId, 'finisher');
      equal(
        canonicalJson(
          jsonObject(started.execution['cursor'], 'cursor')['loop'],
        ),
        canonicalJson(_definition().amrap('finisher')!.toJson()),
      );
      // An identical retry returns the untouched checkpoint.
      equal(
        canonicalJson(
          (await repeats.startBlock(
            'finisher-1',
            'amrap-session',
            'finisher',
          )).toJson(),
        ),
        canonicalJson(started.toJson()),
      );
      equal(
        (await _failure(
          () => repeats.startBlock('again', 'amrap-session', 'finisher'),
        )).code,
        'conflict',
      );
      // A later revision does not change the pinned block.
      final changed = _definitionJson();
      jsonObject(
        (changed['amraps'] as List).single,
        'a',
      )['durationMilliseconds'] = 300000;
      await StoredTrainingService(
        store,
      ).publish(WorkoutDefinition.fromJson(changed), 1);
      equal(
        jsonObject(
          jsonObject(
            (await repeats.show('finisher-1')).execution['cursor'],
            'cursor',
          )['loop'],
          'loop',
        )['durationMilliseconds'],
        600000,
      );
      // An unfinished block still blocks finishing.
      await _failure(() => _finish(store, session));

      // Generic saves keep the immutable block identity.
      final saved = await repeats.save(
        'finisher-1',
        started.version,
        started.execution,
      );
      equal(saved.amrapId, 'finisher');

      // Explicitly skipping the block is a confirmed stop with no work.
      final stopped = await repeats.action(
        'finisher-1',
        expectedVersion: saved.version,
        expectedExecutionVersion: saved.execution['version']! as int,
        action: 'stop',
        confirm: true,
      );
      equal(
        jsonObject(stopped.execution['cursor'], 'cursor')['status'],
        'finished',
      );
      final finished = await _finish(store, session);
      equal(finished.status, SessionStatus.finalized);
      final rounds = await repeatRoundsFromStore(store, 'amrap-session');
      equal(rounds['amrapId'], 'finisher');
      equal(rounds['confirmedRounds'], 0);

      // A finished session keeps its block; a new session has its own.
      final kept = await repeats.show('finisher-1');
      await _failure(
        () => repeats.delete('finisher-1', kept.version, confirm: true),
      );
      final other = await StoredTrainingService(
        store,
      ).start('other', 'upper-amrap', 2, DateTime.utc(2026, 11, 15, 17));
      check(other.revision.definition.amrap('finisher') != null);
      await repeats.startBlock('other-block', 'other', 'finisher');
      equal(
        (await _failure(
          () => repeats.startBlock('late', 'amrap-session', 'finisher'),
        )).code,
        'conflict',
      );
    }),
  );

  test('archive validation pins block identity and requires completion', () {
    final revision = WorkoutRevision.publish(_definition());
    var session = const TrainingService().start(
      sessionId: 's',
      revision: revision,
      startedAt: DateTime.utc(2026, 11, 14, 17),
    );
    final loop = _definition().amrap('finisher')!;
    Map<String, Object?> checkpoint({Object? withLoop}) {
      final execution = const WindowRepeatExecution().start(
        withLoop == null ? loop : WindowRepeatSpec.fromJson(withLoop),
      );
      return {
        'id': 'c',
        'version': 1,
        'execution': execution,
        'sessionId': 's',
        'amrapId': 'finisher',
      };
    }

    validateRepeatSessionBindings(
      [RepeatCheckpoint.fromJson(checkpoint())],
      [session],
    );
    final forged = {...loop.toJson(), 'maxRounds': 5};
    rejects(
      () => validateRepeatSessionBindings(
        [RepeatCheckpoint.fromJson(checkpoint(withLoop: forged))],
        [session],
      ),
    );
    rejects(
      () => validateRepeatSessionBindings(
        [
          RepeatCheckpoint.fromJson({...checkpoint(), 'amrapId': 'other'}),
        ],
        [session],
      ),
    );
    rejects(
      () => validateRepeatSessionBindings(
        [
          RepeatCheckpoint.fromJson(checkpoint()),
          RepeatCheckpoint.fromJson({...checkpoint(), 'id': 'd'}),
        ],
        [session],
      ),
    );
    rejects(
      () => RepeatCheckpoint.fromJson({...checkpoint()}..remove('sessionId')),
    );
    for (final set in session.sets) {
      session = const TrainingService().complete(
        session,
        set.id,
        const {},
        acceptSuggested: true,
      );
    }
    final finalized = session.finish(DateTime.utc(2026, 11, 14, 18));
    // A finalized session cannot lack its authored block.
    rejects(() => validateRepeatSessionBindings(const [], [finalized]));
  });

  test(
    'authored blocks are portable only under v65 formats',
    () => _withStore((store, dir) async {
      final session = await _ready(store);
      final repeats = RepeatCheckpointService(store);
      var block = await repeats.startBlock('b', session.id, 'finisher');
      block = await repeats.action(
        'b',
        expectedVersion: block.version,
        expectedExecutionVersion: block.execution['version']! as int,
        action: 'review-elapsed',
        elapsedMilliseconds: 30000,
        review: {'outcome': 'completed', 'acceptSuggested': true},
      );
      final original = canonicalJson((await store.archive()).toJson());
      equal((await store.backup('$dir/native'))['databaseSchemaVersion'], 67);
      final exported = await LogicalArchiveFiles.export(
        await store.archive(),
        '$dir/logical.json',
      );
      equal(exported['format'], 'bodytmi-logical-export/67');
      final logical = await LogicalArchiveFiles.prepare('$dir/logical.json');
      try {
        await store.restore(
          logical.backup,
          recoveryDestination: '$dir/recovery',
          confirm: true,
        );
      } finally {
        await logical.close();
      }
      await store.close();
      var active = await TrainingStore.open('$dir/db.sqlite');
      try {
        equal(canonicalJson((await active.archive()).toJson()), original);
        final native = await NativeBackup.prepare('$dir/native');
        try {
          await active.restore(
            native,
            recoveryDestination: '$dir/recovery2',
            confirm: true,
          );
        } finally {
          await native.close();
        }
      } finally {
        await active.close();
      }
      active = await TrainingStore.open('$dir/db.sqlite');
      try {
        equal(canonicalJson((await active.archive()).toJson()), original);
        equal(
          (await RepeatCheckpointService(active).show('b')).amrapId,
          'finisher',
        );
      } finally {
        await active.close();
      }

      final envelope = jsonObject(
        jsonDecode(await File('$dir/logical.json').readAsString()),
        'logical',
      )..['format'] = 'bodytmi-logical-export/64';
      await File(
        '$dir/old.json',
      ).writeAsString(jsonEncode(await _resign(envelope)));
      final logicalError = await _failure(
        () => LogicalArchiveFiles.prepare('$dir/old.json'),
      );
      check(
        logicalError.message.contains('AMRAP blocks require logical v65'),
        logicalError.message,
      );
      final copy = '$dir/relabel.sqlite';
      File('$dir/native/database.sqlite').copySync(copy);
      final db = sqlite3.open(copy);
      db.execute('DROP TABLE IF EXISTS block_progressions');
      db.userVersion = 64;
      db.close();
      final nativeError = await _failure(
        () => NativeBackup.validateDatabase(copy),
      );
      check(
        nativeError.message.contains('AMRAP blocks require schema v65'),
        nativeError.message,
      );
    }),
  );

  test(
    'AMRAP block CLI commands start, review and finish a timed block',
    () => _withStore((store, dir) async {
      await store.close();
      Future<({int code, String output, String error})> cmd(
        String action,
        Map<String, Object?> input,
      ) => invoke(
        action.split(' '),
        jsonEncode({
          ...input,
          'schemaVersion': 1,
          'database': '$dir/db.sqlite',
        }),
      );
      Map<String, Object?> data(({int code, String output, String error}) r) {
        equal(r.code, 0);
        return jsonObject(
          jsonObject(jsonDecode(r.output), 'r')['data'],
          'data',
        );
      }

      data(await cmd('store publish', example('amrap-block-workout')));
      var session = data(
        await cmd('store start', {
          'id': 'amrap-session',
          'templateId': 'upper-amrap',
          'revision': 1,
          'startedAt': '2026-11-14T18:00:00+01:00',
        }),
      );
      var version = session['contentVersion']! as int;
      for (final set in session['sets']! as List) {
        session = data(
          await cmd('store complete', {
            'id': 'amrap-session',
            'expectedVersion': version,
            'setId': jsonObject(set, 'set')['id'],
            'actuals': <String, Object?>{},
            'acceptSuggested': true,
          }),
        );
        version = session['contentVersion']! as int;
      }
      final early = await cmd('store finish', {
        'id': 'amrap-session',
        'expectedVersion': version,
        'finishedAt': '2026-11-14T19:00:00+01:00',
      });
      equal(early.code, 2);
      check(early.output.isEmpty);
      var block = data(
        await cmd(
          'repeat-checkpoint start-block',
          example('amrap-block-start'),
        ),
      );
      final missing = await cmd('repeat-checkpoint start-block', {
        'id': 'y',
        'sessionId': 'amrap-session',
        'amrapId': 'nope',
      });
      equal(missing.code, 3);
      Future<void> act(Map<String, Object?> input) async {
        block = data(
          await cmd('repeat-checkpoint action', {
            'id': 'finisher-1',
            'expectedVersion': block['version'],
            'expectedExecutionVersion': jsonObject(
              block['execution'],
              'execution',
            )['version'],
            ...input,
          }),
        );
      }

      for (var i = 0; i < 3; i++) {
        await act({
          'action': 'review-elapsed',
          'elapsedMilliseconds': 40000,
          'review': {'outcome': 'completed', 'acceptSuggested': true},
        });
      }
      await act({'action': 'elapse', 'elapsedMilliseconds': 600000});
      final cursor = jsonObject(
        jsonObject(block['execution'], 'execution')['cursor'],
        'cursor',
      );
      // Reaching the deadline records nothing: the effort awaits review.
      equal(cursor['status'], 'boundary');
      await act({
        'action': 'review',
        'review': {
          'outcome': 'completed',
          'actuals': {
            'reps': {'value': '3', 'unit': 'rep'},
          },
        },
      });
      await act({'action': 'finish', 'confirm': true});
      equal(
        data(
          await cmd('store finish', {
            'id': 'amrap-session',
            'expectedVersion': version,
            'finishedAt': '2026-11-14T19:00:00+01:00',
          }),
        )['status'],
        'finalized',
      );
      final rounds = data(
        await cmd('repeat-checkpoint rounds', {'sessionId': 'amrap-session'}),
      );
      final attempt = jsonObject((rounds['attempts']! as List).single, 'a');
      equal(attempt['amrapId'], 'finisher');
      equal(attempt['confirmedRounds'], 2);
      equal(attempt['terminalReason'], 'windowExpired');
    }),
  );
}

/// The single associated attempt of one session, read transactionally.
Future<Map<String, Object?>> repeatRoundsFromStore(
  TrainingStore store,
  String sessionId,
) async {
  final report = const RepeatHistory().rounds(
    await store.repeatCheckpoints(),
    await store.sessions(),
    sessionId: sessionId,
    includeActive: true,
  );
  return jsonObject((report['attempts']! as List).single, 'attempt');
}
