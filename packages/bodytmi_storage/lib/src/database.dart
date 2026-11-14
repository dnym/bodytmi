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
  ],
)
class TrainingDatabase extends _$TrainingDatabase {
  TrainingDatabase(super.executor);
  @override
  int get schemaVersion => 65;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => transaction(() async {
      await m.createAll();
      await customStatement('PRAGMA application_id = 1112821065');
      await customStatement('PRAGMA user_version = 65');
      await validateMigration();
    }),
    onUpgrade: (m, from, to) async {
      if (!{
            1,
            2,
            3,
            4,
            5,
            6,
            7,
            8,
            9,
            10,
            11,
            12,
            13,
            14,
            15,
            16,
            17,
            18,
            19,
            20,
            21,
            22,
            23,
            24,
            25,
            26,
            27,
            28,
            29,
            30,
            31,
            32,
            33,
            34,
            35,
            36,
            37,
            38,
            39,
            40,
            41,
            42,
            43,
            44,
            45,
            46,
            47,
            48,
            49,
            50,
            51,
            52,
            53,
            54,
            55,
            56,
            57,
            58,
            59,
            60,
            61,
            62,
            63,
            64,
          }.contains(from) ||
          to != 65)
        throw StateError('Unsupported database migration $from -> $to.');
      await transaction(() async {
        final schema = await customSelect(
          'SELECT name,sql FROM sqlite_master WHERE sql IS NOT NULL',
        ).get();
        validateSchema(schema.map((row) => row.data), from);
        if (from == 1) await m.createTable(progressionDecisions);
        if (from < 3) {
          await m.createTable(programRevisions);
          await m.createTable(programRuns);
          await m.createTable(sessionPrograms);
          await m.createTable(programReceipts);
        }
        if (from < 4) await m.createTable(bodyMassRecords);
        if (from < 7) await m.createTable(timingActivities);
        if (from < 8) await m.createTable(workoutExecutions);
        if (from < 12) await m.createTable(familyRevisions);
        if (from < 27) await m.createTable(derivedTargetGraphs);
        if (from < 46) await m.createTable(windowCheckpoints);
        if (from < 48) await m.createTable(repeatCheckpoints);
        if (from < 52) await m.createTable(progressionReconciliations);
        if (from < 53) await m.createTable(leverLinkRevisions);
        if (from < 56) await m.createTable(programUpgradeReceipts);
        if (from < 54) {
          await m.createTable(sharedLeverApplications);
          await m.createTable(linkRetirementAnchors);
        }
        if (from < 58) {
          await m.createTable(exerciseRevisions);
          await m.createTable(implementationRevisions);
        }
        if (from < 59) {
          await m.createTable(equipmentRevisions);
          await m.createTable(gymRevisions);
          await m.createTable(equipmentInstanceRevisions);
        }
        if (from < 64) await m.createTable(importedSessions);
        // Drift also writes this after the callback. Writing it within our
        // transaction prevents a crash leaving new DDL with the old version.
        await customStatement('PRAGMA user_version = 65');
        await validateMigration();
      });
    },
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
    validateSchema(schema.map((row) => row.data), 65);
    if ((await customSelect('PRAGMA foreign_key_check').get()).isNotEmpty) {
      throw const BodyTmiException(
        'storage',
        'Migration found inconsistent references.',
      );
    }
  }
}
