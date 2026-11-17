import 'energy.dart' show requireDate;
import 'errors.dart';

/// The current body plan: one programme (or your own cycle) as a diet run,
/// with the companion changes applied at activation (D14) and what ending
/// it undid. History is kept when a plan ends.
final class BodyPlan {
  BodyPlan._(this.json);
  factory BodyPlan.fromJson(Object? input) {
    final j = jsonObject(input, 'body plan');
    checkKeys(j, {
      'schemaVersion',
      'id',
      'requestId',
      'programme',
      'cycle',
      'startDate',
      'companions',
      'status',
      'endDate',
      'undone',
      'contentVersion',
    });
    if (j['schemaVersion'] != 1)
      invalid('Unsupported body plan schemaVersion.');
    identifier(j, 'id');
    identifier(j, 'requestId');
    if (j['programme'] != null) {
      final p = jsonObject(j['programme'], 'programme');
      checkKeys(p, {'id', 'choices', 'category'});
      identifier(p, 'id');
      jsonObject(p['choices'], 'choices');
      final c = p['category'];
      if (c is! int || c < 1 || c > 3) invalid('category is 1, 2 or 3.');
    }
    final cycle = jsonObject(j['cycle'], 'cycle');
    checkKeys(cycle, {'id', 'revision'});
    identifier(cycle, 'id');
    if (cycle['revision'] is! int) invalid('cycle revision is an integer.');
    final start = requireDate(j['startDate'], 'startDate');
    final companions = jsonObject(j['companions'], 'companions');
    checkKeys(companions, {'steps', 'pausedRuns', 'recommendation'});
    if (companions['steps'] is! bool) invalid('companions.steps is boolean.');
    final runs = <String>{};
    for (final r in jsonList(companions, 'pausedRuns')) {
      final x = jsonObject(r, 'paused run');
      checkKeys(x, {'runId', 'pausedVersion'});
      if (!runs.add(identifier(x, 'runId'))) invalid('Duplicate paused run.');
      if (x['pausedVersion'] is! int) invalid('pausedVersion is an integer.');
    }
    final status = j['status'];
    if (status != 'active' && status != 'ended')
      invalid('A plan is active or ended.');
    if ((status == 'ended') != (j['endDate'] != null))
      invalid('An ended plan, and only one, has an endDate.');
    if (j['endDate'] != null &&
        requireDate(j['endDate'], 'endDate').compareTo(start) <= 0)
      invalid('endDate is after startDate.');
    if (j['undone'] != null) {
      final u = jsonObject(j['undone'], 'undone');
      checkKeys(u, {'resumed', 'leftAlone'});
      for (final id in jsonList(u, 'resumed')) {
        if (id is! String || !runs.contains(id))
          invalid('A resumed run must be one the plan paused.');
      }
      for (final l in jsonList(u, 'leftAlone')) {
        final x = jsonObject(l, 'left alone');
        checkKeys(x, {'runId', 'reason'});
        identifier(x, 'runId');
        requiredString(x, 'reason');
      }
    }
    final version = j['contentVersion'];
    if (version is! int || version < 1) invalid('contentVersion is positive.');
    return BodyPlan._(Map.unmodifiable(j));
  }

  final Map<String, Object?> json;
  String get id => json['id']! as String;
  String get status => json['status']! as String;
  String get startDate => json['startDate']! as String;
  String? get endDate => json['endDate'] as String?;
  int get contentVersion => json['contentVersion']! as int;
  Map<String, Object?> get companions =>
      json['companions']! as Map<String, Object?>;
  bool get stepsCompanion => companions['steps']! as bool;
  List<({String runId, int pausedVersion})> get pausedRuns => [
    for (final r in companions['pausedRuns']! as List)
      (
        runId: (r as Map)['runId']! as String,
        pausedVersion: r['pausedVersion']! as int,
      ),
  ];
  bool covers(String date) =>
      date.compareTo(startDate) >= 0 &&
      (endDate == null || date.compareTo(endDate!) < 0);
  Map<String, Object?> toJson() => json;
}

/// The standalone daily step goal (stage 6 turns it into a goal record):
/// dated revisions; [steps] null clears it from [from].
final class StepGoalRevision {
  StepGoalRevision._(this.number, this.from, this.steps);
  factory StepGoalRevision.publish(
    String from,
    int? steps, {
    StepGoalRevision? previous,
  }) {
    requireDate(from, 'from');
    if (steps != null && (steps < 1 || steps > 200000))
      invalid('steps is a whole number from 1 to 200000.');
    return StepGoalRevision._((previous?.number ?? 0) + 1, from, steps);
  }
  factory StepGoalRevision.fromJson(Object? input) {
    final j = jsonObject(input, 'step goal');
    checkKeys(j, {'schemaVersion', 'revision', 'from', 'steps'});
    final revision = j['revision'];
    if (j['schemaVersion'] != 1 || revision is! int || revision < 1)
      invalid('Invalid step goal revision.');
    final steps = j['steps'];
    if (steps != null && steps is! int) invalid('steps is a whole number.');
    return StepGoalRevision.publish(
      requireDate(j['from'], 'from'),
      steps as int?,
    )._renumber(revision);
  }
  StepGoalRevision _renumber(int n) => StepGoalRevision._(n, from, steps);
  final int number;
  final String from;
  final int? steps;
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'revision': number,
    'from': from,
    'steps': steps,
  };
}

/// The standalone step goal in force on [date]: latest from ≤ date.
StepGoalRevision? stepGoalOn(String date, List<StepGoalRevision> revisions) {
  StepGoalRevision? best;
  for (final r in revisions) {
    if (r.from.compareTo(date) > 0) continue;
    if (best == null ||
        r.from.compareTo(best.from) > 0 ||
        (r.from == best.from && r.number > best.number))
      best = r;
  }
  return best;
}
