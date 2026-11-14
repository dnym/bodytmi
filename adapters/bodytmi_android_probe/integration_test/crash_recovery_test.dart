import 'dart:io';

import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

/// Phase two of tool/crash_check.sh: after a force-stop, the profile must
/// reopen (the OS released the owner lock), hold only whole committed
/// revisions and accept further writes.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('a killed writer leaves a consistent, reopenable profile', (
    tester,
  ) async {
    final base = await getApplicationSupportDirectory();
    final path = '${base.path}/crash/profile.sqlite';
    expect(File(path).existsSync(), isTrue, reason: 'writer profile missing');
    final store = await TrainingStore.open(path);
    final revisions = await store.revisions();
    final numbers = [for (final r in revisions) r.number]..sort();
    expect(numbers.length, greaterThan(20));
    expect(numbers, List.generate(numbers.length, (i) => i + 1));
    final backup = await store.backup('${base.path}/crash/after-kill');
    expect(backup['databaseSchemaVersion'], 64);
    await StoredTrainingService(store)
        .publish(revisions.first.definition, numbers.length);
    await store.close();
    // ignore: avoid_print
    print('BODYTMI_RECOVERED revisions=${numbers.length}');
  });
}
