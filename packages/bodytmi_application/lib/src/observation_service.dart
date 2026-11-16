import 'package:bodytmi_core/bodytmi_core.dart';
import 'canonical_json.dart';
import 'training_repository.dart';

/// Measures and observations: custom measure authoring, and recording,
/// correcting, deleting and listing observations of any measure. Body-mass
/// observations follow the same rules as the `mass` commands, which are
/// views of the same records.
final class ObservationService {
  const ObservationService(this.repository);
  final TrainingRepository repository;

  Future<List<MeasureDefinition>> measures() async =>
      currentMeasures(await repository.measureRevisions());

  Future<MeasureDefinition> measure(String id) async =>
      (await measures()).where((m) => m.id == id).firstOrNull ??
      (throw BodyTmiException('not_found', 'Measure not found: $id.'));

  /// A custom measure's revision; built-ins have none.
  Future<MeasureRevision> measureRevision(String id, [int? number]) async {
    final all =
        (await repository.measureRevisions())
            .where(
              (r) =>
                  r.measure.id == id && (number == null || r.number == number),
            )
            .toList()
          ..sort((a, b) => b.number.compareTo(a.number));
    return all.firstOrNull ??
        (throw const BodyTmiException(
          'not_found',
          'Measure revision not found.',
        ));
  }

  /// Publishes a custom measure revision. A later revision keeps kind and
  /// dimension and must still accept every stored observation of it.
  Future<MeasureRevision> define(
    MeasureDefinition definition,
    int expectedRevision,
  ) => repository.transaction(() async {
    final all = await repository.measureRevisions();
    final before =
        (all.where((r) => r.measure.id == definition.id).toList()
              ..sort((a, b) => b.number.compareTo(a.number)))
            .firstOrNull;
    if ((before?.number ?? 0) != expectedRevision)
      throw const BodyTmiException('conflict', 'Measure revision changed.');
    if (before != null &&
        canonicalJson(before.measure.toJson()) ==
            canonicalJson(definition.toJson()))
      return before;
    final next = MeasureRevision.publish(definition, previous: before);
    for (final r in await repository.observationRecords(
      measureId: definition.id,
    )) {
      r.observation.validateAgainst(definition);
    }
    await repository.insertMeasureRevision(next);
    return next;
  });

  Future<ObservationRecord> show(String id) async =>
      await repository.observationRecord(id) ??
      (throw BodyTmiException('not_found', 'Observation not found: $id.'));

  /// Records (expectedVersion 0) or corrects (the current version) one
  /// observation; its content version becomes expectedVersion + 1. An
  /// identical retry returns the stored record. Deleted identities are never
  /// reused, and an import identity names at most one observation.
  Future<ObservationRecord> save(
    Map<String, Object?> input,
    int expectedVersion,
  ) => repository.transaction(() async {
    if (input.containsKey('contentVersion'))
      invalid('contentVersion is assigned; send expectedVersion.');
    if (expectedVersion < 0) invalid('expectedVersion must be nonnegative.');
    final observation = Observation.fromJson({
      ...input,
      'contentVersion': expectedVersion + 1,
    });
    observation.validateAgainst(await measure(observation.measureId));
    if (observation.isBodyMass) observation.toBodyMass();
    final next = ObservationRecord(observation);
    final current = await repository.observationRecord(observation.id);
    if (current != null &&
        canonicalJson(current.toJson()) == canonicalJson(next.toJson()))
      return current;
    if (current?.deleted == true ||
        (current?.observation.contentVersion ?? 0) != expectedVersion)
      throw const BodyTmiException(
        'conflict',
        'Observation version changed, or the identity was deleted.',
      );
    if (current != null &&
        current.observation.measureId != observation.measureId)
      invalid('An observation cannot change its measure.');
    if (observation.importNamespace != null) {
      final clash = (await repository.observationRecords()).where(
        (r) =>
            r.observation.id != observation.id &&
            r.observation.importNamespace == observation.importNamespace &&
            r.observation.importSourceId == observation.importSourceId,
      );
      if (clash.isNotEmpty)
        throw BodyTmiException(
          'conflict',
          'Import identity already names observation '
              '${clash.first.observation.id}.',
        );
    }
    await repository.saveObservationRecord(next);
    return next;
  });

  /// Marks an observation deleted, keeping its last content; requires
  /// confirm. Repeating the same deletion returns the deleted record.
  Future<ObservationRecord> delete(
    String id,
    int expectedVersion, {
    required bool confirm,
  }) => repository.transaction(() async {
    if (!confirm) invalid('Deleting an observation requires confirm:true.');
    final current = await show(id);
    if (current.deleted) {
      if (current.observation.contentVersion != expectedVersion + 1)
        throw const BodyTmiException(
          'conflict',
          'Observation version changed.',
        );
      return current;
    }
    if (current.observation.contentVersion != expectedVersion)
      throw const BodyTmiException('conflict', 'Observation version changed.');
    final next = ObservationRecord(
      Observation.fromJson({
        ...current.observation.toJson(),
        'contentVersion': expectedVersion + 1,
      }),
      deleted: true,
    );
    await repository.saveObservationRecord(next);
    return next;
  });

  /// The value of one series (measure + exact attributes) in force at
  /// [asOfText], under the measure's policy or an explicit [policy].
  Future<ObservationResolution> resolve(
    String measureId,
    String asOfText, {
    Map<String, String> attributes = const {},
    MeasurePolicy? policy,
    String dailyMode = 'mean',
  }) => repository.transaction(() async {
    final definition = await measure(measureId);
    return ObservationResolution.resolve(
      measure: definition,
      attributes: attributes,
      observations: [
        for (final r in await repository.observationRecords(
          measureId: measureId,
        ))
          if (!r.deleted) r.observation,
      ],
      asOfText: asOfText,
      policy: policy,
      dailyMode: dailyMode,
    );
  });

  /// Observations sorted by local date, then instant or date, then id;
  /// optionally one measure, a local date range, attribute filters and
  /// deleted markers. More than 10000 is an error, never truncation.
  Future<List<ObservationRecord>> list({
    String? measureId,
    String? fromDate,
    String? untilDate,
    Map<String, String> attributes = const {},
    bool includeDeleted = false,
  }) async {
    final rows = [
      for (final r in await repository.observationRecords(
        measureId: measureId,
        fromDate: fromDate,
        untilDate: untilDate,
      ))
        if ((includeDeleted || !r.deleted) &&
            attributes.entries.every(
              (e) => r.observation.attributes[e.key] == e.value,
            ))
          r,
    ];
    if (rows.length > 10000)
      invalid('More than 10000 observations match; narrow the query.');
    rows.sort((a, b) {
      final day = a.observation.localDate.compareTo(b.observation.localDate);
      if (day != 0) return day;
      final at = (a.observation.observedAt?.microsecondsSinceEpoch ?? -1)
          .compareTo(b.observation.observedAt?.microsecondsSinceEpoch ?? -1);
      return at != 0 ? at : a.observation.id.compareTo(b.observation.id);
    });
    return rows;
  }
}
