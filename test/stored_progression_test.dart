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

Map<String, Object?> _rule() =>
    jsonObject(example('double-progression')['rule'], 'rule');
const _slot = 'bench-heavy';
Future<TrainingSession> _finished(
  TrainingStore store,
  String id,
  int day, {
  bool fail = false,
  bool skip = false,
}) async {
  final service = StoredTrainingService(store);
  final session = await service.start(id, definition().id, 1, instant(day));
  return service.edit(id, session.contentVersion, (s) {
    for (final set in s.sets) {
      s = skip
          ? const TrainingService().skip(s, set.id)
          : const TrainingService().complete(
              s,
              set.id,
              fail && set.slotId == _slot
                  ? {...set.suggested, 'reps': Quantity('1', 'rep')}
                  : const {},
              acceptSuggested: true,
            );
    }
    return s.finish(instant(day).add(const Duration(hours: 1)));
  });
}

DateTime _approval(int day) => instant(day).add(const Duration(hours: 2));

Future<void> _v1(String path) async {
  final db = sqlite3.open(path);
  try {
    for (final ddl in schemaV1.values) {
      db.execute(ddl);
    }
    db.execute('PRAGMA application_id = 1112821065');
    db.execute('PRAGMA user_version = 1');
    final rev = revision();
    db.execute('INSERT INTO revisions VALUES (?,?,?)', [
      rev.definition.id,
      1,
      jsonEncode(rev.toJson()),
    ]);
    final old = finished(start(id: 'legacy-history', from: rev));
    db.execute('INSERT INTO sessions VALUES (?,?)', [
      old.id,
      jsonEncode(old.toJson()),
    ]);
    db.execute('INSERT INTO finalizations VALUES (?)', [old.id]);
  } finally {
    db.close();
  }
}

void storedProgressionTests() {
  test(
    'warmups stay outside progression, changed loads require review and revision target edits require reconciliation',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-progression-context-',
      );
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final raw = definition().toJson();
        final children =
            jsonObject(raw['plan'], 'plan')['children']! as List<Object?>;
        children.insert(0, {
          'id': 'warmup',
          'type': 'effort',
          'slot': _slot,
          'role': 'warmup',
        });
        await StoredTrainingService(
          store,
        ).publish(WorkoutDefinition.fromJson(raw), 0);
        var s = await _finished(store, 'warmups', 1);
        s = await StoredTrainingService(store).edit(
          s.id,
          s.contentVersion,
          (s) => const TrainingService().complete(s, s.sets.first.id, {
            ...s.sets.first.actuals,
            'reps': Quantity('1', 'rep'),
          }),
        );
        final service = StoredProgressionService(store);
        final p = await service.propose(s.id, _slot, _rule());
        equal(p.proposal.outcome, 'increaseObjective');
        equal(p.sets.length, 3);
        await service.accept(s.id, _slot, p.version, _approval(1));
        var next = await _finished(store, 'changed-load', 2);
        equal(next.sets.first.suggested['reps']!.value.toString(), '8');
        equal(next.sets[1].suggested['reps']!.value.toString(), '9');
        next = await StoredTrainingService(store).edit(
          next.id,
          next.contentVersion,
          (s) => const TrainingService().complete(s, s.sets[1].id, {
            ...s.sets[1].actuals,
            'mass': Quantity('65', 'kg'),
          }),
        );
        final review = await service.propose(next.id, _slot, _rule());
        equal(review.proposal.outcome, 'review');
        await expectLater(
          service.accept(next.id, _slot, review.version, _approval(2)),
          throwsA(isA<BodyTmiException>()),
        );
        final heavy = jsonObject(
          (raw['slots']! as List<Object?>).first,
          'slot',
        );
        jsonObject(heavy['targets'], 'targets')['mass'] = {
          'value': '65',
          'unit': 'kg',
        };
        await StoredTrainingService(
          store,
        ).publish(WorkoutDefinition.fromJson(raw), 1);
        await expectLater(
          StoredTrainingService(
            store,
          ).start('target-edited', definition().id, 2, instant(3)),
          throwsA(isA<BodyTmiException>()),
        );
        heavy['setupNote'] = 'Changed equipment setup';
        await StoredTrainingService(
          store,
        ).publish(WorkoutDefinition.fromJson(raw), 2);
        final separate = await StoredTrainingService(
          store,
        ).start('new-context', definition().id, 3, instant(4));
        equal(separate.sets[1].suggested['mass']!.value.toString(), '65');
        equal(separate.sets[1].suggested['reps']!.value.toString(), '8');
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'interrupted real Drift migration rolls back and retries without losing v1 data',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-migrate-crash-',
      );
      try {
        final path = '${dir.path}/old.sqlite';
        await _v1(path);
        final binary = await compileNative(
          'packages/bodytmi_storage/test/migration_owner.dart',
          '${dir.path}/migrator',
        );
        final child = await Process.start(binary, [path]);
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
          final raw = sqlite3.open(path);
          try {
            equal(raw.userVersion, 1);
            equal(
              raw
                  .select(
                    "SELECT name FROM sqlite_master WHERE name='progression_decisions'",
                  )
                  .length,
              0,
            );
          } finally {
            raw.close();
          }
          final store = await TrainingStore.open(path);
          try {
            equal((await store.archive()).revisions.length, 1);
            equal(
              (await store.session('legacy-history'))!.status,
              SessionStatus.finalized,
            );
            equal(await store.finalizationCount(), 1);
            equal((await store.progressionDecisions()).length, 0);
          } finally {
            await store.close();
          }
        } finally {
          child.kill(ProcessSignal.sigkill);
          await child.exitCode;
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'successful receipt resets prior failures and imported receipt tampering is rejected',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-receipt-integrity-',
      );
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        await StoredTrainingService(store).publish(definition(), 0);
        final service = StoredProgressionService(store);
        final first = await _finished(store, 'failure', 1, fail: true);
        final failed = await service.propose(first.id, _slot, _rule());
        await service.accept(first.id, _slot, failed.version, _approval(1));
        final second = await _finished(store, 'success', 2);
        final success = await service.propose(second.id, _slot, _rule());
        equal(success.previousFailures, 1);
        equal(success.proposal.failedSessions, 0);
        await service.accept(second.id, _slot, success.version, _approval(2));
        final archive = (await store.archive()).toJson();
        final mutations = <void Function(Map<String, Object?>)>[
          (j) => (j['progressions']! as List<Object?>).add(
            (j['progressions']! as List<Object?>).first,
          ),
          (j) => jsonObject(
            (j['progressions']! as List<Object?>).first,
            'decision',
          )['previousApplication'] = 'missing/slot',
          (j) {
            final d = jsonObject(
              (j['progressions']! as List<Object?>).first,
              'decision',
            );
            final p = jsonObject(d['proposal'], 'proposal');
            jsonObject(p['nextState'], 'state')['failedSessions'] = 99;
          },
        ];
        for (final mutate in mutations) {
          final j = copyJson(archive);
          mutate(j);
          rejects(() => TrainingArchive.fromJson(j));
        }
        final rawRule = _rule();
        final copy = ProgressionDecision(
          session: second,
          slotId: _slot,
          rule: rawRule,
        );
        jsonObject(rawRule['lower'], 'lower')['value'] = '10';
        equal(jsonObject(copy.rule['lower'], 'lower')['value'], '8');
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'durable double progression applies once, seeds later targets and keeps slot/revision history independent',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-receipts-');
      final path = '${dir.path}/db.sqlite';
      var store = await TrainingStore.open(path);
      try {
        await StoredTrainingService(store).publish(definition(), 0);
        final done = await _finished(store, 'first', 1);
        var service = StoredProgressionService(store);
        final pending = await service.propose(done.id, _slot, _rule());
        equal(pending.proposal.outcome, 'increaseObjective');
        equal(pending.acceptedAt, null);
        equal((await service.propose(done.id, _slot, _rule())).version, 1);
        final applied = await service.accept(
          done.id,
          _slot,
          pending.version,
          _approval(1),
        );
        equal(applied.sequence, 1);
        await store.close();
        store = await TrainingStore.open(path);
        service = StoredProgressionService(store);
        jsonEqual(
          (await service.accept(
            done.id,
            _slot,
            pending.version,
            _approval(2),
          )).toJson(),
          applied.toJson(),
        );
        final next = await StoredTrainingService(
          store,
        ).start('next', definition().id, 1, instant(2));
        equal(next.sets.first.suggested['reps']!.value.toString(), '9');
        equal(next.sets.last.suggested['reps']!.value.toString(), '12');
        equal(
          next.revision.definition
              .slot(_slot)
              .targets['reps']!
              .value
              .toString(),
          '8',
        );
        equal(
          (await StoredTrainingService(store).revision(definition().id)).number,
          1,
        );
        final edited = await StoredTrainingService(store).edit(
          done.id,
          done.contentVersion,
          (s) => const TrainingService().complete(s, s.sets.first.id, {
            ...s.sets.first.actuals,
            'reps': Quantity('11', 'rep'),
          }),
        );
        check(await service.stale(applied));
        await StoredTrainingService(
          store,
        ).edit(done.id, edited.contentVersion, (s) => s.finish(_approval(2)));
        equal((await service.propose(done.id, _slot, _rule())).sequence, 1);
        equal(
          (await service.accept(
            done.id,
            _slot,
            pending.version,
            _approval(3),
          )).sequence,
          1,
        );
        equal((await store.progressionDecisions()).length, 1);
        equal(await store.finalizationCount(), 1);
        // An explicitly backdated session cannot consume a future accepted target.
        final old = await StoredTrainingService(
          store,
        ).start('backdated', definition().id, 1, instant(1));
        equal(old.sets.first.suggested['reps']!.value.toString(), '8');
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'edited or competing inputs invalidate pending approvals without overwriting later state',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-stale-receipt-',
      );
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        await StoredTrainingService(store).publish(definition(), 0);
        final a = await _finished(store, 'a', 1);
        final b = await _finished(store, 'b', 2);
        final service = StoredProgressionService(store);
        final first = await service.propose(a.id, _slot, _rule());
        final competing = await service.propose(b.id, _slot, _rule());
        await StoredTrainingService(store).edit(
          a.id,
          a.contentVersion,
          (s) => const TrainingService().complete(s, s.sets.first.id, {
            ...s.sets.first.actuals,
            'reps': Quantity('9', 'rep'),
          }),
        );
        await expectLater(
          service.accept(a.id, _slot, first.version, _approval(3)),
          throwsA(isA<BodyTmiException>()),
        );
        final refreshed = await service.propose(a.id, _slot, _rule());
        equal(refreshed.version, 2);
        await expectLater(
          service.accept(a.id, _slot, first.version, _approval(3)),
          throwsA(isA<BodyTmiException>()),
        );
        await service.accept(a.id, _slot, refreshed.version, _approval(3));
        check(await service.stale(competing));
        await expectLater(
          service.accept(b.id, _slot, competing.version, _approval(4)),
          throwsA(isA<BodyTmiException>()),
        );
        await expectLater(
          service.propose(b.id, _slot, _rule()),
          throwsA(isA<BodyTmiException>()),
        );
        equal(
          (await store.progressionDecisions())
              .where((d) => d.acceptedAt != null)
              .length,
          1,
        );
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'accepted failures count exposures once, skips remain neutral and third failure applies one deload',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-counter-receipt-',
      );
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        await StoredTrainingService(store).publish(definition(), 0);
        final service = StoredProgressionService(store);
        for (var day = 1; day <= 3; day++) {
          final s = await _finished(store, 'failure-$day', day, fail: true);
          final p = await service.propose(s.id, _slot, _rule());
          equal(p.proposal.outcome, day == 3 ? 'deload' : 'failed');
          final applied = await service.accept(
            s.id,
            _slot,
            p.version,
            _approval(day),
          );
          equal(applied.proposal.failedSessions, day == 3 ? 0 : day);
          equal(
            (await service.accept(
              s.id,
              _slot,
              p.version,
              _approval(day),
            )).sequence,
            day,
          );
        }
        final next = await StoredTrainingService(
          store,
        ).start('after-deload', definition().id, 1, instant(4));
        equal(next.sets.first.suggested['mass']!.value.toString(), '54');
        equal(next.sets.first.suggested['reps']!.value.toString(), '8');
        final skipped = await _finished(store, 'skipped', 5, skip: true);
        final p = await service.propose(skipped.id, _slot, _rule());
        equal(p.proposal.outcome, 'unknown');
        await expectLater(
          service.accept(skipped.id, _slot, p.version, _approval(5)),
          throwsA(isA<BodyTmiException>()),
        );
        equal(
          (await store.progressionDecisions())
              .where((d) => d.acceptedAt != null)
              .length,
          3,
        );
        final success = await _finished(store, 'success', 6);
        final successProposal = await service.propose(
          success.id,
          _slot,
          _rule(),
        );
        equal(successProposal.proposal.failedSessions, 0);
        await service.accept(
          success.id,
          _slot,
          successProposal.version,
          _approval(6),
        );
        equal((await store.archive()).progressions.length, 5);
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'receipts and pending stale proposals round-trip through native and logical formats',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-receipt-portability-',
      );
      var store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        await StoredTrainingService(store).publish(definition(), 0);
        final s = await _finished(store, 'accepted', 1);
        final service = StoredProgressionService(store);
        final p = await service.propose(s.id, _slot, _rule());
        await service.accept(s.id, _slot, p.version, _approval(1));
        final next = await _finished(store, 'pending', 2);
        await service.propose(next.id, _slot, _rule());
        await StoredTrainingService(store).edit(
          next.id,
          next.contentVersion,
          (s) => const TrainingService().complete(s, s.sets.first.id, {
            ...s.sets.first.actuals,
            'reps': Quantity('10', 'rep'),
          }),
        );
        final original = canonicalJson((await store.archive()).toJson());
        final manifest = await store.backup('${dir.path}/native');
        equal(manifest['databaseSchemaVersion'], 45);
        await LogicalArchiveFiles.export(
          await store.archive(),
          '${dir.path}/logical.json',
        );
        final logical = await LogicalArchiveFiles.prepare(
          '${dir.path}/logical.json',
        );
        try {
          equal(canonicalJson(logical.archive.toJson()), original);
          await store.restore(
            logical.backup,
            recoveryDestination: '${dir.path}/recovery',
            confirm: true,
          );
        } finally {
          await logical.close();
        }
        await store.close();
        store = await TrainingStore.open('${dir.path}/db.sqlite');
        equal(canonicalJson((await store.archive()).toJson()), original);
        final loaded = StoredProgressionService(store);
        check(await loaded.stale(await loaded.decision(next.id, _slot)));
        equal(
          (await loaded.accept(s.id, _slot, p.version, _approval(3))).sequence,
          1,
        );
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
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'schema v1 migrates without losing history and legacy native/logical backups remain readable',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-v1-migration-',
      );
      try {
        final old = '${dir.path}/v1.sqlite';
        await _v1(old);
        final manifest = await NativeBackup.create(
          old,
          '${dir.path}/v1-backup',
        );
        equal(manifest['databaseSchemaVersion'], 1);
        final legacy = <String, Object?>{
          'format': 'bodytmi-logical-export/1',
          'applicationVersion': '0.1.0',
          'data': {
            'revisions': [revision().toJson()],
            'sessions': <Object?>[],
            'finalizations': <Object?>[],
          },
        };
        legacy['sha256'] = sha256
            .convert(utf8.encode(canonicalJson(legacy)))
            .toString();
        await File('${dir.path}/v1.json').writeAsString(jsonEncode(legacy));
        final logical = await LogicalArchiveFiles.prepare(
          '${dir.path}/v1.json',
        );
        try {
          equal(logical.summary['format'], 'bodytmi-logical-export/1');
          equal(logical.archive.revisions.length, 1);
        } finally {
          await logical.close();
        }
        final store = await TrainingStore.open(old);
        try {
          equal((await store.revision(definition().id))!.number, 1);
          equal((await store.progressionDecisions()).length, 0);
          final native = await NativeBackup.prepare('${dir.path}/v1-backup');
          try {
            await store.restore(
              native,
              recoveryDestination: '${dir.path}/recovery',
              confirm: true,
            );
          } finally {
            await native.close();
          }
        } finally {
          await store.close();
        }
        final reopened = await TrainingStore.open(old);
        try {
          equal((await reopened.archive()).revisions.length, 1);
        } finally {
          await reopened.close();
        }
        final db = sqlite3.open(old);
        try {
          equal(db.userVersion, 45);
        } finally {
          db.close();
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'progression CLI proposes, accepts, retries and seeds a later session across native processes',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-progression-cli-',
      );
      try {
        final path = '${dir.path}/db.sqlite';
        final store = await TrainingStore.open(path);
        try {
          await StoredTrainingService(store).publish(definition(), 0);
          await _finished(store, 'cli', 1);
        } finally {
          await store.close();
        }
        Future<Map<String, Object?>> call(
          String action,
          Map<String, Object?> fields,
        ) async {
          final r = await invoke(
            action.split(' '),
            jsonEncode({'schemaVersion': 1, 'database': path, ...fields}),
          );
          equal(r.code, 0);
          equal(r.error, '');
          return jsonObject(
            jsonObject(jsonDecode(r.output), 'response')['data'],
            'data',
          );
        }

        final proposed = await call('progression propose', {
          'sessionId': 'cli',
          'slotId': _slot,
          'rule': _rule(),
        });
        equal(proposed['applied'], false);
        final accept = {
          'sessionId': 'cli',
          'slotId': _slot,
          'expectedVersion': 1,
          'acceptedAt': _approval(1).toIso8601String(),
        };
        final applied = await call('progression accept', accept);
        equal(applied['applied'], true);
        equal(applied['sequence'], 1);
        jsonEqual(await call('progression accept', accept), applied);
        final started = await call('store start', {
          'id': 'later',
          'templateId': definition().id,
          'revision': 1,
          'startedAt': instant(2).toIso8601String(),
        });
        equal(
          sessionFromJson(
            started,
          ).sets.first.suggested['reps']!.value.toString(),
          '9',
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'transactional acceptance recovers before/after commit without a second application',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-accept-crash-',
      );
      try {
        final path = '${dir.path}/db.sqlite';
        final store = await TrainingStore.open(path);
        try {
          await StoredTrainingService(store).publish(definition(), 0);
          final s = await _finished(store, 'crash', 1);
          await StoredProgressionService(store).propose(s.id, _slot, _rule());
        } finally {
          await store.close();
        }
        final binary = await compileNative(
          'test/helpers/store_owner.dart',
          '${dir.path}/owner',
        );
        for (final mode in ['accept-rollback', 'accept-commit']) {
          final child = await Process.start(binary, [
            path,
            mode,
            'crash',
            _slot,
            _approval(1).toIso8601String(),
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
              final service = StoredProgressionService(recovered);
              final d = await service.decision('crash', _slot);
              equal(d.acceptedAt != null, mode == 'accept-commit');
              if (mode == 'accept-commit')
                equal(
                  (await service.accept(
                    'crash',
                    _slot,
                    1,
                    _approval(2),
                  )).sequence,
                  1,
                );
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
}
