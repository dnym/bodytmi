import 'dart:convert';

import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'body_mass_test.dart';
import 'cli_test.dart' show invoke;
import 'double_progression_test.dart';
import 'support.dart';

void nextFeaturesCliTests() {
  test(
    'CLI mass trend and resolve return the specified versioned snapshots',
    () async {
      final request = <String, Object?>{
        'schemaVersion': 1,
        'context': 'health',
        'asOf': '2026-10-10T12:00:00Z',
        'measurements': exampleMasses().map((m) => m.toJson()).toList(),
      };
      final trend = await invoke(['measurement', 'trend'], jsonEncode(request));
      equal(trend.code, 0);
      equal(trend.error, '');
      final data = jsonObject(
        jsonObject(jsonDecode(trend.output), 'response')['data'],
        'data',
      );
      final days = data['days']! as List<Object?>;
      final last = jsonObject(days.last, 'day');
      equal(jsonObject(last['trend'], 'quantity')['value'], '86.2');
      final resolved = await invoke(
        ['measurement', 'resolve'],
        jsonEncode({
          ...request,
          'override': {'measurementId': 'm8'},
        }),
      );
      equal(resolved.code, 0);
      equal(resolved.error, '');
      final mass = jsonObject(
        jsonObject(jsonDecode(resolved.output), 'response')['data'],
        'data',
      );
      equal(mass['source'], 'measurement');
      equal(jsonObject(mass['mass'], 'mass')['value'], '88');
    },
  );
  test('CLI double-progression advances every set target', () async {
    final result = await invoke(
      ['progression', 'double'],
      jsonEncode({
        'schemaVersion': 1,
        'rule': doubleRuleJson(),
        'currentSets': workingSets(['8', '8', '8']).map(metricsToJson).toList(),
        'results': workingSets(['8', '8', '8']).map(metricsToJson).toList(),
      }),
    );
    equal(result.code, 0);
    equal(result.error, '');
    final data = jsonObject(
      jsonObject(jsonDecode(result.output), 'response')['data'],
      'data',
    );
    equal(data['outcome'], 'increaseObjective');
    final sets = data['nextSets']! as List<Object?>;
    for (final set in sets) {
      equal(jsonObject(jsonObject(set, 'set')['reps'], 'reps')['value'], '9');
    }
  });
  test(
    'new CLI commands reject invalid schema/configuration without internal errors',
    () async {
      final result = await invoke(
        ['measurement', 'resolve'],
        jsonEncode({
          'schemaVersion': 1,
          'context': 'health',
          'asOf': '2026-10-10T12:00:00Z',
          'dailyMode': 'unknown',
          'measurements': <Object?>[],
        }),
      );
      equal(result.code, 2);
      equal(result.output, '');
      equal(
        jsonObject(
          jsonObject(jsonDecode(result.error), 'response')['error'],
          'error',
        )['code'],
        'validation',
      );
      rejects(
        () => const Commands().execute('progression double', {
          'schemaVersion': 1,
          'rule': doubleRuleJson(),
          'currentSets': <Object?>[],
          'results': <Object?>[],
          'state': {'cursor': 1},
        }),
      );
    },
  );
}
