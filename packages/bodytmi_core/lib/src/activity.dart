import 'categorical.dart';
import 'errors.dart';
import 'quantity.dart';
import 'objective.dart';

/// Explicit effort roles. Stored progression defaults to `work` and can select another role.
const effortRoles = {'work', 'warmup', 'backoff', 'drop'};

/// Authored unilateral sides. An effort without one is not side-specific.
const effortSides = {'left', 'right'};

Set<String> maxEffortObjectivesFromJson(Object? input) {
  final json = jsonObject(input, 'objectives');
  if (json.isEmpty || json.length > 100)
    invalid('Objectives need 1 to 100 metrics.');
  final metrics = <String>{};
  for (final entry in json.entries) {
    identifier({'metric': entry.key}, 'metric');
    final objective = jsonObject(entry.value, 'objective');
    checkKeys(objective, {'mode', 'unit'});
    if (objective['mode'] != 'maxEffort' || objective['unit'] != 'rep')
      invalid('This objective requires mode maxEffort and unit rep.');
    metrics.add(entry.key);
  }
  return Set.unmodifiable(metrics);
}

Map<String, Object?> maxEffortObjectivesToJson(Set<String> metrics) => {
  for (final key in (metrics.toList()..sort()))
    key: {'mode': 'maxEffort', 'unit': 'rep'},
};

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
        checkKeys(json, {
          'id',
          'type',
          'slot',
          'role',
          'targets',
          'objectives',
          'side',
          'settings',
        });
        if (json.containsKey('settings')) {
          final settings = categoricalSettingsFromJson(
            json['settings'],
            'Effort settings',
          );
          final base = fromJson({...json}..remove('settings'), depth);
          return (base as Effort).withSettings(settings);
        }
        final role = json['role'] ?? 'work';
        if (!effortRoles.contains(role)) invalid('Unknown effort role.');
        final side = json['side'];
        if (side != null && !effortSides.contains(side))
          invalid('Effort side must be left or right.');
        if (json.containsKey('objectives')) {
          if (json.containsKey('targets') &&
              metricsFromJson(json['targets']).isEmpty)
            invalid('Effort target overrides cannot be empty.');
          final objectives = numericObjectivesFromJson(json['objectives']);
          return Effort.withCriteria(
            id,
            identifier(json, 'slot'),
            role as String,
            objectives,
            targets: json.containsKey('targets')
                ? metricsFromJson(json['targets'])
                : const {},
            side: side as String?,
          );
        }
        return json.containsKey('targets')
            ? Effort.withTargets(
                id,
                identifier(json, 'slot'),
                role as String,
                metricsFromJson(json['targets']),
                side as String?,
              )
            : Effort(
                id,
                identifier(json, 'slot'),
                role as String,
                side as String?,
              );
      case 'rest':
        checkKeys(json, {'id', 'type', 'durationSeconds', 'manual'});
        if (json.containsKey('manual')) {
          if (json['manual'] != true || json.containsKey('durationSeconds')) {
            invalid('Manual rest requires manual:true and no duration.');
          }
          return Rest.manual(id);
        }
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
      case 'amrap':
        checkKeys(json, {'id', 'type', 'amrapId'});
        return AmrapPlacement(id, identifier(json, 'amrapId'));
      case 'variant':
        checkKeys(json, {'id', 'type', 'slot', 'lever', 'branches'});
        final branches = jsonObject(json['branches'], 'variant branches');
        if (branches.length < 2 || branches.length > 64)
          invalid('Variant $id needs 2–64 branches.');
        return Variant(
          id,
          identifier(json, 'slot'),
          identifier(json, 'lever'),
          {
            for (final key in (branches.keys.toList()..sort()))
              identifier({'value': key}, 'value'): fromJson(
                branches[key],
                depth + 1,
              ),
          },
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
      case Effort() || Rest() || AmrapPlacement():
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
      case Variant():
        throw unresolvedVariant();
    }
  }

  /// Every occurrence any variant resolution can produce, with the same paths
  /// a resolved plan yields (a variant contributes no path segment).
  Iterable<ActivityOccurrence> structuralOccurrences() =>
      imposedOccurrences(this).map((e) => e.$1);
}

/// Structural occurrences with the slot settings imposed by enclosing
/// variant branches (slot → lever → value).
Iterable<(ActivityOccurrence, Map<String, Map<String, String>>)>
imposedOccurrences(
  Activity node, [
  String prefix = '',
  Map<String, Map<String, String>> imposed = const {},
]) sync* {
  if (node case Variant(:final slotId, :final lever, :final branches)) {
    for (final e in branches.entries)
      yield* imposedOccurrences(e.value, prefix, {
        ...imposed,
        slotId: {...?imposed[slotId], lever: e.key},
      });
    return;
  }
  final path = prefix.isEmpty ? node.id : '$prefix/${node.id}';
  switch (node) {
    case Effort() || Rest() || AmrapPlacement():
      yield (ActivityOccurrence(path, node), imposed);
    case Sequence(:final items):
      for (final child in items)
        yield* imposedOccurrences(child, path, imposed);
    case Repeat(:final count, :final child, :final restBetweenSeconds):
      for (var i = 0; i < count; i++) {
        yield* imposedOccurrences(child, '$path[$i]', imposed);
        if (i + 1 < count && restBetweenSeconds > 0)
          yield (
            ActivityOccurrence(
              '$path[$i]/between',
              Rest('between', restBetweenSeconds),
            ),
            imposed,
          );
      }
    case TimeWindow(:final child):
      yield* imposedOccurrences(child, path, imposed);
    case Variant():
      break;
  }
}

BodyTmiException unresolvedVariant() => BodyTmiException(
  'validation',
  'Resolve workout variants before expanding plan occurrences.',
);

/// An authored structural choice selected by one categorical lever of a slot,
/// such as a set scheme (5x3, 6x2, 10x1). Each branch is a complete activity
/// subtree; a session freezes one selection and expands only that branch.
/// Branch values have no implied difficulty order.
final class Variant extends Activity {
  Variant(super.id, this.slotId, this.lever, Map<String, Activity> branches)
    : branches = Map.unmodifiable(branches);
  final String slotId;
  final String lever;
  final Map<String, Activity> branches;
  @override
  Iterable<Activity> get children => branches.values;
  @override
  Map<String, Object?> toJson() => {
    'type': 'variant',
    'id': id,
    'slot': slotId,
    'lever': lever,
    'branches': {for (final e in branches.entries) e.key: e.value.toJson()},
  };
}

/// Replaces every reached variant with its selected branch, baking the branch
/// value into that slot's efforts as an authored categorical setting.
/// [reached] collects the selected variant IDs.
Activity resolveVariantActivity(
  Activity node,
  Map<String, String> selections,
  Set<String> reached, [
  Map<String, Map<String, String>> imposed = const {},
]) {
  Activity walk(Activity n) =>
      resolveVariantActivity(n, selections, reached, imposed);
  switch (node) {
    case Variant(:final slotId, :final lever, :final branches):
      final value = selections[node.id];
      if (value == null)
        invalid('Variant ${node.id} needs an explicit selection.');
      final branch = branches[value];
      if (branch == null) invalid('Variant ${node.id} has no branch $value.');
      reached.add(node.id);
      return resolveVariantActivity(branch, selections, reached, {
        ...imposed,
        slotId: {...?imposed[slotId], lever: value},
      });
    case Effort():
      final extra = imposed[node.slotId];
      if (extra == null) return node;
      return node.withSettings({...node.settings, ...extra});
    case Rest() || AmrapPlacement():
      return node;
    case Sequence(:final items):
      return Sequence(node.id, [for (final c in items) walk(c)]);
    case Repeat(:final count, :final child, :final restBetweenSeconds):
      return Repeat(node.id, count, walk(child), restBetweenSeconds);
    case TimeWindow(:final durationSeconds, :final child):
      return TimeWindow(node.id, durationSeconds, walk(child));
  }
}

final class Effort extends Activity {
  const Effort(super.id, this.slotId, [this.role = 'work', this.side])
    : targets = const {},
      maxEffortMetrics = const {},
      criteria = const {},
      settings = const {};
  const Effort._all(
    super.id,
    this.slotId,
    this.role,
    this.side,
    this.targets,
    this.maxEffortMetrics,
    this.criteria,
    this.settings,
  );

  /// The same effort with authored categorical settings overriding its
  /// slot's lever defaults.
  Effort withSettings(Map<String, String> settings) => Effort._all(
    id,
    slotId,
    role,
    side,
    targets,
    maxEffortMetrics,
    criteria,
    sortedSettings(settings),
  );

  /// Authored categorical settings (lever → value) over slot defaults.
  final Map<String, String> settings;
  Effort.withTargets(
    super.id,
    this.slotId,
    this.role,
    Metrics targets, [
    this.side,
  ]) : targets = Map.unmodifiable(targets),
       maxEffortMetrics = const {},
       criteria = const {},
       settings = const {} {
    if (targets.isEmpty) invalid('Effort target overrides cannot be empty.');
  }
  Effort.withObjectives(
    super.id,
    this.slotId,
    this.role,
    Set<String> metrics, {
    Metrics targets = const {},
    this.side,
  }) : targets = Map.unmodifiable(targets),
       maxEffortMetrics = Set.unmodifiable(metrics),
       criteria = const {},
       settings = const {} {
    if (metrics.isEmpty || metrics.length > 100)
      invalid('Objectives need 1 to 100 metrics.');
    for (final key in metrics) identifier({'metric': key}, 'metric');
    if (targets.keys.any(metrics.contains))
      invalid(
        'A max-effort metric cannot also have an effort target override.',
      );
  }
  Effort.withCriteria(
    super.id,
    this.slotId,
    this.role,
    Map<String, NumericObjective> objectives, {
    Metrics targets = const {},
    this.side,
  }) : targets = Map.unmodifiable(targets),
       maxEffortMetrics = Set.unmodifiable(
         objectives.entries
             .where((e) => e.value.mode == 'maxEffort')
             .map((e) => e.key),
       ),
       criteria = Map.unmodifiable(
         Map.fromEntries(
           objectives.entries.where((e) => e.value.mode != 'maxEffort'),
         ),
       ),
       settings = const {} {
    if (objectives.isEmpty || objectives.length > 100)
      invalid('Objectives need 1 to 100 metrics.');
    for (final key in objectives.keys) identifier({'metric': key}, 'metric');
    if (targets.keys.any(maxEffortMetrics.contains))
      invalid(
        'A max-effort metric cannot also have an effort target override.',
      );
    if (targets.keys.any((key) => criteria[key]?.mode == 'observe'))
      invalid(
        'An observation metric cannot also have an effort target override.',
      );
  }
  final Metrics targets;
  final Set<String> maxEffortMetrics;
  final Map<String, NumericObjective> criteria;
  Map<String, Object?> get objectivesJson => {
    ...maxEffortObjectivesToJson(maxEffortMetrics),
    ...numericObjectivesToJson(criteria),
  };

  /// Authored overrides retain metric ownership and the slot's dimensions.
  Metrics resolveTargets(Metrics defaults) {
    for (final entry in targets.entries) {
      if (defaults[entry.key]?.dimension != entry.value.dimension)
        invalid('Effort overrides must name compatible slot target metrics.');
    }
    for (final entry in criteria.entries) {
      final quantity = targets[entry.key] ?? defaults[entry.key];
      if (quantity != null && quantity.dimension != entry.value.unit.dimension)
        invalid('Objective and target dimensions must match.');
      if (entry.value.mode == 'observe' && targets.containsKey(entry.key))
        invalid(
          'An observation metric cannot also have an effort target override.',
        );
    }
    for (final key in maxEffortMetrics) {
      if (defaults[key] != null && defaults[key]!.dimension != Dimension.count)
        invalid('Max-effort repetitions require a compatible count metric.');
    }
    return Map.unmodifiable({
      for (final entry in {...defaults, ...targets}.entries)
        if (!maxEffortMetrics.contains(entry.key) &&
            criteria[entry.key]?.mode != 'observe')
          entry.key: entry.value,
    });
  }

  final String slotId;
  final String role;

  /// Optional unilateral side; absent means the effort is not side-specific.
  final String? side;
  @override
  Map<String, Object?> toJson() => {
    'type': 'effort',
    'id': id,
    'slot': slotId,
    'role': role,
    if (side != null) 'side': side,
    if (settings.isNotEmpty) 'settings': settings,
    if (targets.isNotEmpty) 'targets': metricsToJson(targets),
    if (maxEffortMetrics.isNotEmpty || criteria.isNotEmpty)
      'objectives': objectivesJson,
  };
}

final class Rest extends Activity {
  const Rest(super.id, int durationSeconds)
    : durationSeconds = durationSeconds,
      isManual = false;
  const Rest.manual(super.id) : durationSeconds = null, isManual = true;
  final int? durationSeconds;
  final bool isManual;
  @override
  Map<String, Object?> toJson() => {
    'type': 'rest',
    'id': id,
    if (isManual) 'manual': true else 'durationSeconds': durationSeconds,
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

/// Places one authored AMRAP block of the workout in the finite plan. It is a
/// single traversal occurrence with no sets; the block runs in its own repeat
/// checkpoint, and traversal moves past it only once that block is finished.
final class AmrapPlacement extends Activity {
  const AmrapPlacement(super.id, this.amrapId);
  final String amrapId;
  @override
  Map<String, Object?> toJson() => {
    'type': 'amrap',
    'id': id,
    'amrapId': amrapId,
  };
}

/// Traversal kind of one occurrence: effort, rest or amrap.
String occurrenceKind(Activity activity) => switch (activity) {
  Rest() => 'rest',
  AmrapPlacement() => 'amrap',
  _ => 'effort',
};

final class ActivityOccurrence {
  const ActivityOccurrence(this.id, this.activity);
  final String id;
  final Activity activity;
}

/// Structural group bounds in the finite occurrence stream. A repeat iteration
/// contains its child, while between-round rest belongs to the enclosing repeat.
final class ActivityGroupOccurrence {
  const ActivityGroupOccurrence(
    this.path,
    this.start,
    this.end, {
    this.windowDurationSeconds,
  });
  final String path;
  final int start, end;

  /// Authored duration for a window; this is not a running deadline.
  final int? windowDurationSeconds;
  bool contains(int cursor) => start <= cursor && cursor < end;
  Map<String, Object?> toJson() => {
    'path': path,
    'start': start,
    'end': end,
    if (windowDurationSeconds != null)
      'windowDurationSeconds': windowDurationSeconds,
  };
}

List<ActivityGroupOccurrence> activityGroups(
  Activity root, {
  int? containing,
  Set<String>? paths,
}) {
  final groups = <ActivityGroupOccurrence>[];
  var cursor = 0;
  void add(String path, int start, int end, {int? windowDurationSeconds}) {
    if ((containing == null || start <= containing && containing < end) &&
        (paths == null || paths.contains(path))) {
      if (groups.length >= 10000)
        invalid('Activity group selection exceeds 10000 groups.');
      groups.add(
        ActivityGroupOccurrence(
          path,
          start,
          end,
          windowDurationSeconds: windowDurationSeconds,
        ),
      );
    }
  }

  void walk(Activity node, String prefix) {
    final path = prefix.isEmpty ? node.id : '$prefix/${node.id}';
    final start = cursor;
    switch (node) {
      case Effort() || Rest() || AmrapPlacement():
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
      case TimeWindow(:final child, :final durationSeconds):
        walk(child, path);
        add(path, start, cursor, windowDurationSeconds: durationSeconds);
        return;
      case Variant():
        throw unresolvedVariant();
    }
    add(path, start, cursor);
  }

  walk(root, '');
  return List.unmodifiable(groups);
}
