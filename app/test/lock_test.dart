import 'dart:io';

import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_app/src/app.dart';
import 'package:bodytmi_app/src/lock.dart';
import 'package:bodytmi_app/src/profile.dart';
import 'package:bodytmi_app/src/unlock.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

final class FakeKeyStore implements DeviceKeyStore {
  String? key;
  bool failWrites = false;
  int reads = 0;

  @override
  Future<String?> read() async {
    reads++;
    return key;
  }

  @override
  Future<void> write(String value) async {
    if (failWrites) {
      throw const BodyTmiException('locked', 'Device unlock failed.');
    }
    key = value;
  }

  @override
  Future<void> delete() async => key = null;
}

void main() {
  relockTests();
  final clock = DateTime(2026, 11, 18, 9, 30);
  late Directory dir;
  late String path;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('bodytmi-lock-');
    path = '${dir.path}/p.sqlite';
    await buildDemoProfile(path, now: clock);
  });
  tearDown(() => dir.delete(recursive: true));

  Future<int> massCount(ProfileClient p) async =>
      (await p.call<List<Object?>>('mass list', {'context': 'health'})).length;

  test('passphrase, change, device and none round trip', () async {
    final keys = FakeKeyStore();
    final p = await ProfileClient.open(path, keyStore: keys);
    final count = await massCount(p);
    expect(profileEncrypted(path), isFalse);

    await p.setLock(LockMode.passphrase, passphrase: 'correct horse');
    expect(profileEncrypted(path), isTrue);
    expect(await LockSettings.read(path), LockMode.passphrase);
    expect(await massCount(p), count);
    // Backups made by the app are encrypted with the profile key.
    final backup = await p.call<Map<String, Object?>>('backup create', {
      'destination': '${dir.path}/backup',
    });
    expect(backup['encrypted'], isTrue);
    await expectLater(
      p.setLock(LockMode.passphrase, passphrase: 'short'),
      throwsA(isA<BodyTmiException>()),
    );

    await p.setLock(LockMode.passphrase, passphrase: 'another passphrase');
    await p.close();
    await expectLater(
      ProfileClient.open(path, key: ProfileKey.fromText('correct horse')),
      throwsA(isA<BodyTmiException>()),
    );
    final again = await ProfileClient.open(
      path,
      key: ProfileKey.fromText('another passphrase'),
      keyStore: keys,
    );
    expect(await massCount(again), count);

    await again.setLock(LockMode.device);
    expect(keys.key, isNotNull);
    expect(await LockSettings.read(path), LockMode.device);
    expect(profileEncrypted(path), isTrue);
    await again.close();
    final device = await ProfileClient.open(
      path,
      key: ProfileKey.fromText(keys.key!),
      lock: LockMode.device,
      keyStore: keys,
    );
    expect(await massCount(device), count);

    await device.setLock(LockMode.none);
    expect(profileEncrypted(path), isFalse);
    expect(keys.key, isNull, reason: 'leaving device unlock forgets the key');
    expect(await LockSettings.read(path), LockMode.none);
    expect(await massCount(device), count);
    await device.close();
  });

  test('a failed keystore write leaves the profile as it was', () async {
    final keys = FakeKeyStore()..failWrites = true;
    final p = await ProfileClient.open(path, keyStore: keys);
    await expectLater(
      p.setLock(LockMode.device),
      throwsA(isA<BodyTmiException>()),
    );
    expect(profileEncrypted(path), isFalse);
    expect(p.lock, LockMode.none);
    expect(await massCount(p), greaterThan(0));
    await p.close();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('the unlock screen refuses a wrong passphrase, then opens', (
    tester,
  ) async {
    final keys = FakeKeyStore();
    await tester.runAsync(() async {
      final p = await ProfileClient.open(path, keyStore: keys);
      await p.setLock(LockMode.passphrase, passphrase: 'correct horse');
      await p.close();
    });
    await tester.binding.setSurfaceSize(const Size(420, 2400));
    await tester.pumpWidget(
      BodyTmiRoot(path: path, keyStore: keys, clock: clock),
    );
    await settle(tester);
    expect(find.text('BodyTMI is locked'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'wrong passphrase');
    await tester.tap(find.text('Unlock with passphrase'));
    await settle(tester);
    expect(find.textContaining('Wrong passphrase'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'correct horse');
    await tester.tap(find.text('Unlock with passphrase'));
    await settle(tester);
    await waitFor(tester, find.text('BODY MASS TREND'));
    await tester.runAsync(() async {
      // Release the profile before tearDown deletes it.
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('device unlock opens without a passphrase', (tester) async {
    final keys = FakeKeyStore();
    await tester.runAsync(() async {
      final p = await ProfileClient.open(path, keyStore: keys);
      await p.setLock(LockMode.device);
      await p.close();
    });
    await tester.binding.setSurfaceSize(const Size(420, 2400));
    await tester.pumpWidget(
      BodyTmiRoot(path: path, keyStore: keys, clock: clock),
    );
    await settle(tester);
    expect(keys.reads, 1);
    await waitFor(tester, find.text('BODY MASS TREND'));
  });

  Future<void> leave(WidgetTester tester) async {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await settle(tester);
  }

  Future<void> back(WidgetTester tester) async {
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await settle(tester);
  }

  testWidgets('a locked profile locks again after time away', (tester) async {
    final keys = FakeKeyStore();
    var wall = DateTime(2026, 11, 18, 9, 30);
    await tester.runAsync(() async {
      final p = await ProfileClient.open(path, keyStore: keys);
      await p.setLock(LockMode.passphrase, passphrase: 'correct horse');
      await p.close();
    });
    await tester.binding.setSurfaceSize(const Size(420, 2400));
    await tester.pumpWidget(
      BodyTmiRoot(path: path, keyStore: keys, clock: clock, now: () => wall),
    );
    await settle(tester);
    Future<void> unlock() async {
      await tester.enterText(find.byType(TextField), 'correct horse');
      await tester.tap(find.text('Unlock with passphrase'));
      await waitFor(tester, find.text('BODY MASS TREND'));
    }

    await unlock();
    // One minute away with the five-minute default: still open.
    await leave(tester);
    wall = wall.add(const Duration(minutes: 1));
    await back(tester);
    expect(find.text('BODY MASS TREND'), findsOneWidget);
    // Ten minutes away: locked, the profile closed and the key forgotten.
    await leave(tester);
    wall = wall.add(const Duration(minutes: 10));
    await back(tester);
    await waitFor(tester, find.text('BodyTMI is locked'));
    await unlock();
    await tester.runAsync(() async => tester.pumpWidget(const SizedBox()));
  });

  testWidgets('Immediately locks as soon as the app leaves', (tester) async {
    final keys = FakeKeyStore();
    await tester.runAsync(() async {
      final p = await ProfileClient.open(path, keyStore: keys);
      await p.setLock(LockMode.device);
      await p.setRelockAfter(Duration.zero);
      await p.close();
    });
    await tester.binding.setSurfaceSize(const Size(420, 2400));
    await tester.pumpWidget(
      BodyTmiRoot(path: path, keyStore: keys, clock: clock),
    );
    await waitFor(tester, find.text('BODY MASS TREND'));
    await leave(tester);
    await waitFor(tester, find.text('BodyTMI is locked'));
    // Returning prompts for device unlock again.
    await back(tester);
    await waitFor(tester, find.text('BODY MASS TREND'));
    expect(keys.reads, 2);
    await tester.runAsync(() async => tester.pumpWidget(const SizedBox()));
  });

  testWidgets('an unlocked profile never locks', (tester) async {
    var wall = DateTime(2026, 11, 18, 9, 30);
    await tester.binding.setSurfaceSize(const Size(420, 2400));
    await tester.pumpWidget(
      BodyTmiRoot(
        path: path,
        keyStore: FakeKeyStore(),
        clock: clock,
        now: () => wall,
      ),
    );
    await waitFor(tester, find.text('BODY MASS TREND'));
    await leave(tester);
    wall = wall.add(const Duration(hours: 5));
    await back(tester);
    expect(find.text('BODY MASS TREND'), findsOneWidget);
    await tester.runAsync(() async => tester.pumpWidget(const SizedBox()));
  });

  testWidgets('More sets a passphrase after confirmation', (tester) async {
    final keys = FakeKeyStore();
    late ProfileClient p;
    await tester.runAsync(() async {
      p = await ProfileClient.open(path, keyStore: keys);
    });
    await tester.binding.setSurfaceSize(const Size(420, 2400));
    await tester.pumpWidget(BodyTmiApp(profile: p, clock: clock));
    await settle(tester);
    await tester.tap(find.text('More'));
    await settle(tester);
    await tester.tap(find.text('Passphrase'));
    await settle(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Passphrase'),
      'correct horse',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Repeat passphrase'),
      'correct horsf',
    );
    await tester.tap(find.text('Lock'));
    await settle(tester);
    expect(find.text('The passphrases differ.'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Repeat passphrase'),
      'correct horse',
    );
    await tester.tap(find.text('Lock'));
    await waitFor(tester, find.text('Locked with a passphrase'));
    expect(profileEncrypted(path), isTrue);
    expect(find.text('Change passphrase'), findsOneWidget);
    // Close outside runAsync: running app commands finish only while pumped.
    var closed = false;
    p.close().then((_) => closed = true);
    for (var i = 0; i < 100 && !closed; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(closed, isTrue);
  });
}

void relockTests() {
  test('time away counts the larger of wall clock and stopwatch', () async {
    var wall = DateTime(2026, 11, 18, 9);
    final timer = AwayTimer(now: () => wall);
    timer.left();
    wall = wall.add(const Duration(minutes: 10));
    expect(timer.returned(), greaterThanOrEqualTo(const Duration(minutes: 10)));
    // A clock set back does not shorten the time away below the stopwatch.
    timer.left();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    wall = wall.subtract(const Duration(hours: 2));
    expect(
      timer.returned(),
      greaterThanOrEqualTo(const Duration(milliseconds: 30)),
    );
    expect(timer.returned(), Duration.zero, reason: 'not away any more');
  });

  test('re-lock time is kept beside the mode', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-relock-');
    final path = '${dir.path}/p.sqlite';
    expect(await LockSettings.relockAfter(path), defaultRelockAfter);
    await LockSettings.write(path, LockMode.passphrase);
    await LockSettings.writeRelockAfter(path, const Duration(minutes: 15));
    expect(await LockSettings.read(path), LockMode.passphrase);
    expect(await LockSettings.relockAfter(path), const Duration(minutes: 15));
    expect(
      () => LockSettings.writeRelockAfter(path, const Duration(minutes: 7)),
      throwsA(isA<BodyTmiException>()),
    );
    await dir.delete(recursive: true);
  });
}

/// Pumps until [finder] matches, failing after about ten seconds.
Future<void> waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 200; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsWidgets);
}
