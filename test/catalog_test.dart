import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart' show expectLater, throwsA, isA;
import 'cli_test.dart';
import 'fixtures.dart';
import 'support.dart';

ExerciseDefinition _exercise(String id, {String? name, String? notes}) =>
    ExerciseDefinition.fromJson({
      'id': id,
      if (name != null) 'name': name,
      if (notes != null) 'notes': notes,
    });

ExerciseImplementation _implementation(
  String id,
  String exerciseId, {
  String? name,
}) => ExerciseImplementation.fromJson({
  'id': id,
  'exerciseId': exerciseId,
  if (name != null) 'name': name,
});

Future<void> _withStore(
  Future<void> Function(TrainingStore, String) action,
) async {
  final dir = await Directory.systemTemp.createTemp('bodytmi-catalog-');
  final store = await TrainingStore.open('${dir.path}/db.sqlite');
  try {
    final training = StoredTrainingService(store);
    await training.publish(definition(), 0);
    final s = await training.start('session', 'upper-a', 1, instant(1));
    await training.edit(s.id, s.contentVersion, (s) {
      for (final set in s.sets)
        s = const TrainingService().complete(
          s,
          set.id,
          {},
          acceptSuggested: true,
        );
      return s.finish(instant(2));
    });
    await action(store, dir.path);
  } finally {
    await store.close();
    await dir.delete(recursive: true);
  }
}

Future<void> _fails(Future<Object?> action) =>
    expectLater(action, throwsA(isA<BodyTmiException>()));

void catalogTests() {
  test(
    'catalog definitions validate bounded descriptive fields and revisions retain identities',
    () {
      final exercise = _exercise('row', name: 'Row', notes: 'Three variants.');
      equal(exercise.id, 'row');
      equal(
        canonicalJson(exercise.toJson()),
        canonicalJson({'id': 'row', 'name': 'Row', 'notes': 'Three variants.'}),
      );
      equal(_exercise('bare').toJson().containsKey('name'), false);
      rejects(() => _exercise('bad', name: ' '));
      rejects(() => _exercise('bad', name: 'x' * 201));
      rejects(() => _exercise('bad', notes: 'x' * 4001));
      rejects(() => ExerciseDefinition.fromJson({'id': 'x', 'extra': 1}));
      final first = ExerciseRevision.publish(exercise);
      final next = ExerciseRevision.publish(
        _exercise('row', name: 'Rowing'),
        previous: first,
      );
      equal(next.number, 2);
      equal(first.exercise.name, 'Row');
      rejects(
        () => ExerciseRevision.publish(_exercise('other'), previous: first),
      );
      rejects(() => validateExerciseRevisions([first, first]));
      rejects(() => validateExerciseRevisions([next]));
      final implementation = _implementation('cable-row', 'row', name: 'Cable');
      equal(implementation.exerciseId, 'row');
      equal(
        ExerciseImplementation.fromJson(implementation.toJson()).notes,
        null,
      );
      rejects(() => _implementation('bad', ' '));
      rejects(() => _implementation('bad', 'row', name: 'x' * 201));
      rejects(() => ExerciseImplementation.fromJson({'id': 'bad'}));
      final implementationFirst = ImplementationRevision.publish(
        implementation,
      );
      final implementationNext = ImplementationRevision.publish(
        _implementation('cable-row', 'row', name: 'Seated cable'),
        previous: implementationFirst,
      );
      equal(implementationNext.number, 2);
      rejects(
        () => ImplementationRevision.publish(
          _implementation('other', 'row'),
          previous: implementationFirst,
        ),
      );
      rejects(
        () => ImplementationRevision.publish(
          _implementation('cable-row', 'other'),
          previous: implementationFirst,
        ),
      );
      rejects(
        () => validateImplementationRevisions([implementationFirst], const []),
      );
      rejects(
        () => validateImplementationRevisions(
          [
            implementationFirst,
            ImplementationRevision.publish(_implementation('cable-row', 'row')),
          ],
          [first],
        ),
      );
      rejects(
        () => validateImplementationRevisions([
          implementationFirst,
          implementationNext,
        ], const []),
      );
      validateImplementationRevisions([implementationFirst], [first]);
    },
  );
  test(
    'durable catalog publication is compare-and-set, requires a published exercise and leaves sessions untouched',
    () => _withStore((store, dir) async {
      equal((await store.exerciseRevisions()).length, 0);
      final before = canonicalJson((await store.session('session'))!.toJson());
      final service = CatalogService(store);
      await _fails(
        service.publishImplementation(_implementation('cable-row', 'row'), 0),
      );
      final first = await service.publishExercise(
        _exercise('row', name: 'Row'),
        0,
      );
      equal(first.number, 1);
      await _fails(service.publishExercise(_exercise('row', name: 'Rows'), 0));
      final second = await service.publishExercise(
        _exercise('row', name: 'Rows'),
        1,
      );
      equal(second.number, 2);
      equal((await service.exerciseRevision('row')).number, 2);
      equal((await service.exerciseRevision('row', 1)).number, 1);
      await _fails(service.exerciseRevision('missing'));
      final cable = await service.publishImplementation(
        _implementation('cable-row', 'row', name: 'Cable'),
        0,
      );
      equal(cable.number, 1);
      await service.publishImplementation(
        _implementation('cable-row', 'row', name: 'Seated cable'),
        1,
      );
      await service.publishImplementation(
        _implementation('barbell-row', 'row'),
        0,
      );
      await _fails(
        service.publishImplementation(_implementation('hang', 'hang'), 0),
      );
      equal((await store.implementationRevisions()).length, 3);
      equal((await store.exerciseRevisions()).length, 2);
      equal(
        (await service.implementationRevision('cable-row')).implementation.name,
        'Seated cable',
      );
      await _fails(service.implementationRevision('cable-row', 3));
      equal(canonicalJson((await store.session('session'))!.toJson()), before);
      await store.archive();
    }),
  );
  test(
    'catalog archives reject duplicate/gapped revisions, exercise changes and missing exercise references',
    () => _withStore((store, dir) async {
      final service = CatalogService(store);
      await service.publishExercise(_exercise('row', name: 'Row'), 0);
      await service.publishExercise(_exercise('hang'), 0);
      await service.publishImplementation(
        _implementation('cable-row', 'row'),
        0,
      );
      final base = (await store.archive()).toJson();
      final duplicate = copyJson(base);
      jsonList(
        duplicate,
        'exercises',
      ).add(jsonList(duplicate, 'exercises').first);
      rejects(() => TrainingArchive.fromJson(duplicate));
      final gap = copyJson(base);
      jsonObject(
        jsonList(gap, 'exercises').first,
        'exercise revision',
      )['revision'] = 2;
      rejects(() => TrainingArchive.fromJson(gap));
      final orphan = copyJson(base);
      jsonObject(
        jsonList(orphan, 'implementations').single,
        'implementation',
      )['exerciseId'] = 'missing';
      rejects(() => TrainingArchive.fromJson(orphan));
      final exerciseChange = copyJson(base);
      final moved = copyJson(
        jsonObject(
          jsonList(exerciseChange, 'implementations').single,
          'implementation revision',
        ),
      );
      moved['revision'] = 2;
      jsonObject(moved, 'implementation')['exerciseId'] = 'hang';
      jsonList(exerciseChange, 'implementations').add(moved);
      rejects(() => TrainingArchive.fromJson(exerciseChange));
      await store.backup('$dir/native');
      final db = sqlite3.open('$dir/native/database.sqlite');
      db.execute(
        "UPDATE implementation_revisions SET implementation_id = 'forged'",
      );
      db.close();
      rejects(
        () => NativeBackup.validateDatabase('$dir/native/database.sqlite'),
      );
    }),
  );
  test(
    'v57 profiles migrate without catalog tables and v58 portability preserves every published revision',
    () => _withStore((store, dir) async {
      final original = canonicalJson((await store.archive()).toJson());
      await store.backup('$dir/old');
      final old = sqlite3.open('$dir/old/database.sqlite');
      old.execute('DROP TABLE exercise_revisions');
      old.execute('DROP TABLE implementation_revisions');
      old.execute('DROP TABLE equipment_revisions');
      old.execute('DROP TABLE gym_revisions');
      old.execute('DROP TABLE equipment_instance_revisions');
      old.userVersion = 57;
      old.close();
      equal(NativeBackup.validateDatabase('$dir/old/database.sqlite'), 57);
      await LogicalArchiveFiles.export(await store.archive(), '$dir/old.json');
      final legacy = jsonObject(
        jsonDecode(await File('$dir/old.json').readAsString()),
        'logical',
      );
      legacy['format'] = 'bodytmi-logical-export/57';
      jsonObject(legacy['data'], 'data').remove('exercises');
      jsonObject(legacy['data'], 'data').remove('implementations');
      legacy.remove('sha256');
      legacy['sha256'] = sha256
          .convert(utf8.encode(canonicalJson(legacy)))
          .toString();
      await File('$dir/old.json').writeAsString(jsonEncode(legacy));
      final prepared = await LogicalArchiveFiles.prepare('$dir/old.json');
      try {
        equal(prepared.archive.exercises.length, 0);
        equal(prepared.archive.implementations.length, 0);
      } finally {
        await prepared.close();
      }
      await store.close();
      final migrated = await TrainingStore.open('$dir/old/database.sqlite');
      try {
        equal(canonicalJson((await migrated.archive()).toJson()), original);
        equal(
          (await migrated.backup('$dir/upgraded'))['databaseSchemaVersion'],
          61,
        );
        equal((await migrated.exerciseRevisions()).length, 0);
      } finally {
        await migrated.close();
      }
      var active = await TrainingStore.open('$dir/db.sqlite');
      try {
        final service = CatalogService(active);
        await service.publishExercise(_exercise('row', name: 'Row'), 0);
        await service.publishExercise(_exercise('row', name: 'Barbell row'), 1);
        await service.publishExercise(
          _exercise('hang', name: 'Hang', notes: 'Optional.'),
          0,
        );
        await service.publishImplementation(
          _implementation('cable-row', 'row', name: 'Cable'),
          0,
        );
        await service.publishImplementation(
          _implementation('barbell-row', 'row', name: 'Barbell'),
          0,
        );
        await service.publishImplementation(
          _implementation('dumbbell-row', 'row', name: 'Dumbbell'),
          0,
        );
        final expected = canonicalJson((await active.archive()).toJson());
        await active.backup('$dir/native');
        equal(
          (await LogicalArchiveFiles.export(
            await active.archive(),
            '$dir/logical.json',
          ))['format'],
          'bodytmi-logical-export/61',
        );
        final logical = await LogicalArchiveFiles.prepare('$dir/logical.json');
        try {
          equal(logical.archive.exercises.length, 3);
          equal(logical.archive.implementations.length, 3);
          await active.restore(
            logical.backup,
            recoveryDestination: '$dir/recovery',
            confirm: true,
          );
        } finally {
          await logical.close();
          await active.close();
        }
        active = await TrainingStore.open('$dir/db.sqlite');
        equal(canonicalJson((await active.archive()).toJson()), expected);
        final native = await NativeBackup.prepare('$dir/native');
        try {
          await active.restore(
            native,
            recoveryDestination: '$dir/recovery2',
            confirm: true,
          );
        } finally {
          await native.close();
          await active.close();
        }
        active = await TrainingStore.open('$dir/db.sqlite');
        equal(canonicalJson((await active.archive()).toJson()), expected);
        equal(
          (await CatalogService(
            active,
          ).exerciseRevision('row', 1)).exercise.name,
          'Row',
        );
      } finally {
        await active.close();
      }
      final mislabeled = jsonObject(
        jsonDecode(await File('$dir/logical.json').readAsString()),
        'logical',
      );
      mislabeled['format'] = 'bodytmi-logical-export/57';
      mislabeled.remove('sha256');
      mislabeled['sha256'] = sha256
          .convert(utf8.encode(canonicalJson(mislabeled)))
          .toString();
      await File('$dir/logical.json').writeAsString(jsonEncode(mislabeled));
      final oldLabel = await failure(
        () => LogicalArchiveFiles.prepare('$dir/logical.json'),
      );
      check(
        oldLabel.message.contains('Unknown fields: exercises'),
        'old logical labels reject catalog sections',
      );
      final missing = jsonObject(
        jsonDecode(await File('$dir/old.json').readAsString()),
        'logical',
      );
      File('$dir/old.json').writeAsString(jsonEncode(missing));
      final current = jsonObject(
        jsonDecode(await File('$dir/old.json').readAsString()),
        'logical',
      );
      current['format'] = 'bodytmi-logical-export/60';
      jsonObject(current['data'], 'data').remove('exercises');
      current.remove('sha256');
      current['sha256'] = sha256
          .convert(utf8.encode(canonicalJson(current)))
          .toString();
      await File('$dir/old.json').writeAsString(jsonEncode(current));
      final required = await failure(
        () => LogicalArchiveFiles.prepare('$dir/old.json'),
      );
      check(
        required.message.contains('requires exercise revisions'),
        'the v58 format requires the catalog section',
      );
      final labeled = sqlite3.open('$dir/native/database.sqlite');
      labeled.userVersion = 57;
      labeled.close();
      final nativeError = await failure(
        () => NativeBackup.validateDatabase('$dir/native/database.sqlite'),
      );
      check(
        nativeError.message.contains('does not match supported schema'),
        'a v58 profile cannot claim the older schema label',
      );
    }),
  );
  test(
    'exercise and implementation CLI authoring reports revisions and rejects invalid input with stable exit codes',
    () => _withStore((store, dir) async {
      final original = (await store.session('session'))!;
      await store.close();
      Future<Object?> cmd(String action, Map<String, Object?> input) async {
        final r = await invoke(
          action.split(' '),
          jsonEncode({
            'schemaVersion': 1,
            'database': '$dir/db.sqlite',
            ...input,
          }),
        );
        equal(r.code, 0);
        equal(r.error, '');
        return jsonObject(jsonDecode(r.output), 'response')['data'];
      }

      final first = jsonObject(
        jsonObject(
          await cmd('exercise publish', {
            'exercise': _exercise('row', name: 'Row').toJson(),
            'expectedRevision': 0,
          }),
          'exercise revision',
        )['exercise'],
        'exercise',
      );
      equal(first['name'], 'Row');
      await cmd('exercise publish', {
        'exercise': _exercise('row', name: 'Barbell row').toJson(),
        'expectedRevision': 1,
      });
      jsonEqual(
        await cmd('exercise show', {'exerciseId': 'row', 'revision': 1}),
        {'schemaVersion': 1, 'revision': 1, 'exercise': first},
      );
      equal((await cmd('exercise list', {}) as List<Object?>).length, 2);
      final implementation = jsonObject(
        jsonObject(
          await cmd('implementation publish', {
            'implementation': _implementation(
              'cable-row',
              'row',
              name: 'Cable',
            ).toJson(),
            'expectedRevision': 0,
          }),
          'implementation revision',
        )['implementation'],
        'implementation',
      );
      equal(implementation['exerciseId'], 'row');
      equal((await cmd('implementation list', {}) as List<Object?>).length, 1);
      jsonEqual(
        await cmd('implementation show', {'implementationId': 'cable-row'}),
        {'schemaVersion': 1, 'revision': 1, 'implementation': implementation},
      );
      final missingFields = await invoke([
        'exercise',
        'publish',
      ], jsonEncode({'schemaVersion': 1, 'database': '$dir/db.sqlite'}));
      equal(missingFields.code, 2);
      equal(missingFields.output, '');
      final unknown = await invoke(
        ['exercise', 'show'],
        jsonEncode({
          'schemaVersion': 1,
          'database': '$dir/db.sqlite',
          'exerciseId': 'missing',
        }),
      );
      equal(unknown.code, 3);
      final stale = await invoke(
        ['exercise', 'publish'],
        jsonEncode({
          'schemaVersion': 1,
          'database': '$dir/db.sqlite',
          'exercise': _exercise('row', name: 'Other').toJson(),
          'expectedRevision': 0,
        }),
      );
      equal(stale.code, 5);
      final orphan = await invoke(
        ['implementation', 'publish'],
        jsonEncode({
          'schemaVersion': 1,
          'database': '$dir/db.sqlite',
          'implementation': _implementation('hang', 'unpublished').toJson(),
          'expectedRevision': 0,
        }),
      );
      equal(orphan.code, 3);
      equal(
        jsonObject(
          await cmd('store show', {'id': 'session'}),
          'session',
        )['contentVersion'],
        original.contentVersion,
      );
    }),
  );
  test(
    'process death rolls exercise publication back or commits a complete immutable revision',
    () => _withStore((store, dir) async {
      await store.close();
      final binary = await compileNative(
        'test/helpers/store_owner.dart',
        '$dir/owner',
      );
      for (final mode in ['exercise-rollback', 'exercise-commit']) {
        final child = await Process.start(binary, ['$dir/db.sqlite', mode]);
        final errors = child.stderr.transform(utf8.decoder).join();
        try {
          equal(
            await child.stdout
                .transform(utf8.decoder)
                .transform(const LineSplitter())
                .first
                .timeout(const Duration(seconds: 15)),
            'ready',
          );
          child.kill(ProcessSignal.sigkill);
          await child.exitCode;
          equal(await errors, '');
        } finally {
          child.kill(ProcessSignal.sigkill);
          await child.exitCode;
        }
        final recovered = await TrainingStore.open('$dir/db.sqlite');
        try {
          final committed = mode.endsWith('commit');
          equal(
            (await recovered.exerciseRevisions()).length,
            committed ? 1 : 0,
          );
          if (committed) {
            equal(
              (await CatalogService(
                recovered,
              ).exerciseRevision('row')).exercise.name,
              'Row',
            );
            await _fails(
              CatalogService(
                recovered,
              ).publishExercise(_exercise('row', name: 'Changed'), 0),
            );
          }
          await recovered.archive();
        } finally {
          await recovered.close();
        }
      }
    }),
  );
}

Future<BodyTmiException> failure(Object? Function() action) async {
  try {
    await action();
  } on BodyTmiException catch (error) {
    return error;
  }
  throw StateError('Expected a failure.');
}
