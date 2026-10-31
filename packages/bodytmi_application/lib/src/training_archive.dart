import 'package:bodytmi_core/bodytmi_core.dart';
import 'session_codec.dart';
import 'canonical_json.dart';
import 'progression_decision.dart';

/// Full logical representation of the records currently persisted by training.
/// This is a profile replacement contract, not a neutral external-history import.
final class TrainingArchive {
  TrainingArchive({
    required List<WorkoutRevision> revisions,
    required List<TrainingSession> sessions,
    required List<String> finalizations,
    List<ProgressionDecision> progressions = const [],
  }) : revisions = List<WorkoutRevision>.unmodifiable(
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
       ) {
    _validate();
  }

  factory TrainingArchive.fromJson(Object? input) {
    final json = jsonObject(input, 'logical training data');
    checkKeys(json, {'revisions', 'sessions', 'finalizations', 'progressions'});
    return TrainingArchive(
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
      progressions: [
        for (final item
            in (!json.containsKey('progressions')
                ? <Object?>[]
                : jsonList(json, 'progressions')))
          ProgressionDecision.fromJson(item),
      ],
    );
  }

  final List<WorkoutRevision> revisions;
  final List<TrainingSession> sessions;
  final List<String> finalizations;
  final List<ProgressionDecision> progressions;

  Map<String, Object?> toJson() => {
    'revisions': [for (final r in revisions) r.toJson()],
    'sessions': [for (final s in sessions) s.toJson()],
    'finalizations': finalizations,
    'progressions': [for (final d in progressions) d.toJson()],
  };

  Map<String, Object?> get summary => {
    'revisions': revisions.length,
    'sessions': sessions.length,
    'finalizations': finalizations.length,
    'progressions': progressions.length,
  };

  void _validate() {
    validateProgressionDecisions(progressions, sessions);
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
