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

  static Future<LockMode> read(String profile) async {
    final file = _file(profile);
    if (!await file.exists()) return LockMode.none;
    try {
      final json = jsonDecode(await file.readAsString());
      final name = (json as Map)['mode'];
      return LockMode.values.firstWhere(
        (m) => m.name == name,
        orElse: () => LockMode.passphrase,
      );
    } on FormatException {
      return LockMode.passphrase;
    }
  }

  static Future<void> write(String profile, LockMode mode) async {
    final file = _file(profile);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode({'schemaVersion': 1, 'mode': mode.name}),
      flush: true,
    );
    await temp.rename(file.path);
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
