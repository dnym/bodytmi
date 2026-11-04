import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'fixtures.dart';
import 'support.dart';

void workflowTests() {
  const service = TrainingService();
  test(
    'manual target carry preserves completed, authored and manual targets',
    () {
      final json = definition().toJson();
      final plan = json['plan']! as Map<String, Object?>;
      plan['children'] = [
        for (final id in ['a', 'b', 'c', 'd'])
          {'id': id, 'type': 'effort', 'slot': 'bench-heavy'},
        {
          'id': 'authored',
          'type': 'effort',
          'slot': 'bench-heavy',
          'targets': {
            'mass': {'value': '40', 'unit': 'kg'},
          },
        },
        {
          'id': 'warmup',
          'type': 'effort',
          'slot': 'bench-heavy',
          'role': 'warmup',
        },
        {'id': 'other', 'type': 'effort', 'slot': 'bench-light'},
      ];
      var s = start(
        from: WorkoutRevision.publish(WorkoutDefinition.fromJson(json)),
      );
      s = service.editTarget(s, s.sets[3].id, 'mass', Quantity('55', 'kg'));
      s = service.complete(s, s.sets[2].id, {}, acceptSuggested: true);
      final before = s;
      s = service.editTarget(
        s,
        s.sets[0].id,
        'mass',
        Quantity('70', 'kg'),
        applyToRemaining: true,
      );
      equal(s.contentVersion, before.contentVersion + 1);
      equal(s.sets[0].suggested['mass']!.value.toString(), '70');
      equal(s.sets[1].suggested['mass']!.value.toString(), '70');
      for (var i = 2; i < s.sets.length; i++) {
        equal(
          canonicalJson(s.sets[i].toJson()),
          canonicalJson(before.sets[i].toJson()),
        );
      }
      check(s.sets[0].manualTargets.contains('mass'));
      check(s.sets[1].manualTargets.contains('mass'));
      check(
        identical(
          service.editTarget(
            s,
            s.sets[0].id,
            'mass',
            Quantity('70', 'kg'),
            applyToRemaining: true,
          ),
          s,
        ),
      );
      rejects(
        () => service.editTarget(s, s.sets[2].id, 'mass', Quantity('70', 'kg')),
      );
      rejects(
        () => service.editTarget(s, s.sets[0].id, 'mass', Quantity('70', 's')),
      );
      rejects(
        () => service.editTarget(
          s,
          s.sets[0].id,
          'missing',
          Quantity('1', 'rep'),
        ),
      );
      final decoded = sessionFromJson(s.toJson());
      equal(canonicalJson(decoded.toJson()), canonicalJson(s.toJson()));
      final complete = service.complete(
        s,
        s.sets[0].id,
        {},
        acceptSuggested: true,
      );
      check(complete.sets[0].manualTargets.contains('mass'));
    },
  );
  test(
    'skip slot selects planned efforts and preserves other roles and slots',
    () {
      final json = definition().toJson();
      ((json['plan']! as Map<String, Object?>)['children']! as List<Object?>)
          .insert(0, {
            'id': 'warmup',
            'type': 'effort',
            'slot': 'bench-heavy',
            'role': 'warmup',
          });
      var session = start(
        from: WorkoutRevision.publish(WorkoutDefinition.fromJson(json)),
      );
      final work = session.sets.firstWhere(
        (s) => s.slotId == 'bench-heavy' && s.role == 'work',
      );
      session = service.complete(session, work.id, {}, acceptSuggested: true);
      final before = session;
      rejects(() => service.skipSlot(session, 'missing', confirm: true));
      rejects(
        () => service.skipSlot(
          session,
          'bench-heavy',
          role: 'other',
          confirm: true,
        ),
      );
      rejects(() => service.skipSlot(session, 'bench-heavy', confirm: false));
      final skipped = service.skipSlot(
        session,
        'bench-heavy',
        role: 'work',
        confirm: true,
      );
      equal(skipped.contentVersion, before.contentVersion + 1);
      for (var i = 0; i < before.sets.length; i++) {
        final old = before.sets[i];
        final next = skipped.sets[i];
        if (old.slotId == 'bench-heavy' &&
            old.role == 'work' &&
            old.status == SetStatus.planned) {
          equal(next.status, SetStatus.skipped);
        } else {
          equal(canonicalJson(next.toJson()), canonicalJson(old.toJson()));
        }
      }
      check(
        identical(
          service.skipSlot(skipped, 'bench-heavy', role: 'work', confirm: true),
          skipped,
        ),
      );
      final all = service.skipSlot(skipped, 'bench-heavy', confirm: true);
      equal(all.sets.first.status, SetStatus.skipped);
      equal(all.sets.last.status, SetStatus.planned);
      rejects(
        () => service.skipSlot(
          service.skipRemaining(all, confirm: true).finish(instant(2)),
          'bench-heavy',
          confirm: true,
        ),
      );
    },
  );
  test('skip remaining preserves completed results and increments once', () {
    var session = start();
    final completedId = session.sets.first.id;
    session = service.complete(session, completedId, {
      'mass': Quantity('65', 'kg'),
    }, acceptSuggested: true);
    session = service.skip(session, session.sets[1].id, confirm: true);
    session = service.annotate(
      session,
      session.sets.last.id,
      SetObservations.fromJson({'notes': 'Save for next time'}),
    );
    final complete = canonicalJson(session.sets.first.toJson());
    final earlierSkip = canonicalJson(session.sets[1].toJson());
    rejects(() => service.skipRemaining(session, confirm: false));
    final skipped = service.skipRemaining(session, confirm: true);
    equal(skipped.contentVersion, session.contentVersion + 1);
    equal(canonicalJson(skipped.sets.first.toJson()), complete);
    equal(canonicalJson(skipped.sets[1].toJson()), earlierSkip);
    equal(skipped.sets.last.status, SetStatus.skipped);
    equal(skipped.sets.last.observations!.notes, 'Save for next time');
    check(
      skipped.sets
          .where((s) => s.status == SetStatus.skipped)
          .every((s) => s.actuals.isEmpty),
    );
    check(identical(service.skipRemaining(skipped, confirm: true), skipped));
    final finishedSession = skipped.finish(instant(2));
    rejects(() => service.skipRemaining(finishedSession, confirm: true));
    equal(
      canonicalJson(sessionFromJson(skipped.toJson()).toJson()),
      canonicalJson(skipped.toJson()),
    );
  });
  test(
    'same exercise in heavy/light slots keeps independent actuals and sources',
    () {
      var old = start();
      for (final set in old.sets) {
        old = service.complete(
          old,
          set.id,
          metrics({
            'mass': (set.slotId == 'bench-heavy' ? '62.5' : '47.5', 'kg'),
          }),
          acceptSuggested: true,
        );
      }
      old = old.finish(instant(1).add(const Duration(hours: 1)));
      final next = start(id: 'next', day: 2, history: [old]);
      for (final set in next.sets) {
        equal(
          set.suggested['mass']!.value.toString(),
          set.slotId == 'bench-heavy' ? '62.5' : '47.5',
        );
        equal(
          set.suggested['reps']!.value.toString(),
          set.slotId == 'bench-heavy' ? '8' : '12',
        );
        equal(set.sources['mass']!.sessionId, 'session-1');
        check(set.sources['reps'] == null);
      }
    },
  );
  test('a structural revision preserves slot history and old snapshots', () {
    var old = start();
    old = service.complete(
      old,
      old.sets.first.id,
      metrics({'mass': ('65', 'kg')}),
      acceptSuggested: true,
    );
    for (final set in old.sets.skip(1)) {
      old = service.complete(old, set.id, {}, acceptSuggested: true);
    }
    old = old.finish(instant(1).add(const Duration(hours: 1)));
    final json = definition().toJson();
    json['name'] = 'Revised upper';
    (json['slots']! as List<Object?>).add({
      'id': 'row',
      'exercise': 'row',
      'implementation': 'dumbbell',
      'targets': {
        'mass': {'value': '20', 'unit': 'kg'},
        'reps': {'value': '10', 'unit': 'rep'},
      },
    });
    ((json['plan']! as Map<String, Object?>)['children']! as List<Object?>).add(
      {'id': 'row-set', 'type': 'effort', 'slot': 'row'},
    );
    final rev2 = WorkoutRevision.publish(
      WorkoutDefinition.fromJson(json),
      previous: old.revision,
    );
    final next = start(id: 'next', day: 2, from: rev2, history: [old]);
    equal(next.sets.first.suggested['mass']!.value.toString(), '65');
    equal(old.revision.number, 1);
    equal(old.revision.definition.name, 'Upper A');
    equal(next.revision.number, 2);
  });
  test('different equipment or changed setup note excludes history', () {
    var old = start();
    for (final set in old.sets) {
      old = service.complete(
        old,
        set.id,
        metrics({'mass': ('70', 'kg')}),
        acceptSuggested: true,
      );
    }
    old = old.finish(instant(1).add(const Duration(hours: 1)));
    for (final field in ['equipment', 'setupNote']) {
      final json = definition().toJson();
      final slots = json['slots']! as List<Object?>;
      (slots.first! as Map<String, Object?>)[field] = 'other';
      final rev = WorkoutRevision.publish(
        WorkoutDefinition.fromJson(json),
        previous: old.revision,
      );
      final next = start(id: 'next', day: 2, from: rev, history: [old]);
      equal(next.sets.first.suggested['mass']!.value.toString(), '60');
      check(next.sets.first.sources.isEmpty);
    }
  });
  test('future, unfinished, and another-template history cannot prefill', () {
    final active = start();
    final future = finished(start(id: 'future', day: 3));
    final json = definition().toJson()..['id'] = 'other-template';
    final other = finished(
      start(
        id: 'other',
        from: WorkoutRevision.publish(WorkoutDefinition.fromJson(json)),
      ),
    );
    final next = start(id: 'next', day: 2, history: [active, future, other]);
    check(next.sets.every((s) => s.sources.isEmpty));
  });
  test('history completed after the new session start is not eligible', () {
    var old = start();
    for (final set in old.sets) {
      old = service.complete(old, set.id, {}, acceptSuggested: true);
    }
    old = old.finish(instant(4));
    final next = start(id: 'next', day: 2, history: [old]);
    check(next.sets.every((s) => s.sources.isEmpty));
  });
  test(
    'suggested values are not actuals; completion requires observations or acceptance',
    () {
      final session = start();
      check(session.sets.first.actuals.isEmpty);
      rejects(() => service.complete(session, session.sets.first.id, {}));
      final done = service.complete(
        session,
        session.sets.first.id,
        {},
        acceptSuggested: true,
      );
      equal(done.sets.first.status, SetStatus.completed);
      check(session.sets.first.actuals.isEmpty);
    },
  );
  test(
    'completion rejects wrong dimensions and preserves original prescription',
    () {
      final session = start();
      rejects(
        () => service.complete(
          session,
          session.sets.first.id,
          metrics({'mass': ('60', 's')}),
          acceptSuggested: true,
        ),
      );
      final done = service.complete(
        session,
        session.sets.first.id,
        metrics({'reps': ('7', 'rep')}),
        acceptSuggested: true,
      );
      equal(done.sets.first.actuals['reps']!.value.toString(), '7');
      equal(done.sets.first.suggested['reps']!.value.toString(), '8');
    },
  );
  test(
    'finish requires explicit completion or skip; repeated finish is a no-op',
    () {
      var session = start();
      rejects(() => session.finish(instant(2)));
      for (final set in session.sets) {
        session = service.skip(session, set.id);
      }
      final done = session.finish(instant(2));
      equal(done.status, SessionStatus.finalized);
      jsonEqual(done.finish(instant(3)).toJson(), done.toJson());
      rejects(() => start().finish(instant(0)));
    },
  );
  test(
    'editing a finalized result changes its content version without refinalizing',
    () {
      final done = finished(start());
      final edited = service.complete(
        done,
        done.sets.first.id,
        metrics({'reps': ('11', 'rep')}),
        acceptSuggested: true,
      );
      equal(edited.status, SessionStatus.finalized);
      equal(edited.finishedAt, done.finishedAt);
      equal(
        edited.sets.first.contentVersion,
        done.sets.first.contentVersion + 1,
      );
      equal(edited.sets.first.actuals['reps']!.value.toString(), '11');
      jsonEqual(edited.finish(instant(3)).toJson(), edited.toJson());
    },
  );
  test('skipping completed work needs explicit destructive confirmation', () {
    final done = finished(start());
    rejects(() => service.skip(done, done.sets.first.id));
    final skipped = service.skip(done, done.sets.first.id, confirm: true);
    check(skipped.sets.first.actuals.isEmpty);
  });
  test(
    'session snapshots round-trip and reject forged occurrence identities',
    () {
      final session = finished(start());
      jsonEqual(sessionFromJson(session.toJson()).toJson(), session.toJson());
      final json = copyJson(session.toJson());
      ((json['sets']! as List<Object?>).first! as Map<String, Object?>)['id'] =
          'forged';
      rejects(() => sessionFromJson(json));
      json['schemaVersion'] = 2;
      rejects(() => sessionFromJson(json));
    },
  );
  test(
    'invalid calendar dates cannot silently normalize into another session day',
    () {
      for (final value in [
        '2026-02-30T12:00:00Z',
        '2026-10-01T24:00:00Z',
        '2026-10-01T12:00:00+99:00',
      ]) {
        rejects(() => parseInstant(value, 'start'));
      }
      equal(
        parseInstant('2024-02-29T12:00:00Z', 'start'),
        DateTime.utc(2024, 2, 29, 12),
      );
    },
  );
  test(
    'timestamps require explicit timezone; exported snapshot is immutable',
    () {
      rejects(() => parseInstant('2026-10-01T12:00:00', 'start'));
      final session = start();
      var immutable = false;
      try {
        session.sets.clear();
      } on UnsupportedError {
        immutable = true;
      }
      check(immutable);
      equal(parseInstant('2026-10-01T14:00:00+02:00', 'start'), instant(1));
    },
  );
}
