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

EquipmentDefinition _equipment(String id, {String? name, String? notes}) =>
    EquipmentDefinition.fromJson({
      'id': id,
      if (name != null) 'name': name,
      if (notes != null) 'notes': notes,
    });

GymDefinition _gym(String id, {String? name}) =>
    GymDefinition.fromJson({'id': id, if (name != null) 'name': name});

EquipmentInstance _instance(
  String id,
  String equipmentId, {
  String? gym,
  Object? scale,
}) => EquipmentInstance.fromJson({
  'id': id,
  'equipmentId': equipmentId,
  if (gym != null) 'gym': gym,
  if (scale != null) 'scale': scale,
});

Future<void> _withStore(
  Future<void> Function(TrainingStore, String) action,
) async {
  final dir = await Directory.systemTemp.createTemp('bodytmi-equipment-');
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

Future<void> _publishInventory(TrainingStore store) async {
  final service = EquipmentService(store);
  await service.publishEquipment(_equipment('rack', name: 'Power rack'), 0);
  await service.publishEquipment(_equipment('selectorized-machine'), 0);
  await service.publishGym(_gym('garage', name: 'Garage'), 0);
  await service.publishGym(_gym('commercial'), 0);
  await service.publishInstance(_instance('rack-1', 'rack', gym: 'garage'), 0);
  await service.publishInstance(
    _instance(
      'stack-1',
      'selectorized-machine',
      gym: 'garage',
      scale: {
        'id': 'stack-1-selector',
        'unit': 'kg',
        'ticks': [
          {
            'id': 's-10',
            'value': '10',
            'labels': {'lb': '22'},
          },
          {
            'id': 's-15',
            'value': '15',
            'labels': {'lb': '33'},
          },
        ],
      },
    ),
    0,
  );
  await service.publishInstance(
    _instance('rack-2', 'rack', gym: 'commercial'),
    0,
  );
}

Future<Map<String, Object?>> _resign(Map<String, Object?> envelope) async {
  envelope.remove('sha256');
  envelope['sha256'] = sha256
      .convert(utf8.encode(canonicalJson(envelope)))
      .toString();
  return envelope;
}

void equipmentTests() {
  test(
    'equipment, gym and instance models and validators keep identities and scale labels honest',
    () {
      final rack = EquipmentRevision.publish(_equipment('rack', name: 'Rack'));
      equal(rack.number, 1);
      check(
        canonicalJson(
          EquipmentRevision.publish(
            _equipment('rack', name: 'Power rack'),
            previous: rack,
          ).toJson(),
        ).contains('"revision":2'),
        'equipment revisions number immutably per identity',
      );
      rejects(
        () => EquipmentRevision.fromJson({
          'schemaVersion': 1,
          'revision': 1,
          'equipment': {'id': 'rack', 'name': 'R'.padRight(201, 'x')},
        }),
      );
      rejects(
        () => EquipmentInstance.fromJson({
          'id': 'rack-1',
          'equipmentId': 'rack',
          'unknown': 1,
        }),
      );
      final stack = EquipmentInstanceRevision.publish(
        _instance(
          'stack-1',
          'selectorized-machine',
          scale: {
            'id': 'stack-1-selector',
            'unit': 'kg',
            'ticks': [
              {
                'id': 's-10',
                'value': '10',
                'labels': {'lb': '22'},
              },
              {'id': 's-15', 'value': '15'},
            ],
          },
        ),
      );
      equal(stack.instance.scale!.ticks.length, 2);
      equal(stack.instance.scale!.ticks.first.labels['lb'], '22');
      // A gym move is a new revision; the equipment kind is frozen.
      final moved = EquipmentInstanceRevision.publish(
        _instance('stack-1', 'selectorized-machine', gym: 'garage'),
        previous: stack,
      );
      equal(moved.number, 2);
      equal(moved.instance.gymId, 'garage');
      rejects(
        () => EquipmentInstanceRevision.publish(
          _instance('stack-1', 'other-machine'),
          previous: stack,
        ),
      );
      rejects(
        () => EquipmentInstanceRevision.publish(
          _instance('other', 'selectorized-machine'),
          previous: stack,
        ),
      );
      final gyms = [GymRevision.publish(_gym('garage'))];
      final equipment = [
        rack,
        EquipmentRevision.publish(_equipment('selectorized-machine')),
      ];
      validateEquipmentInstanceRevisions([stack, moved], equipment, gyms);
      // Cross-instance equipment drift, gaps and missing references fail.
      rejects(
        () => validateEquipmentInstanceRevisions(
          [
            stack,
            EquipmentInstanceRevision.publish(
              _instance('stack-1', 'other-machine'),
            ),
          ],
          equipment,
          gyms,
        ),
      );
      rejects(
        () => validateEquipmentInstanceRevisions([moved], equipment, gyms),
      );
      rejects(() => validateEquipmentInstanceRevisions([moved], equipment, []));
      rejects(() => validateEquipmentInstanceRevisions([stack], [rack], gyms));
      rejects(
        () => NumericScale.fromJson({
          'id': 'bad',
          'unit': 'kg',
          'ticks': [
            {'id': 'b', 'value': '20'},
            {'id': 'a', 'value': '10'},
          ],
        }),
      );
      rejects(
        () => NumericScale.fromJson({
          'id': 'bad',
          'unit': 'kg',
          'ticks': [
            {
              'id': 'a',
              'value': '10',
              'labels': {'m': '3'},
            },
          ],
        }),
      );
    },
  );
  test(
    'durable inventory authoring compares-and-sets, rejects orphans, moves gyms by revision and reports effective placement',
    () => _withStore((store, dir) async {
      final before = (await store.archive()).sessions.length;
      final service = EquipmentService(store);
      await _publishInventory(store);
      equal((await store.equipmentRevisions()).length, 2);
      equal((await store.gymRevisions()).length, 2);
      equal((await store.equipmentInstanceRevisions()).length, 3);
      // Compare-and-set on the per-id head.
      await _fails(
        () =>
            service.publishEquipment(_equipment('rack', name: 'Squat rack'), 0),
      );
      final renamed = await service.publishEquipment(
        _equipment('rack', name: 'Squat rack'),
        1,
      );
      equal(renamed.number, 2);
      // Orphans report not_found and store nothing.
      await _fails(
        () => service.publishInstance(_instance('ghost', 'unpublished'), 0),
      );
      await _fails(
        () => service.publishInstance(
          _instance('ghost', 'rack', gym: 'unpublished'),
          0,
        ),
      );
      equal((await store.equipmentInstanceRevisions()).length, 3);
      // A gym move is a new immutable revision; the inventory view follows.
      final moved = await service.publishInstance(
        _instance('rack-1', 'rack', gym: 'commercial'),
        1,
      );
      equal(moved.number, 2);
      equal(
        (await service.instanceRevision('rack-1', 1)).instance.gymId,
        'garage',
      );
      final garage = await service.inventory(gymId: 'garage');
      equal(garage.length, 1);
      equal(garage.single.instance.id, 'stack-1');
      equal(
        garage.single.instance.scale!.ticks.last.quantity.value.toString(),
        '15',
      );
      equal(garage.single.instance.scale!.ticks.last.quantity.unit.name, 'kg');
      final commercial = await service.inventory(gymId: 'commercial');
      jsonEqual(
        [for (final r in commercial) r.instance.id],
        ['rack-1', 'rack-2'],
      );
      equal((await service.inventory()).length, 3);
      // Inventory authoring changes no session content.
      equal((await store.archive()).sessions.length, before);
    }),
  );
  test(
    'archives and native backups reject instance snapshots with forged or missing references',
    () => _withStore((store, dir) async {
      await _publishInventory(store);
      final expected = canonicalJson((await store.archive()).toJson());
      await store.backup('$dir/native');
      equal(
        (await LogicalArchiveFiles.export(
          await store.archive(),
          '$dir/logical.json',
        ))['format'],
        'bodytmi-logical-export/69',
      );
      final logical = await LogicalArchiveFiles.prepare('$dir/logical.json');
      try {
        equal(logical.archive.equipment.length, 2);
        equal(logical.archive.gyms.length, 2);
        equal(logical.archive.instances.length, 3);
      } finally {
        await logical.close();
      }
      final forged = jsonObject(
        jsonDecode(await File('$dir/logical.json').readAsString()),
        'logical',
      );
      final rows =
          jsonObject(forged['data'], 'data')['instances'] as List<Object?>;
      final target = jsonObject(rows.first, 'instance revision');
      jsonObject(target['instance'], 'instance')['equipmentId'] = 'missing';
      await File('$dir/forged.json')
        ..createSync()
        ..writeAsStringSync(jsonEncode(await _resign(forged)));
      final logicalError = await failure(
        () => LogicalArchiveFiles.prepare('$dir/forged.json'),
      );
      check(
        logicalError.message.contains('equipment that is not published'),
        'logical archives validate instance references',
      );
      final tampered = sqlite3.open('$dir/native/database.sqlite');
      try {
        tampered.execute(
          'UPDATE equipment_instance_revisions SET snapshot = '
          "REPLACE(snapshot, '\"equipmentId\":\"rack\"', "
          "'\"equipmentId\":\"missing\"') WHERE rowid = 1",
        );
      } finally {
        tampered.close();
      }
      final database = File('$dir/native/database.sqlite');
      final manifestFile = File('$dir/native/manifest.json');
      final manifest = jsonObject(
        jsonDecode(manifestFile.readAsStringSync()),
        'manifest',
      );
      final entry = jsonObject(manifest['database'], 'backup database');
      final bytes = database.readAsBytesSync();
      entry['bytes'] = bytes.length;
      entry['sha256'] = sha256.convert(bytes).toString();
      manifestFile.writeAsStringSync(jsonEncode(manifest));
      final nativeError = await failure(
        () => NativeBackup.validateDatabase('$dir/native/database.sqlite'),
      );
      check(
        nativeError.message.contains('equipment that is not published'),
        'native backups validate instance references',
      );
      check(
        canonicalJson((await store.archive()).toJson()) == expected,
        'live profile is untouched by validation failures',
      );
    }),
  );
  test(
    'v58 profiles migrate and empty or forged inventory portability is rejected by older labels',
    () => _withStore((store, dir) async {
      // Before any inventory exists the empty sections stay absent-equivalent.
      await LogicalArchiveFiles.export(
        await store.archive(),
        '$dir/clean.json',
      );
      final clean = jsonObject(
        jsonDecode(await File('$dir/clean.json').readAsString()),
        'logical',
      );
      clean['format'] = 'bodytmi-logical-export/58';
      await File('$dir/clean.json')
        ..writeAsStringSync(jsonEncode(await _resign(clean)));
      final cleanPrepared = await LogicalArchiveFiles.prepare(
        '$dir/clean.json',
      );
      await cleanPrepared.close();
      final withoutInventory = canonicalJson((await store.archive()).toJson());
      await _publishInventory(store);
      final original = canonicalJson((await store.archive()).toJson());
      await store.backup('$dir/old');
      final old = sqlite3.open('$dir/old/database.sqlite');
      old.execute('DROP TABLE equipment_revisions');
      old.execute('DROP TABLE gym_revisions');
      old.execute('DROP TABLE equipment_instance_revisions');
      old.execute('DROP TABLE IF EXISTS imported_sessions');
      old.execute('DROP TABLE IF EXISTS block_progressions');
      old.userVersion = 58;
      old.close();
      equal(NativeBackup.validateDatabase('$dir/old/database.sqlite'), 58);
      await store.close();
      final migrated = await TrainingStore.open('$dir/old/database.sqlite');
      try {
        equal(
          canonicalJson((await migrated.archive()).toJson()),
          withoutInventory,
        );
        equal(
          (await migrated.backup('$dir/upgraded'))['databaseSchemaVersion'],
          69,
        );
        equal((await migrated.equipmentInstanceRevisions()).length, 0);
      } finally {
        await migrated.close();
      }
      var active = await TrainingStore.open('$dir/db.sqlite');
      try {
        await active.backup('$dir/native');
        equal(
          (await LogicalArchiveFiles.export(
            await active.archive(),
            '$dir/logical.json',
          ))['format'],
          'bodytmi-logical-export/69',
        );
        final logical = await LogicalArchiveFiles.prepare('$dir/logical.json');
        try {
          equal(logical.archive.instances.length, 3);
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
        check(
          canonicalJson((await active.archive()).toJson()) == original,
          'logical restore preserves the inventory',
        );
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
        check(
          canonicalJson((await active.archive()).toJson()) == original,
          'native restore preserves the inventory',
        );
      } finally {
        await active.close();
      }
      // Honest current content cannot claim the older logical label.
      final relabeled = jsonObject(
        jsonDecode(await File('$dir/logical.json').readAsString()),
        'logical',
      );
      relabeled['format'] = 'bodytmi-logical-export/58';
      await File('$dir/old-label.json')
        ..createSync()
        ..writeAsStringSync(jsonEncode(await _resign(relabeled)));
      final oldLabel = await failure(
        () => LogicalArchiveFiles.prepare('$dir/old-label.json'),
      );
      check(
        oldLabel.message.contains('Unknown fields: equipment'),
        'older logical labels reject the inventory sections',
      );
      // A v59 label without the instance section is rejected as incomplete.
      final missing = jsonObject(
        jsonDecode(await File('$dir/logical.json').readAsString()),
        'logical',
      );
      jsonObject(missing['data'], 'data').remove('instances');
      await File('$dir/missing.json')
        ..createSync()
        ..writeAsStringSync(jsonEncode(await _resign(missing)));
      final required = await failure(
        () => LogicalArchiveFiles.prepare('$dir/missing.json'),
      );
      check(
        required.message.contains('requires equipment instance revisions'),
        'the v59 format requires the instance section',
      );
      final labeled = sqlite3.open('$dir/native/database.sqlite');
      labeled.userVersion = 58;
      labeled.close();
      final nativeError = await failure(
        () => NativeBackup.validateDatabase('$dir/native/database.sqlite'),
      );
      check(
        nativeError.message.contains('does not match supported schema'),
        'a v59 profile cannot claim the older schema label',
      );
    }),
  );
  test(
    'equipment CLI authoring reports revisions and rejects invalid input with stable exit codes',
    () => _withStore((store, dir) async {
      await store.close();
      Future<({int code, String output, String error})> cmd(
        String action,
        Map<String, Object?> input,
      ) => invoke(
        action.split(' '),
        jsonEncode({
          'schemaVersion': 1,
          'database': '$dir/db.sqlite',
          ...input,
        }),
      );
      final published = await cmd('equipment publish', {
        'expectedRevision': 0,
        'equipment': {'id': 'rack', 'name': 'Rack'},
      });
      equal(published.code, 0);
      final gym = await cmd('gym publish', {
        'expectedRevision': 0,
        'gym': {'id': 'garage'},
      });
      equal(gym.code, 0);
      final instance = await cmd('instance publish', {
        'expectedRevision': 0,
        'instance': {
          'id': 'rack-1',
          'equipmentId': 'rack',
          'gym': 'garage',
          'scale': {
            'id': 'rack-1-positions',
            'unit': 'kg',
            'range': {'start': '2.5', 'step': '2.5', 'count': 4},
          },
        },
      });
      equal(instance.code, 0);
      check(
        instance.output.contains('"range"') &&
            instance.output.contains('"start":"2.5"'),
        'the compact range is retained in the published revision',
      );
      final orphan = await cmd('instance publish', {
        'expectedRevision': 0,
        'instance': {'id': 'ghost', 'equipmentId': 'unpublished'},
      });
      equal(orphan.code, 3);
      final invalid = await cmd('instance publish', {
        'expectedRevision': 0,
        'instance': {
          'id': 'bad',
          'equipmentId': 'rack',
          'scale': {'id': 'bad-scale', 'unit': 'kg', 'ticks': <Object?>[]},
        },
      });
      equal(invalid.code, 2);
      final stale = await cmd('equipment publish', {
        'expectedRevision': 0,
        'equipment': {'id': 'rack', 'name': 'Rack!'},
      });
      equal(stale.code, 5);
      final shown = await cmd('instance show', {'instanceId': 'rack-1'});
      equal(shown.code, 0);
      check(
        jsonDecode(shown.output)['data']['instance']['gym'] == 'garage',
        'show returns the frozen placement',
      );
      final pinned = await cmd('equipment show', {
        'equipmentId': 'rack',
        'revision': 1,
      });
      equal(pinned.code, 0);
      final listed = await cmd('instance list', {});
      equal(jsonDecode(listed.output)['data'].length, 1);
      final inventory = await cmd('instance inventory', {'gymId': 'garage'});
      equal(inventory.code, 0);
      equal(jsonDecode(inventory.output)['data'].length, 1);
      final empty = await cmd('instance inventory', {'gymId': 'nowhere'});
      equal(empty.code, 0);
      jsonEqual(jsonDecode(empty.output)['data'], []);
      final missingShow = await cmd('gym show', {'gymId': 'nowhere'});
      equal(missingShow.code, 3);
    }),
  );
  test(
    'process death rolls inventory publication back or commits complete immutable revisions',
    () => _withStore((store, dir) async {
      await store.close();
      final binary = await compileNative(
        'test/helpers/store_owner.dart',
        '$dir/owner',
      );
      for (final mode in ['equipment-rollback', 'equipment-commit']) {
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
            (await recovered.equipmentRevisions()).length,
            committed ? 1 : 0,
          );
          equal((await recovered.gymRevisions()).length, committed ? 1 : 0);
          equal(
            (await recovered.equipmentInstanceRevisions()).length,
            committed ? 1 : 0,
          );
          if (committed) {
            equal(
              (await EquipmentService(
                recovered,
              ).instanceRevision('rack-1')).instance.gymId,
              'garage',
            );
          }
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
  throw StateError('Expected a BodyTmiException.');
}

Future<void> _fails(Future<Object?> Function() action) =>
    expectLater(action(), throwsA(isA<BodyTmiException>()));
