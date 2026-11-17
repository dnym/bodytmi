import 'diet_records.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'blueprint_service.dart';
import 'derived_plan_session.dart';
import 'session_codec.dart';
import 'canonical_json.dart';
import 'progression_anchor.dart';
import 'progression_decision.dart';
import 'reconciliation_receipt.dart';
import 'lever_link.dart';
import 'link_retirement.dart';
import 'shared_lever_application.dart';
import 'program_service.dart';
import 'stored_body_mass_service.dart';
import 'timing_service.dart';
import 'execution_service.dart';
import 'window_checkpoint.dart';
import 'repeat_checkpoint.dart';
import 'history_import_service.dart';
import 'block_progression.dart';
import 'block_progression_service.dart';

/// Full logical representation of the records currently persisted by training.
/// This is a profile replacement contract, not a neutral external-history import.
final class TrainingArchive {
  TrainingArchive({
    required List<WorkoutRevision> revisions,
    required List<TrainingSession> sessions,
    required List<String> finalizations,
    List<ProgressionDecision> progressions = const [],
    List<ProgramRevision> programRevisions = const [],
    List<ProgramRun> programRuns = const [],
    List<SessionProgramBinding> sessionPrograms = const [],
    List<ProgramReceipt> programReceipts = const [],
    List<ProgramUpgradeReceipt> programUpgrades = const [],
    List<ObservationRecord> observations = const [],
    List<MeasureRevision> measures = const [],
    List<SeriesPolicy> seriesPolicies = const [],
    List<ProfileRevision> profile = const [],
    List<BodyFatSourceRevision> bodyFatSources = const [],
    List<DietRecord> dietRecords = const [],
    List<ImportedSessionRecord> importedSessions = const [],
    List<BlockProgressionDecision> blockProgressions = const [],
    List<TimingActivity> timers = const [],
    List<WindowCheckpoint> windowCheckpoints = const [],
    List<RepeatCheckpoint> repeatCheckpoints = const [],
    List<WorkoutExecution> executions = const [],
    List<FamilyRevision> families = const [],
    List<DerivedTargetGraphRevision> graphs = const [],
    List<ReconciliationReceipt> reconciliations = const [],
    List<LeverLinkRevision> links = const [],
    List<SharedLeverApplication> sharedApplications = const [],
    List<LinkRetirementAnchor> linkRetirements = const [],
    List<ExerciseRevision> exercises = const [],
    List<ImplementationRevision> implementations = const [],
    List<ProgressionPresetRevision> presets = const [],
    List<BlueprintRevision> blueprints = const [],
    List<BlueprintInstance> blueprintInstances = const [],
    List<EquipmentRevision> equipment = const [],
    List<GymRevision> gyms = const [],
    List<EquipmentInstanceRevision> instances = const [],
  }) : sharedApplications = List<SharedLeverApplication>.unmodifiable(
         <SharedLeverApplication>[...sharedApplications]..sort((a, b) {
           final id = a.linkId.compareTo(b.linkId);
           return id == 0 ? a.sequence.compareTo(b.sequence) : id;
         }),
       ),
       linkRetirements = List<LinkRetirementAnchor>.unmodifiable(
         <LinkRetirementAnchor>[...linkRetirements]
           ..sort((a, b) => a.id.compareTo(b.id)),
       ),
       links = List<LeverLinkRevision>.unmodifiable(
         <LeverLinkRevision>[...links]..sort((a, b) {
           final id = a.link.id.compareTo(b.link.id);
           return id == 0 ? a.number.compareTo(b.number) : id;
         }),
       ),
       reconciliations = List<ReconciliationReceipt>.unmodifiable(
         <ReconciliationReceipt>[...reconciliations]
           ..sort((a, b) => a.id.compareTo(b.id)),
       ),
       repeatCheckpoints = List<RepeatCheckpoint>.unmodifiable(
         <RepeatCheckpoint>[...repeatCheckpoints]
           ..sort((a, b) => a.id.compareTo(b.id)),
       ),
       windowCheckpoints = List<WindowCheckpoint>.unmodifiable(
         <WindowCheckpoint>[...windowCheckpoints]
           ..sort((a, b) => a.id.compareTo(b.id)),
       ),
       families = List<FamilyRevision>.unmodifiable(
         <FamilyRevision>[...families]..sort((a, b) {
           final id = a.family.id.compareTo(b.family.id);
           return id == 0 ? a.number.compareTo(b.number) : id;
         }),
       ),
       exercises = List<ExerciseRevision>.unmodifiable(
         <ExerciseRevision>[...exercises]..sort((a, b) {
           final id = a.exercise.id.compareTo(b.exercise.id);
           return id == 0 ? a.number.compareTo(b.number) : id;
         }),
       ),
       implementations = List<ImplementationRevision>.unmodifiable(
         <ImplementationRevision>[...implementations]..sort((a, b) {
           final id = a.implementation.id.compareTo(b.implementation.id);
           return id == 0 ? a.number.compareTo(b.number) : id;
         }),
       ),
       presets = List<ProgressionPresetRevision>.unmodifiable(
         <ProgressionPresetRevision>[...presets]..sort((a, b) {
           final id = a.preset.id.compareTo(b.preset.id);
           return id == 0 ? a.number.compareTo(b.number) : id;
         }),
       ),
       blueprints = List<BlueprintRevision>.unmodifiable(
         <BlueprintRevision>[...blueprints]..sort((a, b) {
           final id = a.blueprint.id.compareTo(b.blueprint.id);
           return id == 0 ? a.number.compareTo(b.number) : id;
         }),
       ),
       blueprintInstances = List<BlueprintInstance>.unmodifiable(
         <BlueprintInstance>[...blueprintInstances]..sort((a, b) {
           final id = a.id.compareTo(b.id);
           return id == 0 ? a.number.compareTo(b.number) : id;
         }),
       ),
       equipment = List<EquipmentRevision>.unmodifiable(
         <EquipmentRevision>[...equipment]..sort((a, b) {
           final id = a.equipment.id.compareTo(b.equipment.id);
           return id == 0 ? a.number.compareTo(b.number) : id;
         }),
       ),
       gyms = List<GymRevision>.unmodifiable(
         <GymRevision>[...gyms]..sort((a, b) {
           final id = a.gym.id.compareTo(b.gym.id);
           return id == 0 ? a.number.compareTo(b.number) : id;
         }),
       ),
       instances = List<EquipmentInstanceRevision>.unmodifiable(
         <EquipmentInstanceRevision>[...instances]..sort((a, b) {
           final id = a.instance.id.compareTo(b.instance.id);
           return id == 0 ? a.number.compareTo(b.number) : id;
         }),
       ),
       graphs = List<DerivedTargetGraphRevision>.unmodifiable(
         <DerivedTargetGraphRevision>[...graphs]..sort((a, b) {
           final id = a.graph.id.compareTo(b.graph.id);
           return id == 0 ? a.number.compareTo(b.number) : id;
         }),
       ),
       executions = List<WorkoutExecution>.unmodifiable(
         <WorkoutExecution>[...executions]
           ..sort((a, b) => a.id.compareTo(b.id)),
       ),
       timers = List<TimingActivity>.unmodifiable(
         <TimingActivity>[...timers]..sort((a, b) => a.id.compareTo(b.id)),
       ),
       blockProgressions = List<BlockProgressionDecision>.unmodifiable(
         <BlockProgressionDecision>[...blockProgressions]
           ..sort((a, b) => a.id.compareTo(b.id)),
       ),
       importedSessions = List<ImportedSessionRecord>.unmodifiable(
         <ImportedSessionRecord>[...importedSessions]..sort((a, b) {
           final ns = a.namespace.compareTo(b.namespace);
           return ns == 0 ? a.sourceId.compareTo(b.sourceId) : ns;
         }),
       ),
       profile = List<ProfileRevision>.unmodifiable(
         <ProfileRevision>[...profile]
           ..sort((a, b) => a.number.compareTo(b.number)),
       ),
       dietRecords = List<DietRecord>.unmodifiable(
         <DietRecord>[...dietRecords]..sort((a, b) => a.key.compareTo(b.key)),
       ),
       bodyFatSources = List<BodyFatSourceRevision>.unmodifiable(
         <BodyFatSourceRevision>[...bodyFatSources]
           ..sort((a, b) => a.number.compareTo(b.number)),
       ),
       seriesPolicies = List<SeriesPolicy>.unmodifiable(
         <SeriesPolicy>[...seriesPolicies]..sort((a, b) {
           final key = a.key.compareTo(b.key);
           return key == 0 ? a.number.compareTo(b.number) : key;
         }),
       ),
       measures = List<MeasureRevision>.unmodifiable(
         <MeasureRevision>[...measures]..sort((a, b) {
           final id = a.measure.id.compareTo(b.measure.id);
           return id == 0 ? a.number.compareTo(b.number) : id;
         }),
       ),
       observations = List<ObservationRecord>.unmodifiable(
         <ObservationRecord>[...observations]
           ..sort((a, b) => a.observation.id.compareTo(b.observation.id)),
       ),
       revisions = List<WorkoutRevision>.unmodifiable(
         <WorkoutRevision>[...revisions]..sort((a, b) {
           final id = a.definition.id.compareTo(b.definition.id);
           return id == 0 ? a.number.compareTo(b.number) : id;
         }),
       ),
       sessions = List<TrainingSession>.unmodifiable(
         <TrainingSession>[...sessions]..sort((a, b) => a.id.compareTo(b.id)),
       ),
       finalizations = List<String>.unmodifiable([...finalizations]..sort()),
       progressions = List<ProgressionDecision>.unmodifiable(
         <ProgressionDecision>[...progressions]
           ..sort((a, b) => a.id.compareTo(b.id)),
       ),
       programRevisions = List<ProgramRevision>.unmodifiable(
         <ProgramRevision>[...programRevisions]..sort((a, b) {
           final d = a.definition.id.compareTo(b.definition.id);
           return d == 0 ? a.number.compareTo(b.number) : d;
         }),
       ),
       programRuns = List<ProgramRun>.unmodifiable(
         <ProgramRun>[...programRuns]..sort((a, b) => a.id.compareTo(b.id)),
       ),
       sessionPrograms = List<SessionProgramBinding>.unmodifiable(
         <SessionProgramBinding>[...sessionPrograms]
           ..sort((a, b) => a.sessionId.compareTo(b.sessionId)),
       ),
       programReceipts = List<ProgramReceipt>.unmodifiable(
         <ProgramReceipt>[...programReceipts]..sort((a, b) {
           final d = a.runId.compareTo(b.runId);
           return d == 0 ? a.ordinal.compareTo(b.ordinal) : d;
         }),
       ),
       programUpgrades = List<ProgramUpgradeReceipt>.unmodifiable(
         <ProgramUpgradeReceipt>[...programUpgrades]..sort((a, b) {
           final d = a.runId.compareTo(b.runId);
           if (d != 0) return d;
           final t = a.occurredAt.compareTo(b.occurredAt);
           return t == 0 ? a.requestId.compareTo(b.requestId) : t;
         }),
       ) {
    _validate();
  }

  factory TrainingArchive.fromJson(Object? input) {
    final json = jsonObject(input, 'logical training data');
    checkKeys(json, {
      'revisions',
      'sessions',
      'finalizations',
      'progressions',
      'programRevisions',
      'programRuns',
      'sessionPrograms',
      'programReceipts',
      'programUpgrades',
      'observations',
      'measures',
      'seriesPolicies',
      'profile',
      'bodyFatSources',
      'dietRecords',
      'importedSessions',
      'blockProgressions',
      'timers',
      'windowCheckpoints',
      'repeatCheckpoints',
      'reconciliations',
      'links',
      'sharedApplications',
      'linkRetirements',
      'executions',
      'families',
      'graphs',
      'exercises',
      'implementations',
      'presets',
      'blueprints',
      'blueprintInstances',
      'equipment',
      'gyms',
      'instances',
    });
    List<Object?> optional(String key) =>
        json.containsKey(key) ? jsonList(json, key) : const [];
    return TrainingArchive(
      families: [
        for (final f in optional('families')) FamilyRevision.fromJson(f),
      ],
      exercises: [
        for (final e in optional('exercises')) ExerciseRevision.fromJson(e),
      ],
      implementations: [
        for (final i in optional('implementations'))
          ImplementationRevision.fromJson(i),
      ],
      presets: [
        for (final p in optional('presets'))
          ProgressionPresetRevision.fromJson(p),
      ],
      blueprints: [
        for (final b in optional('blueprints')) BlueprintRevision.fromJson(b),
      ],
      blueprintInstances: [
        for (final b in optional('blueprintInstances'))
          BlueprintInstance.fromJson(b),
      ],
      equipment: [
        for (final e in optional('equipment')) EquipmentRevision.fromJson(e),
      ],
      gyms: [for (final g in optional('gyms')) GymRevision.fromJson(g)],
      instances: [
        for (final i in optional('instances'))
          EquipmentInstanceRevision.fromJson(i),
      ],
      graphs: [
        for (final g in optional('graphs'))
          DerivedTargetGraphRevision.fromJson(g),
      ],
      revisions: [
        for (final item in jsonList(json, 'revisions'))
          WorkoutRevision.fromJson(item),
      ],
      sessions: [
        for (final item in jsonList(json, 'sessions')) sessionFromJson(item),
      ],
      finalizations: [
        for (final item in jsonList(json, 'finalizations'))
          identifier({'id': item}, 'id'),
      ],
      executions: [
        for (final e in optional('executions')) WorkoutExecution.fromJson(e),
      ],
      timers: [for (final t in optional('timers')) TimingActivity.fromJson(t)],
      repeatCheckpoints: [
        for (final c in optional('repeatCheckpoints'))
          RepeatCheckpoint.fromJson(c),
      ],
      windowCheckpoints: [
        for (final c in optional('windowCheckpoints'))
          WindowCheckpoint.fromJson(c),
      ],
      blockProgressions: [
        for (final j in optional('blockProgressions'))
          BlockProgressionDecision.fromJson(j),
      ],
      importedSessions: [
        for (final j in optional('importedSessions'))
          ImportedSessionRecord.fromJson(j),
      ],
      measures: [
        for (final j in optional('measures')) MeasureRevision.fromJson(j),
      ],
      seriesPolicies: [
        for (final j in optional('seriesPolicies')) SeriesPolicy.fromJson(j),
      ],
      profile: [
        for (final j in optional('profile')) ProfileRevision.fromJson(j),
      ],
      bodyFatSources: [
        for (final j in optional('bodyFatSources'))
          BodyFatSourceRevision.fromJson(j),
      ],
      dietRecords: [
        for (final j in optional('dietRecords')) DietRecord.fromJson(j),
      ],
      observations: [
        for (final j in optional('observations')) ObservationRecord.fromJson(j),
      ],
      programRevisions: [
        for (final j in optional('programRevisions'))
          ProgramRevision.fromJson(j),
      ],
      programRuns: [
        for (final j in optional('programRuns')) ProgramRun.fromJson(j),
      ],
      sessionPrograms: [
        for (final j in optional('sessionPrograms'))
          SessionProgramBinding.fromJson(j),
      ],
      programReceipts: [
        for (final j in optional('programReceipts')) ProgramReceipt.fromJson(j),
      ],
      programUpgrades: [
        for (final j in optional('programUpgrades'))
          ProgramUpgradeReceipt.fromJson(j),
      ],
      progressions: [
        for (final item
            in (!json.containsKey('progressions')
                ? <Object?>[]
                : jsonList(json, 'progressions')))
          ProgressionDecision.fromJson(item),
      ],
      reconciliations: [
        for (final item in optional('reconciliations'))
          ReconciliationReceipt.fromJson(item),
      ],
      links: [
        for (final item in optional('links')) LeverLinkRevision.fromJson(item),
      ],
      sharedApplications: [
        for (final item in optional('sharedApplications'))
          SharedLeverApplication.fromJson(item),
      ],
      linkRetirements: [
        for (final item in optional('linkRetirements'))
          LinkRetirementAnchor.fromJson(item),
      ],
    );
  }

  final List<WorkoutExecution> executions;
  final List<FamilyRevision> families;
  final List<ExerciseRevision> exercises;
  final List<ImplementationRevision> implementations;
  final List<ProgressionPresetRevision> presets;
  final List<BlueprintRevision> blueprints;
  final List<BlueprintInstance> blueprintInstances;
  final List<EquipmentRevision> equipment;
  final List<GymRevision> gyms;
  final List<EquipmentInstanceRevision> instances;
  final List<DerivedTargetGraphRevision> graphs;
  final List<TimingActivity> timers;
  final List<WindowCheckpoint> windowCheckpoints;
  final List<RepeatCheckpoint> repeatCheckpoints;

  final List<MeasureRevision> measures;
  final List<SeriesPolicy> seriesPolicies;
  final List<ProfileRevision> profile;
  final List<BodyFatSourceRevision> bodyFatSources;
  final List<DietRecord> dietRecords;

  /// Observations of every measure, body mass included.
  final List<ObservationRecord> observations;

  /// The body-mass observations as body-mass records.
  late final List<BodyMassRecord> bodyMass = [
    for (final r in observations)
      if (r.observation.isBodyMass)
        BodyMassRecord(r.observation.toBodyMass(), deleted: r.deleted),
  ];
  final List<ImportedSessionRecord> importedSessions;
  final List<BlockProgressionDecision> blockProgressions;
  final List<WorkoutRevision> revisions;
  final List<TrainingSession> sessions;
  final List<String> finalizations;
  final List<ProgressionDecision> progressions;
  final List<ReconciliationReceipt> reconciliations;
  final List<LeverLinkRevision> links;
  final List<SharedLeverApplication> sharedApplications;
  final List<LinkRetirementAnchor> linkRetirements;
  final List<ProgramRevision> programRevisions;
  final List<ProgramRun> programRuns;
  final List<SessionProgramBinding> sessionPrograms;
  final List<ProgramReceipt> programReceipts;
  final List<ProgramUpgradeReceipt> programUpgrades;

  Map<String, Object?> toJson() => {
    'families': [for (final f in families) f.toJson()],
    'exercises': [for (final e in exercises) e.toJson()],
    'implementations': [for (final i in implementations) i.toJson()],
    'presets': [for (final p in presets) p.toJson()],
    'blueprints': [for (final b in blueprints) b.toJson()],
    'blueprintInstances': [for (final b in blueprintInstances) b.toJson()],
    'equipment': [for (final e in equipment) e.toJson()],
    'gyms': [for (final g in gyms) g.toJson()],
    'instances': [for (final i in instances) i.toJson()],
    'graphs': [for (final g in graphs) g.toJson()],
    'executions': [for (final e in executions) e.toJson()],
    'timers': [for (final t in timers) t.toJson()],
    'windowCheckpoints': [for (final c in windowCheckpoints) c.toJson()],
    'repeatCheckpoints': [for (final c in repeatCheckpoints) c.toJson()],
    'observations': [for (final r in observations) r.toJson()],
    'measures': [for (final m in measures) m.toJson()],
    'seriesPolicies': [for (final p in seriesPolicies) p.toJson()],
    'profile': [for (final p in profile) p.toJson()],
    'bodyFatSources': [for (final s in bodyFatSources) s.toJson()],
    'dietRecords': [for (final r in dietRecords) r.toJson()],
    'importedSessions': [for (final r in importedSessions) r.toJson()],
    'blockProgressions': [for (final d in blockProgressions) d.toJson()],
    'revisions': [for (final r in revisions) r.toJson()],
    'sessions': [for (final s in sessions) s.toJson()],
    'finalizations': finalizations,
    'progressions': [for (final d in progressions) d.toJson()],
    'reconciliations': [for (final r in reconciliations) r.toJson()],
    'links': [for (final l in links) l.toJson()],
    'sharedApplications': [for (final a in sharedApplications) a.toJson()],
    'linkRetirements': [for (final r in linkRetirements) r.toJson()],
    'programRevisions': [for (final p in programRevisions) p.toJson()],
    'programRuns': [for (final r in programRuns) r.toJson()],
    'sessionPrograms': [for (final b in sessionPrograms) b.toJson()],
    'programReceipts': [for (final r in programReceipts) r.toJson()],
    'programUpgrades': [for (final u in programUpgrades) u.toJson()],
  };

  Map<String, Object?> get summary => {
    'families': families.length,
    'exercises': exercises.length,
    'implementations': implementations.length,
    'presets': presets.length,
    'blueprints': blueprints.length,
    'blueprintInstances': blueprintInstances.length,
    'equipment': equipment.length,
    'gyms': gyms.length,
    'instances': instances.length,
    'graphs': graphs.length,
    'executions': executions.length,
    'timers': timers.length,
    'windowCheckpoints': windowCheckpoints.length,
    'repeatCheckpoints': repeatCheckpoints.length,
    'observations': observations.length,
    'measures': measures.length,
    'seriesPolicies': seriesPolicies.length,
    'profile': profile.length,
    'bodyFatSources': bodyFatSources.length,
    'dietRecords': dietRecords.length,
    'importedSessions': importedSessions.length,
    'blockProgressions': blockProgressions.length,
    'revisions': revisions.length,
    'sessions': sessions.length,
    'finalizations': finalizations.length,
    'progressions': progressions.length,
    'reconciliations': reconciliations.length,
    'links': links.length,
    'sharedApplications': sharedApplications.length,
    'linkRetirements': linkRetirements.length,
    'programRevisions': programRevisions.length,
    'programRuns': programRuns.length,
    'sessionPrograms': sessionPrograms.length,
    'programReceipts': programReceipts.length,
    'programUpgrades': programUpgrades.length,
  };

  void _validate() {
    if (repeatCheckpoints.map((c) => c.id).toSet().length !=
        repeatCheckpoints.length)
      invalid('Duplicate repeat checkpoint identity.');
    validateRepeatClockReservations(
      repeatCheckpoints,
      timers: timers,
      windows: windowCheckpoints,
    );
    validateRepeatSessionBindings(repeatCheckpoints, sessions);
    validateFamilyRevisions(families);
    validateExerciseRevisions(exercises);
    validateImplementationRevisions(implementations, exercises);
    validateProgressionPresetRevisions(presets);
    validatePresetProvenance(progressions, presets);
    validateBlueprintInstances(blueprintInstances, blueprints);
    validateBlueprintLineage(
      blueprintInstances,
      workouts: revisions,
      programs: programRevisions,
      presets: presets,
      equipmentInstances: instances,
    );
    final catalogOwners = implementationOwners(implementations);
    for (final revision in revisions)
      validateCatalogSlotAdoption(revision.definition.slots, catalogOwners);
    validateEquipmentRevisions(equipment);
    validateGymRevisions(gyms);
    validateEquipmentInstanceRevisions(instances, equipment, gyms);
    validateLoadInputReferences(sessions, instances, gyms);
    validateDerivedTargetGraphRevisions(graphs);
    validateProgramPlanReferences(programRevisions, graphs);
    validateTimingData(timers, sessions);
    validateWindowCheckpoints(
      windowCheckpoints,
      sessions,
      timers: timers,
      executions: executions,
    );
    validateExecutionData(executions, sessions, timers);
    validatePlacementCheckpoints(executions, sessions, repeatCheckpoints);
    validateMeasureRevisions(measures);
    validateObservationRecords(
      observations,
      measures: currentMeasures(measures),
    );
    validateSeriesPolicies(seriesPolicies, currentMeasures(measures));
    validateNumbered([for (final p in profile) p.number], 'Profile');
    validateNumbered([
      for (final s in bodyFatSources) s.number,
    ], 'Body-fat source');
    validateDietRecords(dietRecords);
    validateImportedSessions(importedSessions);
    validateBlockProgressions(
      blockProgressions,
      repeatCheckpoints,
      sessions,
      sessionPrograms,
    );
    validateBodyMassInputReferences(sessions, bodyMass);
    validateDerivedPlanReferences(sessions, graphs, {
      for (final b in sessionPrograms) b.sessionId: b.runId,
    }, bodyMass);
    {
      final gymIds = {for (final g in gyms) g.gym.id};
      for (final run in programRuns) {
        if (run.gymId != null && !gymIds.contains(run.gymId))
          invalid('Run ${run.id} names an unpublished default gym.');
      }
    }
    validateProgramData(
      programs: programRevisions,
      runs: programRuns,
      upgrades: programUpgrades,
      bindings: sessionPrograms,
      receipts: programReceipts,
      revisions: revisions,
      sessions: sessions,
      finalizations: finalizations,
    );
    validateProgramUpgrades(programRevisions, programRuns, programUpgrades);
    validateLinkRetirements(
      linkRetirements,
      links,
      sharedApplications,
      progressions,
      reconciliations,
    );
    final linkAnchors = <String, ProgressionAnchor>{
      for (final anchor in <ProgressionAnchor>[
        ...progressions,
        ...reconciliations,
        ...linkRetirements,
      ])
        if (anchor.resolvedAt != null) anchor.id: anchor,
    };
    validateSharedLeverApplications(sharedApplications, links, linkAnchors);
    final linkIndex = SharedLinkIndex(
      revisions: links,
      applications: sharedApplications,
      retirements: linkRetirements,
      anchors: linkAnchors,
    );
    validateProgressionReconciliations(
      reconciliations,
      progressions,
      revisions,
      sessions,
      linkRetirements,
      linkIndex,
    );
    validateLeverLinkRevisions(links, linkRetirements);
    validateLeverLinks(links, progressions, reconciliations, linkRetirements);
    validateProgressionDecisions(
      progressions,
      sessions,
      {for (final b in sessionPrograms) b.sessionId: b.runId},
      [...reconciliations, ...linkRetirements],
      linkIndex,
    );
    final byRevision = <String, WorkoutRevision>{};
    final numbers = <String, int>{};
    for (final revision in revisions) {
      final id = revision.definition.id;
      final expected = (numbers[id] ?? 0) + 1;
      if (revision.number != expected)
        invalid('Logical revisions must be unique and contiguous from 1.');
      numbers[id] = expected;
      byRevision['$id:${revision.number}'] = revision;
    }
    for (final graph in graphs) {
      for (final plan in graph.graph.plans) {
        final workout = byRevision['${plan.templateId}:${plan.revision}'];
        if (workout == null)
          invalid(
            'Derived workout plan references a missing workout revision.',
          );
        plan.validate(workout, graph.graph.nodes);
      }
    }
    final bySession = <String, TrainingSession>{};
    for (final session in sessions) {
      if (bySession.containsKey(session.id))
        invalid('Duplicate logical session identity.');
      bySession[session.id] = session;
      final revision =
          byRevision['${session.definition.id}:${session.revision.number}'];
      if (revision == null ||
          canonicalJson(revision.toJson()) !=
              canonicalJson(session.revision.toJson())) {
        invalid(
          'Logical session prescription does not match its published revision.',
        );
      }
    }
    final receipts = finalizations.toSet();
    if (receipts.length != finalizations.length ||
        receipts.any((id) => !bySession.containsKey(id))) {
      invalid('Duplicate or orphan logical finalization identity.');
    }
    for (final session in sessions) {
      if (session.status == SessionStatus.finalized &&
          !receipts.contains(session.id)) {
        invalid(
          'Finalized logical session lacks its stable finalization identity.',
        );
      }
      for (final set in session.sets) {
        for (final source in set.sources.values) {
          final past = bySession[source.sessionId];
          final matches = past?.sets.where((s) => s.id == source.setId);
          if (matches == null ||
              matches.isEmpty ||
              matches.single.contentVersion < source.contentVersion) {
            invalid(
              'Logical history source session, set or version is invalid.',
            );
          }
        }
      }
    }
  }
}

/// A frozen session instance reference must exist as the corresponding
/// published instance revision with exactly the same snapshot content, and a
/// session's gym must be a published gym.
void validateLoadInputReferences(
  List<TrainingSession> sessions,
  List<EquipmentInstanceRevision> instances,
  List<GymRevision> gyms,
) {
  final published = {
    for (final r in instances) '${r.instance.id}\u0000${r.number}': r,
  };
  final gymIds = {for (final r in gyms) r.gym.id};
  for (final session in sessions) {
    if (session.gymId != null && !gymIds.contains(session.gymId))
      invalid('Session ${session.id} names an unpublished gym.');
    for (final reference in [
      for (final entry in session.loadInputs.entries) entry.value.instance,
      for (final set in session.sets) set.performedOn,
    ]) {
      if (reference == null) continue;
      final row =
          published['${reference.instanceId}\u0000${reference.revision}'];
      if (row == null ||
          canonicalJson(row.instance.toJson()) !=
              canonicalJson(reference.snapshot.toJson()))
        invalid(
          'Session load input instance reference, revision or snapshot '
          'is inconsistent.',
        );
    }
  }
}

/// Corrected/deleted current records may differ from their historical snapshots.
/// Equal versions must still identify exactly the same source content.
void validateBodyMassInputReferences(
  List<TrainingSession> sessions,
  List<BodyMassRecord> records,
) {
  final byId = {for (final r in records) r.measurement.id: r};
  for (final session in sessions) {
    for (final override
        in session.initialBodyMassOverrides?.values ?? <BodyMassOverride>[]) {
      if (override.measurementId != null &&
          !byId.containsKey(override.measurementId))
        invalid('Original body-mass override measurement is missing.');
    }
  }
  for (final s in sessions)
    for (final binding in s.bodyMassInputs.values)
      for (final m in binding.measurements) {
        final current = byId[m.id];
        if (current == null ||
            current.measurement.contentVersion < m.contentVersion ||
            (current.measurement.contentVersion == m.contentVersion &&
                (current.deleted ||
                    canonicalJson(current.measurement.toJson()) !=
                        canonicalJson(m.toJson()))))
          invalid(
            'Session body-mass source identity, content or version is inconsistent.',
          );
      }
}
