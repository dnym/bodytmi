import 'package:bodytmi_core/bodytmi_core.dart';

/// Exact DDL for the existing v1 schema, also checked against Drift-created files.
/// Add a versioned migration and portability mapping when changing this schema.
const schemaV1 = {
  'finalizations':
      'CREATE TABLE "finalizations" ("session_id" TEXT NOT NULL REFERENCES sessions (id), PRIMARY KEY ("session_id"))',
  'revisions':
      'CREATE TABLE "revisions" ("template_id" TEXT NOT NULL, "number" INTEGER NOT NULL, "snapshot" TEXT NOT NULL, PRIMARY KEY ("template_id", "number"))',
  'sessions':
      'CREATE TABLE "sessions" ("id" TEXT NOT NULL, "snapshot" TEXT NOT NULL, PRIMARY KEY ("id"))',
};

void validateSchemaV1(Iterable<Map<String, Object?>> rows) {
  if (rows.length != schemaV1.length ||
      rows.any((row) => schemaV1[row['name']] != row['sql'])) {
    invalid('Database schema does not match supported schema v1.');
  }
}
