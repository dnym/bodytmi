import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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
    final relock = await LockSettings.relockAfter(path);
    return ProfileClient._(
      path,
      store,
      key,
      lock ?? (key == null ? LockMode.none : LockMode.passphrase),
      keyStore ?? KeystoreDeviceKeyStore(),
    )..relockAfter = relock;
  }

  /// Changes how the profile is locked. The profile is rewritten under the
  /// new key (or none) as one verified file replacement; on any failure it
  /// keeps its previous key and lock. A device key is stored before the
  /// rewrite and the previous device key removed only after it.
  Future<void> setLock(LockMode next, {String? passphrase}) =>
      _exclusive(() => _setLock(next, passphrase: passphrase));

  Future<void> _setLock(LockMode next, {String? passphrase}) async {
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

  /// Runs one command and returns its `data`. Commands wait while the store
  /// is being closed or re-keyed, and fail once the profile is locked.
  Future<T> call<T>(
    String command, [
    Map<String, Object?> fields = const {},
  ]) async {
    while (_exclusiveRun != null) {
      await _exclusiveRun!.future;
    }
    return _tracked(() async {
      if (_closed) {
        throw const BodyTmiException('locked', 'The profile is locked.');
      }
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
    });
  }

  int _running = 0;
  bool _closed = false;
  Completer<void>? _exclusiveRun;
  final _idle = <Completer<void>>[];

  Future<T> _tracked<T>(Future<T> Function() action) async {
    _running++;
    try {
      return await action();
    } finally {
      if (--_running == 0) {
        for (final c in _idle) {
          c.complete();
        }
        _idle.clear();
      }
    }
  }

  /// Runs [action] alone: after running commands finish, with new ones
  /// waiting until it is done (closing or re-keying the store).
  Future<T> _exclusive<T>(Future<T> Function() action) async {
    while (_exclusiveRun != null) {
      await _exclusiveRun!.future;
    }
    final gate = _exclusiveRun = Completer<void>();
    try {
      await idle();
      return await action();
    } finally {
      _exclusiveRun = null;
      gate.complete();
    }
  }

  /// Completes once no command is running.
  Future<void> idle() {
    if (_running == 0) return Future.value();
    final c = Completer<void>();
    _idle.add(c);
    return c.future;
  }

  /// How long the app may be away before it locks again (locked profiles).
  Duration relockAfter = defaultRelockAfter;

  Future<void> setRelockAfter(Duration after) async {
    await LockSettings.writeRelockAfter(path, after);
    relockAfter = after;
    notifyListeners();
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
  Future<void> replaceWithDemo() => _exclusive(_replaceWithDemo);

  Future<void> _replaceWithDemo() async {
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

  /// A full logical export as file bytes: plain JSON, or with [passphrase]
  /// a `bodytmi-encrypted/1` file under that passphrase (independent of the
  /// profile lock). The passphrase goes straight to storage, never to disk.
  Future<({Uint8List bytes, Map<String, Object?> summary})> exportArchive({
    String? passphrase,
  }) async {
    while (_exclusiveRun != null) {
      await _exclusiveRun!.future;
    }
    final key = passphrase == null
        ? null
        : ProfileKey.fromText(passphrase, newPassphrase: true);
    return _tracked(
      () => withProfileKey(_key, () async {
        final dir = await Directory.systemTemp.createTemp('bodytmi-export-');
        try {
          final file = '${dir.path}/export.json';
          final summary = await LogicalArchiveFiles.export(
            await _store.archive(),
            file,
            encryptWith: key,
          );
          return (bytes: await File(file).readAsBytes(), summary: summary);
        } finally {
          await dir.delete(recursive: true);
        }
      }),
    );
  }

  /// Validates an export file completely and returns its summary.
  Future<Map<String, Object?>> inspectExport(
    String path, {
    String? passphrase,
  }) => withProfileKey(_key, () async {
    final prepared = await LogicalArchiveFiles.prepare(
      path,
      passphrase: passphrase == null ? null : ProfileKey.fromText(passphrase),
    );
    try {
      return prepared.summary;
    } finally {
      await prepared.close();
    }
  });

  /// Replaces the whole profile with an export, keeping the profile's own
  /// lock. A native backup of the current profile is written to
  /// [recoveryDestination] first; on failure the profile is unchanged.
  Future<Map<String, Object?>> restoreExport(
    String path, {
    String? passphrase,
    required String recoveryDestination,
  }) => _exclusive(
    () => withProfileKey(_key, () async {
      final prepared = await LogicalArchiveFiles.prepare(
        path,
        passphrase: passphrase == null ? null : ProfileKey.fromText(passphrase),
      );
      try {
        await prepared.checkDestination(this.path);
        await prepared.checkDestination(recoveryDestination);
        try {
          await _store.restore(
            prepared.backup,
            recoveryDestination: recoveryDestination,
            confirm: true,
          );
        } finally {
          await _store.close();
          _store = await TrainingStore.open(this.path);
          revision++;
          notifyListeners();
        }
        return prepared.summary;
      } finally {
        await prepared.close();
      }
    }),
  );

  /// Waits for running commands, closes the store and forgets the key.
  Future<void> close() => _exclusive(() async {
    if (_closed) return;
    _closed = true;
    _key = null;
    await _store.close();
  });
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
