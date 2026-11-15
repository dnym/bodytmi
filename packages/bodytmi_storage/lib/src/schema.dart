import 'package:bodytmi_core/bodytmi_core.dart';

/// The single supported database schema version. Until the owner starts
/// using the app for real, schema changes edit [schema] in place and scratch
/// databases are recreated; there are no historical versions or migrations.
const supportedSchemaVersion = 1;

/// Exact supported DDL, also checked against actual Drift-created files.
const schema = {
  'block_progressions':
      'CREATE TABLE "block_progressions" ("id" TEXT NOT NULL, "snapshot" TEXT NOT NULL, PRIMARY KEY ("id"))',
  'body_mass_records':
      'CREATE TABLE "body_mass_records" ("id" TEXT NOT NULL, "snapshot" TEXT NOT NULL, PRIMARY KEY ("id"))',
  'derived_target_graphs':
      'CREATE TABLE "derived_target_graphs" ("graph_id" TEXT NOT NULL, "number" INTEGER NOT NULL, "snapshot" TEXT NOT NULL, PRIMARY KEY ("graph_id", "number"))',
  'equipment_instance_revisions':
      'CREATE TABLE "equipment_instance_revisions" ("instance_id" TEXT NOT NULL, "number" INTEGER NOT NULL, "snapshot" TEXT NOT NULL, PRIMARY KEY ("instance_id", "number"))',
  'equipment_revisions':
      'CREATE TABLE "equipment_revisions" ("equipment_id" TEXT NOT NULL, "number" INTEGER NOT NULL, "snapshot" TEXT NOT NULL, PRIMARY KEY ("equipment_id", "number"))',
  'exercise_revisions':
      'CREATE TABLE "exercise_revisions" ("exercise_id" TEXT NOT NULL, "number" INTEGER NOT NULL, "snapshot" TEXT NOT NULL, PRIMARY KEY ("exercise_id", "number"))',
  'family_revisions':
      'CREATE TABLE "family_revisions" ("family_id" TEXT NOT NULL, "number" INTEGER NOT NULL, "snapshot" TEXT NOT NULL, PRIMARY KEY ("family_id", "number"))',
  'finalizations':
      'CREATE TABLE "finalizations" ("session_id" TEXT NOT NULL REFERENCES sessions (id), PRIMARY KEY ("session_id"))',
  'gym_revisions':
      'CREATE TABLE "gym_revisions" ("gym_id" TEXT NOT NULL, "number" INTEGER NOT NULL, "snapshot" TEXT NOT NULL, PRIMARY KEY ("gym_id", "number"))',
  'implementation_revisions':
      'CREATE TABLE "implementation_revisions" ("implementation_id" TEXT NOT NULL, "number" INTEGER NOT NULL, "snapshot" TEXT NOT NULL, PRIMARY KEY ("implementation_id", "number"))',
  'imported_sessions':
      'CREATE TABLE "imported_sessions" ("namespace" TEXT NOT NULL, "source_id" TEXT NOT NULL, "snapshot" TEXT NOT NULL, PRIMARY KEY ("namespace", "source_id"))',
  'lever_link_revisions':
      'CREATE TABLE "lever_link_revisions" ("link_id" TEXT NOT NULL, "number" INTEGER NOT NULL, "snapshot" TEXT NOT NULL, PRIMARY KEY ("link_id", "number"))',
  'link_retirement_anchors':
      'CREATE TABLE "link_retirement_anchors" ("id" TEXT NOT NULL, "snapshot" TEXT NOT NULL, PRIMARY KEY ("id"))',
  'progression_preset_revisions':
      'CREATE TABLE "progression_preset_revisions" ("preset_id" TEXT NOT NULL, "number" INTEGER NOT NULL, "snapshot" TEXT NOT NULL, PRIMARY KEY ("preset_id", "number"))',
  'program_receipts':
      'CREATE TABLE "program_receipts" ("run_id" TEXT NOT NULL REFERENCES program_runs (id), "ordinal" INTEGER NOT NULL, "operation_key" TEXT NOT NULL, "session_id" TEXT NULL REFERENCES sessions (id), "snapshot" TEXT NOT NULL, PRIMARY KEY ("run_id", "ordinal"), UNIQUE ("run_id", "operation_key"))',
  'program_revisions':
      'CREATE TABLE "program_revisions" ("program_id" TEXT NOT NULL, "number" INTEGER NOT NULL, "snapshot" TEXT NOT NULL, PRIMARY KEY ("program_id", "number"))',
  'program_runs':
      'CREATE TABLE "program_runs" ("id" TEXT NOT NULL, "snapshot" TEXT NOT NULL, PRIMARY KEY ("id"))',
  'program_upgrade_receipts':
      'CREATE TABLE "program_upgrade_receipts" ("run_id" TEXT NOT NULL, "request_id" TEXT NOT NULL, "snapshot" TEXT NOT NULL, PRIMARY KEY ("run_id", "request_id"))',
  'progression_decisions':
      'CREATE TABLE "progression_decisions" ("session_id" TEXT NOT NULL REFERENCES sessions (id), "slot_id" TEXT NOT NULL, "template_id" TEXT NOT NULL, "run_id" TEXT NULL, "sequence" INTEGER NOT NULL, "snapshot" TEXT NOT NULL, PRIMARY KEY ("session_id", "slot_id"))',
  // Indexes follow their table: the staged restore runs these in order.
  'progression_decisions_track':
      'CREATE INDEX progression_decisions_track ON progression_decisions (template_id, slot_id, run_id, sequence)',
  'progression_reconciliations':
      'CREATE TABLE "progression_reconciliations" ("id" TEXT NOT NULL, "snapshot" TEXT NOT NULL, PRIMARY KEY ("id"))',
  'repeat_checkpoints':
      'CREATE TABLE "repeat_checkpoints" ("id" TEXT NOT NULL, "snapshot" TEXT NOT NULL, PRIMARY KEY ("id"))',
  'revisions':
      'CREATE TABLE "revisions" ("template_id" TEXT NOT NULL, "number" INTEGER NOT NULL, "snapshot" TEXT NOT NULL, PRIMARY KEY ("template_id", "number"))',
  'session_programs':
      'CREATE TABLE "session_programs" ("session_id" TEXT NOT NULL REFERENCES sessions (id), "run_id" TEXT NOT NULL REFERENCES program_runs (id), "ordinal" INTEGER NOT NULL, "snapshot" TEXT NOT NULL, PRIMARY KEY ("session_id"), UNIQUE ("run_id", "ordinal"))',
  'sessions':
      'CREATE TABLE "sessions" ("id" TEXT NOT NULL, "template_id" TEXT NOT NULL, "snapshot" TEXT NOT NULL, PRIMARY KEY ("id"))',
  'sessions_template':
      'CREATE INDEX sessions_template ON sessions (template_id)',
  'shared_lever_applications':
      'CREATE TABLE "shared_lever_applications" ("link_id" TEXT NOT NULL, "sequence" INTEGER NOT NULL, "snapshot" TEXT NOT NULL, PRIMARY KEY ("link_id", "sequence"))',
  'timing_activities':
      'CREATE TABLE "timing_activities" ("id" TEXT NOT NULL, "session_id" TEXT NOT NULL REFERENCES sessions (id), "set_id" TEXT NOT NULL, "snapshot" TEXT NOT NULL, PRIMARY KEY ("id"))',
  'window_checkpoints':
      'CREATE TABLE "window_checkpoints" ("id" TEXT NOT NULL, "session_id" TEXT NOT NULL REFERENCES sessions (id), "snapshot" TEXT NOT NULL, PRIMARY KEY ("id"))',
  'workout_executions':
      'CREATE TABLE "workout_executions" ("id" TEXT NOT NULL, "session_id" TEXT NOT NULL REFERENCES sessions (id), "snapshot" TEXT NOT NULL, PRIMARY KEY ("id"), UNIQUE ("session_id"))',
};

void validateSchema(Iterable<Map<String, Object?>> rows) {
  if (rows.length != schema.length ||
      rows.any((row) => schema[row['name']] != row['sql'])) {
    invalid(
      'Database schema does not match supported schema v$supportedSchemaVersion.',
    );
  }
}
