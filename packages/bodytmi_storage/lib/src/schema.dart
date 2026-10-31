import 'package:bodytmi_core/bodytmi_core.dart';

/// Exact supported DDL, also checked against actual Drift-created files.
/// Add a versioned migration and portability mapping when changing this schema.
const schemaV1 = {
  'finalizations':
      'CREATE TABLE "finalizations" ("session_id" TEXT NOT NULL REFERENCES sessions (id), PRIMARY KEY ("session_id"))',
  'revisions':
      'CREATE TABLE "revisions" ("template_id" TEXT NOT NULL, "number" INTEGER NOT NULL, "snapshot" TEXT NOT NULL, PRIMARY KEY ("template_id", "number"))',
  'sessions':
      'CREATE TABLE "sessions" ("id" TEXT NOT NULL, "snapshot" TEXT NOT NULL, PRIMARY KEY ("id"))',
};

const schemaV2 = {
  ...schemaV1,
  'progression_decisions':
      'CREATE TABLE "progression_decisions" ("session_id" TEXT NOT NULL REFERENCES sessions (id), "slot_id" TEXT NOT NULL, "snapshot" TEXT NOT NULL, PRIMARY KEY ("session_id", "slot_id"))',
};

Map<String, String> schemaForVersion(int version) => switch (version) {
  1 => schemaV1,
  2 => schemaV2,
  _ => throw const BodyTmiException(
    'validation',
    'Unsupported database schema.',
  ),
};

void validateSchema(Iterable<Map<String, Object?>> rows, int version) {
  final expected = schemaForVersion(version);
  if (rows.length != expected.length ||
      rows.any((row) => expected[row['name']] != row['sql'])) {
    invalid('Database schema does not match supported schema v$version.');
  }
}
