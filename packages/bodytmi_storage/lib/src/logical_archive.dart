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

const _format = 'bodytmi-logical-export/13';
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
    }.contains(input['format']))
      invalid('Unsupported logical export format.');
    final version = requiredString(input, 'applicationVersion');
    final hash = requiredString(input, 'sha256');
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash))
      invalid('Invalid logical export checksum.');
    final inputData = jsonObject(input['data'], 'logical data');
    final legacy = input['format'] == 'bodytmi-logical-export/1';
    final timingDefaultsData = input['format'] == _format;
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
    checkKeys(inputData, {
      'revisions',
      'sessions',
      'finalizations',
      if (!legacy) 'progressions',
      if (programData) ...programKeys,
      if (massData) 'bodyMass',
      if (timingData) 'timers',
      if (executionData) 'executions',
      if (familyData) 'families',
    });
    if (!legacy && !inputData.containsKey('progressions'))
      invalid('Logical format requires progression records.');
    if (programData && programKeys.any((k) => !inputData.containsKey(k)))
      invalid('Logical v3 requires all program sections.');
    if (massData && !inputData.containsKey('bodyMass'))
      invalid('Logical v4 requires body-mass records.');
    if (timingData && !inputData.containsKey('timers'))
      invalid('Logical v7 requires timing records.');
    if (executionData && !inputData.containsKey('executions'))
      invalid('Logical v8 requires execution records.');
    if (familyData && !inputData.containsKey('families'))
      invalid('Logical v12 requires family revisions.');
    final archive = TrainingArchive.fromJson(inputData);
    if (!timingDefaultsData &&
        archive.revisions.any(
          (r) => r.definition.slots.any((s) => s.timing != null),
        ))
      invalid('Slot timing defaults require logical v13.');
    if (!declineData && archive.progressions.any((d) => d.declinedAt != null))
      invalid('Progression declines require logical v11.');
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
    if (legacy) data.remove('progressions');
    if (!massData) data.remove('bodyMass');
    if (!timingData) data.remove('timers');
    if (!executionData) data.remove('executions');
    if (!familyData) data.remove('families');
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
          for (final ddl in schemaV12.values) {
            db.execute(ddl);
          }
          db.execute('PRAGMA application_id = 1112821065');
          db.execute('PRAGMA user_version = 13');
          for (final family in archive.families) {
            db.execute(
              'INSERT INTO family_revisions(family_id,number,snapshot) VALUES (?,?,?)',
              [family.family.id, family.number, canonicalJson(family.toJson())],
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
                decision.slotId,
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
