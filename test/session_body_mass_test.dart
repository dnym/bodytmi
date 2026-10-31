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

WorkoutDefinition _definition() {
  final j = definition().toJson();
  final slots = jsonList(j, 'slots');
  jsonObject(slots.first, 'slot')['bodyMass'] = {'context': 'clothed-training'};
  jsonObject(slots.last, 'slot')['bodyMass'] = {
    'context': 'health',
    'dailyMode': 'replace',
    'warnIfStale': false,
  };
  return WorkoutDefinition.fromJson(j);
}

BodyMassMeasurement _mass(
  String id,
  String value, {
  String context = 'clothed-training',
  int day = 1,
  int version = 1,
}) => BodyMassMeasurement.fromJson({
  'id': id,
  'context': context,
  'observedAt': instant(
    day,
  ).subtract(const Duration(hours: 1)).toIso8601String(),
  'mass': {'value': value, 'unit': 'kg'},
  'contentVersion': version,
});
Map<String, Object?> _observation(BodyMassMeasurement m) =>
    Map<String, Object?>.from(m.toJson())..remove('contentVersion');
BodyMassOverride _override(Map<String, Object?> j) =>
    BodyMassOverride.fromJson(j);
TrainingSession _start({
  List<BodyMassMeasurement>? measurements,
  Map<String, BodyMassOverride> overrides = const {},
}) => const TrainingService().start(
  sessionId: 'bound',
  revision: WorkoutRevision.publish(_definition()),
  startedAt: instant(10),
  bodyMassMeasurements:
      measurements ??
      [_mass('training', '75'), _mass('health', '70', context: 'health')],
  bodyMassOverrides: overrides,
);
Future<void> _fails(Future<Object?> action) =>
    expectLater(action, throwsA(isA<BodyTmiException>()));
Map<String, Object?> _input(
  Map<String, Object?> session, [
  String slot = 'bench-heavy',
]) =>
    jsonObject(jsonObject(session['bodyMassInputs'], 'inputs')[slot], 'input');
Future<void> _withStore(
  Future<void> Function(TrainingStore, String) action,
) async {
  final dir = await Directory.systemTemp.createTemp('bodytmi-session-mass-');
  final store = await TrainingStore.open('${dir.path}/db.sqlite');
  try {
    await action(store, dir.path);
  } finally {
    await store.close();
    await dir.delete(recursive: true);
  }
}

void sessionBodyMassTests() {
  test(
    'session body mass is explicitly selected, frozen separately from targets and retained through result edits',
    () {
      final s = _start();
      equal(s.bodyMassInputs.length, 2);
      equal(
        s.bodyMassInputs['bench-heavy']!.resolution.mass!.value.toString(),
        '75',
      );
      equal(
        s.bodyMassInputs['bench-light']!.resolution.mass!.value.toString(),
        '70',
      );
      equal(s.bodyMassInputs['bench-heavy']!.resolution.stale, true);
      equal(
        s.bodyMassInputs['bench-light']!.resolution
            .toJson()['warnings']
            .toString(),
        '[]',
      );
      equal(s.sets.first.suggested['mass']!.value.toString(), '60');
      equal(s.sets.first.actuals.isEmpty, true);
      final frozen = canonicalJson(s.bodyMassInputs['bench-heavy']!.toJson());
      final done = finished(s);
      final edited = const TrainingService().complete(
        done,
        done.sets.first.id,
        {'mass': Quantity('65', 'kg'), 'reps': Quantity('9', 'rep')},
      );
      equal(
        canonicalJson(edited.bodyMassInputs['bench-heavy']!.toJson()),
        frozen,
      );
      jsonEqual(sessionFromJson(edited.toJson()).toJson(), edited.toJson());
      final missing = _start(
        measurements: [_mass('health', '70', context: 'health')],
      );
      equal(
        missing.bodyMassInputs['bench-heavy']!.resolution.source,
        'unavailable',
      );
      equal(missing.bodyMassInputs['bench-heavy']!.resolution.mass, null);
      equal(finished(missing).status, SessionStatus.finalized);
      check(!start().toJson().containsKey('bodyMassInputs'));
    },
  );

  test(
    'session overrides select a same-context eligible weigh-in or manual mass without changing prescriptions',
    () {
      final s = _start(
        overrides: {
          'bench-heavy': _override({'measurementId': 'training'}),
          'bench-light': _override({
            'mass': {'value': '154', 'unit': 'lb'},
          }),
        },
      );
      equal(s.bodyMassInputs['bench-heavy']!.resolution.source, 'measurement');
      equal(
        s.bodyMassInputs['bench-heavy']!.measurements.single.id,
        'training',
      );
      equal(s.bodyMassInputs['bench-light']!.resolution.source, 'manual');
      equal(s.bodyMassInputs['bench-light']!.measurements.length, 0);
      equal(s.sets.last.suggested['mass']!.value.toString(), '45');
      jsonEqual(sessionFromJson(s.toJson()).toJson(), s.toJson());
      rejects(
        () => _start(
          overrides: {
            'bench-heavy': _override({'measurementId': 'health'}),
          },
        ),
      );
      rejects(
        () => _start(
          measurements: [_mass('future', '80', day: 11)],
          overrides: {
            'bench-heavy': _override({'measurementId': 'future'}),
          },
        ),
      );
      rejects(
        () => _start(
          overrides: {
            'unknown': _override({
              'mass': {'value': '70', 'unit': 'kg'},
            }),
          },
        ),
      );
      rejects(() => _override({}));
      rejects(
        () => _override({
          'mass': {'value': '0', 'unit': 'kg'},
        }),
      );
      rejects(
        () => BodyMassSelection.fromJson({
          'context': 'training',
          'staleAfterDays': -1,
        }),
      );
    },
  );

  test(
    'freshness detects edited, inserted and deleted source membership while ignoring future, other-context and unused override inputs',
    () {
      final original = [
        _mass('training', '75'),
        _mass('health', '70', context: 'health'),
      ];
      final s = _start(measurements: original);
      final binding = s.bodyMassInputs['bench-heavy']!;
      equal(binding.freshness(original)['changed'], false);
      equal(
        binding.freshness([
          ...original,
          _mass('future', '80', day: 11),
        ])['changed'],
        false,
      );
      equal(
        binding.freshness([
          ...original,
          _mass('other', '80', context: 'other'),
        ])['changed'],
        false,
      );
      equal(
        binding.freshness([_mass('training', '76'), original.last])['changed'],
        true,
      );
      equal(
        binding.freshness([
          ...original,
          _mass('backdated', '77', day: 2),
        ])['changed'],
        true,
      );
      equal(binding.freshness([original.last])['changed'], true);
      final selected = _start(
        overrides: {
          'bench-heavy': _override({'measurementId': 'training'}),
        },
      ).bodyMassInputs['bench-heavy']!;
      equal(
        selected.freshness([
          ...original,
          _mass('new', '78', day: 2),
        ])['changed'],
        false,
      );
      equal(
        selected.freshness([original.last])['reason'],
        'source_unavailable',
      );
      final manual = _start(
        overrides: {
          'bench-heavy': _override({
            'mass': {'value': '77', 'unit': 'kg'},
          }),
        },
      ).bodyMassInputs['bench-heavy']!;
      equal(manual.freshness([])['changed'], false);
      rejects(() => binding.freshness([original.first, original.first]));
      equal(binding.resolution.mass!.value.toString(), '75');
    },
  );

  test(
    'stored and program starts capture sources atomically and identity retries never re-resolve changed inputs',
    () => _withStore((store, dir) async {
      final service = StoredTrainingService(store);
      final measurements = StoredBodyMassService(store);
      await service.publish(_definition(), 0);
      await measurements.save(_observation(_mass('training', '75')), 0);
      final s = await service.start('saved', definition().id, 1, instant(10));
      await measurements.save(_observation(_mass('training', '76')), 1);
      jsonEqual(
        (await service.start(
          'saved',
          definition().id,
          1,
          instant(10),
        )).toJson(),
        s.toJson(),
      );
      final current = await service.start(
        'new',
        definition().id,
        1,
        instant(10),
      );
      equal(
        current.bodyMassInputs['bench-heavy']!.resolution.mass!.value
            .toString(),
        '76',
      );
      await _fails(
        service.edit(
          s.id,
          s.contentVersion,
          (s) => TrainingSession(
            id: s.id,
            revision: s.revision,
            startedAt: s.startedAt,
            sets: s.sets,
            bodyMassInputs: current.bodyMassInputs,
          ),
        ),
      );
      final program = ProgramDefinition.fromJson({
        'id': 'program',
        'name': 'Program',
        'plan': {
          'id': 'day',
          'type': 'day',
          'templateId': definition().id,
          'revision': 1,
        },
      });
      final programs = ProgramService(store);
      await programs.publish(program, 0);
      await programs.create('run', 'program', 1, instant(10));
      final overrides = {
        'bench-heavy': _override({'measurementId': 'training'}),
      };
      final bound = await programs.start(
        'run',
        1,
        'program-session',
        instant(10),
        bodyMassOverrides: overrides,
      );
      await measurements.delete('training', 2, confirm: true);
      jsonEqual(
        (await programs.start(
          'run',
          1,
          'program-session',
          instant(10),
          bodyMassOverrides: overrides,
        )).toJson(),
        bound.toJson(),
      );
      await _fails(programs.start('run', 1, 'program-session', instant(10)));
      await service.edit(bound.id, bound.contentVersion, finished);
      equal((await programs.run('run')).cursor, 1);
      await _fails(
        programs.start(
          'run',
          3,
          'bad',
          instant(11),
          bodyMassOverrides: overrides,
        ),
      );
      equal(await store.session('bad'), null);
      equal((await programs.run('run')).contentVersion, 3);
      equal(
        (await store.session(
          'saved',
        ))!.bodyMassInputs['bench-heavy']!.resolution.mass!.value.toString(),
        '75',
      );
      await store.archive();
    }),
  );

  test(
    'snapshot and archive validation reject forged resolution, selection, source versions, missing bindings and current-version content',
    () => _withStore((store, dir) async {
      final service = StoredTrainingService(store);
      final measurements = StoredBodyMassService(store);
      await service.publish(_definition(), 0);
      await measurements.save(_observation(_mass('training', '75')), 0);
      final s = await service.start('saved', definition().id, 1, instant(10));
      final mutations = <void Function(Map<String, Object?>)>[
        (j) => jsonObject(_input(j)['resolution'], 'resolution')['mass'] = {
          'value': '999',
          'unit': 'kg',
        },
        (j) => jsonObject(_input(j)['selection'], 'selection')['context'] =
            'other',
        (j) => _input(j)['asOf'] = instant(9).toIso8601String(),
        (j) => jsonObject(j['bodyMassInputs'], 'inputs').remove('bench-heavy'),
        (j) => jsonObject(j['bodyMassInputs'], 'inputs')['other'] = _input(j),
      ];
      for (final mutate in mutations) {
        final j = copyJson(s.toJson());
        mutate(j);
        rejects(() => sessionFromJson(j));
      }
      final archive = (await store.archive()).toJson();
      final missing = copyJson(archive);
      jsonList(missing, 'bodyMass').clear();
      rejects(() => TrainingArchive.fromJson(missing));
      final changed = copyJson(archive);
      jsonObject(
        jsonObject(
          jsonList(changed, 'bodyMass').single,
          'record',
        )['measurement'],
        'measurement',
      )['mass'] = {
        'value': '76',
        'unit': 'kg',
      };
      rejects(() => TrainingArchive.fromJson(changed));
      await measurements.save(_observation(_mass('training', '76')), 1);
      await measurements.delete('training', 2, confirm: true);
      jsonEqual(
        TrainingArchive.fromJson(
          (await store.archive()).toJson(),
        ).sessions.single.toJson(),
        s.toJson(),
      );
    }),
  );

  test(
    'numeric progression retains frozen mass inputs across measurement and result corrections',
    () => _withStore((store, dir) async {
      final training = StoredTrainingService(store);
      final mass = StoredBodyMassService(store);
      await training.publish(_definition(), 0);
      await mass.save(_observation(_mass('training', '75')), 0);
      var s = await training.start(
        'progression',
        definition().id,
        1,
        instant(10),
      );
      s = await training.edit(s.id, s.contentVersion, finished);
      final progression = StoredProgressionService(store);
      final rule = jsonObject(example('double-progression')['rule'], 'rule');
      final proposed = await progression.propose(s.id, 'bench-heavy', rule);
      await mass.save(_observation(_mass('training', '76')), 1);
      // The existing numeric preset consumes reps/external load, not body mass.
      equal(await progression.stale(proposed), false);
      await progression.accept(
        s.id,
        'bench-heavy',
        proposed.version,
        instant(10).add(const Duration(hours: 2)),
      );
      s = await training.edit(
        s.id,
        s.contentVersion,
        (s) => const TrainingService().complete(s, s.sets.first.id, {
          'mass': Quantity('60', 'kg'),
          'reps': Quantity('9', 'rep'),
        }),
      );
      final archive = (await store.archive()).toJson();
      final decision = jsonObject(
        jsonList(archive, 'progressions').single,
        'decision',
      );
      final oldSession = jsonObject(decision['session'], 'session');
      final replacement = BodyMassInputSnapshot.capture(
        selection: s.bodyMassInputs['bench-heavy']!.selection,
        asOf: s.startedAt,
        measurements: [],
        override: _override({
          'mass': {'value': '80', 'unit': 'kg'},
        }),
      );
      jsonObject(oldSession['bodyMassInputs'], 'inputs')['bench-heavy'] =
          replacement.toJson();
      rejects(() => TrainingArchive.fromJson(archive));
    }),
  );

  test(
    'body-mass session snapshots survive full native/logical restore and cannot be relabeled as older formats',
    () => _withStore((store, dir) async {
      final service = StoredTrainingService(store);
      await service.publish(_definition(), 0);
      final mass = StoredBodyMassService(store);
      await mass.save(_observation(_mass('training', '75')), 0);
      final s = await service.start('saved', definition().id, 1, instant(10));
      await service.edit(s.id, s.contentVersion, finished);
      await mass.delete('training', 1, confirm: true);
      final original = canonicalJson((await store.archive()).toJson());
      equal((await store.backup('$dir/native'))['databaseSchemaVersion'], 5);
      await LogicalArchiveFiles.export(
        await store.archive(),
        '$dir/export.json',
      );
      final logical = await LogicalArchiveFiles.prepare('$dir/export.json');
      try {
        await store.restore(
          logical.backup,
          recoveryDestination: '$dir/recovery',
          confirm: true,
        );
      } finally {
        await logical.close();
        await store.close();
      }
      final reopened = await TrainingStore.open('$dir/db.sqlite');
      try {
        equal(canonicalJson((await reopened.archive()).toJson()), original);
        equal(
          (await reopened.session(
            'saved',
          ))!.bodyMassInputs['bench-heavy']!.resolution.mass!.value.toString(),
          '75',
        );
        final native = await NativeBackup.prepare('$dir/native');
        try {
          await reopened.restore(
            native,
            recoveryDestination: '$dir/recovery2',
            confirm: true,
          );
        } finally {
          await native.close();
        }
      } finally {
        await reopened.close();
      }
      final again = await TrainingStore.open('$dir/db.sqlite');
      try {
        equal(canonicalJson((await again.archive()).toJson()), original);
      } finally {
        await again.close();
      }
      final doc = jsonObject(
        jsonDecode(await File('$dir/export.json').readAsString()),
        'export',
      )..remove('sha256');
      doc['format'] = 'bodytmi-logical-export/4';
      doc['sha256'] = sha256
          .convert(utf8.encode(canonicalJson(doc)))
          .toString();
      await File('$dir/forged.json').writeAsString(jsonEncode(doc));
      await _fails(LogicalArchiveFiles.prepare('$dir/forged.json'));
      final raw = sqlite3.open('$dir/native/database.sqlite');
      try {
        raw.execute('PRAGMA user_version = 4');
      } finally {
        raw.close();
      }
      rejects(
        () => NativeBackup.validateDatabase('$dir/native/database.sqlite'),
      );
    }),
  );

  test(
    'v4 databases and logical exports upgrade without changing legacy measurements or sessions',
    () => _withStore((store, dir) async {
      await StoredTrainingService(store).publish(definition(), 0);
      await StoredTrainingService(
        store,
      ).start('legacy', definition().id, 1, instant(10));
      await StoredBodyMassService(
        store,
      ).save(_observation(_mass('training', '75')), 0);
      final original = (await store.archive()).toJson();
      final doc = <String, Object?>{
        'format': 'bodytmi-logical-export/4',
        'applicationVersion': '0.1.0',
        'data': original,
      };
      doc['sha256'] = sha256
          .convert(utf8.encode(canonicalJson(doc)))
          .toString();
      await File('$dir/v4.json').writeAsString(jsonEncode(doc));
      final old = await LogicalArchiveFiles.prepare('$dir/v4.json');
      try {
        jsonEqual(old.archive.toJson(), original);
      } finally {
        await old.close();
      }
      await store.close();
      final raw = sqlite3.open('$dir/db.sqlite');
      try {
        raw.execute('PRAGMA user_version = 4');
      } finally {
        raw.close();
      }
      equal(
        (await NativeBackup.create(
          '$dir/db.sqlite',
          '$dir/v4-native',
        ))['databaseSchemaVersion'],
        4,
      );
      final upgraded = await TrainingStore.open('$dir/db.sqlite');
      try {
        jsonEqual((await upgraded.archive()).toJson(), original);
      } finally {
        await upgraded.close();
      }
      final check = sqlite3.open('$dir/db.sqlite');
      try {
        equal(check.userVersion, 5);
      } finally {
        check.close();
      }
    }),
  );

  test(
    'pure and stored native CLI expose matching captures and freshness without rewriting session results',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-session-mass-cli-',
      );
      try {
        Future<Object?> command(
          String command,
          Map<String, Object?> input, {
          bool stored = true,
        }) async {
          final response = await invoke(
            command.split(' '),
            jsonEncode({
              'schemaVersion': 1,
              if (stored) 'database': '${dir.path}/db.sqlite',
              ...input,
            }),
          );
          equal(response.code, 0);
          equal(response.error, '');
          return jsonObject(jsonDecode(response.output), 'response')['data'];
        }

        final rev = await command('store publish', {
          'definition': _definition().toJson(),
          'expectedRevision': 0,
        });
        final observation = _mass('training', '75');
        await command('mass record', {
          'measurement': _observation(observation),
        });
        final stored = jsonObject(
          await command('store start', {
            'id': 'same',
            'templateId': definition().id,
            'revision': 1,
            'startedAt': instant(10).toIso8601String(),
          }),
          'session',
        );
        final pure = await command('session start', {
          'id': 'same',
          'revision': rev,
          'startedAt': instant(10).toIso8601String(),
          'bodyMassMeasurements': [observation.toJson()],
        }, stored: false);
        jsonEqual(stored, pure);
        final changed = _mass('training', '76', version: 2);
        await command('mass update', {
          'measurement': _observation(changed),
          'expectedVersion': 1,
        });
        final status = await command('store mass-status', {'id': 'same'});
        jsonEqual(
          status,
          await command('session mass-status', {
            'session': pure,
            'measurements': [changed.toJson()],
          }, stored: false),
        );
        equal(
          jsonObject(
            jsonObject(
              jsonObject(status, 'status')['inputs'],
              'inputs',
            )['bench-heavy'],
            'input',
          )['changed'],
          true,
        );
        jsonEqual(await command('store show', {'id': 'same'}), stored);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
