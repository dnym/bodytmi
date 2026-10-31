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

const schemaV3 = {
  ...schemaV2,
  'program_revisions':
      'CREATE TABLE "program_revisions" ("program_id" TEXT NOT NULL, "number" INTEGER NOT NULL, "snapshot" TEXT NOT NULL, PRIMARY KEY ("program_id", "number"))',
  'program_runs':
      'CREATE TABLE "program_runs" ("id" TEXT NOT NULL, "snapshot" TEXT NOT NULL, PRIMARY KEY ("id"))',
  'session_programs':
      'CREATE TABLE "session_programs" ("session_id" TEXT NOT NULL REFERENCES sessions (id), "run_id" TEXT NOT NULL REFERENCES program_runs (id), "ordinal" INTEGER NOT NULL, "snapshot" TEXT NOT NULL, PRIMARY KEY ("session_id"), UNIQUE ("run_id", "ordinal"))',
  'program_receipts':
      'CREATE TABLE "program_receipts" ("run_id" TEXT NOT NULL REFERENCES program_runs (id), "ordinal" INTEGER NOT NULL, "operation_key" TEXT NOT NULL, "session_id" TEXT NULL REFERENCES sessions (id), "snapshot" TEXT NOT NULL, PRIMARY KEY ("run_id", "ordinal"), UNIQUE ("run_id", "operation_key"))',
};

const schemaV4 = {
  ...schemaV3,
  'body_mass_records':
      'CREATE TABLE "body_mass_records" ("id" TEXT NOT NULL, "snapshot" TEXT NOT NULL, PRIMARY KEY ("id"))',
};

Map<String, String> schemaForVersion(int version) => switch (version) {
  1 => schemaV1,
  2 => schemaV2,
  3 => schemaV3,
  4 => schemaV4,
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
