import 'package:bodytmi_core/bodytmi_core.dart';
import 'canonical_json.dart';
import 'window_deadlines.dart';

/// Caller-owned scoped logical clock. It records neither traversal nor results.
final class WindowClock {
  const WindowClock();
  static const _limit = 2000000000;
  static const _deadlines = WindowDeadlines();

  Map<String, Object?> start(WorkoutDefinition definition) {
    final scopes = activityGroups(
      definition.plan,
      containing: 0,
    ).where((scope) => scope.windowDurationSeconds != null);
    return _validate(definition, {
      'policy': 'bodytmi-window-clock/1',
      'version': 1,
      'definition': definition.toJson(),
      'status': 'paused',
      'occurrence': 0,
      'elapsedMilliseconds': 0,
      'windowStarts': {for (final scope in scopes) scope.path: 0},
      'ownerId': null,
      'ownerElapsedMilliseconds': 0,
    });
  }

  Map<String, Object?> apply(
    WorkoutDefinition definition,
    Object? input, {
    required int expectedVersion,
    required String action,
    String? ownerId,
    int? ownerElapsedMilliseconds,
    int? toOccurrence,
    int? adjustmentMilliseconds,
  }) {
    final state = _validate(definition, input);
    if (state['version'] != expectedVersion)
      throw const BodyTmiException('conflict', 'Window clock version changed.');
    final status = state['status'];
    final version = state['version'] as int;
    final elapsed = state['elapsedMilliseconds'] as int;
    final occurrence = state['occurrence'] as int;
    final starts = jsonObject(state['windowStarts'], 'windowStarts');
    final next = <String, Object?>{...state, 'version': version + 1};
    if (action != 'recover' && adjustmentMilliseconds != null)
      invalid('Only recovery accepts an elapsed adjustment.');
    switch (action) {
      case 'resume':
        if (status != 'paused' ||
            ownerId == null ||
            ownerElapsedMilliseconds != null ||
            toOccurrence != null)
          invalid('Resume requires a paused clock and an owner.');
        identifier({'id': ownerId}, 'id');
        next.addAll({
          'status': 'running',
          'ownerId': ownerId,
          'ownerElapsedMilliseconds': 0,
        });
      case 'advance':
      case 'pause':
        if (status != 'running' ||
            ownerId == null ||
            ownerId != state['ownerId'] ||
            ownerElapsedMilliseconds == null ||
            toOccurrence != null)
          invalid(
            'A running clock requires its owner and a cumulative sample.',
          );
        final prior = state['ownerElapsedMilliseconds'] as int;
        if (ownerElapsedMilliseconds < prior ||
            ownerElapsedMilliseconds > _limit ||
            elapsed + ownerElapsedMilliseconds - prior > _limit)
          invalid(
            'Clock samples must be monotonic and within the logical-time limit.',
          );
        final sample = elapsed + ownerElapsedMilliseconds - prior;
        final crossing = _deadlines.crossing(
          definition: definition,
          occurrence: occurrence,
          previousElapsedMilliseconds: elapsed,
          elapsedMilliseconds: sample,
          windowStarts: starts,
        );
        if (crossing['status'] == 'crossed') {
          final boundary = jsonObject(crossing['boundary'], 'boundary');
          next.addAll({
            'status': 'boundary',
            'elapsedMilliseconds': boundary['elapsedMilliseconds'],
            'ownerId': null,
            'ownerElapsedMilliseconds': 0,
          });
        } else {
          next.addAll({
            'elapsedMilliseconds': sample,
            'status': action == 'pause' ? 'paused' : 'running',
            'ownerId': action == 'pause' ? null : ownerId,
            'ownerElapsedMilliseconds': action == 'pause'
                ? 0
                : ownerElapsedMilliseconds,
          });
        }
      case 'recover':
        if (status != 'running' ||
            ownerId != null ||
            ownerElapsedMilliseconds != null ||
            toOccurrence != null)
          invalid('Recovery requires an interrupted running clock.');
        final adjustment = adjustmentMilliseconds ?? 0;
        if (adjustment < 0 ||
            adjustment > _limit ||
            elapsed + adjustment > _limit)
          invalid(
            'Recovery adjustment must fit within the logical-time limit.',
          );
        final sample = elapsed + adjustment;
        final crossing = _deadlines.crossing(
          definition: definition,
          occurrence: occurrence,
          previousElapsedMilliseconds: elapsed,
          elapsedMilliseconds: sample,
          windowStarts: starts,
        );
        final boundary = crossing['status'] == 'crossed'
            ? jsonObject(
                crossing['boundary'],
                'boundary',
              )['elapsedMilliseconds']
            : null;
        next.addAll({
          'status': boundary == null ? 'paused' : 'boundary',
          'elapsedMilliseconds': boundary ?? sample,
          'ownerId': null,
          'ownerElapsedMilliseconds': 0,
        });
      case 'move':
        if (!{'paused', 'boundary'}.contains(status) ||
            toOccurrence == null ||
            ownerId != null ||
            ownerElapsedMilliseconds != null)
          invalid(
            'Move requires a paused clock or a pending boundary and a destination.',
          );
        final move = _deadlines.transition(
          definition: definition,
          fromOccurrence: occurrence,
          toOccurrence: toOccurrence,
          elapsedMilliseconds: elapsed,
          windowStarts: starts,
        );
        final count = definition.plan.occurrences().length;
        next.addAll({
          'status': toOccurrence == count ? 'complete' : 'paused',
          'occurrence': toOccurrence,
          'windowStarts': move['windowStarts'],
        });
      default:
        invalid('Unknown window clock action.');
    }
    return _validate(definition, next);
  }

  Map<String, Object?> _validate(WorkoutDefinition definition, Object? input) {
    final state = jsonObject(input, 'window clock');
    checkKeys(state, {
      'policy',
      'definition',
      'version',
      'status',
      'occurrence',
      'elapsedMilliseconds',
      'windowStarts',
      'ownerId',
      'ownerElapsedMilliseconds',
    });
    if (state['policy'] != 'bodytmi-window-clock/1')
      invalid('Unsupported window clock policy.');
    if (canonicalJson(state['definition']) !=
        canonicalJson(definition.toJson()))
      invalid('Window clock definition does not match the pinned workout.');
    final version = state['version'],
        status = state['status'],
        occurrence = state['occurrence'],
        elapsed = state['elapsedMilliseconds'];
    final owner = state['ownerId'], sample = state['ownerElapsedMilliseconds'];
    final starts = jsonObject(state['windowStarts'], 'windowStarts');
    final count = definition.plan.occurrences().length;
    if (version is! int ||
        version < 1 ||
        !{'paused', 'running', 'boundary', 'complete'}.contains(status) ||
        occurrence is! int ||
        occurrence < 0 ||
        occurrence > count ||
        elapsed is! int ||
        elapsed < 0 ||
        elapsed > _limit ||
        sample is! int ||
        sample < 0 ||
        sample > _limit ||
        sample > elapsed)
      invalid('Invalid window clock state.');
    if (status == 'running') {
      identifier({'id': owner}, 'id');
    } else if (owner != null || sample != 0) {
      invalid('Only running clocks have an owner sample.');
    }
    if (status == 'complete') {
      if (occurrence != count || starts.isNotEmpty)
        invalid('Invalid completed window clock.');
    } else {
      if (occurrence >= count)
        invalid('Invalid active window clock occurrence.');
      final view = _deadlines.evaluate(
        definition: definition,
        occurrence: occurrence,
        elapsedMilliseconds: elapsed,
        windowStarts: starts,
      );
      final deadline = view['earliestDeadlineMilliseconds'];
      if ((status == 'boundary' && (deadline == null || deadline != elapsed)) ||
          (status != 'boundary' && view['expired'] == true))
        invalid('Window clock state does not match its boundary.');
    }
    return {
      ...state,
      'windowStarts': Map<String, Object?>.unmodifiable(starts),
    };
  }
}
