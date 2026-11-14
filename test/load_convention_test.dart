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
  ],
};

Map<String, Object?> _slot(
  String id, {
  Object? convention,
  String implementation = 'barbell',
}) => {
  'id': id,
  'exercise': 'row',
  'implementation': implementation,
  'targets': {
    'mass': {'value': '20', 'unit': 'kg'},
    'reps': {'value': '8', 'unit': 'rep'},
  },
  'prefill': <String>[],
  if (convention != null) 'convention': convention,
};

Map<String, Object?> _workout(String id, List<Map<String, Object?>> slots) => {
  'id': id,
  'name': 'Convention practice',
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
}) => EquipmentInstance.fromJson({
  'id': id,
  'equipmentId': equipmentId,
  'gym': 'garage',
  if (loading != null) 'loading': loading,
  if (convention != null) 'convention': convention,
});

Future<void> _withStore(
  Future<void> Function(TrainingStore, String) action,
) async {
  final dir = await Directory.systemTemp.createTemp('bodytmi-convention-');
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

Map<String, Object?> _out(Map<String, Object?> interpretation, String key) =>
    jsonObject(
      jsonObject(interpretation['interpretation'], 'interpretation')[key],
      key,
    );

Map<String, Object?> _unwrap(Map<String, Object?> view) =>
    jsonObject(jsonObject(view['interpretation'], 'interpretation'), 'result');

Object? _quantityValue(Map<String, Object?> entry) {
  equal(entry['status'], 'known');
  final quantity = entry['mass'] ?? entry['repetitions'];
  return jsonObject(quantity, 'quantity')['value'];
}

void loadConventionTests() {
  test('load conventions declare exact structure and capability rules', () {
    final dumbbell = LoadConvention.fromJson({
      'massBasis': 'per-implement',
      'implements': 2,
    });
    equal(dumbbell.implements, 2);
    equal(dumbbell.sides, 'both');
    equal(dumbbell.repCounting, 'per-side');
    jsonEqual(
      LoadConvention.fromJson(dumbbell.toJson()).toJson(),
      dumbbell.toJson(),
    );

    // Defaults serialize compactly.
    jsonEqual(
      LoadConvention.fromJson({'massBasis': 'assembly-total'}).toJson(),
      {'massBasis': 'assembly-total'},
    );

    // A nominal setting cannot declare implements it cannot share.
    rejects(
      () => LoadConvention.fromJson({
        'massBasis': 'nominal-setting',
        'implements': 2,
      }),
    );
    rejects(
      () => LoadConvention.fromJson({
        'massBasis': 'per-implement',
        'implements': 0,
      }),
    );
    rejects(
      () => LoadConvention.fromJson({
        'massBasis': 'per-implement',
        'implements': 65,
      }),
    );
    rejects(() => LoadConvention.fromJson({'massBasis': 'machine'}));
    // Combined counting needs both sides.
    rejects(
      () => LoadConvention.fromJson({
        'massBasis': 'per-implement',
        'sides': 'left',
        'repCounting': 'combined',
      }),
    );

    // Capability: no imaginary bar and no imaginary symmetric sides.
    equal(
      loadConventionBlock(
        LoadConvention.fromJson({'massBasis': 'per-side'}),
        null,
      ),
      'A per-side load basis requires a declared loading configuration.',
    );
    final perSide = LoadConvention.fromJson({'massBasis': 'per-side'});
    final added = LoadConvention.fromJson({'massBasis': 'added-load'});
    final independent = LoadingSpec.fromJson(_hornsLoading);
    equal(
      loadConventionBlock(added, null),
      'An added-load basis requires a declared loading configuration.',
    );
    check(
      loadConventionBlock(perSide, LoadingSpec.fromJson(_barLoading)) == null,
      'a symmetric two-sided channel supports per-side entry',
    );
    equal(
      loadConventionBlock(perSide, independent),
      'A per-side load basis requires a symmetric two-sided loading channel.',
    );
    check(
      loadConventionBlock(added, independent) == null,
      'independent channels still have declared component mass',
    );
    for (final basis in [
      'per-implement',
      'assembly-total',
      'nominal-setting',
    ]) {
      check(
        loadConventionBlock(
              LoadConvention.fromJson({'massBasis': basis}),
              null,
            ) ==
            null,
        '$basis needs no declared loading configuration',
      );
    }

    // Instances enforce capability at authoring time.
    rejects(
      () => _instance(
        'selectorized',
        'machine',
        convention: {'massBasis': 'added-load'},
      ),
    );
    rejects(
      () => _instance(
        'horns',
        'machine',
        loading: _hornsLoading,
        convention: {'massBasis': 'per-side'},
      ),
    );
    final declared = _instance(
      'bar',
      'barbell',
      loading: _barLoading,
      convention: {'massBasis': 'assembly-total'},
    );
    equal(declared.convention!.massBasis, 'assembly-total');
    jsonEqual(declared.toJson()['convention'], {'massBasis': 'assembly-total'});
  });

  test(
    'interpretation reports exact masses and side expansion with explicit unknowns',
    () {
      final bar = LoadingSpec.fromJson(_barLoading);
      Map<String, Object?> interpret(
        Object? convention,
        Quantity mass, {
        Quantity? repetitions,
        LoadingSpec? loading,
      }) => LoadInterpretation.interpret(
        LoadConvention.fromJson(convention),
        mass,
        repetitions: repetitions,
        loading: loading,
      );

      // Two dumbbells logged per implement, upper-body unilateral row.
      final twoDumbbells = interpret(
        {'massBasis': 'per-implement', 'implements': 2, 'sides': 'left'},
        Quantity('22.5', 'kg'),
        repetitions: Quantity('8', 'rep'),
      );
      equal(twoDumbbells['policy'], 'bodytmi-load-interpretation/1');
      equal(_out(twoDumbbells, 'perImplementMass')['status'], 'known');
      equal(
        jsonObject(
          _out(twoDumbbells, 'perImplementMass')['mass'],
          'mass',
        )['value'],
        '22.5',
      );
      equal(_quantityValue(_out(twoDumbbells, 'assemblyMass')), '45');
      equal(_out(twoDumbbells, 'addedMass')['status'], 'unknown');
      check(
        (_out(twoDumbbells, 'addedMass')['reason'] as String).contains(
          'component mass is unknown',
        ),
        'no bar mass is ever assumed',
      );
      final reps = jsonObject(twoDumbbells['repetitions'], 'repetitions');
      equal(reps['workingSides'], 1);
      equal(
        _quantityValue(
          jsonObject(reps['totalLimbRepetitions'], 'totalLimbRepetitions'),
        ),
        '8',
      );
      jsonEqual(jsonObject(twoDumbbells['seriesContext'], 'seriesContext'), {
        'massBasis': 'per-implement',
        'implements': 2,
        'sides': 'left',
        'repCounting': 'per-side',
      });

      // Entered mass including the bar, with declared components.
      final barTotal = interpret(
        {'massBasis': 'assembly-total'},
        Quantity('62.5', 'kg'),
        loading: bar,
      );
      equal(_quantityValue(_out(barTotal, 'addedMass')), '42.5');
      equal(_quantityValue(_out(barTotal, 'perImplementMass')), '62.5');

      // Per-side plate entry resolves exactly under the symmetric channel.
      final perSide = interpret(
        {'massBasis': 'per-side'},
        Quantity('21.25', 'kg'),
        loading: bar,
      );
      equal(_quantityValue(_out(perSide, 'addedMass')), '42.5');
      equal(_quantityValue(_out(perSide, 'assemblyMass')), '62.5');

      // Added load beyond declared components.
      final added = interpret(
        {'massBasis': 'added-load'},
        Quantity('42.5', 'kg'),
        loading: bar,
      );
      equal(_quantityValue(_out(added, 'assemblyMass')), '62.5');

      // A nominal setting has no physical mass.
      final machine = interpret({
        'massBasis': 'nominal-setting',
      }, Quantity('70', 'lb'));
      equal(_out(machine, 'nominalSetting')['status'], 'known');
      for (final key in ['perImplementMass', 'assemblyMass', 'addedMass'])
        equal(_out(machine, key)['status'], 'unknown');
      check(
        (_out(machine, 'perImplementMass')['reason'] as String).contains(
          'no physical mass interpretation',
        ),
        'the nominal basis stays explicitly nominal',
      );

      // An entered assembly below declared components is inconsistent, not negative.
      final under = interpret(
        {'massBasis': 'assembly-total'},
        Quantity('10', 'kg'),
        loading: bar,
      );
      equal(_out(under, 'addedMass')['status'], 'unknown');
      check(
        (_out(under, 'addedMass')['reason'] as String).contains(
          'below the declared component mass',
        ),
        'negative added mass is reported, never constructed',
      );

      // Non-exact implement division stays unknown.
      final uneven = interpret(
        {'massBasis': 'per-implement', 'implements': 3},
        Quantity('20', 'kg'),
        loading: bar,
      );
      equal(_quantityValue(_out(uneven, 'perImplementMass')), '20');
      equal(_quantityValue(_out(uneven, 'assemblyMass')), '60');
      equal(_quantityValue(_out(uneven, 'addedMass')), '40');
      final shared = interpret(
        {'massBasis': 'assembly-total'},
        Quantity('20', 'kg'),
        loading: bar,
      );
      equal(_out(shared, 'perImplementMass')['status'], 'known');
      equal(_quantityValue(_out(shared, 'perImplementMass')), '20');
      final threeWay = interpret({
        'massBasis': 'assembly-total',
        'implements': 3,
      }, Quantity('60', 'kg'));
      equal(_quantityValue(_out(threeWay, 'perImplementMass')), '20');
      final unevenShare = interpret({
        'massBasis': 'assembly-total',
        'implements': 3,
      }, Quantity('61', 'kg'));
      equal(_out(unevenShare, 'perImplementMass')['status'], 'unknown');

      // Combined counting splits only exactly; unilateral per-side stays raw.
      final combined = interpret(
        {'massBasis': 'assembly-total', 'repCounting': 'combined'},
        Quantity('60', 'kg'),
        repetitions: Quantity('10', 'rep'),
      );
      equal(
        _quantityValue(
          jsonObject(
            jsonObject(
              combined['repetitions'],
              'repetitions',
            )['repetitionsPerSide'],
            'repetitionsPerSide',
          ),
        ),
        '5',
      );
      final oddCombined = interpret(
        {'massBasis': 'assembly-total', 'repCounting': 'combined'},
        Quantity('60', 'kg'),
        repetitions: Quantity('9', 'rep'),
      );
      equal(
        jsonObject(
          jsonObject(
            oddCombined['repetitions'],
            'repetitions',
          )['repetitionsPerSide'],
          'repetitionsPerSide',
        )['status'],
        'unknown',
      );

      // Capability applies to interpretation too.
      rejects(() => interpret({'massBasis': 'per-side'}, Quantity('20', 'kg')));
      // Dimensions are enforced.
      rejects(
        () => interpret({'massBasis': 'assembly-total'}, Quantity('20', 's')),
      );
      rejects(
        () => interpret(
          {'massBasis': 'assembly-total'},
          Quantity('20', 'kg'),
          repetitions: Quantity('20', 'kg'),
        ),
      );
    },
  );

  test(
    'stored resolution prefers explicit, then slot, then instance and stays read-only',
    () => _withStore((store, dir) async {
      final service = EquipmentService(store);
      await service.publishEquipment(_equipment('barbell'), 0);
      await service.publishEquipment(_equipment('machine'), 0);
      await service.publishEquipment(_equipment('dumbbell-pair'), 0);
      await service.publishGym(_gym('garage'), 0);
      await service.publishInstance(
        _instance(
          'garage-bar',
          'barbell',
          loading: _barLoading,
          convention: {'massBasis': 'assembly-total'},
        ),
        0,
      );
      await service.publishInstance(
        _instance('garage-dumbbell', 'dumbbell-pair'),
        0,
      );
      await service.publishInstance(
        _instance(
          'selectorized',
          'machine',
          convention: {'massBasis': 'nominal-setting'},
        ),
        0,
      );
      // Publication enforces capability: the horns instance below is rejected.
      final bad = await failure(
        () => service.publishInstance(
          _instance(
            'bad-horns',
            'machine',
            loading: _hornsLoading,
            convention: {'massBasis': 'per-side'},
          ),
          0,
        ),
      );
      equal(bad.code, 'validation');
      check(
        bad.message.contains('symmetric two-sided loading channel'),
        'the publication rejection names the capability rule',
      );

      // Instance default resolution with interpretation.
      final instanceView = await service.loadConvention(
        instanceId: 'garage-bar',
        mass: Quantity('62.5', 'kg'),
      );
      equal(
        jsonObject(instanceView['resolution'], 'resolution')['source'],
        'instance',
      );
      equal(
        jsonObject(instanceView['convention'], 'convention')['massBasis'],
        'assembly-total',
      );
      equal(
        jsonObject(
          jsonObject(instanceView['capability'], 'capability'),
          'capability',
        )['declaredLoading'],
        true,
      );
      final interpretation = _unwrap(instanceView);
      equal(_quantityValue(_out(interpretation, 'addedMass')), '42.5');

      // Slot composition override beats the instance default.
      final training = StoredTrainingService(store);
      await training.publish(
        WorkoutDefinition.fromJson(
          _workout('row-practice', [
            _slot(
              'row',
              convention: {
                'massBasis': 'per-implement',
                'implements': 2,
                'sides': 'left',
              },
            ),
          ]),
        ),
        0,
      );
      final slotView = await service.loadConvention(
        instanceId: 'garage-bar',
        templateId: 'row-practice',
        slotId: 'row',
      );
      equal(jsonObject(slotView['resolution'], 'resolution')['source'], 'slot');
      equal(
        jsonObject(slotView['convention'], 'convention')['massBasis'],
        'per-implement',
      );
      equal(slotView['interpretation'], null);

      // An explicit request convention beats both, and capability is checked
      // against the pinned instance revision.
      final explicitView = await service.loadConvention(
        instanceId: 'garage-bar',
        templateId: 'row-practice',
        slotId: 'row',
        explicit: LoadConvention.fromJson({'massBasis': 'added-load'}),
        mass: Quantity('42.5', 'kg'),
        repetitions: Quantity('8', 'rep'),
      );
      equal(
        jsonObject(explicitView['resolution'], 'resolution')['source'],
        'explicit',
      );
      equal(
        _quantityValue(_out(_unwrap(explicitView), 'assemblyMass')),
        '62.5',
      );
      final blocked = await failure(
        () => service.loadConvention(
          instanceId: 'garage-dumbbell',
          explicit: LoadConvention.fromJson({'massBasis': 'per-side'}),
        ),
      );
      equal(blocked.code, 'validation');
      check(
        blocked.message.contains('declared loading configuration'),
        'the resolution rejection names the missing declaration',
      );

      // Undeclared combinations report not_found. The upper-a slot has no
      // override, so resolution correctly falls back to the instance default.
      final missing = await failure(
        () => service.loadConvention(instanceId: 'garage-dumbbell'),
      );
      equal(missing.code, 'not_found');
      final unknownSlot = await failure(
        () => service.loadConvention(
          instanceId: 'garage-bar',
          templateId: 'row-practice',
          slotId: 'ghost-slot',
        ),
      );
      equal(unknownSlot.code, 'not_found');
      final fallback = await service.loadConvention(
        instanceId: 'garage-bar',
        templateId: 'upper-a',
        slotId: 'bench-heavy',
      );
      equal(
        jsonObject(fallback['resolution'], 'resolution')['source'],
        'instance',
      );
      equal(
        jsonObject(fallback['resolution'], 'resolution')['slotId'],
        'bench-heavy',
      );
      check(
        canonicalJson(
          (await store.archive()).toJson(),
        ).contains('"massBasis":"per-implement"'),
        'resolution read the published slot override',
      );
    }),
  );

  test(
    'conventions are portable only under v61 formats',
    () => _withStore((store, dir) async {
      final service = EquipmentService(store);
      await service.publishEquipment(_equipment('barbell'), 0);
      await service.publishGym(_gym('garage'), 0);
      await service.publishInstance(
        _instance(
          'garage-bar',
          'barbell',
          loading: _barLoading,
          convention: {'massBasis': 'assembly-total'},
        ),
        0,
      );
      final training = StoredTrainingService(store);
      await training.publish(
        WorkoutDefinition.fromJson(
          _workout('row-practice', [
            _slot('row', convention: {'massBasis': 'per-implement'}),
          ]),
        ),
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
          logical.archive.instances.single.instance.convention != null,
          'the logical export retains the instance convention',
        );
        check(
          logical.archive.revisions.any((r) => r.definition.hasLoadConventions),
          'the logical export retains the slot override',
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
        final view = await EquipmentService(
          active,
        ).loadConvention(instanceId: 'garage-bar');
        equal(
          jsonObject(view['convention'], 'convention')['massBasis'],
          'assembly-total',
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

      // Honest current content cannot claim the previous label.
      final relabeled = jsonObject(
        jsonDecode(await File('$dir/logical.json').readAsString()),
        'logical',
      );
      relabeled['format'] = 'bodytmi-logical-export/60';
      await File('$dir/old-label.json')
        ..createSync()
        ..writeAsStringSync(jsonEncode(await _resign(relabeled)));
      final logicalError = await failure(
        () => LogicalArchiveFiles.prepare('$dir/old-label.json'),
      );
      check(
        logicalError.message.contains('conventions require logical v61'),
        'older logical labels reject declared conventions',
      );

      // The same profile without any convention is genuinely older shaped.
      final plain = jsonObject(
        jsonDecode(await File('$dir/logical.json').readAsString()),
        'logical',
      );
      final data = jsonObject(plain['data'], 'data');
      for (final item in data['instances'] as List)
        jsonObject(
          jsonObject(item, 'instance revision')['instance'],
          'instance',
        ).remove('convention');
      for (final item in data['revisions'] as List)
        for (final slot
            in jsonObject(
                  jsonObject(item, 'workout revision')['definition'],
                  'definition',
                )['slots']
                as List)
          jsonObject(slot, 'slot').remove('convention');
      plain['format'] = 'bodytmi-logical-export/60';
      await File('$dir/plain-label.json')
        ..createSync()
        ..writeAsStringSync(jsonEncode(await _resign(plain)));
      final stripped = await LogicalArchiveFiles.prepare(
        '$dir/plain-label.json',
      );
      try {
        check(
          stripped.archive.instances.single.instance.convention == null,
          'a convention-free profile is genuinely older shaped',
        );
      } finally {
        await stripped.close();
      }

      final db = sqlite3.open('$dir/native/database.sqlite');
      db.execute('DROP TABLE IF EXISTS imported_sessions');
      db.execute('DROP TABLE IF EXISTS block_progressions');
      db.userVersion = 60;
      db.close();
      final nativeError = await failure(
        () => NativeBackup.validateDatabase('$dir/native/database.sqlite'),
      );
      check(
        nativeError.message.contains('conventions require schema v61'),
        'an older schema label cannot carry a declared convention',
      );
    }),
  );

  test(
    'load convention CLI commands report interpretations and reject bad input',
    () => _withStore((store, dir) async {
      final service = EquipmentService(store);
      await service.publishEquipment(_equipment('barbell'), 0);
      await service.publishGym(_gym('garage'), 0);
      await service.publishInstance(
        _instance(
          'garage-bar',
          'barbell',
          loading: _barLoading,
          convention: {'massBasis': 'assembly-total'},
        ),
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
      final validated = await cmd('convention validate', {
        'convention': {
          'massBasis': 'per-implement',
          'implements': 2,
          'sides': 'left',
        },
      });
      equal(validated.code, 0);
      check(
        validated.output.contains('"implements":2'),
        'the pure validation echoes the convention',
      );
      final interpreted = await cmd('convention interpret', {
        'convention': {'massBasis': 'per-side'},
        'mass': {'value': '21.25', 'unit': 'kg'},
        'loading': _barLoading,
      });
      equal(interpreted.code, 0);
      check(
        interpreted.output.contains('"assemblyMass"') &&
            interpreted.output.contains('"value":"62.5"'),
        'the pure interpretation resolves the assembly exactly',
      );
      final public = await invoke([
        'convention',
        'interpret',
      ], jsonEncode(example('load-convention')));
      equal(public.code, 0);
      check(
        jsonDecode(public.output)['data']['policy'] ==
            'bodytmi-load-interpretation/1',
        'the public example interprets',
      );
      final bad = await cmd('convention validate', {
        'convention': {'massBasis': 'machine'},
      });
      equal(bad.code, 2);
      final stored = await cmd('store load-convention', {
        'instanceId': 'garage-bar',
        'mass': {'value': '62.5', 'unit': 'kg'},
        'repetitions': {'value': '8', 'unit': 'rep'},
      });
      equal(stored.code, 0);
      check(
        stored.output.contains('"source":"instance"') &&
            stored.output.contains('"addedMass"'),
        'the stored command resolves the instance default',
      );
      final missing = await cmd('store load-convention', {
        'instanceId': 'ghost',
      });
      equal(missing.code, 3);
      final blocked = await cmd('store load-convention', {
        'instanceId': 'garage-bar',
        'convention': {'massBasis': 'per-implement', 'implements': 0},
      });
      equal(blocked.code, 2);
    }),
  );
}
