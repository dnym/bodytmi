import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:sqlite3/sqlite3.dart';
import 'cli_test.dart';
import 'fixtures.dart';
import 'support.dart';

Map<String, Object?> _preset({String? name, Map<String, Object?>? rule}) => {
  ...jsonObject(example('progression-preset')['preset'], 'preset'),
  'name': ?name,
  'rule': ?rule,
};

Future<BodyTmiException> _failure(Object? Function() action) async {
  try {
    await action();
  } on BodyTmiException catch (error) {
    return error;
  }
  throw StateError('Expected a BodyTmiException.');
}

Future<TrainingSession> _finished(
  TrainingStore store,
  String id,
  int day,
) async {
  final service = StoredTrainingService(store);
  final session = await service.start(id, definition().id, 1, instant(day));
  return service.edit(id, session.contentVersion, (s) {
    for (final set in s.sets) {
      s = const TrainingService().complete(
        s,
        set.id,
        const {},
        acceptSuggested: true,
      );
    }
    return s.finish(instant(day).add(const Duration(hours: 1)));
  });
}

void progressionPresetTests() {
  test('presets validate their rule payload for the declared type', () {
    final preset = ProgressionPreset.fromJson(_preset());
    equal(preset.ruleType, 'double');
    jsonEqual(
      ProgressionPreset.fromJson(preset.toJson()).toJson(),
      preset.toJson(),
    );
    rejects(
      () => ProgressionPreset.fromJson({..._preset(), 'ruleType': 'magic'}),
    );
    rejects(
      () => ProgressionPreset.fromJson({..._preset(), 'ruleType': 'threshold'}),
    );
    rejects(
      () => ProgressionPreset.fromJson(_preset(rule: {'objective': 'reps'})),
    );
    rejects(() => ProgressionPreset.fromJson(_preset(name: ' ')));
    rejects(() => ProgressionPreset.fromJson({..._preset(), 'extra': 1}));
    final first = ProgressionPresetRevision.publish(preset);
    final second = ProgressionPresetRevision.publish(preset, previous: first);
    validateProgressionPresetRevisions([first, second]);
    rejects(() => validateProgressionPresetRevisions([second]));
    rejects(() => validateProgressionPresetRevisions([first, first]));
  });

  test(
    'stored presets publish with compare-and-set and survive portability',
    () async {
      final dir = await Directory.systemTemp.createTemp('bodytmi-preset-');
      var store = await TrainingStore.open('${dir.path}/db.sqlite');
      try {
        final presets = PresetService(store);
        final first = await presets.publish(
          ProgressionPreset.fromJson(_preset()),
          0,
        );
        equal(first.number, 1);
        equal(
          (await _failure(
            () => presets.publish(ProgressionPreset.fromJson(_preset()), 0),
          )).code,
          'conflict',
        );
        await presets.publish(
          ProgressionPreset.fromJson(_preset(name: 'Renamed')),
          1,
        );
        equal((await presets.revision('double-8-12')).preset.name, 'Renamed');
        equal((await presets.revision('double-8-12', 1)).number, 1);
        equal(
          (await _failure(() => presets.revision('missing'))).code,
          'not_found',
        );

        final original = canonicalJson((await store.archive()).toJson());
        equal((await store.archive()).presets.length, 2);
        await store.backup('${dir.path}/native');
        await LogicalArchiveFiles.export(
          await store.archive(),
          '${dir.path}/logical.json',
        );
        final logical = await LogicalArchiveFiles.prepare(
          '${dir.path}/logical.json',
        );
        try {
          await store.restore(
            logical.backup,
            recoveryDestination: '${dir.path}/recovery',
            confirm: true,
          );
        } finally {
          await logical.close();
        }
        await store.close();
        store = await TrainingStore.open('${dir.path}/db.sqlite');
        equal(canonicalJson((await store.archive()).toJson()), original);
        // A tampered row identity is rejected by native validation.
        final copy = '${dir.path}/tamper.sqlite';
        File('${dir.path}/native/database.sqlite').copySync(copy);
        final db = sqlite3.open(copy);
        db.execute(
          "UPDATE progression_preset_revisions SET preset_id = 'other' WHERE number = 1",
        );
        db.close();
        final tampered = await _failure(
          () => NativeBackup.validateDatabase(copy),
        );
        check(
          tampered.message.contains('preset revision row identity'),
          tampered.message,
        );
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test('decisions persist preset provenance validated on portability', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-preset-prov-');
    final store = await TrainingStore.open('${dir.path}/db.sqlite');
    try {
      await StoredTrainingService(store).publish(definition(), 0);
      await _finished(store, 'a', 1);
      final presets = PresetService(store);
      await presets.publish(ProgressionPreset.fromJson(_preset()), 0);
      final rule = jsonObject(_preset()['rule'], 'rule');
      final progression = StoredProgressionService(store);
      // The service re-checks the reference inside its transaction.
      equal(
        (await _failure(
          () => progression.propose(
            'a',
            'bench-heavy',
            rule,
            preset: (id: 'double-8-12', revision: 2),
          ),
        )).code,
        'not_found',
      );
      equal(
        (await _failure(
          () => progression.propose(
            'a',
            'bench-heavy',
            {
              ...rule,
              'leverStep': {'value': '5', 'unit': 'kg'},
            },
            preset: (id: 'double-8-12', revision: 1),
          ),
        )).code,
        'validation',
      );
      final proposed = await progression.propose(
        'a',
        'bench-heavy',
        rule,
        preset: (id: 'double-8-12', revision: 1),
      );
      equal(proposed.preset, (id: 'double-8-12', revision: 1));
      // Re-proposing the same rule inline drops the provenance as a new version.
      final inline = await progression.propose('a', 'bench-heavy', rule);
      equal(inline.preset, null);
      equal(inline.version, proposed.version + 1);
      final again = await progression.propose(
        'a',
        'bench-heavy',
        rule,
        preset: (id: 'double-8-12', revision: 1),
      );
      final accepted = await progression.accept(
        'a',
        'bench-heavy',
        again.version,
        instant(1).add(const Duration(hours: 2)),
      );
      equal(accepted.preset, (id: 'double-8-12', revision: 1));
      // A later preset revision never rewrites the decision.
      await presets.publish(
        ProgressionPreset.fromJson(_preset(name: 'Renamed')),
        1,
      );
      equal((await progression.decision('a', 'bench-heavy')).preset, (
        id: 'double-8-12',
        revision: 1,
      ));

      final archive = (await store.archive()).toJson();
      TrainingArchive.fromJson(archive);
      Map<String, Object?> withDecision(
        Map<String, Object?> Function(Map<String, Object?>) change,
      ) {
        final copy = jsonObject(jsonDecode(jsonEncode(archive)), 'a');
        final rows = jsonList(copy, 'progressions');
        rows[0] = change(jsonObject(rows[0], 'row'));
        return copy;
      }

      final missing = await _failure(
        () => TrainingArchive.fromJson(
          withDecision(
            (d) => {
              ...d,
              'preset': {'id': 'double-8-12', 'revision': 9},
            },
          ),
        ),
      );
      check(missing.message.contains('unpublished preset'), missing.message);
      // Removing the preset rows leaves an orphaned reference.
      final orphan = jsonObject(jsonDecode(jsonEncode(archive)), 'a')
        ..['presets'] = <Object?>[];
      rejects(() => TrainingArchive.fromJson(orphan));

      await store.backup('${dir.path}/native');
      final copy = '${dir.path}/tamper.sqlite';
      File('${dir.path}/native/database.sqlite').copySync(copy);
      final db = sqlite3.open(copy);
      db.execute('DELETE FROM progression_preset_revisions');
      db.close();
      final tampered = await _failure(
        () => NativeBackup.validateDatabase(copy),
      );
      check(tampered.message.contains('unpublished preset'), tampered.message);
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  });

  test('CLI propose resolves an explicit preset revision', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-preset-cli-');
    try {
      final store = await TrainingStore.open('${dir.path}/db.sqlite');
      await StoredTrainingService(store).publish(definition(), 0);
      await _finished(store, 'a', 1);
      await _finished(store, 'b', 2);
      await store.close();
      Future<({int code, String output, String error})> cmd(
        String action,
        Map<String, Object?> input,
      ) => invoke(
        action.split(' '),
        jsonEncode({
          'schemaVersion': 1,
          'database': '${dir.path}/db.sqlite',
          ...input,
        }),
      );
      final published = await cmd('preset publish', {
        'preset': _preset(),
        'expectedRevision': 0,
      });
      check(published.code == 0, published.error);
      equal(
        (await cmd('preset publish', {
          'preset': _preset(),
          'expectedRevision': 0,
        })).code,
        5,
      );
      final list = await cmd('preset list', {});
      check(list.output.contains('"double-8-12"'));
      equal((await cmd('preset show', {'presetId': 'missing'})).code, 3);

      final viaPreset = await cmd('progression propose', {
        'sessionId': 'a',
        'slotId': 'bench-heavy',
        'preset': {'id': 'double-8-12', 'revision': 1},
      });
      check(viaPreset.code == 0, viaPreset.error);
      final data = jsonObject(
        jsonObject(jsonDecode(viaPreset.output), 'r')['data'],
        'data',
      );
      jsonEqual(data['preset'], {'id': 'double-8-12', 'revision': 1});
      // The reference is persisted on the decision, not only echoed.
      final shown = await cmd('progression show', {
        'sessionId': 'a',
        'slotId': 'bench-heavy',
      });
      check(shown.code == 0, shown.error);
      jsonEqual(
        jsonObject(
          jsonObject(jsonDecode(shown.output), 'r')['data'],
          'data',
        )['preset'],
        {'id': 'double-8-12', 'revision': 1},
      );
      // The same rule given inline yields the same proposal.
      final inline = await cmd('progression propose', {
        'sessionId': 'b',
        'slotId': 'bench-heavy',
        'rule': _preset()['rule'],
      });
      final inlineData = jsonObject(
        jsonObject(jsonDecode(inline.output), 'r')['data'],
        'data',
      );
      jsonEqual(
        jsonObject(inlineData['proposal'], 'p')['outcome'],
        jsonObject(data['proposal'], 'p')['outcome'],
      );
      check(!inlineData.containsKey('preset'), 'inline rule has no preset');
      // An explicit revision is required, and rule cannot be mixed in.
      equal(
        (await cmd('progression propose', {
          'sessionId': 'a',
          'slotId': 'bench-heavy',
          'preset': {'id': 'double-8-12'},
        })).code,
        2,
      );
      equal(
        (await cmd('progression propose', {
          'sessionId': 'a',
          'slotId': 'bench-heavy',
          'preset': {'id': 'double-8-12', 'revision': 1},
          'ruleType': 'double',
        })).code,
        2,
      );
      equal(
        (await cmd('progression propose', {
          'sessionId': 'a',
          'slotId': 'bench-heavy',
          'preset': {'id': 'double-8-12', 'revision': 9},
        })).code,
        3,
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
