import 'package:bodytmi_core/bodytmi_core.dart';

/// Calculates scoped boundaries from caller-supplied logical elapsed time.
/// It neither owns a clock nor records an execution or completed effort.
final class WindowDeadlines {
  const WindowDeadlines();

  /// Calculates scope changes at an explicitly selected later occurrence.
  /// It does not decide which occurrences should be traversed or skipped.
  Map<String, Object?> transition({
    required WorkoutDefinition definition,
    required int fromOccurrence,
    required int toOccurrence,
    required int elapsedMilliseconds,
    required Map<String, Object?> windowStarts,
  }) {
    final current = evaluate(
      definition: definition,
      occurrence: fromOccurrence,
      elapsedMilliseconds: elapsedMilliseconds,
      windowStarts: windowStarts,
    );
    final occurrences = definition.plan.occurrences().toList();
    if (toOccurrence <= fromOccurrence || toOccurrence > occurrences.length)
      invalid(
        'The destination must be a later occurrence or the end of the plan.',
      );
    final previous =
        activityGroups(
            definition.plan,
            containing: fromOccurrence,
          ).where((scope) => scope.windowDurationSeconds != null).toList()
          ..sort((a, b) => a.path.length.compareTo(b.path.length));
    final next = toOccurrence == occurrences.length
        ? <ActivityGroupOccurrence>[]
        : (activityGroups(
              definition.plan,
              containing: toOccurrence,
            ).where((scope) => scope.windowDurationSeconds != null).toList()
            ..sort((a, b) => a.path.length.compareTo(b.path.length)));
    final previousPaths = previous.map((scope) => scope.path).toSet();
    final nextPaths = next.map((scope) => scope.path).toSet();
    final activeRows = (current['windows'] as List<Map<String, Object?>>);
    if (activeRows.any(
      (row) => row['expired'] == true && nextPaths.contains(row['path']),
    ))
      invalid('Cannot continue within an expired window.');
    for (final scope in next) {
      if (!previousPaths.contains(scope.path) && scope.start != toOccurrence)
        invalid('Cannot enter a window after its first occurrence.');
    }
    final starts = <String, Object?>{
      for (final scope in next)
        scope.path: previousPaths.contains(scope.path)
            ? windowStarts[scope.path]
            : elapsedMilliseconds,
    };
    if (toOccurrence < occurrences.length) {
      evaluate(
        definition: definition,
        occurrence: toOccurrence,
        elapsedMilliseconds: elapsedMilliseconds,
        windowStarts: starts,
      );
    }
    return {
      'policy': 'bodytmi-window-transition/1',
      'fromOccurrence': fromOccurrence,
      'fromOccurrenceId': current['occurrenceId'],
      'toOccurrence': toOccurrence,
      'toOccurrenceId': toOccurrence == occurrences.length
          ? null
          : occurrences[toOccurrence].id,
      'elapsedMilliseconds': elapsedMilliseconds,
      'exited': [
        for (final scope in previous.reversed)
          if (!nextPaths.contains(scope.path)) scope.path,
      ],
      'entered': [
        for (final scope in next)
          if (!previousPaths.contains(scope.path)) scope.path,
      ],
      'windowStarts': starts,
    };
  }

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
