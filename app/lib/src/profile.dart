import 'dart:io';

import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:material_ui/material_ui.dart';

import 'lock.dart';

/// The open profile. Every read and write goes through the same JSON
/// commands as the CLI, borrowing this one long-lived store, so the GUI and
/// CLI cannot disagree about behaviour.
final class ProfileClient extends ChangeNotifier {
  ProfileClient._(this.path, this._store, this._key, this.lock, this.keyStore);

  final String path;
  TrainingStore _store;
  ProfileKey? _key;

  /// How this profile is locked.
  LockMode lock;

  /// Where a device-unlock key is kept.
  final DeviceKeyStore keyStore;

  /// Increases after every successful write, so screens reload.
  int revision = 0;

  /// Opens [path] with [key] (null for a plain profile).
  static Future<ProfileClient> open(
    String path, {
    ProfileKey? key,
    LockMode? lock,
    DeviceKeyStore? keyStore,
  }) async {
    final store = await withProfileKey(key, () => TrainingStore.open(path));
    return ProfileClient._(
      path,
      store,
      key,
      lock ?? (key == null ? LockMode.none : LockMode.passphrase),
      keyStore ?? KeystoreDeviceKeyStore(),
    );
  }

  /// Changes how the profile is locked. The profile is rewritten under the
  /// new key (or none) as one verified file replacement; on any failure it
  /// keeps its previous key and lock. A device key is stored before the
  /// rewrite and the previous device key removed only after it.
  Future<void> setLock(LockMode next, {String? passphrase}) async {
    final ProfileKey? nextKey;
    String? deviceKey;
    switch (next) {
      case LockMode.none:
        nextKey = null;
      case LockMode.passphrase:
        nextKey = ProfileKey.fromText(
          passphrase ?? invalid('A passphrase is required.'),
          newPassphrase: true,
        );
      case LockMode.device:
        deviceKey = newDeviceKey();
        nextKey = ProfileKey.fromText(deviceKey);
    }
    if (next == LockMode.none && _key == null) return;
    // Re-keying device to device would replace the only stored key before
    // the profile is rewritten; there is nothing to gain from it.
    if (next == LockMode.device && lock == LockMode.device) return;
    if (deviceKey != null) await keyStore.write(deviceKey);
    final previous = lock;
    await _store.close();
    try {
      await withProfileKey(_key, () async {
        final owner = await TrainingStore.open(path);
        try {
          await owner.changeKey(nextKey, confirm: true);
        } finally {
          await owner.close();
        }
      });
      _key = nextKey;
      lock = next;
      await LockSettings.write(path, next);
    } catch (_) {
      if (deviceKey != null && previous != LockMode.device) {
        await keyStore.delete();
      }
      rethrow;
    } finally {
      _store = await withProfileKey(_key, () => TrainingStore.open(path));
      revision++;
      notifyListeners();
    }
    if (previous == LockMode.device && next != LockMode.device) {
      await keyStore.delete();
    }
  }

  /// Runs one command and returns its `data`.
  Future<T> call<T>(
    String command, [
    Map<String, Object?> fields = const {},
  ]) async {
    final response = await withProfileKey(
      _key,
      () => TrainingStore.sharing(
        _store,
        () => executeCommand(command, {
          'schemaVersion': 1,
          'database': path,
          ...fields,
        }),
      ),
    );
    return response['data'] as T;
  }

  /// Runs a pure command (one that takes no database, such as the food
  /// dataset search) and returns its `data`.
  Future<T> pure<T>(String command, Map<String, Object?> fields) async =>
      (await executeCommand(command, {'schemaVersion': 1, ...fields}))['data']
          as T;

  /// [call] for commands that change data; listeners reload afterwards.
  Future<T> write<T>(
    String command, [
    Map<String, Object?> fields = const {},
  ]) async {
    final result = await call<T>(command, fields);
    revision++;
    notifyListeners();
    return result;
  }

  /// Replaces this profile with an invented demonstration profile.
  Future<void> replaceWithDemo() async {
    await _store.close();
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      final file = File('$path$suffix');
      if (await file.exists()) await file.delete();
    }
    try {
      await withProfileKey(_key, () => buildDemoProfile(path));
    } finally {
      _store = await withProfileKey(_key, () => TrainingStore.open(path));
      revision++;
      notifyListeners();
    }
  }

  Future<void> close() => _store.close();
}

/// Makes the [ProfileClient] available below it and rebuilds dependants
/// after writes.
final class ProfileScope extends InheritedNotifier<ProfileClient> {
  const ProfileScope({
    super.key,
    required ProfileClient profile,
    required super.child,
  }) : super(notifier: profile);

  static ProfileClient of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ProfileScope>()!.notifier!;
}

/// Loads [load] whenever the profile changes and shows loading and error
/// states consistently.
final class ProfileLoader<T> extends StatefulWidget {
  const ProfileLoader({super.key, required this.load, required this.builder});

  final Future<T> Function(ProfileClient profile) load;
  final Widget Function(BuildContext context, T data) builder;

  @override
  State<ProfileLoader<T>> createState() => _ProfileLoaderState<T>();
}

final class _ProfileLoaderState<T> extends State<ProfileLoader<T>> {
  Future<T>? _future;
  int? _revision;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final profile = ProfileScope.of(context);
    if (_revision != profile.revision) {
      _revision = profile.revision;
      _future = widget.load(profile);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        final error = snapshot.error;
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              error is BodyTmiException ? error.message : '$error',
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      return widget.builder(context, snapshot.data as T);
    },
  );
}
