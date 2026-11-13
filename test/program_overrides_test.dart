import 'dart:convert';
import 'dart:io';

import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

import 'cli_test.dart' show invoke;
import 'fixtures.dart';
import 'support.dart';

Map<String, Object?> _override(
  String slot,
  String metric,
  String mode, {
  String? factor,
  Map<String, String>? quantity,
}) => {
  'slotId': slot,
  'metric': metric,
  'mode': mode,
  if (factor != null) 'factor': factor,
  if (quantity != null) 'quantity': quantity,
};

Map<String, Object?> _day(
  String id,
  String templateId,
  int revision, {
  List<Map<String, Object?>>? overrides,
}) => {
  'id': id,
  'type': 'day',
  'label': 'Day $id',
  'templateId': templateId,
  'revision': revision,
  if (overrides != null) 'overrides': overrides,
};

Map<String, Object?> _cycle(
  List<Map<String, Object?>> days, {
  List<Map<String, Object?>>? overrides,
}) => {
  'id': 'cycle',
  'type': 'group',
  'label': 'Cycle',
  'children': days,
  if (overrides != null) 'overrides': overrides,
};

Map<String, Object?> _program(
  Map<String, Object?> plan, {
  String id = 'ov-program',
}) => {'id': id, 'name': 'Override program', 'plan': plan};

DateTime _at(int day) => instant(day);

Future<BodyTmiException> failure(Object? Function() action) async {
  try {
    await action();
  } on BodyTmiException catch (error) {
    return error;
  }
  throw StateError('Expected a BodyTmiException.');
}

final _doubleRule = jsonObject(example('double-progression')['rule'], 'rule');

void programOverrideTests() {
  Future<TrainingSession> finishRunSession(
    TrainingStore store,
    String sessionId,
    int day, {
    String? heavyActual,
  }) async {
    final session = await StoredTrainingService(store).session(sessionId);
    return StoredTrainingService(store).edit(
      sessionId,
      session.contentVersion,
      (s) {
        for (final set in s.sets) {
          final heavy =
              heavyActual != null &&
              set.slotId == 'bench-heavy' &&
              set.role == 'work';
          s = const TrainingService().complete(
            s,
            set.id,
            heavy
                ? {
                    'mass': Quantity(heavyActual, 'kg'),
                    'reps': set.suggested['reps']!,
                  }
                : const {},
            acceptSuggested: !heavy,
          );
        }
        return s.finish(_at(day).add(const Duration(hours: 1)));
      },
    );
  }

  test(
    'authored overrides merge along node paths with nearest scope winning',
    () async {
      final definition = ProgramDefinition.fromJson(
        _program({
          'id': 'cycle',
          'type': 'group',
          'children': [
            _day(
              'a',
              'upper-a',
              1,
              overrides: [
                _override(
                  'bench-heavy',
                  'mass',
                  'set',
                  quantity: {'value': '25', 'unit': 'kg'},
                ),
              ],
            ),
            {
              'id': 'blocks',
              'type': 'repeat',
              'count': 2,
              'child': _day('b', 'upper-a', 1),
              'overrides': [
                _override('bench-light', 'mass', 'scale', factor: '0.5'),
              ],
            },
          ],
          'overrides': [
            _override('bench-heavy', 'mass', 'scale', factor: '0.8'),
          ],
        }),
      );
      check(
        definition.hasPrescriptionOverrides,
        'definition advertises overrides',
      );
      final dayA = definition.effectiveOverrides('cycle/a');
      equal(dayA.length, 1);
      equal(dayA.single.path, 'cycle/a');
      equal(dayA.single.override.mode, 'set');
      equal(dayA.single.override.quantity!.enteredValue, '25');
      final repeated = definition.effectiveOverrides('cycle/blocks[1]/b');
      equal(repeated.length, 2);
      equal(repeated.first.override.slotId, 'bench-heavy');
      equal(repeated.first.override.mode, 'scale');
      equal(repeated.first.path, 'cycle');
      equal(repeated.last.override.slotId, 'bench-light');
      equal(
        canonicalJson(definition.toJson()),
        canonicalJson(ProgramDefinition.fromJson(definition.toJson()).toJson()),
      );

      final unknownPath = await failure(
        () => definition.effectiveOverrides('cycle/missing'),
      );
      check(
        unknownPath.message.contains('Unknown program scope path'),
        'unknown path',
      );

      for (final bad in [
        _override('bench-heavy', 'mass', 'scale'),
        _override('bench-heavy', 'mass', 'set', factor: '2'),
        _override('bench-heavy', 'mass', 'scale', factor: '0'),
        _override('bench-heavy', 'mass', 'scale', factor: '-1'),
        _override('bench-heavy', 'mass', 'double', factor: '2'),
      ]) {
        final error = await failure(
          () => ProgramDefinition.fromJson(
            _program(_cycle([_day('a', 'upper-a', 1)], overrides: [bad])),
          ),
        );
        check(
          error.message.contains('override'),
          'invalid override payload: ${error.message}',
        );
      }
      final duplicate = await failure(
        () => ProgramDefinition.fromJson(
          _program(
            _cycle(
              [_day('a', 'upper-a', 1)],
              overrides: [
                _override('bench-heavy', 'mass', 'scale', factor: '0.8'),
                _override(
                  'bench-heavy',
                  'mass',
                  'set',
                  quantity: {'value': '25', 'unit': 'kg'},
                ),
              ],
            ),
          ),
        ),
      );
      check(
        duplicate.message.contains('cannot repeat'),
        'one node declares each slot metric once',
      );
    },
  );

  test('scale and set overrides rewrite authored targets exactly', () async {
    final base = const TrainingService().start(
      sessionId: 's',
      revision: revision(),
      startedAt: _at(1),
    );
    final result = applyPrescriptionOverrides(definition(), base.sets, [
      ScopedProgramOverride(
        'cycle',
        ProgramOverride.fromJson(
          _override('bench-heavy', 'mass', 'scale', factor: '0.8'),
        ),
      ),
      ScopedProgramOverride(
        'cycle',
        ProgramOverride.fromJson(
          _override(
            'bench-light',
            'reps',
            'set',
            quantity: {'value': '5', 'unit': 'rep'},
          ),
        ),
      ),
      ScopedProgramOverride(
        'cycle',
        ProgramOverride.fromJson(
          _override('bench-heavy', 'time', 'scale', factor: '0.8'),
        ),
      ),
    ]);
    equal(result.records.length, 2);
    equal(result.records.first.slotId, 'bench-heavy');
    equal(result.records.first.applied.length, 3);
    equal(result.records.first.applied.first.before.enteredValue, '60');
    equal(result.records.first.applied.first.after.enteredValue, '48');
    equal(result.records.first.applied.first.after.enteredUnit.name, 'kg');
    for (final set in result.sets.where((s) => s.slotId == 'bench-heavy')) {
      equal(set.suggested['mass']!.enteredValue, '48');
      equal(set.suggested['reps']!.enteredValue, '8');
    }
    final light = result.sets.firstWhere((s) => s.slotId == 'bench-light');
    equal(light.suggested['reps']!.enteredValue, '5');
    equal(light.suggested['mass']!.enteredValue, '45');

    final fractional = await failure(
      () => applyPrescriptionOverrides(definition(), base.sets, [
        ScopedProgramOverride(
          'cycle',
          ProgramOverride.fromJson(
            _override('bench-heavy', 'reps', 'scale', factor: '0.6'),
          ),
        ),
      ]),
    );
    check(fractional.message.contains('Repetitions'), 'count stays integral');
  });

  test(
    'run start consumes scoped overrides ahead of history prefill and freezes provenance',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-ov-run-');
      final store = await TrainingStore.open('${dir.path}/profile.sqlite');
      try {
        await StoredTrainingService(store).publish(definition(), 0);
        final programs = ProgramService(store);
        await programs.publish(
          ProgramDefinition.fromJson(
            _program(
              _cycle(
                [_day('a', 'upper-a', 1), _day('b', 'upper-a', 1)],
                overrides: [
                  _override('bench-heavy', 'mass', 'scale', factor: '0.8'),
                ],
              ),
            ),
          ),
          0,
        );
        await programs.create('run-1', 'ov-program', 1, _at(1), loop: false);
        final run = await programs.run('run-1');
        final started = await programs.start(
          'run-1',
          run.contentVersion,
          'session-1',
          _at(1),
        );
        for (final set in started.sets) {
          equal(
            set.suggested['mass']!.enteredValue,
            set.slotId == 'bench-heavy' ? '48' : '45',
          );
        }
        equal(started.prescriptionOverrides.length, 1);
        equal(started.prescriptionOverrides.single.path, 'cycle');
        equal(started.prescriptionOverrides.single.applied.length, 3);
        for (final applied in started.prescriptionOverrides.single.applied) {
          equal(applied.before.enteredValue, '60');
          equal(applied.after.enteredValue, '48');
        }

        // The schedule view reports effective overrides descriptively.
        final schedule = await programs.schedule('run-1', count: 2);
        final entry = jsonObject(
          jsonList(schedule, 'days').first,
          'schedule day',
        );
        final scoped = entry['effectiveOverrides']! as List<Object?>;
        equal(scoped.length, 1);
        equal(jsonObject(scoped.single, 'scoped')['path'], 'cycle');
        equal(jsonObject(scoped.single, 'scoped')['mode'], 'scale');
        equal(jsonObject(scoped.single, 'scoped')['factor'], '0.8');

        // A start retry returns the identical frozen session.
        final runNow = await programs.run('run-1');
        final replay = await programs.start(
          'run-1',
          runNow.contentVersion,
          'session-1',
          _at(1),
        );
        equal(canonicalJson(replay.toJson()), canonicalJson(started.toJson()));

        // A completed heavy exposure of 70 kg never prefills over the override.
        await finishRunSession(store, 'session-1', 1, heavyActual: '70');
        final run1 = await programs.run('run-1');
        equal(run1.cursor, 1);

        // A run upgrade to different overrides cannot rewrite the frozen
        // session provenance, but the next day consumes the new values.
        await programs.publish(
          ProgramDefinition.fromJson(
            _program(
              _cycle(
                [_day('a', 'upper-a', 1), _day('b', 'upper-a', 1)],
                overrides: [
                  _override('bench-heavy', 'mass', 'scale', factor: '0.5'),
                ],
              ),
            ),
          ),
          1,
        );
        await programs.upgrade(
          'run-1',
          run1.contentVersion,
          2,
          'upgrade-1',
          _at(2),
        );
        final second = await programs.start(
          'run-1',
          run1.contentVersion + 1,
          'session-2',
          _at(2),
        );
        for (final set in second.sets.where((s) => s.slotId == 'bench-heavy')) {
          equal(set.suggested['mass']!.enteredValue, '30');
          check(
            set.sources['mass'] == null,
            'overrides replace history prefill',
          );
        }
        equal(
          second.prescriptionOverrides.single.applied.first.after.enteredValue,
          '30',
        );
        final drift = await failure(
          () => programs.start(
            'run-1',
            run1.contentVersion + 1,
            'session-1',
            _at(1),
          ),
        );
        equal(drift.code, 'conflict');
        final frozen = await StoredTrainingService(store).session('session-1');
        equal(
          frozen.prescriptionOverrides.single.applied.first.after.enteredValue,
          '48',
        );
        await finishRunSession(store, 'session-2', 2, heavyActual: '65');

        // Portability: native and logical v57 round-trip, old labels rejected.
        final before = canonicalJson((await store.archive()).toJson());
        final manifest = await store.backup('${dir.path}/native');
        equal(manifest['databaseSchemaVersion'], 58);
        equal(
          NativeBackup.validateDatabase('${dir.path}/native/database.sqlite'),
          58,
        );
        final logical = await LogicalArchiveFiles.export(
          await store.archive(),
          '${dir.path}/logical.json',
        );
        equal(logical['format'], 'bodytmi-logical-export/58');
        final prepared = await LogicalArchiveFiles.prepare(
          '${dir.path}/logical.json',
        );
        try {
          equal(canonicalJson(prepared.archive.toJson()), before);
        } finally {
          await prepared.close();
        }

        final relabeled = jsonObject(
          jsonDecode(await File('${dir.path}/logical.json').readAsString()),
          'file',
        );
        relabeled['format'] = 'bodytmi-logical-export/56';
        relabeled.remove('sha256');
        relabeled['sha256'] = sha256
            .convert(utf8.encode(canonicalJson(relabeled)))
            .toString();
        await File(
          '${dir.path}/relabeled.json',
        ).writeAsString(jsonEncode(relabeled));
        final oldLabel = await failure(
          () => LogicalArchiveFiles.prepare('${dir.path}/relabeled.json'),
        );
        check(
          oldLabel.message.contains(
            'prescription overrides require logical v57',
          ),
          'old logical labels reject overrides',
        );

        File('${dir.path}/labeled.sqlite').writeAsBytesSync(
          File('${dir.path}/native/database.sqlite').readAsBytesSync(),
        );
        final nativeDb = sqlite3.open('${dir.path}/labeled.sqlite');
        nativeDb.execute('DROP TABLE IF EXISTS exercise_revisions');
        nativeDb.execute('DROP TABLE IF EXISTS implementation_revisions');
        nativeDb.userVersion = 56;
        nativeDb.close();
        final nativeLabel = await failure(
          () => NativeBackup.validateDatabase('${dir.path}/labeled.sqlite'),
        );
        check(
          nativeLabel.message.contains(
            'prescription overrides require schema v57',
          ),
          'old native labels reject overrides',
        );

        final restorer = await TrainingStore.open(
          '${dir.path}/restored.sqlite',
        );
        try {
          await restorer.restore(
            await NativeBackup.prepare('${dir.path}/native'),
            recoveryDestination: '${dir.path}/recovery',
            confirm: true,
          );
        } finally {
          await restorer.close();
        }
        final restored = await TrainingStore.open(
          '${dir.path}/restored.sqlite',
        );
        try {
          equal(canonicalJson((await restored.archive()).toJson()), before);
          final session = await StoredTrainingService(
            restored,
          ).session('session-1');
          equal(
            session
                .prescriptionOverrides
                .single
                .applied
                .first
                .after
                .enteredValue,
            '48',
          );
        } finally {
          await restored.close();
        }
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'overrides cannot target a progression-controlled metric and start stores nothing',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-ov-track-');
      final store = await TrainingStore.open('${dir.path}/profile.sqlite');
      try {
        await StoredTrainingService(store).publish(definition(), 0);
        final programs = ProgramService(store);
        await programs.publish(
          ProgramDefinition.fromJson(
            _program(
              _cycle([_day('a', 'upper-a', 1), _day('b', 'upper-a', 1)]),
            ),
          ),
          0,
        );
        await programs.create('run-1', 'ov-program', 1, _at(1), loop: false);
        var run = await programs.run('run-1');
        final started = await programs.start(
          'run-1',
          run.contentVersion,
          'session-1',
          _at(1),
        );
        check(started.prescriptionOverrides.isEmpty, 'rev1 has no overrides');
        await finishRunSession(store, 'session-1', 1);
        run = await programs.run('run-1');
        final progression = StoredProgressionService(store);
        final proposal = await progression.propose(
          'session-1',
          'bench-heavy',
          _doubleRule,
        );
        await progression.accept(
          'session-1',
          'bench-heavy',
          proposal.version,
          _at(1).add(const Duration(hours: 2)),
        );

        // Authoring an override over the progression-controlled mass lever
        // passes publication, but the upgraded run start hard-conflicts.
        await programs.publish(
          ProgramDefinition.fromJson(
            _program(
              _cycle(
                [_day('a', 'upper-a', 1), _day('b', 'upper-a', 1)],
                overrides: [
                  _override('bench-heavy', 'mass', 'scale', factor: '0.8'),
                ],
              ),
            ),
          ),
          1,
        );
        await programs.upgrade(
          'run-1',
          run.contentVersion,
          2,
          'upgrade-1',
          _at(2),
        );
        final upgraded = await programs.run('run-1');
        final conflict = await failure(
          () => programs.start(
            'run-1',
            upgraded.contentVersion,
            'session-2',
            _at(2),
          ),
        );
        check(
          conflict.message.contains('progression-controlled metric'),
          'override cannot silently bypass an accepted track',
        );
        final missing = await failure(
          () => StoredTrainingService(store).session('session-2'),
        );
        equal(missing.code, 'not_found');

        // An override on a non-controlled slot metric still works.
        await programs.publish(
          ProgramDefinition.fromJson(
            _program(
              _cycle(
                [_day('a', 'upper-a', 1), _day('b', 'upper-a', 1)],
                overrides: [
                  _override('bench-light', 'mass', 'scale', factor: '0.5'),
                ],
              ),
            ),
          ),
          2,
        );
        final run3 = await programs.run('run-1');
        await programs.upgrade(
          'run-1',
          run3.contentVersion,
          3,
          'upgrade-2',
          _at(2),
        );
        final pinned = await programs.run('run-1');
        final ok = await programs.start(
          'run-1',
          pinned.contentVersion,
          'session-3',
          _at(2),
        );
        equal(
          ok.sets
              .firstWhere((s) => s.slotId == 'bench-light')
              .suggested['mass']!
              .enteredValue,
          '22.5',
        );
        check(
          ok.sets
                  .firstWhere((s) => s.slotId == 'bench-heavy')
                  .suggested['mass']!
                  .enteredValue !=
              '48',
          'the accepted track still owns the heavy lever',
        );
        equal(ok.prescriptionOverrides.single.applied.length, 1);
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'publication requires authored targets and stored snapshots reject tampering',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-ov-publish-');
      final path = '${dir.path}/profile.sqlite';
      final store = await TrainingStore.open(path);
      try {
        await StoredTrainingService(store).publish(definition(), 0);
        final programs = ProgramService(store);
        final unmatched = await failure(
          () => programs.publish(
            ProgramDefinition.fromJson(
              _program(
                _cycle(
                  [_day('a', 'upper-a', 1)],
                  overrides: [
                    _override('bench-heavy', 'time', 'scale', factor: '0.5'),
                  ],
                ),
              ),
            ),
            0,
          ),
        );
        check(
          unmatched.message.contains('authored target'),
          'overrides need an authored slot target',
        );
        final unknownSlot = await failure(
          () => programs.publish(
            ProgramDefinition.fromJson(
              _program(
                _cycle(
                  [_day('a', 'upper-a', 1)],
                  overrides: [
                    _override('no-such-slot', 'mass', 'scale', factor: '0.5'),
                  ],
                ),
              ),
            ),
            0,
          ),
        );
        check(unknownSlot.message.contains('authored target'), 'unknown slot');

        // A caller-derived plan cannot be combined with scoped overrides.
        await programs.publish(
          ProgramDefinition.fromJson(
            _program(
              _cycle(
                [_day('a', 'upper-a', 1), _day('b', 'upper-a', 1)],
                overrides: [
                  _override('bench-heavy', 'mass', 'scale', factor: '0.8'),
                ],
              ),
            ),
          ),
          0,
        );
        await programs.create('run-1', 'ov-program', 1, _at(1), loop: false);
        final run = await programs.run('run-1');
        final combination = await failure(
          () => programs.start(
            'run-1',
            run.contentVersion,
            'session-1',
            _at(1),
            derivedPlan: const DerivedPlanRef('graph-1', 1, 'plan-1'),
          ),
        );
        check(
          combination.message.contains('cannot combine derived plans'),
          'derived plans stay separate from overrides',
        );
        await programs.start('run-1', run.contentVersion, 'session-1', _at(1));
      } finally {
        await store.close();
      }

      // Stored snapshot tampering is rejected when the session is decoded.
      final db = sqlite3.open(path);
      String honestSnapshot = '';
      try {
        final row = db.select('SELECT snapshot FROM sessions WHERE id = ?', [
          'session-1',
        ]).single;
        honestSnapshot = row['snapshot'] as String;
        final snapshot = jsonObject(jsonDecode(honestSnapshot), 'session');
        final records = snapshot['prescriptionOverrides']! as List<Object?>;
        final applied =
            jsonObject(records.first, 'record')['applied']! as List<Object?>;
        final first = jsonObject(applied.first, 'application');
        final after = jsonObject(first['after'], 'after');
        after['value'] = '50';
        after['entered'] = {'value': '50', 'unit': 'kg'};
        db.execute('UPDATE sessions SET snapshot = ? WHERE id = ?', [
          jsonEncode(snapshot),
          'session-1',
        ]);
      } finally {
        db.close();
      }
      final reopened = await TrainingStore.open(path);
      try {
        final tampered = await failure(
          () => StoredTrainingService(reopened).session('session-1'),
        );
        check(
          tampered.message.contains('provenance does not match'),
          'frozen before/after values are checked against the plan',
        );
      } finally {
        await reopened.close();
      }

      // Restoring the honest snapshot and tampering only the suggestion also
      // fails: unedited sets must keep the frozen overridden values.
      final repair = sqlite3.open(path);
      try {
        final snapshot = jsonObject(jsonDecode(honestSnapshot), 'session');
        final sets = snapshot['sets']! as List<Object?>;
        final heavy = sets
            .map((set) => jsonObject(set, 'set'))
            .firstWhere((set) => set['slot'] == 'bench-heavy');
        final suggested = jsonObject(
          jsonObject(heavy, 'set')['suggested'],
          'suggested',
        );
        suggested['mass'] = {
          'value': '50',
          'unit': 'kg',
          'entered': {'value': '50', 'unit': 'kg'},
        };
        repair.execute('UPDATE sessions SET snapshot = ? WHERE id = ?', [
          jsonEncode(snapshot),
          'session-1',
        ]);
      } finally {
        repair.close();
      }
      final again = await TrainingStore.open(path);
      try {
        final tampered = await failure(
          () => StoredTrainingService(again).session('session-1'),
        );
        check(
          tampered.message.contains(
            'do not match frozen prescription overrides',
          ),
          'suggestions must equal the frozen overridden values',
        );
      } finally {
        await again.close();
      }
      await dir.delete(recursive: true);
    },
  );

  test(
    'CLI publishes overridden programs and starts frozen sessions',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-cli-ov-');
      final db = '${dir.path}/profile.sqlite';
      Future<({int code, Map<String, Object?> body})> call(
        String command,
        Map<String, Object?> fields,
      ) async {
        final result = await invoke([
          command.split(' ').first,
          command.split(' ').skip(1).join(' '),
        ], jsonEncode({'schemaVersion': 1, 'database': db, ...fields}));
        final body = result.output.isEmpty
            ? <String, Object?>{}
            : jsonObject(jsonDecode(result.output), 'response');
        return (code: result.code, body: body);
      }

      final loaded = example('upper-a');
      {
        final store = await TrainingStore.open(db);
        try {
          await StoredTrainingService(store).publish(
            WorkoutDefinition.fromJson(
              jsonObject(loaded, 'example')['definition'],
            ),
            0,
          );
        } finally {
          await store.close();
        }
      }
      final exampleFile = jsonObject(
        jsonDecode(
          await File('examples/program-overrides.json').readAsString(),
        ),
        'example',
      );
      final publish = await call('program publish', {
        'definition': jsonObject(exampleFile, 'example')['definition'],
        'expectedRevision': 0,
      });
      equal(publish.code, 0);
      final create = await call('run create', {
        'id': 'run-1',
        'programId': 'ov-program',
        'revision': 1,
        'startedAt': _at(1).toUtc().toIso8601String(),
        'loop': false,
      });
      equal(create.code, 0);
      final show = await call('run show', {'runId': 'run-1'});
      equal(show.code, 0);
      final dataMap = jsonObject(show.body['data'], 'run view');
      final scoped = dataMap['effectiveOverrides']! as List<Object?>;
      equal(scoped.length, 1);
      final start = await call('run start', {
        'runId': 'run-1',
        'expectedVersion': 1,
        'id': 'session-1',
        'startedAt': _at(1).toUtc().toIso8601String(),
      });
      equal(start.code, 0);
      final shown = await call('store show', {'id': 'session-1'});
      equal(shown.code, 0);
      final session = jsonObject(shown.body['data'], 'session');
      final records = session['prescriptionOverrides']! as List<Object?>;
      equal(records.length, 1);
      equal(
        jsonObject(
          jsonObject(
            (jsonObject(records.first, 'record')['applied']! as List<Object?>)
                .first,
            'application',
          )['after'],
          'after',
        )['value'],
        '48',
      );

      // An invalid override payload exits as validation without storing.
      final badProgram = _program(
        _cycle(
          [_day('a', 'upper-a', 1)],
          overrides: [_override('bench-heavy', 'mass', 'scale')],
        ),
      );
      final bad = await call('program publish', {
        'definition': badProgram,
        'expectedRevision': 1,
      });
      equal(bad.code, 2);
      final listed = await call('program list', {});
      equal(listed.code, 0);
      equal((listed.body['data']! as List<Object?>).length, 1);
      await dir.delete(recursive: true);
    },
  );
}
