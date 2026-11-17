import 'package:bodytmi_core/bodytmi_core.dart';
import 'diet_service.dart';
import 'energy_service.dart';
import 'training_repository.dart';

/// Inputs shared by guides and simulations at one time.
typedef _Context = ({
  DietInputs inputs,
  Map<String, Object?> frozen,
  EnergyInputs energy,
  MaintenanceMethod? method,
  Profile profile,
});

/// Programme guides (D4): each built-in diet blueprint computed from your
/// current data, the same guide for your own cycles, the energy-balance
/// simulation, and applying a programme as ordinary day types and a cycle.
final class ProgrammeService {
  const ProgrammeService(this.repository);
  final TrainingRepository repository;

  Future<_Context> _context(
    String asOfText,
    String context,
    MaintenanceMethod? method,
  ) async {
    final (:inputs, :frozen) = await DietService(
      repository,
    ).currentInputs(asOfText, context: context, method: method);
    final r = await EnergyService(
      repository,
    ).resolveInputs(asOfText, context: context, method: method);
    return (
      inputs: inputs,
      frozen: frozen,
      energy: r.inputs,
      method: r.method,
      profile: r.profile,
    );
  }

  /// Policy bodytmi-programme-guide/1 for [programmeId] with [choices]:
  /// day types with resolved goals, schedule, cycle, recommendation, the
  /// book's own estimate, warnings, every input and, given
  /// [simulateDays], the simulation; unavailable naming missing inputs or
  /// choices.
  Future<Map<String, Object?>> guide(
    String programmeId,
    Map<String, Object?> choices,
    String asOfText, {
    String context = 'health',
    MaintenanceMethod? method,
    int? simulateDays,
  }) => repository.transaction(() async {
    final programme = dietProgramme(programmeId);
    final ctx = await _context(asOfText, context, method);
    final base = {
      'policy': 'bodytmi-programme-guide/1',
      'programme': programme.toJson(),
      'choices': choices,
      'asOf': asOfText,
      'inputs': ctx.frozen,
    };
    final category = jsonObject(ctx.frozen['category'], 'category');
    if (category['status'] != 'resolved')
      return {
        ...base,
        'status': 'unavailable',
        'reason': 'The diet category is unavailable: ${category['reason']}',
      };
    final cat = category['value']! as int;
    final missing = programme.missingChoices(choices, cat);
    if (missing.isNotEmpty)
      return {
        ...base,
        'status': 'unavailable',
        'missingChoices': missing,
        'reason': 'Choose ${missing.join(', ')}.',
      };
    final build = programme.build(choices, cat, programmeId);
    final types = {for (final t in build.dayTypes) '${t.id}/1': t};
    final cycle = DietCycle.fromJson({
      'id': 'preview',
      'name': programme.name,
      'loop': build.loop,
      'days': _withRevisions(build.cycleDays, {
        for (final t in build.dayTypes) t.id: 1,
      }),
    });
    double? walkingKm;
    String? walkingReason;
    if (programmeId == 'erfl') {
      (walkingKm, walkingReason) = _walkingKm(
        jsonObject(choices['walking'], 'walking'),
        ctx.profile,
      );
    }
    return {
      ...base,
      'status': 'resolved',
      'category': cat,
      'schedule': build.schedule,
      'recommendation': programme.recommendation,
      'warnings': build.warnings,
      ..._cycleGuide(
        types,
        cycle,
        ctx,
        asOfText.substring(0, 10),
        simulateDays,
        walking: walkingKm == null
            ? const {}
            : {'$programmeId-day/1': walkingKm},
        walkingReason: walkingReason,
      ),
    };
  });

  /// The same guide for one of your own published cycles (policy
  /// bodytmi-cycle-guide/1), starting on [startDate].
  Future<Map<String, Object?>> cycleGuide(
    String cycleId,
    int revision,
    String asOfText, {
    String? startDate,
    String context = 'health',
    MaintenanceMethod? method,
    int? simulateDays,
  }) => repository.transaction(() async {
    final diets = DietService(repository);
    final cycle = (await diets.cycle(cycleId, revision)).cycle;
    final types = {
      for (final ref in cycle.dayTypes)
        '${ref.id}/${ref.revision}': (await diets.dayType(
          ref.id,
          ref.revision,
        )).dayType,
    };
    final ctx = await _context(asOfText, context, method);
    return {
      'policy': 'bodytmi-cycle-guide/1',
      'cycle': {
        'id': cycleId,
        'revision': revision,
        'name': cycle.json['name'],
      },
      'asOf': asOfText,
      'inputs': ctx.frozen,
      ..._cycleGuide(
        types,
        cycle,
        ctx,
        startDate ?? asOfText.substring(0, 10),
        simulateDays,
      ),
    };
  });

  Map<String, Object?> _cycleGuide(
    Map<String, DayType> types,
    DietCycle cycle,
    _Context ctx,
    String startDate,
    int? simulateDays, {
    Map<String, double> walking = const {},
    String? walkingReason,
  }) {
    final goals = {
      for (final e in types.entries) e.key: e.value.resolve(ctx.inputs),
    };
    double? energyOf(String key) {
      final e = goals[key]!['energy'] as Map<String, Object?>?;
      return e == null || e['status'] != 'resolved'
          ? null
          : double.parse(jsonObject(e['value'], 'v')['value']! as String);
    }

    String key(CycleDay d) => '${d.dayType.id}/${d.dayType.revision}';
    final maintenance = ctx.inputs.maintenanceKcal;
    Map<String, Object?> bookEstimate;
    if (maintenance == null) {
      bookEstimate = {
        'status': 'unavailable',
        'reason': 'Maintenance energy is unavailable.',
      };
    } else if (walkingReason != null) {
      bookEstimate = {'status': 'unavailable', 'reason': walkingReason};
    } else {
      var deficit = 0.0, withoutEnergy = 0;
      for (final d in cycle.days) {
        final energy = energyOf(key(d));
        if (energy == null) {
          withoutEnergy++;
        } else {
          deficit += maintenance - energy;
        }
        final km = walking[key(d)];
        if (km != null) deficit += 0.75 * ctx.inputs.massKg! * km;
      }
      final days = cycle.days.length;
      bookEstimate = {
        'status': 'resolved',
        'label': "The book's estimate, not a prediction.",
        'basis': 'deficit ÷ 3,500 kcal per lb of fat',
        'cycleDays': days,
        'deficitPerCycle': {'value': round9(deficit), 'unit': 'kcal'},
        'fatPerCycle': {'value': round9(deficit / 3500), 'unit': 'lb'},
        if (cycle.loop)
          'fatPerWeek': {
            'value': round9(deficit / days * 7 / 3500),
            'unit': 'lb',
          },
        'daysWithoutEnergyGoal': withoutEnergy,
        if (walking.isNotEmpty) 'walkingKmPerDay': round9(walking.values.first),
      };
    }
    Map<String, Object?>? simulation;
    if (simulateDays != null) {
      simulation = _simulate(
        cycle,
        energyOf,
        ctx,
        startDate,
        simulateDays,
        walking,
        walkingReason,
      );
    }
    return {
      'dayTypes': [
        for (final e in types.entries)
          {
            'id': e.value.id,
            'revision': int.parse(e.key.split('/').last),
            'name': e.value.name,
            'goals': goals[e.key],
            'steps': ?e.value.json['steps'],
            'notes': ?e.value.json['notes'],
          },
      ],
      'cycle': _summary(cycle),
      'bookEstimate': bookEstimate,
      'simulation': ?simulation,
    };
  }

  Map<String, Object?> _simulate(
    DietCycle cycle,
    double? Function(String key) energyOf,
    _Context ctx,
    String startDate,
    int days,
    Map<String, double> walking,
    String? walkingReason,
  ) {
    final method = ctx.method;
    final mass = ctx.inputs.massKg, ffm = ctx.inputs.fatFreeMassKg;
    if (method == null || mass == null || ffm == null || walkingReason != null)
      return {
        'policy': simulationPolicy,
        'status': 'unavailable',
        'reason':
            walkingReason ??
            (method == null
                ? 'No maintenance method is selected.'
                : 'The simulation needs body mass and fat-free mass.'),
      };
    CycleDay? dayAt(int day) => !cycle.loop && day >= cycle.days.length
        ? null
        : cycle.days[day % cycle.days.length];
    final maintenance = ctx.inputs.maintenanceKcal!;
    final e = ctx.energy;
    return simulateEnergyBalance(
      startDate: startDate,
      days: days,
      massKg: mass,
      fatFreeMassKg: ffm,
      every: days > 120 ? 7 : 1,
      // After a finite cycle ends, intake returns to maintenance as
      // estimated at the start.
      intake: (day, date) {
        final d = dayAt(day);
        if (d == null) return maintenance;
        return energyOf('${d.dayType.id}/${d.dayType.revision}') ?? maintenance;
      },
      expenditure: (day, m, lean) {
        final r = method.evaluate((
          massKg: m,
          heightCm: e.heightCm,
          fatFreeMassKg: lean,
          age: e.age,
          sex: e.sex,
          category: e.sex == null
              ? null
              : dietCategory(Decimal.parse(round9((m - lean) / m)), e.sex!),
        ));
        if (r['status'] != 'resolved') return null;
        var kcal = double.parse(
          jsonObject(r['value'], 'v')['value']! as String,
        );
        final d = dayAt(day);
        final km = d == null
            ? null
            : walking['${d.dayType.id}/${d.dayType.revision}'];
        if (km != null) kcal += 0.75 * m * km;
        return kcal;
      },
    );
  }

  static (double?, String?) _walkingKm(
    Map<String, Object?> w,
    Profile profile,
  ) {
    if (w.containsKey('distanceKm'))
      return (double.parse(w['distanceKm']! as String), null);
    if (w.containsKey('hours'))
      return (
        double.parse(w['hours']! as String) *
            double.parse(w['speedKmh']! as String),
        null,
      );
    if (profile.stepLength == null)
      return (null, 'A step goal needs the profile step length.');
    return (
      (w['steps']! as int) *
          double.parse(profile.stepLength!.value.toString()) /
          1000,
      null,
    );
  }

  /// Every programme side by side, each with its own choices.
  Future<Map<String, Object?>> compare(
    Map<String, Map<String, Object?>> choices,
    String asOfText, {
    String context = 'health',
    int? simulateDays,
  }) async {
    final unknown = choices.keys.toSet().difference({
      for (final p in dietProgrammes) p.id,
    });
    if (unknown.isNotEmpty)
      invalid('Unknown programmes: ${unknown.join(', ')}.');
    return {
      'policy': 'bodytmi-programme-compare/1',
      'asOf': asOfText,
      'guides': [
        for (final p in dietProgrammes)
          await guide(
            p.id,
            choices[p.id] ?? const {},
            asOfText,
            context: context,
            simulateDays: simulateDays,
          ),
      ],
    };
  }

  /// Publishes the programme's day types (ids `<prefix>-…`) and cycle
  /// `<prefix>` for the category at [asOfText]. Unchanged day types and
  /// cycles are reused; changed ones get a new revision.
  Future<Map<String, Object?>> apply(
    String programmeId,
    Map<String, Object?> choices,
    String asOfText,
    String prefix, {
    String context = 'health',
  }) => repository.transaction(() async {
    identifier({'prefix': prefix}, 'prefix');
    if (prefix.length > 60) invalid('prefix is at most 60 characters.');
    final programme = dietProgramme(programmeId);
    final (:inputs, :frozen) = await DietService(
      repository,
    ).currentInputs(asOfText, context: context);
    final category = jsonObject(frozen['category'], 'category');
    if (category['status'] != 'resolved')
      invalid('The diet category is unavailable: ${category['reason']}');
    final build = programme.build(choices, category['value']! as int, prefix);
    final diets = DietService(repository);
    final revisions = <String, int>{};
    for (final t in build.dayTypes) {
      final head = await _head(() => diets.dayType(t.id));
      revisions[t.id] = (await diets.publishDayType(
        t,
        head?.number ?? 0,
      )).number;
    }
    final cycle = DietCycle.fromJson({
      'id': prefix,
      'name': programme.name,
      'notes': 'Built from programme ${programme.id} (${programme.source}).',
      'loop': build.loop,
      'days': _withRevisions(build.cycleDays, revisions),
    });
    final cycleHead = await _head(() => diets.cycle(prefix));
    final published = await diets.publishCycle(cycle, cycleHead?.number ?? 0);
    return {
      'policy': 'bodytmi-programme-apply/1',
      'programme': programmeId,
      'category': category['value'],
      'choices': choices,
      'schedule': build.schedule,
      'warnings': build.warnings,
      'dayTypes': [
        for (final e in revisions.entries) {'id': e.key, 'revision': e.value},
      ],
      'cycle': {'id': prefix, 'revision': published.number},
    };
  });

  static Future<T?> _head<T>(Future<T> Function() read) async {
    try {
      return await read();
    } on BodyTmiException catch (e) {
      if (e.code == 'not_found') return null;
      rethrow;
    }
  }

  static List<Object?> _withRevisions(
    List<Object?> nodes,
    Map<String, int> revisions,
  ) => [
    for (final n in nodes)
      if ((n! as Map)['type'] == 'day')
        {
          ...(n as Map<String, Object?>),
          'dayType': {'id': n['dayType'], 'revision': revisions[n['dayType']]!},
        }
      else
        {
          ...(n as Map<String, Object?>),
          'days': _withRevisions(n['days']! as List<Object?>, revisions),
        },
  ];

  /// Runs of equal day types: [{dayType, days}].
  static Map<String, Object?> _summary(DietCycle cycle) {
    final runs = <Map<String, Object?>>[];
    for (final d in cycle.days) {
      if (runs.isNotEmpty && runs.last['dayType'] == d.dayType.id) {
        runs.last['days'] = (runs.last['days']! as int) + 1;
      } else {
        runs.add({'dayType': d.dayType.id, 'days': 1});
      }
    }
    return {'loop': cycle.loop, 'length': cycle.days.length, 'runs': runs};
  }
}
