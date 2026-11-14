import 'dart:convert';
import 'dart:io';

import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

Future<Map<String, Object?>> _asset(String name) async =>
    jsonDecode(await rootBundle.loadString('assets/$name.json'))
        as Map<String, Object?>;

Future<Directory> _fresh(String name) async {
  final base = await getApplicationSupportDirectory();
  final dir = Directory('${base.path}/$name');
  if (dir.existsSync()) await dir.delete(recursive: true);
  return dir..createSync(recursive: true);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the unmodified storage stack runs in an Android app', (
    tester,
  ) async {
    final dir = await _fresh('probe');
    // Report the platform facts the storage layer relies on.
    // ignore: avoid_print
    print(
      'BODYTMI_PROBE platform=${Platform.operatingSystem} '
      'version=${Platform.operatingSystemVersion} '
      'support=${dir.path} systemTemp=${Directory.systemTemp.path}',
    );
    final path = '${dir.path}/profile.sqlite';
    final definition = WorkoutDefinition.fromJson(
      (await _asset('upper-a'))['definition'],
    );

    var store = await TrainingStore.open(path);
    final service = StoredTrainingService(store);
    await service.publish(definition, 0);
    var session = await service.start(
      'android-session',
      definition.id,
      1,
      DateTime.utc(2026, 11, 14, 12),
    );
    for (final set in session.sets) {
      session = await service.edit(
        session.id,
        session.contentVersion,
        (s) => const TrainingService().complete(
          s,
          set.id,
          const {},
          acceptSuggested: true,
        ),
      );
    }
    session = await service.edit(
      session.id,
      session.contentVersion,
      (s) => s.finish(DateTime.utc(2026, 11, 14, 13)),
    );
    expect(session.status, SessionStatus.finalized);

    // A second owner in the same process is refused while the first is open.
    Object? contention;
    try {
      await TrainingStore.open(path);
    } catch (error) {
      contention = error;
    }
    expect(contention, isA<BodyTmiException>());

    final before = canonicalJson((await store.archive()).toJson());
    await store.close();

    // Committed writes survive closing and reopening the profile.
    store = await TrainingStore.open(path);
    expect(canonicalJson((await store.archive()).toJson()), before);

    // Neutral history import (identical replay is a no-op).
    final document = HistoryImportDocument.fromJson(
      (await _asset('history-import'))['document'],
    );
    final imports = HistoryImportService(store);
    Future<Map<String, Object?>> apply() => imports.apply(
      document,
      at: DateTime.utc(2026, 11, 14, 14),
      atText: '2026-11-14T14:00:00Z',
      onChanged: 'reject',
      confirm: true,
    );
    await apply();
    final replay = await apply();
    expect(
      (replay['counts']! as Map)['sessions'],
      containsPair('unchanged', 2),
    );
    final withImports = canonicalJson((await store.archive()).toJson());

    // Native backup: consistent online snapshot, validation and restore.
    final manifest = await store.backup('${dir.path}/native');
    expect(manifest['databaseSchemaVersion'], 64);
    expect(
      NativeBackup.validateDatabase('${dir.path}/native/database.sqlite'),
      64,
    );
    // Logical export: canonical JSON, staged SQLite rebuild in systemTemp.
    final exported = await LogicalArchiveFiles.export(
      await store.archive(),
      '${dir.path}/logical.json',
    );
    expect(exported['format'], 'bodytmi-logical-export/64');
    await store.close();

    final restoredPath = '${dir.path}/restored.sqlite';
    var restored = await TrainingStore.open(restoredPath);
    final native = await NativeBackup.prepare('${dir.path}/native');
    try {
      await restored.restore(
        native,
        recoveryDestination: '${dir.path}/recovery-native',
        confirm: true,
      );
    } finally {
      await native.close();
    }
    await restored.close();
    restored = await TrainingStore.open(restoredPath);
    expect(canonicalJson((await restored.archive()).toJson()), withImports);
    await restored.close();

    final logicalPath = '${dir.path}/logical.sqlite';
    var logicalStore = await TrainingStore.open(logicalPath);
    final logical = await LogicalArchiveFiles.prepare(
      '${dir.path}/logical.json',
    );
    try {
      await logicalStore.restore(
        logical.backup,
        recoveryDestination: '${dir.path}/recovery-logical',
        confirm: true,
      );
    } finally {
      await logical.close();
    }
    await logicalStore.close();
    logicalStore = await TrainingStore.open(logicalPath);
    expect(canonicalJson((await logicalStore.archive()).toJson()), withImports);
    await logicalStore.close();
  });
}
