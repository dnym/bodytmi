import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'cli_test.dart';
import 'fixtures.dart';
import 'support.dart';

/// Derived %TM plans over set-scheme variant workouts: one published plan
/// maps every branch; a session resolves only its selected branch.
void variantDerivedPlanTests() {
  test(
    'native CLI derives loads for the selected variant branch only',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-variant-plan-',
      );
      final path = '${dir.path}/db.sqlite';
      try {
        Future<({int code, Map<String, Object?>? data, String error})> cli(
          String name,
          Map<String, Object?> fields,
        ) async {
          final r = await invoke(
            name.split(' '),
            jsonEncode({'schemaVersion': 1, 'database': path, ...fields}),
          );
          return (
            code: r.code,
            error: r.error,
            data: r.code == 0
                ? jsonObject(
                    jsonObject(jsonDecode(r.output), 'response')['data'],
                    'data',
                  )
                : null,
          );
        }

        Future<Map<String, Object?>> ok(
          String name,
          Map<String, Object?> fields,
        ) async {
          final r = await cli(name, fields);
          if (r.code != 0) throw StateError('$name: ${r.error}');
          return r.data!;
        }

        await ok('store publish', {
          'definition': example('set-scheme-practice')['definition'],
          'expectedRevision': 0,
        });
        final graph = example('variant-derived-graph');
        await ok('graph publish', {
          'graph': graph['graph'],
          'expectedRevision': 0,
        });
        // A binding to an occurrence no branch declares is still rejected.
        final broken = copyJson(jsonObject(graph['graph'], 'graph'));
        broken['id'] = 'broken';
        final plan = jsonObject(jsonList(broken, 'plans').single, 'plan');
        plan['bindings'] = [
          {
            'occurrenceId': 'workout/quads[0]/quad',
            'metric': 'load',
            'nodeId': 'tm',
          },
        ];
        equal(
          (await cli('graph publish', {
            'graph': broken,
            'expectedRevision': 0,
          })).code,
          2,
        );

        final preview = await ok('graph plan-preview', {
          'graphId': 'squat-tm',
          'graphRevision': 1,
          'planId': 'by-scheme',
          'asOf': instant(1).toIso8601String(),
          'variants': {'scheme': 'doubles'},
        });
        final rows = jsonList(
          jsonObject(preview['preview'], 'preview'),
          'occurrences',
        );
        equal(rows.length, 6);
        jsonEqual(
          jsonObject(preview['preview'], 'preview')['variantSelections'],
          {'scheme': 'doubles'},
        );

        Future<List<String>> loads(Map<String, Object?> session) async => [
          for (final set in jsonList(session, 'sets'))
            jsonObject(
                  jsonObject(jsonObject(set, 's')['suggested'], 'sg')['load'],
                  'l',
                )['value']
                as String,
        ];
        const derivedPlan = {
          'graphId': 'squat-tm',
          'graphRevision': 1,
          'planId': 'by-scheme',
        };
        final triples = await ok('store start', {
          'id': 'triples',
          'templateId': 'squat-schemes',
          'revision': 1,
          'startedAt': instant(1).toIso8601String(),
          'derivedPlan': derivedPlan,
        });
        jsonEqual(await loads(triples), List.filled(5, '80'));
        final singles = await ok('store start', {
          'id': 'singles',
          'templateId': 'squat-schemes',
          'revision': 1,
          'startedAt': instant(2).toIso8601String(),
          'derivedPlan': derivedPlan,
          'variants': {
            'squat': {'scheme': 'singles'},
          },
        });
        jsonEqual(await loads(singles), List.filled(10, '90'));
        final frozen = jsonObject(
          jsonObject(
            jsonObject(singles['derivedPlanInput'], 'input')['snapshot'],
            'snapshot',
          )['preview'],
          'preview',
        );
        jsonEqual(frozen['variantSelections'], {'scheme': 'singles'});
        // Freshness checks recompute the same structure, so nothing changed.
        final status = await ok('store plan-status', {'id': 'singles'});
        equal(jsonObject(status['comparison'], 'comparison')['changed'], false);
        // Retried starts keep identity; archives revalidate frozen structure.
        final retried = await ok('store start', {
          'id': 'singles',
          'templateId': 'squat-schemes',
          'revision': 1,
          'startedAt': instant(2).toIso8601String(),
          'derivedPlan': derivedPlan,
          'variants': {
            'squat': {'scheme': 'singles'},
          },
        });
        equal(canonicalJson(retried), canonicalJson(singles));
        final export = await ok('archive export', {
          'destination': '${dir.path}/archive.json',
        });
        check(export['sha256'] is String);
        final validated = await invoke(
          ['archive', 'validate'],
          jsonEncode({
            'schemaVersion': 1,
            'source': '${dir.path}/archive.json',
          }),
        );
        equal(validated.code, 0);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
