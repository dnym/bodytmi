import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_app/src/app.dart';
import 'package:bodytmi_app/src/backup.dart';
import 'package:bodytmi_app/src/lock.dart';
import 'package:bodytmi_app/src/profile.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'lock_test.dart' show FakeKeyStore, waitFor;

final class FakeTransfer implements FileTransfer {
  String? savedName;
  Uint8List? saved;

  @override
  Future<bool> save(String name, Uint8List bytes) async {
    savedName = name;
    saved = bytes;
    return true;
  }

  @override
  Future<Uint8List?> pick() async => saved;
}

void main() {
  final clock = DateTime(2026, 11, 18, 9, 30);
  late Directory dir;
  late String path;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('bodytmi-backup-');
    path = '${dir.path}/p.sqlite';
    await buildDemoProfile(path, now: clock);
  });
  tearDown(() => dir.delete(recursive: true));

  Future<int> massCount(ProfileClient p) async =>
      (await p.call<List<Object?>>('mass list', {'context': 'health'})).length;

  Future<void> addMass(ProfileClient p, String id) => p.write('mass record', {
    'measurement': {
      'id': id,
      'context': 'health',
      'observedAt': '2026-11-18T09:00:00+01:00',
      'mass': {'value': '80', 'unit': 'kg'},
    },
  });

  test('plain and encrypted exports; restore keeps the profile lock', () async {
    final p = await ProfileClient.open(path, keyStore: FakeKeyStore());
    final count = await massCount(p);
    final plain = await p.exportArchive();
    expect(
      utf8.decode(plain.bytes),
      contains('"format":"bodytmi-logical-export/1"'),
    );
    final sealed = await p.exportArchive(passphrase: 'export passphrase');
    expect(
      EncryptedFile.recognises(jsonDecode(utf8.decode(sealed.bytes))),
      isTrue,
    );
    expect(utf8.decode(sealed.bytes), isNot(contains('body-mass')));
    expect(
      () => p.exportArchive(passphrase: 'short'),
      throwsA(isA<BodyTmiException>()),
    );
    final file = File('${dir.path}/sealed.json')
      ..writeAsBytesSync(sealed.bytes);
    await expectLater(
      p.inspectExport(file.path),
      throwsA(isA<BodyTmiException>()),
    );
    await expectLater(
      p.inspectExport(file.path, passphrase: 'wrong passphrase'),
      throwsA(isA<BodyTmiException>()),
    );
    final summary = await p.inspectExport(
      file.path,
      passphrase: 'export passphrase',
    );
    expect(summary['encrypted'], isTrue);

    // Lock the profile, change it, then restore the earlier export.
    await p.setLock(LockMode.passphrase, passphrase: 'profile passphrase');
    await addMass(p, 'extra');
    expect(await massCount(p), count + 1);
    await p.restoreExport(
      file.path,
      passphrase: 'export passphrase',
      recoveryDestination: '${dir.path}/recovery/one',
    );
    expect(await massCount(p), count);
    expect(profileEncrypted(path), isTrue, reason: 'keeps its own lock');
    expect(
      File('${dir.path}/recovery/one/database.sqlite').existsSync(),
      isTrue,
    );
    await p.close();
    final reopened = await ProfileClient.open(
      path,
      key: ProfileKey.fromText('profile passphrase'),
    );
    expect(await massCount(reopened), count);
    await reopened.close();
  });

  testWidgets('More exports encrypted and restores it', (tester) async {
    final transfer = FakeTransfer();
    fileTransfer = transfer;
    late ProfileClient p;
    late int count;
    await tester.runAsync(() async {
      p = await ProfileClient.open(path, keyStore: FakeKeyStore());
      count = await massCount(p);
    });
    await tester.binding.setSurfaceSize(const Size(420, 3000));
    await tester.pumpWidget(BodyTmiApp(profile: p, clock: clock));
    await waitFor(tester, find.text('BODY MASS TREND'));
    await tester.tap(find.text('More'));
    await waitFor(tester, find.text('Export…'));
    await tester.tap(find.text('Export…'));
    await waitFor(tester, find.text('Encrypt with a passphrase'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Passphrase'),
      'export passphrase',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Repeat passphrase'),
      'export passphrase',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Export'));
    await waitFor(tester, find.textContaining('Encrypted export saved'));
    expect(transfer.savedName, endsWith('-encrypted.json'));

    var added = false;
    final adding = addMass(p, 'extra').then((_) => added = true);
    for (var i = 0; i < 100 && !added; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await adding;

    await tester.tap(find.text('Restore from export…'));
    await waitFor(tester, find.text('Encrypted export'));
    await tester.enterText(find.byType(TextField).last, 'export passphrase');
    await tester.tap(find.text('Open'));
    await waitFor(tester, find.text('Replace this profile?'));
    await tester.tap(find.widgetWithText(FilledButton, 'Replace'));
    await waitFor(tester, find.textContaining('Restored.'));
    var restored = -1;
    final counting = massCount(p).then((n) => restored = n);
    for (var i = 0; i < 100 && restored < 0; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    await counting;
    expect(restored, count);
    var closed = false;
    p.close().then((_) => closed = true);
    for (var i = 0; i < 100 && !closed; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  });
}
