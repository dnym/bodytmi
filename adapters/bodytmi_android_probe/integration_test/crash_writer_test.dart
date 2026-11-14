import 'dart:convert';
import 'dart:io';

import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

/// Phase one of tool/crash_check.sh: commit revisions continuously until the
/// host force-stops the app process. It is expected to never finish.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('writer commits until the process is killed', (tester) async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/crash');
    if (dir.existsSync()) await dir.delete(recursive: true);
    dir.createSync(recursive: true);
    final definition = WorkoutDefinition.fromJson(
      (jsonDecode(await rootBundle.loadString('assets/upper-a.json'))
          as Map<String, Object?>)['definition'],
    );
    final store = await TrainingStore.open('${dir.path}/profile.sqlite');
    final service = StoredTrainingService(store);
    final deadline = DateTime.now().add(const Duration(minutes: 5));
    for (var n = 0; DateTime.now().isBefore(deadline); n++) {
      await service.publish(definition, n);
      // ignore: avoid_print
      if (n == 20) print('BODYTMI_WRITER_READY');
    }
    fail('The host did not stop the writer.');
  }, timeout: const Timeout(Duration(minutes: 6)));
}
