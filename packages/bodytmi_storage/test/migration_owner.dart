import 'dart:io';
import 'package:drift/native.dart';
import 'package:bodytmi_storage/src/database.dart';

/// Pause inside the actual schema creation transaction after validation, before commit.
final class PausingDatabase extends TrainingDatabase {
  PausingDatabase(super.executor);
  @override
  Future<void> validateMigration() async {
    await super.validateMigration();
    stdout.writeln('ready');
    await stdin.drain<void>();
  }
}

Future<void> main(List<String> args) async {
  final db = PausingDatabase(NativeDatabase(File(args.single)));
  try {
    await db.customSelect('SELECT 1').get();
  } finally {
    await db.close();
  }
}
