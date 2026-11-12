import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'schema.dart';

const _format = 'bodytmi-native-backup/1';
const _maxDatabaseBytes = 512 * 1024 * 1024;
const _maxSnapshotBytes = 8 * 1024 * 1024;
const _snapshotName = 'database.sqlite';

/// Native backup v1 is an uncompressed directory with exactly two regular files.
/// Attachments/settings outside SQLite are not part of the current application.
final class NativeBackup {
  const NativeBackup._();

  /// Caller must own [databasePath] until this completes.
  static Future<Map<String, Object?>> create(
    String databasePath,
    String destination,
  ) async {
    final output = Directory(destination).absolute;
    if (await FileSystemEntity.type(output.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const BodyTmiException(
        'conflict',
        'Backup destination already exists.',
      );
    }
    await output.parent.create(recursive: true);
    final stage = await output.parent.createTemp('.bodytmi-backup-');
    try {
      final snapshot = File('${stage.path}/$_snapshotName');
      await copyDatabase(databasePath, snapshot.path, standalone: true);
      final size = await snapshot.length();
      if (size > _maxDatabaseBytes)
        invalid('Backup exceeds the 512 MiB resource limit.');
      final schemaVersion = validateDatabase(snapshot.path);
      final manifest = <String, Object?>{
        'format': _format,
        'applicationVersion': '0.1.0',
        'databaseSchemaVersion': schemaVersion,
        'database': {
          'file': _snapshotName,
          'bytes': size,
          'sha256': await _digest(snapshot),
        },
      };
      await File(
        '${stage.path}/manifest.json',
      ).writeAsString(jsonEncode(manifest), flush: true);
      // Completed directory publication is one filesystem rename. An interrupted
      // build leaves an unpublished .bodytmi-backup-* directory, never a valid backup.
      if (await FileSystemEntity.type(output.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw const BodyTmiException(
          'conflict',
          'Backup destination already exists.',
        );
      }
      await stage.rename(output.path);
      return manifest;
    } finally {
      if (await stage.exists()) await stage.delete(recursive: true);
    }
  }

  /// Copy and validate before obtaining/changing the destination profile.
  /// The private copy also isolates restoration from later source-file changes.
  static Future<PreparedNativeBackup> prepare(String source) async {
    final directory = Directory(source);
    final sourceDirectory = await directory.resolveSymbolicLinks();
    final members = await directory.list(followLinks: false).take(3).toList();
    if (members.length != 2 ||
        members.any((e) => e is! File) ||
        !await File('${directory.path}/manifest.json').exists() ||
        !await File('${directory.path}/$_snapshotName').exists()) {
      invalid(
        'A backup must contain only manifest.json and database.sqlite regular files.',
      );
    }
    final manifestFile = File('${directory.path}/manifest.json');
    if (await manifestFile.length() > 64 * 1024)
      invalid('Backup manifest exceeds 64 KiB.');
    final manifest = jsonObject(
      jsonDecode(await _readLimited(manifestFile, 64 * 1024)),
      'backup manifest',
    );
    checkKeys(manifest, {
      'format',
      'applicationVersion',
      'databaseSchemaVersion',
      'database',
    });
    if (manifest['format'] != _format ||
        !{
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
        }.contains(manifest['databaseSchemaVersion'])) {
      invalid('Unsupported native backup format or database schema.');
    }
    requiredString(manifest, 'applicationVersion');
    final entry = jsonObject(manifest['database'], 'backup database');
    checkKeys(entry, {'file', 'bytes', 'sha256'});
    final bytes = entry['bytes'];
    final hash = entry['sha256'];
    if (entry['file'] != _snapshotName ||
        bytes is! int ||
        bytes < 1 ||
        bytes > _maxDatabaseBytes ||
        hash is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
      invalid('Invalid backup database entry or resource limit.');
    }
    final input = File('${directory.path}/$_snapshotName');
    if (await input.length() != bytes)
      invalid('Backup database length does not match its manifest.');
    final stage = await Directory.systemTemp.createTemp('bodytmi-restore-');
    try {
      final copy = File('${stage.path}/$_snapshotName');
      // Bound the stream even if the source grows after its length was checked.
      final sink = copy.openWrite();
      var received = 0;
      try {
        await for (final chunk in input.openRead()) {
          received += chunk.length;
          if (received > bytes)
            invalid('Backup database changed while reading.');
          sink.add(chunk);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (received != bytes || await _digest(copy) != hash)
        invalid('Backup database checksum mismatch.');
      if (validateDatabase(copy.path) != manifest['databaseSchemaVersion'])
        invalid('Backup manifest schema version does not match its database.');
      return PreparedNativeBackup._(
        stage,
        copy.path,
        manifest,
        sourceDirectory,
      );
    } catch (_) {
      await stage.delete(recursive: true);
      rethrow;
    }
  }

  /// SQLite's online backup API owns the destination transaction and WAL state.
  /// Never copy the bytes of a live SQLite file here.
  static Future<void> copyDatabase(
    String source,
    String destination, {
    bool standalone = false,
    Future<void> Function(double progress)? onProgress,
  }) async {
    final from = sqlite3.open(source, mode: OpenMode.readOnly);
    Database? to;
    try {
      final pages =
          from.select('PRAGMA page_count').single.values.single as int;
      final pageBytes =
          from.select('PRAGMA page_size').single.values.single as int;
      if (pages * pageBytes > _maxDatabaseBytes)
        invalid('Database exceeds the 512 MiB backup resource limit.');
      to = sqlite3.open(destination);
      to.execute('PRAGMA synchronous = FULL');
      await for (final progress in from.backup(to, nPage: 4096)) {
        await onProgress?.call(progress);
      }
      if (standalone) to.execute('PRAGMA journal_mode = DELETE');
    } finally {
      to?.close();
      from.close();
    }
    final file = await File(destination).open(mode: FileMode.append);
    try {
      await file.flush();
    } finally {
      await file.close();
    }
  }

  /// Validate exact supported schema, foreign keys and all serialized content.
  static int validateDatabase(String path) {
    final db = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      db.execute('PRAGMA trusted_schema = OFF');
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
          }.contains(db.userVersion) ||
          db.select('PRAGMA application_id').single.values.single !=
              1112821065 ||
          db.select('PRAGMA journal_mode').single.values.single != 'delete') {
        invalid(
          'Backup database identity, version or journal mode is unsupported.',
        );
      }
      final schema = db.select(
        'SELECT name, sql FROM sqlite_master WHERE sql IS NOT NULL ORDER BY name',
      );
      validateSchema(schema, db.userVersion);
      final integrity = db.select('PRAGMA integrity_check');
      if (integrity.length != 1 ||
          integrity.single.values.single != 'ok' ||
          db.select('PRAGMA foreign_key_check').isNotEmpty)
        invalid('Backup database integrity or reference check failed.');
      for (final table in [
        'revisions',
        'sessions',
        if (db.userVersion >= 2) 'progression_decisions',
        if (db.userVersion >= 4) 'body_mass_records',
        if (db.userVersion >= 7) 'timing_activities',
        if (db.userVersion >= 46) 'window_checkpoints',
        if (db.userVersion >= 48) 'repeat_checkpoints',
        if (db.userVersion >= 8) 'workout_executions',
        if (db.userVersion >= 12) 'family_revisions',
        if (db.userVersion >= 27) 'derived_target_graphs',
        if (db.userVersion >= 3) ...[
          'program_revisions',
          'program_runs',
          'session_programs',
          'program_receipts',
        ],
      ]) {
        if (db.select(
          'SELECT 1 FROM $table WHERE length(CAST(snapshot AS BLOB)) > ? LIMIT 1',
          [_maxSnapshotBytes],
        ).isNotEmpty) {
          invalid('Backup record exceeds the 8 MiB resource limit.');
        }
      }
      if (db.userVersion >= 12) {
        final families = <FamilyRevision>[];
        for (final row in db.select('SELECT * FROM family_revisions')) {
          final family = FamilyRevision.fromJson(
            jsonDecode(row['snapshot'] as String),
          );
          if (family.family.id != row['family_id'] ||
              family.number != row['number'])
            invalid('Family revision row identity mismatch.');
          families.add(family);
        }
        validateFamilyRevisions(families);
      }
      if (db.userVersion >= 27) {
        final graphs = <DerivedTargetGraphRevision>[];
        for (final row in db.select('SELECT * FROM derived_target_graphs')) {
          final graph = DerivedTargetGraphRevision.fromJson(
            jsonDecode(row['snapshot'] as String),
          );
          if (db.userVersion < 39 &&
              graph.graph.nodes.any((n) => n['kind'] == 'round')) {
            invalid('Derived native-scale rounding requires schema v39.');
          }
          if (db.userVersion < 38 &&
              graph.graph.nodes.any(
                (n) => n['kind'] == 'add' || n['kind'] == 'subtract',
              )) {
            invalid('Binary derived targets require schema v38.');
          }
          if (graph.graph.id != row['graph_id'] ||
              graph.number != row['number'])
            invalid('Derived target graph row identity mismatch.');
          if (db.userVersion < 28 && graph.graph.plans.isNotEmpty) {
            invalid('Published workout plans require schema v28.');
          }
          for (final plan in graph.graph.plans) {
            final rows = db.select(
              'SELECT snapshot FROM revisions WHERE template_id = ? AND number = ?',
              [plan.templateId, plan.revision],
            );
            if (rows.length != 1)
              invalid(
                'Derived workout plan references a missing workout revision.',
              );
            plan.validate(
              WorkoutRevision.fromJson(
                jsonDecode(rows.single['snapshot'] as String),
              ),
              graph.graph.nodes,
            );
          }
          graphs.add(graph);
        }
        validateDerivedTargetGraphRevisions(graphs);
      }
      final revisions = db.prepare(
        'SELECT template_id, number, snapshot FROM revisions ORDER BY template_id, number',
      );
      try {
        final cursor = revisions.selectCursor();
        String? template;
        var number = 0;
        while (cursor.moveNext()) {
          final row = cursor.current;
          final revision = WorkoutRevision.fromJson(
            jsonDecode(row['snapshot'] as String),
          );
          if (db.userVersion < 41 &&
              revision.definition.hasExtendedEffortRoles) {
            invalid('Back-off and drop effort roles require schema v41.');
          }
          if (db.userVersion < 40 && revision.definition.hasManualRest) {
            invalid('Manual rest requires schema v40.');
          }
          if (db.userVersion < 26 && revision.definition.hasTypedObjectives)
            invalid('Authored numeric objectives require schema v26.');
          if (db.userVersion < 25 && revision.definition.hasMaxEffortObjectives)
            invalid('Max-effort objectives require schema v25.');
          if (db.userVersion < 24 && revision.definition.hasEffortTargets)
            invalid('Per-effort target overrides require schema v24.');
          if (db.userVersion < 45 &&
              revision.definition.slots.any((s) => s.timing?.openEnded == true))
            invalid('Open-ended timing defaults require schema v45.');
          if (db.userVersion < 13 &&
              revision.definition.slots.any((s) => s.timing != null))
            invalid('Slot timing defaults require schema v13.');
          if (db.userVersion < 5 &&
              revision.definition.slots.any((s) => s.bodyMass != null))
            invalid('Body-mass session bindings require schema v5.');
          if (db.userVersion < 6 &&
              revision.definition.slots.any((s) => s.effectiveMass != null))
            invalid('Effective-mass models require schema v6.');
          if (template != row['template_id']) {
            template = row['template_id'] as String;
            number = 0;
          }
          if (revision.definition.id != template ||
              revision.number != row['number'] ||
              revision.number != ++number) {
            invalid('Backup revision identity or sequence is inconsistent.');
          }
        }
      } finally {
        revisions.close();
      }
      final sessions = db.prepare('SELECT id, snapshot FROM sessions');
      try {
        final cursor = sessions.selectCursor();
        while (cursor.moveNext()) {
          final row = cursor.current;
          final sessionJson = jsonObject(
            jsonDecode(row['snapshot'] as String),
            'session',
          );
          if (db.userVersion < 30 &&
              sessionJson['derivedPlanInput'] != null &&
              jsonObject(
                sessionJson['derivedPlanInput'],
                'derived plan input',
              ).containsKey('bodyMassSources')) {
            invalid('Derived body mass session inputs require schema v30.');
          }
          if (db.userVersion < 34 &&
              sessionJson.containsKey('initialBodyMassOverrides')) {
            invalid('Body-mass rebind identity requires schema v34.');
          }
          final session = sessionFromJson(sessionJson);
          if (db.userVersion < 44 &&
              session.sets.any((s) => s.timing?.termination == 'manual'))
            invalid('Manual timing termination requires schema v44.');
          if (db.userVersion < 37 &&
              session.sets.any((s) => s.carriedTargets.isNotEmpty)) {
            invalid('Carried actual targets require schema v37.');
          }
          if (db.userVersion < 36 &&
              session.sets.any((s) => s.manualTargets.isNotEmpty)) {
            invalid('Manual session targets require schema v36.');
          }
          if (db.userVersion < 35 && sessionHasBodyMassMetadata(session)) {
            invalid('Body-mass metadata requires schema v35.');
          }
          if (db.userVersion < 32 && usesDerivedTargetlessObjective(session)) {
            invalid('Derived targetless suggestions require schema v32.');
          }
          if (db.userVersion < 31 && usesDerivedHistory(session)) {
            invalid('Derived history session inputs require schema v31.');
          }
          if (db.userVersion < 30 && usesDerivedBodyMass(session)) {
            invalid('Derived body mass session inputs require schema v30.');
          }
          if (db.userVersion < 29 && session.derivedPlanInput != null) {
            invalid('Derived session inputs require schema v29.');
          }
          if (db.userVersion < 21 &&
              session.sets.any((s) => s.observations != null))
            invalid('Set observations require schema v21.');
          if (db.userVersion < 7 && session.sets.any((s) => s.timing != null))
            invalid('Timing results require schema v7.');
          final revision = db.select(
            'SELECT snapshot FROM revisions WHERE template_id = ? AND number = ?',
            [session.revision.definition.id, session.revision.number],
          );
          if (session.id != row['id'] ||
              revision.length != 1 ||
              canonicalJson(
                    WorkoutRevision.fromJson(
                      jsonDecode(revision.single['snapshot'] as String),
                    ).toJson(),
                  ) !=
                  canonicalJson(session.revision.toJson())) {
            invalid('Backup session prescription or identity is inconsistent.');
          }
          if (session.status == SessionStatus.finalized &&
              db.select('SELECT 1 FROM finalizations WHERE session_id = ?', [
                session.id,
              ]).isEmpty) {
            invalid('Finalized backup session has no finalization identity.');
          }
          for (final set in session.sets) {
            for (final source in set.sources.values) {
              final rows = db.select(
                'SELECT snapshot FROM sessions WHERE id = ?',
                [source.sessionId],
              );
              if (rows.isEmpty) invalid('Backup history source is missing.');
              final past = sessionFromJson(
                jsonDecode(rows.single['snapshot'] as String),
              );
              final matches = past.sets.where((s) => s.id == source.setId);
              if (matches.isEmpty ||
                  matches.single.contentVersion < source.contentVersion) {
                invalid('Backup history source version or set is invalid.');
              }
            }
          }
        }
      } finally {
        sessions.close();
      }
      if (db.userVersion >= 2) {
        final decisions = <ProgressionDecision>[];
        for (final row in db.select(
          'SELECT session_id,slot_id,snapshot FROM progression_decisions',
        )) {
          final d = ProgressionDecision.fromJson(
            jsonDecode(row['snapshot'] as String),
          );
          if (db.userVersion < 44 &&
              d.session.sets.any((s) => s.timing?.termination == 'manual'))
            invalid('Frozen manual timing termination requires schema v44.');
          if (db.userVersion < 42 && d.role != 'work')
            invalid('Role-specific progression requires schema v42.');
          if (db.userVersion < 37 &&
              d.session.sets.any((s) => s.carriedTargets.isNotEmpty)) {
            invalid('Frozen carried actual targets require schema v37.');
          }
          if (db.userVersion < 23 &&
              d.ruleType == 'threshold' &&
              ThresholdRule.fromJson(d.rule).incrementBands != null)
            invalid('Performance increment bands require schema v23.');
          if (db.userVersion < 22 &&
              d.ruleType == 'threshold' &&
              ThresholdRule.fromJson(d.rule).advancementEffort != null)
            invalid('Advancement effort conditions require schema v22.');
          if (db.userVersion < 21 &&
              d.session.sets.any((s) => s.observations != null))
            invalid('Frozen set observations require schema v21.');
          if (db.userVersion < 20 &&
              d.ruleType == 'threshold' &&
              ThresholdRule.fromJson(d.rule).hasPerformancePolicy)
            invalid('Explicit performance predicates require schema v20.');
          if (db.userVersion < 19 &&
              d.ruleType == 'threshold' &&
              ThresholdRule.fromJson(d.rule).hasScaleRanges)
            invalid('Fixed-increment scale ranges require schema v19.');
          if (db.userVersion < 18 &&
              d.ruleType == 'threshold' &&
              ThresholdRule.fromJson(d.rule).hasScalePolicy)
            invalid('Numeric scale bindings require schema v18.');
          if (db.userVersion < 17 &&
              d.ruleType == 'threshold' &&
              ThresholdRule.fromJson(d.rule).hasSelectionPolicy)
            invalid('Chosen/priority coordination requires schema v17.');
          if (db.userVersion < 16 &&
              d.ruleType == 'threshold' &&
              ThresholdRule.fromJson(d.rule).hasNumericPolicy)
            invalid('Numeric directions and lower bounds require schema v16.');
          if (db.userVersion < 15 &&
              d.ruleType == 'threshold' &&
              ThresholdRule.fromJson(d.rule).hasExplicitAggregation)
            invalid('Explicit result aggregation requires schema v15.');
          if (db.userVersion < 14 && d.ruleType != 'double')
            invalid('Stored threshold progression requires schema v14.');
          if (db.userVersion < 11 && d.declinedAt != null)
            invalid('Progression declines require schema v11.');
          if (d.session.id != row['session_id'] ||
              d.storageSlotKey != row['slot_id'])
            invalid('Progression receipt identity mismatch.');
          decisions.add(d);
        }
        final sources = [
          for (final row in db.select(
            'SELECT DISTINCT s.id,s.snapshot FROM sessions s JOIN progression_decisions p ON p.session_id=s.id',
          ))
            sessionFromJson(jsonDecode(row['snapshot'] as String)),
        ];
        if (db.userVersion < 3) {
          validateProgressionDecisions(decisions, sources);
        } else {
          final programs = <ProgramRevision>[];
          for (final row in db.select('SELECT * FROM program_revisions')) {
            final p = ProgramRevision.fromJson(
              jsonDecode(row['snapshot'] as String),
            );
            if (p.definition.id != row['program_id'] ||
                p.number != row['number'])
              invalid('Program revision row identity mismatch.');
            if (db.userVersion < 33 &&
                p.definition.plan.nodes.whereType<ProgramDay>().any(
                  (day) => day.derivedPlan != null,
                )) {
              invalid('Program day derived plans require schema v33.');
            }
            programs.add(p);
          }
          final runs = <ProgramRun>[];
          for (final row in db.select('SELECT * FROM program_runs')) {
            final r = ProgramRun.fromJson(
              jsonDecode(row['snapshot'] as String),
            );
            if (r.id != row['id'])
              invalid('Program run row identity mismatch.');
            runs.add(r);
          }
          final bindings = <SessionProgramBinding>[];
          for (final row in db.select('SELECT * FROM session_programs')) {
            final b = SessionProgramBinding.fromJson(
              jsonDecode(row['snapshot'] as String),
            );
            if (b.sessionId != row['session_id'] ||
                b.runId != row['run_id'] ||
                b.ordinal != row['ordinal'])
              invalid('Program binding row identity mismatch.');
            bindings.add(b);
          }
          final receipts = <ProgramReceipt>[];
          for (final row in db.select('SELECT * FROM program_receipts')) {
            final r = ProgramReceipt.fromJson(
              jsonDecode(row['snapshot'] as String),
            );
            if (r.runId != row['run_id'] ||
                r.ordinal != row['ordinal'] ||
                r.operationKey != row['operation_key'] ||
                r.sessionId != row['session_id'])
              invalid('Program receipt row identity mismatch.');
            receipts.add(r);
          }
          final allSessions = [
            for (final row in db.select('SELECT snapshot FROM sessions'))
              sessionFromJson(jsonDecode(row['snapshot'] as String)),
          ];
          final allRevisions = [
            for (final row in db.select('SELECT snapshot FROM revisions'))
              WorkoutRevision.fromJson(jsonDecode(row['snapshot'] as String)),
          ];
          final finalizations = [
            for (final row in db.select('SELECT session_id FROM finalizations'))
              row['session_id'] as String,
          ];
          validateProgramData(
            programs: programs,
            runs: runs,
            bindings: bindings,
            receipts: receipts,
            revisions: allRevisions,
            sessions: allSessions,
            finalizations: finalizations,
          );
          validateProgressionDecisions(decisions, allSessions, {
            for (final b in bindings) b.sessionId: b.runId,
          });
        }
      }
      if (db.userVersion >= 4) {
        final massRecords = <BodyMassRecord>[];
        for (final row in db.select(
          'SELECT id,snapshot FROM body_mass_records',
        )) {
          final record = BodyMassRecord.fromJson(
            jsonDecode(row['snapshot'] as String),
          );
          if (db.userVersion < 35 && record.measurement.hasMetadata)
            invalid('Body-mass metadata requires schema v35.');
          if (record.measurement.id != row['id'])
            invalid('Body-mass row identity mismatch.');
          massRecords.add(record);
        }
        validateBodyMassInputReferences([
          for (final row in db.select('SELECT snapshot FROM sessions'))
            sessionFromJson(jsonDecode(row['snapshot'] as String)),
        ], massRecords);
      }
      if (db.userVersion >= 29) {
        final graphs = [
          for (final row in db.select(
            'SELECT snapshot FROM derived_target_graphs',
          ))
            DerivedTargetGraphRevision.fromJson(
              jsonDecode(row['snapshot'] as String),
            ),
        ];
        final sessions = [
          for (final row in db.select('SELECT snapshot FROM sessions'))
            sessionFromJson(jsonDecode(row['snapshot'] as String)),
        ];
        final runs = <String, String>{};
        for (final row in db.select('SELECT snapshot FROM session_programs')) {
          final binding = SessionProgramBinding.fromJson(
            jsonDecode(row['snapshot'] as String),
          );
          runs[binding.sessionId] = binding.runId;
        }
        final records = [
          for (final row in db.select('SELECT snapshot FROM body_mass_records'))
            BodyMassRecord.fromJson(jsonDecode(row['snapshot'] as String)),
        ];
        validateDerivedPlanReferences(sessions, graphs, runs, records);
        validateProgramPlanReferences([
          for (final row in db.select('SELECT snapshot FROM program_revisions'))
            ProgramRevision.fromJson(jsonDecode(row['snapshot'] as String)),
        ], graphs);
      }
      if (db.userVersion >= 7) {
        final timers = <TimingActivity>[];
        for (final row in db.select('SELECT * FROM timing_activities')) {
          final t = TimingActivity.fromJson(
            jsonDecode(row['snapshot'] as String),
          );
          if (db.userVersion < 44 && t.plan.openEnded)
            invalid('Open-ended timing requires schema v44.');
          if (db.userVersion < 43 && t.plan.unplannedDuration)
            invalid('Unplanned duration timing requires schema v43.');
          if (db.userVersion < 10 && t.plan.tempo != null)
            invalid('Tempo timing requires schema v10.');
          if (db.userVersion < 8 && t.plan.restOnly)
            invalid('Rest-only timing requires schema v8.');
          if (t.id != row['id'] ||
              t.sessionId != row['session_id'] ||
              t.setId != row['set_id'])
            invalid('Timing row identity mismatch.');
          timers.add(t);
        }
        validateTimingData(timers, [
          for (final row in db.select('SELECT snapshot FROM sessions'))
            sessionFromJson(jsonDecode(row['snapshot'] as String)),
        ]);
      }
      if (db.userVersion >= 8) {
        final executions = <WorkoutExecution>[];
        for (final row in db.select('SELECT * FROM workout_executions')) {
          final e = WorkoutExecution.fromJson(
            jsonDecode(row['snapshot'] as String),
          );
          if (db.userVersion < 9 &&
              e.receipts.any(
                (r) =>
                    jsonObject(r['request'], 'execution request')['action'] ==
                    'skip-group',
              ))
            invalid('Group skipping requires schema v9.');
          if (e.id != row['id'] || e.sessionId != row['session_id'])
            invalid('Execution row identity mismatch.');
          executions.add(e);
        }
        validateExecutionData(
          executions,
          [
            for (final row in db.select('SELECT snapshot FROM sessions'))
              sessionFromJson(jsonDecode(row['snapshot'] as String)),
          ],
          [
            for (final row in db.select(
              'SELECT snapshot FROM timing_activities',
            ))
              TimingActivity.fromJson(jsonDecode(row['snapshot'] as String)),
          ],
        );
      }
      if (db.userVersion >= 48) {
        for (final row in db.select('SELECT * FROM repeat_checkpoints')) {
          final checkpoint = RepeatCheckpoint.fromJson(
            jsonDecode(row['snapshot'] as String),
          );
          if (checkpoint.id != row['id'])
            invalid('Repeat checkpoint row identity mismatch.');
        }
      }
      if (db.userVersion >= 46) {
        final checkpoints = <WindowCheckpoint>[];
        for (final row in db.select('SELECT * FROM window_checkpoints')) {
          final checkpoint = WindowCheckpoint.fromJson(
            jsonDecode(row['snapshot'] as String),
          );
          if (db.userVersion < 47 && checkpoint.reserved)
            invalid('Window clock reservations require schema v47.');
          if (checkpoint.id != row['id'] ||
              checkpoint.sessionId != row['session_id'])
            invalid('Window checkpoint row identity mismatch.');
          checkpoints.add(checkpoint);
        }
        validateWindowCheckpoints(
          checkpoints,
          [
            for (final row in db.select('SELECT snapshot FROM sessions'))
              sessionFromJson(jsonDecode(row['snapshot'] as String)),
          ],
          timers: [
            for (final row in db.select(
              'SELECT snapshot FROM timing_activities',
            ))
              TimingActivity.fromJson(jsonDecode(row['snapshot'] as String)),
          ],
          executions: [
            for (final row in db.select(
              'SELECT snapshot FROM workout_executions',
            ))
              WorkoutExecution.fromJson(jsonDecode(row['snapshot'] as String)),
          ],
        );
      }
      return db.userVersion;
    } finally {
      db.close();
    }
  }
}

final class PreparedNativeBackup {
  PreparedNativeBackup._(
    this._directory,
    this._databasePath,
    this.manifest,
    this._sourceDirectory,
  );
  final Directory _directory;
  final String _databasePath;
  final Map<String, Object?> manifest;
  final String _sourceDirectory;
  bool _closed = false;

  /// Keep both the source backup and our validated private copy immutable.
  Future<void> checkDestination(String destination) async {
    final normalized = p.normalize(p.absolute(destination));
    var ancestor = p.dirname(normalized);
    while (!await Directory(ancestor).exists() &&
        p.dirname(ancestor) != ancestor) {
      ancestor = p.dirname(ancestor);
    }
    final resolved = p.join(
      await Directory(ancestor).resolveSymbolicLinks(),
      p.relative(normalized, from: ancestor),
    );
    if (p.equals(resolved, _sourceDirectory) ||
        p.isWithin(_sourceDirectory, resolved) ||
        p.equals(resolved, _directory.path) ||
        p.isWithin(_directory.path, resolved)) {
      invalid('Restore destinations must be outside the source backup.');
    }
    if (await FileSystemEntity.type(normalized, followLinks: false) ==
        FileSystemEntityType.link) {
      final target = await File(normalized).resolveSymbolicLinks();
      if (p.isWithin(_sourceDirectory, target) ||
          p.isWithin(_directory.path, target)) {
        invalid('Restore destination points into the source backup.');
      }
    }
  }

  /// Caller must retain exclusive destination ownership. The active connection
  /// must already be closed. A failure leaves SQLite to recover its transaction.
  Future<void> restoreInto(
    String destination, {
    Future<void> Function(double)? onProgress,
  }) async {
    if (_closed) throw StateError('Prepared backup is closed.');
    await NativeBackup.copyDatabase(
      _databasePath,
      destination,
      onProgress: onProgress,
    );
  }

  Future<void> close() async {
    if (!_closed) {
      _closed = true;
      await _directory.delete(recursive: true);
    }
  }
}

Future<String> _digest(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

Future<String> _readLimited(File file, int limit) async {
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in file.openRead()) {
    if (bytes.length + chunk.length > limit)
      invalid('Backup manifest exceeds 64 KiB.');
    bytes.add(chunk);
  }
  return utf8.decode(bytes.takeBytes());
}
