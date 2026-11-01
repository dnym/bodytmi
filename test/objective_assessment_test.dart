import 'dart:convert';
import 'dart:io';
import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'cli_test.dart';
import 'fixtures.dart';
import 'support.dart';

Map<String, Object?> _q(String value, String unit) => {
  'value': value,
  'unit': unit,
};
Map<String, Object?> _criteria() => {
  'load': {'mode': 'exact', 'value': _q('100', 'lb')},
  'reps': {
    'mode': 'range',
    'minimum': _q('6', 'rep'),
    'maximum': _q('12', 'rep'),
    'upperMeaning': 'progressionThreshold',
  },
  'duration': {'mode': 'minimum', 'minimum': _q('1', 'min')},
  'distance': {
    'mode': 'maximum',
    'maximum': _q('2', 'm'),
    'upperMeaning': 'stoppingCue',
  },
  'extra': {'mode': 'observe', 'unit': 'rep'},
  'amrap': {'mode': 'maxEffort', 'unit': 'rep'},
};
Map<String, Object?> _assess(Object? criteria, Metrics actuals) =>
    const ObjectiveAssessment().evaluate(criteria, actuals);
Map<String, Object?> _metric(Map<String, Object?> data, String name) =>
    jsonObject(jsonObject(data['metrics'], 'metrics')[name], 'metric');
String _status(Map<String, Object?> data) =>
    requiredString(jsonObject(data['summary'], 'summary'), 'relation');

void objectiveAssessmentTests() {
  test(
    'objective assessment compares exact converted quantities and inclusive range boundaries without rounding',
    () {
      final c = _criteria();
      final values = metrics({
        'load': ('45.359237', 'kg'),
        'reps': ('6', 'rep'),
        'duration': ('60', 's'),
        'distance': ('200', 'cm'),
        'extra': ('0', 'rep'),
        'amrap': ('12', 'rep'),
      });
      final result = _assess(c, values);
      equal(_status(result), 'met');
      for (final key in ['load', 'reps', 'duration', 'distance'])
        equal(_metric(result, key)['relation'], 'met');
      equal(_metric(result, 'extra')['relation'], 'observed');
      equal(_metric(result, 'amrap')['relation'], 'observed');
      equal(_metric(result, 'reps')['lowerSatisfied'], true);
      equal(_metric(result, 'reps')['upperSatisfied'], true);
      equal(_metric(result, 'reps')['upperReached'], false);
      equal(_metric(result, 'distance')['upperReached'], true);
      equal(
        jsonObject(_metric(result, 'load')['actual'], 'actual')['value'],
        '45.359237',
      );
      final atUpper = _assess(c, {...values, 'reps': Quantity('12', 'rep')});
      equal(_metric(atUpper, 'reps')['relation'], 'met');
      equal(_metric(atUpper, 'reps')['upperReached'], true);
      final over = _assess(c, {
        ...values,
        'reps': Quantity('13', 'rep'),
        'distance': Quantity('200.00001', 'cm'),
      });
      equal(_metric(over, 'reps')['relation'], 'above');
      equal(_metric(over, 'distance')['upperSatisfied'], false);
      equal(_status(over), 'above');
    },
  );
  test(
    'objective assessment reports mixed and missing independently and never treats zero as missing',
    () {
      final c = {
        'reps': {'mode': 'minimum', 'minimum': _q('1', 'rep')},
        'duration': {
          'mode': 'maximum',
          'maximum': _q('10', 's'),
          'upperMeaning': 'desiredCeiling',
        },
        'distance': {'mode': 'observe', 'unit': 'm'},
      };
      final mixed = _assess(
        c,
        metrics({
          'reps': ('0', 'rep'),
          'duration': ('11', 's'),
          'distance': ('0', 'm'),
        }),
      );
      equal(_status(mixed), 'mixed');
      equal(_metric(mixed, 'reps')['relation'], 'below');
      equal(_metric(mixed, 'distance')['relation'], 'observed');
      equal(
        jsonObject(_metric(mixed, 'distance')['actual'], 'actual')['value'],
        '0',
      );
      final missing = _assess(
        c,
        metrics({'reps': ('0', 'rep'), 'duration': ('11', 's')}),
      );
      equal(_status(missing), 'unknown');
      equal(_metric(missing, 'distance')['relation'], 'unknown');
      final counts = jsonObject(
        jsonObject(missing['summary'], 'summary')['counts'],
        'counts',
      );
      equal(counts['below'], 1);
      equal(counts['above'], 1);
      equal(counts['unknown'], 1);
      equal(
        _status(
          _assess({
            'only': {'mode': 'observe', 'unit': 'kg'},
          }, metrics({'only': ('0', 'kg')})),
        ),
        'observed',
      );
    },
  );
  test(
    'objective assessment keeps upper-bound meaning explicit and reports cues without delivering or applying them',
    () {
      for (final meaning in [
        'desiredCeiling',
        'progressionThreshold',
        'stoppingCue',
      ]) {
        final r = _assess({
          'x': {
            'mode': 'maximum',
            'maximum': _q('10', 's'),
            'upperMeaning': meaning,
          },
        }, metrics({'x': ('10', 's')}));
        final row = _metric(r, 'x');
        equal(row['relation'], 'met');
        equal(row['upperReached'], true);
        equal(
          jsonObject(row['objective'], 'objective')['upperMeaning'],
          meaning,
        );
        equal(jsonObject(r['policy'], 'policy')['purpose'], 'descriptive');
      }
      final below = _assess({
        'x': {
          'mode': 'maximum',
          'maximum': _q('10', 's'),
          'upperMeaning': 'stoppingCue',
        },
      }, metrics({'x': ('9', 's')}));
      equal(_metric(below, 'x')['upperReached'], false);
      equal(_status(below), 'met');
    },
  );
  test(
    'objective assessment rejects malformed policies incompatible units ambiguous bounds and resource overflow',
    () {
      for (final input in <Object?>[
        null,
        <String, Object?>{},
        {
          'x': {'mode': 'unknown'},
        },
        {
          'x': {'mode': 'exact'},
        },
        {
          'x': {
            'mode': 'minimum',
            'minimum': _q('1', 's'),
            'maximum': _q('2', 's'),
          },
        },
        {
          'x': {'mode': 'maximum', 'maximum': _q('2', 's')},
        },
        {
          'x': {
            'mode': 'maximum',
            'maximum': _q('2', 's'),
            'upperMeaning': 'automatic',
          },
        },
        {
          'x': {
            'mode': 'range',
            'minimum': _q('3', 's'),
            'maximum': _q('2', 's'),
            'upperMeaning': 'desiredCeiling',
          },
        },
        {
          'x': {
            'mode': 'range',
            'minimum': _q('1', 's'),
            'maximum': _q('2', 'kg'),
            'upperMeaning': 'desiredCeiling',
          },
        },
        {
          'x': {'mode': 'observe', 'unit': 'made-up'},
        },
        {
          'x': {'mode': 'maxEffort', 'unit': 's'},
        },
        {
          'bad key': {'mode': 'observe', 'unit': 'kg'},
        },
        {
          'x': {'mode': 'observe', 'unit': 'rep', 'extra': true},
        },
      ]) {
        rejects(() => _assess(input, {}));
      }
      rejects(
        () => _assess({
          'x': {'mode': 'minimum', 'minimum': _q('1', 'kg')},
        }, metrics({'x': ('1', 's')})),
      );
      rejects(
        () => _assess({
          for (var i = 0; i < 101; i++)
            'm$i': {'mode': 'observe', 'unit': 'rep'},
        }, {}),
      );
      rejects(
        () => _assess(
          {
            'x': {'mode': 'observe', 'unit': 'rep'},
          },
          {for (var i = 0; i < 10001; i++) 'm$i': Quantity('1', 'rep')},
        ),
      );
    },
  );
  test(
    'objective assessment is deterministic, preserves entered provenance and identifies ignored actual metrics',
    () {
      final c = {
        'z': {
          'mode': 'range',
          'minimum': _q('1', 'min'),
          'maximum': _q('2', 'min'),
          'upperMeaning': 'desiredCeiling',
        },
        'a': {'mode': 'exact', 'value': _q('100', 'lb')},
      };
      final values = metrics({
        'z': ('90.00', 's'),
        'a': ('100.00', 'lb'),
        'unused': ('1', 'rep'),
      });
      final a = _assess(c, values);
      final b = _assess({'a': c['a'], 'z': c['z']}, values);
      equal(canonicalJson(a), canonicalJson(b));
      jsonEqual(a['ignoredActualMetrics'], ['unused']);
      equal(
        jsonObject(
          jsonObject(_metric(a, 'a')['actual'], 'actual')['entered'],
          'entered',
        )['value'],
        '100.00',
      );
      equal(
        jsonObject(
          jsonObject(_metric(a, 'z')['objective'], 'objective')['minimum'],
          'minimum',
        )['unit'],
        's',
      );
      equal(
        jsonObject(
          jsonObject(
            jsonObject(_metric(a, 'z')['objective'], 'objective')['minimum'],
            'minimum',
          )['entered'],
          'entered',
        )['unit'],
        'min',
      );
    },
  );
  test(
    'objective assessment of sessions uses confirmed current actuals, explicit source versions and interruption metadata',
    () {
      final criteria = {
        'mass': {'mode': 'minimum', 'minimum': _q('55', 'kg')},
        'reps': {
          'mode': 'range',
          'minimum': _q('8', 'rep'),
          'maximum': _q('12', 'rep'),
          'upperMeaning': 'progressionThreshold',
        },
      };
      final service = const TrainingService();
      var s = start();
      final setId = s.sets.first.id;
      final planned = service.assessObjectives(s, setId, criteria);
      equal(_status(planned), 'unknown');
      equal(_metric(planned, 'mass')['actual'], null);
      s = service.complete(s, setId, {
        'mass': Quantity('60', 'kg'),
        'reps': Quantity('9', 'rep'),
      });
      final observed = service.assessObjectives(s, setId, criteria);
      equal(_status(observed), 'met');
      final source = jsonObject(observed['source'], 'source');
      equal(source['setContentVersion'], s.sets.first.contentVersion);
      equal(source['interrupted'], false);
      s = service.annotate(
        s,
        setId,
        SetObservations.fromJson({'terminationReason': 'interrupted'}),
      );
      final interrupted = service.assessObjectives(s, setId, criteria);
      equal(_status(interrupted), 'met');
      equal(jsonObject(interrupted['source'], 'source')['interrupted'], true);
      s = service.complete(s, setId, {
        'mass': Quantity('50', 'kg'),
        'reps': Quantity('13', 'rep'),
      });
      final corrected = service.assessObjectives(s, setId, criteria);
      equal(_status(corrected), 'mixed');
      equal(
        jsonObject(corrected['source'], 'source')['setContentVersion'],
        s.sets.first.contentVersion,
      );
      s = service.skip(s, setId, confirm: true);
      final skipped = service.assessObjectives(s, setId, criteria);
      equal(_status(skipped), 'unknown');
      equal(jsonObject(skipped['source'], 'source')['setStatus'], 'skipped');
    },
  );
  test(
    'objective assessment identifies the authored max-effort intent separately from supplied criteria',
    () {
      final revision = WorkoutRevision.publish(
        WorkoutDefinition.fromJson(
          example('max-effort-bodyweight')['definition'],
        ),
      );
      var s = const TrainingService().start(
        sessionId: 'max',
        revision: revision,
        startedAt: instant(1),
      );
      s = const TrainingService().complete(s, s.sets.single.id, {
        'reps': Quantity('0', 'rep'),
      });
      final result = const TrainingService().assessObjectives(
        s,
        s.sets.single.id,
        {
          'reps': {
            'mode': 'range',
            'minimum': _q('1', 'rep'),
            'maximum': _q('10', 'rep'),
            'upperMeaning': 'desiredCeiling',
          },
        },
      );
      equal(_status(result), 'below');
      jsonEqual(jsonObject(result['source'], 'source')['authoredObjectives'], {
        'reps': {'mode': 'maxEffort', 'unit': 'rep'},
      });
      equal(jsonObject(result['policy'], 'policy')['purpose'], 'descriptive');
    },
  );
  test(
    'objective assessment pure CLI accepts partial actuals, validates schemas and preserves explicit criteria',
    () {
      final request = {
        'schemaVersion': 1,
        'objectives': {
          'reps': {
            'mode': 'range',
            'minimum': _q('6', 'rep'),
            'maximum': _q('12', 'rep'),
            'upperMeaning': 'progressionThreshold',
          },
        },
        'actuals': {'reps': _q('12', 'rep')},
      };
      final output = const Commands().execute('objective evaluate', request);
      equal(
        _metric(jsonObject(output['data'], 'data'), 'reps')['upperReached'],
        true,
      );
      rejects(
        () => const Commands().execute('objective evaluate', {
          ...request,
          'extra': true,
        }),
      );
      rejects(
        () => const Commands().execute('objective evaluate', {
          ...request,
          'schemaVersion': 2,
        }),
      );
    },
  );
  test(
    'objective assessment native store and snapshot queries agree without modifying persisted records or progression',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'bodytmi-objective-assessment-',
      );
      final path = '${dir.path}/db.sqlite';
      var store = await TrainingStore.open(path);
      try {
        final service = StoredTrainingService(store);
        final rev = await service.publish(definition(), 0);
        var s = await service.start(
          'one',
          rev.definition.id,
          rev.number,
          instant(1),
        );
        s = await service.edit(s.id, s.contentVersion, finished);
        final rule = jsonObject(example('double-progression')['rule'], 'rule');
        final p = await StoredProgressionService(
          store,
        ).propose(s.id, s.sets.first.slotId, rule);
        final before = canonicalJson((await store.archive()).toJson());
        final criteria = {
          'mass': {'mode': 'minimum', 'minimum': _q('50', 'kg')},
          'reps': {
            'mode': 'range',
            'minimum': _q('8', 'rep'),
            'maximum': _q('12', 'rep'),
            'upperMeaning': 'progressionThreshold',
          },
        };
        final pure = const TrainingService().assessObjectives(
          s,
          s.sets.first.id,
          criteria,
        );
        final query = {
          'schemaVersion': 1,
          'session': s.toJson(),
          'setId': s.sets.first.id,
          'objectives': criteria,
        };
        final snapshot = const Commands().execute(
          'session assess-objectives',
          query,
        );
        equal(canonicalJson(snapshot['data']), canonicalJson(pure));
        await store.close();
        final native = await invoke(
          ['store', 'assess-objectives'],
          jsonEncode({
            'schemaVersion': 1,
            'database': path,
            'id': s.id,
            'setId': s.sets.first.id,
            'objectives': criteria,
          }),
        );
        equal(native.code, 0);
        equal(
          canonicalJson(
            jsonObject(jsonDecode(native.output), 'response')['data'],
          ),
          canonicalJson(pure),
        );
        final bad = await invoke(
          ['store', 'assess-objectives'],
          jsonEncode({
            'schemaVersion': 1,
            'database': path,
            'id': s.id,
            'setId': s.sets.first.id,
            'objectives': {
              'reps': {
                'mode': 'range',
                'minimum': _q('12', 'rep'),
                'maximum': _q('6', 'rep'),
                'upperMeaning': 'desiredCeiling',
              },
            },
          }),
        );
        equal(bad.code, 2);
        equal(bad.output, '');
        check(!bad.error.contains('internal'));
        store = await TrainingStore.open(path);
        equal(canonicalJson((await store.archive()).toJson()), before);
        equal(
          canonicalJson(
            (await StoredProgressionService(
              store,
            ).decision(s.id, s.sets.first.slotId)).toJson(),
          ),
          canonicalJson(p.toJson()),
        );
      } finally {
        await store.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
