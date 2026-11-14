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
      receipts.add(_freeze(r) as Map<String, Object?>);
    }
    return WorkoutExecution._(
      id,
      identifier(j, 'sessionId'),
      parseInstant(j['createdAt'], 'createdAt'),
      count,
      List.unmodifiable(receipts),
    );
  }
  final String id, sessionId;
  final DateTime createdAt;
  final int occurrenceCount;
  final List<Map<String, Object?>> receipts;
  int get cursor => receipts.length;
  int get version => cursor + 1;
  bool get complete => cursor == occurrenceCount;
  String clockId(String kind) => 'execution-$id-$kind-$cursor';
  WorkoutExecution append(Map<String, Object?> receipt) =>
      WorkoutExecution.fromJson({
        ...toJson(),
        'receipts': [...receipts, receipt],
      });
  Map<String, Object?> toJson() => {
    'id': id,
    'sessionId': sessionId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'occurrenceCount': occurrenceCount,
    'receipts': receipts,
  };
}

Object? _freeze(Object? input) => switch (input) {
  Map<String, Object?>() => Map<String, Object?>.unmodifiable({
    for (final k in (input.keys.toList()..sort())) k: _freeze(input[k]),
  }),
  List<Object?>() => List<Object?>.unmodifiable(input.map(_freeze)),
  _ => input,
};
