import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:bodytmi_storage/src/schema.dart';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart' show expectLater, throwsA, isA;
import 'cli_test.dart';
import 'fixtures.dart';
import 'support.dart';

ProgramDefinition _program(String id, {int revision = 1}) =>
    ProgramDefinition.fromJson({
      'id': id,
      'name': id,
      'plan': {
        'id': 'cycle',
        'type': 'group',
        'label': 'Cycle',
        'children': [
          {
            'id': 'a',
            'type': 'day',
            'label': 'First day',
            'templateId': definition().id,
            'revision': revision,
          },
          {
            'id': 'b',
            'type': 'day',
            'label': 'Second day',
            'templateId': definition().id,
            'revision': revision,
          },
        ],
      },
    });
Map<String, Object?> _rule() =>
    jsonObject(example('double-progression')['rule'], 'rule');
DateTime _finish(int day) => instant(day).add(const Duration(hours: 1));
DateTime _accept(int day) => instant(day).add(const Duration(hours: 2));
Future<void> _setup(TrainingStore store) async {
  await StoredTrainingService(store).publish(definition(), 0);
  await ProgramService(store).publish(_program('strength'), 0);
  await ProgramService(store).publish(_program('cardio'), 0);
  await ProgramService(store).create('strength-run', 'strength', 1, instant(1));
  await ProgramService(store).create('cardio-run', 'cardio', 1, instant(1));
}

Future<TrainingSession> _start(
  TrainingStore store,
  String run,
  String id,
  int day,
) async {
  final service = ProgramService(store);
  final state = await service.run(run);
  return service.start(run, state.contentVersion, id, instant(day));
}

Future<TrainingSession> _done(TrainingStore store, TrainingSession session) =>
    StoredTrainingService(
      store,
    ).edit(session.id, session.contentVersion, finished);

void programTests() {
  test(
    'program groups and repeats have stable finite paths and reject invalid or unbounded definitions',
    () {
      final j = _program('nested').toJson();
      j['plan'] = {
        'id': 'block',
        'type': 'repeat',
        'count': 3,
        'child': j['plan'],
      };
      final p = ProgramDefinition.fromJson(j);
      equal(p.dayCount, 6);
      final days = p.plan.occurrences().toList();
      equal(days.map((d) => d.path).toSet().length, 6);
      equal(days.first.path, 'block[0]/cycle/a');
      equal(days.last.path, 'block[2]/cycle/b');
      equal(p.dayAt(7).path, 'block[0]/cycle/b');
      jsonEqual(ProgramDefinition.fromJson(p.toJson()).toJson(), p.toJson());
      final duplicate = copyJson(j);
      jsonObject(
        jsonObject(duplicate['plan'], 'repeat')['child'],
        'group',
      )['id'] = 'a';
      rejects(() => ProgramDefinition.fromJson(duplicate));
      final huge = copyJson(j);
      jsonObject(huge['plan'], 'repeat')['count'] = 10000;
      rejects(() => ProgramDefinition.fromJson(huge));
      final unbounded = copyJson(j);
      jsonObject(unbounded['plan'], 'repeat').remove('count');
      rejects(() => ProgramDefinition.fromJson(unbounded));
      final bad = copyJson(j);
      jsonObject(bad['plan'], 'plan')['overrides'] = {};
      rejects(() => ProgramDefinition.fromJson(bad));
    },
  );

  test(
    'two active runs isolate cursor, raw history and accepted targets despite sharing one workout template',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-multi-program-',
      );
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        await _setup(store);
        equal(
          (await store.programRuns()).where((r) => r.status == 'active').length,
          2,
        );
        var strength = await _done(
          store,
          await _start(store, 'strength-run', 'strength-1', 1),
        );
        strength = await StoredTrainingService(store).edit(
          strength.id,
          strength.contentVersion,
          (s) => const TrainingService().complete(s, s.sets.first.id, {
            ...s.sets.first.actuals,
            'mass': Quantity('70', 'kg'),
          }),
        );
        final cardio = await _start(store, 'cardio-run', 'cardio-1', 2);
        equal(cardio.sets.first.suggested['mass']!.value.toString(), '60');
        check(cardio.sets.first.sources.isEmpty);
        equal((await ProgramService(store).run('strength-run')).cursor, 1);
        equal((await ProgramService(store).run('cardio-run')).cursor, 0);
        strength = await StoredTrainingService(store).edit(
          strength.id,
          strength.contentVersion,
          (s) => const TrainingService().complete(s, s.sets.first.id, {
            ...s.sets.first.actuals,
            'mass': Quantity('60', 'kg'),
          }),
        );
        final progression = StoredProgressionService(store);
        final proposal = await progression.propose(
          strength.id,
          'bench-heavy',
          _rule(),
        );
        equal(proposal.runId, 'strength-run');
        await progression.accept(
          strength.id,
          'bench-heavy',
          proposal.version,
          _accept(2),
        );
        final next = await _start(store, 'strength-run', 'strength-2', 3);
        equal(next.sets.first.suggested['reps']!.value.toString(), '9');
        equal(cardio.sets.first.suggested['reps']!.value.toString(), '8');
        await _done(store, cardio);
        final cardioProposal = await progression.propose(
          cardio.id,
          'bench-heavy',
          _rule(),
        );
        equal(cardioProposal.previousApplication, null);
        equal(cardioProposal.previousFailures, 0);
        await progression.accept(
          cardio.id,
          'bench-heavy',
          cardioProposal.version,
          _accept(3),
        );
        equal(
          (await progression.decision(strength.id, 'bench-heavy')).sequence,
          1,
        );
        equal(
          (await progression.decision(cardio.id, 'bench-heavy')).sequence,
          1,
        );
        final adhoc = await StoredTrainingService(
          store,
        ).start('adhoc', definition().id, 1, instant(4));
        equal(adhoc.sets.first.suggested['reps']!.value.toString(), '8');
        check(adhoc.sets.first.sources.isEmpty);
        await store.archive();
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'skips are neutral and retry-safe, finite runs finish and rotating runs keep separate occurrence identities',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-program-skips-',
      );
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        await StoredTrainingService(store).publish(definition(), 0);
        final service = ProgramService(store);
        await service.publish(_program('p'), 0);
        final run = await service.create(
          'finite',
          'p',
          1,
          instant(1),
          loop: false,
        );
        final first = await service.skip(
          run.id,
          run.contentVersion,
          'request-1',
          _finish(1),
        );
        jsonEqual(
          (await service.skip(
            run.id,
            run.contentVersion,
            'request-1',
            _finish(1),
          )).toJson(),
          first.toJson(),
        );
        equal((await service.run(run.id)).cursor, 1);
        await expectLater(
          service.skip(run.id, run.contentVersion, 'new-request', _finish(2)),
          throwsA(isA<BodyTmiException>()),
        );
        final current = await service.run(run.id);
        await service.skip(
          run.id,
          current.contentVersion,
          'request-2',
          _finish(2),
        );
        final complete = await service.run(run.id);
        equal(complete.status, 'completed');
        equal(complete.current, null);
        await expectLater(
          service.status(run.id, complete.contentVersion, 'active'),
          throwsA(isA<BodyTmiException>()),
        );
        final rotating = await service.create('rotation', 'p', 1, instant(1));
        for (var n = 0; n < 5; n++) {
          final r = await service.run(rotating.id);
          await service.skip(
            r.id,
            r.contentVersion,
            'rotation-$n',
            _finish(n + 1),
          );
        }
        final fifth = await service.run(rotating.id);
        equal(fifth.cursor, 5);
        equal(fifth.current!.path, 'cycle/b');
        equal((await store.sessions()).length, 0);
        equal((await store.progressionDecisions()).length, 0);
        await store.archive();
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'pause blocks new occurrences, existing sessions resume and finalization advances once even after corrections',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-program-resume-',
      );
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        await _setup(store);
        final service = ProgramService(store);
        final initial = await service.run('strength-run');
        var session = await service.start(
          initial.id,
          initial.contentVersion,
          'attached',
          instant(1),
        );
        await expectLater(
          service.start(
            initial.id,
            initial.contentVersion,
            'duplicate',
            instant(1),
          ),
          throwsA(isA<BodyTmiException>()),
        );
        final afterStart = await service.run(initial.id);
        await expectLater(
          StoredTrainingService(store).start(
            'stale-direct-start',
            definition().id,
            1,
            instant(1),
            programRun: initial,
          ),
          throwsA(isA<BodyTmiException>()),
        );
        await expectLater(
          StoredTrainingService(store).edit(
            session.id,
            session.contentVersion,
            (s) => TrainingSession(
              id: 'replacement',
              revision: s.revision,
              startedAt: s.startedAt,
              sets: s.sets,
            ),
          ),
          throwsA(isA<BodyTmiException>()),
        );
        equal(await store.session('stale-direct-start'), null);
        equal(
          (await service.run(initial.id)).contentVersion,
          afterStart.contentVersion,
        );
        final paused = await service.status(
          initial.id,
          afterStart.contentVersion,
          'paused',
        );
        jsonEqual(
          (await service.start(
            initial.id,
            initial.contentVersion,
            'attached',
            instant(1),
          )).toJson(),
          session.toJson(),
        );
        await expectLater(
          service.start(initial.id, paused.contentVersion, 'new', instant(2)),
          throwsA(isA<BodyTmiException>()),
        );
        await expectLater(
          service.skip(initial.id, paused.contentVersion, 'skip', _finish(2)),
          throwsA(isA<BodyTmiException>()),
        );
        await expectLater(
          StoredTrainingService(
            store,
          ).start('attached', definition().id, 1, instant(1)),
          throwsA(isA<BodyTmiException>()),
        );
        session = await _done(store, session);
        equal((await service.run(initial.id)).cursor, 1);
        equal((await service.run(initial.id)).status, 'paused');
        session = await StoredTrainingService(store).edit(
          session.id,
          session.contentVersion,
          (s) => const TrainingService().complete(s, s.sets.first.id, {
            ...s.sets.first.actuals,
            'reps': Quantity('10', 'rep'),
          }),
        );
        await StoredTrainingService(
          store,
        ).edit(session.id, session.contentVersion, (s) => s.finish(_finish(2)));
        equal((await store.programReceipts()).length, 1);
        equal((await service.run(initial.id)).cursor, 1);
        final state = await service.run(initial.id);
        await service.status(initial.id, state.contentVersion, 'active');
        final active = await service.run(initial.id);
        await _start(store, initial.id, 'next', 3);
        await expectLater(
          service.skip(
            initial.id,
            active.contentVersion + 1,
            'occupied',
            _finish(3),
          ),
          throwsA(isA<BodyTmiException>()),
        );
        equal((await service.run('cardio-run')).cursor, 0);
        await store.archive();
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'published programs pin workout revisions and existing runs ignore later library edits',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-program-pins-',
      );
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        await _setup(store);
        final service = ProgramService(store);
        final raw = definition().toJson();
        final slot = jsonObject((raw['slots']! as List<Object?>).first, 'slot');
        jsonObject(slot['targets'], 'targets')['mass'] = {
          'value': '80',
          'unit': 'kg',
        };
        await StoredTrainingService(
          store,
        ).publish(WorkoutDefinition.fromJson(raw), 1);
        await service.publish(_program('strength', revision: 2), 1);
        final old = await _start(store, 'strength-run', 'old-pin', 1);
        equal(old.revision.number, 1);
        equal(old.sets.first.suggested['mass']!.value.toString(), '60');
        await service.create('new-run', 'strength', 2, instant(1));
        final newer = await _start(store, 'new-run', 'new-pin', 2);
        equal(newer.revision.number, 2);
        equal(newer.sets.first.suggested['mass']!.value.toString(), '80');
        await expectLater(
          service.publish(_program('missing', revision: 99), 0),
          throwsA(isA<BodyTmiException>()),
        );
        check(
          !(await store.programRevisions()).any(
            (p) => p.definition.id == 'missing',
          ),
        );
        await store.archive();
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'program definitions, active bindings, receipts and isolated progression survive both portability formats',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-program-backup-',
      );
      var store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        await _setup(store);
        final done = await _done(
          store,
          await _start(store, 'strength-run', 'done', 1),
        );
        final progression = StoredProgressionService(store);
        final p = await progression.propose(done.id, 'bench-heavy', _rule());
        await progression.accept(done.id, 'bench-heavy', p.version, _accept(1));
        await _start(store, 'cardio-run', 'pending', 2);
        final original = canonicalJson((await store.archive()).toJson());
        equal(
          (await store.backup('${dir.path}/native'))['databaseSchemaVersion'],
          21,
        );
        equal(
          (await LogicalArchiveFiles.export(
            await store.archive(),
            '${dir.path}/logical.json',
          ))['format'],
          'bodytmi-logical-export/21',
        );
        final prepared = await LogicalArchiveFiles.prepare(
          '${dir.path}/logical.json',
        );
        try {
          equal(canonicalJson(prepared.archive.toJson()), original);
          await store.restore(
            prepared.backup,
            recoveryDestination: '${dir.path}/recovery',
            confirm: true,
          );
        } finally {
          await prepared.close();
        }
        await store.close();
        store = await TrainingStore.open('${dir.path}/db.sqlite');
        equal(canonicalJson((await store.archive()).toJson()), original);
        final native = await NativeBackup.prepare('${dir.path}/native');
        try {
          await store.restore(
            native,
            recoveryDestination: '${dir.path}/second-recovery',
            confirm: true,
          );
        } finally {
          await native.close();
        }
        await store.close();
        store = await TrainingStore.open('${dir.path}/db.sqlite');
        equal(canonicalJson((await store.archive()).toJson()), original);
        final next = await _start(store, 'strength-run', 'next', 3);
        equal(next.sets.first.suggested['reps']!.value.toString(), '9');
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'logical validation rejects forged run ownership, cursor paths, missing and duplicate receipts',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-program-invalid-',
      );
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        await _setup(store);
        final done = await _done(
          store,
          await _start(store, 'strength-run', 'done', 1),
        );
        final progression = StoredProgressionService(store);
        final p = await progression.propose(done.id, 'bench-heavy', _rule());
        await progression.accept(done.id, 'bench-heavy', p.version, _accept(1));
        await _start(store, 'cardio-run', 'pending', 2);
        final base = (await store.archive()).toJson();
        final mutations = <void Function(Map<String, Object?>)>[
          (j) => jsonObject(
            (j['programRuns']! as List<Object?>).first,
            'run',
          )['cursor'] = 99,
          (j) => (j['programReceipts']! as List<Object?>).clear(),
          (j) => (j['programReceipts']! as List<Object?>).add(
            (j['programReceipts']! as List<Object?>).first,
          ),
          (j) => jsonObject(
            (j['sessionPrograms']! as List<Object?>).first,
            'binding',
          )['path'] = 'forged',
          (j) => jsonObject(
            (j['progressions']! as List<Object?>).first,
            'decision',
          )['runId'] = 'cardio-run',
          (j) => jsonObject(
            (j['progressions']! as List<Object?>).first,
            'decision',
          ).remove('runId'),
          (j) => jsonObject(
            (j['sessionPrograms']! as List<Object?>).first,
            'binding',
          )['runId'] = 'missing-run',
          (j) => jsonObject(
            jsonObject(
              jsonObject(
                (j['programRuns']! as List<Object?>).first,
                'run',
              )['program'],
              'program',
            )['definition'],
            'definition',
          )['name'] = 'forged',
        ];
        for (final mutate in mutations) {
          final j = copyJson(base);
          mutate(j);
          rejects(() => TrainingArchive.fromJson(j));
        }
        await LogicalArchiveFiles.export(
          await store.archive(),
          '${dir.path}/new.json',
        );
        final file = File('${dir.path}/new.json');
        final doc = jsonObject(
          jsonDecode(await file.readAsString()),
          'document',
        );
        jsonObject(doc['data'], 'data').remove('families');
        doc['format'] = 'bodytmi-logical-export/2';
        doc.remove('sha256');
        doc['sha256'] = sha256
            .convert(utf8.encode(canonicalJson(doc)))
            .toString();
        await file.writeAsString(jsonEncode(doc));
        await expectLater(
          LogicalArchiveFiles.prepare(file.path),
          throwsA(isA<BodyTmiException>()),
        );
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'native program CLI selects runs and exposes cursor/resume state without a global active program',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-program-cli-');
      try {
        final path = '${dir.path}/db.sqlite';
        Future<Object?> call(String action, Map<String, Object?> fields) async {
          final r = await invoke(
            action.split(' '),
            jsonEncode({'schemaVersion': 1, 'database': path, ...fields}),
          );
          equal(r.code, 0);
          equal(r.error, '');
          return jsonObject(jsonDecode(r.output), 'response')['data'];
        }

        await call('store publish', {
          'definition': definition().toJson(),
          'expectedRevision': 0,
        });
        for (final p in ['strength', 'cardio']) {
          await call('program publish', {
            'definition': _program(p).toJson(),
            'expectedRevision': 0,
          });
          await call('run create', {
            'id': '$p-run',
            'programId': p,
            'revision': 1,
            'startedAt': instant(1).toIso8601String(),
          });
        }
        equal(
          (await call('run list', {'status': 'active'}) as List<Object?>)
              .length,
          2,
        );
        var s = sessionFromJson(
          await call('run start', {
            'runId': 'strength-run',
            'expectedVersion': 1,
            'id': 'cli',
            'startedAt': instant(1).toIso8601String(),
          }),
        );
        equal(
          jsonObject(
            await call('run show', {'runId': 'strength-run'}),
            'run',
          )['currentSessionId'],
          'cli',
        );
        for (final set in s.sets)
          s = sessionFromJson(
            await call('store complete', {
              'id': s.id,
              'setId': set.id,
              'expectedVersion': s.contentVersion,
              'acceptSuggested': true,
            }),
          );
        s = sessionFromJson(
          await call('store finish', {
            'id': s.id,
            'expectedVersion': s.contentVersion,
            'finishedAt': _finish(1).toIso8601String(),
          }),
        );
        equal(
          jsonObject(
            await call('run show', {'runId': 'strength-run'}),
            'run',
          )['cursor'],
          1,
        );
        equal(
          jsonObject(
            await call('run show', {'runId': 'cardio-run'}),
            'run',
          )['cursor'],
          0,
        );
        await call('store finish', {
          'id': s.id,
          'expectedVersion': s.contentVersion,
          'finishedAt': _finish(1).toIso8601String(),
        });
        equal(
          jsonObject(
            await call('run show', {'runId': 'strength-run'}),
            'run',
          )['cursor'],
          1,
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'program finalization crashes roll back or commit results, receipt and cursor together',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-program-crash-',
      );
      try {
        final path = '${dir.path}/db.sqlite';
        final store = await TrainingStore.open(path);
        try {
          await _setup(store);
          await _start(store, 'strength-run', 'crash', 1);
        } finally {
          await store.close();
        }
        final binary = await compileNative(
          'test/helpers/store_owner.dart',
          '${dir.path}/owner',
        );
        for (final mode in ['finish-rollback', 'finish-commit']) {
          final child = await Process.start(binary, [
            path,
            mode,
            'crash',
            _finish(1).toIso8601String(),
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
            final recovered = await TrainingStore.open(path);
            try {
              final committed = mode == 'finish-commit';
              final s = (await recovered.session('crash'))!;
              equal(
                s.status,
                committed ? SessionStatus.finalized : SessionStatus.active,
              );
              equal(
                (await ProgramService(recovered).run('strength-run')).cursor,
                committed ? 1 : 0,
              );
              equal(
                (await recovered.programReceipts()).length,
                committed ? 1 : 0,
              );
              equal(await recovered.finalizationCount(), committed ? 1 : 0);
              if (committed) {
                await StoredTrainingService(
                  recovered,
                ).edit(s.id, s.contentVersion, (s) => s.finish(_finish(2)));
                equal((await recovered.programReceipts()).length, 1);
              }
              await recovered.archive();
            } finally {
              await recovered.close();
            }
          } finally {
            child.kill(ProcessSignal.sigkill);
            await child.exitCode;
          }
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'v2 schema and logical exports migrate ad hoc receipts without inheriting them into new runs',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-program-v2-');
      try {
        final path = '${dir.path}/v2.sqlite';
        final rev = revision();
        final session = finished(start(id: 'legacy', from: rev));
        final decision = ProgressionDecision(
          session: session,
          slotId: 'bench-heavy',
          rule: _rule(),
        ).accept(_accept(1));
        final db = sqlite3.open(path);
        try {
          for (final ddl in schemaV2.values) db.execute(ddl);
          db.execute('PRAGMA application_id = 1112821065');
          db.execute('PRAGMA user_version = 2');
          db.execute('INSERT INTO revisions VALUES (?,?,?)', [
            rev.definition.id,
            1,
            jsonEncode(rev.toJson()),
          ]);
          db.execute('INSERT INTO sessions VALUES (?,?)', [
            session.id,
            jsonEncode(session.toJson()),
          ]);
          db.execute('INSERT INTO finalizations VALUES (?)', [session.id]);
          db.execute('INSERT INTO progression_decisions VALUES (?,?,?)', [
            session.id,
            'bench-heavy',
            canonicalJson(decision.toJson()),
          ]);
        } finally {
          db.close();
        }
        equal(
          (await NativeBackup.create(
            path,
            '${dir.path}/v2-native',
          ))['databaseSchemaVersion'],
          2,
        );
        final data = TrainingArchive(
          revisions: [rev],
          sessions: [session],
          finalizations: [session.id],
          progressions: [decision],
        ).toJson();
        for (final key in [
          'programRevisions',
          'programRuns',
          'sessionPrograms',
          'programReceipts',
          'bodyMass',
          'timers',
          'executions',
          'families',
        ])
          data.remove(key);
        final envelope = <String, Object?>{
          'format': 'bodytmi-logical-export/2',
          'applicationVersion': '0.1.0',
          'data': data,
        };
        envelope['sha256'] = sha256
            .convert(utf8.encode(canonicalJson(envelope)))
            .toString();
        await File('${dir.path}/v2.json').writeAsString(jsonEncode(envelope));
        final old = await LogicalArchiveFiles.prepare('${dir.path}/v2.json');
        try {
          equal(old.archive.progressions.single.runId, null);
          equal(old.archive.programRuns.length, 0);
        } finally {
          await old.close();
        }
        final store = await TrainingStore.open(path);
        try {
          equal((await store.progressionDecisions()).single.sequence, 1);
          await ProgramService(store).publish(_program('fresh'), 0);
          await ProgramService(store).create('new', 'fresh', 1, instant(2));
          final fresh = await _start(store, 'new', 'fresh', 3);
          equal(fresh.sets.first.suggested['reps']!.value.toString(), '8');
          final adhoc = await StoredTrainingService(
            store,
          ).start('adhoc', definition().id, 1, instant(3));
          equal(adhoc.sets.first.suggested['reps']!.value.toString(), '9');
          await store.archive();
        } finally {
          await store.close();
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
