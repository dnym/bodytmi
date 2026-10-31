import 'errors.dart';
import 'instant.dart';

sealed class ProgramNode {
  const ProgramNode(this.id, this.label);
  final String id;
  final String? label;
  static ProgramNode fromJson(Object? input, [int depth = 0]) {
    if (depth > 64) invalid('Program nesting exceeds 64 levels.');
    final j = jsonObject(input, 'program node');
    final id = identifier(j, 'id');
    final label = j['label'];
    if (label != null && label is! String)
      invalid('Program label must be a string.');
    switch (j['type']) {
      case 'day':
        checkKeys(j, {'id', 'type', 'label', 'templateId', 'revision'});
        return ProgramDay(
          id,
          label as String?,
          identifier(j, 'templateId'),
          positiveProgramInt(j, 'revision'),
        );
      case 'group':
        checkKeys(j, {'id', 'type', 'label', 'children'});
        final children = jsonList(j, 'children');
        if (children.isEmpty) invalid('Program group cannot be empty.');
        return ProgramGroup(id, label as String?, [
          for (final c in children) fromJson(c, depth + 1),
        ]);
      case 'repeat':
        checkKeys(j, {'id', 'type', 'label', 'count', 'child'});
        final count = positiveProgramInt(j, 'count');
        if (count > 10000) invalid('Program repeat exceeds 10000.');
        return ProgramRepeat(
          id,
          label as String?,
          count,
          fromJson(j['child'], depth + 1),
        );
      default:
        invalid('Unknown program node type.');
    }
  }

  Map<String, Object?> toJson();
  Map<String, Object?> get header => {
    'id': id,
    if (label != null) 'label': label,
  };
  Iterable<ProgramNode> get children => const [];
  Iterable<ProgramNode> get nodes sync* {
    yield this;
    for (final c in children) yield* c.nodes;
  }

  Iterable<ProgramDayOccurrence> occurrences([String prefix = '']) sync* {
    final path = prefix.isEmpty ? id : '$prefix/$id';
    switch (this) {
      case ProgramDay():
        yield ProgramDayOccurrence(path, this as ProgramDay);
      case ProgramGroup(:final items):
        for (final c in items) yield* c.occurrences(path);
      case ProgramRepeat(:final count, :final child):
        for (var i = 0; i < count; i++) yield* child.occurrences('$path[$i]');
    }
  }
}

final class ProgramDay extends ProgramNode {
  const ProgramDay(super.id, super.label, this.templateId, this.revision);
  final String templateId;
  final int revision;
  @override
  Map<String, Object?> toJson() => {
    ...header,
    'type': 'day',
    'templateId': templateId,
    'revision': revision,
  };
}

final class ProgramGroup extends ProgramNode {
  ProgramGroup(super.id, super.label, List<ProgramNode> items)
    : items = List.unmodifiable(items);
  final List<ProgramNode> items;
  @override
  Iterable<ProgramNode> get children => items;
  @override
  Map<String, Object?> toJson() => {
    ...header,
    'type': 'group',
    'children': [for (final c in items) c.toJson()],
  };
}

final class ProgramRepeat extends ProgramNode {
  const ProgramRepeat(super.id, super.label, this.count, this.child);
  final int count;
  final ProgramNode child;
  @override
  Iterable<ProgramNode> get children => [child];
  @override
  Map<String, Object?> toJson() => {
    ...header,
    'type': 'repeat',
    'count': count,
    'child': child.toJson(),
  };
}

final class ProgramDayOccurrence {
  const ProgramDayOccurrence(this.path, this.day);
  final String path;
  final ProgramDay day;
  Map<String, Object?> toJson() => {'path': path, 'day': day.toJson()};
}

final class ProgramDefinition {
  ProgramDefinition._(this.id, this.name, this.plan);
  factory ProgramDefinition.fromJson(Object? input) {
    final j = jsonObject(input, 'program definition');
    checkKeys(j, {'id', 'name', 'plan'});
    final plan = ProgramNode.fromJson(j['plan']);
    final ids = <String>{};
    for (final node in plan.nodes)
      if (!ids.add(node.id)) invalid('Duplicate program node identity.');
    var count = 0;
    for (final _ in plan.occurrences())
      if (++count > 10000) invalid('Program cycle exceeds 10000 days.');
    return ProgramDefinition._(
      identifier(j, 'id'),
      requiredString(j, 'name'),
      plan,
    );
  }
  final String id, name;
  final ProgramNode plan;
  late final int dayCount = plan.occurrences().length;
  ProgramDayOccurrence dayAt(int ordinal) =>
      plan.occurrences().elementAt(ordinal % dayCount);
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'plan': plan.toJson(),
  };
}

final class ProgramRevision {
  ProgramRevision._(this.number, this.definition);
  factory ProgramRevision.publish(
    ProgramDefinition definition, {
    ProgramRevision? previous,
  }) {
    if (previous != null && previous.definition.id != definition.id)
      invalid('Program revision must retain identity.');
    return ProgramRevision._((previous?.number ?? 0) + 1, definition);
  }
  factory ProgramRevision.fromJson(Object? input) {
    final j = jsonObject(input, 'program revision');
    checkKeys(j, {'schemaVersion', 'revision', 'definition'});
    if (j['schemaVersion'] != 1)
      invalid('Unsupported program revision version.');
    return ProgramRevision._(
      positiveProgramInt(j, 'revision'),
      ProgramDefinition.fromJson(j['definition']),
    );
  }
  final int number;
  final ProgramDefinition definition;
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'revision': number,
    'definition': definition.toJson(),
  };
}

final class ProgramRun {
  ProgramRun({
    required this.id,
    required this.program,
    required this.startedAt,
    this.loop = true,
    this.cursor = 0,
    this.contentVersion = 1,
    this.status = 'active',
  }) {
    identifier({'id': id}, 'id');
    if (cursor < 0 ||
        contentVersion <= cursor ||
        !{'active', 'paused', 'completed'}.contains(status) ||
        (!loop && cursor > program.definition.dayCount) ||
        ((status == 'completed') !=
            (!loop && cursor == program.definition.dayCount)))
      invalid('Invalid program run state.');
  }
  factory ProgramRun.fromJson(Object? input) {
    final j = jsonObject(input, 'program run');
    checkKeys(j, {
      'id',
      'program',
      'startedAt',
      'loop',
      'cursor',
      'contentVersion',
      'status',
    });
    final loop = j['loop'];
    if (loop is! bool) invalid('Run loop must be boolean.');
    return ProgramRun(
      id: identifier(j, 'id'),
      program: ProgramRevision.fromJson(j['program']),
      startedAt: parseInstant(j['startedAt'], 'startedAt'),
      loop: loop,
      cursor: positiveProgramInt(j, 'cursor', min: 0),
      contentVersion: positiveProgramInt(j, 'contentVersion'),
      status: requiredString(j, 'status'),
    );
  }
  final String id, status;
  final ProgramRevision program;
  final DateTime startedAt;
  final bool loop;
  final int cursor, contentVersion;
  ProgramDayOccurrence? get current =>
      status == 'completed' ? null : program.definition.dayAt(cursor);
  ProgramRun changed({bool advance = false, String? status}) {
    final next = cursor + (advance ? 1 : 0);
    return ProgramRun(
      id: id,
      program: program,
      startedAt: startedAt,
      loop: loop,
      cursor: next,
      contentVersion: contentVersion + 1,
      status: !loop && next == program.definition.dayCount
          ? 'completed'
          : status ?? this.status,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'program': program.toJson(),
    'startedAt': startedAt.toUtc().toIso8601String(),
    'loop': loop,
    'cursor': cursor,
    'contentVersion': contentVersion,
    'status': status,
  };
}

final class SessionProgramBinding {
  const SessionProgramBinding({
    required this.sessionId,
    required this.runId,
    required this.ordinal,
    required this.path,
  });
  factory SessionProgramBinding.fromJson(Object? input) {
    final j = jsonObject(input, 'session program binding');
    checkKeys(j, {'sessionId', 'runId', 'ordinal', 'path'});
    return SessionProgramBinding(
      sessionId: identifier(j, 'sessionId'),
      runId: identifier(j, 'runId'),
      ordinal: positiveProgramInt(j, 'ordinal', min: 0),
      path: requiredString(j, 'path'),
    );
  }
  final String sessionId, runId, path;
  final int ordinal;
  Map<String, Object?> toJson() => {
    'sessionId': sessionId,
    'runId': runId,
    'ordinal': ordinal,
    'path': path,
  };
}

final class ProgramReceipt {
  ProgramReceipt({
    required this.runId,
    required this.ordinal,
    required this.path,
    required this.occurredAt,
    this.sessionId,
    this.requestId,
  }) {
    identifier({'id': runId}, 'id');
    if (ordinal < 0 || (sessionId == null) == (requestId == null))
      invalid('Program receipt needs completion or explicit skip identity.');
    if (sessionId != null) identifier({'id': sessionId}, 'id');
    if (requestId != null) identifier({'id': requestId}, 'id');
    requiredString({'path': path}, 'path');
  }
  factory ProgramReceipt.fromJson(Object? input) {
    final j = jsonObject(input, 'program receipt');
    checkKeys(j, {
      'runId',
      'ordinal',
      'path',
      'occurredAt',
      'sessionId',
      'requestId',
    });
    return ProgramReceipt(
      runId: identifier(j, 'runId'),
      ordinal: positiveProgramInt(j, 'ordinal', min: 0),
      path: requiredString(j, 'path'),
      occurredAt: parseInstant(j['occurredAt'], 'occurredAt'),
      sessionId: j['sessionId'] == null ? null : identifier(j, 'sessionId'),
      requestId: j['requestId'] == null ? null : identifier(j, 'requestId'),
    );
  }
  final String runId, path;
  final String? sessionId, requestId;
  final int ordinal;
  final DateTime occurredAt;
  String get operationKey =>
      sessionId == null ? 'skip/$requestId' : 'finish/$sessionId';
  Map<String, Object?> toJson() => {
    'runId': runId,
    'ordinal': ordinal,
    'path': path,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    'sessionId': sessionId,
    'requestId': requestId,
  };
}

int positiveProgramInt(Map<String, Object?> j, String key, {int min = 1}) {
  final v = j[key];
  if (v is! int || v < min) invalid('$key must be an integer >= $min.');
  return v;
}
