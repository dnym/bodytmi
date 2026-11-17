import 'package:bodytmi_core/bodytmi_core.dart';
import 'diet_service.dart';
import 'energy_service.dart';
import 'observation_service.dart';
import 'plan_service.dart';
import 'programme_service.dart';
import 'training_repository.dart';

const planProposalKind = 'plan-proposal';
const reviewPolicies = {'bodytmi-plan-review/1', 'mcdonald-moderate/1'};

/// A review proposal: explained, pending until accepted or declined,
/// recorded once and never applied automatically.
final class PlanProposal {
  PlanProposal._(this.json);
  factory PlanProposal.fromJson(Object? input) {
    final j = jsonObject(input, 'plan proposal');
    checkKeys(j, {
      'schemaVersion',
      'id',
      'planId',
      'kind',
      'policy',
      'createdOn',
      'status',
      'explanation',
      'evidence',
      'change',
      'resolution',
    });
    if (j['schemaVersion'] != 1) invalid('Unsupported proposal schemaVersion.');
    identifier(j, 'id');
    identifier(j, 'planId');
    if (!const {
      'lower-intake',
      'raise-intake',
      'recompute',
      'category',
      'end',
      'break',
      'insert-rfl',
    }.contains(j['kind']))
      invalid('Unknown proposal kind.');
    if (!reviewPolicies.contains(j['policy']))
      invalid('Unknown review policy.');
    requireDate(j['createdOn'], 'createdOn');
    if (!const {'pending', 'accepted', 'declined'}.contains(j['status']))
      invalid('A proposal is pending, accepted or declined.');
    requiredString(j, 'explanation');
    jsonObject(j['evidence'], 'evidence');
    jsonObject(j['change'], 'change');
    if ((j['status'] == 'pending') != (j['resolution'] == null))
      invalid('Resolved proposals, and only they, have a resolution.');
    return PlanProposal._(Map.unmodifiable(j));
  }
  final Map<String, Object?> json;
  String get id => json['id']! as String;
  String get planId => json['planId']! as String;
  String get kind => json['kind']! as String;
  String get status => json['status']! as String;
  Map<String, Object?> get change => json['change']! as Map<String, Object?>;
  Map<String, Object?> toJson() => json;
}

/// `plan review` and its proposals (section 4.2).
final class ReviewService {
  const ReviewService(this.repository);
  final TrainingRepository repository;

  Future<List<PlanProposal>> proposals({String? planId}) async => [
    for (final r in await repository.dietRecords(kind: planProposalKind))
      if (planId == null || r.snapshot['planId'] == planId)
        PlanProposal.fromJson(r.snapshot),
  ]..sort((a, b) => a.id.compareTo(b.id));

  Future<PlanProposal> proposal(String id) async =>
      (await proposals()).where((p) => p.id == id).firstOrNull ??
      (throw BodyTmiException('not_found', 'Proposal not found: $id.'));

  Future<void> _save(PlanProposal p) => repository.saveDietRecord(
    DietRecord(planProposalKind, p.id, 1, p.toJson()),
  );

  /// The plan's category now: the last accepted category change, else the
  /// category at activation.
  Future<int?> _planCategory(BodyPlan plan) async {
    int? category = (plan.json['programme'] as Map?)?['category'] as int?;
    for (final p in await proposals(planId: plan.id)) {
      if (p.kind == 'category' && p.status == 'accepted')
        category = p.change['category']! as int;
    }
    return category;
  }

  /// Policy bodytmi-plan-review/1 (or mcdonald-moderate/1 for Normal plans
  /// in place of its intake row) at [asOfText]: compares the mass trend
  /// with the simulation, the inputs with the frozen targets, the category
  /// and the cycle, and records at most one pending proposal per kind.
  Future<Map<String, Object?>> review(
    String planId,
    String asOfText, {
    String policy = 'bodytmi-plan-review/1',
    bool performanceDropping = false,
  }) => repository.transaction(() async {
    if (!reviewPolicies.contains(policy))
      invalid('policy is ${reviewPolicies.join(' or ')}.');
    parseInstant(asOfText, 'asOf');
    final date = asOfText.substring(0, 10);
    final plan = await PlanService(repository).plan(planId);
    if (plan.status != 'active') invalid('Only an active plan is reviewed.');
    final programme = (plan.json['programme'] as Map?)?['id'] as String?;
    if (policy == 'mcdonald-moderate/1' && programme != 'normal')
      invalid('mcdonald-moderate/1 reviews Normal plans.');
    final diets = DietService(repository);
    final run = await diets.run(planId);
    if (!run.covers(date)) invalid('The plan does not cover $date.');
    final seg = run.segmentOn(date);
    final cycle = (await diets.cycle(seg.cycleId, seg.cycleRevision)).cycle;
    final findings = <Map<String, Object?>>[];
    final offers = <Map<String, Object?>>[];

    // End: a finite cycle is over.
    if (dietDayOn(run, cycle, date) == null) {
      final end = addDays(seg.anchor, cycle.days.length);
      offers.add({
        'kind': 'end',
        'explanation':
            'The cycle ended on ${addDays(end, -1)}; end the plan from $end.',
        'evidence': {'cycleDays': cycle.days.length, 'anchor': seg.anchor},
        'change': {'endDate': end},
      });
    }

    final (:inputs, :frozen) = await diets.currentInputs(asOfText);
    // Target: the trend mass or selected body fat reached the plan target.
    final target = plan.target;
    if (target != null) {
      final current = target.measure == 'mass'
          ? jsonObject(frozen['mass'] ?? {'status': 'unavailable'}, 'mass')
          : jsonObject(frozen['bodyFat'], 'bodyFat');
      final resolved =
          current['status'] == 'resolved' ||
          (target.measure == 'mass' && frozen['mass'] != null);
      if (!resolved) {
        findings.add({
          'kind': 'target',
          'status': 'unknown',
          'target': target.toJson(),
          'reason': target.measure == 'mass'
              ? 'The trend mass is unavailable.'
              : 'The selected body-fat source is unavailable.',
        });
      } else {
        final value = target.measure == 'mass'
            ? Decimal.parse(current['value']! as String)
            : Quantity.fromJson(current['value']).value;
        final reached = target.reachedBy(value);
        findings.add({
          'kind': 'target',
          'status': reached ? 'reached' : 'not-reached',
          'target': target.toJson(),
          'current': target.measure == 'mass'
              ? {'value': current['value'], 'unit': 'kg'}
              : current['value'],
          if (target.measure == 'bodyFat') 'source': current['source'],
        });
        if (reached && !offers.any((o) => o['kind'] == 'end')) {
          final end = addDays(date, 1);
          offers.add({
            'kind': 'end',
            'explanation':
                'The plan target is reached (${target.measure} '
                '${target.atMost ? 'at most' : 'at least'} '
                '${target.value.enteredValue} ${target.value.enteredUnit.name}); '
                'end the plan from $end.',
            'evidence': {
              'target': target.toJson(),
              'current': findings.last['current'],
            },
            'change': {'endDate': end},
          });
        }
      }
    }
    // Category.
    final category = jsonObject(frozen['category'], 'category');
    final planCategory = await _planCategory(plan);
    if (planCategory != null &&
        category['status'] == 'resolved' &&
        category['value'] != planCategory) {
      offers.add({
        'kind': 'category',
        'explanation':
            'The selected body-fat source now gives category '
            '${category['value']} (the plan uses $planCategory); the '
            'handbook says to recheck about every 4 weeks.',
        'evidence': {'bodyFat': frozen['bodyFat'], 'from': planCategory},
        'change': {'category': category['value']},
      });
    }

    // Recompute: energy or protein targets moved by more than 5 %.
    final moved = <Map<String, Object?>>[];
    for (final ref in cycle.dayTypes) {
      final type = (await diets.dayType(ref.id, ref.revision)).dayType;
      final now = type.resolve(inputs, energyOffset: seg.energyOffset);
      final then = seg.targets['${ref.id}/${ref.revision}']! as Map;
      for (final goal in ['energy', 'protein']) {
        double? v(Map<dynamic, dynamic> goals) {
          final g = goals[goal] as Map?;
          return g == null || g['status'] != 'resolved'
              ? null
              : double.parse((g['value']! as Map)['value']! as String);
        }

        final a = v(then), b = v(now);
        if (a == null || b == null || a == 0) continue;
        final change = (b - a) / a;
        if (change.abs() > 0.05)
          moved.add({
            'dayType': ref.id,
            'goal': goal,
            'frozen': round9(a),
            'current': round9(b),
            'change': round9(change),
          });
      }
    }
    if (moved.isNotEmpty) {
      offers.add({
        'kind': 'recompute',
        'explanation':
            'Mass or fat-free mass moved enough to change a target by more '
            'than 5 %; recompute the targets from current inputs.',
        'evidence': {'moved': moved},
        'change': {'inputs': frozen},
      });
    }

    // Start a break: a Normal plan has run its moderate-diet stint
    // (handbook ch. 15: category 1 4–6, 2 6–12, 3 12–16 weeks).
    if (programme == 'normal' && planCategory != null) {
      final breakType = '${plan.id}-break';
      var since = run.startDate;
      for (final o in run.overrides) {
        if (o.dayType.id == breakType && o.date.compareTo(date) < 0)
          since = addDays(o.date, 1);
      }
      final weeks = const {1: 4, 2: 6, 3: 12}[planCategory]!;
      final ran = daysBetween(since, date);
      final types = await diets.dayTypes();
      final latest = [
        for (final t in types)
          if (t.dayType.id == breakType) t.number,
      ];
      if (ran >= weeks * 7 && latest.isNotEmpty)
        offers.add({
          'kind': 'break',
          'explanation':
              'The diet has run $ran days since $since; category '
              '$planCategory stints are $weeks weeks or more before a '
              '2-week break at maintenance (handbook ch. 15).',
          'evidence': {'since': since, 'days': ran, 'minimumWeeks': weeks},
          'change': {
            'dayType': {
              'id': breakType,
              'revision': latest.reduce((a, b) => a > b ? a : b),
            },
            'days': 14,
          },
        });
    }

    // Intake: trend loss over the last 21 days against the plan.
    final trend = await _trendWindow(run, seg, cycle, date, asOfText);
    findings.add(trend);
    if (trend['status'] == 'resolved' &&
        cycle.days.isNotEmpty &&
        programme != 'erfl') {
      final actual = double.parse(trend['actualLossKg']! as String);
      final planned = double.parse(trend['plannedLossKg']! as String);
      if (policy == 'bodytmi-plan-review/1') {
        if (planned > 0 && actual < 0.25 * planned)
          offers.add({
            'kind': 'lower-intake',
            'explanation':
                'The trend lost ${round9(actual)} kg in 21 days, under 25 % '
                'of the planned ${round9(planned)} kg: lower intake by 100 '
                'kcal a day (or add activity instead).',
            'evidence': trend,
            'change': {'energyDelta': '-100'},
          });
      } else {
        final lbPerWeek = actual / kgPerLb / 3;
        final energy = await _adjustableEnergy(diets, cycle, seg);
        if (energy != null && lbPerWeek < 1) {
          offers.add({
            'kind': 'lower-intake',
            'explanation':
                'Under 1 lb a week (${round9(lbPerWeek)}): cut calories '
                '10 % (handbook ch. 15).',
            'evidence': {...trend, 'lbPerWeek': round9(lbPerWeek)},
            'change': {'energyDelta': round9(-0.1 * energy)},
          });
        } else if (energy != null && lbPerWeek >= 2 && performanceDropping) {
          offers.add({
            'kind': 'raise-intake',
            'explanation':
                '2 lb a week or more (${round9(lbPerWeek)}) with training '
                'performance dropping: add 10 % (handbook ch. 15).',
            'evidence': {...trend, 'lbPerWeek': round9(lbPerWeek)},
            'change': {'energyDelta': round9(0.1 * energy)},
          });
        }
      }
    }

    // Insert RFL days: the trend is 2 % above the plan's baseline mass
    // (IMF ch. 34: act at +1–3 %; 3–4 RFL days a week until back).
    DayTypeRef? rfl;
    for (final ref in cycle.dayTypes) {
      final type = (await diets.dayType(ref.id, ref.revision)).dayType;
      if (type.goals['energy']?.isSum ?? false) rfl = ref;
    }
    final baseline = dietInputsOf(run.inputs).massKg;
    if (rfl != null && baseline != null) {
      final now = await ObservationService(
        repository,
      ).resolve('body-mass', asOfText, attributes: const {'context': 'health'});
      final j = now.toJson();
      if (j['status'] == 'resolved') {
        final mass = double.parse(
          Quantity.fromJson(j['value']).value.toString(),
        );
        if (mass >= baseline * 1.02)
          offers.add({
            'kind': 'insert-rfl',
            'explanation':
                'The mass trend ${round9(mass)} kg is '
                '${round9((mass / baseline - 1) * 100)} % above the plan '
                'baseline ${round9(baseline)} kg; make 3 of the next 7 days '
                'RFL days (IMF ch. 34).',
            'evidence': {'trend': round9(mass), 'baseline': round9(baseline)},
            'change': {'dayType': dayTypeRefToJson(rfl), 'perWeek': 3},
          });
      }
    }

    // Record one pending proposal per kind; an offer whose energy change
    // would break the programme floor is reported, not proposed.
    final existing = await proposals(planId: planId);
    final created = <PlanProposal>[];
    for (final o in offers) {
      if (existing.any((p) => p.kind == o['kind'] && p.status == 'pending'))
        continue;
      if (o['change'] is Map &&
          (o['change']! as Map).containsKey('energyDelta')) {
        final delta = double.parse(
          (o['change']! as Map)['energyDelta']! as String,
        );
        if (!await _fits(diets, cycle, seg, seg.energyOffset + delta)) {
          findings.add({
            'kind': o['kind'],
            'status': 'not-proposed',
            'reason': 'The change would take a goal below zero.',
          });
          continue;
        }
      }
      final p = PlanProposal.fromJson({
        'schemaVersion': 1,
        'id': '$planId--${existing.length + created.length + 1}',
        'planId': planId,
        'kind': o['kind'],
        'policy': policy,
        'createdOn': date,
        'status': 'pending',
        ...o,
      });
      await _save(p);
      created.add(p);
    }
    return {
      'policy': policy,
      'planId': planId,
      'asOf': asOfText,
      'findings': findings,
      'created': [for (final p in created) p.id],
      'pending': [
        for (final p in await proposals(planId: planId))
          if (p.status == 'pending') p.toJson(),
      ],
    };
  });

  Future<double?> _adjustableEnergy(
    DietService diets,
    DietCycle cycle,
    DietSegment seg,
  ) async {
    for (final ref in cycle.dayTypes) {
      final type = (await diets.dayType(ref.id, ref.revision)).dayType;
      if (!type.adjustable) continue;
      final g =
          (seg.targets['${ref.id}/${ref.revision}']! as Map)['energy'] as Map;
      if (g['status'] == 'resolved')
        return double.parse((g['value']! as Map)['value']! as String);
    }
    return null;
  }

  Future<bool> _fits(
    DietService diets,
    DietCycle cycle,
    DietSegment seg,
    double offset,
  ) async {
    var adjustable = false;
    for (final ref in cycle.dayTypes) {
      final type = (await diets.dayType(ref.id, ref.revision)).dayType;
      if (!type.adjustable) continue;
      adjustable = true;
      final goals = type.resolve(
        dietInputsOf(seg.inputs),
        energyOffset: offset,
      );
      if (goals.values.any((g) => (g! as Map)['status'] != 'resolved'))
        return false;
    }
    return adjustable;
  }

  /// Trend mass change over the 21 days before [date] against the
  /// simulation of the same days under the plan.
  Future<Map<String, Object?>> _trendWindow(
    DietRun run,
    DietSegment seg,
    DietCycle cycle,
    String date,
    String asOfText,
  ) async {
    final start = addDays(date, -21);
    if (start.compareTo(seg.from) < 0)
      return {
        'kind': 'trend',
        'status': 'unavailable',
        'reason':
            'Fewer than 21 days since ${seg.from} (the plan start or its '
            'latest change).',
      };
    final observations = ObservationService(repository);
    final time = asOfText.substring(10);
    Future<double?> mass(String day) async {
      final r = (await observations.resolve(
        'body-mass',
        '$day$time',
        attributes: const {'context': 'health'},
      )).toJson();
      return r['status'] == 'resolved'
          ? double.parse(Quantity.fromJson(r['value']).value.toString())
          : null;
    }

    final before = await mass(start), after = await mass(date);
    final energy = await EnergyService(repository).resolveInputs('$start$time');
    final ffmRatio =
        energy.inputs.fatFreeMassKg == null || energy.inputs.massKg == null
        ? null
        : energy.inputs.fatFreeMassKg! / energy.inputs.massKg!;
    if (before == null ||
        after == null ||
        ffmRatio == null ||
        energy.method == null)
      return {
        'kind': 'trend',
        'status': 'unavailable',
        'reason':
            'The mass trend, fat-free mass or maintenance method is '
            'unavailable for the window.',
      };
    final diets = DietService(repository);
    final schedule = await diets.schedule(start, 21, runId: run.id);
    final maintenance = dietInputsOf(seg.inputs).maintenanceKcal;
    final days = (schedule['days']! as List).cast<Map<String, Object?>>();
    final e = energy.inputs;
    final sim = simulateEnergyBalance(
      startDate: start,
      days: 21,
      massKg: before,
      fatFreeMassKg: before * ffmRatio,
      intake: (day, _) {
        final goals = days[day]['goals'] as Map?;
        final g = goals?['energy'] as Map?;
        return g != null && g['status'] == 'resolved'
            ? double.parse((g['value']! as Map)['value']! as String)
            : maintenance;
      },
      expenditure: (_, m, lean) {
        final r = energy.method!.evaluate((
          massKg: m,
          heightCm: e.heightCm,
          fatFreeMassKg: lean,
          age: e.age,
          sex: e.sex,
          category: e.sex == null
              ? null
              : dietCategory(Decimal.parse(round9((m - lean) / m)), e.sex!),
        ));
        return r['status'] == 'resolved'
            ? double.parse(jsonObject(r['value'], 'v')['value']! as String)
            : null;
      },
    );
    if (sim['status'] != 'resolved')
      return {
        'kind': 'trend',
        'status': 'unavailable',
        'reason': sim['reason'],
      };
    final planned = -double.parse(
      jsonObject(sim['change'], 'change')['mass']! as String,
    );
    return {
      'kind': 'trend',
      'status': 'resolved',
      'from': start,
      'to': date,
      'trendFrom': round9(before),
      'trendTo': round9(after),
      'actualLossKg': round9(before - after),
      'plannedLossKg': round9(planned),
    };
  }

  /// Accepts a pending proposal from [from]: changes the plan once
  /// (an energy offset, recomputed inputs, a category change with the
  /// programme re-applied, or ending the plan). Accepting again returns the
  /// accepted proposal.
  Future<PlanProposal> accept(
    String id,
    String from, {
    Map<String, Object?> choices = const {},
  }) => repository.transaction(() async {
    requireDate(from, 'from');
    final p = await proposal(id);
    if (p.status == 'accepted') return p;
    if (p.status != 'pending') invalid('The proposal was declined.');
    final plans = PlanService(repository);
    final plan = await plans.plan(p.planId);
    if (plan.status != 'active') invalid('The plan has ended.');
    final diets = DietService(repository);
    final run = await diets.run(p.planId);
    final seg = run.segmentOn(from);
    final reason = p.json['explanation']! as String;
    switch (p.kind) {
      case 'lower-intake' || 'raise-intake':
        await diets.addSegment(
          run.id,
          run.contentVersion,
          from: from,
          energyOffset:
              seg.energyOffset +
              double.parse(p.change['energyDelta']! as String),
          reason: reason,
          proposal: id,
        );
      case 'recompute':
        await diets.addSegment(
          run.id,
          run.contentVersion,
          from: from,
          inputs: p.change['inputs']! as Map<String, Object?>,
          reason: reason,
          proposal: id,
        );
      case 'category':
        final programme = plan.json['programme']! as Map;
        final merged = {
          ...(programme['choices']! as Map<String, Object?>),
          ...choices,
        };
        final asOf = '${p.json['createdOn']}T12:00:00Z';
        final applied = await ProgrammeService(
          repository,
        ).apply(programme['id']! as String, merged, asOf, plan.id);
        if (applied['category'] != p.change['category'])
          throw const BodyTmiException(
            'conflict',
            'The category changed again; review the plan again.',
          );
        final (inputs: _, :frozen) = await diets.currentInputs(asOf);
        await diets.addSegment(
          run.id,
          run.contentVersion,
          from: from,
          anchor: from,
          cycleId: plan.id,
          cycleRevision:
              jsonObject(applied['cycle'], 'cycle')['revision']! as int,
          inputs: frozen,
          energyOffset: 0,
          reason: reason,
          proposal: id,
        );
      case 'break':
        final ref = dayTypeRefFromJson(p.change['dayType'], 'dayType');
        var current = run;
        for (var i = 0; i < (p.change['days']! as int); i++) {
          final day = addDays(from, i);
          if (!current.covers(day)) break;
          current = await diets.override(
            run.id,
            day,
            ref,
            'Diet break ($id)',
            current.contentVersion,
          );
        }
      case 'insert-rfl':
        final ref = dayTypeRefFromJson(p.change['dayType'], 'dayType');
        var current = run;
        final schedule = await diets.schedule(from, 7, runId: run.id);
        final days = (schedule['days']! as List).cast<Map<String, Object?>>();
        var rflDays = days
            .where((d) => (d['dayType'] as Map?)?['id'] == ref.id)
            .length;
        for (final d in days) {
          if (rflDays >= (p.change['perWeek']! as int)) break;
          final type = d['dayType'] as Map?;
          if (type == null || type['id'] == ref.id) continue;
          current = await diets.override(
            run.id,
            d['date']! as String,
            ref,
            'Inserted RFL day ($id)',
            current.contentVersion,
          );
          rflDays++;
        }
      default: // end
        await plans.end(
          plan.id,
          p.change['endDate']! as String,
          plan.contentVersion,
          confirm: true,
        );
    }
    final next = PlanProposal.fromJson({
      ...p.json,
      'status': 'accepted',
      'resolution': {
        'from': p.kind == 'end' ? p.change['endDate'] : from,
        if (choices.isNotEmpty) 'choices': choices,
      },
    });
    await _save(next);
    return next;
  });

  Future<PlanProposal> decline(String id) => repository.transaction(() async {
    final p = await proposal(id);
    if (p.status == 'declined') return p;
    if (p.status != 'pending') invalid('The proposal was accepted.');
    final next = PlanProposal.fromJson({
      ...p.json,
      'status': 'declined',
      'resolution': <String, Object?>{},
    });
    await _save(next);
    return next;
  });
}

/// Proposals name existing plans; accepted energy, recompute and category
/// proposals each match exactly one change of the plan's diet run.
void validatePlanProposals(
  List<PlanProposal> proposals,
  List<BodyPlan> plans,
  List<DietRun> runs,
) {
  final planIds = {for (final p in plans) p.id};
  final segmentProposals = <String>{
    for (final r in runs)
      for (final s in r.segments)
        if (s['proposal'] != null) s['proposal']! as String,
  };
  final accepted = <String>{};
  for (final p in proposals) {
    if (!planIds.contains(p.planId))
      invalid('Proposal ${p.id} names an unknown plan.');
    if (p.status == 'accepted' &&
        const {
          'lower-intake',
          'raise-intake',
          'recompute',
          'category',
        }.contains(p.kind))
      accepted.add(p.id);
  }
  if (accepted.length != segmentProposals.length ||
      !accepted.every(segmentProposals.contains))
    invalid('Accepted proposals and diet run changes do not match.');
}
