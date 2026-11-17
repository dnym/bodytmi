import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'cli_test.dart';
import 'support.dart';

Map<String, Object?> _q(String value, String unit) => {
  'value': value,
  'unit': unit,
};

const _dataset = 'data/food/slv.json.gz';

String _date(int day) => DateTime.utc(
  2026,
  9,
  1,
).add(Duration(days: day)).toIso8601String().substring(0, 10);

/// Stage 3 "done when" (APP-PLAN section 5) through the native CLI.
void stage3AcceptanceTests() {
  test('stage 3 acceptance: foods, diary, budget and reports', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-stage3-');
    var db = '${dir.path}/db.sqlite';

    Future<({int code, Map<String, Object?> body})> call(
      String name,
      Map<String, Object?> fields,
    ) async {
      final r = await invoke(
        name.split(' '),
        jsonEncode({
          'schemaVersion': 1,
          if (!name.startsWith('food dataset')) 'database': db,
          ...fields,
        }),
      );
      final text = r.code == 0 ? r.output : r.error;
      return (code: r.code, body: jsonObject(jsonDecode(text), 'r'));
    }

    Future<Map<String, Object?>> ok(
      String name,
      Map<String, Object?> fields,
    ) async {
      final r = await call(name, fields);
      check(r.code == 0, '$name: ${r.body}');
      final data = r.body['data'];
      return data is Map<String, Object?> ? data : {'list': data};
    }

    Future<String> fails(
      String name,
      Map<String, Object?> fields,
      int code,
    ) async {
      final r = await call(name, fields);
      check(r.code == code, '$name: expected $code, got ${r.code} ${r.body}');
      return jsonObject(r.body['error'], 'e')['message']! as String;
    }

    Map<String, Object?> at(Object? value, List<String> path) {
      var current = value;
      for (final key in path) {
        current = jsonObject(current, key)[key];
      }
      return jsonObject(current, path.last);
    }

    String nutrientValue(Map<String, Object?> nutrition, String id) =>
        at(nutrition, ['nutrients', id])['value']! as String;

    try {
      // Profile, flat mass, DEXA body fat and an IMF energy method so an
      // IMF 4:3 plan resolves its day budgets.
      await ok('profile set', {
        'profile': {'sex': 'male', 'birthDate': '1988-04-02'},
        'expectedRevision': 0,
      });
      await ok('observation import-apply', {
        'confirm': true,
        'document': {
          'format': 'bodytmi-observation-import/1',
          'source': {'namespace': 'scale'},
          'observations': [
            for (var day = 0; day < 30; day++)
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
      // Starts on a Monday: MMRMMRR, so day 28 is maintenance and 29 RFL.
      equal(DateTime.parse(_date(27)).weekday, DateTime.monday);
      await ok('plan activate', {
        'planId': 'imf',
        'programme': 'imf',
        'choices': {
          'activity': 'weights',
          'pattern': '4:3',
          'arrangement': 'MMRMMRR',
          'fatPerLb': '0.38',
        },
        'startDate': _date(27),
        'asOf': '${_date(26)}T20:00:00+02:00',
        'requestId': 'imf-1',
      });

      // Foods from the packaged Swedish Food Agency dataset.
      final info = await ok('food dataset-info', {'dataset': _dataset});
      equal(info['foods'], 2606);
      equal(at(info, ['licence'])['name'], 'CC BY 4.0');
      final hits = await ok('food dataset-search', {
        'dataset': _dataset,
        'query': 'mellanmjölk',
        'limit': 3,
      });
      jsonEqual((hits['results']! as List).first, {
        'number': 150,
        'name': 'Mellanmjölk fett 1,5% berikad',
        'english': 'Semi-skimmed milk 1.5% fat fortified',
        'match': 'prefix',
      });
      for (final n in [150, 151, 29, 96, 202]) {
        final adopted = await ok('food adopt', {
          'dataset': _dataset,
          'number': n,
        });
        equal(adopted['published'], true);
      }
      equal(
        (await ok('food adopt', {
          'dataset': _dataset,
          'number': 150,
        }))['published'],
        false,
      );
      // Milk is per 100 g; logging millilitres needs a declared density.
      final noDensity = await fails('food nutrition', {
        'food': {'id': 'slv-150'},
        'amount': _q('200', 'ml'),
      }, 2);
      check(noDensity.contains('density'), noDensity);
      for (final id in ['slv-150', 'slv-151']) {
        final food = jsonObject(
          (await ok('food show', {'foodId': id}))['food'],
          'food',
        );
        food['density'] = {'mass': _q('103', 'g'), 'volume': _q('100', 'ml')};
        await ok('food publish', {'food': food, 'expectedRevision': 1});
      }
      // A label food of your own: per 100 ml as printed, no density.
      await ok('food publish', {
        'food': {
          'id': 'oat-drink',
          'name': 'Oat drink',
          'kind': 'base',
          'basis': '100ml',
          'source': {'kind': 'label'},
          'nutrients': {
            'energy': _q('46', 'kcal'),
            'protein': _q('1', 'g'),
            'carbohydrate': _q('6.7', 'g'),
            'fat': _q('1.5', 'g'),
          },
        },
        'expectedRevision': 0,
      });

      // My sandwich and my breakfast (200 ml milk + 1 sandwich).
      await ok('food publish', {
        'food': {
          'id': 'my-sandwich',
          'name': 'My sandwich',
          'kind': 'composite',
          'components': [
            {
              'food': {'id': 'slv-202', 'revision': 1},
              'amount': _q('40', 'g'),
            },
            {
              'food': {'id': 'slv-29', 'revision': 1},
              'amount': _q('8', 'g'),
            },
            {
              'food': {'id': 'slv-96', 'revision': 1},
              'amount': _q('20', 'g'),
            },
          ],
        },
        'expectedRevision': 0,
      });
      Map<String, Object?> breakfast(String milk, String ml) => {
        'id': 'my-breakfast',
        'name': 'My breakfast',
        'kind': 'composite',
        'components': [
          {
            'food': {'id': milk, 'revision': 2},
            'amount': _q(ml, 'ml'),
          },
          {
            'food': {'id': 'my-sandwich', 'revision': 1},
            'amount': {'portion': 'whole', 'count': '1'},
          },
        ],
      };
      await ok('food publish', {
        'food': breakfast('slv-150', '200'),
        'expectedRevision': 0,
      });
      final day1 = _date(28);
      await ok('diary add', {
        'entry': {
          'id': 'breakfast-1',
          'at': '${day1}T07:30:00+02:00',
          'meal': 'breakfast',
          'food': {'id': 'my-breakfast'},
          'amount': {'portion': 'whole', 'count': '1'},
        },
      });
      final before = await ok('diary day', {'date': day1});
      equal((before['entries']! as List).length, 1);
      // 200 ml milk at 1.03 g/ml is 206 g, plus 68 g of sandwich.
      equal(at(before, ['totals', 'mass'])['value'], '274');

      // Republish with 150 ml low-fat milk: the earlier day is unchanged.
      await ok('food publish', {
        'food': breakfast('slv-151', '150'),
        'expectedRevision': 1,
      });
      final after = await ok('diary day', {'date': day1});
      equal(canonicalJson(after['totals']), canonicalJson(before['totals']));
      final v2 = await ok('food show', {'foodId': 'my-breakfast'});
      check(
        Decimal.parse(nutrientValue(at(v2, ['whole']), 'energy')).compareTo(
              Decimal.parse(
                nutrientValue(jsonObject(before['totals'], 't'), 'energy'),
              ),
            ) <
            0,
        'low-fat breakfast has less energy',
      );

      // A cycle between composites is rejected.
      final cycle = await fails('food publish', {
        'food': {
          'id': 'my-sandwich',
          'name': 'My sandwich',
          'kind': 'composite',
          'components': [
            {
              'food': {'id': 'my-breakfast', 'revision': 1},
              'amount': {'portion': 'whole', 'count': '1'},
            },
          ],
        },
        'expectedRevision': 1,
      }, 2);
      check(cycle.contains('contain itself'), cycle);

      // A batch recipe logged in portions: 4 portions of a 1200 g pot.
      await ok('food publish', {
        'food': {
          'id': 'cheese-bake',
          'name': 'Cheese bake',
          'kind': 'composite',
          'components': [
            {
              'food': {'id': 'slv-96', 'revision': 1},
              'amount': _q('300', 'g'),
            },
            {
              'food': {'id': 'slv-202', 'revision': 1},
              'amount': _q('500', 'g'),
            },
          ],
          'batch': {'finalMass': _q('1200', 'g'), 'portions': 4},
        },
        'expectedRevision': 0,
      });
      final bake = await ok('food show', {'foodId': 'cheese-bake'});
      final perPortion = at(bake, ['perPortion']);
      equal(at(perPortion, ['mass'])['value'], '300');
      final day2 = _date(29); // an RFL day
      for (final date in [day1, day2]) {
        await ok('diary add', {
          'entry': {
            'id': 'dinner-$date',
            'at': '${date}T18:00:00+02:00',
            'meal': 'dinner',
            'food': {'id': 'cheese-bake'},
            'amount': {'portion': 'portion', 'count': '1'},
          },
        });
      }
      // The same portion by mass is the same nutrition.
      final byMass = await ok('food nutrition', {
        'food': {'id': 'cheese-bake'},
        'amount': _q('300', 'g'),
      });
      equal(
        nutrientValue(byMass, 'energy'),
        nutrientValue(perPortion, 'energy'),
      );
      // A 01:30 snack belongs to the evening before (diary day 04:00).
      await ok('diary add', {
        'entry': {
          'id': 'late-snack',
          'at': '${_date(30)}T01:30:00+02:00',
          'quick': {'energy': _q('150', 'kcal'), 'protein': _q('10', 'g')},
        },
      });
      equal(
        jsonObject((await ok('diary show', {'id': 'late-snack'})), 'e')['date'],
        day2,
      );

      // RFL and maintenance days show different remaining budgets for the
      // same dinner.
      await ok('diary mark', {'date': day1, 'status': 'complete'});
      final maint = await ok('diary day', {'date': day1});
      final rfl = await ok('diary day', {'date': day2});
      equal(maint['status'], 'complete');
      equal(rfl['status'], 'partial');
      equal(at(maint, ['budget', 'dayType'])['id'], 'imf-maintenance');
      equal(at(rfl, ['budget', 'dayType'])['id'], 'imf-rfl');
      final maintEnergy = at(maint, ['budget', 'goals', 'energy']);
      final rflEnergy = at(rfl, ['budget', 'goals', 'energy']);
      check(
        canonicalJson(maintEnergy['target']) !=
            canonicalJson(rflEnergy['target']),
        'different energy budgets',
      );
      check(
        canonicalJson(maintEnergy['remaining']) !=
            canonicalJson(rflEnergy['remaining']),
        'different remaining energy',
      );
      // Remaining = target - eaten, exactly.
      final target = Decimal.parse(
        jsonObject(maintEnergy['target'], 't')['value']! as String,
      );
      final eaten = Decimal.parse(
        jsonObject(maintEnergy['eaten'], 'e')['value']! as String,
      );
      final remaining = jsonObject(maintEnergy['remaining'], 'r');
      if (remaining['over'] == null) {
        equal(
          Fraction.decimal(target) - Fraction.decimal(eaten),
          Fraction.parse(remaining['value']! as String),
        );
      }
      // The quick snack declares no fat: day 2 fat is partly known, so the
      // remaining fat is only an upper bound.
      equal(at(rfl, ['totals', 'nutrients', 'fat'])['status'], 'partial');
      equal(
        at(rfl, ['budget', 'goals', 'fat', 'remaining'])['bound'],
        'atMost',
      );

      // Reports: a complete and a partial day, and a complete empty day.
      await ok('diary mark', {'date': _date(30), 'status': 'complete'});
      final report = await ok('diary report', {
        'from': day1,
        'until': _date(32),
      });
      jsonEqual(report['counts'], {'complete': 2, 'partial': 1, 'unlogged': 1});
      final complete = at(report, ['averages', 'completeDays']);
      equal(complete['days'], 2);
      final energy = at(complete, ['nutrients', 'energy']);
      equal(energy['days'], 2);
      equal(
        Fraction.parse(energy['value']! as String),
        Fraction.parse(
              jsonObject(
                    at(maint, ['totals', 'nutrients', 'energy']),
                    'e',
                  )['value']!
                  as String,
            ) /
            Fraction.integer(2),
      );
      final logged = at(report, ['averages', 'loggedDays']);
      equal(logged['days'], 3);
      equal(at(logged, ['nutrients', 'fat'])['days'], 2);
      final adherence = await ok('diary adherence', {
        'from': day1,
        'until': _date(32),
        'tolerancePercent': '10',
      });
      jsonEqual(adherence['days'], {
        'total': 4,
        'evaluated': 2,
        'notComplete': 2,
        'withoutPlan': 0,
      });

      // Water, repeat, edits and deletion.
      await ok('diary water', {
        'id': 'water-1',
        'at': '${day2}T10:00:00+02:00',
        'amount': _q('5', 'dl'),
      });
      final copies = await ok('diary repeat', {
        'from': day1,
        'to': _date(32),
        'idPrefix': 'again',
        'meal': 'breakfast',
      });
      equal((copies['list']! as List).length, 1);
      await fails('diary add', {
        'entry': {
          'id': 'late-snack',
          'at': '${day2}T12:00:00+02:00',
          'quick': {'energy': _q('1', 'kcal')},
        },
      }, 5);
      await ok('diary update', {
        'id': 'late-snack',
        'expectedVersion': 1,
        'entry': {
          'id': 'late-snack',
          'at': '${_date(30)}T01:30:00+02:00',
          'quick': {
            'energy': _q('150', 'kcal'),
            'protein': _q('10', 'g'),
            'carbohydrate': _q('5', 'g'),
            'fat': _q('7', 'g'),
            'fibre': _q('0', 'g'),
          },
        },
      });
      await fails('diary update', {
        'id': 'late-snack',
        'expectedVersion': 1,
        'entry': {
          'id': 'late-snack',
          'at': '${_date(30)}T01:30:00+02:00',
          'quick': {'energy': _q('1', 'kcal')},
        },
      }, 5);
      await fails('diary delete', {'id': 'water-1', 'expectedVersion': 1}, 2);
      await ok('diary delete', {
        'id': 'water-1',
        'expectedVersion': 1,
        'confirm': true,
      });

      // Maintenance calibrated from the diary: flat trend mass and 21
      // complete days at 2600 kcal give 2600 kcal (from day 1: the trend
      // needs a weigh-in before the window), compared with the IMF
      // formula in force. Too few complete days are reported, not guessed.
      final short = await ok('energy calibrate', {
        'from': _date(0),
        'until': _date(21),
      });
      equal(short['status'], 'insufficient');
      for (var day = 0; day < 21; day++) {
        await ok('diary add', {
          'entry': {
            'id': 'tracked-$day',
            'at': '${_date(day)}T12:00:00+02:00',
            'quick': {'energy': _q('2600', 'kcal'), 'protein': _q('150', 'g')},
          },
        });
        await ok('diary mark', {'date': _date(day), 'status': 'complete'});
      }
      final calibrated = await ok('energy calibrate', {
        'from': _date(1),
        'until': _date(21),
      });
      check(calibrated['status'] == 'calibrated', '$calibrated');
      equal(at(calibrated, ['value'])['value'], '2600');
      equal(at(calibrated, ['factors', 'massChange'])['value'], '0');
      final band = at(calibrated, ['comparison'])['band'];
      check(
        const {'agrees', 'between', 'disagrees'}.contains(band),
        'band $band',
      );

      // Nordic reference values over the tracked complete days, kept
      // apart from the plan: 150 g protein against 0.83 g/kg of 91 kg.
      final nordic = await ok('diary reference', {
        'from': _date(1),
        'until': _date(21),
      });
      equal(nordic['completeDays'], 20);
      final rows = (nordic['references']! as List).cast<Map<String, Object?>>();
      final protein = rows.singleWhere(
        (r) => r['nutrient'] == 'protein' && r['kind'] == 'riPerKg',
      );
      equal(at(protein, ['amount'])['value'], '75.53');
      equal(protein['relation'], 'meets');
      equal(
        rows.singleWhere((r) => r['nutrient'] == 'fat')['relation'],
        'unknown',
      );

      // Backup and logical export round trips keep the diary exactly.
      final reference = await ok('diary day', {'date': day2});
      final backup = '${dir.path}/backup';
      await ok('backup create', {'destination': backup});
      final export = '${dir.path}/export.json';
      await ok('archive export', {'destination': export});
      for (final (command, source) in [
        ('backup restore', backup),
        ('archive restore', export),
      ]) {
        db = '${dir.path}/${command.split(' ').first}.sqlite';
        await ok(command, {
          'source': source,
          'recoveryDestination': '${dir.path}/recovery-$command',
          'confirm': true,
        });
        equal(
          canonicalJson(await ok('diary day', {'date': day2})),
          canonicalJson(reference),
        );
      }
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
