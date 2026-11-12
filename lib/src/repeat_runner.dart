import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';

/// Runs a reserved repeat clock using foreground monotonic samples.
Future<Map<String, Object?>> runRepeatClock(
  TrainingStore store,
  String id,
  int expectedVersion,
  int expectedExecutionVersion, {
  int? runForMilliseconds,
  bool stream = false,
}) async {
  final service = RepeatCheckpointService(store);
  final random = Random.secure();
  final owner =
      'repeat-${List.generate(4, (_) => random.nextInt(0x7fffffff).toRadixString(16)).join('-')}';
  var interrupted = false;
  final subscription = ProcessSignal.sigint.watch().listen((_) {
    interrupted = true;
  });
  try {
    var checkpoint = await service.action(
      id,
      expectedVersion: expectedVersion,
      expectedExecutionVersion: expectedExecutionVersion,
      action: 'resume',
      ownerId: owner,
    );
    final watch = Stopwatch()..start();
    if (stream) {
      stdout.writeln(
        jsonEncode({
          'schemaVersion': 1,
          'data': {'type': 'repeat-started', 'checkpointId': id},
        }),
      );
      await stdout.flush();
    }
    var state = jsonObject(checkpoint.execution['cursor'], 'cursor');
    while (state['status'] == 'running') {
      final sample = runForMilliseconds == null
          ? watch.elapsedMilliseconds
          : min(watch.elapsedMilliseconds, runForMilliseconds);
      final pause =
          interrupted ||
          (runForMilliseconds != null && sample >= runForMilliseconds);
      checkpoint = await service.action(
        id,
        expectedVersion: checkpoint.version,
        expectedExecutionVersion: checkpoint.execution['version'] as int,
        action: pause ? 'pause' : 'advance',
        ownerId: owner,
        ownerElapsedMilliseconds: sample,
      );
      state = jsonObject(checkpoint.execution['cursor'], 'cursor');
      if (state['status'] != 'running') break;
      final remaining = runForMilliseconds == null
          ? 50
          : runForMilliseconds - watch.elapsedMilliseconds;
      if (remaining > 0)
        await Future<void>.delayed(Duration(milliseconds: min(50, remaining)));
    }
    watch.stop();
    final cues = <Map<String, Object?>>[];
    if (state['status'] == 'boundary') {
      final cue = {'type': 'repeat-boundary', 'checkpointId': id};
      cues.add(cue);
      if (stream) stdout.writeln(jsonEncode({'schemaVersion': 1, 'data': cue}));
    }
    return {
      'checkpoint': checkpoint.toJson(),
      'cues': cues,
      'cueCount': cues.length,
      'omittedCueCount': 0,
      'interrupted': interrupted,
      'requiresRecovery': false,
    };
  } finally {
    await subscription.cancel();
  }
}
