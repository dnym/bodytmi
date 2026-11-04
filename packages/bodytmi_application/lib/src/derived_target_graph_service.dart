import 'package:bodytmi_core/bodytmi_core.dart';
import 'body_mass_service.dart';
import 'training_repository.dart';

/// Durable published graphs and read-only resolution against stored sources.
final class DerivedTargetGraphService {
  const DerivedTargetGraphService(this.repository);
  final TrainingRepository repository;

  Future<DerivedTargetGraphRevision> publish(
    DerivedTargetGraph graph,
    int expectedRevision,
  ) => repository.transaction(() async {
    final all = await repository.derivedTargetGraphRevisions();
    validateDerivedTargetGraphRevisions(all);
    final matches = all.where((r) => r.graph.id == graph.id).toList()
      ..sort((a, b) => b.number.compareTo(a.number));
    final before = matches.firstOrNull;
    if ((before?.number ?? 0) != expectedRevision)
      throw const BodyTmiException(
        'conflict',
        'Derived target graph revision changed.',
      );
    final next = DerivedTargetGraphRevision.publish(graph, previous: before);
    await repository.insertDerivedTargetGraphRevision(next);
    return next;
  });

  Future<DerivedTargetGraphRevision> revision(String id, [int? number]) async {
    final all =
        (await repository.derivedTargetGraphRevisions())
            .where(
              (r) => r.graph.id == id && (number == null || r.number == number),
            )
            .toList()
          ..sort((a, b) => b.number.compareTo(a.number));
    return all.firstOrNull ??
        (throw const BodyTmiException(
          'not_found',
          'Derived target graph revision not found.',
        ));
  }

  Future<List<DerivedTargetGraphRevision>> list() async =>
      (await repository.derivedTargetGraphRevisions())..sort((a, b) {
        final id = a.graph.id.compareTo(b.graph.id);
        return id == 0 ? a.number.compareTo(b.number) : id;
      });

  /// Resolves a published graph against stored data without modifying it.
  ///
  /// Manual bindings use their frozen value/version. Body-mass bindings use
  /// the stored resolver with an explicit asOf (binding value, else the
  /// command value). History bindings use finalized confirmed sets only.
  Future<Map<String, Object?>> resolve(
    String graphId, [
    int? number,
    DateTime? asOf,
    String? runId,
    bool allRuns = false,
  ]) => repository.transaction(() async {
    if (runId != null) identifier({'runId': runId}, 'runId');
    if (runId != null && allRuns)
      invalid('Choose a run or all runs, not both.');
    final revision = await this.revision(graphId, number);
    final graph = revision.graph;
    final measurements = [
      for (final record in await repository.bodyMassRecords())
        if (!record.deleted) record.measurement,
    ];
    final sessions = [
      for (final session in await repository.sessions())
        if (session.status == SessionStatus.finalized) session,
    ];
    final runBySession = {
      for (final binding in await repository.sessionPrograms())
        binding.sessionId: binding.runId,
    };
    final resolvedBindings = <String, Map<String, Object?>>{};
    final resolverNodes = <Map<String, Object?>>[];
    var historySourceCount = 0;
    for (final node in graph.nodes) {
      if (node['kind'] != 'source') {
        resolverNodes.add(node);
        continue;
      }
      final sourceId = node['sourceId']! as String;
      final binding = Map<String, Object?>.from(graph.bindings[sourceId]!);
      final unit = Unit.parse(node['unit']! as String);
      Quantity? value;
      int? version;
      switch (binding['kind']) {
        case 'manual':
          value = Quantity.fromJson(binding['value']);
          version = binding['version']! as int;
        case 'bodyMass':
          final effective = binding.containsKey('asOf')
              ? parseInstant(binding['asOf'], 'asOf')
              : asOf;
          if (effective == null)
            invalid('Body-mass binding requires an explicit asOf.');
          if (asOf != null && effective.isAfter(asOf))
            invalid(
              'Body-mass binding asOf cannot be after the resolution asOf.',
            );
          final eligible = [
            for (final m in measurements)
              if (m.context == binding['context'] &&
                  !m.observedAt.isAfter(effective))
                m,
          ];
          if (eligible.isNotEmpty) {
            version = eligible
                .map((m) => m.contentVersion)
                .reduce((a, b) => a > b ? a : b);
          }
          final resolution = const BodyMassService().resolve({
            'measurements': [for (final m in eligible) m.toJson()],
            'context': binding['context'],
            'asOf': effective.toUtc().toIso8601String(),
            'dailyMode': binding['dailyMode'],
            if (binding.containsKey('staleAfterDays'))
              'staleAfterDays': binding['staleAfterDays'],
            if (binding.containsKey('warnIfStale'))
              'warnIfStale': binding['warnIfStale'],
          });
          value = resolution.mass;
          binding['provenance'] = {
            'context': binding['context'],
            'asOf': effective.toUtc().toIso8601String(),
            'source': resolution.source,
            if (resolution.sourceObservedAt != null)
              'observedAt': resolution.sourceObservedAt!
                  .toUtc()
                  .toIso8601String(),
            'stale': resolution.stale,
            'sourceFingerprint': resolution.sourceFingerprint,
            'sourceVersionSemantics': 'maximumMeasurementVersionOnly',
          };
        case 'history':
          final history = _historySelection(
            sessions,
            binding,
            unit,
            asOf,
            runBySession,
            runId,
            allRuns,
            10000 - historySourceCount,
          );
          historySourceCount +=
              (history.$2['sources']! as List<Object?>).length;
          final selection = history.$1;
          if (selection != null) {
            value = selection.$1;
            version = selection.$2;
          }
          binding['provenance'] = {
            'metric': binding['metric'],
            'direction': binding['direction'],
            if (selection != null) 'session': selection.$3,
            if (selection != null) 'set': selection.$4,
            'sourceVersionSemantics': 'selectedSessionVersionOnly',
            'sourceFingerprint': history.$2,
          };
      }
      binding['value'] = value?.toJson();
      binding['status'] = value == null ? 'unresolved' : 'resolved';
      if (version != null) binding['sourceVersion'] = version;
      resolvedBindings[sourceId] = binding;
      resolverNodes.add({
        ...node,
        'sourceVersion': version,
        'value': value?.toJson(),
      });
    }
    return {
      'policy': 'bodytmi-derived-target-graph-resolution/3',
      'historyScope': {
        'mode': allRuns
            ? 'all'
            : runId == null
            ? 'adHoc'
            : 'run',
        if (runId != null) 'runId': runId,
        if (asOf != null) 'asOf': asOf.toUtc().toIso8601String(),
      },
      'graph': {
        'id': graph.id,
        'number': revision.number,
        if (graph.name != null) 'name': graph.name,
        'nodes': graph.nodes,
      },
      'bindings': {for (final id in graph.sourceIds) id: resolvedBindings[id]!},
      'resolution': const DerivedTargets().resolve(resolverNodes),
    };
  });
}

typedef _Selection = (Quantity, int, String, String, DateTime, int);

(_Selection?, Map<String, Object?>) _historySelection(
  List<TrainingSession> sessions,
  Map<String, Object?> binding,
  Unit unit,
  DateTime? asOf,
  Map<String, String> runBySession,
  String? runId,
  bool allRuns,
  int remainingSources,
) {
  final metric = binding['metric']! as String;
  final direction = binding['direction']! as String;
  final includeWarmups = (binding['includeWarmups'] ?? false) as bool;
  final from = binding.containsKey('from')
      ? parseInstant(binding['from'], 'from')
      : null;
  final until = binding.containsKey('until')
      ? parseInstant(binding['until'], 'until')
      : null;
  _Selection? best;
  final sources = <Map<String, Object?>>[];
  for (final session in sessions) {
    if (!allRuns && runBySession[session.id] != runId) continue;
    if (asOf != null &&
        (session.finishedAt == null || session.finishedAt!.isAfter(asOf)))
      continue;
    if (from != null && session.startedAt.isBefore(from)) continue;
    if (until != null && !session.startedAt.isBefore(until)) continue;
    final definition = session.revision.definition;
    if (binding['templateId'] != null &&
        binding['templateId'] != definition.id) {
      continue;
    }
    for (final set in session.sets) {
      if (!includeWarmups && set.role == 'warmup') continue;
      if (set.status != SetStatus.completed) continue;
      if (set.observations?.interrupted ?? false) continue;
      final actual = set.actuals[metric];
      if (actual == null || actual.dimension != unit.dimension) continue;
      final slot = definition.slot(set.slotId);
      if (binding['slotId'] != null && binding['slotId'] != set.slotId)
        continue;
      if (binding['exerciseId'] != null &&
          binding['exerciseId'] != slot.exerciseId)
        continue;
      if (binding['implementationId'] != null &&
          binding['implementationId'] != slot.implementation)
        continue;
      if (binding['equipment'] != null &&
          binding['equipment'] != slot.equipmentId)
        continue;
      if (binding['setup'] != null && binding['setup'] != slot.setupNote)
        continue;
      if (binding['role'] != null && binding['role'] != set.role) continue;
      if (binding['ordinal'] != null && binding['ordinal'] != set.ordinal)
        continue;
      if (sources.length >= remainingSources) {
        invalid(
          'Graph history sources exceed the 10000-result resource limit.',
        );
      }
      sources.add({
        'sessionId': session.id,
        'sessionVersion': session.contentVersion,
        'setId': set.id,
        'setVersion': set.contentVersion,
        'runId': runBySession[session.id],
        'startedAt': session.startedAt.toUtc().toIso8601String(),
        'finishedAt': session.finishedAt!.toUtc().toIso8601String(),
        'slotId': set.slotId,
        'role': set.role,
        'ordinal': set.ordinal,
        'value': actual.toJson(),
      });
      final candidate = (
        actual,
        session.contentVersion,
        session.id,
        set.id,
        session.startedAt,
        set.ordinal,
      );
      if (best == null || _better(candidate, best, direction)) {
        best = candidate;
      }
    }
  }
  sources.sort((a, b) {
    final session = (a['sessionId']! as String).compareTo(
      b['sessionId']! as String,
    );
    return session != 0
        ? session
        : (a['setId']! as String).compareTo(b['setId']! as String);
  });
  return (
    best,
    {
      'policy': 'bodytmi-history-source/1',
      'metric': metric,
      'direction': direction,
      'sources': sources,
    },
  );
}

bool _better(_Selection candidate, _Selection incumbent, String direction) {
  final comparison = direction == 'highest'
      ? candidate.$1.compareTo(incumbent.$1)
      : incumbent.$1.compareTo(candidate.$1);
  if (comparison > 0) return true;
  if (comparison < 0) return false;
  // Equal values: earliest start, then session ID, ordinal, set ID.
  final time = candidate.$5.compareTo(incumbent.$5);
  if (time != 0) return time < 0;
  final id = candidate.$3.compareTo(incumbent.$3);
  if (id != 0) return id < 0;
  final ordinal = candidate.$6.compareTo(incumbent.$6);
  if (ordinal != 0) return ordinal < 0;
  return candidate.$4.compareTo(incumbent.$4) < 0;
}
