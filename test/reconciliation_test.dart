import 'dart:convert';
import 'dart:io';

import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
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
}) async {
  final started = await service.start(id, _template, revision, instant(day));
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

Future<void> _acceptedTrack(
  TrainingStore store,
  StoredProgressionService progression,
) async {
  final session = await _logged(StoredTrainingService(store), 'accepted', 1);
  final pending = await progression.propose(session.id, _slot, _rule());
  await progression.accept(
    session.id,
    _slot,
    pending.version,
    instant(1).add(const Duration(hours: 2)),
  );
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
}
