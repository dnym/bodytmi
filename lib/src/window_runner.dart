import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';

/// Runs one reserved scoped clock epoch using monotonic elapsed samples.
Future<Map<String, Object?>> runWindowClock(
  TrainingStore store,
  String id,
  int expectedVersion,
  int expectedSessionVersion,
  int expectedClockVersion, {
  int? runForMilliseconds,
  bool stream = false,
  bool advanceReviewed = false,
}) async {
  final service = WindowCheckpointService(store);
  final random = Random.secure();
  final owner =
      'window-${List.generate(4, (_) => random.nextInt(0x7fffffff).toRadixString(16)).join('-')}';
  var interrupted = false;
  final subscription = ProcessSignal.sigint.watch().listen((_) {
    interrupted = true;
  });
  try {
    var current = await service.action(
      id,
      expectedVersion: expectedVersion,
      expectedSessionVersion: expectedSessionVersion,
      expectedClockVersion: expectedClockVersion,
      action: 'resume',
      ownerId: owner,
    );
    final watch = Stopwatch()..start();
    if (stream) {
      stdout.writeln(
        jsonEncode({
          'schemaVersion': 1,
          'data': {'type': 'window-started', 'checkpointId': id},
        }),
      );
      await stdout.flush();
    }
    var state = jsonObject(current.clock['clock'], 'clock');
    while (state['status'] == 'running') {
      final sample = runForMilliseconds == null
          ? watch.elapsedMilliseconds
          : min(watch.elapsedMilliseconds, runForMilliseconds);
      final pause =
          interrupted ||
          (runForMilliseconds != null && sample >= runForMilliseconds);
      current = await service.action(
        id,
        expectedVersion: current.version,
        expectedSessionVersion: expectedSessionVersion,
        expectedClockVersion: state['version'] as int,
        action: pause ? 'pause' : 'advance',
        ownerId: owner,
        ownerElapsedMilliseconds: sample,
      );
      state = jsonObject(current.clock['clock'], 'clock');
      if (state['status'] != 'running') break;
      final remaining = runForMilliseconds == null
          ? 50
          : runForMilliseconds - watch.elapsedMilliseconds;
      if (remaining > 0) {
        await Future<void>.delayed(Duration(milliseconds: min(50, remaining)));
      }
    }
    watch.stop();
    final cues = <Map<String, Object?>>[];
    var boundaryAdvanced = false;
    if (state['status'] == 'boundary') {
      final cue = {
        'type': 'window-boundary',
        'checkpointId': id,
        'boundaryEvidence': state['boundaryEvidence'],
      };
      cues.add(cue);
      if (stream) {
        stdout.writeln(jsonEncode({'schemaVersion': 1, 'data': cue}));
      }
      if (advanceReviewed && !interrupted) {
        final advanced = await service.advanceReviewedBoundary(
          id,
          expectedVersion: current.version,
          expectedSessionVersion: expectedSessionVersion,
          expectedClockVersion: state['version'] as int,
        );
        if (advanced != null) {
          current = advanced;
          boundaryAdvanced = true;
        }
      }
    }
    return {
      'checkpoint': current.toJson(),
      'cues': cues,
      'cueCount': cues.length,
      'omittedCueCount': 0,
      'interrupted': interrupted,
      'requiresRecovery': false,
      if (advanceReviewed) 'boundaryAdvanced': boundaryAdvanced,
    };
  } finally {
    await subscription.cancel();
  }
}
