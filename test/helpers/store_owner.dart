import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';

Future<void> main(List<String> args) async {
  final store = await TrainingStore.open(args[0]);
  try {
    if (args.length == 4 && args[1].startsWith('finish-')) {
      Future<void> finish() async {
        final s = (await store.session(args[2]))!;
        await StoredTrainingService(store).edit(s.id, s.contentVersion, (
          session,
        ) {
          for (final set in session.sets)
            session = const TrainingService().complete(
              session,
              set.id,
              const {},
              acceptSuggested: true,
            );
          return session.finish(DateTime.parse(args[3]));
        });
      }

      if (args[1] == 'finish-rollback')
        await store.transaction(() async {
          await finish();
          stdout.writeln('ready');
          await stdin.drain<void>();
        });
      else {
        await finish();
        stdout.writeln('ready');
        await stdin.drain<void>();
      }
    } else if (args.length == 5 && args[1].startsWith('accept-')) {
      Future<void> accept() async {
        await StoredProgressionService(
          store,
        ).accept(args[2], args[3], 1, DateTime.parse(args[4]));
      }

      if (args[1] == 'accept-rollback') {
        await store.transaction(() async {
          await accept();
          stdout.writeln('ready');
          await stdin.drain<void>();
        });
      } else {
        await accept();
        stdout.writeln('ready');
        await stdin.drain<void>();
      }
    } else if (args.length == 4 && args[1] == 'restore') {
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
