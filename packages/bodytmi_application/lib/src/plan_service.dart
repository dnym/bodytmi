import 'package:bodytmi_core/bodytmi_core.dart';
import 'diet_service.dart';
import 'program_service.dart';
import 'programme_service.dart';
import 'training_repository.dart';

const bodyPlanKind = 'body-plan';
const stepGoalKind = 'step-goal';

/// The body plan (section 4.2): activating a programme or your own cycle
/// as the diet run, with explicitly chosen companion changes (D14), and
/// ending it with explicit undo.
final class PlanService {
  const PlanService(this.repository);
  final TrainingRepository repository;

  Future<List<BodyPlan>> plans() async => [
    for (final r in await repository.dietRecords(kind: bodyPlanKind))
      BodyPlan.fromJson(r.snapshot),
  ]..sort((a, b) => a.startDate.compareTo(b.startDate));

  Future<BodyPlan> plan(String id) async =>
      (await plans()).where((p) => p.id == id).firstOrNull ??
      (throw BodyTmiException('not_found', 'Body plan not found: $id.'));

  Future<List<StepGoalRevision>> stepGoals() async => [
    for (final r in await repository.dietRecords(kind: stepGoalKind))
      StepGoalRevision.fromJson(r.snapshot),
  ]..sort((a, b) => a.number.compareTo(b.number));

  /// Sets (or with null clears) the standalone daily step goal from [from].
  Future<StepGoalRevision> setStepGoal(
    String from,
    int? steps,
    int expectedRevision,
  ) => repository.transaction(() async {
    final all = await stepGoals();
    final head = all.lastOrNull;
    if ((head?.number ?? 0) != expectedRevision)
      throw const BodyTmiException('conflict', 'Step goal changed.');
    final next = StepGoalRevision.publish(from, steps, previous: head);
    await repository.saveDietRecord(
      DietRecord(stepGoalKind, 'daily', next.number, next.toJson()),
    );
    return next;
  });

  /// The step goal on [date]: the active plan's day-type goal when the plan
  /// took over steps, else the standalone goal, else none.
  Future<Map<String, Object?>> stepGoalOnDate(String date) async {
    requireDate(date, 'date');
    for (final p in await plans()) {
      if (!p.covers(date) || !p.stepsCompanion) continue;
      final schedule = await DietService(
        repository,
      ).schedule(date, 1, runId: p.id);
      final day = jsonObject((schedule['days']! as List).single, 'day');
      final steps = day['steps'];
      if (steps != null)
        return {'date': date, 'steps': steps, 'source': 'plan', 'plan': p.id};
    }
    final standalone = stepGoalOn(date, await stepGoals());
    return standalone?.steps == null
        ? {'date': date, 'steps': null, 'source': 'none'}
        : {
            'date': date,
            'steps': standalone!.steps,
            'source': 'standalone',
            'revision': standalone.number,
          };
  }

  /// What activation would do: the guide and the companion changes the
  /// programme suggests, each with what it would replace. Writes nothing.
  Future<Map<String, Object?>> preview({
    String? programme,
    Map<String, Object?> choices = const {},
    String? cycleId,
    int? cycleRevision,
    required String startDate,
    required String asOfText,
    String context = 'health',
  }) => repository.transaction(() async {
    requireDate(startDate, 'startDate');
    final programmes = ProgrammeService(repository);
    final guide = programme != null
        ? await programmes.guide(programme, choices, asOfText, context: context)
        : await programmes.cycleGuide(
            cycleId ?? invalid('Name a programme or a cycle.'),
            cycleRevision ?? invalid('cycleRevision is required.'),
            asOfText,
            startDate: startDate,
            context: context,
          );
    return {
      'policy': 'bodytmi-plan-preview/1',
      'startDate': startDate,
      'guide': guide,
      'companions': await _offers(programme, guide, startDate),
    };
  });

  Future<List<Map<String, Object?>>> _offers(
    String? programme,
    Map<String, Object?> guide,
    String startDate,
  ) async {
    final offers = <Map<String, Object?>>[];
    final withSteps = [
      for (final d
          in (guide['dayTypes'] as List? ?? const [])
              .cast<Map<String, Object?>>())
        if (d['steps'] != null) {'dayType': d['id'], 'steps': d['steps']},
    ];
    if (withSteps.isNotEmpty) {
      final current = stepGoalOn(startDate, await stepGoals());
      offers.add({
        'kind': 'steps',
        'description': 'Use the plan’s daily step goals while it is active.',
        'goals': withSteps,
        'replaces': current?.steps == null
            ? null
            : {'steps': current!.steps, 'revision': current.number},
      });
    }
    if (programme == 'erfl') {
      for (final run in await repository.programRuns()) {
        if (run.status != 'active') continue;
        offers.add({
          'kind': 'pauseRun',
          'runId': run.id,
          'programId': run.program.definition.id,
          'description': 'Pause this training run during the plan.',
          'replaces': {
            'status': 'active',
            'contentVersion': run.contentVersion,
          },
        });
      }
    }
    final recommendation = jsonObject(
      jsonObject(
            guide['programme'] ?? const <String, Object?>{},
            'p',
          )['recommendation'] ??
          const <String, Object?>{},
      'recommendation',
    );
    if (programme == 'rfl')
      offers.add({
        'kind': 'recommendedTraining',
        'description': recommendation['training'],
        'action':
            'Information only: publish and start a matching program yourself.',
      });
    return offers;
  }

  /// Activates a plan: applies the programme (day types and cycle
  /// `<planId>…`) or uses your cycle, starts diet run [planId], and applies
  /// only the companions named ([steps], [pauseRuns]) in one transaction.
  /// Retrying with the same id and request returns the stored plan.
  Future<BodyPlan> activate({
    required String planId,
    String? programme,
    Map<String, Object?> choices = const {},
    String? cycleId,
    int? cycleRevision,
    required String startDate,
    required String asOfText,
    required String requestId,
    bool steps = false,
    List<String> pauseRuns = const [],
    String context = 'health',
  }) => repository.transaction(() async {
    if (planId.length > 80) invalid('planId is at most 80 characters.');
    final existing = (await plans()).where((p) => p.id == planId).firstOrNull;
    if (existing != null) {
      if (existing.json['requestId'] == requestId) return existing;
      throw BodyTmiException('conflict', 'Body plan $planId already exists.');
    }
    if ((programme == null) == (cycleId == null))
      invalid('Name exactly one of programme and cycle.');
    final preview = await this.preview(
      programme: programme,
      choices: choices,
      cycleId: cycleId,
      cycleRevision: cycleRevision,
      startDate: startDate,
      asOfText: asOfText,
      context: context,
    );
    final guide = jsonObject(preview['guide'], 'guide');
    if (programme != null && guide['status'] != 'resolved')
      invalid('The programme guide is unavailable: ${guide['reason']}');
    final offers = (preview['companions']! as List)
        .cast<Map<String, Object?>>();
    if (steps && !offers.any((o) => o['kind'] == 'steps'))
      invalid('This plan offers no step goal.');
    final offeredRuns = {
      for (final o in offers)
        if (o['kind'] == 'pauseRun') o['runId'],
    };
    for (final id in pauseRuns) {
      if (!offeredRuns.contains(id))
        invalid('Run $id is not offered for pausing by this plan.');
    }
    int revision;
    String cycle;
    if (programme != null) {
      final applied = await ProgrammeService(
        repository,
      ).apply(programme, choices, asOfText, planId, context: context);
      cycle = planId;
      revision = jsonObject(applied['cycle'], 'cycle')['revision']! as int;
    } else {
      cycle = cycleId!;
      revision = cycleRevision!;
    }
    await DietService(repository).start(
      runId: planId,
      cycleId: cycle,
      cycleRevision: revision,
      startDate: startDate,
      asOfText: asOfText,
      requestId: requestId,
      context: context,
    );
    final paused = <Map<String, Object?>>[];
    final runs = ProgramService(repository);
    for (final id in pauseRuns.toSet()) {
      final run = await runs.run(id);
      final next = await runs.status(id, run.contentVersion, 'paused');
      paused.add({'runId': id, 'pausedVersion': next.contentVersion});
    }
    final plan = BodyPlan.fromJson({
      'schemaVersion': 1,
      'id': planId,
      'requestId': requestId,
      'programme': programme == null
          ? null
          : {
              'id': programme,
              'choices': choices,
              'category': guide['category'],
            },
      'cycle': {'id': cycle, 'revision': revision},
      'startDate': startDate,
      'companions': {
        'steps': steps,
        'pausedRuns': paused,
        if (offers.any((o) => o['kind'] == 'recommendedTraining'))
          'recommendation': offers.firstWhere(
            (o) => o['kind'] == 'recommendedTraining',
          )['description'],
      },
      'status': 'active',
      'contentVersion': 1,
    });
    await repository.saveDietRecord(
      DietRecord(bodyPlanKind, planId, 1, plan.toJson()),
    );
    return plan;
  });

  /// Ends the plan before [date] and undoes the companions named: resumes
  /// each run in [resumeRuns] the plan paused, unless you changed it since
  /// (then it is left alone and reported). The plan's step goals stop with
  /// it, so the standalone goal applies again.
  Future<BodyPlan> end(
    String planId,
    String date,
    int expectedVersion, {
    List<String> resumeRuns = const [],
    required bool confirm,
  }) => repository.transaction(() async {
    if (!confirm) invalid('Ending a body plan requires confirm:true.');
    final plan = await this.plan(planId);
    if (plan.status != 'active') invalid('The plan has already ended.');
    if (plan.contentVersion != expectedVersion)
      throw const BodyTmiException('conflict', 'Body plan changed.');
    final diets = DietService(repository);
    final run = await diets.run(planId);
    await diets.end(planId, date, run.contentVersion, confirm: true);
    final paused = {for (final p in plan.pausedRuns) p.runId: p.pausedVersion};
    final resumed = <String>[];
    final leftAlone = <Map<String, Object?>>[];
    final runs = ProgramService(repository);
    for (final id in resumeRuns.toSet()) {
      final version = paused[id] ?? invalid('The plan did not pause run $id.');
      final current = await runs.run(id);
      if (current.contentVersion != version || current.status != 'paused') {
        leftAlone.add({
          'runId': id,
          'reason': 'The run was changed after the plan paused it.',
        });
        continue;
      }
      await runs.status(id, current.contentVersion, 'active');
      resumed.add(id);
    }
    final next = BodyPlan.fromJson({
      ...plan.json,
      'status': 'ended',
      'endDate': date,
      'undone': {'resumed': resumed, 'leftAlone': leftAlone},
      'contentVersion': expectedVersion + 1,
    });
    await repository.saveDietRecord(
      DietRecord(bodyPlanKind, planId, 1, next.toJson()),
    );
    return next;
  });
}

/// Every plan names its own diet run with the same id, dates and cycle.
void validateBodyPlans(List<BodyPlan> plans, List<DietRun> runs) {
  final byId = {for (final r in runs) r.id: r};
  for (final p in plans) {
    final run = byId[p.id] ?? invalid('Body plan ${p.id} has no diet run.');
    final cycle = p.json['cycle']! as Map;
    if (run.startDate != p.startDate ||
        run.endDate != p.endDate ||
        run.cycleId != cycle['id'] ||
        run.cycleRevision != cycle['revision'])
      invalid('Body plan ${p.id} does not match its diet run.');
  }
}
