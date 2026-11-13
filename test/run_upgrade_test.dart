import 'dart:convert';
import 'dart:io';

import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

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
    'upgrade guards reject completed prefixes, current sessions and stale versions',
    () => withStore((store, _) async {
      final programs = ProgramService(store);
      await programs.publish(
        ProgramDefinition.fromJson(
          _program([_day('a', 'upper-a', 1), _day('b', 'upper-a', 1)]),
        ),
        0,
      );
      await programs.create('run-1', 'upgrade-program', 1, _at(1));
      final run = await advance(store, 'run-1', 'session-a', 1);

      // Changing the completed day's prescription is rejected.
      await programs.publish(
        ProgramDefinition.fromJson(
          _program([_day('x', 'upper-a', 1), _day('b', 'upper-a', 1)]),
        ),
        1,
      );
      var error = await failure(
        () => programs.upgrade(
          'run-1',
          run.contentVersion,
          2,
          'upgrade-1',
          _at(2),
        ),
      );
      check(
        error.message.contains('retain their pinned prescription'),
        'completed days are protected',
      );

      // Changing cycle length after advancement is rejected.
      await programs.publish(
        ProgramDefinition.fromJson(_program([_day('a', 'upper-a', 1)])),
        2,
      );
      error = await failure(
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
      await programs.create('paused-run', 'upgrade-program', 4, _at(1));
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
      await programs.create('looping', 'upgrade-program', 3, _at(4));
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
      await programs.create('run-1', 'upgrade-program', 1, _at(1));
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
    'native and logical v56 archives carry upgrade receipts and older labels reject them',
    () => withStore((store, dir) async {
      final programs = ProgramService(store);
      await programs.publish(
        ProgramDefinition.fromJson(
          _program([_day('a', 'upper-a', 1), _day('b', 'upper-a', 1)]),
        ),
        0,
      );
      await programs.create('run-1', 'upgrade-program', 1, _at(1));
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
      equal((await store.backup('$dir/native'))['databaseSchemaVersion'], 57);
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

      // The same SQLite tables under a v55 label are rejected: the new
      // table itself does not belong to the v55 schema.
      File(
        '$dir/labeled.sqlite',
      ).writeAsBytesSync(File('$dir/native/database.sqlite').readAsBytesSync());
      final labeled = sqlite3.open('$dir/labeled.sqlite');
      labeled.userVersion = 55;
      labeled.close();
      final nativeError = await failure(
        () => NativeBackup.validateDatabase('$dir/labeled.sqlite'),
      );
      check(
        nativeError.message.contains('does not match supported schema'),
        'old labels fail schema validation because the receipt table is new',
      );

      // A v55-labeled logical file with an upgrades section is rejected.
      final json = jsonObject(
        jsonDecode(await File('$dir/logical.json').readAsString()),
        'file',
      );
      json['format'] = 'bodytmi-logical-export/55';
      json.remove('sha256');
      json['sha256'] = sha256
          .convert(utf8.encode(canonicalJson(json)))
          .toString();
      await File('$dir/relabeled.json').writeAsString(jsonEncode(json));
      final logicalError = await failure(
        () => LogicalArchiveFiles.prepare('$dir/relabeled.json'),
      );
      check(
        logicalError.message.contains('Unknown fields'),
        'old logical labels cannot carry upgrades',
      );
      // An empty section under the old label remains equivalent to absence.
      final empty = jsonObject(
        jsonDecode(await File('$dir/logical.json').readAsString()),
        'file',
      );
      jsonObject(empty['data'], 'data')['programUpgrades'] = [];
      empty['format'] = 'bodytmi-logical-export/55';
      empty.remove('sha256');
      empty['sha256'] = sha256
          .convert(utf8.encode(canonicalJson(empty)))
          .toString();
      await File('$dir/empty-old.json').writeAsString(jsonEncode(empty));
      final honest = await LogicalArchiveFiles.prepare('$dir/empty-old.json');
      try {
        equal(honest.archive.programUpgrades.isEmpty, true);
      } finally {
        await honest.close();
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
