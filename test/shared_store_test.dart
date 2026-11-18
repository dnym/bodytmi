import 'dart:io';

import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';

import 'support.dart';

void sharedStoreTests() {
  test('commands borrow a shared open store and never close it', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-shared-');
    final db = '${dir.path}/db.sqlite';
    final store = await TrainingStore.open(db);
    try {
      // Without sharing, a second open in this process is refused.
      try {
        await TrainingStore.open(db);
        throw StateError('Expected the profile to be in use.');
      } on BodyTmiException catch (e) {
        equal(e.code, 'in_use');
      }
      Future<Map<String, Object?>> run(
        String command,
        Map<String, Object?> f,
      ) => TrainingStore.sharing(
        store,
        () =>
            executeCommand(command, {'schemaVersion': 1, 'database': db, ...f}),
      );
      await run('mass record', {
        'measurement': {
          'id': 'm1',
          'context': 'health',
          'observedAt': '2026-11-18T07:00:00+01:00',
          'mass': {'value': '80', 'unit': 'kg'},
        },
      });
      final list = await run('mass list', {'context': 'health'});
      equal((list['data']! as List).length, 1);
      // The owner's handle still works after the commands closed theirs.
      equal((await store.bodyMassRecords()).length, 1);
      try {
        await run('profile set-passphrase', {
          'passphraseFile': '${dir.path}/missing',
          'confirm': true,
        });
        throw StateError('Expected a refusal.');
      } on BodyTmiException catch (e) {
        check(e.code == 'not_found' || e.code == 'in_use', e.code);
      }
      await File('${dir.path}/pw').writeAsString('long enough passphrase');
      try {
        await run('profile set-passphrase', {
          'passphraseFile': '${dir.path}/pw',
          'confirm': true,
        });
        throw StateError('Expected a refusal.');
      } on BodyTmiException catch (e) {
        equal(e.code, 'in_use');
      }
      equal((await store.bodyMassRecords()).length, 1);
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });

  test('the demo profile builds through the ordinary commands', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-demo-');
    final db = '${dir.path}/demo.sqlite';
    try {
      final now = DateTime(2026, 11, 18, 9, 30);
      await buildDemoProfile(db, now: now);
      final request = {'schemaVersion': 1, 'database': db};
      final day = await executeCommand('diary day', {
        ...request,
        'date': '2026-11-18',
      });
      // Lunch at 12:05 is after 09:30, so it is not logged.
      equal(((day['data']! as Map)['entries']! as List).length, 2);
      final runs = await executeCommand('run list', request);
      equal((runs['data']! as List).length, 1);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
