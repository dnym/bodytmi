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

const _slot = 'bench-heavy';
Map<String, Object?> _rule() =>
    jsonObject(example('double-progression')['rule'], 'rule');
DateTime _at(int day) => instant(day).add(const Duration(hours: 2));
Future<void> _fails(Future<Object?> action) =>
    expectLater(action, throwsA(isA<BodyTmiException>()));
Future<void> _withStore(
  Future<void> Function(TrainingStore, String) action,
) async {
  final dir = await Directory.systemTemp.createTemp('bodytmi-decline-');
  final store = await TrainingStore.open('${dir.path}/db.sqlite');
  try {
    await StoredTrainingService(store).publish(definition(), 0);
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
  bool fail = false,
  bool skip = false,
  bool changedLoad = false,
  String? run,
}) async {
  final training = StoredTrainingService(store);
  final started = run == null
      ? await training.start(id, definition().id, 1, instant(day))
      : await ProgramService(store).start(
          run,
          (await ProgramService(store).run(run)).contentVersion,
          id,
          instant(day),
        );
  return training.edit(started.id, started.contentVersion, (s) {
    for (final set in s.sets) {
      s = skip
          ? const TrainingService().skip(s, set.id, confirm: true)
          : const TrainingService().complete(s, set.id, {
              if (fail && set.slotId == _slot) 'reps': Quantity('1', 'rep'),
              if (changedLoad && set.slotId == _slot)
                'mass': Quantity('59', 'kg'),
            }, acceptSuggested: true);
    }
    return s.finish(instant(day).add(const Duration(hours: 1)));
  });
}

void declineTests() {
  test(
    'declining advancement holds targets and resolves the exposure once through later corrections and competing actions',
    () => _withStore((store, dir) async {
      final service = StoredProgressionService(store);
      final s = await _finish(store, 'one', 1);
      final p = await service.propose(s.id, _slot, _rule());
      equal(p.proposal.outcome, 'increaseObjective');
      final d = await service.decline(s.id, _slot, p.version, _at(1));
      equal(d.status, 'declined');
      equal(d.sequence, 1);
      equal(d.failedSessions, 0);
      equal(d.acceptedAt, null);
      equal(d.nextSets.first['reps']!.value.toString(), '8');
      equal(d.proposal.nextSets.first['reps']!.value.toString(), '9');
      await _fails(service.accept(s.id, _slot, p.version, _at(1)));
      var corrected = await StoredTrainingService(store).edit(
        s.id,
        s.contentVersion,
        (s) => const TrainingService().complete(s, s.sets.first.id, {
          'reps': Quantity('12', 'rep'),
        }, acceptSuggested: true),
      );
      corrected = await StoredTrainingService(
        store,
      ).edit(corrected.id, corrected.contentVersion, (s) => s.finish(_at(1)));
      equal(await service.stale(d), true);
      final retry = await service.decline(s.id, _slot, p.version, _at(2));
      jsonEqual(retry.toJson(), d.toJson());
      jsonEqual(
        (await service.propose(s.id, _slot, _rule())).toJson(),
        d.toJson(),
      );
      await _fails(
        service.propose(s.id, _slot, {..._rule(), 'deloadAfter': 9}),
      );
      final next = await _finish(store, 'two', 2);
      equal(next.sets.first.suggested['reps']!.value.toString(), '8');
      final proposed = await service.propose(next.id, _slot, _rule());
      equal(proposed.previousApplication, d.id);
      equal(proposed.previousSequence, 1);
      await service.accept(next.id, _slot, proposed.version, _at(2));
      await _fails(service.decline(next.id, _slot, proposed.version, _at(2)));
      final third = await _finish(store, 'three', 3);
      equal(third.sets.first.suggested['reps']!.value.toString(), '9');
      await store.archive();
    }),
  );
  test(
    'declined deload retains the failure count and load, then the next accepted deload resets once',
    () => _withStore((store, dir) async {
      final service = StoredProgressionService(store);
      for (var day = 1; day <= 2; day++) {
        await _finish(store, 'fail-$day', day, fail: true);
        final p = await service.propose('fail-$day', _slot, _rule());
        final applied = await service.accept(
          'fail-$day',
          _slot,
          p.version,
          _at(day),
        );
        equal(applied.failedSessions, day);
      }
      await _finish(store, 'fail-3', 3, fail: true);
      final p = await service.propose('fail-3', _slot, _rule());
      equal(p.proposal.outcome, 'deload');
      equal(p.proposal.failedSessions, 0);
      final declined = await service.decline(
        'fail-3',
        _slot,
        p.version,
        _at(3),
      );
      equal(declined.failedSessions, 3);
      equal(declined.sequence, 3);
      equal(declined.nextSets.first['mass']!.value.toString(), '60');
      for (var i = 0; i < 3; i++) {
        equal(
          (await service.decline(
            'fail-3',
            _slot,
            p.version,
            _at(3),
          )).failedSessions,
          3,
        );
        equal((await service.propose('fail-3', _slot, _rule())).sequence, 3);
      }
      final fourth = await _finish(store, 'fail-4', 4, fail: true);
      equal(fourth.sets.first.suggested['mass']!.value.toString(), '60');
      final next = await service.propose(fourth.id, _slot, _rule());
      equal(next.previousFailures, 3);
      equal(next.proposal.outcome, 'deload');
      final accepted = await service.accept(
        fourth.id,
        _slot,
        next.version,
        _at(4),
      );
      equal(accepted.failedSessions, 0);
      equal(accepted.sequence, 4);
      final fifth = await _finish(store, 'success', 5);
      equal(fifth.sets.first.suggested['mass']!.value.toString(), '54');
      await store.archive();
    }),
  );
  test(
    'declined success resets failures, while unknown or changed-load declines preserve the prior counter',
    () => _withStore((store, dir) async {
      final service = StoredProgressionService(store);
      await _finish(store, 'failed', 1, fail: true);
      var p = await service.propose('failed', _slot, _rule());
      var d = await service.decline('failed', _slot, p.version, _at(1));
      equal(d.failedSessions, 1);
      await _finish(store, 'skipped', 2, skip: true);
      p = await service.propose('skipped', _slot, _rule());
      equal(p.proposal.outcome, 'unknown');
      d = await service.decline('skipped', _slot, p.version, _at(2));
      equal(d.failedSessions, 1);
      await _finish(store, 'changed', 3, changedLoad: true);
      p = await service.propose('changed', _slot, _rule());
      equal(p.proposal.outcome, 'review');
      d = await service.decline('changed', _slot, p.version, _at(3));
      equal(d.failedSessions, 1);
      await _finish(store, 'success', 4);
      p = await service.propose('success', _slot, _rule());
      d = await service.decline('success', _slot, p.version, _at(4));
      equal(d.failedSessions, 0);
      equal(d.nextSets.first['reps']!.value.toString(), '8');
      await store.archive();
    }),
  );
  test(
    'decline requires current input/version lineage and valid resolution chronology',
    () => _withStore((store, dir) async {
      final service = StoredProgressionService(store);
      final s = await _finish(store, 'one', 1);
      var p = await service.propose(s.id, _slot, _rule());
      await _fails(service.decline(s.id, _slot, p.version + 1, _at(1)));
      await _fails(service.decline(s.id, _slot, p.version, instant(1)));
      await StoredTrainingService(store).edit(
        s.id,
        s.contentVersion,
        (s) => const TrainingService().complete(s, s.sets.first.id, {
          'reps': Quantity('9', 'rep'),
        }, acceptSuggested: true),
      );
      await _fails(service.decline(s.id, _slot, p.version, _at(1)));
      p = await service.propose(s.id, _slot, _rule());
      equal(p.version, 2);
      final other = await _finish(store, 'other', 2);
      var q = await service.propose(other.id, _slot, _rule());
      await service.decline(other.id, _slot, q.version, _at(2));
      await _fails(service.decline(s.id, _slot, p.version, _at(3)));
      p = await service.propose(s.id, _slot, _rule());
      await _fails(service.decline(s.id, _slot, p.version, _at(1)));
      final d = await service.decline(s.id, _slot, p.version, _at(3));
      equal(d.previousApplication, q.id);
      equal(d.sequence, 2);
      await store.archive();
    }),
  );
  test(
    'declined exposure counters and retained prescriptions remain isolated across simultaneous program runs',
    () => _withStore((store, dir) async {
      final programs = ProgramService(store),
          service = StoredProgressionService(store);
      for (final id in ['strength', 'cardio']) {
        await programs.publish(
          ProgramDefinition.fromJson({
            'id': id,
            'name': id,
            'plan': {
              'id': 'day',
              'type': 'day',
              'templateId': definition().id,
              'revision': 1,
            },
          }),
          0,
        );
        await programs.create(id, id, 1, instant(1), loop: true);
      }
      await _finish(store, 'strength-one', 1, fail: true, run: 'strength');
      var p = await service.propose('strength-one', _slot, _rule());
      await service.decline('strength-one', _slot, p.version, _at(1));
      final strength = canonicalJson((await programs.run('strength')).toJson());
      final cardio = await _finish(store, 'cardio-one', 2, run: 'cardio');
      p = await service.propose(cardio.id, _slot, _rule());
      equal(p.previousFailures, 0);
      equal(p.previousApplication, null);
      await service.accept(cardio.id, _slot, p.version, _at(2));
      equal(canonicalJson((await programs.run('strength')).toJson()), strength);
      final next = await _finish(
        store,
        'strength-two',
        3,
        fail: true,
        run: 'strength',
      );
      p = await service.propose(next.id, _slot, _rule());
      equal(p.previousFailures, 1);
      equal(p.sets.first.suggested['reps']!.value.toString(), '8');
      await store.archive();
    }),
  );
  test(
    'resolved decline receipts are immutable and aggregate validation rejects forged resolution and lineage',
    () => _withStore((store, dir) async {
      final service = StoredProgressionService(store);
      await _finish(store, 'one', 1, fail: true);
      var p = await service.propose('one', _slot, _rule());
      final d = await service.decline('one', _slot, p.version, _at(1));
      final reopened = copyJson(d.toJson())..remove('declinedAt');
      await _fails(
        store.saveProgressionDecision(ProgressionDecision.fromJson(reopened)),
      );
      await _finish(store, 'two', 2, fail: true);
      p = await service.propose('two', _slot, _rule());
      await service.decline('two', _slot, p.version, _at(2));
      final base = (await store.archive()).toJson();
      final changes = <void Function(List<Object?>)>[
        (rows) => jsonObject(rows.first, 'decision')['acceptedAt'] = _at(
          1,
        ).toIso8601String(),
        (rows) => jsonObject(rows.first, 'decision')['declinedAt'] = instant(
          1,
        ).toIso8601String(),
        (rows) => jsonObject(rows.first, 'decision')['declinedAt'] = null,
        (rows) => jsonObject(rows.last, 'decision')['previousFailures'] = 9,
        (rows) =>
            jsonObject(rows.last, 'decision')['previousApplication'] = null,
        (rows) => jsonObject(rows.last, 'decision')['declinedAt'] = _at(
          1,
        ).toIso8601String(),
      ];
      for (final change in changes) {
        final j = copyJson(base);
        change(jsonList(j, 'progressions'));
        rejects(() => TrainingArchive.fromJson(j));
      }
    }),
  );
  test(
    'v10 profiles migrate unchanged and v11 native/logical restoration retains declines while old labels reject them',
    () => _withStore((store, dir) async {
      await _finish(store, 'one', 1, fail: true);
      final service = StoredProgressionService(store);
      final p = await service.propose('one', _slot, _rule());
      final before = canonicalJson((await store.archive()).toJson());
      check(!p.toJson().containsKey('declinedAt'));
      await store.backup('$dir/old');
      await LogicalArchiveFiles.export(await store.archive(), '$dir/old.json');
      final oldJson = jsonObject(
        jsonDecode(await File('$dir/old.json').readAsString()),
        'old',
      );
      jsonObject(oldJson['data'], 'data').remove('families');
      oldJson['format'] = 'bodytmi-logical-export/10';
      oldJson.remove('sha256');
      oldJson['sha256'] = sha256
          .convert(utf8.encode(canonicalJson(oldJson)))
          .toString();
      await File('$dir/old.json').writeAsString(jsonEncode(oldJson));
      final legacy = await LogicalArchiveFiles.prepare('$dir/old.json');
      try {
        equal(canonicalJson(legacy.archive.toJson()), before);
      } finally {
        await legacy.close();
      }
      final old = sqlite3.open('$dir/old/database.sqlite');
      old.execute('DROP TABLE family_revisions');
      old.execute('DROP TABLE derived_target_graphs');
      old.userVersion = 10;
      old.close();
      equal(NativeBackup.validateDatabase('$dir/old/database.sqlite'), 10);
      await store.close();
      final migrated = await TrainingStore.open('$dir/old/database.sqlite');
      try {
        equal(canonicalJson((await migrated.archive()).toJson()), before);
        equal(
          (await migrated.backup('$dir/migrated'))['databaseSchemaVersion'],
          27,
        );
      } finally {
        await migrated.close();
      }
      var active = await TrainingStore.open('$dir/db.sqlite');
      try {
        await StoredProgressionService(
          active,
        ).decline('one', _slot, p.version, _at(1));
        await _finish(active, 'two', 2, fail: true);
        var next = await StoredProgressionService(
          active,
        ).propose('two', _slot, _rule());
        equal(next.previousFailures, 1);
        final expected = canonicalJson((await active.archive()).toJson());
        await active.backup('$dir/native');
        equal(
          (await LogicalArchiveFiles.export(
            await active.archive(),
            '$dir/new.json',
          ))['format'],
          'bodytmi-logical-export/27',
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
        final retry = await StoredProgressionService(
          active,
        ).decline('one', _slot, p.version, _at(3));
        equal(retry.failedSessions, 1);
        next = await StoredProgressionService(
          active,
        ).accept('two', _slot, next.version, _at(2));
        equal(next.failedSessions, 2);
      } finally {
        await active.close();
      }
      final forged = sqlite3.open('$dir/native/database.sqlite');
      forged.execute('DROP TABLE family_revisions');
      forged.execute('DROP TABLE derived_target_graphs');
      forged.userVersion = 10;
      forged.close();
      rejects(
        () => NativeBackup.validateDatabase('$dir/native/database.sqlite'),
      );
      final mislabeled = jsonObject(
        jsonDecode(await File('$dir/new.json').readAsString()),
        'logical',
      );
      jsonObject(mislabeled['data'], 'data').remove('families');
      mislabeled['format'] = 'bodytmi-logical-export/10';
      mislabeled.remove('sha256');
      mislabeled['sha256'] = sha256
          .convert(utf8.encode(canonicalJson(mislabeled)))
          .toString();
      await File('$dir/new.json').writeAsString(jsonEncode(mislabeled));
      await _fails(LogicalArchiveFiles.prepare('$dir/new.json'));
    }),
  );
  test(
    'native progression decline exposes held targets and counted failures across retries and result edits',
    () => _withStore((store, dir) async {
      final session = await _finish(store, 'one', 1, fail: true);
      await store.close();
      Future<Map<String, Object?>> command(
        String action,
        Map<String, Object?> input,
      ) async {
        final r = await invoke(
          action.split(' '),
          jsonEncode({
            'schemaVersion': 1,
            'database': '$dir/db.sqlite',
            ...input,
          }),
        );
        equal(r.code, 0);
        equal(r.error, '');
        return jsonObject(
          jsonObject(jsonDecode(r.output), 'response')['data'],
          'data',
        );
      }

      final p = await command('progression propose', {
        'sessionId': 'one',
        'slotId': _slot,
        'rule': _rule(),
      });
      equal(p['status'], 'pending');
      equal(p['resolvedState'], null);
      final request = {
        'sessionId': 'one',
        'slotId': _slot,
        'expectedVersion': p['version'],
        'declinedAt': _at(1).toIso8601String(),
      };
      final d = await command('progression decline', request);
      equal(d['status'], 'declined');
      equal(d['applied'], false);
      equal(d['stale'], false);
      equal(jsonObject(d['resolvedState'], 'state')['failedSessions'], 1);
      jsonEqual(await command('progression decline', request), d);
      await command('store complete', {
        'id': 'one',
        'setId': session.sets.first.id,
        'expectedVersion': session.contentVersion,
        'actuals': {
          'mass': {'value': '60', 'unit': 'kg'},
          'reps': {'value': '12', 'unit': 'rep'},
        },
      });
      final viewed = await command('progression show', {
        'sessionId': 'one',
        'slotId': _slot,
      });
      equal(viewed['inputsChanged'], true);
      equal(viewed['stale'], false);
      equal(viewed['status'], 'declined');
      equal((await command('progression decline', request))['sequence'], 1);
      final rejected = await invoke(
        ['progression', 'accept'],
        jsonEncode({
          'schemaVersion': 1,
          'database': '$dir/db.sqlite',
          'sessionId': 'one',
          'slotId': _slot,
          'expectedVersion': p['version'],
          'acceptedAt': _at(2).toIso8601String(),
        }),
      );
      check(rejected.code != 0);
      equal(rejected.output, '');
    }),
  );
  test(
    'process death rolls back or commits decline counter/receipt together and retry cannot recount the exposure',
    () => _withStore((store, dir) async {
      await _finish(store, 'one', 1, fail: true);
      await StoredProgressionService(store).propose('one', _slot, _rule());
      await store.close();
      final binary = await compileNative(
        'test/helpers/store_owner.dart',
        '$dir/owner',
      );
      for (final mode in ['decline-rollback', 'decline-commit']) {
        final child = await Process.start(binary, [
          '$dir/db.sqlite',
          mode,
          'one',
          _slot,
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
          final d = await service.decision('one', _slot);
          final committed = mode.endsWith('commit');
          equal(d.status, committed ? 'declined' : 'pending');
          equal(d.sequence, committed ? 1 : 0);
          if (committed) {
            equal(
              (await service.decline(
                'one',
                _slot,
                d.version,
                _at(1),
              )).failedSessions,
              1,
            );
            await _finish(recovered, 'two', 2, fail: true);
            equal(
              (await service.propose('two', _slot, _rule())).previousFailures,
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
