import 'dart:convert';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'cli_test.dart';
import 'support.dart';

Map<String, Object?> _measure(Map<String, Object?> extra) => {
  'id': 'resting-hr',
  'name': 'Resting heart rate',
  'kind': 'quantity',
  'dimension': 'frequency',
  'unit': 'bpm',
  ...extra,
};

/// Measures declare what is recorded and how it may be summarised and
/// resolved; the body catalog ships as built-in measures.
void measureTests() {
  test('measure definitions validate kinds, summaries and policies', () {
    final hr = MeasureDefinition.fromJson(_measure({}));
    jsonEqual(hr.summaries.toList()..sort(), ['count', 'last']);
    equal(hr.resolution.policy, 'latest');
    jsonEqual(MeasureDefinition.fromJson(hr.toJson()).toJson(), hr.toJson());
    // The preferred unit must match the dimension.
    rejects(() => MeasureDefinition.fromJson(_measure({'unit': 'kg'})));
    // Summing needs a declaration a kind permits.
    MeasureDefinition.fromJson(
      _measure({
        'summaries': ['mean', 'sum'],
      }),
    );
    rejects(
      () => MeasureDefinition.fromJson({
        'id': 'mood',
        'name': 'Mood',
        'kind': 'rating',
        'scale': {'minimum': 1, 'maximum': 5},
        'summaries': ['sum'],
      }),
    );
    final mood = MeasureDefinition.fromJson({
      'id': 'mood',
      'name': 'Mood',
      'kind': 'rating',
      'scale': {
        'minimum': 1,
        'maximum': 5,
        'anchors': {'1': 'Very low', '5': 'Very good'},
      },
      'summaries': ['mean', 'last'],
    });
    equal(mood.scale!.anchors[5], 'Very good');
    rejects(
      () => MeasureDefinition.fromJson({
        'id': 'mood',
        'name': 'Mood',
        'kind': 'rating',
        'scale': {
          'minimum': 1,
          'maximum': 5,
          'anchors': {'9': 'Off scale'},
        },
      }),
    );
    rejects(
      () => MeasureDefinition.fromJson({
        'id': 'feel',
        'name': 'Feel',
        'kind': 'category',
      }),
    );
    // Only quantities extrapolate; trend is for mass and ratio.
    rejects(
      () => MeasureDefinition.fromJson(
        _measure({
          'resolution': {'policy': 'trend'},
        }),
      ),
    );
    final extrapolated = MeasureDefinition.fromJson(
      _measure({
        'resolution': {'policy': 'extrapolated', 'minPoints': 6},
      }),
    );
    equal(extrapolated.resolution.windowDays, 90);
    equal(extrapolated.resolution.minPoints, 6);
    equal(extrapolated.resolution.maxAheadDays, 30);
    rejects(
      () => MeasureDefinition.fromJson(
        _measure({
          'resolution': {'policy': 'latest', 'windowDays': 30},
        }),
      ),
    );
    rejects(
      () => MeasureDefinition.fromJson(
        _measure({
          'resolution': {
            'policy': 'extrapolated',
            'windowDays': 14,
            'minSpanDays': 28,
          },
        }),
      ),
    );
  });

  test('the built-in body catalog', () {
    final ids = [for (final m in builtInMeasures) m.id];
    jsonEqual(ids, [
      'body-mass',
      'body-fat',
      'height',
      'circumference',
      'skinfold',
      'steps',
    ]);
    MeasureDefinition byId(String id) =>
        builtInMeasures.firstWhere((m) => m.id == id);
    equal(byId('body-mass').resolution.policy, 'trend');
    equal(byId('body-mass').resolution.staleAfterDays, 7);
    equal(byId('circumference').resolution.staleAfterDays, 60);
    equal(byId('height').resolution.staleAfterDays, null);
    check(byId('circumference').attributes['site']!.contains('neck'));
    check(byId('body-fat').attributes['method']!.contains('dexa'));
    check(byId('steps').summaries.contains('sum'));
    equal(byId('steps').dimension, Dimension.steps);
    check(!byId('body-mass').summaries.contains('sum'), 'mass never sums');
  });

  test('CLI measure validate and builtins', () async {
    final valid = await invoke([
      'measure',
      'validate',
    ], jsonEncode({'schemaVersion': 1, 'measure': _measure({})}));
    equal(valid.code, 0);
    final invalid = await invoke(
      ['measure', 'validate'],
      jsonEncode({
        'schemaVersion': 1,
        'measure': _measure({'kind': 'mystery'}),
      }),
    );
    equal(invalid.code, 2);
    final builtins = await invoke([
      'measure',
      'builtins',
    ], jsonEncode({'schemaVersion': 1}));
    equal(builtins.code, 0);
    final data = jsonObject(
      jsonObject(jsonDecode(builtins.output), 'r')['data'],
      'd',
    );
    equal(jsonList(data, 'measures').length, builtInMeasures.length);
  });
}
