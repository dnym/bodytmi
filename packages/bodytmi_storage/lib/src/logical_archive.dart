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

const _format = 'bodytmi-logical-export/1';
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
    if (input['format'] != _format)
      invalid('Unsupported logical export format.');
    final version = requiredString(input, 'applicationVersion');
    final hash = requiredString(input, 'sha256');
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash))
      invalid('Invalid logical export checksum.');
    final inputData = jsonObject(input['data'], 'logical data');
    const sections = {
      'revisions',
      'sessions',
      'finalizations',
      'progressions',
      'programRevisions',
      'programRuns',
      'sessionPrograms',
      'programReceipts',
      'observations',
      'foods',
      'diaryEntries',
      'measures',
      'seriesPolicies',
      'profile',
      'bodyFatSources',
      'dietRecords',
      'timers',
      'windowCheckpoints',
      'repeatCheckpoints',
      'reconciliations',
      'links',
      'sharedApplications',
      'linkRetirements',
      'programUpgrades',
      'executions',
      'families',
      'graphs',
      'exercises',
      'implementations',
      'presets',
      'blueprints',
      'blueprintInstances',
      'equipment',
      'gyms',
      'instances',
      'importedSessions',
      'blockProgressions',
    };
    checkKeys(inputData, sections);
    for (final section in sections) {
      if (!inputData.containsKey(section))
        invalid('Logical export is missing its $section section.');
    }
    final archive = TrainingArchive.fromJson(inputData);

    final data = archive.toJson();

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
          for (final ddl in schema.values) {
            db.execute(ddl);
          }
          db.execute('PRAGMA application_id = 1112821065');
          db.execute('PRAGMA user_version = $supportedSchemaVersion');
          for (final family in archive.families) {
            db.execute(
              'INSERT INTO family_revisions(family_id,number,snapshot) VALUES (?,?,?)',
              [family.family.id, family.number, canonicalJson(family.toJson())],
            );
          }
          for (final exercise in archive.exercises) {
            db.execute(
              'INSERT INTO exercise_revisions(exercise_id,number,snapshot) VALUES (?,?,?)',
              [
                exercise.exercise.id,
                exercise.number,
                canonicalJson(exercise.toJson()),
              ],
            );
          }
          for (final implementation in archive.implementations) {
            db.execute(
              'INSERT INTO implementation_revisions(implementation_id,number,snapshot) VALUES (?,?,?)',
              [
                implementation.implementation.id,
                implementation.number,
                canonicalJson(implementation.toJson()),
              ],
            );
          }
          for (final preset in archive.presets) {
            db.execute(
              'INSERT INTO progression_preset_revisions(preset_id,number,snapshot) VALUES (?,?,?)',
              [preset.preset.id, preset.number, canonicalJson(preset.toJson())],
            );
          }
          for (final b in archive.blueprints) {
            db.execute(
              'INSERT INTO blueprint_revisions(blueprint_id,number,snapshot) VALUES (?,?,?)',
              [b.blueprint.id, b.number, canonicalJson(b.toJson())],
            );
          }
          for (final i in archive.blueprintInstances) {
            db.execute(
              'INSERT INTO blueprint_instances(instance_id,number,snapshot) VALUES (?,?,?)',
              [i.id, i.number, canonicalJson(i.toJson())],
            );
          }
          for (final equipment in archive.equipment) {
            db.execute(
              'INSERT INTO equipment_revisions(equipment_id,number,snapshot) VALUES (?,?,?)',
              [
                equipment.equipment.id,
                equipment.number,
                canonicalJson(equipment.toJson()),
              ],
            );
          }
          for (final gym in archive.gyms) {
            db.execute(
              'INSERT INTO gym_revisions(gym_id,number,snapshot) VALUES (?,?,?)',
              [gym.gym.id, gym.number, canonicalJson(gym.toJson())],
            );
          }
          for (final instance in archive.instances) {
            db.execute(
              'INSERT INTO equipment_instance_revisions(instance_id,number,snapshot) VALUES (?,?,?)',
              [
                instance.instance.id,
                instance.number,
                canonicalJson(instance.toJson()),
              ],
            );
          }
          for (final decision in archive.blockProgressions) {
            db.execute(
              'INSERT INTO block_progressions(id,snapshot) VALUES (?,?)',
              [decision.id, canonicalJson(decision.toJson())],
            );
          }
          for (final record in archive.importedSessions) {
            db.execute(
              'INSERT INTO imported_sessions(namespace,source_id,snapshot) VALUES (?,?,?)',
              [
                record.namespace,
                record.sourceId,
                canonicalJson(record.toJson()),
              ],
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
            db.execute(
              'INSERT INTO sessions (id, template_id, snapshot) VALUES (?, ?, ?)',
              [
                session.id,
                session.definition.id,
                canonicalJson(session.toJson()),
              ],
            );
          }
          for (final id in archive.finalizations) {
            db.execute('INSERT INTO finalizations (session_id) VALUES (?)', [
              id,
            ]);
          }
          for (final decision in archive.progressions) {
            db.execute(
              'INSERT INTO progression_decisions(session_id,slot_id,template_id,run_id,sequence,snapshot) VALUES (?,?,?,?,?,?)',
              [
                decision.session.id,
                decision.storageSlotKey,
                decision.templateId,
                decision.runId,
                decision.sequence,
                canonicalJson(decision.toJson()),
              ],
            );
          }
          for (final receipt in archive.reconciliations)
            db.execute(
              'INSERT INTO progression_reconciliations(id,snapshot) VALUES (?,?)',
              [receipt.id, canonicalJson(receipt.toJson())],
            );
          for (final link in archive.links)
            db.execute(
              'INSERT INTO lever_link_revisions(link_id,number,snapshot) VALUES (?,?,?)',
              [link.link.id, link.number, canonicalJson(link.toJson())],
            );
          for (final a in archive.sharedApplications)
            db.execute(
              'INSERT INTO shared_lever_applications(link_id,sequence,snapshot) VALUES (?,?,?)',
              [a.linkId, a.sequence, canonicalJson(a.toJson())],
            );
          for (final r in archive.linkRetirements)
            db.execute(
              'INSERT INTO link_retirement_anchors(id,snapshot) VALUES (?,?)',
              [r.id, canonicalJson(r.toJson())],
            );
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
          for (final u in archive.programUpgrades)
            db.execute(
              'INSERT INTO program_upgrade_receipts(run_id,request_id,snapshot) VALUES (?,?,?)',
              [u.runId, u.requestId, canonicalJson(u.toJson())],
            );
          for (final p in archive.profile) {
            db.execute(
              'INSERT INTO profile_revisions(number,snapshot) VALUES (?,?)',
              [p.number, canonicalJson(p.toJson())],
            );
          }
          for (final r in archive.dietRecords) {
            db.execute(
              'INSERT INTO diet_records(kind,id,number,snapshot) VALUES (?,?,?,?)',
              [r.kind, r.id, r.number, canonicalJson(r.snapshot)],
            );
          }
          for (final s in archive.bodyFatSources) {
            db.execute(
              'INSERT INTO body_fat_sources(number,snapshot) VALUES (?,?)',
              [s.number, canonicalJson(s.toJson())],
            );
          }
          for (final p in archive.seriesPolicies) {
            db.execute(
              'INSERT INTO series_policies(series_key,number,snapshot) VALUES (?,?,?)',
              [p.key, p.number, canonicalJson(p.toJson())],
            );
          }
          for (final m in archive.measures) {
            db.execute(
              'INSERT INTO measure_revisions(measure_id,number,snapshot) VALUES (?,?,?)',
              [m.measure.id, m.number, canonicalJson(m.toJson())],
            );
          }
          for (final r in archive.observations) {
            db.execute(
              'INSERT INTO observations(id,measure_id,local_date,snapshot) VALUES (?,?,?,?)',
              [
                r.observation.id,
                r.observation.measureId,
                r.observation.localDate,
                canonicalJson(r.toJson()),
              ],
            );
          }
          for (final f in archive.foods) {
            db.execute(
              'INSERT INTO food_revisions(food_id,number,snapshot) VALUES (?,?,?)',
              [f.food.id, f.number, canonicalJson(f.toJson())],
            );
          }
          for (final e in archive.diaryEntries) {
            db.execute(
              'INSERT INTO diary_entries(id,local_date,snapshot) VALUES (?,?,?)',
              [e.id, e.date, canonicalJson(e.toJson())],
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
