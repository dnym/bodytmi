import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart' show expectLater, throwsA, isA;
import 'cli_test.dart';
import 'fixtures.dart';
import 'support.dart';

Future<BodyTmiException> failure(Object? Function() action) async {
  try {
    await action();
  } on BodyTmiException catch (error) {
    return error;
  }
  throw StateError('Expected a BodyTmiException.');
}

Future<void> _fails(Future<Object?> Function() action) =>
    expectLater(action(), throwsA(isA<BodyTmiException>()));

WorkoutDefinition _adoptedDefinition() => WorkoutDefinition.fromJson({
  'id': 'catalog-adopt-practice',
  'name': 'Published catalog adoption',
  'slots': [
    {
      'id': 'cable',
      'exercise': 'row',
      'implementation': 'cable-row',
      'equipment': 'practice-cable',
      'targets': {
        'mass': {'value': '25', 'unit': 'kg'},
        'reps': {'value': '10', 'unit': 'rep'},
      },
    },
    {
      'id': 'dumbbell',
      'exercise': 'row',
      'implementation': 'dumbbell',
      'equipment': 'practice-dumbbell',
      'targets': {
        'mass': {'value': '20', 'unit': 'kg'},
        'reps': {'value': '12', 'unit': 'rep'},
      },
    },
  ],
  'plan': {
    'id': 'practice',
    'type': 'sequence',
    'children': [
      {'id': 'cable-set', 'type': 'effort', 'slot': 'cable'},
      {'id': 'dumbbell-set', 'type': 'effort', 'slot': 'dumbbell'},
    ],
  },
});

Map<String, Object?> _crossedDefinition(int revision) => {
  'id': 'crossed-workout',
  'name': 'Crossed ownership',
  'slots': [
    {
      'id': 'cable',
      'exercise': 'squat',
      'implementation': 'cable-row',
      'equipment': 'practice-cable',
      'targets': {
        'mass': {'value': '25', 'unit': 'kg'},
        'reps': {'value': '10', 'unit': 'rep'},
      },
    },
    {
      'id': 'dumbbell',
      'exercise': 'squat',
      'implementation': 'dumbbell',
      'equipment': 'practice-dumbbell',
      'targets': {
        'mass': {'value': '20', 'unit': 'kg'},
        'reps': {'value': '12', 'unit': 'rep'},
      },
    },
  ],
  'plan': {
    'id': 'practice',
    'type': 'sequence',
    'children': [
      {'id': 'cable-set', 'type': 'effort', 'slot': 'cable'},
      {'id': 'dumbbell-set', 'type': 'effort', 'slot': 'dumbbell'},
    ],
  },
};

Future<void> _withAdoptionStore(
  Future<void> Function(TrainingStore, String) action,
) async {
  final dir = await Directory.systemTemp.createTemp('bodytmi-adoption-');
  final store = await TrainingStore.open('${dir.path}/db.sqlite');
  try {
    await action(store, dir.path);
  } finally {
    await store.close();
    await dir.delete(recursive: true);
  }
}

void catalogAdoptionTests() {
  test(
    'slot adoption keeps unmatched implementation shorthand and rejects crossed catalog ownership',
    () {
      final slots = _adoptedDefinition().slots;
      validateCatalogSlotAdoption(slots, const {});
      validateCatalogSlotAdoption(slots, {'other': 'press'});
      BodyTmiException crossedFailure;
      try {
        validateCatalogSlotAdoption(slots, {'cable-row': 'squat'});
        throw StateError('Expected a BodyTmiException.');
      } on BodyTmiException catch (error) {
        crossedFailure = error;
      }
      check(
        crossedFailure.message.contains('belongs to exercise squat, not row'),
        'a matched implementation must belong to the slot exercise',
      );
      validateCatalogSlotAdoption(slots, {'cable-row': 'row'});
      final cable = ImplementationRevision.publish(
        ExerciseImplementation.fromJson({
          'id': 'cable-row',
          'exerciseId': 'row',
        }),
      );
      final dumbbell = ImplementationRevision.publish(
        ExerciseImplementation.fromJson({
          'id': 'dumbbell',
          'exerciseId': 'row',
        }),
      );
      jsonEqual(implementationOwners([cable, dumbbell]), {
        'cable-row': 'row',
        'dumbbell': 'row',
      });
    },
  );
  test(
    'stored publication enforces crossed ownership and optional catalog adoption without disturbing legacy shorthand',
    () => _withAdoptionStore((store, dir) async {
      final training = StoredTrainingService(store);
      final first = await training.publish(_adoptedDefinition(), 0);
      equal(first.number, 1);
      await training.publish(definition(), 0);
      final catalog = CatalogService(store);
      await catalog.publishExercise(
        ExerciseDefinition.fromJson({'id': 'row', 'name': 'Row'}),
        0,
      );
      await catalog.publishImplementation(
        ExerciseImplementation.fromJson({
          'id': 'cable-row',
          'exerciseId': 'row',
        }),
        0,
      );
      final crossed = await failure(
        () async => training.publish(
          WorkoutDefinition.fromJson(_crossedDefinition(0)),
          0,
        ),
      );
      equal(crossed.code, 'validation');
      check(
        crossed.message.contains('belongs to exercise row, not squat'),
        'crossed ownership names both identities',
      );
      equal((await store.revision('catalog-adopt-practice'))!.number, 1);
      equal((await store.revision('crossed-workout')), null);
      final early = await failure(
        () async =>
            training.publish(_adoptedDefinition(), 1, requireCatalog: true),
      );
      equal(early.code, 'not_found');
      check(
        early.message.contains(
          'Slot implementation dumbbell is not a published implementation',
        ),
        'full adoption names the missing implementation',
      );
      equal((await store.revision('catalog-adopt-practice'))!.number, 1);
      await catalog.publishImplementation(
        ExerciseImplementation.fromJson({
          'id': 'dumbbell',
          'exerciseId': 'row',
        }),
        0,
      );
      final adopted = await training.publish(
        _adoptedDefinition(),
        1,
        requireCatalog: true,
      );
      equal(adopted.number, 2);
      await _fails(() => training.publish(_adoptedDefinition(), 1));
      final legacy = await training.publish(_adoptedDefinition(), 2);
      equal(legacy.number, 3);
      final strict = await training.publish(
        _adoptedDefinition(),
        3,
        requireCatalog: true,
      );
      equal(strict.number, 4);
      final strictJson = copyJson(strict.toJson());
      strictJson['revision'] = 3;
      equal(canonicalJson(legacy.toJson()), canonicalJson(strictJson));
    }),
  );
  test(
    'family publication optionally demands published catalog members and default membership stays descriptive',
    () => _withAdoptionStore((store, dir) async {
      final families = FamilyService(store);
      final catalog = CatalogService(store);
      await families.publish(
        ExerciseFamily.fromJson({
          'id': 'pulls',
          'name': 'Pulls',
          'exercises': ['row', 'hang'],
        }),
        0,
      );
      final missing = await failure(
        () async => families.publish(
          ExerciseFamily.fromJson({
            'id': 'pulls',
            'name': 'Pulls',
            'exercises': ['row'],
          }),
          1,
          requireCatalog: true,
        ),
      );
      equal(missing.code, 'not_found');
      check(
        missing.message.contains(
          'Family member row is not a published catalog exercise',
        ),
        'the missing member is named',
      );
      equal((await families.revision('pulls')).number, 1);
      await catalog.publishExercise(
        ExerciseDefinition.fromJson({'id': 'row'}),
        0,
      );
      final adopted = await families.publish(
        ExerciseFamily.fromJson({
          'id': 'pulls',
          'name': 'Pulls',
          'exercises': ['row'],
        }),
        1,
        requireCatalog: true,
      );
      equal(adopted.number, 2);
      equal((await families.revision('pulls')).number, 2);
    }),
  );
  test(
    'archives and native backups reject published workout slots crossing catalog ownership',
    () => _withAdoptionStore((store, dir) async {
      final training = StoredTrainingService(store);
      await training.publish(_adoptedDefinition(), 0);
      final catalog = CatalogService(store);
      await catalog.publishExercise(
        ExerciseDefinition.fromJson({'id': 'row'}),
        0,
      );
      await catalog.publishExercise(
        ExerciseDefinition.fromJson({'id': 'squat'}),
        0,
      );
      await catalog.publishImplementation(
        ExerciseImplementation.fromJson({
          'id': 'cable-row',
          'exerciseId': 'row',
        }),
        0,
      );
      await catalog.publishImplementation(
        ExerciseImplementation.fromJson({
          'id': 'dumbbell',
          'exerciseId': 'row',
        }),
        0,
      );
      await catalog.publishImplementation(
        ExerciseImplementation.fromJson({
          'id': 'dumbbell',
          'exerciseId': 'row',
          'name': 'Single-arm',
        }),
        1,
      );
      final base = (await store.archive()).toJson();
      final crossed = copyJson(base);
      jsonObject(
        jsonObject(
          jsonList(crossed, 'implementations').first as Map<String, Object?>,
          'implementation revision',
        )['implementation'],
        'implementation',
      )['exerciseId'] = 'squat';
      final crossedError = await failure(
        () => TrainingArchive.fromJson(crossed),
      );
      check(
        crossedError.message.contains('belongs to exercise squat, not row'),
        'archive validation cross-checks every published slot: $crossedError',
      );
      final slotMoved = copyJson(base);
      final revisionJson = jsonObject(
        jsonList(slotMoved, 'revisions').first as Map<String, Object?>,
        'workout revision',
      );
      jsonObject(
        jsonList(
              jsonObject(revisionJson['definition'], 'workout definition'),
              'slots',
            ).first
            as Map<String, Object?>,
        'slot',
      )['exercise'] = 'squat';
      final slotError = await failure(
        () => TrainingArchive.fromJson(slotMoved),
      );
      check(
        slotError.message.contains('belongs to exercise row, not squat'),
        'a moved slot exercise against a owned implementation conflicts',
      );
      await store.backup('$dir/native');
      final db = sqlite3.open('$dir/native/database.sqlite');
      db.execute(
        "UPDATE implementation_revisions SET snapshot = replace("
        "snapshot, '\"exerciseId\":\"row\"', '\"exerciseId\":\"squat\"') "
        "WHERE implementation_id = 'cable-row' AND number = 1",
      );
      db.close();
      final native = await failure(
        () => NativeBackup.validateDatabase('$dir/native/database.sqlite'),
      );
      check(
        native.message.contains('belongs to exercise squat, not row'),
        'native verification cross-checks pinned slots: $native',
      );
    }),
  );
  test(
    'adoption CLI reports stable exit codes and portability round-trips an adopted profile',
    () => _withAdoptionStore((store, dir) async {
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

      Future<int> attempt(String action, Map<String, Object?> input) async =>
          (await invoke(
            action.split(' '),
            jsonEncode({
              'schemaVersion': 1,
              'database': '$dir/db.sqlite',
              ...input,
            }),
          )).code;

      final definition = _adoptedDefinition().toJson();
      equal(
        await attempt('store publish', {
          'definition': definition,
          'expectedRevision': 0,
          'requireCatalog': true,
        }),
        3,
      );
      equal(
        await attempt('store publish', {
          'definition': definition,
          'expectedRevision': 0,
        }),
        0,
      );
      await cmd('exercise publish', {
        'exercise': {'id': 'row', 'name': 'Row'},
        'expectedRevision': 0,
      });
      await cmd('implementation publish', {
        'implementation': {'id': 'cable-row', 'exerciseId': 'row'},
        'expectedRevision': 0,
      });
      equal(
        await attempt('store publish', {
          'definition': _crossedDefinition(0),
          'expectedRevision': 0,
        }),
        2,
      );
      equal(
        await attempt('store publish', {
          'definition': definition,
          'expectedRevision': 1,
          'requireCatalog': 'yes',
        }),
        2,
      );
      await cmd('implementation publish', {
        'implementation': {'id': 'dumbbell', 'exerciseId': 'row'},
        'expectedRevision': 0,
      });
      await cmd('store publish', {
        'definition': definition,
        'expectedRevision': 1,
        'requireCatalog': true,
      });
      final reopened = await TrainingStore.open('$dir/db.sqlite');
      String expected;
      try {
        equal((await reopened.revision('catalog-adopt-practice'))!.number, 2);
        equal((await reopened.revision('crossed-workout')), null);
        expected = canonicalJson((await reopened.archive()).toJson());
        equal(
          (await reopened.backup('$dir/native'))['databaseSchemaVersion'],
          60,
        );
        equal(
          (await LogicalArchiveFiles.export(
            await reopened.archive(),
            '$dir/logical.json',
          ))['format'],
          'bodytmi-logical-export/60',
        );
        equal(NativeBackup.validateDatabase('$dir/native/database.sqlite'), 60);
        final logical = await LogicalArchiveFiles.prepare('$dir/logical.json');
        try {
          equal(logical.archive.implementations.length, 2);
          await reopened.restore(
            logical.backup,
            recoveryDestination: '$dir/recovery',
            confirm: true,
          );
        } finally {
          await logical.close();
        }
      } finally {
        await reopened.close();
      }
      final restored = await TrainingStore.open('$dir/db.sqlite');
      try {
        equal(canonicalJson((await restored.archive()).toJson()), expected);
        equal((await restored.implementationRevisions()).length, 2);
        equal((await restored.revision('catalog-adopt-practice'))!.number, 2);
        await StoredTrainingService(
          restored,
        ).publish(_adoptedDefinition(), 2, requireCatalog: true);
        equal((await restored.revision('catalog-adopt-practice'))!.number, 3);
      } finally {
        await restored.close();
      }
    }),
  );
}
