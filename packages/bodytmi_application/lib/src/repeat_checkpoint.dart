import 'dart:convert';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'canonical_json.dart';
import 'training_repository.dart';
import 'window_repeat_execution.dart';
import 'window_checkpoint.dart';

/// An independently saved repeat ledger. It is not a training session.
final class RepeatCheckpoint {
  RepeatCheckpoint._(this.id, this.version, this._execution, this.reserved);
  factory RepeatCheckpoint.fromJson(Object? input) {
    final json = jsonObject(input, 'repeat checkpoint');
    checkKeys(json, {'id', 'version', 'execution', 'reserved'});
    final id = identifier(json, 'id');
    final version = json['version'];
    if (version is! int || version < 1 || version > 2000000000)
      invalid('Invalid repeat checkpoint version.');
    final execution = jsonObject(
      const WindowRepeatExecution().view(json['execution'])['execution'],
      'execution',
    );
    if (json.containsKey('reserved') && json['reserved'] != true)
      invalid('reserved must be true when specified.');
    final reserved = json['reserved'] == true;
    final status = jsonObject(execution['cursor'], 'cursor')['status'];
    if (status == 'running' && !reserved)
      invalid('A running repeat requires a timing reservation.');
    if (reserved && !{'paused', 'running', 'boundary'}.contains(status))
      invalid('A repeat reservation requires an active cursor.');
    return RepeatCheckpoint._(id, version, canonicalJson(execution), reserved);
  }
  final String id;
  final int version;
  final bool reserved;
  final String _execution;
  Map<String, Object?> get execution =>
      jsonObject(jsonDecode(_execution), 'execution');
  Map<String, Object?> toJson() => {
    'id': id,
    'version': version,
    'execution': execution,
    if (reserved) 'reserved': true,
  };
}

void validateRepeatClockReservations(
  List<RepeatCheckpoint> checkpoints, {
  List<TimingActivity> timers = const [],
  List<WindowCheckpoint> windows = const [],
}) {
  final count = checkpoints.where((c) => c.reserved).length;
  if (count > 1 ||
      (count > 0 &&
          (timers.any((t) => t.active) || windows.any((w) => w.reserved))))
    invalid('Only one logical timing activity may be active.');
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
    if (existing?.reserved == true)
      invalid('Release the repeat clock before replacing its snapshot.');
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

  Future<RepeatCheckpoint> reserve(
    String id,
    int expectedVersion,
  ) => repository.transaction(() async {
    final current = await show(id);
    if (current.version != expectedVersion)
      throw const BodyTmiException(
        'conflict',
        'Repeat checkpoint version changed.',
      );
    if (current.reserved) invalid('This repeat already reserves the clock.');
    final status = jsonObject(current.execution['cursor'], 'cursor')['status'];
    if (!{'paused', 'boundary'}.contains(status))
      invalid('Reserve requires a paused or boundary repeat.');
    if ((await repository.repeatCheckpoints()).any((c) => c.reserved) ||
        (await repository.windowCheckpoints()).any((c) => c.reserved) ||
        (await repository.timingActivities()).any((t) => t.active))
      throw const BodyTmiException(
        'conflict',
        'Another timing activity is active.',
      );
    final next = RepeatCheckpoint.fromJson({
      'id': id,
      'version': current.version + 1,
      'execution': current.execution,
      'reserved': true,
    });
    await repository.saveRepeatCheckpoint(next);
    return next;
  });

  Future<RepeatCheckpoint> release(
    String id,
    int expectedVersion, {
    required bool confirm,
  }) => repository.transaction(() async {
    if (!confirm) invalid('Releasing the clock requires confirmation.');
    final current = await show(id);
    if (current.version != expectedVersion)
      throw const BodyTmiException(
        'conflict',
        'Repeat checkpoint version changed.',
      );
    if (!current.reserved) invalid('This repeat does not reserve the clock.');
    if (jsonObject(current.execution['cursor'], 'cursor')['status'] ==
        'running')
      invalid('Pause or recover the repeat clock before releasing it.');
    final next = RepeatCheckpoint.fromJson({
      'id': id,
      'version': current.version + 1,
      'execution': current.execution,
    });
    await repository.saveRepeatCheckpoint(next);
    return next;
  });

  /// Apply a review or owner-sampled clock action atomically.
  Future<RepeatCheckpoint> action(
    String id, {
    required int expectedVersion,
    required int expectedExecutionVersion,
    required String action,
    Map<String, Object?>? review,
    Map<String, Object?>? correction,
    int? elapsedMilliseconds,
    String? ownerId,
    int? ownerElapsedMilliseconds,
    int? adjustmentMilliseconds,
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
      'resume',
      'advance',
      'pause',
      'recover',
    }.contains(action))
      invalid('Unknown inert repeat checkpoint action.');
    final current = await show(id);
    if (current.version != expectedVersion)
      throw const BodyTmiException(
        'conflict',
        'Repeat checkpoint version changed.',
      );
    if ({'resume', 'advance', 'pause', 'recover'}.contains(action) &&
        !current.reserved)
      invalid('Reserve the repeat timing slot before clock actions.');
    const engine = WindowRepeatExecution();
    late final Map<String, Object?> execution;
    if (action == 'elapse' || action == 'review-elapsed') {
      if (elapsedMilliseconds == null ||
          elapsedMilliseconds < 1 ||
          ownerId != null ||
          ownerElapsedMilliseconds != null ||
          adjustmentMilliseconds != null ||
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
        ownerId: ownerId,
        ownerElapsedMilliseconds: ownerElapsedMilliseconds,
        adjustmentMilliseconds: adjustmentMilliseconds,
        review: review,
        correction: correction,
        confirm: confirm,
      );
    }
    final next = RepeatCheckpoint.fromJson({
      'id': id,
      'version': current.version + 1,
      'execution': execution,
      if (current.reserved &&
          {
            'paused',
            'running',
            'boundary',
          }.contains(jsonObject(execution['cursor'], 'cursor')['status']))
        'reserved': true,
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
    if (current.reserved)
      invalid('Release the repeat clock before deleting its checkpoint.');
    await repository.deleteRepeatCheckpoint(id);
  });
}
