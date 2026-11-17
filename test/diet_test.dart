import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'cli_test.dart';
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

Object? _goal(Map<String, Object?> goals, String name) {
  final g = jsonObject(goals[name], name);
  return g['status'] == 'resolved'
      ? jsonObject(g['value'], 'value')['value']
      : g['status'];
}

/// IMF ch. 15–16, Joe: 200 lb, 22 % (156 lb LBM), category 2, aerobic.
const _maintenanceDay = {
  'id': 'imf-maintenance',
  'name': 'Maintenance day',
  'notes': 'Hard training belongs on maintenance days.',
  'goals': {
    'energy': {'basis': 'maintenance'},
    'protein': {'basis': 'fat-free-mass', 'perLb': '0.9'},
    'fat': {'basis': 'mass', 'perLb': '0.38'},
    'carbohydrate': {'remainder': true},
  },
};
const _rflDay = {
  'id': 'imf-rfl',
  'name': 'RFL day',
  'goals': {
    'energy': {'sum': true},
    'protein': {'basis': 'fat-free-mass', 'perLb': '0.9'},
    'carbohydrate': {
      'fixed': {'value': '20', 'unit': 'g'},
    },
    'fat': {
      'fixed': {'value': '20', 'unit': 'g'},
    },
  },
};

Map<String, Object?> _day(String id) => {
  'type': 'day',
  'dayType': {'id': id, 'revision': 1},
};

void dietTests() {
  test('day type goals and cycle structure', () {
    final joe = (
      maintenanceKcal: 3400.0,
      massKg: 200 * kgPerLb,
      fatFreeMassKg: 156 * kgPerLb,
    );
    // Book: 140 P / 541 C / 75 F (rounded); exactly 140.4 / 538.6 / 76.
    final m = DayType.fromJson(_maintenanceDay).resolve(joe);
    equal(_goal(m, 'energy'), '3400');
    equal(_goal(m, 'protein'), '140.4');
    equal(_goal(m, 'fat'), '76');
    equal(_goal(m, 'carbohydrate'), '538.6');
    final rfl = DayType.fromJson(_rflDay).resolve(joe);
    equal(_goal(rfl, 'energy'), '821.6');
    // Normal: maintenance − 500 kcal, 1.8 g/kg body mass; a quarter of
    // maintenance; a range.
    final normal = DayType.fromJson({
      'id': 'normal',
      'name': 'Deficit day',
      'goals': {
        'energy': {'basis': 'maintenance', 'subtract': _q('500', 'kcal')},
        'protein': {'basis': 'mass', 'perKg': '1.8'},
        'fibre': {'minimum': _q('25', 'g'), 'maximum': _q('35', 'g')},
      },
      'steps': 10000,
    }).resolve((maintenanceKcal: 2500.0, massKg: 80.0, fatFreeMassKg: null));
    equal(_goal(normal, 'energy'), '2000');
    equal(_goal(normal, 'protein'), '144');
    equal(
      jsonObject(jsonObject(normal['fibre'], 'f')['minimum'], 'm')['value'],
      '25',
    );
    equal(
      _goal(
        DayType.fromJson(
          {
            'id': 'quarter',
            'name': 'Quarter',
            'goals': {
              'energy': {'basis': 'maintenance', 'factor': '0.25'},
            },
          },
        ).resolve((maintenanceKcal: 2000.0, massKg: null, fatFreeMassKg: null)),
        'energy',
      ),
      '500',
    );
    // Missing inputs and impossible remainders are unavailable.
    final missing = DayType.fromJson(
      _maintenanceDay,
    ).resolve((maintenanceKcal: null, massKg: 90.0, fatFreeMassKg: 70.0));
    equal(_goal(missing, 'energy'), 'unavailable');
    equal(_goal(missing, 'carbohydrate'), 'unavailable');
    final tight = DayType.fromJson(
      _maintenanceDay,
    ).resolve((maintenanceKcal: 900.0, massKg: 90.0, fatFreeMassKg: 70.0));
    equal(_goal(tight, 'carbohydrate'), 'unavailable');

    Map<String, Object?> withGoals(Map<String, Object?> goals) => {
      'id': 'x',
      'name': 'X',
      'goals': goals,
    };
    rejects(
      () => DayType.fromJson(
        withGoals({
          'energy': {'basis': 'maintenance'},
          'protein': {'fixed': _q('100', 'g')},
          'fat': {'remainder': true},
          'carbohydrate': {'remainder': true},
        }),
      ),
    );
    rejects(
      () => DayType.fromJson(
        withGoals({
          'protein': {'fixed': _q('100', 'g')},
          'carbohydrate': {'remainder': true},
        }),
      ),
    );
    rejects(
      () => DayType.fromJson(
        withGoals({
          'protein': {'basis': 'maintenance'},
        }),
      ),
    );
    rejects(
      () => DayType.fromJson(
        withGoals({
          'energy': {'fixed': _q('100', 'g')},
        }),
      ),
    );
    rejects(
      () => DayType.fromJson(
        withGoals({
          'protein': {'basis': 'mass', 'perLb': '1', 'perKg': '2'},
        }),
      ),
    );

    // IMF 1:13: 13 RFL days then one maintenance day, looping.
    final cycle = DietCycle.fromJson({
      'id': 'imf-1-13',
      'name': 'IMF 1:13',
      'loop': true,
      'days': [
        {
          'type': 'repeat',
          'count': 13,
          'label': 'RFL',
          'days': [_day('imf-rfl')],
        },
        _day('imf-maintenance'),
      ],
    });
    equal(cycle.days.length, 14);
    equal(cycle.days.last.dayType.id, 'imf-maintenance');
    jsonEqual(cycle.days[12].path, ['RFL 13/13']);
    equal(cycle.dayTypes.length, 2);
    rejects(
      () => DietCycle.fromJson({
        'id': 'big',
        'name': 'Big',
        'loop': false,
        'days': [
          {
            'type': 'repeat',
            'count': 3661,
            'days': [_day('imf-rfl')],
          },
        ],
      }),
    );
  });

  test('stored diet runs follow the calendar', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-diet-');
    final store = await TrainingStore.open('${dir.path}/db.sqlite');
    try {
      final diets = DietService(store);
      final body = BodyService(store);
      final observations = ObservationService(store);
      await body.setProfile(Profile.fromJson({'sex': 'male'}), 0);
      await observations.save({
        'id': 'mass',
        'measure': 'body-mass',
        'value': _q('200', 'lb'),
        'observedAt': '2026-11-01T07:00:00+01:00',
        'attributes': {'context': 'health'},
      }, 0);
      await observations.save({
        'id': 'dexa',
        'measure': 'body-fat',
        'value': _q('22', 'percent'),
        'date': '2026-11-01',
        'attributes': {'method': 'dexa'},
      }, 0);
      await body.selectSource(
        '2026-01-01',
        BodyFatSource.fromJson({'kind': 'series', 'method': 'dexa'}),
        0,
      );
      await diets.publishDayType(DayType.fromJson(_maintenanceDay), 0);
      await diets.publishDayType(DayType.fromJson(_rflDay), 0);
      equal(
        (await diets.publishDayType(DayType.fromJson(_rflDay), 1)).number,
        1,
      );
      equal(
        (await _failure(
          () => diets.publishCycle(
            DietCycle.fromJson({
              'id': 'bad',
              'name': 'Bad',
              'loop': true,
              'days': [_day('nope')],
            }),
            0,
          ),
        )).code,
        'not_found',
      );
      // IMF 4:3 non-ADF: M M RFL M M RFL RFL, starting on a Monday.
      await diets.publishCycle(
        DietCycle.fromJson({
          'id': 'imf-4-3',
          'name': 'IMF 4:3',
          'loop': true,
          'days': [
            for (final d in ['M', 'M', 'R', 'M', 'M', 'R', 'R'])
              _day(d == 'M' ? 'imf-maintenance' : 'imf-rfl'),
          ],
        }),
        0,
      );
      // Without a maintenance method the maintenance day cannot resolve.
      final refused = await _failure(
        () => diets.start(
          runId: 'cut',
          cycleId: 'imf-4-3',
          cycleRevision: 1,
          startDate: '2026-11-02',
          asOfText: '2026-11-01T20:00:00+01:00',
          requestId: 'r1',
        ),
      );
      check(refused.message.contains('imf-maintenance/1'), refused.message);
      await EnergyService(store).selectMethod(
        '2026-01-01',
        MaintenanceMethod.fromJson({
          'formula': 'manual',
          'energy': _q('3400', 'kcal'),
        }),
        0,
      );
      Future<DietRun> start() => diets.start(
        runId: 'cut',
        cycleId: 'imf-4-3',
        cycleRevision: 1,
        startDate: '2026-11-02',
        asOfText: '2026-11-01T20:00:00+01:00',
        requestId: 'r1',
      );
      final run = await start();
      equal(
        canonicalJson((await start()).toJson()),
        canonicalJson(run.toJson()),
      );
      final frozen = jsonObject(run.targets['imf-maintenance/1'], 'm');
      equal(_goal(frozen, 'carbohydrate'), '538.6');

      // A later weigh-in never changes the frozen targets.
      await observations.save({
        'id': 'mass2',
        'measure': 'body-mass',
        'value': _q('150', 'lb'),
        'observedAt': '2026-11-03T07:00:00+01:00',
        'attributes': {'context': 'health'},
      }, 0);

      List<String> week(Map<String, Object?> schedule) => [
        for (final d
            in (schedule['days']! as List).cast<Map<String, Object?>>())
          d['dayType'] == null
              ? '-'
              : jsonObject(d['dayType'], 'd')['id'] == 'imf-rfl'
              ? 'R'
              : 'M',
      ];
      var schedule = await diets.schedule('2026-11-01', 15);
      equal(week(schedule).join(), '-MMRMMRRMMRMMRR');
      final monday = jsonObject((schedule['days']! as List)[1], 'd');
      equal(monday['source'], 'cycle');
      equal(monday['cycleDay'], 1);
      equal(_goal(jsonObject(monday['goals'], 'g'), 'protein'), '140.4');

      // Thursday's maintenance day moves to Saturday; week two unchanged.
      final moved = await diets.move(
        'cut',
        '2026-11-05',
        '2026-11-07',
        'Dinner out on Saturday',
        1,
      );
      equal(moved.contentVersion, 2);
      schedule = await diets.schedule('2026-11-02', 14);
      equal(week(schedule).join(), 'MMRRMMRMMRMMRR');
      final saturday = jsonObject((schedule['days']! as List)[5], 'd');
      equal(saturday['source'], 'override');
      equal(saturday['reason'], 'Dinner out on Saturday');
      equal(
        (await _failure(
          () => diets.move('cut', '2026-11-05', '2026-11-07', 'x', 1),
        )).code,
        'conflict',
      );
      // Remove one override: the date returns to its cycle day type.
      await diets.override('cut', '2026-11-05', null, 'undo', 2);
      schedule = await diets.schedule('2026-11-02', 7);
      equal(week(schedule).join(), 'MMRMMMR');

      // One run at a time.
      equal(
        (await _failure(
          () => diets.start(
            runId: 'other',
            cycleId: 'imf-4-3',
            cycleRevision: 1,
            startDate: '2026-12-01',
            asOfText: '2026-11-30T20:00:00+01:00',
            requestId: 'r2',
          ),
        )).code,
        'conflict',
      );
      equal(
        (await _failure(
          () => diets.end('cut', '2026-11-20', 3, confirm: false),
        )).code,
        'validation',
      );
      equal(
        (await _failure(
          () => diets.end('cut', '2026-11-03', 3, confirm: true),
        )).code,
        'validation',
      );
      await diets.override('cut', '2026-11-07', null, 'undo', 3);
      final ended = await diets.end('cut', '2026-11-20', 4, confirm: true);
      equal(ended.endDate, '2026-11-20');
      final second = await diets.start(
        runId: 'other',
        cycleId: 'imf-4-3',
        cycleRevision: 1,
        startDate: '2026-11-20',
        asOfText: '2026-11-19T20:00:00+01:00',
        requestId: 'r2',
      );
      // The new run froze the later weigh-in: lower targets.
      equal(
        _goal(jsonObject(second.targets['imf-maintenance/1'], 'g'), 'fat'),
        '57',
      );
      schedule = await diets.schedule('2026-11-18', 4);
      jsonEqual(
        [
          for (final d
              in (schedule['days']! as List).cast<Map<String, Object?>>())
            d['run'],
        ],
        ['cut', 'cut', 'other', 'other'],
      );

      // Archives validate cross references and frozen targets.
      final json = (await store.archive()).toJson();
      TrainingArchive.fromJson(json);
      final forged = jsonDecode(jsonEncode(json)) as Map<String, Object?>;
      final row = (forged['dietRecords']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere((r) => r['kind'] == 'diet-run' && r['id'] == 'other');
      ((((row['snapshot'] as Map)['targets'] as Map)['imf-maintenance/1']
              as Map)['fat']
          as Map)['value'] = {
        'value': '58',
        'unit': 'g',
      };
      rejects(() => TrainingArchive.fromJson(forged));
      final backup = '${dir.path}/backup';
      await store.backup(backup);
      NativeBackup.validateDatabase('$backup/database.sqlite');
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });

  test('CLI day types, cycles and diet schedule', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-diet-cli-');
    final db = '${dir.path}/db.sqlite';
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
      final fixed = {
        'id': 'fixed',
        'name': 'Fixed day',
        'goals': {
          'energy': {'fixed': _q('2000', 'kcal')},
          'protein': {'fixed': _q('150', 'g')},
          'fat': {'fixed': _q('60', 'g')},
          'carbohydrate': {'remainder': true},
        },
        'steps': 10000,
      };
      check(
        (await cli('daytype publish', {
              'dayType': fixed,
              'expectedRevision': 0,
            })).code ==
            0,
      );
      final preview = await cli('daytype resolve', {
        'dayTypeId': 'fixed',
        'asOf': '2026-11-16T12:00:00+01:00',
      });
      check(preview.code == 0, preview.error);
      equal(
        _goal(
          jsonObject(jsonObject(preview.data, 'p')['goals'], 'g'),
          'carbohydrate',
        ),
        '215',
      );
      check(
        (await cli('cycle publish', {
              'cycle': {
                'id': 'flat',
                'name': 'Flat',
                'loop': false,
                'days': [
                  {
                    'type': 'repeat',
                    'count': 2,
                    'days': [_day('fixed')],
                  },
                ],
              },
              'expectedRevision': 0,
            })).code ==
            0,
      );
      final started = await cli('diet start', {
        'runId': 'run1',
        'cycleId': 'flat',
        'cycleRevision': 1,
        'startDate': '2026-11-16',
        'asOf': '2026-11-16T08:00:00+01:00',
        'requestId': 'req1',
      });
      check(started.code == 0, started.error);
      final schedule = await cli('diet schedule', {
        'from': '2026-11-16',
        'days': 3,
      });
      final days = (jsonObject(schedule.data, 's')['days']! as List)
          .cast<Map<String, Object?>>();
      equal(days[1]['steps'], 10000);
      equal(days[2]['dayType'], null);
      equal(
        (await cli('diet override', {
          'runId': 'run1',
          'date': '2026-11-16',
          'dayType': {'id': 'missing', 'revision': 1},
          'reason': 'x',
          'expectedVersion': 1,
        })).code,
        3,
      );
      equal(
        (await cli('diet end', {
          'runId': 'run1',
          'date': '2026-11-18',
          'expectedVersion': 1,
        })).code,
        2,
      );
      equal(((await cli('diet list', {})).data! as List).length, 1);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
