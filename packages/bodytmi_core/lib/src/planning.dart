import 'dart:math' as math;

import 'diary.dart' show checkDate;
import 'errors.dart';
import 'instant.dart';
import 'nutrient.dart';
import 'sleep.dart' show clockMinutes;

/// One value per local date from a named source (policy
/// bodytmi-daily-metric/1). Sources and fields:
/// * `observation` {measure, attributes?, summary mean|last|sum|min|max|count
///   (default mean), resolved?: true for the measure's resolution policy at
///   the end of the day};
/// * `sleep` {field asleepMinutes|sleepPeriodMinutes|inBedMinutes|quality|
///   awakenings|onsetClock|wakeClock|midpointClock} of the main sleep that
///   ends on the date (clock fields are minutes after local midnight, onset
///   before midnight negative);
/// * `diary` {nutrient, field total (default) | lastIntakeClock}: totals of
///   complete days whose items all declare it; the last intake time of a
///   nutrient (clock minutes, `none` on a complete day without it);
/// * `activity` {category or kind, field minutes|count};
/// * `practice` {practiceId?, field minutes|count} of confirmed sessions;
/// * `training` {field sessions}: finished training sessions started that
///   day;
/// * `budget` {goal energy|protein|carbohydrate|fat|fibre}: eaten minus the
///   plan target on complete plan days.
/// A day without data is unknown, never zero; logging nothing is not a
/// missed day.
final class DailyMetric {
  DailyMetric._(this.json);
  factory DailyMetric.fromJson(Object? input) {
    final j = jsonObject(input, 'metric');
    final source = j['source'];
    void fields(Set<String> keys) => checkKeys(j, {'source', 'label', ...keys});
    String oneOf(String key, Set<String> values, [String? fallback]) {
      final v = j[key] ?? fallback;
      if (v is! String || !values.contains(v))
        invalid('$source $key is one of ${values.join(', ')}.');
      return v;
    }

    switch (source) {
      case 'observation':
        fields({'measure', 'attributes', 'summary', 'resolved'});
        identifier(j, 'measure');
        if (j['attributes'] != null) {
          for (final e in jsonObject(j['attributes'], 'attributes').entries) {
            identifier({'a': e.key}, 'a');
            identifier({'a': e.value}, 'a');
          }
        }
        oneOf('summary', {
          'mean',
          'last',
          'sum',
          'min',
          'max',
          'count',
        }, 'mean');
        if (j['resolved'] != null && j['resolved'] != true)
          invalid('resolved is true when given.');
        if (j['resolved'] == true && j['summary'] != null)
          invalid('A resolved observation metric has no summary.');
      case 'sleep':
        fields({'field'});
        oneOf('field', {
          'asleepMinutes',
          'sleepPeriodMinutes',
          'inBedMinutes',
          'quality',
          'awakenings',
          'onsetClock',
          'wakeClock',
          'midpointClock',
        });
      case 'diary':
        fields({'nutrient', 'field'});
        nutrient(requiredString(j, 'nutrient'));
        oneOf('field', {'total', 'lastIntakeClock'}, 'total');
      case 'activity':
        fields({'category', 'kind', 'field'});
        if ((j['category'] == null) == (j['kind'] == null))
          invalid('An activity metric names a category or a kind.');
        identifier(j, j['category'] != null ? 'category' : 'kind');
        oneOf('field', {'minutes', 'count'});
      case 'practice':
        fields({'practiceId', 'field'});
        if (j['practiceId'] != null) identifier(j, 'practiceId');
        oneOf('field', {'minutes', 'count'});
      case 'training':
        fields({'field'});
        oneOf('field', {'sessions'});
      case 'budget':
        fields({'goal'});
        oneOf('goal', {'energy', 'protein', 'carbohydrate', 'fat', 'fibre'});
      default:
        invalid(
          'A metric source is observation, sleep, diary, activity, practice, '
          'training or budget.',
        );
    }
    final label = j['label'];
    if (label != null &&
        (label is! String || label.isEmpty || label.length > 200))
      invalid('A metric label is text of at most 200 characters.');
    return DailyMetric._(Map.unmodifiable(j));
  }
  final Map<String, Object?> json;
  String get source => json['source']! as String;
  String? get field => json['field'] as String?;
  bool get isClock => field?.endsWith('Clock') ?? false;
  Map<String, Object?> toJson() => json;
}

/// One day of a metric: a value, `unknown` (no data) or `none` (a complete
/// day without the thing, e.g. no caffeine).
typedef DayValue = ({String date, String status, double? value});

/// Descriptive statistics of the known values.
Map<String, Object?> describeValues(List<DayValue> days) {
  final values = [
    for (final d in days)
      if (d.value != null) d.value!,
  ]..sort();
  final known = values.length;
  if (known == 0)
    return {
      'days': days.length,
      'known': 0,
      'none': days.where((d) => d.status == 'none').length,
    };
  final mean = values.reduce((a, b) => a + b) / known;
  final median = known.isOdd
      ? values[known ~/ 2]
      : (values[known ~/ 2 - 1] + values[known ~/ 2]) / 2;
  final sd = known < 2
      ? null
      : math.sqrt(
          values.fold<double>(0, (s, v) => s + (v - mean) * (v - mean)) /
              (known - 1),
        );
  return {
    'days': days.length,
    'known': known,
    'none': days.where((d) => d.status == 'none').length,
    'mean': round3(mean),
    'median': round3(median),
    'sd': ?(sd == null ? null : round3(sd)),
    'min': round3(values.first),
    'max': round3(values.last),
  };
}

double round3(double v) => (v * 1000).roundToDouble() / 1000;

/// A target: at most, at least, or within a range.
final class Target {
  Target._(this.json);
  factory Target.fromJson(Object? input) {
    final j = jsonObject(input, 'target');
    checkKeys(j, {'relation', 'value', 'minimum', 'maximum'});
    final r = j['relation'];
    double num(String k) {
      final v = j[k];
      if (v is! String || double.tryParse(v) == null)
        invalid('target $k is a decimal string.');
      return double.parse(v);
    }

    if (r == 'atMost' || r == 'atLeast') {
      checkKeys(j, {'relation', 'value'});
      num('value');
    } else if (r == 'within') {
      checkKeys(j, {'relation', 'minimum', 'maximum'});
      if (num('minimum') > num('maximum'))
        invalid('target minimum exceeds its maximum.');
    } else {
      invalid('A target relation is atMost, atLeast or within.');
    }
    return Target._(Map.unmodifiable(j));
  }
  final Map<String, Object?> json;
  bool met(double v) => switch (json['relation']) {
    'atMost' => v <= double.parse(json['value']! as String),
    'atLeast' => v >= double.parse(json['value']! as String),
    _ =>
      v >= double.parse(json['minimum']! as String) &&
          v <= double.parse(json['maximum']! as String),
  };
  Map<String, Object?> toJson() => json;
}

String? _text(Map<String, Object?> j, String key, int max) {
  final v = j[key];
  if (v == null) return null;
  if (v is! String || v.trim().isEmpty || v.length > max)
    invalid('$key is nonempty text of at most $max characters.');
  return v;
}

int _version(Map<String, Object?> j) {
  final v = j['version'];
  if (v is! int || v < 1) invalid('version must be positive.');
  return v;
}

/// A goal: a metric aggregated over a period against a target.
final class Goal {
  Goal._(this.json);
  factory Goal.fromJson(Object? input) {
    final j = jsonObject(input, 'goal');
    checkKeys(j, {
      'id',
      'version',
      'name',
      'metric',
      'aggregate',
      'target',
      'from',
      'until',
      'status',
      'notes',
    });
    identifier(j, 'id');
    _version(j);
    if (_text(j, 'name', 200) == null) invalid('A goal has a name.');
    _text(j, 'notes', 4000);
    final metric = DailyMetric.fromJson(j['metric']);
    final aggregate = j['aggregate'] ?? 'mean';
    if (!const {
      'mean',
      'sum',
      'min',
      'max',
      'latest',
      'daysMet',
    }.contains(aggregate))
      invalid('aggregate is mean, sum, min, max, latest or daysMet.');
    if (metric.isClock && aggregate == 'sum')
      invalid('Clock times are not summed.');
    Target.fromJson(j['target']);
    final from = checkDate(j['from'], 'from');
    if (j['until'] != null &&
        checkDate(j['until'], 'until').compareTo(from) <= 0)
      invalid('until is after from.');
    if (!const {'active', 'achieved', 'abandoned'}.contains(j['status']))
      invalid('A goal is active, achieved or abandoned.');
    return Goal._(Map.unmodifiable({...j, 'aggregate': aggregate}));
  }
  final Map<String, Object?> json;
  String get id => json['id']! as String;
  int get version => json['version']! as int;
  DailyMetric get metric => DailyMetric.fromJson(json['metric']);
  Target get target => Target.fromJson(json['target']);
  String get aggregate => json['aggregate']! as String;
  String get from => json['from']! as String;
  String? get until => json['until'] as String?;
  Map<String, Object?> toJson() => json;
}

/// What completes a routine on a day: an activity in a category, a
/// confirmed practice, an observation of a measure, or a manual check.
final class Routine {
  Routine._(this.json);
  factory Routine.fromJson(Object? input) {
    final j = jsonObject(input, 'routine');
    checkKeys(j, {
      'id',
      'version',
      'name',
      'action',
      'schedule',
      'from',
      'until',
      'notes',
    });
    identifier(j, 'id');
    _version(j);
    if (_text(j, 'name', 200) == null) invalid('A routine has a name.');
    _text(j, 'notes', 4000);
    final a = jsonObject(j['action'], 'action');
    switch (a['kind']) {
      case 'activity':
        checkKeys(a, {'kind', 'category'});
        identifier(a, 'category');
      case 'practice':
        checkKeys(a, {'kind', 'practiceId'});
        identifier(a, 'practiceId');
      case 'observation':
        checkKeys(a, {'kind', 'measure'});
        identifier(a, 'measure');
      case 'check':
        checkKeys(a, {'kind'});
      default:
        invalid(
          'A routine action is activity, practice, observation or check.',
        );
    }
    final s = jsonObject(j['schedule'], 'schedule');
    checkKeys(s, {'weekdays', 'at', 'relative', 'windowMinutes'});
    for (final w in (s['weekdays'] as List?) ?? const []) {
      if (w is! int || w < 1 || w > 7) invalid('weekdays are 1 (Mon)–7.');
    }
    if (s['at'] != null && s['relative'] != null)
      invalid('A routine is due at a clock time or relative to an anchor.');
    if (s['at'] != null) clockMinutes(s['at'], 'at');
    if (s['relative'] != null) {
      final r = jsonObject(s['relative'], 'relative');
      checkKeys(r, {'anchor', 'meal', 'offsetMinutes'});
      if (!const {'wake', 'bedtime', 'meal', 'workout'}.contains(r['anchor']))
        invalid('An anchor is wake, bedtime, meal or workout.');
      if ((r['anchor'] == 'meal') != (r['meal'] != null))
        invalid('A meal anchor, and only one, names its meal label.');
      final o = r['offsetMinutes'] ?? 0;
      if (o is! int || o.abs() > 720)
        invalid('offsetMinutes is a whole number within ±720.');
    }
    final w = s['windowMinutes'];
    if (w != null && (w is! int || w < 1 || w > 1440))
      invalid('windowMinutes is from 1 to 1440.');
    checkDate(j['from'], 'from');
    if (j['until'] != null) checkDate(j['until'], 'until');
    return Routine._(Map.unmodifiable(j));
  }
  final Map<String, Object?> json;
  String get id => json['id']! as String;
  int get version => json['version']! as int;
  Map<String, Object?> get action => json['action']! as Map<String, Object?>;
  Map<String, Object?> get schedule =>
      json['schedule']! as Map<String, Object?>;
  bool activeOn(String date) {
    if (date.compareTo(json['from']! as String) < 0) return false;
    final until = json['until'] as String?;
    if (until != null && date.compareTo(until) >= 0) return false;
    final weekdays = schedule['weekdays'] as List?;
    final wd = DateTime.parse('${date}T00:00:00Z').weekday;
    return weekdays == null || weekdays.contains(wd);
  }

  Map<String, Object?> toJson() => json;
}

/// A descriptive personal trial: a question, an action, a baseline and a
/// trial period, outcome metrics, and your conclusion.
final class Trial {
  Trial._(this.json);
  factory Trial.fromJson(Object? input) {
    final j = jsonObject(input, 'trial');
    checkKeys(j, {
      'id',
      'version',
      'question',
      'action',
      'baseline',
      'trial',
      'outcomes',
      'conclusion',
    });
    identifier(j, 'id');
    _version(j);
    if (_text(j, 'question', 1000) == null) invalid('A trial asks a question.');
    final a = jsonObject(j['action'], 'action');
    checkKeys(a, {'description', 'metric', 'target'});
    if (_text(a, 'description', 1000) == null)
      invalid('A trial action has a description.');
    if ((a['metric'] == null) != (a['target'] == null))
      invalid('An action check names both metric and target.');
    if (a['metric'] != null) {
      DailyMetric.fromJson(a['metric']);
      Target.fromJson(a['target']);
    }
    (String, String) period(String key) {
      final p = jsonObject(j[key], key);
      checkKeys(p, {'from', 'until'});
      final from = checkDate(p['from'], '$key from');
      final until = checkDate(p['until'], '$key until');
      if (until.compareTo(from) <= 0) invalid('$key until is after from.');
      return (from, until);
    }

    final b = period('baseline'), t = period('trial');
    if (t.$1.compareTo(b.$2) < 0)
      invalid('The trial period starts after the baseline ends.');
    final outcomes = jsonList(j, 'outcomes');
    if (outcomes.isEmpty || outcomes.length > 16)
      invalid('A trial has 1–16 outcome metrics.');
    for (final o in outcomes) {
      DailyMetric.fromJson(o);
    }
    if (j['conclusion'] != null) {
      final c = jsonObject(j['conclusion'], 'conclusion');
      checkKeys(c, {'decision', 'notes', 'at'});
      if (!const {'keep', 'adjust', 'stop', 'unclear'}.contains(c['decision']))
        invalid('A conclusion is keep, adjust, stop or unclear.');
      _text(c, 'notes', 4000);
      parseInstant(c['at'], 'at');
    }
    return Trial._(Map.unmodifiable(j));
  }
  final Map<String, Object?> json;
  String get id => json['id']! as String;
  int get version => json['version']! as int;
  Map<String, Object?> toJson() => json;
}

/// A saved cross-domain view: labelled metrics over a window.
final class SavedReview {
  SavedReview._(this.json);
  factory SavedReview.fromJson(Object? input) {
    final j = jsonObject(input, 'review');
    checkKeys(j, {'id', 'version', 'name', 'metrics', 'notes'});
    identifier(j, 'id');
    _version(j);
    if (_text(j, 'name', 200) == null) invalid('A review has a name.');
    _text(j, 'notes', 4000);
    final metrics = jsonList(j, 'metrics');
    if (metrics.isEmpty || metrics.length > 32)
      invalid('A review has 1–32 metrics.');
    for (final m in metrics) {
      DailyMetric.fromJson(m);
    }
    return SavedReview._(Map.unmodifiable(j));
  }
  final Map<String, Object?> json;
  String get id => json['id']! as String;
  int get version => json['version']! as int;
  Map<String, Object?> toJson() => json;
}
