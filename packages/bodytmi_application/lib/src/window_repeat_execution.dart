import 'package:bodytmi_core/bodytmi_core.dart';
import 'window_repeat_cursor.dart';

/// Caller-owned explicit result ledger over a structural repeat cursor.
/// This is not a stored training session or progression input.
final class WindowRepeatExecution {
  const WindowRepeatExecution();
  static const _cursor = WindowRepeatCursor();
  static const _limit = 2000000000;

  Map<String, Object?> start(WindowRepeatSpec loop) => _validate({
    'policy': 'bodytmi-window-repeat-execution/1',
    'version': 1,
    'cursor': _cursor.start(loop),
    'entries': <Object?>[],
  });

  Map<String, Object?> view(Object? input) {
    final state = _validate(input);
    final cursor = jsonObject(state['cursor'], 'cursor');
    final cursorView = _cursor.view(cursor);
    final loop = WindowRepeatSpec.fromJson(cursor['loop']);
    final plan = loop.roundDefinition.plan.occurrences().toList();
    final effortCount = plan.where((item) => item.activity is Effort).length;
    final entries = jsonList(state, 'entries');
    final rounds = <int, List<Map<String, Object?>>>{};
    for (var i = 0; i < entries.length; i++) {
      final entry = jsonObject(entries[i], 'entry');
      if (entry['outcome'] != 'rest') {
        (rounds[i ~/ plan.length] ??= []).add(entry);
      }
    }
    var confirmed = 0, partial = 0;
    final rows = <Map<String, Object?>>[];
    for (final group in rounds.entries) {
      final performed = group.value
          .where((entry) => entry['outcome'] == 'completed')
          .toList();
      final eligible = performed.where((entry) {
        final observations = entry['observations'];
        return observations == null ||
            !SetObservations.fromJson(observations).interrupted;
      }).length;
      final fullyConfirmed = eligible == effortCount;
      final isPartial = !fullyConfirmed && performed.isNotEmpty;
      if (fullyConfirmed) confirmed++;
      if (isPartial) partial++;
      rows.add({
        'round': group.key,
        'status': fullyConfirmed
            ? 'confirmed'
            : isPartial
            ? 'partial'
            : 'unconfirmed',
        'reviewedEfforts': group.value.length,
      });
    }
    final step =
        (cursor['round'] as int) * plan.length + (cursor['occurrence'] as int);
    return {
      'execution': state,
      'current': cursorView['current'],
      'currentReviewed': entries.length > step,
      'confirmedRounds': confirmed,
      'partialRounds': partial,
      'rounds': rows,
    };
  }

  Map<String, Object?> apply(
    Object? input, {
    required int expectedVersion,
    required String action,
    String? ownerId,
    int? ownerElapsedMilliseconds,
    int? adjustmentMilliseconds,
    bool confirm = false,
    Map<String, Object?>? review,
    Map<String, Object?>? correction,
  }) {
    final state = _validate(input);
    if (state['version'] != expectedVersion)
      throw const BodyTmiException(
        'conflict',
        'Window repeat execution version changed.',
      );
    final version = state['version'] as int;
    if (version >= _limit)
      invalid('Execution version exceeds the resource limit.');
    final cursor = jsonObject(state['cursor'], 'cursor');
    final loop = WindowRepeatSpec.fromJson(cursor['loop']);
    final plan = loop.roundDefinition.plan.occurrences().toList();
    final index = cursor['occurrence'] as int;
    final round = cursor['round'] as int;
    final entries = [...jsonList(state, 'entries')];
    var nextCursor = cursor;
    if (action == 'correct') {
      if (ownerId != null ||
          ownerElapsedMilliseconds != null ||
          adjustmentMilliseconds != null ||
          confirm ||
          review != null ||
          correction == null)
        invalid('Correction takes only an occurrence and replacement values.');
      if (cursor['status'] == 'running')
        invalid('Pause or recover the repeat clock before correcting results.');
      checkKeys(correction, {'occurrenceId', 'actuals', 'observations'});
      final occurrenceId = requiredString(correction, 'occurrenceId');
      if (!correction.containsKey('actuals') &&
          !correction.containsKey('observations'))
        invalid('Correction requires actuals or observations.');
      final entryIndex = entries.indexWhere(
        (entry) => jsonObject(entry, 'entry')['id'] == occurrenceId,
      );
      if (entryIndex < 0) invalid('No reviewed occurrence has that identity.');
      final existing = jsonObject(entries[entryIndex], 'entry');
      if (existing['outcome'] != 'completed')
        invalid('Only completed effort results can be corrected.');
      entries[entryIndex] = _reviewEntry(
        loop,
        plan[entryIndex % plan.length],
        entryIndex ~/ plan.length,
        {
          'outcome': 'completed',
          'actuals': correction.containsKey('actuals')
              ? jsonObject(correction['actuals'], 'actuals')
              : existing['actuals'],
          if (correction.containsKey('observations')) ...{
            if (correction['observations'] != null)
              'observations': correction['observations'],
          } else if (existing.containsKey('observations'))
            'observations': existing['observations'],
        },
        confirm: false,
      );
    } else if (action == 'review') {
      if (adjustmentMilliseconds != null ||
          review == null ||
          correction != null)
        invalid(
          'Review takes an explicit result and an optional running clock sample.',
        );
      final status = cursor['status'];
      if (status != 'paused' && status != 'running' && status != 'boundary')
        invalid('Review requires an active cursor or pending boundary.');
      if (status != 'running' &&
          (ownerId != null || ownerElapsedMilliseconds != null))
        invalid('Only a running review takes an owner sample.');
      final step = round * plan.length + index;
      if (entries.length != step)
        invalid('The current occurrence is already reviewed.');
      final item = plan[index];
      if (status == 'boundary' && item.activity is Rest)
        invalid(
          'At a boundary, finish a rest without recording an elapsed result.',
        );
      final result = _reviewEntry(loop, item, round, review, confirm: confirm);
      if (status == 'paused' || status == 'running') {
        nextCursor = _cursor.apply(
          cursor,
          expectedVersion: cursor['version'] as int,
          action: 'acknowledge',
          ownerId: ownerId,
          ownerElapsedMilliseconds: ownerElapsedMilliseconds,
        );
      }
      if (!(nextCursor['status'] == 'boundary' && item.activity is Rest))
        entries.add(result);
    } else {
      if (review != null || correction != null || action == 'acknowledge')
        invalid('Use explicit review to advance the result ledger.');
      if (action == 'finish' &&
          cursor['status'] == 'boundary' &&
          plan[index].activity is Effort &&
          entries.length == round * plan.length + index)
        invalid(
          'Review or explicitly skip the boundary effort before finishing.',
        );
      nextCursor = _cursor.apply(
        cursor,
        expectedVersion: cursor['version'] as int,
        action: action,
        ownerId: ownerId,
        ownerElapsedMilliseconds: ownerElapsedMilliseconds,
        adjustmentMilliseconds: adjustmentMilliseconds,
        confirm: confirm,
      );
    }
    return _validate({
      'policy': 'bodytmi-window-repeat-execution/1',
      'version': version + 1,
      'cursor': nextCursor,
      'entries': entries,
    });
  }

  Map<String, Object?> _reviewEntry(
    WindowRepeatSpec loop,
    ActivityOccurrence item,
    int round,
    Map<String, Object?> review, {
    required bool confirm,
  }) {
    checkKeys(review, {
      'outcome',
      'actuals',
      'acceptSuggested',
      'observations',
    });
    final outcome = requiredString(review, 'outcome');
    final id = '${loop.id}[$round]/${item.id}';
    if (item.activity is Rest) {
      if (outcome != 'rest' || !confirm || review.length != 1)
        invalid('A rest requires explicit confirmation and no actuals.');
      return {'id': id, 'outcome': 'rest'};
    }
    if (outcome == 'skipped') {
      if (!confirm || review.length != 1)
        invalid('Skipping requires confirmation and no actuals.');
      return {'id': id, 'outcome': 'skipped'};
    }
    if (outcome != 'completed' || confirm)
      invalid('Effort review must complete or confirm-skip.');
    final accept = review['acceptSuggested'] ?? false;
    if (accept is! bool) invalid('acceptSuggested must be a boolean.');
    final effort = item.activity as Effort;
    final slot = loop.roundDefinition.slot(effort.slotId);
    final set =
        TrainingSet(
          id: id,
          slotId: slot.id,
          role: effort.role,
          ordinal: 0,
          suggested: effort.resolveTargets(slot.targets),
          maxEffortMetrics: effort.maxEffortMetrics,
          criteria: effort.criteria,
        ).complete(
          metricsFromJson(review['actuals'] ?? <String, Object?>{}),
          acceptSuggested: accept,
        );
    final observations = review.containsKey('observations')
        ? SetObservations.fromJson(review['observations'])
        : null;
    if (observations?.isEmpty == true)
      invalid('Provide nonempty observations or omit them.');
    if (observations != null) set.annotate(observations);
    return {
      'id': id,
      'outcome': 'completed',
      'actuals': metricsToJson(set.actuals),
      if (observations != null) 'observations': observations.toJson(),
    };
  }

  Map<String, Object?> _validate(Object? input) {
    final state = jsonObject(input, 'window repeat execution');
    checkKeys(state, {'policy', 'version', 'cursor', 'entries'});
    if (state['policy'] != 'bodytmi-window-repeat-execution/1')
      invalid('Unknown window repeat execution policy.');
    final version = state['version'];
    if (version is! int || version < 1 || version > _limit)
      invalid('Invalid execution version.');
    final cursor = jsonObject(
      _cursor.view(state['cursor'])['cursor'],
      'cursor',
    );
    if (version < (cursor['version'] as int))
      invalid('Execution version predates its cursor.');
    final loop = WindowRepeatSpec.fromJson(cursor['loop']);
    if (loop.roundDefinition.plan.nodes.any((node) => node is TimeWindow))
      invalid('Nested time windows require their own clock integration.');
    if (loop.roundDefinition.slots.any(
      (slot) => slot.bodyMass != null || slot.prefillMetrics.isNotEmpty,
    ))
      invalid(
        'Caller-owned repeat results do not resolve body mass or history prefill.',
      );
    final plan = loop.roundDefinition.plan.occurrences().toList();
    final raw = jsonList(state, 'entries');
    final step =
        (cursor['round'] as int) * plan.length + (cursor['occurrence'] as int);
    final boundary =
        cursor['status'] == 'boundary' ||
        (cursor['status'] == 'finished' &&
            cursor['terminalReason'] == 'windowExpired');
    final boundaryEffort =
        boundary && plan[cursor['occurrence'] as int].activity is Effort;
    if (raw.length > 10000 ||
        raw.length < step ||
        raw.length > step + (boundaryEffort ? 1 : 0) ||
        (cursor['status'] == 'finished' &&
            boundaryEffort &&
            raw.length != step + 1))
      invalid('Result ledger does not match the structural cursor.');
    final entries = <Map<String, Object?>>[];
    for (var i = 0; i < raw.length; i++) {
      final entry = jsonObject(raw[i], 'entry');
      checkKeys(entry, {'id', 'outcome', 'actuals', 'observations'});
      final item = plan[i % plan.length];
      final round = i ~/ plan.length;
      final id = '${loop.id}[$round]/${item.id}';
      if (entry['id'] != id)
        invalid('Result ledger occurrence identity mismatch.');
      final outcome = requiredString(entry, 'outcome');
      final normalized = _reviewEntry(loop, item, round, {
        for (final e in entry.entries)
          if (e.key != 'id') e.key: e.value,
      }, confirm: outcome != 'completed');
      entries.add(normalized);
    }
    return {
      'policy': 'bodytmi-window-repeat-execution/1',
      'version': version,
      'cursor': cursor,
      'entries': entries,
    };
  }
}
