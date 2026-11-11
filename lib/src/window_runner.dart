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
  bool stopAtRest = false,
}) async {
  final service = WindowCheckpointService(store);
  int? restRemaining;
  int? restDuration;
  String? restOccurrenceId;
  if (stopAtRest) {
    final view = await service.status(id);
    final checkpoint = jsonObject(view['checkpoint'], 'checkpoint');
    final state = jsonObject(
      jsonObject(checkpoint['clock'], 'clock')['clock'],
      'clock',
    );
    if (checkpoint['version'] != expectedVersion ||
        view['sessionContentVersion'] != expectedSessionVersion ||
        state['version'] != expectedClockVersion)
      throw const BodyTmiException(
        'conflict',
        'Checkpoint, session or clock version changed.',
      );
    final current = view['currentOccurrence'];
    final restView = view['rest'];
    if (current == null || restView == null)
      invalid('stopAtRest requires a current timed rest.');
    final rest = jsonObject(restView, 'rest');
    if (rest['manual'] == true || rest['remainingMilliseconds'] is! int)
      invalid(
        'stopAtRest requires a timed rest with a known occurrence start.',
      );
    restRemaining = rest['remainingMilliseconds'] as int;
    restDuration = rest['durationMilliseconds'] as int;
    restOccurrenceId = jsonObject(current, 'occurrence')['id'] as String;
  }
  final limit = restRemaining == null
      ? runForMilliseconds
      : runForMilliseconds == null
      ? restRemaining
      : min(restRemaining, runForMilliseconds);
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
      final sample = limit == null
          ? watch.elapsedMilliseconds
          : min(watch.elapsedMilliseconds, limit);
      final pause = interrupted || (limit != null && sample >= limit);
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
      final remaining = limit == null ? 50 : limit - watch.elapsedMilliseconds;
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
    } else if (stopAtRest &&
        !interrupted &&
        restRemaining != null &&
        limit == restRemaining &&
        state['status'] == 'paused') {
      final cue = {
        'type': 'window-rest-target',
        'checkpointId': id,
        'occurrenceId': restOccurrenceId,
        'durationMilliseconds': restDuration,
      };
      cues.add(cue);
      if (stream) stdout.writeln(jsonEncode({'schemaVersion': 1, 'data': cue}));
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
