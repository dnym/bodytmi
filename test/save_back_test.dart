import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'cli_test.dart';
import 'fixtures.dart';
import 'support.dart';

Quantity _kg(String v) => Quantity.fromJson({'value': v, 'unit': 'kg'});

const _heavy = 'workout/heavy[0]/heavy-set';
const _light = 'workout/light';

Future<BodyTmiException> _failure(Object? Function() action) async {
  try {
    await action();
  } on BodyTmiException catch (error) {
    return error;
  }
  throw StateError('Expected a BodyTmiException.');
}

Future<void> _withStore(Future<void> Function(TrainingStore) action) async {
  final dir = await Directory.systemTemp.createTemp('bodytmi-saveback-');
  final store = await TrainingStore.open('${dir.path}/db.sqlite');
  try {
    await action(store);
  } finally {
    await store.close();
    await dir.delete(recursive: true);
  }
}

String? _effortMass(WorkoutDefinition d, String id) => d.plan.nodes
    .whereType<Effort>()
    .firstWhere((e) => e.id == id)
    .targets['mass']
    ?.enteredValue;

void saveBackTests() {
  test('save-back writes intended target edits under explicit Q35 modes', () {
    return _withStore((store) async {
      final training = StoredTrainingService(store);
      final saveBack = SaveBackService(store);
      await training.publish(definition(), 0);
      var s = await training.start('a', 'upper-a', 1, instant(1));
      s = await training.editTarget(
        'a',
        s.contentVersion,
        _light,
        'mass',
        _kg('47.5'),
      );
      // One edited occurrence of a repeated effort cannot become a node target.
      s = await training.editTarget(
        'a',
        s.contentVersion,
        _heavy,
        'mass',
        _kg('62.5'),
      );

      final kept = await saveBack.saveBack('a', mode: 'session');
      equal(kept['changed'], true);
      equal(kept['published'], null);
      equal((await training.revision('upper-a')).number, 1);
      final notSaved = jsonList(kept, 'notSaved');
      equal(notSaved.length, 1);
      equal(
        jsonObject(notSaved.single, 'n')['reason'],
        'repeated-occurrences-differ',
      );
      // Publishing needs confirmation.
      equal(
        (await _failure(() => saveBack.saveBack('a', mode: 'save'))).code,
        'validation',
      );
      final saved = await saveBack.saveBack('a', mode: 'save', confirm: true);
      jsonEqual(saved['published'], {'templateId': 'upper-a', 'revision': 2});
      final head = await training.revision('upper-a');
      equal(_effortMass(head.definition, 'light'), '47.5');
      equal(_effortMass(head.definition, 'heavy-set'), null);
      // Results are never copied and the session keeps its pinned revision.
      equal((await training.session('a')).revision.number, 1);

      // The template moved on: an explicit separate template is required.
      final stale = await _failure(
        () => saveBack.saveBack('a', mode: 'save', confirm: true),
      );
      equal(stale.code, 'conflict');
      check(stale.message.contains('newTemplateId'), stale.message);
      final separate = await saveBack.saveBack(
        'a',
        mode: 'save',
        confirm: true,
        newTemplateId: 'upper-a-copy',
      );
      jsonEqual(separate['published'], {
        'templateId': 'upper-a-copy',
        'revision': 1,
      });
      equal(
        (await _failure(
          () => saveBack.saveBack(
            'a',
            mode: 'save',
            confirm: true,
            newTemplateId: 'upper-a-copy',
          ),
        )).code,
        'conflict',
      );

      // Editing every occurrence of the repeat saves one node target; an
      // unchanged session under save is a no-op, increment forces a boundary.
      var b = await training.start('b', 'upper-a', 2, instant(2));
      b = await training.editTarget(
        'b',
        b.contentVersion,
        _heavy,
        'mass',
        _kg('62.5'),
        applyToRemaining: true,
      );
      final heavy = await saveBack.saveBack('b', mode: 'save', confirm: true);
      equal(jsonList(heavy, 'saved').length, 3);
      equal(
        _effortMass(
          (await training.revision('upper-a')).definition,
          'heavy-set',
        ),
        '62.5',
      );
      await training.start('c', 'upper-a', 3, instant(3));
      final none = await saveBack.saveBack('c', mode: 'save', confirm: true);
      equal(none['changed'], false);
      equal(none['published'], null);
      final forced = await saveBack.saveBack(
        'c',
        mode: 'increment',
        confirm: true,
      );
      jsonEqual(forced['published'], {'templateId': 'upper-a', 'revision': 4});
      jsonEqual(
        (await training.revision('upper-a', 4)).definition.toJson(),
        (await training.revision('upper-a', 3)).definition.toJson(),
      );
      equal(
        (await _failure(() => saveBack.saveBack('c', mode: 'other'))).code,
        'validation',
      );
    });
  });

  test('save-back keeps progression-controlled metrics session-only', () {
    return _withStore((store) async {
      final training = StoredTrainingService(store);
      await training.publish(definition(), 0);
      var s = await training.start('a', 'upper-a', 1, instant(1));
      s = await training.edit('a', s.contentVersion, (s) {
        for (final set in s.sets)
          s = const TrainingService().complete(
            s,
            set.id,
            const {},
            acceptSuggested: true,
          );
        return s.finish(instant(1).add(const Duration(hours: 1)));
      });
      final progression = StoredProgressionService(store);
      final proposed = await progression.propose(
        'a',
        'bench-heavy',
        jsonObject(
          jsonObject(example('progression-preset')['preset'], 'p')['rule'],
          'rule',
        ),
      );
      await progression.accept(
        'a',
        'bench-heavy',
        proposed.version,
        instant(1).add(const Duration(hours: 2)),
      );
      var b = await training.start('b', 'upper-a', 1, instant(2));
      b = await training.editTarget(
        'b',
        b.contentVersion,
        _heavy,
        'mass',
        _kg('70'),
        applyToRemaining: true,
      );
      final result = await SaveBackService(
        store,
      ).saveBack('b', mode: 'save', confirm: true);
      equal(result['changed'], false);
      equal(result['published'], null);
      final reasons = {
        for (final n in jsonList(result, 'notSaved'))
          jsonObject(n, 'n')['reason'],
      };
      jsonEqual(reasons.toList(), ['progression-controlled']);
    });
  });

  test('CLI store save-back reports and publishes explicitly', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-saveback-cli-');
    try {
      final database = '${dir.path}/db.sqlite';
      final store = await TrainingStore.open(database);
      final training = StoredTrainingService(store);
      await training.publish(definition(), 0);
      final s = await training.start('a', 'upper-a', 1, instant(1));
      await training.editTarget(
        'a',
        s.contentVersion,
        _light,
        'mass',
        _kg('50'),
      );
      await store.close();
      Future<({int code, String output, String error})> cmd(
        Map<String, Object?> input,
      ) => invoke([
        'store',
        'save-back',
      ], jsonEncode({'schemaVersion': 1, 'database': database, ...input}));
      equal((await cmd({'id': 'a', 'mode': 'save'})).code, 2);
      equal((await cmd({'id': 'a', 'mode': 'later'})).code, 2);
      equal((await cmd({'id': 'missing', 'mode': 'session'})).code, 3);
      final ok = await cmd({...example('save-back'), 'database': database});
      check(ok.code == 0, ok.error);
      final data = jsonObject(
        jsonObject(jsonDecode(ok.output), 'r')['data'],
        'd',
      );
      equal(data['policy'], 'bodytmi-save-back/1');
      jsonEqual(data['published'], {'templateId': 'upper-a', 'revision': 2});
      equal(
        (await cmd({...example('save-back'), 'database': database})).code,
        5,
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
