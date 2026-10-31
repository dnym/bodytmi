import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';

Future<void> main(List<String> args) async {
  final store = await TrainingStore.open(args[0]);
  try {
    if (args.length == 2) {
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
