import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// How the profile is locked (D24: locking is optional).
enum LockMode {
  /// A plain SQLite profile.
  none,

  /// Encrypted with a passphrase asked for when the app opens.
  passphrase,

  /// Encrypted with a random key kept in the phone's keystore and released
  /// by fingerprint or screen lock.
  device,
}

/// The lock mode, kept beside the profile as `<profile>.lock.json`. It holds
/// no secret; it only says how to unlock. The database header is the truth
/// about whether the file is encrypted.
final class LockSettings {
  const LockSettings._();

  static File _file(String profile) => File('$profile.lock.json');

  static Future<Map<String, Object?>> _json(String profile) async {
    final file = _file(profile);
    if (!await file.exists()) return {};
    try {
      final json = jsonDecode(await file.readAsString());
      return json is Map<String, Object?> ? json : {'mode': 'passphrase'};
    } on FormatException {
      return {'mode': 'passphrase'};
    }
  }

  static Future<LockMode> read(String profile) async {
    final json = await _json(profile);
    if (json.isEmpty) return LockMode.none;
    return LockMode.values.firstWhere(
      (m) => m.name == json['mode'],
      orElse: () => LockMode.passphrase,
    );
  }

  /// How long the app may be away before a locked profile locks again.
  static Future<Duration> relockAfter(String profile) async {
    final seconds = (await _json(profile))['relockAfterSeconds'];
    return relockChoices.contains(
          Duration(seconds: seconds is int ? seconds : -1),
        )
        ? Duration(seconds: seconds! as int)
        : defaultRelockAfter;
  }

  static Future<void> write(String profile, LockMode mode) =>
      _update(profile, {'mode': mode.name});

  static Future<void> writeRelockAfter(String profile, Duration after) {
    if (!relockChoices.contains(after)) {
      invalid('Choose one of the offered re-lock times.');
    }
    return _update(profile, {'relockAfterSeconds': after.inSeconds});
  }

  static Future<void> _update(
    String profile,
    Map<String, Object?> fields,
  ) async {
    final file = _file(profile);
    final json = {...await _json(profile), 'schemaVersion': 1, ...fields};
    json.putIfAbsent('mode', () => LockMode.none.name);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(json), flush: true);
    await temp.rename(file.path);
  }
}

/// Offered re-lock delays after the app leaves the screen.
const relockChoices = [
  Duration.zero,
  Duration(minutes: 1),
  Duration(minutes: 5),
  Duration(minutes: 15),
  Duration(hours: 1),
];
const defaultRelockAfter = Duration(minutes: 5);

/// Measures time away from the app with both the wall clock and a monotonic
/// stopwatch, and counts the larger: a monotonic clock may stop in deep
/// sleep, and the wall clock can be changed.
final class AwayTimer {
  AwayTimer({DateTime Function()? now}) : _now = now ?? DateTime.now;
  final DateTime Function() _now;
  final _watch = Stopwatch();
  DateTime? _leftAt;

  bool get away => _leftAt != null;

  void left() {
    if (_leftAt != null) return;
    _leftAt = _now();
    _watch
      ..reset()
      ..start();
  }

  /// Time away, then forgets it.
  Duration returned() {
    final left = _leftAt;
    _leftAt = null;
    _watch.stop();
    if (left == null) return Duration.zero;
    final wall = _now().difference(left);
    return wall > _watch.elapsed ? wall : _watch.elapsed;
  }
}

/// Where a device-unlock key lives.
abstract interface class DeviceKeyStore {
  /// The stored key, after the user authenticates; null when absent.
  Future<String?> read();
  Future<void> write(String key);
  Future<void> delete();
}

/// The Android keystore: an AES key that requires fingerprint or device
/// credential for every use wraps the profile key. Errors never reset the
/// store (the plugin's default would silently delete the key, making the
/// profile unreadable).
final class KeystoreDeviceKeyStore implements DeviceKeyStore {
  KeystoreDeviceKeyStore()
    : _storage = const FlutterSecureStorage(
        aOptions: AndroidOptions.biometric(
          enforceBiometrics: true,
          requireBiometricsPerOperation: true,
          resetOnError: false,
          // Migration preserves an existing key; never reset (delete) it.
          migrateOnAlgorithmChange: true,
          storageNamespace: 'bodytmi-profile-key',
          biometricPromptTitle: 'Unlock BodyTMI',
          biometricPromptSubtitle: 'Your health data is locked',
          biometricPromptNegativeButton: 'Cancel',
        ),
      );

  final FlutterSecureStorage _storage;
  static const _name = 'profile-key';

  @override
  Future<String?> read() => _guard(() => _storage.read(key: _name));

  @override
  Future<void> write(String key) =>
      _guard(() => _storage.write(key: _name, value: key));

  @override
  Future<void> delete() => _guard(() => _storage.delete(key: _name));

  static Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on Exception catch (e) {
      final detail = '$e'.split('\n').first;
      throw BodyTmiException(
        'locked',
        'Device unlock failed or was cancelled. A screen lock (PIN, pattern '
            'or password) must be set on the phone. '
            '(${detail.length > 160 ? '${detail.substring(0, 160)}…' : detail})',
      );
    }
  }
}

/// A new random device key: 32 bytes as base64url text.
String newDeviceKey() {
  final random = Random.secure();
  return base64Url.encode([for (var i = 0; i < 32; i++) random.nextInt(256)]);
}

/// Whether the profile file at [path] is encrypted.
bool profileEncrypted(String path) =>
    databaseFileState(path) == DatabaseFileState.encrypted;
