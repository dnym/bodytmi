import 'dart:convert';
import 'dart:io';

import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart' show expectLater, isA, throwsA;

import 'fixtures.dart';
import 'support.dart';

WorkoutDefinition _workout() => WorkoutDefinition.fromJson({
  'id': 'targetless',
  'name': 'Bounded objectives',
  'slots': [
    {
      'id': 'slot',
      'exercise': 'exercise',
      'implementation': 'machine',
      'targets': <String, Object?>{},
    },
  ],
  'plan': {
    'id': 'workout',
    'type': 'sequence',
    'children': [
      {
        'id': 'bounded',
        'type': 'effort',
        'slot': 'slot',
        'objectives': {
          'mass': {
            'mode': 'minimum',
            'minimum': {'value': '50', 'unit': 'kg'},
          },
          'reps': {'mode': 'observe', 'unit': 'rep'},
        },
      },
      {
        'id': 'other',
        'type': 'effort',
        'slot': 'slot',
        'objectives': {
          'mass': {
            'mode': 'minimum',
            'minimum': {'value': '50', 'unit': 'kg'},
          },
        },
      },
    ],
  },
});

Map<String, Object?> _graph({
  String metric = 'mass',
  String occurrence = 'workout/bounded',
}) => {
  'id': 'bounded-graph',
  'nodes': [
    {
      'id': 'source',
      'kind': 'source',
      'unit': metric == 'reps' ? 'rep' : 'kg',
      'sourceId': 'input',
    },
  ],
  'bindings': {
    'input': {
      'kind': 'manual',
      'version': 1,
      'value': {'value': '80', 'unit': metric == 'reps' ? 'rep' : 'kg'},
    },
  },
  'plans': [
    {
      'id': 'plan',
      'templateId': 'targetless',
      'revision': 1,
      'bindings': [
        {'occurrenceId': occurrence, 'metric': metric, 'nodeId': 'source'},
      ],
    },
  ],
};

void derivedTargetlessSessionTests() {
  Future<void> withStore(
    Future<void> Function(TrainingStore, String) action,
  ) async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-targetless-');
    final store = await TrainingStore.open('${dir.path}/profile.sqlite');
    try {
      await StoredTrainingService(store).publish(_workout(), 0);
      await action(store, dir.path);
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  }

  test(
    'derived plans supply bounded targetless suggestions without changing objective semantics',
    () => withStore((store, dir) async {
      final training = StoredTrainingService(store);
      final graphs = DerivedTargetGraphService(store);
      await graphs.publish(DerivedTargetGraph.fromJson(_graph()), 0);
      final session = await training.start(
        'planned',
        'targetless',
        1,
        instant(2),
        derivedPlan: const DerivedPlanRef('bounded-graph', 1, 'plan'),
      );
      final set = session.sets.first;
      equal(set.suggested['mass']!.value.toString(), '80');
      equal(set.criteria['mass']!.lower!.value.toString(), '50');
      check(!set.suggested.containsKey('reps'));
      check(session.sets.last.suggested.isEmpty);
      rejects(
        () => const TrainingService().complete(
          session,
          set.id,
          {},
          acceptSuggested: true,
        ),
      );
      final completed = await training.edit(
        session.id,
        session.contentVersion,
        (s) => const TrainingService().complete(s, set.id, {
          'reps': Quantity('7', 'rep'),
        }, acceptSuggested: true),
      );
      equal(completed.sets.first.actuals['mass']!.value.toString(), '80');
      equal(completed.sets.first.actuals['reps']!.value.toString(), '7');
      equal(
        canonicalJson(sessionFromJson(completed.toJson()).toJson()),
        canonicalJson(completed.toJson()),
      );
      final retry = await training.start(
        'planned',
        'targetless',
        1,
        instant(2),
        derivedPlan: const DerivedPlanRef('bounded-graph', 1, 'plan'),
      );
      equal(canonicalJson(retry.toJson()), canonicalJson(completed.toJson()));
      await LogicalArchiveFiles.export(
        await store.archive(),
        '$dir/export.json',
      );
      final prepared = await LogicalArchiveFiles.prepare('$dir/export.json');
      try {
        await store.restore(
          prepared.backup,
          recoveryDestination: '$dir/recovery',
          confirm: true,
        );
        await store.close();
        final reopened = await TrainingStore.open('$dir/profile.sqlite');
        try {
          equal(
            canonicalJson(
              (await StoredTrainingService(
                reopened,
              ).session('planned')).toJson(),
            ),
            canonicalJson(completed.toJson()),
          );
        } finally {
          await reopened.close();
        }
      } finally {
        await prepared.close();
      }
    }),
  );

  test(
    'targetless derived suggestions require published mapped bounded objectives',
    () => withStore((store, _) async {
      final graphs = DerivedTargetGraphService(store);
      await expectLater(
        graphs.publish(DerivedTargetGraph.fromJson(_graph(metric: 'reps')), 0),
        throwsA(isA<BodyTmiException>()),
      );
      await graphs.publish(DerivedTargetGraph.fromJson(_graph()), 0);
      final session = await StoredTrainingService(store).start(
        'planned',
        'targetless',
        1,
        instant(2),
        derivedPlan: const DerivedPlanRef('bounded-graph', 1, 'plan'),
      );
      final forged = copyJson(session.toJson());
      final sets = jsonList(forged, 'sets');
      final other = jsonObject(sets.last, 'set');
      jsonObject(other['suggested'], 'suggested')['mass'] = {
        'value': '80',
        'unit': 'kg',
      };
      rejects(() => sessionFromJson(forged));
      final noPlan = copyJson(session.toJson())..remove('derivedPlanInput');
      rejects(() => sessionFromJson(noPlan));
    }),
  );

  test(
    'v31 labels reject derived targetless suggestions',
    () => withStore((store, dir) async {
      await DerivedTargetGraphService(
        store,
      ).publish(DerivedTargetGraph.fromJson(_graph()), 0);
      await StoredTrainingService(store).start(
        'planned',
        'targetless',
        1,
        instant(2),
        derivedPlan: const DerivedPlanRef('bounded-graph', 1, 'plan'),
      );
      await LogicalArchiveFiles.export(
        await store.archive(),
        '$dir/export.json',
      );
      final envelope =
          jsonDecode(await File('$dir/export.json').readAsString())
              as Map<String, Object?>;
      envelope['format'] = 'bodytmi-logical-export/31';
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
      await File('$dir/old.json').writeAsString(jsonEncode(envelope));
      await expectLater(
        LogicalArchiveFiles.prepare('$dir/old.json'),
        throwsA(isA<BodyTmiException>()),
      );
      await store.snapshot('$dir/snapshot.sqlite');
      equal(NativeBackup.validateDatabase('$dir/snapshot.sqlite'), 36);
      final db = sqlite3.open('$dir/snapshot.sqlite');
      db.userVersion = 31;
      db.close();
      rejects(() => NativeBackup.validateDatabase('$dir/snapshot.sqlite'));
    }),
  );
  test(
    'v31 profiles migrate without changing existing sessions',
    () => withStore((store, dir) async {
      final original = await StoredTrainingService(
        store,
      ).start('old', 'targetless', 1, instant(1));
      await store.snapshot('$dir/old.sqlite');
      final db = sqlite3.open('$dir/old.sqlite');
      db.userVersion = 31;
      db.close();
      final reopened = await TrainingStore.open('$dir/old.sqlite');
      try {
        final same = await StoredTrainingService(reopened).session('old');
        equal(canonicalJson(same.toJson()), canonicalJson(original.toJson()));
      } finally {
        await reopened.close();
      }
      final migrated = sqlite3.open('$dir/old.sqlite');
      equal(migrated.userVersion, 36);
      migrated.close();
    }),
  );

  test(
    'bounded derived objectives work in two independent program runs',
    () => withStore((store, _) async {
      await DerivedTargetGraphService(
        store,
      ).publish(DerivedTargetGraph.fromJson(_graph()), 0);
      final programs = ProgramService(store);
      await programs.publish(
        ProgramDefinition.fromJson({
          'id': 'program',
          'name': 'Program',
          'plan': {
            'id': 'day',
            'type': 'day',
            'templateId': 'targetless',
            'revision': 1,
          },
        }),
        0,
      );
      for (final run in ['strength', 'cardio']) {
        await programs.create(run, 'program', 1, instant(1));
        final session = await programs.start(
          run,
          1,
          '$run-session',
          instant(2),
          derivedPlan: const DerivedPlanRef('bounded-graph', 1, 'plan'),
        );
        equal(session.sets.first.suggested['mass']!.value.toString(), '80');
        final graph = jsonObject(
          jsonObject(
            session.derivedPlanInput!.snapshot['preview'],
            'preview',
          )['graphResolution'],
          'graph',
        );
        equal(jsonObject(graph['historyScope'], 'scope')['runId'], run);
      }
      equal((await store.archive()).sessions.length, 2);
    }),
  );
}
