import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';

Future<void> main(List<String> args) async {
  final store = await TrainingStore.open(args[0]);
  try {
    if (args.length == 4 && args[1] == 'restore') {
      final prepared = await NativeBackup.prepare(args[2]);
      try {
        await store.restore(
          prepared,
          recoveryDestination: args[3],
          confirm: true,
          onProgress: (progress) async {
            if (progress < 1) {
              stdout.writeln('ready');
              await stdin.drain<void>();
            }
          },
        );
      } finally {
        await prepared.close();
      }
    } else if (args.length == 2) {
      await store.transaction(() async {
        final json =
            jsonDecode(File('examples/upper-a.json').readAsStringSync())
                as Map<String, dynamic>;
        await StoredTrainingService(
          store,
        ).publish(WorkoutDefinition.fromJson(json['definition']), 0);
        stdout.writeln('ready');
        await stdin.drain<void>();
      });
    } else {
      stdout.writeln('ready');
      await stdin.drain<void>();
    }
  } finally {
    await store.close();
  }
}
