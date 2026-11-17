import 'package:bodytmi_core/bodytmi_core.dart';

import 'support.dart';

void practiceTests() {
  test('practices validate ratings, phases and plans', () {
    final p = PracticeDefinition.fromJson({
      'id': 'rest',
      'name': 'Quiet rest',
      'ratings': [
        {
          'id': 'tired',
          'label': 'Tired',
          'minimum': 1,
          'maximum': 5,
          'when': 'before',
        },
      ],
    });
    // Without a duration the clock is open-ended and ends when you end it.
    check(p.plan.openEnded);
    jsonEqual(p.checkRatings({'tired': 3}, 'before'), {'tired': 3});
    rejects(() => p.checkRatings({'tired': 3}, 'after'));
    rejects(() => p.checkRatings({'tired': 6}, 'before'));
    rejects(() => p.checkRatings({'calm': 3}, 'before'));
    rejects(
      () => PracticeDefinition.fromJson({
        'id': 'x',
        'name': 'X',
        'durationSeconds': 0,
      }),
    );
    rejects(
      () => PracticeDefinition.fromJson({
        'id': 'x',
        'name': 'X',
        'ratings': [
          {'id': 'a', 'label': 'A', 'minimum': 5, 'maximum': 5},
        ],
      }),
    );
    final timed = PracticeDefinition.fromJson({
      'id': 'breathe',
      'name': 'Breathe',
      'durationSeconds': 60,
      'preparationSeconds': 5,
      'phases': {
        'phases': [
          {'id': 'in', 'milliseconds': 4000},
          {'id': 'out', 'milliseconds': 6000},
        ],
      },
    });
    equal(timed.plan.effortMilliseconds, 60000);
    equal(timed.plan.preparationMilliseconds, 5000);
    equal(timed.plan.tempo!.toJson()['phases'] is List, true);
  });

  test('practice clocks belong to their sessions', () {
    final revision = PracticeRevision.publish(
      PracticeDefinition.fromJson({
        'id': 'breathe',
        'name': 'Breathe',
        'durationSeconds': 60,
      }),
    );
    TimingActivity clock(String session) => TimingActivity.create(
      id: 'practice-$session',
      sessionId: 'practice:$session',
      setId: 'practice',
      metric: 'duration',
      plan: revision.practice.plan,
      at: DateTime.utc(2026, 11, 18, 7),
      owner: 'practice',
    );
    PracticeSession session(String id) => PracticeSession.fromJson({
      'schemaVersion': 1,
      'id': id,
      'version': 1,
      'practice': {'id': 'breathe', 'revision': 1},
      'startedAt': '2026-11-18T08:00:00+01:00',
      'clockId': 'practice-$id',
      'status': 'active',
    });
    validatePractices([revision], [session('a')], [clock('a')]);
    // A practice clock must name practice:<session>, not a training id.
    rejects(
      () => TimingActivity.create(
        id: 'x',
        sessionId: 'a',
        setId: 'practice',
        metric: 'duration',
        plan: revision.practice.plan,
        at: DateTime.utc(2026, 11, 18, 7),
        owner: 'practice',
      ),
    );
    // A clock pointing at another session, or an orphan clock, is rejected.
    final forged = TimingActivity.fromJson({
      ...clock('b').toJson(),
      'id': 'practice-a',
    });
    rejects(() => validatePractices([revision], [session('a')], [forged]));
    rejects(
      () => validatePractices([revision], [session('a')], [
        clock('a'),
        clock('b'),
      ]),
    );
    rejects(() => validatePractices([], [session('a')], [clock('a')]));
    // Confirmation needs an ended clock.
    rejects(() => clock('a').confirmPractice(DateTime.utc(2026, 11, 18, 8), 2));
  });

  test('box breathing and guided playlists', () {
    final box = boxBreathingPractice(secondsPerSide: 10);
    final phases = box.plan.tempo!.toJson()['phases']! as List;
    equal(phases.length, 4);
    check(phases.every((p) => (p as Map)['milliseconds'] == 10000));
    equal(box.plan.effortMilliseconds, 300000);
    check((box.json['source']! as String).contains('PMC9873947'));
    rejects(() => boxBreathingPractice(secondsPerSide: 30));
    final guided = PracticeDefinition.fromJson({
      'id': 'body-scan',
      'name': 'Body scan',
      'kind': 'meditation',
      'playlist': [
        {
          'id': 'scan-20',
          'title': 'Body scan, 20 min',
          'file': 'meditation/body-scan-20.mp3',
          'sha256': '0' * 64,
          'durationSeconds': 1200,
        },
      ],
    });
    equal(guided.playlist.single['id'], 'scan-20');
    rejects(
      () => PracticeDefinition.fromJson({
        'id': 'x',
        'name': 'X',
        'playlist': [
          {'id': 'a', 'title': 'A', 'file': 'a.mp3', 'sha256': 'abc'},
        ],
      }),
    );
    final revision = PracticeRevision.publish(guided);
    PracticeSession session(String track) => PracticeSession.fromJson({
      'schemaVersion': 1,
      'id': 's',
      'version': 1,
      'practice': {'id': 'body-scan', 'revision': 1},
      'startedAt': '2026-11-18T21:00:00+01:00',
      'status': 'confirmed',
      'confirmedAt': '2026-11-18T21:20:00+01:00',
      'actual': {'milliseconds': 1200000, 'source': 'manual'},
      'trackId': track,
    });
    validatePractices([revision], [session('scan-20')], []);
    rejects(() => validatePractices([revision], [session('other')], []));
  });
}
