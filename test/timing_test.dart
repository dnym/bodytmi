import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart' show expectLater, throwsA, isA;
import 'cli_test.dart';
import 'fixtures.dart';
import 'support.dart';

TimingPlan _plan({
  String overrun = 'stop',
  int prep = 10000,
  int effort = 60000,
  int rest = 20000,
}) => TimingPlan.fromJson({
  'preparationMilliseconds': prep,
  'effortMilliseconds': effort,
  'restMilliseconds': rest,
  'overrun': overrun,
  if (effort > 5000) 'nearEndMilliseconds': 5000,
});
WorkoutDefinition _definition() => WorkoutDefinition.fromJson({
  'id': 'timed',
  'name': 'Timed practice',
  'slots': [
    {
      'id': 'hold',
      'exercise': 'hold',
      'implementation': 'bar',
      'targets': {
        'duration': {'value': '60', 'unit': 's'},
        'mass': {'value': '2', 'unit': 'kg'},
        'reps': {'value': '8', 'unit': 'rep'},
      },
    },
  ],
  'plan': {'id': 'effort', 'type': 'effort', 'slot': 'hold'},
});
TimingActivity _clock({TimingPlan? plan}) => TimingActivity.create(
  id: 'clock',
  sessionId: 'session',
  setId: 'effort',
  metric: 'duration',
  plan: plan ?? _plan(),
  at: instant(1),
);
Future<void> _fails(Future<Object?> action) =>
    expectLater(action, throwsA(isA<BodyTmiException>()));
Future<void> _withStore(
  Future<void> Function(TrainingStore, String) action,
) async {
  final dir = await Directory.systemTemp.createTemp('bodytmi-timing-');
  final store = await TrainingStore.open('${dir.path}/db.sqlite');
  try {
    await StoredTrainingService(store).publish(_definition(), 0);
    await StoredTrainingService(store).start('session', 'timed', 1, instant(1));
    await action(store, dir.path);
  } finally {
    await store.close();
    await dir.delete(recursive: true);
  }
}

Future<TimingActivity> _create(
  TrainingStore store, {
  String id = 'clock',
  String session = 'session',
  TimingPlan? plan,
}) => TimingService(
  store,
).start(id, session, 'effort', 'duration', plan ?? _plan(), instant(1));
Future<TimingActivity> _elapsed(
  TrainingStore store, {
  String id = 'clock',
}) async {
  final service = TimingService(store);
  final t = await service.show(id);
  final running = await service.resume(id, t.version, 'epoch', instant(1));
  return (await service.advance(
    id,
    running.version,
    'epoch',
    90000,
    instant(1),
  )).activity;
}

void timingTests() {
  test(
    'skip remaining requires active and unreviewed clocks to be discarded',
    () => _withStore((store, _) async {
      final training = StoredTrainingService(store);
      final session = await training.session('session');
      final clock = await _create(store);
      await _fails(
        training.editTarget(
          session.id,
          session.contentVersion,
          session.sets.single.id,
          'duration',
          Quantity('5', 's'),
        ),
      );
      await _fails(
        training.skipSlot(
          session.id,
          session.contentVersion,
          session.sets.single.slotId,
          confirm: true,
        ),
      );
      final other = await training.start(
        'other-session',
        'timed',
        1,
        instant(1),
      );
      final otherSkipped = await training.skipRemaining(
        other.id,
        other.contentVersion,
        confirm: true,
      );
      equal(otherSkipped.sets.single.status, SetStatus.skipped);
      equal((await TimingService(store).show(clock.id)).status, 'paused');
      await _fails(
        training.skipRemaining(
          session.id,
          session.contentVersion,
          confirm: true,
        ),
      );
      final pending = await _elapsed(store);
      equal(pending.status, 'awaitingConfirmation');
      await _fails(
        training.editTarget(
          session.id,
          session.contentVersion,
          session.sets.single.id,
          'duration',
          Quantity('5', 's'),
        ),
      );
      await _fails(
        training.skipSlot(
          session.id,
          session.contentVersion,
          session.sets.single.slotId,
          confirm: true,
        ),
      );
      await _fails(
        training.skipRemaining(
          session.id,
          session.contentVersion,
          confirm: true,
        ),
      );
      await TimingService(store).stop(
        pending.id,
        pending.version,
        instant(1),
        confirm: true,
        discard: true,
      );
      final skipped = await training.skipRemaining(
        session.id,
        session.contentVersion,
        confirm: true,
      );
      equal(skipped.sets.single.status, SetStatus.skipped);
      equal(skipped.contentVersion, session.contentVersion + 1);
      check(clock.id == pending.id);
    }),
  );
  test(
    'preparation, effort and rest boundaries preserve only effort duration and await confirmation',
    () {
      var t = _clock().resume('epoch', instant(1));
      t = t.advance(9999, 'epoch', instant(1)).activity;
      equal(t.phase, 'preparation');
      equal(t.effortElapsedMilliseconds, 0);
      var step = t.advance(10000, 'epoch', instant(1));
      t = step.activity;
      equal(t.phase, 'effort');
      equal(step.cues.single['kind'], 'phase');
      step = t.advance(65000, 'epoch', instant(1));
      t = step.activity;
      equal(step.cues.single['kind'], 'near-end');
      step = t.advance(70000, 'epoch', instant(1));
      t = step.activity;
      equal(t.phase, 'rest');
      equal(t.effortElapsedMilliseconds, 60000);
      equal(t.status, 'running');
      step = t.advance(99000, 'epoch', instant(1));
      t = step.activity;
      equal(t.status, 'awaitingConfirmation');
      equal(t.phase, 'done');
      equal(t.elapsedMilliseconds, 90000);
      equal(t.effortElapsedMilliseconds, 60000);
      equal(t.confirmation, null);
      jsonEqual(TimingActivity.fromJson(t.toJson()).toJson(), t.toJson());
    },
  );
  test(
    'pause/resume freezes the phase, rejects invalid owners/samples and permits explicit early/overrun effort endings',
    () {
      var t = _clock()
          .resume('first', instant(1))
          .advance(15000, 'first', instant(1))
          .activity
          .pause(instant(1));
      equal(t.effortElapsedMilliseconds, 5000);
      rejects(() => t.advance(90000, 'first', instant(9)));
      rejects(() => t.resume('first', instant(9)));
      t = t.resume('second', instant(9));
      rejects(() => t.advance(1, 'first', instant(9)));
      t = t
          .advance(2000, 'second', instant(1))
          .activity; // Wall clock moves backwards.
      equal(t.effortElapsedMilliseconds, 7000);
      rejects(() => t.advance(1999, 'second', instant(1)));
      t = t.endEffort(instant(1));
      equal(t.phase, 'rest');
      equal(t.termination, 'early');
      t = t.advance(22000, 'second', instant(1)).activity;
      equal(t.termination, 'early');
      equal(t.status, 'awaitingConfirmation');
      var over = _clock(
        plan: _plan(overrun: 'continue'),
      ).resume('epoch', instant(1));
      over = over.advance(75000, 'epoch', instant(1)).activity;
      equal(over.phase, 'effort');
      equal(over.effortElapsedMilliseconds, 65000);
      over = over.endEffort(instant(1));
      equal(over.termination, 'overrun');
      over = over.advance(95000, 'epoch', instant(1)).activity;
      equal(over.status, 'awaitingConfirmation');
      equal(over.termination, 'overrun');
    },
  );
  test(
    'interruption recovery requires an explicit freeze or elapsed adjustment, never wall-clock catch-up or cue replay',
    () {
      final running = _clock()
          .resume('epoch', instant(1))
          .advance(15000, 'epoch', instant(1))
          .activity;
      final restored = TimingActivity.fromJson(running.toJson());
      rejects(() => restored.resume('new', instant(9)));
      final frozen = restored.recover(instant(9));
      equal(frozen.status, 'paused');
      equal(frozen.effortElapsedMilliseconds, 5000);
      var resumed = frozen.resume('new', instant(9));
      resumed = resumed.advance(50000, 'new', instant(9)).activity;
      equal(resumed.effortElapsedMilliseconds, 55000);
      equal(resumed.advance(50000, 'new', instant(9)).cues.length, 0);
      final adjusted = restored.recover(
        instant(9),
        adjustmentMilliseconds: 100000,
      );
      equal(adjusted.status, 'awaitingConfirmation');
      equal(adjusted.confirmation, null);
      final collision = _clock(
        plan: _plan(prep: 0, rest: 0),
      ).resume('epoch', instant(1)).advance(60000, 'epoch', instant(1));
      equal(collision.cues.length, 1);
      equal(collision.cues.single['kind'], 'phase');
      rejects(() => TimingPlan.fromJson({'effortMilliseconds': 0}));
      rejects(
        () => TimingPlan.fromJson({
          'effortMilliseconds': 10,
          'nearEndMilliseconds': 10,
        }),
      );
    },
  );
  test(
    'one clock is enforced across sessions; expiry does not log work and confirmation is atomic and exactly once',
    () => _withStore((store, dir) async {
      final timers = TimingService(store),
          training = StoredTrainingService(store);
      await training.start('other', 'timed', 1, instant(1));
      final initial = await _create(store);
      jsonEqual((await _create(store)).toJson(), initial.toJson());
      await _fails(_create(store, id: 'other-clock', session: 'other'));
      final current = (await store.session('session'))!;
      await _fails(training.edit(current.id, current.contentVersion, finished));
      final ended = await _elapsed(store);
      equal(
        (await store.session('session'))!.sets.single.status,
        SetStatus.planned,
      );
      await _fails(
        timers.confirm(
          ended.id,
          ended.version,
          99,
          instant(1),
          {},
          acceptSuggested: true,
        ),
      );
      equal((await timers.show(ended.id)).status, 'awaitingConfirmation');
      await _fails(
        timers.confirm(
          ended.id,
          ended.version,
          current.contentVersion,
          instant(1),
          {},
        ),
      );
      equal((await timers.show(ended.id)).status, 'awaitingConfirmation');
      final confirmed = await timers.confirm(
        ended.id,
        ended.version,
        current.contentVersion,
        instant(1),
        {},
        acceptSuggested: true,
      );
      var session = (await store.session('session'))!;
      equal(session.sets.single.actuals['duration']!.value.toString(), '60');
      equal(session.sets.single.timing!.mode, 'timer');
      equal(confirmed.status, 'confirmed');
      jsonEqual(
        (await timers.confirm(
          ended.id,
          ended.version,
          current.contentVersion,
          instant(1),
          {},
          acceptSuggested: true,
        )).toJson(),
        confirmed.toJson(),
      );
      session = await training.edit(
        session.id,
        session.contentVersion,
        (s) => const TrainingService().complete(s, 'effort', {
          'duration': Quantity('59', 's'),
          'mass': Quantity('2', 'kg'),
          'reps': Quantity('8', 'rep'),
        }),
      );
      equal(session.sets.single.timing!.mode, 'manual-edit');
      await timers.confirm(
        ended.id,
        ended.version,
        current.contentVersion,
        instant(1),
        {},
        acceptSuggested: true,
      );
      equal(
        (await store.session(
          'session',
        ))!.sets.single.actuals['duration']!.value.toString(),
        '59',
      );
      await _create(store, id: 'next-clock', session: 'other');
      await store.archive();
    }),
  );
  test(
    'manual duration override is explicit, preparation cancellation cannot certify work, and discard leaves actuals absent',
    () => _withStore((store, dir) async {
      final service = TimingService(store);
      final windowed = _definition().toJson();
      windowed['id'] = 'windowed';
      windowed['plan'] = {
        'id': 'scope',
        'type': 'window',
        'durationSeconds': 60,
        'child': windowed['plan'],
      };
      final training = StoredTrainingService(store);
      await training.publish(WorkoutDefinition.fromJson(windowed), 0);
      await training.start('window-session', 'windowed', 1, instant(1));
      await _fails(
        service.start(
          'unsupported',
          'window-session',
          'scope/effort',
          'duration',
          _plan(),
          instant(1),
        ),
      );
      equal((await store.timingActivities()).length, 0);
      var t = await _create(store);
      await _fails(service.stop(t.id, t.version, instant(1), confirm: false));
      t = await service.stop(t.id, t.version, instant(1), confirm: true);
      await _fails(
        service.confirm(
          t.id,
          t.version,
          1,
          instant(1),
          {},
          acceptSuggested: true,
        ),
      );
      t = await service.stop(
        t.id,
        t.version,
        instant(1),
        confirm: true,
        discard: true,
      );
      equal(t.status, 'discarded');
      equal((await store.session('session'))!.sets.single.actuals.length, 0);
      await _create(store, id: 'override');
      t = await _elapsed(store, id: 'override');
      t = await service.confirm(t.id, t.version, 1, instant(1), {
        'duration': Quantity('55', 's'),
      }, acceptSuggested: true);
      equal(t.confirmation!['setVersion'], 2);
      equal(
        (await store.session('session'))!.sets.single.timing!.mode,
        'manual-override',
      );
      await store.archive();
    }),
  );
  test(
    'archive validation rejects forged clock state, duplicate active clocks and altered confirmation/result references',
    () => _withStore((store, dir) async {
      await _create(store);
      final t = await _elapsed(store);
      await TimingService(
        store,
      ).confirm(t.id, t.version, 1, instant(1), {}, acceptSuggested: true);
      final base = (await store.archive()).toJson();
      final mutations = <void Function(Map<String, Object?>)>[
        (j) => jsonList(j, 'timers').clear(),
        (j) => jsonObject(jsonList(j, 'timers').single, 'timer')['sessionId'] =
            'missing',
        (j) => jsonObject(
          jsonList(j, 'timers').single,
          'timer',
        )['effortElapsedMilliseconds'] = 100000,
        (j) => jsonObject(
          jsonObject(jsonList(j, 'timers').single, 'timer')['confirmation'],
          'confirmation',
        )['setVersion'] = 999,
        (j) => jsonObject(
          jsonObject(
            jsonObject(jsonList(j, 'timers').single, 'timer')['confirmation'],
            'confirmation',
          )['request'],
          'request',
        )['acceptSuggested'] = false,
      ];
      for (final mutate in mutations) {
        final j = copyJson(base);
        mutate(j);
        rejects(() => TrainingArchive.fromJson(j));
      }
      final noResults = copyJson(base);
      jsonList(noResults, 'timers').clear();
      rejects(() => TrainingArchive.fromJson(noResults));
      final another = TimingActivity.create(
        id: 'a',
        sessionId: 'session',
        setId: 'effort',
        metric: 'duration',
        plan: _plan(),
        at: instant(1),
      );
      rejects(
        () => validateTimingData(
          [
            another,
            TimingActivity.create(
              id: 'b',
              sessionId: 'session',
              setId: 'effort',
              metric: 'duration',
              plan: _plan(),
              at: instant(1),
            ),
          ],
          [
            const TrainingService().start(
              sessionId: 'session',
              revision: WorkoutRevision.publish(_definition()),
              startedAt: instant(1),
            ),
          ],
        ),
      );
    }),
  );
  test(
    'native/logical restore retains interrupted clocks and timed result receipts without advancing time or logging work',
    () => _withStore((store, dir) async {
      final training = StoredTrainingService(store),
          timers = TimingService(store);
      await _create(store);
      final ended = await _elapsed(store);
      await timers.confirm(
        ended.id,
        ended.version,
        1,
        instant(1),
        {},
        acceptSuggested: true,
      );
      await training.start('other', 'timed', 1, instant(1));
      var running = await _create(store, id: 'running', session: 'other');
      running = await timers.resume(
        running.id,
        running.version,
        'epoch',
        instant(1),
      );
      await timers.advance(
        running.id,
        running.version,
        'epoch',
        15000,
        instant(1),
      );
      final original = canonicalJson((await store.archive()).toJson());
      equal((await store.backup('$dir/native'))['databaseSchemaVersion'], 1);
      await LogicalArchiveFiles.export(
        await store.archive(),
        '$dir/logical.json',
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
        equal(
          (await again.session('other'))!.sets.single.status,
          SetStatus.planned,
        );
      } finally {
        await again.close();
      }
    }),
  );
  test(
    'timing confirmation does not advance a program and result corrections/refinalization cannot replay either receipt',
    () => _withStore((store, dir) async {
      final programs = ProgramService(store),
          timers = TimingService(store),
          training = StoredTrainingService(store);
      await programs.publish(
        ProgramDefinition.fromJson({
          'id': 'program',
          'name': 'Program',
          'plan': {
            'id': 'day',
            'type': 'day',
            'templateId': 'timed',
            'revision': 1,
          },
        }),
        0,
      );
      await programs.create('run', 'program', 1, instant(1));
      final session = await programs.start(
        'run',
        1,
        'program-session',
        instant(1),
      );
      await _create(store, session: session.id);
      final t = await _elapsed(store);
      await timers.confirm(
        t.id,
        t.version,
        1,
        instant(1),
        {},
        acceptSuggested: true,
      );
      equal((await programs.run('run')).cursor, 0);
      var done = (await store.session(session.id))!;
      done = await training.edit(done.id, done.contentVersion, finished);
      equal((await programs.run('run')).cursor, 1);
      done = await training.edit(
        done.id,
        done.contentVersion,
        (s) => const TrainingService().complete(s, 'effort', {
          'duration': Quantity('61', 's'),
          'mass': Quantity('2', 'kg'),
          'reps': Quantity('8', 'rep'),
        }),
      );
      await training.edit(
        done.id,
        done.contentVersion,
        (s) => s.finish(instant(1).add(const Duration(hours: 2))),
      );
      await timers.confirm(
        t.id,
        t.version,
        1,
        instant(1),
        {},
        acceptSuggested: true,
      );
      equal((await programs.run('run')).cursor, 1);
      equal((await store.programReceipts()).length, 1);
      equal(
        (await store.session(
          done.id,
        ))!.sets.single.actuals['duration']!.value.toString(),
        '61',
      );
      await store.archive();
    }),
  );

  test(
    'process death preserves timing checkpoints and atomically rolls back or commits confirmation with actuals',
    () => _withStore((store, dir) async {
      await _create(store);
      await store.close();
      final binary = await compileNative(
        'test/helpers/store_owner.dart',
        '$dir/owner',
      );
      Future<void> crash(String mode) async {
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
      }

      for (final mode in ['clock-rollback', 'clock-commit']) {
        await crash(mode);
        final recovered = await TrainingStore.open('$dir/db.sqlite');
        try {
          final t = await TimingService(recovered).show('clock');
          equal(t.status, mode == 'clock-commit' ? 'running' : 'paused');
          equal(t.effortElapsedMilliseconds, mode == 'clock-commit' ? 5000 : 0);
          equal(
            (await recovered.session('session'))!.sets.single.status,
            SetStatus.planned,
          );
          if (mode == 'clock-commit') {
            final service = TimingService(recovered);
            var frozen = await service.recover(t.id, t.version, instant(9));
            equal(frozen.effortElapsedMilliseconds, 5000);
            frozen = await service.resume(
              t.id,
              frozen.version,
              'new-epoch',
              instant(9),
            );
            await service.advance(
              t.id,
              frozen.version,
              'new-epoch',
              75000,
              instant(9),
            );
          }
        } finally {
          await recovered.close();
        }
      }
      for (final mode in ['confirm-timing-rollback', 'confirm-timing-commit']) {
        await crash(mode);
        final recovered = await TrainingStore.open('$dir/db.sqlite');
        try {
          final t = await TimingService(recovered).show('clock');
          final committed = mode == 'confirm-timing-commit';
          equal(t.status, committed ? 'confirmed' : 'awaitingConfirmation');
          final session = (await recovered.session('session'))!;
          equal(
            session.sets.single.status,
            committed ? SetStatus.completed : SetStatus.planned,
          );
          equal(session.sets.single.timing != null, committed);
          if (committed) {
            final c = t.confirmation!;
            await TimingService(recovered).confirm(
              t.id,
              c['sourceVersion']! as int,
              1,
              instant(1),
              {},
              acceptSuggested: true,
            );
            equal((await recovered.session('session'))!.contentVersion, 2);
          }
          await recovered.archive();
        } finally {
          await recovered.close();
        }
      }
    }),
  );

  test(
    'foreground process kill requires recovery, while SIGINT explicitly pauses the persisted logical phase',
    () => _withStore((store, dir) async {
      await _create(store, plan: _plan(prep: 0, effort: 10000, rest: 0));
      await store.close();
      final binary = await compileNative('bin/bodytmi.dart', '$dir/native');
      Future<({Process child, Future<String> output, Future<String> errors})>
      launch(int version) async {
        final child = await Process.start(binary, ['timer', 'run']);
        final output = child.stdout.transform(utf8.decoder).join(),
            errors = child.stderr.transform(utf8.decoder).join();
        child.stdin.writeln(
          jsonEncode({
            'schemaVersion': 1,
            'database': '$dir/db.sqlite',
            'id': 'clock',
            'expectedVersion': version,
          }),
        );
        await child.stdin.close();
        return (child: child, output: output, errors: errors);
      }

      Future<void> checkpoint() async {
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        final raw = sqlite3.open('$dir/db.sqlite', mode: OpenMode.readOnly);
        try {
          while (DateTime.now().isBefore(deadline)) {
            final rows = raw.select(
              "SELECT snapshot FROM timing_activities WHERE id='clock'",
            );
            final json = jsonObject(
              jsonDecode(rows.single['snapshot'] as String),
              'timer',
            );
            if (json['status'] == 'running' &&
                (json['ownerElapsedMilliseconds']! as int) > 0)
              return;
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          throw StateError('Foreground clock did not checkpoint.');
        } finally {
          raw.close();
        }
      }

      var process = await launch(1);
      try {
        await checkpoint();
        process.child.kill(ProcessSignal.sigkill);
        await process.child.exitCode;
        await process.output;
        equal(await process.errors, '');
      } finally {
        process.child.kill(ProcessSignal.sigkill);
        await process.child.exitCode;
      }
      final recovered = await TrainingStore.open('$dir/db.sqlite');
      int version;
      try {
        final service = TimingService(recovered);
        final t = await service.show('clock');
        equal(t.status, 'running');
        check(t.effortElapsedMilliseconds > 0);
        final frozen = await service.recover(t.id, t.version, instant(20));
        equal(frozen.status, 'paused');
        equal(frozen.effortElapsedMilliseconds, t.effortElapsedMilliseconds);
        version = frozen.version;
        equal(
          (await recovered.session('session'))!.sets.single.status,
          SetStatus.planned,
        );
      } finally {
        await recovered.close();
      }
      process = await launch(version);
      try {
        await checkpoint();
        process.child.kill(ProcessSignal.sigint);
        equal(
          await process.child.exitCode.timeout(const Duration(seconds: 10)),
          0,
        );
        equal(await process.errors, '');
        final response = jsonObject(
          jsonObject(jsonDecode(await process.output), 'response')['data'],
          'run',
        );
        equal(response['interrupted'], true);
        equal(jsonObject(response['timer'], 'timer')['status'], 'paused');
      } finally {
        process.child.kill(ProcessSignal.sigkill);
        await process.child.exitCode;
      }
    }),
  );

  test(
    'foreground native runner uses a real monotonic clock, streams optional cues and leaves results for explicit review',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-timing-cli-');
      try {
        Future<Object?> command(String name, Map<String, Object?> input) async {
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
          return jsonObject(jsonDecode(r.output), 'response')['data'];
        }

        await command('store publish', {
          'definition': _definition().toJson(),
          'expectedRevision': 0,
        });
        await command('store start', {
          'id': 'session',
          'templateId': 'timed',
          'revision': 1,
          'startedAt': instant(1).toIso8601String(),
        });
        await command('timer start', {
          'id': 'clock',
          'sessionId': 'session',
          'setId': 'effort',
          'metric': 'duration',
          'plan': _plan(prep: 20, effort: 40, rest: 20).toJson(),
          'at': instant(1).toIso8601String(),
        });
        final response = await invoke(
          ['timer', 'run'],
          jsonEncode({
            'schemaVersion': 1,
            'database': '${dir.path}/db.sqlite',
            'id': 'clock',
            'expectedVersion': 1,
            'stream': true,
          }),
        );
        equal(response.code, 0);
        equal(response.error, '');
        final lines = const LineSplitter().convert(response.output);
        check(lines.length >= 2);
        final result = jsonObject(
          jsonObject(jsonDecode(lines.last), 'response')['data'],
          'result',
        );
        final timer = jsonObject(result['timer'], 'timer');
        equal(timer['status'], 'awaitingConfirmation');
        equal(timer['effortElapsedMilliseconds'], 40);
        final session = jsonObject(
          await command('store show', {'id': 'session'}),
          'session',
        );
        equal(
          jsonObject(jsonList(session, 'sets').single, 'set')['status'],
          'planned',
        );
        await command('timer confirm', {
          'id': 'clock',
          'expectedVersion': timer['version'],
          'expectedSessionVersion': 1,
          'at': instant(1).toIso8601String(),
          'acceptSuggested': true,
        });
        final finished = jsonObject(
          await command('store show', {'id': 'session'}),
          'session',
        );
        equal(
          jsonObject(
            jsonObject(jsonList(finished, 'sets').single, 'set')['actuals'],
            'actuals',
          )['duration'].toString().contains('0.04'),
          true,
        );
        await command('store start', {
          'id': 'other',
          'templateId': 'timed',
          'revision': 1,
          'startedAt': instant(1).toIso8601String(),
        });
        await command('timer start', {
          'id': 'bounded',
          'sessionId': 'other',
          'setId': 'effort',
          'metric': 'duration',
          'plan': _plan(prep: 0, effort: 1000, rest: 0).toJson(),
          'at': instant(1).toIso8601String(),
        });
        final bounded = jsonObject(
          await command('timer run', {
            'id': 'bounded',
            'expectedVersion': 1,
            'runForMilliseconds': 20,
          }),
          'run',
        );
        equal(jsonObject(bounded['timer'], 'timer')['status'], 'paused');
        equal(
          jsonObject(bounded['timer'], 'timer')['effortElapsedMilliseconds'],
          20,
        );
        final endedEarly = jsonObject(
          await command('timer end-effort', {
            'id': 'bounded',
            'expectedVersion': jsonObject(bounded['timer'], 'timer')['version'],
            'at': instant(1).toIso8601String(),
          }),
          'timer',
        );
        equal(endedEarly['status'], 'awaitingConfirmation');
        equal(endedEarly['termination'], 'early');
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
