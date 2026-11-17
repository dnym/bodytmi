import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'cli_test.dart';
import 'support.dart';

Map<String, Object?> _q(String value, String unit) => {
  'value': value,
  'unit': unit,
};

double _n(Object? value) =>
    double.parse(value is Map ? value['value']! as String : value! as String);

Map<String, Object?> _dayType(Map<String, Object?> guide, String id) =>
    (guide['dayTypes']! as List).cast<Map<String, Object?>>().firstWhere(
      (d) => d['id'] == id,
    );

Object? _goal(Map<String, Object?> day, String name) => jsonObject(
  jsonObject(jsonObject(day['goals'], 'g')[name], name)['value'],
  'v',
)['value'];

/// IMF ch. 14–16 Joe: 200 lb male, 22 % body fat (category 2), moderate
/// activity plus two hours of medium aerobic work.
Future<void> _joe(TrainingStore store, {bool stepLength = false}) async {
  final body = BodyService(store);
  await body.setProfile(
    Profile.fromJson({
      'sex': 'male',
      'birthDate': '1990-01-01',
      if (stepLength) 'stepLength': _q('75', 'cm'),
    }),
    0,
  );
  final observations = ObservationService(store);
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
  await EnergyService(store).selectMethod(
    '2026-01-01',
    MaintenanceMethod.fromJson({
      'formula': 'mcdonald-imf-tdee',
      'activity': 'moderate',
      'exercise': [
        {'kind': 'medium-aerobic', 'hours': '2'},
      ],
    }),
    0,
  );
}

const _asOf = '2026-11-01T20:00:00+01:00';
const _imf = {
  'activity': 'aerobic',
  'pattern': '4:3',
  'arrangement': 'MMRMMRR',
  'fatPerLb': '0.38',
};

void programmeTests() {
  test('energy-balance simulation keeps the Forbes curve and energy', () {
    // 100 kg with 30 kg fat; 1,000 kcal/day deficit for 180 days.
    final sim = simulateEnergyBalance(
      startDate: '2026-01-01',
      days: 180,
      massKg: 100,
      fatFreeMassKg: 70,
      intake: (_, _) => 1500,
      expenditure: (_, _, _) => 2500,
    );
    equal(sim['status'], 'resolved');
    equal(sim['estimate'], true);
    final change = jsonObject(sim['change'], 'c');
    final fat = _n(change['fatMass']), lean = _n(change['fatFreeMass']);
    // Along the Forbes curve ΔL = 10.4 ln(F1 / F0).
    check(
      (lean - 10.4 * math.log((30 + fat) / 30)).abs() < 0.01,
      'lean $lean, fat $fat',
    );
    // Energy: ΔF·39.5 + ΔL·7.6 MJ equals the deficit.
    check(
      ((fat * 39.5 + lean * 7.6) + 180000 * 0.004184).abs() < 0.01,
      'energy',
    );
    // Hall 2008 (Int J Obes 32:573, eq. on p. 2), closed form with the
    // Lambert W function: ΔL/ΔBW = 1 + Fi/ΔBW − (10.4/ΔBW)
    // W{e^(ΔBW/10.4) Fi e^(Fi/10.4) / 10.4}. The simulated path matches it.
    double lambertW(double x) {
      var w = math.log(x + 1);
      for (var i = 0; i < 100; i++) {
        w -= (w * math.exp(w) - x) / (math.exp(w) * (w + 1));
      }
      return w;
    }

    final dBW = fat + lean;
    final hall =
        1 +
        30 / dBW -
        10.4 /
            dBW *
            lambertW(math.exp(dBW / 10.4) * 30 * math.exp(30 / 10.4) / 10.4);
    check((lean / dBW - hall).abs() < 1e-3, 'Hall share $hall');

    // The lean share grows as fat falls: leaner people lose more lean.
    final lean20 = simulateEnergyBalance(
      startDate: '2026-01-01',
      days: 60,
      massKg: 80,
      fatFreeMassKg: 70,
      intake: (_, _) => 1500,
      expenditure: (_, _, _) => 2500,
    );
    final c = jsonObject(lean20['change'], 'c');
    check(
      _n(c['fatFreeMass']) / _n(c['mass']) > lean / (lean + fat),
      'leaner share',
    );
    equal(
      simulateEnergyBalance(
        startDate: '2026-01-01',
        days: 3,
        massKg: 80,
        fatFreeMassKg: 60,
        intake: (day, _) => day == 1 ? null : 2000,
        expenditure: (_, _, _) => 2500,
      )['status'],
      'unavailable',
    );
    rejects(
      () => simulateEnergyBalance(
        startDate: '2026-01-01',
        days: 731,
        massKg: 80,
        fatFreeMassKg: 60,
        intake: (_, _) => 0,
        expenditure: (_, _, _) => 0,
      ),
    );
  });

  test('programme guides, comparison and apply', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-programme-');
    final store = await TrainingStore.open('${dir.path}/db.sqlite');
    try {
      final programmes = ProgrammeService(store);
      // No sex or body fat: the category, hence the guide, is unavailable.
      final early = await programmes.guide('imf', _imf, _asOf);
      equal(early['status'], 'unavailable');
      await _joe(store);

      // IMF 4:3: maintenance day 3,420 kcal; RFL day 140.4 g protein.
      final imf = await programmes.guide('imf', _imf, _asOf, simulateDays: 28);
      equal(imf['status'], 'resolved');
      equal(imf['category'], 2);
      final maintenance = _dayType(imf, 'imf-maintenance');
      equal(_goal(maintenance, 'energy'), '3420');
      equal(_goal(maintenance, 'protein'), '140.4');
      equal(_goal(maintenance, 'fat'), '76');
      final rfl = _dayType(imf, 'imf-rfl');
      equal(_goal(rfl, 'energy'), '821.6');
      // Three RFL days a week, each (3,420 − 821.6) kcal below
      // maintenance: 7,795.2 kcal ÷ 3,500 = 2.227… lb a week.
      final book = jsonObject(imf['bookEstimate'], 'b');
      check(
        (_n(book['fatPerWeek']) - 7795.2 / 3500).abs() < 1e-6,
        '${book['fatPerWeek']}',
      );
      final sim = jsonObject(imf['simulation'], 's');
      equal(sim['status'], 'resolved');
      check(_n(jsonObject(sim['change'], 'c')['fatMass']) < 0, 'fat falls');
      final points = (sim['points']! as List).cast<Map<String, Object?>>();
      equal(points.length, 29);
      equal(points[2]['intake'], '821.6');

      // RFL needs category-2 choices; the guide names them.
      final rflGuide = await programmes.guide('rfl', {}, _asOf);
      equal(rflGuide['status'], 'unavailable');
      jsonEqual(rflGuide['missingChoices'], [
        'activity',
        'breakActivity',
        'breakDays',
        'dietWeeks',
        'refeedCarbohydratePerLb',
      ]);
      final rflChoices = {
        'activity': 'aerobic',
        'breakActivity': 'moderate',
        'breakDays': 14,
        'dietWeeks': 4,
        'refeedCarbohydratePerLb': '1.5',
      };
      final full = await programmes.guide('rfl', rflChoices, _asOf);
      equal(full['status'], 'resolved');
      // Handbook category 2 aerobic: 1.1 g/lb of 156 lb fat-free mass.
      equal(_goal(_dayType(full, 'rfl-rfl'), 'protein'), '171.6');
      // Break: 1.0 g/lb protein, 100 g + 1.0 g/lb carbohydrate, fat the rest.
      final rest = _dayType(full, 'rfl-break');
      equal(_goal(rest, 'protein'), '156');
      equal(_goal(rest, 'carbohydrate'), '256');
      equal(jsonObject(full['cycle'], 'c')['length'], 42);
      rejects(
        () =>
            dietProgramme('rfl').build({...rflChoices, 'dietWeeks': 7}, 2, 'x'),
      );

      // ERFL by steps needs a step length; by distance it works.
      final erflSteps = await programmes.guide('erfl', {
        'walking': {'steps': 30000},
        'afterDays': 3,
      }, _asOf);
      equal(
        jsonObject(erflSteps['bookEstimate'], 'b')['status'],
        'unavailable',
      );
      final erfl = await programmes.guide(
        'erfl',
        {
          'walking': {'distanceKm': '20'},
          'afterDays': 3,
        },
        _asOf,
        simulateDays: 7,
      );
      // Category 2 aerobic-only column: 1.1 g/lb.
      equal(_goal(_dayType(erfl, 'erfl-day'), 'protein'), '171.6');
      equal(_dayType(erfl, 'erfl-after')['steps'], 10000);
      final erflBook = jsonObject(erfl['bookEstimate'], 'b');
      equal(erflBook['walkingKmPerDay'], '20');
      check(!erflBook.containsKey('fatPerWeek'), 'finite');

      // Normal: 500 below 3,420, 1.8 g/kg.
      final normal = await programmes.guide('normal', {}, _asOf);
      equal(_goal(_dayType(normal, 'normal-day'), 'energy'), '2920');
      final percent = await programmes.guide('normal', {
        'deficit': {'percent': '15'},
      }, _asOf);
      equal(_goal(_dayType(percent, 'normal-day'), 'energy'), '2907');

      // Side by side.
      final compared = await programmes.compare({
        'imf': _imf,
        'rfl': rflChoices,
      }, _asOf);
      jsonEqual(
        [
          for (final g
              in (compared['guides']! as List).cast<Map<String, Object?>>())
            g['status'],
        ],
        ['resolved', 'resolved', 'unavailable', 'resolved'],
      );

      // IMF warning with four full-volume training days.
      final warned = await programmes.guide('imf', {
        ..._imf,
        'pattern': '3:4',
        'arrangement': 'MRMRMRR',
        'fullVolumeTrainingDays': 4,
      }, _asOf);
      equal((warned['warnings']! as List).length, 1);
      rejects(
        () => dietProgramme(
          'imf',
        ).build({..._imf, 'arrangement': 'MMMMMRR'}, 2, 'x'),
      );

      // Apply publishes ordinary records; reapplying reuses them.
      final applied = await programmes.apply('imf', _imf, _asOf, 'cut');
      jsonEqual(applied['cycle'], {'id': 'cut', 'revision': 1});
      final again = await programmes.apply('imf', _imf, _asOf, 'cut');
      jsonEqual(again['dayTypes'], applied['dayTypes']);
      final changed = await programmes.apply(
        'imf',
        {..._imf, 'fatPerLb': '0.3'},
        _asOf,
        'cut',
      );
      jsonEqual(changed['cycle'], {'id': 'cut', 'revision': 2});
      final run = await DietService(store).start(
        runId: 'cut',
        cycleId: 'cut',
        cycleRevision: 2,
        startDate: '2026-11-02',
        asOfText: _asOf,
        requestId: 'r',
      );
      equal(run.targets.length, 2);

      // A custom 13 + 1 cycle of your own day types gets the same guide.
      final diets = DietService(store);
      await diets.publishCycle(
        DietCycle.fromJson({
          'id': 'mine',
          'name': '13 + 1',
          'loop': true,
          'days': [
            {
              'type': 'repeat',
              'count': 13,
              'days': [
                {
                  'type': 'day',
                  'dayType': {'id': 'cut-rfl', 'revision': 1},
                },
              ],
            },
            {
              'type': 'day',
              'dayType': {'id': 'cut-maintenance', 'revision': 2},
            },
          ],
        }),
        0,
      );
      final mine = await programmes.cycleGuide(
        'mine',
        1,
        _asOf,
        simulateDays: 14,
      );
      equal(mine['policy'], 'bodytmi-cycle-guide/1');
      check(
        (_n(jsonObject(mine['bookEstimate'], 'b')['fatPerCycle']) -
                    13 * (3420 - 821.6) / 3500)
                .abs() <
            1e-6,
        'cycle estimate',
      );
      equal(jsonObject(mine['simulation'], 's')['status'], 'resolved');
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });

  test('CLI programme list, guide and apply', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-prog-cli-');
    final db = '${dir.path}/db.sqlite';
    final store = await TrainingStore.open(db);
    await _joe(store, stepLength: true);
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
      final list = await invoke([
        'programme',
        'list',
      ], jsonEncode({'schemaVersion': 1}));
      equal(
        (jsonObject(jsonDecode(list.output), 'r')['data']! as List).length,
        4,
      );
      final guide = await cli('programme guide', {
        'programme': 'erfl',
        'choices': {
          'walking': {'steps': 40000},
          'afterDays': 3,
        },
        'asOf': _asOf,
        'simulateDays': 7,
      });
      check(guide.code == 0, guide.error);
      // 40,000 × 0.75 m = 30 km a day.
      equal(
        jsonObject(
          jsonObject(guide.data, 'g')['bookEstimate'],
          'b',
        )['walkingKmPerDay'],
        '30',
      );
      equal(
        (await cli('programme guide', {
          'programme': 'keto',
          'asOf': _asOf,
        })).code,
        3,
      );
      equal(
        (await cli('programme apply', {
          'programme': 'imf',
          'choices': {..._imf, 'pattern': '9:9'},
          'asOf': _asOf,
          'prefix': 'p',
        })).code,
        2,
      );
      final applied = await cli('programme apply', {
        'programme': 'imf',
        'choices': _imf,
        'asOf': _asOf,
        'prefix': 'p',
      });
      check(applied.code == 0, applied.error);
      final cycleGuide = await cli('cycle guide', {
        'cycleId': 'p',
        'revision': 1,
        'asOf': _asOf,
      });
      check(cycleGuide.code == 0, cycleGuide.error);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
