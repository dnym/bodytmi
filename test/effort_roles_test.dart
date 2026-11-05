import 'dart:convert';
import 'dart:io';

import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart' show expectLater, isA, throwsA;

import 'cli_test.dart';
import 'fixtures.dart';
import 'support.dart';

WorkoutDefinition _definition() => WorkoutDefinition.fromJson({
  'id': 'role-practice',
  'name': 'Practice with back-off and drop segments',
  'slots': [
    {
      'id': 'lift',
      'exercise': 'lift',
      'implementation': 'barbell',
      'targets': {
        'mass': {'value': '10', 'unit': 'kg'},
        'reps': {'value': '8', 'unit': 'rep'},
      },
      'prefill': ['mass'],
    },
  ],
  'plan': {
    'id': 'workout',
    'type': 'sequence',
    'children': [
      {'id': 'warm', 'type': 'effort', 'slot': 'lift', 'role': 'warmup'},
      {
        'id': 'work',
        'type': 'repeat',
        'count': 2,
        'child': {'id': 'set', 'type': 'effort', 'slot': 'lift'},
      },
      {'id': 'back', 'type': 'effort', 'slot': 'lift', 'role': 'backoff'},
      {
        'id': 'drop',
        'type': 'repeat',
        'count': 2,
        'child': {
          'id': 'segment',
          'type': 'effort',
          'slot': 'lift',
          'role': 'drop',
        },
      },
    ],
  },
});

Map<String, Object?> _rule() => {
  'metric': 'reps',
  'minimum': {'value': '8', 'unit': 'rep'},
  'threshold': {'value': '8', 'unit': 'rep'},
  'increments': {
    'mass': {'value': '1', 'unit': 'kg'},
  },
};

TrainingSession _complete(TrainingSession session) {
  const training = TrainingService();
  for (final set in session.sets) {
    final mass = switch (set.role) {
      'warmup' => '1',
      'work' => '10',
      'backoff' => '8',
      'drop' => set.ordinal == 0 ? '6' : '5',
      _ => throw StateError('Unexpected role.'),
    };
    session = training.complete(session, set.id, {
      'mass': Quantity(mass, 'kg'),
      'reps': Quantity(set.role == 'work' ? '8' : '0', 'rep'),
    }, acceptSuggested: true);
  }
  return session.finish(session.startedAt.add(const Duration(hours: 1)));
}

void effortRolesTests() {
  test(
    'track-aware active preview uses durable counters, checks baseline and makes no changes',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-track-preview-',
      );
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final training = StoredTrainingService(store);
        final progression = StoredProgressionService(store);
        await training.publish(_definition(), 0);
        var first = await training.start(
          'prior',
          'role-practice',
          1,
          instant(1),
        );
        first = await training.edit(first.id, first.contentVersion, (s) {
          for (final set in s.sets) {
            s = const TrainingService().complete(
              s,
              set.id,
              set.role == 'work' ? {'reps': Quantity('0', 'rep')} : {},
              acceptSuggested: true,
            );
          }
          return s.finish(instant(1).add(const Duration(hours: 1)));
        });
        final proposed = await progression.propose(
          first.id,
          'lift',
          _rule(),
          ruleType: 'threshold',
        );
        final declined = await progression.decline(
          first.id,
          'lift',
          proposed.version,
          instant(1).add(const Duration(hours: 2)),
        );
        equal(declined.failedSessions, 1);
        var current = await training.start(
          'current',
          'role-practice',
          1,
          instant(2),
        );
        current = await training.edit(current.id, current.contentVersion, (s) {
          for (final set in s.sets.where((s) => s.role == 'work')) {
            s = const TrainingService().complete(
              s,
              set.id,
              {},
              acceptSuggested: true,
            );
          }
          return s;
        });
        final before = canonicalJson((await store.archive()).toJson());
        final preview = await progression.previewFromTrack(
          current.id,
          'lift',
          _rule(),
          ruleType: 'threshold',
        );
        equal(preview['policy'], 'bodytmi-stored-progression-preview/1');
        equal(preview['finalizationRequired'], true);
        equal(jsonObject(preview['state'], 'state')['failedSessions'], 1);
        equal(
          jsonObject(preview['proposal'], 'proposal')['outcome'],
          'advance',
        );
        final source = jsonObject(preview['stateSource'], 'state source');
        equal(source['previousApplication'], declined.id);
        equal(source['previousSequence'], 1);
        equal(source['previousInputsChanged'], false);
        equal(source['runId'], null);
        equal(canonicalJson((await store.archive()).toJson()), before);
        first = await training.edit(
          first.id,
          first.contentVersion,
          (s) => const TrainingService().complete(
            s,
            first.sets.firstWhere((set) => set.role == 'work').id,
            {'reps': Quantity('1', 'rep')},
            acceptSuggested: true,
          ),
        );
        final afterCorrection = await progression.previewFromTrack(
          current.id,
          'lift',
          _rule(),
          ruleType: 'threshold',
        );
        equal(
          jsonObject(
            afterCorrection['stateSource'],
            'source',
          )['previousInputsChanged'],
          true,
        );
        equal(
          jsonObject(afterCorrection['state'], 'state')['failedSessions'],
          1,
        );
        final edited = await training.start(
          'edited',
          'role-practice',
          1,
          instant(3),
        );
        await training.editTarget(
          edited.id,
          edited.contentVersion,
          edited.sets.firstWhere((s) => s.role == 'work').id,
          'mass',
          Quantity('15', 'kg'),
        );
        await expectLater(
          progression.previewFromTrack(
            edited.id,
            'lift',
            _rule(),
            ruleType: 'threshold',
          ),
          throwsA(isA<BodyTmiException>()),
        );
        final otherRule = {
          ..._rule(),
          'minimum': {'value': '7', 'unit': 'rep'},
        };
        await expectLater(
          progression.previewFromTrack(
            current.id,
            'lift',
            otherRule,
            ruleType: 'threshold',
          ),
          throwsA(isA<BodyTmiException>()),
        );
        final untracked = await progression.previewFromTrack(
          current.id,
          'lift',
          _rule(),
          role: 'backoff',
          ruleType: 'threshold',
        );
        equal(
          jsonObject(untracked['stateSource'], 'source')['previousApplication'],
          null,
        );
        equal(jsonObject(untracked['state'], 'state')['failedSessions'], 0);
        var later = await training.start(
          'later',
          'role-practice',
          1,
          instant(4),
        );
        later = await training.edit(later.id, later.contentVersion, (s) {
          for (final set in s.sets) {
            s = const TrainingService().complete(
              s,
              set.id,
              {},
              acceptSuggested: true,
            );
          }
          return s.finish(instant(4).add(const Duration(hours: 1)));
        });
        final laterProposal = await progression.propose(
          later.id,
          'lift',
          _rule(),
          ruleType: 'threshold',
        );
        final laterDecision = await progression.decline(
          later.id,
          'lift',
          laterProposal.version,
          instant(4).add(const Duration(hours: 2)),
        );
        final currentLineage = await progression.previewFromTrack(
          current.id,
          'lift',
          _rule(),
          ruleType: 'threshold',
        );
        final currentSource = jsonObject(
          currentLineage['stateSource'],
          'source',
        );
        equal(currentSource['previousApplication'], laterDecision.id);
        equal(currentSource['previousResolvedAfterSessionStart'], true);
        equal(
          jsonObject(currentLineage['state'], 'state')['failedSessions'],
          0,
        );
        await expectLater(
          progression.previewFromTrack(
            first.id,
            'lift',
            _rule(),
            ruleType: 'threshold',
          ),
          throwsA(isA<BodyTmiException>()),
        );
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'active-session progression previews use confirmed role results without creating decisions',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-active-preview-',
      );
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final training = StoredTrainingService(store);
        await training.publish(_definition(), 0);
        var session = await training.start(
          'active-preview',
          'role-practice',
          1,
          instant(1),
        );
        final work = session.sets.where((set) => set.role == 'work').toList();
        session = await training.edit(
          session.id,
          session.contentVersion,
          (s) => const TrainingService().complete(
            s,
            work[0].id,
            {},
            acceptSuggested: true,
          ),
        );
        Map<String, Object?> preview(TrainingSession s) =>
            const RoleProgressionPreview().evaluate(
              session: s,
              slotId: 'lift',
              role: 'work',
              ruleType: 'threshold',
              rule: _rule(),
              failedSessions: 2,
            );
        equal(
          jsonObject(preview(session)['proposal'], 'proposal')['outcome'],
          'unknown',
        );
        session = await training.edit(
          session.id,
          session.contentVersion,
          (s) => const TrainingService().complete(
            s,
            work[1].id,
            {},
            acceptSuggested: true,
          ),
        );
        final before = canonicalJson((await store.archive()).toJson());
        final ready = preview(session);
        equal(ready['policy'], 'bodytmi-role-progression-preview/2');
        equal(ready['sessionStatus'], 'active');
        equal(ready['finalizationRequired'], true);
        equal(ready['sessionContentVersion'], session.contentVersion);
        equal(jsonObject(ready['proposal'], 'proposal')['outcome'], 'advance');
        equal(jsonObject(ready['state'], 'state')['failedSessions'], 2);
        final doublePreview = const RoleProgressionPreview().evaluate(
          session: session,
          slotId: 'lift',
          rule: jsonObject(example('double-progression')['rule'], 'rule'),
        );
        equal(
          jsonObject(doublePreview['proposal'], 'proposal')['outcome'],
          'increaseObjective',
        );
        check(session.sets.any((set) => set.status == SetStatus.planned));
        final pure = const Commands().execute('session progression-preview', {
          'schemaVersion': 1,
          'session': session.toJson(),
          'slotId': 'lift',
          'ruleType': 'threshold',
          'rule': _rule(),
          'state': {'failedSessions': 2},
        });
        equal(canonicalJson(pure['data']), canonicalJson(ready));
        await expectLater(
          StoredProgressionService(
            store,
          ).propose(session.id, 'lift', _rule(), ruleType: 'threshold'),
          throwsA(isA<BodyTmiException>()),
        );
        equal((await store.progressionDecisions()).length, 0);
        equal(canonicalJson((await store.archive()).toJson()), before);
        session = await training.edit(
          session.id,
          session.contentVersion,
          (s) => const TrainingService().complete(s, work[0].id, {
            'mass': Quantity('12', 'kg'),
          }, acceptSuggested: true),
        );
        final changed = preview(session);
        equal(jsonObject(changed['proposal'], 'proposal')['outcome'], 'review');
        check(
          changed['sessionContentVersion'] != ready['sessionContentVersion'],
        );
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'role-specific progression remains isolated across simultaneous runs',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-role-runs-');
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final training = StoredTrainingService(store);
        final programs = ProgramService(store);
        await training.publish(_definition(), 0);
        for (final name in ['strength', 'cardio']) {
          await programs.publish(
            ProgramDefinition.fromJson({
              'id': name,
              'name': name,
              'plan': {
                'id': 'day',
                'type': 'day',
                'templateId': 'role-practice',
                'revision': 1,
              },
            }),
            0,
          );
          await programs.create('$name-run', name, 1, instant(1));
          var session = await programs.start(
            '$name-run',
            1,
            '$name-one',
            instant(1),
          );
          session = await training.edit(session.id, session.contentVersion, (
            s,
          ) {
            for (final set in s.sets) {
              s = const TrainingService().complete(
                s,
                set.id,
                {},
                acceptSuggested: true,
              );
            }
            return s.finish(instant(1).add(const Duration(hours: 1)));
          });
        }
        final service = StoredProgressionService(store);
        final proposal = await service.propose(
          'strength-one',
          'lift',
          _rule(),
          role: 'backoff',
          ruleType: 'threshold',
        );
        await service.accept(
          'strength-one',
          'lift',
          proposal.version,
          instant(1).add(const Duration(hours: 2)),
          role: 'backoff',
        );
        final cardioProposal = await service.propose(
          'cardio-one',
          'lift',
          _rule(),
          role: 'backoff',
          ruleType: 'threshold',
        );
        equal(cardioProposal.previousApplication, null);
        final cardioPreview = await service.previewFromTrack(
          'cardio-one',
          'lift',
          _rule(),
          role: 'backoff',
          ruleType: 'threshold',
        );
        final cardioSource = jsonObject(cardioPreview['stateSource'], 'source');
        equal(cardioSource['runId'], 'cardio-run');
        equal(cardioSource['previousApplication'], null);
        equal(cardioSource['pendingVersion'], cardioProposal.version);
        equal(cardioSource['pendingStale'], false);
        Future<Map<String, Object?>> track(
          String? runId,
          DateTime asOf, {
          String role = 'backoff',
        }) => service.track(
          templateId: 'role-practice',
          revision: 1,
          slotId: 'lift',
          asOf: asOf,
          runId: runId,
          role: role,
        );
        equal(
          (await track(
            'strength-run',
            instant(1).add(const Duration(hours: 1)),
          ))['resolved'],
          false,
        );
        final current = await track(
          'strength-run',
          instant(1).add(const Duration(hours: 2)),
        );
        equal(current['decisionId'], proposal.id);
        equal(current['status'], 'accepted');
        equal(current['inputsChanged'], false);
        equal(jsonObject(current['state'], 'state')['failedSessions'], 0);
        final nextTargets = jsonObject(
          jsonList(jsonObject(current['state'], 'state'), 'nextSets').single,
          'targets',
        );
        equal(jsonObject(nextTargets['mass'], 'mass')['value'], '11');
        equal(nextTargets.containsKey('reps'), false);
        equal((await track('cardio-run', instant(2)))['resolved'], false);
        equal((await track(null, instant(2)))['resolved'], false);
        equal(
          (await track('strength-run', instant(2), role: 'work'))['resolved'],
          false,
        );
        await expectLater(
          track('missing-run', instant(2)),
          throwsA(isA<BodyTmiException>()),
        );
        await expectLater(
          track('strength-run', instant(2), role: 'invalid'),
          throwsA(isA<BodyTmiException>()),
        );
        for (final name in ['strength', 'cardio']) {
          final run = await programs.run('$name-run');
          final next = await programs.start(
            '$name-run',
            run.contentVersion,
            '$name-two',
            instant(2),
          );
          equal(
            next.sets
                .singleWhere((s) => s.role == 'backoff')
                .suggested['mass']!
                .value
                .toString(),
            name == 'strength' ? '11' : '10',
          );
        }
        final source = await training.session('strength-one');
        final backoff = source.sets.singleWhere((s) => s.role == 'backoff');
        await training.edit(
          source.id,
          source.contentVersion,
          (s) => const TrainingService().complete(s, backoff.id, {
            'reps': Quantity('9', 'rep'),
          }, acceptSuggested: true),
        );
        final changed = await track('strength-run', instant(2));
        equal(changed['inputsChanged'], true);
        equal(changed['decisionId'], current['decisionId']);
        equal(canonicalJson(changed['state']), canonicalJson(current['state']));
        await store.archive();
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test('durable progression isolates roles, lineage and portability', () async {
    final dir = await Directory.systemTemp.createTemp(
      'bodytmi-role-progression-',
    );
    final store = await TrainingStore.open('${dir.path}/db.sqlite');
    try {
      final training = StoredTrainingService(store);
      final progression = StoredProgressionService(store);
      await store.snapshot('${dir.path}/v41.sqlite');
      final oldProfile = sqlite3.open('${dir.path}/v41.sqlite');
      oldProfile.userVersion = 41;
      oldProfile.close();
      equal(NativeBackup.validateDatabase('${dir.path}/v41.sqlite'), 41);
      final migrated = await TrainingStore.open('${dir.path}/v41.sqlite');
      await migrated.close();
      final migratedDb = sqlite3.open('${dir.path}/v41.sqlite');
      equal(migratedDb.userVersion, 42);
      migratedDb.close();
      await training.publish(_definition(), 0);
      var session = await training.start(
        'first',
        'role-practice',
        1,
        instant(1),
      );
      session = await training.edit(session.id, session.contentVersion, (s) {
        for (final set in s.sets) {
          s = const TrainingService().complete(
            s,
            set.id,
            set.role == 'drop' ? {'reps': Quantity('0', 'rep')} : {},
            acceptSuggested: true,
          );
        }
        return s.finish(instant(1).add(const Duration(hours: 1)));
      });
      final decisions = <String, ProgressionDecision>{};
      for (final role in ['work', 'backoff', 'drop', 'warmup']) {
        decisions[role] = await progression.propose(
          session.id,
          'lift',
          _rule(),
          ruleType: 'threshold',
          role: role,
        );
      }
      equal(decisions['work']!.id, 'first/lift');
      equal(decisions['backoff']!.id, 'first/lift/backoff');
      equal(decisions['drop']!.proposal.outcome, 'failed');
      final at = instant(1).add(const Duration(hours: 2));
      for (final role in ['work', 'backoff', 'warmup']) {
        await progression.accept(
          session.id,
          'lift',
          decisions[role]!.version,
          at,
          role: role,
        );
      }
      final declined = await progression.decline(
        session.id,
        'lift',
        decisions['drop']!.version,
        at,
        role: 'drop',
      );
      equal(declined.failedSessions, 1);
      final held = await progression.track(
        templateId: 'role-practice',
        revision: 1,
        slotId: 'lift',
        role: 'drop',
        asOf: at,
      );
      equal(held['status'], 'declined');
      equal(jsonObject(held['state'], 'state')['failedSessions'], 1);
      equal(
        (await progression.decline(
          session.id,
          'lift',
          declined.version,
          at,
          role: 'drop',
        )).failedSessions,
        1,
      );
      equal((await progression.decision(session.id, 'lift')).role, 'work');
      var next = await training.start('second', 'role-practice', 1, instant(2));
      equal(
        next.sets.map((s) => s.suggested['mass']!.value.toString()).join(','),
        '11,11,11,11,10,10',
      );
      next = await training.edit(next.id, next.contentVersion, (s) {
        for (final set in s.sets) {
          s = const TrainingService().complete(
            s,
            set.id,
            {},
            acceptSuggested: true,
          );
        }
        return s.finish(instant(2).add(const Duration(hours: 1)));
      });
      final following = await progression.propose(
        next.id,
        'lift',
        _rule(),
        ruleType: 'threshold',
        role: 'backoff',
      );
      equal(following.previousApplication, decisions['backoff']!.id);
      equal(following.previousSequence, 1);
      final dropFollowing = await progression.propose(
        next.id,
        'lift',
        _rule(),
        ruleType: 'threshold',
        role: 'drop',
      );
      equal(dropFollowing.previousFailures, 1);
      final data = canonicalJson((await store.archive()).toJson());
      await store.backup('${dir.path}/native');
      final file = '${dir.path}/logical.json';
      await LogicalArchiveFiles.export(await store.archive(), file);
      final prepared = await LogicalArchiveFiles.prepare(file);
      final destination = await TrainingStore.open(
        '${dir.path}/restore.sqlite',
      );
      try {
        await destination.restore(
          prepared.backup,
          recoveryDestination: '${dir.path}/recovery',
          confirm: true,
        );
      } finally {
        await destination.close();
        await prepared.close();
      }
      final restored = await TrainingStore.open('${dir.path}/restore.sqlite');
      try {
        equal(canonicalJson((await restored.archive()).toJson()), data);
        final native = await NativeBackup.prepare('${dir.path}/native');
        try {
          await restored.restore(
            native,
            recoveryDestination: '${dir.path}/native-recovery',
            confirm: true,
          );
        } finally {
          await native.close();
        }
      } finally {
        await restored.close();
      }
      final nativeRestored = await TrainingStore.open(
        '${dir.path}/restore.sqlite',
      );
      try {
        equal(canonicalJson((await nativeRestored.archive()).toJson()), data);
      } finally {
        await nativeRestored.close();
      }
      final envelope = jsonObject(
        jsonDecode(await File(file).readAsString()),
        'envelope',
      );
      envelope['format'] = 'bodytmi-logical-export/41';
      envelope['sha256'] = sha256
          .convert(
            utf8.encode(
              canonicalJson({
                for (final e in envelope.entries)
                  if (e.key != 'sha256') e.key: e.value,
              }),
            ),
          )
          .toString();
      await File('${dir.path}/old.json').writeAsString(jsonEncode(envelope));
      await expectLater(
        LogicalArchiveFiles.prepare('${dir.path}/old.json'),
        throwsA(isA<BodyTmiException>()),
      );
      await store.snapshot('${dir.path}/old.sqlite');
      final old = sqlite3.open('${dir.path}/old.sqlite');
      old.userVersion = 41;
      old.close();
      rejects(() => NativeBackup.validateDatabase('${dir.path}/old.sqlite'));
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });
  test(
    'role progression previews preserve explicit state and treat skipped sets as unknown',
    () {
      var session = const TrainingService().start(
        sessionId: 'preview',
        revision: WorkoutRevision.publish(_definition()),
        startedAt: instant(1),
      );
      for (final set in session.sets) {
        session = const TrainingService().skip(session, set.id);
      }
      session = session.finish(instant(1).add(const Duration(hours: 1)));
      final doubleRule = jsonObject(
        example('double-progression')['rule'],
        'rule',
      );
      final preview = const RoleProgressionPreview().evaluate(
        session: session,
        slotId: 'lift',
        role: 'drop',
        rule: doubleRule,
        failedSessions: 2,
      );
      equal(jsonObject(preview['proposal'], 'proposal')['outcome'], 'unknown');
      equal(jsonObject(preview['state'], 'state')['failedSessions'], 2);
      rejects(
        () => const RoleProgressionPreview().evaluate(
          session: session,
          slotId: 'lift',
          rule: doubleRule,
          cursor: 1,
        ),
      );
      rejects(
        () => const Commands().execute('session progression-preview', {
          'schemaVersion': 1,
          'session': session.toJson(),
          'slotId': 'lift',
          'rule': doubleRule,
          'state': {'failedSessions': '2'},
        }),
      );
    },
  );
  test(
    'effort roles keep independent ordinals, history, summaries and filters',
    () {
      final workout = _definition();
      check(workout.hasExtendedEffortRoles);
      final rev = WorkoutRevision.publish(workout);
      final session = const TrainingService().start(
        sessionId: 'one',
        revision: rev,
        startedAt: instant(1),
      );
      equal(
        session.sets.map((s) => '${s.role}:${s.ordinal}').join(','),
        'warmup:0,work:0,work:1,backoff:0,drop:0,drop:1',
      );
      final old = _complete(session);
      final preview = const RoleProgressionPreview().evaluate(
        session: old,
        slotId: 'lift',
        role: 'work',
        ruleType: 'threshold',
        rule: _rule(),
      );
      equal(jsonObject(preview['proposal'], 'proposal')['outcome'], 'advance');
      equal(jsonList(preview, 'setIds').length, 2);
      final backoffPreview = const RoleProgressionPreview().evaluate(
        session: old,
        slotId: 'lift',
        role: 'backoff',
        ruleType: 'threshold',
        rule: _rule(),
        failedSessions: 2,
      );
      equal(
        jsonObject(backoffPreview['proposal'], 'proposal')['outcome'],
        'review',
      );
      equal(jsonList(backoffPreview, 'setIds').length, 1);
      equal(jsonObject(backoffPreview['state'], 'state')['failedSessions'], 2);
      final unfinished = const RoleProgressionPreview().evaluate(
        session: session,
        slotId: 'lift',
        rule: _rule(),
        ruleType: 'threshold',
      );
      equal(
        jsonObject(unfinished['proposal'], 'proposal')['outcome'],
        'unknown',
      );
      equal(unfinished['finalizationRequired'], true);
      rejects(
        () => const RoleProgressionPreview().evaluate(
          session: old,
          slotId: 'lift',
          role: 'other',
          rule: _rule(),
          ruleType: 'threshold',
        ),
      );
      rejects(
        () => const RoleProgressionPreview().evaluate(
          session: old,
          slotId: 'missing',
          rule: _rule(),
          ruleType: 'threshold',
        ),
      );
      final next = const TrainingService().start(
        sessionId: 'two',
        revision: rev,
        startedAt: instant(2),
        history: [old],
      );
      equal(
        next.sets.map((s) => s.suggested['mass']!.value.toString()).join(','),
        '10,10,10,8,6,5',
      );
      check(next.sets.first.sources.isEmpty);
      for (final set in next.sets.skip(1)) {
        final prior = old.sets.firstWhere(
          (s) => s.role == set.role && s.ordinal == set.ordinal,
        );
        equal(set.sources['mass']!.setId, prior.id);
      }
      final summary = const TrainingAnalytics().summary(old);
      equal(jsonObject(summary['counts'], 'counts')['included'], 5);
      final selected = const TrainingAnalytics().summary(
        old,
        roles: ['drop', 'warmup'],
        sumMetrics: ['mass'],
      );
      final counts = jsonObject(selected['counts'], 'counts');
      equal(
        jsonObject(selected['policy'], 'policy')['id'],
        'bodytmi-session-summary/4',
      );
      equal(counts['included'], 3);
      equal(counts['excludedWarmups'], 0);
      equal(counts['excludedRoles'], 3);
      equal(
        jsonList(jsonObject(selected['policy'], 'policy'), 'roles').join(','),
        'drop,warmup',
      );
      equal(
        jsonObject(jsonList(selected, 'totals').single, 'total')['value'],
        '12',
      );
      rejects(() => const TrainingAnalytics().summary(old, roles: []));
      rejects(
        () => const TrainingAnalytics().summary(old, roles: ['work', 'work']),
      );
      rejects(() => const TrainingAnalytics().summary(old, roles: ['other']));
      rejects(
        () => const TrainingAnalytics().summary(
          old,
          roles: ['work'],
          includeWarmups: true,
        ),
      );
      for (final role in ['work', 'backoff', 'drop']) {
        final series = const TrainingAnalytics().series(
          [old],
          metric: 'mass',
          context: {'role': role},
        );
        equal(series['pointCount'], role == 'backoff' ? 1 : 2);
      }
      final records = const ContextualRecords().evaluate(
        [old],
        metric: 'mass',
        direction: 'higher',
        context: {'role': 'drop'},
      );
      equal(records['eligibleCount'], 2);
      final skipped = const TrainingService().skipSlot(
        next,
        'lift',
        role: 'drop',
        confirm: true,
      );
      check(
        skipped.sets
            .where((s) => s.role == 'drop')
            .every((s) => s.status == SetStatus.skipped),
      );
      check(
        skipped.sets
            .where((s) => s.role != 'drop')
            .every((s) => s.status == SetStatus.planned),
      );
      final changed = const TrainingService().editTarget(
        next,
        next.sets[1].id,
        'mass',
        Quantity('11', 'kg'),
        applyToRemaining: true,
      );
      equal(changed.sets[2].suggested['mass']!.value.toString(), '11');
      equal(changed.sets[3].suggested['mass']!.value.toString(), '8');
      equal(changed.sets[4].suggested['mass']!.value.toString(), '6');
      equal(
        canonicalJson(sessionFromJson(changed.toJson()).toJson()),
        canonicalJson(changed.toJson()),
      );
      final bad = workout.toJson();
      jsonObject(
        jsonList(jsonObject(bad['plan'], 'plan'), 'children').first,
        'set',
      )['role'] = 'unknown';
      rejects(() => WorkoutDefinition.fromJson(bad));
    },
  );

  test(
    'default work progression remains independent across program runs',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-roles-');
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final training = StoredTrainingService(store);
        await training.publish(_definition(), 0);
        final programs = ProgramService(store);
        for (final name in ['strength', 'cardio']) {
          await programs.publish(
            ProgramDefinition.fromJson({
              'id': name,
              'name': name,
              'plan': {
                'id': 'day',
                'type': 'day',
                'templateId': 'role-practice',
                'revision': 1,
              },
            }),
            0,
          );
          await programs.create('$name-run', name, 1, instant(1));
        }
        var strength = await programs.start(
          'strength-run',
          1,
          'strength-one',
          instant(1),
        );
        final cardio = await programs.start(
          'cardio-run',
          1,
          'cardio-one',
          instant(1),
        );
        final cardioRun = canonicalJson(
          (await programs.run('cardio-run')).toJson(),
        );
        strength = await training.edit(
          strength.id,
          strength.contentVersion,
          _complete,
        );
        final graphs = DerivedTargetGraphService(store);
        for (final role in ['backoff', 'drop']) {
          await graphs.publish(
            DerivedTargetGraph.fromJson({
              'id': 'source-$role',
              'nodes': [
                {
                  'id': 'selected',
                  'kind': 'source',
                  'unit': 'kg',
                  'sourceId': 'history',
                },
              ],
              'bindings': {
                'history': {
                  'kind': 'history',
                  'metric': 'mass',
                  'templateId': 'role-practice',
                  'slotId': 'lift',
                  'role': role,
                },
              },
            }),
            0,
          );
          final resolved = await graphs.resolve(
            'source-$role',
            1,
            instant(2),
            'strength-run',
          );
          final binding = jsonObject(
            jsonObject(resolved['bindings'], 'bindings')['history'],
            'history',
          );
          equal(
            jsonObject(binding['value'], 'value')['value'],
            role == 'backoff' ? '8' : '6',
          );
        }
        final progression = StoredProgressionService(store);
        final proposal = await progression.propose(
          strength.id,
          'lift',
          _rule(),
          ruleType: 'threshold',
        );
        equal(proposal.proposal.outcome, 'advance');
        equal(proposal.sets.length, 2);
        check(proposal.sets.every((s) => s.role == 'work'));
        await progression.accept(
          strength.id,
          'lift',
          proposal.version,
          instant(1).add(const Duration(hours: 2)),
        );
        final next = await programs.start(
          'strength-run',
          (await programs.run('strength-run')).contentVersion,
          'strength-two',
          instant(2),
        );
        equal(
          next.sets.map((s) => s.suggested['mass']!.value.toString()).join(','),
          '10,11,11,8,6,5',
        );
        equal(
          canonicalJson((await programs.run('cardio-run')).toJson()),
          cardioRun,
        );
        equal(
          canonicalJson((await training.session(cardio.id)).toJson()),
          canonicalJson(cardio.toJson()),
        );
        final skipped = await training.skipSlot(
          next.id,
          next.contentVersion,
          'lift',
          role: 'backoff',
          confirm: true,
        );
        equal(
          skipped.sets.singleWhere((s) => s.role == 'backoff').status,
          SetStatus.skipped,
        );
        check(
          skipped.sets
              .where((s) => s.role != 'backoff')
              .every((s) => s.status == SetStatus.planned),
        );
        await store.archive();
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'role snapshots migrate and reject older native and logical labels',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-roles-portability-',
      );
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final training = StoredTrainingService(store);
        await training.publish(definition(), 0);
        await store.snapshot('${dir.path}/v40.sqlite');
        final previous = sqlite3.open('${dir.path}/v40.sqlite');
        previous.userVersion = 40;
        previous.close();
        equal(NativeBackup.validateDatabase('${dir.path}/v40.sqlite'), 40);
        final migrated = await TrainingStore.open('${dir.path}/v40.sqlite');
        equal(
          (await StoredTrainingService(
            migrated,
          ).revision(definition().id)).number,
          1,
        );
        await migrated.close();
        await training.publish(_definition(), 0);
        final session = await training.start(
          'roles',
          'role-practice',
          1,
          instant(1),
        );
        await training.edit(session.id, session.contentVersion, _complete);
        final original = canonicalJson((await store.archive()).toJson());
        await store.backup('${dir.path}/native');
        final file = '${dir.path}/logical.json';
        await LogicalArchiveFiles.export(await store.archive(), file);
        final prepared = await LogicalArchiveFiles.prepare(file);
        final dest = await TrainingStore.open('${dir.path}/restore.sqlite');
        try {
          await dest.restore(
            prepared.backup,
            recoveryDestination: '${dir.path}/recovery',
            confirm: true,
          );
        } finally {
          await dest.close();
          await prepared.close();
        }
        final restored = await TrainingStore.open('${dir.path}/restore.sqlite');
        try {
          equal(canonicalJson((await restored.archive()).toJson()), original);
          final native = await NativeBackup.prepare('${dir.path}/native');
          try {
            await restored.restore(
              native,
              recoveryDestination: '${dir.path}/recovery-native',
              confirm: true,
            );
          } finally {
            await native.close();
          }
        } finally {
          await restored.close();
        }
        final nativeRestored = await TrainingStore.open(
          '${dir.path}/restore.sqlite',
        );
        try {
          equal(
            canonicalJson((await nativeRestored.archive()).toJson()),
            original,
          );
        } finally {
          await nativeRestored.close();
        }
        final envelope =
            jsonDecode(await File(file).readAsString()) as Map<String, Object?>;
        envelope['format'] = 'bodytmi-logical-export/40';
        envelope['sha256'] = sha256
            .convert(
              utf8.encode(
                canonicalJson({
                  for (final e in envelope.entries)
                    if (e.key != 'sha256') e.key: e.value,
                }),
              ),
            )
            .toString();
        await File('${dir.path}/old.json').writeAsString(jsonEncode(envelope));
        await expectLater(
          LogicalArchiveFiles.prepare('${dir.path}/old.json'),
          throwsA(isA<BodyTmiException>()),
        );
        await store.snapshot('${dir.path}/roles.sqlite');
        equal(NativeBackup.validateDatabase('${dir.path}/roles.sqlite'), 42);
        final relabeled = sqlite3.open('${dir.path}/roles.sqlite');
        relabeled.userVersion = 40;
        relabeled.close();
        rejects(
          () => NativeBackup.validateDatabase('${dir.path}/roles.sqlite'),
        );
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test('native CLI publishes, logs and filters explicit roles', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-roles-cli-');
    final path = '${dir.path}/db.sqlite';
    try {
      Future<Object?> call(String name, Map<String, Object?> fields) async {
        final response = await invoke(
          name.split(' '),
          jsonEncode({'schemaVersion': 1, 'database': path, ...fields}),
        );
        equal(response.code, 0);
        return jsonObject(jsonDecode(response.output), 'response')['data'];
      }

      await call('store publish', {
        'definition': _definition().toJson(),
        'expectedRevision': 0,
      });
      var session = sessionFromJson(
        await call('store start', {
          'id': 'cli',
          'templateId': 'role-practice',
          'revision': 1,
          'startedAt': instant(1).toIso8601String(),
        }),
      );
      var execution = jsonObject(
        await call('execution start', {
          'id': 'cli-execution',
          'sessionId': session.id,
          'at': instant(1).toIso8601String(),
        }),
        'execution',
      );
      for (final set in session.sets) {
        final current = jsonObject(execution['current'], 'current');
        equal(current['id'], set.id);
        execution = jsonObject(
          await call('execution complete', {
            'id': 'cli-execution',
            'expectedVersion': execution['version'],
            'expectedSessionVersion': session.contentVersion,
            'requestId': 'set-${set.role}-${set.ordinal}',
            'at': instant(1).toIso8601String(),
            'acceptSuggested': true,
          }),
          'execution',
        );
        session = sessionFromJson(await call('store show', {'id': session.id}));
        if (set.role == 'work' && set.ordinal == 1) {
          final preview = jsonObject(
            await call('store progression-preview', {
              'id': session.id,
              'slotId': 'lift',
              'ruleType': 'threshold',
              'rule': _rule(),
            }),
            'preview',
          );
          equal(preview['finalizationRequired'], true);
          equal(
            jsonObject(preview['proposal'], 'proposal')['outcome'],
            'advance',
          );
          final pure = const Commands().execute('session progression-preview', {
            'schemaVersion': 1,
            'session': session.toJson(),
            'slotId': 'lift',
            'ruleType': 'threshold',
            'rule': _rule(),
          });
          equal(canonicalJson(preview), canonicalJson(pure['data']));
          final tracked = jsonObject(
            await call('store progression-preview', {
              'id': session.id,
              'slotId': 'lift',
              'ruleType': 'threshold',
              'rule': _rule(),
              'useTrack': true,
            }),
            'preview',
          );
          equal(tracked['policy'], 'bodytmi-stored-progression-preview/1');
          equal(
            jsonObject(tracked['stateSource'], 'source')['previousApplication'],
            null,
          );
          equal(
            canonicalJson(tracked['proposal']),
            canonicalJson(preview['proposal']),
          );
          final mixed = await invoke(
            ['store', 'progression-preview'],
            jsonEncode({
              'schemaVersion': 1,
              'database': path,
              'id': session.id,
              'slotId': 'lift',
              'ruleType': 'threshold',
              'rule': _rule(),
              'useTrack': true,
              'state': <String, Object?>{},
            }),
          );
          check(mixed.code != 0);
          equal(mixed.output, '');
          final denied = await invoke(
            ['progression', 'propose'],
            jsonEncode({
              'schemaVersion': 1,
              'database': path,
              'sessionId': session.id,
              'slotId': 'lift',
              'ruleType': 'threshold',
              'rule': _rule(),
            }),
          );
          check(denied.code != 0);
          equal(denied.output, '');
        }
      }
      equal(execution['status'], 'completed');
      await call('store finish', {
        'id': session.id,
        'expectedVersion': session.contentVersion,
        'finishedAt': instant(
          1,
        ).add(const Duration(hours: 1)).toIso8601String(),
      });
      final roleSummary = jsonObject(
        await call('store summary', {
          'id': session.id,
          'roles': ['backoff', 'drop'],
          'sumMetrics': ['mass'],
        }),
        'summary',
      );
      equal(jsonObject(roleSummary['counts'], 'counts')['included'], 3);
      final finished = await call('store show', {'id': session.id});
      final storedPreview = await call('store progression-preview', {
        'id': session.id,
        'slotId': 'lift',
        'role': 'drop',
        'ruleType': 'threshold',
        'rule': _rule(),
        'state': {'failedSessions': 1, 'cursor': 0},
      });
      final purePreview = const Commands().execute(
        'session progression-preview',
        {
          'schemaVersion': 1,
          'session': finished,
          'slotId': 'lift',
          'role': 'drop',
          'ruleType': 'threshold',
          'rule': _rule(),
          'state': {'failedSessions': 1, 'cursor': 0},
        },
      )['data'];
      equal(canonicalJson(storedPreview), canonicalJson(purePreview));
      final decision = jsonObject(
        await call('progression propose', {
          'sessionId': session.id,
          'slotId': 'lift',
          'role': 'drop',
          'ruleType': 'threshold',
          'rule': _rule(),
        }),
        'decision',
      );
      equal(decision['role'], 'drop');
      final accepted = jsonObject(
        await call('progression accept', {
          'sessionId': session.id,
          'slotId': 'lift',
          'role': 'drop',
          'expectedVersion': decision['version'],
          'acceptedAt': instant(
            1,
          ).add(const Duration(hours: 2)).toIso8601String(),
        }),
        'decision',
      );
      equal(accepted['status'], 'accepted');
      final track = jsonObject(
        await call('progression track', {
          'templateId': 'role-practice',
          'revision': 1,
          'slotId': 'lift',
          'role': 'drop',
          'asOf': instant(2).toIso8601String(),
        }),
        'track',
      );
      equal(track['decisionId'], accepted['id']);
      equal(track['role'], 'drop');
      equal(track['runId'], null);
      equal(
        jsonObject(
          await call('progression show', {
            'sessionId': session.id,
            'slotId': 'lift',
            'role': 'drop',
          }),
          'decision',
        )['id'],
        accepted['id'],
      );
      final later = sessionFromJson(
        await call('store start', {
          'id': 'later',
          'templateId': 'role-practice',
          'revision': 1,
          'startedAt': instant(2).toIso8601String(),
        }),
      );
      check(
        later.sets
            .where((s) => s.role == 'drop')
            .every((s) => s.suggested['mass']!.value.toString() == '11'),
      );
      check(
        later.sets
            .where((s) => s.role == 'work')
            .every((s) => s.suggested['mass']!.value.toString() == '10'),
      );
      final pureSummary = const Commands().execute('session summary', {
        'schemaVersion': 1,
        'session': finished,
        'roles': ['drop', 'backoff'],
        'sumMetrics': ['mass'],
      })['data'];
      equal(canonicalJson(roleSummary), canonicalJson(pureSummary));
      final series = jsonObject(
        await call('store series', {
          'metric': 'mass',
          'context': {'role': 'drop'},
        }),
        'series',
      );
      equal(series['pointCount'], 2);
      final groups = jsonList(series, 'series');
      equal(
        jsonObject(
          jsonObject(groups.single, 'series')['context'],
          'context',
        )['role'],
        'drop',
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
