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

Future<TrainingSession> _logged(
  StoredTrainingService service,
  String id,
  int day,
) async {
  final started = await service.start(id, 'bench-pair', 1, instant(day));
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
}) => {
  'id': id,
  'metrics': metrics,
  if (cadence != null) 'cadence': cadence,
  'members': members,
  'baseline': baseline,
};

List<Object?> _sharedVector(String mass) => [
  for (var i = 0; i < 3; i++)
    {
      'mass': {'value': mass, 'unit': 'kg'},
    },
];

/// Completes every set with its suggested load but the given repetition
/// overrides per slot, then finalizes.
Future<TrainingSession> _exposure(
  StoredTrainingService service,
  TrainingSession started,
  Map<String, String> repsBySlot,
) => service.edit(started.id, started.contentVersion, (session) {
  for (final set in session.sets) {
    session = const TrainingService().complete(session, set.id, {
      'mass': set.suggested['mass']!,
      'reps': repsBySlot.containsKey(set.slotId)
          ? Quantity(repsBySlot[set.slotId]!, 'rep')
          : set.suggested['reps']!,
    });
  }
  return session.finish(started.startedAt.add(const Duration(hours: 1)));
});

List<String> _masses(Object? vector) => [
  for (final set in vector! as List)
    jsonObject(jsonObject(set, 'set')['mass'], 'mass')['value']! as String,
];

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

String _digest(String canonical) =>
    sha256.convert(utf8.encode(canonical)).toString();

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
  if (!keep) {
    data.remove('sharedApplications');
    data.remove('linkRetirements');
  }
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

void linkConsumptionTests() {
  test(
    'linked each-exposure sessions consume and advance one shared chain',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-link-use-');
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        await StoredTrainingService(store).publish(_pair(), 0);
        final tracks = await _tracks(store);
        equal(tracks.heavy.nextSets.first['mass']!.value.toString(), '60');
        equal(tracks.light.nextSets.first['mass']!.value.toString(), '47.5');
        final linkService = LeverLinkService(store);
        equal(
          (await linkService.create(
            input: _link(id: 'consumed'),
            createdAt: instant(2),
            expectedRevision: 0,
            confirm: true,
          )).number,
          1,
        );
        var state = await linkService.state('consumed');
        equal((state['chain']! as List).length, 0);
        equal(jsonObject(state['state'], 'state')['applicationSequence'], 0);
        equal(jsonObject(state['state'], 'state')['applicationId'], null);
        check(
          _masses(
            jsonObject(state['state'], 'state')['vector'],
          ).every((mass) => mass == '60'),
          'the chain seeds from the published baseline member',
        );

        final training = StoredTrainingService(store);
        final progression = StoredProgressionService(store);

        // A linked start consumes the shared mass but keeps member-only reps.
        final second = await training.start(
          'second',
          'bench-pair',
          1,
          instant(3),
        );
        for (final set in second.sets.where(
          (set) => set.slotId == 'bench-light',
        )) {
          equal(set.suggested['mass']!.value.toString(), '60');
          equal(set.suggested['reps']!.value.toString(), '8');
        }
        equal(
          second.sets
              .where((set) => set.slotId == 'bench-heavy')
              .first
              .suggested['reps']!
              .value
              .toString(),
          '9',
        );
        await _exposure(training, second, {'bench-light': '12'});
        final pending = await progression.propose(
          'second',
          'bench-light',
          _rule(),
        );
        final accepted = await progression.accept(
          'second',
          'bench-light',
          pending.version,
          instant(3).add(const Duration(hours: 3)),
        );
        equal(accepted.nextSets.first['mass']!.value.toString(), '62.5');
        state = await linkService.state('consumed');
        final chain = state['chain']! as List;
        equal(chain.length, 1);
        final row = jsonObject(chain.first, 'row');
        equal(row['id'], 'consumed/1');
        equal(row['originKind'], 'accept');
        equal(row['originSessionId'], 'second');
        equal(row['originDecisionId'], 'second/bench-light');
        equal(_masses(row['nextSets']).join(','), '62.5,62.5,62.5');
        equal(jsonObject(state['state'], 'state')['applicationSequence'], 1);

        // A decline appends the held vector plus one shared failure.
        final third = await training.start(
          'third',
          'bench-pair',
          1,
          instant(5),
        );
        equal(
          third.sets
              .where((set) => set.slotId == 'bench-light')
              .first
              .suggested['mass']!
              .value
              .toString(),
          '62.5',
        );
        await _exposure(training, third, {'bench-light': '5'});
        final pendingThird = await progression.propose(
          'third',
          'bench-light',
          _rule(),
        );
        final declined = await progression.decline(
          'third',
          'bench-light',
          pendingThird.version,
          instant(5).add(const Duration(hours: 3)),
        );
        equal(declined.failedSessions, 1);
        state = await linkService.state('consumed');
        final declinedRow = jsonObject((state['chain']! as List).last, 'row');
        equal(declinedRow['id'], 'consumed/2');
        equal(declinedRow['originKind'], 'decline');
        equal(declinedRow['failedSessions'], 1);
        equal(declinedRow['previousFailures'], 0);
        equal(_masses(declinedRow['nextSets']).join(','), '62.5,62.5,62.5');

        // A later manual advance strands a session that planned earlier.
        final raced = await training.start(
          'raced',
          'bench-pair',
          1,
          instant(6),
        );
        final racedLight = raced.sets
            .where((set) => set.slotId == 'bench-light')
            .first;
        equal(racedLight.suggested['mass']!.value.toString(), '62.5');
        final moved = await linkService.advance(
          linkId: 'consumed',
          nextSets: _sharedVector('65'),
          failedSessions: 1,
          expectedSequence: 2,
          at: instant(6).add(const Duration(minutes: 30)),
          confirm: true,
        );
        equal(moved.originKind, 'manual');
        check(
          (await _conflict(
            () => progression.propose('raced', 'bench-light', _rule()),
          ))!.contains('advanced after this session started'),
          'a moved chain never silently rebases a started session',
        );
        check(
          (await store.progressionDecisions()).every(
            (d) => d.resolvedAt != null || d.session.id != 'raced',
          ),
          'the conflicting proposal persisted nothing',
        );

        // Retiring the member at its session start forks it back to local.
        await _exposure(training, raced, {'bench-light': '8'});
        final retirement = await linkService.retire(
          linkId: 'consumed',
          memberAnchorId: 'accepted/bench-light',
          retiredAt: instant(6),
          confirm: true,
        );
        equal(retirement.id, 'consumed/retire/accepted/bench-light');
        equal(retirement.failedSessions, 1);
        equal(retirement.nextSets.first['mass']!.value.toString(), '62.5');
        equal(retirement.previousApplication, 'third/bench-light');

        final pendingRaced = await progression.propose(
          'raced',
          'bench-light',
          _rule(),
        );
        final racedAccepted = await progression.accept(
          'raced',
          'bench-light',
          pendingRaced.version,
          instant(6).add(const Duration(hours: 4)),
        );
        equal(racedAccepted.previousApplication, retirement.id);
        state = await linkService.state('consumed');
        equal((state['chain']! as List).length, 3);

        // The chain and the retired context now move independently.
        await linkService.advance(
          linkId: 'consumed',
          nextSets: _sharedVector('70'),
          failedSessions: 0,
          expectedSequence: 3,
          at: instant(7),
          confirm: true,
        );
        final unlinked = await training.start(
          'unlinked',
          'bench-pair',
          1,
          instant(8),
        );
        equal(
          unlinked.sets
              .where((set) => set.slotId == 'bench-light')
              .first
              .suggested['mass']!
              .value
              .toString(),
          '62.5',
        );
        equal(
          unlinked.sets
              .where((set) => set.slotId == 'bench-light')
              .first
              .suggested['reps']!
              .value
              .toString(),
          '9',
        );
        final heavyLater = await training.start(
          'heavy-later',
          'bench-pair',
          1,
          instant(8),
        );
        equal(
          heavyLater.sets
              .where((set) => set.slotId == 'bench-heavy')
              .first
              .suggested['mass']!
              .value
              .toString(),
          '70',
        );

        final heavyTrack = await progression.track(
          templateId: 'bench-pair',
          revision: 1,
          slotId: 'bench-heavy',
          asOf: instant(8).add(const Duration(hours: 2)),
        );
        equal(heavyTrack['policy'], 'bodytmi-progression-track/3');
        equal(heavyTrack['sourceKind'], 'decision');
        final linkView = jsonObject(heavyTrack['link'], 'link');
        equal(linkView['linkId'], 'consumed');
        equal(linkView['cadence'], 'each-exposure');
        equal(linkView['chainApplicationId'], 'consumed/4');
        equal(linkView['chainSequence'], 4);
        equal(
          _masses(
            jsonObject(heavyTrack['state'], 'state')['nextSets'],
          ).join(','),
          '70,70,70',
        );
        final lightTrack = await progression.track(
          templateId: 'bench-pair',
          revision: 1,
          slotId: 'bench-light',
          asOf: instant(6).add(const Duration(hours: 2)),
        );
        equal(lightTrack['sourceKind'], 'retirement');
        equal(lightTrack['retirementLink'], 'consumed');
        equal(lightTrack['supersedes'], 'third/bench-light');
        check(
          !lightTrack.containsKey('link'),
          'a retired context is not reported as linked',
        );
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'manual cadence links advance only through explicit link advance',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-link-manual-');
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        await StoredTrainingService(store).publish(_pair(), 0);
        await _tracks(store);
        final linkService = LeverLinkService(store);
        await linkService.create(
          input: _link(id: 'manual', cadence: 'manual'),
          createdAt: instant(2),
          expectedRevision: 0,
          confirm: true,
        );

        final probe = await linkService.status(
          _link(id: 'probe', members: const ['accepted/bench-heavy', 'x/lift']),
        );
        equal(probe['policy'], 'bodytmi-lever-link-status/1');
        equal(probe['contractOk'], false);
        equal(probe['currentRevision'], 0);
        check(
          (probe['blockers']! as List).cast<String>().any(
            (blocker) => blocker.contains('not a resolved'),
          ),
          'unresolved members are reported',
        );
        final ready = await linkService.status(_link(id: 'ready'));
        equal(ready['contractOk'], true);
        equal(
          _masses(jsonObject(ready['seed'], 'seed')['vector']).join(','),
          '60,60,60',
        );

        // A member accept on a manual link writes no chain row.
        final training = StoredTrainingService(store);
        final progression = StoredProgressionService(store);
        final second = await training.start(
          'second',
          'bench-pair',
          1,
          instant(3),
        );
        equal(
          second.sets
              .where((set) => set.slotId == 'bench-light')
              .first
              .suggested['mass']!
              .value
              .toString(),
          '60',
        );
        await _exposure(training, second, {'bench-light': '12'});
        final pending = await progression.propose(
          'second',
          'bench-light',
          _rule(),
        );
        await progression.accept(
          'second',
          'bench-light',
          pending.version,
          instant(3).add(const Duration(hours: 3)),
        );
        var state = await linkService.state('manual');
        check(
          (state['chain']! as List).isEmpty,
          'manual cadence member resolutions record no chain row',
        );

        check(
          (await _invalid(
            () => linkService.advance(
              linkId: 'manual',
              nextSets: _sharedVector('62.5'),
              failedSessions: 0,
              expectedSequence: 0,
              at: instant(4),
              confirm: false,
            ),
          ))!.contains('requires confirm:true'),
          'manual advances are explicit',
        );
        check(
          (await _invalid(
            () => linkService.advance(
              linkId: 'manual',
              nextSets: _sharedVector('62.5'),
              failedSessions: 0,
              cursor: 3,
              expectedSequence: 0,
              at: instant(4),
              confirm: true,
            ),
          ))!.contains('Invalid shared lever counters'),
          'double shared chains carry no coordinator position',
        );
        check(
          (await _invalid(
            () => linkService.advance(
              linkId: 'manual',
              nextSets: [
                for (var i = 0; i < 3; i++)
                  {
                    'reps': {'value': '8', 'unit': 'rep'},
                  },
              ],
              failedSessions: 0,
              expectedSequence: 0,
              at: instant(4),
              confirm: true,
            ),
          ))!.contains('exactly the shared metrics'),
          'shared vectors carry only the linked metrics',
        );
        check(
          (await _invalid(
            () => linkService.advance(
              linkId: 'manual',
              nextSets: [
                for (var i = 0; i < 2; i++)
                  {
                    'mass': {'value': '62.5', 'unit': 'kg'},
                  },
              ],
              failedSessions: 0,
              expectedSequence: 0,
              at: instant(4),
              confirm: true,
            ),
          ))!.contains('every working set'),
          'shared vectors cover every working set',
        );
        check(
          (await _conflict(
            () => linkService.advance(
              linkId: 'manual',
              nextSets: _sharedVector('62.5'),
              failedSessions: 0,
              expectedSequence: 1,
              at: instant(4),
              confirm: true,
            ),
          ))!.contains('advanced (sequence 0); expected 1'),
          'expectedSequence is compare-and-set',
        );
        final advanced = await linkService.advance(
          linkId: 'manual',
          nextSets: _sharedVector('62.5'),
          failedSessions: 0,
          expectedSequence: 0,
          at: instant(4),
          confirm: true,
        );
        equal(advanced.id, 'manual/1');
        equal(advanced.originKind, 'manual');
        equal(advanced.originSessionId, null);
        equal(
          canonicalJson(
            (await linkService.advance(
              linkId: 'manual',
              nextSets: _sharedVector('62.5'),
              failedSessions: 0,
              expectedSequence: 0,
              at: instant(4),
              confirm: true,
            )).toJson(),
          ),
          canonicalJson(advanced.toJson()),
        );
        check(
          (await _conflict(
            () => linkService.advance(
              linkId: 'manual',
              nextSets: _sharedVector('65'),
              failedSessions: 0,
              expectedSequence: 0,
              at: instant(4),
              confirm: true,
            ),
          ))!.contains('already recorded'),
          'a recorded sequence cannot be rewritten',
        );
        check(
          (await _conflict(
            () => linkService.advance(
              linkId: 'manual',
              nextSets: _sharedVector('65'),
              failedSessions: 0,
              expectedSequence: 2,
              at: instant(5),
              confirm: true,
            ),
          ))!.contains('advanced (sequence 1); expected 2'),
          'a stale expectation conflicts',
        );
        check(
          (await _invalid(
            () => linkService.advance(
              linkId: 'manual',
              nextSets: _sharedVector('65'),
              failedSessions: 0,
              expectedSequence: 1,
              at: instant(4).subtract(const Duration(hours: 1)),
              confirm: true,
            ),
          ))!.contains('cannot precede'),
          'chain time never moves backward',
        );

        // Later starts consume the advanced chain even without member rows.
        final third = await training.start(
          'third',
          'bench-pair',
          1,
          instant(5),
        );
        equal(
          third.sets
              .where((set) => set.slotId == 'bench-light')
              .first
              .suggested['mass']!
              .value
              .toString(),
          '62.5',
        );
        await _exposure(training, third, {'bench-light': '12'});
        final pendingThird = await progression.propose(
          'third',
          'bench-light',
          _rule(),
        );
        await progression.accept(
          'third',
          'bench-light',
          pendingThird.version,
          instant(5).add(const Duration(hours: 3)),
        );
        state = await linkService.state('manual');
        check(
          (state['chain']! as List).length == 1,
          'manual cadence stays explicit after more member exposures',
        );
        final members = state['members']! as List;
        check(
          members.length == 2 &&
              members.every(
                (member) => jsonObject(member, 'm')['retiredAt'] == null,
              ),
          'members stay unretired',
        );
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'shared chains and retirements survive portability and old labels reject them',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-link-use-port-',
      );
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      TrainingArchive? archived;
      String before;
      try {
        await StoredTrainingService(store).publish(_pair(), 0);
        await _tracks(store);
        final linkService = LeverLinkService(store);
        await linkService.create(
          input: _link(id: 'portable-chain'),
          createdAt: instant(2),
          expectedRevision: 0,
          confirm: true,
        );
        final training = StoredTrainingService(store);
        final progression = StoredProgressionService(store);
        final second = await training.start(
          'second',
          'bench-pair',
          1,
          instant(3),
        );
        await _exposure(training, second, {'bench-light': '12'});
        final pending = await progression.propose(
          'second',
          'bench-light',
          _rule(),
        );
        await progression.accept(
          'second',
          'bench-light',
          pending.version,
          instant(3).add(const Duration(hours: 3)),
        );
        await linkService.retire(
          linkId: 'portable-chain',
          memberAnchorId: 'accepted/bench-light',
          retiredAt: instant(4),
          confirm: true,
        );
        archived = await store.archive();
        before = canonicalJson(archived.toJson());
        equal(archived.sharedApplications.length, 1);
        equal(archived.linkRetirements.length, 1);
        equal(
          (await store.backup('${dir.path}/native'))['databaseSchemaVersion'],
          58,
        );
        await LogicalArchiveFiles.export(archived, '${dir.path}/full.json');
      } finally {
        await store.close();
      }
      try {
        equal(
          NativeBackup.validateDatabase('${dir.path}/native/database.sqlite'),
          58,
        );
        final full = await LogicalArchiveFiles.prepare('${dir.path}/full.json');
        try {
          equal(canonicalJson(full.archive.toJson()), before);
          equal(full.archive.sharedApplications.length, 1);
          equal(full.archive.linkRetirements.length, 1);
          final target = await TrainingStore.open(
            '${dir.path}/restored.sqlite',
          );
          try {
            await target.restore(
              full.backup,
              recoveryDestination: '${dir.path}/recovery',
              confirm: true,
            );
          } finally {
            await target.close();
          }
          final reopened = await TrainingStore.open(
            '${dir.path}/restored.sqlite',
          );
          try {
            equal(canonicalJson((await reopened.archive()).toJson()), before);
            final state = await LeverLinkService(
              reopened,
            ).state('portable-chain');
            equal((state['chain']! as List).length, 1);
          } finally {
            await reopened.close();
          }
        } finally {
          await full.close();
        }
        check(
          (await _relabelRejects(
            '${dir.path}/full.json',
            53,
            keep: true,
          )).contains('Unknown fields'),
          'shared chains need the new logical label',
        );
        check(
          (await _relabelRejects(
            '${dir.path}/full.json',
            54,
            keep: false,
          )).contains('requires shared lever applications'),
          'the new label names its sections',
        );
        File('${dir.path}/labeled.sqlite').writeAsBytesSync(
          File('${dir.path}/native/database.sqlite').readAsBytesSync(),
        );
        final labeled = sqlite3.open('${dir.path}/labeled.sqlite');
        labeled.userVersion = 53;
        labeled.close();
        check(
          _nativeError(
            '${dir.path}/labeled.sqlite',
          ).contains('does not match supported schema v53'),
          'a v54 profile cannot claim the older schema label',
        );
        File('${dir.path}/dropped.sqlite').writeAsBytesSync(
          File('${dir.path}/native/database.sqlite').readAsBytesSync(),
        );
        final dropped = sqlite3.open('${dir.path}/dropped.sqlite');
        dropped.execute('DROP TABLE shared_lever_applications');
        dropped.execute('DROP TABLE link_retirement_anchors');
        dropped.execute('DROP TABLE IF EXISTS program_upgrade_receipts');
        dropped.execute('DROP TABLE IF EXISTS exercise_revisions');
        dropped.execute('DROP TABLE IF EXISTS implementation_revisions');
        dropped.userVersion = 53;
        dropped.close();
        check(
          _nativeError(
            '${dir.path}/dropped.sqlite',
          ).contains('Progression baseline is inconsistent'),
          'a relabeled profile cannot silently drop the chain its linked '
          'exposure decision depends on',
        );
        // A genuinely unlinked v53 profile upgrades honestly to v54.
        final plain = '${dir.path}/plain.sqlite';
        final plainStore = await TrainingStore.open(plain);
        try {
          await StoredTrainingService(plainStore).publish(_pair(), 0);
          await _tracks(plainStore);
          await LeverLinkService(plainStore).create(
            input: _link(id: 'idle-link'),
            createdAt: instant(2),
            expectedRevision: 0,
            confirm: true,
          );
          equal(
            (await plainStore.backup(
              '${dir.path}/plain-native',
            ))['databaseSchemaVersion'],
            58,
          );
        } finally {
          await plainStore.close();
        }
        final aged = sqlite3.open('${dir.path}/plain-native/database.sqlite');
        aged.execute('DROP TABLE shared_lever_applications');
        aged.execute('DROP TABLE link_retirement_anchors');
        aged.execute('DROP TABLE IF EXISTS program_upgrade_receipts');
        aged.execute('DROP TABLE IF EXISTS exercise_revisions');
        aged.execute('DROP TABLE IF EXISTS implementation_revisions');
        aged.userVersion = 53;
        aged.close();
        equal(
          _nativeError('${dir.path}/plain-native/database.sqlite'),
          'ok:53',
        );
        final migrated = await TrainingStore.open(
          '${dir.path}/plain-native/database.sqlite',
        );
        try {
          final after = await migrated.archive();
          equal(after.sharedApplications.length, 0);
          equal(after.linkRetirements.length, 0);
          check(
            after.sessions.length == 1,
            'the v53 profile keeps its sessions through the upgrade',
          );
          check(
            after.links.any((revision) => revision.link.id == 'idle-link'),
            'the v53 profile keeps its unlinked link through the upgrade',
          );
          equal(
            (await migrated.backup(
              '${dir.path}/upgraded',
            ))['databaseSchemaVersion'],
            58,
          );
          final state = await LeverLinkService(migrated).state('idle-link');
          equal((state['chain']! as List).length, 0);
        } finally {
          await migrated.close();
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test('the CLI advances, states and retires one shared lever track', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-link-use-cli-');
    final path = '${dir.path}/db.sqlite';
    final store = await TrainingStore.open(path);
    try {
      await StoredTrainingService(store).publish(_pair(), 0);
      await _tracks(store);
      await LeverLinkService(store).create(
        input: _link(id: 'cli-shared'),
        createdAt: instant(2),
        expectedRevision: 0,
        confirm: true,
      );
    } finally {
      await store.close();
    }
    Future<({int code, String output, String error})> command(
      List<String> names,
      Map<String, Object?> input,
    ) => invoke(
      names,
      jsonEncode({'schemaVersion': 1, 'database': path, ...input}),
    );

    equal((await command(['link', 'state'], {})).code, 2);
    equal((await command(['link', 'state'], {'linkId': 'nope'})).code, 3);
    final shown = await command(['link', 'state'], {'linkId': 'cli-shared'});
    equal(shown.code, 0);
    final stateData = jsonObject(
      jsonObject(jsonDecode(shown.output), 'response')['data'],
      'data',
    );
    equal(stateData['policy'], 'bodytmi-lever-link-state/1');
    equal((stateData['chain']! as List).length, 0);

    equal(
      (await command(['link', 'status'], {'link': _link(id: 'probe')})).code,
      0,
    );
    equal((await command(['link', 'status'], {})).code, 2);

    equal(
      (await command(
        ['link', 'advance'],
        {
          'linkId': 'cli-shared',
          'nextSets': _sharedVector('62.5'),
          'failedSessions': 0,
          'expectedSequence': 0,
          'at': '2026-10-02T12:30:00Z',
        },
      )).code,
      2,
    );
    equal(
      (await command(
        ['link', 'advance'],
        {
          'linkId': 'nope',
          'nextSets': _sharedVector('62.5'),
          'failedSessions': 0,
          'expectedSequence': 0,
          'at': '2026-10-02T12:30:00Z',
          'confirm': true,
        },
      )).code,
      3,
    );
    equal(
      (await command(
        ['link', 'advance'],
        {
          'linkId': 'cli-shared',
          'nextSets': _sharedVector('62.5'),
          'failedSessions': 0,
          'expectedSequence': 5,
          'at': '2026-10-02T12:30:00Z',
          'confirm': true,
        },
      )).code,
      5,
    );
    final advanced = await command(
      ['link', 'advance'],
      {
        'linkId': 'cli-shared',
        'nextSets': _sharedVector('62.5'),
        'failedSessions': 0,
        'expectedSequence': 0,
        'at': '2026-10-02T12:30:00Z',
        'confirm': true,
      },
    );
    equal(advanced.code, 0);
    equal(
      jsonObject(
        jsonObject(jsonDecode(advanced.output), 'response')['data'],
        'data',
      )['id'],
      'cli-shared/1',
    );
    final replay = await command(
      ['link', 'advance'],
      {
        'linkId': 'cli-shared',
        'nextSets': _sharedVector('62.5'),
        'failedSessions': 0,
        'expectedSequence': 0,
        'at': '2026-10-02T12:30:00Z',
        'confirm': true,
      },
    );
    equal(replay.output, advanced.output);
    equal(
      (await command(
        ['link', 'advance'],
        {
          'linkId': 'cli-shared',
          'nextSets': _sharedVector('65'),
          'failedSessions': 0,
          'expectedSequence': 0,
          'at': '2026-10-02T12:30:00Z',
          'confirm': true,
        },
      )).code,
      5,
    );

    equal(
      (await command(
        ['link', 'retire'],
        {
          'linkId': 'cli-shared',
          'memberAnchorId': 'accepted/bench-light',
          'retiredAt': '2026-10-03T12:00:00Z',
        },
      )).code,
      2,
    );
    final retired = await command(
      ['link', 'retire'],
      {
        'linkId': 'cli-shared',
        'memberAnchorId': 'accepted/bench-light',
        'retiredAt': '2026-10-03T12:00:00Z',
        'confirm': true,
      },
    );
    check(retired.code == 0, 'CLI retire failed: ${retired.error}');
    equal(
      jsonObject(
        jsonObject(jsonDecode(retired.output), 'response')['data'],
        'data',
      )['id'],
      'cli-shared/retire/accepted/bench-light',
    );
    equal(
      (await command(
        ['link', 'retire'],
        {
          'linkId': 'cli-shared',
          'memberAnchorId': 'accepted/bench-light',
          'retiredAt': '2026-10-04T12:00:00Z',
          'confirm': true,
        },
      )).code,
      5,
    );
    final afterStateResponse = jsonDecode(
      (await command(['link', 'state'], {'linkId': 'cli-shared'})).output,
    );
    final afterState = jsonObject(
      jsonObject(afterStateResponse, 'response')['data'],
      'data',
    );
    equal((afterState['chain']! as List).length, 1);
    final members = afterState['members']! as List;
    check(
      members.any(
        (member) =>
            jsonObject(member, 'm')['anchorId'] == 'accepted/bench-light' &&
            (jsonObject(member, 'm')['retiredAt']! as String).startsWith(
              '2026-10-03T12:00:00',
            ),
      ),
      'the state view names the retired member',
    );
    await dir.delete(recursive: true);
  });
}
