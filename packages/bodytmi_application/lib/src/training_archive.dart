import 'package:bodytmi_core/bodytmi_core.dart';
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
    List<BodyMassRecord> bodyMass = const [],
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
       bodyMass = List<BodyMassRecord>.unmodifiable(
         <BodyMassRecord>[...bodyMass]
           ..sort((a, b) => a.measurement.id.compareTo(b.measurement.id)),
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
      'bodyMass',
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
    });
    List<Object?> optional(String key) =>
        json.containsKey(key) ? jsonList(json, key) : const [];
    return TrainingArchive(
      families: [
        for (final f in optional('families')) FamilyRevision.fromJson(f),
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
      bodyMass: [
        for (final j in optional('bodyMass')) BodyMassRecord.fromJson(j),
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
  final List<DerivedTargetGraphRevision> graphs;
  final List<TimingActivity> timers;
  final List<WindowCheckpoint> windowCheckpoints;
  final List<RepeatCheckpoint> repeatCheckpoints;
  final List<BodyMassRecord> bodyMass;
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
    'graphs': [for (final g in graphs) g.toJson()],
    'executions': [for (final e in executions) e.toJson()],
    'timers': [for (final t in timers) t.toJson()],
    'windowCheckpoints': [for (final c in windowCheckpoints) c.toJson()],
    'repeatCheckpoints': [for (final c in repeatCheckpoints) c.toJson()],
    'bodyMass': [for (final r in bodyMass) r.toJson()],
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
    'graphs': graphs.length,
    'executions': executions.length,
    'timers': timers.length,
    'windowCheckpoints': windowCheckpoints.length,
    'repeatCheckpoints': repeatCheckpoints.length,
    'bodyMass': bodyMass.length,
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
    if (bodyMass.map((r) => r.measurement.id).toSet().length != bodyMass.length)
      invalid('Duplicate body-mass observation identity.');
    validateBodyMassInputReferences(sessions, bodyMass);
    validateDerivedPlanReferences(sessions, graphs, {
      for (final b in sessionPrograms) b.sessionId: b.runId,
    }, bodyMass);
    validateProgramData(
      programs: programRevisions,
      runs: programRuns,
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
          byRevision['${session.revision.definition.id}:${session.revision.number}'];
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

/// Whether raw metadata is frozen within a session's body-mass inputs.
bool sessionHasBodyMassMetadata(TrainingSession session) =>
    session.bodyMassInputs.values.any(
      (input) => input.measurements.any((m) => m.hasMetadata),
    ) ||
    (session.derivedPlanInput?.bodyMassSources.values.any(
          (sources) => sources.any((m) => m.hasMetadata),
        ) ??
        false);
