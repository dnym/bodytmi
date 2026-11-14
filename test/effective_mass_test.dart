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

Map<String, Object?> _model({
  String fraction = '0.65',
  String multiplier = '2',
  Object? assistance,
}) => {
  'id': 'declared-model',
  'version': 1,
  'bodyMassFraction': fraction,
  'addedMass': {'metric': 'mass', 'multiplier': multiplier},
  'assistance':
      assistance ??
      {
        'mass': {'value': '2.5', 'unit': 'kg'},
      },
};
WorkoutDefinition _definition({Map<String, Object?>? model}) {
  final j = definition().toJson();
  final slots = jsonList(j, 'slots');
  jsonObject(slots.first, 'slot')['bodyMass'] = {'context': 'clothed-training'};
  jsonObject(slots.first, 'slot')['effectiveMass'] = model ?? _model();
  return WorkoutDefinition.fromJson(j);
}

BodyMassMeasurement _measurement([String value = '75', int version = 1]) =>
    BodyMassMeasurement.fromJson({
      'id': 'mass',
      'context': 'clothed-training',
      'observedAt': instant(1).toIso8601String(),
      'mass': {'value': value, 'unit': 'kg'},
      'contentVersion': version,
    });
TrainingSession _start({String? mass = '75', Map<String, Object?>? model}) =>
    const TrainingService().start(
      sessionId: 'effective',
      revision: WorkoutRevision.publish(_definition(model: model)),
      startedAt: instant(10),
      bodyMassMeasurements: [if (mass != null) _measurement(mass)],
    );
Map<String, Object?> _view(TrainingSession s) =>
    const EffectiveMassService().evaluate(s);
Map<String, Object?> _estimate(TrainingSession s, {bool actual = false}) =>
    jsonObject(
      jsonObject(jsonList(_view(s), 'estimates').first, 'set')[actual
          ? 'actual'
          : 'suggested'],
      'estimate',
    );
String? _value(Map<String, Object?> result) => result['mass'] == null
    ? null
    : jsonObject(result['mass'], 'mass')['value'] as String;
Future<void> _withStore(
  Future<void> Function(TrainingStore, String) action,
) async {
  final dir = await Directory.systemTemp.createTemp('bodytmi-effective-mass-');
  final store = await TrainingStore.open('${dir.path}/db.sqlite');
  try {
    await action(store, dir.path);
  } finally {
    await store.close();
    await dir.delete(recursive: true);
  }
}

void effectiveMassTests() {
  test(
    'effective load follows an explicitly refreshed pre-workout mass snapshot',
    () {
      final before = _start();
      final beforeValue = _value(_estimate(before));
      final after = const TrainingService().refreshBodyMass(before, [
        _measurement('80', 2),
      ], confirm: true);
      equal(_value(_estimate(before)), beforeValue);
      check(_value(_estimate(after)) != beforeValue);
      equal(after.contentVersion, before.contentVersion + 1);
    },
  );

  test(
    'effective mass uses explicit fractional body mass, implement count and modeled assistance with exact unit conversion',
    () {
      final model = EffectiveMassModel.fromJson(
        _model(assistance: {'metric': 'assistance', 'multiplier': '0.5'}),
      );
      final body = _start().bodyMassInputs['bench-heavy']!;
      final estimate = model.evaluate(
        metrics: {
          'mass': Quantity('10', 'kg'),
          'assistance': Quantity('5', 'kg'),
        },
        bodyMass: body,
      );
      equal(_value(estimate), '66.25');
      equal(estimate['policy'], 'effective-mass/1');
      final inputs = jsonObject(estimate['inputs'], 'inputs');
      equal(jsonObject(inputs['addedMass'], 'added')['multiplier'], '2');
      equal(
        jsonObject(inputs['assistance'], 'assistance')['multiplier'],
        '0.5',
      );
      final external = EffectiveMassModel.fromJson(
        _model(
          fraction: '0',
          assistance: {
            'mass': {'value': '0', 'unit': 'kg'},
          },
        ),
      );
      equal(
        _value(external.evaluate(metrics: {'mass': Quantity('100', 'lb')})),
        '90.718474',
      );
      final single = EffectiveMassModel.fromJson(
        _model(
          fraction: '0',
          multiplier: '1',
          assistance: {
            'mass': {'value': '0', 'unit': 'kg'},
          },
        ),
      );
      equal(
        _value(single.evaluate(metrics: {'mass': Quantity('100', 'lb')})),
        '45.359237',
      );
      jsonEqual(
        EffectiveMassModel.fromJson(model.toJson()).toJson(),
        model.toJson(),
      );
    },
  );

  test(
    'effective-mass models require explicit bindings, fractions, multipliers and compatible dimensions',
    () {
      final mutations = <void Function(Map<String, Object?>)>[
        (j) => j.remove('bodyMassFraction'),
        (j) => j['bodyMassFraction'] = '1.1',
        (j) => j['bodyMassFraction'] = '-0.1',
        (j) => j['version'] = 0,
        (j) => j.remove('assistance'),
        (j) => jsonObject(j['addedMass'], 'added').remove('multiplier'),
        (j) => jsonObject(j['addedMass'], 'added')['multiplier'] = '-1',
        (j) => j['assistance'] = {
          'mass': {'value': '1', 'unit': 's'},
        },
        (j) => j['addedMass'] = {
          'mass': {'value': '1', 'unit': 'kg'},
          'metric': 'mass',
        },
      ];
      for (final mutate in mutations) {
        final j = _model();
        mutate(j);
        rejects(() => EffectiveMassModel.fromJson(j));
      }
      final j = _definition().toJson();
      final slot = jsonObject(jsonList(j, 'slots').first, 'slot');
      slot.remove('bodyMass');
      rejects(() => WorkoutDefinition.fromJson(j));
      slot['bodyMass'] = {'context': 'clothed-training'};
      jsonObject(
        jsonObject(slot['effectiveMass'], 'model')['addedMass'],
        'added',
      )['metric'] = 'reps';
      rejects(() => WorkoutDefinition.fromJson(j));
      final external = _model(fraction: '0');
      final noBody = _definition(model: external).toJson();
      jsonObject(jsonList(noBody, 'slots').first, 'slot').remove('bodyMass');
      WorkoutDefinition.fromJson(noBody);
      rejects(
        () => EffectiveMassModel.fromJson(
          external,
        ).evaluate(metrics: {'mass': Quantity('1', 's')}),
      );
    },
  );

  test(
    'missing, unconfirmed and negative estimates remain unavailable while explicit zeros and fractional rounding are preserved',
    () {
      final missing = _estimate(_start(mass: null));
      equal(missing['status'], 'unavailable');
      equal(missing['reason'], 'missing_inputs');
      equal(missing['mass'], null);
      check((missing['missingInputs']! as List<Object?>).contains('bodyMass'));
      final pending = _start();
      equal(_estimate(pending, actual: true)['reason'], 'unconfirmed');
      equal(_estimate(pending, actual: true)['mass'], null);
      final skipped = const TrainingService().skip(
        pending,
        pending.sets.first.id,
      );
      equal(_estimate(skipped, actual: true)['mass'], null);
      final negative = _estimate(
        _start(
          model: _model(
            assistance: {
              'mass': {'value': '1000', 'unit': 'kg'},
            },
          ),
        ),
      );
      equal(negative['reason'], 'negative_estimate');
      equal(negative['mass'], null);
      final zero = EffectiveMassModel.fromJson({
        ..._model(fraction: '0'),
        'addedMass': {
          'mass': {'value': '0', 'unit': 'kg'},
        },
        'assistance': {
          'mass': {'value': '0', 'unit': 'kg'},
        },
      });
      equal(_value(zero.evaluate(metrics: {})), '0');
      for (final fraction in ['0.0000000005', '0.9999999995']) {
        final model = {...zero.toJson(), 'bodyMassFraction': fraction};
        equal(
          _value(_estimate(_start(mass: '1', model: model))),
          fraction.startsWith('0.000') ? '0.000000001' : '1',
        );
      }
      final overflow = EffectiveMassModel.fromJson(
        _model(
          fraction: '0',
          multiplier: '1000',
          assistance: {
            'mass': {'value': '0', 'unit': 'kg'},
          },
        ),
      );
      final huge = List.filled(80, '9').join();
      equal(
        overflow.evaluate(metrics: {'mass': Quantity(huge, 'kg')})['reason'],
        'out_of_range',
      );
    },
  );

  test(
    'suggested and confirmed-actual estimates have explicit dependency fingerprints and never mutate raw training or numeric progression',
    () {
      final s = _start();
      final before = canonicalJson(s.toJson());
      final suggestion = _estimate(s);
      equal(_value(suggestion), '166.25');
      equal(jsonList(suggestion, 'warnings').single, 'stale_body_mass');
      equal(canonicalJson(s.toJson()), before);
      final done = finished(s);
      equal(_value(_estimate(done, actual: true)), '166.25');
      final corrected = const TrainingService().complete(
        done,
        done.sets.first.id,
        {'mass': Quantity('65', 'kg'), 'reps': Quantity('9', 'rep')},
      );
      final actual = _estimate(corrected, actual: true);
      equal(_value(actual), '176.25');
      equal(_value(_estimate(corrected)), '166.25');
      check(
        canonicalJson(actual['dependencyFingerprint']) !=
            canonicalJson(
              _estimate(done, actual: true)['dependencyFingerprint'],
            ),
      );
      equal(corrected.sets.first.actuals['mass']!.value.toString(), '65');
      check(!corrected.sets.first.actuals.containsKey('effectiveMass'));
      final rule = jsonObject(example('double-progression')['rule'], 'rule');
      final d = ProgressionDecision(
        session: done,
        slotId: 'bench-heavy',
        rule: rule,
      );
      equal(d.proposal.nextSets.first['mass']!.value.toString(), '60');
      equal(d.proposal.nextSets.first['reps']!.value.toString(), '9');
      final changed = _start(model: _model(multiplier: '1'));
      check(
        canonicalJson(_estimate(changed)['dependencyFingerprint']) !=
            canonicalJson(suggestion['dependencyFingerprint']),
      );
      equal(jsonList(_view(start()), 'estimates').length, 0);
    },
  );

  test(
    'pinned model and captured mass survive source/library changes, corrections and both portability formats',
    () => _withStore((store, dir) async {
      final service = StoredTrainingService(store);
      final mass = StoredBodyMassService(store);
      await service.publish(_definition(), 0);
      final measurement = _measurement().toJson()..remove('contentVersion');
      await mass.save(measurement, 0);
      var session = await service.start('old', definition().id, 1, instant(10));
      session = await service.edit(
        session.id,
        session.contentVersion,
        finished,
      );
      final original = canonicalJson(_view(session));
      await mass.save({
        ...measurement,
        'mass': {'value': '80', 'unit': 'kg'},
      }, 1);
      final changedModel = _model(multiplier: '1')..['version'] = 2;
      await service.publish(_definition(model: changedModel), 1);
      final next = await service.start('next', definition().id, 2, instant(11));
      equal(_value(_estimate(next)), '109.5');
      equal(canonicalJson(_view(await service.session('old'))), original);
      equal((await store.backup('$dir/native'))['databaseSchemaVersion'], 62);
      equal(
        (await LogicalArchiveFiles.export(
          await store.archive(),
          '$dir/logical.json',
        ))['format'],
        'bodytmi-logical-export/62',
      );
      final logical = await LogicalArchiveFiles.prepare('$dir/logical.json');
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
        equal(canonicalJson(_view((await reopened.session('old'))!)), original);
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
        equal(canonicalJson(_view((await again.session('old'))!)), original);
      } finally {
        await again.close();
      }
    }),
  );

  test(
    'legacy schema/format labels cannot carry new effective-mass model semantics',
    () => _withStore((store, dir) async {
      await StoredTrainingService(store).publish(_definition(), 0);
      await store.backup('$dir/native');
      await LogicalArchiveFiles.export(
        await store.archive(),
        '$dir/logical.json',
      );
      final doc = jsonObject(
        jsonDecode(await File('$dir/logical.json').readAsString()),
        'document',
      )..remove('sha256');
      jsonObject(doc['data'], 'data').remove('families');
      doc['format'] = 'bodytmi-logical-export/5';
      doc['sha256'] = sha256
          .convert(utf8.encode(canonicalJson(doc)))
          .toString();
      await File('$dir/forged.json').writeAsString(jsonEncode(doc));
      var rejected = false;
      try {
        await LogicalArchiveFiles.prepare('$dir/forged.json');
      } on BodyTmiException {
        rejected = true;
      }
      check(rejected);
      final raw = sqlite3.open('$dir/native/database.sqlite');
      try {
        raw.execute('DROP TABLE family_revisions');
        raw.execute('DROP TABLE workout_executions');
        raw.execute('DROP TABLE timing_activities');
        raw.execute('DROP TABLE derived_target_graphs');
        raw.execute('DROP TABLE IF EXISTS repeat_checkpoints');
        raw.execute('DROP TABLE IF EXISTS window_checkpoints');
        raw.execute('DROP TABLE IF EXISTS progression_reconciliations');
        raw.execute('DROP TABLE IF EXISTS lever_link_revisions');
        raw.execute('DROP TABLE IF EXISTS shared_lever_applications');
        raw.execute('DROP TABLE IF EXISTS link_retirement_anchors');
        raw.execute('DROP TABLE IF EXISTS program_upgrade_receipts');
        raw.execute('DROP TABLE IF EXISTS exercise_revisions');
        raw.execute('DROP TABLE IF EXISTS implementation_revisions');
        raw.execute('DROP TABLE IF EXISTS equipment_revisions');
        raw.execute('DROP TABLE IF EXISTS gym_revisions');
        raw.execute('DROP TABLE IF EXISTS equipment_instance_revisions');
        raw.execute('PRAGMA user_version = 5');
      } finally {
        raw.close();
      }
      rejects(
        () => NativeBackup.validateDatabase('$dir/native/database.sqlite'),
      );
    }),
  );

  test(
    'v5 profiles retain their exact frozen inputs and do not acquire an estimate model when upgraded',
    () => _withStore((store, dir) async {
      final definition = WorkoutDefinition.fromJson(
        example('bodyweight-practice')['definition'],
      );
      final service = StoredTrainingService(store);
      await service.publish(definition, 0);
      final m = _measurement().toJson()..remove('contentVersion');
      await StoredBodyMassService(store).save(m, 0);
      final s = await service.start('legacy', definition.id, 1, instant(10));
      final original = (await store.archive()).toJson();
      final doc = <String, Object?>{
        'format': 'bodytmi-logical-export/5',
        'applicationVersion': '0.1.0',
        'data': (Map<String, Object?>.from(original)
          ..remove('timers')
          ..remove('families')
          ..remove('executions')),
      };
      doc['sha256'] = sha256
          .convert(utf8.encode(canonicalJson(doc)))
          .toString();
      await File('$dir/v5.json').writeAsString(jsonEncode(doc));
      final prepared = await LogicalArchiveFiles.prepare('$dir/v5.json');
      try {
        jsonEqual(prepared.archive.toJson(), original);
      } finally {
        await prepared.close();
      }
      await store.close();
      final raw = sqlite3.open('$dir/db.sqlite');
      try {
        raw.execute('DROP TABLE family_revisions');
        raw.execute('DROP TABLE workout_executions');
        raw.execute('DROP TABLE timing_activities');
        raw.execute('DROP TABLE derived_target_graphs');
        raw.execute('DROP TABLE IF EXISTS repeat_checkpoints');
        raw.execute('DROP TABLE IF EXISTS window_checkpoints');
        raw.execute('DROP TABLE IF EXISTS progression_reconciliations');
        raw.execute('DROP TABLE IF EXISTS lever_link_revisions');
        raw.execute('DROP TABLE IF EXISTS shared_lever_applications');
        raw.execute('DROP TABLE IF EXISTS link_retirement_anchors');
        raw.execute('DROP TABLE IF EXISTS program_upgrade_receipts');
        raw.execute('DROP TABLE IF EXISTS exercise_revisions');
        raw.execute('DROP TABLE IF EXISTS implementation_revisions');
        raw.execute('DROP TABLE IF EXISTS equipment_revisions');
        raw.execute('DROP TABLE IF EXISTS gym_revisions');
        raw.execute('DROP TABLE IF EXISTS equipment_instance_revisions');
        raw.execute('PRAGMA user_version = 5');
      } finally {
        raw.close();
      }
      equal(
        (await NativeBackup.create(
          '$dir/db.sqlite',
          '$dir/v5-native',
        ))['databaseSchemaVersion'],
        5,
      );
      final reopened = await TrainingStore.open('$dir/db.sqlite');
      try {
        jsonEqual((await reopened.session('legacy'))!.toJson(), s.toJson());
        equal(
          jsonList(
            _view((await reopened.session('legacy'))!),
            'estimates',
          ).length,
          0,
        );
      } finally {
        await reopened.close();
      }
    }),
  );

  test(
    'native pure/stored effective-load CLI results match and result corrections change only the actual estimate',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-effective-cli-',
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

        await command('store publish', {
          'definition': _definition().toJson(),
          'expectedRevision': 0,
        });
        final observation = _measurement().toJson()..remove('contentVersion');
        await command('mass record', {'measurement': observation});
        var session = jsonObject(
          await command('store start', {
            'id': 'cli',
            'templateId': definition().id,
            'revision': 1,
            'startedAt': instant(10).toIso8601String(),
          }),
          'session',
        );
        final estimated = await command('store effective-load', {'id': 'cli'});
        jsonEqual(
          estimated,
          await command('session effective-load', {
            'session': session,
          }, stored: false),
        );
        final set = jsonObject(jsonList(session, 'sets').first, 'set');
        session = jsonObject(
          await command('store complete', {
            'id': 'cli',
            'setId': set['id'],
            'expectedVersion': session['contentVersion'],
            'actuals': {
              'mass': {'value': '65', 'unit': 'kg'},
              'reps': {'value': '8', 'unit': 'rep'},
            },
          }),
          'session',
        );
        final corrected = jsonObject(
          await command('store effective-load', {'id': 'cli'}),
          'view',
        );
        final row = jsonObject(
          jsonList(corrected, 'estimates').first,
          'estimate',
        );
        equal(_value(jsonObject(row['actual'], 'actual')), '176.25');
        equal(_value(jsonObject(row['suggested'], 'suggested')), '166.25');
        jsonEqual(
          corrected,
          await command('session effective-load', {
            'session': session,
          }, stored: false),
        );
        jsonEqual(await command('store show', {'id': 'cli'}), session);
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
