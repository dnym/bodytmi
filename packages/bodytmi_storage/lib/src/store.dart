import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'database.dart';
import 'native_backup.dart';
import 'schema_v1.dart';

/// A single native owner. Never unlink the lock file: the OS holds ownership.
final class TrainingStore implements TrainingRepository {
  TrainingStore._(this._db, this._lock, this.path);
  final TrainingDatabase _db;
  final RandomAccessFile _lock;
  final String path;
  static final _owned = <String>{};
  bool _databaseClosed = false;
  bool _closed = false;

  static Future<TrainingStore> open(String path) async {
    final file = File(path).absolute;
    await file.parent.create(recursive: true);
    if (!await file.exists()) await file.create();
    final canonical = await file.resolveSymbolicLinks();
    if (!_owned.add(canonical)) _busy();
    RandomAccessFile? lock;
    TrainingDatabase? db;
    try {
      lock = await File('$canonical.owner.lock').open(mode: FileMode.append);
      try {
        await lock.lock(FileLock.exclusive);
      } on FileSystemException {
        _busy();
      }
      db = TrainingDatabase(
        NativeDatabase(
          File(canonical),
          setup: (native) {
            final applicationId = native
                .select('PRAGMA application_id')
                .single
                .values
                .single;
            final tables = native.select(
              "SELECT name FROM sqlite_master WHERE type = 'table'",
            );
            if (native.userVersion > 1) {
              throw const BodyTmiException(
                'storage',
                'Database schema is newer than this application supports.',
              );
            }
            if (applicationId != 1112821065 &&
                (native.userVersion != 0 ||
                    tables.isNotEmpty ||
                    applicationId != 0)) {
              throw const BodyTmiException(
                'storage',
                'File is not a supported BodyTMI database.',
              );
            }
          },
        ),
      );
      await db.customSelect('SELECT 1').get();
      final integrity = await db.customSelect('PRAGMA quick_check').get();
      if (integrity.length != 1 ||
          integrity.single.data.values.single != 'ok') {
        throw const BodyTmiException(
          'storage',
          'Database integrity check failed.',
        );
      }
      return TrainingStore._(db, lock, canonical);
    } catch (_) {
      await db?.close();
      await lock?.close();
      _owned.remove(canonical);
      rethrow;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      if (!_databaseClosed) await _db.close();
    } finally {
      try {
        await _lock.close();
      } finally {
        _owned.remove(path);
      }
    }
  }

  Future<Map<String, Object?>> backup(String destination) {
    if (_closed || _databaseClosed) throw StateError('Store is closed.');
    return NativeBackup.create(path, destination);
  }

  Future<TrainingArchive> archive() => _db.transaction(() async {
    final schema = await _db
        .customSelect(
          'SELECT name, sql FROM sqlite_master WHERE sql IS NOT NULL',
        )
        .get();
    validateSchemaV1(schema.map((row) => row.data));
    final size = await _db.customSelect('''
      SELECT COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM revisions), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM sessions), 0) AS bytes
    ''').getSingle();
    if (size.read<int>('bytes') > 64 * 1024 * 1024) {
      invalid('Logical export exceeds the 64 MiB resource limit.');
    }
    return StoredTrainingService(this).exportArchive();
  });

  /// Terminal operation on this handle; close() releases ownership afterwards.
  /// Replacement is committed by SQLite, rather than renaming a set of WAL files.
  Future<void> restore(
    PreparedNativeBackup backup, {
    required String recoveryDestination,
    required bool confirm,
    Future<void> Function(double)? onProgress,
  }) async {
    if (!confirm)
      invalid('Restore replaces the profile and requires confirm:true.');
    if (_closed || _databaseClosed) throw StateError('Store is closed.');
    await backup.checkDestination(path);
    await backup.checkDestination(recoveryDestination);
    await this.backup(recoveryDestination);
    await _db.close();
    _databaseClosed = true;
    await backup.restoreInto(path, onProgress: onProgress);
  }

  @override
  Future<T> transaction<T>(Future<T> Function() action) =>
      _db.transaction(action);
  @override
  Future<List<WorkoutRevision>> revisions() async {
    final result = <WorkoutRevision>[];
    for (final row in await _db.select(_db.revisions).get()) {
      final revision = WorkoutRevision.fromJson(jsonDecode(row.snapshot));
      if (revision.definition.id != row.templateId ||
          revision.number != row.number) {
        invalid('Stored revision identity is inconsistent.');
      }
      result.add(revision);
    }
    return result;
  }

  @override
  Future<List<String>> finalizationIds() async => [
    for (final row in await _db.select(_db.finalizations).get()) row.sessionId,
  ];
  @override
  Future<WorkoutRevision?> revision(String templateId, [int? number]) async {
    final query = _db.select(_db.revisions)
      ..where((r) => r.templateId.equals(templateId));
    if (number != null) query.where((r) => r.number.equals(number));
    query.orderBy([(r) => OrderingTerm.desc(r.number)]);
    query.limit(1);
    final row = await query.getSingleOrNull();
    return row == null
        ? null
        : WorkoutRevision.fromJson(jsonDecode(row.snapshot));
  }

  @override
  Future<void> insertRevision(WorkoutRevision revision) async {
    await _db
        .into(_db.revisions)
        .insert(
          RevisionsCompanion.insert(
            templateId: revision.definition.id,
            number: revision.number,
            snapshot: jsonEncode(revision.toJson()),
          ),
        );
  }

  @override
  Future<TrainingSession?> session(String id) async {
    final row = await (_db.select(
      _db.sessions,
    )..where((s) => s.id.equals(id))).getSingleOrNull();
    return row == null ? null : sessionFromJson(jsonDecode(row.snapshot));
  }

  @override
  Future<List<TrainingSession>> sessions() async {
    final result = <TrainingSession>[];
    for (final row in await (_db.select(
      _db.sessions,
    )..orderBy([(s) => OrderingTerm.asc(s.id)])).get()) {
      final session = sessionFromJson(jsonDecode(row.snapshot));
      if (session.id != row.id)
        invalid('Stored session identity is inconsistent.');
      result.add(session);
    }
    return result;
  }

  @override
  Future<void> insertSession(TrainingSession session) async {
    await _db
        .into(_db.sessions)
        .insert(
          SessionsCompanion.insert(
            id: session.id,
            snapshot: jsonEncode(session.toJson()),
          ),
        );
  }

  @override
  Future<void> updateSession(TrainingSession session) async {
    await (_db.update(
      _db.sessions,
    )..where((s) => s.id.equals(session.id))).write(
      SessionsCompanion(snapshot: Value(jsonEncode(session.toJson()))),
    );
  }

  @override
  Future<void> recordFinalization(String sessionId) async {
    await _db
        .into(_db.finalizations)
        .insert(
          FinalizationsCompanion.insert(sessionId: sessionId),
          mode: InsertMode.insertOrIgnore,
        );
  }

  /// Consistent engine snapshot including WAL writes; not the full backup archive contract.
  Future<void> snapshot(String destination) async {
    if (await FileSystemEntity.type(destination) !=
        FileSystemEntityType.notFound) {
      throw const BodyTmiException(
        'conflict',
        'Snapshot destination already exists.',
      );
    }
    await _db.customStatement('VACUUM INTO ?', [
      File(destination).absolute.path,
    ]);
  }

  Future<int> finalizationCount() async =>
      (await _db.select(_db.finalizations).get()).length;
}

Never _busy() => throw const BodyTmiException(
  'in_use',
  'Database is already owned by another application.',
);
