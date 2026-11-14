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
  'elapsed': ('300', 's'),
  'mass': ('10', 'kg'),
  'distance': ('1000', 'm'),
});
Map<String, Object?> _rule({
  String direction = 'lower',
  String mode = 'all',
  int? count,
}) => {
  'metric': 'elapsed',
  'performance': {
    'direction': direction,
    'failureLimit': {
      'value': direction == 'lower' ? '300' : '240',
      'unit': 's',
    },
    'advancementLimit': {
      'value': direction == 'lower' ? '240' : '300',
      'unit': 's',
    },
  },
  'increments': {
    'mass': {'value': '1', 'unit': 'kg'},
  },
  'resets': {
    'elapsed': {'value': '300', 'unit': 's'},
    'distance': {'value': '1000', 'unit': 'm'},
  },
  if (mode != 'all')
    'aggregation': {'mode': mode, if (count != null) 'count': count},
  'deloadAfter': 2,
  'deloadMetrics': ['mass'],
};
List<Metrics?> _results(List<String?> values) => [
  for (final v in values) v == null ? null : metrics({'elapsed': (v, 's')}),
];
ProgressionProposal _eval(
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
  'id': 'performance',
  'name': 'Explicit performance direction',
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
  final dir = await Directory.systemTemp.createTemp('bodytmi-performance-');
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
  List<String?> values = const ['240', '240'],
  String? run,
}) async {
  final training = StoredTrainingService(store);
  final s = run == null
      ? await training.start(id, 'performance', 1, instant(day))
      : await ProgramService(store).start(
          run,
          (await ProgramService(store).run(run)).contentVersion,
          id,
          instant(day),
        );
  return training.edit(id, s.contentVersion, (s) {
    var i = 0;
    for (final set in s.sets) {
      final value = set.role == 'warmup' ? '1000' : values[i++];
      s = value == null
          ? const TrainingService().skip(s, set.id, confirm: true)
          : const TrainingService().complete(s, set.id, {
              'elapsed': Quantity(value, 's'),
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

void performanceDirectionTests() {
  test(
    'lower-is-better performance applies inclusive gates independently of the increasing controlled lever',
    () {
      for (final (values, outcome) in [
        (['240', '230'], 'advance'),
        (['300', '260'], 'hold'),
        (['301', '200'], 'failed'),
      ]) {
        final p = _eval(_rule(), values);
        equal(p.outcome, outcome);
        equal(p.assessment!.direction, 'lower');
        equal(p.assessment!.failureLimit.value.toString(), '300');
        if (outcome == 'advance') {
          equal(p.nextValues['mass']!.value.toString(), '11');
          equal(p.nextValues['elapsed']!.value.toString(), '300');
        }
      }
      final direct = ThresholdAssessment.evaluate(
        advancement: ResultAggregation.fromJson({'mode': 'all'}),
        failure: ResultAggregation.fromJson({'mode': 'all'}, failure: true),
        metric: 'elapsed',
        minimum: Quantity('300', 's'),
        threshold: Quantity('240', 's'),
        results: _results(['240']),
        direction: 'lower',
      );
      check(direct.toJson().containsKey('performance'));
      final zero = _eval(_rule(), ['0', '0']);
      equal(zero.outcome, 'advance');
      equal(zero.assessment!.values.first!.value.toString(), '0');
      final rule = ThresholdRule.fromJson(_rule());
      equal(rule.failureLimit.value.toString(), '300');
      equal(rule.advancementLimit.value.toString(), '240');
    },
  );
  test(
    'lower best selects the smallest observation and all/any/last/K-of-N retain failure precedence and completeness',
    () {
      for (final (mode, count, expected) in [
        ('all', null, 'hold'),
        ('any', null, 'advance'),
        ('best', null, 'advance'),
        ('last', null, 'hold'),
        ('kOfN', 1, 'advance'),
        ('kOfN', 2, 'hold'),
      ]) {
        final rule = _rule(mode: mode, count: count);
        final p = _eval(rule, ['280', '240', '250']);
        equal(p.outcome, expected);
        if (mode == 'best')
          equal(p.assessment!.selected!.value.toString(), '240');
        equal(_eval(rule, ['301', '200', '200']).outcome, 'failed');
        final missing = _eval(rule, ['200', null, '301'], failures: 1);
        equal(missing.outcome, 'unknown');
        equal(missing.failedSessions, 1);
      }
      equal(
        _eval(_rule(mode: 'last'), ['280', '260', '240']).outcome,
        'advance',
      );
      equal(_eval(_rule(), [], failures: 1).outcome, 'unknown');
      final deload = _eval(_rule(), ['301', '320'], failures: 1);
      equal(deload.outcome, 'deload');
      equal(deload.nextValues['mass']!.value.toString(), '9');
    },
  );
  test(
    'lower total predicates use exact compatible units and allow distinct total failure and last-result advancement scopes',
    () {
      final total = {
        ..._rule(mode: 'total'),
        'failureAggregation': {'mode': 'total'},
        'performance': {
          'direction': 'lower',
          'failureLimit': {'value': '700', 'unit': 's'},
          'advancementLimit': {'value': '600', 'unit': 's'},
        },
      };
      equal(_eval(total, ['200', '200', '200']).outcome, 'advance');
      equal(_eval(total, ['250', '250', '250']).outcome, 'failed');
      equal(_eval(total, ['220', '220', '220']).outcome, 'hold');
      final last = {
        ...total,
        'aggregation': {'mode': 'last'},
        'performance': {
          'direction': 'lower',
          'failureLimit': {'value': '700', 'unit': 's'},
          'advancementLimit': {'value': '200', 'unit': 's'},
        },
      };
      equal(_eval(last, ['250', '250', '200']).outcome, 'advance');
      equal(_eval(last, ['251', '250', '200']).outcome, 'failed');
      final p = ThresholdRule.fromJson(_rule()).evaluate(
        current: _current,
        results: [
          metrics({'elapsed': ('4', 'min')}),
          metrics({'elapsed': ('240000', 'ms')}),
        ],
      );
      equal(p.outcome, 'advance');
    },
  );
  test(
    'explicit performance bounds reject mixed legacy syntax, wrong ordering/dimensions and unknown directions while legacy output remains unchanged',
    () {
      for (final performance in <Object?>[
        null,
        {'direction': 'faster'},
        {'direction': 'lower'},
        {
          'direction': 'lower',
          'failureLimit': {'value': '200', 'unit': 's'},
          'advancementLimit': {'value': '240', 'unit': 's'},
        },
        {
          'direction': 'lower',
          'failureLimit': {'value': '300', 'unit': 'kg'},
          'advancementLimit': {'value': '240', 'unit': 's'},
        },
      ]) {
        rejects(
          () =>
              ThresholdRule.fromJson({..._rule(), 'performance': performance}),
        );
      }
      rejects(
        () => ThresholdRule.fromJson({
          ..._rule(),
          'minimum': {'value': '240', 'unit': 's'},
        }),
      );
      rejects(
        () => ThresholdRule.fromJson({
          ..._rule(),
          'threshold': {'value': '300', 'unit': 's'},
        }),
      );
      final legacy = _rule()..remove('performance');
      legacy['minimum'] = {'value': '240', 'unit': 's'};
      legacy['threshold'] = {'value': '300', 'unit': 's'};
      final old = _eval(legacy, ['300', '300']);
      final explicit = _eval(_rule(direction: 'higher'), ['300', '300']);
      equal(old.outcome, explicit.outcome);
      equal(
        canonicalJson(metricsToJson(old.nextValues)),
        canonicalJson(metricsToJson(explicit.nextValues)),
      );
      check(!old.toJson().containsKey('assessment'));
      equal(old.reason, 'Every required upper threshold reached (inclusive).');
      check(explicit.toJson().containsKey('assessment'));
      rejects(
        () => _eval(_rule(), [
          '240',
          '240',
        ]).assessment!.values.first!.compareTo(Quantity('1', 'kg')),
      );
    },
  );
  test(
    'stored faster-performance approvals, declines and corrections preserve warmups, target resets and one application identity',
    () => _withStore((store, dir) async {
      final service = StoredProgressionService(store);
      final rule = _rule();
      final first = await _finish(store, 'one', 1);
      final p = await _propose(store, first.id, rule);
      equal(p.proposal.outcome, 'advance');
      equal(p.proposal.assessment!.values.length, 2);
      await service.accept(first.id, 'movement', p.version, _at(1));
      final second = await _finish(store, 'two', 2);
      equal(second.sets.first.suggested['mass']!.value.toString(), '10');
      equal(second.sets.last.suggested['mass']!.value.toString(), '11');
      equal(second.sets.last.suggested['elapsed']!.value.toString(), '300');
      final q = await _propose(store, second.id, rule);
      final d = await service.decline(second.id, 'movement', q.version, _at(2));
      equal(d.nextSets.first['mass']!.value.toString(), '11');
      await StoredTrainingService(store).edit(
        second.id,
        second.contentVersion,
        (s) => const TrainingService().complete(s, s.sets.last.id, {
          'elapsed': Quantity('301', 's'),
        }, acceptSuggested: true),
      );
      equal((await _propose(store, second.id, rule)).status, 'declined');
      final next = await _finish(store, 'three', 3);
      final r = await _propose(store, next.id, rule);
      final applied = await service.accept(
        next.id,
        'movement',
        r.version,
        _at(3),
      );
      equal(applied.nextSets.first['mass']!.value.toString(), '12');
      equal(applied.sequence, 3);
      equal(
        (await service.accept(next.id, 'movement', r.version, _at(3))).sequence,
        3,
      );
      await store.archive();
    }),
  );
  test(
    'changed controlled work requires review, pending faster inputs stale on edits and forged predicate evidence is rejected',
    () => _withStore((store, dir) async {
      var s = await _finish(store, 'one', 1);
      final service = StoredProgressionService(store);
      final rule = _rule();
      final p = await _propose(store, s.id, rule);
      s = await StoredTrainingService(store).edit(
        s.id,
        s.contentVersion,
        (s) => const TrainingService().complete(s, s.sets.last.id, {
          'elapsed': Quantity('240', 's'),
          'distance': Quantity('999', 'm'),
        }, acceptSuggested: true),
      );
      await _fails(service.accept(s.id, 'movement', p.version, _at(1)));
      final q = await _propose(store, s.id, rule);
      equal(q.proposal.outcome, 'review');
      await _fails(service.accept(s.id, 'movement', q.version, _at(1)));
      s = await StoredTrainingService(store).edit(
        s.id,
        s.contentVersion,
        (s) => const TrainingService().complete(s, s.sets.last.id, {
          'elapsed': Quantity('301', 's'),
        }, acceptSuggested: true),
      );
      final r = await _propose(store, s.id, rule);
      equal(r.proposal.outcome, 'failed');
      equal(r.proposal.failedSessions, 1);
      final forged = copyJson(r.toJson());
      final assessment =
          (forged['proposal'] as Map<String, Object?>)['assessment']
              as Map<String, Object?>;
      (assessment['performance'] as Map<String, Object?>)['direction'] =
          'higher';
      rejects(() => ProgressionDecision.fromJson(forged));
      await service.decline(s.id, 'movement', r.version, _at(1));
      final next = await _finish(store, 'two', 2);
      await _fails(_propose(store, next.id, _rule(direction: 'higher')));
      await store.archive();
    }),
  );
  test(
    'simultaneous runs can use opposite performance directions without sharing targets or failed counters',
    () => _withStore((store, dir) async {
      final programs = ProgramService(store);
      await programs.publish(
        ProgramDefinition.fromJson({
          'id': 'shared',
          'name': 'Independent performance policies',
          'plan': {
            'id': 'day',
            'type': 'day',
            'templateId': 'performance',
            'revision': 1,
          },
        }),
        0,
      );
      for (final run in ['strength', 'cardio'])
        await programs.create(run, 'shared', 1, instant(1));
      for (final (day, run, direction, values) in [
        (1, 'strength', 'higher', ['300', '300']),
        (2, 'cardio', 'lower', ['240', '240']),
      ]) {
        final s = await _finish(store, run, day, run: run, values: values);
        final p = await _propose(store, s.id, _rule(direction: direction));
        equal(p.proposal.outcome, 'advance');
        await StoredProgressionService(
          store,
        ).accept(s.id, 'movement', p.version, _at(day));
      }
      final strength = await _finish(
        store,
        'strength-next',
        3,
        run: 'strength',
        values: ['310', '310'],
      );
      equal(
        (await _propose(
          store,
          strength.id,
          _rule(direction: 'higher'),
        )).proposal.outcome,
        'advance',
      );
      final cardio = await _finish(
        store,
        'cardio-next',
        4,
        run: 'cardio',
        values: ['310', '310'],
      );
      final p = await _propose(store, cardio.id, _rule());
      equal(p.proposal.outcome, 'failed');
      equal(p.previousFailures, 0);
      await store.archive();
    }),
  );
  test(
    'v19 legacy higher thresholds migrate unchanged and v20 restores preserve pending lower predicates while older labels reject them',
    () => _withStore((store, dir) async {
      final s = await _finish(store, 'one', 1);
      final legacyRule = _rule()..remove('performance');
      legacyRule['minimum'] = {'value': '240', 'unit': 's'};
      legacyRule['threshold'] = {'value': '300', 'unit': 's'};
      await _propose(store, s.id, legacyRule);
      final before = canonicalJson((await store.archive()).toJson());
      await store.backup('$dir/old');
      await store.close();
      final old = sqlite3.open('$dir/old/database.sqlite');
      old.execute('DROP TABLE derived_target_graphs');
      old.execute('DROP TABLE IF EXISTS repeat_checkpoints');
      old.execute('DROP TABLE IF EXISTS window_checkpoints');
      old.execute('DROP TABLE IF EXISTS progression_reconciliations');
      old.execute('DROP TABLE IF EXISTS lever_link_revisions');
      old.execute('DROP TABLE IF EXISTS shared_lever_applications');
      old.execute('DROP TABLE IF EXISTS link_retirement_anchors');
      old.execute('DROP TABLE IF EXISTS program_upgrade_receipts');
      old.execute('DROP TABLE IF EXISTS exercise_revisions');
      old.execute('DROP TABLE IF EXISTS implementation_revisions');
      old.execute('DROP TABLE IF EXISTS equipment_revisions');
      old.execute('DROP TABLE IF EXISTS gym_revisions');
      old.execute('DROP TABLE IF EXISTS equipment_instance_revisions');
      old.execute('DROP TABLE IF EXISTS imported_sessions');
      old.userVersion = 19;
      old.close();
      equal(NativeBackup.validateDatabase('$dir/old/database.sqlite'), 19);
      final upgraded = await TrainingStore.open('$dir/old/database.sqlite');
      try {
        equal(canonicalJson((await upgraded.archive()).toJson()), before);
        equal(
          (await upgraded.backup('$dir/upgraded'))['databaseSchemaVersion'],
          65,
        );
      } finally {
        await upgraded.close();
      }
      final active = await TrainingStore.open('$dir/db.sqlite');
      try {
        Future<void> relabel(String file) async {
          final j = jsonObject(
            jsonDecode(await File(file).readAsString()),
            'logical',
          );
          j['format'] = 'bodytmi-logical-export/19';
          j.remove('sha256');
          j['sha256'] = sha256
              .convert(utf8.encode(canonicalJson(j)))
              .toString();
          await File(file).writeAsString(jsonEncode(j));
        }

        await LogicalArchiveFiles.export(
          await active.archive(),
          '$dir/legacy.json',
        );
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
            equal(d.proposal.assessment!.direction, 'lower');
            equal(d.nextSets.first['mass']!.value.toString(), '11');
            equal(
              (await service.accept(
                s.id,
                'movement',
                p.version,
                _at(1),
              )).sequence,
              1,
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
        forged.execute('DROP TABLE IF EXISTS shared_lever_applications');
        forged.execute('DROP TABLE IF EXISTS link_retirement_anchors');
        forged.execute('DROP TABLE IF EXISTS program_upgrade_receipts');
        forged.execute('DROP TABLE IF EXISTS exercise_revisions');
        forged.execute('DROP TABLE IF EXISTS implementation_revisions');
        forged.execute('DROP TABLE IF EXISTS equipment_revisions');
        forged.execute('DROP TABLE IF EXISTS gym_revisions');
        forged.execute('DROP TABLE IF EXISTS equipment_instance_revisions');
        forged.execute('DROP TABLE IF EXISTS imported_sessions');
        forged.userVersion = 19;
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
    'pure and stored native CLI expose direction-neutral failure comparisons and matching lower predicate evidence',
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

      final pure = await cmd('progression evaluate', {
        'rule': _rule(),
        'current': metricsToJson(_current),
        'results': [
          for (final r in _results(['240', '240'])) metricsToJson(r!),
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
        'rule': _rule(),
      });
      equal(
        canonicalJson(jsonObject(stored['proposal'], 'proposal')['assessment']),
        canonicalJson(pure['assessment']),
      );
      final first =
          (jsonObject(pure['assessment'], 'assessment')['results']
                      as List<Object?>)
                  .first
              as Map<String, Object?>;
      equal(first['failsFailureLimit'], false);
      check(!first.containsKey('belowMinimum'));
      final bad = await invoke(
        ['progression', 'propose'],
        jsonEncode({
          'schemaVersion': 1,
          ...request,
          'ruleType': 'threshold',
          'rule': {
            ..._rule(),
            'minimum': {'value': '1', 'unit': 's'},
          },
        }),
      );
      check(bad.code != 0);
      equal(bad.output, '');
      check(!bad.error.contains('internal'));
    }),
  );
  test(
    'process death commits or rolls back a lower-performance approval and retry cannot grant a fresh increment',
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
          equal(p.proposal.assessment!.direction, 'lower');
          if (p.acceptedAt != null) {
            equal(
              (await service.accept(
                'one',
                'movement',
                p.version,
                _at(1),
              )).sequence,
              1,
            );
            final next = await _finish(recovered, 'two', 2);
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
