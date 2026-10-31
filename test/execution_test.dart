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

void executionTests() {
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
      equal((await store.backup('$dir/native'))['databaseSchemaVersion'], 8);
      equal(
        (await LogicalArchiveFiles.export(
          await store.archive(),
          '$dir/logical.json',
        ))['format'],
        'bodytmi-logical-export/8',
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
        'data': Map<String, Object?>.from(original)..remove('executions'),
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
        raw.execute('DROP TABLE workout_executions');
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
          'data': (await upgraded.archive()).toJson()..remove('executions'),
        };
        payload['sha256'] = sha256
            .convert(utf8.encode(canonicalJson(payload)))
            .toString();
        await File('$dir/rest-forged.json').writeAsString(jsonEncode(payload));
        await _fails(LogicalArchiveFiles.prepare('$dir/rest-forged.json'));
        final forged = sqlite3.open('$dir/rest-native/database.sqlite');
        try {
          forged.execute('DROP TABLE workout_executions');
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
        final restRequest = {
          'id': 'execution',
          'expectedVersion': view['version'],
          'expectedSessionVersion': view['sessionContentVersion'],
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
