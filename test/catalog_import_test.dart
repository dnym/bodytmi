import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'cli_test.dart';
import 'support.dart';

Map<String, Object?> _starter() => jsonObject(
  jsonDecode(File('data/starter-catalog.json').readAsStringSync()),
  'catalog',
);

Future<BodyTmiException> _failure(Future<Object?> Function() action) async {
  try {
    await action();
  } on BodyTmiException catch (error) {
    return error;
  }
  throw StateError('Expected a BodyTmiException.');
}

/// The starter catalog is an ordinary catalog import: previewed, applied
/// atomically and idempotently, never deleting anything.
void catalogImportTests() {
  test('the starter catalog validates and names its source', () {
    final document = CatalogImportDocument.fromJson(_starter());
    equal(document.sourceName, 'BodyTMI starter catalog');
    check(document.exercises.length >= 10, 'exercises');
    check(
      document.equipment.any((e) => e.id == 'barbell' && e.interchangeable),
      'barbells are interchangeable',
    );
    check(
      document.equipment.any(
        (e) => e.id == 'leg-press-machine' && !e.interchangeable,
      ),
      'machines are not',
    );
    // Every implementation names an exercise of the same file.
    final exercises = {for (final e in document.exercises) e.id};
    check(
      document.implementations.every((i) => exercises.contains(i.exerciseId)),
      'implementation owners are in the catalog',
    );
    rejects(
      () =>
          CatalogImportDocument.fromJson({..._starter(), 'format': 'other/1'}),
    );
    rejects(
      () => CatalogImportDocument.fromJson({
        'format': CatalogImportDocument.format,
        'source': {'name': 'Empty'},
      }),
    );
    rejects(
      () => CatalogImportDocument.fromJson({
        'format': CatalogImportDocument.format,
        'source': {'name': 'Twice'},
        'exercises': [
          {'id': 'x'},
          {'id': 'x'},
        ],
      }),
    );
  });

  test('catalog imports apply atomically and idempotently', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-catalog-imp-');
    final store = await TrainingStore.open('${dir.path}/db.sqlite');
    try {
      final imports = CatalogImportService(store);
      final starter = CatalogImportDocument.fromJson(_starter());
      final preview = await imports.preview(starter);
      final total =
          starter.exercises.length +
          starter.implementations.length +
          starter.equipment.length +
          starter.blueprints.length;
      equal(jsonObject(preview['counts'], 'c')['new'], total);
      equal((await store.exerciseRevisions()).isEmpty, true);
      equal(
        (await _failure(
          () => imports.apply(starter, onChanged: 'reject', confirm: false),
        )).code,
        'validation',
      );
      final applied = await imports.apply(
        starter,
        onChanged: 'reject',
        confirm: true,
      );
      equal(applied['applied'], true);
      equal((await store.exerciseRevisions()).length, starter.exercises.length);
      equal((await store.blueprintRevisions()).length, 2);
      // Applying again changes nothing.
      final again = await imports.apply(
        starter,
        onChanged: 'reject',
        confirm: true,
      );
      equal(jsonObject(again['counts'], 'c')['unchanged'], total);
      equal((await store.exerciseRevisions()).length, starter.exercises.length);

      // A changed entry is refused as a whole, even beside a new one.
      final edited = _starter();
      final exercises = jsonList(edited, 'exercises');
      edited['exercises'] = [
        {...jsonObject(exercises.first, 'e'), 'name': 'Renamed'},
        ...exercises.skip(1),
        {'id': 'new-lift', 'name': 'New lift'},
      ];
      final changed = CatalogImportDocument.fromJson(edited);
      final refused = await _failure(
        () => imports.apply(changed, onChanged: 'reject', confirm: true),
      );
      equal(refused.code, 'conflict');
      check(refused.message.contains('exercise squat'), refused.message);
      equal(
        (await store.exerciseRevisions()).any(
          (r) => r.exercise.id == 'new-lift',
        ),
        false,
      );
      await imports.apply(changed, onChanged: 'update', confirm: true);
      equal((await CatalogService(store).exerciseRevision('squat')).number, 2);
      // Entries missing from a later file are never deleted.
      await imports.apply(
        CatalogImportDocument.fromJson({
          'format': CatalogImportDocument.format,
          'source': {'name': 'Mine'},
          'exercises': [
            {'id': 'my-lift'},
          ],
        }),
        onChanged: 'reject',
        confirm: true,
      );
      equal(
        (await store.exerciseRevisions()).any((r) => r.exercise.id == 'squat'),
        true,
      );
      // An implementation whose exercise is missing writes nothing.
      final orphan = await _failure(
        () => imports.apply(
          CatalogImportDocument.fromJson({
            'format': CatalogImportDocument.format,
            'source': {'name': 'Orphan'},
            'equipment': [
              {'id': 'rings'},
            ],
            'implementations': [
              {'id': 'ring-dip', 'exerciseId': 'ring-work'},
            ],
          }),
          onChanged: 'reject',
          confirm: true,
        ),
      );
      equal(orphan.code, 'not_found');
      equal(
        (await store.equipmentRevisions()).any(
          (r) => r.equipment.id == 'rings',
        ),
        false,
      );

      // Swedish labels are searchable, and catalog ids adopt cleanly.
      final hits = searchCatalog(
        query: 'knäböj',
        locale: 'sv',
        exercises: await store.exerciseRevisions(),
        implementations: await store.implementationRevisions(),
        equipment: await store.equipmentRevisions(),
      );
      check(
        jsonList(
          hits,
          'results',
        ).any((r) => jsonObject(r, 'r')['id'] == 'squat'),
        'squat found by its Swedish name',
      );
      await StoredTrainingService(store).publish(
        WorkoutDefinition.fromJson({
          'id': 'catalog-day',
          'name': 'Catalog day',
          'slots': [
            {
              'id': 'squat',
              'exercise': 'squat',
              'implementation': 'barbell-back-squat',
              'equipment': 'barbell',
              'targets': {
                'mass': {'value': '60', 'unit': 'kg'},
              },
            },
          ],
          'plan': {'id': 'w', 'type': 'effort', 'slot': 'squat'},
        }),
        0,
        requireCatalog: true,
      );
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });

  test('CLI catalog validate, preview and apply', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-catalog-cli-');
    final db = '${dir.path}/db.sqlite';
    Future<int> cli(String name, Map<String, Object?> fields) async =>
        (await invoke(
          name.split(' '),
          jsonEncode({'schemaVersion': 1, ...fields}),
        )).code;
    try {
      equal(await cli('catalog validate', {'document': _starter()}), 0);
      equal(
        await cli('catalog validate', {
          'document': {..._starter(), 'format': 'x'},
        }),
        2,
      );
      equal(
        await cli('catalog preview', {'database': db, 'document': _starter()}),
        0,
      );
      equal(
        await cli('catalog apply', {'database': db, 'document': _starter()}),
        2,
      );
      equal(
        await cli('catalog apply', {
          'database': db,
          'document': _starter(),
          'confirm': true,
        }),
        0,
      );
      final edited = _starter();
      edited['equipment'] = [
        {'id': 'barbell', 'name': 'Bar'},
      ];
      edited.remove('exercises');
      edited.remove('implementations');
      edited.remove('blueprints');
      equal(
        await cli('catalog apply', {
          'database': db,
          'document': edited,
          'confirm': true,
        }),
        5,
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
