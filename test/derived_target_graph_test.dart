import 'dart:convert';
import 'dart:io';

import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:bodytmi_storage/bodytmi_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart' show expectLater, throwsA, isA;

import 'fixtures.dart';
import 'support.dart';

Map<String, Object?> _graph({
  String id = 'bench-percentages',
  Map<String, Object?>? bindings,
  List<Object?>? nodes,
}) => {
  'id': id,
  'name': 'Bench percentage ladder',
  'nodes':
      nodes ??
      [
        {
          'id': 'working',
          'kind': 'scale',
          'unit': 'kg',
          'input': 'max',
          'factor': '0.8',
        },
        {'id': 'max', 'kind': 'source', 'unit': 'kg', 'sourceId': 'bench_max'},
        {
          'id': 'mass',
          'kind': 'source',
          'unit': 'kg',
          'sourceId': 'training_mass',
        },
      ],
  'bindings':
      bindings ??
      {
        'bench_max': {
          'kind': 'history',
          'metric': 'mass',
          'direction': 'highest',
          'templateId': 'upper-a',
          'slotId': 'bench-heavy',
        },
        'training_mass': {'kind': 'bodyMass', 'context': 'clothed-training'},
      },
};

void derivedTargetGraphTests() {
  test(
    'derived target graphs normalize nodes and require an explicit policy per source',
    () {
      final graph = DerivedTargetGraph.fromJson(_graph());
      equal(graph.id, 'bench-percentages');
      equal(graph.name, 'Bench percentage ladder');
      equal(graph.sourceIds.join(','), 'bench_max,training_mass');
      equal(graph.nodes.map((n) => n['id']).join(','), 'mass,max,working');
      final round = DerivedTargetGraph.fromJson(graph.toJson());
      jsonEqual(round.toJson(), graph.toJson());
      rejects(
        () => DerivedTargetGraph.fromJson(
          _graph(
            nodes: [
              {
                'id': 'a',
                'kind': 'scale',
                'unit': 'kg',
                'input': 'b',
                'factor': '1',
              },
              {
                'id': 'b',
                'kind': 'scale',
                'unit': 'kg',
                'input': 'a',
                'factor': '1',
              },
            ],
            bindings: {
              'x': {
                'kind': 'manual',
                'version': 1,
                'value': {'value': '1', 'unit': 'kg'},
              },
              'y': {
                'kind': 'manual',
                'version': 1,
                'value': {'value': '1', 'unit': 'kg'},
              },
            },
          ),
        ),
      );
      rejects(
        () => DerivedTargetGraph.fromJson(
          _graph(
            nodes: [
              {
                'id': 'x',
                'kind': 'scale',
                'unit': 'kg',
                'input': 'missing',
                'factor': '1',
              },
            ],
            bindings: {
              'x': {
                'kind': 'manual',
                'version': 1,
                'value': {'value': '1', 'unit': 'kg'},
              },
            },
          ),
        ),
      );
      rejects(
        () => DerivedTargetGraph.fromJson(
          _graph(
            bindings: {
              'bench_max': {
                'kind': 'manual',
                'version': 0,
                'value': {'value': '1', 'unit': 'kg'},
              },
              'training_mass': {'kind': 'bodyMass', 'context': 'x'},
            },
          ),
        ),
      );
      rejects(
        () => DerivedTargetGraph.fromJson(
          _graph(
            bindings: {
              'bench_max': {
                'kind': 'manual',
                'version': 1,
                'value': {'value': '1', 'unit': 'rep'},
              },
              'training_mass': {'kind': 'bodyMass', 'context': 'x'},
            },
          ),
        ),
      );
      rejects(
        () => DerivedTargetGraph.fromJson(
          _graph(
            nodes: [
              {'id': 'x', 'kind': 'source', 'unit': 'rep', 'sourceId': 'x'},
            ],
            bindings: {
              'x': {'kind': 'bodyMass', 'context': 'x'},
            },
          ),
        ),
      );
      rejects(
        () => DerivedTargetGraph.fromJson(
          _graph(
            bindings: {
              'bench_max': {
                'kind': 'bodyMass',
                'context': 'x',
                'dailyMode': 'smooth',
              },
              'training_mass': {'kind': 'bodyMass', 'context': 'x'},
            },
          ),
        ),
      );
      rejects(
        () => DerivedTargetGraph.fromJson(
          _graph(
            bindings: {
              'bench_max': {
                'kind': 'history',
                'metric': 'mass',
                'direction': 'greatest',
              },
              'training_mass': {'kind': 'bodyMass', 'context': 'x'},
            },
          ),
        ),
      );
      rejects(
        () => DerivedTargetGraph.fromJson(
          _graph(
            bindings: {
              'bench_max': {'kind': 'history', 'metric': 'mass', 'ordinal': -1},
              'training_mass': {'kind': 'bodyMass', 'context': 'x'},
            },
          ),
        ),
      );
      rejects(
        () => DerivedTargetGraph.fromJson(
          _graph(
            bindings: {
              'bench_max': {
                'kind': 'history',
                'metric': 'mass',
                'from': 'yesterday',
              },
              'training_mass': {'kind': 'bodyMass', 'context': 'x'},
            },
          ),
        ),
      );
      rejects(
        () => DerivedTargetGraph.fromJson(
          _graph(
            bindings: {
              'bench_max': {'kind': 'mystery'},
              'training_mass': {'kind': 'bodyMass', 'context': 'x'},
            },
          ),
        ),
      );
      rejects(
        () => DerivedTargetGraph.fromJson(
          _graph(
            bindings: {
              'bench_max': {'kind': 'bodyMass', 'context': 'x'},
              'training_mass': {'kind': 'bodyMass', 'context': 'x'},
              'extra': {
                'kind': 'manual',
                'version': 1,
                'value': {'value': '1', 'unit': 'kg'},
              },
            },
          ),
        ),
      );
      rejects(
        () => DerivedTargetGraph.fromJson(
          _graph(
            nodes: [
              for (var i = 0; i < 257; i++)
                {
                  'id': 'n$i',
                  'kind': 'source',
                  'unit': 'kg',
                  'sourceId': 's$i',
                },
            ],
            bindings: {
              for (var i = 0; i < 257; i++)
                's$i': {
                  'kind': 'manual',
                  'version': 1,
                  'value': {'value': '1', 'unit': 'kg'},
                },
            },
          ),
        ),
      );
    },
  );

  test(
    'derived target graph revisions number immutably per graph identity',
    () {
      final first = DerivedTargetGraphRevision.publish(
        DerivedTargetGraph.fromJson(_graph()),
      );
      final second = DerivedTargetGraphRevision.publish(
        DerivedTargetGraph.fromJson(_graph()),
        previous: first,
      );
      equal(first.number, 1);
      equal(second.number, 2);
      rejects(
        () => DerivedTargetGraphRevision.publish(
          DerivedTargetGraph.fromJson(_graph(id: 'other')),
          previous: first,
        ),
      );
      rejects(
        () => DerivedTargetGraphRevision.fromJson({
          'schemaVersion': 1,
          'revision': 0,
          'graph': _graph(),
        }),
      );
      rejects(() => validateDerivedTargetGraphRevisions([first, first]));
      rejects(() => validateDerivedTargetGraphRevisions([second]));
    },
  );

  Future<void> _stored(Future<void> Function(TrainingStore) action) async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-graph-');
    final store = await TrainingStore.open('${dir.path}/db.sqlite');
    try {
      final rev = revision();
      await store.insertRevision(rev);
      var first = start(id: 's-one', day: 1, from: rev);
      for (final set in first.sets) {
        first = const TrainingService().complete(first, set.id, {
          'mass': Quantity('70', 'kg'),
          'reps': Quantity('8', 'rep'),
        });
      }
      first = first.finish(instant(1).add(const Duration(hours: 1)));
      await store.insertSession(first);
      await store.recordFinalization(first.id);
      var second = start(id: 's-two', day: 3, from: rev);
      for (final set in second.sets) {
        second = const TrainingService().complete(second, set.id, {
          'mass': Quantity('75', 'kg'),
          'reps': Quantity('6', 'rep'),
        });
      }
      for (final set in second.sets) {
        if (set.slotId == 'bench-heavy') {
          second = const TrainingService().annotate(
            second,
            set.id,
            SetObservations.fromJson({
              'terminationReason': 'interrupted',
              'notes': 'Stopped early.',
            }),
          );
        }
      }
      second = second.finish(instant(3).add(const Duration(hours: 1)));
      await store.insertSession(second);
      await store.recordFinalization(second.id);
      await StoredBodyMassService(store).save({
        'id': 'mass-a',
        'context': 'clothed-training',
        'observedAt': '2026-10-01T08:00:00+00:00',
        'mass': {'value': '80', 'unit': 'kg'},
      }, 0);
      await StoredBodyMassService(store).save({
        'id': 'mass-b',
        'context': 'health',
        'observedAt': '2026-10-02T08:00:00+00:00',
        'mass': {'value': '79', 'unit': 'kg'},
      }, 0);
      await action(store);
    } finally {
      await store.close();
      await dir.delete(recursive: true);
    }
  }

  Map<String, Object?> _nodeValue(Map<String, Object?> resolved, String node) {
    final nodes =
        (jsonObject(resolved['resolution'], 'resolution')['nodes']!
                as List<Object?>)
            .map((e) => jsonObject(e, 'node'))
            .toList();
    return jsonObject(
      jsonObject(nodes.singleWhere((n) => n['id'] == node)['value'], 'value'),
      'value',
    );
  }

  test(
    'history selection uses distinct extremes and excludes results finalized after asOf',
    () => _stored((store) async {
      final rev = revision();
      for (final item in [(2, 'fifty', '50'), (4, 'hundred', '100')]) {
        var session = start(id: item.$2, day: item.$1, from: rev);
        for (final set in session.sets) {
          session = const TrainingService().complete(session, set.id, {
            'mass': Quantity(item.$3, 'kg'),
            'reps': Quantity('8', 'rep'),
          });
        }
        session = session.finish(
          instant(item.$1).add(const Duration(hours: 1)),
        );
        await store.insertSession(session);
        await store.recordFinalization(session.id);
      }
      final service = DerivedTargetGraphService(store);
      for (final direction in ['lowest', 'highest']) {
        await service.publish(
          DerivedTargetGraph.fromJson(
            _graph(
              id: direction,
              bindings: {
                'bench_max': {
                  'kind': 'history',
                  'metric': 'mass',
                  'slotId': 'bench-heavy',
                  'direction': direction,
                },
                'training_mass': {
                  'kind': 'manual',
                  'version': 1,
                  'value': {'value': '1', 'unit': 'kg'},
                },
              },
            ),
          ),
          0,
        );
      }
      equal(
        _nodeValue(
          await service.resolve('lowest', null, instant(10)),
          'max',
        )['value'],
        '50',
      );
      equal(
        _nodeValue(
          await service.resolve('highest', null, instant(10)),
          'max',
        )['value'],
        '100',
      );
      equal(
        _nodeValue(
          await service.resolve('highest', null, instant(4)),
          'max',
        )['value'],
        '70',
      );
      equal(
        _nodeValue(
          await service.resolve('lowest', null, instant(2)),
          'max',
        )['value'],
        '70',
      );
      equal(
        _nodeValue(
          await service.resolve(
            'lowest',
            null,
            instant(2).add(const Duration(hours: 1)),
          ),
          'max',
        )['value'],
        '50',
      );
    }),
  );

  test(
    'history graph selects ad hoc, one run, or explicit all-runs context',
    () => _stored((store) async {
      final programs = ProgramService(store);
      final template = definition();
      await programs.publish(
        ProgramDefinition.fromJson({
          'id': 'two-runs',
          'name': 'Two runs',
          'plan': {
            'id': 'cycle',
            'type': 'group',
            'children': [
              {
                'id': 'day',
                'type': 'day',
                'templateId': template.id,
                'revision': 1,
              },
            ],
          },
        }),
        0,
      );
      for (final item in [
        ('run-a', 'session-a', '45'),
        ('run-b', 'session-b', '110'),
      ]) {
        await programs.create(item.$1, 'two-runs', 1, instant(1));
        final session = await programs.start(item.$1, 1, item.$2, instant(4));
        await StoredTrainingService(store).edit(
          session.id,
          session.contentVersion,
          (value) {
            var completed = value;
            for (final set in completed.sets) {
              completed = const TrainingService().complete(completed, set.id, {
                'mass': Quantity(item.$3, 'kg'),
                'reps': Quantity('8', 'rep'),
              });
            }
            return completed.finish(instant(4).add(const Duration(hours: 1)));
          },
        );
      }
      final service = DerivedTargetGraphService(store);
      await service.publish(
        DerivedTargetGraph.fromJson(_graph(id: 'scoped')),
        0,
      );
      final adHoc = await service.resolve('scoped', null, instant(10));
      equal(_nodeValue(adHoc, 'max')['value'], '70');
      equal(jsonObject(adHoc['historyScope'], 'scope')['mode'], 'adHoc');
      equal(
        _nodeValue(
          await service.resolve('scoped', null, instant(10), 'run-a'),
          'max',
        )['value'],
        '45',
      );
      equal(
        _nodeValue(
          await service.resolve('scoped', null, instant(10), 'run-b'),
          'max',
        )['value'],
        '110',
      );
      equal(
        _nodeValue(
          await service.resolve('scoped', null, instant(10), null, true),
          'max',
        )['value'],
        '110',
      );
      await expectLater(
        service.resolve('scoped', null, instant(10), 'run-a', true),
        throwsA(isA<BodyTmiException>()),
      );
    }),
  );

  test(
    'body mass source fingerprints detect inserted and deleted observations even when max version is unchanged',
    () => _stored((store) async {
      final service = DerivedTargetGraphService(store);
      await service.publish(
        DerivedTargetGraph.fromJson(_graph(id: 'fingerprint')),
        0,
      );
      Map<String, Object?> mass(Map<String, Object?> result) => jsonObject(
        jsonObject(result['bindings'], 'bindings')['training_mass'],
        'mass',
      );
      final before = mass(
        await service.resolve('fingerprint', null, instant(10)),
      );
      final bodyMass = StoredBodyMassService(store);
      await bodyMass.save({
        'id': 'inserted',
        'context': 'clothed-training',
        'observedAt': '2026-10-02T08:00:00Z',
        'mass': {'value': '85', 'unit': 'kg'},
      }, 0);
      final after = mass(
        await service.resolve('fingerprint', null, instant(10)),
      );
      equal(before['sourceVersion'], after['sourceVersion']);
      final beforeFingerprint = jsonObject(
        jsonObject(before['provenance'], 'provenance')['sourceFingerprint'],
        'fingerprint',
      );
      final afterFingerprint = jsonObject(
        jsonObject(after['provenance'], 'provenance')['sourceFingerprint'],
        'fingerprint',
      );
      check(jsonEncode(beforeFingerprint) != jsonEncode(afterFingerprint));
      await bodyMass.delete('mass-a', 1, confirm: true);
      final deleted = mass(
        await service.resolve('fingerprint', null, instant(10)),
      );
      equal(after['sourceVersion'], deleted['sourceVersion']);
      check(
        jsonEncode(afterFingerprint) !=
            jsonEncode(
              jsonObject(
                jsonObject(
                  deleted['provenance'],
                  'provenance',
                )['sourceFingerprint'],
                'fingerprint',
              ),
            ),
      );
    }),
  );

  test(
    'history source fingerprints retain eligible membership and change for non-winning results',
    () => _stored((store) async {
      final service = DerivedTargetGraphService(store);
      await service.publish(
        DerivedTargetGraph.fromJson(_graph(id: 'history-fingerprint')),
        0,
      );
      Map<String, Object?> history(Map<String, Object?> result) => jsonObject(
        jsonObject(result['bindings'], 'bindings')['bench_max'],
        'history',
      );
      Map<String, Object?> fingerprint(Map<String, Object?> binding) =>
          jsonObject(
            jsonObject(
              binding['provenance'],
              'provenance',
            )['sourceFingerprint'],
            'fingerprint',
          );
      final before = history(
        await service.resolve('history-fingerprint', null, instant(10)),
      );
      final beforeFingerprint = fingerprint(before);
      equal(beforeFingerprint['policy'], 'bodytmi-history-source/1');
      final rev = revision();
      var lower = start(id: 'nonwinner', day: 4, from: rev);
      for (final set in lower.sets) {
        lower = const TrainingService().complete(lower, set.id, {
          'mass': Quantity('60', 'kg'),
          'reps': Quantity('8', 'rep'),
        });
      }
      lower = lower.finish(instant(4).add(const Duration(hours: 1)));
      await store.insertSession(lower);
      await store.recordFinalization(lower.id);
      final inserted = history(
        await service.resolve('history-fingerprint', null, instant(10)),
      );
      equal(jsonObject(inserted['value'], 'value')['value'], '70');
      equal(inserted['sourceVersion'], before['sourceVersion']);
      check(jsonEncode(beforeFingerprint) != jsonEncode(fingerprint(inserted)));
      final eligible = fingerprint(inserted)['sources']! as List<Object?>;
      check(
        eligible.any(
          (s) => jsonObject(s, 'source')['sessionId'] == 'nonwinner',
        ),
      );
      check(
        !eligible.any((s) => jsonObject(s, 'source')['sessionId'] == 's-two'),
      );
      final current = await StoredTrainingService(store).session('nonwinner');
      final set = current.sets.firstWhere((s) => s.slotId == 'bench-heavy');
      await StoredTrainingService(store).edit(
        current.id,
        current.contentVersion,
        (session) => const TrainingService().complete(session, set.id, {
          'mass': Quantity('65', 'kg'),
          'reps': Quantity('8', 'rep'),
        }),
      );
      final edited = history(
        await service.resolve('history-fingerprint', null, instant(10)),
      );
      equal(jsonObject(edited['value'], 'value')['value'], '70');
      check(
        jsonEncode(fingerprint(inserted)) != jsonEncode(fingerprint(edited)),
      );
      final repeat = history(
        await service.resolve('history-fingerprint', null, instant(10)),
      );
      jsonEqual(fingerprint(edited), fingerprint(repeat));
    }),
  );

  test(
    'unresolved history sources still provide an empty fingerprint',
    () => _stored((store) async {
      final service = DerivedTargetGraphService(store);
      await service.publish(
        DerivedTargetGraph.fromJson(
          _graph(
            id: 'history-empty',
            bindings: {
              'bench_max': {
                'kind': 'history',
                'metric': 'mass',
                'templateId': 'not-present',
              },
              'training_mass': {
                'kind': 'manual',
                'version': 1,
                'value': {'value': '1', 'unit': 'kg'},
              },
            },
          ),
        ),
        0,
      );
      final result = await service.resolve('history-empty', null, instant(10));
      final source = jsonObject(
        jsonObject(result['bindings'], 'bindings')['bench_max'],
        'source',
      );
      equal(source['status'], 'unresolved');
      final fp = jsonObject(
        jsonObject(source['provenance'], 'provenance')['sourceFingerprint'],
        'fingerprint',
      );
      equal((fp['sources']! as List<Object?>).length, 0);
    }),
  );

  test(
    'graph status detects changed body mass and non-winning history in the captured revision and scope',
    () => _stored((store) async {
      final service = DerivedTargetGraphService(store);
      final graph = DerivedTargetGraph.fromJson(_graph(id: 'status-graph'));
      await service.publish(graph, 0);
      final snapshot = await service.resolve('status-graph', null, instant(10));
      final original = jsonEncode(snapshot);
      final same = await service.status(snapshot);
      equal(same['changed'], false);
      equal(same['policy'], 'bodytmi-derived-target-graph-status/1');
      final massService = StoredBodyMassService(store);
      await massService.save({
        'id': 'new-mass',
        'context': 'clothed-training',
        'observedAt': '2026-10-02T08:00:00Z',
        'mass': {'value': '85', 'unit': 'kg'},
      }, 0);
      final workoutRevision = revision();
      var session = start(id: 'new-history', day: 4, from: workoutRevision);
      for (final set in session.sets) {
        session = const TrainingService().complete(session, set.id, {
          'mass': Quantity('60', 'kg'),
          'reps': Quantity('8', 'rep'),
        });
      }
      session = session.finish(instant(4).add(const Duration(hours: 1)));
      await store.insertSession(session);
      await store.recordFinalization(session.id);
      // A later graph revision must not change the captured revision being checked.
      await service.publish(graph, 1);
      final changed = await service.status(snapshot);
      equal(changed['changed'], true);
      final sources = jsonObject(changed['sources'], 'sources');
      equal(jsonObject(sources['bench_max'], 'history')['changed'], true);
      equal(jsonObject(sources['training_mass'], 'mass')['changed'], true);
      equal(
        _nodeValue({
          'resolution': changed['currentResolution'],
        }, 'max')['value'],
        '70',
      );
      equal(jsonEncode(snapshot), original);
    }),
  );

  test(
    'graph status rejects altered arithmetic, revision, scope and binding policy',
    () => _stored((store) async {
      final service = DerivedTargetGraphService(store);
      await service.publish(
        DerivedTargetGraph.fromJson(_graph(id: 'status-invalid')),
        0,
      );
      final snapshot = await service.resolve(
        'status-invalid',
        null,
        instant(10),
      );
      Future<void> reject(Map<String, Object?> altered) async => expectLater(
        service.status(altered),
        throwsA(isA<BodyTmiException>()),
      );
      final output = copyJson(snapshot);
      final nodes =
          jsonObject(output['resolution'], 'resolution')['nodes']!
              as List<Object?>;
      jsonObject(nodes.last, 'node')['value'] = {'value': '999', 'unit': 'kg'};
      await reject(output);
      final graph = copyJson(snapshot);
      jsonObject(graph['graph'], 'graph')['nodes'] = <Object?>[];
      await reject(graph);
      final scope = copyJson(snapshot);
      jsonObject(scope['historyScope'], 'scope')['runId'] = 'other';
      await reject(scope);
      final policy = copyJson(snapshot);
      jsonObject(
        jsonObject(policy['bindings'], 'bindings')['bench_max'],
        'source',
      )['direction'] = 'lowest';
      await reject(policy);
      final missing = copyJson(snapshot);
      jsonObject(missing['bindings'], 'bindings').remove('bench_max');
      await reject(missing);
    }),
  );

  test(
    'stored graph publication checks expected revisions and resolves stored sources with provenance',
    () => _stored((store) async {
      final service = DerivedTargetGraphService(store);
      final published = await service.publish(
        DerivedTargetGraph.fromJson(_graph()),
        0,
      );
      equal(published.number, 1);
      await expectLater(
        service.publish(DerivedTargetGraph.fromJson(_graph()), 0),
        throwsA(isA<BodyTmiException>()),
      );
      equal((await service.revision('bench-percentages')).number, 1);
      equal(
        (await service.revision('bench-percentages', 1)).graph.id,
        'bench-percentages',
      );
      await expectLater(
        service.revision('missing'),
        throwsA(isA<BodyTmiException>()),
      );
      equal(
        (await service.list())
            .map((g) => '${g.graph.id}:${g.number}')
            .join(','),
        'bench-percentages:1',
      );
      final resolved = await service.resolve(
        'bench-percentages',
        null,
        DateTime.utc(2026, 10, 30),
      );
      equal(resolved['policy'], 'bodytmi-derived-target-graph-resolution/3');
      final bindings = jsonObject(resolved['bindings'], 'bindings');
      final history = jsonObject(bindings['bench_max'], 'history');
      equal(history['status'], 'resolved');
      // Session content version: start (1) + four completions + finish.
      equal(history['sourceVersion'], 6);
      // The interrupted 75 kg set is excluded; the 70 kg confirmed set wins.
      equal(jsonObject(history['value'], 'value')['value'], '70');
      equal(
        jsonObject(history['provenance'], 'provenance')['session'],
        's-one',
      );
      final mass = jsonObject(bindings['training_mass'], 'mass');
      // The command asOf covers the stored 2026-10-01 observation.
      equal(mass['status'], 'resolved');
      equal(jsonObject(mass['value'], 'value')['value'], '80');
      equal(
        jsonObject(mass['provenance'], 'provenance')['context'],
        'clothed-training',
      );
    }),
  );

  test(
    'graph resolution derives downstream scales from resolved stored sources',
    () => _stored((store) async {
      final service = DerivedTargetGraphService(store);
      final published = await service.publish(
        DerivedTargetGraph.fromJson(
          _graph(
            bindings: {
              'bench_max': {
                'kind': 'history',
                'metric': 'mass',
                'slotId': 'bench-heavy',
              },
              'training_mass': {
                'kind': 'manual',
                'version': 1,
                'value': {'value': '80', 'unit': 'kg'},
              },
            },
          ),
        ),
        0,
      );
      final resolved = await service.resolve(
        published.graph.id,
        null,
        DateTime.utc(2026, 10, 30),
      );
      // 80% of the 70 kg confirmed maximum.
      equal(_nodeValue(resolved, 'working')['value'], '56');
      equal(
        jsonObject(
          jsonObject(resolved['bindings'], 'bindings')['training_mass'],
          'mass',
        )['sourceVersion'],
        1,
      );
    }),
  );

  test(
    'history bindings honor direction, scope, time bounds and interruption',
    () => _stored((store) async {
      final service = DerivedTargetGraphService(store);
      Map<String, Object?> graph(String id, Map<String, Object?> binding) =>
          _graph(
            id: id,
            bindings: {
              'bench_max': binding,
              'training_mass': {
                'kind': 'manual',
                'version': 1,
                'value': {'value': '1', 'unit': 'kg'},
              },
            },
          );

      final highest = await service.publish(
        DerivedTargetGraph.fromJson(
          graph('g-high', {
            'kind': 'history',
            'metric': 'mass',
            'direction': 'highest',
            'slotId': 'bench-heavy',
          }),
        ),
        0,
      );
      final resolved = await service.resolve(
        highest.graph.id,
        null,
        DateTime.utc(2026, 10, 30),
      );
      // The interrupted 75 kg set in s-two is excluded; 70 kg wins.
      equal(_nodeValue(resolved, 'max')['value'], '70');
      equal(
        jsonObject(
          jsonObject(
            jsonObject(resolved['bindings'], 'bindings')['bench_max'],
            'binding',
          )['provenance'],
          'provenance',
        )['session'],
        's-one',
      );

      final lowest = await service.publish(
        DerivedTargetGraph.fromJson(
          graph('g-low', {
            'kind': 'history',
            'metric': 'mass',
            'direction': 'lowest',
            'slotId': 'bench-heavy',
          }),
        ),
        0,
      );
      final lowerResolved = await service.resolve(
        lowest.graph.id,
        null,
        DateTime.utc(2026, 10, 30),
      );
      equal(_nodeValue(lowerResolved, 'max')['value'], '70');

      // Scope to a template with no sessions: unresolved, not zero.
      final scoped = await service.publish(
        DerivedTargetGraph.fromJson(
          graph('g-scoped', {
            'kind': 'history',
            'metric': 'mass',
            'templateId': 'absent-template',
          }),
        ),
        0,
      );
      final scopedResolved = await service.resolve(
        scoped.graph.id,
        null,
        DateTime.utc(2026, 10, 30),
      );
      equal(
        jsonObject(
          jsonObject(scopedResolved['bindings'], 'bindings')['bench_max'],
          'binding',
        )['status'],
        'unresolved',
      );

      // Until excludes s-two (day 3); s-one alone remains.
      final bounded = await service.publish(
        DerivedTargetGraph.fromJson(
          graph('g-bounded', {
            'kind': 'history',
            'metric': 'mass',
            'until': '2026-10-03T00:00:00Z',
          }),
        ),
        0,
      );
      final boundedResolved = await service.resolve(
        bounded.graph.id,
        null,
        DateTime.utc(2026, 10, 30),
      );
      equal(
        jsonObject(
          jsonObject(
            jsonObject(boundedResolved['bindings'], 'bindings')['bench_max'],
            'binding',
          )['provenance'],
          'provenance',
        )['session'],
        's-one',
      );
    }),
  );

  test(
    'body-mass bindings use the stored resolver with explicit time and context isolation',
    () => _stored((store) async {
      final service = DerivedTargetGraphService(store);
      final published = await service.publish(
        DerivedTargetGraph.fromJson(
          _graph(
            id: 'g-mass',
            bindings: {
              'bench_max': {
                'kind': 'manual',
                'version': 1,
                'value': {'value': '1', 'unit': 'kg'},
              },
              'training_mass': {
                'kind': 'bodyMass',
                'context': 'clothed-training',
                'asOf': '2026-10-01T12:00:00Z',
              },
            },
          ),
        ),
        0,
      );
      final resolved = await service.resolve(
        published.graph.id,
        null,
        DateTime.utc(2026, 10, 30),
      );
      final mass = jsonObject(
        jsonObject(resolved['bindings'], 'bindings')['training_mass'],
        'mass',
      );
      equal(mass['status'], 'resolved');
      equal(jsonObject(mass['value'], 'value')['value'], '80');
      // The binding asOf outranks the command asOf.
      equal(
        jsonObject(mass['provenance'], 'provenance')['asOf'],
        '2026-10-01T12:00:00.000Z',
      );
      // A graph cannot use a fixed future body-mass cutoff in an earlier query.
      await expectLater(
        service.resolve(published.graph.id, null, DateTime.utc(2026, 9, 30)),
        throwsA(isA<BodyTmiException>()),
      );
      // A context with no observations stays unresolved, not zero.
      final empty = await service.publish(
        DerivedTargetGraph.fromJson(
          _graph(
            id: 'g-mass-empty',
            bindings: {
              'bench_max': {
                'kind': 'manual',
                'version': 1,
                'value': {'value': '1', 'unit': 'kg'},
              },
              'training_mass': {
                'kind': 'bodyMass',
                'context': 'health',
                'asOf': '2026-10-01T12:00:00Z',
              },
            },
          ),
        ),
        0,
      );
      final emptyResolved = await service.resolve(
        empty.graph.id,
        null,
        DateTime.utc(2026, 10, 30),
      );
      equal(
        jsonObject(
          jsonObject(emptyResolved['bindings'], 'bindings')['training_mass'],
          'binding',
        )['status'],
        'unresolved',
      );
      // Body-mass resolution requires an explicit asOf somewhere.
      final noTime = await service.publish(
        DerivedTargetGraph.fromJson(
          _graph(
            id: 'g-mass-notime',
            bindings: {
              'bench_max': {
                'kind': 'manual',
                'version': 1,
                'value': {'value': '1', 'unit': 'kg'},
              },
              'training_mass': {'kind': 'bodyMass', 'context': 'health'},
            },
          ),
        ),
        0,
      );
      await expectLater(
        service.resolve(noTime.graph.id),
        throwsA(isA<BodyTmiException>()),
      );
    }),
  );

  test(
    'graph portability round-trips through logical v30 and native backups, and old labels reject graphs',
    () => _stored((store) async {
      final dbPath = store.path;
      await DerivedTargetGraphService(
        store,
      ).publish(DerivedTargetGraph.fromJson(_graph()), 0);
      final archive = await store.archive();
      equal(archive.summary['graphs'], 1);
      final dir = await Directory.systemTemp.createTemp('bodytmi-graph-io-');
      try {
        final path = '${dir.path}/export.json';
        await LogicalArchiveFiles.export(archive, path);
        final envelope = jsonObject(
          jsonDecode(await File(path).readAsString()),
          'envelope',
        );
        equal(envelope['format'], 'bodytmi-logical-export/54');
        equal(
          (jsonObject(envelope['data'], 'data')['graphs']! as List<Object?>)
              .length,
          1,
        );
        final prepared = await LogicalArchiveFiles.prepare(path);
        try {
          equal(prepared.archive.graphs.length, 1);
          await store.restore(
            prepared.backup,
            recoveryDestination: '${dir.path}/recovery',
            confirm: true,
          );
        } finally {
          await prepared.close();
        }
        await store.close();
        final reopened = await TrainingStore.open(dbPath);
        try {
          equal(
            (await DerivedTargetGraphService(
              reopened,
            ).revision('bench-percentages')).number,
            1,
          );
        } finally {
          await reopened.close();
        }
        // A v26 label cannot carry the graphs section.
        final doc = copyJson(envelope);
        doc['format'] = 'bodytmi-logical-export/26';
        doc['sha256'] = sha256
            .convert(
              utf8.encode(
                canonicalJson({
                  for (final entry in doc.entries)
                    if (entry.key != 'sha256') entry.key: entry.value,
                }),
              ),
            )
            .toString();
        final bad = '${dir.path}/old-label.json';
        await File(bad).writeAsString(jsonEncode(doc));
        await expectLater(
          LogicalArchiveFiles.prepare(bad),
          throwsA(isA<BodyTmiException>()),
        );
        final backup = '${dir.path}/backup';
        await NativeBackup.create(dbPath, backup);
        final preparedBackup = await NativeBackup.prepare(backup);
        try {
          equal(preparedBackup.manifest['databaseSchemaVersion'], 54);
        } finally {
          await preparedBackup.close();
        }
      } finally {
        await dir.delete(recursive: true);
      }
    }),
  );
}
