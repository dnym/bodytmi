import 'package:bodytmi_core/bodytmi_core.dart';
import 'derived_plan_session.dart';
import 'session_codec.dart';
import 'canonical_json.dart';
import 'progression_decision.dart';
import 'program_service.dart';
import 'stored_body_mass_service.dart';
import 'timing_service.dart';
import 'execution_service.dart';

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
    List<BodyMassRecord> bodyMass = const [],
    List<TimingActivity> timers = const [],
    List<WorkoutExecution> executions = const [],
    List<FamilyRevision> families = const [],
    List<DerivedTargetGraphRevision> graphs = const [],
  }) : families = List<FamilyRevision>.unmodifiable(
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
      'bodyMass',
      'timers',
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
      progressions: [
        for (final item
            in (!json.containsKey('progressions')
                ? <Object?>[]
                : jsonList(json, 'progressions')))
          ProgressionDecision.fromJson(item),
      ],
    );
  }

  final List<WorkoutExecution> executions;
  final List<FamilyRevision> families;
  final List<DerivedTargetGraphRevision> graphs;
  final List<TimingActivity> timers;
  final List<BodyMassRecord> bodyMass;
  final List<WorkoutRevision> revisions;
  final List<TrainingSession> sessions;
  final List<String> finalizations;
  final List<ProgressionDecision> progressions;
  final List<ProgramRevision> programRevisions;
  final List<ProgramRun> programRuns;
  final List<SessionProgramBinding> sessionPrograms;
  final List<ProgramReceipt> programReceipts;

  Map<String, Object?> toJson() => {
    'families': [for (final f in families) f.toJson()],
    'graphs': [for (final g in graphs) g.toJson()],
    'executions': [for (final e in executions) e.toJson()],
    'timers': [for (final t in timers) t.toJson()],
    'bodyMass': [for (final r in bodyMass) r.toJson()],
    'revisions': [for (final r in revisions) r.toJson()],
    'sessions': [for (final s in sessions) s.toJson()],
    'finalizations': finalizations,
    'progressions': [for (final d in progressions) d.toJson()],
    'programRevisions': [for (final p in programRevisions) p.toJson()],
    'programRuns': [for (final r in programRuns) r.toJson()],
    'sessionPrograms': [for (final b in sessionPrograms) b.toJson()],
    'programReceipts': [for (final r in programReceipts) r.toJson()],
  };

  Map<String, Object?> get summary => {
    'families': families.length,
    'graphs': graphs.length,
    'executions': executions.length,
    'timers': timers.length,
    'bodyMass': bodyMass.length,
    'revisions': revisions.length,
    'sessions': sessions.length,
    'finalizations': finalizations.length,
    'progressions': progressions.length,
    'programRevisions': programRevisions.length,
    'programRuns': programRuns.length,
    'sessionPrograms': sessionPrograms.length,
    'programReceipts': programReceipts.length,
  };

  void _validate() {
    validateFamilyRevisions(families);
    validateDerivedTargetGraphRevisions(graphs);
    validateTimingData(timers, sessions);
    validateExecutionData(executions, sessions, timers);
    if (bodyMass.map((r) => r.measurement.id).toSet().length != bodyMass.length)
      invalid('Duplicate body-mass observation identity.');
    validateBodyMassInputReferences(sessions, bodyMass);
    validateDerivedPlanReferences(sessions, graphs, {
      for (final b in sessionPrograms) b.sessionId: b.runId,
    });
    validateProgramData(
      programs: programRevisions,
      runs: programRuns,
      bindings: sessionPrograms,
      receipts: programReceipts,
      revisions: revisions,
      sessions: sessions,
      finalizations: finalizations,
    );
    validateProgressionDecisions(progressions, sessions, {
      for (final b in sessionPrograms) b.sessionId: b.runId,
    });
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
