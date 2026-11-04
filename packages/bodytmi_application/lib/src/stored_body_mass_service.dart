import 'package:bodytmi_core/bodytmi_core.dart';
import 'body_mass_service.dart';
import 'canonical_json.dart';
import 'training_repository.dart';

/// A retained deletion prevents reuse of an observation's stable identity.
/// This stores only the latest content, not a correction audit trail.
final class BodyMassRecord {
  BodyMassRecord(this.measurement, {this.deleted = false}) {
    if (deleted && measurement.contentVersion < 2)
      invalid('Deleted observation must have a deletion content version.');
  }
  factory BodyMassRecord.fromJson(Object? input) {
    final j = jsonObject(input, 'body-mass record');
    checkKeys(j, {'measurement', 'deleted'});
    if (j['deleted'] is! bool) invalid('deleted must be boolean.');
    final record = BodyMassRecord(
      BodyMassMeasurement.fromJson(j['measurement']),
      deleted: j['deleted'] as bool,
    );
    return record;
  }
  final BodyMassMeasurement measurement;
  final bool deleted;
  Map<String, Object?> toJson() => {
    'measurement': measurement.toJson(),
    'deleted': deleted,
  };
}

final class StoredBodyMassService {
  const StoredBodyMassService(this.repository);
  final TrainingRepository repository;

  Future<BodyMassRecord> show(String id) async =>
      (await repository.bodyMassRecords())
          .where((r) => r.measurement.id == id)
          .firstOrNull ??
      (throw const BodyTmiException(
        'not_found',
        'Body-mass observation not found.',
      ));

  Future<List<BodyMassRecord>> list({
    String? context,
    bool includeDeleted = false,
  }) async {
    if (context != null) identifier({'id': context}, 'id');
    return (await repository.bodyMassRecords())
        .where(
          (r) =>
              (includeDeleted || !r.deleted) &&
              (context == null || r.measurement.context == context),
        )
        .toList()
      ..sort((a, b) {
        final time = a.measurement.observedAt.compareTo(
          b.measurement.observedAt,
        );
        return time == 0 ? a.measurement.id.compareTo(b.measurement.id) : time;
      });
  }

  /// Expected zero creates; a positive version replaces the entire observation.
  /// Supplying versions in the observation itself is deliberately forbidden.
  Future<BodyMassRecord> save(
    Map<String, Object?> observation,
    int expectedVersion,
  ) => repository.transaction(() async {
    checkKeys(observation, {
      'id',
      'context',
      'observedAt',
      'mass',
      'source',
      'notes',
    });
    if (expectedVersion < 0) invalid('expectedVersion must be nonnegative.');
    final next = BodyMassRecord(
      BodyMassMeasurement.fromJson({
        ...observation,
        'contentVersion': expectedVersion + 1,
      }),
    );
    final current = (await repository.bodyMassRecords())
        .where((r) => r.measurement.id == next.measurement.id)
        .firstOrNull;
    // Lost responses may retry precisely the same content and prior version.
    if (current != null &&
        canonicalJson(current.toJson()) == canonicalJson(next.toJson()))
      return current;
    if (current?.deleted == true ||
        (current?.measurement.contentVersion ?? 0) != expectedVersion)
      _conflict();
    if (current == null && expectedVersion != 0) _conflict();
    await repository.saveBodyMassRecord(next);
    return next;
  });

  Future<BodyMassRecord> delete(
    String id,
    int expectedVersion, {
    required bool confirm,
  }) => repository.transaction(() async {
    identifier({'id': id}, 'id');
    if (expectedVersion < 1) invalid('expectedVersion must be positive.');
    if (!confirm) invalid('Deleting an observation requires confirm:true.');
    final current = await show(id);
    if (current.deleted) {
      if (current.measurement.contentVersion != expectedVersion + 1)
        _conflict();
      return current;
    }
    if (current.measurement.contentVersion != expectedVersion) _conflict();
    final next = BodyMassRecord(
      BodyMassMeasurement.fromJson({
        ...current.measurement.toJson(),
        'contentVersion': expectedVersion + 1,
      }),
      deleted: true,
    );
    await repository.saveBodyMassRecord(next);
    return next;
  });

  Future<BodyMassTrend> trend(Map<String, Object?> input) =>
      repository.transaction(() async {
        checkKeys(input, {'context', 'asOf', 'dailyMode'});
        return const BodyMassService().trend({
          ...input,
          'measurements': [
            for (final r in await list()) r.measurement.toJson(),
          ],
        });
      });
  Future<BodyMassResolution> resolve(Map<String, Object?> input) =>
      repository.transaction(() async {
        checkKeys(input, {
          'context',
          'asOf',
          'dailyMode',
          'override',
          'staleAfterDays',
          'warnIfStale',
        });
        return const BodyMassService().resolve({
          ...input,
          'measurements': [
            for (final r in await list()) r.measurement.toJson(),
          ],
        });
      });
}

Never _conflict() => throw const BodyTmiException(
  'conflict',
  'Body-mass observation changed or identity already exists. Refresh before retrying.',
);
