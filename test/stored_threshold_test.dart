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

Map<String, Object?> _rule({String mode = 'weighted'}) => {
  'metric': 'duration',
  'minimum': {'value': '10', 'unit': 's'},
  'threshold': {'value': '60', 'unit': 's'},
  'increments': {
    'mass': {'value': '1', 'unit': 'kg'},
    'distance': {'value': '0.1', 'unit': 'm'},
    'angle': {'value': '0.1', 'unit': 'rad'},
  },
  'resets': {
    'duration': {'value': '10', 'unit': 's'},
  },
  'coordination': mode == 'all'
      ? {'mode': 'all'}
      : {
          'mode': mode,
          'order': mode == 'weighted'
              ? ['mass', 'mass', 'mass', 'distance', 'distance', 'angle']
              : ['mass', 'distance', 'angle'],
        },
  'deloadAfter': 2,
  'deloadPercent': '10',
  'deloadMetrics': ['mass', 'distance'],
};
WorkoutDefinition _definition() => WorkoutDefinition.fromJson({
  'id': 'threshold',
  'name': 'Numeric practice',
  'slots': [
    {
      'id': 'movement',
      'exercise': 'custom',
      'implementation': 'custom',
      'targets': {
        'duration': {'value': '60', 'unit': 's'},
        'mass': {'value': '10', 'unit': 'kg'},
        'distance': {'value': '1', 'unit': 'm'},
        'angle': {'value': '1', 'unit': 'rad'},
        'reps': {'value': '5', 'unit': 'rep'},
      },
      'prefill': ['reps'],
    },
  ],
  'plan': {
    'id': 'practice',
    'type': 'sequence',
    'children': [
      {'id': 'warmup', 'type': 'effort', 'slot': 'movement', 'role': 'warmup'},
      {
        'id': 'work',
        'type': 'repeat',
        'count': 2,
        'child': {'id': 'set', 'type': 'effort', 'slot': 'movement'},
      },
    ],
  },
});
DateTime _at(int day) => instant(day).add(const Duration(hours: 2));
Future<void> _fails(Future<Object?> action) =>
    expectLater(action, throwsA(isA<BodyTmiException>()));
Future<void> _withStore(
  Future<void> Function(TrainingStore, String) action,
) async {
  final dir = await Directory.systemTemp.createTemp('bodytmi-threshold-');
  final store = await TrainingStore.open('${dir.path}/db.sqlite');
  try {
    await StoredTrainingService(store).publish(_definition(), 0);
    await action(store, dir.path);
  } finally {
    await store.close();
    await dir.delete(recursive: true);
  }
}

Future<TrainingSession> _finish(
  TrainingStore store,
  String id,
  int day, {
  String duration = '60',
  bool skip = false,
  bool changed = false,
  String? run,
}) async {
  final training = StoredTrainingService(store);
  final s = run == null
      ? await training.start(id, 'threshold', 1, instant(day))
      : await ProgramService(store).start(
          run,
          (await ProgramService(store).run(run)).contentVersion,
          id,
          instant(day),
        );
  return training.edit(id, s.contentVersion, (s) {
    for (final set in s.sets) {
      s = skip
          ? const TrainingService().skip(s, set.id, confirm: true)
          : const TrainingService().complete(s, set.id, {
              'duration': Quantity(set.role == 'warmup' ? '1' : duration, 's'),
              'reps': Quantity('7', 'rep'),
              if (changed && set.role == 'work')
                'mass': set.suggested['mass']!.add(Quantity('1', 'kg')),
            }, acceptSuggested: true);
    }
    return s.finish(instant(day).add(const Duration(hours: 1)));
  });
}

Future<ProgressionDecision> _propose(
  TrainingStore store,
  String id,
  Map<String, Object?> rule,
) => StoredProgressionService(
  store,
).propose(id, 'movement', rule, ruleType: 'threshold');

void storedThresholdTests() {
  test(
    'durable weighted 3:2:1 coordination advances one vector lever per acceptance and keeps resets, warmups and history prefill separate',
    () => _withStore((store, dir) async {
      final service = StoredProgressionService(store);
      final rule = _rule();
      for (var day = 1; day <= 6; day++) {
        final s = await _finish(store, 's$day', day);
        final p = await _propose(store, s.id, rule);
        equal(p.previousCursor, day - 1);
        equal(p.proposal.outcome, 'advance');
        equal(p.sets.length, 2);
        equal(p.proposal.cursor, day % 6);
        equal(
          canonicalJson((await _propose(store, s.id, rule)).toJson()),
          canonicalJson(p.toJson()),
        );
        final applied = await service.accept(
          s.id,
          'movement',
          p.version,
          _at(day),
        );
        equal(applied.cursor, day % 6);
        equal(applied.sequence, day);
        equal(
          canonicalJson(
            (await service.accept(
              s.id,
              'movement',
              p.version,
              _at(day),
            )).toJson(),
          ),
          canonicalJson(applied.toJson()),
        );
      }
      final next = await StoredTrainingService(
        store,
      ).start('next', 'threshold', 1, instant(7));
      final work = next.sets.where((s) => s.role == 'work').first;
      equal(work.suggested['mass']!.value.toString(), '13');
      equal(work.suggested['distance']!.value.toString(), '1.2');
      equal(work.suggested['angle']!.value.toString(), '1.1');
      equal(work.suggested['duration']!.value.toString(), '10');
      equal(work.suggested['reps']!.value.toString(), '7');
      equal(next.sets.first.suggested['mass']!.value.toString(), '10');
      equal(next.sets.first.suggested['duration']!.value.toString(), '60');
      await store.archive();
    }),
  );
  test(
    'declines, failed and neutral exposures, deloads and holds never consume coordinator positions',
    () => _withStore((store, dir) async {
      final service = StoredProgressionService(store);
      final rule = _rule(mode: 'roundRobin');
      final cases = [
        ('60', false, false, 'advance'),
        ('1', false, false, 'failed'),
        ('1', false, false, 'deload'),
        ('30', false, false, 'hold'),
        ('60', true, false, 'unknown'),
        ('60', false, true, 'review'),
      ];
      final failures = [0, 1, 2, 0, 0, 0];
      for (var i = 0; i < cases.length; i++) {
        final c = cases[i];
        var s = await _finish(
          store,
          's$i',
          i + 1,
          duration: c.$1,
          skip: c.$2,
          changed: c.$3,
        );
        if (i == 1) {
          s = await StoredTrainingService(store).edit(
            s.id,
            s.contentVersion,
            (s) => const TrainingService().complete(s, s.sets.last.id, {
              'duration': Quantity('60', 's'),
            }, acceptSuggested: true),
          );
        }
        final p = await _propose(store, s.id, rule);
        equal(p.proposal.outcome, c.$4);
        equal(p.previousCursor, 0);
        if (c.$4 == 'review' || c.$4 == 'unknown')
          await _fails(service.accept(s.id, 'movement', p.version, _at(i + 1)));
        final d = c.$4 == 'hold'
            ? await service.accept(s.id, 'movement', p.version, _at(i + 1))
            : await service.decline(s.id, 'movement', p.version, _at(i + 1));
        equal(d.cursor, 0);
        equal(d.failedSessions, failures[i]);
        equal(d.nextSets.first['mass']!.value.toString(), '10');
      }
      final s = await _finish(store, 'advance', 7);
      final p = await _propose(store, s.id, rule);
      final d = await service.accept(s.id, 'movement', p.version, _at(7));
      equal(d.cursor, 1);
      equal(d.nextSets.first['mass']!.value.toString(), '11');
      final failed = await _finish(store, 'failed', 8, duration: '1');
      final fp = await _propose(store, failed.id, rule);
      final fd = await service.accept(
        failed.id,
        'movement',
        fp.version,
        _at(8),
      );
      equal(fd.failedSessions, 1);
      equal(fd.cursor, 1);
      final deload = await _finish(store, 'deload', 9, duration: '1');
      final dp = await _propose(store, deload.id, rule);
      equal(dp.proposal.outcome, 'deload');
      final dd = await service.accept(
        deload.id,
        'movement',
        dp.version,
        _at(9),
      );
      equal(dd.failedSessions, 0);
      equal(dd.cursor, 1);
      equal(dd.nextSets.first['mass']!.value.toString(), '9.9');
      equal(dd.nextSets.first['distance']!.value.toString(), '0.9');
      equal(dd.nextSets.first['duration']!.value.toString(), '10');
      await store.archive();
    }),
  );
  test(
    'all-together coordination applies atomically across unequal set vectors and blocks every change when one set reaches a bound',
    () => _withStore((store, dir) async {
      var s = await _finish(store, 'one', 1);
      s = await StoredTrainingService(store).edit(s.id, s.contentVersion, (
        session,
      ) {
        final old = session.sets.last;
        final updated = TrainingSet(
          id: old.id,
          slotId: old.slotId,
          role: old.role,
          ordinal: old.ordinal,
          suggested: {...old.suggested, 'mass': Quantity('10.5', 'kg')},
          actuals: {...old.actuals, 'mass': Quantity('10.5', 'kg')},
          status: old.status,
          contentVersion: old.contentVersion + 1,
        );
        return session.replaceSet(updated);
      });
      final all = ProgressionDecision(
        session: s,
        slotId: 'movement',
        rule: _rule(mode: 'all'),
        ruleType: 'threshold',
      ).proposal;
      equal(all.outcome, 'advance');
      equal(all.nextSets.first['mass']!.value.toString(), '11');
      equal(all.nextSets.last['mass']!.value.toString(), '11.5');
      equal(all.nextSets.last['distance']!.value.toString(), '1.1');
      equal(all.nextSets.last['angle']!.value.toString(), '1.1');
      equal(all.nextSets.last['duration']!.value.toString(), '10');
      final rule = {
        ..._rule(mode: 'all'),
        'maximums': {
          'mass': {'value': '11', 'unit': 'kg'},
        },
      };
      final p = await _propose(store, s.id, rule);
      equal(p.proposal.outcome, 'blocked');
      equal(p.proposal.cursor, 0);
      equal(p.proposal.nextSets.first['mass']!.value.toString(), '10');
      equal(p.proposal.nextSets.last['mass']!.value.toString(), '10.5');
      equal(p.proposal.nextSets.first['duration']!.value.toString(), '60');
      final d = await StoredProgressionService(
        store,
      ).accept(s.id, 'movement', p.version, _at(1));
      equal(d.cursor, 0);
      equal(d.failedSessions, 0);
      final next = await _finish(store, 'two', 2);
      final noBound = {
        ...rule,
        'maximums': {
          'mass': {'value': '20', 'unit': 'kg'},
        },
      };
      await _fails(
        _propose(store, next.id, noBound),
      ); // Rule changes require reconciliation.
      await store.archive();
    }),
  );
  test(
    'threshold receipts reject changed inputs, competing rule types and forged coordinator lineage without replay after corrections',
    () => _withStore((store, dir) async {
      final service = StoredProgressionService(store);
      final rule = _rule();
      var s = await _finish(store, 'one', 1);
      var p = await _propose(store, s.id, rule);
      s = await StoredTrainingService(store).edit(
        s.id,
        s.contentVersion,
        (s) => const TrainingService().complete(s, s.sets.last.id, {
          'duration': Quantity('61', 's'),
        }, acceptSuggested: true),
      );
      await _fails(service.accept(s.id, 'movement', p.version, _at(1)));
      p = await _propose(store, s.id, rule);
      equal(p.version, 2);
      final d = await service.accept(s.id, 'movement', p.version, _at(1));
      s = await StoredTrainingService(store).edit(
        s.id,
        s.contentVersion,
        (s) => const TrainingService().complete(s, s.sets.last.id, {
          'duration': Quantity('1', 's'),
        }, acceptSuggested: true),
      );
      equal(await service.stale(d), true);
      equal(
        (await service.accept(s.id, 'movement', p.version, _at(2))).cursor,
        1,
      );
      equal((await _propose(store, s.id, rule)).sequence, 1);
      await _finish(store, 'two', 2);
      await _propose(store, 'two', rule);
      await _fails(
        service.propose(
          'two',
          'movement',
          jsonObject(example('double-progression')['rule'], 'rule'),
        ),
      );
      final base = (await store.archive()).toJson();
      for (final mutate in <void Function(List<Object?>)>[
        (rows) => jsonObject(rows.last, 'decision')['previousCursor'] = 0,
        (rows) => jsonObject(
          jsonObject(
            jsonObject(rows.first, 'decision')['proposal'],
            'proposal',
          )['nextState'],
          'state',
        )['cursor'] = 5,
        (rows) =>
            jsonObject(rows.first, 'decision')['ruleType'] = 'unsupported',
      ]) {
        final data = copyJson(base);
        mutate(jsonList(data, 'progressions'));
        rejects(() => TrainingArchive.fromJson(data));
      }
    }),
  );
  test(
    'simultaneous runs retain separate weighted cursors and controlled vectors even with the same workout and rule',
    () => _withStore((store, dir) async {
      final programs = ProgramService(store),
          service = StoredProgressionService(store);
      await programs.publish(
        ProgramDefinition.fromJson({
          'id': 'shared',
          'name': 'Shared',
          'plan': {
            'id': 'day',
            'type': 'day',
            'templateId': 'threshold',
            'revision': 1,
          },
        }),
        0,
      );
      for (final id in ['strength', 'cardio'])
        await programs.create(id, 'shared', 1, instant(1));
      for (var day = 1; day <= 3; day++) {
        final s = await _finish(store, 'strength$day', day, run: 'strength');
        final p = await _propose(store, s.id, _rule());
        await service.accept(s.id, 'movement', p.version, _at(day));
      }
      final cardio = await _finish(store, 'cardio', 4, run: 'cardio');
      final p = await _propose(store, cardio.id, _rule());
      equal(p.previousCursor, 0);
      equal(p.previousSequence, 0);
      equal(p.sets.first.suggested['mass']!.value.toString(), '10');
      final strength = await _finish(store, 'next', 5, run: 'strength');
      final q = await _propose(store, strength.id, _rule());
      equal(q.previousCursor, 3);
      equal(q.proposal.nextSets.first['distance']!.value.toString(), '1.1');
      await store.archive();
    }),
  );
  test(
    'v13 profiles retain old history and v14 native/logical restore preserve threshold vectors, pending inputs and coordinator cursor',
    () => _withStore((store, dir) async {
      await _finish(store, 'legacy', 1);
      final before = canonicalJson((await store.archive()).toJson());
      await store.backup('$dir/old');
      final old = sqlite3.open('$dir/old/database.sqlite');
      old.userVersion = 13;
      old.close();
      equal(NativeBackup.validateDatabase('$dir/old/database.sqlite'), 13);
      await LogicalArchiveFiles.export(await store.archive(), '$dir/old.json');
      final j = jsonObject(
        jsonDecode(await File('$dir/old.json').readAsString()),
        'logical',
      );
      j['format'] = 'bodytmi-logical-export/13';
      j.remove('sha256');
      j['sha256'] = sha256.convert(utf8.encode(canonicalJson(j))).toString();
      await File('$dir/old.json').writeAsString(jsonEncode(j));
      final legacy = await LogicalArchiveFiles.prepare('$dir/old.json');
      try {
        equal(canonicalJson(legacy.archive.toJson()), before);
      } finally {
        await legacy.close();
      }
      await store.close();
      final upgraded = await TrainingStore.open('$dir/old/database.sqlite');
      try {
        equal(canonicalJson((await upgraded.archive()).toJson()), before);
        equal(
          (await upgraded.backup('$dir/upgraded'))['databaseSchemaVersion'],
          20,
        );
      } finally {
        await upgraded.close();
      }
      var active = await TrainingStore.open('$dir/db.sqlite');
      try {
        var p = await _propose(active, 'legacy', _rule());
        await StoredProgressionService(
          active,
        ).accept('legacy', 'movement', p.version, _at(1));
        await _finish(active, 'next', 2);
        p = await _propose(active, 'next', _rule());
        equal(p.previousCursor, 1);
        final expected = canonicalJson((await active.archive()).toJson());
        equal(
          (await active.backup('$dir/native'))['databaseSchemaVersion'],
          20,
        );
        equal(
          (await LogicalArchiveFiles.export(
            await active.archive(),
            '$dir/logical.json',
          ))['format'],
          'bodytmi-logical-export/20',
        );
        final logical = await LogicalArchiveFiles.prepare('$dir/logical.json');
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
        final applied = await StoredProgressionService(
          active,
        ).accept('next', 'movement', p.version, _at(2));
        equal(applied.cursor, 2);
        equal(applied.nextSets.first['mass']!.value.toString(), '12');
      } finally {
        await active.close();
      }
      final forged = sqlite3.open('$dir/native/database.sqlite');
      forged.userVersion = 13;
      forged.close();
      rejects(
        () => NativeBackup.validateDatabase('$dir/native/database.sqlite'),
      );
      final mislabeled = jsonObject(
        jsonDecode(await File('$dir/logical.json').readAsString()),
        'logical',
      );
      mislabeled['format'] = 'bodytmi-logical-export/13';
      mislabeled.remove('sha256');
      mislabeled['sha256'] = sha256
          .convert(utf8.encode(canonicalJson(mislabeled)))
          .toString();
      await File('$dir/logical.json').writeAsString(jsonEncode(mislabeled));
      await _fails(LogicalArchiveFiles.prepare('$dir/logical.json'));
    }),
  );
  test(
    'native threshold CLI exposes proposed versus resolved cursor and keeps declines from consuming a position',
    () => _withStore((store, dir) async {
      await _finish(store, 'one', 1);
      await _finish(store, 'two', 2);
      await store.close();
      Future<Map<String, Object?>> cmd(
        String action,
        Map<String, Object?> request,
      ) async {
        final r = await invoke(
          action.split(' '),
          jsonEncode({
            'schemaVersion': 1,
            'database': '$dir/db.sqlite',
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

      final p = await cmd('progression propose', {
        'sessionId': 'one',
        'slotId': 'movement',
        'ruleType': 'threshold',
        'rule': _rule(),
      });
      equal(p['resolvedState'], null);
      equal(p['previousCursor'], 0);
      final request = {
        'sessionId': 'one',
        'slotId': 'movement',
        'expectedVersion': p['version'],
        'acceptedAt': _at(1).toIso8601String(),
      };
      final d = await cmd('progression accept', request);
      equal(jsonObject(d['resolvedState'], 'state')['cursor'], 1);
      jsonEqual(await cmd('progression accept', request), d);
      // The prestarted second session has the old vector and needs reconciliation;
      // this must not apply a second transition from an obsolete baseline.
      final stale = await invoke(
        ['progression', 'propose'],
        jsonEncode({
          'schemaVersion': 1,
          'database': '$dir/db.sqlite',
          'sessionId': 'two',
          'slotId': 'movement',
          'ruleType': 'threshold',
          'rule': _rule(),
        }),
      );
      check(stale.code != 0);
      equal(stale.output, '');
      var s = await cmd('store start', {
        'id': 'fresh',
        'templateId': 'threshold',
        'revision': 1,
        'startedAt': instant(3).toIso8601String(),
      });
      for (final item in jsonList(s, 'sets')) {
        final set = jsonObject(item, 'set');
        s = await cmd('store complete', {
          'id': 'fresh',
          'setId': set['id'],
          'expectedVersion': s['contentVersion'],
          'actuals': {
            'duration': {'value': '60', 'unit': 's'},
          },
          'acceptSuggested': true,
        });
      }
      s = await cmd('store finish', {
        'id': 'fresh',
        'expectedVersion': s['contentVersion'],
        'finishedAt': instant(4).toIso8601String(),
      });
      final q = await cmd('progression propose', {
        'sessionId': 'fresh',
        'slotId': 'movement',
        'ruleType': 'threshold',
        'rule': _rule(),
      });
      final declined = await cmd('progression decline', {
        'sessionId': 'fresh',
        'slotId': 'movement',
        'expectedVersion': q['version'],
        'declinedAt': _at(4).toIso8601String(),
      });
      equal(jsonObject(declined['resolvedState'], 'state')['cursor'], 1);
      equal(
        jsonObject(
          jsonObject(declined['proposal'], 'proposal')['nextState'],
          'state',
        )['cursor'],
        2,
      );
    }),
  );
  test(
    'process death commits or rolls back threshold approval and retry never consumes another weighted position',
    () => _withStore((store, dir) async {
      await _finish(store, 'one', 1);
      await _propose(store, 'one', _rule());
      await store.close();
      final binary = await compileNative(
        'test/helpers/store_owner.dart',
        '$dir/owner',
      );
      for (final mode in ['accept-rollback', 'accept-commit']) {
        final child = await Process.start(binary, [
          '$dir/db.sqlite',
          mode,
          'one',
          'movement',
          _at(1).toIso8601String(),
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
        } finally {
          child.kill(ProcessSignal.sigkill);
          await child.exitCode;
        }
        final recovered = await TrainingStore.open('$dir/db.sqlite');
        try {
          final service = StoredProgressionService(recovered);
          final p = await service.decision('one', 'movement');
          final committed = mode.endsWith('commit');
          equal(p.status, committed ? 'accepted' : 'pending');
          equal(p.sequence, committed ? 1 : 0);
          equal(p.previousCursor, 0);
          if (committed) {
            equal(
              (await service.accept(
                'one',
                'movement',
                p.version,
                _at(1),
              )).cursor,
              1,
            );
            await _finish(recovered, 'two', 2);
            equal(
              (await _propose(recovered, 'two', _rule())).previousCursor,
              1,
            );
          }
          await recovered.archive();
        } finally {
          await recovered.close();
        }
      }
    }),
  );
}
