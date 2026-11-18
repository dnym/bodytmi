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

Map<String, Object?> _milk(String fat) => {
  'sourceId': 'milk',
  'name': 'Milk',
  'kind': 'base',
  'basis': '100ml',
  'source': {'kind': 'label'},
  'nutrients': {
    'energy': _q('60', 'kcal'),
    'protein': _q('3.4', 'g'),
    'fat': _q(fat, 'g'),
  },
  'density': {'mass': _q('103', 'g'), 'volume': _q('100', 'ml')},
};

Map<String, Object?> _foods(List<Map<String, Object?>> foods) => {
  'format': 'bodytmi-food-import/1',
  'source': {'namespace': 'oldapp', 'app': 'Old app'},
  'foods': foods,
};

final _bread = {
  'sourceId': 'bread',
  'id': 'bread',
  'name': 'Bread',
  'kind': 'base',
  'basis': '100g',
  'nutrients': {'energy': _q('250', 'kcal'), 'protein': _q('9', 'g')},
};

final _sandwich = {
  'sourceId': 'sandwich',
  'name': 'Sandwich',
  'kind': 'composite',
  'components': [
    {
      'food': {'sourceId': 'bread'},
      'amount': _q('60', 'g'),
    },
  ],
};

final _breakfast = {
  'sourceId': 'breakfast',
  'name': 'Breakfast',
  'kind': 'composite',
  'components': [
    {
      'food': {'sourceId': 'milk'},
      'amount': _q('200', 'ml'),
    },
    {
      'food': {'sourceId': 'sandwich'},
      'amount': {'portion': 'whole', 'count': '1'},
    },
  ],
};

void foodImportTests() {
  test(
    'food and diary imports: preview, apply, cascade, pins, portability',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-food-import-');
      var db = '${dir.path}/db.sqlite';

      Future<({int code, Map<String, Object?> body})> call(
        String name,
        Map<String, Object?> fields, {
        bool database = true,
      }) async {
        final r = await invoke(
          name.split(' '),
          jsonEncode({
            'schemaVersion': 1,
            if (database) 'database': db,
            ...fields,
          }),
        );
        final text = r.code == 0 ? r.output : r.error;
        return (code: r.code, body: jsonObject(jsonDecode(text), 'r'));
      }

      Future<Map<String, Object?>> ok(
        String name,
        Map<String, Object?> fields, {
        bool database = true,
      }) async {
        final r = await call(name, fields, database: database);
        check(r.code == 0, '$name: ${r.body}');
        return jsonObject(r.body['data'], 'data');
      }

      Future<void> fails(
        String name,
        Map<String, Object?> fields,
        int code, {
        bool database = true,
      }) async {
        final r = await call(name, fields, database: database);
        check(r.code == code, '$name: expected $code, got ${r.code} ${r.body}');
      }

      Map<String, Object?> statuses(Map<String, Object?> report, String key) =>
          jsonObject(
            jsonDecode(
              canonicalJson({
                for (final e in report[key]! as List)
                  (e as Map)['sourceId'] as String: e['status'],
              }),
            ),
            'statuses',
          );

      final milkId = importedId('oldapp', 'milk');
      final breakfastId = importedId('oldapp', 'breakfast');
      try {
        // Validation is pure: dependency order, unknown references, cycles.
        final doc = _foods([_breakfast, _sandwich, _bread, _milk('1.5')]);
        final valid = await ok('food import-validate', {
          'document': doc,
        }, database: false);
        equal(valid['foods'], 4);
        await fails(
          'food import-validate',
          {
            'document': _foods([_sandwich]),
          },
          2,
          database: false,
        );
        await fails(
          'food import-validate',
          {
            'document': _foods([
              {
                ..._sandwich,
                'components': [
                  {
                    'food': {'sourceId': 'sandwich'},
                    'amount': _q('1', 'g'),
                  },
                ],
              },
            ]),
          },
          2,
          database: false,
        );

        // Preview, confirmation, apply, idempotent reapply.
        final preview = await ok('food import-preview', {'document': doc});
        jsonEqual(preview['counts'], {
          'new': 4,
          'unchanged': 0,
          'changed': 0,
          'conflict': 0,
        });
        await fails('food import-apply', {'document': doc}, 2);
        final applied = await ok('food import-apply', {
          'document': doc,
          'confirm': true,
        });
        equal(applied['applied'], true);
        final again = await ok('food import-apply', {
          'document': doc,
          'confirm': true,
        });
        equal(jsonObject(again['counts'], 'c')['unchanged'], 4);
        final shown = jsonObject(
          (await ok('food show', {'foodId': breakfastId}))['food'],
          'food',
        );
        jsonEqual(shown['import'], {
          'namespace': 'oldapp',
          'sourceId': 'breakfast',
        });
        jsonEqual(
          jsonObject((shown['components']! as List).first, 'c')['food'],
          {'id': milkId, 'revision': 1},
        );

        // A diary logged against the imported breakfast, pinned to revision 1.
        final diary = {
          'format': 'bodytmi-diary-import/1',
          'source': {'namespace': 'oldapp'},
          'entries': [
            {
              'sourceId': 'e1',
              'at': '2026-11-02T07:30:00+01:00',
              'meal': 'breakfast',
              'food': {'namespace': 'oldapp', 'sourceId': 'breakfast'},
              'amount': {'portion': 'whole', 'count': '1'},
            },
            {
              'sourceId': 'e2',
              'at': '2026-11-03T01:00:00+01:00',
              'quick': {'energy': _q('300', 'kcal')},
            },
            {
              'sourceId': 'e3',
              'at': '2026-11-02T12:00:00+01:00',
              'food': {'id': 'bread', 'revision': 1},
              'amount': _q('100', 'g'),
            },
          ],
          'days': [
            {'date': '2026-11-02', 'status': 'complete'},
          ],
        };
        final dv = await ok('diary import-validate', {
          'document': diary,
        }, database: false);
        equal(dv['entries'], 3);
        final dp = await ok('diary import-preview', {'document': diary});
        jsonEqual(dp['counts'], {
          'new': 3,
          'unchanged': 0,
          'changed': 0,
          'conflict': 0,
        });
        // The 01:00 snack belongs to the evening before (04:00 day start).
        final e2 = (dp['entries']! as List)
            .cast<Map<String, Object?>>()
            .firstWhere((e) => e['sourceId'] == 'e2');
        equal(e2['date'], '2026-11-02');
        await ok('diary import-apply', {'document': diary, 'confirm': true});
        final day = await ok('diary day', {'date': '2026-11-02'});
        equal(day['status'], 'complete');
        equal((day['entries']! as List).length, 3);

        // A changed component cascades to its composites only.
        final changedDoc = _foods([_breakfast, _sandwich, _bread, _milk('3')]);
        final cp = await ok('food import-preview', {'document': changedDoc});
        jsonEqual(statuses(cp, 'foods'), {
          'bread': 'unchanged',
          'breakfast': 'changed',
          'milk': 'changed',
          'sandwich': 'unchanged',
        });
        await fails('food import-apply', {
          'document': changedDoc,
          'confirm': true,
        }, 5);
        await ok('food import-apply', {
          'document': changedDoc,
          'confirm': true,
          'onChanged': 'update',
        });
        final v2 = jsonObject(
          (await ok('food show', {'foodId': breakfastId}))['food'],
          'food',
        );
        jsonEqual(jsonObject((v2['components']! as List).first, 'c')['food'], {
          'id': milkId,
          'revision': 2,
        });
        // The logged diary keeps its pinned revision and totals.
        final day2 = await ok('diary day', {'date': '2026-11-02'});
        equal(canonicalJson(day2['totals']), canonicalJson(day['totals']));
        final da = await ok('diary import-apply', {
          'document': diary,
          'confirm': true,
        });
        equal(jsonObject(da['counts'], 'c')['unchanged'], 3);
        equal(jsonObject(da['dayCounts'], 'c')['unchanged'], 1);

        // Absent foods are reported and kept.
        final partial = await ok('food import-preview', {
          'document': _foods([_milk('3')]),
        });
        // bread has an explicit id but is still this namespace's food.
        jsonEqual(partial['absent'], ['bread', 'breakfast', 'sandwich']);

        // Conflicts: an id owned by another food; nothing is written.
        await ok('food publish', {
          'food': {
            'id': 'own',
            'name': 'Own',
            'kind': 'base',
            'basis': '100g',
            'nutrients': {'energy': _q('1', 'kcal')},
          },
          'expectedRevision': 0,
        });
        final clash = _foods([
          {..._bread, 'sourceId': 'other', 'id': 'own'},
          {
            ..._sandwich,
            'sourceId': 'other-sandwich',
            'components': [
              {
                'food': {'sourceId': 'other'},
                'amount': _q('1', 'g'),
              },
            ],
          },
        ]);
        final cl = await ok('food import-preview', {'document': clash});
        jsonEqual(statuses(cl, 'foods'), {
          'other': 'conflict',
          'other-sandwich': 'conflict',
        });
        await fails('food import-apply', {
          'document': clash,
          'confirm': true,
        }, 5);
        await fails('food show', {
          'foodId': importedId('oldapp', 'other-sandwich'),
        }, 3);

        // A diary entry naming a food that was never imported is a conflict.
        final missing = {
          ...diary,
          'entries': [
            {
              'sourceId': 'e9',
              'at': '2026-11-04T08:00:00+01:00',
              'food': {'namespace': 'oldapp', 'sourceId': 'nothing'},
              'amount': _q('1', 'g'),
            },
          ],
          'days': [
            {'date': '2026-11-02', 'status': 'partial'},
          ],
        };
        final mp = await ok('diary import-preview', {'document': missing});
        equal(statuses(mp, 'entries')['e9'], 'conflict');
        jsonEqual(
          jsonObject((mp['days']! as List).first, 'd')['status'],
          'changed',
        );
        await fails('diary import-apply', {
          'document': missing,
          'confirm': true,
        }, 5);
        equal(
          (await ok('diary day', {'date': '2026-11-02'}))['status'],
          'complete',
        );

        // Both portability formats keep the import provenance.
        final backup = '${dir.path}/backup';
        await ok('backup create', {'destination': backup});
        final export = '${dir.path}/export.json';
        await ok('archive export', {'destination': export});
        final reference = await ok('diary day', {'date': '2026-11-02'});
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
            canonicalJson(await ok('diary day', {'date': '2026-11-02'})),
            canonicalJson(reference),
          );
          final re = await ok('food import-apply', {
            'document': changedDoc,
            'confirm': true,
          });
          equal(jsonObject(re['counts'], 'c')['unchanged'], 4);
        }
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
