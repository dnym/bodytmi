import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';

Future<void> main(List<String> args) async {
  final store = await TrainingStore.open(args[0]);
  try {
    if (args.length == 2 && args[1].startsWith('repeat-action-')) {
      Future<void> action() async {
        await RepeatCheckpointService(store).action(
          'repeat',
          expectedVersion: 1,
          expectedExecutionVersion: 1,
          action: 'review',
          review: {'outcome': 'completed', 'acceptSuggested': true},
        );
      }

      if (args[1].endsWith('rollback')) {
        await store.transaction(() async {
          await action();
          stdout.writeln('ready');
          await stdin.drain<void>();
        });
      } else {
        await action();
        stdout.writeln('ready');
        await stdin.drain<void>();
      }
    } else if (args.length == 2 && args[1].startsWith('checkpoint-action-')) {
      Future<void> action() async {
        await WindowCheckpointService(store).action(
          'cp',
          expectedVersion: 2,
          expectedSessionVersion: 1,
          expectedClockVersion: 1,
          action: 'resume',
          ownerId: 'crashed-epoch',
        );
      }

      if (args[1].endsWith('rollback')) {
        await store.transaction(() async {
          await action();
          stdout.writeln('ready');
          await stdin.drain<void>();
        });
      } else {
        await action();
        stdout.writeln('ready');
        await stdin.drain<void>();
      }
    } else if (args.length == 2 && args[1].startsWith('checkpoint-reserve-')) {
      Future<void> action() async {
        await WindowCheckpointService(store).reserve('cp', 1);
      }

      if (args[1].endsWith('rollback')) {
        await store.transaction(() async {
          await action();
          stdout.writeln('ready');
          await stdin.drain<void>();
        });
      } else {
        await action();
        stdout.writeln('ready');
        await stdin.drain<void>();
      }
    } else if (args.length == 2 &&
        (args[1].startsWith('checkpoint-review-') ||
            args[1].startsWith('reserved-review-'))) {
      Future<void> action() async {
        await WindowCheckpointService(store).review(
          'cp',
          expectedVersion: args[1].startsWith('reserved-review-') ? 2 : 1,
          expectedSessionVersion: 1,
          expectedClockVersion: 1,
          toOccurrence: 1,
          action: 'skip',
          confirm: true,
        );
      }

      if (args[1].endsWith('rollback')) {
        await store.transaction(() async {
          await action();
          stdout.writeln('ready');
          await stdin.drain<void>();
        });
      } else {
        await action();
        stdout.writeln('ready');
        await stdin.drain<void>();
      }
    } else if (args.length == 2 && args[1].startsWith('family-')) {
      Future<void> publish() async {
        await FamilyService(store).publish(
          ExerciseFamily.fromJson({
            'id': 'rows',
            'name': 'Rows',
            'exercises': ['row'],
          }),
          0,
        );
      }

      if (args[1].endsWith('rollback')) {
        await store.transaction(() async {
          await publish();
          stdout.writeln('ready');
          await stdin.drain<void>();
        });
      } else {
        await publish();
        stdout.writeln('ready');
        await stdin.drain<void>();
      }
    } else if (args.length == 2 &&
        (args[1].startsWith('execution-step-') ||
            args[1].startsWith('execution-group-'))) {
      Future<void> action() async {
        if (args[1].startsWith('execution-group-')) {
          await ExecutionService(store).skipGroup(
            'execution',
            1,
            1,
            'crash-group',
            'workout/rounds[0]',
            DateTime.utc(2026, 10, 1, 12),
            confirm: true,
          );
          return;
        }
        await ExecutionService(store).step(
          'execution',
          1,
          1,
          'crash-step',
          DateTime.utc(2026, 10, 1, 12),
          action: 'complete',
          acceptSuggested: true,
        );
      }

      if (args[1].endsWith('rollback'))
        await store.transaction(() async {
          await action();
          stdout.writeln('ready');
          await stdin.drain<void>();
        });
      else {
        await store.transaction(action);
        stdout.writeln('ready');
        await stdin.drain<void>();
      }
    } else if (args.length == 2 &&
        (args[1].startsWith('clock-') ||
            args[1].startsWith('confirm-timing-'))) {
      Future<void> action() async {
        final service = TimingService(store);
        var t = await service.show('clock');
        final at = DateTime.utc(2026, 10, 1, 12);
        if (args[1].startsWith('clock-')) {
          t = await service.resume(t.id, t.version, 'crashed-epoch', at);
          await service.advance(t.id, t.version, 'crashed-epoch', 15000, at);
        } else {
          final session = (await store.session(t.sessionId))!;
          await service.confirm(
            t.id,
            t.version,
            session.contentVersion,
            at,
            {},
            acceptSuggested: true,
          );
        }
      }

      if (args[1].endsWith('rollback')) {
        await store.transaction(() async {
          await action();
          stdout.writeln('ready');
          await stdin.drain<void>();
        });
      } else {
        await store.transaction(action);
        stdout.writeln('ready');
        await stdin.drain<void>();
      }
    } else if (args.length == 2 && args[1].startsWith('mass-')) {
      Future<void> write() async {
        final service = StoredBodyMassService(store);
        final one = await service.show('one');
        final observation = Map<String, Object?>.from(one.measurement.toJson())
          ..remove('contentVersion');
        observation['mass'] = {'value': '72', 'unit': 'kg'};
        await service.save(observation, 1);
        await service.delete('one', 2, confirm: true);
        await service.save({...observation, 'id': 'two'}, 0);
      }

      if (args[1] == 'mass-rollback') {
        await store.transaction(() async {
          await write();
          stdout.writeln('ready');
          await stdin.drain<void>();
        });
      } else {
        await store.transaction(write);
        stdout.writeln('ready');
        await stdin.drain<void>();
      }
    } else if (args.length == 4 && args[1].startsWith('finish-')) {
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
    } else if (args.length == 5 &&
        (args[1].startsWith('accept-') || args[1].startsWith('decline-'))) {
      Future<void> accept() async {
        final service = StoredProgressionService(store);
        if (args[1].startsWith('decline-')) {
          await service.decline(args[2], args[3], 1, DateTime.parse(args[4]));
        } else {
          await service.accept(args[2], args[3], 1, DateTime.parse(args[4]));
        }
      }

      if (args[1].endsWith('-rollback')) {
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
