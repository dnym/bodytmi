import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'database.dart'
    hide
        ProgressionDecision,
        ProgressionReconciliation,
        ProgramRevision,
        ProgramRun,
        ProgramReceipt,
        TimingActivity,
        WorkoutExecution;
import 'database.dart' as rows show ProgressionDecision, Session;
import 'native_backup.dart';
import 'read_cache.dart';
import 'schema.dart';

/// A single native owner. Never unlink the lock file: the OS holds ownership.
final class TrainingStore implements TrainingRepository {
  TrainingStore._(this._db, this._lock, this.path, this._cache);
  final TrainingDatabase _db;
  final ReadCache _cache;
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
    final cache = ReadCache();
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
            if (native.userVersion > supportedSchemaVersion) {
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
        ).interceptWith(ReadCacheInterceptor(cache)),
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
      return TrainingStore._(db, lock, canonical, cache);
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
    validateSchema(schema.map((row) => row.data));
    final size = await _db.customSelect('''
      SELECT COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM revisions), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM sessions), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM progression_decisions), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM program_revisions), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM program_runs), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM session_programs), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM program_receipts), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM observations), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM food_revisions), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM diary_entries), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM measure_revisions), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM series_policies), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM profile_revisions), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM body_fat_sources), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM diet_records), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM timing_activities), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM window_checkpoints), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM repeat_checkpoints), 0)
            + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM progression_reconciliations), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM workout_executions), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM family_revisions), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM exercise_revisions), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM implementation_revisions), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM progression_preset_revisions), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM blueprint_revisions), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM blueprint_instances), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM equipment_revisions), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM gym_revisions), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM equipment_instance_revisions), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM imported_sessions), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM block_progressions), 0)
           + COALESCE((SELECT SUM(length(CAST(snapshot AS BLOB))) FROM derived_target_graphs), 0) AS bytes
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
      _cache.transaction(() => _db.transaction(action));
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
  Future<List<ExerciseRevision>> exerciseRevisions() async {
    final result = <ExerciseRevision>[];
    for (final row in await _db.select(_db.exerciseRevisions).get()) {
      final revision = ExerciseRevision.fromJson(jsonDecode(row.snapshot));
      if (revision.exercise.id != row.exerciseId ||
          revision.number != row.number)
        invalid('Stored exercise revision identity is inconsistent.');
      result.add(revision);
    }
    validateExerciseRevisions(result);
    return result;
  }

  @override
  Future<void> insertExerciseRevision(ExerciseRevision revision) async {
    await _db
        .into(_db.exerciseRevisions)
        .insert(
          ExerciseRevisionsCompanion.insert(
            exerciseId: revision.exercise.id,
            number: revision.number,
            snapshot: _snapshot(revision.toJson()),
          ),
        );
  }

  @override
  Future<List<ImplementationRevision>> implementationRevisions() async {
    final exercises = await exerciseRevisions();
    final result = <ImplementationRevision>[];
    for (final row in await _db.select(_db.implementationRevisions).get()) {
      final revision = ImplementationRevision.fromJson(
        jsonDecode(row.snapshot),
      );
      if (revision.implementation.id != row.implementationId ||
          revision.number != row.number)
        invalid('Stored implementation revision identity is inconsistent.');
      result.add(revision);
    }
    validateImplementationRevisions(result, exercises);
    return result;
  }

  @override
  Future<void> insertImplementationRevision(
    ImplementationRevision revision,
  ) async {
    final exerciseId = revision.implementation.exerciseId;
    final exists =
        await (_db.select(_db.exerciseRevisions)
              ..where((t) => t.exerciseId.equals(exerciseId))
              ..limit(1))
            .get();
    if (exists.isEmpty)
      throw const BodyTmiException(
        'not_found',
        'Implementation references an exercise that is not published.',
      );
    await _db
        .into(_db.implementationRevisions)
        .insert(
          ImplementationRevisionsCompanion.insert(
            implementationId: revision.implementation.id,
            number: revision.number,
            snapshot: _snapshot(revision.toJson()),
          ),
        );
  }

  @override
  Future<List<ProgressionPresetRevision>> progressionPresetRevisions() =>
      _cache.list('progressionPresetRevisions', () async {
        final result = <ProgressionPresetRevision>[];
        for (final row
            in await _db.select(_db.progressionPresetRevisions).get()) {
          final revision = ProgressionPresetRevision.fromJson(
            jsonDecode(row.snapshot),
          );
          if (revision.preset.id != row.presetId ||
              revision.number != row.number)
            invalid(
              'Stored progression preset revision identity is inconsistent.',
            );
          result.add(revision);
        }
        validateProgressionPresetRevisions(result);
        return result;
      });

  @override
  Future<List<BlueprintRevision>> blueprintRevisions() =>
      _cache.list('blueprintRevisions', () async {
        final result = <BlueprintRevision>[];
        for (final row in await _db.select(_db.blueprintRevisions).get()) {
          final revision = BlueprintRevision.fromJson(jsonDecode(row.snapshot));
          if (revision.blueprint.id != row.blueprintId ||
              revision.number != row.number)
            invalid('Stored blueprint revision identity is inconsistent.');
          result.add(revision);
        }
        validateBlueprintRevisions(result);
        return result;
      });

  @override
  Future<void> insertBlueprintRevision(BlueprintRevision revision) => _db
      .into(_db.blueprintRevisions)
      .insert(
        BlueprintRevisionsCompanion.insert(
          blueprintId: revision.blueprint.id,
          number: revision.number,
          snapshot: _snapshot(revision.toJson()),
        ),
      );

  @override
  Future<List<BlueprintInstance>> blueprintInstances() =>
      _cache.list('blueprintInstances', () async {
        final result = <BlueprintInstance>[];
        for (final row in await _db.select(_db.blueprintInstances).get()) {
          final instance = BlueprintInstance.fromJson(jsonDecode(row.snapshot));
          if (instance.id != row.instanceId || instance.number != row.number)
            invalid('Stored blueprint instance identity is inconsistent.');
          result.add(instance);
        }
        return result;
      });

  @override
  Future<void> insertBlueprintInstance(BlueprintInstance instance) => _db
      .into(_db.blueprintInstances)
      .insert(
        BlueprintInstancesCompanion.insert(
          instanceId: instance.id,
          number: instance.number,
          snapshot: _snapshot(instance.toJson()),
        ),
      );

  @override
  Future<void> insertProgressionPresetRevision(
    ProgressionPresetRevision revision,
  ) => _db
      .into(_db.progressionPresetRevisions)
      .insert(
        ProgressionPresetRevisionsCompanion.insert(
          presetId: revision.preset.id,
          number: revision.number,
          snapshot: _snapshot(revision.toJson()),
        ),
      );

  @override
  Future<List<EquipmentRevision>> equipmentRevisions() async {
    final result = <EquipmentRevision>[];
    for (final row in await _db.select(_db.equipmentRevisions).get()) {
      final revision = EquipmentRevision.fromJson(jsonDecode(row.snapshot));
      if (revision.equipment.id != row.equipmentId ||
          revision.number != row.number)
        invalid('Stored equipment revision identity is inconsistent.');
      result.add(revision);
    }
    validateEquipmentRevisions(result);
    return result;
  }

  @override
  Future<void> insertEquipmentRevision(EquipmentRevision revision) async {
    await _db
        .into(_db.equipmentRevisions)
        .insert(
          EquipmentRevisionsCompanion.insert(
            equipmentId: revision.equipment.id,
            number: revision.number,
            snapshot: _snapshot(revision.toJson()),
          ),
        );
  }

  @override
  Future<List<GymRevision>> gymRevisions() async {
    final result = <GymRevision>[];
    for (final row in await _db.select(_db.gymRevisions).get()) {
      final revision = GymRevision.fromJson(jsonDecode(row.snapshot));
      if (revision.gym.id != row.gymId || revision.number != row.number)
        invalid('Stored gym revision identity is inconsistent.');
      result.add(revision);
    }
    validateGymRevisions(result);
    return result;
  }

  @override
  Future<void> insertGymRevision(GymRevision revision) async {
    await _db
        .into(_db.gymRevisions)
        .insert(
          GymRevisionsCompanion.insert(
            gymId: revision.gym.id,
            number: revision.number,
            snapshot: _snapshot(revision.toJson()),
          ),
        );
  }

  @override
  Future<List<EquipmentInstanceRevision>> equipmentInstanceRevisions() async {
    final equipment = await equipmentRevisions();
    final gyms = await gymRevisions();
    final result = <EquipmentInstanceRevision>[];
    for (final row in await _db.select(_db.equipmentInstanceRevisions).get()) {
      final revision = EquipmentInstanceRevision.fromJson(
        jsonDecode(row.snapshot),
      );
      if (revision.instance.id != row.instanceId ||
          revision.number != row.number)
        invalid('Stored equipment instance revision identity is inconsistent.');
      result.add(revision);
    }
    validateEquipmentInstanceRevisions(result, equipment, gyms);
    return result;
  }

  @override
  Future<void> insertEquipmentInstanceRevision(
    EquipmentInstanceRevision revision,
  ) async {
    final equipmentId = revision.instance.equipmentId;
    final equipment =
        await (_db.select(_db.equipmentRevisions)
              ..where((t) => t.equipmentId.equals(equipmentId))
              ..limit(1))
            .get();
    if (equipment.isEmpty)
      throw const BodyTmiException(
        'not_found',
        'Instance references equipment that is not published.',
      );
    final gymId = revision.instance.gymId;
    if (gymId != null) {
      final gyms =
          await (_db.select(_db.gymRevisions)
                ..where((t) => t.gymId.equals(gymId))
                ..limit(1))
              .get();
      if (gyms.isEmpty)
        throw const BodyTmiException(
          'not_found',
          'Instance references a gym that is not published.',
        );
    }
    await _db
        .into(_db.equipmentInstanceRevisions)
        .insert(
          EquipmentInstanceRevisionsCompanion.insert(
            instanceId: revision.instance.id,
            number: revision.number,
            snapshot: _snapshot(revision.toJson()),
          ),
        );
  }

  @override
  Future<List<DerivedTargetGraphRevision>> derivedTargetGraphRevisions() =>
      _cache.list('derivedTargetGraphRevisions', () async {
        final result = <DerivedTargetGraphRevision>[];
        for (final row in await _db.select(_db.derivedTargetGraphs).get()) {
          final revision = DerivedTargetGraphRevision.fromJson(
            jsonDecode(row.snapshot),
          );
          if (revision.graph.id != row.graphId ||
              revision.number != row.number) {
            invalid('Stored derived target graph identity is inconsistent.');
          }
          result.add(revision);
        }
        validateDerivedTargetGraphRevisions(result);
        return result;
      });

  @override
  Future<void> insertDerivedTargetGraphRevision(
    DerivedTargetGraphRevision revision,
  ) async {
    await _db
        .into(_db.derivedTargetGraphs)
        .insert(
          DerivedTargetGraphsCompanion.insert(
            graphId: revision.graph.id,
            number: revision.number,
            snapshot: _snapshot(revision.toJson()),
          ),
        );
  }

  @override
  Future<List<WorkoutRevision>> revisions() =>
      _cache.list('revisions', () async {
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
      });

  @override
  Future<List<String>> finalizationIds() async => [
    for (final row in await _db.select(_db.finalizations).get()) row.sessionId,
  ];
  @override
  Future<List<ProgressionDecision>> progressionDecisions() =>
      _cache.list('progressionDecisions', () async {
        final result = <ProgressionDecision>[];
        for (final row in await _db.select(_db.progressionDecisions).get()) {
          result.add(_decision(row));
        }
        return result;
      });

  ProgressionDecision _decision(rows.ProgressionDecision row) {
    final decision = ProgressionDecision.fromJson(jsonDecode(row.snapshot));
    if (decision.session.id != row.sessionId ||
        decision.storageSlotKey != row.slotId ||
        decision.templateId != row.templateId ||
        decision.runId != row.runId ||
        decision.sequence != row.sequence)
      invalid('Stored progression identity is inconsistent.');
    return decision;
  }

  @override
  Future<ProgressionDecision?> progressionDecision(
    String sessionId,
    String slotKey,
  ) async {
    final row =
        await (_db.select(_db.progressionDecisions)..where(
              (r) => r.sessionId.equals(sessionId) & r.slotId.equals(slotKey),
            ))
            .getSingleOrNull();
    return row == null ? null : _decision(row);
  }

  @override
  Future<List<ProgressionDecision>> latestTrackDecisions(
    String templateId,
    String slotKey,
    String? runId,
    bool Function(ProgressionDecision) where,
  ) async {
    final query = _db.select(_db.progressionDecisions)
      ..where(
        (r) =>
            r.templateId.equals(templateId) &
            r.slotId.equals(slotKey) &
            (runId == null ? r.runId.isNull() : r.runId.equals(runId)),
      )
      ..orderBy([(r) => OrderingTerm.desc(r.sequence)]);
    final found = <ProgressionDecision>[];
    int? top;
    for (final row in await query.get()) {
      if (top != null && row.sequence < top) break;
      final decision = _decision(row);
      if (!where(decision)) continue;
      top = row.sequence;
      found.add(decision);
    }
    return found;
  }

  @override
  Future<void> saveProgressionDecision(
    ProgressionDecision decision, {
    bool reopening = false,
  }) async {
    final snapshot = canonicalJson(decision.toJson());
    if (utf8.encode(snapshot).length > 8 * 1024 * 1024)
      invalid('Progression decision exceeds the 8 MiB resource limit.');
    final old =
        await (_db.select(_db.progressionDecisions)..where(
              (r) =>
                  r.sessionId.equals(decision.session.id) &
                  r.slotId.equals(decision.storageSlotKey),
            ))
            .getSingleOrNull();
    if (old != null) {
      final previous = ProgressionDecision.fromJson(jsonDecode(old.snapshot));
      final reopens =
          reopening &&
          decision.resolvedAt == null &&
          decision.version == previous.version + 1 &&
          decision.ruleType == previous.ruleType &&
          canonicalJson(decision.rule) == canonicalJson(previous.rule) &&
          decision.previousApplication == previous.previousApplication &&
          decision.previousSequence == previous.previousSequence &&
          decision.previousFailures == previous.previousFailures &&
          decision.previousCursor == previous.previousCursor;
      if (previous.resolvedAt != null &&
          !reopens &&
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
            slotId: decision.storageSlotKey,
            templateId: decision.templateId,
            runId: Value(decision.runId),
            sequence: decision.sequence,
            snapshot: snapshot,
          ),
        );
  }

  @override
  Future<List<ReconciliationReceipt>> progressionReconciliations() =>
      _cache.list('progressionReconciliations', () async {
        final result = <ReconciliationReceipt>[];
        for (final row
            in await _db.select(_db.progressionReconciliations).get()) {
          final receipt = ReconciliationReceipt.fromJson(
            jsonDecode(row.snapshot),
          );
          if (receipt.id != row.id)
            invalid('Reconciliation row identity does not match its key.');
          result.add(receipt);
        }
        return result;
      });

  @override
  Future<void> saveProgressionReconciliation(
    ReconciliationReceipt reconciliation,
  ) async {
    final snapshot = canonicalJson(reconciliation.toJson());
    if (utf8.encode(snapshot).length > 8 * 1024 * 1024)
      invalid('Progression reconciliation exceeds the 8 MiB resource limit.');
    final old = await (_db.select(
      _db.progressionReconciliations,
    )..where((r) => r.id.equals(reconciliation.id))).getSingleOrNull();
    if (old != null) {
      if (canonicalJson(jsonDecode(old.snapshot)) !=
          canonicalJson(reconciliation.toJson()))
        throw const BodyTmiException(
          'conflict',
          'A progression reconciliation is immutable.',
        );
      return;
    }
    await _db
        .into(_db.progressionReconciliations)
        .insert(
          ProgressionReconciliationsCompanion.insert(
            id: reconciliation.id,
            snapshot: snapshot,
          ),
        );
  }

  @override
  Future<List<LeverLinkRevision>> leverLinkRevisions() =>
      _cache.list('leverLinkRevisions', () async {
        final result = <LeverLinkRevision>[];
        for (final row in await _db.select(_db.leverLinkRevisions).get()) {
          final revision = LeverLinkRevision.fromJson(jsonDecode(row.snapshot));
          if (revision.link.id != row.linkId || revision.number != row.number)
            invalid('Stored lever link revision identity mismatch.');
          result.add(revision);
        }
        validateLeverLinkRevisions(result);
        return result;
      });

  @override
  Future<void> insertLeverLinkRevision(LeverLinkRevision revision) async {
    await _db
        .into(_db.leverLinkRevisions)
        .insert(
          LeverLinkRevisionsCompanion.insert(
            linkId: revision.link.id,
            number: revision.number,
            snapshot: _snapshot(revision.toJson()),
          ),
        );
  }

  @override
  Future<List<SharedLeverApplication>> sharedLeverApplications() =>
      _cache.list('sharedLeverApplications', () async {
        final result = <SharedLeverApplication>[];
        for (final row in await _db.select(_db.sharedLeverApplications).get()) {
          final application = SharedLeverApplication.fromJson(
            jsonDecode(row.snapshot),
          );
          if (application.linkId != row.linkId ||
              application.sequence != row.sequence)
            invalid('Stored shared lever application identity mismatch.');
          result.add(application);
        }
        return result;
      });

  @override
  Future<void> insertSharedLeverApplication(
    SharedLeverApplication application,
  ) async {
    await _db
        .into(_db.sharedLeverApplications)
        .insert(
          SharedLeverApplicationsCompanion.insert(
            linkId: application.linkId,
            sequence: application.sequence,
            snapshot: _snapshot(application.toJson()),
          ),
        );
  }

  @override
  Future<List<LinkRetirementAnchor>> linkRetirements() =>
      _cache.list('linkRetirements', () async {
        final result = <LinkRetirementAnchor>[];
        for (final row in await _db.select(_db.linkRetirementAnchors).get()) {
          final retirement = LinkRetirementAnchor.fromJson(
            jsonDecode(row.snapshot),
          );
          if (retirement.id != row.id)
            invalid('Stored lever link retirement identity mismatch.');
          result.add(retirement);
        }
        return result;
      });

  @override
  Future<void> insertLinkRetirementAnchor(
    LinkRetirementAnchor retirement,
  ) async {
    await _db
        .into(_db.linkRetirementAnchors)
        .insert(
          LinkRetirementAnchorsCompanion.insert(
            id: retirement.id,
            snapshot: _snapshot(retirement.toJson()),
          ),
        );
  }

  @override
  Future<List<ProgramRevision>> programRevisions() =>
      _cache.list('programRevisions', () async {
        final result = <ProgramRevision>[];
        for (final row in await _db.select(_db.programRevisions).get()) {
          final p = ProgramRevision.fromJson(jsonDecode(row.snapshot));
          if (p.definition.id != row.programId || p.number != row.number)
            invalid('Stored program revision identity mismatch.');
          result.add(p);
        }
        return result;
      });

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
  Future<List<ProgramRun>> programRuns() =>
      _cache.list('programRuns', () async {
        final result = <ProgramRun>[];
        for (final row in await _db.select(_db.programRuns).get()) {
          final r = ProgramRun.fromJson(jsonDecode(row.snapshot));
          if (r.id != row.id) invalid('Stored run identity mismatch.');
          result.add(r);
        }
        return result;
      });

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
  Future<List<SessionProgramBinding>> sessionPrograms() =>
      _cache.list('sessionPrograms', () async {
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
      });

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
  Future<List<WorkoutExecution>> executions({String? sessionId}) =>
      sessionId == null
      ? _cache.list('executions', () => _executions(null))
      : _executions(sessionId);

  Future<List<WorkoutExecution>> _executions(String? sessionId) async {
    final result = <WorkoutExecution>[];
    final query = _db.select(_db.workoutExecutions);
    if (sessionId != null) query.where((e) => e.sessionId.equals(sessionId));
    for (final row in await query.get()) {
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
  Future<List<TimingActivity>> activeTimingActivities() async {
    final result = <TimingActivity>[];
    for (final row
        in await _db
            .customSelect(
              "SELECT id, session_id, set_id, snapshot FROM timing_activities "
              "WHERE json_extract(snapshot, '\$.status') IN ('running', 'paused')",
              readsFrom: {_db.timingActivities},
            )
            .get()) {
      final timer = TimingActivity.fromJson(
        jsonDecode(row.read<String>('snapshot')),
      );
      if (timer.id != row.read<String>('id') ||
          timer.sessionId != row.read<String>('session_id') ||
          timer.setId != row.read<String>('set_id') ||
          !timer.active)
        invalid('Timing row identity mismatch.');
      result.add(timer);
    }
    return result;
  }

  @override
  Future<List<TimingActivity>> timingActivities({
    String? sessionId,
    String? idPrefix,
  }) => sessionId == null && idPrefix == null
      ? _cache.list('timingActivities', () => _timingActivities(null, null))
      : _timingActivities(sessionId, idPrefix);

  Future<List<TimingActivity>> _timingActivities(
    String? sessionId,
    String? idPrefix,
  ) async {
    final result = <TimingActivity>[];
    final query = _db.select(_db.timingActivities);
    if (sessionId != null) query.where((t) => t.sessionId.equals(sessionId));
    // LIKE treats '_' in identifiers as a wildcard: a superset, never a miss.
    if (idPrefix != null) query.where((t) => t.id.like('$idPrefix%'));
    for (final row in await query.get()) {
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
  Future<RepeatCheckpoint?> repeatCheckpoint(String id) async {
    final row = await (_db.select(
      _db.repeatCheckpoints,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    final result = RepeatCheckpoint.fromJson(jsonDecode(row.snapshot));
    if (result.id != row.id)
      invalid('Repeat checkpoint row identity mismatch.');
    return result;
  }

  @override
  Future<List<RepeatCheckpoint>> repeatCheckpoints() => _cache.list(
    'repeatCheckpoints',
    () async {
      final result = <RepeatCheckpoint>[];
      for (final row in await _db.select(_db.repeatCheckpoints).get()) {
        final checkpoint = RepeatCheckpoint.fromJson(jsonDecode(row.snapshot));
        if (checkpoint.id != row.id)
          invalid('Repeat checkpoint row identity mismatch.');
        result.add(checkpoint);
      }
      return result;
    },
  );

  @override
  Future<void> saveRepeatCheckpoint(RepeatCheckpoint checkpoint) async {
    await _db
        .into(_db.repeatCheckpoints)
        .insertOnConflictUpdate(
          RepeatCheckpointsCompanion.insert(
            id: checkpoint.id,
            snapshot: _snapshot(checkpoint.toJson()),
          ),
        );
  }

  @override
  Future<void> deleteRepeatCheckpoint(String id) async {
    await (_db.delete(
      _db.repeatCheckpoints,
    )..where((t) => t.id.equals(id))).go();
  }

  @override
  Future<WindowCheckpoint?> windowCheckpoint(String id) async {
    final row = await (_db.select(
      _db.windowCheckpoints,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    final checkpoint = WindowCheckpoint.fromJson(jsonDecode(row.snapshot));
    if (checkpoint.id != row.id || checkpoint.sessionId != row.sessionId)
      invalid('Window checkpoint row identity mismatch.');
    return checkpoint;
  }

  @override
  Future<List<WindowCheckpoint>> windowCheckpoints() => _cache.list(
    'windowCheckpoints',
    () async {
      final result = <WindowCheckpoint>[];
      for (final row in await _db.select(_db.windowCheckpoints).get()) {
        final checkpoint = WindowCheckpoint.fromJson(jsonDecode(row.snapshot));
        if (checkpoint.id != row.id || checkpoint.sessionId != row.sessionId)
          invalid('Window checkpoint row identity mismatch.');
        result.add(checkpoint);
      }
      return result;
    },
  );

  @override
  Future<void> saveWindowCheckpoint(WindowCheckpoint checkpoint) async {
    await _db
        .into(_db.windowCheckpoints)
        .insertOnConflictUpdate(
          WindowCheckpointsCompanion.insert(
            id: checkpoint.id,
            sessionId: checkpoint.sessionId,
            snapshot: _snapshot(checkpoint.toJson()),
          ),
        );
  }

  @override
  Future<void> deleteWindowCheckpoint(String id) async {
    await (_db.delete(
      _db.windowCheckpoints,
    )..where((t) => t.id.equals(id))).go();
  }

  ObservationRecord _observationRow(StoredObservation row) {
    final record = ObservationRecord.fromJson(jsonDecode(row.snapshot));
    if (record.observation.id != row.id ||
        record.observation.measureId != row.measureId ||
        record.observation.localDate != row.localDate)
      invalid('Observation row identity mismatch.');
    return record;
  }

  @override
  Future<List<ObservationRecord>> observationRecords({
    String? measureId,
    String? fromDate,
    String? untilDate,
  }) async {
    final query = _db.select(_db.observations)
      ..where(
        (t) =>
            (measureId == null
                ? const Constant(true)
                : t.measureId.equals(measureId)) &
            (fromDate == null
                ? const Constant(true)
                : t.localDate.isBiggerOrEqualValue(fromDate)) &
            (untilDate == null
                ? const Constant(true)
                : t.localDate.isSmallerThanValue(untilDate)),
      );
    return [for (final row in await query.get()) _observationRow(row)];
  }

  @override
  Future<ObservationRecord?> observationRecord(String id) async {
    final row = await (_db.select(
      _db.observations,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _observationRow(row);
  }

  @override
  Future<void> saveObservationRecord(ObservationRecord record) async {
    await _db
        .into(_db.observations)
        .insertOnConflictUpdate(
          ObservationsCompanion.insert(
            id: record.observation.id,
            measureId: record.observation.measureId,
            localDate: record.observation.localDate,
            snapshot: _snapshot(record.toJson()),
          ),
        );
  }

  @override
  Future<List<FoodRevision>> foodRevisions({String? foodId}) =>
      _cache.list('foodRevisions:${foodId ?? ''}', () async {
        final query = _db.select(_db.foodRevisions);
        if (foodId != null) query.where((t) => t.foodId.equals(foodId));
        query.orderBy([
          (t) => OrderingTerm(expression: t.foodId),
          (t) => OrderingTerm(expression: t.number),
        ]);
        return [
          for (final row in await query.get())
            (() {
              final r = FoodRevision.fromJson(jsonDecode(row.snapshot));
              if (r.food.id != row.foodId || r.number != row.number)
                invalid('Stored food revision identity is inconsistent.');
              return r;
            })(),
        ];
      });

  @override
  Future<void> insertFoodRevision(FoodRevision revision) => _db
      .into(_db.foodRevisions)
      .insert(
        FoodRevisionsCompanion.insert(
          foodId: revision.food.id,
          number: revision.number,
          snapshot: _snapshot(revision.toJson()),
        ),
      );

  DiaryEntry _diaryRow(StoredDiaryEntry row) {
    final e = DiaryEntry.fromJson(jsonDecode(row.snapshot));
    if (e.id != row.id || e.date != row.localDate)
      invalid('Diary entry row identity mismatch.');
    return e;
  }

  @override
  Future<List<DiaryEntry>> diaryEntries({
    String? fromDate,
    String? untilDate,
  }) async {
    final query = _db.select(_db.diaryEntries)
      ..where(
        (t) =>
            (fromDate == null
                ? const Constant(true)
                : t.localDate.isBiggerOrEqualValue(fromDate)) &
            (untilDate == null
                ? const Constant(true)
                : t.localDate.isSmallerThanValue(untilDate)),
      );
    final result = [for (final row in await query.get()) _diaryRow(row)];
    result.sort((a, b) {
      final t = a.instant.compareTo(b.instant);
      return t != 0 ? t : a.id.compareTo(b.id);
    });
    return result;
  }

  @override
  Future<DiaryEntry?> diaryEntry(String id) async {
    final row = await (_db.select(
      _db.diaryEntries,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _diaryRow(row);
  }

  @override
  Future<void> saveDiaryEntry(DiaryEntry entry) => _db
      .into(_db.diaryEntries)
      .insertOnConflictUpdate(
        DiaryEntriesCompanion.insert(
          id: entry.id,
          localDate: entry.date,
          snapshot: _snapshot(entry.toJson()),
        ),
      );

  @override
  Future<void> deleteDiaryEntry(String id) =>
      (_db.delete(_db.diaryEntries)..where((t) => t.id.equals(id))).go();

  @override
  Future<List<MeasureRevision>> measureRevisions() =>
      _cache.list('measureRevisions', () async {
        final result = <MeasureRevision>[];
        for (final row in await _db.select(_db.measureRevisions).get()) {
          final revision = MeasureRevision.fromJson(jsonDecode(row.snapshot));
          if (revision.measure.id != row.measureId ||
              revision.number != row.number)
            invalid('Stored measure revision identity is inconsistent.');
          result.add(revision);
        }
        validateMeasureRevisions(result);
        return result;
      });

  @override
  Future<void> insertMeasureRevision(MeasureRevision revision) => _db
      .into(_db.measureRevisions)
      .insert(
        MeasureRevisionsCompanion.insert(
          measureId: revision.measure.id,
          number: revision.number,
          snapshot: _snapshot(revision.toJson()),
        ),
      );

  @override
  Future<List<SeriesPolicy>> seriesPolicies() =>
      _cache.list('seriesPolicies', () async {
        final result = <SeriesPolicy>[];
        for (final row in await _db.select(_db.seriesPolicies).get()) {
          final policy = SeriesPolicy.fromJson(jsonDecode(row.snapshot));
          if (policy.key != row.seriesKey || policy.number != row.number)
            invalid('Stored series policy identity is inconsistent.');
          result.add(policy);
        }
        return result;
      });

  @override
  Future<void> insertSeriesPolicy(SeriesPolicy policy) => _db
      .into(_db.seriesPolicies)
      .insert(
        SeriesPoliciesCompanion.insert(
          seriesKey: policy.key,
          number: policy.number,
          snapshot: _snapshot(policy.toJson()),
        ),
      );

  @override
  Future<List<ProfileRevision>> profileRevisions() =>
      _cache.list('profileRevisions', () async {
        final result = <ProfileRevision>[];
        for (final row in await _db.select(_db.profileRevisions).get()) {
          final revision = ProfileRevision.fromJson(jsonDecode(row.snapshot));
          if (revision.number != row.number)
            invalid('Stored profile revision identity is inconsistent.');
          result.add(revision);
        }
        return result;
      });

  @override
  Future<void> insertProfileRevision(ProfileRevision revision) => _db
      .into(_db.profileRevisions)
      .insert(
        ProfileRevisionsCompanion.insert(
          number: Value(revision.number),
          snapshot: _snapshot(revision.toJson()),
        ),
      );

  @override
  Future<List<BodyFatSourceRevision>> bodyFatSourceRevisions() =>
      _cache.list('bodyFatSources', () async {
        final result = <BodyFatSourceRevision>[];
        for (final row in await _db.select(_db.bodyFatSources).get()) {
          final revision = BodyFatSourceRevision.fromJson(
            jsonDecode(row.snapshot),
          );
          if (revision.number != row.number)
            invalid('Stored body-fat source identity is inconsistent.');
          result.add(revision);
        }
        return result;
      });

  @override
  Future<void> insertBodyFatSourceRevision(BodyFatSourceRevision revision) =>
      _db
          .into(_db.bodyFatSources)
          .insert(
            BodyFatSourcesCompanion.insert(
              number: Value(revision.number),
              snapshot: _snapshot(revision.toJson()),
            ),
          );

  @override
  Future<List<DietRecord>> dietRecords({String? kind}) =>
      _cache.list('dietRecords:${kind ?? ''}', () async {
        final query = _db.select(_db.dietRecords);
        if (kind != null) query.where((t) => t.kind.equals(kind));
        final result = <DietRecord>[];
        for (final row in await query.get()) {
          final record = DietRecord(
            row.kind,
            row.id,
            row.number,
            jsonObject(jsonDecode(row.snapshot), 'snapshot'),
          );
          result.add(record);
        }
        result.sort((a, b) {
          final k = a.kind.compareTo(b.kind);
          if (k != 0) return k;
          final i = a.id.compareTo(b.id);
          return i != 0 ? i : a.number.compareTo(b.number);
        });
        return result;
      });

  @override
  Future<void> saveDietRecord(DietRecord record) => _db
      .into(_db.dietRecords)
      .insertOnConflictUpdate(
        DietRecordsCompanion.insert(
          kind: record.kind,
          id: record.id,
          number: record.number,
          snapshot: _snapshot(record.snapshot),
        ),
      );

  /// Body-mass records are observations of measure `body-mass`.
  @override
  Future<List<BodyMassRecord>> bodyMassRecords() =>
      _cache.list('bodyMassRecords', () async {
        return [
          for (final r in await observationRecords(measureId: 'body-mass'))
            BodyMassRecord(r.observation.toBodyMass(), deleted: r.deleted),
        ];
      });

  @override
  Future<void> saveBodyMassRecord(BodyMassRecord record) async {
    final existing = await observationRecord(record.measurement.id);
    if (existing != null && !existing.observation.isBodyMass)
      throw BodyTmiException(
        'conflict',
        'Observation ${record.measurement.id} belongs to another measure.',
      );
    await saveObservationRecord(
      ObservationRecord(
        Observation.fromBodyMass(record.measurement),
        deleted: record.deleted,
      ),
    );
  }

  @override
  Future<List<BlockProgressionDecision>> blockProgressions() =>
      _cache.list('blockProgressions', () async {
        final result = <BlockProgressionDecision>[];
        for (final row in await _db.select(_db.blockProgressions).get()) {
          final decision = BlockProgressionDecision.fromJson(
            jsonDecode(row.snapshot),
          );
          if (decision.id != row.id)
            invalid('Stored block progression identity is inconsistent.');
          result.add(decision);
        }
        return result;
      });

  @override
  Future<void> saveBlockProgression(BlockProgressionDecision decision) async {
    await _db
        .into(_db.blockProgressions)
        .insertOnConflictUpdate(
          BlockProgressionsCompanion.insert(
            id: decision.id,
            snapshot: _snapshot(decision.toJson()),
          ),
        );
  }

  @override
  Future<List<ImportedSessionRecord>> importedSessions() async {
    final result = <ImportedSessionRecord>[];
    for (final row in await _db.select(_db.importedSessions).get()) {
      final record = ImportedSessionRecord.fromJson(jsonDecode(row.snapshot));
      if (record.namespace != row.namespace || record.sourceId != row.sourceId)
        invalid('Stored imported session identity is inconsistent.');
      result.add(record);
    }
    validateImportedSessions(result);
    return result;
  }

  @override
  Future<void> saveImportedSession(ImportedSessionRecord record) async {
    await _db
        .into(_db.importedSessions)
        .insertOnConflictUpdate(
          ImportedSessionsCompanion.insert(
            namespace: record.namespace,
            sourceId: record.sourceId,
            snapshot: _snapshot(record.toJson()),
          ),
        );
  }

  @override
  Future<void> deleteImportedSession(String namespace, String sourceId) async {
    await (_db.delete(_db.importedSessions)..where(
          (t) => t.namespace.equals(namespace) & t.sourceId.equals(sourceId),
        ))
        .go();
  }

  @override
  Future<List<ProgramReceipt>> programReceipts() =>
      _cache.list('programReceipts', () async {
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
      });

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
  Future<List<ProgramUpgradeReceipt>> programUpgrades() =>
      _cache.list('programUpgrades', () async {
        final result = <ProgramUpgradeReceipt>[];
        for (final row in await _db.select(_db.programUpgradeReceipts).get()) {
          final r = ProgramUpgradeReceipt.fromJson(jsonDecode(row.snapshot));
          if (r.runId != row.runId || r.requestId != row.requestId)
            invalid('Stored program upgrade identity mismatch.');
          result.add(r);
        }
        return result;
      });

  @override
  Future<void> insertProgramUpgrade(ProgramUpgradeReceipt receipt) async {
    await _db
        .into(_db.programUpgradeReceipts)
        .insert(
          ProgramUpgradeReceiptsCompanion.insert(
            runId: receipt.runId,
            requestId: receipt.requestId,
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
    return row == null ? null : _session(row);
  }

  TrainingSession _session(rows.Session row) {
    final session = sessionFromJson(jsonDecode(row.snapshot));
    if (session.id != row.id || session.definition.id != row.templateId)
      invalid('Stored session identity is inconsistent.');
    return session;
  }

  @override
  Future<List<TrainingSession>> sessions({String? templateId}) =>
      templateId == null
      ? _cache.list('sessions', () => _sessions(null))
      : _cache.list('sessions/$templateId', () => _sessions(templateId));

  Future<List<TrainingSession>> _sessions(String? templateId) async {
    final query = _db.select(_db.sessions)
      ..orderBy([(s) => OrderingTerm.asc(s.id)]);
    if (templateId != null) query.where((s) => s.templateId.equals(templateId));
    return [for (final row in await query.get()) _session(row)];
  }

  @override
  Future<void> insertSession(TrainingSession session) async {
    await _db
        .into(_db.sessions)
        .insert(
          SessionsCompanion.insert(
            id: session.id,
            templateId: session.definition.id,
            snapshot: _snapshot(session.toJson()),
          ),
        );
  }

  @override
  Future<void> updateSession(TrainingSession session) async {
    await (_db.update(
      _db.sessions,
    )..where((s) => s.id.equals(session.id))).write(
      SessionsCompanion(
        templateId: Value(session.definition.id),
        snapshot: Value(_snapshot(session.toJson())),
      ),
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

String _snapshot(Object? value) {
  final json = canonicalJson(value);
  if (utf8.encode(json).length > 8 * 1024 * 1024)
    invalid('Stored snapshot exceeds 8 MiB.');
  return json;
}
