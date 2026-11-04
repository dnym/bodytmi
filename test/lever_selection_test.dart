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
Map<String, Object?> _rule({
  String mode = 'priority',
  String chosen = 'mass',
}) => {
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
    'assistance': {'value': '38', 'unit': 'kg'},
    'supportHeight': {'value': '0.1', 'unit': 'm'},
  },
  'maximums': {
    'assistance': {'value': '60', 'unit': 'kg'},
    'mass': {'value': '11', 'unit': 'kg'},
  },
  'resets': {
    'reps': {'value': '5', 'unit': 'rep'},
  },
  'coordination': mode == 'chosen'
      ? {'mode': mode, 'metric': chosen}
      : {
          'mode': mode,
          'order': ['assistance', 'mass', 'supportHeight'],
        },
  'deloadAfter': 2,
  'deloadMetrics': ['assistance', 'mass', 'supportHeight'],
};
ProgressionProposal _eval(
  Map<String, Object?> rule, {
  Metrics? current,
  String? reps = '8',
  int failures = 0,
}) => ThresholdRule.fromJson(rule).evaluate(
  current: current ?? _current,
  results: [
    reps == null ? null : metrics({'reps': (reps, 'rep')}),
  ],
  failedSessions: failures,
);
Future<void> _fails(Future<Object?> action) =>
    expectLater(action, throwsA(isA<BodyTmiException>()));
DateTime _at(int day) => instant(day).add(const Duration(hours: 2));
WorkoutDefinition _definition() => WorkoutDefinition.fromJson({
  'id': 'selection',
  'name': 'Vector-wide lever selection',
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
  final dir = await Directory.systemTemp.createTemp('bodytmi-selection-');
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
      ? await training.start(id, 'selection', 1, instant(day))
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

void leverSelectionTests() {
  test(
    'chosen coordination changes exactly its configured lever and holds without fallback when that lever is bounded',
    () {
      final p = _eval(_rule(mode: 'chosen'));
      equal(p.outcome, 'advance');
      equal(p.cursor, 0);
      equal(p.nextValues['mass']!.value.toString(), '11');
      equal(p.nextValues['assistance']!.value.toString(), '40');
      equal(p.nextValues['supportHeight']!.value.toString(), '0.5');
      equal(p.nextValues['reps']!.value.toString(), '5');
      equal(p.coordination!.selectedMetric, 'mass');
      equal(p.coordination!.candidates.single.metric, 'mass');
      final blocked = _eval(_rule(mode: 'chosen', chosen: 'assistance'));
      equal(blocked.outcome, 'blocked');
      equal(blocked.coordination!.selectedMetric, null);
      equal(
        blocked.coordination!.candidates.single.blockedSets.single.ordinal,
        0,
      );
      equal(
        canonicalJson(metricsToJson(blocked.nextValues)),
        canonicalJson(metricsToJson(_current)),
      );
    },
  );
  test(
    'priority selects the first whole-vector applicable candidate afresh after each accepted numeric change',
    () {
      final p = _eval(_rule());
      equal(p.coordination!.selectedMetric, 'mass');
      equal(p.coordination!.candidates.length, 2);
      equal(p.coordination!.candidates.first.metric, 'assistance');
      check(
        p.coordination!.candidates.first.blockedSets.single.reason.contains(
          'lower',
        ),
      );
      final next = _eval(_rule(), current: p.nextValues);
      equal(next.outcome, 'advance');
      equal(next.coordination!.selectedMetric, 'supportHeight');
      equal(next.coordination!.candidates.length, 3);
      equal(next.cursor, 0);
      equal(next.nextValues['supportHeight']!.value.toString(), '0.45');
      final early = _eval({
        ..._rule(),
        'minimums': {
          'assistance': {'value': '35', 'unit': 'kg'},
        },
      });
      equal(early.coordination!.selectedMetric, 'assistance');
      equal(early.nextValues['assistance']!.value.toString(), '35');
    },
  );
  test(
    'priority never selects different levers for unequal sets and all blocked candidates hold every target with per-set explanations',
    () {
      final rule = {
        ..._rule(),
        'minimums': {
          'assistance': {'value': '35', 'unit': 'kg'},
        },
      };
      final current = [
        _current,
        {..._current, 'assistance': Quantity('38', 'kg')},
      ];
      final proposals = ThresholdRule.fromJson(rule).evaluateVector(
        currentSets: current,
        results: [
          metrics({'reps': ('8', 'rep')}),
          metrics({'reps': ('8', 'rep')}),
        ],
      );
      for (var i = 0; i < proposals.length; i++) {
        final p = proposals[i];
        equal(p.coordination!.selectedMetric, 'mass');
        equal(p.nextValues['mass']!.value.toString(), '11');
        equal(
          p.nextValues['assistance']!.compareTo(current[i]['assistance']!),
          0,
        );
        equal(p.coordination!.candidates.first.blockedSets.single.ordinal, 1);
      }
      check(
        identical(proposals.first.coordination, proposals.last.coordination),
      );
      final none = {
        ...rule,
        'minimums': {
          'assistance': {'value': '38', 'unit': 'kg'},
          'supportHeight': {'value': '0.5', 'unit': 'm'},
        },
        'maximums': {
          'mass': {'value': '10', 'unit': 'kg'},
        },
      };
      final blocked = ThresholdRule.fromJson(none).evaluateVector(
        currentSets: current,
        results: [
          metrics({'reps': ('8', 'rep')}),
        ],
      );
      for (var i = 0; i < blocked.length; i++) {
        equal(blocked[i].outcome, 'blocked');
        equal(blocked[i].coordination!.selectedMetric, null);
        equal(blocked[i].coordination!.candidates.length, 3);
        equal(
          canonicalJson(metricsToJson(blocked[i].nextValues)),
          canonicalJson(metricsToJson(current[i])),
        );
      }
    },
  );
  test(
    'failure, unknown, hold and deload bypass advancement candidate selection and do not grant a cursor',
    () {
      for (final (reps, failures, expected, nextFailures) in [
        ('1', 0, 'failed', 1),
        (null, 1, 'unknown', 1),
        ('6', 1, 'hold', 0),
        ('1', 1, 'deload', 0),
      ]) {
        final p = _eval(_rule(), reps: reps, failures: failures);
        equal(p.outcome, expected);
        equal(p.failedSessions, nextFailures);
        equal(p.cursor, 0);
        equal(p.coordination!.selectedMetric, null);
        equal(p.coordination!.candidates.length, 0);
        if (expected == 'deload') {
          equal(p.nextValues['assistance']!.value.toString(), '44');
          equal(p.nextValues['mass']!.value.toString(), '9');
        }
      }
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
      equal(blocked.coordination!.candidates.length, 0);
    },
  );
  test(
    'selection policies reject ambiguous configuration, impossible cursors, invalid input fallback and excessive candidate-set work',
    () {
      for (final coordination in <Object?>[
        {'mode': 'chosen'},
        {'mode': 'chosen', 'metric': 'absent'},
        {
          'mode': 'chosen',
          'metric': 'mass',
          'order': ['mass'],
        },
        {'mode': 'priority'},
        {'mode': 'priority', 'order': <Object?>[]},
        {
          'mode': 'priority',
          'order': ['mass', 'mass'],
        },
        {
          'mode': 'priority',
          'order': ['absent'],
        },
        {
          'mode': 'priority',
          'order': ['mass'],
          'metric': 'mass',
        },
        {
          'mode': 'roundRobin',
          'order': ['mass'],
          'metric': 'mass',
        },
      ]) {
        rejects(
          () => ThresholdRule.fromJson({
            ..._rule(),
            'coordination': coordination,
          }),
        );
      }
      rejects(
        () => ThresholdRule.fromJson(_rule()).evaluate(
          current: _current,
          results: [
            metrics({'reps': ('8', 'rep')}),
          ],
          cursor: 1,
        ),
      );
      rejects(
        () => _eval(_rule(), current: {..._current}..remove('assistance')),
      );
      final increments = {
        for (var i = 0; i < 1000; i++) 'lever$i': {'value': '1', 'unit': 'kg'},
      };
      final huge = ThresholdRule.fromJson({
        ..._rule(),
        'increments': increments,
        'directions': <String, Object?>{},
        'deloadMetrics': <Object?>[],
        'coordination': {'mode': 'priority', 'order': increments.keys.toList()},
      });
      final current = {
        ..._current,
        for (final key in increments.keys) key: Quantity('10', 'kg'),
      };
      rejects(
        () => huge.evaluateVector(
          currentSets: List.filled(101, current),
          results: [
            metrics({'reps': ('8', 'rep')}),
          ],
        ),
      );
      final p = _eval(_rule());
      try {
        p.coordination!.candidates.clear();
        throw StateError('Mutable candidate evidence');
      } on UnsupportedError {
        /* Expected. */
      }
    },
  );
  test(
    'existing all, round-robin and weighted proposal shapes retain their original coordinator semantics',
    () {
      for (final mode in ['all', 'roundRobin', 'weighted']) {
        final rule = {
          ..._rule(),
          'coordination': mode == 'all'
              ? {'mode': mode}
              : {
                  'mode': mode,
                  'order': ['mass', 'supportHeight'],
                },
        };
        final p = _eval(rule);
        equal(p.coordination, null);
        check(!p.toJson().containsKey('coordination'));
        equal(p.outcome, mode == 'all' ? 'blocked' : 'advance');
        equal(p.cursor, mode == 'all' ? 0 : 1);
      }
    },
  );
  test(
    'stored priority selection, decline and retry preserve unequal vectors, warmups and the same application identity',
    () => _withStore((store, dir) async {
      var s = await _finish(store, 'one', 1);
      s = await StoredTrainingService(store).edit(s.id, s.contentVersion, (s) {
        final old = s.sets.last;
        return s.replaceSet(
          TrainingSet(
            id: old.id,
            slotId: old.slotId,
            role: old.role,
            ordinal: old.ordinal,
            suggested: {...old.suggested, 'assistance': Quantity('38', 'kg')},
            actuals: {...old.actuals, 'assistance': Quantity('38', 'kg')},
            status: old.status,
            contentVersion: old.contentVersion + 1,
          ),
        );
      });
      final rule = _rule();
      final service = StoredProgressionService(store);
      final p = await _propose(store, s.id, rule);
      equal(p.proposal.coordination!.selectedMetric, 'mass');
      final d = await service.accept(s.id, 'movement', p.version, _at(1));
      equal(d.cursor, 0);
      equal(d.sequence, 1);
      final two = await _finish(store, 'two', 2);
      equal(two.sets.first.suggested['mass']!.value.toString(), '10');
      equal(two.sets.last.suggested['mass']!.value.toString(), '11');
      equal(two.sets.last.suggested['assistance']!.value.toString(), '38');
      final q = await _propose(store, two.id, rule);
      equal(q.proposal.coordination!.selectedMetric, 'supportHeight');
      final declined = await service.decline(
        two.id,
        'movement',
        q.version,
        _at(2),
      );
      equal(declined.nextSets.first['supportHeight']!.value.toString(), '0.5');
      equal(declined.sequence, 2);
      await StoredTrainingService(store).edit(
        two.id,
        two.contentVersion,
        (s) => const TrainingService().complete(s, s.sets.last.id, {
          'reps': Quantity('1', 'rep'),
        }, acceptSuggested: true),
      );
      equal((await _propose(store, two.id, rule)).status, 'declined');
      final three = await _finish(store, 'three', 3);
      final r = await _propose(store, three.id, rule);
      final applied = await service.accept(
        three.id,
        'movement',
        r.version,
        _at(3),
      );
      equal(applied.nextSets.first['supportHeight']!.value.toString(), '0.45');
      equal(applied.sequence, 3);
      equal(
        canonicalJson(
          (await service.accept(
            three.id,
            'movement',
            r.version,
            _at(3),
          )).toJson(),
        ),
        canonicalJson(applied.toJson()),
      );
      await store.archive();
    }),
  );
  test(
    'chosen and priority policies stay isolated by run, while stale inputs and forged candidate explanations are rejected',
    () => _withStore((store, dir) async {
      final programs = ProgramService(store);
      await programs.publish(
        ProgramDefinition.fromJson({
          'id': 'shared',
          'name': 'Separate selections',
          'plan': {
            'id': 'day',
            'type': 'day',
            'templateId': 'selection',
            'revision': 1,
          },
        }),
        0,
      );
      for (final run in ['strength', 'cardio'])
        await programs.create(run, 'shared', 1, instant(1));
      final chosen = _rule(mode: 'chosen');
      final priority = {
        ..._rule(),
        'minimums': {
          'assistance': {'value': '0', 'unit': 'kg'},
        },
      };
      for (final (day, run, rule, selected) in [
        (1, 'strength', chosen, 'mass'),
        (2, 'cardio', priority, 'assistance'),
      ]) {
        final s = await _finish(store, run, day, run: run);
        final p = await _propose(store, s.id, rule);
        final d = await StoredProgressionService(
          store,
        ).accept(s.id, 'movement', p.version, _at(day));
        equal(d.proposal.coordination!.selectedMetric, selected);
      }
      final s = await _finish(store, 'next', 3, run: 'cardio');
      final p = await _propose(store, s.id, priority);
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
      final q = await _propose(store, changed.id, priority);
      equal(q.proposal.outcome, 'review');
      await _fails(_propose(store, changed.id, chosen));
      for (final key in ['selectedMetric', 'candidates']) {
        final forged = copyJson(p.toJson());
        final coordination =
            (forged['proposal'] as Map<String, Object?>)['coordination']
                as Map<String, Object?>;
        if (key == 'selectedMetric') {
          coordination[key] = 'mass';
        } else {
          coordination[key] = [];
        }
        rejects(() => ProgressionDecision.fromJson(forged));
      }
      await store.archive();
    }),
  );
  test(
    'a reset bound shared by every priority candidate holds the full stored vector and resets a successful exposure counter once',
    () => _withStore((store, dir) async {
      final rule = {
        ..._rule(),
        'minimums': {
          'reps': {'value': '6', 'unit': 'rep'},
        },
      };
      final service = StoredProgressionService(store);
      final first = await _finish(store, 'one', 1, reps: '1');
      final p = await _propose(store, first.id, rule);
      await service.accept(first.id, 'movement', p.version, _at(1));
      final second = await _finish(store, 'two', 2);
      final q = await _propose(store, second.id, rule);
      equal(q.proposal.outcome, 'blocked');
      equal(q.proposal.coordination!.candidates.length, 3);
      equal(q.proposal.failedSessions, 0);
      final d = await service.accept(second.id, 'movement', q.version, _at(2));
      equal(d.sequence, 2);
      equal(d.failedSessions, 0);
      equal(d.nextSets.first['mass']!.value.toString(), '10');
      equal(d.nextSets.first['reps']!.value.toString(), '8');
      await store.archive();
    }),
  );
  test(
    'v16 rule receipts migrate unchanged and v17 native and logical restore preserve pending priority evidence while old labels reject it',
    () => _withStore((store, dir) async {
      final s = await _finish(store, 'one', 1);
      final oldRule = {
        ..._rule(),
        'coordination': {
          'mode': 'roundRobin',
          'order': ['mass', 'supportHeight'],
        },
      };
      await _propose(store, s.id, oldRule);
      final before = canonicalJson((await store.archive()).toJson());
      await store.backup('$dir/old');
      await store.close();
      final old = sqlite3.open('$dir/old/database.sqlite');
      old.execute('DROP TABLE derived_target_graphs');
      old.userVersion = 16;
      old.close();
      equal(NativeBackup.validateDatabase('$dir/old/database.sqlite'), 16);
      final upgraded = await TrainingStore.open('$dir/old/database.sqlite');
      try {
        equal(canonicalJson((await upgraded.archive()).toJson()), before);
        equal(
          (await upgraded.backup('$dir/upgraded'))['databaseSchemaVersion'],
          38,
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
          j['format'] = 'bodytmi-logical-export/16';
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
        final p = await _propose(active, s.id, _rule());
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
            equal(d.cursor, 0);
            equal(d.proposal.coordination!.selectedMetric, 'mass');
            equal(d.nextSets.first['mass']!.value.toString(), '11');
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
        forged.userVersion = 16;
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
    'native pure and stored selection CLI match and malformed chosen requests return validation errors',
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

      final rule = {
        ..._rule(),
        'minimums': {
          'assistance': {'value': '0', 'unit': 'kg'},
        },
      };
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
      final proposal = jsonObject(stored['proposal'], 'proposal');
      equal(
        canonicalJson(proposal['coordination']),
        canonicalJson(pure['coordination']),
      );
      final nextSets = proposal['nextSets'] as List<Object?>;
      equal(canonicalJson(nextSets.first), canonicalJson(pure['nextValues']));
      final d = await cmd('progression accept', {
        ...request,
        'expectedVersion': stored['version'],
        'acceptedAt': _at(1).toIso8601String(),
      });
      equal(jsonObject(d['resolvedState'], 'state')['cursor'], 0);
      final bad = await invoke(
        ['progression', 'propose'],
        jsonEncode({
          'schemaVersion': 1,
          ...request,
          'ruleType': 'threshold',
          'rule': {
            ...rule,
            'coordination': {'mode': 'chosen'},
          },
        }),
      );
      check(bad.code != 0);
      equal(bad.output, '');
      check(!bad.error.contains('internal'));
    }),
  );
  test(
    'process death rolls back or commits priority selection with the same candidate evidence and no duplicate application on retry',
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
          equal(p.status, mode.endsWith('commit') ? 'accepted' : 'pending');
          equal(p.proposal.coordination!.selectedMetric, 'mass');
          equal(
            p.proposal.coordination!.candidates.first.blockedSets.length,
            2,
          );
          if (p.acceptedAt != null) {
            final retry = await service.accept(
              'one',
              'movement',
              p.version,
              _at(1),
            );
            equal(retry.sequence, 1);
            equal(retry.cursor, 0);
            final next = await _finish(recovered, 'two', 2);
            equal(next.sets.last.suggested['mass']!.value.toString(), '11');
            equal(
              (await _propose(
                recovered,
                next.id,
                _rule(),
              )).proposal.coordination!.selectedMetric,
              'supportHeight',
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
