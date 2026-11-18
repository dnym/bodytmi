import 'dart:io';

import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:material_ui/material_ui.dart';

/// The open profile. Every read and write goes through the same JSON
/// commands as the CLI, borrowing this one long-lived store, so the GUI and
/// CLI cannot disagree about behaviour.
final class ProfileClient extends ChangeNotifier {
  ProfileClient._(this.path, this._store);

  final String path;
  TrainingStore _store;

  /// Increases after every successful write, so screens reload.
  int revision = 0;

  static Future<ProfileClient> open(String path) async =>
      ProfileClient._(path, await TrainingStore.open(path));

  /// Runs one command and returns its `data`.
  Future<T> call<T>(
    String command, [
    Map<String, Object?> fields = const {},
  ]) async {
    final response = await TrainingStore.sharing(
      _store,
      () => executeCommand(command, {
        'schemaVersion': 1,
        'database': path,
        ...fields,
      }),
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
      await buildDemoProfile(path);
    } finally {
      _store = await TrainingStore.open(path);
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
