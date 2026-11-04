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

Map<String, Object?> _scale({List<int> values = const [5, 10, 15]}) => {
  'id': 'native-stack',
  'unit': 'lb',
  'ticks': [
    for (final v in values)
      {
        'id': 'p$v',
        'value': '$v',
        'labels': {
          'lb': '$v',
          'kg': v == 5
              ? '2.3'
              : v == 10
              ? '4.5'
              : '6.8',
        },
      },
  ],
};
final _current = metrics({
  'reps': ('8', 'rep'),
  'mass': ('10', 'lb'),
  'assistance': ('10', 'kg'),
});
Map<String, Object?> _rule({
  String mode = 'priority',
  Map<String, Object?>? scale,
}) => {
  'metric': 'reps',
  'minimum': {'value': '5', 'unit': 'rep'},
  'threshold': {'value': '8', 'unit': 'rep'},
  'increments': {
    'mass': {'value': '0.1', 'unit': 'lb'},
    'assistance': {'value': '1', 'unit': 'kg'},
  },
  'directions': {'assistance': 'decrease'},
  'minimums': {
    'assistance': {'value': '0', 'unit': 'kg'},
  },
  'resets': {
    'reps': {'value': '5', 'unit': 'rep'},
  },
  'coordination': mode == 'priority'
      ? {
          'mode': mode,
          'order': ['mass', 'assistance'],
        }
      : {'mode': 'chosen', 'metric': 'mass'},
  'scales': {
    'mass': {
      'scale': scale ?? _scale(),
      'rounding': 'nearest',
      'deloadRounding': 'atMost',
    },
  },
  'deloadAfter': 2,
  'deloadMetrics': ['mass', 'assistance'],
};
ProgressionProposal _eval(
  Map<String, Object?> rule, {
  Metrics? current,
  String reps = '8',
  int failures = 0,
}) => ThresholdRule.fromJson(rule).evaluate(
  current: current ?? _current,
  results: [
    metrics({'reps': (reps, 'rep')}),
  ],
  failedSessions: failures,
);
Future<void> _fails(Future<Object?> action) =>
    expectLater(action, throwsA(isA<BodyTmiException>()));
DateTime _at(int day) => instant(day).add(const Duration(hours: 2));
WorkoutDefinition _definition() => WorkoutDefinition.fromJson({
  'id': 'scaled',
  'name': 'Native scale practice',
  'slots': [
    {
      'id': 'movement',
      'exercise': 'custom',
      'implementation': 'custom',
      'equipment': 'stack-a',
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
  final dir = await Directory.systemTemp.createTemp('bodytmi-scale-');
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
      ? await training.start(id, 'scaled', 1, instant(day))
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

void numericScaleTests() {
  fixedRangeTests();
  test(
    'native scales retain one tick identity with exact canonical quantity and independent approximate printed labels',
    () {
      final s = NumericScale.fromJson(_scale());
      equal(s.ticks.length, 3);
      equal(s.ticks.first.quantity.value.toString(), '2.26796185');
      equal(s.ticks.first.labels['kg'], '2.3');
      equal(s.ticks.first.labels['lb'], '5');
      equal(s.ticks.first.quantity.enteredUnit, Unit.lb);
      equal(s.ticks.first.quantity.enteredValue, '5');
      equal(canonicalJson(s.toJson()), canonicalJson(_scale()));
      try {
        s.ticks.first.labels.clear();
        throw StateError('Mutable labels');
      } on UnsupportedError {
        /* Expected. */
      }
    },
  );
  test(
    'explicit nearest, at-most and at-least resolution use canonical units, explain rounding and have deterministic directional ties',
    () {
      final s = NumericScale.fromJson(_scale());
      equal(s.resolve(Quantity('2.26796185', 'kg'), 'nearest').tick!.id, 'p5');
      equal(s.resolve(Quantity('7.5', 'lb'), 'nearest').tick!.id, 'p5');
      equal(
        s
            .resolve(
              Quantity('7.5', 'lb'),
              'nearest',
              beyond: Quantity('0', 'lb'),
              direction: 'increase',
            )
            .tick!
            .id,
        'p10',
      );
      equal(
        s
            .resolve(
              Quantity('7.5', 'lb'),
              'nearest',
              beyond: Quantity('15', 'lb'),
              direction: 'decrease',
            )
            .tick!
            .id,
        'p5',
      );
      equal(s.resolve(Quantity('7.5', 'lb'), 'atMost').tick!.id, 'p5');
      equal(s.resolve(Quantity('7.5', 'lb'), 'atLeast').tick!.id, 'p10');
      equal(s.resolve(Quantity('4', 'lb'), 'atMost').tick, null);
      equal(s.resolve(Quantity('16', 'lb'), 'atLeast').tick, null);
      equal(s.resolve(Quantity('4', 'lb'), 'nearest').tick!.id, 'p5');
      equal(
        s.resolve(Quantity('7.5', 'lb'), 'nearest').toJson()['exact'],
        false,
      );
      equal(s.resolve(Quantity('5', 'lb'), 'nearest').toJson()['exact'], true);
    },
  );
  test(
    'directional lookup excludes the current setting before rounding and reports exhaustion without manufacturing ticks',
    () {
      final s = NumericScale.fromJson(_scale());
      equal(
        s
            .resolve(
              Quantity('10.1', 'lb'),
              'nearest',
              beyond: Quantity('10', 'lb'),
              direction: 'increase',
            )
            .tick!
            .id,
        'p15',
      );
      equal(
        s
            .resolve(
              Quantity('9.9', 'lb'),
              'nearest',
              beyond: Quantity('10', 'lb'),
              direction: 'decrease',
            )
            .tick!
            .id,
        'p5',
      );
      equal(
        s
            .resolve(
              Quantity('10.1', 'lb'),
              'atMost',
              beyond: Quantity('10', 'lb'),
              direction: 'increase',
            )
            .tick,
        null,
      );
      equal(
        s
            .resolve(
              Quantity('15.1', 'lb'),
              'nearest',
              beyond: Quantity('15', 'lb'),
              direction: 'increase',
            )
            .tick,
        null,
      );
      equal(
        s
            .resolve(
              Quantity('4.9', 'lb'),
              'nearest',
              beyond: Quantity('5', 'lb'),
              direction: 'decrease',
            )
            .tick,
        null,
      );
      equal(
        s
            .resolve(
              Quantity('11', 'lb'),
              'nearest',
              beyond: Quantity('11', 'lb'),
              direction: 'increase',
            )
            .tick!
            .id,
        'p15',
      );
    },
  );
  test(
    'scale validation rejects duplicate or unordered ticks, invalid labels/units, ambiguous lookup requests and resource overflow',
    () {
      for (final ticks in <List<Object?>>[
        [],
        [
          {'id': 'a', 'value': 1},
        ],
        [
          {'id': 'a', 'value': '1'},
          {'id': 'a', 'value': '2'},
        ],
        [
          {'id': 'a', 'value': '1'},
          {'id': 'b', 'value': '1.0'},
        ],
        [
          {'id': 'a', 'value': '2'},
          {'id': 'b', 'value': '1'},
        ],
        [
          {'id': 'a', 'value': '-1'},
        ],
        [
          {
            'id': 'a',
            'value': '1',
            'labels': {'s': 'one'},
          },
        ],
        [
          {
            'id': 'a',
            'value': '1',
            'labels': {'kg': 1},
          },
        ],
        [
          {'id': 'a', 'value': '1', 'labels': null},
        ],
      ]) {
        rejects(() => NumericScale.fromJson({..._scale(), 'ticks': ticks}));
      }
      rejects(
        () => NumericScale.fromJson({
          ..._scale(),
          'ticks': List.filled(1001, {'id': 'a', 'value': '1'}),
        }),
      );
      rejects(
        () => NumericScale.fromJson({
          ..._scale(),
          'unit': 'rep',
          'ticks': [
            {'id': 'a', 'value': '1.5'},
          ],
        }),
      );
      final s = NumericScale.fromJson(_scale());
      rejects(() => s.resolve(Quantity('1', 's'), 'nearest'));
      rejects(() => s.resolve(Quantity('1', 'lb'), 'unknown'));
      rejects(
        () => s.resolve(Quantity('1', 'lb'), 'nearest', direction: 'increase'),
      );
      rejects(
        () => s.resolve(
          Quantity('1', 'lb'),
          'nearest',
          beyond: Quantity('1', 'lb'),
        ),
      );
      rejects(
        () => s.resolve(
          Quantity('1', 'lb'),
          'nearest',
          beyond: Quantity('1', 'lb'),
          direction: 'sideways',
        ),
      );
      rejects(
        () => ThresholdRule.fromJson({
          ..._rule(),
          'scales': {
            'absent': {'scale': _scale(), 'rounding': 'nearest'},
          },
        }),
      );
      rejects(
        () => ThresholdRule.fromJson({
          ..._rule(),
          'scales': {
            'mass': {
              'scale': {..._scale(), 'unit': 's'},
              'rounding': 'nearest',
            },
          },
        }),
      );
      rejects(() => ThresholdRule.fromJson({..._rule(), 'scales': null}));
    },
  );
  test(
    'binary scale selection matches an independent exhaustive search over irregular ticks, targets, directions and rounding policies',
    () {
      final scale = NumericScale.fromJson({
        'id': 'irregular',
        'unit': 'kg',
        'ticks': [
          for (final v in [0, 2, 5, 9]) {'id': 'p$v', 'value': '$v'},
        ],
      });
      for (var half = 0; half <= 20; half++) {
        final target = Quantity('${half ~/ 2}.${half.isEven ? 0 : 5}', 'kg');
        for (final (beyond, direction) in <(int?, String?)>[
          (null, null),
          (0, 'increase'),
          (3, 'increase'),
          (9, 'increase'),
          (0, 'decrease'),
          (3, 'decrease'),
          (9, 'decrease'),
        ]) {
          for (final rounding in ['nearest', 'atMost', 'atLeast']) {
            final eligible = scale.ticks.where((t) {
              final value = int.parse(t.quantity.enteredValue);
              if (beyond != null &&
                  (direction == 'increase' ? value <= beyond : value >= beyond))
                return false;
              return rounding == 'atMost'
                  ? t.quantity.compareTo(target) <= 0
                  : rounding == 'atLeast'
                  ? t.quantity.compareTo(target) >= 0
                  : true;
            }).toList();
            eligible.sort((a, b) {
              if (rounding == 'atMost') return b.quantity.compareTo(a.quantity);
              if (rounding == 'atLeast')
                return a.quantity.compareTo(b.quantity);
              Decimal distance(Quantity q) => q.compareTo(target) >= 0
                  ? q.value - target.value
                  : target.value - q.value;
              final comparison = distance(
                a.quantity,
              ).compareTo(distance(b.quantity));
              return comparison != 0
                  ? comparison
                  : direction == 'increase'
                  ? b.quantity.compareTo(a.quantity)
                  : a.quantity.compareTo(b.quantity);
            });
            final result = scale.resolve(
              target,
              rounding,
              beyond: beyond == null ? null : Quantity('$beyond', 'kg'),
              direction: direction,
            );
            equal(result.tick?.id, eligible.firstOrNull?.id);
          }
        }
      }
    },
  );
  test(
    'numeric progression records native tick rounding, enforces bounds afterward, falls back on exhaustion and preserves legacy step shape',
    () {
      final p = _eval(_rule());
      equal(p.outcome, 'advance');
      equal(p.coordination!.selectedMetric, 'mass');
      equal(p.nextValues['mass']!.enteredValue, '15');
      equal(p.nextValues['mass']!.enteredUnit, Unit.lb);
      equal(p.scaleResolutions.single.metric, 'mass');
      equal(p.scaleResolutions.single.tick!.id, 'p15');
      equal(p.scaleResolutions.single.toJson()['exact'], false);
      final after = _eval(_rule(), current: p.nextValues);
      equal(after.coordination!.selectedMetric, 'assistance');
      equal(after.nextValues['assistance']!.value.toString(), '9');
      check(
        after.coordination!.candidates.first.blockedSets.single.reason.contains(
          'tick',
        ),
      );
      final bounded = _eval({
        ..._rule(mode: 'chosen'),
        'maximums': {
          'mass': {'value': '6', 'unit': 'kg'},
        },
      });
      equal(bounded.outcome, 'blocked');
      equal(bounded.nextValues['mass']!.enteredValue, '10');
      final old = _rule()..remove('scales');
      final legacy = _eval(old);
      equal(legacy.nextValues['mass']!.value.toString(), '4.581282937');
      check(!legacy.toJson().containsKey('scaleResolutions'));
    },
  );
  test(
    'stored native scale approvals retain tick provenance per set, seed future native targets and keep declines/warmups independent',
    () => _withStore((store, dir) async {
      final service = StoredProgressionService(store);
      final rule = _rule();
      final first = await _finish(store, 'one', 1);
      final p = await _propose(store, first.id, rule);
      equal(p.proposal.scaleResolutions.length, 2);
      equal(p.proposal.scaleResolutions.last.single.tick!.labels['kg'], '6.8');
      await service.accept(first.id, 'movement', p.version, _at(1));
      final second = await _finish(store, 'two', 2);
      equal(second.sets.first.suggested['mass']!.enteredValue, '10');
      equal(second.sets.last.suggested['mass']!.enteredValue, '15');
      equal(second.sets.last.suggested['mass']!.enteredUnit, Unit.lb);
      final q = await _propose(store, second.id, rule);
      equal(q.proposal.coordination!.selectedMetric, 'assistance');
      final d = await service.decline(second.id, 'movement', q.version, _at(2));
      equal(d.nextSets.first['assistance']!.value.toString(), '10');
      await StoredTrainingService(store).edit(
        second.id,
        second.contentVersion,
        (s) => const TrainingService().complete(s, s.sets.last.id, {
          'reps': Quantity('1', 'rep'),
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
      equal(applied.nextSets.first['assistance']!.value.toString(), '9');
      equal(applied.sequence, 3);
      await store.archive();
    }),
  );
  test(
    'scale-aware deload rounding moves strictly easier and one exhausted set holds the whole stored vector with its failed counter',
    () => _withStore((store, dir) async {
      final direct = _eval(
        _rule(),
        current: {..._current, 'mass': Quantity('15', 'lb')},
        reps: '1',
        failures: 1,
      );
      equal(direct.outcome, 'deload');
      equal(direct.nextValues['mass']!.enteredValue, '10');
      equal(direct.scaleResolutions.single.tick!.id, 'p10');
      var s = await _finish(store, 'one', 1, reps: '1');
      s = await StoredTrainingService(store).edit(s.id, s.contentVersion, (s) {
        final old = s.sets.last;
        return s.replaceSet(
          TrainingSet(
            id: old.id,
            slotId: old.slotId,
            role: old.role,
            ordinal: old.ordinal,
            suggested: {...old.suggested, 'mass': Quantity('5', 'lb')},
            actuals: {...old.actuals, 'mass': Quantity('5', 'lb')},
            status: old.status,
            contentVersion: old.contentVersion + 1,
          ),
        );
      });
      final service = StoredProgressionService(store);
      final rule = _rule();
      final p = await _propose(store, s.id, rule);
      await service.accept(s.id, 'movement', p.version, _at(1));
      final second = await _finish(store, 'two', 2, reps: '1');
      final q = await _propose(store, second.id, rule);
      equal(q.proposal.outcome, 'blocked');
      equal(q.proposal.failedSessions, 2);
      equal(q.proposal.scaleResolutions.first.single.tick!.id, 'p5');
      equal(q.proposal.scaleResolutions.last.single.tick, null);
      equal(q.proposal.nextSets.first['mass']!.enteredValue, '10');
      equal(q.proposal.nextSets.last['mass']!.enteredValue, '5');
      equal(q.proposal.nextSets.first['assistance']!.value.toString(), '10');
      final d = await service.accept(second.id, 'movement', q.version, _at(2));
      equal(d.failedSessions, 2);
      equal(
        (await service.accept(
          second.id,
          'movement',
          q.version,
          _at(2),
        )).sequence,
        2,
      );
      await store.archive();
    }),
  );
  test(
    'different frozen native scales remain isolated by run and stale or forged tick inputs cannot be accepted',
    () => _withStore((store, dir) async {
      final programs = ProgramService(store);
      await programs.publish(
        ProgramDefinition.fromJson({
          'id': 'shared',
          'name': 'Separate native scales',
          'plan': {
            'id': 'day',
            'type': 'day',
            'templateId': 'scaled',
            'revision': 1,
          },
        }),
        0,
      );
      for (final run in ['strength', 'cardio'])
        await programs.create(run, 'shared', 1, instant(1));
      for (final (day, run, rule, native) in [
        (1, 'strength', _rule(), '15'),
        (2, 'cardio', _rule(scale: _scale(values: [10, 12, 14])), '12'),
      ]) {
        final s = await _finish(store, run, day, run: run);
        final p = await _propose(store, s.id, rule);
        final d = await StoredProgressionService(
          store,
        ).accept(s.id, 'movement', p.version, _at(day));
        equal(d.nextSets.first['mass']!.enteredValue, native);
      }
      final s = await _finish(store, 'next', 3, run: 'cardio');
      final rule = _rule(scale: _scale(values: [10, 12, 14]));
      final p = await _propose(store, s.id, rule);
      await StoredTrainingService(store).edit(
        s.id,
        s.contentVersion,
        (s) => const TrainingService().complete(s, s.sets.last.id, {
          'reps': Quantity('8', 'rep'),
          'mass': Quantity('13', 'lb'),
        }, acceptSuggested: true),
      );
      await _fails(
        StoredProgressionService(
          store,
        ).accept(s.id, 'movement', p.version, _at(3)),
      );
      equal((await _propose(store, s.id, rule)).proposal.outcome, 'review');
      await _fails(_propose(store, s.id, _rule()));
      final forged = copyJson(p.toJson());
      final proofs =
          (forged['proposal'] as Map<String, Object?>)['scaleResolutions']
              as List<Object?>;
      final resolutions =
          (proofs.first as Map<String, Object?>)['resolutions']
              as List<Object?>;
      ((resolutions.first as Map<String, Object?>)['tick']
              as Map<String, Object?>)['id'] =
          'forged';
      rejects(() => ProgressionDecision.fromJson(forged));
      await store.archive();
    }),
  );
  test(
    'v17 receipts migrate unchanged and v18 native and logical restores preserve pending tick provenance while older labels reject scales',
    () => _withStore((store, dir) async {
      final s = await _finish(store, 'one', 1);
      final oldRule = _rule()..remove('scales');
      await _propose(store, s.id, oldRule);
      final before = canonicalJson((await store.archive()).toJson());
      await store.backup('$dir/old');
      await store.close();
      final old = sqlite3.open('$dir/old/database.sqlite');
      old.execute('DROP TABLE derived_target_graphs');
      old.userVersion = 17;
      old.close();
      equal(NativeBackup.validateDatabase('$dir/old/database.sqlite'), 17);
      final upgraded = await TrainingStore.open('$dir/old/database.sqlite');
      try {
        equal(canonicalJson((await upgraded.archive()).toJson()), before);
        equal(
          (await upgraded.backup('$dir/upgraded'))['databaseSchemaVersion'],
          34,
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
          j['format'] = 'bodytmi-logical-export/17';
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
            equal(d.proposal.scaleResolutions.last.single.tick!.id, 'p15');
            equal(d.nextSets.first['mass']!.enteredValue, '15');
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
        forged.userVersion = 17;
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
    'native scale validate/resolve and pure/stored progression expose matching units and tick evidence with clean invalid-input errors',
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

      final scale = await cmd('scale validate', {'scale': _scale()});
      equal(canonicalJson(scale), canonicalJson(_scale()));
      final resolved = await cmd('scale resolve', {
        'scale': _scale(),
        'target': {'value': '10.1', 'unit': 'lb'},
        'rounding': 'nearest',
        'beyond': {'value': '10', 'unit': 'lb'},
        'direction': 'increase',
      });
      equal(
        jsonObject(
          jsonObject(resolved['resolution'], 'resolution')['tick'],
          'tick',
        )['id'],
        'p15',
      );
      final pure = await cmd('progression evaluate', {
        'rule': _rule(),
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
        'rule': _rule(),
      });
      final proof =
          (jsonObject(stored['proposal'], 'proposal')['scaleResolutions']
                      as List<Object?>)
                  .first
              as Map<String, Object?>;
      equal(
        canonicalJson(proof['resolutions']),
        canonicalJson(pure['scaleResolutions']),
      );
      final bad = await invoke(
        ['scale', 'resolve'],
        jsonEncode({
          'schemaVersion': 1,
          'scale': _scale(),
          'target': {'value': '10', 'unit': 'lb'},
          'rounding': 'nearest',
          'direction': 'increase',
        }),
      );
      check(bad.code != 0);
      equal(bad.output, '');
      check(!bad.error.contains('internal'));
    }),
  );
  test(
    'process death rolls back or commits scale-aware approval and retry preserves tick identity without another progression application',
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
          equal(p.proposal.scaleResolutions.first.single.tick!.id, 'p15');
          if (p.acceptedAt != null) {
            final retry = await service.accept(
              'one',
              'movement',
              p.version,
              _at(1),
            );
            equal(retry.sequence, 1);
            final next = await _finish(recovered, 'two', 2);
            equal(next.sets.last.suggested['mass']!.enteredValue, '15');
            equal(
              (await _propose(
                recovered,
                next.id,
                _rule(),
              )).proposal.coordination!.selectedMetric,
              'assistance',
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

Map<String, Object?> _range({
  String start = '5',
  String step = '2.5',
  int count = 7,
}) => {
  'id': 'fixed-stack',
  'unit': 'lb',
  'range': {
    'start': start,
    'step': step,
    'count': count,
    'idPrefix': 'position',
  },
};

void fixedRangeTests() {
  test(
    'fixed native ranges preserve their compact declaration and generate exact deterministic positions without conversion drift',
    () {
      final s = NumericScale.fromJson(_range());
      equal(s.ticks.length, 7);
      equal(s.ticks.first.id, 'position-0');
      equal(s.ticks.last.id, 'position-6');
      equal(s.ticks[2].quantity.enteredValue, '10');
      equal(s.ticks[2].quantity.enteredUnit, Unit.lb);
      equal(s.ticks[1].quantity.value.toString(), '3.401942775');
      equal(s.ticks.last.quantity.enteredValue, '20');
      equal(s.ticks[1].labels.length, 0);
      equal(canonicalJson(s.toJson()), canonicalJson(_range()));
      equal(
        canonicalJson(NumericScale.fromJson(s.toJson()).toJson()),
        canonicalJson(s.toJson()),
      );
      final zero = NumericScale.fromJson({
        'id': 'rep-selector',
        'unit': 'rep',
        'range': {'start': '0', 'step': '1', 'count': 3},
      });
      equal(zero.ticks.first.id, 'tick-0');
      equal(zero.ticks.last.quantity.value.toString(), '2');
      equal(
        (zero.toJson()['range'] as Map<String, Object?>)['idPrefix'],
        'tick',
      );
    },
  );
  test(
    'fixed ranges reject ambiguous representations, invalid arithmetic/counts/identities and unrepresentable generated quantities',
    () {
      for (final range in <Object?>[
        null,
        {'start': 5, 'step': '1', 'count': 2},
        {'start': '-1', 'step': '1', 'count': 2},
        {'start': '5', 'step': '0', 'count': 2},
        {'start': '5', 'step': '-1', 'count': 2},
        {'start': '5', 'step': '1', 'count': 0},
        {'start': '5', 'step': '1', 'count': 1001},
        {'start': '5', 'step': '1', 'count': 1.5},
        {'start': '5', 'step': '1', 'count': '2'},
        {'start': '5', 'step': '1', 'count': 2, 'idPrefix': null},
        {'start': '5', 'step': '1', 'count': 2, 'idPrefix': 'bad/path'},
        {'start': '5', 'step': '1', 'count': 2, 'idPrefix': 'a' * 97},
        {'start': '5', 'step': '1', 'count': 2, 'end': '6'},
      ]) {
        rejects(() => NumericScale.fromJson({..._range(), 'range': range}));
      }
      rejects(() => NumericScale.fromJson({..._range(), 'ticks': <Object?>[]}));
      rejects(() => NumericScale.fromJson({'id': 'none', 'unit': 'lb'}));
      rejects(
        () => NumericScale.fromJson({..._range(step: '0.5'), 'unit': 'rep'}),
      );
      rejects(
        () =>
            NumericScale.fromJson(_range(start: '9' * 80, step: '1', count: 2)),
      );
      final single = NumericScale.fromJson(_range(count: 1));
      equal(single.ticks.length, 1);
      final limit = NumericScale.fromJson(
        _range(start: '0', step: '0.1', count: 1000),
      );
      equal(limit.ticks.last.quantity.enteredValue, '99.9');
    },
  );
  test(
    'generated fixed positions resolve identically to an equivalent explicit tick declaration for every rounding and direction',
    () {
      final fixed = NumericScale.fromJson(_range());
      final explicit = NumericScale.fromJson({
        'id': fixed.id,
        'unit': fixed.unit.name,
        'ticks': [for (final t in fixed.ticks) t.toJson()],
      });
      for (var i = 0; i <= 50; i++) {
        final target = Quantity('${i ~/ 2}.${i.isEven ? 0 : 5}', 'lb');
        for (final rounding in ['nearest', 'atMost', 'atLeast']) {
          for (final (beyond, direction) in <(String?, String?)>[
            (null, null),
            ('10', 'increase'),
            ('10', 'decrease'),
          ]) {
            final b = beyond == null ? null : Quantity(beyond, 'lb');
            equal(
              canonicalJson(
                fixed
                    .resolve(target, rounding, beyond: b, direction: direction)
                    .toJson(),
              ),
              canonicalJson(
                explicit
                    .resolve(target, rounding, beyond: b, direction: direction)
                    .toJson(),
              ),
            );
          }
        }
      }
      final p = _eval(_rule(scale: _range()));
      equal(p.scaleResolutions.single.tick!.id, 'position-3');
      equal(p.nextValues['mass']!.enteredValue, '12.5');
      final deload = _eval(
        _rule(scale: _range()),
        current: p.nextValues,
        reps: '1',
        failures: 1,
      );
      equal(deload.outcome, 'deload');
      equal(deload.nextValues['mass']!.enteredValue, '10');
    },
  );
  test(
    'stored fixed-range advances, scale exhaustion and declines retain generated identities and independent run targets',
    () => _withStore((store, dir) async {
      final programs = ProgramService(store);
      await programs.publish(
        ProgramDefinition.fromJson({
          'id': 'shared',
          'name': 'Separate fixed settings',
          'plan': {
            'id': 'day',
            'type': 'day',
            'templateId': 'scaled',
            'revision': 1,
          },
        }),
        0,
      );
      for (final run in ['strength', 'cardio'])
        await programs.create(run, 'shared', 1, instant(1));
      final rule = _rule(scale: _range());
      final service = StoredProgressionService(store);
      for (var day = 1; day <= 4; day++) {
        final s = await _finish(store, 's$day', day, run: 'strength');
        final p = await _propose(store, s.id, rule);
        equal(
          p.proposal.scaleResolutions.first.single.tick!.id,
          'position-${day + 2}',
        );
        await service.accept(s.id, 'movement', p.version, _at(day));
      }
      final cardio = await _finish(store, 'cardio', 5, run: 'cardio');
      final c = await _propose(store, cardio.id, _rule());
      final cd = await service.accept(cardio.id, 'movement', c.version, _at(5));
      equal(cd.nextSets.first['mass']!.enteredValue, '15');
      final exhausted = await _finish(store, 'exhausted', 6, run: 'strength');
      equal(exhausted.sets.first.suggested['mass']!.enteredValue, '10');
      equal(exhausted.sets.last.suggested['mass']!.enteredValue, '20');
      final p = await _propose(store, exhausted.id, rule);
      equal(p.proposal.coordination!.selectedMetric, 'assistance');
      final d = await service.decline(
        exhausted.id,
        'movement',
        p.version,
        _at(6),
      );
      equal(d.nextSets.first['assistance']!.value.toString(), '10');
      await StoredTrainingService(store).edit(
        exhausted.id,
        exhausted.contentVersion,
        (s) => const TrainingService().complete(s, s.sets.last.id, {
          'reps': Quantity('1', 'rep'),
        }, acceptSuggested: true),
      );
      equal((await _propose(store, exhausted.id, rule)).status, 'declined');
      final next = await _finish(store, 'next', 7, run: 'strength');
      final q = await _propose(store, next.id, rule);
      final applied = await service.accept(
        next.id,
        'movement',
        q.version,
        _at(7),
      );
      equal(applied.nextSets.first['assistance']!.value.toString(), '9');
      final forged = copyJson(applied.toJson());
      final binding =
          ((forged['rule'] as Map<String, Object?>)['scales']
                  as Map<String, Object?>)['mass']
              as Map<String, Object?>;
      (((binding['scale'] as Map<String, Object?>)['range'])
              as Map<String, Object?>)['step'] =
          '5';
      rejects(() => ProgressionDecision.fromJson(forged));
      await store.archive();
    }),
  );
  test(
    'v18 explicit-tick receipts migrate unchanged while v19 portability preserves pending fixed-range provenance and rejects legacy labels',
    () => _withStore((store, dir) async {
      final s = await _finish(store, 'one', 1);
      await _propose(store, s.id, _rule());
      final before = canonicalJson((await store.archive()).toJson());
      await store.backup('$dir/old');
      await store.close();
      final old = sqlite3.open('$dir/old/database.sqlite');
      old.execute('DROP TABLE derived_target_graphs');
      old.userVersion = 18;
      old.close();
      equal(NativeBackup.validateDatabase('$dir/old/database.sqlite'), 18);
      final upgraded = await TrainingStore.open('$dir/old/database.sqlite');
      try {
        equal(canonicalJson((await upgraded.archive()).toJson()), before);
        equal(
          (await upgraded.backup('$dir/upgraded'))['databaseSchemaVersion'],
          34,
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
          j['format'] = 'bodytmi-logical-export/18';
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
        final p = await _propose(active, s.id, _rule(scale: _range()));
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
            equal(
              d.proposal.scaleResolutions.last.single.tick!.id,
              'position-3',
            );
            equal(d.nextSets.first['mass']!.enteredValue, '12.5');
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
        forged.userVersion = 18;
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
    'native CLI round-trips compact ranges and rejects malformed ranges without internal errors',
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

      final scale = await cmd('scale validate', {'scale': _range()});
      equal(canonicalJson(scale), canonicalJson(_range()));
      check(!scale.containsKey('ticks'));
      final resolved = await cmd('scale resolve', {
        'scale': _range(),
        'target': {'value': '10.1', 'unit': 'lb'},
        'rounding': 'nearest',
        'beyond': {'value': '10', 'unit': 'lb'},
        'direction': 'increase',
      });
      equal(
        jsonObject(
          jsonObject(resolved['resolution'], 'resolution')['tick'],
          'tick',
        )['id'],
        'position-3',
      );
      final request = {
        'database': '$dir/db.sqlite',
        'sessionId': s.id,
        'slotId': 'movement',
      };
      final stored = await cmd('progression propose', {
        ...request,
        'ruleType': 'threshold',
        'rule': _rule(scale: _range()),
      });
      final proof =
          (jsonObject(stored['proposal'], 'proposal')['scaleResolutions']
                      as List<Object?>)
                  .first
              as Map<String, Object?>;
      final tick =
          (((proof['resolutions'] as List<Object?>).first
                  as Map<String, Object?>)['tick'])
              as Map<String, Object?>;
      equal(tick['id'], 'position-3');
      final bad = await invoke(
        ['scale', 'validate'],
        jsonEncode({
          'schemaVersion': 1,
          'scale': {
            ..._range(),
            'range': {'start': '5', 'step': '0', 'count': 3},
          },
        }),
      );
      check(bad.code != 0);
      equal(bad.output, '');
      check(!bad.error.contains('internal'));
    }),
  );
  test(
    'process death around fixed-range acceptance preserves deterministic position identity and exactly-once application',
    () => _withStore((store, dir) async {
      await _finish(store, 'one', 1);
      await _propose(store, 'one', _rule(scale: _range()));
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
          equal(
            p.proposal.scaleResolutions.first.single.tick!.id,
            'position-3',
          );
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
            equal(next.sets.last.suggested['mass']!.enteredValue, '12.5');
          }
          await recovered.archive();
        } finally {
          await recovered.close();
        }
      }
    }),
  );
}
