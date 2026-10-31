// SDK-only test entrypoint. No network or Flutter installation is required.
import 'dart:io';

import 'activity_test.dart';
import 'body_mass_test.dart';
import 'double_progression_test.dart';
import 'next_features_cli_test.dart';
import 'cli_test.dart';
import 'progression_test.dart';
import 'quantity_test.dart';
import 'support.dart';
import 'workflow_test.dart';

Future<void> main() async {
  quantityTests();
  activityTests();
  workflowTests();
  progressionTests();
  cliTests();
  bodyMassTests();
  doubleProgressionTests();
  nextFeaturesCliTests();
  var failures = 0;
  for (final test in tests) {
    try {
      await test.body();
      stdout.writeln('PASS ${test.name}');
    } catch (error, stack) {
      failures++;
      stderr.writeln('FAIL ${test.name}\n$error\n$stack');
    }
  }
  stdout.writeln('${tests.length - failures}/${tests.length} tests passed.');
  if (failures != 0) exitCode = 1;
}
