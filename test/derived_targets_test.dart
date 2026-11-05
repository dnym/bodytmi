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
  test('round nodes retain native ticks and explicit rounding decisions', () {
    final scale = {
      'id': 'machine',
      'unit': 'kg',
      'ticks': [
        {
          'id': 'light',
          'value': '20',
          'labels': {'lb': '44'},
        },
        {
          'id': 'middle',
          'value': '22.5',
          'labels': {'lb': '50'},
        },
        {
          'id': 'heavy',
          'value': '25',
          'labels': {'lb': '55'},
        },
      ],
    };
    Map<String, Object?> round(String id, String policy) => {
      'id': id,
      'kind': 'round',
      'unit': 'kg',
      'input': 'requested',
      'scale': scale,
      'rounding': policy,
    };
    final nodes = [
      _source('max', 'kg', _q('100', 'kg'), version: 2),
      _scale('requested', 'kg', 'max', '0.2375'),
      round('nearest', 'nearest'),
      round('up', 'atLeast'),
      round('down', 'atMost'),
    ];
    final result = const DerivedTargets().resolve(nodes);
    equal(
      jsonObject(_node(result, 'nearest')['value'], 'value')['value'],
      '22.5',
    );
    equal(jsonObject(_node(result, 'up')['value'], 'value')['value'], '25');
    equal(jsonObject(_node(result, 'down')['value'], 'value')['value'], '22.5');
    final selection = jsonObject(
      _node(result, 'nearest')['selection'],
      'selection',
    );
    equal(selection['scaleId'], 'machine');
    equal(jsonObject(selection['tick'], 'tick')['id'], 'middle');
    equal(
      jsonObject(
        jsonObject(selection['tick'], 'tick')['labels'],
        'labels',
      )['lb'],
      '50',
    );
    equal(selection['exact'], false);
    jsonEqual(result, const DerivedTargets().resolve(nodes.reversed.toList()));
    final snapshot = const DerivedTargetSnapshot().capture(
      [
        {
          'id': 'requested',
          'kind': 'source',
          'unit': 'kg',
          'sourceId': 'request',
        },
        round('nearest', 'nearest'),
      ],
      {
        'request': {'version': 1, 'value': _q('23.75', 'kg')},
      },
    );
    final status = const DerivedTargetSnapshot().status(snapshot, {
      'request': {'version': 2, 'value': _q('24', 'kg')},
    });
    equal(status['changed'], true);
    final current = jsonObject(status['current'], 'current');
    equal(
      jsonObject(_node(current, 'nearest')['value'], 'value')['value'],
      '25',
    );
  });
  test(
    'round nodes propagate missing and unavailable settings and validate scales',
    () {
      Map<String, Object?> round(
        String input,
        String policy,
        Object scale, [
        String unit = 'kg',
      ]) => {
        'id': 'result',
        'kind': 'round',
        'unit': unit,
        'input': input,
        'scale': scale,
        'rounding': policy,
      };
      final scale = {
        'id': 'fixed',
        'unit': 'lb',
        'range': {'start': '10', 'step': '5', 'count': 3},
      };
      final missing = const DerivedTargets().resolve([
        _source('a', 'kg', null),
        round('a', 'nearest', scale),
      ]);
      equal(_node(missing, 'result')['status'], 'unresolved');
      equal(_node(missing, 'result')['selection'], null);
      final unavailable = const DerivedTargets().resolve([
        _source('a', 'lb', _q('25', 'lb'), version: 1),
        round('a', 'atLeast', scale),
      ]);
      equal(_node(unavailable, 'result')['status'], 'unresolved');
      equal(
        jsonObject(
          _node(unavailable, 'result')['selection'],
          'selection',
        )['outcome'],
        'blocked',
      );
      final downward = const DerivedTargets().resolve([
        _source('a', 'lb', _q('25', 'lb'), version: 1),
        round('a', 'atMost', scale),
      ]);
      equal(
        jsonObject(
          jsonObject(
            _node(downward, 'result')['selection'],
            'selection',
          )['tick'],
          'tick',
        )['id'],
        'tick-2',
      );
      rejects(
        () => const DerivedTargets().resolve([
          _source('a', 's', null),
          round('a', 'nearest', scale),
        ]),
      );
      rejects(
        () => const DerivedTargets().resolve([
          _source('a', 'kg', null),
          round('a', 'nearest', scale, 's'),
        ]),
      );
      rejects(
        () => const DerivedTargets().resolve([
          _source('a', 'kg', null),
          round('a', 'invalid', scale),
        ]),
      );
      rejects(
        () =>
            const DerivedTargets().resolve([round('result', 'nearest', scale)]),
      );
      final huge = [
        for (var i = 0; i < 11; i++)
          {
            'id': 'r$i',
            'kind': 'round',
            'unit': 'kg',
            'input': 'a',
            'scale': {
              'id': 's$i',
              'unit': 'kg',
              'range': {'start': '0', 'step': '1', 'count': 1000},
            },
            'rounding': 'nearest',
          },
      ];
      rejects(
        () =>
            const DerivedTargets().resolve([_source('a', 'kg', null), ...huge]),
      );
    },
  );
  test(
    'binary graph arithmetic uses exact quantities and explicit dependencies',
    () {
      final nodes = [
        _source('maximum', 'rep', _q('8', 'rep'), version: 4),
        _source('margin', 'rep', _q('1', 'rep'), version: 2),
        {
          'id': 'goal',
          'kind': 'subtract',
          'unit': 'rep',
          'left': 'maximum',
          'right': 'margin',
        },
        _scale('volume', 'rep', 'goal', '3'),
        _source('pounds', 'lb', _q('100', 'lb'), version: 3),
        _source('plates', 'kg', _q('2.5', 'kg'), version: 1),
        {
          'id': 'load',
          'kind': 'add',
          'unit': 'kg',
          'left': 'pounds',
          'right': 'plates',
        },
      ];
      final result = const DerivedTargets().resolve(nodes);
      equal(
        jsonObject(_node(result, 'goal')['value'], 'quantity')['value'],
        '7',
      );
      equal(
        jsonObject(_node(result, 'volume')['value'], 'quantity')['value'],
        '21',
      );
      equal(
        jsonObject(_node(result, 'load')['value'], 'quantity')['value'],
        '47.859237',
      );
      jsonEqual(
        result,
        const DerivedTargets().resolve(nodes.reversed.toList()),
      );
      final snapshot = const DerivedTargetSnapshot().capture(
        [
          {'id': 'max', 'kind': 'source', 'unit': 'rep', 'sourceId': 'record'},
          {
            'id': 'margin',
            'kind': 'source',
            'unit': 'rep',
            'sourceId': 'margin',
          },
          {
            'id': 'goal',
            'kind': 'subtract',
            'unit': 'rep',
            'left': 'max',
            'right': 'margin',
          },
        ],
        {
          'record': {'version': 4, 'value': _q('8', 'rep')},
          'margin': {'version': 2, 'value': _q('1', 'rep')},
        },
      );
      final status = const DerivedTargetSnapshot().status(snapshot, {
        'record': {'version': 5, 'value': _q('9', 'rep')},
        'margin': {'version': 2, 'value': _q('1', 'rep')},
      });
      equal(status['changed'], true);
      equal(
        jsonObject(
          _node(jsonObject(status['current'], 'current'), 'goal')['value'],
          'value',
        )['value'],
        '8',
      );
    },
  );
  test(
    'binary graph arithmetic validates both branches and propagates missing values',
    () {
      Map<String, Object?> binary(
        String kind,
        String left,
        String right, [
        String unit = 'rep',
      ]) => {
        'id': 'result',
        'kind': kind,
        'unit': unit,
        'left': left,
        'right': right,
      };
      final a = _source('a', 'rep', _q('1', 'rep'), version: 1);
      final b = _source('b', 'rep', _q('2', 'rep'), version: 1);
      rejects(
        () => const DerivedTargets().resolve([
          a,
          b,
          binary('subtract', 'a', 'b'),
        ]),
      );
      rejects(
        () =>
            const DerivedTargets().resolve([a, binary('add', 'a', 'missing')]),
      );
      rejects(
        () => const DerivedTargets().resolve([a, binary('add', 'a', 'result')]),
      );
      rejects(
        () => const DerivedTargets().resolve([
          a,
          _source('b', 'kg', null),
          binary('add', 'a', 'b'),
        ]),
      );
      final unresolved = const DerivedTargets().resolve([
        a,
        _source('b', 'rep', null),
        binary('subtract', 'a', 'b'),
      ]);
      equal(_node(unresolved, 'result')['status'], 'unresolved');
      equal(_node(unresolved, 'result')['value'], null);
      final zero = const DerivedTargets().resolve([
        a,
        binary('subtract', 'a', 'a'),
      ]);
      equal(jsonObject(_node(zero, 'result')['value'], 'value')['value'], '0');
    },
  );
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
