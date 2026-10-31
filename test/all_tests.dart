import 'execution_test.dart';
import 'timing_test.dart';
import 'effective_mass_test.dart';
import 'session_body_mass_test.dart';
import 'stored_body_mass_test.dart';
import 'program_test.dart';
import 'stored_progression_test.dart';
import 'logical_archive_test.dart';
import 'backup_test.dart';
import 'storage_test.dart';
import 'activity_test.dart';
import 'body_mass_test.dart';
import 'double_progression_test.dart';
import 'next_features_cli_test.dart';
import 'cli_test.dart';
import 'progression_test.dart';
import 'quantity_test.dart';
import 'workflow_test.dart';

Future<void> main() async {
  executionTests();
  timingTests();
  effectiveMassTests();
  sessionBodyMassTests();
  storedBodyMassTests();
  programTests();
  storedProgressionTests();
  logicalArchiveTests();
  backupTests();
  storageTests();
  quantityTests();
  activityTests();
  workflowTests();
  progressionTests();
  cliTests();
  bodyMassTests();
  doubleProgressionTests();
  nextFeaturesCliTests();
}
