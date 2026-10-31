import 'errors.dart';

/// A finite activity plan. Window boundaries are retained, not treated as success.
sealed class Activity {
  const Activity(this.id);
  final String id;

  static Activity fromJson(Object? input, [int depth = 0]) {
    if (depth > 64)
      invalid('Activity nesting exceeds the current resource limit (64).');
    final json = jsonObject(input, 'activity');
    final id = identifier(json, 'id');
    switch (requiredString(json, 'type')) {
      case 'effort':
        checkKeys(json, {'id', 'type', 'slot', 'role'});
        final role = json['role'] ?? 'work';
        if (role != 'work' && role != 'warmup') invalid('Unknown effort role.');
        return Effort(id, identifier(json, 'slot'), role as String);
      case 'rest':
        checkKeys(json, {'id', 'type', 'durationSeconds'});
        return Rest(id, _positiveInt(json, 'durationSeconds'));
      case 'sequence':
        checkKeys(json, {'id', 'type', 'children'});
        final children = jsonList(json, 'children');
        if (children.isEmpty) invalid('Sequence must have children.');
        return Sequence(id, [
          for (final child in children) fromJson(child, depth + 1),
        ]);
      case 'repeat':
        checkKeys(json, {'id', 'type', 'count', 'child', 'restBetweenSeconds'});
        final rest = json['restBetweenSeconds'] ?? 0;
        if (rest is! int || rest < 0)
          invalid('Rest between rounds must be nonnegative.');
        return Repeat(
          id,
          _positiveInt(json, 'count'),
          fromJson(json['child'], depth + 1),
          rest,
        );
      case 'window':
        checkKeys(json, {'id', 'type', 'durationSeconds', 'child'});
        return TimeWindow(
          id,
          _positiveInt(json, 'durationSeconds'),
          fromJson(json['child'], depth + 1),
        );
      default:
        invalid('Unsupported activity type: ${json['type']}.');
    }
  }

  static int _positiveInt(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! int || value <= 0 || value > 1000000) {
      invalid('$key must be an integer from 1 through 1000000.');
    }
    return value;
  }

  Map<String, Object?> toJson();
  Iterable<Activity> get children => const [];

  Iterable<Activity> get nodes sync* {
    yield this;
    for (final child in children) {
      yield* child.nodes;
    }
  }

  /// Expands structural occurrences only; does not run timers or confirm efforts.
  Iterable<ActivityOccurrence> occurrences([String prefix = '']) sync* {
    final path = prefix.isEmpty ? id : '$prefix/$id';
    switch (this) {
      case Effort() || Rest():
        yield ActivityOccurrence(path, this);
      case Sequence(:final items):
        for (final child in items) {
          yield* child.occurrences(path);
        }
      case Repeat(:final count, :final child, :final restBetweenSeconds):
        for (var i = 0; i < count; i++) {
          yield* child.occurrences('$path[$i]');
          if (i + 1 < count && restBetweenSeconds > 0) {
            yield ActivityOccurrence(
              '$path[$i]/between',
              Rest('between', restBetweenSeconds),
            );
          }
        }
      case TimeWindow(:final child):
        yield* child.occurrences(path);
    }
  }
}

final class Effort extends Activity {
  const Effort(super.id, this.slotId, [this.role = 'work']);
  final String slotId;
  final String role;
  @override
  Map<String, Object?> toJson() => {
    'type': 'effort',
    'id': id,
    'slot': slotId,
    'role': role,
  };
}

final class Rest extends Activity {
  const Rest(super.id, this.durationSeconds);
  final int durationSeconds;
  @override
  Map<String, Object?> toJson() => {
    'type': 'rest',
    'id': id,
    'durationSeconds': durationSeconds,
  };
}

final class Sequence extends Activity {
  Sequence(super.id, List<Activity> children)
    : items = List.unmodifiable(children);
  final List<Activity> items;
  @override
  Iterable<Activity> get children => items;
  @override
  Map<String, Object?> toJson() => {
    'type': 'sequence',
    'id': id,
    'children': [for (final item in items) item.toJson()],
  };
}

final class Repeat extends Activity {
  const Repeat(super.id, this.count, this.child, [this.restBetweenSeconds = 0]);
  final int count;
  final Activity child;
  final int restBetweenSeconds;
  @override
  Iterable<Activity> get children => [child];
  @override
  Map<String, Object?> toJson() => {
    'type': 'repeat',
    'id': id,
    'count': count,
    'child': child.toJson(),
    'restBetweenSeconds': restBetweenSeconds,
  };
}

final class TimeWindow extends Activity {
  const TimeWindow(super.id, this.durationSeconds, this.child);
  final int durationSeconds;
  final Activity child;
  @override
  Iterable<Activity> get children => [child];
  @override
  Map<String, Object?> toJson() => {
    'type': 'window',
    'id': id,
    'durationSeconds': durationSeconds,
    'child': child.toJson(),
  };
}

final class ActivityOccurrence {
  const ActivityOccurrence(this.id, this.activity);
  final String id;
  final Activity activity;
}

/// Structural group bounds in the finite occurrence stream. A repeat iteration
/// contains its child, while between-round rest belongs to the enclosing repeat.
final class ActivityGroupOccurrence {
  const ActivityGroupOccurrence(this.path, this.start, this.end);
  final String path;
  final int start, end;
  bool contains(int cursor) => start <= cursor && cursor < end;
  Map<String, Object?> toJson() => {'path': path, 'start': start, 'end': end};
}

List<ActivityGroupOccurrence> activityGroups(
  Activity root, {
  int? containing,
  Set<String>? paths,
}) {
  final groups = <ActivityGroupOccurrence>[];
  var cursor = 0;
  void add(String path, int start, int end) {
    if ((containing == null || start <= containing && containing < end) &&
        (paths == null || paths.contains(path)))
      groups.add(ActivityGroupOccurrence(path, start, end));
  }

  void walk(Activity node, String prefix) {
    final path = prefix.isEmpty ? node.id : '$prefix/${node.id}';
    final start = cursor;
    switch (node) {
      case Effort() || Rest():
        if (++cursor > 10000)
          invalid('Activity traversal exceeds 10000 occurrences.');
        return;
      case Sequence(:final items):
        for (final child in items) walk(child, path);
      case Repeat(:final count, :final child, :final restBetweenSeconds):
        for (var i = 0; i < count; i++) {
          final round = cursor;
          walk(child, '$path[$i]');
          add('$path[$i]', round, cursor);
          if (i + 1 < count && restBetweenSeconds > 0 && ++cursor > 10000)
            invalid('Activity traversal exceeds 10000 occurrences.');
        }
      case TimeWindow():
        invalid('Scoped window groups are not implemented yet.');
    }
    add(path, start, cursor);
  }

  walk(root, '');
  return List.unmodifiable(groups);
}
