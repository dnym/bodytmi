import 'dart:convert';
import 'dart:io';
import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:test/test.dart' show expectLater, throwsA, isA;
import 'cli_test.dart';
import 'fixtures.dart';
import 'support.dart';

Map<String, Object?> _tempo([int scale = 1]) => {
  'phases': [
    {'id': 'lower', 'milliseconds': 3000 * scale},
    {'id': 'hold', 'milliseconds': 1000 * scale},
    {'id': 'raise', 'milliseconds': 2000 * scale},
  ],
};
TimingPlan _plan({
  int prep = 1000,
  int effort = 12000,
  int rest = 1000,
  String overrun = 'stop',
}) => TimingPlan.fromJson({
  'preparationMilliseconds': prep,
  'effortMilliseconds': effort,
  'restMilliseconds': rest,
  'overrun': overrun,
  'nearEndMilliseconds': 1000,
  'tempo': _tempo(),
});
TimingActivity _clock({TimingPlan? plan}) => TimingActivity.create(
  id: 'clock',
  sessionId: 'session',
  setId: 'effort',
  metric: 'duration',
  plan: plan ?? _plan(),
  at: instant(1),
);
WorkoutDefinition _definition() => WorkoutDefinition.fromJson({
  'id': 'tempo',
  'name': 'Tempo practice',
  'slots': [
    {
      'id': 'movement',
      'exercise': 'custom',
      'implementation': 'custom',
      'targets': {
        'duration': {'value': '12', 'unit': 's'},
        'reps': {'value': '5', 'unit': 'rep'},
      },
    },
  ],
  'plan': {'id': 'effort', 'type': 'effort', 'slot': 'movement'},
});
Future<void> _withStore(
  Future<void> Function(TrainingStore, String) action,
) async {
  final dir = await Directory.systemTemp.createTemp('bodytmi-tempo-');
  final store = await TrainingStore.open('${dir.path}/db.sqlite');
  try {
    await StoredTrainingService(store).publish(_definition(), 0);
    await StoredTrainingService(store).start('session', 'tempo', 1, instant(1));
    await action(store, dir.path);
  } finally {
    await store.close();
    await dir.delete(recursive: true);
  }
}

Future<void> _fails(Future<Object?> action) =>
    expectLater(action, throwsA(isA<BodyTmiException>()));

void tempoTests() {
  test(
    'older backups reject manual termination hidden only in frozen progression inputs',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-open-frozen-');
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final training = StoredTrainingService(store);
        await training.publish(
          WorkoutDefinition.fromJson({
            'id': 'frozen',
            'name': 'Frozen',
            'slots': [
              {
                'id': 'lift',
                'exercise': 'squat',
                'implementation': 'bodyweight',
                'targets': {
                  'reps': {'value': '5', 'unit': 'rep'},
                },
              },
            ],
            'plan': {'id': 'set', 'type': 'effort', 'slot': 'lift'},
          }),
          0,
        );
        var session = await training.start('session', 'frozen', 1, instant(1));
        final timers = TimingService(store);
        var clock = await timers.start(
          'clock',
          session.id,
          'set',
          'duration',
          TimingPlan.fromJson({'unplannedDuration': true, 'openEnded': true}),
          instant(1),
        );
        clock = await timers.resume(
          clock.id,
          clock.version,
          'owner',
          instant(1),
        );
        clock = (await timers.advance(
          clock.id,
          clock.version,
          'owner',
          100,
          instant(1),
          action: 'pause',
        )).activity;
        clock = await timers.endEffort(clock.id, clock.version, instant(1));
        await timers.confirm(
          clock.id,
          clock.version,
          session.contentVersion,
          instant(1),
          {'reps': Quantity('9', 'rep')},
        );
        session = await training.session(session.id);
        session = await training.edit(
          session.id,
          session.contentVersion,
          (s) => s.finish(instant(1)),
        );
        final rule = {
          'metric': 'reps',
          'minimum': {'value': '5', 'unit': 'rep'},
          'threshold': {'value': '5', 'unit': 'rep'},
          'increments': {
            'reps': {'value': '1', 'unit': 'rep'},
          },
        };
        await StoredProgressionService(
          store,
        ).propose(session.id, 'lift', rule, ruleType: 'threshold');
        await training.edit(
          session.id,
          session.contentVersion,
          (s) => const TrainingService().skip(s, 'set', confirm: true),
        );
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'open-ended timers never infer a target and keep the timing resource bound',
    () {
      final plan = TimingPlan.fromJson({
        'openEnded': true,
        'unplannedDuration': true,
        'tempo': _tempo(),
      });
      var empty = _clock(plan: plan);
      empty = empty.stop(instant(1));
      equal(empty.termination, 'no-effort');
      equal(empty.status, 'awaitingConfirmation');
      rejects(() => empty.confirmed(<String, Object?>{}, instant(1)));
      var running = _clock(plan: plan).resume('owner', instant(1));
      final step = running.advance(604800000, 'owner', instant(1));
      running = step.activity;
      equal(running.status, 'running');
      equal(running.effortElapsedMilliseconds, 604800000);
      check(
        step.cues.every(
          (cue) => cue['kind'] != 'target' && cue['kind'] != 'near-end',
        ),
      );
      rejects(() => running.advance(604800001, 'owner', instant(1)));
      running = running.pause(instant(1)).endEffort(instant(1));
      equal(running.termination, 'manual');
      equal(running.status, 'awaitingConfirmation');
    },
  );
  test(
    'open-ended rep clocks require manual effort end and preserve recovery and portability',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-open-tempo-');
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final training = StoredTrainingService(store);
        await training.publish(
          WorkoutDefinition.fromJson({
            'id': 'open-reps',
            'name': 'Repetitions',
            'slots': [
              {
                'id': 'lift',
                'exercise': 'squat',
                'implementation': 'bodyweight',
                'targets': {
                  'reps': {'value': '5', 'unit': 'rep'},
                },
              },
            ],
            'plan': {'id': 'set', 'type': 'effort', 'slot': 'lift'},
          }),
          0,
        );
        var session = await training.start(
          'session',
          'open-reps',
          1,
          instant(1),
        );
        final plan = TimingPlan.fromJson({
          'openEnded': true,
          'unplannedDuration': true,
          'preparationMilliseconds': 1000,
          'tempo': _tempo(),
        });
        check(plan.openEnded);
        check(!plan.toJson().containsKey('effortMilliseconds'));
        check(!plan.toJson().containsKey('overrun'));
        jsonEqual(TimingPlan.fromJson(plan.toJson()).toJson(), plan.toJson());
        for (final bad in [
          {'openEnded': true},
          {'openEnded': false, 'effortMilliseconds': 100},
          {
            'openEnded': true,
            'unplannedDuration': true,
            'effortMilliseconds': 100,
          },
          {'openEnded': true, 'unplannedDuration': true, 'overrun': 'continue'},
          {
            'openEnded': true,
            'unplannedDuration': true,
            'nearEndMilliseconds': 10,
          },
        ]) {
          rejects(() => TimingPlan.fromJson(bad));
        }
        final timers = TimingService(store);
        var clock = await timers.start(
          'clock',
          session.id,
          session.sets.single.id,
          'duration',
          plan,
          instant(1),
        );
        clock = await timers.resume(
          clock.id,
          clock.version,
          'owner',
          instant(1),
        );
        var sample = await timers.advance(
          clock.id,
          clock.version,
          'owner',
          16000,
          instant(1),
        );
        clock = sample.activity;
        equal(clock.status, 'running');
        equal(clock.effortElapsedMilliseconds, 15000);
        check(
          sample.cues.every(
            (cue) => cue['kind'] != 'target' && cue['kind'] != 'near-end',
          ),
        );
        clock = await timers.recover(clock.id, clock.version, instant(1));
        equal(clock.status, 'paused');
        equal(clock.effortElapsedMilliseconds, 15000);
        clock = await timers.resume(
          clock.id,
          clock.version,
          'next-owner',
          instant(1),
        );
        clock = (await timers.advance(
          clock.id,
          clock.version,
          'next-owner',
          2000,
          instant(1),
          action: 'pause',
        )).activity;
        clock = await timers.endEffort(clock.id, clock.version, instant(1));
        equal(clock.status, 'awaitingConfirmation');
        equal(clock.termination, 'manual');
        equal(
          (await training.session(session.id)).sets.single.status,
          SetStatus.planned,
        );
        await _fails(
          timers.confirm(
            clock.id,
            clock.version,
            session.contentVersion,
            instant(1),
            {},
          ),
        );
        clock = await timers.confirm(
          clock.id,
          clock.version,
          session.contentVersion,
          instant(1),
          {'reps': Quantity('9', 'rep')},
        );
        session = await training.session(session.id);
        equal(session.sets.single.actuals['duration']!.value.toString(), '17');
        equal(session.sets.single.actuals['reps']!.value.toString(), '9');
        equal(session.sets.single.timing!.termination, 'manual');
        final managedSession = await training.start(
          'managed',
          'open-reps',
          1,
          instant(2),
        );
        final executions = ExecutionService(store);
        var execution = await executions.start(
          'execution',
          managedSession.id,
          instant(2),
        );
        var managed = await executions.time(
          execution.id,
          execution.version,
          instant(2),
          metric: 'duration',
          plan: plan,
        );
        managed = await timers.resume(
          managed.id,
          managed.version,
          'managed-owner',
          instant(2),
        );
        managed = (await timers.advance(
          managed.id,
          managed.version,
          'managed-owner',
          4000,
          instant(2),
          action: 'pause',
        )).activity;
        managed = await timers.endEffort(
          managed.id,
          managed.version,
          instant(2),
        );
        execution = await executions.step(
          execution.id,
          execution.version,
          managedSession.contentVersion,
          'review',
          instant(2),
          action: 'confirm',
          timerId: managed.id,
          timerVersion: managed.version,
          actuals: {'reps': Quantity('6', 'rep')},
        );
        check(execution.complete);
        equal(
          (await training.session(
            managedSession.id,
          )).sets.single.timing!.termination,
          'manual',
        );
        final interruptedSession = await training.start(
          'interrupted',
          'open-reps',
          1,
          instant(3),
        );
        var interrupted = await timers.start(
          'interrupted-clock',
          interruptedSession.id,
          interruptedSession.sets.single.id,
          'duration',
          plan,
          instant(3),
        );
        interrupted = await timers.resume(
          interrupted.id,
          interrupted.version,
          'lost-owner',
          instant(3),
        );
        interrupted = (await timers.advance(
          interrupted.id,
          interrupted.version,
          'lost-owner',
          4500,
          instant(3),
        )).activity;
        equal(interrupted.effortElapsedMilliseconds, 3500);
        final archive = canonicalJson((await store.archive()).toJson());
        await store.backup('${dir.path}/native');
        final file = '${dir.path}/logical.json';
        await LogicalArchiveFiles.export(await store.archive(), file);
        final prepared = await LogicalArchiveFiles.prepare(file);
        final destination = await TrainingStore.open(
          '${dir.path}/restored.sqlite',
        );
        try {
          await destination.restore(
            prepared.backup,
            recoveryDestination: '${dir.path}/recovery',
            confirm: true,
          );
        } finally {
          await destination.close();
          await prepared.close();
        }
        final reopened = await TrainingStore.open(
          '${dir.path}/restored.sqlite',
        );
        try {
          equal(canonicalJson((await reopened.archive()).toJson()), archive);
          final native = await NativeBackup.prepare('${dir.path}/native');
          try {
            await reopened.restore(
              native,
              recoveryDestination: '${dir.path}/native-recovery',
              confirm: true,
            );
          } finally {
            await native.close();
          }
        } finally {
          await reopened.close();
        }
        final nativeRestored = await TrainingStore.open(
          '${dir.path}/restored.sqlite',
        );
        try {
          equal(
            canonicalJson((await nativeRestored.archive()).toJson()),
            archive,
          );
          final restoredTimer = await TimingService(
            nativeRestored,
          ).show('interrupted-clock');
          equal(restoredTimer.status, 'running');
          final frozen = await TimingService(
            nativeRestored,
          ).recover(restoredTimer.id, restoredTimer.version, instant(4));
          equal(frozen.status, 'paused');
          equal(frozen.effortElapsedMilliseconds, 3500);
          equal(
            (await StoredTrainingService(
              nativeRestored,
            ).session('interrupted')).sets.single.status,
            SetStatus.planned,
          );
        } finally {
          await nativeRestored.close();
        }
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'native CLI times a repetition-only set with an explicit additional duration',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-rep-timer-cli-',
      );
      final database = '${dir.path}/db.sqlite';
      try {
        Future<Map<String, Object?>> call(
          String command,
          Map<String, Object?> data,
        ) async {
          final result = await invoke(
            command.split(' '),
            jsonEncode({'schemaVersion': 1, 'database': database, ...data}),
          );
          equal(result.code, 0);
          equal(result.error, '');
          return jsonObject(
            jsonObject(jsonDecode(result.output), 'response')['data'],
            'data',
          );
        }

        await call('store publish', {
          'definition': {
            'id': 'reps-only',
            'name': 'Rep practice',
            'slots': [
              {
                'id': 'lift',
                'exercise': 'squat',
                'implementation': 'bodyweight',
                'targets': {
                  'reps': {'value': '5', 'unit': 'rep'},
                },
              },
            ],
            'plan': {'id': 'set', 'type': 'effort', 'slot': 'lift'},
          },
          'expectedRevision': 0,
        });
        final session = await call('store start', {
          'id': 'session',
          'templateId': 'reps-only',
          'revision': 1,
          'startedAt': instant(1).toIso8601String(),
        });
        final clock = await call('timer start', {
          'id': 'clock',
          'sessionId': 'session',
          'setId': 'set',
          'metric': 'duration',
          'plan': {
            'unplannedDuration': true,
            'effortMilliseconds': 100,
            'tempo': {
              'phases': [
                {'id': 'lower', 'milliseconds': 25},
                {'id': 'raise', 'milliseconds': 25},
              ],
            },
          },
          'at': instant(1).toIso8601String(),
        });
        final run = await call('timer run', {
          'id': 'clock',
          'expectedVersion': clock['version'],
        });
        final ended = jsonObject(run['timer'], 'timer');
        equal(ended['status'], 'awaitingConfirmation');
        final before = await call('store show', {'id': 'session'});
        equal(
          jsonObject(jsonList(before, 'sets').single, 'set')['status'],
          'planned',
        );
        await call('timer confirm', {
          'id': 'clock',
          'expectedVersion': ended['version'],
          'expectedSessionVersion': session['contentVersion'],
          'at': instant(1).toIso8601String(),
          'actuals': {
            'reps': {'value': '7', 'unit': 'rep'},
          },
        });
        final after = await call('store show', {'id': 'session'});
        final actuals = jsonObject(
          jsonObject(jsonList(after, 'sets').single, 'set')['actuals'],
          'actuals',
        );
        equal(jsonObject(actuals['reps'], 'reps')['value'], '7');
        equal(jsonObject(actuals['duration'], 'duration')['value'], '0.1');
        final nextSession = await call('store start', {
          'id': 'open-session',
          'templateId': 'reps-only',
          'revision': 1,
          'startedAt': instant(2).toIso8601String(),
        });
        final openClock = await call('timer start', {
          'id': 'open-clock',
          'sessionId': 'open-session',
          'setId': 'set',
          'metric': 'duration',
          'plan': {
            'unplannedDuration': true,
            'openEnded': true,
            'tempo': {
              'phases': [
                {'id': 'lower', 'milliseconds': 25},
                {'id': 'raise', 'milliseconds': 25},
              ],
            },
          },
          'at': instant(2).toIso8601String(),
        });
        final openRun = await call('timer run', {
          'id': 'open-clock',
          'expectedVersion': openClock['version'],
          'runForMilliseconds': 150,
        });
        final paused = jsonObject(openRun['timer'], 'timer');
        equal(paused['status'], 'paused');
        check((paused['effortElapsedMilliseconds']! as int) > 0);
        check(
          jsonList(
            openRun,
            'cues',
          ).every((cue) => jsonObject(cue, 'cue')['kind'] != 'target'),
        );
        final endedOpen = await call('timer end-effort', {
          'id': 'open-clock',
          'expectedVersion': paused['version'],
          'at': instant(2).toIso8601String(),
        });
        equal(endedOpen['termination'], 'manual');
        await call('timer confirm', {
          'id': 'open-clock',
          'expectedVersion': endedOpen['version'],
          'expectedSessionVersion': nextSession['contentVersion'],
          'at': instant(2).toIso8601String(),
          'actuals': {
            'reps': {'value': '8', 'unit': 'rep'},
          },
        });
        final openResult = await call('store show', {'id': 'open-session'});
        final openActuals = jsonObject(
          jsonObject(jsonList(openResult, 'sets').single, 'set')['actuals'],
          'actuals',
        );
        equal(jsonObject(openActuals['reps'], 'reps')['value'], '8');
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'explicit unplanned duration clocks time repetition sets and preserve confirmation across backups',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-rep-tempo-');
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final definition = WorkoutDefinition.fromJson({
          'id': 'reps-only',
          'name': 'Repetitions',
          'slots': [
            {
              'id': 'lift',
              'exercise': 'squat',
              'implementation': 'bodyweight',
              'targets': {
                'reps': {'value': '5', 'unit': 'rep'},
              },
            },
          ],
          'plan': {'id': 'set', 'type': 'effort', 'slot': 'lift'},
        });
        final training = StoredTrainingService(store);
        await training.publish(definition, 0);
        var session = await training.start(
          'rep-session',
          'reps-only',
          1,
          instant(1),
        );
        final plan = TimingPlan.fromJson({
          'unplannedDuration': true,
          'preparationMilliseconds': 1000,
          'effortMilliseconds': 3000,
          'tempo': _tempo(),
        });
        rejects(
          () => TimingPlan.fromJson({
            'effortMilliseconds': 3000,
            'unplannedDuration': false,
          }),
        );
        rejects(
          () => TimingPlan.fromJson({
            'restOnly': true,
            'effortMilliseconds': 0,
            'restMilliseconds': 1000,
            'unplannedDuration': true,
          }),
        );
        final timers = TimingService(store);
        await _fails(
          timers.start(
            'bad',
            session.id,
            session.sets.single.id,
            'reps',
            plan,
            instant(1),
          ),
        );
        await _fails(
          timers.start(
            'missing',
            session.id,
            session.sets.single.id,
            'duration',
            null,
            instant(1),
          ),
        );
        var clock = await timers.start(
          'rep-clock',
          session.id,
          session.sets.single.id,
          'duration',
          plan,
          instant(1),
        );
        equal(clock.plan.unplannedDuration, true);
        clock = await timers.resume(
          clock.id,
          clock.version,
          'owner',
          instant(1),
        );
        await _fails(
          timers.start(
            'competing',
            session.id,
            session.sets.single.id,
            'duration',
            plan,
            instant(1),
          ),
        );
        clock = (await timers.advance(
          clock.id,
          clock.version,
          'owner',
          2000,
          instant(1),
        )).activity;
        equal(clock.effortElapsedMilliseconds, 1000);
        clock = await timers.recover(clock.id, clock.version, instant(1));
        equal(clock.status, 'paused');
        equal(clock.effortElapsedMilliseconds, 1000);
        clock = await timers.resume(
          clock.id,
          clock.version,
          'owner-next',
          instant(1),
        );
        clock = (await timers.advance(
          clock.id,
          clock.version,
          'owner-next',
          2000,
          instant(1),
        )).activity;
        equal(clock.status, 'awaitingConfirmation');
        equal(
          (await training.session(session.id)).sets.single.status,
          SetStatus.planned,
        );
        await _fails(
          timers.confirm(
            clock.id,
            clock.version,
            session.contentVersion,
            instant(1),
            {},
          ),
        );
        clock = await timers.confirm(
          clock.id,
          clock.version,
          session.contentVersion,
          instant(1),
          {'reps': Quantity('7', 'rep')},
        );
        session = await training.session(session.id);
        equal(session.sets.single.actuals['reps']!.value.toString(), '7');
        equal(session.sets.single.actuals['duration']!.value.toString(), '3');
        equal(session.sets.single.timing!.elapsedMilliseconds, 3000);
        check(!session.sets.single.suggested.containsKey('duration'));
        equal(
          (await timers.confirm(
            clock.id,
            clock.version - 1,
            session.contentVersion - 1,
            instant(1),
            {'reps': Quantity('7', 'rep')},
          )).status,
          'confirmed',
        );
        final managedSession = await training.start(
          'managed-reps',
          'reps-only',
          1,
          instant(2),
        );
        final executions = ExecutionService(store);
        var execution = await executions.start(
          'rep-execution',
          managedSession.id,
          instant(2),
        );
        var managedClock = await executions.time(
          execution.id,
          execution.version,
          instant(2),
          metric: 'elapsed',
          plan: plan,
        );
        managedClock = await timers.resume(
          managedClock.id,
          managedClock.version,
          'managed-owner',
          instant(2),
        );
        managedClock = (await timers.advance(
          managedClock.id,
          managedClock.version,
          'managed-owner',
          4000,
          instant(2),
        )).activity;
        equal(managedClock.status, 'awaitingConfirmation');
        execution = await executions.step(
          execution.id,
          execution.version,
          managedSession.contentVersion,
          'review',
          instant(2),
          action: 'confirm',
          timerId: managedClock.id,
          timerVersion: managedClock.version,
          actuals: {'reps': Quantity('6', 'rep')},
        );
        check(execution.complete);
        final managedResult = (await training.session(
          managedSession.id,
        )).sets.single;
        equal(managedResult.actuals['reps']!.value.toString(), '6');
        equal(managedResult.actuals['elapsed']!.value.toString(), '3');
        final archive = canonicalJson((await store.archive()).toJson());
        await store.backup('${dir.path}/native');
        final file = '${dir.path}/logical.json';
        await LogicalArchiveFiles.export(await store.archive(), file);
        final prepared = await LogicalArchiveFiles.prepare(file);
        final destination = await TrainingStore.open(
          '${dir.path}/restored.sqlite',
        );
        try {
          await destination.restore(
            prepared.backup,
            recoveryDestination: '${dir.path}/recovery',
            confirm: true,
          );
        } finally {
          await destination.close();
          await prepared.close();
        }
        final reopened = await TrainingStore.open(
          '${dir.path}/restored.sqlite',
        );
        try {
          equal(canonicalJson((await reopened.archive()).toJson()), archive);
          final native = await NativeBackup.prepare('${dir.path}/native');
          try {
            await reopened.restore(
              native,
              recoveryDestination: '${dir.path}/native-recovery',
              confirm: true,
            );
          } finally {
            await native.close();
          }
        } finally {
          await reopened.close();
        }
        final nativeRestored = await TrainingStore.open(
          '${dir.path}/restored.sqlite',
        );
        try {
          equal(
            canonicalJson((await nativeRestored.archive()).toJson()),
            archive,
          );
        } finally {
          await nativeRestored.close();
        }
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'tempo samples expose current cues without inferring repetitions or a duration target',
    () async {
      final plan = TempoPlan.fromJson(_tempo());
      equal(plan.cueAt(0, 0, includeInitial: true), null);
      equal(plan.cueAt(0, 1000), null);
      equal(plan.cueAt(0, 1000, includeInitial: true)!.phaseId, 'lower');
      equal(plan.cueAt(1000, 3000)!.phaseId, 'hold');
      equal(plan.cueAt(3000, 11500)!.phaseId, 'raise');
      equal(plan.cueAt(11500, 11500), null);
      rejects(() => plan.cueAt(2000, 1000));
      rejects(() => plan.cueAt(-1, 0));
      rejects(() => plan.cueAt(0, 604800001));
      final request = {
        'schemaVersion': 1,
        'tempo': _tempo(),
        'previousElapsedMilliseconds': 1000,
        'elapsedMilliseconds': 3500,
        'includeInitial': false,
      };
      final response = const Commands().execute('tempo sample', request);
      final data = jsonObject(response['data'], 'sample');
      equal(jsonObject(data['position'], 'position')['phaseId'], 'hold');
      equal(jsonObject(data['cue'], 'cue')['boundaryEffortMilliseconds'], 3000);
      check(!data.containsKey('reps') && !data.containsKey('actuals'));
      final cli = await invoke(['tempo', 'sample'], jsonEncode(request));
      equal(cli.code, 0);
      equal(
        canonicalJson(jsonObject(jsonDecode(cli.output), 'response')),
        canonicalJson(response),
      );
      var clock = _clock(plan: _plan(prep: 0, rest: 0));
      clock = clock.resume('owner', instant(1));
      clock = clock.advance(1000, 'owner', instant(1)).activity;
      final step = clock.advance(3500, 'owner', instant(1));
      equal(step.cues.single['kind'], 'tempo');
      equal(
        canonicalJson(step.cues.single['tempo']),
        canonicalJson(data['cue']),
      );
    },
  );
  test(
    'tempo boundaries use effort only and repeat unequal phases without certifying reps',
    () {
      var t = _clock().resume('epoch', instant(1));
      equal(t.tempoState, null);
      var step = t.advance(1000, 'epoch', instant(1));
      t = step.activity;
      equal(step.cues.single['kind'], 'phase');
      equal(t.tempoState!.phaseId, 'lower');
      equal(t.tempoState!.cycleIndex, 0);
      step = t.advance(1001, 'epoch', instant(1));
      t = step.activity;
      equal(
        step.cues.length,
        0,
      ); // Entry was disclosed by the preparation boundary.
      step = t.advance(4000, 'epoch', instant(1));
      t = step.activity;
      equal(step.cues.single['kind'], 'tempo');
      equal(step.cues.single['elapsedMilliseconds'], 4000);
      equal(t.tempoState!.phaseId, 'hold');
      equal(t.tempoState!.phaseElapsedMilliseconds, 0);
      t = t.advance(5500, 'epoch', instant(1)).activity;
      equal(t.tempoState!.phaseId, 'raise');
      equal(t.tempoState!.phaseElapsedMilliseconds, 500);
      equal(t.tempoState!.phaseRemainingMilliseconds, 1500);
      t = t.advance(7000, 'epoch', instant(1)).activity;
      equal(t.tempoState!.phaseId, 'lower');
      equal(t.tempoState!.cycleIndex, 1);
      t = t.advance(13000, 'epoch', instant(1)).activity;
      equal(t.phase, 'rest');
      equal(t.tempoState, null);
      t = t.advance(14000, 'epoch', instant(1)).activity;
      equal(t.status, 'awaitingConfirmation');
      equal(t.confirmation, null);
      equal(t.effortElapsedMilliseconds, 12000);
      equal(t.toViewJson()['tempoState'], null);
      check(!t.toJson().containsKey('tempoState'));
      jsonEqual(TimingActivity.fromJson(t.toJson()).toJson(), t.toJson());
    },
  );
  test(
    'tempo configuration is bounded, immutable and rejects ambiguous or nonpositive phases',
    () {
      final bad = <Object?>[
        null,
        {'phases': <Object?>[]},
        {
          'phases': [
            {'id': 'x', 'milliseconds': 0},
          ],
        },
        {
          'phases': [
            {'id': 'x', 'milliseconds': 1.5},
          ],
        },
        {
          'phases': [
            {'id': 'x', 'milliseconds': 1},
            {'id': 'x', 'milliseconds': 1},
          ],
        },
        {
          'phases': [
            {'id': 'x', 'milliseconds': 86400000},
            {'id': 'y', 'milliseconds': 1},
          ],
        },
        {
          'phases': List.generate(17, (i) => {'id': 'p$i', 'milliseconds': 1}),
        },
        {
          'phases': [
            {'id': 'x', 'milliseconds': 1, 'guessedReps': 1},
          ],
        },
        {..._tempo(), 'autoComplete': true},
      ];
      for (final value in bad) rejects(() => TempoPlan.fromJson(value));
      rejects(
        () => TimingPlan.fromJson({
          'restOnly': true,
          'effortMilliseconds': 0,
          'restMilliseconds': 1000,
          'tempo': _tempo(),
        }),
      );
      final input = _tempo();
      final tempo = TempoPlan.fromJson(input);
      jsonObject(jsonList(input, 'phases').first, 'phase')['milliseconds'] = 99;
      equal(tempo.phases.first.milliseconds, 3000);
      equal(tempo.position(6000).cycleIndex, 1);
      rejects(() => tempo.position(-1));
      final old = TimingPlan.fromJson({'effortMilliseconds': 1000});
      check(!old.toJson().containsKey('tempo'));
      check(!_clock(plan: old).toViewJson().containsKey('tempoState'));
    },
  );
  test(
    'delayed tempo checkpoints have bounded delivery and arbitrate phase, target and near-end collisions',
    () {
      var t = _clock(
        plan: _plan(prep: 0, effort: 10000, rest: 0),
      ).resume('epoch', instant(1));
      var step = t.advance(1, 'epoch', instant(1));
      t = step.activity;
      equal(step.cues.single['kind'], 'tempo');
      step = t.advance(9000, 'epoch', instant(1));
      t = step.activity;
      equal(
        step.cues.single['kind'],
        'near-end',
      ); // Tempo hold starts at 9000 too.
      equal(t.tempoState!.phaseId, 'hold');
      step = t.advance(10000, 'epoch', instant(1));
      equal(step.cues.single['kind'], 'phase');
      equal(step.activity.tempoState, null);
      t = _clock(
        plan: _plan(prep: 0, effort: 12000, rest: 0, overrun: 'continue'),
      ).resume('epoch', instant(1));
      step = t.advance(12000, 'epoch', instant(1));
      t = step.activity;
      equal(step.cues.single['kind'], 'target');
      equal(t.tempoState!.cycleIndex, 2);
      step = t.advance(15000, 'epoch', instant(1));
      equal(step.cues.single['kind'], 'tempo');
      equal(step.activity.tempoState!.phaseId, 'hold');
      final fast = TimingPlan.fromJson({
        'effortMilliseconds': 86400000,
        'tempo': {
          'phases': [
            {'id': 'beat', 'milliseconds': 1},
          ],
        },
      });
      t = _clock(plan: fast).resume('epoch', instant(1));
      step = t.advance(80000000, 'epoch', instant(1));
      equal(step.cues.length, 1);
      equal(step.activity.tempoState!.cycleIndex, 80000000);
      equal(step.cues.single['elapsedMilliseconds'], 80000000);
      equal(
        step.activity.advance(80000000, 'epoch', instant(1)).cues.length,
        0,
      );
    },
  );
  test(
    'tempo pause and recovery retain phase and do not replay missed beats or infer wall-time cycles',
    () {
      var t = _clock()
          .resume('epoch', instant(1))
          .advance(4500, 'epoch', instant(1))
          .activity;
      equal(t.tempoState!.phaseId, 'hold');
      final state = canonicalJson(t.tempoState!.toJson());
      t = TimingActivity.fromJson(t.toJson()).recover(instant(9));
      equal(canonicalJson(t.tempoState!.toJson()), state);
      t = t.resume('new', instant(9));
      var step = t.advance(100, 'new', instant(1));
      t = step.activity;
      equal(step.cues.length, 0);
      equal(t.tempoState!.phaseElapsedMilliseconds, 600);
      t = t.recover(instant(9), adjustmentMilliseconds: 10000);
      equal(t.status, 'awaitingConfirmation');
      equal(t.tempoState, null);
      equal(t.confirmation, null);
    },
  );
  test(
    'stored tempo pause suppresses cue delivery, explicit result review needs actuals and retries preserve corrections',
    () => _withStore((store, dir) async {
      final timing = TimingService(store);
      var t = await timing.start(
        'clock',
        'session',
        'effort',
        'duration',
        _plan(),
        instant(1),
      );
      t = await timing.resume(t.id, t.version, 'epoch', instant(1));
      var step = await timing.advance(
        t.id,
        t.version,
        'epoch',
        4000,
        instant(1),
        action: 'pause',
      );
      t = step.activity;
      equal(step.cues.length, 0);
      equal(t.tempoState!.phaseId, 'hold');
      t = await timing.resume(t.id, t.version, 'new', instant(1));
      step = await timing.advance(t.id, t.version, 'new', 10000, instant(1));
      t = step.activity;
      equal(t.status, 'awaitingConfirmation');
      equal(
        (await store.session('session'))!.sets.single.status,
        SetStatus.planned,
      );
      await _fails(timing.confirm(t.id, t.version, 1, instant(1), {}));
      t = await timing.confirm(t.id, t.version, 1, instant(1), {
        'reps': Quantity('3', 'rep'),
      });
      var s = (await store.session('session'))!;
      equal(
        s.sets.single.actuals['reps']!.value.toString(),
        '3',
      ); // Not two tempo cycles.
      equal(s.sets.single.actuals['duration']!.value.toString(), '12');
      final training = StoredTrainingService(store);
      s = await training.edit(
        s.id,
        s.contentVersion,
        (s) => const TrainingService().complete(s, 'effort', {
          'reps': Quantity('4', 'rep'),
          'duration': Quantity('11', 's'),
        }),
      );
      await timing.confirm(t.id, t.version - 1, 1, instant(1), {
        'reps': Quantity('3', 'rep'),
      });
      equal(
        (await store.session(
          'session',
        ))!.sets.single.actuals['reps']!.value.toString(),
        '4',
      );
      await store.archive();
    }),
  );
  test(
    'execution views expose tempo state while confirmation and skipping remain explicit',
    () => _withStore((store, dir) async {
      final execution = ExecutionService(store), timing = TimingService(store);
      var e = await execution.start('execution', 'session', instant(1));
      var t = await execution.time(
        e.id,
        e.version,
        instant(1),
        plan: _plan(rest: 0),
      );
      t = await timing.resume(t.id, t.version, 'epoch', instant(1));
      t = (await timing.advance(
        t.id,
        t.version,
        'epoch',
        4000,
        instant(1),
      )).activity;
      var v = await execution.view(e.id);
      equal(
        jsonObject(
          jsonObject(v['timer'], 'timer')['tempoState'],
          'tempo',
        )['phaseId'],
        'hold',
      );
      equal(v['cursor'], 0);
      e = await execution.step(
        e.id,
        e.version,
        1,
        'omit',
        instant(1),
        action: 'skip',
        confirm: true,
      );
      equal(e.complete, true);
      equal((await timing.show(t.id)).tempoState, null);
      equal(
        (await store.session('session'))!.sets.single.status,
        SetStatus.skipped,
      );
      v = await execution.view(e.id);
      equal(v['timer'], null);
      await store.archive();
    }),
  );
  test(
    'tempo native and logical restoration retain interrupted phase while v9 labels reject new timing plans',
    () => _withStore((store, dir) async {
      final timing = TimingService(store);
      var t = await timing.start(
        'clock',
        'session',
        'effort',
        'duration',
        _plan(),
        instant(1),
      );
      t = await timing.resume(t.id, t.version, 'epoch', instant(1));
      await timing.advance(t.id, t.version, 'epoch', 4500, instant(1));
      final expected = canonicalJson((await store.archive()).toJson());
      equal((await store.backup('$dir/native'))['databaseSchemaVersion'], 1);
      equal(
        (await LogicalArchiveFiles.export(
          await store.archive(),
          '$dir/logical.json',
        ))['format'],
        'bodytmi-logical-export/1',
      );
      final logical = await LogicalArchiveFiles.prepare('$dir/logical.json');
      try {
        equal(canonicalJson(logical.archive.toJson()), expected);
        await store.restore(
          logical.backup,
          recoveryDestination: '$dir/recovery',
          confirm: true,
        );
      } finally {
        await logical.close();
        await store.close();
      }
      var active = await TrainingStore.open('$dir/db.sqlite');
      try {
        equal(canonicalJson((await active.archive()).toJson()), expected);
        final native = await NativeBackup.prepare('$dir/native');
        try {
          await active.restore(
            native,
            recoveryDestination: '$dir/recovery2',
            confirm: true,
          );
        } finally {
          await native.close();
          await active.close();
        }
        active = await TrainingStore.open('$dir/db.sqlite');
        equal(canonicalJson((await active.archive()).toJson()), expected);
        final recovered = await TimingService(active).recover(
          'clock',
          (await TimingService(active).show('clock')).version,
          instant(9),
        );
        equal(recovered.tempoState!.phaseId, 'hold');
        equal(recovered.tempoState!.phaseElapsedMilliseconds, 500);
        equal(
          (await active.session('session'))!.sets.single.status,
          SetStatus.planned,
        );
      } finally {
        await active.close();
      }
    }),
  );
  test(
    'native foreground tempo streams guidance and retains results for explicit confirmation',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-tempo-cli-');
      try {
        Future<Map<String, Object?>> cmd(
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

        await cmd('store publish', {
          'definition': _definition().toJson(),
          'expectedRevision': 0,
        });
        await cmd('store start', {
          'id': 'session',
          'templateId': 'tempo',
          'revision': 1,
          'startedAt': instant(1).toIso8601String(),
        });
        var t = await cmd('timer start', {
          'id': 'clock',
          'sessionId': 'session',
          'setId': 'effort',
          'metric': 'duration',
          'plan': {
            'effortMilliseconds': 1000,
            'nearEndMilliseconds': 100,
            'tempo': {
              'phases': [
                {'id': 'lower', 'milliseconds': 100},
                {'id': 'raise', 'milliseconds': 100},
              ],
            },
          },
          'at': instant(1).toIso8601String(),
        });
        equal(jsonObject(t['tempoState'], 'tempo')['phaseId'], 'lower');
        final r = await invoke(
          ['timer', 'run'],
          jsonEncode({
            'schemaVersion': 1,
            'database': '${dir.path}/db.sqlite',
            'id': 'clock',
            'expectedVersion': 1,
            'stream': true,
          }),
        );
        equal(r.code, 0);
        equal(r.error, '');
        final rows = r.output
            .trim()
            .split('\n')
            .map(
              (line) => jsonObject(
                jsonObject(jsonDecode(line), 'row')['data'],
                'data',
              ),
            )
            .toList();
        check(
          rows
              .where((r) => r['type'] == 'timing-cue' && r['kind'] == 'tempo')
              .isNotEmpty,
        );
        equal(
          jsonObject(rows.last['timer'], 'timer')['status'],
          'awaitingConfirmation',
        );
        equal(jsonObject(rows.last['timer'], 'timer')['tempoState'], null);
        final s = await cmd('store show', {'id': 'session'});
        equal(
          jsonObject(jsonList(s, 'sets').single, 'set')['status'],
          'planned',
        );
        t = await cmd('timer show', {'id': 'clock'});
        await cmd('timer confirm', {
          'id': 'clock',
          'expectedVersion': t['version'],
          'expectedSessionVersion': 1,
          'at': instant(1).toIso8601String(),
          'actuals': {
            'reps': {'value': '2', 'unit': 'rep'},
          },
        });
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
