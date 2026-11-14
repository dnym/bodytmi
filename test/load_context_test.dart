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

final Map<String, Object?> _barLoading = {
  'components': [
    {
      'id': 'bar',
      'kind': 'bar',
      'mass': {'value': '20', 'unit': 'kg'},
    },
  ],
  'channel': {'id': 'barbell', 'sides': 2, 'symmetry': 'required'},
  'plates': [
    {
      'mass': {'value': '20', 'unit': 'kg'},
      'count': 2,
    },
  ],
};

Map<String, Object?> _slot(
  String id, {
  Object? convention,
  String? equipment,
}) => {
  'id': id,
  'exercise': 'bench-press',
  'implementation': 'barbell',
  'targets': {
    'mass': {'value': '60', 'unit': 'kg'},
    'reps': {'value': '5', 'unit': 'rep'},
  },
  'prefill': <String>[],
  if (equipment != null) 'equipment': equipment,
  if (convention != null) 'convention': convention,
};

Map<String, Object?> _workout(String id, List<Map<String, Object?>> slots) => {
  'id': id,
  'name': 'Load context practice',
  'slots': slots,
  'plan': {
    'id': 'workout',
    'type': 'sequence',
    'children': [
      {'id': 'set-1', 'type': 'effort', 'slot': slots.first['id']},
    ],
  },
};

EquipmentDefinition _equipment(String id) =>
    EquipmentDefinition.fromJson({'id': id});
GymDefinition _gym(String id) => GymDefinition.fromJson({'id': id});
EquipmentInstance _instance(
  String id,
  String equipmentId, {
  Object? loading,
  Object? convention,
  String? notes,
}) => EquipmentInstance.fromJson({
  'id': id,
  'equipmentId': equipmentId,
  'gym': 'garage',
  if (loading != null) 'loading': loading,
  if (convention != null) 'convention': convention,
  if (notes != null) 'notes': notes,
});

LoadInstanceReference _reference(
  EquipmentInstance instance, {
  int revision = 1,
}) => LoadInstanceReference(instance.id, instance, revision);

Future<void> _withStore(
  Future<void> Function(TrainingStore, String) action,
) async {
  final dir = await Directory.systemTemp.createTemp('bodytmi-load-context-');
  final store = await TrainingStore.open('${dir.path}/db.sqlite');
  try {
    await action(store, dir.path);
  } finally {
    await store.close();
    await dir.delete(recursive: true);
  }
}

/// Publishes the shared equipment chain and a single bound-slot workout.
Future<void> _seed(TrainingStore store) async {
  final equipment = EquipmentService(store);
  await equipment.publishEquipment(_equipment('barbell'), 0);
  await equipment.publishEquipment(_equipment('dumbbell-pair'), 0);
  await equipment.publishGym(_gym('garage'), 0);
  await equipment.publishInstance(
    _instance(
      'garage-bar',
      'barbell',
      loading: _barLoading,
      convention: {'massBasis': 'assembly-total'},
    ),
    0,
  );
  await equipment.publishInstance(
    _instance('garage-dumbbell', 'dumbbell-pair'),
    0,
  );
  await StoredTrainingService(store).publish(
    WorkoutDefinition.fromJson(
      _workout('bench-practice', [_slot('bench', equipment: 'barbell')]),
    ),
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

Future<BodyTmiException> failure(Object? Function() action) async {
  try {
    await action();
  } on BodyTmiException catch (error) {
    return error;
  }
  throw StateError('Expected a BodyTmiException.');
}

BodyTmiException syncFailure(void Function() action) {
  try {
    action();
  } on BodyTmiException catch (error) {
    return error;
  }
  throw StateError('Expected a BodyTmiException.');
}

void loadContextTests() {
  test('load input snapshots resolve precedence exactly once', () {
    final instance = _instance(
      'garage-bar',
      'barbell',
      loading: _barLoading,
      convention: {'massBasis': 'assembly-total'},
    );
    final slotConvention = LoadConvention.fromJson({
      'massBasis': 'per-implement',
      'implements': 2,
    });
    final sessionConvention = LoadConvention.fromJson({
      'massBasis': 'added-load',
    });

    final override = LoadInputSnapshot.capture(
      sessionConvention: sessionConvention,
      slotConvention: slotConvention,
      instance: _reference(instance),
    );
    equal(override.source, 'session');
    equal(override.convention!.massBasis, 'added-load');

    final slot = LoadInputSnapshot.capture(
      slotConvention: slotConvention,
      instance: _reference(instance),
    );
    equal(slot.source, 'slot');
    equal(slot.convention!.massBasis, 'per-implement');

    final defaultSource = LoadInputSnapshot.capture(
      instance: _reference(instance),
    );
    equal(defaultSource.source, 'instance');
    equal(defaultSource.convention!.massBasis, 'assembly-total');

    final none = LoadInputSnapshot.capture();
    equal(none.source, 'none');
    check(none.isTrivial, 'nothing declared stays trivial');
    final instanceOnly = LoadInputSnapshot.capture(
      instance: _reference(_instance('plain-rack', 'barbell')),
    );
    equal(instanceOnly.source, 'none');
    check(
      !instanceOnly.isTrivial,
      'an instance binding without a convention is still recorded',
    );

    // Capability is checked against the bound instance at capture.
    rejects(
      () => LoadInputSnapshot.capture(
        sessionConvention: LoadConvention.fromJson({'massBasis': 'per-side'}),
      ),
    );

    // A session capture round-trips and its forgeries are rejected.
    jsonEqual(
      LoadInputSnapshot.fromJson(defaultSource.toJson()).toJson(),
      defaultSource.toJson(),
    );
    final forgedSource = Map<String, Object?>.from(slot.toJson());
    forgedSource['source'] = 'instance';
    equal(
      syncFailure(() => LoadInputSnapshot.fromJson(forgedSource)).message,
      'An instance convention source must match the instance default.',
    );
    final droppedSource = Map<String, Object?>.from(defaultSource.toJson());
    droppedSource['source'] = 'none';
    droppedSource.remove('convention');
    equal(
      syncFailure(() => LoadInputSnapshot.fromJson(droppedSource)).message,
      'An instance default convention was not captured.',
    );
    final conventionless = Map<String, Object?>.from(slot.toJson());
    conventionless.remove('convention');
    rejects(() => LoadInputSnapshot.fromJson(conventionless));

    rejects(() => LoadInstanceReference(instance.id, instance, 0));
    rejects(() => LoadInstanceReference('other-instance', instance, 1));
  });

  test('captures are cross-checked against the pinned slot composition', () {
    final instance = _instance(
      'garage-bar',
      'barbell',
      loading: _barLoading,
      convention: {'massBasis': 'assembly-total'},
    );
    final slotConvention = LoadConvention.fromJson({'massBasis': 'per-side'});
    final capture = LoadInputSnapshot.capture(
      slotConvention: slotConvention,
      instance: _reference(instance),
    );
    capture.matchesSlot(
      slotId: 'bench',
      slotConvention: slotConvention,
      slotEquipmentId: 'barbell',
    );
    final drifted = syncFailure(() {
      capture.matchesSlot(
        slotId: 'bench',
        slotConvention: LoadConvention.fromJson({'massBasis': 'per-implement'}),
        slotEquipmentId: 'barbell',
      );
    });
    check(
      drifted.message.contains('does not match the pinned slot'),
      'a drifted slot convention is rejected',
    );
    final foreignEquipment = syncFailure(() {
      capture.matchesSlot(
        slotId: 'bench',
        slotConvention: slotConvention,
        slotEquipmentId: 'dumbbell-pair',
      );
    });
    check(
      foreignEquipment.message.contains(
        'does not belong to the slot equipment',
      ),
      'the instance must belong to the slot equipment',
    );

    // Only a session override may come from outside the pinned composition.
    final override = LoadInputSnapshot.capture(
      sessionConvention: LoadConvention.fromJson({'massBasis': 'added-load'}),
      instance: _reference(instance),
    );
    override.matchesSlot(
      slotId: 'bench',
      slotConvention: null,
      slotEquipmentId: 'barbell',
    );
    final impossible = syncFailure(() {
      LoadInputSnapshot.capture(
        sessionConvention: LoadConvention.fromJson({'massBasis': 'per-side'}),
        instance: _reference(_instance('plain-bench', 'barbell')),
      ).matchesSlot(
        slotId: 'bench',
        slotConvention: null,
        slotEquipmentId: null,
      );
    });
    check(
      impossible.message.contains('declared loading configuration'),
      'capability is enforced, never trusted from a stored capture',
    );
  });

  test('pure session start freezes load contexts and rejects mismatches', () {
    final definition = WorkoutDefinition.fromJson(
      _workout('bench-practice', [_slot('bench', equipment: 'barbell')]),
    );
    final instance = _instance(
      'garage-bar',
      'barbell',
      loading: _barLoading,
      convention: {'massBasis': 'assembly-total'},
    );
    final session = const TrainingService().start(
      sessionId: 'loaded',
      revision: WorkoutRevision.publish(definition),
      startedAt: instant(10),
      loadInstances: {'bench': _reference(instance)},
    );
    equal(session.loadInputs['bench']!.source, 'instance');
    equal(session.loadInputs['bench']!.instance!.revision, 1);
    jsonEqual(
      sessionFromJson(session.toJson()).loadInputs['bench']!.toJson(),
      session.loadInputs['bench']!.toJson(),
    );

    // A session override wins over the pinned composition.
    final overridden = const TrainingService().start(
      sessionId: 'overridden',
      revision: WorkoutRevision.publish(definition),
      startedAt: instant(10),
      loadInstances: {'bench': _reference(instance)},
      loadConventions: {
        'bench': LoadConvention.fromJson({'massBasis': 'added-load'}),
      },
    );
    equal(overridden.loadInputs['bench']!.source, 'session');
    equal(overridden.loadInputs['bench']!.convention!.massBasis, 'added-load');

    // Trivial slots are never recorded.
    final plain = const TrainingService().start(
      sessionId: 'plain',
      revision: WorkoutRevision.publish(definition),
      startedAt: instant(10),
    );
    check(plain.loadInputs.isEmpty, 'no declarations, no payload');
    check(
      !plain.toJson().containsKey('loadInputs'),
      'a load-free session stays honest at older labels',
    );

    final unknownSlot = syncFailure(() {
      const TrainingService().start(
        sessionId: 'ghost',
        revision: WorkoutRevision.publish(definition),
        startedAt: instant(10),
        loadInstances: {'ghost-slot': _reference(instance)},
      );
    });
    equal(unknownSlot.message, 'Load binding names an unknown slot.');
    final foreign = syncFailure(() {
      const TrainingService().start(
        sessionId: 'foreign',
        revision: WorkoutRevision.publish(definition),
        startedAt: instant(10),
        loadInstances: {
          'bench': _reference(_instance('garage-db', 'dumbbell-pair')),
        },
      );
    });
    check(
      foreign.message.contains('garage-db') &&
          foreign.message.contains('dumbbell-pair') &&
          foreign.message.contains('bench'),
      'the mismatch names the instance, its kind and the slot',
    );

    // Forged session payloads are rejected by the codec.
    final tampered = copyJson(session.toJson());
    jsonObject(
      jsonObject(tampered['loadInputs'], 'loadInputs')['bench'],
      'load input',
    )['source'] = 'slot';
    equal(
      syncFailure(() => sessionFromJson(tampered)).message,
      'Load convention source does not match the pinned slot.',
    );
    final emptied = copyJson(session.toJson());
    emptied['loadInputs'] = <String, Object?>{};
    rejects(() => sessionFromJson(emptied));
  });

  test('load status compares frozen contexts without rewriting them', () {
    final instance = _instance(
      'garage-bar',
      'barbell',
      loading: _barLoading,
      convention: {'massBasis': 'assembly-total'},
    );
    final captured = {
      'bench': LoadInputSnapshot.capture(instance: _reference(instance)),
    };
    final same = loadStatus(
      captured,
      instances: {'bench': _reference(instance)},
    );
    equal(same['policy'], 'bodytmi-load-status/1');
    equal(same['changed'], false);

    final moved = loadStatus(
      captured,
      instances: {
        'bench': _reference(
          _instance(
            'garage-bar',
            'barbell',
            loading: _barLoading,
            convention: {'massBasis': 'added-load'},
          ),
          revision: 2,
        ),
      },
    );
    equal(moved['changed'], true);

    // A slot the session never captured stays unchanged: later authoring
    // cannot alter a frozen session context.
    final authored = loadStatus(
      captured,
      instances: {'bench': _reference(instance)},
      slotConventions: {
        'unloaded': LoadConvention.fromJson({'massBasis': 'nominal-setting'}),
      },
    );
    equal(authored['changed'], false);
    final uncaptured = loadStatus(
      const {},
      slotConventions: {
        'bench': LoadConvention.fromJson({'massBasis': 'assembly-total'}),
      },
    );
    equal(uncaptured['changed'], false);
    check(
      jsonObject(jsonList(uncaptured, 'slots').single, 'slot')['captured'] ==
          null,
      'the report shows the slot was never captured',
    );
  });

  test(
    'stored starts freeze instance revisions and keep start identity',
    () => _withStore((store, dir) async {
      await _seed(store);
      final service = StoredTrainingService(store);
      final session = await service.start(
        'loaded',
        'bench-practice',
        1,
        instant(10),
        loadBindings: {'bench': 'garage-bar'},
      );
      equal(session.loadInputs['bench']!.source, 'instance');
      equal(session.loadInputs['bench']!.instance!.revision, 1);
      equal(
        session.loadInputs['bench']!.convention!.massBasis,
        'assembly-total',
      );

      // A retry with the same request returns the same frozen session.
      final retry = await service.start(
        'loaded',
        'bench-practice',
        1,
        instant(10),
        loadBindings: {'bench': 'garage-bar'},
      );
      equal(canonicalJson(retry.toJson()), canonicalJson(session.toJson()));
      // A different load request for the same identity conflicts.
      final reconfigured = await failure(
        () => service.start(
          'loaded',
          'bench-practice',
          1,
          instant(10),
          loadBindings: {'bench': 'garage-bar'},
          loadConventions: {
            'bench': LoadConvention.fromJson({'massBasis': 'added-load'}),
          },
        ),
      );
      equal(reconfigured.code, 'conflict');
      final rebound = await failure(
        () => service.start(
          'loaded',
          'bench-practice',
          1,
          instant(10),
          loadBindings: {'bench': 'garage-dumbbell'},
        ),
      );
      equal(rebound.code, 'conflict');

      // Unknown instances and slots are errors storing nothing.
      final missing = await failure(
        () => service.start(
          'missing',
          'bench-practice',
          1,
          instant(10),
          loadBindings: {'bench': 'ghost'},
        ),
      );
      equal(missing.code, 'not_found');
      equal(missing.message, 'Equipment instance not found: ghost.');
      final ghostSlot = await failure(
        () => service.start(
          'ghost-slot',
          'bench-practice',
          1,
          instant(10),
          loadBindings: {'ghost-slot': 'garage-bar'},
        ),
      );
      equal(ghostSlot.code, 'validation');
      equal(ghostSlot.message, 'Load binding names an unknown slot.');
      final foreign = await failure(
        () => service.start(
          'foreign',
          'bench-practice',
          1,
          instant(10),
          loadBindings: {'bench': 'garage-dumbbell'},
        ),
      );
      equal(foreign.code, 'validation');
      check(
        foreign.message.contains('not the equipment declared by slot bench'),
        'the stored start enforces slot equipment membership',
      );
      final archive = (await store.archive()).toJson();
      check(
        !canonicalJson(archive).contains('"missing"'),
        'failed starts persist nothing',
      );

      // A later instance revision never rewrites the frozen session.
      await EquipmentService(store).publishInstance(
        _instance(
          'garage-bar',
          'barbell',
          loading: _barLoading,
          convention: {'massBasis': 'added-load'},
          notes: 'Re-calibrated.',
        ),
        1,
      );
      final frozen = await service.session('loaded');
      equal(frozen.loadInputs['bench']!.instance!.revision, 1);
      equal(
        frozen.loadInputs['bench']!.convention!.massBasis,
        'assembly-total',
      );

      // A fresh start consumes the new latest revision.
      final next = await service.start(
        'next',
        'bench-practice',
        1,
        instant(11),
        loadBindings: {'bench': 'garage-bar'},
      );
      equal(next.loadInputs['bench']!.instance!.revision, 2);
      equal(next.loadInputs['bench']!.convention!.massBasis, 'added-load');

      // Completion and finish retain the frozen context.
      var current = await service.session('loaded');
      current = await service.edit(
        current.id,
        current.contentVersion,
        (s) => const TrainingService().complete(s, s.sets.first.id, {
          'mass': Quantity('62.5', 'kg'),
          'reps': Quantity('5', 'rep'),
        }),
      );
      current = await service.edit(
        current.id,
        current.contentVersion,
        (s) => s.finish(instant(11)),
      );
      check(current.finishedAt != null, 'the session finished');
      final finished = await service.session('loaded');
      equal(finished.loadInputs['bench']!.instance!.revision, 1);

      // Load status reports the newer instance without rewriting anything.
      final revisions = await store.equipmentInstanceRevisions();
      final latest = revisions
          .where((r) => r.instance.id == 'garage-bar')
          .fold<EquipmentInstanceRevision?>(
            null,
            (a, b) => a == null || b.number > a.number ? b : a,
          )!;
      final status = loadStatus(
        finished.loadInputs,
        slotConventions: {
          for (final s in finished.revision.definition.slots)
            s.id: s.convention,
        },
        instances: {
          'bench': LoadInstanceReference(
            latest.instance.id,
            latest.instance,
            latest.number,
          ),
        },
      );
      equal(status['changed'], true);
      final stillFrozen = await service.session('loaded');
      equal(stillFrozen.loadInputs['bench']!.instance!.revision, 1);
    }),
  );

  test(
    'load contexts are portable only under v62 formats',
    () => _withStore((store, dir) async {
      await _seed(store);
      await StoredTrainingService(store).start(
        'loaded',
        'bench-practice',
        1,
        instant(10),
        loadBindings: {'bench': 'garage-bar'},
      );
      final original = canonicalJson((await store.archive()).toJson());
      await store.backup('$dir/native');
      final exported = await LogicalArchiveFiles.export(
        await store.archive(),
        '$dir/logical.json',
      );
      equal(exported['format'], 'bodytmi-logical-export/64');
      final logical = await LogicalArchiveFiles.prepare('$dir/logical.json');
      try {
        check(
          logical.archive.sessions.single.loadInputs.isNotEmpty,
          'the logical export retains the frozen load context',
        );
        await store.restore(
          logical.backup,
          recoveryDestination: '$dir/recovery',
          confirm: true,
        );
      } finally {
        await logical.close();
      }
      await store.close();
      var active = await TrainingStore.open('$dir/db.sqlite');
      try {
        equal(canonicalJson((await active.archive()).toJson()), original);
        final native = await NativeBackup.prepare('$dir/native');
        try {
          await active.restore(
            native,
            recoveryDestination: '$dir/recovery2',
            confirm: true,
          );
        } finally {
          await native.close();
        }
      } finally {
        await active.close();
      }
      active = await TrainingStore.open('$dir/db.sqlite');
      try {
        equal(canonicalJson((await active.archive()).toJson()), original);
        equal(
          (await active.archive())
              .sessions
              .single
              .loadInputs
              .entries
              .single
              .value
              .instance!
              .revision,
          1,
        );
      } finally {
        await active.close();
      }

      // Honest current content cannot claim the previous label.
      final relabeled = jsonObject(
        jsonDecode(await File('$dir/logical.json').readAsString()),
        'logical',
      );
      relabeled['format'] = 'bodytmi-logical-export/61';
      await File('$dir/old-label.json')
        ..createSync()
        ..writeAsStringSync(jsonEncode(await _resign(relabeled)));
      final logicalError = await failure(
        () => LogicalArchiveFiles.prepare('$dir/old-label.json'),
      );
      check(
        logicalError.message.contains('load contexts require logical v62'),
        'older logical labels reject frozen load contexts',
      );

      // The same profile without any load context is genuinely older shaped.
      final plain = copyJson(relabeled);
      for (final item in jsonObject(plain['data'], 'data')['sessions'] as List)
        jsonObject(item, 'session').remove('loadInputs');
      plain['format'] = 'bodytmi-logical-export/61';
      await File('$dir/plain-label.json')
        ..createSync()
        ..writeAsStringSync(jsonEncode(await _resign(plain)));
      final stripped = await LogicalArchiveFiles.prepare(
        '$dir/plain-label.json',
      );
      try {
        check(
          stripped.archive.sessions.single.loadInputs.isEmpty,
          'a load-free session is genuinely older shaped',
        );
      } finally {
        await stripped.close();
      }

      final db = sqlite3.open('$dir/native/database.sqlite');
      db.execute('DROP TABLE IF EXISTS imported_sessions');
      db.userVersion = 61;
      db.close();
      final nativeError = await failure(
        () => NativeBackup.validateDatabase('$dir/native/database.sqlite'),
      );
      check(
        nativeError.message.contains('load contexts require schema v62'),
        'an older schema label cannot carry a frozen load context',
      );
    }),
  );

  test(
    'a genuinely load-free profile stays honest under older labels',
    () => _withStore((store, dir) async {
      final plainStore = await TrainingStore.open('$dir/plain.sqlite');
      try {
        await StoredTrainingService(plainStore).publish(definition(), 0);
        await plainStore.backup('$dir/plain-native');
      } finally {
        await plainStore.close();
      }
      final db = sqlite3.open('$dir/plain-native/database.sqlite');
      db.execute('DROP TABLE IF EXISTS imported_sessions');
      db.userVersion = 61;
      db.close();
      await NativeBackup.validateDatabase('$dir/plain-native/database.sqlite');
      check(true, 'a load-free profile passes the older schema label');
    }),
  );

  test(
    'load context CLI commands start, report and reject bad input',
    () => _withStore((store, dir) async {
      final equipment = EquipmentService(store);
      await equipment.publishEquipment(_equipment('gym-bar-1'), 0);
      await equipment.publishGym(_gym('garage'), 0);
      await equipment.publishInstance(
        EquipmentInstance.fromJson(
          jsonObject(example('load-context-instance')['instance'], 'instance'),
        ),
        0,
      );
      await StoredTrainingService(store).publish(definition(), 0);
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

      final started = await cmd('store start', {
        ...example('load-context-session'),
        'database': '$dir/db.sqlite',
      });
      equal(started.code, 0);
      check(
        started.output.contains('"source":"session"') &&
            started.output.contains('"massBasis":"added-load"'),
        'the public example records a session override over the instance',
      );

      final status = await cmd('store load-status', {
        'id': 'loaded-row-session',
      });
      equal(status.code, 0);
      check(
        status.output.contains('"policy":"bodytmi-load-status/1"') &&
            status.output.contains('"changed":false'),
        'unchanged sources report an unchanged context',
      );

      // The pure query sees the same frozen context.
      final sessionJson = jsonObject(
        jsonDecode(started.output)['data'],
        'data',
      );
      final pureStatus = await invoke(
        ['session', 'load-status'],
        jsonEncode({
          'schemaVersion': 1,
          'session': sessionJson,
          'instances': {
            'bench-heavy': {
              'instanceId': 'garage-bar-1',
              'revision': 1,
              'snapshot': jsonObject(
                example('load-context-instance')['instance'],
                'instance',
              ),
            },
          },
        }),
      );
      equal(pureStatus.code, 0);
      check(
        pureStatus.output.contains('"changed":false'),
        'the pure status agrees with the stored status',
      );

      final missing = await cmd('store start', {
        'id': 'ghost-start',
        'templateId': 'upper-a',
        'revision': 1,
        'startedAt': '2026-11-14T09:00:00+00:00',
        'loadBindings': {'bench-heavy': 'ghost-instance'},
      });
      equal(missing.code, 3);
      final badSlot = await cmd('store start', {
        'id': 'bad-slot',
        'templateId': 'upper-a',
        'revision': 1,
        'startedAt': '2026-11-14T09:00:00+00:00',
        'loadBindings': {'ghost-slot': 'garage-bar-1'},
      });
      equal(badSlot.code, 2);
      final badConvention = await cmd('store start', {
        'id': 'bad-convention',
        'templateId': 'upper-a',
        'revision': 1,
        'startedAt': '2026-11-14T09:00:00+00:00',
        'loadConventions': {
          'bench-heavy': {'massBasis': 'per-side'},
        },
      });
      equal(badConvention.code, 2);
      check(
        badConvention.error.contains('declared loading configuration'),
        'the CLI reports the missing capability',
      );
    }),
  );
}
