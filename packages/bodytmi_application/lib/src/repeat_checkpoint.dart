import 'dart:convert';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'canonical_json.dart';
import 'training_repository.dart';
import 'window_repeat_execution.dart';
import 'window_checkpoint.dart';
import 'block_progression.dart';

/// A repeat ledger, optionally associated with an existing training session.
final class RepeatCheckpoint {
  RepeatCheckpoint._(
    this.id,
    this.version,
    this._execution,
    this.reserved,
    this.sessionId,
    this.amrapId,
    this.blockTargets,
  );
  factory RepeatCheckpoint.fromJson(Object? input) {
    final json = jsonObject(input, 'repeat checkpoint');
    checkKeys(json, {
      'id',
      'version',
      'execution',
      'reserved',
      'sessionId',
      'amrapId',
      'blockTargets',
    });
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
    final sessionId = json.containsKey('sessionId')
        ? identifier(json, 'sessionId')
        : null;
    final amrapId = json.containsKey('amrapId')
        ? identifier(json, 'amrapId')
        : null;
    if (amrapId != null && sessionId == null)
      invalid('An authored AMRAP checkpoint needs its session.');
    final blockTargets = <String, BlockTargetSource>{};
    if (json.containsKey('blockTargets')) {
      if (amrapId == null)
        invalid('Accepted block targets need an authored AMRAP block.');
      final map = jsonObject(json['blockTargets'], 'blockTargets');
      if (map.isEmpty) invalid('blockTargets cannot be empty.');
      for (final entry in map.entries) {
        identifier({'id': entry.key}, 'id');
        final source = jsonObject(entry.value, 'block target source');
        checkKeys(source, {'decisionId', 'targets'});
        final targets = metricsFromJson(source['targets']);
        if (targets.isEmpty) invalid('Block target sources need targets.');
        blockTargets[entry.key] = (
          decisionId: requiredString(source, 'decisionId'),
          targets: targets,
        );
      }
    }
    return RepeatCheckpoint._(
      id,
      version,
      canonicalJson(execution),
      reserved,
      sessionId,
      amrapId,
      Map.unmodifiable(blockTargets),
    );
  }
  final String id;
  final int version;
  final bool reserved;
  final String? sessionId;

  /// The authored AMRAP block of the session's pinned workout revision.
  final String? amrapId;

  /// Round slot targets supplied by accepted block progression at start,
  /// with the decision that produced them.
  final Map<String, BlockTargetSource> blockTargets;
  final String _execution;
  Map<String, Object?> get execution =>
      jsonObject(jsonDecode(_execution), 'execution');
  Map<String, Object?> toJson() => {
    'id': id,
    'version': version,
    'execution': execution,
    if (reserved) 'reserved': true,
    if (sessionId != null) 'sessionId': sessionId,
    if (amrapId != null) 'amrapId': amrapId,
    if (blockTargets.isNotEmpty) 'blockTargets': _blockTargetsJson,
  };

  Map<String, Object?> get _blockTargetsJson => {
    for (final entry in (blockTargets.keys.toList()..sort()))
      entry: {
        'decisionId': blockTargets[entry]!.decisionId,
        'targets': metricsToJson(blockTargets[entry]!.targets),
      },
  };

  /// Identity fields carried unchanged through every rewrite.
  Map<String, Object?> get _identity => {
    if (sessionId != null) 'sessionId': sessionId,
    if (amrapId != null) 'amrapId': amrapId,
    if (blockTargets.isNotEmpty) 'blockTargets': _blockTargetsJson,
  };
}

typedef BlockTargetSource = ({String decisionId, Metrics targets});

/// The authored block with accepted round slot targets substituted.
WindowRepeatSpec applyBlockTargets(
  WindowRepeatSpec authored,
  Map<String, BlockTargetSource> targets,
) {
  if (targets.isEmpty) return authored;
  final json = jsonObject(jsonDecode(canonicalJson(authored.toJson())), 'loop');
  final round = jsonObject(json['roundDefinition'], 'round');
  final slots = jsonList(round, 'slots');
  for (final entry in targets.entries) {
    final slot = slots
        .map((s) => jsonObject(s, 'slot'))
        .where((s) => s['id'] == entry.key)
        .firstOrNull;
    if (slot == null) invalid('Block targets name an unknown round slot.');
    slot['targets'] = {
      ...jsonObject(slot['targets'], 'targets'),
      ...metricsToJson(entry.value.targets),
    };
  }
  return WindowRepeatSpec.fromJson(json);
}

void validateRepeatSessionBindings(
  List<RepeatCheckpoint> checkpoints,
  List<TrainingSession> sessions,
) {
  final byId = {for (final session in sessions) session.id: session};
  for (final checkpoint in checkpoints) {
    final sessionId = checkpoint.sessionId;
    if (sessionId == null) continue;
    final session = byId[sessionId];
    if (session == null) invalid('Repeat checkpoint session is missing.');
    if (session.status == SessionStatus.finalized &&
        jsonObject(checkpoint.execution['cursor'], 'cursor')['status'] !=
            'finished')
      invalid('A finalized session requires finished repeat checkpoints.');
    final amrapId = checkpoint.amrapId;
    if (amrapId == null) continue;
    final authored = session.revision.definition.amrap(amrapId);
    if (authored == null)
      invalid('Repeat checkpoint names an AMRAP block its session lacks.');
    if (canonicalJson(
          jsonObject(checkpoint.execution['cursor'], 'cursor')['loop'],
        ) !=
        canonicalJson(
          applyBlockTargets(authored, checkpoint.blockTargets).toJson(),
        ))
      invalid('Repeat checkpoint loop differs from its authored AMRAP block.');
  }
  final blocks = <String>{};
  for (final checkpoint in checkpoints) {
    if (checkpoint.amrapId != null &&
        !blocks.add('${checkpoint.sessionId}\u0000${checkpoint.amrapId}'))
      invalid('An authored AMRAP block has more than one checkpoint.');
  }
  for (final session in sessions) {
    if (session.status != SessionStatus.finalized) continue;
    for (final amrap in session.revision.definition.amraps) {
      if (!blocks.contains('${session.id}\u0000${amrap.id}'))
        invalid(
          'A finalized session needs a finished checkpoint for AMRAP block '
          '${amrap.id}.',
        );
    }
  }
}

/// Finalization guard: authored AMRAP blocks without a checkpoint.
List<String> missingAmrapBlocks(
  TrainingSession session,
  List<RepeatCheckpoint> checkpoints,
) => [
  for (final amrap in session.revision.definition.amraps)
    if (!checkpoints.any(
      (c) => c.sessionId == session.id && c.amrapId == amrap.id,
    ))
      amrap.id,
];

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
    Object? execution, {
    String? sessionId,
  }) => repository.transaction(() async {
    identifier({'id': id}, 'id');
    final existing = await repository.repeatCheckpoint(id);
    if ((existing?.version ?? 0) != expectedVersion)
      throw const BodyTmiException(
        'conflict',
        'Repeat checkpoint version changed.',
      );
    if (existing?.reserved == true)
      invalid('Release the repeat clock before replacing its snapshot.');
    if (sessionId != null) identifier({'id': sessionId}, 'id');
    if (existing != null &&
        sessionId != null &&
        sessionId != existing.sessionId)
      invalid('A repeat checkpoint cannot change its session association.');
    final binding = existing?.sessionId ?? sessionId;
    if (existing == null && binding != null) {
      final session = await repository.session(binding);
      if (session == null)
        throw const BodyTmiException('not_found', 'Session not found.');
      if (session.status != SessionStatus.active)
        invalid('A repeat can only be associated with an active session.');
    }
    final next = RepeatCheckpoint.fromJson({
      'id': id,
      'version': expectedVersion + 1,
      'execution': execution,
      if (binding != null) 'sessionId': binding,
      if (existing?.amrapId != null) 'amrapId': existing!.amrapId,
      if (existing?.blockTargets.isNotEmpty ?? false)
        'blockTargets': existing!._blockTargetsJson,
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
      if (jsonObject(existing.execution['cursor'], 'cursor')['status'] ==
              'finished' &&
          jsonObject(next.execution['cursor'], 'cursor')['status'] !=
              'finished')
        invalid('A finished repeat cannot be reopened.');
    }
    if (binding != null)
      validateRepeatSessionBindings([next], await repository.sessions());
    await repository.saveRepeatCheckpoint(next);
    return next;
  });

  /// Starts the ledger of an authored AMRAP block from the session's pinned
  /// revision. Retrying the identical request returns the untouched
  /// checkpoint; any other existing checkpoint for that block conflicts.
  /// Skipping a block is an explicit confirmed `stop` on this checkpoint.
  Future<RepeatCheckpoint> startBlock(
    String id,
    String sessionId,
    String amrapId,
  ) => repository.transaction(() async {
    // Accepted block progression for this session's run, as of its start.
    identifier({'id': id}, 'id');
    identifier({'id': sessionId}, 'id');
    identifier({'id': amrapId}, 'id');
    final session =
        await repository.session(sessionId) ??
        (throw const BodyTmiException('not_found', 'Session not found.'));
    final authored =
        session.revision.definition.amrap(amrapId) ??
        (throw const BodyTmiException(
          'not_found',
          'The session workout revision has no such AMRAP block.',
        ));
    final runId = (await repository.sessionPrograms())
        .where((b) => b.sessionId == sessionId)
        .firstOrNull
        ?.runId;
    final decisions = await repository.blockProgressions();
    final sources = <String, BlockTargetSource>{};
    for (final slot in authored.roundDefinition.slots) {
      final latest = latestBlockDecision(
        decisions,
        blockTrackKey(runId, session.revision.definition.id, amrapId, slot.id),
        asOf: session.startedAt,
      );
      if (latest != null)
        sources[slot.id] = (
          decisionId: latest.id,
          targets: latest.resolvedTargets,
        );
    }
    final loop = applyBlockTargets(authored, sources);
    final next = RepeatCheckpoint.fromJson({
      'id': id,
      'version': 1,
      'execution': const WindowRepeatExecution().start(loop),
      'sessionId': sessionId,
      'amrapId': amrapId,
      if (sources.isNotEmpty)
        'blockTargets': {
          for (final entry in sources.entries)
            entry.key: {
              'decisionId': entry.value.decisionId,
              'targets': metricsToJson(entry.value.targets),
            },
        },
    });
    final all = await repository.repeatCheckpoints();
    final existing = all.where((c) => c.id == id).firstOrNull;
    if (existing != null) {
      if (canonicalJson(existing.toJson()) == canonicalJson(next.toJson()))
        return existing;
      throw const BodyTmiException(
        'conflict',
        'A repeat checkpoint with this ID already exists.',
      );
    }
    if (all.any((c) => c.sessionId == sessionId && c.amrapId == amrapId))
      throw const BodyTmiException(
        'conflict',
        'This AMRAP block already has a checkpoint.',
      );
    if (session.status != SessionStatus.active)
      invalid('An AMRAP block can only start in an active session.');
    // A placed block starts in plan order once traversal has reached it.
    final placement = session.revision.definition.amrapPlacement(amrapId);
    if (placement != null) {
      final traversal = (await repository.executions())
          .where((e) => e.sessionId == sessionId)
          .firstOrNull;
      final index = session.revision.definition.plan
          .occurrences()
          .toList()
          .indexWhere((o) => o.id == placement);
      if (traversal != null && traversal.cursor < index)
        invalid(
          'AMRAP block $amrapId is placed at $placement; advance the '
          'traversal to it before starting the block.',
        );
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
      ...current._identity,
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
      ...current._identity,
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
      ...current._identity,
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
    if (current.amrapId != null &&
        (await repository.session(current.sessionId!))?.status ==
            SessionStatus.finalized)
      invalid('A finished session keeps its authored AMRAP block results.');
    if ((await repository.executions()).any(
      (e) => e.receipts.any((r) => r['checkpointId'] == id),
    ))
      invalid(
        'Traversal already advanced past this AMRAP block; its checkpoint '
        'stays as the advancement source.',
      );
    await repository.deleteRepeatCheckpoint(id);
  });
}
