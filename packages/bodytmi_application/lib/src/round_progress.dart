import 'package:bodytmi_core/bodytmi_core.dart';

/// Reports authored finite repeat iterations using explicit current results.
final class RoundProgress {
  const RoundProgress();

  Map<String, Object?> evaluate(TrainingSession session, String groupPath) {
    if (groupPath.trim().isEmpty) invalid('groupPath must be nonempty.');
    final definition = session.definition;
    final groups = activityGroups(definition.plan);
    final expression = RegExp(
      '^${RegExp.escape(groupPath)}\\[([0-9]+)\\]' + r'$',
    );
    final rounds = <({int ordinal, ActivityGroupOccurrence group})>[];
    for (final group in groups) {
      final match = expression.firstMatch(group.path);
      if (match != null)
        rounds.add((ordinal: int.parse(match[1]!), group: group));
    }
    rounds.sort((a, b) => a.ordinal.compareTo(b.ordinal));
    if (rounds.isEmpty || !groups.any((group) => group.path == groupPath))
      invalid('groupPath must identify an authored repeat occurrence.');
    for (var i = 0; i < rounds.length; i++) {
      if (rounds[i].ordinal != i)
        invalid('Repeat iteration identities are inconsistent.');
    }
    final plan = definition.plan.occurrences().toList();
    final sets = {for (final set in session.sets) set.id: set};
    final rows = <Map<String, Object?>>[];
    var confirmedRounds = 0, partialRounds = 0;
    for (final round in rounds) {
      final efforts = <TrainingSet>[
        for (var i = round.group.start; i < round.group.end; i++)
          if (plan[i].activity is Effort) sets[plan[i].id]!,
      ];
      if (efforts.isEmpty)
        invalid('A round report requires effort in each iteration.');
      final confirmed = efforts.every((set) => set.eligibleForPerformance);
      final performed = efforts.any((set) => set.status == SetStatus.completed);
      final skipped = efforts.every((set) => set.status == SetStatus.skipped);
      final unstarted = efforts.every((set) => set.status == SetStatus.planned);
      final status = confirmed
          ? 'confirmed'
          : performed
          ? 'partial'
          : skipped
          ? 'skipped'
          : unstarted
          ? 'unstarted'
          : 'incomplete';
      if (confirmed) confirmedRounds++;
      if (status == 'partial') partialRounds++;
      rows.add({
        'ordinal': round.ordinal,
        'path': round.group.path,
        'startOccurrence': round.group.start,
        'endOccurrence': round.group.end,
        'status': status,
        'efforts': [
          for (final set in efforts)
            {
              'id': set.id,
              'slot': set.slotId,
              'role': set.role,
              'status': set.status.name,
              'eligibleForPerformance': set.eligibleForPerformance,
              'actuals': metricsToJson(set.actuals),
              if (set.observations != null)
                'observations': set.observations!.toJson(),
            },
        ],
      });
    }
    return {
      'policy': 'bodytmi-round-progress/1',
      'sessionId': session.id,
      'sessionContentVersion': session.contentVersion,
      'sessionStatus': session.status.name,
      'templateId': definition.id,
      'revision': session.revision.number,
      'groupPath': groupPath,
      'confirmedRounds': confirmedRounds,
      'partialRounds': partialRounds,
      'rounds': rows,
    };
  }
}
