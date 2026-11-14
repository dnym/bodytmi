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

Map<String, Object?> _rule(
  String mode, {
  int? count,
  bool totalFailure = false,
}) => {
  'metric': 'reps',
  'minimum': {'value': totalFailure ? '15' : '5', 'unit': 'rep'},
  'threshold': {'value': mode == 'total' ? '18' : '12', 'unit': 'rep'},
  'increments': {
    'mass': {'value': '1', 'unit': 'kg'},
  },
  'resets': {
    'reps': {'value': '5', 'unit': 'rep'},
  },
  'aggregation': {'mode': mode, if (count != null) 'count': count},
  if (totalFailure) 'failureAggregation': {'mode': 'total'},
  'deloadAfter': 2,
  'deloadMetrics': ['mass'],
};
final _current = metrics({'mass': ('10', 'kg'), 'reps': ('8', 'rep')});
List<Metrics?> _results(List<String?> reps) => [
  for (final value in reps)
    value == null ? null : metrics({'reps': (value, 'rep')}),
];
ProgressionProposal _evaluate(
  Map<String, Object?> rule,
  List<String?> values, {
  int failures = 0,
}) => ThresholdRule.fromJson(rule).evaluate(
  current: _current,
  results: _results(values),
  failedSessions: failures,
);
Future<void> _fails(Future<Object?> action) =>
    expectLater(action, throwsA(isA<BodyTmiException>()));
DateTime _at(int day) => instant(day).add(const Duration(hours: 2));
WorkoutDefinition _definition() => WorkoutDefinition.fromJson({
  'id': 'aggregate',
  'name': 'Explicit numeric aggregation',
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
        'count': 3,
        'child': {'id': 'set', 'type': 'effort', 'slot': 'movement'},
      },
    ],
  },
});
Future<void> _withStore(
  Future<void> Function(TrainingStore, String) action,
) async {
  final dir = await Directory.systemTemp.createTemp('bodytmi-aggregation-');
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
  int day,
  List<String?> values, {
  String? run,
}) async {
  final training = StoredTrainingService(store);
  var s = run == null
      ? await training.start(id, 'aggregate', 1, instant(day))
      : await ProgramService(store).start(
          run,
          (await ProgramService(store).run(run)).contentVersion,
          id,
          instant(day),
        );
  s = await training.edit(id, s.contentVersion, (s) {
    var i = 0;
    for (final set in s.sets) {
      final reps = set.role == 'warmup' ? '100' : values[i++];
      s = reps == null
          ? const TrainingService().skip(s, set.id, confirm: true)
          : const TrainingService().complete(s, set.id, {
              'reps': Quantity(reps, 'rep'),
            }, acceptSuggested: true);
    }
    return s.finish(instant(day).add(const Duration(hours: 1)));
  });
  return s;
}

Future<ProgressionDecision> _propose(
  TrainingStore store,
  String id,
  Map<String, Object?> rule,
) => StoredProgressionService(
  store,
).propose(id, 'movement', rule, ruleType: 'threshold');

void aggregationTests() {
  test(
    'numeric advancement selects all, any, greatest best, ordered last and K-of-N while retaining individual comparisons',
    () {
      for (final (mode, count, expected) in [
        ('all', null, 'hold'),
        ('any', null, 'advance'),
        ('best', null, 'advance'),
        ('last', null, 'hold'),
        ('kOfN', 2, 'hold'),
        ('kOfN', 1, 'advance'),
      ]) {
        final p = _evaluate(_rule(mode, count: count), ['8', '12', '10']);
        equal(p.outcome, expected);
        equal(p.assessment!.reachesThreshold.join(','), 'false,true,false');
        equal(p.assessment!.belowMinimum.join(','), 'false,false,false');
        equal(p.failedSessions, 0);
      }
      equal(_evaluate(_rule('last'), ['12', '8', '12']).outcome, 'advance');
      equal(
        _evaluate(_rule('kOfN', count: 2), ['12', '8', '12']).outcome,
        'advance',
      );
      equal(
        _evaluate(_rule('best'), [
          '8',
          '12',
          '10',
        ]).assessment!.selected!.value.toString(),
        '12',
      );
    },
  );
  test(
    'failure gating precedes every advancement selection and incomplete work remains unknown even with qualifying or failed observations',
    () {
      for (final mode in ['all', 'any', 'best', 'last', 'total', 'kOfN']) {
        final rule = _rule(mode, count: mode == 'kOfN' ? 1 : null);
        final p = _evaluate(rule, ['1', '12', '12'], failures: 0);
        equal(p.outcome, 'failed');
        equal(p.failedSessions, 1);
        equal(p.assessment!.eligible, false);
        for (final values in <List<String?>>[
          [],
          [null],
          ['1', null, '12'],
          ['12', '12', null],
        ]) {
          final unknown = _evaluate(rule, values, failures: 1);
          equal(unknown.outcome, 'unknown');
          equal(unknown.failedSessions, 1);
          equal(unknown.assessment!.selected, null);
          equal(unknown.assessment!.total, null);
        }
      }
    },
  );
  test(
    'total uses exact canonical arithmetic and failure totals can have a distinct scope from last-set thresholds',
    () {
      final duration = {
        ..._rule('total'),
        'metric': 'duration',
        'minimum': {'value': '2', 'unit': 's'},
        'threshold': {'value': '10', 'unit': 's'},
        'resets': {
          'duration': {'value': '2', 'unit': 's'},
        },
      };
      final p = ThresholdRule.fromJson(duration).evaluate(
        current: metrics({'mass': ('10', 'kg'), 'duration': ('5', 's')}),
        results: [
          metrics({'duration': ('0.1', 'min')}),
          metrics({'duration': ('4000', 'ms')}),
        ],
      );
      equal(p.outcome, 'advance');
      equal(p.assessment!.total!.value.toString(), '10');
      final rule = _rule('last', totalFailure: true);
      equal(_evaluate(rule, ['1', '2', '12']).outcome, 'advance');
      equal(_evaluate(rule, ['1', '1', '12']).outcome, 'failed');
      equal(_evaluate(rule, ['6', '6', '6']).outcome, 'hold');
      final zero = _evaluate(_rule('total', totalFailure: true), [
        '0',
        '0',
        '0',
      ]);
      equal(zero.outcome, 'failed');
      equal(zero.assessment!.total!.value.toString(), '0');
    },
  );
  test(
    'aggregation rejects impossible counts, ambiguous options, incompatible dimensions and resource overflow',
    () {
      for (final policy in <Object?>[
        null,
        {'mode': 'median'},
        {'mode': 'kOfN'},
        {'mode': 'kOfN', 'count': 0},
        {'mode': 'kOfN', 'count': 1.5},
        {'mode': 'kOfN', 'count': 10001},
        {'mode': 'any', 'count': 1},
        {'mode': 'all', 'extra': true},
      ]) {
        rejects(
          () =>
              ThresholdRule.fromJson({..._rule('all'), 'aggregation': policy}),
        );
      }
      rejects(
        () => ThresholdRule.fromJson({
          ..._rule('all'),
          'failureAggregation': {'mode': 'any'},
        }),
      );
      rejects(() => _evaluate(_rule('kOfN', count: 4), ['12', '12', '12']));
      rejects(
        () => ThresholdRule.fromJson({
          ..._rule('total'),
          'minimum': {'value': '5', 'unit': 'kg'},
          'threshold': {'value': '18', 'unit': 'kg'},
        }),
      );
      rejects(
        () => ThresholdRule.fromJson(_rule('any')).evaluate(
          current: _current,
          results: [
            metrics({'reps': ('12', 's')}),
          ],
        ),
      );
      rejects(() => _evaluate(_rule('total'), List.filled(10001, '12')));
      rejects(
        () => ThresholdRule.fromJson({
          ..._rule('all'),
          'minimum': {'value': '13', 'unit': 'rep'},
        }),
      );
      final p = _evaluate(_rule('all'), ['12']);
      try {
        p.assessment!.values.clear();
        throw StateError('Mutable evidence');
      } on UnsupportedError {
        /* Expected. */
      }
    },
  );
  test(
    'legacy all-required proposals retain their JSON shape and vector classification is shared without dropping unequal targets',
    () {
      final rule = _rule('all')..remove('aggregation');
      final legacy = _evaluate(rule, ['12', '12', '12']);
      check(!legacy.toJson().containsKey('assessment'));
      final explicit = ThresholdRule.fromJson(_rule('any')).evaluateVector(
        currentSets: [
          _current,
          {..._current, 'mass': Quantity('10.5', 'kg')},
        ],
        results: _results(['8', '12']),
      );
      equal(explicit.first.nextValues['mass']!.value.toString(), '11');
      equal(explicit.last.nextValues['mass']!.value.toString(), '11.5');
      check(identical(explicit.first.assessment, explicit.last.assessment));
      equal(explicit.first.assessment!.values.length, 2);
    },
  );
  test(
    'stored last-set advancement excludes warmups, resets only on acceptance and cannot replay after decline or correction',
    () => _withStore((store, dir) async {
      final rule = {
        ..._rule('last'),
        'coordination': {
          'mode': 'weighted',
          'order': ['mass', 'mass'],
        },
      };
      final service = StoredProgressionService(store);
      final first = await _finish(store, 'one', 1, ['8', '8', '12']);
      final p = await _propose(store, first.id, rule);
      equal(p.proposal.outcome, 'advance');
      equal(p.proposal.assessment!.values.length, 3);
      equal(p.proposal.assessment!.selected!.value.toString(), '12');
      final d = await service.accept(first.id, 'movement', p.version, _at(1));
      equal(d.nextSets.first['mass']!.value.toString(), '11');
      equal(d.cursor, 1);
      final second = await _finish(store, 'two', 2, ['5', '5', '12']);
      equal(second.sets.first.suggested['mass']!.value.toString(), '10');
      equal(second.sets.last.suggested['mass']!.value.toString(), '11');
      equal(second.sets.last.suggested['reps']!.value.toString(), '5');
      final q = await _propose(store, second.id, rule);
      equal(
        (await service.decline(
          second.id,
          'movement',
          q.version,
          _at(2),
        )).cursor,
        1,
      );
      await StoredTrainingService(store).edit(
        second.id,
        second.contentVersion,
        (s) => const TrainingService().complete(s, s.sets.last.id, {
          'reps': Quantity('1', 'rep'),
        }, acceptSuggested: true),
      );
      final retry = await _propose(store, second.id, rule);
      equal(retry.status, 'declined');
      equal(retry.proposal.assessment!.selected!.value.toString(), '12');
      final third = await _finish(store, 'three', 3, ['5', '5', '5']);
      equal(third.sets.last.suggested['mass']!.value.toString(), '11');
      equal((await _propose(store, third.id, rule)).proposal.outcome, 'hold');
      await store.archive();
    }),
  );
  test(
    'aggregate eligibility cannot bypass an atomic vector bound or changed controlled actuals',
    () => _withStore((store, dir) async {
      var s = await _finish(store, 'one', 1, ['8', '8', '12']);
      s = await StoredTrainingService(store).edit(s.id, s.contentVersion, (s) {
        final old = s.sets.last;
        return s.replaceSet(
          TrainingSet(
            id: old.id,
            slotId: old.slotId,
            role: old.role,
            ordinal: old.ordinal,
            suggested: {...old.suggested, 'mass': Quantity('10.5', 'kg')},
            actuals: {...old.actuals, 'mass': Quantity('10.5', 'kg')},
            status: old.status,
            contentVersion: old.contentVersion + 1,
          ),
        );
      });
      final rule = {
        ..._rule('any'),
        'maximums': {
          'mass': {'value': '11', 'unit': 'kg'},
        },
      };
      final blocked = await _propose(store, s.id, rule);
      equal(blocked.proposal.outcome, 'blocked');
      equal(blocked.proposal.assessment!.eligible, true);
      equal(blocked.proposal.nextSets.first['mass']!.value.toString(), '10');
      equal(blocked.proposal.nextSets.last['mass']!.value.toString(), '10.5');
      equal(blocked.proposal.nextSets.first['reps']!.value.toString(), '8');
      s = await StoredTrainingService(store).edit(
        s.id,
        s.contentVersion,
        (s) => const TrainingService().complete(s, s.sets.last.id, {
          'mass': Quantity('11', 'kg'),
          'reps': Quantity('12', 'rep'),
        }, acceptSuggested: true),
      );
      final review = await _propose(store, s.id, rule);
      equal(review.proposal.outcome, 'review');
      equal(review.proposal.assessment!.eligible, true);
      await _fails(
        StoredProgressionService(
          store,
        ).accept(s.id, 'movement', review.version, _at(1)),
      );
      await store.archive();
    }),
  );
  test(
    'total failure counters and deload receipts persist independently across simultaneous runs',
    () => _withStore((store, dir) async {
      final programs = ProgramService(store);
      await programs.publish(
        ProgramDefinition.fromJson({
          'id': 'shared',
          'name': 'Independent',
          'plan': {
            'id': 'day',
            'type': 'day',
            'templateId': 'aggregate',
            'revision': 1,
          },
        }),
        0,
      );
      for (final id in ['strength', 'cardio'])
        await programs.create(id, 'shared', 1, instant(1));
      final rule = _rule('total', totalFailure: true);
      final service = StoredProgressionService(store);
      for (final (day, values, expected, count) in [
        (1, ['8', '5', '4'], 'hold', 0),
        (2, ['5', '4', '3'], 'failed', 1),
        (3, ['4', '4', '4'], 'deload', 0),
      ]) {
        final s = await _finish(store, 's$day', day, values, run: 'strength');
        final p = await _propose(store, s.id, rule);
        equal(p.proposal.outcome, expected);
        final d = await service.accept(s.id, 'movement', p.version, _at(day));
        equal(d.failedSessions, count);
      }
      final s = await _finish(store, 'after', 4, [
        '6',
        '6',
        '6',
      ], run: 'strength');
      equal(s.sets.last.suggested['mass']!.value.toString(), '9');
      final c = await _finish(store, 'cardio', 5, [
        '6',
        '6',
        '6',
      ], run: 'cardio');
      equal(c.sets.last.suggested['mass']!.value.toString(), '10');
      final p = await _propose(store, c.id, rule);
      equal(p.previousSequence, 0);
      equal(p.previousFailures, 0);
      equal(p.proposal.outcome, 'advance');
      await store.archive();
    }),
  );
  test(
    'pending aggregate evidence invalidates on edits and forged individual or aggregate classifications cannot be restored',
    () => _withStore((store, dir) async {
      var s = await _finish(store, 'one', 1, ['8', '8', '12']);
      final rule = _rule('last');
      final service = StoredProgressionService(store);
      final p = await _propose(store, s.id, rule);
      s = await StoredTrainingService(store).edit(
        s.id,
        s.contentVersion,
        (s) => const TrainingService().complete(s, s.sets.last.id, {
          'reps': Quantity('8', 'rep'),
        }, acceptSuggested: true),
      );
      await _fails(service.accept(s.id, 'movement', p.version, _at(1)));
      final q = await _propose(store, s.id, rule);
      equal(q.version, p.version + 1);
      equal(q.proposal.outcome, 'hold');
      equal(q.proposal.assessment!.selected!.value.toString(), '8');
      for (final key in ['eligible', 'results']) {
        final j = copyJson(q.toJson());
        final a =
            (j['proposal'] as Map<String, Object?>)['assessment']
                as Map<String, Object?>;
        if (key == 'eligible') {
          a[key] = true;
        } else {
          (a[key] as List<Object?>).removeLast();
        }
        rejects(() => ProgressionDecision.fromJson(j));
      }
      await service.accept(s.id, 'movement', q.version, _at(1));
      final next = await _finish(store, 'two', 2, ['12', '12', '12']);
      await _fails(_propose(store, next.id, _rule('any')));
      await store.archive();
    }),
  );
  test(
    'v14 threshold receipts migrate unchanged while v15 native and logical restoration preserve pending aggregate evidence and reject old labels',
    () => _withStore((store, dir) async {
      final s = await _finish(store, 'one', 1, ['8', '8', '12']);
      final legacyRule = _rule('all')..remove('aggregation');
      await _propose(store, s.id, legacyRule);
      final before = canonicalJson((await store.archive()).toJson());
      await store.backup('$dir/old');
      await store.close();
      final db = sqlite3.open('$dir/old/database.sqlite');
      db.execute('DROP TABLE derived_target_graphs');
      db.execute('DROP TABLE IF EXISTS repeat_checkpoints');
      db.execute('DROP TABLE IF EXISTS window_checkpoints');
      db.execute('DROP TABLE IF EXISTS progression_reconciliations');
      db.execute('DROP TABLE IF EXISTS lever_link_revisions');
      db.execute('DROP TABLE IF EXISTS shared_lever_applications');
      db.execute('DROP TABLE IF EXISTS link_retirement_anchors');
      db.execute('DROP TABLE IF EXISTS program_upgrade_receipts');
      db.execute('DROP TABLE IF EXISTS exercise_revisions');
      db.execute('DROP TABLE IF EXISTS implementation_revisions');
      db.execute('DROP TABLE IF EXISTS equipment_revisions');
      db.execute('DROP TABLE IF EXISTS gym_revisions');
      db.execute('DROP TABLE IF EXISTS equipment_instance_revisions');
      db.userVersion = 14;
      db.close();
      equal(NativeBackup.validateDatabase('$dir/old/database.sqlite'), 14);
      final upgraded = await TrainingStore.open('$dir/old/database.sqlite');
      try {
        equal(canonicalJson((await upgraded.archive()).toJson()), before);
        equal(
          (await upgraded.backup('$dir/upgraded'))['databaseSchemaVersion'],
          63,
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
          j['format'] = 'bodytmi-logical-export/14';
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
        // A pending unapproved rule can be replaced; terminal lineage cannot.
        final p = await _propose(active, s.id, _rule('last'));
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
            final d = await StoredProgressionService(
              restored,
            ).accept(s.id, 'movement', p.version, _at(1));
            equal(d.nextSets.first['mass']!.value.toString(), '11');
            equal(d.proposal.assessment!.selected!.value.toString(), '12');
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
        forged.execute('DROP TABLE IF EXISTS shared_lever_applications');
        forged.execute('DROP TABLE IF EXISTS link_retirement_anchors');
        forged.execute('DROP TABLE IF EXISTS program_upgrade_receipts');
        forged.execute('DROP TABLE IF EXISTS exercise_revisions');
        forged.execute('DROP TABLE IF EXISTS implementation_revisions');
        forged.execute('DROP TABLE IF EXISTS equipment_revisions');
        forged.execute('DROP TABLE IF EXISTS gym_revisions');
        forged.execute('DROP TABLE IF EXISTS equipment_instance_revisions');
        forged.userVersion = 14;
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
    'native pure and stored CLI share assessment semantics and reject malformed aggregation without internal errors',
    () => _withStore((store, dir) async {
      final s = await _finish(store, 'one', 1, ['8', '8', '12']);
      await store.close();
      final rule = _rule('last');
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

      final pure = await cmd('progression evaluate', {
        'rule': rule,
        'current': metricsToJson(_current),
        'results': [
          for (final r in _results(['8', '8', '12'])) metricsToJson(r!),
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
      equal(
        canonicalJson(pure['assessment']),
        canonicalJson(jsonObject(stored['proposal'], 'proposal')['assessment']),
      );
      final accepted = await cmd('progression accept', {
        ...request,
        'expectedVersion': stored['version'],
        'acceptedAt': _at(1).toIso8601String(),
      });
      equal(
        jsonObject(accepted['resolvedState'], 'state')['failedSessions'],
        0,
      );
      final bad = await invoke(
        ['progression', 'evaluate'],
        jsonEncode({
          'schemaVersion': 1,
          'rule': {
            ...rule,
            'aggregation': {'mode': 'kOfN', 'count': 4},
          },
          'current': metricsToJson(_current),
          'results': [
            metricsToJson(_results(['12']).single!),
          ],
        }),
      );
      check(bad.code != 0);
      equal(bad.output, '');
      check(!bad.error.contains('internal'));
    }),
  );
  test(
    'process death rolls back or commits aggregate approval with immutable evidence and retry never reapplies it',
    () => _withStore((store, dir) async {
      await _finish(store, 'one', 1, ['8', '8', '12']);
      await _propose(store, 'one', _rule('last'));
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
          equal(p.proposal.assessment!.selected!.value.toString(), '12');
          if (p.acceptedAt != null) {
            final retry = await service.accept(
              'one',
              'movement',
              p.version,
              _at(1),
            );
            equal(retry.sequence, 1);
            final next = await _finish(recovered, 'two', 2, ['8', '8', '12']);
            equal(next.sets.last.suggested['mass']!.value.toString(), '11');
          }
          await recovered.archive();
        } finally {
          await recovered.close();
        }
      }
    }),
  );
}
