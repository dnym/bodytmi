import 'package:bodytmi_core/bodytmi_core.dart';

/// Calculates scoped boundaries from caller-supplied logical elapsed time.
/// It neither owns a clock nor records an execution or completed effort.
final class WindowDeadlines {
  const WindowDeadlines();

  /// Reports the first boundary reached by a pair of logical-time samples.
  /// A caller must handle that boundary before sampling later deadlines.
  Map<String, Object?> crossing({
    required WorkoutDefinition definition,
    required int occurrence,
    required int previousElapsedMilliseconds,
    required int elapsedMilliseconds,
    required Map<String, Object?> windowStarts,
  }) {
    if (elapsedMilliseconds < previousElapsedMilliseconds)
      invalid('Logical elapsed samples must be monotonic.');
    final previous = evaluate(
      definition: definition,
      occurrence: occurrence,
      elapsedMilliseconds: previousElapsedMilliseconds,
      windowStarts: windowStarts,
    );
    final current = evaluate(
      definition: definition,
      occurrence: occurrence,
      elapsedMilliseconds: elapsedMilliseconds,
      windowStarts: windowStarts,
    );
    final earliest = current['earliestDeadlineMilliseconds'] as int?;
    final alreadyExpired = previous['expired'] as bool;
    final crossed =
        !alreadyExpired && earliest != null && elapsedMilliseconds >= earliest;
    final windows = (current['windows'] as List<Map<String, Object?>>)
        .where((window) => window['deadlineMilliseconds'] == earliest)
        .toList();
    final scopes = activityGroups(definition.plan, containing: occurrence);
    final scopeByPath = {for (final scope in scopes) scope.path: scope};
    final outermost = crossed ? scopeByPath[windows.first['path']]! : null;
    return {
      'policy': 'bodytmi-window-crossing/1',
      'occurrence': occurrence,
      'occurrenceId': current['occurrenceId'],
      'previousElapsedMilliseconds': previousElapsedMilliseconds,
      'elapsedMilliseconds': elapsedMilliseconds,
      'status': alreadyExpired
          ? 'alreadyExpired'
          : crossed
          ? 'crossed'
          : 'within',
      'boundary': crossed
          ? {
              'elapsedMilliseconds': earliest,
              'paths': [for (final window in windows) window['path']],
              'scopeStart': outermost!.start,
              'scopeEnd': outermost.end,
              'currentOccurrence': occurrence,
            }
          : null,
    };
  }

  Map<String, Object?> evaluate({
    required WorkoutDefinition definition,
    required int occurrence,
    required int elapsedMilliseconds,
    required Map<String, Object?> windowStarts,
  }) {
    if (occurrence < 0 ||
        elapsedMilliseconds < 0 ||
        elapsedMilliseconds > 2000000000) {
      invalid('Invalid occurrence or logical elapsed milliseconds.');
    }
    final occurrences = definition.plan.occurrences().toList();
    if (occurrence >= occurrences.length) invalid('Unknown occurrence index.');
    final scopes =
        activityGroups(
            definition.plan,
            containing: occurrence,
          ).where((group) => group.windowDurationSeconds != null).toList()
          ..sort((a, b) => a.path.length.compareTo(b.path.length));
    final expected = scopes.map((scope) => scope.path).toSet();
    if (windowStarts.length != expected.length ||
        !expected.containsAll(windowStarts.keys)) {
      invalid(
        'windowStarts must contain exactly the windows enclosing the occurrence.',
      );
    }
    final rows = <Map<String, Object?>>[];
    int? priorStart, parentDeadline;
    for (final scope in scopes) {
      final start = windowStarts[scope.path];
      if (start is! int ||
          start < 0 ||
          start > elapsedMilliseconds ||
          (priorStart != null && start < priorStart) ||
          (parentDeadline != null && start >= parentDeadline)) {
        invalid(
          'Window start must be within logical time and its enclosing window.',
        );
      }
      final deadline = start + scope.windowDurationSeconds! * 1000;
      if (deadline > 2000000000)
        invalid('Window deadline exceeds the logical-time limit.');
      final remaining = deadline > elapsedMilliseconds
          ? deadline - elapsedMilliseconds
          : 0;
      rows.add({
        'path': scope.path,
        'startMilliseconds': start,
        'durationMilliseconds': scope.windowDurationSeconds! * 1000,
        'deadlineMilliseconds': deadline,
        'remainingMilliseconds': remaining,
        'overrunMilliseconds': elapsedMilliseconds > deadline
            ? elapsedMilliseconds - deadline
            : 0,
        'expired': remaining == 0,
      });
      priorStart = start;
      parentDeadline = parentDeadline == null || deadline < parentDeadline
          ? deadline
          : parentDeadline;
    }
    final deadlines = [
      for (final row in rows) row['deadlineMilliseconds']! as int,
    ]..sort();
    final earliest = deadlines.firstOrNull;
    return {
      'policy': 'bodytmi-window-deadlines/1',
      'occurrence': occurrence,
      'occurrenceId': occurrences[occurrence].id,
      'elapsedMilliseconds': elapsedMilliseconds,
      'windows': rows,
      'earliestDeadlineMilliseconds': earliest,
      'expired': earliest != null && elapsedMilliseconds >= earliest,
    };
  }
}
