import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'cli_test.dart' show invoke;
import 'fixtures.dart';
import 'support.dart';

void continuousRunTests() {
  test('confirmOnTarget needs a target that stops at its target', () {
    final ok = EffortTimingDefaults.fromJson({
      'metric': 'duration',
      'confirmOnTarget': true,
    });
    check(ok.confirmOnTarget);
    jsonEqual(EffortTimingDefaults.fromJson(ok.toJson()).toJson(), ok.toJson());
    rejects(
      () => EffortTimingDefaults.fromJson({
        'metric': 'duration',
        'confirmOnTarget': true,
        'overrun': 'continue',
      }),
    );
    rejects(
      () => EffortTimingDefaults.fromJson({
        'metric': 'duration',
        'confirmOnTarget': true,
        'openEnded': true,
      }),
    );
    rejects(
      () => EffortTimingDefaults.fromJson({
        'metric': 'duration',
        'confirmOnTarget': false,
      }),
    );
  });

  test('run intervals confirm on target and continuous run walks the '
      'workout unattended', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-c25k-');
    final db = '${dir.path}/db.sqlite';
    try {
      Future<Map<String, Object?>> ok(
        String name,
        Map<String, Object?> fields,
      ) async {
        final r = await invoke(
          name.split(' '),
          jsonEncode({'schemaVersion': 1, 'database': db, ...fields}),
        );
        if (r.code != 0) throw StateError('$name: ${r.code} ${r.error}');
        return jsonObject(
          jsonObject(jsonDecode(r.output), 'response')['data'],
          'data',
        );
      }

      // Short intervals: 0.2 s runs, 1 s walks.
      final definition = copyJson(
        jsonObject(example('run-walk-intervals')['definition'], 'definition'),
      );
      final plan = jsonObject(definition['plan'], 'plan');
      plan['count'] = 3;
      plan['restBetweenSeconds'] = 1;
      jsonObject(
        jsonObject(jsonList(definition, 'slots').single, 'slot')['targets'],
        'targets',
      )['duration'] = {
        'value': '200',
        'unit': 'ms',
      };
      await ok('store publish', {
        'definition': definition,
        'expectedRevision': 0,
      });
      final session = await ok('store start', {
        'id': 's',
        'templateId': 'run-walk-intervals',
        'revision': 1,
        'startedAt': instant(1).toIso8601String(),
      });
      final started = await ok('execution start', {
        'id': 'x',
        'sessionId': 's',
        'at': instant(1).toIso8601String(),
      });
      final result = await ok('execution run', {
        'id': 'x',
        'expectedVersion': started['version'],
        'expectedSessionVersion': session['contentVersion'],
        'requestId': 'go',
        'at': instant(1).toIso8601String(),
        'continuous': true,
      });
      equal(result['continuous'], true);
      final execution = jsonObject(result['execution'], 'execution');
      equal(execution['status'], 'completed');
      final shown = await ok('store show', {'id': 's'});
      for (final set in jsonList(shown, 'sets')) {
        final row = jsonObject(set, 'set');
        equal(row['status'], 'completed');
        equal(
          jsonObject(jsonObject(row['timing'], 'timing'), 't')['termination'],
          'target',
        );
      }
      final receipts = jsonList(execution, 'receipts');
      equal(receipts.length, 5);
      for (final r in receipts.where(
        (r) => jsonObject(r, 'receipt')['kind'] == 'rest',
      ))
        check(
          (jsonObject(r, 'rest')['restElapsedMilliseconds']! as int) >= 1000,
        );
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
