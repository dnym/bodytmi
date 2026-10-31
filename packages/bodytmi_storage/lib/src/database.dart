import 'package:drift/drift.dart';

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

@DriftDatabase(tables: [Revisions, Sessions, Finalizations])
class TrainingDatabase extends _$TrainingDatabase {
  TrainingDatabase(super.executor);
  @override
  int get schemaVersion => 1;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await customStatement('PRAGMA application_id = 1112821065');
    },
    onUpgrade: (m, from, to) async =>
        throw StateError('Unsupported database migration $from -> $to.'),
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA synchronous = FULL');
      await customStatement('PRAGMA journal_mode = WAL');
    },
  );
}
