import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';

/// A foreground native clock epoch. Wall time is metadata, never elapsed input.
Future<Map<String, Object?>> runTiming(
  TrainingStore store,
  String id,
  int expectedVersion, {
  int? runForMilliseconds,
  bool stream = false,
}) async {
  final service = TimingService(store);
  final owner =
      'clock-${List.generate(4, (_) => Random.secure().nextInt(0x7fffffff).toRadixString(16)).join('-')}';
  var interrupted = false;
  final subscription = ProcessSignal.sigint.watch().listen((_) {
    interrupted = true;
  });
  final cues = <Map<String, Object?>>[];
  try {
    var current = await service.resume(
      id,
      expectedVersion,
      owner,
      DateTime.now().toUtc(),
    );
    final watch = Stopwatch()..start();
    while (current.status == 'running') {
      final sample = runForMilliseconds == null
          ? watch.elapsedMilliseconds
          : min(watch.elapsedMilliseconds, runForMilliseconds);
      final pause =
          interrupted ||
          (runForMilliseconds != null && sample >= runForMilliseconds);
      final step = await service.advance(
        id,
        current.version,
        owner,
        sample,
        DateTime.now().toUtc(),
        action: pause ? 'pause' : 'advance',
      );
      current = step.activity;
      // A delayed sample can cross several boundaries. Deliver the newest cue,
      // suppressing obsolete cues rather than claiming they sounded on time.
      if (step.cues.isNotEmpty) {
        final cue = {...step.cues.last, 'timerId': id};
        cues.add(cue);
        if (stream)
          stdout.writeln(
            jsonEncode({
              'schemaVersion': 1,
              'data': {'type': 'timing-cue', ...cue},
            }),
          );
      }
      if (current.status != 'running') break;
      final remaining = runForMilliseconds == null
          ? 50
          : runForMilliseconds - watch.elapsedMilliseconds;
      if (remaining > 0)
        await Future<void>.delayed(Duration(milliseconds: min(50, remaining)));
    }
    watch.stop();
    return {
      'timer': current.toJson(),
      'cues': cues,
      'interrupted': interrupted,
      'requiresRecovery': false,
    };
  } finally {
    await subscription.cancel();
  }
}
