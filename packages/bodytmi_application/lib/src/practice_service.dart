import 'package:bodytmi_core/bodytmi_core.dart';

import 'canonical_json.dart';
import 'timing_service.dart';
import 'training_repository.dart';

const practiceKind = 'practice';
const practiceSessionKind = 'practice-session';

/// Archive and backup check of practices, their sessions and clocks.
void validatePracticeRecords(
  List<DietRecord> records,
  List<TimingActivity> timers,
) => validatePractices(
  [
    for (final r in records)
      if (r.kind == practiceKind) PracticeRevision.fromJson(r.snapshot),
  ],
  [
    for (final r in records)
      if (r.kind == practiceSessionKind) PracticeSession.fromJson(r.snapshot),
  ],
  timers,
);

/// Practices (meditation, breathing, quiet rest, stretching...) and their
/// timed sessions. The clock is an ordinary timing activity owned by the
/// session, so the single foreground clock (F9), pause, resume and recovery
/// after a crash work as for training; a clock running out awaits
/// confirmation and confirming completes the session.
final class PracticeService {
  const PracticeService(this.repository);
  final TrainingRepository repository;

  Future<List<PracticeRevision>> revisions() async => [
    for (final r in await repository.dietRecords(kind: practiceKind))
      PracticeRevision.fromJson(r.snapshot),
  ];

  Future<PracticeRevision> revision(String id, [int? number]) async {
    final all = [
      for (final r in await revisions())
        if (r.practice.id == id) r,
    ]..sort((a, b) => a.number.compareTo(b.number));
    if (all.isEmpty)
      throw BodyTmiException('not_found', 'Practice $id is not defined.');
    if (number == null) return all.last;
    return all.where((r) => r.number == number).firstOrNull ??
        (throw BodyTmiException(
          'not_found',
          'Practice $id has no revision $number.',
        ));
  }

  Future<PracticeRevision> define(
    PracticeDefinition practice,
    int expectedRevision,
  ) => repository.transaction(() async {
    final all = [
      for (final r in await revisions())
        if (r.practice.id == practice.id) r,
    ]..sort((a, b) => a.number.compareTo(b.number));
    if ((all.lastOrNull?.number ?? 0) != expectedRevision)
      throw const BodyTmiException('conflict', 'Practice revision changed.');
    final next = PracticeRevision.publish(practice, previous: all.lastOrNull);
    await repository.saveDietRecord(
      DietRecord(practiceKind, practice.id, next.number, next.toJson()),
    );
    return next;
  });

  Future<List<PracticeSession>> sessions() async => [
    for (final r in await repository.dietRecords(kind: practiceSessionKind))
      PracticeSession.fromJson(r.snapshot),
  ]..sort((a, b) => a.startedAt.compareTo(b.startedAt));

  Future<PracticeSession> session(String id) async =>
      (await sessions()).where((s) => s.id == id).firstOrNull ??
      (throw BodyTmiException('not_found', 'Practice session $id not found.'));

  Future<void> _save(PracticeSession s) => repository.saveDietRecord(
    DietRecord(practiceSessionKind, s.id, 1, s.toJson()),
  );

  static String clockIdOf(String sessionId) => 'practice-$sessionId';

  /// Starts a session with a paused clock. A retry with the same inputs
  /// returns the stored session.
  Future<({PracticeSession session, TimingActivity clock})> start({
    required String id,
    required String practiceId,
    int? revision,
    required String at,
    Object? before,
    String? trackId,
  }) => repository.transaction(() async {
    if (id.length > 80) invalid('A practice session id is at most 80.');
    final p = await this.revision(practiceId, revision);
    final ratings = p.practice.checkRatings(before, 'before');
    if (trackId != null && !p.practice.playlist.any((t) => t['id'] == trackId))
      invalid('Practice $practiceId has no track $trackId.');
    final next = PracticeSession.fromJson({
      'schemaVersion': 1,
      'id': id,
      'version': 1,
      'practice': {'id': practiceId, 'revision': p.number},
      'startedAt': at,
      'clockId': clockIdOf(id),
      'status': 'active',
      if (ratings.isNotEmpty) 'before': ratings,
      'trackId': ?trackId,
    });
    final existing = (await sessions()).where((s) => s.id == id).firstOrNull;
    if (existing != null) {
      final first = {...existing.toJson(), 'version': 1, 'status': 'active'}
        ..remove('after')
        ..remove('actual')
        ..remove('confirmedAt')
        ..remove('notes');
      if (canonicalJson(first) != canonicalJson(next.toJson()))
        throw BodyTmiException('conflict', 'Practice session $id exists.');
      return (
        session: existing,
        clock: await TimingService(repository).show(existing.clockId!),
      );
    }
    if ((await repository.activeTimingActivities()).isNotEmpty ||
        (await repository.windowCheckpoints()).any((c) => c.reserved) ||
        (await repository.repeatCheckpoints()).any((c) => c.reserved))
      throw const BodyTmiException(
        'conflict',
        'Another clock is active; stop or discard it first.',
      );
    final clock = TimingActivity.create(
      id: clockIdOf(id),
      sessionId: next.clockSessionId,
      setId: 'practice',
      metric: 'duration',
      plan: p.practice.plan,
      at: parseInstant(at, 'at'),
      owner: 'practice',
    );
    await repository.saveTimingActivity(clock);
    await _save(next);
    return (session: next, clock: clock);
  });

  /// Ends the practice clock before (or at) its target; it then awaits
  /// confirmation. Open-ended practices always end this way.
  Future<TimingActivity> end(String id, int clockVersion, DateTime at) async {
    final s = await session(id);
    if (s.status != 'active') invalid('The practice session is not active.');
    return TimingService(
      repository,
    ).stop(s.clockId!, clockVersion, at, confirm: true);
  }

  /// Records the actual time from the ended clock, after-ratings and notes.
  Future<PracticeSession> confirm(
    String id,
    int expectedVersion,
    String at, {
    Object? after,
    String? notes,
  }) => repository.transaction(() async {
    final s = await session(id);
    if (s.status == 'confirmed') return s;
    if (s.status != 'active') invalid('The practice session was abandoned.');
    if (s.version != expectedVersion)
      throw const BodyTmiException('conflict', 'Practice session changed.');
    final p = await revision(s.practiceId, s.practiceRevision);
    final ratings = p.practice.checkRatings(after, 'after');
    final timing = TimingService(repository);
    final clock = await timing.show(s.clockId!);
    if (clock.status != 'awaitingConfirmation')
      invalid(
        clock.status == 'running'
            ? 'The clock is running; pause or recover it, then end it.'
            : 'End the practice clock before confirming the session.',
      );
    final instant = parseInstant(at, 'at');
    final next = PracticeSession.fromJson({
      ...s.toJson(),
      'version': s.version + 1,
      'status': 'confirmed',
      'confirmedAt': at,
      'actual': {
        'milliseconds': clock.effortElapsedMilliseconds,
        'source': 'clock',
        'termination': clock.termination,
      },
      if (ratings.isNotEmpty) 'after': ratings,
      'notes': ?notes,
    });
    await repository.saveTimingActivity(
      clock.confirmPractice(instant, next.version),
    );
    await _save(next);
    return next;
  });

  /// Discards the clock and marks the session abandoned.
  Future<PracticeSession> abandon(String id, int expectedVersion) =>
      repository.transaction(() async {
        final s = await session(id);
        if (s.status != 'active')
          invalid('The practice session is not active.');
        if (s.version != expectedVersion)
          throw const BodyTmiException('conflict', 'Practice session changed.');
        final timing = TimingService(repository);
        final clock = await timing.show(s.clockId!);
        await repository.saveTimingActivity(
          clock.stop(DateTime.now().toUtc(), discard: true),
        );
        final next = PracticeSession.fromJson({
          ...s.toJson(),
          'version': s.version + 1,
          'status': 'abandoned',
        });
        await _save(next);
        return next;
      });

  /// Logs a practice done without the timer: entered time, no clock.
  Future<PracticeSession> log({
    required String id,
    required String practiceId,
    int? revision,
    required String at,
    required int milliseconds,
    Object? before,
    Object? after,
    String? notes,
  }) => repository.transaction(() async {
    if ((await sessions()).any((s) => s.id == id))
      throw BodyTmiException('conflict', 'Practice session $id exists.');
    final p = await this.revision(practiceId, revision);
    final b = p.practice.checkRatings(before, 'before');
    final a = p.practice.checkRatings(after, 'after');
    final next = PracticeSession.fromJson({
      'schemaVersion': 1,
      'id': id,
      'version': 1,
      'practice': {'id': practiceId, 'revision': p.number},
      'startedAt': at,
      'status': 'confirmed',
      'confirmedAt': at,
      'actual': {'milliseconds': milliseconds, 'source': 'manual'},
      if (b.isNotEmpty) 'before': b,
      if (a.isNotEmpty) 'after': a,
      'notes': ?notes,
    });
    await _save(next);
    return next;
  });
}
