import 'dart:convert';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'canonical_json.dart';
import 'training_repository.dart';
import 'window_repeat_execution.dart';

/// An inert, independently saved repeat ledger. It is not a training session.
final class RepeatCheckpoint {
  RepeatCheckpoint._(this.id, this.version, this._execution);
  factory RepeatCheckpoint.fromJson(Object? input) {
    final json = jsonObject(input, 'repeat checkpoint');
    checkKeys(json, {'id', 'version', 'execution'});
    final id = identifier(json, 'id');
    final version = json['version'];
    if (version is! int || version < 1 || version > 2000000000)
      invalid('Invalid repeat checkpoint version.');
    final execution = jsonObject(
      const WindowRepeatExecution().view(json['execution'])['execution'],
      'execution',
    );
    if (jsonObject(execution['cursor'], 'cursor')['status'] == 'running')
      invalid('Only inert repeat snapshots can be stored.');
    return RepeatCheckpoint._(id, version, canonicalJson(execution));
  }
  final String id;
  final int version;
  final String _execution;
  Map<String, Object?> get execution =>
      jsonObject(jsonDecode(_execution), 'execution');
  Map<String, Object?> toJson() => {
    'id': id,
    'version': version,
    'execution': execution,
  };
}

final class RepeatCheckpointService {
  const RepeatCheckpointService(this.repository);
  final TrainingRepository repository;
  Future<RepeatCheckpoint> show(String id) async =>
      await repository.repeatCheckpoint(id) ??
      (throw const BodyTmiException(
        'not_found',
        'Repeat checkpoint not found.',
      ));
  Future<List<RepeatCheckpoint>> list() async {
    final values = await repository.repeatCheckpoints();
    values.sort((a, b) => a.id.compareTo(b.id));
    return values;
  }

  Future<RepeatCheckpoint> save(
    String id,
    int expectedVersion,
    Object? execution,
  ) => repository.transaction(() async {
    identifier({'id': id}, 'id');
    final existing = await repository.repeatCheckpoint(id);
    if ((existing?.version ?? 0) != expectedVersion)
      throw const BodyTmiException(
        'conflict',
        'Repeat checkpoint version changed.',
      );
    final next = RepeatCheckpoint.fromJson({
      'id': id,
      'version': expectedVersion + 1,
      'execution': execution,
    });
    if (existing != null) {
      final oldLoop = jsonObject(
        jsonObject(existing.execution['cursor'], 'cursor')['loop'],
        'loop',
      );
      final nextLoop = jsonObject(
        jsonObject(next.execution['cursor'], 'cursor')['loop'],
        'loop',
      );
      if (canonicalJson(oldLoop) != canonicalJson(nextLoop))
        invalid('Repeat checkpoint cannot change its pinned loop.');
      if ((next.execution['version'] as int) <
          (existing.execution['version'] as int))
        invalid('Repeat checkpoint cannot move to an older execution version.');
      if (next.execution['version'] == existing.execution['version'] &&
          canonicalJson(next.execution) != canonicalJson(existing.execution))
        invalid('Repeat execution content changed without a new version.');
    }
    await repository.saveRepeatCheckpoint(next);
    return next;
  });

  /// Apply an inert action or an explicit elapsed-time sample atomically.
  Future<RepeatCheckpoint> action(
    String id, {
    required int expectedVersion,
    required int expectedExecutionVersion,
    required String action,
    Map<String, Object?>? review,
    Map<String, Object?>? correction,
    int? elapsedMilliseconds,
    bool confirm = false,
  }) => repository.transaction(() async {
    if (!{
      'review',
      'review-batch',
      'correct',
      'revise',
      'finish',
      'stop',
      'elapse',
      'review-elapsed',
    }.contains(action))
      invalid('Unknown inert repeat checkpoint action.');
    final current = await show(id);
    if (current.version != expectedVersion)
      throw const BodyTmiException(
        'conflict',
        'Repeat checkpoint version changed.',
      );
    const engine = WindowRepeatExecution();
    late final Map<String, Object?> execution;
    if (action == 'elapse' || action == 'review-elapsed') {
      if (elapsedMilliseconds == null ||
          elapsedMilliseconds < 1 ||
          correction != null ||
          (action == 'elapse' && (review != null || confirm)) ||
          (action == 'review-elapsed' && review == null))
        invalid(
          'Elapsed actions require a positive duration and compatible review fields.',
        );
      const owner = 'repeat-checkpoint-sample';
      final running = engine.apply(
        current.execution,
        expectedVersion: expectedExecutionVersion,
        action: 'resume',
        ownerId: owner,
      );
      if (action == 'elapse') {
        execution = engine.apply(
          running,
          expectedVersion: running['version'] as int,
          action: 'pause',
          ownerId: owner,
          ownerElapsedMilliseconds: elapsedMilliseconds,
        );
      } else {
        final reviewed = engine.apply(
          running,
          expectedVersion: running['version'] as int,
          action: 'review',
          ownerId: owner,
          ownerElapsedMilliseconds: elapsedMilliseconds,
          review: review,
          confirm: confirm,
        );
        execution =
            jsonObject(reviewed['cursor'], 'cursor')['status'] == 'running'
            ? engine.apply(
                reviewed,
                expectedVersion: reviewed['version'] as int,
                action: 'pause',
                ownerId: owner,
                ownerElapsedMilliseconds: elapsedMilliseconds,
              )
            : reviewed;
      }
    } else {
      if (elapsedMilliseconds != null)
        invalid('Only elapsed actions take an elapsed duration.');
      execution = engine.apply(
        current.execution,
        expectedVersion: expectedExecutionVersion,
        action: action,
        review: review,
        correction: correction,
        confirm: confirm,
      );
    }
    final next = RepeatCheckpoint.fromJson({
      'id': id,
      'version': current.version + 1,
      'execution': execution,
    });
    await repository.saveRepeatCheckpoint(next);
    return next;
  });
  Future<void> delete(
    String id,
    int expectedVersion, {
    required bool confirm,
  }) => repository.transaction(() async {
    if (!confirm) invalid('Confirm before deleting a repeat checkpoint.');
    final current = await show(id);
    if (current.version != expectedVersion)
      throw const BodyTmiException(
        'conflict',
        'Repeat checkpoint version changed.',
      );
    await repository.deleteRepeatCheckpoint(id);
  });
}
