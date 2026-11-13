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
const _slot = 'bench-heavy';
final _template = definition().id;

Future<TrainingSession> _logged(
  StoredTrainingService service,
  String id,
  int day, {
  int revision = 1,
  bool fail = false,
}) async {
  final started = await service.start(id, _template, revision, instant(day));
  return service.edit(id, started.contentVersion, (session) {
    for (final set in session.sets) {
      session = const TrainingService().complete(
        session,
        set.id,
        fail && set.slotId == _slot ? {'reps': Quantity('1', 'rep')} : const {},
        acceptSuggested: true,
      );
    }
    return session.finish(instant(day).add(const Duration(hours: 1)));
  });
}

/// Completes every still-planned set with its suggestion and finalizes.
Future<TrainingSession> _finish(
  StoredTrainingService service,
  TrainingSession session,
) => service.edit(session.id, session.contentVersion, (session) {
  for (final set in session.sets.where(
    (set) => set.status == SetStatus.planned,
  )) {
    session = const TrainingService().complete(
      session,
      set.id,
      const {},
      acceptSuggested: true,
    );
  }
  return session.finish(session.startedAt.add(const Duration(hours: 1)));
});

Future<ProgressionDecision> _acceptedTrack(
  TrainingStore store,
  StoredProgressionService progression,
) async {
  final session = await _logged(StoredTrainingService(store), 'accepted', 1);
  final pending = await progression.propose(session.id, _slot, _rule());
  return progression.accept(
    session.id,
    _slot,
    pending.version,
    instant(1).add(const Duration(hours: 2)),
  );
}

Map<String, Object?> _thresholdRule() => {
  'metric': 'reps',
  'minimum': {'value': '1', 'unit': 'rep'},
  'threshold': {'value': '8', 'unit': 'rep'},
  'increments': {
    'mass': {'value': '2.5', 'unit': 'kg'},
    'reps': {'value': '1', 'unit': 'rep'},
  },
  'coordination': {
    'mode': 'roundRobin',
    'order': ['mass', 'reps'],
  },
};

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
  if (!keep) data.remove('reconciliations');
  if (label < 54) data.remove('links');
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
  throw StateError('Expected the older label to reject receipts.');
}

String _digest(String canonical) =>
    sha256.convert(utf8.encode(canonical)).toString();

String _nativeError(String database) {
  try {
    return 'ok:${NativeBackup.validateDatabase(database)}';
  } on BodyTmiException catch (error) {
    return error.message;
  }
}

List<String> _suggested(Object? sets, String metric) => [
  for (final set in sets! as List<Object?>)
    jsonObject(
          jsonObject(jsonObject(set, 'set')['suggested'], 'suggested')[metric],
          metric,
        )['value']!
        as String,
];
List<String> _planned(Iterable<TrainingSet> sets, String metric) => [
  for (final set in sets) set.suggested[metric]!.value.toString(),
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

Map<String, Object?> _slotTargets(Map<String, Object?> definitionJson) =>
    jsonObject(
      jsonObject(
        (definitionJson['slots']! as List<Object?>).first,
        'slot',
      )['targets'],
      'targets',
    );

List<String> _kinds(Map<String, Object?> report) => [
  for (final blocker in report['blockers']! as List<Object?>)
    jsonObject(blocker, 'blocker')['kind']! as String,
];

List<Object?> _values(Object? sets, String metric) => [
  for (final set in sets! as List<Object?>)
    jsonObject(jsonObject(set, 'set')[metric], metric)['value'],
];

Future<String?> _conflict(Future<Object?> action()) async {
  try {
    await action();
  } on BodyTmiException catch (error) {
    equal(error.code, 'conflict');
    return error.message;
  }
  throw StateError('Expected a conflict.');
}

void reconciliationTests() {
  test(
    'reconcile-status names each prescription difference that blocks a later start',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-reconcile-');
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final service = StoredTrainingService(store);
        final progression = StoredProgressionService(store);
        await service.publish(definition(), 0);
        await _acceptedTrack(store, progression);
        Future<Map<String, Object?>> status(int revision) =>
            progression.reconcileStatus(
              templateId: _template,
              revision: revision,
              slotId: _slot,
              asOf: instant(2),
            );

        final same = await status(1);
        equal(same['policy'], 'bodytmi-progression-reconciliation/1');
        equal(same['reconciliationRequired'], false);
        check(same['track'] != null, 'the accepted track is reported');
        final track = jsonObject(same['track'], 'track');
        equal(track['ruleType'], 'double');
        equal(track['sourceSessionId'], 'accepted');
        equal(track['workingSetCount'], 3);
        jsonEqual(same['controlledMetrics'], ['mass', 'reps']);
        jsonEqual(
          _values(jsonObject(track['state'], 'state')['nextSets'], 'reps'),
          ['9', '9', '9'],
        );
        jsonEqual(_kinds(same), []);

        // A controlled slot target changes without forming a new context.
        final drifted = copyJson(definition().toJson());
        _slotTargets(drifted)['reps'] = {'value': '10', 'unit': 'rep'};
        await service.publish(WorkoutDefinition.fromJson(drifted), 1);
        final target = await status(2);
        equal(target['reconciliationRequired'], true);
        jsonEqual(target['blockerKinds'], ['slotTarget']);
        jsonEqual(
          jsonObject(target['blockedCommands'], 'commands')['store start'],
          ['slotTarget'],
        );
        jsonEqual(
          _values(
            jsonObject(target['candidate'], 'candidate')['effortTargets'],
            'reps',
          ),
          ['10', '10', '10'],
        );
        final blocker = jsonObject(
          (target['blockers']! as List<Object?>).first,
          'blocker',
        );
        equal(blocker['metric'], 'reps');
        equal(jsonObject(blocker['prior'], 'prior')['value'], '8');
        equal(jsonObject(blocker['proposed'], 'proposed')['value'], '10');
        final message = await _conflict(
          () => service.start('drifted-start', _template, 2, instant(3)),
        );
        check(message!.contains('slotTarget'), 'a conflict names its kind');
        check(
          message.contains('reconcile-status'),
          'a conflict points at the report command',
        );
        equal(await store.session('drifted-start'), null);

        // The authored working-set count no longer matches the applied vector.
        final extra = copyJson(definition().toJson());
        jsonObject(
          jsonObject(
            (jsonObject(extra['plan'], 'plan')['children']! as List<Object?>)
                .first,
            'repeat',
          ),
          'repeat',
        )['count'] = 4;
        await service.publish(WorkoutDefinition.fromJson(extra), 2);
        final count = await status(3);
        jsonEqual(count['blockerKinds'], ['workingSetCount']);
        jsonEqual((count['blockers']! as List<Object?>).first, {
          'kind': 'workingSetCount',
          'priorWorkingSetCount': 3,
          'proposedWorkingSetCount': 4,
        });
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'authored per-effort targets, manual session targets and rule edits each need reconciliation',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-reconcile-rule-',
      );
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final service = StoredTrainingService(store);
        final progression = StoredProgressionService(store);
        await service.publish(definition(), 0);
        await _acceptedTrack(store, progression);

        // Authored per-effort targets equal to the applied vector are still an
        // authored change of a resolved controlled context.
        final authored = copyJson(definition().toJson());
        jsonObject(
          jsonObject(
            jsonObject(
              (jsonObject(authored['plan'], 'plan')['children']!
                      as List<Object?>)
                  .first,
              'repeat',
            )['child'],
            'child',
          ),
          'child',
        )['targets'] = {
          'reps': {'value': '9', 'unit': 'rep'},
          'mass': {'value': '60', 'unit': 'kg'},
        };
        await service.publish(WorkoutDefinition.fromJson(authored), 1);
        final effort = await progression.reconcileStatus(
          templateId: _template,
          revision: 2,
          slotId: _slot,
          asOf: instant(2),
        );
        jsonEqual(effort['blockerKinds'], ['effortTarget']);
        final shifted = jsonObject(
          (effort['blockers']! as List<Object?>).first,
          'blocker',
        );
        equal(shifted['ordinal'], 0);
        equal(shifted['metric'], 'reps');
        equal(jsonObject(shifted['prior'], 'prior')['value'], '8');
        equal(jsonObject(shifted['proposed'], 'proposed')['value'], '9');

        // A later compatible session keeps the applied targets.
        final active = await service.start('later', _template, 1, instant(2));
        final held = await progression.reconcileStatus(
          templateId: _template,
          revision: 1,
          slotId: _slot,
          asOf: instant(3),
          sessionId: active.id,
        );
        equal(held['reconciliationRequired'], false);
        jsonEqual(
          _values(
            jsonObject(held['candidate'], 'candidate')['sessionTargets'],
            'reps',
          ),
          ['9', '9', '9'],
        );

        final clean = await _logged(service, 'clean', 2);
        final changedRule = copyJson(_rule());
        jsonObject(changedRule['objectiveStep'], 'objectiveStep')['value'] =
            '2';
        final rule = await progression.reconcileStatus(
          templateId: _template,
          revision: 1,
          slotId: _slot,
          asOf: instant(3),
          sessionId: clean.id,
          rule: changedRule,
        );
        jsonEqual(rule['blockerKinds'], ['rule']);
        jsonEqual(
          jsonObject(
            rule['blockedCommands'],
            'commands',
          )['progression propose'],
          ['rule'],
        );
        final ruleMessage = await _conflict(
          () => progression.propose(clean.id, _slot, changedRule),
        );
        check(ruleMessage!.contains('rule'), 'a rule conflict names its kind');

        // A manually edited suggestion diverges from the applied vector.
        final edited = await service.edit(
          active.id,
          active.contentVersion,
          (session) => const TrainingService().editTarget(
            session,
            session.sets.firstWhere((set) => set.slotId == _slot).id,
            'reps',
            Quantity('11', 'rep'),
          ),
        );
        equal(
          edited.sets
              .firstWhere((set) => set.slotId == _slot)
              .suggested['reps']!
              .value
              .toString(),
          '11',
        );
        final divergence = await progression.reconcileStatus(
          templateId: _template,
          revision: 1,
          slotId: _slot,
          asOf: instant(3),
          sessionId: edited.id,
        );
        jsonEqual(divergence['blockerKinds'], ['sessionTarget']);
        final blocker = jsonObject(
          (divergence['blockers']! as List<Object?>).first,
          'blocker',
        );
        equal(blocker['ordinal'], 0);
        equal(blocker['metric'], 'reps');
        equal(jsonObject(blocker['applied'], 'applied')['value'], '9');
        equal(jsonObject(blocker['suggested'], 'suggested')['value'], '11');
        final done = await _finish(service, edited);
        final baselineMessage = await _conflict(
          () => progression.propose(done.id, _slot, _rule()),
        );
        check(
          baselineMessage!.contains('sessionTarget'),
          'a baseline conflict names its kind',
        );
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'the reconciliation report is read-only and reachable through the CLI',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-reconcile-cli-',
      );
      final path = '${dir.path}/db.sqlite';
      final store = await TrainingStore.open(path);
      try {
        final service = StoredTrainingService(store);
        await service.publish(definition(), 0);
        await _acceptedTrack(store, StoredProgressionService(store));
        final drifted = copyJson(definition().toJson());
        _slotTargets(drifted)['reps'] = {'value': '10', 'unit': 'rep'};
        await service.publish(WorkoutDefinition.fromJson(drifted), 1);
      } finally {
        await store.close();
      }
      Future<({int code, String output, String error})> command(
        Map<String, Object?> input,
      ) => invoke(
        ['progression', 'reconcile-status'],
        jsonEncode({
          'schemaVersion': 1,
          'database': path,
          'templateId': _template,
          'slotId': _slot,
          'asOf': '2026-10-02T12:00:00Z',
          ...input,
        }),
      );
      final report = await command({'revision': 2});
      equal(report.code, 0);
      equal(report.error, '');
      final data = jsonObject(
        jsonObject(jsonDecode(report.output), 'response')['data'],
        'data',
      );
      jsonEqual(data['blockerKinds'], ['slotTarget']);
      equal(data['reconciliationRequired'], true);
      check(
        (data['blockerKinds']! as List<Object?>).isNotEmpty,
        'a drifted prescription needs reconciliation',
      );
      equal((await command({})).code, 2);
      equal((await command({'revision': 2, 'confirm': true})).code, 2);
      equal((await command({'revision': 2, 'runId': 'no-such-run'})).code, 3);
      final repeated = await command({'revision': 2});
      equal(repeated.output, report.output);
      await dir.delete(recursive: true);
    },
  );

  test(
    'a durable reconciliation re-anchors the track and a later start and proposal consume it',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-reconcile-act-',
      );
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final service = StoredTrainingService(store);
        final progression = StoredProgressionService(store);
        await service.publish(definition(), 0);
        final applied = await _acceptedTrack(store, progression);
        final drifted = copyJson(definition().toJson());
        _slotTargets(drifted)['reps'] = {'value': '10', 'unit': 'rep'};
        await service.publish(WorkoutDefinition.fromJson(drifted), 1);

        final blocked = await _conflict(
          () => service.start('after', _template, 2, instant(2)),
        );
        check(
          blocked!.contains('slotTarget'),
          'a blocked start names its kind',
        );
        check(
          (await store.sessions()).length == 1,
          'a blocked start stores nothing',
        );

        final stale = await _conflict(
          () => progression.reconcile(
            id: 'other-act',
            templateId: _template,
            revision: 2,
            slotId: _slot,
            expectedSequence: 7,
            kinds: ['slotTarget'],
            reconciledAt: instant(2),
            confirm: true,
          ),
        );
        check(
          stale!.contains('expected sequence'),
          'the sequence is compare-and-set',
        );
        final mismatched = await _conflict(
          () => progression.reconcile(
            id: 'other-kinds',
            templateId: _template,
            revision: 2,
            slotId: _slot,
            expectedSequence: 1,
            kinds: ['effortTarget'],
            reconciledAt: instant(2),
            confirm: true,
          ),
        );
        check(
          mismatched!.contains('kinds differ'),
          'kinds must name the current blockers',
        );
        final unnecessary = await _conflict(
          () => progression.reconcile(
            id: 'other-target',
            templateId: _template,
            revision: 1,
            slotId: _slot,
            expectedSequence: 1,
            kinds: ['slotTarget'],
            reconciledAt: instant(2),
            confirm: true,
          ),
        );
        check(
          unnecessary!.contains('nothing needs reconciliation'),
          'a matching candidate writes nothing',
        );
        final unconfirmed = await _invalid(
          () => progression.reconcile(
            id: 'unconfirmed',
            templateId: _template,
            revision: 2,
            slotId: _slot,
            expectedSequence: 1,
            kinds: ['slotTarget'],
            reconciledAt: instant(2),
            confirm: false,
          ),
        );
        check(unconfirmed!.contains('confirm:true'), 'reconciling confirms');
        check(
          (await progression.reconciliations()).isEmpty,
          'a rejected reconciliation writes nothing',
        );

        final receipt = await progression.reconcile(
          id: 'reanchor-heavy',
          templateId: _template,
          revision: 2,
          slotId: _slot,
          expectedSequence: 1,
          kinds: ['slotTarget'],
          reconciledAt: instant(2),
          confirm: true,
        );
        equal(receipt.status, 'reconciled');
        equal(receipt.sequence, 2);
        equal(receipt.previousSequence, 1);
        equal(receipt.previousApplication, applied.id);
        equal(receipt.pinnedRevision.number, 2);
        equal(receipt.ruleType, 'double');
        jsonEqual(receipt.acknowledgedKinds, ['slotTarget']);
        check(
          receipt.sourceSessionId == null,
          'a revision-only adoption names no source session',
        );
        jsonEqual(_planned(receipt.sets, 'reps'), ['10', '10', '10']);
        jsonEqual(_planned(receipt.sets, 'mass'), ['60', '60', '60']);
        check(
          receipt.sets.every(
            (set) => set.status == SetStatus.planned && set.actuals.isEmpty,
          ),
          'a reconciliation adopts only planned suggestions',
        );

        final replay = await progression.reconcile(
          id: 'reanchor-heavy',
          templateId: _template,
          revision: 2,
          slotId: _slot,
          expectedSequence: 1,
          kinds: ['slotTarget'],
          reconciledAt: instant(2),
          confirm: true,
        );
        equal(canonicalJson(replay.toJson()), canonicalJson(receipt.toJson()));
        final competing = await _conflict(
          () => progression.reconcile(
            id: 'reanchor-heavy',
            templateId: _template,
            revision: 2,
            slotId: _slot,
            expectedSequence: 1,
            kinds: ['slotTarget'],
            reconciledAt: instant(2),
            resetFailures: true,
            confirm: true,
          ),
        );
        check(
          competing!.contains('different act'),
          'one identity records one act',
        );
        final twice = await _conflict(
          () => progression.reconcile(
            id: 'again-heavy',
            templateId: _template,
            revision: 2,
            slotId: _slot,
            expectedSequence: 2,
            kinds: ['slotTarget'],
            reconciledAt: instant(2),
            confirm: true,
          ),
        );
        check(
          twice!.contains('nothing needs reconciliation'),
          'the receipt now matches the candidate prescription',
        );
        equal((await progression.reconciliations()).length, 1);

        final started = await service.start('after', _template, 2, instant(2));
        jsonEqual(
          _planned(started.sets.where((set) => set.slotId == _slot), 'reps'),
          ['10', '10', '10'],
        );
        final finished = await _finish(service, started);
        final pending = await progression.propose(finished.id, _slot, _rule());
        equal(pending.previousApplication, receipt.id);
        equal(pending.previousSequence, 2);
        final next = await progression.accept(
          finished.id,
          _slot,
          pending.version,
          instant(3),
        );
        equal(next.sequence, 3);
        equal(next.previousApplication, receipt.id);
        jsonEqual(
          [for (final set in next.nextSets) set['reps']!.value.toString()],
          ['11', '11', '11'],
        );
        equal((await progression.decision(finished.id, _slot)).id, next.id);

        final track = await progression.track(
          templateId: _template,
          revision: 2,
          slotId: _slot,
          asOf: instant(2).add(const Duration(minutes: 1)),
        );
        equal(track['policy'], 'bodytmi-progression-track/3');
        equal(track['sourceKind'], 'reconciliation');
        equal(track['decisionId'], receipt.id);
        equal(track['supersedes'], applied.id);
        jsonEqual(track['acknowledgedKinds'], ['slotTarget']);
        equal(track['status'], 'reconciled');
        equal(track['sequence'], 2);
        jsonEqual(
          _values(jsonObject(track['state'], 'state')['nextSets'], 'reps'),
          ['10', '10', '10'],
        );
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'a reconciliation carries or explicitly resets failed exposures without replaying the resolved decision',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-reconcile-fail-',
      );
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final service = StoredTrainingService(store);
        final progression = StoredProgressionService(store);
        await service.publish(definition(), 0);
        final missed = await _logged(service, 'missed', 1, fail: true);
        final pending = await progression.propose(missed.id, _slot, _rule());
        final declined = await progression.decline(
          missed.id,
          _slot,
          pending.version,
          instant(1).add(const Duration(hours: 2)),
        );
        equal(declined.failedSessions, 1);
        equal(declined.sequence, 1);

        final drifted = copyJson(definition().toJson());
        _slotTargets(drifted)['reps'] = {'value': '10', 'unit': 'rep'};
        await service.publish(WorkoutDefinition.fromJson(drifted), 1);
        final carried = await progression.reconcile(
          id: 'carry-failures',
          templateId: _template,
          revision: 2,
          slotId: _slot,
          expectedSequence: 1,
          kinds: ['slotTarget'],
          reconciledAt: instant(2),
          confirm: true,
        );
        equal(carried.previousFailures, 1);
        equal(carried.failedSessions, 1);
        check(!carried.resetFailures, 'carrying the counter is the default');

        final further = copyJson(definition().toJson());
        _slotTargets(further)['reps'] = {'value': '12', 'unit': 'rep'};
        await service.publish(WorkoutDefinition.fromJson(further), 2);
        final reset = await progression.reconcile(
          id: 'reset-failures',
          templateId: _template,
          revision: 3,
          slotId: _slot,
          expectedSequence: 2,
          kinds: ['slotTarget'],
          reconciledAt: instant(3),
          resetFailures: true,
          confirm: true,
        );
        equal(reset.previousFailures, 1);
        equal(reset.failedSessions, 0);
        equal(reset.previousApplication, carried.id);
        equal(reset.previousSequence, 2);
        equal(reset.sequence, 3);

        final unchanged = await progression.decision(missed.id, _slot);
        equal(unchanged.failedSessions, 1);
        equal(unchanged.sequence, 1);
        check(
          unchanged.declinedAt == declined.declinedAt,
          'the decline stays terminal',
        );
        jsonEqual(
          (await progression.reconciliations())
              .map((receipt) => receipt.id)
              .toList()
            ..sort(),
          ['carry-failures', 'reset-failures'],
        );

        final track = await progression.track(
          templateId: _template,
          revision: 3,
          slotId: _slot,
          asOf: instant(4),
        );
        equal(track['sourceKind'], 'reconciliation');
        equal(track['decisionId'], reset.id);
        equal(jsonObject(track['state'], 'state')['failedSessions'], 0);
        equal(track['resetFailures'], true);
        final started = await service.start(
          'after-resets',
          _template,
          3,
          instant(4),
        );
        jsonEqual(
          _planned(started.sets.where((set) => set.slotId == _slot), 'reps'),
          ['12', '12', '12'],
        );
        final later = await progression.propose(
          (await _finish(service, started)).id,
          _slot,
          _rule(),
        );
        equal(later.previousFailures, 0);
        equal(later.previousApplication, reset.id);

        final changed = copyJson(definition().toJson());
        _slotTargets(changed)['reps'] = {'value': '14', 'unit': 'rep'};
        await service.publish(WorkoutDefinition.fromJson(changed), 3);
        final cursorless = await _invalid(
          () => progression.reconcile(
            id: 'double-cursor',
            templateId: _template,
            revision: 4,
            slotId: _slot,
            expectedSequence: 3,
            kinds: ['slotTarget'],
            reconciledAt: instant(5),
            resetCursor: true,
            confirm: true,
          ),
        );
        check(
          cursorless!.contains('reconciliation state'),
          'a double-progression track holds no coordinator position',
        );
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'a reconciliation keeps coordinator positions unless reset and rejects stored state drift',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-reconcile-cursor-',
      );
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final service = StoredTrainingService(store);
        final progression = StoredProgressionService(store);
        await service.publish(definition(), 0);
        final first = await _logged(service, 'counted', 1);
        final pending = await progression.propose(
          first.id,
          _slot,
          _thresholdRule(),
          ruleType: 'threshold',
        );
        equal(pending.previousCursor, 0);
        equal(pending.previousSequence, 0);
        final applied = await progression.accept(
          first.id,
          _slot,
          pending.version,
          instant(1).add(const Duration(hours: 2)),
        );
        equal(applied.ruleType, 'threshold');
        equal(applied.cursor, 1);
        equal(applied.failedSessions, 0);

        final drifted = copyJson(definition().toJson());
        _slotTargets(drifted)['reps'] = {'value': '10', 'unit': 'rep'};
        await service.publish(WorkoutDefinition.fromJson(drifted), 1);
        final carried = await progression.reconcile(
          id: 'keep-cursor',
          templateId: _template,
          revision: 2,
          slotId: _slot,
          expectedSequence: 1,
          kinds: ['slotTarget'],
          reconciledAt: instant(2),
          confirm: true,
        );
        equal(carried.ruleType, 'threshold');
        equal(carried.previousCursor, 1);
        equal(carried.cursor, 1);
        equal(carried.toJson()['cursor'], 1);
        jsonEqual(_planned(carried.sets, 'reps'), ['10', '10', '10']);

        final further = copyJson(definition().toJson());
        _slotTargets(further)['reps'] = {'value': '12', 'unit': 'rep'};
        await service.publish(WorkoutDefinition.fromJson(further), 2);
        final reset = await progression.reconcile(
          id: 'drop-cursor',
          templateId: _template,
          revision: 3,
          slotId: _slot,
          expectedSequence: 2,
          kinds: ['slotTarget'],
          reconciledAt: instant(3),
          resetCursor: true,
          confirm: true,
        );
        equal(reset.previousCursor, 1);
        equal(reset.cursor, 0);
        equal(reset.ruleType, 'threshold');
        equal(reset.toJson()['cursor'], 0);

        final track = await progression.track(
          templateId: _template,
          revision: 3,
          slotId: _slot,
          asOf: instant(4),
        );
        equal(jsonObject(track['state'], 'state')['cursor'], 0);
        equal(track['resetFailures'], false);
        equal(track['ruleType'], 'threshold');

        final counter = carried.toJson()..['failedSessions'] = 4;
        rejects(() => ReconciliationReceipt.fromJson(counter));
        final unlabeled = carried.toJson()..remove('cursor');
        rejects(() => ReconciliationReceipt.fromJson(unlabeled));
        final mislabeled = carried.toJson()..['ruleType'] = 'double';
        rejects(() => ReconciliationReceipt.fromJson(mislabeled));
        final explicitWork = carried.toJson()..['role'] = 'work';
        rejects(() => ReconciliationReceipt.fromJson(explicitWork));
        rejects(
          () => ReconciliationReceipt(
            id: 'double-reset',
            runId: null,
            revision: revision(),
            slotId: _slot,
            role: 'work',
            sets: baselineSets(revision(), _slot, 'work'),
            rule: _rule(),
            ruleType: 'double',
            previousApplication: applied.id,
            previousSequence: 1,
            previousFailures: 0,
            previousCursor: 1,
            reconciledAt: instant(2),
            acknowledgedKinds: const ['slotTarget'],
          ),
        );
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'native and logical v52 archives carry receipts while older labels reject them',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-reconcile-port-',
      );
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      TrainingArchive? archived;
      try {
        final service = StoredTrainingService(store);
        final progression = StoredProgressionService(store);
        await service.publish(definition(), 0);
        await _acceptedTrack(store, progression);
        final drifted = copyJson(definition().toJson());
        _slotTargets(drifted)['reps'] = {'value': '10', 'unit': 'rep'};
        await service.publish(WorkoutDefinition.fromJson(drifted), 1);
        await progression.reconcile(
          id: 'portable-reanchor',
          templateId: _template,
          revision: 2,
          slotId: _slot,
          expectedSequence: 1,
          kinds: ['slotTarget'],
          reconciledAt: instant(2),
          confirm: true,
        );
        final started = await service.start('after', _template, 2, instant(2));
        final finished = await _finish(service, started);
        final pending = await progression.propose(finished.id, _slot, _rule());
        await progression.accept(
          finished.id,
          _slot,
          pending.version,
          instant(3),
        );
        archived = await store.archive();
        equal(
          (await store.backup('${dir.path}/native'))['databaseSchemaVersion'],
          58,
        );
        await LogicalArchiveFiles.export(archived, '${dir.path}/full.json');
        await LogicalArchiveFiles.export(archived, '${dir.path}/bare.json');
      } finally {
        await store.close();
      }
      final before = canonicalJson(archived.toJson());
      equal(
        NativeBackup.validateDatabase('${dir.path}/native/database.sqlite'),
        58,
      );
      final full = await LogicalArchiveFiles.prepare('${dir.path}/full.json');
      try {
        equal(canonicalJson(full.archive.toJson()), before);
        check(
          full.archive.reconciliations.any(
            (receipt) => receipt.id == 'portable-reanchor',
          ),
          'the receipt survives the logical round trip',
        );
      } finally {
        await full.close();
      }
      check(
        (await _relabelRejects(
          '${dir.path}/full.json',
          51,
          keep: true,
        )).contains('Unknown fields'),
        'receipts need the new label',
      );
      check(
        (await _relabelRejects(
          '${dir.path}/bare.json',
          52,
          keep: false,
        )).contains('requires progression reconciliations'),
        'the new label names its section',
      );
      check(
        (await _relabelRejects(
          '${dir.path}/bare.json',
          51,
          keep: false,
        )).contains('base application'),
        'an anchored decision cannot cross to an older label',
      );
      File('${dir.path}/labeled.sqlite').writeAsBytesSync(
        File('${dir.path}/native/database.sqlite').readAsBytesSync(),
      );
      final labeled = sqlite3.open('${dir.path}/labeled.sqlite');
      labeled.userVersion = 51;
      labeled.close();
      check(
        _nativeError(
          '${dir.path}/labeled.sqlite',
        ).contains('does not match supported schema v51'),
        'a v52 profile cannot claim the older schema label',
      );
      File('${dir.path}/dropped.sqlite').writeAsBytesSync(
        File('${dir.path}/native/database.sqlite').readAsBytesSync(),
      );
      final dropped = sqlite3.open('${dir.path}/dropped.sqlite');
      dropped.execute('DROP TABLE progression_reconciliations');
      dropped.execute('DROP TABLE IF EXISTS lever_link_revisions');
      dropped.execute('DROP TABLE IF EXISTS shared_lever_applications');
      dropped.execute('DROP TABLE IF EXISTS link_retirement_anchors');
      dropped.execute('DROP TABLE IF EXISTS program_upgrade_receipts');
      dropped.execute('DROP TABLE IF EXISTS exercise_revisions');
      dropped.execute('DROP TABLE IF EXISTS implementation_revisions');
      dropped.userVersion = 51;
      dropped.close();
      check(
        _nativeError('${dir.path}/dropped.sqlite').contains('base application'),
        'a forged v51 profile loses the receipt its decision referenced',
      );
      final reopened = await TrainingStore.open(
        '${dir.path}/native/database.sqlite',
      );
      try {
        equal(canonicalJson((await reopened.archive()).toJson()), before);
        equal(
          (await StoredProgressionService(reopened).reconciliations()).length,
          1,
        );
      } finally {
        await reopened.close();
      }
      await dir.delete(recursive: true);
    },
  );

  test(
    'the CLI records one reconciliation and then starts the drifted revision',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-reconcile-act-cli-',
      );
      final path = '${dir.path}/db.sqlite';
      final store = await TrainingStore.open(path);
      try {
        final service = StoredTrainingService(store);
        await service.publish(definition(), 0);
        await _acceptedTrack(store, StoredProgressionService(store));
        final drifted = copyJson(definition().toJson());
        _slotTargets(drifted)['reps'] = {'value': '10', 'unit': 'rep'};
        await service.publish(WorkoutDefinition.fromJson(drifted), 1);
      } finally {
        await store.close();
      }
      Future<({int code, String output, String error})> command(
        Map<String, Object?> input,
      ) => invoke(
        ['progression', 'reconcile'],
        jsonEncode({
          'schemaVersion': 1,
          'database': path,
          'id': 'cli-reanchor',
          'templateId': _template,
          'revision': 2,
          'slotId': _slot,
          'expectedSequence': 1,
          'kinds': ['slotTarget'],
          'reconciledAt': '2026-10-02T12:00:00Z',
          ...input,
        }),
      );
      equal((await command({})).code, 2);
      equal((await command({'confirm': true, 'kinds': null})).code, 2);
      equal((await command({'confirm': true, 'id': ''})).code, 2);
      final first = await command({'confirm': true});
      equal(first.code, 0);
      final data = jsonObject(
        jsonObject(jsonDecode(first.output), 'response')['data'],
        'data',
      );
      equal(data['applied'], true);
      equal(data['status'], 'reconciled');
      equal(data['sequence'], 2);
      equal(data['previousApplication'], 'accepted/bench-heavy');
      jsonEqual(data['acknowledgedKinds'], ['slotTarget']);
      jsonEqual(
        _values(
          jsonObject(data['resolvedState'], 'resolvedState')['nextSets'],
          'reps',
        ),
        ['10', '10', '10'],
      );
      equal((await command({'confirm': true})).output, first.output);
      equal(
        (await command({'confirm': true, 'expectedSequence': 9})).output,
        first.output,
      );
      equal((await command({'confirm': true, 'resetFailures': true})).code, 5);
      equal(
        (await command({
          'confirm': true,
          'id': 'other-cli-act',
          'expectedSequence': 9,
        })).code,
        5,
      );
      equal((await command({'confirm': true, 'revision': 1})).code, 5);
      final shown = await invoke(
        ['progression', 'reconcile-show'],
        jsonEncode({
          'schemaVersion': 1,
          'database': path,
          'id': 'cli-reanchor',
        }),
      );
      equal(shown.code, 0);
      equal(shown.output, first.output);
      equal(
        (await invoke(
          ['progression', 'reconcile-show'],
          jsonEncode({'schemaVersion': 1, 'database': path, 'id': 'missing'}),
        )).code,
        3,
      );
      final listed = await invoke([
        'progression',
        'reconcile-list',
      ], jsonEncode({'schemaVersion': 1, 'database': path}));
      equal(listed.code, 0);
      final listedData = jsonObject(
        jsonObject(jsonDecode(listed.output), 'response')['data'],
        'data',
      );
      final rows = jsonList(listedData, 'reconciliations');
      equal(rows.length, 1);
      equal(jsonObject(rows.first, 'receipt')['id'], 'cli-reanchor');
      final started = await invoke(
        ['store', 'start'],
        jsonEncode({
          'schemaVersion': 1,
          'database': path,
          'id': 'cli-after',
          'templateId': _template,
          'revision': 2,
          'startedAt': '2026-10-02T12:00:00Z',
        }),
      );
      equal(started.code, 0);
      final startedData = jsonObject(
        jsonObject(jsonDecode(started.output), 'response')['data'],
        'data',
      );
      jsonEqual(_suggested(startedData['sets'], 'reps'), [
        '10',
        '10',
        '10',
        '12',
      ]);
      await dir.delete(recursive: true);
    },
  );
}
