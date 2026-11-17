import 'package:bodytmi_core/bodytmi_core.dart';
import 'canonical_json.dart';
import 'energy_service.dart';
import 'training_repository.dart';

const dayTypeKind = 'day-type';
const dietCycleKind = 'diet-cycle';
const dietRunKind = 'diet-run';

/// Day types, diet cycles and calendar diet runs (D20, F21).
final class DietService {
  const DietService(this.repository);
  final TrainingRepository repository;

  Future<List<DayTypeRevision>> dayTypes() async => [
    for (final r in await repository.dietRecords(kind: dayTypeKind))
      DayTypeRevision.fromJson(r.snapshot),
  ];

  Future<DayTypeRevision> dayType(String id, [int? revision]) async {
    final all = [
      for (final r in await dayTypes())
        if (r.dayType.id == id && (revision == null || r.number == revision)) r,
    ]..sort((a, b) => b.number.compareTo(a.number));
    return all.firstOrNull ??
        (throw BodyTmiException('not_found', 'Day type not found: $id.'));
  }

  Future<DayTypeRevision> publishDayType(
    DayType dayType,
    int expectedRevision,
  ) => repository.transaction(() async {
    final head =
        ((await dayTypes()).where((r) => r.dayType.id == dayType.id).toList()
              ..sort((a, b) => b.number.compareTo(a.number)))
            .firstOrNull;
    if ((head?.number ?? 0) != expectedRevision)
      throw const BodyTmiException('conflict', 'Day type revision changed.');
    if (head != null &&
        canonicalJson(head.dayType.toJson()) == canonicalJson(dayType.toJson()))
      return head;
    final next = DayTypeRevision.publish(dayType, previous: head);
    await repository.saveDietRecord(
      DietRecord(dayTypeKind, dayType.id, next.number, next.toJson()),
    );
    return next;
  });

  Future<List<DietCycleRevision>> cycles() async => [
    for (final r in await repository.dietRecords(kind: dietCycleKind))
      DietCycleRevision.fromJson(r.snapshot),
  ];

  Future<DietCycleRevision> cycle(String id, [int? revision]) async {
    final all = [
      for (final r in await cycles())
        if (r.cycle.id == id && (revision == null || r.number == revision)) r,
    ]..sort((a, b) => b.number.compareTo(a.number));
    return all.firstOrNull ??
        (throw BodyTmiException('not_found', 'Diet cycle not found: $id.'));
  }

  Future<DietCycleRevision> publishCycle(
    DietCycle cycle,
    int expectedRevision,
  ) => repository.transaction(() async {
    final head =
        ((await cycles()).where((r) => r.cycle.id == cycle.id).toList()
              ..sort((a, b) => b.number.compareTo(a.number)))
            .firstOrNull;
    if ((head?.number ?? 0) != expectedRevision)
      throw const BodyTmiException('conflict', 'Diet cycle revision changed.');
    if (head != null &&
        canonicalJson(head.cycle.toJson()) == canonicalJson(cycle.toJson()))
      return head;
    for (final ref in cycle.dayTypes) {
      await dayType(ref.id, ref.revision);
    }
    final next = DietCycleRevision.publish(cycle, previous: head);
    await repository.saveDietRecord(
      DietRecord(dietCycleKind, cycle.id, next.number, next.toJson()),
    );
    return next;
  });

  /// Current inputs at [asOfText]: maintenance by the method in force (or
  /// [method]), trend mass and fat-free mass from the body report.
  Future<({DietInputs inputs, Map<String, Object?> frozen})> currentInputs(
    String asOfText, {
    String context = 'health',
    MaintenanceMethod? method,
  }) async {
    final estimate = await EnergyService(
      repository,
    ).estimate(asOfText, context: context, method: method);
    final shown = jsonObject(estimate['inputs'], 'inputs');
    final maintenance = jsonObject(estimate['maintenance'], 'maintenance');
    Map<String, Object?>? kg(Map<String, Object?> r) {
      if (r['status'] != 'resolved') return null;
      final q = Quantity.fromJson(r['value']);
      return {...r, 'value': q.value.toString(), 'unit': 'kg'};
    }

    final mass = kg(jsonObject(shown['mass'], 'mass'));
    final ffm = kg(jsonObject(shown['fatFreeMass'], 'fatFreeMass'));
    final energy = maintenance['status'] == 'resolved'
        ? {
            'value': jsonObject(maintenance['value'], 'value')['value'],
            'unit': 'kcal',
            'formula': maintenance['formula'],
            'method': maintenance['method'],
          }
        : null;
    double? v(Map<String, Object?>? x) =>
        x == null ? null : double.parse(x['value']! as String);
    return (
      inputs: (
        maintenanceKcal: v(energy),
        massKg: v(mass),
        fatFreeMassKg: v(ffm),
      ),
      frozen: <String, Object?>{
        'asOf': asOfText,
        'context': context,
        'maintenance': energy,
        'mass': mass,
        'fatFreeMass': ffm,
        'bodyFat': shown['bodyFat'],
        'category': shown['category'],
        if (maintenance['status'] != 'resolved')
          'maintenanceReason': maintenance['reason'],
      },
    );
  }

  /// A day type's goals from current inputs (read-only preview).
  Future<Map<String, Object?>> resolveDayType(
    String id,
    String asOfText, {
    int? revision,
    String context = 'health',
    MaintenanceMethod? method,
  }) => repository.transaction(() async {
    final r = await dayType(id, revision);
    final (:inputs, :frozen) = await currentInputs(
      asOfText,
      context: context,
      method: method,
    );
    return {
      'policy': 'bodytmi-day-type-goals/1',
      'dayType': {'id': id, 'revision': r.number, 'name': r.dayType.name},
      'inputs': frozen,
      'goals': r.dayType.resolve(inputs),
      'steps': ?r.dayType.json['steps'],
    };
  });

  Future<List<DietRun>> runs() async => [
    for (final r in await repository.dietRecords(kind: dietRunKind))
      DietRun.fromJson(r.snapshot),
  ]..sort((a, b) => a.startDate.compareTo(b.startDate));

  Future<DietRun> run(String id) async =>
      (await runs()).where((r) => r.id == id).firstOrNull ??
      (throw BodyTmiException('not_found', 'Diet run not found: $id.'));

  Future<Map<String, Object?>> _targets(
    Iterable<DayTypeRef> refs,
    DietInputs inputs,
  ) async {
    final targets = <String, Object?>{};
    for (final ref in refs) {
      final key = '${ref.id}/${ref.revision}';
      if (targets.containsKey(key)) continue;
      final goals = (await dayType(
        ref.id,
        ref.revision,
      )).dayType.resolve(inputs);
      final unavailable = [
        for (final e in goals.entries)
          if ((e.value! as Map)['status'] != 'resolved')
            '${e.key} (${(e.value! as Map)['reason']})',
      ];
      if (unavailable.isNotEmpty)
        invalid('Day type $key cannot be resolved: ${unavailable.join('; ')}');
      targets[key] = goals;
    }
    return targets;
  }

  /// Starts [cycleId] on [startDate], freezing inputs at [asOfText] and
  /// the targets of every day type the cycle uses. One run at a time: a
  /// run still open on [startDate] must be ended first. Retrying with the
  /// same id and request returns the stored run.
  Future<DietRun> start({
    required String runId,
    required String cycleId,
    required int cycleRevision,
    required String startDate,
    required String asOfText,
    required String requestId,
    String context = 'health',
  }) => repository.transaction(() async {
    requireDate(startDate, 'startDate');
    parseInstant(asOfText, 'asOf');
    final existing = (await runs()).where((r) => r.id == runId).firstOrNull;
    if (existing != null) {
      if (existing.json['requestId'] == requestId &&
          existing.cycleId == cycleId &&
          existing.cycleRevision == cycleRevision &&
          existing.startDate == startDate)
        return existing;
      throw BodyTmiException('conflict', 'Diet run $runId already exists.');
    }
    for (final other in await runs()) {
      if (other.endDate == null || other.endDate!.compareTo(startDate) > 0)
        throw BodyTmiException(
          'conflict',
          'Diet run ${other.id} is still open on $startDate; end it first.',
        );
    }
    final cycle = (await this.cycle(cycleId, cycleRevision)).cycle;
    final (:inputs, :frozen) = await currentInputs(asOfText, context: context);
    final run = DietRun.fromJson({
      'schemaVersion': 1,
      'id': runId,
      'cycle': {'id': cycleId, 'revision': cycleRevision},
      'startDate': startDate,
      'requestId': requestId,
      'inputs': frozen,
      'targets': await _targets(cycle.dayTypes, inputs),
      'overrides': const <Object?>[],
      'contentVersion': 1,
    });
    await repository.saveDietRecord(
      DietRecord(dietRunKind, runId, 1, run.toJson()),
    );
    return run;
  });

  Future<DietRun> _update(
    String runId,
    int expectedVersion,
    Future<Map<String, Object?>> Function(DietRun run, DietCycle cycle) change,
  ) => repository.transaction(() async {
    final current = await run(runId);
    if (current.contentVersion != expectedVersion)
      throw const BodyTmiException('conflict', 'Diet run changed.');
    final cycle = (await this.cycle(
      current.cycleId,
      current.cycleRevision,
    )).cycle;
    final next = current.copyWith({
      ...await change(current, cycle),
      'contentVersion': expectedVersion + 1,
    });
    await repository.saveDietRecord(
      DietRecord(dietRunKind, runId, 1, next.toJson()),
    );
    return next;
  });

  Future<Map<String, Object?>> _withOverrides(
    DietRun run,
    List<DietOverride> overrides,
  ) async {
    final targets = {
      ...run.targets,
      ...await _targets([
        for (final o in overrides)
          if (!run.targets.containsKey('${o.dayType.id}/${o.dayType.revision}'))
            o.dayType,
      ], run.frozenInputs),
    };
    return {
      'overrides': [
        for (final o in [
          ...overrides,
        ]..sort((a, b) => a.date.compareTo(b.date)))
          {
            'date': o.date,
            'dayType': dayTypeRefToJson(o.dayType),
            'reason': o.reason,
          },
      ],
      'targets': targets,
    };
  }

  /// Replaces one date's day type ([dayType] null removes the override).
  /// Later dates keep their cycle day types.
  Future<DietRun> override(
    String runId,
    String date,
    DayTypeRef? dayType,
    String reason,
    int expectedVersion,
  ) => _update(runId, expectedVersion, (run, cycle) async {
    requireDate(date, 'date');
    if (!run.covers(date)) invalid('The run does not cover $date.');
    final rest = [
      for (final o in run.overrides)
        if (o.date != date) o,
    ];
    if (dayType == null) {
      if (rest.length == run.overrides.length)
        invalid('There is no override on $date.');
      return _withOverrides(run, rest);
    }
    await this.dayType(dayType.id, dayType.revision);
    return _withOverrides(run, [
      ...rest,
      (date: date, dayType: dayType, reason: reason),
    ]);
  });

  /// Swaps the day types prescribed on two dates (e.g. a maintenance day
  /// moved to Saturday), as two overrides; nothing else moves.
  Future<DietRun> move(
    String runId,
    String from,
    String to,
    String reason,
    int expectedVersion,
  ) => _update(runId, expectedVersion, (run, cycle) async {
    requireDate(from, 'from');
    requireDate(to, 'to');
    if (from == to) invalid('from and to differ.');
    final a = dietDayOn(run, cycle, from), b = dietDayOn(run, cycle, to);
    if (a == null || b == null) invalid('Both dates must be days of the run.');
    final rest = [
      for (final o in run.overrides)
        if (o.date != from && o.date != to) o,
    ];
    return _withOverrides(run, [
      ...rest,
      (date: from, dayType: b.dayType, reason: reason),
      (date: to, dayType: a.dayType, reason: reason),
    ]);
  });

  /// Ends the run before [date] (exclusive); requires confirm.
  Future<DietRun> end(
    String runId,
    String date,
    int expectedVersion, {
    required bool confirm,
  }) => _update(runId, expectedVersion, (run, cycle) async {
    if (!confirm) invalid('Ending a diet run requires confirm:true.');
    requireDate(date, 'date');
    if (run.endDate != null) invalid('The run has already ended.');
    if (date.compareTo(run.startDate) <= 0)
      invalid('A run ends after its start date.');
    if (run.overrides.any((o) => o.date.compareTo(date) >= 0))
      invalid('Remove overrides on or after $date first.');
    return {'endDate': date};
  });

  /// Policy bodytmi-diet-schedule/1: [days] dates from [from], each with
  /// the run covering it (or [runId] only), its day type, whether it comes
  /// from the cycle or an override, and the frozen goals.
  Future<Map<String, Object?>> schedule(
    String from,
    int days, {
    String? runId,
  }) => repository.transaction(() async {
    requireDate(from, 'from');
    if (days < 1 || days > 366) invalid('days is from 1 to 366.');
    final all = runId == null ? await runs() : [await run(runId)];
    final cycles = <String, DietCycle>{};
    final names = <String, DayTypeRevision>{};
    final out = <Map<String, Object?>>[];
    for (var i = 0; i < days; i++) {
      final date = addDays(from, i);
      final run = all.where((r) => r.covers(date)).firstOrNull;
      if (run == null) {
        out.add({'date': date, 'run': null});
        continue;
      }
      final cycle = cycles['${run.cycleId}/${run.cycleRevision}'] ??=
          (await this.cycle(run.cycleId, run.cycleRevision)).cycle;
      final day = dietDayOn(run, cycle, date);
      if (day == null) {
        out.add({
          'date': date,
          'run': run.id,
          'dayType': null,
          'reason': 'The finite cycle has ended.',
        });
        continue;
      }
      final key = '${day.dayType.id}/${day.dayType.revision}';
      final type = names[key] ??= await dayType(
        day.dayType.id,
        day.dayType.revision,
      );
      out.add({
        'date': date,
        'run': run.id,
        'dayType': {
          ...dayTypeRefToJson(day.dayType),
          'name': type.dayType.name,
        },
        'source': day.source,
        if (day.reason != null) 'reason': day.reason,
        if (day.index != null) 'cycleDay': day.index! + 1,
        if (day.day?.label != null) 'label': day.day!.label,
        if (day.day != null && day.day!.path.isNotEmpty) 'path': day.day!.path,
        'goals': run.targets[key],
        'steps': ?type.dayType.json['steps'],
        'notes': ?type.dayType.json['notes'],
      });
    }
    return {'policy': 'bodytmi-diet-schedule/1', 'from': from, 'days': out};
  });
}

/// Cross-record checks for archives: cycles pin published day types, runs
/// pin published cycles and day types, frozen targets recompute from their
/// frozen inputs, and runs never overlap.
void validateDietReferences(
  List<DayTypeRevision> dayTypes,
  List<DietCycleRevision> cycles,
  List<DietRun> runs,
) {
  final types = {for (final t in dayTypes) t.key: t};
  final cycleKeys = {
    for (final c in cycles) '${c.cycle.id}/${c.number}': c.cycle,
  };
  for (final c in cycles) {
    for (final ref in c.cycle.dayTypes) {
      if (!types.containsKey('${ref.id}/${ref.revision}'))
        invalid('Diet cycle ${c.cycle.id} pins an unpublished day type.');
    }
  }
  final sorted = [...runs]..sort((a, b) => a.startDate.compareTo(b.startDate));
  for (var i = 0; i < sorted.length; i++) {
    final run = sorted[i];
    final cycle =
        cycleKeys['${run.cycleId}/${run.cycleRevision}'] ??
        invalid('Diet run ${run.id} pins an unpublished cycle.');
    final refs = {...cycle.dayTypes, for (final o in run.overrides) o.dayType};
    final keys = {for (final r in refs) '${r.id}/${r.revision}'};
    if (keys.length != run.targets.length ||
        !keys.every(run.targets.containsKey))
      invalid('Diet run ${run.id} targets do not match its day types.');
    for (final ref in refs) {
      final key = '${ref.id}/${ref.revision}';
      final type =
          types[key] ??
          invalid('Diet run ${run.id} uses an unpublished day type.');
      if (canonicalJson(type.dayType.resolve(run.frozenInputs)) !=
          canonicalJson(run.targets[key]))
        invalid('Diet run ${run.id} targets do not match its frozen inputs.');
    }
    if (run.endDate != null &&
        run.overrides.any((o) => o.date.compareTo(run.endDate!) >= 0))
      invalid('Diet run ${run.id} has overrides after its end.');
    if (i > 0) {
      final previous = sorted[i - 1];
      if (previous.endDate == null ||
          previous.endDate!.compareTo(run.startDate) > 0)
        invalid('Diet runs ${previous.id} and ${run.id} overlap.');
    }
  }
}
