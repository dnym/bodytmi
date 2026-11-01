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

@DriftDatabase(
  tables: [
    Revisions,
    FamilyRevisions,
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
  ],
)
class TrainingDatabase extends _$TrainingDatabase {
  TrainingDatabase(super.executor);
  @override
  int get schemaVersion => 21;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => transaction(() async {
      await m.createAll();
      await customStatement('PRAGMA application_id = 1112821065');
      await customStatement('PRAGMA user_version = 21');
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
          }.contains(from) ||
          to != 21)
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
        // Drift also writes this after the callback. Writing it within our
        // transaction prevents a crash leaving new DDL with the old version.
        await customStatement('PRAGMA user_version = 21');
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
    validateSchema(schema.map((row) => row.data), 21);
    if ((await customSelect('PRAGMA foreign_key_check').get()).isNotEmpty) {
      throw const BodyTmiException(
        'storage',
        'Migration found inconsistent references.',
      );
    }
  }
}
