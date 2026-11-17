import 'errors.dart';
import 'instant.dart';
import 'tempo.dart';
import 'timing.dart';

/// A rating a practice asks for before and/or after (e.g. calm 1–10).
final class PracticeRating {
  PracticeRating._(this.json);
  factory PracticeRating.fromJson(Object? input) {
    final j = jsonObject(input, 'rating');
    checkKeys(j, {'id', 'label', 'minimum', 'maximum', 'when'});
    identifier(j, 'id');
    final label = requiredString(j, 'label');
    if (label.length > 200) invalid('A rating label is at most 200.');
    final min = j['minimum'], max = j['maximum'];
    if (min is! int || max is! int || min < 0 || max <= min || max > 100)
      invalid('A rating scale is whole numbers 0–100 with minimum < maximum.');
    final when = j['when'] ?? 'both';
    if (!const {'before', 'after', 'both'}.contains(when))
      invalid('A rating is asked before, after or both.');
    return PracticeRating._(Map.unmodifiable({...j, 'when': when}));
  }
  final Map<String, Object?> json;
  String get id => json['id']! as String;
  int get minimum => json['minimum']! as int;
  int get maximum => json['maximum']! as int;
  bool askedAt(String moment) =>
      json['when'] == 'both' || json['when'] == moment;
}

/// A practice: meditation, breathing, quiet rest, stretching or anything
/// timed. Optional duration (open-ended without), optional preparation and
/// an optional phase cycle (a tempo plan, e.g. inhale/hold/exhale).
final class PracticeDefinition {
  PracticeDefinition._(this.json, this.ratings);
  factory PracticeDefinition.fromJson(Object? input) {
    final j = jsonObject(input, 'practice');
    checkKeys(j, {
      'id',
      'name',
      'kind',
      'notes',
      'source',
      'durationSeconds',
      'preparationSeconds',
      'phases',
      'ratings',
    });
    identifier(j, 'id');
    final name = requiredString(j, 'name');
    if (name.length > 200) invalid('A practice name is at most 200.');
    if (j['kind'] != null) identifier(j, 'kind');
    for (final key in ['notes', 'source']) {
      final v = j[key];
      if (v != null && (v is! String || v.trim().isEmpty || v.length > 4000))
        invalid('$key is nonempty text of at most 4000 characters.');
    }
    for (final key in ['durationSeconds', 'preparationSeconds']) {
      final v = j[key];
      if (v != null && (v is! int || v < 1 || v > 86400))
        invalid('$key is a whole number of seconds from 1 to 86400.');
    }
    if (j['phases'] != null) TempoPlan.fromJson(j['phases']);
    final ratings = <PracticeRating>[];
    final ids = <String>{};
    for (final r in (j['ratings'] as List?) ?? const []) {
      final rating = PracticeRating.fromJson(r);
      if (!ids.add(rating.id)) invalid('Duplicate rating ${rating.id}.');
      ratings.add(rating);
    }
    if (ratings.length > 16) invalid('A practice has at most 16 ratings.');
    final def = PracticeDefinition._(Map.unmodifiable(j), ratings);
    def.plan;
    return def;
  }
  final Map<String, Object?> json;
  final List<PracticeRating> ratings;
  String get id => json['id']! as String;
  int? get durationSeconds => json['durationSeconds'] as int?;

  /// The clock plan: the duration as the effort target (a timer running out
  /// awaits confirmation), or open-ended without one.
  TimingPlan get plan => TimingPlan.fromJson({
    if (durationSeconds != null)
      'effortMilliseconds': durationSeconds! * 1000
    else ...{
      'openEnded': true,
      'unplannedDuration': true,
    },
    if (json['preparationSeconds'] != null)
      'preparationMilliseconds': (json['preparationSeconds']! as int) * 1000,
    if (json['phases'] != null) 'tempo': json['phases'],
  });

  /// Validates [values] against the ratings asked at [moment].
  Map<String, int> checkRatings(Object? values, String moment) {
    if (values == null) return const {};
    final v = jsonObject(values, '$moment ratings');
    final out = <String, int>{};
    for (final e in v.entries) {
      final r =
          ratings.where((r) => r.id == e.key).firstOrNull ??
          invalid('Practice $id has no rating ${e.key}.');
      if (!r.askedAt(moment)) invalid('Rating ${e.key} is not asked $moment.');
      final n = e.value;
      if (n is! int || n < r.minimum || n > r.maximum)
        invalid('Rating ${e.key} is from ${r.minimum} to ${r.maximum}.');
      out[e.key] = n;
    }
    return out;
  }

  Map<String, Object?> toJson() => json;
}

final class PracticeRevision {
  PracticeRevision._(this.number, this.practice);
  factory PracticeRevision.publish(
    PracticeDefinition practice, {
    PracticeRevision? previous,
  }) => PracticeRevision._((previous?.number ?? 0) + 1, practice);
  factory PracticeRevision.fromJson(Object? input) {
    final j = jsonObject(input, 'practice revision');
    checkKeys(j, {'schemaVersion', 'revision', 'practice'});
    final n = j['revision'];
    if (j['schemaVersion'] != 1 || n is! int || n < 1)
      invalid('Invalid practice revision.');
    return PracticeRevision._(n, PracticeDefinition.fromJson(j['practice']));
  }
  final int number;
  final PracticeDefinition practice;
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'revision': number,
    'practice': practice.toJson(),
  };
}

/// One practice session: the pinned practice revision, its clock, optional
/// before/after ratings and, once confirmed, the actual time. A clock
/// running out does not complete it; confirmation does.
final class PracticeSession {
  PracticeSession._(this.json);
  factory PracticeSession.fromJson(Object? input) {
    final j = jsonObject(input, 'practice session');
    checkKeys(j, {
      'schemaVersion',
      'id',
      'version',
      'practice',
      'startedAt',
      'clockId',
      'status',
      'before',
      'after',
      'actual',
      'confirmedAt',
      'notes',
    });
    if (j['schemaVersion'] != 1) invalid('Invalid practice session.');
    identifier(j, 'id');
    final v = j['version'];
    if (v is! int || v < 1) invalid('version must be positive.');
    final p = jsonObject(j['practice'], 'practice');
    checkKeys(p, {'id', 'revision'});
    identifier(p, 'id');
    if (p['revision'] is! int || (p['revision']! as int) < 1)
      invalid('A practice revision is positive.');
    parseInstant(j['startedAt'], 'startedAt');
    if (j['clockId'] != null) identifier(j, 'clockId');
    final status = j['status'];
    if (!const {'active', 'confirmed', 'abandoned'}.contains(status))
      invalid('A practice session is active, confirmed or abandoned.');
    if ((status == 'confirmed') != (j['actual'] != null) ||
        (status == 'confirmed') != (j['confirmedAt'] != null))
      invalid('A confirmed practice session, and only one, has actual time.');
    if (j['confirmedAt'] != null) parseInstant(j['confirmedAt'], 'confirmedAt');
    if (j['actual'] != null) {
      final a = jsonObject(j['actual'], 'actual');
      checkKeys(a, {'milliseconds', 'source', 'termination'});
      final ms = a['milliseconds'];
      if (ms is! int || ms < 0 || ms > 86400000)
        invalid('Actual time is 0 to 24 hours in milliseconds.');
      if (a['source'] != 'clock' && a['source'] != 'manual')
        invalid('Actual time comes from the clock or is entered manually.');
      if ((a['source'] == 'clock') != (j['clockId'] != null))
        invalid('Clock time needs the session clock.');
    }
    final notes = j['notes'];
    if (notes != null &&
        (notes is! String || notes.trim().isEmpty || notes.length > 4000))
      invalid('Notes are nonempty text of at most 4000 characters.');
    return PracticeSession._(Map.unmodifiable(j));
  }
  final Map<String, Object?> json;
  String get id => json['id']! as String;
  int get version => json['version']! as int;
  String get status => json['status']! as String;
  String? get clockId => json['clockId'] as String?;
  String get practiceId => (json['practice']! as Map)['id']! as String;
  int get practiceRevision => (json['practice']! as Map)['revision']! as int;
  DateTime get startedAt => parseInstant(json['startedAt'], 'startedAt');
  String get date => (json['startedAt']! as String).substring(0, 10);
  String get clockSessionId => 'practice:$id';
  Map<String, Object?> toJson() => json;
}

/// Sessions pin published practice revisions with valid ratings; each
/// session's clock is a practice clock of that session, and a confirmed
/// clock time equals the clock's measured time.
void validatePractices(
  List<PracticeRevision> practices,
  List<PracticeSession> sessions,
  List<TimingActivity> timers,
) {
  final byKey = {for (final p in practices) '${p.practice.id}/${p.number}': p};
  final numbers = <String, List<int>>{};
  for (final p in practices) {
    numbers.putIfAbsent(p.practice.id, () => []).add(p.number);
  }
  for (final e in numbers.entries) {
    final sorted = [...e.value]..sort();
    for (var i = 0; i < sorted.length; i++) {
      if (sorted[i] != i + 1)
        invalid('Practice ${e.key} revisions have a gap.');
    }
  }
  final clocks = {
    for (final t in timers)
      if (t.isPractice) t.id: t,
  };
  final used = <String>{};
  for (final s in sessions) {
    final p =
        byKey['${s.practiceId}/${s.practiceRevision}'] ??
        invalid('Practice session ${s.id} pins an unpublished practice.');
    p.practice.checkRatings(s.json['before'], 'before');
    p.practice.checkRatings(s.json['after'], 'after');
    if (s.clockId == null) continue;
    final clock =
        clocks[s.clockId] ??
        invalid('Practice session ${s.id} has no practice clock.');
    if (!used.add(clock.id) || clock.sessionId != s.clockSessionId)
      invalid('Practice clock ${clock.id} belongs to another session.');
    final actual = s.json['actual'] as Map?;
    if (s.status == 'confirmed' && actual!['source'] == 'clock') {
      if (clock.status != 'confirmed' ||
          actual['milliseconds'] != clock.effortElapsedMilliseconds)
        invalid('Practice session ${s.id} time does not match its clock.');
    }
    if (s.status == 'active' &&
        !(clock.active || clock.status == 'awaitingConfirmation'))
      invalid('Active practice session ${s.id} has an ended clock.');
  }
  for (final c in clocks.values) {
    if (!sessions.any((s) => s.clockId == c.id))
      invalid('Practice clock ${c.id} has no session.');
  }
}
