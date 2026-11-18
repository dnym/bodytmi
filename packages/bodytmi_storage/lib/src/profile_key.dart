import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:sqlite3/sqlite3.dart';

/// The passphrase of encrypted SQLite files (SQLite3MultipleCiphers, its
/// default ChaCha20-Poly1305 cipher with its own per-file salt and key
/// derivation). One key applies to every database file opened in a zone:
/// the profile, its backups and temporary restore copies, so pages copy
/// between them unchanged. Without a key every file is plain SQLite.
final class ProfileKey {
  ProfileKey._(this.passphrase);

  /// A passphrase read from text; one trailing line break is removed.
  factory ProfileKey.fromText(String text, {bool newPassphrase = false}) {
    var value = text;
    if (value.endsWith('\r\n')) {
      value = value.substring(0, value.length - 2);
    } else if (value.endsWith('\n')) {
      value = value.substring(0, value.length - 1);
    }
    if (value.isEmpty || value.length > 1024)
      invalid('A passphrase is 1 to 1024 characters.');
    if (value.contains('\u0000')) invalid('A passphrase has no NUL character.');
    if (newPassphrase && value.runes.length < 8)
      invalid('A new passphrase has at least 8 characters.');
    return ProfileKey._(value);
  }

  /// Reads a passphrase file (at most 4 KiB of UTF-8).
  static Future<ProfileKey> readFile(
    String path, {
    bool newPassphrase = false,
  }) async {
    final file = File(path);
    if (!await file.exists())
      throw BodyTmiException('not_found', 'Passphrase file not found: $path');
    if (await file.length() > 4096)
      invalid('A passphrase file is at most 4 KiB.');
    final String text;
    try {
      text = utf8.decode(await file.readAsBytes());
    } on FormatException {
      invalid('A passphrase file is UTF-8 text.');
    }
    return ProfileKey.fromText(text, newPassphrase: newPassphrase);
  }

  final String passphrase;

  String get _literal => "'${passphrase.replaceAll("'", "''")}'";

  @override
  String toString() => 'ProfileKey(…)';
}

/// The profile cipher as configured by SQLite3MultipleCiphers defaults.
const profileCipher = 'sqlite3mc-chacha20-poly1305';

const _zoneKey = #bodytmiProfileKey;

/// Runs [body] with [key] applying to every database it opens.
Future<T> withProfileKey<T>(ProfileKey? key, Future<T> Function() body) =>
    runZoned(body, zoneValues: {_zoneKey: _Holder(key)});

/// The key of the current zone, or `null` for plain files.
ProfileKey? get currentProfileKey => (Zone.current[_zoneKey] as _Holder?)?.key;

final class _Holder {
  const _Holder(this.key);
  final ProfileKey? key;
}

/// What a database file holds, judged from its first 16 bytes.
enum DatabaseFileState { missing, empty, plain, encrypted }

const _plainHeader = 'SQLite format 3\u0000';

DatabaseFileState databaseFileState(String path) {
  final file = File(path);
  if (!file.existsSync()) return DatabaseFileState.missing;
  final handle = file.openSync();
  try {
    final head = handle.readSync(16);
    if (head.isEmpty) return DatabaseFileState.empty;
    return head.length == 16 && String.fromCharCodes(head) == _plainHeader
        ? DatabaseFileState.plain
        : DatabaseFileState.encrypted;
  } finally {
    handle.closeSync();
  }
}

/// Refuses a key for a plain file and a missing key for an encrypted one,
/// before SQLite reads anything.
void checkKeyMatches(String path, ProfileKey? key) {
  switch (databaseFileState(path)) {
    case DatabaseFileState.plain when key != null:
      throw const BodyTmiException(
        'storage',
        'This database is not encrypted; omit --passphrase-file.',
      );
    case DatabaseFileState.encrypted when key == null:
      throw const BodyTmiException(
        'storage',
        'This database is encrypted; supply its passphrase with '
            '--passphrase-file.',
      );
    default:
  }
}

/// Keys a freshly opened connection and proves the key reads the file.
void applyProfileKey(Database db, ProfileKey? key) {
  if (key == null) return;
  db.execute('PRAGMA key = ${key._literal}');
  verifyKey(db);
}

void verifyKey(Database db) {
  try {
    db.select('SELECT count(*) FROM sqlite_master');
  } on SqliteException catch (e) {
    if (e.extendedResultCode == 26 || e.resultCode == 26)
      throw const BodyTmiException(
        'storage',
        'Wrong passphrase, or the file is not a BodyTMI database.',
      );
    rethrow;
  }
}

/// Opens a database file with the current zone key.
Database openKeyed(String path, {OpenMode mode = OpenMode.readWriteCreate}) {
  final key = currentProfileKey;
  checkKeyMatches(path, key);
  final db = sqlite3.open(path, mode: mode);
  try {
    applyProfileKey(db, key);
    return db;
  } catch (_) {
    db.close();
    rethrow;
  }
}

/// Sets, changes or (with `null`) removes the key of a closed, owned
/// database file. SQLite3MultipleCiphers rewrites pages in place, which an
/// interruption can leave readable under neither key, so the rewrite runs
/// on a private copy beside the profile: checkpoint the WAL into the main
/// file, copy it, rekey and verify the copy, then rename it over the
/// profile in one atomic step. Until the rename the profile is unchanged;
/// a leftover copy from an interrupted change is deleted next time.
Future<void> changeDatabaseKey(String path, ProfileKey? next) async {
  final file = File(path);
  final directory = file.parent;
  final prefix = '.${file.uri.pathSegments.last}.rekey-';
  await for (final entry in directory.list(followLinks: false)) {
    final name = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    if (entry is File && name.startsWith(prefix)) await entry.delete();
  }
  final db = openKeyed(path);
  try {
    db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    db.execute('PRAGMA journal_mode = DELETE');
  } finally {
    db.close();
  }
  for (final suffix in ['-wal', '-shm', '-journal']) {
    if (await File('$path$suffix').exists())
      throw BodyTmiException(
        'storage',
        'The database still has a $suffix file; open it once and retry.',
      );
  }
  final random = Random.secure();
  final copy = File(
    '${directory.path}/$prefix'
    '${List.generate(8, (_) => random.nextInt(16).toRadixString(16)).join()}',
  );
  try {
    await file.copy(copy.path);
    final rekeyed = openKeyed(copy.path);
    try {
      rekeyed.execute('PRAGMA rekey = ${next == null ? "''" : next._literal}');
    } finally {
      rekeyed.close();
    }
    await withProfileKey(next, () async {
      final check = openKeyed(copy.path);
      try {
        final result = check.select('PRAGMA quick_check');
        if (result.length != 1 || result.single.values.single != 'ok')
          throw const BodyTmiException(
            'storage',
            'Database integrity check failed after the key change.',
          );
      } finally {
        check.close();
      }
    });
    final handle = await copy.open(mode: FileMode.append);
    try {
      await handle.flush();
    } finally {
      await handle.close();
    }
    await copy.rename(path);
  } finally {
    if (await copy.exists()) await copy.delete();
  }
}
