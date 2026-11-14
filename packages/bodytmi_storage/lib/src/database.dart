import 'package:drift/drift.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'schema.dart';

part 'database.g.dart';

class Revisions extends Table {
  TextColumn get templateId => text()();
  IntColumn get number => integer()();
  TextColumn get snapshot => text()();
  @override
  Set<Column> get primaryKey => {templateId, number};
}

@DataClassName('StoredFamilyRevision')
class FamilyRevisions extends Table {
  TextColumn get familyId => text()();
  IntColumn get number => integer()();
  TextColumn get snapshot => text()();
  @override
  Set<Column> get primaryKey => {familyId, number};
}

@DataClassName('StoredExerciseRevision')
class ExerciseRevisions extends Table {
  TextColumn get exerciseId => text()();
  IntColumn get number => integer()();
  TextColumn get snapshot => text()();
  @override
  Set<Column> get primaryKey => {exerciseId, number};
}

@DataClassName('StoredImplementationRevision')
class ImplementationRevisions extends Table {
  TextColumn get implementationId => text()();
  IntColumn get number => integer()();
  TextColumn get snapshot => text()();
  @override
  Set<Column> get primaryKey => {implementationId, number};
}

@DataClassName('StoredEquipmentRevision')
class EquipmentRevisions extends Table {
  TextColumn get equipmentId => text()();
  IntColumn get number => integer()();
  TextColumn get snapshot => text()();
  @override
  Set<Column> get primaryKey => {equipmentId, number};
}

@DataClassName('StoredGymRevision')
class GymRevisions extends Table {
  TextColumn get gymId => text()();
  IntColumn get number => integer()();
  TextColumn get snapshot => text()();
  @override
  Set<Column> get primaryKey => {gymId, number};
}

@DataClassName('StoredEquipmentInstanceRevision')
class EquipmentInstanceRevisions extends Table {
  TextColumn get instanceId => text()();
  IntColumn get number => integer()();
  TextColumn get snapshot => text()();
  @override
  Set<Column> get primaryKey => {instanceId, number};
}

class Sessions extends Table {
  TextColumn get id => text()();
  TextColumn get snapshot => text()();
  @override
  Set<Column> get primaryKey => {id};
}

/// Stable finalization identity survives edits. It is not a progression approval.
class Finalizations extends Table {
  TextColumn get sessionId => text().references(Sessions, #id)();
  @override
  Set<Column> get primaryKey => {sessionId};
}

class ProgressionDecisions extends Table {
  TextColumn get sessionId => text().references(Sessions, #id)();
  TextColumn get slotId => text()();
  TextColumn get snapshot => text()();
  @override
  Set<Column> get primaryKey => {sessionId, slotId};
}

class ProgramRevisions extends Table {
  TextColumn get programId => text()();
  IntColumn get number => integer()();
  TextColumn get snapshot => text()();
  @override
  Set<Column> get primaryKey => {programId, number};
}

class ProgramRuns extends Table {
  TextColumn get id => text()();
  TextColumn get snapshot => text()();
  @override
  Set<Column> get primaryKey => {id};
}

class SessionPrograms extends Table {
  TextColumn get sessionId => text().references(Sessions, #id)();
  TextColumn get runId => text().references(ProgramRuns, #id)();
  IntColumn get ordinal => integer()();
  TextColumn get snapshot => text()();
  @override
  Set<Column> get primaryKey => {sessionId};
  @override
  List<Set<Column>> get uniqueKeys => [
    {runId, ordinal},
  ];
}

class ProgramReceipts extends Table {
  TextColumn get runId => text().references(ProgramRuns, #id)();
  IntColumn get ordinal => integer()();
  TextColumn get operationKey => text()();
  TextColumn get sessionId => text().nullable().references(Sessions, #id)();
  TextColumn get snapshot => text()();
  @override
  Set<Column> get primaryKey => {runId, ordinal};
  @override
  List<Set<Column>> get uniqueKeys => [
    {runId, operationKey},
  ];
}

class BodyMassRecords extends Table {
  TextColumn get id => text()();
  TextColumn get snapshot => text()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('StoredBlockProgression')
class BlockProgressions extends Table {
  TextColumn get id => text()();
  TextColumn get snapshot => text()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('StoredImportedSession')
class ImportedSessions extends Table {
  TextColumn get namespace => text()();
  TextColumn get sourceId => text()();
  TextColumn get snapshot => text()();
  @override
  Set<Column> get primaryKey => {namespace, sourceId};
}

@DataClassName('StoredDerivedTargetGraphRevision')
class DerivedTargetGraphs extends Table {
  TextColumn get graphId => text()();
  IntColumn get number => integer()();
  TextColumn get snapshot => text()();
  @override
  Set<Column> get primaryKey => {graphId, number};
}

class TimingActivities extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text().references(Sessions, #id)();
  TextColumn get setId => text()();
  TextColumn get snapshot => text()();
  @override
  Set<Column> get primaryKey => {id};
}

class WorkoutExecutions extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text().references(Sessions, #id)();
  TextColumn get snapshot => text()();
  @override
  Set<Column> get primaryKey => {id};
  @override
  List<Set<Column>> get uniqueKeys => [
    {sessionId},
  ];
}

@DataClassName('StoredWindowCheckpoint')
class WindowCheckpoints extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text().references(Sessions, #id)();
  TextColumn get snapshot => text()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('StoredRepeatCheckpoint')
class RepeatCheckpoints extends Table {
  TextColumn get id => text()();
  TextColumn get snapshot => text()();
  @override
  Set<Column> get primaryKey => {id};
}

class ProgressionReconciliations extends Table {
  TextColumn get id => text()();
  TextColumn get snapshot => text()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('StoredLeverLinkRevision')
class LeverLinkRevisions extends Table {
  TextColumn get linkId => text()();
  IntColumn get number => integer()();
  TextColumn get snapshot => text()();
  @override
  Set<Column> get primaryKey => {linkId, number};
}

@DataClassName('StoredSharedLeverApplication')
class SharedLeverApplications extends Table {
  TextColumn get linkId => text()();
  IntColumn get sequence => integer()();
  TextColumn get snapshot => text()();
  @override
  Set<Column> get primaryKey => {linkId, sequence};
}

@DataClassName('StoredLinkRetirementAnchor')
class LinkRetirementAnchors extends Table {
  TextColumn get id => text()();
  TextColumn get snapshot => text()();
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('StoredProgramUpgradeReceipt')
class ProgramUpgradeReceipts extends Table {
  TextColumn get runId => text()();
  TextColumn get requestId => text()();
  TextColumn get snapshot => text()();
  @override
  Set<Column> get primaryKey => {runId, requestId};
}

@DriftDatabase(
  tables: [
    Revisions,
    FamilyRevisions,
    ExerciseRevisions,
    ImplementationRevisions,
    EquipmentRevisions,
    GymRevisions,
    EquipmentInstanceRevisions,
    Sessions,
    Finalizations,
    ProgressionDecisions,
    ProgramRevisions,
    ProgramRuns,
    SessionPrograms,
    ProgramReceipts,
    BodyMassRecords,
    TimingActivities,
    WorkoutExecutions,
    DerivedTargetGraphs,
    WindowCheckpoints,
    RepeatCheckpoints,
    ProgressionReconciliations,
    LeverLinkRevisions,
    SharedLeverApplications,
    LinkRetirementAnchors,
    ProgramUpgradeReceipts,
    ImportedSessions,
    BlockProgressions,
  ],
)
class TrainingDatabase extends _$TrainingDatabase {
  TrainingDatabase(super.executor);
  @override
  int get schemaVersion => supportedSchemaVersion;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => transaction(() async {
      await m.createAll();
      await customStatement('PRAGMA application_id = 1112821065');
      await customStatement('PRAGMA user_version = $supportedSchemaVersion');
      await validateMigration();
    }),
    // There are no historical schema versions. A future upgrade adds its
    // steps here: the DDL, the user_version write and validation all run in
    // one transaction, so a crash leaves the previous schema intact.
    onUpgrade: (m, from, to) => transaction(() async {
      throw StateError('Unsupported database migration $from -> $to.');
    }),
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA synchronous = FULL');
      await customStatement('PRAGMA journal_mode = WAL');
    },
  );

  /// Called before committing schema creation/upgrade, also instrumented by the
  /// native crash test to terminate while the real migration transaction is open.
  Future<void> validateMigration() async {
    final schema = await customSelect(
      'SELECT name,sql FROM sqlite_master WHERE sql IS NOT NULL',
    ).get();
    validateSchema(schema.map((row) => row.data));
    if ((await customSelect('PRAGMA foreign_key_check').get()).isNotEmpty) {
      throw const BodyTmiException(
        'storage',
        'Migration found inconsistent references.',
      );
    }
  }
}
