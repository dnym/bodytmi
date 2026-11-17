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
  test('a reached plan target proposes ending the plan', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-target-');
    final store = await TrainingStore.open('${dir.path}/db.sqlite');
    try {
      // 90 kg falling 0.1 kg a day; the trend lags behind the scale.
      await _setUp(
        store,
        mass: (day) => (90 - day * 0.1).toStringAsFixed(1),
        days: 60,
      );
      final plans = PlanService(store);
      final reviews = ReviewService(store);
      var plan = await plans.activate(
        planId: 'cut',
        programme: 'normal',
        startDate: _date(1),
        asOfText: _at(0),
        requestId: 'r',
      );
      rejects(
        () => PlanTarget.fromJson({
          'measure': 'mass',
          'relation': 'atMost',
          'value': _q('20', 'percent'),
        }),
      );
      rejects(
        () => PlanTarget.fromJson({
          'measure': 'bodyFat',
          'relation': 'below',
          'value': _q('15', 'percent'),
        }),
      );
      final stale = await _failure(
        () => plans.setTarget('cut', plan.contentVersion + 1, null),
      );
      equal(stale.code, 'conflict');
      plan = await plans.setTarget('cut', plan.contentVersion, {
        'measure': 'mass',
        'relation': 'atMost',
        'value': _q('86', 'kg'),
      });
      equal(plan.target!.value.enteredValue, '86');
      Map<String, Object?> finding(Map<String, Object?> review) =>
          (review['findings']! as List)
              .cast<Map<String, Object?>>()
              .singleWhere((f) => f['kind'] == 'target');
      var review = await reviews.review('cut', _at(20));
      equal(finding(review)['status'], 'not-reached');
      check(
        !(review['pending']! as List).any((p) => (p as Map)['kind'] == 'end'),
      );
      review = await reviews.review('cut', _at(55));
      equal(finding(review)['status'], 'reached');
      final end = (review['pending']! as List)
          .cast<Map<String, Object?>>()
          .singleWhere((p) => p['kind'] == 'end');
      jsonEqual(end['change'], {'endDate': _date(56)});
      await reviews.accept(end['id']! as String, _date(56));
      plan = await plans.plan('cut');
      equal(plan.status, 'ended');
      equal(plan.endDate, _date(56));
      // A body-fat target needs the selected source; it never guesses.
      final other = await TrainingStore.open('${dir.path}/other.sqlite');
      try {
        await _setUp(other, mass: (_) => '90', days: 30);
        final p = await PlanService(other).activate(
          planId: 'bf',
          programme: 'normal',
          startDate: _date(1),
          asOfText: _at(0),
          requestId: 'r',
        );
        await PlanService(other).setTarget('bf', p.contentVersion, {
          'measure': 'bodyFat',
          'relation': 'atMost',
          'value': _q('20', 'percent'),
        });
        final r = await ReviewService(other).review('bf', _at(10));
        equal(finding(r)['status'], 'reached');
        equal(
          canonicalJson(finding(r)['current']),
          canonicalJson({'value': '20', 'unit': 'percent'}),
        );
      } finally {
        await other.close();
      }
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });

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
      // A second intake proposal, and (six weeks in) a break.
      final second = (review['pending']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere((p) => p['kind'] == 'lower-intake');
      check(
        (review['pending']! as List).cast<Map<String, Object?>>().any(
          (p) => p['kind'] == 'break',
        ),
        'break proposed',
      );
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

void reviewBreakTests() {
  test('break and inserted RFL day proposals', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-review-4-');
    final store = await TrainingStore.open('${dir.path}/db.sqlite');
    try {
      // Losing steadily, so only the stint length triggers a proposal.
      await _setUp(store, mass: (day) => '${95 - day * 0.1}');
      final plans = PlanService(store);
      final reviews = ReviewService(store);
      await plans.activate(
        planId: 'cut',
        programme: 'normal',
        startDate: _date(1),
        asOfText: _at(0),
        requestId: 'r',
        namedDiet: 'mediterranean',
      );
      equal((await plans.plan('cut')).json['namedDiet'], 'mediterranean');
      var review = await reviews.review('cut', _at(40));
      check(
        !(review['pending']! as List).cast<Map<String, Object?>>().any(
          (p) => p['kind'] == 'break',
        ),
        'category 2 needs 6 weeks',
      );
      review = await reviews.review('cut', _at(43));
      final proposal = (review['pending']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere((p) => p['kind'] == 'break');
      await reviews.accept(proposal['id']! as String, _date(44));
      final schedule = await DietService(
        store,
      ).schedule(_date(43), 16, runId: 'cut');
      List<Object?> ids() => [
        for (final d
            in (schedule['days']! as List).cast<Map<String, Object?>>())
          jsonObject(d['dayType'], 'd')['id'],
      ];
      equal(ids().first, 'cut-day');
      equal(ids().where((d) => d == 'cut-break').length, 14);
      equal(ids().last, 'cut-day');
      // Break energy is maintenance: 500 kcal above the deficit day.
      check(
        (_energyOn(schedule, 1) - _energyOn(schedule, 0) - 500).abs() < 1e-6,
        'break at maintenance',
      );
      // The next stint counts from the end of the break.
      review = await reviews.review('cut', _at(60));
      check(
        !(review['pending']! as List).cast<Map<String, Object?>>().any(
          (p) => p['kind'] == 'break',
        ),
        'no second break yet',
      );
      TrainingArchive.fromJson((await store.archive()).toJson());
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });

  test('a regain above baseline proposes inserted RFL days', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-review-5-');
    final store = await TrainingStore.open('${dir.path}/db.sqlite');
    try {
      // Stable at 90 kg, then 92.5 kg from day 20 (2.8 % above).
      await _setUp(store, mass: (day) => day < 20 ? '90' : '92.5', days: 40);
      final plans = PlanService(store);
      final reviews = ReviewService(store);
      await plans.activate(
        planId: 'keep',
        programme: 'imf',
        choices: {
          'activity': 'weights',
          'pattern': '6:1',
          'arrangement': 'MMMMMMR',
          'fatPerLb': '0.38',
        },
        startDate: _date(1),
        asOfText: _at(0),
        requestId: 'r',
      );
      var review = await reviews.review('keep', _at(10));
      check(
        !(review['pending']! as List).cast<Map<String, Object?>>().any(
          (p) => p['kind'] == 'insert-rfl',
        ),
        'at baseline',
      );
      review = await reviews.review('keep', _at(35));
      final proposal = (review['pending']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere((p) => p['kind'] == 'insert-rfl');
      await reviews.accept(proposal['id']! as String, _date(36));
      final schedule = await DietService(
        store,
      ).schedule(_date(36), 7, runId: 'keep');
      final rfl = [
        for (final d
            in (schedule['days']! as List).cast<Map<String, Object?>>())
          if (jsonObject(d['dayType'], 'd')['id'] == 'keep-rfl') d['date'],
      ];
      equal(rfl.length, 3);
      TrainingArchive.fromJson((await store.archive()).toJson());
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });
}
