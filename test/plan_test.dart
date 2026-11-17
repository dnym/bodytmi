import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'cli_test.dart';
import 'fixtures.dart';
import 'support.dart';

Map<String, Object?> _q(String value, String unit) => {
  'value': value,
  'unit': unit,
};

Future<BodyTmiException> _failure(Future<Object?> Function() action) async {
  try {
    await action();
  } on BodyTmiException catch (error) {
    return error;
  }
  throw StateError('Expected a BodyTmiException.');
}

Future<void> _body(TrainingStore store) async {
  final body = BodyService(store);
  await body.setProfile(
    Profile.fromJson({
      'sex': 'male',
      'birthDate': '1990-01-01',
      'stepLength': _q('75', 'cm'),
    }),
    0,
  );
  final observations = ObservationService(store);
  await observations.save({
    'id': 'mass',
    'measure': 'body-mass',
    'value': _q('90', 'kg'),
    'observedAt': '2026-11-01T07:00:00+01:00',
    'attributes': {'context': 'health'},
  }, 0);
  await observations.save({
    'id': 'dexa',
    'measure': 'body-fat',
    'value': _q('20', 'percent'),
    'date': '2026-11-01',
    'attributes': {'method': 'dexa'},
  }, 0);
  await body.selectSource(
    '2026-01-01',
    BodyFatSource.fromJson({'kind': 'series', 'method': 'dexa'}),
    0,
  );
  await EnergyService(store).selectMethod(
    '2026-01-01',
    MaintenanceMethod.fromJson({
      'formula': 'mcdonald-rfl-maintenance',
      'activity': 'moderate',
      'calPerLb': '13',
    }),
    0,
  );
}

Future<void> _trainingRuns(TrainingStore store) async {
  await StoredTrainingService(store).publish(definition(), 0);
  final programs = ProgramService(store);
  await programs.publish(
    ProgramDefinition.fromJson({
      'id': 'strength',
      'name': 'Strength',
      'plan': {
        'id': 'cycle',
        'type': 'group',
        'label': 'Cycle',
        'children': [
          {
            'id': 'a',
            'type': 'day',
            'label': 'A',
            'templateId': 'upper-a',
            'revision': 1,
          },
        ],
      },
    }),
    0,
  );
  for (final id in ['lift', 'other']) {
    await programs.create(
      id,
      'strength',
      1,
      DateTime.utc(2026, 10, 1),
      loop: true,
    );
  }
}

const _asOf = '2026-11-01T20:00:00+01:00';
const _erfl = {
  'walking': {'steps': 40000},
  'afterDays': 3,
};

void planTests() {
  test('ERFL plan with companions, then ending it undoes them', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-plan-');
    final store = await TrainingStore.open('${dir.path}/db.sqlite');
    try {
      await _body(store);
      await _trainingRuns(store);
      final plans = PlanService(store);
      await plans.setStepGoal('2026-01-01', 8000, 0);

      final preview = await plans.preview(
        programme: 'erfl',
        choices: _erfl,
        startDate: '2026-11-02',
        asOfText: _asOf,
      );
      final offers = (preview['companions']! as List)
          .cast<Map<String, Object?>>();
      final steps = offers.firstWhere((o) => o['kind'] == 'steps');
      jsonEqual(steps['replaces'], {'steps': 8000, 'revision': 1});
      jsonEqual(
        [
          for (final o in offers)
            if (o['kind'] == 'pauseRun') o['runId'],
        ],
        ['lift', 'other'],
      );
      // Nothing changed by previewing.
      equal((await ProgramService(store).run('lift')).status, 'active');

      // Only named companions apply: pause one of the two runs.
      rejects2() async => _failure(
        () => plans.activate(
          planId: 'erfl',
          programme: 'erfl',
          choices: _erfl,
          startDate: '2026-11-02',
          asOfText: _asOf,
          requestId: 'r1',
          pauseRuns: ['nope'],
        ),
      );
      equal((await rejects2()).code, 'validation');
      final plan = await plans.activate(
        planId: 'erfl',
        programme: 'erfl',
        choices: _erfl,
        startDate: '2026-11-02',
        asOfText: _asOf,
        requestId: 'r1',
        steps: true,
        pauseRuns: ['lift'],
      );
      equal(plan.status, 'active');
      equal((await ProgramService(store).run('lift')).status, 'paused');
      equal((await ProgramService(store).run('other')).status, 'active');
      // Retry returns the same plan without pausing again.
      equal(
        (await plans.activate(
          planId: 'erfl',
          programme: 'erfl',
          choices: _erfl,
          startDate: '2026-11-02',
          asOfText: _asOf,
          requestId: 'r1',
          steps: true,
          pauseRuns: ['lift'],
        )).contentVersion,
        1,
      );

      // Step goals: the walking goal for 4 days, then 10,000; standalone
      // before the plan.
      Future<Object?> stepsOn(String date) async =>
          (await plans.stepGoalOnDate(date))['steps'];
      equal(await stepsOn('2026-11-01'), 8000);
      equal(await stepsOn('2026-11-02'), 40000);
      equal(await stepsOn('2026-11-05'), 40000);
      equal(await stepsOn('2026-11-06'), 10000);
      equal((await plans.stepGoalOnDate('2026-11-06'))['source'], 'plan');
      // The finite cycle ends after 4 + 3 days: standalone again.
      equal(await stepsOn('2026-11-09'), 8000);

      // A second plan cannot start while this one is open.
      equal(
        (await _failure(
          () => plans.activate(
            planId: 'normal',
            programme: 'normal',
            startDate: '2026-11-10',
            asOfText: _asOf,
            requestId: 'r2',
          ),
        )).code,
        'conflict',
      );

      // You resumed and paused "lift" yourself: ending leaves it alone.
      final runs = ProgramService(store);
      var lift = await runs.run('lift');
      lift = await runs.status('lift', lift.contentVersion, 'active');
      await runs.status('lift', lift.contentVersion, 'paused');
      final ended = await plans.end(
        'erfl',
        '2026-11-09',
        1,
        resumeRuns: ['lift'],
        confirm: true,
      );
      equal(ended.status, 'ended');
      final undone = jsonObject(ended.json['undone'], 'undone');
      jsonEqual(undone['resumed'], []);
      equal((undone['leftAlone']! as List).length, 1);
      equal((await runs.run('lift')).status, 'paused');
      // History keeps the plan's goals; after its end the standalone one.
      equal(await stepsOn('2026-11-06'), 10000);
      equal(await stepsOn('2026-11-09'), 8000);

      // A normal plan from your own day after; resuming works when unchanged.
      final normal = await plans.activate(
        planId: 'normal',
        programme: 'normal',
        startDate: '2026-11-10',
        asOfText: _asOf,
        requestId: 'r2',
      );
      equal(normal.json['programme'] is Map, true);
      final normalPreview = await plans.preview(
        programme: 'rfl',
        choices: const {},
        startDate: '2026-11-10',
        asOfText: _asOf,
      );
      // The RFL guide needs choices; preview still lists no actions.
      equal(jsonObject(normalPreview['guide'], 'g')['status'], 'unavailable');

      final json = (await store.archive()).toJson();
      TrainingArchive.fromJson(json);
      final forged = jsonDecode(jsonEncode(json)) as Map<String, Object?>;
      final row = (forged['dietRecords']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere((r) => r['kind'] == 'body-plan' && r['id'] == 'erfl');
      (row['snapshot']! as Map)['endDate'] = '2026-11-08';
      rejects(() => TrainingArchive.fromJson(forged));
      final backup = '${dir.path}/backup';
      await store.backup(backup);
      NativeBackup.validateDatabase('$backup/database.sqlite');
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });

  test('ending a plan resumes runs it paused when unchanged', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-plan-2-');
    final store = await TrainingStore.open('${dir.path}/db.sqlite');
    try {
      await _body(store);
      await _trainingRuns(store);
      final plans = PlanService(store);
      await plans.activate(
        planId: 'erfl',
        programme: 'erfl',
        choices: _erfl,
        startDate: '2026-11-02',
        asOfText: _asOf,
        requestId: 'r1',
        pauseRuns: ['lift', 'other'],
      );
      equal(
        (await _failure(
          () => plans.end('erfl', '2026-11-09', 1, confirm: false),
        )).code,
        'validation',
      );
      final ended = await plans.end(
        'erfl',
        '2026-11-09',
        1,
        resumeRuns: ['lift'],
        confirm: true,
      );
      jsonEqual(jsonObject(ended.json['undone'], 'u')['resumed'], ['lift']);
      equal((await ProgramService(store).run('lift')).status, 'active');
      // Only the runs you name are resumed.
      equal((await ProgramService(store).run('other')).status, 'paused');
      // Without steps the plan never touched the step goal.
      equal((await plans.stepGoalOnDate('2026-11-02'))['source'], 'none');
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });

  test('CLI plan preview, activate, end and step goals', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-plan-cli-');
    final db = '${dir.path}/db.sqlite';
    final store = await TrainingStore.open(db);
    await _body(store);
    await store.close();
    Future<({int code, Object? data, String error})> cli(
      String name,
      Map<String, Object?> fields,
    ) async {
      final r = await invoke(
        name.split(' '),
        jsonEncode({'schemaVersion': 1, 'database': db, ...fields}),
      );
      return (
        code: r.code,
        data: r.code == 0
            ? jsonObject(jsonDecode(r.output), 'r')['data']
            : null,
        error: r.error,
      );
    }

    try {
      check(
        (await cli('stepgoal set', {
              'from': '2026-10-01',
              'steps': 7000,
              'expectedRevision': 0,
            })).code ==
            0,
      );
      final preview = await cli('plan preview', {
        'programme': 'imf',
        'choices': {
          'activity': 'weights',
          'pattern': '5:2',
          'arrangement': 'MMMMMRR',
          'fatPerLb': '0.38',
        },
        'startDate': '2026-11-02',
        'asOf': _asOf,
      });
      check(preview.code == 0, preview.error);
      equal((jsonObject(preview.data, 'p')['companions']! as List).length, 0);
      final activated = await cli('plan activate', {
        'planId': 'imf',
        'programme': 'imf',
        'choices': {
          'activity': 'weights',
          'pattern': '5:2',
          'arrangement': 'MMMMMRR',
          'fatPerLb': '0.38',
        },
        'startDate': '2026-11-02',
        'asOf': _asOf,
        'requestId': 'go',
        'companions': {'steps': true},
      });
      equal(activated.code, 2);
      final ok = await cli('plan activate', {
        'planId': 'imf',
        'programme': 'imf',
        'choices': {
          'activity': 'weights',
          'pattern': '5:2',
          'arrangement': 'MMMMMRR',
          'fatPerLb': '0.38',
        },
        'startDate': '2026-11-02',
        'asOf': _asOf,
        'requestId': 'go',
      });
      check(ok.code == 0, ok.error);
      final schedule = await cli('diet schedule', {
        'from': '2026-11-02',
        'days': 7,
      });
      equal(
        jsonObject(
              (jsonObject(schedule.data, 's')['days']! as List).last,
              'd',
            )['dayType']
            is Map,
        true,
      );
      equal(((await cli('plan list', {})).data! as List).length, 1);
      final ended = await cli('plan end', {
        'planId': 'imf',
        'date': '2026-12-01',
        'expectedVersion': 1,
        'confirm': true,
      });
      check(ended.code == 0, ended.error);
      equal(
        jsonObject(
          (await cli('stepgoal show', {'date': '2026-11-10'})).data,
          's',
        )['steps'],
        7000,
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
