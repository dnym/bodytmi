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

String _date(int day) => DateTime.utc(
  2026,
  10,
  1,
).add(Duration(days: day)).toIso8601String().substring(0, 10);

String _at(int day) => '${_date(day)}T20:00:00+01:00';

Future<BodyTmiException> _failure(Future<Object?> Function() action) async {
  try {
    await action();
  } on BodyTmiException catch (error) {
    return error;
  }
  throw StateError('Expected a BodyTmiException.');
}

/// A male profile weighing [mass](day) kg every morning for [days] days,
/// 20 % body fat (DEXA, category 2), RFL handbook maintenance 13 cal/lb.
Future<void> _setUp(
  TrainingStore store, {
  required String Function(int day) mass,
  int days = 90,
}) async {
  final body = BodyService(store);
  await body.setProfile(
    Profile.fromJson({'sex': 'male', 'birthDate': '1990-01-01'}),
    0,
  );
  final observations = ObservationService(store);
  for (var day = 0; day < days; day++) {
    await observations.save({
      'id': 'mass-$day',
      'measure': 'body-mass',
      'value': _q(mass(day), 'kg'),
      'observedAt': '${_date(day)}T07:00:00+01:00',
      'attributes': {'context': 'health'},
    }, 0);
  }
  await observations.save({
    'id': 'dexa',
    'measure': 'body-fat',
    'value': _q('20', 'percent'),
    'date': _date(0),
    'attributes': {'method': 'dexa'},
  }, 0);
  await body.selectSource(
    _date(0),
    BodyFatSource.fromJson({'kind': 'series', 'method': 'dexa'}),
    0,
  );
  await EnergyService(store).selectMethod(
    _date(0),
    MaintenanceMethod.fromJson({
      'formula': 'mcdonald-rfl-maintenance',
      'activity': 'moderate',
      'calPerLb': '13',
    }),
    0,
  );
}

double _energyOn(Map<String, Object?> schedule, int index) {
  final day = jsonObject((schedule['days']! as List)[index], 'day');
  final energy = jsonObject(jsonObject(day['goals'], 'goals')['energy'], 'e');
  return double.parse(jsonObject(energy['value'], 'v')['value']! as String);
}

void reviewTests() {
  test('flat mass proposes −100 kcal a day, accepted once', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-review-');
    final store = await TrainingStore.open('${dir.path}/db.sqlite');
    try {
      await _setUp(store, mass: (_) => '90');
      final plans = PlanService(store);
      final reviews = ReviewService(store);
      await plans.activate(
        planId: 'cut',
        programme: 'normal',
        startDate: _date(1),
        asOfText: _at(0),
        requestId: 'r',
      );
      // Too early: fewer than 21 days.
      var review = await reviews.review('cut', _at(15));
      equal((review['created']! as List).length, 0);
      equal(
        jsonObject((review['findings']! as List).first, 'f')['status'],
        'unavailable',
      );
      review = await reviews.review('cut', _at(25));
      final trend = jsonObject((review['findings']! as List).first, 't');
      equal(trend['actualLossKg'], '0');
      check(double.parse(trend['plannedLossKg']! as String) > 1, '$trend');
      final pending = (review['pending']! as List).cast<Map<String, Object?>>();
      equal(pending.length, 1);
      equal(pending.single['kind'], 'lower-intake');
      jsonEqual(pending.single['change'], {'energyDelta': '-100'});
      // Recorded once: reviewing again adds nothing.
      review = await reviews.review('cut', _at(25));
      equal((review['created']! as List).length, 0);
      equal((review['pending']! as List).length, 1);

      final id = pending.single['id']! as String;
      final accepted = await reviews.accept(id, _date(26));
      equal(accepted.status, 'accepted');
      equal((await reviews.accept(id, _date(30))).status, 'accepted');
      final schedule = await DietService(
        store,
      ).schedule(_date(24), 4, runId: 'cut');
      // 90 kg × 13 cal/lb = 2,579.71…; minus 500; minus 100 from day 26.
      final before = _energyOn(schedule, 1), after = _energyOn(schedule, 2);
      check((before - after - 100).abs() < 1e-6, '$before → $after');
      equal(_energyOn(schedule, 3), after);
      final run = await DietService(store).run('cut');
      equal(run.segments.length, 1);
      // A new window needs 21 days after the change.
      review = await reviews.review('cut', _at(30));
      equal((review['created']! as List).length, 0);
      review = await reviews.review('cut', _at(48));
      equal((review['created']! as List).length, 1);
      final second = jsonObject((review['pending']! as List).single, 'p');
      await reviews.decline(second['id']! as String);
      equal(
        (await _failure(
          () => reviews.accept(second['id']! as String, _date(49)),
        )).code,
        'validation',
      );

      // Archives: a forged acceptance without its change is rejected.
      final json = (await store.archive()).toJson();
      TrainingArchive.fromJson(json);
      final forged = jsonDecode(jsonEncode(json)) as Map<String, Object?>;
      final row = (forged['dietRecords']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere((r) => r['kind'] == 'diet-run');
      (row['snapshot']! as Map).remove('segments');
      rejects(() => TrainingArchive.fromJson(forged));
      final backup = '${dir.path}/backup';
      await store.backup(backup);
      NativeBackup.validateDatabase('$backup/database.sqlite');
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });

  test('recompute, category, moderate policy and end proposals', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-review-2-');
    final store = await TrainingStore.open('${dir.path}/db.sqlite');
    try {
      // Mass falls from 100 kg by 0.25 kg a day.
      await _setUp(store, mass: (day) => '${100 - day * 0.25}');
      final plans = PlanService(store);
      final reviews = ReviewService(store);
      await plans.activate(
        planId: 'cut',
        programme: 'normal',
        startDate: _date(1),
        asOfText: _at(0),
        requestId: 'r',
      );
      // After 40 days the trend is ~10 % lower: energy and protein moved.
      var review = await reviews.review('cut', _at(40));
      final kinds = [
        for (final p
            in (review['pending']! as List).cast<Map<String, Object?>>())
          p['kind'],
      ];
      check(kinds.contains('recompute'), '$kinds');
      check(!kinds.contains('lower-intake'), 'losing well');
      final recompute = (review['pending']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere((p) => p['kind'] == 'recompute');
      await reviews.accept(recompute['id']! as String, _date(41));
      final schedule = await DietService(
        store,
      ).schedule(_date(40), 2, runId: 'cut');
      check(_energyOn(schedule, 1) < _energyOn(schedule, 0), 'lower target');

      // A leaner DEXA moves the category; accepting re-applies the
      // programme from that date.
      await ObservationService(store).save({
        'id': 'dexa-2',
        'measure': 'body-fat',
        'value': _q('14', 'percent'),
        'date': _date(45),
        'attributes': {'method': 'dexa'},
      }, 0);
      review = await reviews.review('cut', _at(46));
      final category = (review['pending']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere((p) => p['kind'] == 'category');
      jsonEqual(category['change'], {'category': 1});
      await reviews.accept(category['id']! as String, _date(47));
      review = await reviews.review('cut', _at(47));
      check(
        !(review['pending']! as List).cast<Map<String, Object?>>().any(
          (p) => p['kind'] == 'category',
        ),
        'category settled',
      );
      // The moderate policy is for Normal plans only and proposes −10 %.
      final flat = await Directory.systemTemp.createTemp('bodytmi-review-3-');
      final other = await TrainingStore.open('${flat.path}/db.sqlite');
      try {
        await _setUp(other, mass: (_) => '90', days: 40);
        await PlanService(other).activate(
          planId: 'moderate',
          programme: 'normal',
          choices: {
            'deficit': {'percent': '15'},
          },
          startDate: _date(1),
          asOfText: _at(0),
          requestId: 'r',
        );
        final m = await ReviewService(
          other,
        ).review('moderate', _at(25), policy: 'mcdonald-moderate/1');
        final p = jsonObject((m['pending']! as List).single, 'p');
        equal(p['policy'], 'mcdonald-moderate/1');
        // 10 % of 0.85 × 2,579.71… kcal.
        check(
          (double.parse(
                        jsonObject(p['change'], 'c')['energyDelta']! as String,
                      ) +
                      0.1 * 0.85 * 90 / kgPerLb * 13)
                  .abs() <
              1e-6,
          '${p['change']}',
        );
      } finally {
        await other.close();
        await flat.delete(recursive: true);
      }

      // ERFL: once its finite cycle is over, review proposes ending it.
      final ended = await reviews.proposals(planId: 'cut');
      check(ended.isNotEmpty, 'proposals listed');
      await plans.end('cut', _date(50), 1, confirm: true);
      await plans.activate(
        planId: 'erfl',
        programme: 'erfl',
        choices: {
          'walking': {'distanceKm': '20'},
          'afterDays': 3,
        },
        startDate: _date(50),
        asOfText: _at(49),
        requestId: 'e',
      );
      equal(
        (await _failure(() => reviews.review('cut', _at(52)))).code,
        'validation',
      );
      review = await reviews.review('erfl', _at(57));
      final end = (review['pending']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere((p) => p['kind'] == 'end');
      jsonEqual(end['change'], {'endDate': _date(57)});
      await reviews.accept(end['id']! as String, _date(57));
      equal((await plans.plan('erfl')).status, 'ended');
      TrainingArchive.fromJson((await store.archive()).toJson());
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });

  test('CLI plan review, proposals, accept and decline', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-review-cli-');
    final db = '${dir.path}/db.sqlite';
    final store = await TrainingStore.open(db);
    await _setUp(store, mass: (_) => '90', days: 30);
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
        (await cli('plan activate', {
              'planId': 'cut',
              'programme': 'normal',
              'startDate': _date(1),
              'asOf': _at(0),
              'requestId': 'r',
            })).code ==
            0,
      );
      equal(
        (await cli('plan review', {
          'planId': 'cut',
          'asOf': _at(25),
          'policy': 'nonsense',
        })).code,
        2,
      );
      final review = await cli('plan review', {
        'planId': 'cut',
        'asOf': _at(25),
      });
      check(review.code == 0, review.error);
      final proposals =
          (await cli('plan proposals', {'planId': 'cut'})).data! as List;
      final id = jsonObject(proposals.single, 'p')['id'];
      final accepted = await cli('plan accept', {
        'proposalId': id,
        'from': _date(26),
      });
      check(accepted.code == 0, accepted.error);
      equal((await cli('plan decline', {'proposalId': id})).code, 2);
      equal(
        (await cli('plan accept', {'proposalId': 'x', 'from': _date(26)})).code,
        3,
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
