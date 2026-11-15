import 'package:bodytmi_core/bodytmi_core.dart';

import 'canonical_json.dart';

/// Pure descriptive comparison of a session's recorded plate arrangements
/// against caller-supplied current instance snapshots. The recorded stacks
/// stay evaluated against their frozen instance revision; current revisions
/// only report whether the same stack is still available today and whether
/// the fresh plate helper would plan that same stack. Nothing is rewritten,
/// no prior consumption is simulated, and no mass relation is enforced.
Map<String, Object?> arrangementStatus(
  TrainingSession session, {
  Map<String, LoadInstanceReference> currentInstances = const {},
}) {
  final blocks = <Map<String, Object?>>[];
  for (final set in session.sets) {
    final arrangement = set.loadArrangement;
    if (arrangement == null) continue;
    final frozen = session.instanceOf(set)!;
    if (frozen.instanceId != arrangement.instanceId ||
        frozen.snapshot.loading == null)
      invalid('Recorded arrangement provenance is inconsistent.');
    arrangement.validateAgainst(frozen.snapshot.loading!);
    final channelMass = arrangement.channelMass;
    final totalMass = channelMass + frozen.snapshot.loading!.tareMass;
    final current = currentInstances[frozen.instanceId];
    final headLoading = current?.snapshot.loading;
    final masses = {
      'channelMass': Quantity(channelMass.toString(), 'kg').toJson(),
      'totalMass': Quantity(totalMass.toString(), 'kg').toJson(),
    };
    String? feasibilityBlock;
    try {
      if (current == null)
        feasibilityBlock = 'The instance binding no longer resolves.';
      else if (headLoading == null)
        feasibilityBlock =
            'The current instance revision has no declared loading.';
      else
        arrangement.validateAgainst(headLoading);
    } on BodyTmiException catch (error) {
      feasibilityBlock = error.message;
    }
    String? planStatus;
    if (feasibilityBlock == null) {
      final plan = PlatePlan.evaluate(
        headLoading!,
        Quantity(totalMass.toString(), 'kg'),
      );
      final match = jsonList(plan, 'arrangements')
          .cast<Map<String, Object?>>()
          .any((entry) => _matches(arrangement, headLoading, entry));
      planStatus = match ? 'planned' : 'feasible-not-planned';
    }
    final interpretation = _massRelation(session, set, arrangement, totalMass);
    // Only a capture whose effective convention came from the instance
    // default can be moved by a later instance revision; session and slot
    // overrides stay frozen exactly like the rest of the session context.
    final input = session.loadInputs[set.slotId];
    final frozenConvention = input?.convention == null
        ? null
        : canonicalJson(input!.convention!.toJson());
    final currentEffectiveConvention = input?.source == 'instance'
        ? (current?.snapshot.convention == null
              ? null
              : canonicalJson(current!.snapshot.convention!.toJson()))
        : frozenConvention;
    final conventionChanged =
        current != null && currentEffectiveConvention != frozenConvention;
    blocks.add({
      'setId': set.id,
      'slotId': set.slotId,
      'instanceId': frozen.instanceId,
      'frozenRevision': frozen.revision,
      'currentRevision': current?.revision,
      'arrangement': arrangement.toJson(),
      'computed': masses,
      'sides': [
        for (final side in arrangementSides(
          arrangement,
          frozen.snapshot.loading!,
        ))
          {
            'plates': [for (final usage in side) usage.toJson()],
          },
      ],
      'feasibleUnderCurrent': feasibilityBlock == null,
      if (feasibilityBlock != null) 'feasibilityReason': feasibilityBlock,
      'freshPlan': planStatus,
      'conventionChanged': conventionChanged,
      'massRelation': interpretation,
      'changed':
          current == null ||
          current.revision != frozen.revision ||
          feasibilityBlock != null ||
          planStatus != 'planned' ||
          conventionChanged,
    });
  }
  return {
    'policy': 'bodytmi-load-arrangement-status/1',
    'sessionId': session.id,
    'sets': blocks,
    'changed': blocks.any((b) => b['changed'] == true),
  };
}

/// A fresh plan arrangement entry matches the recorded stack when its per-side
/// plates reproduce the recorded aggregate usage exactly.
bool _matches(
  LoadArrangement arrangement,
  LoadingSpec loading,
  Map<String, Object?> planEntry,
) {
  final used = <String, int>{};
  for (final sideValue in jsonList(planEntry, 'sides')) {
    final side = jsonObject(sideValue, 'plan side');
    for (final plateValue in jsonList(side, 'plates')) {
      final plate = jsonObject(plateValue, 'plan plate');
      final mass = Quantity.fromJson(plate['mass']);
      final count = plate['count'];
      if (count is! int) return false;
      used.update(
        mass.value.toString(),
        (value) => value + count,
        ifAbsent: () => count,
      );
    }
  }
  final recorded = {
    for (final plate in arrangement.plates)
      plate.mass.value.toString(): plate.count,
  };
  if (used.length != recorded.length) return false;
  for (final entry in recorded.entries)
    if (used[entry.key] != entry.value) return false;
  return arrangement.channel == loading.channel.id;
}

/// Exact descriptive relation between the set's entered mass actual and the
/// arrangement's computed assembly mass under the session's frozen entry
/// convention. The relation never blocks a record: an added-load basis can
/// legitimately store the stack plus an unlisted handle tare, and a mismatch
/// is disclosed, not corrected.
Map<String, Object?> _massRelation(
  TrainingSession session,
  TrainingSet set,
  LoadArrangement arrangement,
  Decimal totalMass,
) {
  final entered = set.actuals['mass'];
  if (entered == null)
    return {
      'status': 'unknown',
      'reason': 'The set has no mass actual to compare.',
    };
  final convention = session.loadInputs[set.slotId]?.convention;
  if (convention == null)
    return {
      'status': 'unknown',
      'reason': 'The session captured no entry convention for this slot.',
    };
  final interpretation = LoadInterpretation.interpret(
    convention,
    entered,
    loading: session.instanceOf(set)!.snapshot.loading,
  );
  final assembly = jsonObject(
    jsonObject(
      interpretation['interpretation'],
      'interpretation',
    )['assemblyMass'],
    'assemblyMass',
  );
  if (assembly['status'] != 'known')
    return {
      'status': 'unknown',
      'reason':
          'The entry convention leaves the entered assembly mass unknown.',
      'interpretation': interpretation,
    };
  final interpreted = Quantity.fromJson(assembly['mass']);
  final arrangementTotal = Quantity(totalMass.toString(), 'kg');
  return {
    'status': 'known',
    'relation': interpreted.value == arrangementTotal.value
        ? 'same'
        : 'differs',
    'enteredMass': entered.toJson(),
    'interpretedAssemblyMass': interpreted.toJson(),
    'arrangementTotalMass': arrangementTotal.toJson(),
  };
}
