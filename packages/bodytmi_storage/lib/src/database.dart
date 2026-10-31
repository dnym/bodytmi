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

@DriftDatabase(
  tables: [Revisions, Sessions, Finalizations, ProgressionDecisions],
)
class TrainingDatabase extends _$TrainingDatabase {
  TrainingDatabase(super.executor);
  @override
  int get schemaVersion => 2;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => transaction(() async {
      await m.createAll();
      await customStatement('PRAGMA application_id = 1112821065');
      await customStatement('PRAGMA user_version = 2');
      await validateMigration();
    }),
    onUpgrade: (m, from, to) async {
      if (from != 1 || to != 2)
        throw StateError('Unsupported database migration $from -> $to.');
      await transaction(() async {
        final schema = await customSelect(
          'SELECT name,sql FROM sqlite_master WHERE sql IS NOT NULL',
        ).get();
        validateSchema(schema.map((row) => row.data), 1);
        await m.createTable(progressionDecisions);
        // Drift also writes this after the callback. Writing it within our
        // transaction prevents a crash leaving new DDL with the old version.
        await customStatement('PRAGMA user_version = 2');
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
    validateSchema(schema.map((row) => row.data), 2);
    if ((await customSelect('PRAGMA foreign_key_check').get()).isNotEmpty) {
      throw const BodyTmiException(
        'storage',
        'Migration found inconsistent references.',
      );
    }
  }
}
