import 'dart:convert';

import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'support.dart';

List<Object?> _graph() => [
  {
    'id': 'working',
    'kind': 'scale',
    'unit': 'kg',
    'input': 'max',
    'factor': '0.80',
  },
  {'id': 'max', 'kind': 'source', 'unit': 'kg', 'sourceId': 'squat'},
  {
    'id': 'warmup',
    'kind': 'scale',
    'unit': 'lb',
    'input': 'working',
    'factor': '0.5',
  },
  {'id': 'other', 'kind': 'source', 'unit': 'kg', 'sourceId': 'bench'},
];
Map<String, Object?> _bindings({String value = '200', int version = 3}) => {
  'squat': {
    'version': version,
    'value': {'value': value, 'unit': 'lb'},
  },
};
Map<String, Object?> _nodes(Object? resolution, String id) =>
    (jsonObject(resolution, 'resolution')['nodes']! as List<Object?>)
        .map((e) => jsonObject(e, 'node'))
        .singleWhere((e) => e['id'] == id);

void derivedTargetSnapshotTests() {
  const service = DerivedTargetSnapshot();
  test(
    'derived target capture separates authored graph from versioned source bindings and freezes exact results',
    () {
      final graph = _graph();
      final bindings = _bindings();
      final snapshot = service.capture(graph, bindings);
      equal(snapshot['policy'], 'bodytmi-derived-target-snapshot/1');
      final sources = jsonObject(snapshot['bindings'], 'bindings');
      equal(sources['bench'], null);
      equal(
        jsonObject(
          jsonObject(sources['squat'], 'source')['value'],
          'value',
        )['value'],
        '90.718474',
      );
      equal(
        jsonObject(
          _nodes(snapshot['resolution'], 'working')['value'],
          'value',
        )['value'],
        '72.5747792',
      );
      equal(_nodes(snapshot['resolution'], 'other')['status'], 'unresolved');
      jsonEqual(snapshot, service.capture(graph.reversed.toList(), bindings));
      bindings['squat'] = null;
      equal(
        jsonObject(
          jsonObject(sources['squat'], 'source')['value'],
          'value',
        )['value'],
        '90.718474',
      );
    },
  );
  test(
    'derived target status identifies missing, inserted, changed and unchanged sources without rewriting captured output',
    () {
      final snapshot = service.capture(_graph(), _bindings());
      final same = service.status(snapshot, _bindings());
      equal(same['changed'], false);
      final inserted = {
        ..._bindings(),
        'bench': {
          'version': 1,
          'value': {'value': '80', 'unit': 'kg'},
        },
      };
      final status = service.status(snapshot, inserted);
      equal(status['changed'], true);
      final sources = jsonObject(status['sources'], 'sources');
      equal(jsonObject(sources['bench'], 'source')['changed'], true);
      equal(jsonObject(sources['squat'], 'source')['changed'], false);
      equal(_nodes(status['captured'], 'other')['status'], 'unresolved');
      equal(_nodes(status['current'], 'other')['status'], 'resolved');
      equal(service.status(snapshot, _bindings(version: 4))['changed'], true);
      equal(service.status(snapshot, _bindings(value: '201'))['changed'], true);
      equal(service.status(snapshot, <String, Object?>{})['changed'], true);
    },
  );
  test(
    'derived target snapshots reject forged outputs and malformed graph or bindings',
    () {
      final snapshot = service.capture(_graph(), _bindings());
      final forged = jsonDecode(jsonEncode(snapshot)) as Map<String, Object?>;
      final node = _nodes(forged['resolution'], 'working');
      node['value'] = {'value': '1', 'unit': 'kg'};
      rejects(() => service.status(forged, _bindings()));
      rejects(() => service.capture(_graph(), {'unrelated': null}));
      rejects(
        () => service.capture(_graph(), {
          'squat': {
            'version': 0,
            'value': {'value': '1', 'unit': 'kg'},
          },
        }),
      );
      rejects(
        () => service.capture(_graph(), {
          'squat': {
            'version': 1,
            'value': {'value': '1', 'unit': 's'},
          },
        }),
      );
      rejects(
        () => service.capture([
          ..._graph(),
          {'id': 'bad', 'kind': 'source', 'unit': 's', 'sourceId': 'squat'},
        ], <String, Object?>{}),
      );
      rejects(
        () => service.capture([
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
        ], <String, Object?>{}),
      );
      rejects(
        () => service.capture([
          {
            'id': 'a',
            'kind': 'source',
            'unit': 'kg',
            'sourceId': 'x',
            'value': null,
          },
        ], <String, Object?>{}),
      );
    },
  );
  test('derived target capture and status commands match pure operations', () {
    final capture = const Commands().execute('target capture', {
      'schemaVersion': 1,
      'graph': _graph(),
      'bindings': _bindings(),
    });
    final snapshot = jsonObject(capture['data'], 'snapshot');
    jsonEqual(snapshot, service.capture(_graph(), _bindings()));
    final status = const Commands().execute('target status', {
      'schemaVersion': 1,
      'snapshot': snapshot,
      'bindings': _bindings(version: 4),
    });
    jsonEqual(status['data'], service.status(snapshot, _bindings(version: 4)));
  });
}
