import 'dart:convert';
import 'dart:io';
import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart' show expectLater, throwsA, isA;
import 'cli_test.dart';
import 'fixtures.dart';
import 'support.dart';

const _service = TrainingService();
final _observed = <String, Object?>{
  'rpe': {'value': '08.50', 'scale': '0-10'},
  'rir': '0',
  'notes': 'Grip tired — keep technique.',
  'terminationReason': 'grip-failure',
};
SetObservations _observations(Map<String, Object?> value) =>
    SetObservations.fromJson(value);
TrainingSession _annotate(
  TrainingSession s,
  Map<String, Object?> value, {
  bool confirm = false,
}) => _service.annotate(
  s,
  s.sets.first.id,
  _observations(value),
  confirm: confirm,
);
Map<String, Object?> _threshold() => {
  'metric': 'reps',
  'minimum': {'value': '6', 'unit': 'rep'},
  'threshold': {'value': '8', 'unit': 'rep'},
  'increments': {
    'mass': {'value': '1', 'unit': 'kg'},
  },
};
ProgressionDecision _decision(
  TrainingSession s, {
  String type = 'threshold',
  int failures = 0,
}) => ProgressionDecision(
  session: s,
  slotId: s.sets.first.slotId,
  rule: type == 'threshold'
      ? _threshold()
      : jsonObject(example('double-progression')['rule'], 'rule'),
  previousApplication: null,
  previousSequence: 0,
  previousFailures: failures,
  version: 1,
  ruleType: type,
);

void setObservationsTests() {
  test(
    'set observations validate distinct scales and retain explicit zero without inferring RIR',
    () {
      final o = _observations(_observed);
      equal(o.rpe.toString(), '8.5');
      equal(o.rir.toString(), '0');
      final rating = _observations({
        'rpe': {'value': '6', 'scale': '6-20'},
      });
      check(rating.rir == null);
      equal(
        _observations({
          'rpe': {'value': '0', 'scale': '0-10'},
        }).rpe.toString(),
        '0',
      );
      for (final bad in <Map<String, Object?>>[
        {
          'rpe': {'value': '8'},
        },
        {
          'rpe': {'value': '5', 'scale': '6-20'},
        },
        {
          'rpe': {'value': '10.01', 'scale': '0-10'},
        },
        {
          'rpe': {'value': 8, 'scale': '0-10'},
        },
        {
          'rpe': {'value': '8', 'scale': 'unknown'},
        },
        {'rir': '-0.1'},
        {'rir': 0},
        {'rir': null},
        {'notes': ''},
        {'notes': 'x' * 4001},
        {'terminationReason': 'made-up'},
        {'unknown': true},
      ]) {
        rejects(() => _observations(bad));
      }
    },
  );
  test(
    'set observations require confirmed effort and support notes on planned sets and reasons on skips',
    () {
      final planned = start();
      final noted = _annotate(planned, {'notes': 'Use a secure grip.'});
      equal(noted.sets.first.observations!.notes, 'Use a secure grip.');
      rejects(() => _annotate(planned, {'rir': '0'}));
      rejects(() => _annotate(planned, {'terminationReason': 'interrupted'}));
      final skipped = _service.skip(noted, noted.sets.first.id);
      final reason = _annotate(skipped, {
        'notes': 'Interrupted before work.',
        'terminationReason': 'interrupted',
      });
      equal(reason.sets.first.status, SetStatus.skipped);
      rejects(
        () => _annotate(reason, {
          'rpe': {'value': '0', 'scale': '0-10'},
        }),
      );
    },
  );
  test(
    'set observations survive codec completion corrections and finish; explicit clearing and skip remove effort reports',
    () {
      final old = finished(start());
      check(!old.sets.first.toJson().containsKey('observations'));
      var s = _annotate(old, _observed);
      final version = s.sets.first.contentVersion;
      equal(s.contentVersion, old.contentVersion + 1);
      equal(s.sets.first.contentVersion, old.sets.first.contentVersion + 1);
      final encoded = canonicalJson(s.toJson());
      equal(canonicalJson(sessionFromJson(s.toJson()).toJson()), encoded);
      s = _service.complete(s, s.sets.first.id, {
        'reps': Quantity('7', 'rep'),
      }, acceptSuggested: true);
      equal(s.sets.first.observations!.rpe.toString(), '8.5');
      equal(s.sets.first.contentVersion, version + 1);
      check(
        s
                .finish(instant(1).add(const Duration(hours: 1)))
                .sets
                .first
                .observations !=
            null,
      );
      rejects(() => _annotate(s, {}));
      check(_annotate(s, {}, confirm: true).sets.first.observations == null);
      final skipped = _service.skip(s, s.sets.first.id, confirm: true);
      jsonEqual(skipped.sets.first.observations!.toJson(), {
        'notes': _observed['notes'],
      });
      check(skipped.sets.first.actuals.isEmpty);
      final forged = copyJson(s.toJson());
      final row = jsonObject(jsonList(forged, 'sets').first, 'set');
      row['status'] = 'planned';
      row['actuals'] = <String, Object?>{};
      rejects(() => sessionFromJson(forged));
    },
  );
  test(
    'set observations keep pain descriptive and interruption neutral in both stored progression rule types',
    () {
      final s = finished(start());
      for (final type in ['threshold', 'double']) {
        final plain = _decision(s, type: type).proposal;
        for (final reason in [
          'pain-discomfort',
          'grip-failure',
          'max-effort',
        ]) {
          equal(
            canonicalJson(
              _decision(
                _annotate(s, {'terminationReason': reason}),
                type: type,
              ).proposal.toJson(),
            ),
            canonicalJson(plain.toJson()),
          );
        }
        final interrupted = _annotate(s, {'terminationReason': 'interrupted'});
        final p = _decision(interrupted, type: type, failures: 2).proposal;
        equal(p.outcome, 'unknown');
        equal(p.failedSessions, 2);
        check(!interrupted.sets.first.eligibleForPerformance);
        check(
          _annotate(
            interrupted,
            {},
            confirm: true,
          ).sets.first.eligibleForPerformance,
        );
      }
    },
  );
  test(
    'set observations exclude interruption from history prefill while preserving earlier history and raw analytics',
    () {
      final early = finished(start(id: 'early'));
      var later = finished(start(id: 'later', day: 2));
      later = _service.complete(later, later.sets.first.id, {
        'mass': Quantity('120', 'kg'),
      }, acceptSuggested: true);
      later = _annotate(later, {
        'terminationReason': 'interrupted',
        'notes': 'Stopped early.',
      });
      final next = start(id: 'next', day: 3, history: [early, later]);
      equal(next.sets.first.sources['mass']!.sessionId, 'early');
      final pain = _annotate(later, {'terminationReason': 'pain-discomfort'});
      equal(
        start(
          id: 'pain',
          day: 3,
          history: [early, pain],
        ).sets.first.sources['mass']!.sessionId,
        'later',
      );
      final summary = const TrainingAnalytics().summary(later);
      equal(
        jsonObject(
          jsonList(summary, 'sets').first,
          'set',
        )['observations'].toString(),
        later.sets.first.observations!.toJson().toString(),
      );
      final series = const TrainingAnalytics().series([later], metric: 'mass');
      final firstSeries = jsonObject(
        jsonList(series, 'series').first,
        'series',
      );
      check(
        jsonList(
          firstSeries,
          'points',
        ).any((p) => jsonObject(p, 'point').containsKey('observations')),
      );
      final records = const ContextualRecords().evaluate(
        [later],
        metric: 'mass',
        direction: 'higher',
      );
      equal(records['excludedCount'], 1);
      equal(
        jsonObject(jsonList(records, 'excluded').first, 'exclusion')['reason'],
        'interrupted-set',
      );
      equal(
        jsonObject(records['policy'], 'policy')['id'],
        'bodytmi-contextual-records/2',
      );
    },
  );
  test(
    'set observations pure CLI replaces annotations and enforces clear confirmation',
    () async {
      final s = finished(start());
      final result = const Commands().execute('session annotate', {
        'schemaVersion': 1,
        'session': s.toJson(),
        'setId': s.sets.first.id,
        'observations': _observed,
      });
      equal(
        sessionFromJson(result['data']).sets.first.observations!.rir.toString(),
        '0',
      );
    },
  );
  test(
    'set observations preserve planned notes through explicit timer confirmation and protect active clock inputs',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-observation-clock-',
      );
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final service = StoredTrainingService(store);
        final rev = await service.publish(
          WorkoutDefinition.fromJson(example('tempo-practice')['definition']),
          0,
        );
        var s = await service.start(
          'timed',
          rev.definition.id,
          rev.number,
          instant(1),
        );
        s = await service.edit(
          s.id,
          s.contentVersion,
          (s) => _annotate(s, {'notes': 'Stop when technique changes.'}),
        );
        final timer = TimingService(store);
        var t = await timer.start(
          'clock',
          s.id,
          s.sets.first.id,
          'duration',
          TimingPlan.fromJson({'effortMilliseconds': 1000}),
          instant(1),
        );
        await expectLater(
          service.edit(
            s.id,
            s.contentVersion,
            (s) => _annotate(s, {'notes': 'Changed.'}),
          ),
          throwsA(isA<BodyTmiException>()),
        );
        equal((await service.session(s.id)).contentVersion, s.contentVersion);
        t = await timer.resume(t.id, t.version, 'owner', instant(1));
        t = (await timer.advance(
          t.id,
          t.version,
          'owner',
          1000,
          instant(1),
        )).activity;
        check((await service.session(s.id)).sets.first.actuals.isEmpty);
        t = await timer.confirm(
          t.id,
          t.version,
          s.contentVersion,
          instant(1),
          {},
          acceptSuggested: true,
        );
        s = await service.session(s.id);
        equal(s.sets.first.observations!.notes, 'Stop when technique changes.');
        final timing = canonicalJson(s.sets.first.timing!.toJson());
        s = await service.edit(
          s.id,
          s.contentVersion,
          (s) => _annotate(s, {
            'rir': '1.5',
            'terminationReason': 'pain-discomfort',
          }),
        );
        equal(canonicalJson(s.sets.first.timing!.toJson()), timing);
        check(s.sets.first.eligibleForPerformance);
        equal(
          sessionFromJson(s.toJson()).sets.first.observations!.rir.toString(),
          '1.5',
        );
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'set observations migrate v20 without inventing annotations or rewriting existing receipts',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-observation-upgrade-',
      );
      var store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final service = StoredTrainingService(store);
        final r = await service.publish(definition(), 0);
        var s = await service.start(
          'legacy',
          r.definition.id,
          r.number,
          instant(1),
        );
        s = await service.edit(s.id, s.contentVersion, finished);
        final progression = StoredProgressionService(store);
        await progression.propose(
          s.id,
          s.sets.first.slotId,
          _threshold(),
          ruleType: 'threshold',
        );
        final before = canonicalJson((await store.archive()).toJson());
        await store.backup('${dir.path}/legacy');
        await LogicalArchiveFiles.export(
          await store.archive(),
          '${dir.path}/legacy.json',
        );
        await store.close();
        final old = sqlite3.open('${dir.path}/legacy/database.sqlite');
        old.execute('DROP TABLE derived_target_graphs');
        old.execute('DROP TABLE IF EXISTS repeat_checkpoints');
        old.execute('DROP TABLE IF EXISTS window_checkpoints');
        old.userVersion = 20;
        old.close();
        equal(
          NativeBackup.validateDatabase('${dir.path}/legacy/database.sqlite'),
          20,
        );
        store = await TrainingStore.open('${dir.path}/legacy/database.sqlite');
        equal(canonicalJson((await store.archive()).toJson()), before);
        equal(
          (await store.backup('${dir.path}/upgraded'))['databaseSchemaVersion'],
          51,
        );
        final logical = jsonObject(
          jsonDecode(await File('${dir.path}/legacy.json').readAsString()),
          'logical',
        );
        logical['format'] = 'bodytmi-logical-export/20';
        logical.remove('sha256');
        logical['sha256'] = sha256
            .convert(utf8.encode(canonicalJson(logical)))
            .toString();
        await File('${dir.path}/old.json').writeAsString(jsonEncode(logical));
        final prepared = await LogicalArchiveFiles.prepare(
          '${dir.path}/old.json',
        );
        try {
          equal(canonicalJson(prepared.archive.toJson()), before);
        } finally {
          await prepared.close();
        }
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'set observations native CLI edits persist with optimistic conflicts and backups preserve current and frozen annotations',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-observations-',
      );
      final path = '${dir.path}/db.sqlite';
      try {
        var store = await TrainingStore.open(path);
        final service = StoredTrainingService(store);
        final rev = await service.publish(definition(), 0);
        var s = await service.start(
          'one',
          rev.definition.id,
          rev.number,
          instant(1),
        );
        s = await service.edit(s.id, s.contentVersion, (s) => finished(s));
        await store.close();
        final request = {
          'schemaVersion': 1,
          'database': path,
          'id': s.id,
          'expectedVersion': s.contentVersion,
          'setId': s.sets.first.id,
          'observations': _observed,
        };
        final cli = await invoke(['store', 'annotate'], jsonEncode(request));
        equal(cli.code, 0);
        final conflict = await invoke([
          'store',
          'annotate',
        ], jsonEncode(request));
        equal(conflict.code, 5);
        store = await TrainingStore.open(path);
        try {
          s = await StoredTrainingService(store).session(s.id);
          final progression = StoredProgressionService(store);
          final pending = await progression.propose(
            s.id,
            s.sets.first.slotId,
            _threshold(),
            ruleType: 'threshold',
          );
          final before = canonicalJson((await store.archive()).toJson());
          await store.backup('${dir.path}/backup');
          await LogicalArchiveFiles.export(
            await store.archive(),
            '${dir.path}/logical.json',
          );
          final logical = await LogicalArchiveFiles.prepare(
            '${dir.path}/logical.json',
          );
          final restored = await TrainingStore.open(
            '${dir.path}/restored.sqlite',
          );
          try {
            await restored.restore(
              logical.backup,
              recoveryDestination: '${dir.path}/recovery',
              confirm: true,
            );
          } finally {
            await restored.close();
            await logical.close();
          }
          final reopened = await TrainingStore.open(
            '${dir.path}/restored.sqlite',
          );
          try {
            equal(canonicalJson((await reopened.archive()).toJson()), before);
          } finally {
            await reopened.close();
          }
          // Editing annotations stales a pending proposal without modifying its frozen source.
          s = await StoredTrainingService(store).edit(
            s.id,
            s.contentVersion,
            (s) => _annotate(s, {'terminationReason': 'interrupted'}),
          );
          await expectLater(
            progression.accept(
              s.id,
              s.sets.first.slotId,
              pending.version,
              instant(2),
            ),
            throwsA(isA<BodyTmiException>()),
          );
          final unknown = await progression.propose(
            s.id,
            s.sets.first.slotId,
            _threshold(),
            ruleType: 'threshold',
          );
          equal(unknown.proposal.outcome, 'unknown');
          await expectLater(
            progression.accept(
              s.id,
              s.sets.first.slotId,
              unknown.version,
              instant(2),
            ),
            throwsA(isA<BodyTmiException>()),
          );
          final declined = await progression.decline(
            s.id,
            s.sets.first.slotId,
            unknown.version,
            instant(2),
          );
          s = await StoredTrainingService(store).edit(
            s.id,
            s.contentVersion,
            (s) => _annotate(s, {}, confirm: true),
          );
          final retried = await progression.propose(
            s.id,
            s.sets.first.slotId,
            _threshold(),
            ruleType: 'threshold',
          );
          equal(
            canonicalJson(retried.toJson()),
            canonicalJson(declined.toJson()),
          );
          await LogicalArchiveFiles.export(
            await store.archive(),
            '${dir.path}/frozen.json',
          );
          final frozen = jsonObject(
            jsonDecode(await File('${dir.path}/frozen.json').readAsString()),
            'logical',
          );
          frozen['format'] = 'bodytmi-logical-export/20';
          frozen.remove('sha256');
          frozen['sha256'] = sha256
              .convert(utf8.encode(canonicalJson(frozen)))
              .toString();
          await File('${dir.path}/old.json').writeAsString(jsonEncode(frozen));
          await expectLater(
            LogicalArchiveFiles.prepare('${dir.path}/old.json'),
            throwsA(isA<BodyTmiException>()),
          );
          await store.backup('${dir.path}/frozen-backup');
        } finally {
          await store.close();
        }
        for (final source in ['backup', 'frozen-backup']) {
          final db = sqlite3.open('${dir.path}/$source/database.sqlite');
          db.execute('DROP TABLE derived_target_graphs');
          db.execute('DROP TABLE IF EXISTS repeat_checkpoints');
          db.execute('DROP TABLE IF EXISTS window_checkpoints');
          db.userVersion = 20;
          db.close();
          rejects(
            () => NativeBackup.validateDatabase(
              '${dir.path}/$source/database.sqlite',
            ),
          );
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
