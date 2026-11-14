import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'cli_test.dart';
import 'fixtures.dart';
import 'support.dart';

final _dumbbell = SubstituteComposition.fromJson({
  'exercise': 'bench-press',
  'implementation': 'dumbbell',
});

Map<String, Object?> _kg(String value) => {'value': value, 'unit': 'kg'};

Future<BodyTmiException> _failure(Object? Function() action) async {
  try {
    await action();
  } on BodyTmiException catch (error) {
    return error;
  }
  throw StateError('Expected a BodyTmiException.');
}

Future<void> _withStore(
  Future<void> Function(TrainingStore, String) action,
) async {
  final dir = await Directory.systemTemp.createTemp('bodytmi-substitute-');
  final store = await TrainingStore.open('${dir.path}/db.sqlite');
  try {
    await action(store, dir.path);
  } finally {
    await store.close();
    await dir.delete(recursive: true);
  }
}

Future<Map<String, Object?>> _resign(Map<String, Object?> envelope) async {
  envelope.remove('sha256');
  envelope['sha256'] = sha256
      .convert(utf8.encode(canonicalJson(envelope)))
      .toString();
  return envelope;
}

List<TrainingSet> _heavy(TrainingSession s) => [
  for (final set in s.sets)
    if (set.slotId == 'bench-heavy') set,
];

/// Completes every planned set, supplying [heavyMass] for heavy sets.
Future<TrainingSession> _finishAll(
  StoredTrainingService service,
  TrainingSession session,
  int day, {
  String? heavyMass,
}) async {
  for (final set in session.sets) {
    if (set.status != SetStatus.planned) continue;
    session = await service.edit(
      session.id,
      session.contentVersion,
      (s) => const TrainingService().complete(
        s,
        set.id,
        set.slotId == 'bench-heavy' && heavyMass != null
            ? metrics({'mass': (heavyMass, 'kg')})
            : const {},
        acceptSuggested: true,
      ),
    );
  }
  return service.edit(
    session.id,
    session.contentVersion,
    (s) => s.finish(DateTime.utc(2026, 10, day, 13)),
  );
}

void substitutionTests() {
  test('substitution never inherits an original lever value silently', () {
    final session = start();
    final original = canonicalJson(session.toJson());
    final swapped = const TrainingService().substitute(
      session,
      slotId: 'bench-heavy',
      scope: 'remaining',
      composition: _dumbbell,
      targets: {
        'reps': {'source': 'keep'},
      },
    );
    for (final set in _heavy(swapped)) {
      final swap = set.substitution!;
      equal(swap.composition, _dumbbell);
      equal(swap.targets['reps']!.source, 'keep');
      equal(swap.targets['mass']!.source, 'unresolved');
      check(swap.targets['mass']!.reason!.contains('No finished result'));
      check(!set.suggested.containsKey('mass'), 'no machine mass copied');
      equal(set.suggested['reps']!.enteredValue, '8');
    }
    // The light slot is untouched; the template itself never changes.
    equal(
      swapped.sets.last.suggested['mass']!.enteredValue,
      session.sets.last.suggested['mass']!.enteredValue,
    );
    check(
      swapped.revision.definition.slot('bench-heavy').implementation ==
          'barbell',
    );
    final setId = _heavy(swapped).first.id;
    // An unresolved target needs an explicit actual.
    rejects(
      () => const TrainingService().complete(
        swapped,
        setId,
        const {},
        acceptSuggested: true,
      ),
    );
    final done = const TrainingService().complete(
      swapped,
      setId,
      metrics({'mass': ('22', 'kg')}),
      acceptSuggested: true,
    );
    equal(done.set(setId).actuals['mass']!.enteredValue, '22');
    // Snapshots round-trip and keep the substitution.
    jsonEqual(
      sessionFromJson(jsonDecode(jsonEncode(done.toJson()))).toJson(),
      done.toJson(),
    );
    // Reverting restores the exact prior planned state of planned sets.
    final reverted = const TrainingService().revertSubstitution(
      swapped,
      slotId: 'bench-heavy',
      scope: 'remaining',
    );
    for (var i = 0; i < reverted.sets.length; i++) {
      jsonEqual(
        reverted.sets[i].suggested.map((k, v) => MapEntry(k, v.toJson())),
        session.sets[i].suggested.map((k, v) => MapEntry(k, v.toJson())),
      );
      equal(reverted.sets[i].substitution, null);
    }
    check(canonicalJson(reverted.toJson()) != original, 'versions advanced');

    TrainingSession sub({
      String scope = 'remaining',
      String? setId,
      SubstituteComposition? composition,
      Map<String, Map<String, Object?>> targets = const {},
    }) => const TrainingService().substitute(
      session,
      slotId: 'bench-heavy',
      scope: scope,
      setId: setId,
      composition: composition ?? _dumbbell,
      targets: targets,
    );
    final slot = session.revision.definition.slot('bench-heavy');
    rejects(
      () => sub(
        composition: SubstituteComposition.fromJson({
          'exercise': slot.exerciseId,
          'implementation': slot.implementation,
          'equipment': ?slot.equipmentId,
          'setupNote': ?slot.setupNote,
        }),
      ),
    );
    rejects(() => sub(scope: 'occurrence'));
    rejects(() => sub(scope: 'remaining', setId: setId));
    rejects(() => sub(scope: 'everything'));
    rejects(
      () => sub(
        targets: {
          'tempo': {'source': 'keep'},
        },
      ),
    );
    rejects(
      () => sub(
        targets: {
          'reps': {'source': 'keep', 'value': _kg('1')},
        },
      ),
    );
    rejects(
      () => sub(
        targets: {
          'mass': {
            'source': 'explicit',
            'value': {'value': '8', 'unit': 'rep'},
          },
        },
      ),
    );
    // Occurrence scope touches exactly one set.
    final one = sub(scope: 'occurrence', setId: setId);
    equal(one.sets.where((s) => s.substitution != null).length, 1);
    // A completed set cannot be substituted.
    rejects(
      () => const TrainingService().substitute(
        done,
        slotId: 'bench-heavy',
        scope: 'occurrence',
        setId: setId,
        composition: _dumbbell,
      ),
    );
  });

  test(
    'substitutes keep their own history, prefill and progression scope',
    () => _withStore((store, dir) async {
      final service = StoredTrainingService(store);
      await service.publish(definition(), 0);
      var s1 = await service.start('s1', 'upper-a', 1, instant(1));
      s1 = await _finishAll(service, s1, 1, heavyMass: '60');

      var s2 = await service.start('s2', 'upper-a', 1, instant(2));
      s2 = await service.substitute(
        's2',
        s2.contentVersion,
        slotId: 'bench-heavy',
        scope: 'remaining',
        composition: _dumbbell,
        targets: {
          'mass': {'source': 'explicit', 'value': _kg('20')},
          'reps': {'source': 'keep'},
        },
      );
      equal(_heavy(s2).first.suggested['mass']!.enteredValue, '20');
      equal(_heavy(s2).first.substitution!.targets['mass']!.source, 'explicit');
      s2 = await _finishAll(service, s2, 2);

      // The original slot never prefills from the substitute.
      final s3 = await service.start('s3', 'upper-a', 1, instant(3));
      equal(_heavy(s3).first.suggested['mass']!.enteredValue, '60');
      equal(_heavy(s3).first.sources['mass']!.sessionId, 's1');
      // A later substitution offers the substitute's own history.
      final s3b = await service.substitute(
        's3',
        s3.contentVersion,
        slotId: 'bench-heavy',
        scope: 'occurrence',
        setId: _heavy(s3).first.id,
        composition: _dumbbell,
      );
      final swapped = _heavy(s3b).first;
      equal(swapped.suggested['mass']!.enteredValue, '20');
      final source = swapped.substitution!.targets['mass']!;
      equal(source.source, 'history');
      equal(source.historySessionId, 's2');
      // Reps defaulted to history too and were found there.
      equal(swapped.substitution!.targets['reps']!.source, 'history');

      // Series keep the substitute in its own context.
      final series = const TrainingAnalytics().series(
        await store.sessions(),
        metric: 'mass',
        context: {'slotId': 'bench-heavy'},
      );
      final rows = [
        for (final r in series['series']! as List)
          jsonObject(jsonObject(r, 'row')['context'], 'context'),
      ];
      jsonEqual([for (final c in rows) c['implementation']]..sort(), [
        'barbell',
        'dumbbell',
      ]);
      check(
        rows.any((c) => c['substituted'] == true),
        'substitute rows are marked',
      );
      final only = const TrainingAnalytics().series(
        await store.sessions(),
        metric: 'mass',
        context: {'substituted': true},
      );
      equal((only['series']! as List).length, 1);
      rejects(
        () => const TrainingAnalytics().series(
          [],
          context: {'substituted': false},
        ),
      );

      // A substituted exposure is not proposed for the original track.
      final progression = StoredProgressionService(store);
      final refused = await _failure(
        () => progression.propose(
          's2',
          'bench-heavy',
          jsonObject(example('double-progression')['rule'], 'rule'),
        ),
      );
      check(refused.message.contains('not an exposure'), refused.message);

      // Reverting is exact and requires substituted planned sets.
      final reverted = await service.revertSubstitution(
        's3',
        s3b.contentVersion,
        slotId: 'bench-heavy',
        scope: 'remaining',
      );
      equal(_heavy(reverted).first.sources['mass']!.sessionId, 's1');
      equal(_heavy(reverted).first.substitution, null);
      equal(
        (await _failure(
          () => service.revertSubstitution(
            's3',
            reverted.contentVersion,
            slotId: 'bench-heavy',
            scope: 'remaining',
          ),
        )).code,
        'validation',
      );
      // Stale versions conflict.
      equal(
        (await _failure(
          () => service.substitute(
            's3',
            1,
            slotId: 'bench-heavy',
            scope: 'remaining',
            composition: _dumbbell,
          ),
        )).code,
        'conflict',
      );
      // Catalog ownership applies to the replacement.
      await CatalogService(
        store,
      ).publishExercise(ExerciseDefinition.fromJson({'id': 'fly'}), 0);
      await CatalogService(store).publishImplementation(
        ExerciseImplementation.fromJson({
          'id': 'dumbbell',
          'exerciseId': 'fly',
        }),
        0,
      );
      final owned = await _failure(
        () => service.substitute(
          's3',
          reverted.contentVersion,
          slotId: 'bench-heavy',
          scope: 'remaining',
          composition: _dumbbell,
        ),
      );
      check(owned.message.contains('belongs to exercise fly'), owned.message);
    }),
  );

  test(
    'substitutions are portable only under v67 formats',
    () => _withStore((store, dir) async {
      final service = StoredTrainingService(store);
      await service.publish(definition(), 0);
      final s = await service.start('s1', 'upper-a', 1, instant(1));
      await service.substitute(
        's1',
        s.contentVersion,
        slotId: 'bench-heavy',
        scope: 'remaining',
        composition: _dumbbell,
        targets: {
          'mass': {'source': 'explicit', 'value': _kg('20')},
        },
      );
      final original = canonicalJson((await store.archive()).toJson());
      equal((await store.backup('$dir/native'))['databaseSchemaVersion'], 69);
      await LogicalArchiveFiles.export(
        await store.archive(),
        '$dir/logical.json',
      );
      final logical = await LogicalArchiveFiles.prepare('$dir/logical.json');
      try {
        await store.restore(
          logical.backup,
          recoveryDestination: '$dir/recovery',
          confirm: true,
        );
      } finally {
        await logical.close();
      }
      await store.close();
      final active = await TrainingStore.open('$dir/db.sqlite');
      try {
        equal(canonicalJson((await active.archive()).toJson()), original);
      } finally {
        await active.close();
      }
      final envelope = jsonObject(
        jsonDecode(await File('$dir/logical.json').readAsString()),
        'logical',
      )..['format'] = 'bodytmi-logical-export/66';
      await File(
        '$dir/old.json',
      ).writeAsString(jsonEncode(await _resign(envelope)));
      final logicalError = await _failure(
        () => LogicalArchiveFiles.prepare('$dir/old.json'),
      );
      check(
        logicalError.message.contains('substitutions require logical v67'),
        logicalError.message,
      );
      final copy = '$dir/relabel.sqlite';
      File('$dir/native/database.sqlite').copySync(copy);
      final db = sqlite3.open(copy);
      db.userVersion = 66;
      db.close();
      final nativeError = await _failure(
        () => NativeBackup.validateDatabase(copy),
      );
      check(
        nativeError.message.contains('substitutions require schema v67'),
        nativeError.message,
      );
    }),
  );

  test(
    'substitution CLI commands substitute, complete and revert',
    () => _withStore((store, dir) async {
      await StoredTrainingService(store).publish(definition(), 0);
      await store.close();
      Future<({int code, String output, String error})> cmd(
        String action,
        Map<String, Object?> input,
      ) => invoke(
        action.split(' '),
        jsonEncode({
          ...input,
          'schemaVersion': 1,
          'database': '$dir/db.sqlite',
        }),
      );
      equal(
        (await cmd('store start', {
          'id': 's1',
          'templateId': 'upper-a',
          'revision': 1,
          'startedAt': '2026-10-01T12:00:00Z',
        })).code,
        0,
      );
      final swapped = await cmd('store substitute', example('substitute-set'));
      equal(swapped.code, 0);
      check(swapped.output.contains('"source":"unresolved"'));
      final stale = await cmd('store substitute', example('substitute-set'));
      equal(stale.code, 5);
      final noMass = await cmd('store complete', {
        'id': 's1',
        'expectedVersion': 2,
        'setId': 'workout/heavy[0]/heavy-set',
        'actuals': <String, Object?>{},
        'acceptSuggested': true,
      });
      equal(noMass.code, 2);
      equal(noMass.output, '');
      final completed = await cmd('store complete', {
        'id': 's1',
        'expectedVersion': 2,
        'setId': 'workout/heavy[0]/heavy-set',
        'actuals': {'mass': _kg('22')},
        'acceptSuggested': true,
      });
      equal(completed.code, 0);
      final reverted = await cmd('store revert-substitution', {
        'id': 's1',
        'expectedVersion': 3,
        'slotId': 'bench-heavy',
        'scope': 'remaining',
      });
      equal(reverted.code, 0);
      final sets =
          jsonObject(
                jsonObject(jsonDecode(reverted.output), 'r')['data'],
                'data',
              )['sets']!
              as List;
      // The completed substitute stays attached to what was performed.
      check(jsonObject(sets.first, 's').containsKey('substitution'));
      check(!jsonObject(sets[1], 's').containsKey('substitution'));
    }),
  );
}
