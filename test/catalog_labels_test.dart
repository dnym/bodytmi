import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'cli_test.dart';
import 'fixtures.dart';
import 'support.dart';

Map<String, Object?> _row() =>
    jsonObject(example('exercise-labels')['exercise'], 'exercise');

List<Map<String, Object?>> _results(Map<String, Object?> search) => [
  for (final r in jsonList(search, 'results')) jsonObject(r, 'result'),
];

void catalogLabelTests() {
  test('catalog labels validate tags, names and aliases', () {
    final row = ExerciseDefinition.fromJson(_row());
    jsonEqual(ExerciseDefinition.fromJson(row.toJson()).toJson(), row.toJson());
    equal(row.labels.display('sv-SE', row.name).name, 'Rodd');
    equal(row.labels.display('sv-SE', row.name).match, 'language');
    equal(row.labels.display('fr', row.name).match, 'root');
    equal(row.labels.display('fr', null).match, 'none');
    // Unlabelled entries keep their old JSON shape.
    check(
      !ExerciseDefinition.fromJson({'id': 'x'}).toJson().containsKey('labels'),
    );
    for (final labels in <Object?>[
      <String, Object?>{},
      {
        'SV': {'name': 'Rodd'},
      },
      {
        'sv_SE': {'name': 'Rodd'},
      },
      {
        'sr-latn': {'name': 'Veslanje'},
      },
      {'sv': <String, Object?>{}},
      {
        'sv': {'name': ' '},
      },
      {
        'sv': {
          'aliases': ['Rodd', ' rodd '],
        },
      },
      {
        'sv': {'name': 'Rodd', 'extra': 1},
      },
      {
        'sv': {'aliases': <Object?>[]},
      },
    ]) {
      rejects(() => ExerciseDefinition.fromJson({..._row(), 'labels': labels}));
    }
    final latn = EquipmentDefinition.fromJson({
      'id': 'bar',
      'labels': {
        'sr-Latn-RS': {'name': 'Šipka'},
      },
    });
    equal(latn.labels.display('sr-Latn-RS', null).name, 'Šipka');
    final implementation = ExerciseImplementation.fromJson({
      'id': 'cable-row',
      'exerciseId': 'row',
      'labels': {
        'sv': {
          'aliases': ['Kabelrodd'],
        },
      },
    });
    equal(implementation.labels.entries['sv']!.aliases.single, 'Kabelrodd');
  });

  test('catalog search ranks matches over the latest revisions', () {
    final first = ExerciseRevision.publish(
      ExerciseDefinition.fromJson({'id': 'row', 'name': 'Row'}),
    );
    final row = ExerciseRevision.publish(
      ExerciseDefinition.fromJson(_row()),
      previous: first,
    );
    final hang = ExerciseRevision.publish(
      ExerciseDefinition.fromJson({
        'id': 'dead-hang',
        'name': 'Dead hang',
        'labels': {
          'sv': {'name': 'Häng'},
        },
      }),
    );
    final cable = ImplementationRevision.publish(
      ExerciseImplementation.fromJson({
        'id': 'cable-row',
        'exerciseId': 'row',
        'name': 'Cable row',
        'labels': {
          'sv': {'name': 'Kabelrodd'},
        },
      }),
    );
    final bar = EquipmentRevision.publish(
      EquipmentDefinition.fromJson({'id': 'barbell', 'name': 'Barbell'}),
    );
    Map<String, Object?> search(
      String query, {
      String? locale,
      List<String> kinds = catalogSearchKinds,
      int limit = 50,
    }) => searchCatalog(
      query: query,
      locale: locale,
      kinds: kinds,
      limit: limit,
      exercises: [first, row, hang],
      implementations: [cable],
      equipment: [bar],
    );

    // Latest revision supplies the labels: revision 1 had none.
    final rodd = _results(search('RODD', locale: 'sv-SE'));
    equal(rodd.length, 2);
    equal(rodd[0]['id'], 'row');
    equal(rodd[0]['revision'], 2);
    equal(rodd[0]['displayName'], 'Rodd');
    equal(rodd[0]['displayLocale'], 'sv');
    jsonEqual(rodd[0]['match'], {
      'rank': 'exact',
      'field': 'label',
      'locale': 'sv',
      'text': 'Rodd',
    });
    equal(rodd[1]['id'], 'cable-row');
    equal(rodd[1]['exerciseId'], 'row');
    equal(jsonObject(rodd[1]['match'], 'm')['rank'], 'substring');
    // Aliases and word prefixes match; another locale's labels do not.
    equal(
      jsonObject(
        _results(search('hantel', locale: 'sv'))[0]['match'],
        'm',
      )['field'],
      'alias',
    );
    equal(_results(search('rudern', locale: 'sv')).length, 0);
    equal(_results(search('rudern'))[0]['displayName'], 'Row');
    equal(
      jsonObject(_results(search('hang'))[0]['match'], 'm')['rank'],
      'word-prefix',
    );
    // No accent folding: ä is its own letter.
    equal(_results(search('hang', locale: 'sv'))[0]['displayName'], 'Häng');
    equal(_results(search('häng'))[0]['id'], 'dead-hang');
    equal(_results(search('hong')).length, 0);
    // Kinds and limit.
    equal(_results(search('row', kinds: ['equipment'])).length, 0);
    final limited = search('r', limit: 1);
    equal(limited['truncated'], true);
    equal(_results(limited).length, 1);
    for (final bad in [
      () => search(' '),
      () => search('row', locale: 'sv_SE'),
      () => search('row', kinds: ['gym']),
      () => search('row', kinds: []),
      () => search('row', limit: 0),
    ]) {
      rejects(bad);
    }
  });

  test('CLI catalog search reads stored labelled revisions', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-labels-');
    try {
      final database = '${dir.path}/db.sqlite';
      Future<({int code, String output, String error})> cmd(
        String action,
        Map<String, Object?> input,
      ) => invoke(
        action.split(' '),
        jsonEncode({'schemaVersion': 1, 'database': database, ...input}),
      );
      final published = await cmd('exercise publish', {
        'exercise': _row(),
        'expectedRevision': 0,
      });
      check(published.code == 0, published.error);
      final shown = await cmd('exercise show', {'exerciseId': 'row'});
      check(shown.output.contains('Skivstångsrodd'), shown.output);
      final found = await cmd('catalog search', {
        ...example('catalog-search'),
        'database': database,
      });
      check(found.code == 0, found.error);
      final data = jsonObject(
        jsonObject(jsonDecode(found.output), 'r')['data'],
        'data',
      );
      equal(data['policy'], 'bodytmi-catalog-search/1');
      equal(_results(data).single['displayName'], 'Rodd');
      equal(
        (await cmd('catalog search', {'query': 'row', 'locale': 'sv_SE'})).code,
        2,
      );
      equal(
        (await cmd('catalog search', {'query': 'row', 'extra': 1})).code,
        2,
      );
      // Labels travel with the logical export.
      final store = await TrainingStore.open(database);
      try {
        final archive = await store.archive();
        equal(archive.exercises.single.exercise.labels.entries.length, 2);
        await LogicalArchiveFiles.export(archive, '${dir.path}/l.json');
        final prepared = await LogicalArchiveFiles.prepare(
          '${dir.path}/l.json',
        );
        await prepared.close();
      } finally {
        await store.close();
      }
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
