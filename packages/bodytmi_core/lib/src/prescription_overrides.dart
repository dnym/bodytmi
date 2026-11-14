import 'errors.dart';
import 'quantity.dart';
import 'workout.dart';

/// An explicit scoped adjustment to authored workout targets declared on a
/// program node. A scale override multiplies each entered target value
/// exactly; a set override replaces the target with a fixed authored
/// quantity. Overrides only rewrite targets that already have an authored
/// value; they never invent, remove or relabel metrics.
final class ProgramOverride {
  ProgramOverride({
    required this.slotId,
    required this.metric,
    required this.mode,
    this.factor,
    this.quantity,
  }) {
    identifier({'slotId': slotId}, 'slotId');
    identifier({'metric': metric}, 'metric');
    switch (mode) {
      case 'scale':
        if (factor == null || quantity != null) {
          invalid('Scale prescription overrides require only a factor.');
        } else if (factor!.compareTo(Decimal.zero) <= 0) {
          invalid('Prescription override factors must be positive.');
        }
      case 'set':
        if (quantity == null || factor != null) {
          invalid('Set prescription overrides require only a quantity.');
        }
      default:
        invalid('Unknown prescription override mode.');
    }
  }

  factory ProgramOverride.fromJson(Object? input) {
    final json = jsonObject(input, 'prescription override');
    checkKeys(json, {'slotId', 'metric', 'mode', 'factor', 'quantity'});
    return ProgramOverride(
      slotId: identifier(json, 'slotId'),
      metric: identifier(json, 'metric'),
      mode: requiredString(json, 'mode'),
      factor: json['factor'] == null
          ? null
          : Decimal.parse(requiredString(json, 'factor')),
      quantity: json['quantity'] == null
          ? null
          : Quantity.fromJson(json['quantity']),
    );
  }

  final String slotId, metric, mode;
  final Decimal? factor;
  final Quantity? quantity;

  String get scopeKey => '$slotId\u0000$metric';

  Quantity apply(Quantity base) => mode == 'scale'
      ? Quantity(
          (Decimal.parse(base.enteredValue) * factor!).toString(),
          base.enteredUnit.name,
        )
      : quantity!;

  Map<String, Object?> toJson() => {
    'slotId': slotId,
    'metric': metric,
    'mode': mode,
    if (factor != null) 'factor': factor!.toString(),
    if (quantity != null) 'quantity': quantity!.toJson(),
  };
}

/// One effective override paired with the program node path that declared it.
final class ScopedProgramOverride {
  const ScopedProgramOverride(this.path, this.override);
  final String path;
  final ProgramOverride override;
  Map<String, Object?> toJson() => {'path': path, ...override.toJson()};
}

/// One session set rewritten by a frozen prescription override, with the
/// authored prior target and applied result for provenance.
final class PrescriptionOverrideApplication {
  const PrescriptionOverrideApplication({
    required this.setId,
    required this.before,
    required this.after,
  });

  factory PrescriptionOverrideApplication.fromJson(Object? input) {
    final json = jsonObject(input, 'prescription override application');
    checkKeys(json, {'setId', 'before', 'after'});
    return PrescriptionOverrideApplication(
      setId: requiredString(json, 'setId'),
      before: Quantity.fromJson(json['before']),
      after: Quantity.fromJson(json['after']),
    );
  }

  final String setId;
  final Quantity before, after;

  Map<String, Object?> toJson() => {
    'setId': setId,
    'before': before.toJson(),
    'after': after.toJson(),
  };
}

/// The durable session-snapshot record of one program prescription override.
final class PrescriptionOverrideRecord {
  PrescriptionOverrideRecord({
    required this.path,
    required this.slotId,
    required this.metric,
    required this.mode,
    this.factor,
    this.quantity,
    required List<PrescriptionOverrideApplication> applied,
  }) : applied = List.unmodifiable(applied) {
    requiredString({'path': path}, 'path');
    if (applied.isEmpty) {
      invalid('Prescription override records require applied sets.');
    }
    override;
  }

  factory PrescriptionOverrideRecord.fromJson(Object? input) {
    final json = jsonObject(input, 'prescription override record');
    checkKeys(json, {
      'path',
      'slotId',
      'metric',
      'mode',
      'factor',
      'quantity',
      'applied',
    });
    return PrescriptionOverrideRecord(
      path: requiredString(json, 'path'),
      slotId: identifier(json, 'slotId'),
      metric: identifier(json, 'metric'),
      mode: requiredString(json, 'mode'),
      factor: json['factor'] == null
          ? null
          : Decimal.parse(requiredString(json, 'factor')),
      quantity: json['quantity'] == null
          ? null
          : Quantity.fromJson(json['quantity']),
      applied: [
        for (final item in jsonList(json, 'applied'))
          PrescriptionOverrideApplication.fromJson(item),
      ],
    );
  }

  final String path, slotId, metric, mode;
  final Decimal? factor;
  final Quantity? quantity;
  final List<PrescriptionOverrideApplication> applied;

  /// Revalidates the stored mode payload pairing through the authoring model.
  ProgramOverride get override => ProgramOverride(
    slotId: slotId,
    metric: metric,
    mode: mode,
    factor: factor,
    quantity: quantity,
  );

  Map<String, Object?> toJson() => {
    'path': path,
    'slotId': slotId,
    'metric': metric,
    'mode': mode,
    if (factor != null) 'factor': factor!.toString(),
    if (quantity != null) 'quantity': quantity!.toJson(),
    'applied': [for (final a in applied) a.toJson()],
  };
}

/// Rewritten sets plus the provenance records for one start operation.
final class PrescriptionOverrideResult {
  const PrescriptionOverrideResult(this.sets, this.records);
  final List<TrainingSet> sets;
  final List<PrescriptionOverrideRecord> records;
}

/// Applies effective program overrides to freshly expanded session sets.
/// The authored base target is the prior value regardless of history prefill,
/// so overridden metrics also drop their history prefill sources. Overrides
/// that match no authored target under the pinned revision apply nothing.
PrescriptionOverrideResult applyPrescriptionOverrides(
  WorkoutDefinition definition,
  List<TrainingSet> sets,
  List<ScopedProgramOverride> overrides,
) {
  if (overrides.isEmpty) return PrescriptionOverrideResult(sets, const []);
  final slotIds = {for (final slot in definition.slots) slot.id};
  final authored = <String, List<Metrics>>{};
  final replacement = <String, Metrics>{};
  final records = <PrescriptionOverrideRecord>[];
  for (final scoped in overrides) {
    final override = scoped.override;
    if (!slotIds.contains(override.slotId)) continue;
    final applied = <PrescriptionOverrideApplication>[];
    for (final set in sets) {
      if (set.slotId != override.slotId) continue;
      final byRole = authored.putIfAbsent(
        '${override.slotId}\u0000${set.role}',
        () => definition.roleTargets(override.slotId, set.role),
      );
      if (set.ordinal >= byRole.length) continue;
      final base = byRole[set.ordinal][override.metric];
      if (base == null) continue;
      final value = override.apply(base);
      applied.add(
        PrescriptionOverrideApplication(
          setId: set.id,
          before: base,
          after: value,
        ),
      );
      replacement.putIfAbsent(set.id, () => {})[override.metric] = value;
    }
    if (applied.isNotEmpty) {
      records.add(
        PrescriptionOverrideRecord(
          path: scoped.path,
          slotId: override.slotId,
          metric: override.metric,
          mode: override.mode,
          factor: override.factor,
          quantity: override.quantity,
          applied: applied,
        ),
      );
    }
  }
  if (records.isEmpty) return PrescriptionOverrideResult(sets, const []);
  final rebuilt = [
    for (final set in sets)
      replacement[set.id] == null
          ? set
          : TrainingSet(
              id: set.id,
              slotId: set.slotId,
              role: set.role,
              ordinal: set.ordinal,
              settings: set.settings,
              actualSettings: set.actualSettings,
              suggested: {...set.suggested, ...replacement[set.id]!},
              sources: {
                for (final entry in set.sources.entries)
                  if (!replacement[set.id]!.containsKey(entry.key))
                    entry.key: entry.value,
              },
              manualTargets: set.manualTargets,
              carriedTargets: set.carriedTargets,
              status: set.status,
              actuals: set.actuals,
              contentVersion: set.contentVersion,
              timing: set.timing,
              observations: set.observations,
              maxEffortMetrics: set.maxEffortMetrics,
              criteria: set.criteria,
            ),
  ];
  return PrescriptionOverrideResult(rebuilt, records);
}
