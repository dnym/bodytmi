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
    {
      'mass': {'value': '10', 'unit': 'kg'},
      'count': 2,
    },
    {
      'mass': {'value': '2.5', 'unit': 'kg'},
      'count': 2,
    },
  ],
};

final Map<String, Object?> _hornLoading = {
  'components': [
    {
      'id': 'carriage',
      'kind': 'tare',
      'mass': {'value': '5', 'unit': 'kg'},
    },
  ],
  'channel': {'id': 'horns', 'sides': 2, 'symmetry': 'independent'},
  'plates': [
    {
      'mass': {'value': '20', 'unit': 'kg'},
      'count': 2,
    },
    {
      'mass': {'value': '10', 'unit': 'kg'},
      'count': 1,
    },
  ],
};

Map<String, Object?> _slot(String id, {String? equipment}) => {
  'id': id,
  'exercise': 'bench-press',
  'implementation': 'barbell',
  'targets': {
    'mass': {'value': '85', 'unit': 'kg'},
    'reps': {'value': '5', 'unit': 'rep'},
  },
  'prefill': <String>[],
  if (equipment != null) 'equipment': equipment,
};

Map<String, Object?> _workout(String id, List<Map<String, Object?>> slots) => {
  'id': id,
  'name': 'Arrangement practice',
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

LoadArrangement _arrangement(
  List<Map<String, Object?>> plates, {
  String instanceId = 'garage-bar',
  String channel = 'barbell',
}) => LoadArrangement.fromJson({
  'instanceId': instanceId,
  'channel': channel,
  'plates': plates,
});

LoadInstanceReference _reference(
  EquipmentInstance instance, {
  int revision = 1,
}) => LoadInstanceReference(instance.id, instance, revision);

Future<void> _withStore(
  Future<void> Function(TrainingStore, String) action,
) async {
  final dir = await Directory.systemTemp.createTemp('bodytmi-load-arrange-');
  final store = await TrainingStore.open('${dir.path}/db.sqlite');
  try {
    await action(store, dir.path);
  } finally {
    await store.close();
    await dir.delete(recursive: true);
  }
}

Future<void> _seed(TrainingStore store) async {
  final equipment = EquipmentService(store);
  await equipment.publishEquipment(_equipment('barbell'), 0);
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

void loadArrangementTests() {
  test('arrangement structure and stock feasibility are exact', () {
    final loading = LoadingSpec.fromJson(_barLoading);

    // Entered plates sort deterministically by canonical mass descending.
    final stacked = _arrangement([
      {
        'mass': {'value': '2.5', 'unit': 'kg'},
        'count': 2,
      },
      {
        'mass': {'value': '20', 'unit': 'kg'},
        'count': 2,
      },
      {
        'mass': {'value': '10', 'unit': 'kg'},
        'count': 2,
      },
    ]);
    equal(stacked.plates.first.mass.value.toString(), '20');
    equal(stacked.channelMass.toString(), '65');

    // The same denomination entered twice, even with different trailing
    // digits, collides.
    equal(
      syncFailure(
        () => _arrangement([
          {
            'mass': {'value': '20', 'unit': 'kg'},
            'count': 2,
          },
          {
            'mass': {'value': '20.00', 'unit': 'kg'},
            'count': 1,
          },
        ]),
      ).message,
      'Plate arrangement denominations must be distinct.',
    );
    rejects(() => _arrangement([]));
    rejects(
      () => _arrangement([
        {
          'mass': {'value': '20', 'unit': 'kg'},
          'count': 0,
        },
      ]),
    );
    rejects(
      () => _arrangement([
        {
          'mass': {'value': '0', 'unit': 'kg'},
          'count': 1,
        },
      ]),
    );

    // Stock keys match canonically, never by entered spelling.
    _arrangement([
      {
        'mass': {'value': '2.50', 'unit': 'kg'},
        'count': 2,
      },
    ]).validateAgainst(loading);
    final foreign = syncFailure(
      () => _arrangement([
        {
          'mass': {'value': '5', 'unit': 'kg'},
          'count': 2,
        },
      ]).validateAgainst(loading),
    );
    check(
      foreign.message.contains('outside the declared inventory: 5 kg.'),
      'undeclared denominations are named, ${foreign.message}',
    );
    final overrun = syncFailure(
      () => _arrangement([
        {
          'mass': {'value': '20', 'unit': 'kg'},
          'count': 4,
        },
      ]).validateAgainst(loading),
    );
    check(
      overrun.message.contains('exceeds the declared count of 20 kg plates.'),
      'stock counts bound every denomination, ${overrun.message}',
    );
    final oddSplit = syncFailure(
      () => _arrangement([
        {
          'mass': {'value': '20', 'unit': 'kg'},
          'count': 1,
        },
      ]).validateAgainst(loading),
    );
    check(
      oddSplit.message.contains('split equally across its sides'),
      'a symmetric channel cannot claim a one-sided plate, ${oddSplit.message}',
    );
    final otherChannel = syncFailure(
      () => _arrangement([
        {
          'mass': {'value': '20', 'unit': 'kg'},
          'count': 2,
        },
      ], channel: 'horns').validateAgainst(loading),
    );
    equal(
      otherChannel.message,
      'Plate arrangement channel does not match the instance.',
    );
  });

  test('side splits are equal for symmetric and balanced for independent', () {
    final barbell = LoadingSpec.fromJson(_barLoading);
    final symmetric = _arrangement([
      {
        'mass': {'value': '20', 'unit': 'kg'},
        'count': 2,
      },
      {
        'mass': {'value': '10', 'unit': 'kg'},
        'count': 2,
      },
    ]);
    final sides = arrangementSides(symmetric, barbell);
    equal(sides.length, 2);
    for (final side in sides) {
      equal(side.length, 2);
      equal(side.first.mass.value.toString(), '20');
      equal(side.first.count, 1);
    }

    final horns = LoadingSpec.fromJson(_hornLoading);
    final uneven = LoadArrangement.fromJson({
      'instanceId': 'machine-a',
      'channel': 'horns',
      'plates': [
        {
          'mass': {'value': '20', 'unit': 'kg'},
          'count': 2,
        },
        {
          'mass': {'value': '10', 'unit': 'kg'},
          'count': 1,
        },
      ],
    });
    uneven.validateAgainst(horns);
    final split = arrangementSides(uneven, horns);
    equal(split.length, 2);
    equal(split[0].length, 2); // 20 + 10
    equal(split[1].length, 1); // 20
    var displayed = Decimal.zero;
    for (final side in split)
      for (final usage in side)
        displayed += usage.mass.value * Decimal.parse('${usage.count}');
    equal(displayed.toString(), '50');
  });

  test(
    'arrangements record only for completed sets and clear with confirm',
    () {
      final definition = WorkoutDefinition.fromJson(
        _workout('bench-practice', [_slot('bench', equipment: 'barbell')]),
      );
      final instance = _instance(
        'garage-bar',
        'barbell',
        loading: _barLoading,
        convention: {'massBasis': 'assembly-total'},
      );
      var session = const TrainingService().start(
        sessionId: 'arranged',
        revision: WorkoutRevision.publish(definition),
        startedAt: instant(10),
        loadInstances: {'bench': _reference(instance)},
      );
      final setId = session.sets.first.id;
      final stack = _arrangement([
        {
          'mass': {'value': '20', 'unit': 'kg'},
          'count': 2,
        },
        {
          'mass': {'value': '10', 'unit': 'kg'},
          'count': 2,
        },
        {
          'mass': {'value': '2.5', 'unit': 'kg'},
          'count': 2,
        },
      ]);

      final planned = syncFailure(
        () => const TrainingService().arrange(session, setId, stack),
      );
      equal(
        planned.message,
        'Plate arrangements record only for completed sets.',
      );

      session = const TrainingService().complete(session, setId, {
        'mass': Quantity('85', 'kg'),
        'reps': Quantity('5', 'rep'),
      });
      var before = session.set(setId).contentVersion;
      session = const TrainingService().arrange(session, setId, stack);
      equal(session.set(setId).loadArrangement!.plates.length, 3);
      check(
        session.set(setId).contentVersion == before + 1,
        'recording bumps the set version',
      );

      // Replacing is allowed without confirmation; clearing is not.
      session = const TrainingService().arrange(
        session,
        setId,
        _arrangement([
          {
            'mass': {'value': '20', 'unit': 'kg'},
            'count': 2,
          },
        ]),
      );
      equal(session.set(setId).loadArrangement!.plates.length, 1);
      equal(
        syncFailure(
          () => const TrainingService().arrange(session, setId, null),
        ).message,
        'Confirm before clearing a recorded plate arrangement.',
      );
      session = const TrainingService().arrange(
        session,
        setId,
        null,
        confirm: true,
      );
      check(
        session.set(setId).loadArrangement == null,
        'confirmed clearing removes the stack',
      );

      // Corrections keep the stack; skipping discards it.
      session = const TrainingService().arrange(session, setId, stack);
      session = const TrainingService().complete(session, setId, {
        'mass': Quantity('85', 'kg'),
        'reps': Quantity('4', 'rep'),
      });
      check(
        session.set(setId).loadArrangement != null,
        'a corrected result keeps the recorded stack',
      );
      session = const TrainingService().complete(session, setId, {
        'mass': Quantity('85', 'kg'),
        'reps': Quantity('4', 'rep'),
      });
      session = const TrainingService().skip(session, setId, confirm: true);
      check(
        session.set(setId).loadArrangement == null,
        'a confirmed skip discards the stack',
      );
      rejects(() => const TrainingService().arrange(session, setId, stack));

      // Round-trips retain the stack.
      session = const TrainingService().complete(session, setId, {
        'mass': Quantity('85', 'kg'),
        'reps': Quantity('5', 'rep'),
      });
      session = const TrainingService().arrange(session, setId, stack);
      jsonEqual(
        sessionFromJson(session.toJson()).set(setId).toJson(),
        session.set(setId).toJson(),
      );
      equal(
        sessionFromJson(session.toJson()).set(setId).loadArrangement!.channel,
        'barbell',
      );
    },
  );

  test('arrangements require the frozen binding and codec forgery fails', () {
    final definition = WorkoutDefinition.fromJson(
      _workout('bench-practice', [_slot('bench', equipment: 'barbell')]),
    );
    final instance = _instance(
      'garage-bar',
      'barbell',
      loading: _barLoading,
      convention: {'massBasis': 'assembly-total'},
    );
    final stack = _arrangement([
      {
        'mass': {'value': '20', 'unit': 'kg'},
        'count': 2,
      },
    ]);

    // A session without a frozen instance binding cannot record stacks.
    var plain = const TrainingService().start(
      sessionId: 'plain',
      revision: WorkoutRevision.publish(definition),
      startedAt: instant(10),
    );
    plain = const TrainingService().complete(plain, plain.sets.first.id, {
      'mass': Quantity('85', 'kg'),
      'reps': Quantity('5', 'rep'),
    });
    equal(
      syncFailure(
        () =>
            const TrainingService().arrange(plain, plain.sets.first.id, stack),
      ).message,
      'A plate arrangement requires a frozen session load binding.',
    );

    // An undeclared-loading instance has no arrangements at all.
    var unloaded = const TrainingService().start(
      sessionId: 'unloaded',
      revision: WorkoutRevision.publish(
        WorkoutDefinition.fromJson(
          _workout('other-practice', [_slot('bench', equipment: 'barbell')]),
        ),
      ),
      startedAt: instant(10),
      loadInstances: {'bench': _reference(_instance('plain-bar', 'barbell'))},
    );
    unloaded = const TrainingService().complete(
      unloaded,
      unloaded.sets.first.id,
      {'mass': Quantity('85', 'kg'), 'reps': Quantity('5', 'rep')},
    );
    equal(
      syncFailure(
        () => const TrainingService().arrange(
          unloaded,
          unloaded.sets.first.id,
          _arrangement([
            {
              'mass': {'value': '20', 'unit': 'kg'},
              'count': 2,
            },
          ], instanceId: 'plain-bar'),
        ),
      ).message,
      'A plate arrangement requires an instance with declared loading.',
    );

    // A stack naming another instance is inconsistent even if valid there.
    var session = const TrainingService().start(
      sessionId: 'bound',
      revision: WorkoutRevision.publish(definition),
      startedAt: instant(10),
      loadInstances: {'bench': _reference(instance)},
    );
    session = const TrainingService().complete(session, session.sets.first.id, {
      'mass': Quantity('85', 'kg'),
      'reps': Quantity('5', 'rep'),
    });
    final foreign = syncFailure(
      () => const TrainingService().arrange(
        session,
        session.sets.first.id,
        _arrangement([
          {
            'mass': {'value': '20', 'unit': 'kg'},
            'count': 2,
          },
        ], instanceId: 'other-bar'),
      ),
    );
    equal(
      foreign.message,
      'Plate arrangement instance identity is inconsistent.',
    );

    // Stored payloads are re-validated: stripped bindings, invented plates
    // and planned-set stacks all fail the codec.
    session = const TrainingService().arrange(
      session,
      session.sets.first.id,
      stack,
    );
    final stripped = copyJson(session.toJson());
    stripped.remove('loadInputs');
    equal(
      syncFailure(() => sessionFromJson(stripped)).message,
      'A plate arrangement requires a frozen session load binding.',
    );
    final invented = copyJson(session.toJson());
    jsonObject(
      jsonList(invented, 'sets').cast<Map<String, Object?>>().first,
      'set',
    )['loadArrangement'] = {
      'instanceId': 'garage-bar',
      'channel': 'barbell',
      'plates': [
        {
          'mass': {'value': '1000', 'unit': 'kg'},
          'count': 2,
        },
      ],
    };
    check(
      syncFailure(
        () => sessionFromJson(invented),
      ).message.contains('outside the declared inventory: 1000 kg.'),
      'invented denominations cannot enter a stored session',
    );
    final onPlanned = copyJson(
      const TrainingService()
          .start(
            sessionId: 'planned-attempt',
            revision: WorkoutRevision.publish(definition),
            startedAt: instant(10),
            loadInstances: {'bench': _reference(instance)},
          )
          .toJson(),
    );
    jsonObject(
      jsonList(onPlanned, 'sets').cast<Map<String, Object?>>().first,
      'set',
    )['loadArrangement'] = stack
        .toJson();
    equal(
      syncFailure(() => sessionFromJson(onPlanned)).message,
      'Plate arrangements record only for completed sets.',
    );
  });

  test(
    'stored arrangements report feasibility and plan agreement',
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
      final setId = session.sets.first.id;
      var current = await service.edit(
        'loaded',
        session.contentVersion,
        (s) => const TrainingService().complete(s, setId, {
          'mass': Quantity('85', 'kg'),
          'reps': Quantity('5', 'rep'),
        }),
      );
      current = await service.edit(
        'loaded',
        current.contentVersion,
        (s) => const TrainingService().arrange(
          s,
          setId,
          _arrangement([
            {
              'mass': {'value': '20', 'unit': 'kg'},
              'count': 2,
            },
            {
              'mass': {'value': '10', 'unit': 'kg'},
              'count': 2,
            },
            {
              'mass': {'value': '2.5', 'unit': 'kg'},
              'count': 2,
            },
          ]),
        ),
      );
      equal(current.set(setId).loadArrangement!.plates.length, 3);

      var status = await EquipmentService(store).arrangeStatus('loaded');
      equal(status['policy'], 'bodytmi-load-arrangement-status/1');
      equal(status['changed'], false);
      var block = jsonObject(jsonList(status, 'sets').single, 'block');
      equal(block['frozenRevision'], 1);
      equal(block['currentRevision'], 1);
      equal(block['feasibleUnderCurrent'], true);
      equal(block['freshPlan'], 'planned');
      equal(
        jsonObject(
          jsonObject(block['computed'], 'computed')['totalMass'],
          'totalMass',
        )['value'],
        '85',
      );
      equal(
        jsonObject(block['massRelation'], 'massRelation')['relation'],
        'same',
      );
      equal(jsonList(block, 'sides').length, 2);

      // A revision without the small plates makes the recorded stack
      // unavailable; the frozen record itself stays valid.
      await EquipmentService(store).publishInstance(
        _instance(
          'garage-bar',
          'barbell',
          loading: {
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
              {
                'mass': {'value': '10', 'unit': 'kg'},
                'count': 2,
              },
            ],
          },
          convention: {'massBasis': 'assembly-total'},
          notes: 'Small plates moved.',
        ),
        1,
      );
      status = await EquipmentService(store).arrangeStatus('loaded');
      equal(status['changed'], true);
      block = jsonObject(jsonList(status, 'sets').single, 'block');
      equal(block['currentRevision'], 2);
      equal(block['feasibleUnderCurrent'], false);
      check(
        (block['feasibilityReason']! as String).contains(
          'outside the declared inventory: 2.5 kg.',
        ),
        'the reason names the missing stock, ${block['feasibilityReason']}',
      );
      equal(block['freshPlan'], null);
      final frozen = await service.session('loaded');
      check(
        frozen.set(setId).loadArrangement != null,
        'the recorded stack is never rewritten',
      );

      // Restoring the plates re-feasibilizes; a drifted instance default
      // convention is disclosed, not applied.
      await EquipmentService(store).publishInstance(
        _instance(
          'garage-bar',
          'barbell',
          loading: _barLoading,
          convention: {'massBasis': 'added-load'},
          notes: 'Entered plates only.',
        ),
        2,
      );
      status = await EquipmentService(store).arrangeStatus('loaded');
      block = jsonObject(jsonList(status, 'sets').single, 'block');
      equal(block['currentRevision'], 3);
      equal(block['feasibleUnderCurrent'], true);
      equal(block['freshPlan'], 'planned');
      equal(block['conventionChanged'], true);
      equal(status['changed'], true);

      // An entered mass that disagrees with the stack is disclosed only.
      final drifted = await service.start(
        'drifted',
        'bench-practice',
        1,
        instant(11),
        loadBindings: {'bench': 'garage-bar'},
        loadConventions: {
          'bench': LoadConvention.fromJson({'massBasis': 'added-load'}),
        },
      );
      await service.edit(
        'drifted',
        drifted.contentVersion,
        (s) => const TrainingService().complete(s, s.sets.first.id, {
          'mass': Quantity('60', 'kg'),
          'reps': Quantity('5', 'rep'),
        }),
      );
      await service.edit(
        'drifted',
        (await service.session('drifted')).contentVersion,
        (s) => const TrainingService().arrange(
          s,
          s.sets.first.id,
          _arrangement([
            {
              'mass': {'value': '20', 'unit': 'kg'},
              'count': 2,
            },
          ]),
        ),
      );
      status = await EquipmentService(store).arrangeStatus('drifted');
      block = jsonObject(jsonList(status, 'sets').single, 'block');
      equal(block['freshPlan'], 'planned');
      equal(
        jsonObject(block['massRelation'], 'massRelation')['relation'],
        'differs',
      );
      equal(
        jsonObject(
          jsonObject(
            block['massRelation'],
            'massRelation',
          )['interpretedAssemblyMass'],
          'interpreted',
        )['value'],
        '80',
      );
      equal(
        jsonObject(
          jsonObject(
            block['massRelation'],
            'massRelation',
          )['arrangementTotalMass'],
          'arrangement total',
        )['value'],
        '60',
      );

      // A stack the fresh helper would not pick stays feasible but is
      // labeled honestly: this instance's plan would reach 40 kg with the
      // two 10 kg plates, not the four recorded 5 kg plates.
      await EquipmentService(store).publishInstance(
        _instance(
          'garage-bar-b',
          'barbell',
          loading: {
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
                'mass': {'value': '10', 'unit': 'kg'},
                'count': 2,
              },
              {
                'mass': {'value': '5', 'unit': 'kg'},
                'count': 4,
              },
            ],
          },
          convention: {'massBasis': 'assembly-total'},
        ),
        0,
      );
      final alternate = await service.start(
        'alternate',
        'bench-practice',
        1,
        instant(12),
        loadBindings: {'bench': 'garage-bar-b'},
      );
      await service.edit(
        'alternate',
        alternate.contentVersion,
        (s) => const TrainingService().complete(s, s.sets.first.id, {
          'mass': Quantity('40', 'kg'),
          'reps': Quantity('5', 'rep'),
        }),
      );
      await service.edit(
        'alternate',
        (await service.session('alternate')).contentVersion,
        (s) => const TrainingService().arrange(
          s,
          s.sets.first.id,
          _arrangement([
            {
              'mass': {'value': '5', 'unit': 'kg'},
              'count': 4,
            },
          ], instanceId: 'garage-bar-b'),
        ),
      );
      status = await EquipmentService(store).arrangeStatus('alternate');
      block = jsonObject(jsonList(status, 'sets').single, 'block');
      equal(block['feasibleUnderCurrent'], true);
      equal(block['freshPlan'], 'feasible-not-planned');
      equal(
        jsonObject(block['massRelation'], 'massRelation')['relation'],
        'same',
      );
      equal(status['changed'], true);
    }),
  );

  test(
    'arrangements are portable only under v63 formats',
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
      final setId = session.sets.first.id;
      var current = await service.edit(
        'loaded',
        session.contentVersion,
        (s) => const TrainingService().complete(s, setId, {
          'mass': Quantity('85', 'kg'),
          'reps': Quantity('5', 'rep'),
        }),
      );
      current = await service.edit(
        'loaded',
        current.contentVersion,
        (s) => const TrainingService().arrange(
          s,
          setId,
          _arrangement([
            {
              'mass': {'value': '20', 'unit': 'kg'},
              'count': 2,
            },
          ]),
        ),
      );
      final original = canonicalJson((await store.archive()).toJson());
      await store.backup('$dir/native');
      final exported = await LogicalArchiveFiles.export(
        await store.archive(),
        '$dir/logical.json',
      );
      equal(exported['format'], 'bodytmi-logical-export/63');
      var logical = await LogicalArchiveFiles.prepare('$dir/logical.json');
      try {
        check(
          logical.archive.sessions.single.sets.any(
            (s) => s.loadArrangement != null,
          ),
          'the logical export retains the recorded stack',
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
        check(
          (await active.archive()).sessions.single.sets.any(
            (s) => s.loadArrangement!.channel == 'barbell',
          ),
          'restored profiles keep the recorded stack',
        );
      } finally {
        await active.close();
      }

      // The recorded stack cannot claim the previous label.
      final relabeled = jsonObject(
        jsonDecode(await File('$dir/logical.json').readAsString()),
        'logical',
      );
      relabeled['format'] = 'bodytmi-logical-export/62';
      await File('$dir/old-label.json')
        ..createSync()
        ..writeAsStringSync(jsonEncode(await _resign(relabeled)));
      final logicalError = await failure(
        () => LogicalArchiveFiles.prepare('$dir/old-label.json'),
      );
      check(
        logicalError.message.contains('plate arrangements require logical v63'),
        'older logical labels reject recorded stacks',
      );

      // The same profile without any stack is genuinely older shaped.
      final plain = copyJson(relabeled);
      for (final item
          in jsonObject(plain['data'], 'data')['sessions'] as List) {
        for (final set in jsonObject(item, 'session')['sets'] as List)
          jsonObject(set, 'set').remove('loadArrangement');
      }
      plain['format'] = 'bodytmi-logical-export/62';
      await File('$dir/plain-label.json')
        ..createSync()
        ..writeAsStringSync(jsonEncode(await _resign(plain)));
      final stripped = await LogicalArchiveFiles.prepare(
        '$dir/plain-label.json',
      );
      try {
        check(
          stripped.archive.sessions.single.sets.every(
            (s) => s.loadArrangement == null,
          ),
          'a stack-free session is genuinely older shaped',
        );
      } finally {
        await stripped.close();
      }

      final db = sqlite3.open('$dir/native/database.sqlite');
      db.userVersion = 62;
      db.close();
      final nativeError = await failure(
        () => NativeBackup.validateDatabase('$dir/native/database.sqlite'),
      );
      check(
        nativeError.message.contains('plate arrangements require schema v63'),
        'an older schema label cannot carry a recorded stack',
      );
    }),
  );

  test(
    'arrangement CLI commands record, report and reject bad input',
    () => _withStore((store, dir) async {
      final equipment = EquipmentService(store);
      await equipment.publishEquipment(_equipment('gym-bar-1'), 0);
      await equipment.publishGym(_gym('garage'), 0);
      await equipment.publishInstance(
        EquipmentInstance.fromJson(
          jsonObject(example('arrange-instance')['instance'], 'instance'),
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
        ...example('arrange-session'),
        'database': '$dir/db.sqlite',
      });
      equal(started.code, 0);
      check(
        started.output.contains('"source":"instance"'),
        'the public example freezes the instance default',
      );
      final completed = await cmd('store complete', {
        'id': 'arranged-bench-session',
        'expectedVersion': 1,
        'setId': 'workout/heavy[0]/heavy-set',
        'actuals': {
          'mass': {'value': '90', 'unit': 'kg'},
          'reps': {'value': '5', 'unit': 'rep'},
        },
      });
      equal(completed.code, 0);

      final arranged = await cmd('store arrange', {
        ...example('arrange-set'),
        'database': '$dir/db.sqlite',
      });
      equal(arranged.code, 0);
      check(
        arranged.output.contains('"loadArrangement"'),
        'the stored session returns the recorded stack',
      );

      final status = await cmd('store arrange-status', {
        'id': 'arranged-bench-session',
      });
      equal(status.code, 0);
      check(
        status.output.contains(
              '"policy":"bodytmi-load-arrangement-status/1"',
            ) &&
            status.output.contains('"changed":false') &&
            status.output.contains('"freshPlan":"planned"'),
        'the current plan agrees with the recorded stack',
      );

      // The pure status sees the same frozen stack.
      final sessionJson = jsonObject(
        jsonDecode(arranged.output)['data'],
        'data',
      );
      final pureStatus = await invoke(
        ['session', 'arrange-status'],
        jsonEncode({
          'schemaVersion': 1,
          'session': sessionJson,
          'instances': {
            'bench-heavy': {
              'instanceId': 'garage-rack-bar-olympic',
              'revision': 1,
              'snapshot': jsonObject(
                example('arrange-instance')['instance'],
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

      // The pure edit path records too.
      final pureArrange = await invoke(
        ['session', 'arrange'],
        jsonEncode({
          'schemaVersion': 1,
          'session': sessionJson,
          'setId': 'workout/heavy[0]/heavy-set',
          'arrangement': {
            'instanceId': 'garage-rack-bar-olympic',
            'channel': 'barbell',
            'plates': [
              {
                'mass': {'value': '20', 'unit': 'kg'},
                'count': 2,
              },
            ],
          },
        }),
      );
      equal(pureArrange.code, 0);
      check(
        pureArrange.output.contains('"loadArrangement"'),
        'the pure session edit records the smaller stack',
      );

      final noConfirm = await cmd('store arrange', {
        'id': 'arranged-bench-session',
        'expectedVersion': 3,
        'setId': 'workout/heavy[0]/heavy-set',
        'arrangement': null,
      });
      equal(noConfirm.code, 2);
      check(
        noConfirm.error.contains('Confirm before clearing'),
        'clearing needs explicit confirmation',
      );
      final stale = await cmd('store arrange', {
        'id': 'arranged-bench-session',
        'expectedVersion': 1,
        'setId': 'workout/heavy[0]/heavy-set',
        'arrangement': null,
        'confirm': true,
      });
      equal(stale.code, 5);
      final ghost = await cmd('store arrange-status', {'id': 'ghost'});
      equal(ghost.code, 3);
      final badPlate = await cmd('store arrange', {
        'id': 'arranged-bench-session',
        'expectedVersion': 3,
        'setId': 'workout/heavy[0]/heavy-set',
        'arrangement': {
          'instanceId': 'garage-rack-bar-olympic',
          'channel': 'barbell',
          'plates': [
            {
              'mass': {'value': '20', 'unit': 'kg'},
              'count': -1,
            },
          ],
        },
      });
      equal(badPlate.code, 2);
      final notCompleted = await cmd('store arrange', {
        'id': 'arranged-bench-session',
        'expectedVersion': 3,
        'setId': 'workout/heavy[1]/heavy-set',
        'arrangement': {
          'instanceId': 'garage-rack-bar-olympic',
          'channel': 'barbell',
          'plates': [
            {
              'mass': {'value': '20', 'unit': 'kg'},
              'count': 2,
            },
          ],
        },
      });
      equal(notCompleted.code, 2);
      check(
        notCompleted.error.contains('only for completed sets'),
        'planned sets cannot carry a stack',
      );
    }),
  );
}
