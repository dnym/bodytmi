import 'dart:convert';

import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_core/bodytmi_core.dart';

import 'support.dart';

Map<String, Object?> _source(
  String id,
  String unit,
  Object? value, {
  int? version,
}) => {
  'id': id,
  'kind': 'source',
  'unit': unit,
  'sourceId': '${id}_track',
  'sourceVersion': version,
  'value': value,
};
Map<String, Object?> _scale(
  String id,
  String unit,
  String input,
  String factor,
) => {
  'id': id,
  'kind': 'scale',
  'unit': unit,
  'input': input,
  'factor': factor,
};
Map<String, Object?> _q(String value, String unit) => {
  'value': value,
  'unit': unit,
};
List<Object?> _nodes(Map<String, Object?> result) =>
    result['nodes']! as List<Object?>;
Map<String, Object?> _node(Map<String, Object?> result, String id) => _nodes(
  result,
).map((v) => jsonObject(v, 'node')).singleWhere((v) => v['id'] == id);

void derivedTargetsTests() {
  test(
    'derived targets resolve explicit dependency graphs deterministically with exact units and versions',
    () {
      final nodes = [
        _scale('warmup', 'kg', 'working', '0.5'),
        _scale('working', 'lb', 'trainingMax', '0.75'),
        _source('trainingMax', 'kg', _q('200', 'lb'), version: 7),
      ];
      final result = const DerivedTargets().resolve(nodes);
      equal(result['policy'], 'bodytmi-derived-targets/1');
      jsonEqual(
        _nodes(result).map((v) => (v as Map<String, Object?>)['id']).toList(),
        ['trainingMax', 'working', 'warmup'],
      );
      equal(
        jsonObject(_node(result, 'working')['value'], 'quantity')['value'],
        '68.0388555',
      );
      equal(
        jsonObject(_node(result, 'warmup')['value'], 'quantity')['value'],
        '34.01942775',
      );
      equal(_node(result, 'trainingMax')['sourceVersion'], 7);
      equal(
        jsonObject(
          jsonObject(_node(result, 'trainingMax')['value'], 'value')['entered'],
          'entered',
        )['unit'],
        'lb',
      );
      jsonEqual(
        result,
        const DerivedTargets().resolve(nodes.reversed.toList()),
      );
      final response = const Commands().execute('target resolve', {
        'schemaVersion': 1,
        'nodes': nodes,
      });
      jsonEqual(response['data'], result);
    },
  );
  test(
    'missing sources stay unresolved through all consumers without inventing zero',
    () {
      final result = const DerivedTargets().resolve([
        _source('max', 'kg', null),
        _scale('work', 'lb', 'max', '0.8'),
        _source('other', 'rep', _q('0', 'rep'), version: 1),
      ]);
      equal(_node(result, 'work')['status'], 'unresolved');
      equal(_node(result, 'work')['value'], null);
      equal(_node(result, 'other')['status'], 'resolved');
      equal(jsonObject(_node(result, 'other')['value'], 'value')['value'], '0');
    },
  );
  test(
    'derived targets reject missing references, cycles, invalid dimensions and fractional repetitions',
    () {
      void reject(List<Object?> nodes) =>
          rejects(() => const DerivedTargets().resolve(nodes));
      reject([_scale('a', 'kg', 'missing', '0.5')]);
      reject([_scale('a', 'kg', 'b', '1'), _scale('b', 'kg', 'a', '1')]);
      reject([_source('a', 'kg', null), _scale('b', 's', 'a', '1')]);
      reject([_source('a', 'kg', _q('1', 's'), version: 1)]);
      reject([
        _source('a', 'rep', _q('3', 'rep'), version: 1),
        _scale('b', 'rep', 'a', '0.5'),
      ]);
      reject([_source('a', 'kg', _q('1', 'kg'))]);
      reject([_source('a', 'kg', null, version: 1)]);
      reject([_scale('a', 'kg', 'a', '-1')]);
      reject([_source('a', 'kg', null), _source('a', 'kg', null)]);
      reject([]);
    },
  );
  test(
    'derived target command rejects undeclared fields and round trips JSON',
    () {
      final request =
          jsonDecode(
                '{"schemaVersion":1,"nodes":[{"id":"max","kind":"source","unit":"kg","sourceId":"manual","sourceVersion":2,"value":{"value":"100","unit":"kg"}},{"id":"work","kind":"scale","unit":"kg","input":"max","factor":"0.85"}]}',
              )
              as Map<String, Object?>;
      final result = const Commands().execute('target resolve', request);
      equal(
        jsonObject(
          _node(jsonObject(result['data'], 'data'), 'work')['value'],
          'value',
        )['value'],
        '85',
      );
      rejects(
        () => const Commands().execute('target resolve', {
          ...request,
          'extra': true,
        }),
      );
    },
  );
}
