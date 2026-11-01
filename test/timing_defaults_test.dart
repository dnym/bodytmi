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

Map<String, Object?> _defaults({int prep = 1000, int near = 1000}) => {
  'metric': 'duration',
  'preparationMilliseconds': prep,
  'nearEndMilliseconds': near,
  'overrun': 'stop',
  'tempo': {
    'phases': [
      {'id': 'lower', 'milliseconds': 1000},
      {'id': 'raise', 'milliseconds': 1000},
    ],
  },
};
WorkoutDefinition _definition({
  bool defaults = true,
  int prep = 1000,
  String seconds = '12',
  bool ambiguous = false,
}) => WorkoutDefinition.fromJson({
  'id': 'guided',
  'name': 'Guided practice',
  'slots': [
    {
      'id': 'movement',
      'exercise': 'custom',
      'implementation': 'custom',
      'targets': {
        'duration': {'value': seconds, 'unit': 's'},
        'mass': {'value': '10', 'unit': 'kg'},
        'reps': {'value': '5', 'unit': 'rep'},
        if (ambiguous) 'otherDuration': {'value': '2', 'unit': 's'},
      },
      if (defaults) 'timing': _defaults(prep: prep),
    },
  ],
  'plan': {
    'id': 'practice',
    'type': 'repeat',
    'count': 2,
    'restBetweenSeconds': 1,
    'child': {'id': 'effort', 'type': 'effort', 'slot': 'movement'},
  },
});
Future<void> _fails(Future<Object?> action) =>
    expectLater(action, throwsA(isA<BodyTmiException>()));
Future<void> _withStore(
  Future<void> Function(TrainingStore, String) action, {
  bool defaults = true,
}) async {
  final dir = await Directory.systemTemp.createTemp('bodytmi-defaults-');
  final store = await TrainingStore.open('${dir.path}/db.sqlite');
  try {
    await StoredTrainingService(
      store,
    ).publish(_definition(defaults: defaults), 0);
    await StoredTrainingService(
      store,
    ).start('session', 'guided', 1, instant(1));
    await action(store, dir.path);
  } finally {
    await store.close();
    await dir.delete(recursive: true);
  }
}

void timingDefaultsTests() {
  test(
    'slot timing defaults validate explicit duration bindings and canonical options without prescribing an independent effort target',
    () {
      final def = _definition();
      final timing = def.slots.single.timing!;
      equal(timing.metric, 'duration');
      equal(timing.resolve(def.slots.single.targets).effortMilliseconds, 12000);
      final changed = {
        ...def.slots.single.targets,
        'duration': Quantity('0.25', 'min'),
      };
      equal(timing.resolve(changed).effortMilliseconds, 15000);
      check(!timing.toJson().containsKey('effortMilliseconds'));
      check(!timing.toJson().containsKey('restMilliseconds'));
      jsonEqual(
        WorkoutDefinition.fromJson(def.toJson()).toJson(),
        def.toJson(),
      );
      for (final bad in <Map<String, Object?>>[
        {..._defaults(), 'metric': 'missing'},
        {..._defaults(), 'metric': 'mass'},
        {..._defaults(), 'effortMilliseconds': 12000},
        {..._defaults(), 'restMilliseconds': 1000},
        {..._defaults(), 'nearEndMilliseconds': 12000},
        {
          ..._defaults(),
          'tempo': {'phases': <Object?>[]},
        },
      ]) {
        final j = def.toJson();
        jsonObject(jsonList(j, 'slots').single, 'slot')['timing'] = bad;
        rejects(() => WorkoutDefinition.fromJson(j));
      }
      rejects(() => _definition(seconds: '0.0001'));
      rejects(() => _definition(seconds: '0'));
      rejects(() => _definition(seconds: '86401'));
      final input = _defaults();
      final frozen = EffortTimingDefaults.fromJson(input);
      input['preparationMilliseconds'] = 999;
      equal(frozen.toJson()['preparationMilliseconds'], 1000);
    },
  );
  test(
    'timers use pinned slot defaults when omitted, explicit plans replace them and retries retain the resolved clock',
    () => _withStore((store, dir) async {
      final timing = TimingService(store),
          training = StoredTrainingService(store);
      final source = canonicalJson((await store.session('session'))!.toJson());
      var t = await timing.start(
        'clock',
        'session',
        'practice[0]/effort',
        'duration',
        null,
        instant(1),
      );
      equal(t.plan.preparationMilliseconds, 1000);
      equal(t.plan.effortMilliseconds, 12000);
      equal(t.plan.restMilliseconds, 0);
      check(t.plan.tempo != null);
      await training.publish(_definition(prep: 2000), 1);
      jsonEqual(
        (await timing.start(
          t.id,
          t.sessionId,
          t.setId,
          t.metric,
          null,
          instant(1),
        )).toJson(),
        t.toJson(),
      );
      t = await timing.stop(
        t.id,
        t.version,
        instant(1),
        confirm: true,
        discard: true,
      );
      final override = await timing.start(
        'override',
        'session',
        t.setId,
        'duration',
        TimingPlan.fromJson({'effortMilliseconds': 2000}),
        instant(1),
      );
      equal(override.plan.preparationMilliseconds, 0);
      equal(override.plan.tempo, null);
      await timing.stop(
        override.id,
        override.version,
        instant(1),
        confirm: true,
        discard: true,
      );
      equal(canonicalJson((await store.session('session'))!.toJson()), source);
      await training.start('new', 'guided', 2, instant(2));
      final newer = await timing.start(
        'new-clock',
        'new',
        t.setId,
        'duration',
        null,
        instant(2),
      );
      equal(newer.plan.preparationMilliseconds, 2000);
      await store.archive();
    }),
  );
  test(
    'managed execution selects the declared duration among multiple metrics and keeps authored recovery separate from effort defaults',
    () => _withStore((store, dir) async {
      final training = StoredTrainingService(store),
          timing = TimingService(store),
          execution = ExecutionService(store);
      await training.publish(_definition(ambiguous: true), 1);
      await training.start('ambiguous', 'guided', 2, instant(2));
      final e = await execution.start('execution', 'ambiguous', instant(2));
      var t = await execution.time(e.id, e.version, instant(2));
      equal(t.metric, 'duration');
      equal(t.plan.preparationMilliseconds, 1000);
      equal(t.plan.restMilliseconds, 0);
      t = await timing.resume(t.id, t.version, 'epoch', instant(2));
      t = (await timing.advance(
        t.id,
        t.version,
        'epoch',
        13000,
        instant(2),
      )).activity;
      final next = await execution.step(
        e.id,
        e.version,
        1,
        'confirm',
        instant(2),
        action: 'confirm',
        timerId: t.id,
        timerVersion: t.version,
        acceptSuggested: true,
      );
      final rest = await timing.show(next.clockId('rest'));
      equal(rest.plan.restMilliseconds, 1000);
      equal(rest.plan.preparationMilliseconds, 0);
      equal(rest.plan.tempo, null);
      await timing.stop(
        rest.id,
        rest.version,
        instant(2),
        confirm: true,
        discard: true,
      );
      await training.start('explicit-metric', 'guided', 2, instant(3));
      final other = await timing.start(
        'other',
        'explicit-metric',
        t.setId,
        'otherDuration',
        null,
        instant(3),
      );
      equal(other.plan.effortMilliseconds, 2000);
      equal(other.plan.preparationMilliseconds, 0);
      equal(other.plan.tempo, null);
      await store.archive();
    }),
  );
  test(
    'accepted duration progression controls default effort length and incompatible shortened targets require an explicit override',
    () => _withStore((store, dir) async {
      final training = StoredTrainingService(store);
      var s = (await store.session('session'))!;
      s = await training.edit(s.id, s.contentVersion, (s) {
        for (final set in s.sets)
          s = const TrainingService().complete(
            s,
            set.id,
            {},
            acceptSuggested: true,
          );
        return s.finish(instant(2));
      });
      final progression = StoredProgressionService(store);
      final rule = <String, Object?>{
        'objective': 'duration',
        'lever': 'mass',
        'lower': {'value': '0.5', 'unit': 's'},
        'upper': {'value': '20', 'unit': 's'},
        'objectiveStep': {'value': '1', 'unit': 's'},
        'leverStep': {'value': '1', 'unit': 'kg'},
        'deloadAfter': 1,
      };
      final p = await progression.propose(s.id, 'movement', rule);
      await progression.accept(s.id, 'movement', p.version, instant(2));
      final next = await training.start('next', 'guided', 1, instant(3));
      final t = await TimingService(store).start(
        'clock',
        next.id,
        next.sets.first.id,
        'duration',
        null,
        instant(3),
      );
      equal(t.plan.effortMilliseconds, 13000);
      equal(t.plan.preparationMilliseconds, 1000);
      await TimingService(
        store,
      ).stop(t.id, t.version, instant(3), confirm: true, discard: true);
      final failed = await training.edit(next.id, next.contentVersion, (s) {
        for (final set in s.sets) {
          s = const TrainingService().complete(s, set.id, {
            'duration': Quantity('1', 's'),
          }, acceptSuggested: true);
        }
        return s.finish(instant(4));
      });
      final deload = await progression.propose(failed.id, 'movement', rule);
      equal(deload.proposal.outcome, 'deload');
      await progression.accept(
        failed.id,
        'movement',
        deload.version,
        instant(4),
      );
      final shortened = await training.start(
        'shortened',
        'guided',
        1,
        instant(5),
      );
      equal(
        shortened.sets.first.suggested['duration']!.value.toString(),
        '0.5',
      );
      await _fails(
        TimingService(store).start(
          'too-short',
          shortened.id,
          shortened.sets.first.id,
          'duration',
          null,
          instant(5),
        ),
      );
      equal(await store.timingActivity('too-short'), null);
      final explicit = TimingPlan.fromJson({'effortMilliseconds': 500});
      final override = await TimingService(store).start(
        'override',
        shortened.id,
        shortened.sets.first.id,
        'duration',
        explicit,
        instant(5),
      );
      equal(override.plan.effortMilliseconds, 500);
      equal(override.plan.nearEndMilliseconds, null);
      equal(shortened.sets.first.status, SetStatus.planned);
      await store.archive();
    }),
  );
  test(
    'v12 profiles migrate without inferred defaults while v13 native/logical restore pins published guidance and resolved interrupted clocks',
    () => _withStore((store, dir) async {
      final before = canonicalJson((await store.archive()).toJson());
      await store.backup('$dir/old');
      final old = sqlite3.open('$dir/old/database.sqlite');
      old.userVersion = 12;
      old.close();
      equal(NativeBackup.validateDatabase('$dir/old/database.sqlite'), 12);
      await LogicalArchiveFiles.export(await store.archive(), '$dir/old.json');
      final j = jsonObject(
        jsonDecode(await File('$dir/old.json').readAsString()),
        'logical',
      );
      j['format'] = 'bodytmi-logical-export/12';
      j.remove('sha256');
      j['sha256'] = sha256.convert(utf8.encode(canonicalJson(j))).toString();
      await File('$dir/old.json').writeAsString(jsonEncode(j));
      final prepared = await LogicalArchiveFiles.prepare('$dir/old.json');
      try {
        equal(canonicalJson(prepared.archive.toJson()), before);
      } finally {
        await prepared.close();
      }
      await store.close();
      final migrated = await TrainingStore.open('$dir/old/database.sqlite');
      try {
        equal(canonicalJson((await migrated.archive()).toJson()), before);
        equal(
          (await migrated.revision(
            'guided',
            1,
          ))!.definition.slots.single.timing,
          null,
        );
      } finally {
        await migrated.close();
      }
      var active = await TrainingStore.open('$dir/db.sqlite');
      try {
        await StoredTrainingService(active).publish(_definition(), 1);
        await StoredTrainingService(
          active,
        ).start('guided', 'guided', 2, instant(2));
        var t = await TimingService(active).start(
          'clock',
          'guided',
          'practice[0]/effort',
          'duration',
          null,
          instant(2),
        );
        t = await TimingService(
          active,
        ).resume(t.id, t.version, 'epoch', instant(2));
        await TimingService(
          active,
        ).advance(t.id, t.version, 'epoch', 2500, instant(2));
        final expected = canonicalJson((await active.archive()).toJson());
        equal(
          (await active.backup('$dir/native'))['databaseSchemaVersion'],
          23,
        );
        equal(
          (await LogicalArchiveFiles.export(
            await active.archive(),
            '$dir/new.json',
          ))['format'],
          'bodytmi-logical-export/23',
        );
        final logical = await LogicalArchiveFiles.prepare('$dir/new.json');
        try {
          await active.restore(
            logical.backup,
            recoveryDestination: '$dir/recovery',
            confirm: true,
          );
        } finally {
          await logical.close();
          await active.close();
        }
        active = await TrainingStore.open('$dir/db.sqlite');
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
        t = await TimingService(active).show('clock');
        final frozen = await TimingService(
          active,
        ).recover(t.id, t.version, instant(9));
        equal(frozen.tempoState!.phaseId, 'raise');
        equal(frozen.tempoState!.phaseElapsedMilliseconds, 500);
      } finally {
        await active.close();
      }
      final forged = sqlite3.open('$dir/native/database.sqlite');
      forged.userVersion = 12;
      forged.close();
      rejects(
        () => NativeBackup.validateDatabase('$dir/native/database.sqlite'),
      );
      final mislabeled = jsonObject(
        jsonDecode(await File('$dir/new.json').readAsString()),
        'logical',
      );
      mislabeled['format'] = 'bodytmi-logical-export/12';
      mislabeled.remove('sha256');
      mislabeled['sha256'] = sha256
          .convert(utf8.encode(canonicalJson(mislabeled)))
          .toString();
      await File('$dir/new.json').writeAsString(jsonEncode(mislabeled));
      await _fails(LogicalArchiveFiles.prepare('$dir/new.json'));
    }, defaults: false),
  );
  test(
    'native timer start and execution run honor published guidance without request plans and still require explicit result review',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-defaults-cli-',
      );
      try {
        Future<Map<String, Object?>> cmd(
          String action,
          Map<String, Object?> request,
        ) async {
          final r = await invoke(
            action.split(' '),
            jsonEncode({
              'schemaVersion': 1,
              'database': '${dir.path}/db.sqlite',
              ...request,
            }),
          );
          equal(r.code, 0);
          equal(r.error, '');
          return jsonObject(
            jsonObject(jsonDecode(r.output), 'response')['data'],
            'data',
          );
        }

        final definition = _definition().toJson();
        final slot = jsonObject(jsonList(definition, 'slots').single, 'slot');
        jsonObject(slot['targets'], 'targets')['duration'] = {
          'value': '0.3',
          'unit': 's',
        };
        slot['timing'] = {
          'metric': 'duration',
          'preparationMilliseconds': 20,
          'nearEndMilliseconds': 50,
          'tempo': {
            'phases': [
              {'id': 'lower', 'milliseconds': 100},
              {'id': 'raise', 'milliseconds': 100},
            ],
          },
        };
        await cmd('store publish', {
          'definition': definition,
          'expectedRevision': 0,
        });
        await cmd('store start', {
          'id': 'session',
          'templateId': 'guided',
          'revision': 1,
          'startedAt': instant(1).toIso8601String(),
        });
        var t = await cmd('timer start', {
          'id': 'clock',
          'sessionId': 'session',
          'setId': 'practice[0]/effort',
          'metric': 'duration',
          'at': instant(1).toIso8601String(),
        });
        equal(jsonObject(t['plan'], 'plan')['preparationMilliseconds'], 20);
        await cmd('timer discard', {
          'id': 'clock',
          'expectedVersion': t['version'],
          'at': instant(1).toIso8601String(),
          'confirm': true,
        });
        await cmd('execution start', {
          'id': 'execution',
          'sessionId': 'session',
          'at': instant(1).toIso8601String(),
        });
        final run = await cmd('execution run', {
          'id': 'execution',
          'expectedVersion': 1,
          'expectedSessionVersion': 1,
          'requestId': 'run',
          'at': instant(1).toIso8601String(),
        });
        equal(run['requiresReview'], true);
        final view = jsonObject(run['execution'], 'execution');
        equal(view['cursor'], 0);
        t = jsonObject(view['timer'], 'timer');
        equal(t['effortElapsedMilliseconds'], 300);
        equal(jsonObject(t['plan'], 'plan')['preparationMilliseconds'], 20);
        equal(
          jsonObject(
            jsonObject(view['current'], 'current')['set'],
            'set',
          )['status'],
          'planned',
        );
        final confirmed = await cmd('execution confirm', {
          'id': 'execution',
          'expectedVersion': 1,
          'expectedSessionVersion': 1,
          'requestId': 'review',
          'timerId': t['id'],
          'timerVersion': t['version'],
          'at': instant(1).toIso8601String(),
          'acceptSuggested': true,
        });
        equal(confirmed['cursor'], 1);
        equal(jsonObject(confirmed['timer'], 'timer')['phase'], 'rest');
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'process death preserves or rolls back resolved default clocks and recovery retains logical tempo without inferred actuals',
    () => _withStore((store, dir) async {
      await StoredTrainingService(store).publish(_definition(seconds: '60'), 1);
      await StoredTrainingService(store).start('long', 'guided', 2, instant(1));
      await TimingService(store).start(
        'clock',
        'long',
        'practice[0]/effort',
        'duration',
        null,
        instant(1),
      );
      await store.close();
      final binary = await compileNative(
        'test/helpers/store_owner.dart',
        '$dir/owner',
      );
      for (final mode in ['clock-rollback', 'clock-commit']) {
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
          final t = await TimingService(recovered).show('clock');
          final committed = mode.endsWith('commit');
          equal(t.plan.preparationMilliseconds, 1000);
          equal(t.status, committed ? 'running' : 'paused');
          equal(t.effortElapsedMilliseconds, committed ? 14000 : 0);
          if (committed) {
            final frozen = await TimingService(
              recovered,
            ).recover(t.id, t.version, instant(9));
            equal(frozen.tempoState!.cycleIndex, 7);
            equal(frozen.tempoState!.phaseId, 'lower');
          }
          equal(
            (await recovered.session('long'))!.sets.first.status,
            SetStatus.planned,
          );
          await recovered.archive();
        } finally {
          await recovered.close();
        }
      }
    }),
  );
}
