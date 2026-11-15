import 'errors.dart';
import 'quantity.dart';

/// One nominal selector with native markings. Alternate labels do not define
/// independent loads or assert physical force/equivalence between equipment.
final class ScaleTick {
  ScaleTick._(this.id, this.quantity, this.labels);
  final String id;
  final Quantity quantity;
  final Map<String, String> labels;
  Map<String, Object?> toJson() => {
    'id': id,
    'value': quantity.enteredValue,
    if (labels.isNotEmpty) 'labels': labels,
  };
}

/// Compact author declaration of a finite native selector. Generated identities
/// are positional and deterministic, not inferred from a mutable inventory.
final class FixedScaleRange {
  FixedScaleRange._(this.start, this.step, this.count, this.idPrefix);
  factory FixedScaleRange.fromJson(Object? input, Unit unit) {
    final j = jsonObject(input, 'fixed scale range');
    checkKeys(j, {'start', 'step', 'count', 'idPrefix'});
    final start = requiredString(j, 'start');
    final step = requiredString(j, 'step');
    Quantity(start, unit.name);
    if (Quantity(step, unit.name).value.compareTo(Decimal.zero) <= 0)
      invalid('A fixed scale step must be positive.');
    final count = j['count'];
    if (count is! int || count < 1 || count > 1000)
      invalid('A fixed scale range needs 1 to 1000 positions.');
    final prefix = identifier({
      'id': j.containsKey('idPrefix') ? j['idPrefix'] : 'tick',
    }, 'id');
    if (prefix.length > 96)
      invalid('Fixed scale identity prefix exceeds 96 characters.');
    return FixedScaleRange._(start, step, count, prefix);
  }
  final String start, step, idPrefix;
  final int count;
  Map<String, Object?> toJson() => {
    'start': start,
    'step': step,
    'count': count,
    'idPrefix': idPrefix,
  };
}

final class NumericScale {
  NumericScale._(this.id, this.unit, this.ticks, this.range);

  /// A scale of derived positions, such as every weight a bar's declared
  /// plates can make. It is computed from frozen data, never authored or
  /// stored, so the 1000-tick authoring limit does not apply (100000 does).
  factory NumericScale.derived(String id, Unit unit, List<Quantity> ascending) {
    identifier({'id': id}, 'id');
    if (ascending.isEmpty || ascending.length > 100000)
      invalid('A derived scale needs 1 to 100000 positions.');
    final ticks = <ScaleTick>[];
    for (var i = 0; i < ascending.length; i++) {
      final quantity = ascending[i];
      if (quantity.dimension != unit.dimension)
        invalid('Derived scale positions must match the scale unit.');
      if (ticks.isNotEmpty && ticks.last.quantity.compareTo(quantity) >= 0)
        invalid('Derived scale positions must strictly increase.');
      ticks.add(ScaleTick._('$id-$i', quantity, const {}));
    }
    return NumericScale._(id, unit, List.unmodifiable(ticks), null);
  }
  factory NumericScale.fromJson(Object? input) {
    final j = jsonObject(input, 'numeric scale');
    checkKeys(j, {'id', 'unit', 'ticks', 'range'});
    if (j.containsKey('ticks') == j.containsKey('range'))
      invalid('A numeric scale needs exactly one of ticks or range.');
    final unit = Unit.parse(requiredString(j, 'unit'));
    final range = j.containsKey('range')
        ? FixedScaleRange.fromJson(j['range'], unit)
        : null;
    final List<Object?> inputTicks;
    if (range == null) {
      inputTicks = jsonList(j, 'ticks');
    } else {
      final start = Decimal.parse(range.start),
          step = Decimal.parse(range.step);
      inputTicks = [
        for (var i = 0; i < range.count; i++)
          {
            'id': '${range.idPrefix}-$i',
            'value': (start + step * Decimal.parse('$i')).toString(),
          },
      ];
    }
    if (inputTicks.isEmpty || inputTicks.length > 1000)
      invalid('A numeric scale needs 1 to 1000 ticks.');
    final ticks = <ScaleTick>[];
    final ids = <String>{};
    for (final inputTick in inputTicks) {
      final t = jsonObject(inputTick, 'scale tick');
      checkKeys(t, {'id', 'value', 'labels'});
      final id = identifier(t, 'id');
      if (!ids.add(id)) invalid('Scale tick identities must be unique.');
      final quantity = Quantity(requiredString(t, 'value'), unit.name);
      if (ticks.isNotEmpty && ticks.last.quantity.compareTo(quantity) >= 0)
        invalid('Scale tick values must be strictly increasing.');
      final labels = jsonObject(
        t.containsKey('labels') ? t['labels'] : <String, Object?>{},
        'tick labels',
      );
      for (final entry in labels.entries) {
        if (Unit.parse(entry.key).dimension != unit.dimension ||
            entry.value is! String ||
            (entry.value as String).trim().isEmpty ||
            (entry.value as String).length > 100)
          invalid('Tick labels need compatible units and 1 to 100 characters.');
      }
      ticks.add(
        ScaleTick._(
          id,
          quantity,
          Map.unmodifiable(labels.cast<String, String>()),
        ),
      );
    }
    return NumericScale._(
      identifier(j, 'id'),
      unit,
      List.unmodifiable(ticks),
      range,
    );
  }
  final String id;
  final Unit unit;
  final List<ScaleTick> ticks;
  final FixedScaleRange? range;
  Map<String, Object?> toJson() => {
    'id': id,
    'unit': unit.name,
    if (range == null) 'ticks': [for (final tick in ticks) tick.toJson()],
    if (range != null) 'range': range!.toJson(),
  };

  static String roundingPolicy(Object? input) {
    if (input is! String || !{'nearest', 'atMost', 'atLeast'}.contains(input))
      invalid('Rounding must be nearest, atMost or atLeast.');
    return input;
  }

  /// Binary lookup in the native selector's ordered canonical values. For a
  /// directional request, exclude the current value before rounding so nearest
  /// cannot repeatedly resolve to a setting that makes no progress.
  ScaleResolution resolve(
    Quantity target,
    String rounding, {
    Quantity? beyond,
    String? direction,
  }) {
    roundingPolicy(rounding);
    if (target.dimension != unit.dimension ||
        (beyond != null && beyond.dimension != unit.dimension))
      invalid('Scale and requested quantities need compatible dimensions.');
    if ((beyond == null) != (direction == null) ||
        (direction != null && !{'increase', 'decrease'}.contains(direction)))
      invalid(
        'Directional scale lookup needs beyond and increase/decrease together.',
      );
    int bound(Quantity value, {bool upper = false}) {
      var lo = 0, hi = ticks.length;
      while (lo < hi) {
        final mid = (lo + hi) ~/ 2;
        final comparison = ticks[mid].quantity.compareTo(value);
        if (comparison < 0 || (upper && comparison == 0)) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      return lo;
    }

    final lo = beyond != null && direction == 'increase'
        ? bound(beyond, upper: true)
        : 0;
    final hi = beyond != null && direction == 'decrease'
        ? bound(beyond)
        : ticks.length;
    int? selected;
    if (lo < hi) {
      if (rounding == 'atLeast') {
        final index = bound(target);
        final candidate = index < lo ? lo : index;
        if (candidate < hi) selected = candidate;
      } else if (rounding == 'atMost') {
        final index = bound(target, upper: true) - 1;
        final candidate = index >= hi ? hi - 1 : index;
        if (candidate >= lo) selected = candidate;
      } else {
        final index = bound(target);
        final upper = index < lo
            ? lo
            : index > hi
            ? hi
            : index;
        final lower = upper - 1;
        if (lower < lo) {
          selected = upper;
        } else if (upper >= hi) {
          selected = lower;
        } else {
          final lowerDistance = target.value - ticks[lower].quantity.value;
          final upperDistance = ticks[upper].quantity.value - target.value;
          final comparison = lowerDistance.compareTo(upperDistance);
          selected =
              comparison < 0 || (comparison == 0 && direction != 'increase')
              ? lower
              : upper;
        }
      }
    }
    return ScaleResolution._(
      id,
      target,
      rounding,
      beyond,
      direction,
      selected == null ? null : ticks[selected],
    );
  }
}

final class ScaleResolution {
  ScaleResolution._(
    this.scaleId,
    this.target,
    this.rounding,
    this.beyond,
    this.direction,
    this.tick, [
    this.metric,
  ]);
  final String scaleId, rounding;
  final String? metric;
  ScaleResolution forMetric(String value) => ScaleResolution._(
    scaleId,
    target,
    rounding,
    beyond,
    direction,
    tick,
    identifier({'id': value}, 'id'),
  );
  final Quantity target;
  final Quantity? beyond;
  final String? direction;
  final ScaleTick? tick;
  Map<String, Object?> toJson() => {
    if (metric != null) 'metric': metric,
    'scaleId': scaleId,
    'target': target.toJson(),
    'rounding': rounding,
    if (beyond != null) 'beyond': beyond!.toJson(),
    if (direction != null) 'direction': direction,
    'outcome': tick == null ? 'blocked' : 'resolved',
    'reason': tick == null
        ? 'No available tick satisfies direction and rounding.'
        : 'An available native tick satisfies the declared policy.',
    'tick': tick?.toJson(),
    'quantity': tick?.quantity.toJson(),
    'exact': tick == null ? null : tick!.quantity.compareTo(target) == 0,
  };
}

/// Frozen rule binding, independent of a mutable inventory/catalog lookup.
final class ScaleBinding {
  ScaleBinding._(this._scale, this.rounding, this.deloadRounding);

  /// Either an authored `scale`, or `instance: true`: the positions of the
  /// equipment instance an exposure was performed on (every total its
  /// declared plates can make, or its selector markings), bound by the
  /// stored progression from the frozen session before evaluation.
  factory ScaleBinding.fromJson(Object? input) {
    final j = jsonObject(input, 'scale binding');
    checkKeys(j, {'scale', 'instance', 'rounding', 'deloadRounding'});
    if (j.containsKey('scale') == j.containsKey('instance'))
      invalid('A scale binding names exactly one of scale or instance.');
    if (j.containsKey('instance') && j['instance'] != true)
      invalid('An instance scale binding is written instance: true.');
    final rounding = NumericScale.roundingPolicy(j['rounding']);
    return ScaleBinding._(
      j.containsKey('scale') ? NumericScale.fromJson(j['scale']) : null,
      rounding,
      j.containsKey('deloadRounding')
          ? NumericScale.roundingPolicy(j['deloadRounding'])
          : rounding,
    );
  }
  final NumericScale? _scale;
  final String rounding, deloadRounding;

  /// Whether this binding takes its positions from the instance used.
  bool get fromInstance => _scale == null;
  NumericScale get scale =>
      _scale ??
      invalid(
        'This rule rounds to the equipment instance used; evaluate it from a '
        'stored session whose sets have an instance with declared loading '
        'or a selector scale.',
      );

  /// This binding with the instance's positions in place.
  ScaleBinding bound(NumericScale positions) =>
      ScaleBinding._(positions, rounding, deloadRounding);
}
