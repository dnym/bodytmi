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

const schemaV7 = {
  ...schemaV4,
  'timing_activities':
      'CREATE TABLE "timing_activities" ("id" TEXT NOT NULL, "session_id" TEXT NOT NULL REFERENCES sessions (id), "set_id" TEXT NOT NULL, "snapshot" TEXT NOT NULL, PRIMARY KEY ("id"))',
};

const schemaV8 = {
  ...schemaV7,
  'workout_executions':
      'CREATE TABLE "workout_executions" ("id" TEXT NOT NULL, "session_id" TEXT NOT NULL REFERENCES sessions (id), "snapshot" TEXT NOT NULL, PRIMARY KEY ("id"), UNIQUE ("session_id"))',
};

const schemaV12 = {
  ...schemaV8,
  'family_revisions':
      'CREATE TABLE "family_revisions" ("family_id" TEXT NOT NULL, "number" INTEGER NOT NULL, "snapshot" TEXT NOT NULL, PRIMARY KEY ("family_id", "number"))',
};

Map<String, String> schemaForVersion(int version) => switch (version) {
  1 => schemaV1,
  2 => schemaV2,
  3 => schemaV3,
  4 => schemaV4,
  5 => schemaV4, // Same tables; v5 adds frozen body-mass session payloads.
  6 => schemaV4, // Same tables; v6 adds pinned effective-mass models.
  7 => schemaV7,
  8 => schemaV8,
  9 => schemaV8, // Same tables; v9 adds atomic group-skip receipt payloads.
  10 => schemaV8, // Same tables; v10 adds tempo timing plans.
  11 => schemaV8, // Same tables; v11 adds terminal progression declines.
  12 => schemaV12,
  13 => schemaV12, // Same tables; v13 adds pinned slot timing defaults.
  14 =>
    schemaV12, // Same tables; v14 adds durable vector threshold coordination.
  15 =>
    schemaV12, // Same tables; v15 adds explicit result aggregation policies.
  16 =>
    schemaV12, // Same tables; v16 adds numeric harder directions and lower bounds.
  17 => schemaV12, // Same tables; v17 adds chosen/priority vector coordination.
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
