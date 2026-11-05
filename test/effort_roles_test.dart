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
    'stored progression remains work-only and independent across program runs',
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
        equal(NativeBackup.validateDatabase('${dir.path}/roles.sqlite'), 41);
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
