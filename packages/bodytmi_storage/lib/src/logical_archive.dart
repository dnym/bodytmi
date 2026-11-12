import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'native_backup.dart';
import 'schema.dart';

const _format = 'bodytmi-logical-export/50';
const _maxBytes = 64 * 1024 * 1024;

/// File I/O and checksums for the full current logical training-store contract.
/// A logical file is portable JSON, not a SQLite backup or neutral history log.
final class LogicalArchiveFiles {
  const LogicalArchiveFiles._();

  static Future<Map<String, Object?>> export(
    TrainingArchive archive,
    String destination,
  ) async {
    final output = File(destination).absolute;
    await _unused(output.path);
    final body = <String, Object?>{
      'format': _format,
      'applicationVersion': '0.1.0',
      'data': archive.toJson(),
    };
    final hash = _checksum(body);
    final bytes = utf8.encode(canonicalJson({...body, 'sha256': hash}));
    if (bytes.length > _maxBytes)
      invalid('Logical export exceeds the 64 MiB resource limit.');
    await output.parent.create(recursive: true);
    final stage = await output.parent.createTemp('.bodytmi-export-');
    try {
      final file = await File(
        '${stage.path}/export.json',
      ).writeAsBytes(bytes, flush: true);
      await _unused(output.path);
      await file.rename(output.path);
      return {
        'destination': destination,
        'format': _format,
        'sha256': hash,
        'records': archive.summary,
      };
    } finally {
      await stage.delete(recursive: true);
    }
  }

  /// Validate the complete logical file and reconstruct only in temporary storage.
  /// Live-profile replacement later uses the same native transaction/recovery path.
  static Future<PreparedLogicalArchive> prepare(String source) async {
    final file = File(source);
    final sourcePath = await file.resolveSymbolicLinks();
    final input = jsonObject(jsonDecode(await _read(file)), 'logical export');
    checkKeys(input, {'format', 'applicationVersion', 'data', 'sha256'});
    if (!{
      _format,
      'bodytmi-logical-export/1',
      'bodytmi-logical-export/2',
      'bodytmi-logical-export/3',
      'bodytmi-logical-export/4',
      'bodytmi-logical-export/5',
      'bodytmi-logical-export/6',
      'bodytmi-logical-export/7',
      'bodytmi-logical-export/8',
      'bodytmi-logical-export/9',
      'bodytmi-logical-export/10',
      'bodytmi-logical-export/11',
      'bodytmi-logical-export/12',
      'bodytmi-logical-export/13',
      'bodytmi-logical-export/14',
      'bodytmi-logical-export/15',
      'bodytmi-logical-export/16',
      'bodytmi-logical-export/17',
      'bodytmi-logical-export/18',
      'bodytmi-logical-export/19',
      'bodytmi-logical-export/20',
      'bodytmi-logical-export/21',
      'bodytmi-logical-export/22',
      'bodytmi-logical-export/23',
      'bodytmi-logical-export/24',
      'bodytmi-logical-export/25',
      'bodytmi-logical-export/26',
      'bodytmi-logical-export/27',
      'bodytmi-logical-export/28',
      'bodytmi-logical-export/29',
      'bodytmi-logical-export/30',
      'bodytmi-logical-export/31',
      'bodytmi-logical-export/32',
      'bodytmi-logical-export/33',
      'bodytmi-logical-export/34',
      'bodytmi-logical-export/35',
      'bodytmi-logical-export/36',
      'bodytmi-logical-export/37',
      'bodytmi-logical-export/38',
      'bodytmi-logical-export/39',
      'bodytmi-logical-export/40',
      'bodytmi-logical-export/41',
      'bodytmi-logical-export/42',
      'bodytmi-logical-export/43',
      'bodytmi-logical-export/44',
      'bodytmi-logical-export/45',
      'bodytmi-logical-export/46',
      'bodytmi-logical-export/47',
      'bodytmi-logical-export/48',
      'bodytmi-logical-export/49',
    }.contains(input['format']))
      invalid('Unsupported logical export format.');
    final version = requiredString(input, 'applicationVersion');
    final hash = requiredString(input, 'sha256');
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash))
      invalid('Invalid logical export checksum.');
    final inputData = jsonObject(input['data'], 'logical data');
    final legacy = input['format'] == 'bodytmi-logical-export/1';
    final repeatRunningData = input['format'] == _format;
    final repeatReservationData =
        repeatRunningData || input['format'] == 'bodytmi-logical-export/49';
    final repeatData =
        repeatReservationData || input['format'] == 'bodytmi-logical-export/48';
    final reservationData =
        repeatData || input['format'] == 'bodytmi-logical-export/47';
    final checkpointData =
        reservationData || input['format'] == 'bodytmi-logical-export/46';
    final openEndedDefaultsData =
        checkpointData || input['format'] == 'bodytmi-logical-export/45';
    final openEndedTimingData =
        openEndedDefaultsData || input['format'] == 'bodytmi-logical-export/44';
    final unplannedTimingData =
        openEndedTimingData || input['format'] == 'bodytmi-logical-export/43';
    final roleProgressionData =
        unplannedTimingData || input['format'] == 'bodytmi-logical-export/42';
    final extendedRolesData =
        roleProgressionData || input['format'] == 'bodytmi-logical-export/41';
    final manualRestData =
        extendedRolesData || input['format'] == 'bodytmi-logical-export/40';
    final roundedTargetsData =
        manualRestData || input['format'] == 'bodytmi-logical-export/39';
    final binaryTargetsData =
        roundedTargetsData || input['format'] == 'bodytmi-logical-export/38';
    final carriedTargetsData =
        binaryTargetsData || input['format'] == 'bodytmi-logical-export/37';
    final manualTargetsData =
        carriedTargetsData || input['format'] == 'bodytmi-logical-export/36';
    final massMetadataData =
        manualTargetsData || input['format'] == 'bodytmi-logical-export/35';
    final rebindData =
        massMetadataData || input['format'] == 'bodytmi-logical-export/34';
    final programPlanData =
        rebindData || input['format'] == 'bodytmi-logical-export/33';
    final targetlessSessionData =
        programPlanData || input['format'] == 'bodytmi-logical-export/32';
    final historySessionData =
        targetlessSessionData || input['format'] == 'bodytmi-logical-export/31';
    final derivedBodyMassData =
        historySessionData || input['format'] == 'bodytmi-logical-export/30';
    final derivedSessionData =
        derivedBodyMassData || input['format'] == 'bodytmi-logical-export/29';
    final planData =
        derivedSessionData || input['format'] == 'bodytmi-logical-export/28';
    final graphData =
        planData || input['format'] == 'bodytmi-logical-export/27';
    final typedObjectiveData =
        graphData || input['format'] == 'bodytmi-logical-export/26';
    final objectiveData =
        typedObjectiveData || input['format'] == 'bodytmi-logical-export/25';
    final effortTargetsData =
        objectiveData || input['format'] == 'bodytmi-logical-export/24';
    final bandData =
        effortTargetsData || input['format'] == 'bodytmi-logical-export/23';
    final effortData =
        bandData || input['format'] == 'bodytmi-logical-export/22';
    final observationsData =
        effortData || input['format'] == 'bodytmi-logical-export/21';
    final performanceData =
        observationsData || input['format'] == 'bodytmi-logical-export/20';
    final rangeData =
        performanceData || input['format'] == 'bodytmi-logical-export/19';
    final scaleData =
        rangeData || input['format'] == 'bodytmi-logical-export/18';
    final selectionData =
        scaleData || input['format'] == 'bodytmi-logical-export/17';
    final numericPolicyData =
        selectionData || input['format'] == 'bodytmi-logical-export/16';
    final aggregationData =
        numericPolicyData || input['format'] == 'bodytmi-logical-export/15';
    final thresholdData =
        aggregationData || input['format'] == 'bodytmi-logical-export/14';
    final timingDefaultsData =
        thresholdData || input['format'] == 'bodytmi-logical-export/13';
    final familyData =
        timingDefaultsData || input['format'] == 'bodytmi-logical-export/12';
    final declineData =
        familyData || input['format'] == 'bodytmi-logical-export/11';
    final tempoData =
        declineData || input['format'] == 'bodytmi-logical-export/10';
    final groupData =
        tempoData || input['format'] == 'bodytmi-logical-export/9';
    final executionData =
        groupData || input['format'] == 'bodytmi-logical-export/8';
    final timingData =
        executionData || input['format'] == 'bodytmi-logical-export/7';
    final inputDataV6 =
        timingData || input['format'] == 'bodytmi-logical-export/6';
    final inputDataV5 =
        inputDataV6 || input['format'] == 'bodytmi-logical-export/5';
    final massData =
        inputDataV5 || input['format'] == 'bodytmi-logical-export/4';
    final programData =
        massData || input['format'] == 'bodytmi-logical-export/3';
    const programKeys = {
      'programRevisions',
      'programRuns',
      'sessionPrograms',
      'programReceipts',
    };
    // An empty graphs section carries no payload and is equivalent to its
    // absence in v26 and earlier; non-empty graphs remain a v27-only section.
    final hadGraphs = inputData.containsKey('graphs');
    final hadRepeatCheckpoints = inputData.containsKey('repeatCheckpoints');
    if (!repeatData &&
        inputData['repeatCheckpoints'] is List &&
        (inputData['repeatCheckpoints'] as List).isEmpty) {
      inputData.remove('repeatCheckpoints');
    }
    final hadWindowCheckpoints = inputData.containsKey('windowCheckpoints');
    if (!checkpointData) {
      final checkpoints = inputData['windowCheckpoints'];
      if (checkpoints is List<Object?> && checkpoints.isEmpty)
        inputData.remove('windowCheckpoints');
    }
    if (!graphData) {
      final graphs = inputData['graphs'];
      if (graphs is List<Object?> && graphs.isEmpty) {
        inputData.remove('graphs');
      }
    }
    checkKeys(inputData, {
      'revisions',
      'sessions',
      'finalizations',
      if (!legacy) 'progressions',
      if (programData) ...programKeys,
      if (massData) 'bodyMass',
      if (timingData) 'timers',
      if (checkpointData) 'windowCheckpoints',
      if (repeatData) 'repeatCheckpoints',
      if (executionData) 'executions',
      if (familyData) 'families',
      if (graphData) 'graphs',
    });
    if (!legacy && !inputData.containsKey('progressions'))
      invalid('Logical format requires progression records.');
    if (programData && programKeys.any((k) => !inputData.containsKey(k)))
      invalid('Logical v3 requires all program sections.');
    if (massData && !inputData.containsKey('bodyMass'))
      invalid('Logical v4 requires body-mass records.');
    if (timingData && !inputData.containsKey('timers'))
      invalid('Logical v7 requires timing records.');
    if (repeatData && !inputData.containsKey('repeatCheckpoints'))
      invalid('Logical v48 requires repeat checkpoints.');
    if (checkpointData && !inputData.containsKey('windowCheckpoints'))
      invalid('Logical v46 requires window checkpoint records.');
    if (executionData && !inputData.containsKey('executions'))
      invalid('Logical v8 requires execution records.');
    if (familyData && !inputData.containsKey('families'))
      invalid('Logical v12 requires family revisions.');
    if (graphData && !inputData.containsKey('graphs'))
      invalid('Logical v27 requires derived target graph revisions.');
    if (!derivedBodyMassData) {
      for (final item in jsonList(inputData, 'sessions')) {
        final session = jsonObject(item, 'session');
        final input = session['derivedPlanInput'];
        if (input != null &&
            jsonObject(
              input,
              'derived plan input',
            ).containsKey('bodyMassSources')) {
          invalid('Derived body mass session inputs require logical v30.');
        }
      }
    }
    if (!rebindData) {
      for (final item in jsonList(inputData, 'sessions')) {
        if (jsonObject(item, 'session').containsKey('initialBodyMassOverrides'))
          invalid('Body-mass rebind identity requires logical v34.');
      }
    }
    final archive = TrainingArchive.fromJson(inputData);
    if (!repeatRunningData &&
        archive.repeatCheckpoints.any(
          (c) =>
              jsonObject(c.execution['cursor'], 'cursor')['status'] ==
              'running',
        ))
      invalid('Running repeat clocks require logical v50.');
    if (!repeatReservationData &&
        archive.repeatCheckpoints.any((c) => c.reserved))
      invalid('Repeat clock reservations require logical v49.');
    if (!reservationData &&
        archive.windowCheckpoints.any((checkpoint) => checkpoint.reserved))
      invalid('Window clock reservations require logical v47.');
    if (!roleProgressionData &&
        archive.progressions.any((d) => d.role != 'work'))
      invalid('Role-specific progression requires logical v42.');
    if (!extendedRolesData &&
        archive.revisions.any((r) => r.definition.hasExtendedEffortRoles)) {
      invalid('Back-off and drop effort roles require logical v41.');
    }
    if (!manualRestData &&
        archive.revisions.any((r) => r.definition.hasManualRest)) {
      invalid('Manual rest requires logical v40.');
    }
    if (!roundedTargetsData &&
        archive.graphs.any(
          (g) => g.graph.nodes.any((n) => n['kind'] == 'round'),
        )) {
      invalid('Derived native-scale rounding requires logical v39.');
    }
    if (!binaryTargetsData &&
        archive.graphs.any(
          (g) => g.graph.nodes.any(
            (n) => n['kind'] == 'add' || n['kind'] == 'subtract',
          ),
        )) {
      invalid('Binary derived targets require logical v38.');
    }
    if (!carriedTargetsData &&
        (archive.sessions.any(
              (s) => s.sets.any((set) => set.carriedTargets.isNotEmpty),
            ) ||
            archive.progressions.any(
              (p) => p.session.sets.any((set) => set.carriedTargets.isNotEmpty),
            ))) {
      invalid('Carried actual targets require logical v37.');
    }
    if (!manualTargetsData &&
        archive.sessions.any(
          (s) => s.sets.any((set) => set.manualTargets.isNotEmpty),
        )) {
      invalid('Manual session targets require logical v36.');
    }
    if (!massMetadataData &&
        (archive.bodyMass.any((r) => r.measurement.hasMetadata) ||
            archive.sessions.any(sessionHasBodyMassMetadata))) {
      invalid('Body-mass metadata requires logical v35.');
    }
    if (!programPlanData &&
        archive.programRevisions.any(
          (p) => p.definition.plan.nodes.whereType<ProgramDay>().any(
            (day) => day.derivedPlan != null,
          ),
        )) {
      invalid('Program day derived plans require logical v33.');
    }
    if (!targetlessSessionData &&
        archive.sessions.any(usesDerivedTargetlessObjective)) {
      invalid('Derived targetless suggestions require logical v32.');
    }
    if (!historySessionData && archive.sessions.any(usesDerivedHistory)) {
      invalid('Derived history session inputs require logical v31.');
    }
    if (!derivedBodyMassData && archive.sessions.any(usesDerivedBodyMass)) {
      invalid('Derived body mass session inputs require logical v30.');
    }
    if (!derivedSessionData &&
        archive.sessions.any((s) => s.derivedPlanInput != null)) {
      invalid('Derived session inputs require logical v29.');
    }
    if (!planData && archive.graphs.any((g) => g.graph.plans.isNotEmpty)) {
      invalid('Published workout plans require logical v28.');
    }
    if (!typedObjectiveData &&
        archive.revisions.any((r) => r.definition.hasTypedObjectives))
      invalid('Authored numeric objectives require logical v26.');
    if (!objectiveData &&
        archive.revisions.any((r) => r.definition.hasMaxEffortObjectives))
      invalid('Max-effort objectives require logical v25.');
    if (!effortTargetsData &&
        archive.revisions.any((r) => r.definition.hasEffortTargets))
      invalid('Per-effort target overrides require logical v24.');
    if (!bandData &&
        archive.progressions.any(
          (d) =>
              d.ruleType == 'threshold' &&
              ThresholdRule.fromJson(d.rule).incrementBands != null,
        ))
      invalid('Performance increment bands require logical v23.');
    if (!effortData &&
        archive.progressions.any(
          (d) =>
              d.ruleType == 'threshold' &&
              ThresholdRule.fromJson(d.rule).advancementEffort != null,
        ))
      invalid('Advancement effort conditions require logical v22.');
    if (!observationsData &&
        [
          ...archive.sessions,
          ...archive.progressions.map((d) => d.session),
        ].any((s) => s.sets.any((set) => set.observations != null)))
      invalid('Set observations require logical v21.');
    if (!performanceData &&
        archive.progressions.any(
          (d) =>
              d.ruleType == 'threshold' &&
              ThresholdRule.fromJson(d.rule).hasPerformancePolicy,
        ))
      invalid('Explicit performance predicates require logical v20.');
    if (!rangeData &&
        archive.progressions.any(
          (d) =>
              d.ruleType == 'threshold' &&
              ThresholdRule.fromJson(d.rule).hasScaleRanges,
        ))
      invalid('Fixed-increment scale ranges require logical v19.');
    if (!scaleData &&
        archive.progressions.any(
          (d) =>
              d.ruleType == 'threshold' &&
              ThresholdRule.fromJson(d.rule).hasScalePolicy,
        ))
      invalid('Numeric scale bindings require logical v18.');
    if (!selectionData &&
        archive.progressions.any(
          (d) =>
              d.ruleType == 'threshold' &&
              ThresholdRule.fromJson(d.rule).hasSelectionPolicy,
        ))
      invalid('Chosen/priority coordination requires logical v17.');
    if (!numericPolicyData &&
        archive.progressions.any(
          (d) =>
              d.ruleType == 'threshold' &&
              ThresholdRule.fromJson(d.rule).hasNumericPolicy,
        ))
      invalid('Numeric directions and lower bounds require logical v16.');
    if (!aggregationData &&
        archive.progressions.any(
          (d) =>
              d.ruleType == 'threshold' &&
              ThresholdRule.fromJson(d.rule).hasExplicitAggregation,
        ))
      invalid('Explicit result aggregation requires logical v15.');
    if (!thresholdData &&
        archive.progressions.any((d) => d.ruleType != 'double'))
      invalid('Stored threshold progression requires logical v14.');
    if (!openEndedDefaultsData &&
        archive.revisions.any(
          (r) => r.definition.slots.any((s) => s.timing?.openEnded == true),
        ))
      invalid('Open-ended timing defaults require logical v45.');
    if (!timingDefaultsData &&
        archive.revisions.any(
          (r) => r.definition.slots.any((s) => s.timing != null),
        ))
      invalid('Slot timing defaults require logical v13.');
    if (!declineData && archive.progressions.any((d) => d.declinedAt != null))
      invalid('Progression declines require logical v11.');
    if (!openEndedTimingData &&
        (archive.timers.any((t) => t.plan.openEnded) ||
            archive.sessions.any(
              (s) => s.sets.any((set) => set.timing?.termination == 'manual'),
            ) ||
            archive.progressions.any(
              (d) => d.session.sets.any(
                (set) => set.timing?.termination == 'manual',
              ),
            )))
      invalid('Open-ended timing requires logical v44.');
    if (!unplannedTimingData &&
        archive.timers.any((t) => t.plan.unplannedDuration))
      invalid('Unplanned duration timing requires logical v43.');
    if (!tempoData && archive.timers.any((t) => t.plan.tempo != null))
      invalid('Tempo timing requires logical v10.');
    if (!groupData &&
        archive.executions.any(
          (e) => e.receipts.any(
            (r) =>
                jsonObject(r['request'], 'execution request')['action'] ==
                'skip-group',
          ),
        ))
      invalid('Group skipping requires logical v9.');
    if (!executionData && archive.timers.any((t) => t.plan.restOnly))
      invalid('Rest-only timing requires logical v8.');
    if (!inputDataV5 &&
        archive.revisions.any(
          (r) => r.definition.slots.any((s) => s.bodyMass != null),
        ))
      invalid('Body-mass session bindings require logical format v5.');
    if (!inputDataV6 &&
        archive.revisions.any(
          (r) => r.definition.slots.any((s) => s.effectiveMass != null),
        ))
      invalid('Effective-mass models require logical format v6.');
    final data = archive.toJson();
    if (!repeatData && !hadRepeatCheckpoints) data.remove('repeatCheckpoints');
    if (legacy) data.remove('progressions');
    if (!massData) data.remove('bodyMass');
    if (!timingData) data.remove('timers');
    if (!checkpointData && !hadWindowCheckpoints)
      data.remove('windowCheckpoints');
    if (!executionData) data.remove('executions');
    if (!familyData) data.remove('families');
    if (!graphData && !hadGraphs) data.remove('graphs');
    if (!programData) for (final key in programKeys) data.remove(key);
    if (_checksum({
          'format': input['format'],
          'applicationVersion': version,
          'data': data,
        }) !=
        hash) {
      invalid('Logical export checksum mismatch.');
    }
    final stage = await Directory.systemTemp.createTemp('bodytmi-logical-');
    try {
      final path = '${stage.path}/profile.sqlite';
      final db = sqlite3.open(path);
      try {
        db.execute('PRAGMA foreign_keys = ON');
        db.execute('PRAGMA synchronous = FULL');
        db.execute('BEGIN');
        try {
          for (final ddl in schemaV48.values) {
            db.execute(ddl);
          }
          db.execute('PRAGMA application_id = 1112821065');
          db.execute('PRAGMA user_version = 50');
          for (final family in archive.families) {
            db.execute(
              'INSERT INTO family_revisions(family_id,number,snapshot) VALUES (?,?,?)',
              [family.family.id, family.number, canonicalJson(family.toJson())],
            );
          }
          for (final graph in archive.graphs) {
            db.execute(
              'INSERT INTO derived_target_graphs(graph_id,number,snapshot) VALUES (?,?,?)',
              [graph.graph.id, graph.number, canonicalJson(graph.toJson())],
            );
          }
          for (final revision in archive.revisions) {
            db.execute(
              'INSERT INTO revisions (template_id, number, snapshot) VALUES (?, ?, ?)',
              [
                revision.definition.id,
                revision.number,
                canonicalJson(revision.toJson()),
              ],
            );
          }
          for (final session in archive.sessions) {
            db.execute('INSERT INTO sessions (id, snapshot) VALUES (?, ?)', [
              session.id,
              canonicalJson(session.toJson()),
            ]);
          }
          for (final id in archive.finalizations) {
            db.execute('INSERT INTO finalizations (session_id) VALUES (?)', [
              id,
            ]);
          }
          for (final decision in archive.progressions) {
            db.execute(
              'INSERT INTO progression_decisions(session_id,slot_id,snapshot) VALUES (?,?,?)',
              [
                decision.session.id,
                decision.storageSlotKey,
                canonicalJson(decision.toJson()),
              ],
            );
          }
          for (final p in archive.programRevisions)
            db.execute(
              'INSERT INTO program_revisions(program_id,number,snapshot) VALUES (?,?,?)',
              [p.definition.id, p.number, canonicalJson(p.toJson())],
            );
          for (final r in archive.programRuns)
            db.execute('INSERT INTO program_runs(id,snapshot) VALUES (?,?)', [
              r.id,
              canonicalJson(r.toJson()),
            ]);
          for (final b in archive.sessionPrograms)
            db.execute(
              'INSERT INTO session_programs(session_id,run_id,ordinal,snapshot) VALUES (?,?,?,?)',
              [b.sessionId, b.runId, b.ordinal, canonicalJson(b.toJson())],
            );
          for (final r in archive.programReceipts)
            db.execute(
              'INSERT INTO program_receipts(run_id,ordinal,operation_key,session_id,snapshot) VALUES (?,?,?,?,?)',
              [
                r.runId,
                r.ordinal,
                r.operationKey,
                r.sessionId,
                canonicalJson(r.toJson()),
              ],
            );
          for (final r in archive.bodyMass) {
            db.execute(
              'INSERT INTO body_mass_records(id,snapshot) VALUES (?,?)',
              [r.measurement.id, canonicalJson(r.toJson())],
            );
          }
          for (final t in archive.timers) {
            db.execute(
              'INSERT INTO timing_activities(id,session_id,set_id,snapshot) VALUES (?,?,?,?)',
              [t.id, t.sessionId, t.setId, canonicalJson(t.toJson())],
            );
          }
          for (final c in archive.repeatCheckpoints) {
            db.execute(
              'INSERT INTO repeat_checkpoints(id,snapshot) VALUES (?,?)',
              [c.id, canonicalJson(c.toJson())],
            );
          }
          for (final c in archive.windowCheckpoints) {
            db.execute(
              'INSERT INTO window_checkpoints(id,session_id,snapshot) VALUES (?,?,?)',
              [c.id, c.sessionId, canonicalJson(c.toJson())],
            );
          }
          for (final e in archive.executions) {
            db.execute(
              'INSERT INTO workout_executions(id,session_id,snapshot) VALUES (?,?,?)',
              [e.id, e.sessionId, canonicalJson(e.toJson())],
            );
          }
          db.execute('COMMIT');
        } catch (_) {
          db.execute('ROLLBACK');
          rethrow;
        }
      } finally {
        db.close();
      }
      await NativeBackup.create(path, '${stage.path}/native');
      final backup = await NativeBackup.prepare('${stage.path}/native');
      return PreparedLogicalArchive._(
        archive,
        hash,
        sourcePath,
        backup,
        input['format'] as String,
      );
    } finally {
      await stage.delete(recursive: true);
    }
  }
}

final class PreparedLogicalArchive {
  PreparedLogicalArchive._(
    this.archive,
    this.checksum,
    this._sourcePath,
    this.backup,
    this.sourceFormat,
  );
  final TrainingArchive archive;
  final String checksum;
  final String _sourcePath;
  final PreparedNativeBackup backup;
  final String sourceFormat;

  Map<String, Object?> get summary => {
    'format': sourceFormat,
    'sha256': checksum,
    'records': archive.summary,
  };

  Future<void> checkDestination(String destination) async {
    await backup.checkDestination(destination);
    final output = p.normalize(p.absolute(destination));
    var sameSource = output == _sourcePath;
    if (await FileSystemEntity.type(output) != FileSystemEntityType.notFound) {
      final resolved = await File(output).resolveSymbolicLinks();
      sameSource =
          sameSource ||
          resolved == _sourcePath ||
          (await File(_sourcePath).exists() &&
              await FileSystemEntity.identical(resolved, _sourcePath));
    }
    if (sameSource) {
      invalid(
        'Restore destinations must not overwrite the logical source file.',
      );
    }
  }

  Future<void> close() => backup.close();
}

String _checksum(Map<String, Object?> body) =>
    sha256.convert(utf8.encode(canonicalJson(body))).toString();

Future<void> _unused(String destination) async {
  if (await FileSystemEntity.type(destination, followLinks: false) !=
      FileSystemEntityType.notFound) {
    throw const BodyTmiException(
      'conflict',
      'Logical export destination already exists.',
    );
  }
}

Future<String> _read(File file) async {
  if (await file.length() > _maxBytes)
    invalid('Logical export exceeds the 64 MiB resource limit.');
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in file.openRead()) {
    if (bytes.length + chunk.length > _maxBytes)
      invalid('Logical export exceeds the 64 MiB resource limit.');
    bytes.add(chunk);
  }
  return utf8.decode(bytes.takeBytes());
}
