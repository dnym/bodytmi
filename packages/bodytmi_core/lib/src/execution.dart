import 'errors.dart';
import 'instant.dart';

/// A durable finite traversal. Receipts acknowledge occurrences, not quantities.
/// Correcting results cannot grant a new cursor-advancement identity.
final class WorkoutExecution {
  WorkoutExecution._(
    this.id,
    this.sessionId,
    this.createdAt,
    this.occurrenceCount,
    this.receipts,
    this.moves,
    this.order,
  );
  factory WorkoutExecution.create(
    String id,
    String sessionId,
    DateTime at,
    int count,
  ) => WorkoutExecution.fromJson({
    'id': id,
    'sessionId': sessionId,
    'createdAt': at.toUtc().toIso8601String(),
    'occurrenceCount': count,
    'receipts': <Object?>[],
  });
  factory WorkoutExecution.fromJson(Object? input) {
    final j = jsonObject(input, 'workout execution');
    checkKeys(j, {
      'id',
      'sessionId',
      'createdAt',
      'occurrenceCount',
      'receipts',
      'moves',
    });
    final id = identifier(j, 'id');
    if (id.length > 64) invalid('Execution ID exceeds 64 characters.');
    final count = j['occurrenceCount'];
    if (count is! int || count < 1 || count > 10000)
      invalid('Invalid execution size.');
    final rows = jsonList(j, 'receipts');
    if (rows.length > count) invalid('Execution cursor exceeds its plan.');
    final receipts = <Map<String, Object?>>[];
    final requests = <String>{};
    for (var i = 0; i < rows.length; i++) {
      final r = jsonObject(rows[i], 'execution receipt');
      checkKeys(r, {
        'ordinal',
        'path',
        'kind',
        'requestId',
        'request',
        'at',
        'setVersion',
        'resultStatus',
        'timerId',
        'checkpointId',
        'restElapsedMilliseconds',
      });
      if (r['ordinal'] != i ||
          !{'effort', 'rest', 'amrap'}.contains(r['kind']) ||
          !requests.add(identifier(r, 'requestId')))
        invalid(
          'Execution receipts must have distinct requests and contiguous ordinals.',
        );
      requiredString(r, 'path');
      parseInstant(r['at'], 'at');
      jsonObject(r['request'], 'execution request');
      if (r['kind'] == 'effort') {
        final version = r['setVersion'];
        if (version is! int ||
            version < 1 ||
            !{'completed', 'skipped'}.contains(r['resultStatus']))
          invalid('Invalid execution result acknowledgment.');
      } else if (r.containsKey('setVersion') || r.containsKey('resultStatus'))
        invalid('Rest acknowledgment cannot contain effort actuals.');
      if (r['kind'] == 'amrap') {
        if (r.containsKey('timerId'))
          invalid('An AMRAP placement is not timed by the traversal.');
        if (r.containsKey('checkpointId')) identifier(r, 'checkpointId');
      } else if (r.containsKey('checkpointId'))
        invalid('Only AMRAP placements reference a repeat checkpoint.');
      if (r.containsKey('timerId')) identifier(r, 'timerId');
      if (r.containsKey('restElapsedMilliseconds')) {
        final taken = r['restElapsedMilliseconds'];
        if (r['kind'] != 'rest' ||
            !r.containsKey('timerId') ||
            taken is! int ||
            taken < 0 ||
            taken > 86400000)
          invalid('Only a timed rest receipt records the rest taken.');
      }
      receipts.add(_freeze(r) as Map<String, Object?>);
    }
    // Explicit reorders: each move takes not-yet-reached occurrences and
    // puts them next, at the cursor or right after the current rest.
    if (j.containsKey('moves') && jsonList(j, 'moves').isEmpty)
      invalid('Empty execution moves must be omitted.');
    final order = List<int>.generate(count, (i) => i);
    final moves = <Map<String, Object?>>[];
    var lastCursor = 0;
    DateTime? lastAt;
    for (final item in j.containsKey('moves') ? jsonList(j, 'moves') : []) {
      final m = jsonObject(item, 'execution move');
      checkKeys(m, {'cursor', 'position', 'occurrences', 'requestId', 'at'});
      final cursor = m['cursor'], position = m['position'];
      final at = parseInstant(m['at'], 'at');
      final moved = jsonList(m, 'occurrences');
      if (cursor is! int ||
          cursor < lastCursor ||
          cursor > rows.length ||
          (lastAt != null && at.isBefore(lastAt)) ||
          position is! int ||
          (position != cursor && position != cursor + 1) ||
          position >= count ||
          moved.isEmpty ||
          moved.any((i) => i is! int || i < 0 || i >= count) ||
          moved.toSet().length != moved.length ||
          moved.any((i) => order.indexOf(i as int) < position) ||
          !requests.add(identifier(m, 'requestId')))
        invalid('Invalid execution move.');
      order.removeWhere(moved.contains);
      order.insertAll(position, moved.cast<int>());
      lastCursor = cursor;
      lastAt = at;
      moves.add(_freeze(m) as Map<String, Object?>);
    }
    return WorkoutExecution._(
      id,
      identifier(j, 'sessionId'),
      parseInstant(j['createdAt'], 'createdAt'),
      count,
      List.unmodifiable(receipts),
      List.unmodifiable(moves),
      List.unmodifiable(order),
    );
  }
  final String id, sessionId;
  final DateTime createdAt;
  final int occurrenceCount;
  final List<Map<String, Object?>> receipts;

  /// Explicit reorders, oldest first.
  final List<Map<String, Object?>> moves;

  /// Plan index of the occurrence at each traversal position.
  final List<int> order;
  int get cursor => receipts.length;

  /// Advances with every receipt and every move, so a step computed before
  /// a reorder conflicts instead of acting on another occurrence.
  int get version => cursor + 1 + moves.length;

  /// The version a receipt at [ordinal] was made under.
  int versionAt(int ordinal) =>
      ordinal + 1 + moves.where((m) => (m['cursor']! as int) <= ordinal).length;
  bool get complete => cursor == occurrenceCount;
  String clockId(String kind) => 'execution-$id-$kind-$cursor';
  WorkoutExecution append(Map<String, Object?> receipt) =>
      WorkoutExecution.fromJson({
        ...toJson(),
        'receipts': [...receipts, receipt],
      });
  WorkoutExecution withMove(Map<String, Object?> move) =>
      WorkoutExecution.fromJson({
        ...toJson(),
        'moves': [...moves, move],
      });
  Map<String, Object?> toJson() => {
    'id': id,
    'sessionId': sessionId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'occurrenceCount': occurrenceCount,
    'receipts': receipts,
    if (moves.isNotEmpty) 'moves': moves,
  };
}

Object? _freeze(Object? input) => switch (input) {
  Map<String, Object?>() => Map<String, Object?>.unmodifiable({
    for (final k in (input.keys.toList()..sort())) k: _freeze(input[k]),
  }),
  List<Object?>() => List<Object?>.unmodifiable(input.map(_freeze)),
  _ => input,
};
