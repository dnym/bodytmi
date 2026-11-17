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

String _date(int day) => DateTime.utc(
  2026,
  9,
  1,
).add(Duration(days: day)).toIso8601String().substring(0, 10);

/// Stage 2 "done when" (APP-PLAN section 5) through the native CLI. The
/// training run that ERFL pauses is set up through the library.
void stage2AcceptanceTests() {
  test('stage 2 acceptance: programmes, plans and review', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-stage2-');
    final db = '${dir.path}/db.sqlite';
    final store = await TrainingStore.open(db);
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
    await programs.create(
      'lift',
      'strength',
      1,
      DateTime.utc(2026, 9, 1),
      loop: true,
    );
    await store.close();

    Future<Map<String, Object?>> ok(
      String name,
      Map<String, Object?> fields,
    ) async {
      final r = await invoke(
        name.split(' '),
        jsonEncode({'schemaVersion': 1, 'database': db, ...fields}),
      );
      check(r.code == 0, '$name: ${r.error}');
      final data = jsonObject(jsonDecode(r.output), 'r')['data'];
      return data is Map<String, Object?> ? data : {'list': data};
    }

    List<Map<String, Object?>> list(Object? value) =>
        (value! as List).cast<Map<String, Object?>>();

    try {
      // Your data: flat 91 kg for 100 days, DEXA 22 %, IMF energy.
      await ok('profile set', {
        'profile': {
          'sex': 'male',
          'birthDate': '1988-04-02',
          'stepLength': _q('76', 'cm'),
        },
        'expectedRevision': 0,
      });
      await ok('observation import-apply', {
        'confirm': true,
        'document': {
          'format': 'bodytmi-observation-import/1',
          'source': {'namespace': 'scale'},
          'observations': [
            for (var day = 0; day < 100; day++)
              {
                'sourceId': 'mass-$day',
                'measure': 'body-mass',
                'value': _q('91', 'kg'),
                'observedAt': '${_date(day)}T07:00:00+02:00',
                'attributes': {'context': 'health'},
              },
            {
              'sourceId': 'dexa',
              'measure': 'body-fat',
              'value': _q('22', 'percent'),
              'date': _date(0),
              'attributes': {'method': 'dexa'},
            },
          ],
        },
      });
      await ok('body source', {
        'from': _date(0),
        'source': {'kind': 'series', 'method': 'dexa'},
        'expectedRevision': 0,
      });
      await ok('energy method', {
        'from': _date(0),
        'method': {
          'formula': 'mcdonald-imf-tdee',
          'activity': 'light',
          'exercise': [
            {'kind': 'high-weights', 'hours': '1'},
          ],
        },
        'expectedRevision': 0,
      });
      await ok('stepgoal set', {
        'from': _date(0),
        'steps': 8000,
        'expectedRevision': 0,
      });

      // 1. The four guides side by side, each number with its source.
      final imfChoices = {
        'activity': 'weights',
        'pattern': '4:3',
        'arrangement': 'MMRMMRR',
        'fatPerLb': '0.38',
      };
      final compared = await ok('programme compare', {
        'asOf': '${_date(33)}T20:00:00+02:00',
        'simulateDays': 28,
        'choices': {
          'normal': <String, Object?>{},
          'rfl': {
            'activity': 'weights',
            'breakActivity': 'light',
            'breakDays': 14,
            'dietWeeks': 3,
            'refeedCarbohydratePerLb': '3',
          },
          'erfl': {
            'walking': {'steps': 40000},
            'afterDays': 3,
          },
          'imf': imfChoices,
        },
      });
      final guides = list(compared['guides']);
      equal(guides.length, 4);
      for (final g in guides) {
        equal(g['status'], 'resolved');
        equal(g['category'], 2);
        equal(jsonObject(g['simulation'], 's')['status'], 'resolved');
        equal(jsonObject(g['bookEstimate'], 'b')['status'], 'resolved');
        for (final day in list(g['dayTypes'])) {
          final sources = jsonObject(day['sources'], 'sources');
          for (final goal in jsonObject(day['goals'], 'goals').keys) {
            check(
              sources.containsKey(goal),
              '${g['programme']} ${day['id']} $goal has no source',
            );
          }
        }
      }
      // E.g. the RFL protein row: category 2, weights, 1.25 g/lb.
      final rfl = list(
        guides[1]['dayTypes'],
      ).firstWhere((d) => d['id'] == 'rfl-rfl');
      check(
        (jsonObject(rfl['sources'], 's')['protein']! as String).contains(
          'ch. 8 table 1: category 2, weights: 1.25',
        ),
        '${rfl['sources']}',
      );

      // 2. ERFL with a 4-day walking goal and one paused run; ending it
      // resumes the run and restores the step goal.
      final preview = await ok('plan preview', {
        'programme': 'erfl',
        'choices': {
          'walking': {'steps': 40000},
          'afterDays': 3,
        },
        'startDate': _date(34),
        'asOf': '${_date(33)}T20:00:00+02:00',
      });
      final offered = list(preview['companions']);
      check(offered.any((o) => o['kind'] == 'steps'), 'steps offered');
      check(
        offered.any((o) => o['kind'] == 'pauseRun' && o['runId'] == 'lift'),
        'pause offered',
      );
      await ok('plan activate', {
        'planId': 'erfl',
        'programme': 'erfl',
        'choices': {
          'walking': {'steps': 40000},
          'afterDays': 3,
        },
        'startDate': _date(34),
        'asOf': '${_date(33)}T20:00:00+02:00',
        'requestId': 'erfl-1',
        'companions': {
          'steps': true,
          'pauseRuns': ['lift'],
        },
      });
      equal((await ok('run show', {'runId': 'lift'}))['status'], 'paused');
      for (var day = 34; day < 38; day++) {
        equal(
          (await ok('stepgoal show', {'date': _date(day)}))['steps'],
          40000,
        );
      }
      equal((await ok('stepgoal show', {'date': _date(38)}))['steps'], 10000);
      final erflReview = await ok('plan review', {
        'planId': 'erfl',
        'asOf': '${_date(41)}T20:00:00+02:00',
      });
      final end = list(
        erflReview['pending'],
      ).firstWhere((p) => p['kind'] == 'end');
      jsonEqual(end['change'], {'endDate': _date(41)});
      final ended = await ok('plan end', {
        'planId': 'erfl',
        'date': _date(41),
        'expectedVersion': 1,
        'resumeRuns': ['lift'],
        'confirm': true,
      });
      jsonEqual(jsonObject(ended['undone'], 'u')['resumed'], ['lift']);
      equal((await ok('run show', {'runId': 'lift'}))['status'], 'active');
      equal((await ok('stepgoal show', {'date': _date(41)}))['steps'], 8000);

      // 3. IMF 4:3 from Monday; its Thursday maintenance day moves to
      // Saturday without shifting later days.
      equal(DateTime.parse(_date(41)).weekday, DateTime.monday);
      await ok('plan activate', {
        'planId': 'imf',
        'programme': 'imf',
        'choices': imfChoices,
        'startDate': _date(41),
        'asOf': '${_date(40)}T20:00:00+02:00',
        'requestId': 'imf-1',
      });
      Future<String> week(int from) async {
        final s = await ok('diet schedule', {
          'runId': 'imf',
          'from': _date(from),
          'days': 7,
        });
        return [
          for (final d in list(s['days']))
            jsonObject(d['dayType'], 'd')['id'] == 'imf-rfl' ? 'R' : 'M',
        ].join();
      }

      equal(await week(41), 'MMRMMRR');
      await ok('diet move', {
        'runId': 'imf',
        'from': _date(44),
        'to': _date(46),
        'reason': 'Dinner with friends on Saturday',
        'expectedVersion': 1,
      });
      equal(await week(41), 'MMRRMMR');
      equal(await week(48), 'MMRMMRR');

      // 4. Your own 13 + 1 cycle gets the same guide and simulation.
      for (final (id, goals) in [
        (
          'my-rfl',
          {
            'energy': {'sum': true},
            'protein': {'basis': 'fat-free-mass', 'perLb': '1.1'},
            'carbohydrate': {'fixed': _q('20', 'g')},
            'fat': {'fixed': _q('20', 'g')},
          },
        ),
        (
          'my-maintenance',
          {
            'energy': {'basis': 'maintenance'},
            'protein': {'basis': 'fat-free-mass', 'perLb': '1.1'},
            'fat': {'basis': 'mass', 'perLb': '0.38'},
            'carbohydrate': {'remainder': true},
          },
        ),
      ]) {
        await ok('daytype publish', {
          'dayType': {'id': id, 'name': id, 'goals': goals},
          'expectedRevision': 0,
        });
      }
      await ok('cycle publish', {
        'cycle': {
          'id': 'thirteen-one',
          'name': '13 + 1',
          'loop': true,
          'days': [
            {
              'type': 'repeat',
              'count': 13,
              'days': [
                {
                  'type': 'day',
                  'dayType': {'id': 'my-rfl', 'revision': 1},
                },
              ],
            },
            {
              'type': 'day',
              'dayType': {'id': 'my-maintenance', 'revision': 1},
            },
          ],
        },
        'expectedRevision': 0,
      });
      final mine = await ok('cycle guide', {
        'cycleId': 'thirteen-one',
        'revision': 1,
        'asOf': '${_date(48)}T20:00:00+02:00',
        'simulateDays': 28,
      });
      equal(jsonObject(mine['simulation'], 's')['status'], 'resolved');
      equal(jsonObject(mine['bookEstimate'], 'b')['status'], 'resolved');
      equal(jsonObject(mine['cycle'], 'c')['length'], 14);

      // 5. A Normal plan on flat mass: review proposes −100 kcal a day;
      // accepting changes the target once.
      await ok('plan end', {
        'planId': 'imf',
        'date': _date(55),
        'expectedVersion': 1,
        'confirm': true,
      });
      await ok('plan activate', {
        'planId': 'normal',
        'programme': 'normal',
        'startDate': _date(55),
        'asOf': '${_date(54)}T20:00:00+02:00',
        'requestId': 'n-1',
      });
      final review = await ok('plan review', {
        'planId': 'normal',
        'asOf': '${_date(80)}T20:00:00+02:00',
      });
      final lower = list(review['pending']).single;
      equal(lower['kind'], 'lower-intake');
      jsonEqual(lower['change'], {'energyDelta': '-100'});
      for (var i = 0; i < 2; i++) {
        final accepted = await ok('plan accept', {
          'proposalId': lower['id'],
          'from': _date(81),
        });
        equal(accepted['status'], 'accepted');
      }
      final again = await ok('plan review', {
        'planId': 'normal',
        'asOf': '${_date(81)}T20:00:00+02:00',
      });
      equal(list(again['pending']).length, 0);
      final schedule = await ok('diet schedule', {
        'runId': 'normal',
        'from': _date(79),
        'days': 4,
      });
      final energy = [
        for (final d in list(schedule['days']))
          double.parse(
            jsonObject(
                  jsonObject(
                    jsonObject(d['goals'], 'g')['energy'],
                    'e',
                  )['value'],
                  'v',
                )['value']!
                as String,
          ),
      ];
      check((energy[1] - energy[2] - 100).abs() < 1e-6, '$energy');
      equal(energy[3], energy[2]);
      equal(energy[0], energy[1]);

      // Everything round-trips through both backup formats.
      await ok('backup create', {'destination': '${dir.path}/backup'});
      await ok('archive export', {'destination': '${dir.path}/export.json'});
      final restored = '${dir.path}/restored.sqlite';
      final r = await invoke(
        ['archive', 'restore'],
        jsonEncode({
          'schemaVersion': 1,
          'database': restored,
          'source': '${dir.path}/export.json',
          'recoveryDestination': '${dir.path}/recovery',
          'confirm': true,
        }),
      );
      check(r.code == 0, r.error);
      final back = await invoke(
        ['diet', 'schedule'],
        jsonEncode({
          'schemaVersion': 1,
          'database': restored,
          'runId': 'normal',
          'from': _date(79),
          'days': 4,
        }),
      );
      equal(
        canonicalJson(jsonObject(jsonDecode(back.output), 'r')['data']),
        canonicalJson(schedule),
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
