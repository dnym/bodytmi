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

final _current = metrics({
  'reps': ('8', 'rep'),
  'assistance': ('40', 'kg'),
  'mass': ('10', 'kg'),
  'supportHeight': ('0.5', 'm'),
});
Map<String, Object?> _rule({String mode = 'all'}) => {
  'metric': 'reps',
  'minimum': {'value': '5', 'unit': 'rep'},
  'threshold': {'value': '8', 'unit': 'rep'},
  'increments': {
    'assistance': {'value': '5', 'unit': 'kg'},
    'mass': {'value': '1', 'unit': 'kg'},
    'supportHeight': {'value': '0.05', 'unit': 'm'},
  },
  'directions': {'assistance': 'decrease', 'supportHeight': 'decrease'},
  'minimums': {
    'assistance': {'value': '0', 'unit': 'kg'},
    'supportHeight': {'value': '0.1', 'unit': 'm'},
  },
  'maximums': {
    'assistance': {'value': '60', 'unit': 'kg'},
  },
  'resets': {
    'reps': {'value': '5', 'unit': 'rep'},
  },
  'coordination': mode == 'all'
      ? {'mode': mode}
      : {
          'mode': mode,
          'order': mode == 'weighted'
              ? ['assistance', 'assistance', 'mass', 'supportHeight']
              : ['assistance', 'mass', 'supportHeight'],
        },
  'deloadAfter': 2,
  'deloadPercent': '10',
  'deloadMetrics': ['assistance', 'mass', 'supportHeight'],
};
ProgressionProposal _eval(
  Map<String, Object?> rule, {
  Metrics? current,
  String reps = '8',
  int failures = 0,
  int cursor = 0,
}) => ThresholdRule.fromJson(rule).evaluate(
  current: current ?? _current,
  results: [
    metrics({'reps': (reps, 'rep')}),
  ],
  failedSessions: failures,
  cursor: cursor,
);
Future<void> _fails(Future<Object?> action) =>
    expectLater(action, throwsA(isA<BodyTmiException>()));
DateTime _at(int day) => instant(day).add(const Duration(hours: 2));
WorkoutDefinition _definition() => WorkoutDefinition.fromJson({
  'id': 'directed',
  'name': 'Explicit numeric directions',
  'slots': [
    {
      'id': 'movement',
      'exercise': 'custom',
      'implementation': 'custom',
      'targets': metricsToJson(_current),
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
Future<void> _withStore(
  Future<void> Function(TrainingStore, String) action,
) async {
  final dir = await Directory.systemTemp.createTemp('bodytmi-direction-');
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
  String reps = '8',
  String? run,
}) async {
  final training = StoredTrainingService(store);
  final s = run == null
      ? await training.start(id, 'directed', 1, instant(day))
      : await ProgramService(store).start(
          run,
          (await ProgramService(store).run(run)).contentVersion,
          id,
          instant(day),
        );
  return training.edit(id, s.contentVersion, (s) {
    for (final set in s.sets) {
      s = const TrainingService().complete(s, set.id, {
        'reps': Quantity(set.role == 'warmup' ? '0' : reps, 'rep'),
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

void numericDirectionTests() {
  test(
    'explicit decreasing steps use exact canonical subtraction without negative quantities or named exercise branches',
    () {
      final p = _eval(_rule());
      equal(p.outcome, 'advance');
      equal(p.nextValues['assistance']!.value.toString(), '35');
      equal(p.nextValues['mass']!.value.toString(), '11');
      equal(p.nextValues['supportHeight']!.value.toString(), '0.45');
      final rule = {
        ..._rule(),
        'increments': {
          'assistance': {'value': '1', 'unit': 'lb'},
        },
        'directions': {'assistance': 'decrease'},
        'minimums': <String, Object?>{},
        'maximums': <String, Object?>{},
        'deloadMetrics': ['assistance'],
      };
      final result = _eval(
        rule,
        current: {..._current, 'assistance': Quantity('10', 'lb')},
      );
      equal(result.nextValues['assistance']!.value.toString(), '4.08233133');
      final countRule = {
        ...rule,
        'increments': {
          'reps': {'value': '1', 'unit': 'rep'},
        },
        'directions': {'reps': 'decrease'},
        'resets': <String, Object?>{},
        'deloadMetrics': <Object?>[],
      };
      equal(_eval(countRule).nextValues['reps']!.value.toString(), '7');
    },
  );
  test(
    'mixed harder directions obey round-robin and weighted frequency and inclusive lower bounds',
    () {
      var current = _current;
      var cursor = 0;
      final rule = _rule(mode: 'weighted');
      for (var i = 0; i < 4; i++) {
        final p = _eval(rule, current: current, cursor: cursor);
        equal(p.outcome, 'advance');
        current = p.nextValues;
        cursor = p.cursor;
      }
      equal(cursor, 0);
      equal(current['assistance']!.value.toString(), '30');
      equal(current['mass']!.value.toString(), '11');
      equal(current['supportHeight']!.value.toString(), '0.45');
      final round = _rule(mode: 'roundRobin');
      equal(
        _eval(round, cursor: 0).nextValues['assistance']!.value.toString(),
        '35',
      );
      equal(_eval(round, cursor: 1).nextValues['mass']!.value.toString(), '11');
      equal(
        _eval(round, cursor: 2).nextValues['supportHeight']!.value.toString(),
        '0.45',
      );
      final bounded = {
        ..._rule(),
        'minimums': {
          'assistance': {'value': '35', 'unit': 'kg'},
        },
      };
      final first = _eval(bounded);
      equal(first.outcome, 'advance');
      final blocked = _eval(bounded, current: first.nextValues);
      equal(blocked.outcome, 'blocked');
      equal(blocked.nextValues['mass']!.value.toString(), '11');
    },
  );
  test(
    'below-zero steps and lower-bound resets block every transformation and preserve the coordinator',
    () {
      final rule = _rule(mode: 'roundRobin');
      final current = {..._current, 'assistance': Quantity('4', 'kg')};
      final p = _eval(rule, current: current);
      equal(p.outcome, 'blocked');
      equal(p.cursor, 0);
      equal(
        canonicalJson(metricsToJson(p.nextValues)),
        canonicalJson(metricsToJson(current)),
      );
      final zero = _eval(
        rule,
        current: {..._current, 'assistance': Quantity('5', 'kg')},
      );
      equal(zero.outcome, 'advance');
      equal(zero.nextValues['assistance']!.value.toString(), '0');
      final reset = _eval({
        ..._rule(),
        'minimums': {
          'reps': {'value': '6', 'unit': 'rep'},
        },
      });
      equal(reset.outcome, 'blocked');
      equal(reset.nextValues['assistance']!.value.toString(), '40');
      equal(reset.nextValues['reps']!.value.toString(), '8');
    },
  );
  test(
    'deload reverses each declared harder direction and blocked deloads retain the counted failed exposure',
    () {
      final p = _eval(_rule(), reps: '1', failures: 1);
      equal(p.outcome, 'deload');
      equal(p.failedSessions, 0);
      equal(p.nextValues['assistance']!.value.toString(), '44');
      equal(p.nextValues['mass']!.value.toString(), '9');
      equal(p.nextValues['supportHeight']!.value.toString(), '0.55');
      equal(p.nextValues['reps']!.value.toString(), '8');
      final blocked = _eval(
        {
          ..._rule(),
          'maximums': {
            'assistance': {'value': '43', 'unit': 'kg'},
          },
        },
        reps: '1',
        failures: 1,
      );
      equal(blocked.outcome, 'blocked');
      equal(blocked.failedSessions, 2);
      equal(blocked.nextValues['mass']!.value.toString(), '10');
      final lower = _eval(
        {
          ..._rule(),
          'minimums': {
            'mass': {'value': '9.5', 'unit': 'kg'},
          },
        },
        reps: '1',
        failures: 1,
      );
      equal(lower.outcome, 'blocked');
      equal(lower.failedSessions, 2);
    },
  );
  test(
    'numeric policies reject unknown directions, contradictory bounds and incompatible steps even before incomplete-work classification',
    () {
      for (final directions in <Object?>[
        null,
        {'assistance': 'harder'},
        {'absent': 'decrease'},
        {'reps': 'decrease'},
        {'mass': 1},
      ]) {
        rejects(
          () => ThresholdRule.fromJson({..._rule(), 'directions': directions}),
        );
      }
      rejects(() => ThresholdRule.fromJson({..._rule(), 'minimums': null}));
      rejects(
        () => ThresholdRule.fromJson({
          ..._rule(),
          'minimums': {
            'assistance': {'value': '61', 'unit': 'kg'},
          },
        }),
      );
      rejects(
        () => ThresholdRule.fromJson({
          ..._rule(),
          'minimums': {
            'assistance': {'value': '1', 'unit': 's'},
          },
        }),
      );
      final wrongStep = {
        ..._rule(),
        'increments': {
          'assistance': {'value': '1', 'unit': 's'},
        },
        'directions': {'assistance': 'decrease'},
      };
      rejects(
        () => ThresholdRule.fromJson(
          wrongStep,
        ).evaluate(current: _current, results: [null]),
      );
      rejects(
        () => _eval({
          ..._rule(),
          'minimums': {
            'absent': {'value': '1', 'unit': 'kg'},
          },
        }),
      );
      rejects(
        () => _eval({
          ..._rule(),
          'deloadMetrics': ['reps'],
        }),
      );
      try {
        ThresholdRule.fromJson(_rule()).directions.clear();
        throw StateError('Mutable directions');
      } on UnsupportedError {
        /* Expected. */
      }
    },
  );
  test(
    'omitted numeric policy preserves legacy increasing steps, deload proposals and serialization',
    () {
      final old = _rule()
        ..remove('directions')
        ..remove('minimums');
      final rule = ThresholdRule.fromJson(old);
      equal(rule.hasNumericPolicy, false);
      final p = _eval(old);
      equal(p.nextValues['assistance']!.value.toString(), '45');
      check(!p.toJson().containsKey('directions'));
      equal(p.reason, 'Every required upper threshold reached (inclusive).');
      final failed = _eval(old, reps: '1', failures: 1);
      equal(failed.nextValues['assistance']!.value.toString(), '36');
      equal(
        failed.reason,
        'Failed-session threshold reached; reduction proposed.',
      );
    },
  );
  test(
    'stored decreasing approvals, declines and subsequent targets remain exactly once with weighted cursor and independent warmups',
    () => _withStore((store, dir) async {
      final rule = _rule(mode: 'weighted');
      final service = StoredProgressionService(store);
      final s = await _finish(store, 'one', 1);
      final p = await _propose(store, s.id, rule);
      final d = await service.accept(s.id, 'movement', p.version, _at(1));
      equal(d.cursor, 1);
      equal(d.nextSets.first['assistance']!.value.toString(), '35');
      final two = await _finish(store, 'two', 2);
      equal(two.sets.first.suggested['assistance']!.value.toString(), '40');
      equal(two.sets.last.suggested['assistance']!.value.toString(), '35');
      final q = await _propose(store, two.id, rule);
      final declined = await service.decline(
        two.id,
        'movement',
        q.version,
        _at(2),
      );
      equal(declined.cursor, 1);
      equal(declined.nextSets.first['assistance']!.value.toString(), '35');
      await StoredTrainingService(store).edit(
        two.id,
        two.contentVersion,
        (s) => const TrainingService().complete(s, s.sets.last.id, {
          'reps': Quantity('1', 'rep'),
        }, acceptSuggested: true),
      );
      equal((await _propose(store, two.id, rule)).status, 'declined');
      final next = await _finish(store, 'three', 3);
      equal(next.sets.last.suggested['assistance']!.value.toString(), '35');
      final r = await _propose(store, next.id, rule);
      equal(r.previousCursor, 1);
      await service.accept(next.id, 'movement', r.version, _at(3));
      equal(
        (await service.accept(next.id, 'movement', r.version, _at(3))).cursor,
        2,
      );
      await store.archive();
    }),
  );
  test(
    'one bounded deload set holds the complete stored vector and retains failures instead of accepting another set counter reset',
    () => _withStore((store, dir) async {
      final rule = {
        ..._rule(),
        'maximums': {
          'assistance': {'value': '44', 'unit': 'kg'},
        },
      };
      var s = await _finish(store, 'one', 1, reps: '1');
      s = await StoredTrainingService(store).edit(s.id, s.contentVersion, (s) {
        final old = s.sets.last;
        return s.replaceSet(
          TrainingSet(
            id: old.id,
            slotId: old.slotId,
            role: old.role,
            ordinal: old.ordinal,
            suggested: {...old.suggested, 'assistance': Quantity('42', 'kg')},
            actuals: {...old.actuals, 'assistance': Quantity('42', 'kg')},
            status: old.status,
            contentVersion: old.contentVersion + 1,
          ),
        );
      });
      final service = StoredProgressionService(store);
      var p = await _propose(store, s.id, rule);
      equal(p.proposal.outcome, 'failed');
      await service.accept(s.id, 'movement', p.version, _at(1));
      final second = await _finish(store, 'two', 2, reps: '1');
      p = await _propose(store, second.id, rule);
      equal(p.proposal.outcome, 'blocked');
      equal(p.proposal.failedSessions, 2);
      equal(p.proposal.nextSets.first['assistance']!.value.toString(), '40');
      equal(p.proposal.nextSets.last['assistance']!.value.toString(), '42');
      equal(p.proposal.nextSets.first['mass']!.value.toString(), '10');
      final d = await service.accept(second.id, 'movement', p.version, _at(2));
      equal(d.failedSessions, 2);
      final third = await _finish(store, 'three', 3, reps: '1');
      final q = await _propose(store, third.id, rule);
      equal(q.proposal.failedSessions, 3);
      equal(
        (await service.decline(
          third.id,
          'movement',
          q.version,
          _at(3),
        )).failedSessions,
        3,
      );
      await store.archive();
    }),
  );
  test(
    'opposite numeric direction rules stay isolated by run and pending source edits require fresh review',
    () => _withStore((store, dir) async {
      final programs = ProgramService(store);
      await programs.publish(
        ProgramDefinition.fromJson({
          'id': 'shared',
          'name': 'Separate directions',
          'plan': {
            'id': 'day',
            'type': 'day',
            'templateId': 'directed',
            'revision': 1,
          },
        }),
        0,
      );
      for (final run in ['strength', 'cardio'])
        await programs.create(run, 'shared', 1, instant(1));
      final down = _rule();
      final up = {
        ..._rule(),
        'directions': {'assistance': 'increase', 'supportHeight': 'decrease'},
      };
      for (final (day, run, rule, value) in [
        (1, 'strength', down, '35'),
        (2, 'cardio', up, '45'),
      ]) {
        final s = await _finish(store, run, day, run: run);
        final p = await _propose(store, s.id, rule);
        final d = await StoredProgressionService(
          store,
        ).accept(s.id, 'movement', p.version, _at(day));
        equal(d.nextSets.first['assistance']!.value.toString(), value);
      }
      final s = await _finish(store, 'next', 3, run: 'strength');
      final p = await _propose(store, s.id, down);
      final changed = await StoredTrainingService(store).edit(
        s.id,
        s.contentVersion,
        (s) => const TrainingService().complete(s, s.sets.last.id, {
          'assistance': Quantity('34', 'kg'),
          'reps': Quantity('8', 'rep'),
        }, acceptSuggested: true),
      );
      await _fails(
        StoredProgressionService(
          store,
        ).accept(s.id, 'movement', p.version, _at(3)),
      );
      final q = await _propose(store, changed.id, down);
      equal(q.proposal.outcome, 'review');
      await _fails(_propose(store, changed.id, up));
      final forged = copyJson(p.toJson());
      (forged['rule'] as Map<String, Object?>)['directions'] = {
        'assistance': 'increase',
        'supportHeight': 'decrease',
      };
      rejects(() => ProgressionDecision.fromJson(forged));
      await store.archive();
    }),
  );
  test(
    'v15 implicit directions migrate unchanged and v16 native and logical restores preserve pending decreasing inputs while old labels reject them',
    () => _withStore((store, dir) async {
      final s = await _finish(store, 'one', 1);
      final oldRule = _rule()
        ..remove('directions')
        ..remove('minimums');
      await _propose(store, s.id, oldRule);
      final before = canonicalJson((await store.archive()).toJson());
      await store.backup('$dir/old');
      await store.close();
      final old = sqlite3.open('$dir/old/database.sqlite');
      old.execute('DROP TABLE derived_target_graphs');
      old.execute('DROP TABLE IF EXISTS repeat_checkpoints');
      old.execute('DROP TABLE IF EXISTS window_checkpoints');
      old.execute('DROP TABLE IF EXISTS progression_reconciliations');
      old.execute('DROP TABLE IF EXISTS lever_link_revisions');
      old.userVersion = 15;
      old.close();
      equal(NativeBackup.validateDatabase('$dir/old/database.sqlite'), 15);
      final upgraded = await TrainingStore.open('$dir/old/database.sqlite');
      try {
        equal(canonicalJson((await upgraded.archive()).toJson()), before);
        equal(
          (await upgraded.backup('$dir/upgraded'))['databaseSchemaVersion'],
          53,
        );
      } finally {
        await upgraded.close();
      }
      final active = await TrainingStore.open('$dir/db.sqlite');
      try {
        await LogicalArchiveFiles.export(
          await active.archive(),
          '$dir/legacy.json',
        );
        Future<void> relabel(String file) async {
          final j = jsonObject(
            jsonDecode(await File(file).readAsString()),
            'logical',
          );
          j['format'] = 'bodytmi-logical-export/15';
          j.remove('sha256');
          j['sha256'] = sha256
              .convert(utf8.encode(canonicalJson(j)))
              .toString();
          await File(file).writeAsString(jsonEncode(j));
        }

        await relabel('$dir/legacy.json');
        final legacy = await LogicalArchiveFiles.prepare('$dir/legacy.json');
        try {
          equal(canonicalJson(legacy.archive.toJson()), before);
        } finally {
          await legacy.close();
        }
        final p = await _propose(active, s.id, _rule(mode: 'weighted'));
        final expected = canonicalJson((await active.archive()).toJson());
        await active.backup('$dir/native');
        await LogicalArchiveFiles.export(
          await active.archive(),
          '$dir/logical.json',
        );
        await active.close();
        for (final kind in ['native', 'logical']) {
          final prepared = kind == 'native'
              ? await NativeBackup.prepare('$dir/native')
              : (await LogicalArchiveFiles.prepare('$dir/logical.json')).backup;
          final target = await TrainingStore.open('$dir/$kind.sqlite');
          try {
            await target.restore(
              prepared,
              recoveryDestination: '$dir/$kind-recovery',
              confirm: true,
            );
          } finally {
            await target.close();
            await prepared.close();
          }
          final restored = await TrainingStore.open('$dir/$kind.sqlite');
          try {
            equal(canonicalJson((await restored.archive()).toJson()), expected);
            final service = StoredProgressionService(restored);
            final d = await service.accept(s.id, 'movement', p.version, _at(1));
            equal(d.cursor, 1);
            equal(d.nextSets.first['assistance']!.value.toString(), '35');
            equal(
              canonicalJson(
                (await service.accept(
                  s.id,
                  'movement',
                  p.version,
                  _at(1),
                )).toJson(),
              ),
              canonicalJson(d.toJson()),
            );
          } finally {
            await restored.close();
          }
        }
        final forged = sqlite3.open('$dir/native/database.sqlite');
        forged.execute('DROP TABLE derived_target_graphs');
        forged.execute('DROP TABLE IF EXISTS repeat_checkpoints');
        forged.execute('DROP TABLE IF EXISTS window_checkpoints');
        forged.execute('DROP TABLE IF EXISTS progression_reconciliations');
        forged.execute('DROP TABLE IF EXISTS lever_link_revisions');
        forged.userVersion = 15;
        forged.close();
        rejects(
          () => NativeBackup.validateDatabase('$dir/native/database.sqlite'),
        );
        await relabel('$dir/logical.json');
        await _fails(LogicalArchiveFiles.prepare('$dir/logical.json'));
      } finally {
        await active.close();
      }
    }),
  );
  test(
    'native pure and stored CLI agree on decreasing prescriptions and reject malformed directions without internal errors',
    () => _withStore((store, dir) async {
      final s = await _finish(store, 'one', 1);
      await store.close();
      Future<Map<String, Object?>> cmd(
        String action,
        Map<String, Object?> request,
      ) async {
        final r = await invoke(
          action.split(' '),
          jsonEncode({'schemaVersion': 1, ...request}),
        );
        equal(r.code, 0);
        equal(r.error, '');
        return jsonObject(
          jsonObject(jsonDecode(r.output), 'response')['data'],
          'data',
        );
      }

      final rule = _rule();
      final pure = await cmd('progression evaluate', {
        'rule': rule,
        'current': metricsToJson(_current),
        'results': [
          metricsToJson(metrics({'reps': ('8', 'rep')})),
        ],
      });
      final request = {
        'database': '$dir/db.sqlite',
        'sessionId': s.id,
        'slotId': 'movement',
      };
      final stored = await cmd('progression propose', {
        ...request,
        'ruleType': 'threshold',
        'rule': rule,
      });
      final nextSets =
          jsonObject(stored['proposal'], 'proposal')['nextSets']
              as List<Object?>;
      equal(canonicalJson(nextSets.first), canonicalJson(pure['nextValues']));
      final d = await cmd('progression accept', {
        ...request,
        'expectedVersion': stored['version'],
        'acceptedAt': _at(1).toIso8601String(),
      });
      equal(jsonObject(d['resolvedState'], 'state')['failedSessions'], 0);
      final bad = await invoke(
        ['progression', 'propose'],
        jsonEncode({
          'schemaVersion': 1,
          ...request,
          'ruleType': 'threshold',
          'rule': {
            ...rule,
            'directions': {'assistance': 'sideways'},
          },
        }),
      );
      check(bad.code != 0);
      equal(bad.output, '');
      check(!bad.error.contains('internal'));
    }),
  );
  test(
    'process death commits or rolls back a decreasing acceptance and retry retains the same target and weighted cursor',
    () => _withStore((store, dir) async {
      await _finish(store, 'one', 1);
      await _propose(store, 'one', _rule(mode: 'weighted'));
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
          equal(p.status, mode.endsWith('commit') ? 'accepted' : 'pending');
          if (p.acceptedAt != null) {
            final retry = await service.accept(
              'one',
              'movement',
              p.version,
              _at(1),
            );
            equal(retry.sequence, 1);
            equal(retry.cursor, 1);
            final next = await _finish(recovered, 'two', 2);
            equal(
              next.sets.last.suggested['assistance']!.value.toString(),
              '35',
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
