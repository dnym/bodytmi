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
      'include': true,
    },
    {
      'id': 'collars',
      'kind': 'collar',
      'mass': {'value': '1', 'unit': 'kg'},
      'include': false,
    },
  ],
  'channel': {'id': 'barbell', 'sides': 2, 'symmetry': 'required'},
  'plates': [
    {
      'mass': {'value': '25', 'unit': 'kg'},
      'count': 4,
    },
    {
      'mass': {'value': '10', 'unit': 'kg'},
      'count': 4,
    },
    {
      'mass': {'value': '5', 'unit': 'kg'},
      'count': 2,
    },
    {
      'mass': {'value': '2.5', 'unit': 'kg'},
      'count': 2,
    },
    {
      'mass': {'value': '1.25', 'unit': 'kg'},
      'count': 2,
    },
  ],
};

final Map<String, Object?> _hornsLoading = {
  'components': [
    {
      'id': 'horns',
      'kind': 'tare',
      'mass': {'value': '5', 'unit': 'kg'},
    },
  ],
  'channel': {'id': 'horns', 'sides': 2, 'symmetry': 'independent'},
  'plates': [
    {
      'mass': {'value': '5', 'unit': 'kg'},
      'count': 2,
    },
    {
      'mass': {'value': '2.5', 'unit': 'kg'},
      'count': 1,
    },
  ],
};

EquipmentDefinition _equipment(String id) =>
    EquipmentDefinition.fromJson({'id': id});
GymDefinition _gym(String id) => GymDefinition.fromJson({'id': id});
EquipmentInstance _instance(String id, String equipmentId, {Object? loading}) =>
    EquipmentInstance.fromJson({
      'id': id,
      'equipmentId': equipmentId,
      'gym': 'garage',
      if (loading != null) 'loading': loading,
    });

Future<void> _withStore(
  Future<void> Function(TrainingStore, String) action,
) async {
  final dir = await Directory.systemTemp.createTemp('bodytmi-plate-');
  final store = await TrainingStore.open('${dir.path}/db.sqlite');
  try {
    final training = StoredTrainingService(store);
    await training.publish(definition(), 0);
    await action(store, dir.path);
  } finally {
    await store.close();
    await dir.delete(recursive: true);
  }
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

List<Map<String, Object?>> _arrangements(Map<String, Object?> plan) => [
  for (final item in plan['arrangements'] as List)
    jsonObject(item, 'arrangement'),
];

Map<String, Object?> _mass(Object? arrangement, String key) =>
    jsonObject(jsonObject(arrangement, 'arrangement')[key], key);

List<List<Object?>> _side(Map<String, Object?> arrangement, int which) {
  final sides = arrangement['sides'] as List;
  final side = jsonObject(sides[which - 1], 'side');
  equal(side['side'], which);
  return [
    for (final plate in side['plates'] as List)
      [
        jsonObject(
          jsonObject(jsonObject(plate, 'plate')['mass'], 'mass')['entered'],
          'entered',
        )['value'],
        plate['count'],
      ],
  ];
}

void plateMathTests() {
  test(
    'declared loading configurations validate exactly and never assume a bar',
    () {
      final bar = LoadingSpec.fromJson(_barLoading);
      equal(bar.channel.sides, 2);
      check(bar.channel.symmetric, 'the barbell channel requires symmetry');
      // Excluded components stay declared but contribute no mass.
      equal(bar.tareMass.toString(), '20');
      final roundTrip = LoadingSpec.fromJson(bar.toJson());
      jsonEqual(roundTrip.toJson(), bar.toJson());

      rejects(
        () => LoadingSpec.fromJson({
          ..._barLoading,
          'components': [
            {
              'id': 'bar',
              'kind': 'plate',
              'mass': {'value': '20', 'unit': 'kg'},
            },
          ],
        }),
      );
      rejects(
        () => LoadingSpec.fromJson({
          ..._barLoading,
          'components': [
            {
              'id': 'bar',
              'kind': 'bar',
              'mass': {'value': '20', 'unit': 'rep'},
            },
          ],
        }),
      );
      rejects(
        () => LoadingSpec.fromJson({
          ..._barLoading,
          'components': [
            {
              'id': 'bar',
              'kind': 'bar',
              'mass': {'value': '20', 'unit': 'kg'},
              'include': 'yes',
            },
          ],
        }),
      );
      rejects(
        () => LoadingSpec.fromJson({
          ..._barLoading,
          'channel': {'id': 'one', 'sides': 1, 'symmetry': 'independent'},
        }),
      );
      rejects(
        () => LoadingSpec.fromJson({
          ..._barLoading,
          'channel': {'id': 'many', 'sides': 3, 'symmetry': 'required'},
        }),
      );
      rejects(
        () => LoadingSpec.fromJson({
          ..._barLoading,
          'plates': [
            {
              'mass': {'value': '25', 'unit': 'kg'},
              'count': 0,
            },
          ],
        }),
      );
      rejects(
        () => LoadingSpec.fromJson({
          ..._barLoading,
          'plates': [
            {
              'mass': {'value': '-2.5', 'unit': 'kg'},
              'count': 2,
            },
          ],
        }),
      );
      rejects(
        () => LoadingSpec.fromJson({
          ..._barLoading,
          'plates': [
            {
              'mass': {'value': '25', 'unit': 'kg'},
              'count': 2,
            },
            {
              'mass': {'value': '25.00', 'unit': 'kg'},
              'count': 1,
            },
          ],
        }),
      );
      rejects(
        () => LoadingSpec.fromJson({..._barLoading, 'plates': <Object?>[]}),
      );
      // An instance without a declared configuration carries no loading model.
      equal(_instance('plain-bar', 'barbell').loading, null);
      equal(
        _instance('loaded', 'barbell', loading: _barLoading).loading != null,
        true,
      );
      rejects(
        () => EquipmentInstance.fromJson({
          'id': 'bad',
          'equipmentId': 'barbell',
          'loading': {'components': _barLoading['components']},
        }),
      );
    },
  );
  test(
    'the plate helper returns only feasible arrangements and labels approximations',
    () {
      final bar = LoadingSpec.fromJson(_barLoading);
      final exact = PlatePlan.evaluate(bar, Quantity('102.5', 'kg'));
      equal(exact['policy'], 'bodytmi-plate-plan/1');
      equal(exact['status'], 'exact');
      equal(_mass(exact, 'tareMass')['value'], '20');
      var arrangements = _arrangements(exact);
      equal(arrangements.length, 1);
      equal(arrangements[0]['relation'], 'exact');
      equal(_mass(arrangements[0], 'channelMass')['value'], '82.5');
      equal(_mass(arrangements[0], 'totalMass')['value'], '102.5');
      jsonEqual(_side(arrangements[0], 1), [
        ['25', 1],
        ['10', 1],
        ['5', 1],
        ['1.25', 1],
      ]);
      jsonEqual(_side(arrangements[0], 2), _side(arrangements[0], 1));
      // Unused denominations stay visible.
      equal((arrangements[0]['remaining'] as List).length, 3);

      // Unreachable targets yield both labeled neighbors, never a silent fix.
      final near = PlatePlan.evaluate(bar, Quantity('103', 'kg'));
      equal(near['status'], 'nearest');
      arrangements = _arrangements(near);
      equal(arrangements.length, 2);
      equal(arrangements[0]['relation'], 'nearest-lower');
      equal(_mass(arrangements[0], 'totalMass')['value'], '102.5');
      equal(arrangements[1]['relation'], 'nearest-higher');
      equal(_mass(arrangements[1], 'totalMass')['value'], '105');

      // Exhausted inventory offers only the reachable lower choice.
      final short = PlatePlan.evaluate(bar, Quantity('200', 'kg'));
      equal(short['status'], 'missing-inventory');
      arrangements = _arrangements(short);
      equal(arrangements.length, 1);
      equal(arrangements[0]['relation'], 'nearest-lower');
      equal(_mass(arrangements[0], 'totalMass')['value'], '177.5');
      check(
        (arrangements[0]['remaining'] as List).isEmpty,
        'the whole declared inventory is consumed',
      );

      // Components alone above the target is not a plate problem.
      final below = PlatePlan.evaluate(bar, Quantity('15', 'kg'));
      equal(below['status'], 'below-components');
      arrangements = _arrangements(below);
      equal(arrangements.length, 1);
      equal(arrangements[0]['relation'], 'nearest-higher');
      equal(_mass(arrangements[0], 'channelMass')['value'], '0');
      equal(_mass(arrangements[0], 'totalMass')['value'], '20');

      // A one-sided channel carries the tare and every plate once.
      final handle = LoadingSpec.fromJson({
        'components': [
          {
            'id': 'handle',
            'kind': 'handle',
            'mass': {'value': '4', 'unit': 'kg'},
          },
        ],
        'channel': {'id': 'handle', 'sides': 1, 'symmetry': 'required'},
        'plates': [
          {
            'mass': {'value': '2.5', 'unit': 'kg'},
            'count': 2,
          },
        ],
      });
      final one = PlatePlan.evaluate(handle, Quantity('9', 'kg'));
      equal(one['status'], 'exact');
      arrangements = _arrangements(one);
      equal(_mass(arrangements[0], 'totalMass')['value'], '9');
      jsonEqual(_side(arrangements[0], 1), [
        ['2.5', 2],
      ]);
      equal((arrangements[0]['sides'] as List).length, 1);
      equal((arrangements[0]['sides'] as List).single == null, false);

      // An independent channel may differ per side; the split is display only.
      final horns = LoadingSpec.fromJson(_hornsLoading);
      final odd = PlatePlan.evaluate(horns, Quantity('12.5', 'kg'));
      equal(odd['sideAllocation'], 'display-only');
      arrangements = _arrangements(odd);
      equal(odd['status'], 'exact');
      equal(_mass(arrangements[0], 'totalMass')['value'], '12.5');
      jsonEqual(_side(arrangements[0], 1), [
        ['5', 1],
      ]);
      jsonEqual(_side(arrangements[0], 2), [
        ['2.5', 1],
      ]);
      // The odd total between reachable sums shows both labeled neighbors.
      final tight = PlatePlan.evaluate(horns, Quantity('16.25', 'kg'));
      equal(tight['status'], 'nearest');
      arrangements = _arrangements(tight);
      equal(_mass(arrangements[0], 'totalMass')['value'], '15');
      equal(_mass(arrangements[1], 'totalMass')['value'], '17.5');

      // Mixed units are converted exactly; no plate is replaced by a guess.
      final lb = LoadingSpec.fromJson({
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
            'mass': {'value': '45', 'unit': 'lb'},
            'count': 4,
          },
        ],
      });
      final dual = PlatePlan.evaluate(lb, Quantity('100', 'kg'));
      equal(dual['status'], 'nearest');
      arrangements = _arrangements(dual);
      equal(_mass(arrangements[0], 'totalMass')['value'], '60.8233133');
      equal(_mass(arrangements[1], 'totalMass')['value'], '101.6466266');
      jsonEqual(_side(arrangements[1], 1), [
        ['45', 2],
      ]);
      // The same stack reaches an exact pound target exactly.
      final exactLb = PlatePlan.evaluate(lb, Quantity('101.6466266', 'kg'));
      equal(exactLb['status'], 'exact');

      rejects(() => PlatePlan.evaluate(bar, Quantity('102.5', 'rep')));
      rejects(
        () => PlatePlan.evaluate(bar, Quantity('100000000', 'kg')),
        'validation',
      );
    },
  );
  test(
    'stored plate plans pin the instance revision and keep the store unchanged',
    () => _withStore((store, dir) async {
      final service = EquipmentService(store);
      await service.publishEquipment(_equipment('barbell'), 0);
      await service.publishGym(_gym('garage'), 0);
      await service.publishInstance(_instance('plain-bar', 'barbell'), 0);
      await service.publishInstance(
        _instance('loaded-bar', 'barbell', loading: _barLoading),
        0,
      );

      final plan = await service.platePlan(
        'loaded-bar',
        Quantity('102.5', 'kg'),
      );
      equal(plan['instanceId'], 'loaded-bar');
      equal(plan['instanceRevision'], 1);
      equal(jsonObject(plan['plan'], 'plan')['status'], 'exact');
      // A pinned older revision never borrows a newer configuration.
      final loading2 = LoadingSpec.fromJson(_barLoading);
      final evolved = await service.publishInstance(
        EquipmentInstance.fromJson({
          'id': 'loaded-bar',
          'equipmentId': 'barbell',
          'gym': 'garage',
          'loading': {
            ..._barLoading,
            'plates': [
              ..._barLoading['plates'] as List,
              {
                'mass': {'value': '0.25', 'unit': 'kg'},
                'count': 2,
              },
            ],
          },
        }),
        1,
      );
      equal(evolved.number, 2);
      final pinned = await service.platePlan(
        'loaded-bar',
        Quantity('103', 'kg'),
        1,
      );
      equal(pinned['instanceRevision'], 1);
      equal(jsonObject(pinned['plan'], 'plan')['status'], 'nearest');
      final latest = await service.platePlan(
        'loaded-bar',
        Quantity('103', 'kg'),
      );
      equal(latest['instanceRevision'], 2);
      // The micro plates reach the exact target on the newer configuration.
      equal(jsonObject(latest['plan'], 'plan')['status'], 'exact');
      equal(evolved.instance.loading!.plates.length, 6);
      equal(
        evolved.instance.loading!.channel.symmetric,
        loading2.channel.symmetric,
      );
      final before = canonicalJson((await store.archive()).toJson());

      // Undeclared equipment has no plate arithmetic at all.
      final missing = await failure(
        () => service.platePlan('plain-bar', Quantity('60', 'kg')),
      );
      equal(missing.code, 'not_found');
      check(
        missing.message.contains('no loading configuration'),
        'the rejection names the missing declaration',
      );
      final unknown = await failure(
        () => service.platePlan('ghost', Quantity('60', 'kg')),
      );
      equal(unknown.code, 'not_found');
      // Reading a plan never writes: no session, target or record changes.
      equal(canonicalJson((await store.archive()).toJson()), before);
    }),
  );
  test(
    'loading declarations are portable only under v60 formats',
    () => _withStore((store, dir) async {
      final service = EquipmentService(store);
      await service.publishEquipment(_equipment('barbell'), 0);
      await service.publishGym(_gym('garage'), 0);
      await service.publishInstance(
        _instance('loaded-bar', 'barbell', loading: _barLoading),
        0,
      );
      final original = canonicalJson((await store.archive()).toJson());
      await store.backup('$dir/native');
      final exported = await LogicalArchiveFiles.export(
        await store.archive(),
        '$dir/logical.json',
      );
      equal(exported['format'], 'bodytmi-logical-export/66');
      final logical = await LogicalArchiveFiles.prepare('$dir/logical.json');
      try {
        check(
          logical.archive.instances.single.instance.loading != null,
          'the logical export retains the configuration',
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
        final restored = canonicalJson((await active.archive()).toJson());
        equal(restored, original);
        check(
          restored.contains('"symmetry":"required"'),
          'the restored profile keeps the declared channel',
        );
        final plan = await EquipmentService(
          active,
        ).platePlan('loaded-bar', Quantity('102.5', 'kg'));
        equal(jsonObject(plan['plan'], 'plan')['status'], 'exact');
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
      } finally {
        await active.close();
      }

      // Honest current content cannot claim the older labels.
      final relabeled = jsonObject(
        jsonDecode(await File('$dir/logical.json').readAsString()),
        'logical',
      );
      relabeled['format'] = 'bodytmi-logical-export/59';
      await File('$dir/old-label.json')
        ..createSync()
        ..writeAsStringSync(jsonEncode(await _resign(relabeled)));
      final logicalError = await failure(
        () => LogicalArchiveFiles.prepare('$dir/old-label.json'),
      );
      check(
        logicalError.message.contains(
          'loading declarations require logical v60',
        ),
        'older logical labels reject declared loading',
      );
      // The same payload without loading stays honest at the older label.
      final plain = jsonObject(
        jsonDecode(await File('$dir/logical.json').readAsString()),
        'logical',
      );
      for (final item in jsonObject(plain['data'], 'data')['instances'] as List)
        jsonObject(
          jsonObject(item, 'instance revision')['instance'],
          'instance',
        ).remove('loading');
      plain['format'] = 'bodytmi-logical-export/59';
      await File('$dir/plain-label.json')
        ..createSync()
        ..writeAsStringSync(jsonEncode(await _resign(plain)));
      final stripped = await LogicalArchiveFiles.prepare(
        '$dir/plain-label.json',
      );
      try {
        check(
          stripped.archive.instances.single.instance.loading == null,
          'a configuration-free profile is genuinely older shaped',
        );
      } finally {
        await stripped.close();
      }

      final db = sqlite3.open('$dir/native/database.sqlite');
      db.execute('DROP TABLE IF EXISTS imported_sessions');
      db.execute('DROP TABLE IF EXISTS block_progressions');
      db.userVersion = 59;
      db.close();
      final nativeError = await failure(
        () => NativeBackup.validateDatabase('$dir/native/database.sqlite'),
      );
      check(
        nativeError.message.contains('loading declarations require schema v60'),
        'an older schema label cannot carry a loading declaration',
      );
    }),
  );
  test(
    'plate plan CLI commands report arrangements and reject bad input',
    () => _withStore((store, dir) async {
      final service = EquipmentService(store);
      await service.publishEquipment(_equipment('barbell'), 0);
      await service.publishGym(_gym('garage'), 0);
      await service.publishInstance(_instance('plain-bar', 'barbell'), 0);
      await service.publishInstance(
        _instance('loaded-bar', 'barbell', loading: _barLoading),
        0,
      );
      await store.close();
      Future<({int code, String output, String error})> cmd(
        String action,
        Map<String, Object?> input,
      ) => invoke(
        action.split(' '),
        jsonEncode({
          'schemaVersion': 1,
          if (action.startsWith('store')) 'database': '$dir/db.sqlite',
          ...input,
        }),
      );
      final pure = await cmd('plate plan', {
        'loading': _barLoading,
        'target': {'value': '102.5', 'unit': 'kg'},
      });
      equal(pure.code, 0);
      check(
        pure.output.contains('"status":"exact"') &&
            pure.output.contains('"totalMass"'),
        'the pure command returns the arrangement',
      );
      final public = await invoke([
        'plate',
        'plan',
      ], jsonEncode(example('plate-plan')));
      equal(public.code, 0);
      check(
        jsonDecode(public.output)['data']['status'] == 'exact',
        'the public example plans exactly',
      );
      final stored = await cmd('store plate-plan', {
        'instanceId': 'loaded-bar',
        'target': {'value': '103', 'unit': 'kg'},
      });
      equal(stored.code, 0);
      check(
        stored.output.contains('"status":"nearest"') &&
            stored.output.contains('nearest-higher'),
        'the stored command labels both neighbors',
      );
      final pinned = await cmd('store plate-plan', {
        'instanceId': 'loaded-bar',
        'revision': 1,
        'target': {'value': '200', 'unit': 'kg'},
      });
      equal(pinned.code, 0);
      check(
        pinned.output.contains('"status":"missing-inventory"'),
        'a pinned revision evaluates its own inventory',
      );
      final undeclared = await cmd('store plate-plan', {
        'instanceId': 'plain-bar',
        'target': {'value': '60', 'unit': 'kg'},
      });
      equal(undeclared.code, 3);
      check(
        undeclared.error.contains('no loading configuration'),
        'the missing declaration is reported, not guessed',
      );
      final missing = await cmd('store plate-plan', {
        'instanceId': 'ghost',
        'target': {'value': '60', 'unit': 'kg'},
      });
      equal(missing.code, 3);
      final badTarget = await cmd('store plate-plan', {
        'instanceId': 'loaded-bar',
        'target': {'value': '10', 'unit': 'rep'},
      });
      equal(badTarget.code, 2);
      final badLoading = await cmd('plate plan', {
        'loading': {..._barLoading, 'plates': <Object?>[]},
        'target': {'value': '60', 'unit': 'kg'},
      });
      equal(badLoading.code, 2);
    }),
  );
}
