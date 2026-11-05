import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart' show expectLater, throwsA, isA;
import 'cli_test.dart';
import 'fixtures.dart';
import 'support.dart';

WorkoutDefinition _definition() => WorkoutDefinition.fromJson({
  'id': 'traversal',
  'name': 'Finite practice',
  'slots': [
    {
      'id': 'hold',
      'exercise': 'hold',
      'implementation': 'bar',
      'targets': {
        'duration': {'value': '1', 'unit': 's'},
        'mass': {'value': '1', 'unit': 'kg'},
      },
    },
    {
      'id': 'lift',
      'exercise': 'lift',
      'implementation': 'barbell',
      'targets': {
        'mass': {'value': '10', 'unit': 'kg'},
        'reps': {'value': '8', 'unit': 'rep'},
      },
    },
  ],
  'plan': {
    'id': 'workout',
    'type': 'sequence',
    'children': [
      {'id': 'hold-set', 'type': 'effort', 'slot': 'hold'},
      {'id': 'recovery', 'type': 'rest', 'durationSeconds': 1},
      {'id': 'lift-set', 'type': 'effort', 'slot': 'lift'},
    ],
  },
});
WorkoutDefinition _manualDefinition() => WorkoutDefinition.fromJson({
  ..._definition().toJson(),
  'id': 'manual-rest',
  'plan': {
    'id': 'workout',
    'type': 'sequence',
    'children': [
      {'id': 'hold-set', 'type': 'effort', 'slot': 'hold'},
      {'id': 'recovery', 'type': 'rest', 'manual': true},
      {'id': 'lift-set', 'type': 'effort', 'slot': 'lift'},
    ],
  },
});
Future<void> _fails(Future<Object?> action) =>
    expectLater(action, throwsA(isA<BodyTmiException>()));
Future<void> _withStore(
  Future<void> Function(TrainingStore, String) action,
) async {
  final dir = await Directory.systemTemp.createTemp('bodytmi-execution-');
  final store = await TrainingStore.open('${dir.path}/db.sqlite');
  try {
    final service = StoredTrainingService(store);
    await service.publish(_definition(), 0);
    await service.start('session', 'traversal', 1, instant(1));
    await action(store, dir.path);
  } finally {
    await store.close();
    await dir.delete(recursive: true);
  }
}

Future<WorkoutExecution> _start(
  TrainingStore store, {
  String id = 'execution',
  String session = 'session',
}) => ExecutionService(store).start(id, session, instant(1));
Future<TimingActivity> _finishRest(
  TrainingStore store,
  WorkoutExecution e,
) async {
  final service = TimingService(store);
  var t = await service.show(e.clockId('rest'));
  t = await service.resume(t.id, t.version, 'epoch-${e.cursor}', instant(1));
  return (await service.advance(
    t.id,
    t.version,
    t.ownerId!,
    t.plan.restMilliseconds,
    instant(1),
  )).activity;
}

Future<WorkoutExecution> _step(
  TrainingStore store,
  WorkoutExecution e,
  String request, {
  String action = 'advance',
  bool confirm = false,
}) async {
  final s = (await store.session(e.sessionId))!;
  return ExecutionService(store).step(
    e.id,
    e.version,
    s.contentVersion,
    request,
    instant(1),
    action: action,
    acceptSuggested: action == 'complete',
    confirm: confirm,
  );
}

WorkoutDefinition _groupDefinition() => WorkoutDefinition.fromJson({
  ..._definition().toJson(),
  'id': 'groups',
  'plan': {
    'id': 'workout',
    'type': 'sequence',
    'children': [
      {
        'id': 'rounds',
        'type': 'repeat',
        'count': 2,
        'restBetweenSeconds': 1,
        'child': {
          'id': 'pair',
          'type': 'sequence',
          'children': [
            {'id': 'hold', 'type': 'effort', 'slot': 'hold'},
            {'id': 'inner-rest', 'type': 'rest', 'durationSeconds': 1},
            {'id': 'lift', 'type': 'effort', 'slot': 'lift'},
          ],
        },
      },
      {'id': 'tail', 'type': 'effort', 'slot': 'lift'},
    ],
  },
});
Future<WorkoutExecution> _startGroups(TrainingStore store) async {
  final training = StoredTrainingService(store);
  await training.publish(_groupDefinition(), 0);
  await training.start('group-session', 'groups', 1, instant(1));
  return ExecutionService(
    store,
  ).start('execution', 'group-session', instant(1));
}

void executionTests() {
  test(
    'manual rest advances only explicitly and survives both portability formats',
    () => _withStore((store, dir) async {
      await store.snapshot('$dir/v39.sqlite');
      final old = sqlite3.open('$dir/v39.sqlite');
      old.userVersion = 39;
      old.close();
      equal(NativeBackup.validateDatabase('$dir/v39.sqlite'), 39);
      final migrated = await TrainingStore.open('$dir/v39.sqlite');
      equal(
        (await StoredTrainingService(migrated).revision('traversal')).number,
        1,
      );
      await migrated.close();
      final training = StoredTrainingService(store);
      await training.publish(_manualDefinition(), 0);
      final session = await training.start(
        'manual-session',
        'manual-rest',
        1,
        instant(1),
      );
      final service = ExecutionService(store);
      var e = await service.start('manual-execution', session.id, instant(1));
      e = await _step(store, e, 'hold', action: 'complete');
      equal(e.cursor, 1);
      final view = await service.view(e.id);
      equal(view['timer'], null);
      equal(
        jsonObject(
          jsonObject(view['current'], 'current')['activity'],
          'activity',
        )['manual'],
        true,
      );
      check((await store.timingActivities()).isEmpty);
      await _fails(service.time(e.id, e.version, instant(1)));
      await _fails(
        TimingService(
          store,
        ).startRest('manual-clock', session.id, 'workout/recovery', instant(1)),
      );
      final current = (await store.session(session.id))!;
      await _fails(
        service.step(
          e.id,
          e.version + 1,
          current.contentVersion,
          'rest',
          instant(1),
        ),
      );
      final before = canonicalJson((await store.archive()).toJson());
      await store.backup('$dir/native-manual');
      final file = '$dir/manual.json';
      await LogicalArchiveFiles.export(await store.archive(), file);
      final prepared = await LogicalArchiveFiles.prepare(file);
      final destination = await TrainingStore.open('$dir/restore.sqlite');
      try {
        await destination.restore(
          prepared.backup,
          recoveryDestination: '$dir/recovery',
          confirm: true,
        );
      } finally {
        await destination.close();
        await prepared.close();
      }
      final restored = await TrainingStore.open('$dir/restore.sqlite');
      try {
        equal(canonicalJson((await restored.archive()).toJson()), before);
        final native = await NativeBackup.prepare('$dir/native-manual');
        try {
          await restored.restore(
            native,
            recoveryDestination: '$dir/recovery-native',
            confirm: true,
          );
        } finally {
          await native.close();
        }
      } finally {
        await restored.close();
      }
      final nativeRestored = await TrainingStore.open('$dir/restore.sqlite');
      try {
        equal(canonicalJson((await nativeRestored.archive()).toJson()), before);
      } finally {
        await nativeRestored.close();
      }
      final envelope =
          jsonDecode(await File(file).readAsString()) as Map<String, Object?>;
      envelope['format'] = 'bodytmi-logical-export/39';
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
      await File('$dir/old-manual.json').writeAsString(jsonEncode(envelope));
      await _fails(LogicalArchiveFiles.prepare('$dir/old-manual.json'));
      await store.snapshot('$dir/manual.sqlite');
      equal(NativeBackup.validateDatabase('$dir/manual.sqlite'), 42);
      final relabeled = sqlite3.open('$dir/manual.sqlite');
      relabeled.userVersion = 39;
      relabeled.close();
      rejects(() => NativeBackup.validateDatabase('$dir/manual.sqlite'));
      final previous = e;
      e = await service.step(
        e.id,
        e.version,
        current.contentVersion,
        'rest',
        instant(1),
      );
      equal(e.cursor, 2);
      equal(e.receipts[1]['timerId'], null);
      final retry = await service.step(
        previous.id,
        previous.version,
        current.contentVersion,
        'rest',
        instant(1),
      );
      equal(retry.cursor, 2);
      e = await _step(store, e, 'lift', action: 'complete');
      check(e.complete);
      final done = await training.session(session.id);
      equal(done.sets.last.status, SetStatus.completed);
      check((await store.timingActivities()).isEmpty);
      final archive = await store.archive();
      final forged = copyJson(archive.toJson());
      final recorded = jsonObject(
        jsonList(forged, 'executions').single,
        'execution',
      );
      jsonObject(jsonList(recorded, 'receipts')[1], 'receipt')['timerId'] =
          'invented-clock';
      rejects(() => TrainingArchive.fromJson(forged));
    }),
  );
  test(
    'manual rest before a timed rest rolls back if the next clock conflicts',
    () => _withStore((store, _) async {
      final def = _manualDefinition().toJson();
      def['id'] = 'consecutive-rest';
      def['plan'] = {
        'id': 'workout',
        'type': 'sequence',
        'children': [
          {'id': 'manual', 'type': 'rest', 'manual': true},
          {'id': 'timed', 'type': 'rest', 'durationSeconds': 2},
          {'id': 'lift', 'type': 'effort', 'slot': 'lift'},
        ],
      };
      final training = StoredTrainingService(store);
      await training.publish(WorkoutDefinition.fromJson(def), 0);
      final session = await training.start(
        'rest-session',
        'consecutive-rest',
        1,
        instant(1),
      );
      final clock = await TimingService(store).start(
        'other-clock',
        'session',
        'workout/hold-set',
        'duration',
        TimingPlan.fromJson({'effortMilliseconds': 1000}),
        instant(1),
      );
      final service = ExecutionService(store);
      var e = await service.start('rest-execution', session.id, instant(1));
      await _fails(
        service.step(
          e.id,
          e.version,
          session.contentVersion,
          'manual',
          instant(1),
        ),
      );
      equal((await service.show(e.id)).cursor, 0);
      await TimingService(
        store,
      ).stop(clock.id, clock.version, instant(1), confirm: true, discard: true);
      e = await service.step(
        e.id,
        e.version,
        session.contentVersion,
        'manual',
        instant(1),
      );
      equal(e.cursor, 1);
      equal(
        (await TimingService(store).show(e.clockId('rest'))).status,
        'paused',
      );
      await store.archive();
    }),
  );
  test(
    'group and individual skips acknowledge manual rest without a clock',
    () => _withStore((store, _) async {
      final training = StoredTrainingService(store);
      await training.publish(_manualDefinition(), 0);
      await training.start('group-manual', 'manual-rest', 1, instant(1));
      var e = await ExecutionService(
        store,
      ).start('group-manual-exec', 'group-manual', instant(1));
      e = await ExecutionService(store).skipGroup(
        e.id,
        e.version,
        1,
        'skip-all',
        'workout',
        instant(1),
        confirm: true,
      );
      check(e.complete);
      check(!e.receipts[1].containsKey('timerId'));
      await training.start('single-manual', 'manual-rest', 1, instant(1));
      var second = await ExecutionService(
        store,
      ).start('single-manual-exec', 'single-manual', instant(1));
      second = await _step(store, second, 'hold', action: 'complete');
      final s = await training.session('single-manual');
      await _fails(
        ExecutionService(store).step(
          second.id,
          second.version,
          s.contentVersion,
          'skip-rest',
          instant(1),
          action: 'skip',
        ),
      );
      second = await ExecutionService(store).step(
        second.id,
        second.version,
        s.contentVersion,
        'skip-rest',
        instant(1),
        action: 'skip',
        confirm: true,
      );
      equal(second.cursor, 2);
      check(!second.receipts[1].containsKey('timerId'));
      check((await store.timingActivities()).isEmpty);
      await store.archive();
    }),
  );
  test(
    'manual rest advances only its selected program after session finish',
    () => _withStore((store, _) async {
      final training = StoredTrainingService(store);
      await training.publish(_manualDefinition(), 0);
      final programs = ProgramService(store);
      for (final name in ['strength', 'cardio']) {
        await programs.publish(
          ProgramDefinition.fromJson({
            'id': name,
            'name': name,
            'plan': {
              'id': 'day',
              'type': 'day',
              'templateId': 'manual-rest',
              'revision': 1,
            },
          }),
          0,
        );
        await programs.create('$name-run', name, 1, instant(1));
      }
      final strength = await programs.start(
        'strength-run',
        1,
        'strength-session',
        instant(1),
      );
      final cardio = await programs.start(
        'cardio-run',
        1,
        'cardio-session',
        instant(1),
      );
      final cardioRun = canonicalJson(
        (await programs.run('cardio-run')).toJson(),
      );
      final cardioSession = canonicalJson(cardio.toJson());
      var e = await ExecutionService(
        store,
      ).start('program-execution', strength.id, instant(1));
      e = await _step(store, e, 'hold', action: 'complete');
      e = await _step(store, e, 'manual-rest');
      e = await _step(store, e, 'lift', action: 'complete');
      check(e.complete);
      equal((await programs.run('strength-run')).cursor, 0);
      var s = await training.session(strength.id);
      s = await training.edit(
        s.id,
        s.contentVersion,
        (s) => s.finish(instant(1).add(const Duration(hours: 1))),
      );
      await training.edit(
        s.id,
        s.contentVersion,
        (s) => s.finish(instant(1).add(const Duration(hours: 1))),
      );
      equal((await programs.run('strength-run')).cursor, 1);
      equal(
        canonicalJson((await programs.run('cardio-run')).toJson()),
        cardioRun,
      );
      equal(
        canonicalJson((await training.session(cardio.id)).toJson()),
        cardioSession,
      );
      equal((await store.programReceipts()).length, 1);
      await store.archive();
    }),
  );
  test('native CLI exposes manual rest and explicit advancement', () async {
    final dir = await Directory.systemTemp.createTemp(
      'bodytmi-manual-rest-cli-',
    );
    final path = '${dir.path}/db.sqlite';
    try {
      Future<Map<String, Object?>> call(
        String name,
        Map<String, Object?> fields,
      ) async {
        final response = await invoke(
          name.split(' '),
          jsonEncode({'schemaVersion': 1, 'database': path, ...fields}),
        );
        equal(response.code, 0);
        return jsonObject(
          jsonObject(jsonDecode(response.output), 'response')['data'],
          'data',
        );
      }

      await call('store publish', {
        'definition': _manualDefinition().toJson(),
        'expectedRevision': 0,
      });
      await call('store start', {
        'id': 'cli',
        'templateId': 'manual-rest',
        'revision': 1,
        'startedAt': instant(1).toIso8601String(),
      });
      await call('execution start', {
        'id': 'ex',
        'sessionId': 'cli',
        'at': instant(1).toIso8601String(),
      });
      var view = await call('execution complete', {
        'id': 'ex',
        'expectedVersion': 1,
        'expectedSessionVersion': 1,
        'requestId': 'hold',
        'at': instant(1).toIso8601String(),
        'acceptSuggested': true,
      });
      equal(view['cursor'], 1);
      equal(view['timer'], null);
      final request = {
        'id': 'ex',
        'expectedVersion': view['version'],
        'expectedSessionVersion': view['sessionContentVersion'],
        'requestId': 'rest',
        'at': instant(1).toIso8601String(),
      };
      final run = await invoke([
        'execution',
        'run',
      ], jsonEncode({'schemaVersion': 1, 'database': path, ...request}));
      equal(run.code, 2);
      equal(run.output, '');
      view = await call('execution advance', request);
      equal(view['cursor'], 2);
      equal((await call('execution advance', request))['cursor'], 2);
      view = await call('execution complete', {
        'id': 'ex',
        'expectedVersion': view['version'],
        'expectedSessionVersion': view['sessionContentVersion'],
        'requestId': 'lift',
        'at': instant(1).toIso8601String(),
        'acceptSuggested': true,
      });
      equal(view['status'], 'completed');
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test(
    'carry confirmed actuals during guided rest keeps cursor and source version',
    () => _withStore((store, dir) async {
      final execution = await _startGroups(store);
      final advanced = await _step(
        store,
        execution,
        'first',
        action: 'complete',
      );
      final training = StoredTrainingService(store);
      var session = await training.session('group-session');
      final first = session.sets.first;
      final rest = await TimingService(store).show(advanced.clockId('rest'));
      await store.snapshot('$dir/v36.sqlite');
      final previous = sqlite3.open('$dir/v36.sqlite');
      previous.userVersion = 36;
      previous.close();
      equal(NativeBackup.validateDatabase('$dir/v36.sqlite'), 36);
      final migrated = await TrainingStore.open('$dir/v36.sqlite');
      equal(
        canonicalJson(
          (await StoredTrainingService(migrated).session(session.id)).toJson(),
        ),
        canonicalJson(session.toJson()),
      );
      await migrated.close();
      session = await training.carryActual(
        session.id,
        session.contentVersion,
        first.id,
        'mass',
      );
      final other = session.sets.lastWhere((s) => s.slotId == 'hold');
      equal(other.carriedTargets['mass']!.setId, first.id);
      equal(other.carriedTargets['mass']!.contentVersion, first.contentVersion);
      equal((await TimingService(store).show(rest.id)).version, rest.version);
      equal((await ExecutionService(store).show(execution.id)).cursor, 1);
      await expectLater(
        training.carryActual(
          session.id,
          session.contentVersion - 1,
          first.id,
          'mass',
        ),
        throwsA(isA<BodyTmiException>()),
      );
      session = await training.edit(
        session.id,
        session.contentVersion,
        (s) => const TrainingService().complete(s, first.id, {
          'mass': Quantity('2', 'kg'),
        }, acceptSuggested: true),
      );
      equal(
        session.set(other.id).carriedTargets['mass']!.contentVersion,
        first.contentVersion,
      );
      equal(session.set(other.id).suggested['mass']!.value.toString(), '1');
      await store.backup('$dir/carry-native');
      final file = '$dir/carry.json';
      await LogicalArchiveFiles.export(await store.archive(), file);
      final prepared = await LogicalArchiveFiles.prepare(file);
      final destination = await TrainingStore.open(
        '$dir/carry-restored.sqlite',
      );
      try {
        await destination.restore(
          prepared.backup,
          recoveryDestination: '$dir/carry-recovery',
          confirm: true,
        );
      } finally {
        await destination.close();
        await prepared.close();
      }
      final restored = await TrainingStore.open('$dir/carry-restored.sqlite');
      try {
        equal(
          canonicalJson(
            (await StoredTrainingService(
              restored,
            ).session(session.id)).toJson(),
          ),
          canonicalJson(session.toJson()),
        );
      } finally {
        await restored.close();
      }
      final envelope =
          jsonDecode(await File(file).readAsString()) as Map<String, Object?>;
      envelope['format'] = 'bodytmi-logical-export/36';
      envelope['sha256'] = sha256
          .convert(
            utf8.encode(
              canonicalJson({
                for (final e in envelope.entries)
                  if (e.key != 'sha256') e.key: e.value,
              }),
            ),
          )
          .toString();
      await File('$dir/old-carry.json').writeAsString(jsonEncode(envelope));
      await _fails(LogicalArchiveFiles.prepare('$dir/old-carry.json'));
      await store.snapshot('$dir/carry.sqlite');
      equal(NativeBackup.validateDatabase('$dir/carry.sqlite'), 42);
      final old = sqlite3.open('$dir/carry.sqlite');
      old.userVersion = 36;
      old.close();
      rejects(() => NativeBackup.validateDatabase('$dir/carry.sqlite'));
    }),
  );
  test(
    'carrying an actual rolls back if a destination effort clock is active',
    () => _withStore((store, _) async {
      final training = StoredTrainingService(store);
      await training.publish(_groupDefinition(), 0);
      var session = await training.start(
        'carry-session',
        'groups',
        1,
        instant(1),
      );
      session = await training.edit(
        session.id,
        session.contentVersion,
        (s) => const TrainingService().complete(
          s,
          s.sets.first.id,
          {},
          acceptSuggested: true,
        ),
      );
      final destination = session.sets.lastWhere((s) => s.slotId == 'hold');
      await TimingService(store).start(
        'carry-clock',
        session.id,
        destination.id,
        'duration',
        TimingPlan.fromJson({'effortMilliseconds': 1000}),
        instant(1),
      );
      await _fails(
        training.carryActual(
          session.id,
          session.contentVersion,
          session.sets.first.id,
          'mass',
        ),
      );
      equal(
        canonicalJson((await training.session(session.id)).toJson()),
        canonicalJson(session.toJson()),
      );
    }),
  );
  test(
    'guided target edits preserve receipts and rest clocks and apply to upcoming sets',
    () => _withStore((store, dir) async {
      var execution = await _startGroups(store);
      final training = StoredTrainingService(store);
      var session = await training.session('group-session');
      final first = session.sets.first;
      final oldSessionVersion = session.contentVersion;
      session = await training.editTarget(
        session.id,
        session.contentVersion,
        first.id,
        'mass',
        Quantity('3', 'kg'),
        applyToRemaining: true,
      );
      check(
        session.sets
            .where((s) => s.slotId == 'hold')
            .every((s) => s.suggested['mass']!.value.toString() == '3'),
      );
      await _fails(
        ExecutionService(store).step(
          execution.id,
          execution.version,
          oldSessionVersion,
          'stale',
          instant(1),
          action: 'complete',
          acceptSuggested: true,
        ),
      );
      execution = await _step(store, execution, 'hold', action: 'complete');
      equal(execution.cursor, 1);
      final holdResult = (await training.session(session.id)).sets.first;
      equal(holdResult.actuals['mass']!.value.toString(), '3');
      final rest = await TimingService(store).show(execution.clockId('rest'));
      session = await training.session(session.id);
      final lift = session.sets.firstWhere((s) => s.slotId == 'lift');
      session = await training.editTarget(
        session.id,
        session.contentVersion,
        lift.id,
        'mass',
        Quantity('12', 'kg'),
        applyToRemaining: true,
      );
      equal((await TimingService(store).show(rest.id)).version, rest.version);
      equal((await ExecutionService(store).show(execution.id)).cursor, 1);
      equal(
        canonicalJson(session.sets.first.toJson()),
        canonicalJson(holdResult.toJson()),
      );
      final retry = await ExecutionService(store).step(
        execution.id,
        1,
        oldSessionVersion + 1,
        'hold',
        instant(1),
        action: 'complete',
        acceptSuggested: true,
      );
      equal(retry.cursor, 1);
      await store.backup('$dir/edited-backup');
      final export = '$dir/edited-export.json';
      await LogicalArchiveFiles.export(await store.archive(), export);
      final prepared = await LogicalArchiveFiles.prepare(export);
      final destination = await TrainingStore.open('$dir/restored.sqlite');
      try {
        await destination.restore(
          prepared.backup,
          recoveryDestination: '$dir/recovery',
          confirm: true,
        );
      } finally {
        await destination.close();
        await prepared.close();
      }
      final restored = await TrainingStore.open('$dir/restored.sqlite');
      try {
        equal(
          canonicalJson(
            (await StoredTrainingService(
              restored,
            ).session(session.id)).toJson(),
          ),
          canonicalJson(session.toJson()),
        );
        equal((await ExecutionService(restored).show(execution.id)).cursor, 1);
        equal(
          (await TimingService(restored).show(rest.id)).version,
          rest.version,
        );
      } finally {
        await restored.close();
      }
      await _finishRest(store, execution);
      execution = await _step(store, execution, 'rest');
      execution = await _step(store, execution, 'lift', action: 'complete');
      session = await training.session(session.id);
      equal(session.set(lift.id).actuals['mass']!.value.toString(), '12');
      equal(execution.cursor, 3);
    }),
  );
  test(
    'target edits protect affected clocks while allowing unrelated effort clocks',
    () => _withStore((store, _) async {
      final execution = await _startGroups(store);
      final training = StoredTrainingService(store);
      var session = await training.session('group-session');
      final first = session.sets.first;
      final lastHold = session.sets.lastWhere((s) => s.slotId == 'hold');
      final clock = await TimingService(store).start(
        'future-clock',
        session.id,
        lastHold.id,
        'duration',
        TimingPlan.fromJson({'effortMilliseconds': 1000}),
        instant(1),
      );
      await _fails(
        training.editTarget(
          session.id,
          session.contentVersion,
          first.id,
          'mass',
          Quantity('3', 'kg'),
          applyToRemaining: true,
        ),
      );
      equal(
        canonicalJson((await training.session(session.id)).toJson()),
        canonicalJson(session.toJson()),
      );
      session = await training.editTarget(
        session.id,
        session.contentVersion,
        first.id,
        'mass',
        Quantity('3', 'kg'),
      );
      equal((await TimingService(store).show(clock.id)).version, clock.version);
      equal((await ExecutionService(store).show(execution.id)).cursor, 0);
      final resumed = await TimingService(
        store,
      ).resume(clock.id, clock.version, 'epoch', instant(1));
      final pending = (await TimingService(
        store,
      ).advance(clock.id, resumed.version, 'epoch', 1000, instant(1))).activity;
      equal(pending.status, 'awaitingConfirmation');
      await _fails(
        training.editTarget(
          session.id,
          session.contentVersion,
          lastHold.id,
          'duration',
          Quantity('2', 's'),
        ),
      );
      equal(
        (await training.session(session.id)).contentVersion,
        session.contentVersion,
      );
    }),
  );
  test(
    'skip remaining defers to active traversal and preserves its cursor',
    () => _withStore((store, _) async {
      final execution = await _start(store);
      final training = StoredTrainingService(store);
      final before = await training.session('session');
      await _fails(
        training.skipSlot(
          before.id,
          before.contentVersion,
          before.sets.first.slotId,
          confirm: true,
        ),
      );
      await _fails(
        training.skipRemaining(before.id, before.contentVersion, confirm: true),
      );
      equal((await ExecutionService(store).show(execution.id)).cursor, 0);
      equal(
        canonicalJson((await training.session(before.id)).toJson()),
        canonicalJson(before.toJson()),
      );
      final completed = await ExecutionService(store).skipGroup(
        execution.id,
        execution.version,
        before.contentVersion,
        'skip-all',
        'workout',
        instant(1),
        confirm: true,
      );
      check(completed.complete);
      final skipped = await training.session(before.id);
      equal(
        (await training.skipRemaining(
          skipped.id,
          skipped.contentVersion,
          confirm: true,
        )).contentVersion,
        skipped.contentVersion,
      );
    }),
  );
  test(
    'skipping a workout group advances only its selected program on finish, with no progression application',
    () => _withStore((store, dir) async {
      final programs = ProgramService(store),
          executions = ExecutionService(store);
      for (final id in ['strength', 'cardio']) {
        await programs.publish(
          ProgramDefinition.fromJson({
            'id': id,
            'name': id,
            'plan': {
              'id': 'day',
              'type': 'day',
              'templateId': 'traversal',
              'revision': 1,
            },
          }),
          0,
        );
        await programs.create('$id-run', id, 1, instant(1));
        await programs.start('$id-run', 1, id, instant(1));
        await _start(store, id: '$id-execution', session: id);
      }
      final cardio = canonicalJson((await programs.run('cardio-run')).toJson());
      await executions.skipGroup(
        'strength-execution',
        1,
        1,
        'omit-workout',
        'workout',
        instant(1),
        confirm: true,
      );
      equal((await programs.run('strength-run')).cursor, 0);
      equal((await store.progressionDecisions()).length, 0);
      final training = StoredTrainingService(store);
      var s = (await store.session('strength'))!;
      s = await training.edit(
        s.id,
        s.contentVersion,
        (s) => s.finish(instant(1)),
      );
      equal((await programs.run('strength-run')).cursor, 1);
      equal(canonicalJson((await programs.run('cardio-run')).toJson()), cardio);
      await executions.skipGroup(
        'strength-execution',
        1,
        1,
        'omit-workout',
        'workout',
        instant(1),
        confirm: true,
      );
      await training.edit(s.id, s.contentVersion, (s) => s.finish(instant(1)));
      equal((await programs.run('strength-run')).cursor, 1);
      equal((await store.programReceipts()).length, 1);
      await store.archive();
    }),
  );

  test(
    'v8 profiles migrate unchanged and v9 native/logical restore retains group receipts while old labels reject them',
    () => _withStore((store, dir) async {
      final e = await _startGroups(store);
      final original = canonicalJson((await store.archive()).toJson());
      await store.backup('$dir/v8');
      final old = sqlite3.open('$dir/v8/database.sqlite');
      old.execute('DROP TABLE family_revisions');
      old.execute('DROP TABLE derived_target_graphs');
      old.userVersion = 8;
      old.close();
      equal(await NativeBackup.validateDatabase('$dir/v8/database.sqlite'), 8);
      await store.close();
      final migrated = await TrainingStore.open('$dir/v8/database.sqlite');
      try {
        equal(canonicalJson((await migrated.archive()).toJson()), original);
        equal(
          (await migrated.backup('$dir/migrated'))['databaseSchemaVersion'],
          42,
        );
      } finally {
        await migrated.close();
      }
      var active = await TrainingStore.open('$dir/db.sqlite');
      try {
        await LogicalArchiveFiles.export(
          await active.archive(),
          '$dir/old.json',
        );
        final legacy = jsonObject(
          jsonDecode(await File('$dir/old.json').readAsString()),
          'legacy',
        );
        jsonObject(legacy['data'], 'data').remove('families');
        legacy['format'] = 'bodytmi-logical-export/8';
        legacy.remove('sha256');
        legacy['sha256'] = sha256
            .convert(utf8.encode(canonicalJson(legacy)))
            .toString();
        await File('$dir/old.json').writeAsString(jsonEncode(legacy));
        final oldLogical = await LogicalArchiveFiles.prepare('$dir/old.json');
        await oldLogical.close();
        await ExecutionService(active).skipGroup(
          e.id,
          1,
          1,
          'round',
          'workout/rounds[0]',
          instant(1),
          confirm: true,
        );
        final skipped = canonicalJson((await active.archive()).toJson());
        await active.backup('$dir/native');
        await LogicalArchiveFiles.export(
          await active.archive(),
          '$dir/new.json',
        );
        final logical = await LogicalArchiveFiles.prepare('$dir/new.json');
        try {
          await active.restore(
            logical.backup,
            recoveryDestination: '$dir/recovery-logical',
            confirm: true,
          );
          await active.close();
          active = await TrainingStore.open('$dir/db.sqlite');
          equal(canonicalJson((await active.archive()).toJson()), skipped);
        } finally {
          await logical.close();
        }
        final native = await NativeBackup.prepare('$dir/native');
        try {
          await active.restore(
            native,
            recoveryDestination: '$dir/recovery-native',
            confirm: true,
          );
          await active.close();
          active = await TrainingStore.open('$dir/db.sqlite');
          equal(canonicalJson((await active.archive()).toJson()), skipped);
        } finally {
          await native.close();
        }
        equal(
          (await ExecutionService(active).skipGroup(
            e.id,
            1,
            1,
            'round',
            'workout/rounds[0]',
            instant(1),
            confirm: true,
          )).cursor,
          3,
        );
        final forged = sqlite3.open('$dir/native/database.sqlite');
        forged.execute('DROP TABLE family_revisions');
        forged.execute('DROP TABLE derived_target_graphs');
        forged.userVersion = 8;
        forged.close();
        rejects(
          () => NativeBackup.validateDatabase('$dir/native/database.sqlite'),
        );
        final mislabeled = jsonObject(
          jsonDecode(await File('$dir/new.json').readAsString()),
          'export',
        );
        jsonObject(mislabeled['data'], 'data').remove('families');
        mislabeled['format'] = 'bodytmi-logical-export/8';
        mislabeled.remove('sha256');
        mislabeled['sha256'] = sha256
            .convert(utf8.encode(canonicalJson(mislabeled)))
            .toString();
        await File('$dir/new.json').writeAsString(jsonEncode(mislabeled));
        await _fails(LogicalArchiveFiles.prepare('$dir/new.json'));
      } finally {
        await active.close();
      }
    }),
  );
  test(
    'native CLI exposes structural choices and skips one group with explicit confirmation and stable retries',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-group-cli-');
      try {
        Future<Map<String, Object?>> command(
          String name,
          Map<String, Object?> input,
        ) async {
          final r = await invoke(
            name.split(' '),
            jsonEncode({
              'schemaVersion': 1,
              'database': '${dir.path}/db.sqlite',
              ...input,
            }),
          );
          equal(r.code, 0);
          equal(r.error, '');
          return jsonObject(
            jsonObject(jsonDecode(r.output), 'response')['data'],
            'data',
          );
        }

        await command('store publish', {
          'definition': _groupDefinition().toJson(),
          'expectedRevision': 0,
        });
        await command('store start', {
          'id': 'session',
          'templateId': 'groups',
          'revision': 1,
          'startedAt': instant(1).toIso8601String(),
        });
        var v = await command('execution start', {
          'id': 'execution',
          'sessionId': 'session',
          'at': instant(1).toIso8601String(),
        });
        final choices = jsonList(
          v,
          'groups',
        ).map((g) => jsonObject(g, 'group')['path']).toSet();
        check(choices.contains('workout/rounds[0]'));
        check(!choices.contains('workout/rounds[1]'));
        final req = {
          'id': 'execution',
          'expectedVersion': 1,
          'expectedSessionVersion': 1,
          'requestId': 'skip-round',
          'groupPath': 'workout/rounds[0]',
          'at': instant(1).toIso8601String(),
          'confirm': true,
        };
        final denied = await invoke(
          ['execution', 'skip-group'],
          jsonEncode({
            'schemaVersion': 1,
            'database': '${dir.path}/db.sqlite',
            ...req,
            'confirm': false,
          }),
        );
        check(denied.code != 0);
        equal(denied.output, '');
        v = await command('execution skip-group', req);
        equal(v['cursor'], 3);
        equal(jsonObject(v['timer'], 'timer')['phase'], 'rest');
        final retry = await command('execution skip-group', req);
        jsonEqual(retry, v);
        final session = await command('store show', {'id': 'session'});
        equal(
          jsonList(
            session,
            'sets',
          ).where((s) => jsonObject(s, 'set')['status'] == 'skipped').length,
          2,
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'process death commits or rolls back the entire skipped round, boundary receipts and following rest clock',
    () => _withStore((store, dir) async {
      await _startGroups(store);
      await store.close();
      final binary = await compileNative(
        'test/helpers/store_owner.dart',
        '$dir/group-owner',
      );
      for (final mode in [
        'execution-group-rollback',
        'execution-group-commit',
      ]) {
        final child = await Process.start(binary, ['$dir/db.sqlite', mode]);
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
        } finally {
          child.kill(ProcessSignal.sigkill);
          await child.exitCode;
        }
        final recovered = await TrainingStore.open('$dir/db.sqlite');
        try {
          final service = ExecutionService(recovered);
          final e = await service.show('execution');
          final committed = mode.endsWith('commit');
          equal(e.cursor, committed ? 3 : 0);
          equal(
            (await recovered.session(
              'group-session',
            ))!.sets.where((s) => s.status == SetStatus.skipped).length,
            committed ? 2 : 0,
          );
          equal((await recovered.timingActivities()).length, committed ? 1 : 0);
          if (committed) {
            equal(
              (await service.skipGroup(
                e.id,
                1,
                1,
                'crash-group',
                'workout/rounds[0]',
                instant(1),
                confirm: true,
              )).cursor,
              3,
            );
          }
          await recovered.archive();
        } finally {
          await recovered.close();
        }
      }
    }),
  );

  test(
    'group bounds distinguish nested repeat rounds and enclosing recovery',
    () {
      final groups = activityGroups(_groupDefinition().plan);
      final byPath = {for (final g in groups) g.path: g};
      equal(byPath['workout/rounds[0]']!.start, 0);
      equal(byPath['workout/rounds[0]']!.end, 3);
      equal(byPath['workout/rounds[1]']!.start, 4);
      equal(byPath['workout/rounds']!.end, 7);
      equal(byPath['workout']!.end, 8);
      equal(byPath['workout/rounds[0]']!.contains(3), false);
      final window = activityGroups(
        TimeWindow('window', 10, const Effort('e', 'hold')),
      ).single;
      equal(window.windowDurationSeconds, 10);
      equal(window.start, 0);
      equal(window.end, 1);
    },
  );
  test(
    'skipping a partial round preserves actuals, discards its rest and prepares only the next boundary',
    () => _withStore((store, dir) async {
      var e = await _startGroups(store);
      e = await _step(store, e, 'first', action: 'complete');
      final before = (await store.session('group-session'))!;
      final rest = await TimingService(store).show(e.clockId('rest'));
      final service = ExecutionService(store);
      final view = await service.view(e.id);
      check(
        jsonList(
          view,
          'groups',
        ).any((g) => jsonObject(g, 'group')['path'] == 'workout/rounds[0]'),
      );
      e = await service.skipGroup(
        e.id,
        e.version,
        before.contentVersion,
        'round',
        'workout/rounds[0]',
        instant(1),
        confirm: true,
      );
      equal(e.cursor, 3);
      equal((await TimingService(store).show(rest.id)).status, 'discarded');
      var s = (await store.session('group-session'))!;
      equal(s.sets.first.status, SetStatus.completed);
      jsonEqual(s.sets.first.toJson(), before.sets.first.toJson());
      equal(s.sets[1].status, SetStatus.skipped);
      equal((await store.timingActivities()).length, 2);
      equal(
        (await TimingService(store).show(e.clockId('rest'))).status,
        'paused',
      );
      s = await StoredTrainingService(store).edit(
        s.id,
        s.contentVersion,
        (session) => const TrainingService().complete(
          session,
          session.sets.first.id,
          {'duration': Quantity('2', 's')},
          acceptSuggested: true,
        ),
      );
      e = await service.skipGroup(
        e.id,
        2,
        before.contentVersion,
        'round',
        'workout/rounds[0]',
        instant(1),
        confirm: true,
      );
      equal(e.cursor, 3);
      equal(
        (await store.session(
          s.id,
        ))!.sets.first.actuals['duration']!.value.toString(),
        '2',
      );
      await _fails(
        service.skipGroup(
          e.id,
          2,
          before.contentVersion,
          'round',
          'workout/rounds',
          instant(1),
          confirm: true,
        ),
      );
      e = await service.skipGroup(
        e.id,
        e.version,
        s.contentVersion,
        'remaining-rounds',
        'workout/rounds',
        instant(1),
        confirm: true,
      );
      equal(e.cursor, 7);
      equal(
        (await store.timingActivities()).length,
        2,
      ); // No omitted interior rest clocks.
      s = (await store.session(s.id))!;
      equal(s.sets.where((set) => set.status == SetStatus.skipped).length, 3);
      equal(s.sets.last.status, SetStatus.planned);
      e = await _step(store, e, 'tail', action: 'complete');
      equal(e.complete, true);
      s = (await store.session(s.id))!;
      await StoredTrainingService(
        store,
      ).edit(s.id, s.contentVersion, (s) => s.finish(instant(1)));
      await store.archive();
    }),
  );
  test(
    'group skip preserves previously logged future work and neutral skipped results',
    () => _withStore((store, dir) async {
      final e = await _startGroups(store);
      var s = (await store.session(e.sessionId))!;
      s = await StoredTrainingService(store).edit(
        s.id,
        s.contentVersion,
        (s) => const TrainingService().complete(
          s,
          s.sets[1].id,
          {},
          acceptSuggested: true,
        ),
      );
      final saved = s.sets[1].toJson();
      final next = await ExecutionService(store).skipGroup(
        e.id,
        e.version,
        s.contentVersion,
        'all',
        'workout',
        instant(1),
        confirm: true,
      );
      equal(next.complete, true);
      s = (await store.session(e.sessionId))!;
      jsonEqual(s.sets[1].toJson(), saved);
      equal(s.sets.where((set) => set.status == SetStatus.skipped).length, 4);
      equal((await store.timingActivities()).length, 0);
      await store.archive();
    }),
  );
  test(
    'group skip rejects wrong scope, stale versions, missing confirmation and reused child request IDs',
    () => _withStore((store, dir) async {
      final service = ExecutionService(store);
      var e = await _startGroups(store);
      for (final path in [
        'workout/round',
        'workout/rounds[1]',
        'workout/rounds[0]/pair/hold',
      ]) {
        await _fails(
          service.skipGroup(
            e.id,
            1,
            1,
            'skip',
            path,
            instant(1),
            confirm: true,
          ),
        );
      }
      await _fails(
        service.skipGroup(
          e.id,
          1,
          1,
          'skip',
          'workout',
          instant(1),
          confirm: false,
        ),
      );
      await _fails(
        service.skipGroup(
          e.id,
          2,
          1,
          'skip',
          'workout',
          instant(1),
          confirm: true,
        ),
      );
      await _fails(
        service.skipGroup(
          e.id,
          1,
          2,
          'skip',
          'workout',
          instant(1),
          confirm: true,
        ),
      );
      await _fails(
        service.skipGroup(
          e.id,
          1,
          1,
          'skip',
          'workout',
          instant(1).subtract(const Duration(seconds: 1)),
          confirm: true,
        ),
      );
      e = await _step(store, e, 'skip-group-2', action: 'complete');
      await _fails(
        service.skipGroup(
          e.id,
          2,
          2,
          'skip',
          'workout',
          instant(1),
          confirm: true,
        ),
      );
      equal((await service.show(e.id)).cursor, 1);
      equal(
        (await store.session(e.sessionId))!.sets[1].status,
        SetStatus.planned,
      );
    }),
  );
  test(
    'next-rest clock conflicts roll back discarded review clocks, all results and the entire group cursor',
    () => _withStore((store, dir) async {
      final e = await _startGroups(store);
      final service = ExecutionService(store), timers = TimingService(store);
      var t = await service.time(e.id, e.version, instant(1));
      t = await timers.resume(t.id, t.version, 'epoch', instant(1));
      t = (await timers.advance(
        t.id,
        t.version,
        'epoch',
        1000,
        instant(1),
      )).activity;
      equal(t.status, 'awaitingConfirmation');
      await StoredTrainingService(
        store,
      ).start('other', 'traversal', 1, instant(1));
      await timers.start(
        'other-clock',
        'other',
        'workout/hold-set',
        'duration',
        TimingPlan.fromJson({'effortMilliseconds': 1000}),
        instant(1),
      );
      final before = canonicalJson((await store.archive()).toJson());
      await _fails(
        service.skipGroup(
          e.id,
          1,
          1,
          'conflict',
          'workout/rounds[0]',
          instant(1),
          confirm: true,
        ),
      );
      equal(canonicalJson((await store.archive()).toJson()), before);
      await timers.stop(
        'other-clock',
        1,
        instant(1),
        confirm: true,
        discard: true,
      );
      final next = await service.skipGroup(
        e.id,
        1,
        1,
        'conflict',
        'workout/rounds[0]',
        instant(1),
        confirm: true,
      );
      equal(next.cursor, 3);
      equal((await timers.show(t.id)).status, 'discarded');
      await store.archive();
    }),
  );
  test(
    'aggregate validation rejects truncated, reordered and forged group receipts',
    () => _withStore((store, dir) async {
      final e = await _startGroups(store);
      await ExecutionService(
        store,
      ).skipGroup(e.id, 1, 1, 'all', 'workout', instant(1), confirm: true);
      final base = (await store.archive()).toJson();
      final mutations = <void Function(List<Object?>)>[
        (rows) => rows.removeLast(),
        (rows) => jsonObject(
          jsonObject(rows.first, 'row')['request'],
          'request',
        )['groupPath'] = 'workout/rounds[0]',
        (rows) => jsonObject(
          jsonObject(rows[1], 'row')['request'],
          'request',
        )['sessionVersion'] = 2,
        (rows) => jsonObject(rows[1], 'row')['requestId'] = 'forged',
        (rows) => jsonObject(
          jsonObject(rows[1], 'row')['request'],
          'request',
        )['groupStart'] = 1,
        (rows) => jsonObject(
          jsonObject(rows.first, 'row')['request'],
          'request',
        )['groupEnd'] = 3,
        (rows) => jsonObject(
          jsonObject(rows.first, 'row')['request'],
          'request',
        )['confirm'] = false,
      ];
      for (final mutate in mutations) {
        final data = copyJson(base);
        final execution = jsonObject(
          jsonList(data, 'executions').single,
          'execution',
        );
        mutate(jsonList(execution, 'receipts'));
        rejects(() => TrainingArchive.fromJson(data));
      }
    }),
  );

  test(
    'the requested nested 3x12 walk/run traversal acknowledges 72 efforts and exactly two outer rests without a trailing rest',
    () => _withStore((store, dir) async {
      final definition = WorkoutDefinition.fromJson({
        'id': 'nested',
        'name': 'Nested intervals',
        'slots': [
          for (final id in ['walk', 'run'])
            {
              'id': id,
              'exercise': id,
              'implementation': 'outdoors',
              'targets': {
                'duration': {'value': '30', 'unit': 's'},
              },
            },
        ],
        'plan': {
          'id': 'outer',
          'type': 'repeat',
          'count': 3,
          'restBetweenSeconds': 120,
          'child': {
            'id': 'inner',
            'type': 'repeat',
            'count': 12,
            'child': {
              'id': 'pair',
              'type': 'sequence',
              'children': [
                for (final id in ['walk', 'run'])
                  {'id': id, 'type': 'effort', 'slot': id},
              ],
            },
          },
        },
      });
      final training = StoredTrainingService(store);
      await training.publish(definition, 0);
      await training.start('nested', 'nested', 1, instant(1));
      var e = await _start(store, id: 'nested-execution', session: 'nested');
      equal(e.occurrenceCount, 74);
      var rests = 0, efforts = 0;
      while (!e.complete) {
        final s = (await store.session('nested'))!;
        final o = executionPlan(s)[e.cursor];
        if (o.activity is Rest) {
          final t = await _finishRest(store, e);
          equal(t.status, 'completed');
          equal(t.phase, 'done');
          equal(t.effortElapsedMilliseconds, 0);
          equal(t.elapsedMilliseconds, 120000);
          await _fails(
            TimingService(store).confirm(
              t.id,
              t.version,
              s.contentVersion,
              instant(1),
              {},
              acceptSuggested: true,
            ),
          );
          e = await _step(store, e, 'rest-${e.cursor}');
          rests++;
        } else {
          e = await _step(store, e, 'effort-${e.cursor}', action: 'complete');
          efforts++;
        }
      }
      equal(rests, 2);
      equal(efforts, 72);
      equal(e.receipts.last['kind'], 'effort');
      final s = (await store.session('nested'))!;
      equal(s.sets.where((s) => s.status == SetStatus.completed).length, 72);
      equal(s.sets.map((s) => s.id).toSet().length, 72);
      equal(s.status, SessionStatus.active);
      final sum =
          s.sets.fold(
            Decimal.zero,
            (sum, set) => sum + set.actuals['duration']!.value,
          ) +
          Decimal.parse((rests * 120).toString());
      equal(sum.toString(), '2400');
      await training.edit(
        s.id,
        s.contentVersion,
        (s) => s.finish(instant(1).add(const Duration(minutes: 40))),
      );
      await store.archive();
    }),
  );
  test(
    'manual completion prepares authored rest, acknowledges it once, and retries preserve corrected actuals and cursor',
    () => _withStore((store, dir) async {
      final service = ExecutionService(store),
          training = StoredTrainingService(store);
      // A wall-clock jump does not invalidate the logical occurrence order.
      var e = await service.start(
        'execution',
        'session',
        instant(1).add(const Duration(minutes: 10)),
      );
      e = await _step(store, e, 'first', action: 'complete');
      equal(e.cursor, 1);
      final rest = await TimingService(store).show(e.clockId('rest'));
      equal(rest.phase, 'rest');
      equal(rest.status, 'paused');
      equal(rest.effortElapsedMilliseconds, 0);
      await _fails(_step(store, e, 'premature'));
      await _fails(training.edit('session', 2, finished));
      await _finishRest(store, e);
      e = await _step(store, e, 'rest');
      equal(e.cursor, 2);
      await training.edit(
        'session',
        2,
        (s) => const TrainingService().complete(s, 'workout/hold-set', {
          'duration': Quantity('2', 's'),
          'mass': Quantity('5', 'kg'),
        }),
      );
      final retry = await service.step(
        e.id,
        1,
        1,
        'first',
        instant(1),
        action: 'complete',
        acceptSuggested: true,
      );
      equal(retry.cursor, 2);
      equal(
        (await store.session(
          'session',
        ))!.sets.first.actuals['mass']!.value.toString(),
        '5',
      );
      await _fails(
        service.step(
          e.id,
          1,
          1,
          'first',
          instant(2),
          action: 'complete',
          acceptSuggested: true,
        ),
      );
      e = await _step(store, e, 'second', action: 'complete');
      equal(e.complete, true);
      final s = (await store.session('session'))!;
      await training.edit(s.id, s.contentVersion, (s) => s.finish(instant(2)));
      equal((await service.show(e.id)).cursor, 3);
      await store.archive();
    }),
  );
  test(
    'timed effort confirmation atomically advances traversal into rest but never another program or its cursor',
    () => _withStore((store, dir) async {
      final programs = ProgramService(store),
          executions = ExecutionService(store),
          training = StoredTrainingService(store),
          timers = TimingService(store);
      for (final id in ['strength', 'cardio']) {
        await programs.publish(
          ProgramDefinition.fromJson({
            'id': id,
            'name': id,
            'plan': {
              'id': 'day',
              'type': 'day',
              'templateId': 'traversal',
              'revision': 1,
            },
          }),
          0,
        );
        await programs.create('$id-run', id, 1, instant(1));
        await programs.start('$id-run', 1, id, instant(1));
        await _start(store, id: '$id-execution', session: id);
      }
      var e = await executions.show('strength-execution');
      var timer = await executions.time(
        e.id,
        e.version,
        instant(1),
        plan: TimingPlan.fromJson({
          'preparationMilliseconds': 10000,
          'effortMilliseconds': 1000,
        }),
      );
      timer = await timers.resume(timer.id, timer.version, 'epoch', instant(1));
      timer = (await timers.advance(
        timer.id,
        timer.version,
        'epoch',
        11000,
        instant(1),
      )).activity;
      equal(e.cursor, 0);
      equal(
        (await store.session('strength'))!.sets.first.status,
        SetStatus.planned,
      );
      e = await executions.step(
        e.id,
        1,
        1,
        'confirm',
        instant(1),
        action: 'confirm',
        timerId: timer.id,
        timerVersion: timer.version,
        acceptSuggested: true,
      );
      equal(e.cursor, 1);
      equal(
        (await store.session(
          'strength',
        ))!.sets.first.actuals['duration']!.value.toString(),
        '1',
      );
      equal((await executions.show('cardio-execution')).cursor, 0);
      equal((await programs.run('strength-run')).cursor, 0);
      equal((await programs.run('cardio-run')).cursor, 0);
      await _finishRest(store, e);
      e = await _step(store, e, 'rest');
      e = await _step(store, e, 'lift', action: 'complete');
      final s = (await store.session('strength'))!;
      await training.edit(s.id, s.contentVersion, (s) => s.finish(instant(2)));
      await executions.step(
        e.id,
        1,
        1,
        'confirm',
        instant(1),
        action: 'confirm',
        timerId: timer.id,
        timerVersion: timer.version,
        acceptSuggested: true,
      );
      equal((await programs.run('strength-run')).cursor, 1);
      equal((await programs.run('cardio-run')).cursor, 0);
      equal((await store.programReceipts()).length, 1);
      await store.archive();
    }),
  );
  test(
    'neutral skips discard active clocks, and a conflicting next rest rolls back result/cursor/receipt creation',
    () => _withStore((store, dir) async {
      final execution = ExecutionService(store),
          training = StoredTrainingService(store),
          timers = TimingService(store);
      var e = await _start(store);
      await training.start('other', 'traversal', 1, instant(1));
      var blocking = await timers.start(
        'blocking',
        'other',
        'workout/hold-set',
        'duration',
        TimingPlan.fromJson({'effortMilliseconds': 1000}),
        instant(1),
      );
      await _fails(_step(store, e, 'blocked', action: 'complete'));
      equal(
        (await store.session('session'))!.sets.first.status,
        SetStatus.planned,
      );
      equal((await execution.show(e.id)).cursor, 0);
      equal((await store.timingActivities()).length, 1);
      await timers.stop(
        blocking.id,
        blocking.version,
        instant(1),
        confirm: true,
        discard: true,
      );
      final effort = await execution.time(e.id, e.version, instant(1));
      await _fails(_step(store, e, 'no-confirm', action: 'skip'));
      e = await _step(store, e, 'skip-effort', action: 'skip', confirm: true);
      equal((await timers.show(effort.id)).status, 'discarded');
      equal(
        (await store.session('session'))!.sets.first.status,
        SetStatus.skipped,
      );
      e = await _step(store, e, 'skip-rest', action: 'skip', confirm: true);
      e = await _step(store, e, 'skip-lift', action: 'skip', confirm: true);
      equal(e.complete, true);
      equal((await store.progressionDecisions()).length, 0);
      equal(
        (await store.session(
          'session',
        ))!.sets.where((s) => s.actuals.isNotEmpty).length,
        0,
      );
      await store.archive();
    }),
  );
  test(
    'execution rejects windows, ambiguous occurrence IDs, oversized rests/IDs and conflicting managed clock identities before changing state',
    () => _withStore((store, dir) async {
      final training = StoredTrainingService(store);
      for (final mode in ['window', 'collision', 'long-rest']) {
        final j = _definition().toJson();
        j['id'] = mode;
        j['plan'] = switch (mode) {
          'window' => {
            'id': 'scope',
            'type': 'window',
            'durationSeconds': 1,
            'child': j['plan'],
          },
          'collision' => {
            'id': 'repeat',
            'type': 'repeat',
            'count': 2,
            'restBetweenSeconds': 1,
            'child': {'id': 'between', 'type': 'effort', 'slot': 'hold'},
          },
          _ => {
            'id': 'sequence',
            'type': 'sequence',
            'children': [
              {'id': 'hold', 'type': 'effort', 'slot': 'hold'},
              {'id': 'rest', 'type': 'rest', 'durationSeconds': 86401},
            ],
          },
        };
        await training.publish(WorkoutDefinition.fromJson(j), 0);
        await training.start(mode, mode, 1, instant(1));
        await _fails(_start(store, id: mode, session: mode));
      }
      await _fails(_start(store, id: List.filled(65, 'x').join()));
      await training.start('other', 'traversal', 1, instant(1));
      await TimingService(store).start(
        'execution-reserved-effort-0',
        'other',
        'workout/hold-set',
        'duration',
        TimingPlan.fromJson({'effortMilliseconds': 1000}),
        instant(1),
      );
      await _fails(_start(store, id: 'reserved'));
      equal((await store.executions()).length, 0);
      final timing = TimingService(store);
      final blocked = await timing.show('execution-reserved-effort-0');
      await timing.stop(
        blocked.id,
        blocked.version,
        instant(1),
        confirm: true,
        discard: true,
      );
      final fractional = _definition().toJson();
      fractional['id'] = 'fractional';
      jsonObject(
        jsonObject(jsonList(fractional, 'slots').first, 'slot')['targets'],
        'targets',
      )['duration'] = {
        'value': '0.0001',
        'unit': 's',
      };
      await training.publish(WorkoutDefinition.fromJson(fractional), 0);
      await training.start('fractional', 'fractional', 1, instant(1));
      final e = await _start(store, id: 'fractional', session: 'fractional');
      final execution = ExecutionService(store);
      await _fails(execution.time(e.id, e.version, instant(1)));
      final explicit = await execution.time(
        e.id,
        e.version,
        instant(1),
        plan: TimingPlan.fromJson({'effortMilliseconds': 1}),
      );
      equal(explicit.plan.effortMilliseconds, 1);
      equal(
        (await store.session(
          'fractional',
        ))!.sets.first.suggested['duration']!.value.toString(),
        '0.0001',
      );
    }),
  );
  test(
    'full validation rejects forged traversal paths, result versions, rest ownership and request content',
    () => _withStore((store, dir) async {
      var e = await _start(store);
      e = await _step(store, e, 'first', action: 'complete');
      await _finishRest(store, e);
      e = await _step(store, e, 'rest');
      final base = (await store.archive()).toJson();
      Map<String, Object?> receipt(Map<String, Object?> j, int n) => jsonObject(
        jsonList(
          jsonObject(jsonList(j, 'executions').single, 'execution'),
          'receipts',
        )[n],
        'receipt',
      );
      final mutations = <void Function(Map<String, Object?>)>[
        (j) => receipt(j, 0)['path'] = 'forged',
        (j) => receipt(j, 0)['ordinal'] = 9,
        (j) => receipt(j, 0)['setVersion'] = 999,
        (j) => receipt(j, 1)['timerId'] = 'missing',
        (j) => jsonObject(receipt(j, 0)['request'], 'request')['actuals'] = {
          'mass': {'value': '99', 'unit': 'kg'},
          'duration': {'value': '1', 'unit': 's'},
        },
        (j) => jsonList(j, 'timers').clear(),
        (j) => jsonList(j, 'executions').add(jsonList(j, 'executions').single),
      ];
      for (final mutate in mutations) {
        final j = copyJson(base);
        mutate(j);
        rejects(() => TrainingArchive.fromJson(j));
      }
      await store.archive();
    }),
  );
  test(
    'current rest checkpoints and cursor receipts survive native/logical restore without logging or advancing on recovery',
    () => _withStore((store, dir) async {
      var e = await _start(store);
      e = await _step(store, e, 'first', action: 'complete');
      var timer = await TimingService(store).show(e.clockId('rest'));
      timer = await TimingService(
        store,
      ).resume(timer.id, timer.version, 'epoch', instant(1));
      await TimingService(
        store,
      ).advance(timer.id, timer.version, 'epoch', 250, instant(1));
      final original = canonicalJson((await store.archive()).toJson());
      equal((await store.backup('$dir/native'))['databaseSchemaVersion'], 42);
      equal(
        (await LogicalArchiveFiles.export(
          await store.archive(),
          '$dir/logical.json',
        ))['format'],
        'bodytmi-logical-export/42',
      );
      final prepared = await LogicalArchiveFiles.prepare('$dir/logical.json');
      try {
        await store.restore(
          prepared.backup,
          recoveryDestination: '$dir/recovery',
          confirm: true,
        );
      } finally {
        await prepared.close();
        await store.close();
      }
      final reopened = await TrainingStore.open('$dir/db.sqlite');
      try {
        equal(canonicalJson((await reopened.archive()).toJson()), original);
        final native = await NativeBackup.prepare('$dir/native');
        try {
          await reopened.restore(
            native,
            recoveryDestination: '$dir/recovery2',
            confirm: true,
          );
        } finally {
          await native.close();
        }
      } finally {
        await reopened.close();
      }
      final again = await TrainingStore.open('$dir/db.sqlite');
      try {
        equal(canonicalJson((await again.archive()).toJson()), original);
        final service = ExecutionService(again), timing = TimingService(again);
        final view = await service.view(e.id);
        equal(jsonObject(view['timer'], 'timer')['requiresRecovery'], true);
        equal((await service.show(e.id)).cursor, 1);
        var t = await timing.show(e.clockId('rest'));
        t = await timing.recover(t.id, t.version, instant(9));
        equal(t.phaseElapsedMilliseconds, 250);
        t = await timing.resume(t.id, t.version, 'new', instant(9));
        t = (await timing.advance(
          t.id,
          t.version,
          'new',
          750,
          instant(9),
        )).activity;
        equal(t.status, 'completed');
        equal(t.effortElapsedMilliseconds, 0);
        await _step(again, e, 'rest');
        equal(
          (await again.session('session'))!.sets.last.status,
          SetStatus.planned,
        );
      } finally {
        await again.close();
      }
    }),
  );
  test(
    'schema/logical v7 migrate with unchanged per-set clocks while old labels cannot carry execution or rest-only semantics',
    () => _withStore((store, dir) async {
      final timer = await TimingService(store).start(
        'legacy',
        'session',
        'workout/hold-set',
        'duration',
        TimingPlan.fromJson({'effortMilliseconds': 1000}),
        instant(1),
      );
      final original = (await store.archive()).toJson();
      final doc = <String, Object?>{
        'format': 'bodytmi-logical-export/7',
        'applicationVersion': '0.1.0',
        'data': Map<String, Object?>.from(original)
          ..remove('families')
          ..remove('executions'),
      };
      doc['sha256'] = sha256
          .convert(utf8.encode(canonicalJson(doc)))
          .toString();
      await File('$dir/v7.json').writeAsString(jsonEncode(doc));
      final prepared = await LogicalArchiveFiles.prepare('$dir/v7.json');
      try {
        jsonEqual(prepared.archive.toJson(), original);
      } finally {
        await prepared.close();
      }
      doc.remove('sha256');
      doc['data'] = original;
      doc['sha256'] = sha256
          .convert(utf8.encode(canonicalJson(doc)))
          .toString();
      await File('$dir/forged.json').writeAsString(jsonEncode(doc));
      await _fails(LogicalArchiveFiles.prepare('$dir/forged.json'));
      await store.close();
      final raw = sqlite3.open('$dir/db.sqlite');
      try {
        raw.execute('DROP TABLE family_revisions');
        raw.execute('DROP TABLE workout_executions');
        raw.execute('DROP TABLE derived_target_graphs');
        raw.execute('PRAGMA user_version = 7');
      } finally {
        raw.close();
      }
      equal(
        (await NativeBackup.create(
          '$dir/db.sqlite',
          '$dir/v7-native',
        ))['databaseSchemaVersion'],
        7,
      );
      final upgraded = await TrainingStore.open('$dir/db.sqlite');
      try {
        jsonEqual(
          (await TimingService(upgraded).show(timer.id)).toJson(),
          timer.toJson(),
        );
        equal((await upgraded.executions()).length, 0);
        final timing = TimingService(upgraded);
        await timing.stop(
          timer.id,
          timer.version,
          instant(1),
          confirm: true,
          discard: true,
        );
        await timing.startRest(
          'new-rest',
          'session',
          'workout/recovery',
          instant(1),
        );
        await upgraded.backup('$dir/rest-native');
        final payload = <String, Object?>{
          'format': 'bodytmi-logical-export/7',
          'applicationVersion': '0.1.0',
          'data': (await upgraded.archive()).toJson()
            ..remove('families')
            ..remove('executions'),
        };
        payload['sha256'] = sha256
            .convert(utf8.encode(canonicalJson(payload)))
            .toString();
        await File('$dir/rest-forged.json').writeAsString(jsonEncode(payload));
        await _fails(LogicalArchiveFiles.prepare('$dir/rest-forged.json'));
        final forged = sqlite3.open('$dir/rest-native/database.sqlite');
        try {
          forged.execute('DROP TABLE family_revisions');
          forged.execute('DROP TABLE workout_executions');
          forged.execute('DROP TABLE derived_target_graphs');
          forged.execute('PRAGMA user_version = 7');
        } finally {
          forged.close();
        }
        rejects(
          () =>
              NativeBackup.validateDatabase('$dir/rest-native/database.sqlite'),
        );
      } finally {
        await upgraded.close();
      }
    }),
  );
  test(
    'native execution CLI runs a timed effort, explicitly reviews it, times authored rest and exposes the next manual effort',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-execution-cli-',
      );
      try {
        Future<Map<String, Object?>> command(
          String name,
          Map<String, Object?> input,
        ) async {
          final r = await invoke(
            name.split(' '),
            jsonEncode({
              'schemaVersion': 1,
              'database': '${dir.path}/db.sqlite',
              ...input,
            }),
          );
          equal(r.code, 0);
          equal(r.error, '');
          return jsonObject(
            jsonObject(jsonDecode(r.output), 'response')['data'],
            'data',
          );
        }

        await command('store publish', {
          'definition': _definition().toJson(),
          'expectedRevision': 0,
        });
        await command('store start', {
          'id': 'session',
          'templateId': 'traversal',
          'revision': 1,
          'startedAt': instant(1).toIso8601String(),
        });
        var view = await command('execution start', {
          'id': 'execution',
          'sessionId': 'session',
          'at': instant(1).toIso8601String(),
        });
        final run = await command('execution run', {
          'id': 'execution',
          'expectedVersion': 1,
          'expectedSessionVersion': 1,
          'requestId': 'hold-clock',
          'at': instant(1).toIso8601String(),
          'plan': {'preparationMilliseconds': 2, 'effortMilliseconds': 4},
        });
        equal(run['requiresReview'], true);
        view = jsonObject(run['execution'], 'execution');
        equal(view['cursor'], 0);
        equal(
          jsonObject(
            jsonObject(view['current'], 'current')['set'],
            'set',
          )['status'],
          'planned',
        );
        final timer = jsonObject(view['timer'], 'timer');
        view = await command('execution confirm', {
          'id': 'execution',
          'expectedVersion': 1,
          'expectedSessionVersion': 1,
          'requestId': 'confirm',
          'at': instant(1).toIso8601String(),
          'timerId': timer['id'],
          'timerVersion': timer['version'],
          'acceptSuggested': true,
        });
        equal(view['cursor'], 1);
        equal(jsonObject(view['timer'], 'timer')['phase'], 'rest');
        final edited = await command('store edit-target', {
          'id': 'session',
          'expectedVersion': view['sessionContentVersion'],
          'setId': 'workout/lift-set',
          'metric': 'mass',
          'value': {'value': '12', 'unit': 'kg'},
        });
        final restRequest = {
          'id': 'execution',
          'expectedVersion': view['version'],
          'expectedSessionVersion': edited['contentVersion'],
          'requestId': 'rest',
          'at': instant(1).toIso8601String(),
        };
        final rested = await command('execution run', restRequest);
        view = jsonObject(rested['execution'], 'execution');
        equal(view['cursor'], 2);
        equal(jsonObject(view['current'], 'current')['id'], 'workout/lift-set');
        view = await command('execution complete', {
          'id': 'execution',
          'expectedVersion': view['version'],
          'expectedSessionVersion': view['sessionContentVersion'],
          'requestId': 'lift',
          'at': instant(1).toIso8601String(),
          'acceptSuggested': true,
        });
        equal(view['status'], 'completed');
        final retry = await command('execution run', restRequest);
        equal(retry['alreadyApplied'], true);
        equal(jsonObject(retry['execution'], 'execution')['cursor'], 3);
        final session = await command('store show', {'id': 'session'});
        final lift = jsonObject(jsonList(session, 'sets').last, 'lift');
        equal(
          jsonObject(
            jsonObject(lift['actuals'], 'actuals')['mass'],
            'mass',
          )['value'],
          '12',
        );
        equal(
          jsonObject(
            jsonObject(jsonList(session, 'sets').first, 'set')['actuals'],
            'actuals',
          )['duration'].toString().contains('0.004'),
          true,
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'process death rolls back or commits effort results, traversal receipt and prepared rest clock together',
    () => _withStore((store, dir) async {
      await _start(store);
      await store.close();
      final binary = await compileNative(
        'test/helpers/store_owner.dart',
        '$dir/owner',
      );
      for (final mode in ['execution-step-rollback', 'execution-step-commit']) {
        final child = await Process.start(binary, ['$dir/db.sqlite', mode]);
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
        } finally {
          child.kill(ProcessSignal.sigkill);
          await child.exitCode;
        }
        final recovered = await TrainingStore.open('$dir/db.sqlite');
        try {
          final service = ExecutionService(recovered);
          final e = await service.show('execution');
          final committed = mode.endsWith('commit');
          equal(e.cursor, committed ? 1 : 0);
          equal(
            (await recovered.session('session'))!.sets.first.status,
            committed ? SetStatus.completed : SetStatus.planned,
          );
          equal((await recovered.timingActivities()).length, committed ? 1 : 0);
          if (committed) {
            await service.step(
              e.id,
              1,
              1,
              'crash-step',
              instant(1),
              action: 'complete',
              acceptSuggested: true,
            );
            equal((await service.show(e.id)).cursor, 1);
          }
          await recovered.archive();
        } finally {
          await recovered.close();
        }
      }
    }),
  );
}
