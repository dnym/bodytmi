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
        manifest['databaseSchemaVersion'] != supportedSchemaVersion) {
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
      if (db.userVersion != supportedSchemaVersion ||
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
      validateSchema(schema);
      final integrity = db.select('PRAGMA integrity_check');
      if (integrity.length != 1 ||
          integrity.single.values.single != 'ok' ||
          db.select('PRAGMA foreign_key_check').isNotEmpty)
        invalid('Backup database integrity or reference check failed.');
      for (final table in [
        'revisions',
        'sessions',
        'progression_decisions',
        'observations',
        'measure_revisions',
        'timing_activities',
        'window_checkpoints',
        'repeat_checkpoints',
        'progression_reconciliations',
        'lever_link_revisions',
        'shared_lever_applications',
        'link_retirement_anchors',
        'program_upgrade_receipts',
        'workout_executions',
        'family_revisions',
        'exercise_revisions',
        'implementation_revisions',
        'progression_preset_revisions',
        'blueprint_revisions',
        'blueprint_instances',
        'equipment_revisions',
        'gym_revisions',
        'equipment_instance_revisions',
        'derived_target_graphs',
        'imported_sessions',
        'block_progressions',
        ...[
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
      {
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
      final catalogOwners = <String, String>{};
      {
        final exercises = <ExerciseRevision>[];
        for (final row in db.select('SELECT * FROM exercise_revisions')) {
          final exercise = ExerciseRevision.fromJson(
            jsonDecode(row['snapshot'] as String),
          );
          if (exercise.exercise.id != row['exercise_id'] ||
              exercise.number != row['number'])
            invalid('Exercise revision row identity mismatch.');
          exercises.add(exercise);
        }
        validateExerciseRevisions(exercises);
        final implementations = <ImplementationRevision>[];
        for (final row in db.select('SELECT * FROM implementation_revisions')) {
          final implementation = ImplementationRevision.fromJson(
            jsonDecode(row['snapshot'] as String),
          );
          if (implementation.implementation.id != row['implementation_id'] ||
              implementation.number != row['number'])
            invalid('Implementation revision row identity mismatch.');
          implementations.add(implementation);
        }
        validateImplementationRevisions(implementations, exercises);
        catalogOwners.addAll(implementationOwners(implementations));
      }
      final presets = <ProgressionPresetRevision>[];
      {
        for (final row in db.select(
          'SELECT * FROM progression_preset_revisions',
        )) {
          final preset = ProgressionPresetRevision.fromJson(
            jsonDecode(row['snapshot'] as String),
          );
          if (preset.preset.id != row['preset_id'] ||
              preset.number != row['number'])
            invalid('Progression preset revision row identity mismatch.');
          presets.add(preset);
        }
        validateProgressionPresetRevisions(presets);
      }
      {
        final blueprints = <BlueprintRevision>[];
        for (final row in db.select('SELECT * FROM blueprint_revisions')) {
          final b = BlueprintRevision.fromJson(
            jsonDecode(row['snapshot'] as String),
          );
          if (b.blueprint.id != row['blueprint_id'] ||
              b.number != row['number'])
            invalid('Blueprint revision row identity mismatch.');
          blueprints.add(b);
        }
        validateBlueprintRevisions(blueprints);
        final instances = <BlueprintInstance>[];
        for (final row in db.select('SELECT * FROM blueprint_instances')) {
          final i = BlueprintInstance.fromJson(
            jsonDecode(row['snapshot'] as String),
          );
          if (i.id != row['instance_id'] || i.number != row['number'])
            invalid('Blueprint instance row identity mismatch.');
          instances.add(i);
        }
        validateBlueprintInstances(instances, blueprints);
        bool exists(String table, String column, String id, int number) =>
            db.select('SELECT 1 FROM $table WHERE $column = ? AND number = ?', [
              id,
              number,
            ]).isNotEmpty;
        for (final i in instances) {
          if (i.workouts.entries.any(
                (e) => !exists(
                  'revisions',
                  'template_id',
                  i.workoutId(e.key),
                  e.value,
                ),
              ) ||
              (i.programRevision != null &&
                  !exists(
                    'program_revisions',
                    'program_id',
                    i.id,
                    i.programRevision!,
                  )) ||
              i.presets.entries.any(
                (e) => !exists(
                  'progression_preset_revisions',
                  'preset_id',
                  i.presetId(e.key),
                  e.value,
                ),
              ) ||
              i.instances.entries.any(
                (e) => !exists(
                  'equipment_instance_revisions',
                  'instance_id',
                  i.instanceId(e.key),
                  e.value,
                ),
              ))
            invalid(
              'Blueprint instance ${i.id} names an unpublished revision.',
            );
        }
      }
      {
        final equipment = <EquipmentRevision>[];
        for (final row in db.select('SELECT * FROM equipment_revisions')) {
          final entry = EquipmentRevision.fromJson(
            jsonDecode(row['snapshot'] as String),
          );
          if (entry.equipment.id != row['equipment_id'] ||
              entry.number != row['number'])
            invalid('Equipment revision row identity mismatch.');
          equipment.add(entry);
        }
        validateEquipmentRevisions(equipment);
        final gyms = <GymRevision>[];
        for (final row in db.select('SELECT * FROM gym_revisions')) {
          final entry = GymRevision.fromJson(
            jsonDecode(row['snapshot'] as String),
          );
          if (entry.gym.id != row['gym_id'] || entry.number != row['number'])
            invalid('Gym revision row identity mismatch.');
          gyms.add(entry);
        }
        validateGymRevisions(gyms);
        final instances = <EquipmentInstanceRevision>[];
        for (final row in db.select(
          'SELECT * FROM equipment_instance_revisions',
        )) {
          final entry = EquipmentInstanceRevision.fromJson(
            jsonDecode(row['snapshot'] as String),
          );
          if (entry.instance.id != row['instance_id'] ||
              entry.number != row['number'])
            invalid('Equipment instance revision row identity mismatch.');

          instances.add(entry);
        }
        validateEquipmentInstanceRevisions(instances, equipment, gyms);
        {
          validateLoadInputReferences(
            [
              for (final row in db.select('SELECT snapshot FROM sessions'))
                sessionFromJson(jsonDecode(row['snapshot'] as String)),
            ],
            instances,
            gyms,
          );
        }
      }
      {
        final graphs = <DerivedTargetGraphRevision>[];
        for (final row in db.select('SELECT * FROM derived_target_graphs')) {
          final graph = DerivedTargetGraphRevision.fromJson(
            jsonDecode(row['snapshot'] as String),
          );

          if (graph.graph.id != row['graph_id'] ||
              graph.number != row['number'])
            invalid('Derived target graph row identity mismatch.');

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

          if (template != row['template_id']) {
            template = row['template_id'] as String;
            number = 0;
          }
          if (revision.definition.id != template ||
              revision.number != row['number'] ||
              revision.number != ++number) {
            invalid('Backup revision identity or sequence is inconsistent.');
          }
          validateCatalogSlotAdoption(revision.definition.slots, catalogOwners);
        }
      } finally {
        revisions.close();
      }
      final sessions = db.prepare(
        'SELECT id, template_id, snapshot FROM sessions',
      );
      try {
        final cursor = sessions.selectCursor();
        while (cursor.moveNext()) {
          final row = cursor.current;
          final sessionJson = jsonObject(
            jsonDecode(row['snapshot'] as String),
            'session',
          );

          final session = sessionFromJson(sessionJson);

          final revision = db.select(
            'SELECT snapshot FROM revisions WHERE template_id = ? AND number = ?',
            [session.definition.id, session.revision.number],
          );
          if (session.id != row['id'] ||
              session.definition.id != row['template_id'] ||
              revision.length != 1 ||
              canonicalJson(
                    WorkoutRevision.fromJson(
                      jsonDecode(revision.single['snapshot'] as String),
                    ).toJson(),
                  ) !=
                  canonicalJson(session.revision.toJson())) {
            invalid('Backup session prescription or identity is inconsistent.');
          }
          validateCatalogSlotAdoption(session.definition.slots, catalogOwners);
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
      final reconciliations = <ReconciliationReceipt>[];
      {
        for (final row in db.select(
          'SELECT id,snapshot FROM progression_reconciliations',
        )) {
          final receipt = ReconciliationReceipt.fromJson(
            jsonDecode(row['snapshot'] as String),
          );
          if (receipt.id != row['id'])
            invalid('Reconciliation row identity does not match its key.');

          reconciliations.add(receipt);
        }
      }
      {
        final decisions = <ProgressionDecision>[];
        for (final row in db.select(
          'SELECT session_id,slot_id,template_id,run_id,sequence,snapshot '
          'FROM progression_decisions',
        )) {
          final d = ProgressionDecision.fromJson(
            jsonDecode(row['snapshot'] as String),
          );

          if (d.session.id != row['session_id'] ||
              d.storageSlotKey != row['slot_id'] ||
              d.templateId != row['template_id'] ||
              d.runId != row['run_id'] ||
              d.sequence != row['sequence'])
            invalid('Progression receipt identity mismatch.');
          decisions.add(d);
        }
        validatePresetProvenance(decisions, presets);
        {
          final programs = <ProgramRevision>[];
          for (final row in db.select('SELECT * FROM program_revisions')) {
            final p = ProgramRevision.fromJson(
              jsonDecode(row['snapshot'] as String),
            );
            if (p.definition.id != row['program_id'] ||
                p.number != row['number'])
              invalid('Program revision row identity mismatch.');

            programs.add(p);
          }
          final runs = <ProgramRun>[];
          for (final row in db.select('SELECT * FROM program_runs')) {
            final r = ProgramRun.fromJson(
              jsonDecode(row['snapshot'] as String),
            );
            if (r.id != row['id'])
              invalid('Program run row identity mismatch.');
            if (r.gymId != null &&
                db.select('SELECT 1 FROM gym_revisions WHERE gym_id = ?', [
                  r.gymId,
                ]).isEmpty)
              invalid('Run ${r.id} names an unpublished default gym.');
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
          final upgrades = <ProgramUpgradeReceipt>[];
          {
            for (final row in db.select(
              'SELECT run_id,request_id,snapshot FROM program_upgrade_receipts',
            )) {
              final u = ProgramUpgradeReceipt.fromJson(
                jsonDecode(row['snapshot'] as String),
              );
              if (u.runId != row['run_id'] || u.requestId != row['request_id'])
                invalid('Program upgrade row identity mismatch.');
              upgrades.add(u);
            }
          }
          validateProgramUpgrades(programs, runs, upgrades);
          validateProgramData(
            programs: programs,
            runs: runs,
            upgrades: upgrades,
            bindings: bindings,
            receipts: receipts,
            revisions: allRevisions,
            sessions: allSessions,
            finalizations: finalizations,
          );
          {
            final links = <LeverLinkRevision>[];
            for (final row in db.select(
              'SELECT link_id,number,snapshot FROM lever_link_revisions',
            )) {
              final link = LeverLinkRevision.fromJson(
                jsonDecode(row['snapshot'] as String),
              );
              if (link.link.id != row['link_id'] ||
                  link.number != row['number'])
                invalid('Lever link revision row identity mismatch.');
              links.add(link);
            }
            final sharedApplications = <SharedLeverApplication>[];
            final linkRetirements = <LinkRetirementAnchor>[];
            {
              for (final row in db.select(
                'SELECT link_id,sequence,snapshot FROM shared_lever_applications',
              )) {
                final application = SharedLeverApplication.fromJson(
                  jsonDecode(row['snapshot'] as String),
                );
                if (application.linkId != row['link_id'] ||
                    application.sequence != row['sequence'])
                  invalid('Shared lever application row identity mismatch.');
                sharedApplications.add(application);
              }
              for (final row in db.select(
                'SELECT id,snapshot FROM link_retirement_anchors',
              )) {
                final retirement = LinkRetirementAnchor.fromJson(
                  jsonDecode(row['snapshot'] as String),
                );
                if (retirement.id != row['id'])
                  invalid('Lever link retirement row identity mismatch.');
                linkRetirements.add(retirement);
              }
            }
            final linkAnchors = <String, ProgressionAnchor>{
              for (final anchor in <ProgressionAnchor>[
                ...decisions,
                ...reconciliations,
                ...linkRetirements,
              ])
                if (anchor.resolvedAt != null) anchor.id: anchor,
            };
            final linkIndex = SharedLinkIndex(
              revisions: links,
              applications: sharedApplications,
              anchors: linkAnchors,
              retirements: linkRetirements,
            );
            validateLinkRetirements(
              linkRetirements,
              links,
              sharedApplications,
              decisions,
              reconciliations,
            );
            validateSharedLeverApplications(
              sharedApplications,
              links,
              linkAnchors,
            );
            validateLeverLinkRevisions(links, linkRetirements);
            validateLeverLinks(
              links,
              decisions,
              reconciliations,
              linkRetirements,
            );
            if (reconciliations.isNotEmpty)
              validateProgressionReconciliations(
                reconciliations,
                decisions,
                allRevisions,
                allSessions,
                linkRetirements,
                linkIndex,
              );
            validateProgressionDecisions(
              decisions,
              allSessions,
              {for (final b in bindings) b.sessionId: b.runId},
              [...reconciliations, ...linkRetirements],
              linkIndex,
            );
          }
        }
      }
      {
        final observations = <ObservationRecord>[];
        for (final row in db.select(
          'SELECT id,measure_id,local_date,snapshot FROM observations',
        )) {
          final record = ObservationRecord.fromJson(
            jsonDecode(row['snapshot'] as String),
          );
          if (record.observation.id != row['id'] ||
              record.observation.measureId != row['measure_id'] ||
              record.observation.localDate != row['local_date'])
            invalid('Observation row identity mismatch.');
          observations.add(record);
        }
        final measureRevisions = <MeasureRevision>[];
        for (final row in db.select('SELECT * FROM measure_revisions')) {
          final m = MeasureRevision.fromJson(
            jsonDecode(row['snapshot'] as String),
          );
          if (m.measure.id != row['measure_id'] || m.number != row['number'])
            invalid('Measure revision row identity mismatch.');
          measureRevisions.add(m);
        }
        validateMeasureRevisions(measureRevisions);
        validateObservationRecords(
          observations,
          measures: currentMeasures(measureRevisions),
        );
        final massRecords = [
          for (final r in observations)
            if (r.observation.isBodyMass)
              BodyMassRecord(r.observation.toBodyMass(), deleted: r.deleted),
        ];
        validateBodyMassInputReferences([
          for (final row in db.select('SELECT snapshot FROM sessions'))
            sessionFromJson(jsonDecode(row['snapshot'] as String)),
        ], massRecords);
      }
      {
        final imported = <ImportedSessionRecord>[];
        for (final row in db.select('SELECT * FROM imported_sessions')) {
          final record = ImportedSessionRecord.fromJson(
            jsonDecode(row['snapshot'] as String),
          );
          if (record.namespace != row['namespace'] ||
              record.sourceId != row['source_id'])
            invalid('Imported session row identity mismatch.');
          imported.add(record);
        }
        validateImportedSessions(imported);
      }
      {
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
          for (final row in db.select(
            "SELECT snapshot FROM observations WHERE measure_id = 'body-mass'",
          ))
            (() {
              final r = ObservationRecord.fromJson(
                jsonDecode(row['snapshot'] as String),
              );
              return BodyMassRecord(
                r.observation.toBodyMass(),
                deleted: r.deleted,
              );
            })(),
        ];
        validateDerivedPlanReferences(sessions, graphs, runs, records);
        validateProgramPlanReferences([
          for (final row in db.select('SELECT snapshot FROM program_revisions'))
            ProgramRevision.fromJson(jsonDecode(row['snapshot'] as String)),
        ], graphs);
      }
      {
        final timers = <TimingActivity>[];
        for (final row in db.select('SELECT * FROM timing_activities')) {
          final t = TimingActivity.fromJson(
            jsonDecode(row['snapshot'] as String),
          );

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
      final executions = <WorkoutExecution>[];
      {
        for (final row in db.select('SELECT * FROM workout_executions')) {
          final e = WorkoutExecution.fromJson(
            jsonDecode(row['snapshot'] as String),
          );

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
      final repeatCheckpoints = <RepeatCheckpoint>[];
      {
        for (final row in db.select('SELECT * FROM repeat_checkpoints')) {
          final checkpoint = RepeatCheckpoint.fromJson(
            jsonDecode(row['snapshot'] as String),
          );
          if (checkpoint.id != row['id'])
            invalid('Repeat checkpoint row identity mismatch.');

          repeatCheckpoints.add(checkpoint);
        }
        validatePlacementCheckpoints(executions, [
          for (final row in db.select('SELECT snapshot FROM sessions'))
            sessionFromJson(jsonDecode(row['snapshot'] as String)),
        ], repeatCheckpoints);
      }
      {
        validateRepeatSessionBindings(repeatCheckpoints, [
          for (final row in db.select('SELECT snapshot FROM sessions'))
            sessionFromJson(jsonDecode(row['snapshot'] as String)),
        ]);
        {
          final decisions = <BlockProgressionDecision>[];
          for (final row in db.select('SELECT * FROM block_progressions')) {
            final decision = BlockProgressionDecision.fromJson(
              jsonDecode(row['snapshot'] as String),
            );
            if (decision.id != row['id'])
              invalid('Block progression row identity mismatch.');
            decisions.add(decision);
          }
          validateBlockProgressions(
            decisions,
            repeatCheckpoints,
            [
              for (final row in db.select('SELECT snapshot FROM sessions'))
                sessionFromJson(jsonDecode(row['snapshot'] as String)),
            ],
            [
              for (final row in db.select(
                'SELECT snapshot FROM session_programs',
              ))
                SessionProgramBinding.fromJson(
                  jsonDecode(row['snapshot'] as String),
                ),
            ],
          );
        }
        validateRepeatClockReservations(
          repeatCheckpoints,
          timers: [
            for (final row in db.select(
              'SELECT snapshot FROM timing_activities',
            ))
              TimingActivity.fromJson(jsonDecode(row['snapshot'] as String)),
          ],
          windows: [
            for (final row in db.select(
              'SELECT snapshot FROM window_checkpoints',
            ))
              WindowCheckpoint.fromJson(jsonDecode(row['snapshot'] as String)),
          ],
        );
      }
      {
        final checkpoints = <WindowCheckpoint>[];
        for (final row in db.select('SELECT * FROM window_checkpoints')) {
          final checkpoint = WindowCheckpoint.fromJson(
            jsonDecode(row['snapshot'] as String),
          );

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
