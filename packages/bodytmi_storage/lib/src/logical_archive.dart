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

const _format = 'bodytmi-logical-export/2';
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
    if (!{_format, 'bodytmi-logical-export/1'}.contains(input['format']))
      invalid('Unsupported logical export format.');
    final version = requiredString(input, 'applicationVersion');
    final hash = requiredString(input, 'sha256');
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash))
      invalid('Invalid logical export checksum.');
    final legacy = input['format'] == 'bodytmi-logical-export/1';
    if (!legacy &&
        !jsonObject(input['data'], 'logical data').containsKey('progressions'))
      invalid('Logical format v2 requires progression records.');
    if (legacy)
      checkKeys(jsonObject(input['data'], 'legacy logical data'), {
        'revisions',
        'sessions',
        'finalizations',
      });
    final archive = TrainingArchive.fromJson(input['data']);
    final data = archive.toJson();
    if (legacy) data.remove('progressions');
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
          for (final ddl in schemaV2.values) {
            db.execute(ddl);
          }
          db.execute('PRAGMA application_id = 1112821065');
          db.execute('PRAGMA user_version = 2');
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
