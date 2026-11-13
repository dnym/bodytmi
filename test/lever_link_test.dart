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

Map<String, Object?> _rule() =>
    jsonObject(example('double-progression')['rule'], 'rule');

WorkoutDefinition _pair() =>
    WorkoutDefinition.fromJson(example('lever-link-practice')['definition']);

Map<String, Object?> _thresholdRule({
  List<String> increments = const ['mass', 'reps'],
}) => {
  'metric': 'reps',
  'minimum': {'value': '1', 'unit': 'rep'},
  'threshold': {'value': '8', 'unit': 'rep'},
  'increments': {
    for (final metric in increments)
      metric: metric == 'mass'
          ? {'value': '2.5', 'unit': 'kg'}
          : {'value': '1', 'unit': 'rep'},
  },
};

Future<TrainingSession> _logged(
  StoredTrainingService service,
  String id,
  int day, {
  int revision = 1,
  ProgramRun? programRun,
}) async {
  final started = await service.start(
    id,
    'bench-pair',
    revision,
    instant(day),
    programRun: programRun,
  );
  return service.edit(id, started.contentVersion, (session) {
    for (final set in session.sets) {
      session = const TrainingService().complete(
        session,
        set.id,
        const {},
        acceptSuggested: true,
      );
    }
    return session.finish(instant(day).add(const Duration(hours: 1)));
  });
}

/// Resolves one double-progression track for each of the two bench slots.
Future<({ProgressionDecision heavy, ProgressionDecision light})> _tracks(
  TrainingStore store,
) async {
  final service = StoredTrainingService(store);
  final progression = StoredProgressionService(store);
  final session = await _logged(service, 'accepted', 1);
  final heavy = await progression.propose(session.id, 'bench-heavy', _rule());
  final light = await progression.propose(session.id, 'bench-light', _rule());
  return (
    heavy: await progression.accept(
      session.id,
      'bench-heavy',
      heavy.version,
      instant(1).add(const Duration(hours: 2)),
    ),
    light: await progression.accept(
      session.id,
      'bench-light',
      light.version,
      instant(1).add(const Duration(hours: 2)),
    ),
  );
}

Map<String, Object?> _link({
  String id = 'bench-shared',
  List<String> members = const ['accepted/bench-heavy', 'accepted/bench-light'],
  String baseline = 'accepted/bench-heavy',
  List<String> metrics = const ['mass'],
  String? cadence,
  String? name,
}) => {
  'id': id,
  if (name != null) 'name': name,
  'metrics': metrics,
  if (cadence != null) 'cadence': cadence,
  'members': members,
  'baseline': baseline,
};

String _digest(String canonical) =>
    sha256.convert(utf8.encode(canonical)).toString();

Future<String?> _invalid(Future<Object?> action()) async {
  try {
    await action();
  } on BodyTmiException catch (error) {
    equal(error.code, 'validation');
    return error.message;
  }
  throw StateError('Expected a validation error.');
}

Future<String?> _conflict(Future<Object?> action()) async {
  try {
    await action();
  } on BodyTmiException catch (error) {
    equal(error.code, 'conflict');
    return error.message;
  }
  throw StateError('Expected a conflict.');
}

String _nativeError(String database) {
  try {
    return 'ok:${NativeBackup.validateDatabase(database)}';
  } on BodyTmiException catch (error) {
    return error.message;
  }
}

Future<String> _relabelRejects(
  String source,
  int label, {
  required bool keep,
}) async {
  final json = jsonObject(
    jsonDecode(await File(source).readAsString()),
    'file',
  );
  final data = jsonObject(json['data'], 'data');
  if (!keep) data.remove('links');
  json['format'] = 'bodytmi-logical-export/$label';
  json.remove('sha256');
  json['sha256'] = _digest(canonicalJson(json));
  await File(source).writeAsString(jsonEncode(json));
  try {
    final prepared = await LogicalArchiveFiles.prepare(source);
    await prepared.close();
  } on BodyTmiException catch (error) {
    return error.message;
  }
  throw StateError('Expected the relabel to be rejected.');
}

void leverLinkTests() {
  test(
    'link create binds two resolved tracks to one shared lever intent',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-link-');
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        await StoredTrainingService(store).publish(_pair(), 0);
        final tracks = await _tracks(store);
        equal(tracks.heavy.id, 'accepted/bench-heavy');
        equal(tracks.light.id, 'accepted/bench-light');
        final service = LeverLinkService(store);
        final created = await service.create(
          input: _link(name: 'Shared bench mass'),
          createdAt: instant(2),
          expectedRevision: 0,
          confirm: true,
        );
        equal(created.number, 1);
        final link = created.link;
        equal(link.id, 'bench-shared');
        equal(link.name, 'Shared bench mass');
        equal(link.cadence, 'each-exposure');
        jsonEqual(link.metrics, ['mass']);
        equal(link.baseline, 'accepted/bench-heavy');
        jsonEqual(
          [for (final member in link.members) member.anchorId],
          ['accepted/bench-heavy', 'accepted/bench-light'],
        );
        jsonEqual(
          [for (final member in link.members) member.templateId],
          ['bench-pair', 'bench-pair'],
        );
        equal(link.members.first.slot.id, 'bench-heavy');
        equal(link.members.first.role, 'work');
        final shown = await service.revision('bench-shared');
        equal(canonicalJson(shown.toJson()), canonicalJson(created.toJson()));
        final listed = await service.list();
        equal(listed.length, 1);
        // The stored archive cross-validates members against their tracks.
        final archive = await store.archive();
        equal(archive.links.length, 1);
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'one link identity replays, evolves only its fields and keeps membership',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-link-rev-');
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        await StoredTrainingService(store).publish(_pair(), 0);
        await _tracks(store);
        final service = LeverLinkService(store);
        final first = await service.create(
          input: _link(),
          createdAt: instant(2),
          expectedRevision: 0,
          confirm: true,
        );
        final replay = await service.create(
          input: _link(),
          createdAt: instant(3),
          expectedRevision: 1,
          confirm: true,
        );
        equal(canonicalJson(replay.toJson()), canonicalJson(first.toJson()));
        final evolved = await service.create(
          input: _link(metrics: ['mass', 'reps'], cadence: 'manual'),
          createdAt: instant(3),
          expectedRevision: 1,
          confirm: true,
        );
        equal(evolved.number, 2);
        equal(evolved.link.cadence, 'manual');
        final listed = await service.list();
        equal(listed.length, 2);
        equal(
          canonicalJson(listed.first.toJson()),
          canonicalJson(first.toJson()),
        );
        final old = await service.revision('bench-shared', 1);
        equal(old.number, 1);
        check(
          await _conflict(
                () => service.create(
                  input: _link(),
                  createdAt: instant(2),
                  expectedRevision: 0,
                  confirm: true,
                ),
              ) !=
              null,
          'compare-and-set rejects a stale base',
        );
        check(
          await _conflict(
                () => service.create(
                  input: _link(baseline: 'accepted/bench-light'),
                  createdAt: instant(3),
                  expectedRevision: 1,
                  confirm: true,
                ),
              ) !=
              null,
          'the baseline is immutable',
        );
        check(
          await _conflict(
                () => service.create(
                  input: _link(members: const ['accepted/bench-heavy']),
                  createdAt: instant(3),
                  expectedRevision: 1,
                  confirm: true,
                ),
              ) !=
              null,
          'membership is immutable',
        );
        await _invalid(
          () => service.create(
            input: _link(),
            createdAt: instant(2),
            expectedRevision: 0,
            confirm: false,
          ),
        );
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'overlapping links, unresolved anchors and incompatible writers fail',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-link-bad-');
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        await StoredTrainingService(store).publish(_pair(), 0);
        final service = LeverLinkService(store);
        final progression = StoredProgressionService(store);
        final session = await _logged(
          StoredTrainingService(store),
          'pending',
          1,
        );
        final pending = await progression.propose(
          session.id,
          'bench-heavy',
          _rule(),
        );
        check(
          await _invalid(
                () => service.create(
                  input: _link(
                    id: 'pending-link',
                    members: ['pending/bench-heavy', 'accepted/bench-heavy'],
                  ),
                  createdAt: instant(2),
                  expectedRevision: 0,
                  confirm: true,
                ),
              ) !=
              null,
          'members must be resolved tracks',
        );
        equal(pending.acceptedAt, null);
        await _tracks(store);
        final first = await service.create(
          input: _link(id: 'first-link'),
          createdAt: instant(2),
          expectedRevision: 0,
          confirm: true,
        );
        check(
          await _conflict(
                () => service.create(
                  input: _link(id: 'second-link'),
                  createdAt: instant(2),
                  expectedRevision: 0,
                  confirm: true,
                ),
              ) !=
              null,
          'one track backs at most one link',
        );
        equal(first.number, 1);
        check(
          await _invalid(
                () => service.create(
                  input: _link(
                    id: 'bad',
                    members: const ['accepted/bench-heavy'],
                  ),
                  createdAt: instant(2),
                  expectedRevision: 0,
                  confirm: true,
                ),
              ) !=
              null,
          'a link needs at least two members',
        );
        check(
          await _invalid(
                () => service.create(
                  input: _link(id: 'bad', baseline: 'nope/bench-heavy'),
                  createdAt: instant(2),
                  expectedRevision: 0,
                  confirm: true,
                ),
              ) !=
              null,
          'the baseline must be a member',
        );
        check(
          await _invalid(
                () => service.create(
                  input: _link(id: 'bad', cadence: 'sometimes'),
                  createdAt: instant(2),
                  expectedRevision: 0,
                  confirm: true,
                ),
              ) !=
              null,
          'cadence is explicit',
        );
        check(
          await _invalid(
                () => service.create(
                  input: _link(id: 'bad', metrics: ['distance']),
                  createdAt: instant(2),
                  expectedRevision: 0,
                  confirm: true,
                ),
              ) !=
              null,
          'shared metrics must be controlled by every member',
        );
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'linked tracks must share the rule kind and coordinated lever shape',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-link-rule-');
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        await StoredTrainingService(store).publish(_pair(), 0);
        final service = StoredTrainingService(store);
        final progression = StoredProgressionService(store);
        final session = await _logged(service, 'accepted', 1);
        final heavy = await progression.propose(
          session.id,
          'bench-heavy',
          _rule(),
        );
        await progression.accept(
          session.id,
          'bench-heavy',
          heavy.version,
          instant(1).add(const Duration(hours: 2)),
        );
        final light = await progression.propose(
          session.id,
          'bench-light',
          _thresholdRule(),
          ruleType: 'threshold',
        );
        await progression.accept(
          session.id,
          'bench-light',
          light.version,
          instant(1).add(const Duration(hours: 2)),
        );
        final links = LeverLinkService(store);
        check(
          await _invalid(
                () => links.create(
                  input: _link(),
                  createdAt: instant(2),
                  expectedRevision: 0,
                  confirm: true,
                ),
              ) !=
              null,
          'rule kinds must match',
        );
        // Every track resolves one exposure per context, so later member
        // tracks come from fresh run-isolated contexts.
        await ProgramService(store).publish(
          ProgramDefinition.fromJson({
            'id': 'link-cycle',
            'name': 'Link cycle',
            'plan': {
              'id': 'cycle',
              'type': 'day',
              'label': 'Upper',
              'templateId': 'bench-pair',
              'revision': 1,
            },
          }),
          0,
        );
        final doubleRun = await ProgramService(
          store,
        ).create('double-run', 'link-cycle', 1, instant(2));
        final wideRun = await ProgramService(
          store,
        ).create('wide-run', 'link-cycle', 1, instant(2));
        final narrowRun = await ProgramService(
          store,
        ).create('narrow-run', 'link-cycle', 1, instant(2));
        final thirdRun = await ProgramService(
          store,
        ).create('third-run', 'link-cycle', 1, instant(2));
        // The same rule kind on both tracks links cleanly.  Run-scoped
        // contexts keep these tracks separate from the ad hoc probes above.
        await _logged(service, 'second', 2, programRun: doubleRun);
        final secondHeavy = await progression.propose(
          'second',
          'bench-heavy',
          _rule(),
        );
        final secondLight = await progression.propose(
          'second',
          'bench-light',
          _rule(),
        );
        await progression.accept(
          'second',
          'bench-heavy',
          secondHeavy.version,
          instant(2).add(const Duration(hours: 2)),
        );
        await progression.accept(
          'second',
          'bench-light',
          secondLight.version,
          instant(2).add(const Duration(hours: 2)),
        );
        final double = await links.create(
          input: _link(
            id: 'first-link',
            baseline: 'second/bench-heavy',
            members: ['second/bench-heavy', 'second/bench-light'],
          ),
          createdAt: instant(2),
          expectedRevision: 0,
          confirm: true,
        );
        equal(double.number, 1);
        // Same kind but a different coordinated lever shape also fails.
        await _logged(service, 'wide', 3, programRun: wideRun);
        final wideHeavy = await progression.propose(
          'wide',
          'bench-heavy',
          _thresholdRule(),
          ruleType: 'threshold',
        );
        await progression.accept(
          'wide',
          'bench-heavy',
          wideHeavy.version,
          instant(3).add(const Duration(hours: 2)),
        );
        await _logged(service, 'narrow', 4, programRun: narrowRun);
        final narrowLight = await progression.propose(
          'narrow',
          'bench-light',
          _thresholdRule(increments: ['mass']),
          ruleType: 'threshold',
        );
        await progression.accept(
          'narrow',
          'bench-light',
          narrowLight.version,
          instant(4).add(const Duration(hours: 2)),
        );
        check(
          await _invalid(
                () => links.create(
                  input: _link(
                    id: 'shape-link',
                    baseline: 'wide/bench-heavy',
                    members: ['wide/bench-heavy', 'narrow/bench-light'],
                  ),
                  createdAt: instant(5),
                  expectedRevision: 0,
                  confirm: true,
                ),
              ) !=
              null,
          'linked threshold tracks need one coordinated lever shape',
        );
        // Matching threshold shapes link cleanly even though a different
        // double link already exists elsewhere.
        await _logged(service, 'third', 5, programRun: thirdRun);
        final heavy3 = await progression.propose(
          'third',
          'bench-heavy',
          _thresholdRule(),
          ruleType: 'threshold',
        );
        final light3 = await progression.propose(
          'third',
          'bench-light',
          _thresholdRule(),
          ruleType: 'threshold',
        );
        await progression.accept(
          'third',
          'bench-heavy',
          heavy3.version,
          instant(5).add(const Duration(hours: 2)),
        );
        await progression.accept(
          'third',
          'bench-light',
          light3.version,
          instant(5).add(const Duration(hours: 2)),
        );
        final same = await links.create(
          input: _link(
            id: 'threshold-link',
            baseline: 'third/bench-heavy',
            members: ['third/bench-heavy', 'third/bench-light'],
          ),
          createdAt: instant(6),
          expectedRevision: 0,
          confirm: true,
        );
        equal(same.number, 1);
        check(
          await _conflict(
                () => links.create(
                  input: _link(
                    id: 'overlap-link',
                    baseline: 'third/bench-heavy',
                    members: ['third/bench-heavy', 'wide/bench-heavy'],
                  ),
                  createdAt: instant(6),
                  expectedRevision: 0,
                  confirm: true,
                ),
              ) !=
              null,
          'a linked track cannot join a second link',
        );
        equal((await links.list()).length, 2);
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'pure revision rules keep numbering contiguous and links disjoint',
    () async {
      final slot = definition().slots.first;
      final lightSlot = definition().slots.last;
      LeverLink link(
        String id,
        List<LeverLinkMember> members,
        String baseline,
      ) => LeverLink(
        id: id,
        metrics: const ['mass'],
        members: members,
        baseline: baseline,
        createdAt: instant(1),
      );
      final first = LeverLinkMember(
        anchorId: 'a/one',
        runId: null,
        templateId: 'upper-a',
        slot: slot,
        role: 'work',
      );
      final second = LeverLinkMember(
        anchorId: 'b/two',
        runId: null,
        templateId: 'upper-a',
        slot: lightSlot,
        role: 'work',
      );
      final third = LeverLinkMember(
        anchorId: 'c/three',
        runId: 'run-1',
        templateId: 'upper-a',
        slot: slot,
        role: 'work',
      );
      final one = LeverLinkRevision.publish(
        link('one', [first, second], 'a/one'),
      );
      LeverLinkRevision before(int number, LeverLink body) =>
          LeverLinkRevision.fromJson({
            'schemaVersion': 1,
            'revision': number,
            'link': body.toJson(),
          });
      check(() {
        validateLeverLinkRevisions([
          one,
          LeverLinkRevision.publish(
            link('one', [first, second], 'a/one'),
            previous: one,
          ),
        ]);
        return true;
      }(), 'later revisions may keep membership and evolve only fields');
      rejects(
        () => validateLeverLinkRevisions([
          before(2, link('gappy', [first, second], 'a/one')),
        ]),
      );
      rejects(
        () => validateLeverLinkRevisions([
          one,
          before(3, link('one', [first, second], 'a/one')),
        ]),
      );
      rejects(
        () => validateLeverLinkRevisions([
          one,
          before(2, link('one', [first, second, third], 'a/one')),
        ]),
      );
      rejects(
        () => validateLeverLinkRevisions([
          one,
          before(2, link('one', [first, second], 'b/two')),
        ]),
      );
      rejects(
        () => validateLeverLinkRevisions([
          one,
          LeverLinkRevision.publish(link('shared', [first, third], 'c/three')),
        ]),
      );
      rejects(() => link('baseline', [first, second], 'missing'));
      rejects(() => link('alone', [first], 'a/one'));
      rejects(
        () => LeverLinkMember(
          anchorId: 'x',
          runId: null,
          templateId: 'upper-a',
          slot: slot,
          role: 'sprint',
        ),
      );
    },
  );

  test(
    'native and logical v54 archives carry links while older labels reject them',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-link-port-');
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      TrainingArchive? archived;
      String before;
      try {
        await StoredTrainingService(store).publish(_pair(), 0);
        await _tracks(store);
        await LeverLinkService(store).create(
          input: _link(id: 'portable-link', name: 'Portable'),
          createdAt: instant(2),
          expectedRevision: 0,
          confirm: true,
        );
        archived = await store.archive();
        before = canonicalJson(archived.toJson());
        equal(
          (await store.backup('${dir.path}/native'))['databaseSchemaVersion'],
          60,
        );
        await LogicalArchiveFiles.export(archived, '${dir.path}/full.json');
        await LogicalArchiveFiles.export(archived, '${dir.path}/bare.json');
      } finally {
        await store.close();
      }
      try {
        equal(
          NativeBackup.validateDatabase('${dir.path}/native/database.sqlite'),
          60,
        );
        final full = await LogicalArchiveFiles.prepare('${dir.path}/full.json');
        try {
          equal(canonicalJson(full.archive.toJson()), before);
          check(
            full.archive.links.any(
              (revision) => revision.link.id == 'portable-link',
            ),
            'the link survives the logical round trip',
          );
        } finally {
          await full.close();
        }
        check(
          (await _relabelRejects(
            '${dir.path}/full.json',
            52,
            keep: true,
          )).contains('Unknown fields'),
          'links need the new label',
        );
        check(
          (await _relabelRejects(
            '${dir.path}/bare.json',
            54,
            keep: false,
          )).contains('requires lever links'),
          'the new label names its section',
        );
        File('${dir.path}/labeled.sqlite').writeAsBytesSync(
          File('${dir.path}/native/database.sqlite').readAsBytesSync(),
        );
        final labeled = sqlite3.open('${dir.path}/labeled.sqlite');
        labeled.userVersion = 52;
        labeled.close();
        check(
          _nativeError(
            '${dir.path}/labeled.sqlite',
          ).contains('does not match supported schema v52'),
          'a v53 profile cannot claim the older schema label',
        );
        File('${dir.path}/dropped.sqlite').writeAsBytesSync(
          File('${dir.path}/native/database.sqlite').readAsBytesSync(),
        );
        final dropped = sqlite3.open('${dir.path}/dropped.sqlite');
        dropped.execute('DROP TABLE lever_link_revisions');
        dropped.execute('DROP TABLE IF EXISTS shared_lever_applications');
        dropped.execute('DROP TABLE IF EXISTS link_retirement_anchors');
        dropped.execute('DROP TABLE IF EXISTS program_upgrade_receipts');
        dropped.execute('DROP TABLE IF EXISTS exercise_revisions');
        dropped.execute('DROP TABLE IF EXISTS implementation_revisions');
        dropped.execute('DROP TABLE IF EXISTS equipment_revisions');
        dropped.execute('DROP TABLE IF EXISTS gym_revisions');
        dropped.execute('DROP TABLE IF EXISTS equipment_instance_revisions');
        dropped.userVersion = 52;
        dropped.close();
        equal(_nativeError('${dir.path}/dropped.sqlite'), 'ok:52');
        final migrated = await TrainingStore.open('${dir.path}/dropped.sqlite');
        try {
          final after = await migrated.archive();
          equal(after.links.length, 0);
          equal(after.sessions.length, 1);
          equal(
            (await migrated.backup(
              '${dir.path}/upgraded',
            ))['databaseSchemaVersion'],
            60,
          );
        } finally {
          await migrated.close();
        }
        final reopened = await TrainingStore.open(
          '${dir.path}/native/database.sqlite',
        );
        try {
          equal(canonicalJson((await reopened.archive()).toJson()), before);
          equal((await LeverLinkService(reopened).list()).length, 1);
        } finally {
          await reopened.close();
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test('the CLI creates, shows and lists one shared lever link', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-link-act-cli-');
    final path = '${dir.path}/db.sqlite';
    final store = await TrainingStore.open(path);
    try {
      await StoredTrainingService(store).publish(_pair(), 0);
      await _tracks(store);
    } finally {
      await store.close();
    }
    Future<({int code, String output, String error})> command(
      Map<String, Object?> input,
    ) => invoke(
      ['link', 'create'],
      jsonEncode({
        'schemaVersion': 1,
        'database': path,
        'expectedRevision': 0,
        'createdAt': '2026-10-02T12:00:00Z',
        'link': _link(id: 'cli-link'),
        ...input,
      }),
    );
    equal((await command({})).code, 2);
    equal((await command({'confirm': true, 'expectedRevision': -1})).code, 2);
    equal((await command({'confirm': true, 'createdAt': 'yesterday'})).code, 2);
    final first = await command({'confirm': true});
    equal(first.code, 0);
    final created = jsonObject(
      jsonObject(jsonDecode(first.output), 'response')['data'],
      'data',
    );
    equal(created['revision'], 1);
    equal(jsonObject(created['link'], 'link')['id'], 'cli-link');
    equal(
      (await command({'confirm': true, 'expectedRevision': 1})).output,
      first.output,
    );
    equal((await command({'confirm': true, 'expectedRevision': 5})).code, 5);
    equal(
      (await command({
        'confirm': true,
        'expectedRevision': 1,
        'link': _link(id: 'cli-link', baseline: 'accepted/bench-light'),
      })).code,
      5,
    );
    equal(
      (await command({
        'confirm': true,
        'expectedRevision': 1,
        'link': _link(id: 'cli-link', metrics: ['mass', 'reps']),
      })).code,
      0,
    );
    final shown = await invoke(
      ['link', 'show'],
      jsonEncode({
        'schemaVersion': 1,
        'database': path,
        'linkId': 'cli-link',
        'revision': 1,
      }),
    );
    equal(shown.code, 0);
    equal(shown.output, first.output);
    equal(
      (await invoke(
        ['link', 'show'],
        jsonEncode({'schemaVersion': 1, 'database': path, 'linkId': 'nope'}),
      )).code,
      3,
    );
    final listed = await invoke([
      'link',
      'list',
    ], jsonEncode({'schemaVersion': 1, 'database': path}));
    equal(listed.code, 0);
    final rows =
        jsonObject(jsonDecode(listed.output), 'response')['data']!
            as List<Object?>;
    equal(rows.length, 2);
    equal(
      jsonObject(jsonObject(rows.first, 'revision')['link'], 'link')['id'],
      'cli-link',
    );
    equal(
      (await invoke([
        'link',
        'create',
      ], jsonEncode({'schemaVersion': 1, 'database': path}))).code,
      2,
    );
    await dir.delete(recursive: true);
  });
}
