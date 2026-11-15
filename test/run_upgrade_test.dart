import 'dart:convert';
import 'dart:io';

import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';

import 'cli_test.dart' show invoke;
import 'fixtures.dart';
import 'support.dart';

Map<String, Object?> _day(
  String id,
  String templateId,
  int revision, {
  Map<String, Object?>? derivedPlan,
}) => {
  'id': id,
  'type': 'day',
  'label': 'Day $id',
  'templateId': templateId,
  'revision': revision,
  if (derivedPlan != null) 'derivedPlan': derivedPlan,
};

Map<String, Object?> _cycle(List<Map<String, Object?>> days) => {
  'id': 'cycle',
  'type': 'group',
  'label': 'Cycle',
  'children': days,
};

Map<String, Object?> _program(
  List<Map<String, Object?>> days, {
  String id = 'upgrade-program',
}) => {'id': id, 'name': 'Upgrade program', 'plan': _cycle(days)};

DateTime _at(int day) => instant(day);

Future<BodyTmiException> failure(Object? Function() action) async {
  try {
    await action();
  } on BodyTmiException catch (error) {
    return error;
  }
  throw StateError('Expected a BodyTmiException.');
}

void runUpgradeTests() {
  Future<void> withStore(
    Future<void> Function(TrainingStore, String) action,
  ) async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-run-upgrade-');
    final path = '${dir.path}/profile.sqlite';
    final store = await TrainingStore.open(path);
    try {
      await StoredTrainingService(store).publish(definition(), 0);
      await action(store, dir.path);
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  }

  Future<ProgramRun> advance(
    TrainingStore store,
    String runId,
    String sessionId,
    int day,
  ) async {
    final programs = ProgramService(store);
    final run = await programs.run(runId);
    final session = await programs.start(
      runId,
      run.contentVersion,
      sessionId,
      _at(day),
    );
    await StoredTrainingService(store).edit(sessionId, session.contentVersion, (
      s,
    ) {
      for (final set in s.sets) {
        s = const TrainingService().complete(
          s,
          set.id,
          const {},
          acceptSuggested: true,
        );
      }
      return s.finish(_at(day).add(const Duration(hours: 1)));
    });
    return programs.run(runId);
  }

  test(
    'an explicit run upgrade re-pins the run without moving its cursor',
    () => withStore((store, _) async {
      final programs = ProgramService(store);
      await programs.publish(
        ProgramDefinition.fromJson(
          _program([_day('a', 'upper-a', 1), _day('b', 'upper-a', 1)]),
        ),
        0,
      );
      await programs.create('run-1', 'upgrade-program', 1, _at(1), loop: false);
      final run = await advance(store, 'run-1', 'session-a', 1);
      equal(run.cursor, 1);
      equal(run.program.number, 1);

      // Same completed prefix, different second day.
      await programs.publish(
        ProgramDefinition.fromJson(
          _program([_day('a', 'upper-a', 1), _day('b2', 'upper-a', 1)]),
        ),
        1,
      );
      final receipt = await programs.upgrade(
        'run-1',
        run.contentVersion,
        2,
        'upgrade-1',
        _at(2),
      );
      equal(receipt.fromRevision, 1);
      equal(receipt.toRevision, 2);
      equal(receipt.programId, 'upgrade-program');
      final updated = await programs.run('run-1');
      equal(updated.program.number, 2);
      equal(updated.cursor, 1);
      equal(updated.contentVersion, run.contentVersion + 1);

      // Byte-identical replay returns the same receipt without a second bump.
      final replay = await programs.upgrade(
        'run-1',
        run.contentVersion,
        2,
        'upgrade-1',
        _at(2),
      );
      equal(canonicalJson(replay.toJson()), canonicalJson(receipt.toJson()));
      final again = await programs.run('run-1');
      equal(again.contentVersion, updated.contentVersion);
      equal(again.program.number, 2);

      // The upgraded day is the one consumed by the next start.
      final started = await programs.start(
        'run-1',
        again.contentVersion,
        'session-b',
        _at(3),
      );
      equal(started.sets.isNotEmpty, true);
      equal((await programs.upgrades('run-1')).length, 1);

      // A reused request identity with different inputs conflicts.
      final conflict = await failure(
        () => programs.upgrade(
          'run-1',
          again.contentVersion,
          1,
          'upgrade-1',
          _at(4),
        ),
      );
      check(
        conflict.message.contains('reused with different inputs'),
        'upgrade identity reuse is explicit',
      );
    }),
  );

  test(
    'upgrade guards reject cycle changes, current sessions and stale versions',
    () => withStore((store, _) async {
      final programs = ProgramService(store);
      await programs.publish(
        ProgramDefinition.fromJson(
          _program([_day('a', 'upper-a', 1), _day('b', 'upper-a', 1)]),
        ),
        0,
      );
      await programs.create('run-1', 'upgrade-program', 1, _at(1), loop: true);
      final run = await advance(store, 'run-1', 'session-a', 1);

      // Changing a completed day is allowed (covered by the looping-cycle
      // test); revision 2 only keeps the revision numbering below.
      await programs.publish(
        ProgramDefinition.fromJson(
          _program([_day('x', 'upper-a', 1), _day('b', 'upper-a', 1)]),
        ),
        1,
      );

      // Changing cycle length after advancement is rejected.
      await programs.publish(
        ProgramDefinition.fromJson(_program([_day('a', 'upper-a', 1)])),
        2,
      );
      var error = await failure(
        () => programs.upgrade(
          'run-1',
          run.contentVersion,
          3,
          'upgrade-2',
          _at(2),
        ),
      );
      check(
        error.message.contains('cycle length'),
        'cycle length is protected',
      );

      // Pinning the same revision is a conflict, not a silent no-op.
      await programs.publish(
        ProgramDefinition.fromJson(
          _program([_day('a', 'upper-a', 1), _day('b2', 'upper-a', 1)]),
        ),
        3,
      );
      error = await failure(
        () => programs.upgrade(
          'run-1',
          run.contentVersion,
          1,
          'upgrade-3',
          _at(2),
        ),
      );
      check(
        error.message.contains('already pins'),
        'same-revision pin conflicts',
      );

      // A stale expectedVersion conflicts before anything is written.
      error = await failure(
        () => programs.upgrade(
          'run-1',
          run.contentVersion + 5,
          4,
          'upgrade-4',
          _at(2),
        ),
      );
      check(
        error.message.contains('version changed'),
        'version check is a guard',
      );

      // The current day must be resolved before an upgrade.
      final started = await programs.start(
        'run-1',
        run.contentVersion,
        'session-b',
        _at(2),
      );
      final bound = await programs.run('run-1');
      error = await failure(
        () => programs.upgrade(
          'run-1',
          bound.contentVersion,
          4,
          'upgrade-5',
          _at(2),
        ),
      );
      check(
        error.message.contains('already has a session'),
        'a bound current day blocks upgrade',
      );
      equal(started.status, SessionStatus.active);

      // Paused runs may upgrade explicitly once the day is resolved.
      await programs.publish(
        ProgramDefinition.fromJson(
          _program([_day('a', 'upper-a', 1), _day('b3', 'upper-a', 1)]),
        ),
        4,
      );
      await programs.create(
        'paused-run',
        'upgrade-program',
        4,
        _at(1),
        loop: true,
      );
      final fresh = await programs.run('paused-run');
      await programs.skip('paused-run', fresh.contentVersion, 'skip-a', _at(2));
      await programs.status(
        'paused-run',
        (await programs.run('paused-run')).contentVersion,
        'paused',
      );
      final skipped = await programs.run('paused-run');
      equal(skipped.cursor, 1);
      final receipt = await programs.upgrade(
        'paused-run',
        skipped.contentVersion,
        5,
        'upgrade-6',
        _at(3),
      );
      equal(receipt.fromRevision, 4);
      equal(receipt.toRevision, 5);
      equal((await programs.run('paused-run')).status, 'paused');
    }),
  );

  test(
    'a looping run re-pins a completed day after a full cycle',
    () => withStore((store, dir) async {
      final programs = ProgramService(store);
      final training = StoredTrainingService(store);
      final lighter = definition().toJson();
      lighter['name'] = 'Upper A, lighter';
      await training.publish(WorkoutDefinition.fromJson(lighter), 1);
      await programs.publish(
        ProgramDefinition.fromJson(
          _program([_day('a', 'upper-a', 1), _day('b', 'upper-a', 1)]),
        ),
        0,
      );
      await programs.create('run-1', 'upgrade-program', 1, _at(1), loop: true);
      // One full cycle and the next day A: every day has run at least once.
      await advance(store, 'run-1', 'a-1', 1);
      await advance(store, 'run-1', 'b-1', 2);
      var run = await advance(store, 'run-1', 'a-2', 3);
      equal(run.cursor, 3);

      // Day B (already completed in cycle one) moves to workout revision 2.
      await programs.publish(
        ProgramDefinition.fromJson(
          _program([_day('a', 'upper-a', 1), _day('b', 'upper-a', 2)]),
        ),
        1,
      );
      final receipt = await programs.upgrade(
        'run-1',
        run.contentVersion,
        2,
        'lighter-b',
        _at(4),
      );
      equal(receipt.cursor, 3);
      run = await advance(store, 'run-1', 'b-2', 5);
      equal((await training.session('b-2')).revision.number, 2);
      equal((await training.session('b-1')).revision.number, 1);
      equal(run.cursor, 4);

      // Both archives still validate the cycle-one day B under revision 1.
      final archive = await store.archive();
      TrainingArchive.fromJson(archive.toJson());
      await store.backup('$dir/native');
      await (await NativeBackup.prepare('$dir/native')).close();

      // A receipt claiming the pin changed before day B of cycle one would
      // put that session under revision 2: rejected.
      final forged = archive.toJson();
      final rows = forged['programUpgrades'] as List;
      (rows.single as Map<String, Object?>)['cursor'] = 1;
      rejects(() => TrainingArchive.fromJson(forged));
      // A cursor ahead of the run is rejected too.
      (rows.single as Map<String, Object?>)['cursor'] = 9;
      rejects(() => TrainingArchive.fromJson(forged));
    }),
  );

  test(
    'a finite run repeats days by jumping back, and reopens when finished',
    () => withStore((store, dir) async {
      final programs = ProgramService(store);
      await programs.publish(
        ProgramDefinition.fromJson(
          _program([
            for (final d in ['d1', 'd2', 'd3', 'd4']) _day(d, 'upper-a', 1),
          ]),
        ),
        0,
      );
      await programs.create('run-1', 'upgrade-program', 1, _at(1), loop: false);
      await advance(store, 'run-1', 's1', 1);
      await advance(store, 'run-1', 's2', 2);
      var run = await advance(store, 'run-1', 's3', 3);
      equal(run.current!.path, 'cycle/d4');
      // Back from travel: repeat from day 2.
      run = await programs.jump(
        'run-1',
        run.contentVersion,
        'cycle/d2',
        'repeat-d2',
        _at(4),
      );
      equal(run.cursor, 3);
      equal(run.current!.path, 'cycle/d2');
      final schedule = await programs.schedule('run-1');
      equal(schedule['remaining'], 3);
      jsonEqual(
        [
          for (final d in jsonList(schedule, 'days'))
            jsonObject(d, 'd')['path'],
        ],
        ['cycle/d2', 'cycle/d3', 'cycle/d4'],
      );
      // Retry replays; reuse with other inputs, stale versions, the same
      // day, unknown paths and a bound current day are refused.
      final replay = await programs.jump(
        'run-1',
        run.contentVersion - 1,
        'cycle/d2',
        'repeat-d2',
        _at(4),
      );
      equal(canonicalJson(replay.toJson()), canonicalJson(run.toJson()));
      for (final attempt in [
        () => programs.jump(
          'run-1',
          run.contentVersion,
          'cycle/d3',
          'repeat-d2',
          _at(4),
        ),
        () => programs.jump(
          'run-1',
          run.contentVersion + 1,
          'cycle/d3',
          'other',
          _at(4),
        ),
        () => programs.jump(
          'run-1',
          run.contentVersion,
          'cycle/d2',
          'same',
          _at(4),
        ),
        () => programs.jump(
          'run-1',
          run.contentVersion,
          'cycle/nope',
          'unknown',
          _at(4),
        ),
      ]) {
        await failure(attempt);
      }
      run = await advance(store, 'run-1', 's4', 5);
      equal(run.current!.path, 'cycle/d3');
      run = await advance(store, 'run-1', 's5', 6);
      run = await advance(store, 'run-1', 's6', 7);
      equal(run.status, 'completed');
      equal(run.cursor, 6);
      // Repeat the last day after finishing: the run reopens.
      run = await programs.jump(
        'run-1',
        run.contentVersion,
        'cycle/d4',
        'one-more',
        _at(8),
      );
      equal(run.status, 'active');
      final started = await programs.start(
        'run-1',
        run.contentVersion,
        's7',
        _at(9),
      );
      run = await programs.run('run-1');
      final bound = await failure(
        () => programs.jump(
          'run-1',
          run.contentVersion,
          'cycle/d1',
          'while-bound',
          _at(9),
        ),
      );
      check(bound.message.contains('already has a session'), bound.message);
      await StoredTrainingService(store).edit('s7', started.contentVersion, (
        s,
      ) {
        for (final set in s.sets) {
          s = const TrainingService().complete(
            s,
            set.id,
            const {},
            acceptSuggested: true,
          );
        }
        return s.finish(_at(9).add(const Duration(hours: 1)));
      });
      run = await programs.run('run-1');
      equal(run.status, 'completed');
      equal(run.cursor, 7);
      // Sessions keep the day they ran as; archives validate through jumps.
      final bindings = {
        for (final b in await store.sessionPrograms()) b.sessionId: b.path,
      };
      equal(bindings['s4'], 'cycle/d2');
      equal(bindings['s7'], 'cycle/d4');
      final archive = await store.archive();
      TrainingArchive.fromJson(archive.toJson());
      await store.backup('$dir/native');
      await (await NativeBackup.prepare('$dir/native')).close();
      final forged = archive.toJson();
      final runJson = jsonObject(
        (forged['programRuns']! as List).single,
        'run',
      );
      final jumps = runJson['jumps']! as List;
      jsonObject(jumps.first, 'jump')['position'] = 2;
      rejects(() => TrainingArchive.fromJson(forged));
    }),
  );

  test(
    'a looping run jumps within its current cycle and upgrades keep jumps',
    () => withStore((store, _) async {
      final programs = ProgramService(store);
      await programs.publish(
        ProgramDefinition.fromJson(
          _program([_day('a', 'upper-a', 1), _day('b', 'upper-a', 1)]),
        ),
        0,
      );
      await programs.create('loop', 'upgrade-program', 1, _at(1), loop: true);
      var run = await programs.run('loop');
      for (var i = 0; i < 5; i++) {
        run = await advance(store, 'loop', 'l$i', i + 1);
      }
      equal(run.current!.path, 'cycle/b');
      run = await programs.jump(
        'loop',
        run.contentVersion,
        'cycle/a',
        'redo-a',
        _at(6),
      );
      equal(run.positionAt(run.cursor), 4);
      equal(run.current!.path, 'cycle/a');
      await programs.publish(
        ProgramDefinition.fromJson(
          _program([_day('a', 'upper-a', 1), _day('b2', 'upper-a', 1)]),
        ),
        1,
      );
      await programs.upgrade('loop', run.contentVersion, 2, 'up', _at(7));
      run = await programs.run('loop');
      equal(run.jumps.length, 1);
      run = await advance(store, 'loop', 'l5', 8);
      equal(run.current!.path, 'cycle/b2');
      TrainingArchive.fromJson((await store.archive()).toJson());
    }),
  );

  test(
    'finite and looping runs apply their day-count rules differently',
    () => withStore((store, _) async {
      final programs = ProgramService(store);
      await programs.publish(
        ProgramDefinition.fromJson(
          _program([_day('a', 'upper-a', 1), _day('b', 'upper-a', 1)]),
        ),
        0,
      );
      await programs.create(
        'finite',
        'upgrade-program',
        1,
        _at(1),
        loop: false,
      );
      final run = await advance(store, 'finite', 'session-a', 1);

      // Fewer published days than the cursor already consumed is rejected.
      await programs.publish(
        ProgramDefinition.fromJson(_program([_day('a', 'upper-a', 1)])),
        1,
      );
      final error = await failure(
        () => programs.upgrade(
          'finite',
          run.contentVersion,
          2,
          'upgrade-1',
          _at(2),
        ),
      );
      check(
        error.message.contains('enough days'),
        'finite day count is enforced',
      );

      // Completed finite runs cannot be re-pinned at all.
      await advance(store, 'finite', 'session-b', 2);
      final done = await programs.run('finite');
      equal(done.status, 'completed');
      await programs.publish(
        ProgramDefinition.fromJson(
          _program([_day('a', 'upper-a', 1), _day('b2', 'upper-a', 1)]),
        ),
        2,
      );
      final after = await failure(
        () => programs.upgrade(
          'finite',
          done.contentVersion,
          3,
          'upgrade-2',
          _at(3),
        ),
      );
      check(
        after.message.contains('Completed finite runs'),
        'completed runs are final',
      );

      // Looping runs keep the cycle but may change the cycle entirely.
      await programs.create(
        'looping',
        'upgrade-program',
        3,
        _at(4),
        loop: true,
      );
      final loop = await advance(store, 'looping', 'session-c', 5);
      equal(loop.cursor, 1);
      await programs.publish(
        ProgramDefinition.fromJson(
          _program([_day('a', 'upper-a', 1), _day('b', 'upper-a', 1)]),
        ),
        3,
      );
      final receipt = await programs.upgrade(
        'looping',
        loop.contentVersion,
        4,
        'upgrade-3',
        _at(6),
      );
      equal(receipt.fromRevision, 3);
      equal(receipt.toRevision, 4);
      equal((await programs.run('looping')).program.number, 4);
    }),
  );

  test(
    'upgrade chains roll back and forward with durable ordering',
    () => withStore((store, _) async {
      final programs = ProgramService(store);
      await programs.publish(
        ProgramDefinition.fromJson(
          _program([_day('a', 'upper-a', 1), _day('b', 'upper-a', 1)]),
        ),
        0,
      );
      await programs.create('run-1', 'upgrade-program', 1, _at(1), loop: true);
      var run = await programs.run('run-1');
      await programs.publish(
        ProgramDefinition.fromJson(
          _program([_day('a', 'upper-a', 1), _day('b2', 'upper-a', 1)]),
        ),
        1,
      );
      await programs.publish(
        ProgramDefinition.fromJson(
          _program([_day('a', 'upper-a', 1), _day('b3', 'upper-a', 1)]),
        ),
        2,
      );
      run = await programs
          .upgrade('run-1', run.contentVersion, 2, 'up-1', _at(2))
          .then((_) => programs.run('run-1'));
      equal(run.program.number, 2);
      // Explicit rollback re-pin is allowed and receipted.
      run = await programs
          .upgrade('run-1', run.contentVersion, 3, 'up-2', _at(3))
          .then((_) => programs.run('run-1'));
      equal(run.program.number, 3);
      run = await programs
          .upgrade('run-1', run.contentVersion, 2, 'up-3', _at(4))
          .then((_) => programs.run('run-1'));
      equal(run.program.number, 2);
      final upgrades = await programs.upgrades('run-1');
      equal(upgrades.length, 3);
      equal(
        canonicalJson([for (final u in upgrades) u.toRevision]),
        canonicalJson([2, 3, 2]),
      );
      // A missing target revision is a clean not-found.
      final missing = await failure(
        () => programs.upgrade('run-1', run.contentVersion, 9, 'up-4', _at(5)),
      );
      check(
        missing.message.contains('Program revision not found'),
        'missing revisions fail cleanly',
      );
    }),
  );

  test(
    'native and logical archives carry upgrade receipts',
    () => withStore((store, dir) async {
      final programs = ProgramService(store);
      await programs.publish(
        ProgramDefinition.fromJson(
          _program([_day('a', 'upper-a', 1), _day('b', 'upper-a', 1)]),
        ),
        0,
      );
      await programs.create('run-1', 'upgrade-program', 1, _at(1), loop: true);
      final run = await advance(store, 'run-1', 'session-a', 1);
      await programs.publish(
        ProgramDefinition.fromJson(
          _program([_day('a', 'upper-a', 1), _day('b2', 'upper-a', 1)]),
        ),
        1,
      );
      final receipt = await programs.upgrade(
        'run-1',
        run.contentVersion,
        2,
        'upgrade-1',
        _at(2),
      );
      equal((await store.backup('$dir/native'))['databaseSchemaVersion'], 1);
      final archive = await store.archive();
      final before = canonicalJson(archive.toJson());
      await LogicalArchiveFiles.export(archive, '$dir/logical.json');
      final prepared = await LogicalArchiveFiles.prepare('$dir/logical.json');
      try {
        equal(canonicalJson(prepared.archive.toJson()), before);
        equal(prepared.archive.programUpgrades.length, 1);
        equal(
          canonicalJson(prepared.archive.programUpgrades.single.toJson()),
          canonicalJson(receipt.toJson()),
        );
      } finally {
        await prepared.close();
      }
      // Forged chains fail archive validation.
      final forged = await store.archive();
      final tampered = forged.toJson();
      tampered['programUpgrades'] = [
        {
          'schemaVersion': 1,
          'runId': 'run-1',
          'programId': 'upgrade-program',
          'fromRevision': 1,
          'toRevision': 1,
          'cursor': 1,
          'occurredAt': _at(2).toUtc().toIso8601String(),
          'requestId': 'upgrade-forged',
        },
      ];
      final forgedError = await failure(
        () => TrainingArchive.fromJson(tampered),
      );
      check(
        forgedError.message.contains('revisions must be distinct'),
        'forged chains fail archive validation',
      );

      // Restore keeps the chain durable.
      final backup = await NativeBackup.prepare('$dir/native');
      final restorer = await TrainingStore.open('$dir/restored.sqlite');
      try {
        await restorer.restore(
          backup,
          recoveryDestination: '$dir/recovery',
          confirm: true,
        );
      } finally {
        await restorer.close();
      }
      final restored = await TrainingStore.open('$dir/restored.sqlite');
      try {
        final runs = await ProgramService(restored).run('run-1');
        equal(runs.program.number, 2);
        equal((await ProgramService(restored).upgrades('run-1')).length, 1);
        equal(canonicalJson((await restored.archive()).toJson()), before);
      } finally {
        await restored.close();
      }
    }),
  );

  test('CLI run upgrade records durable receipts', () async {
    final dir = await Directory.systemTemp.createTemp(
      'bodytmi-cli-run-upgrade-',
    );
    final db = '${dir.path}/profile.sqlite';
    Future<({int code, Map<String, Object?> body})> call(
      String command,
      Map<String, Object?> fields,
    ) async {
      final result = await invoke([
        command.split(' ').first,
        command.split(' ').skip(1).join(' '),
      ], jsonEncode({'schemaVersion': 1, 'database': db, ...fields}));
      final body = result.output.isEmpty
          ? <String, Object?>{}
          : jsonObject(jsonDecode(result.output), 'response');
      return (code: result.code, body: body);
    }

    final published = await call('store publish', {
      'definition': definition().toJson(),
      'expectedRevision': 0,
    });
    equal(published.code, 0);
    final program = _program([
      _day('a', 'upper-a', 1),
      _day('b', 'upper-a', 1),
    ]);
    final first = await call('program publish', {
      'definition': program,
      'expectedRevision': 0,
    });
    equal(first.code, 0);
    final created = await call('run create', {
      'id': 'cli-run',
      'programId': 'upgrade-program',
      'revision': 1,
      'startedAt': _at(1).toUtc().toIso8601String(),
      'loop': false,
    });
    equal(created.code, 0);
    program['plan'] = _cycle([
      _day('a', 'upper-a', 1),
      _day('b2', 'upper-a', 1),
    ]);
    final second = await call('program publish', {
      'definition': program,
      'expectedRevision': 1,
    });
    equal(second.code, 0);
    final upgraded = await call('run upgrade', {
      'runId': 'cli-run',
      'expectedVersion': 1,
      'revision': 2,
      'requestId': 'cli-upgrade',
      'at': _at(2).toUtc().toIso8601String(),
      'confirm': true,
    });
    equal(upgraded.code, 0);
    final data = jsonObject(upgraded.body['data'], 'data');
    equal(jsonObject(data['receipt'], 'receipt')['toRevision'], 2);
    equal(jsonObject(data['run'], 'run')['program'] == null, false);
    final replay = await call('run upgrade', {
      'runId': 'cli-run',
      'expectedVersion': 1,
      'revision': 2,
      'requestId': 'cli-upgrade',
      'at': _at(2).toUtc().toIso8601String(),
      'confirm': true,
    });
    equal(replay.code, 0);
    equal(
      canonicalJson(replay.body['data']),
      canonicalJson(upgraded.body['data']),
    );
    final listed = await call('run upgrades', {'runId': 'cli-run'});
    equal(listed.code, 0);
    equal((listed.body['data']! as List).length, 1);

    // Missing confirm, unknown run and stale version fail cleanly.
    final unconfirmed = await call('run upgrade', {
      'runId': 'cli-run',
      'expectedVersion': 1,
      'revision': 1,
      'requestId': 'cli-upgrade-2',
      'at': _at(3).toUtc().toIso8601String(),
      'confirm': false,
    });
    equal(unconfirmed.code, 2);
    final missingRun = await call('run upgrades', {'runId': 'nobody'});
    equal(missingRun.code, 3);
    final stale = await call('run upgrade', {
      'runId': 'cli-run',
      'expectedVersion': 9,
      'revision': 1,
      'requestId': 'cli-upgrade-3',
      'at': _at(3).toUtc().toIso8601String(),
      'confirm': true,
    });
    equal(stale.code, 5);
    await dir.delete(recursive: true);
  });
}
