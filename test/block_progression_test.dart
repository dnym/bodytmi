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

Map<String, Object?> _ruleJson({int failure = 6, int advance = 8}) => {
  'performance': {
    'score': 'confirmedRounds',
    'failureLimit': failure,
    'advancementLimit': advance,
  },
  'increments': {
    'mass': {'value': '4', 'unit': 'kg'},
  },
  'maximums': {
    'mass': {'value': '24', 'unit': 'kg'},
  },
  'deloadAfter': 2,
  'deloadDecrements': {
    'mass': {'value': '4', 'unit': 'kg'},
  },
};

BlockProgressionRule _rule({int failure = 6, int advance = 8}) =>
    BlockProgressionRule.fromJson(
      _ruleJson(failure: failure, advance: advance),
    );

/// The public AMRAP example with a 16 kg push implement to progress.
WorkoutDefinition _definition() {
  final json = copyJson(
    jsonObject(example('amrap-block-workout')['definition'], 'def'),
  );
  final round = jsonObject(
    jsonObject((json['amraps']! as List).single, 'a')['roundDefinition'],
    'round',
  );
  jsonObject(
    jsonObject((round['slots']! as List).first, 'slot')['targets'],
    't',
  )['mass'] = {
    'value': '16',
    'unit': 'kg',
  };
  return WorkoutDefinition.fromJson(json);
}

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
  final dir = await Directory.systemTemp.createTemp('bodytmi-block-');
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

/// Starts a session and its block, reviewing [rounds] full rounds (two
/// efforts each) explicitly before the deadline. Optional [pushMass]
/// records a different controlled actual on the first push.
Future<RepeatCheckpoint> _block(
  TrainingStore store,
  String sessionId,
  int day,
  int rounds, {
  bool finishBlock = true,
  bool finishSession = true,
  bool stopEarly = false,
  String? pushMass,
}) async {
  final service = StoredTrainingService(store);
  var session = await service.start(
    sessionId,
    'upper-amrap',
    1,
    DateTime.utc(2026, 11, day, 17),
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
  final repeats = RepeatCheckpointService(store);
  var block = await repeats.startBlock(
    '$sessionId-block',
    sessionId,
    'finisher',
  );
  Future<void> act(
    String action, {
    Map<String, Object?>? review,
    int? elapsed,
    bool confirm = false,
  }) async {
    block = await repeats.action(
      block.id,
      expectedVersion: block.version,
      expectedExecutionVersion: block.execution['version']! as int,
      action: action,
      review: review,
      elapsedMilliseconds: elapsed,
      confirm: confirm,
    );
  }

  for (var i = 0; i < rounds * 2; i++) {
    await act(
      'review-elapsed',
      elapsed: 20000,
      review: i == 0 && pushMass != null
          ? {
              'outcome': 'completed',
              'actuals': {
                'reps': {'value': '5', 'unit': 'rep'},
                'mass': {'value': pushMass, 'unit': 'kg'},
              },
            }
          : {'outcome': 'completed', 'acceptSuggested': true},
    );
  }
  if (!finishBlock) return block;
  if (stopEarly) {
    await act('stop', confirm: true);
  } else {
    await act('elapse', elapsed: 600000);
    await act('review', review: {'outcome': 'skipped'}, confirm: true);
    await act('finish', confirm: true);
  }
  if (finishSession)
    await service.edit(
      session.id,
      session.contentVersion,
      (s) => s.finish(DateTime.utc(2026, 11, day, 18)),
    );
  return block;
}

String _mass(Metrics targets) => targets['mass']!.enteredValue;

void blockProgressionTests() {
  test('block rules validate and classify one exposure exactly', () {
    rejects(() => BlockProgressionRule.fromJson({..._ruleJson(), 'x': 1}));
    rejects(
      () => BlockProgressionRule.fromJson({
        ..._ruleJson(),
        'performance': {
          'score': 'reps',
          'failureLimit': 1,
          'advancementLimit': 2,
        },
      }),
    );
    rejects(() => _rule(failure: 9, advance: 8));
    rejects(
      () => BlockProgressionRule.fromJson({
        ..._ruleJson(),
        'increments': {
          'mass': {'value': '0', 'unit': 'kg'},
        },
      }),
    );
    rejects(
      () => BlockProgressionRule.fromJson(
        {..._ruleJson()}..remove('deloadAfter'),
      ),
    );
    rejects(
      () => BlockProgressionRule.fromJson({
        ..._ruleJson(),
        'maximums': {
          'reps': {'value': '9', 'unit': 'rep'},
        },
      }),
    );
    final loop = _definition().amrap('finisher')!;
    _rule().validateFor(loop, 'push');
    rejects(() => _rule().validateFor(loop, 'missing'), 'not_found');
    rejects(
      () => BlockProgressionRule.fromJson({
        ..._ruleJson(),
        'increments': {
          'mass': {'value': '1', 'unit': 'rep'},
        },
      }).validateFor(loop, 'push'),
    );
    jsonEqual(
      BlockProgressionRule.fromJson(_rule().toJson()).toJson(),
      _rule().toJson(),
    );
  });

  test(
    'block scores drive durable round slot targets for the next block',
    () => _withStore((store, dir) async {
      await StoredTrainingService(store).publish(_definition(), 0);
      final blocks = BlockProgressionService(store);

      // Proposals need a finished session.
      final open = await _block(store, 'open', 1, 3, finishSession: false);
      check(open.blockTargets.isEmpty);
      await _failure(() => blocks.propose('open', 'finisher', 'push', _rule()));

      await _block(store, 's1', 2, 9);
      var d = await blocks.propose('s1', 'finisher', 'push', _rule());
      equal(d.outcome, 'advance');
      equal(d.status, 'pending');
      // Retrying the identical proposal is a no-op.
      equal(
        (await blocks.propose('s1', 'finisher', 'push', _rule())).version,
        d.version,
      );
      equal(
        (await _failure(
          () => blocks.resolve(
            's1',
            'finisher',
            'push',
            expectedVersion: 9,
            at: DateTime.utc(2026, 11, 2, 19),
            accept: true,
          ),
        )).code,
        'conflict',
      );
      d = await blocks.resolve(
        's1',
        'finisher',
        'push',
        expectedVersion: d.version,
        at: DateTime.utc(2026, 11, 2, 19),
        accept: true,
      );
      equal(_mass(d.resolvedTargets), '20');
      // A lost-response retry returns the same receipt; a proposal after
      // resolution never replays it.
      equal(
        (await blocks.resolve(
          's1',
          'finisher',
          'push',
          expectedVersion: 1,
          at: DateTime.utc(2026, 11, 2, 19),
          accept: true,
        )).version,
        2,
      );
      equal(
        canonicalJson(
          (await blocks.propose('s1', 'finisher', 'push', _rule())).toJson(),
        ),
        canonicalJson(d.toJson()),
      );

      // The next block starts from the accepted targets with provenance.
      final b2 = await _block(store, 's2', 3, 4);
      equal(b2.blockTargets['push']!.decisionId, 's1/finisher/push');
      equal(
        WindowRepeatSpec.fromJson(
          jsonObject(b2.execution['cursor'], 'cursor')['loop'],
        ).roundDefinition.slot('push').targets['mass']!.enteredValue,
        '20',
      );
      // Pull keeps its authored targets; only the controlled slot moved.
      check(!b2.blockTargets.containsKey('pull'));
      var f = await blocks.propose('s2', 'finisher', 'push', _rule());
      equal(f.outcome, 'failed');
      equal(f.anchorId, 's1/finisher/push');
      f = await blocks.resolve(
        's2',
        'finisher',
        'push',
        expectedVersion: f.version,
        at: DateTime.utc(2026, 11, 3, 19),
        accept: false,
      );
      equal(f.resolvedFailures, 1);
      equal(_mass(f.resolvedTargets), '20');

      // A second failure reaches deloadAfter.
      await _block(store, 's3', 4, 5);
      var deload = await blocks.propose('s3', 'finisher', 'push', _rule());
      equal(deload.outcome, 'deload');
      deload = await blocks.resolve(
        's3',
        'finisher',
        'push',
        expectedVersion: deload.version,
        at: DateTime.utc(2026, 11, 4, 19),
        accept: true,
      );
      equal(_mass(deload.resolvedTargets), '16');
      equal(deload.resolvedFailures, 0);

      // An early-stopped block is neutral: the counter is unchanged.
      await _block(store, 's4', 5, 2, stopEarly: true);
      final neutral = await blocks.propose('s4', 'finisher', 'push', _rule());
      equal(neutral.outcome, 'unknown');
      await _failure(
        () => blocks.resolve(
          's4',
          'finisher',
          'push',
          expectedVersion: neutral.version,
          at: DateTime.utc(2026, 11, 5, 19),
          accept: true,
        ),
      );
      final declined = await blocks.resolve(
        's4',
        'finisher',
        'push',
        expectedVersion: neutral.version,
        at: DateTime.utc(2026, 11, 5, 19),
        accept: false,
      );
      equal(declined.resolvedFailures, 0);

      // A different controlled actual requires review.
      await _block(store, 's5', 6, 9, pushMass: '18');
      equal(
        (await blocks.propose('s5', 'finisher', 'push', _rule())).outcome,
        'review',
      );

      final track = await blocks.track(
        templateId: 'upper-amrap',
        amrapId: 'finisher',
        roundSlotId: 'push',
        asOf: DateTime.utc(2026, 11, 30),
      );
      equal(track['decisionId'], 's4/finisher/push');
      equal(track['source'], 'decision');
      equal(
        (await blocks.track(
          templateId: 'upper-amrap',
          amrapId: 'finisher',
          roundSlotId: 'push',
          runId: 'some-run',
          asOf: DateTime.utc(2026, 11, 30),
        ))['source'],
        'authored',
      );
    }),
  );

  test(
    'stale sources and competing exposures cannot resolve',
    () => _withStore((store, dir) async {
      await StoredTrainingService(store).publish(_definition(), 0);
      final blocks = BlockProgressionService(store);
      // Two sessions start from the same authored baseline.
      await _block(store, 'a', 1, 9);
      await _block(store, 'b', 2, 9);
      final a = await blocks.propose('a', 'finisher', 'push', _rule());
      final b = await blocks.propose('b', 'finisher', 'push', _rule());
      await blocks.resolve(
        'a',
        'finisher',
        'push',
        expectedVersion: a.version,
        at: DateTime.utc(2026, 11, 2, 19),
        accept: true,
      );
      // b's targets no longer follow: it would replay the same increment.
      equal(
        (await _failure(
          () => blocks.resolve(
            'b',
            'finisher',
            'push',
            expectedVersion: b.version,
            at: DateTime.utc(2026, 11, 2, 20),
            accept: true,
          ),
        )).code,
        'conflict',
      );

      // Correcting a finished block makes its pending proposal stale.
      await _block(store, 'c', 3, 9);
      final c = await blocks.propose('c', 'finisher', 'push', _rule());
      var block = await RepeatCheckpointService(store).show('c-block');
      block = await RepeatCheckpointService(store).action(
        'c-block',
        expectedVersion: block.version,
        expectedExecutionVersion: block.execution['version']! as int,
        action: 'correct',
        correction: {
          'occurrenceId': 'finisher[0]/round/push-set',
          'actuals': {
            'reps': {'value': '4', 'unit': 'rep'},
            'mass': {'value': '20', 'unit': 'kg'},
          },
        },
      );
      check(await blocks.stale(c));
      equal(
        (await _failure(
          () => blocks.resolve(
            'c',
            'finisher',
            'push',
            expectedVersion: c.version,
            at: DateTime.utc(2026, 11, 3, 19),
            accept: true,
          ),
        )).code,
        'conflict',
      );
      final again = await blocks.propose('c', 'finisher', 'push', _rule());
      equal(again.version, c.version + 1);
      check(!await blocks.stale(again));
    }),
  );

  test(
    'block progression is portable only under v66 formats',
    () => _withStore((store, dir) async {
      await StoredTrainingService(store).publish(_definition(), 0);
      final blocks = BlockProgressionService(store);
      await _block(store, 's1', 1, 9);
      final d = await blocks.propose('s1', 'finisher', 'push', _rule());
      await blocks.resolve(
        's1',
        'finisher',
        'push',
        expectedVersion: d.version,
        at: DateTime.utc(2026, 11, 1, 19),
        accept: true,
      );
      await _block(store, 's2', 2, 3, finishSession: false, finishBlock: false);
      final original = canonicalJson((await store.archive()).toJson());
      equal((await store.backup('$dir/native'))['databaseSchemaVersion'], 67);
      final exported = await LogicalArchiveFiles.export(
        await store.archive(),
        '$dir/logical.json',
      );
      equal(exported['format'], 'bodytmi-logical-export/67');
      final logical = await LogicalArchiveFiles.prepare('$dir/logical.json');
      try {
        equal(logical.archive.blockProgressions.length, 1);
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
      } finally {
        await active.close();
      }

      final envelope = jsonObject(
        jsonDecode(await File('$dir/logical.json').readAsString()),
        'logical',
      );
      final old = copyJson(envelope)..['format'] = 'bodytmi-logical-export/65';
      await File('$dir/old.json').writeAsString(jsonEncode(await _resign(old)));
      await _failure(() => LogicalArchiveFiles.prepare('$dir/old.json'));
      // Forged consumed targets do not match the accepted decision.
      final forged = copyJson(envelope);
      for (final c
          in jsonObject(forged['data'], 'data')['repeatCheckpoints']! as List) {
        final targets = jsonObject(c, 'c')['blockTargets'];
        if (targets == null) continue;
        jsonObject(
          jsonObject(jsonObject(targets, 't')['push'], 'p')['targets'],
          'targets',
        )['mass'] = {
          'value': '28',
          'unit': 'kg',
        };
      }
      await File(
        '$dir/forged.json',
      ).writeAsString(jsonEncode(await _resign(forged)));
      await _failure(() => LogicalArchiveFiles.prepare('$dir/forged.json'));

      final copy = '$dir/relabel.sqlite';
      File('$dir/native/database.sqlite').copySync(copy);
      final db = sqlite3.open(copy);
      db.execute('DROP TABLE block_progressions');
      db.userVersion = 65;
      db.close();
      final nativeError = await _failure(
        () => NativeBackup.validateDatabase(copy),
      );
      check(
        nativeError.message.contains('Block progression targets require'),
        nativeError.message,
      );
    }),
  );

  test(
    'block progression CLI commands propose, accept and report tracks',
    () => _withStore((store, dir) async {
      await StoredTrainingService(store).publish(_definition(), 0);
      await _block(store, 's1', 1, 9);
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
      final identity = {
        'sessionId': 's1',
        'amrapId': 'finisher',
        'roundSlotId': 'push',
      };
      final proposed = await cmd('progression block-propose', {
        ...identity,
        'rule': _ruleJson(),
      });
      equal(proposed.code, 0);
      check(proposed.output.contains('"outcome":"advance"'));
      check(proposed.output.contains('"stale":false'));
      equal(
        (await cmd('progression block-propose', {
          ...identity,
          'rule': {'bad': true},
        })).code,
        2,
      );
      equal(
        (await cmd('progression block-show', {
          ...identity,
          'roundSlotId': 'pull',
        })).code,
        3,
      );
      final accepted = await cmd('progression block-accept', {
        ...identity,
        'expectedVersion': 1,
        'acceptedAt': '2026-11-01T19:00:00Z',
      });
      equal(accepted.code, 0);
      check(accepted.output.contains('"applied":true'));
      equal(
        (await cmd('progression block-decline', {
          ...identity,
          'expectedVersion': 1,
          'declinedAt': '2026-11-01T19:00:00Z',
        })).code,
        5,
      );
      final track = await cmd('progression block-track', {
        'templateId': 'upper-amrap',
        'amrapId': 'finisher',
        'roundSlotId': 'push',
        'asOf': '2026-11-02T00:00:00Z',
      });
      equal(track.code, 0);
      check(track.output.contains('"value":"20"'));
      final series = await cmd('store series', {
        'metric': 'mass',
        'includeBlocks': true,
      });
      equal(series.code, 0);
      final blocks = jsonObject(
        jsonObject(jsonDecode(series.output), 'r')['data'],
        'data',
      )['blocks'];
      equal(jsonObject(blocks, 'blocks')['pointCount'], 9);
    }),
  );
}
