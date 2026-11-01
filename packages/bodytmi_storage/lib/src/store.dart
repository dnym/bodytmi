import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'database.dart'
    hide
        ProgressionDecision,
        ProgramRevision,
        ProgramRun,
        ProgramReceipt,
        BodyMassRecord,
        TimingActivity,
        WorkoutExecution;
import 'native_backup.dart';
import 'schema.dart';

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
            if (native.userVersion > 22) {
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
    validateSchema(schema.map((row) => row.data), 22);
    final size = await _db.customSelect('''
      SELECT COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM revisions), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM sessions), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM progression_decisions), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM program_revisions), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM program_runs), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM session_programs), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM program_receipts), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM body_mass_records), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM timing_activities), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM workout_executions), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM family_revisions), 0) AS bytes
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
  Future<List<FamilyRevision>> familyRevisions() async {
    final result = <FamilyRevision>[];
    for (final row in await _db.select(_db.familyRevisions).get()) {
      final revision = FamilyRevision.fromJson(jsonDecode(row.snapshot));
      if (revision.family.id != row.familyId || revision.number != row.number)
        invalid('Stored family revision identity is inconsistent.');
      result.add(revision);
    }
    validateFamilyRevisions(result);
    return result;
  }

  @override
  Future<void> insertFamilyRevision(FamilyRevision revision) async {
    await _db
        .into(_db.familyRevisions)
        .insert(
          FamilyRevisionsCompanion.insert(
            familyId: revision.family.id,
            number: revision.number,
            snapshot: _snapshot(revision.toJson()),
          ),
        );
  }

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
  Future<List<ProgressionDecision>> progressionDecisions() async {
    final result = <ProgressionDecision>[];
    for (final row in await _db.select(_db.progressionDecisions).get()) {
      final decision = ProgressionDecision.fromJson(jsonDecode(row.snapshot));
      if (decision.session.id != row.sessionId || decision.slotId != row.slotId)
        invalid('Stored progression identity is inconsistent.');
      result.add(decision);
    }
    return result;
  }

  @override
  Future<void> saveProgressionDecision(ProgressionDecision decision) async {
    final snapshot = canonicalJson(decision.toJson());
    if (utf8.encode(snapshot).length > 8 * 1024 * 1024)
      invalid('Progression decision exceeds the 8 MiB resource limit.');
    final old =
        await (_db.select(_db.progressionDecisions)..where(
              (r) =>
                  r.sessionId.equals(decision.session.id) &
                  r.slotId.equals(decision.slotId),
            ))
            .getSingleOrNull();
    if (old != null) {
      final previous = ProgressionDecision.fromJson(jsonDecode(old.snapshot));
      if (previous.resolvedAt != null &&
          canonicalJson(previous.toJson()) !=
              canonicalJson(decision.toJson())) {
        throw const BodyTmiException(
          'conflict',
          'A resolved progression receipt is immutable.',
        );
      }
    }
    await _db
        .into(_db.progressionDecisions)
        .insertOnConflictUpdate(
          ProgressionDecisionsCompanion.insert(
            sessionId: decision.session.id,
            slotId: decision.slotId,
            snapshot: snapshot,
          ),
        );
  }

  @override
  Future<List<ProgramRevision>> programRevisions() async {
    final result = <ProgramRevision>[];
    for (final row in await _db.select(_db.programRevisions).get()) {
      final p = ProgramRevision.fromJson(jsonDecode(row.snapshot));
      if (p.definition.id != row.programId || p.number != row.number)
        invalid('Stored program revision identity mismatch.');
      result.add(p);
    }
    return result;
  }

  @override
  Future<void> insertProgramRevision(ProgramRevision revision) async {
    await _db
        .into(_db.programRevisions)
        .insert(
          ProgramRevisionsCompanion.insert(
            programId: revision.definition.id,
            number: revision.number,
            snapshot: _snapshot(revision.toJson()),
          ),
        );
  }

  @override
  Future<List<ProgramRun>> programRuns() async {
    final result = <ProgramRun>[];
    for (final row in await _db.select(_db.programRuns).get()) {
      final r = ProgramRun.fromJson(jsonDecode(row.snapshot));
      if (r.id != row.id) invalid('Stored run identity mismatch.');
      result.add(r);
    }
    return result;
  }

  @override
  Future<void> saveProgramRun(ProgramRun run) async {
    await _db
        .into(_db.programRuns)
        .insertOnConflictUpdate(
          ProgramRunsCompanion.insert(
            id: run.id,
            snapshot: _snapshot(run.toJson()),
          ),
        );
  }

  @override
  Future<List<SessionProgramBinding>> sessionPrograms() async {
    final result = <SessionProgramBinding>[];
    for (final row in await _db.select(_db.sessionPrograms).get()) {
      final b = SessionProgramBinding.fromJson(jsonDecode(row.snapshot));
      if (b.sessionId != row.sessionId ||
          b.runId != row.runId ||
          b.ordinal != row.ordinal)
        invalid('Stored session binding identity mismatch.');
      result.add(b);
    }
    return result;
  }

  @override
  Future<void> insertSessionProgram(SessionProgramBinding binding) async {
    await _db
        .into(_db.sessionPrograms)
        .insert(
          SessionProgramsCompanion.insert(
            sessionId: binding.sessionId,
            runId: binding.runId,
            ordinal: binding.ordinal,
            snapshot: _snapshot(binding.toJson()),
          ),
        );
  }

  @override
  Future<WorkoutExecution?> execution(String id) async {
    final row = await (_db.select(
      _db.workoutExecutions,
    )..where((e) => e.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    final e = WorkoutExecution.fromJson(jsonDecode(row.snapshot));
    if (e.id != row.id || e.sessionId != row.sessionId)
      invalid('Execution row identity mismatch.');
    return e;
  }

  @override
  Future<List<WorkoutExecution>> executions() async {
    final result = <WorkoutExecution>[];
    for (final row in await _db.select(_db.workoutExecutions).get()) {
      final e = WorkoutExecution.fromJson(jsonDecode(row.snapshot));
      if (e.id != row.id || e.sessionId != row.sessionId)
        invalid('Execution row identity mismatch.');
      result.add(e);
    }
    return result;
  }

  @override
  Future<void> saveExecution(WorkoutExecution execution) async {
    await _db
        .into(_db.workoutExecutions)
        .insertOnConflictUpdate(
          WorkoutExecutionsCompanion.insert(
            id: execution.id,
            sessionId: execution.sessionId,
            snapshot: _snapshot(execution.toJson()),
          ),
        );
  }

  @override
  Future<TimingActivity?> timingActivity(String id) async {
    final row = await (_db.select(
      _db.timingActivities,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    final t = TimingActivity.fromJson(jsonDecode(row.snapshot));
    if (t.id != row.id || t.sessionId != row.sessionId || t.setId != row.setId)
      invalid('Timing row identity mismatch.');
    return t;
  }

  @override
  Future<List<TimingActivity>> timingActivities() async {
    final result = <TimingActivity>[];
    for (final row in await _db.select(_db.timingActivities).get()) {
      final timer = TimingActivity.fromJson(jsonDecode(row.snapshot));
      if (timer.id != row.id ||
          timer.sessionId != row.sessionId ||
          timer.setId != row.setId)
        invalid('Timing row identity mismatch.');
      result.add(timer);
    }
    return result;
  }

  @override
  Future<void> saveTimingActivity(TimingActivity timer) async {
    await _db
        .into(_db.timingActivities)
        .insertOnConflictUpdate(
          TimingActivitiesCompanion.insert(
            id: timer.id,
            sessionId: timer.sessionId,
            setId: timer.setId,
            snapshot: _snapshot(timer.toJson()),
          ),
        );
  }

  @override
  Future<List<BodyMassRecord>> bodyMassRecords() async {
    final result = <BodyMassRecord>[];
    for (final row in await _db.select(_db.bodyMassRecords).get()) {
      final record = BodyMassRecord.fromJson(jsonDecode(row.snapshot));
      if (record.measurement.id != row.id)
        invalid('Body-mass row identity mismatch.');
      result.add(record);
    }
    return result;
  }

  @override
  Future<void> saveBodyMassRecord(BodyMassRecord record) async {
    await _db
        .into(_db.bodyMassRecords)
        .insertOnConflictUpdate(
          BodyMassRecordsCompanion.insert(
            id: record.measurement.id,
            snapshot: _snapshot(record.toJson()),
          ),
        );
  }

  @override
  Future<List<ProgramReceipt>> programReceipts() async {
    final result = <ProgramReceipt>[];
    for (final row in await _db.select(_db.programReceipts).get()) {
      final r = ProgramReceipt.fromJson(jsonDecode(row.snapshot));
      if (r.runId != row.runId ||
          r.ordinal != row.ordinal ||
          r.operationKey != row.operationKey ||
          r.sessionId != row.sessionId)
        invalid('Stored occurrence receipt identity mismatch.');
      result.add(r);
    }
    return result;
  }

  @override
  Future<void> insertProgramReceipt(ProgramReceipt receipt) async {
    await _db
        .into(_db.programReceipts)
        .insert(
          ProgramReceiptsCompanion.insert(
            runId: receipt.runId,
            ordinal: receipt.ordinal,
            operationKey: receipt.operationKey,
            sessionId: Value(receipt.sessionId),
            snapshot: _snapshot(receipt.toJson()),
          ),
        );
  }

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
            snapshot: _snapshot(revision.toJson()),
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
            snapshot: _snapshot(session.toJson()),
          ),
        );
  }

  @override
  Future<void> updateSession(TrainingSession session) async {
    await (_db.update(_db.sessions)..where((s) => s.id.equals(session.id)))
        .write(SessionsCompanion(snapshot: Value(_snapshot(session.toJson()))));
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

String _snapshot(Object? value) {
  final json = canonicalJson(value);
  if (utf8.encode(json).length > 8 * 1024 * 1024)
    invalid('Stored snapshot exceeds 8 MiB.');
  return json;
}
