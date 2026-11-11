import 'dart:math';
import 'package:bodytmi_core/bodytmi_core.dart';

/// Pages one virtual round at a time; it does not execute or record work.
final class WindowRepeatPreview {
  const WindowRepeatPreview();

  Map<String, Object?> page(
    WindowRepeatSpec loop, {
    required int round,
    required int elapsedMilliseconds,
    int offset = 0,
    int limit = 100,
  }) {
    if (round < 0 || round > 10000)
      invalid('round must be between 0 and 10000.');
    if (elapsedMilliseconds < 0 || elapsedMilliseconds > 2000000000)
      invalid('elapsedMilliseconds exceeds the logical-time limit.');
    if (offset < 0 || limit < 1 || limit > 1000)
      invalid(
        'offset must be nonnegative and limit must be between 1 and 1000.',
      );
    final plan = loop.roundDefinition.plan;
    final count = plan.occurrences().length;
    if (offset > count) invalid('offset exceeds the round occurrence count.');
    final status = elapsedMilliseconds >= loop.durationMilliseconds
        ? 'windowExpired'
        : round >= loop.maxRounds || (round + 1) * count > loop.maxOccurrences
        ? 'resourceLimit'
        : 'ready';
    final reason = status != 'resourceLimit'
        ? null
        : round >= loop.maxRounds
        ? 'maxRounds'
        : 'maxOccurrences';
    final end = status == 'ready' ? min(count, offset + limit) : offset;
    final prefix = '${loop.id}[$round]';
    return {
      'policy': 'bodytmi-window-repeat-page/1',
      'loop': loop.toJson(),
      'round': round,
      'elapsedMilliseconds': elapsedMilliseconds,
      'status': status,
      if (reason != null) 'limitReason': reason,
      'occurrenceCount': count,
      'offset': offset,
      'nextOffset': status == 'ready' && end < count ? end : null,
      'occurrences': [
        if (status == 'ready')
          for (final item in plan.occurrences().skip(offset).take(end - offset))
            {'id': '$prefix/${item.id}', 'activity': item.activity.toJson()},
      ],
    };
  }
}
