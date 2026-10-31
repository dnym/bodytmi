import 'package:bodytmi_core/bodytmi_core.dart';
import 'training_service.dart';

/// One repository transaction is the durability boundary of each operation.
abstract interface class TrainingRepository {
  Future<T> transaction<T>(Future<T> Function() action);
  Future<WorkoutRevision?> revision(String templateId, [int? number]);
  Future<void> insertRevision(WorkoutRevision revision);
  Future<TrainingSession?> session(String id);
  Future<List<TrainingSession>> sessions();
  Future<void> insertSession(TrainingSession session);
  Future<void> updateSession(TrainingSession session);
  Future<void> recordFinalization(String sessionId);
}

final class StoredTrainingService {
  const StoredTrainingService(this.repository);
  final TrainingRepository repository;

  Future<WorkoutRevision> publish(
    WorkoutDefinition definition,
    int expectedRevision,
  ) => repository.transaction(() async {
    final previous = await repository.revision(definition.id);
    if ((previous?.number ?? 0) != expectedRevision) _conflict();
    final next = WorkoutRevision.publish(definition, previous: previous);
    await repository.insertRevision(next);
    return next;
  });

  Future<WorkoutRevision> revision(String id, [int? number]) async =>
      await repository.revision(id, number) ?? _missing('Revision');

  Future<TrainingSession> session(String id) async =>
      await repository.session(id) ?? _missing('Session');

  Future<TrainingSession> start(
    String id,
    String templateId,
    int number,
    DateTime startedAt,
  ) => repository.transaction(() async {
    final prescription = await revision(templateId, number);
    final existing = await repository.session(id);
    if (existing != null) {
      if (existing.revision.definition.id != templateId ||
          existing.revision.number != number ||
          existing.startedAt != startedAt)
        _conflict();
      return existing;
    }
    final next = const TrainingService().start(
      sessionId: id,
      revision: prescription,
      startedAt: startedAt,
      history: await repository.sessions(),
    );
    await repository.insertSession(next);
    return next;
  });

  Future<TrainingSession> edit(
    String id,
    int expectedVersion,
    TrainingSession Function(TrainingSession) change,
  ) => repository.transaction(() async {
    final current = await session(id);
    if (current.contentVersion != expectedVersion) _conflict();
    final next = change(current);
    await repository.updateSession(next);
    if (next.status == SessionStatus.finalized)
      await repository.recordFinalization(id);
    return next;
  });
}

Never _conflict() => throw const BodyTmiException(
  'conflict',
  'Stored content changed or identity already exists. Refresh before retrying.',
);
Never _missing(String kind) =>
    throw BodyTmiException('not_found', '$kind not found.');
