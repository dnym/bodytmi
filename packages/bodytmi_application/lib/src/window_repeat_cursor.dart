import 'package:bodytmi_core/bodytmi_core.dart';
import 'window_repeat_preview.dart';

/// Caller-owned structural cursor. It records no effort results or session data.
final class WindowRepeatCursor {
  const WindowRepeatCursor();
  static const _limit = 2000000000;

  Map<String, Object?> start(WindowRepeatSpec loop) {
    final page = const WindowRepeatPreview().page(
      loop,
      round: 0,
      elapsedMilliseconds: 0,
      limit: 1,
    );
    final limited = page['status'] == 'resourceLimit';
    return _validate({
      'policy': 'bodytmi-window-repeat-cursor/1',
      'loop': loop.toJson(),
      'version': 1,
      'status': limited ? 'limitReached' : 'paused',
      'round': 0,
      'occurrence': 0,
      'elapsedMilliseconds': 0,
      'ownerId': null,
      'ownerElapsedMilliseconds': 0,
      if (limited) 'terminalReason': 'resourceLimit',
    });
  }

  Map<String, Object?> view(Object? input) {
    final cursor = _validate(input);
    final status = cursor['status'];
    final loop = WindowRepeatSpec.fromJson(cursor['loop']);
    Map<String, Object?>? current;
    if (status == 'paused' || status == 'running' || status == 'boundary') {
      final round = cursor['round'] as int;
      final index = cursor['occurrence'] as int;
      final item = loop.roundDefinition.plan.occurrences().elementAt(index);
      current = {
        'round': round,
        'index': index,
        'id': '${loop.id}[$round]/${item.id}',
        'activity': item.activity.toJson(),
      };
    }
    return {'cursor': cursor, 'current': current};
  }

  Map<String, Object?> apply(
    Object? input, {
    required int expectedVersion,
    required String action,
    String? ownerId,
    int? ownerElapsedMilliseconds,
    int? adjustmentMilliseconds,
    bool confirm = false,
  }) {
    final state = _validate(input);
    if (state['version'] != expectedVersion)
      throw const BodyTmiException(
        'conflict',
        'Window repeat cursor version changed.',
      );
    final version = state['version'] as int;
    if (version >= _limit)
      invalid('Cursor version exceeds the resource limit.');
    final loop = WindowRepeatSpec.fromJson(state['loop']);
    final status = state['status'];
    final elapsed = state['elapsedMilliseconds'] as int;
    final next = <String, Object?>{...state, 'version': version + 1};
    if (action != 'finish' && action != 'stop' && confirm)
      invalid('Only finish or stop accepts confirmation.');
    if (action != 'recover' && adjustmentMilliseconds != null)
      invalid('Only recovery accepts an elapsed adjustment.');
    switch (action) {
      case 'resume':
        if (status != 'paused' ||
            ownerId == null ||
            ownerElapsedMilliseconds != null)
          invalid('Resume requires a paused cursor and an owner.');
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
            ownerElapsedMilliseconds == null)
          invalid(
            'A running cursor requires its owner and a cumulative sample.',
          );
        final prior = state['ownerElapsedMilliseconds'] as int;
        if (ownerElapsedMilliseconds < prior ||
            ownerElapsedMilliseconds > _limit ||
            elapsed + ownerElapsedMilliseconds - prior > _limit)
          invalid(
            'Clock samples must be monotonic and within the logical-time limit.',
          );
        final sample = elapsed + ownerElapsedMilliseconds - prior;
        if (sample >= loop.durationMilliseconds) {
          next.addAll({
            'status': 'boundary',
            'elapsedMilliseconds': loop.durationMilliseconds,
            'ownerId': null,
            'ownerElapsedMilliseconds': 0,
            'terminalReason': 'windowExpired',
            'unappliedMilliseconds': sample - loop.durationMilliseconds,
          });
        } else {
          next.addAll({
            'status': action == 'pause' ? 'paused' : 'running',
            'elapsedMilliseconds': sample,
            'ownerId': action == 'pause' ? null : ownerId,
            'ownerElapsedMilliseconds': action == 'pause'
                ? 0
                : ownerElapsedMilliseconds,
          });
        }
      case 'recover':
        if (status != 'running' ||
            ownerId != null ||
            ownerElapsedMilliseconds != null)
          invalid('Recovery requires an interrupted running cursor.');
        final adjustment = adjustmentMilliseconds ?? 0;
        if (adjustment < 0 ||
            adjustment > _limit ||
            elapsed + adjustment > _limit)
          invalid('Recovery adjustment exceeds the logical-time limit.');
        final sample = elapsed + adjustment;
        next.addAll({
          'status': sample >= loop.durationMilliseconds ? 'boundary' : 'paused',
          'elapsedMilliseconds': sample >= loop.durationMilliseconds
              ? loop.durationMilliseconds
              : sample,
          'ownerId': null,
          'ownerElapsedMilliseconds': 0,
        });
        if (sample >= loop.durationMilliseconds) {
          next['terminalReason'] = 'windowExpired';
          next['unappliedMilliseconds'] = sample - loop.durationMilliseconds;
        }
      case 'acknowledge':
        if (status != 'paused' ||
            ownerId != null ||
            ownerElapsedMilliseconds != null)
          invalid('Acknowledgment requires a paused cursor.');
        final count = loop.roundDefinition.plan.occurrences().length;
        final index = (state['occurrence'] as int) + 1;
        if (index < count) {
          next['occurrence'] = index;
        } else {
          final round = (state['round'] as int) + 1;
          final page = const WindowRepeatPreview().page(
            loop,
            round: round,
            elapsedMilliseconds: elapsed,
            limit: 1,
          );
          next.addAll({'round': round, 'occurrence': 0});
          if (page['status'] == 'resourceLimit') {
            next['status'] = 'limitReached';
            next['terminalReason'] = 'resourceLimit';
          }
        }
      case 'finish':
        if (!confirm ||
            !{'boundary', 'limitReached'}.contains(status) ||
            ownerId != null ||
            ownerElapsedMilliseconds != null)
          invalid(
            'Finish requires confirmation at a boundary or resource limit.',
          );
        next['status'] = 'finished';
      case 'stop':
        if (!confirm ||
            status != 'paused' ||
            ownerId != null ||
            ownerElapsedMilliseconds != null)
          invalid('Stop requires confirmation and a paused cursor.');
        next.addAll({'status': 'finished', 'terminalReason': 'stopped'});
      default:
        invalid('Unknown window repeat cursor action.');
    }
    return _validate(next);
  }

  Map<String, Object?> _validate(Object? input) {
    final state = jsonObject(input, 'window repeat cursor');
    checkKeys(state, {
      'policy',
      'loop',
      'version',
      'status',
      'round',
      'occurrence',
      'elapsedMilliseconds',
      'ownerId',
      'ownerElapsedMilliseconds',
      'terminalReason',
      'unappliedMilliseconds',
    });
    if (state['policy'] != 'bodytmi-window-repeat-cursor/1')
      invalid('Unknown window repeat cursor policy.');
    final loop = WindowRepeatSpec.fromJson(state['loop']);
    final version = state['version'],
        round = state['round'],
        index = state['occurrence'];
    final elapsed = state['elapsedMilliseconds'],
        sample = state['ownerElapsedMilliseconds'];
    final status = state['status'];
    if (version is! int ||
        version < 1 ||
        version > _limit ||
        round is! int ||
        round < 0 ||
        round > 10000 ||
        index is! int ||
        index < 0 ||
        elapsed is! int ||
        elapsed < 0 ||
        elapsed > loop.durationMilliseconds ||
        sample is! int ||
        sample < 0 ||
        sample > elapsed ||
        !{
          'paused',
          'running',
          'boundary',
          'limitReached',
          'finished',
        }.contains(status))
      invalid('Invalid window repeat cursor.');
    if (status == 'running') {
      identifier({'id': state['ownerId']}, 'id');
    } else if (state['ownerId'] != null || sample != 0) {
      invalid('Only a running cursor can have an owner sample.');
    }
    final count = loop.roundDefinition.plan.occurrences().length;
    if (version < 1 + round * count + index)
      invalid('Cursor version predates its structural acknowledgments.');
    final reason = state['terminalReason'];
    final limited =
        round >= loop.maxRounds || (round + 1) * count > loop.maxOccurrences;
    if (status == 'limitReached' ||
        (status == 'finished' && reason == 'resourceLimit')) {
      if (!limited ||
          index != 0 ||
          (round > 0 &&
              (round - 1 >= loop.maxRounds ||
                  round * count > loop.maxOccurrences)) ||
          elapsed >= loop.durationMilliseconds ||
          reason != 'resourceLimit' ||
          state.containsKey('unappliedMilliseconds'))
        invalid('Invalid repeat resource-limit state.');
    } else {
      if (limited || index >= count) invalid('Invalid repeat occurrence.');
      if (status == 'finished' && reason == 'stopped') {
        if (elapsed >= loop.durationMilliseconds ||
            state.containsKey('unappliedMilliseconds'))
          invalid('Invalid stopped cursor state.');
      } else if (status == 'boundary' || status == 'finished') {
        final unapplied = state['unappliedMilliseconds'];
        if (elapsed != loop.durationMilliseconds ||
            reason != 'windowExpired' ||
            unapplied is! int ||
            unapplied < 0 ||
            unapplied > _limit - elapsed)
          invalid('Invalid repeat boundary state.');
      } else if (elapsed >= loop.durationMilliseconds ||
          reason != null ||
          state.containsKey('unappliedMilliseconds')) {
        invalid('Invalid active repeat cursor state.');
      }
    }
    return {...state, 'loop': loop.toJson()};
  }
}
