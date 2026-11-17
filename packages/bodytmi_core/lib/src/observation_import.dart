import 'package:crypto/crypto.dart';
import 'dart:convert';

import 'errors.dart';
import 'instant.dart';
import 'observation.dart';

const observationImportFormat = 'bodytmi-observation-import/1';
const _maxObservations = 100000;

/// One entry of a `bodytmi-observation-import/1` document: an observation
/// without storage identity, keyed by its source id. The stored observation
/// id is the entry's `id`, or a deterministic one derived from namespace and
/// source id, so importing the same file again never creates a second record.
final class ImportedObservation {
  ImportedObservation._(this.sourceId, this.json);
  factory ImportedObservation.fromJson(Object? input, String namespace) {
    final j = jsonObject(input, 'imported observation');
    checkKeys(j, {
      'sourceId',
      'id',
      'measure',
      'value',
      'observedAt',
      'date',
      'attributes',
      'source',
      'notes',
    });
    final sourceId = requiredString(j, 'sourceId');
    if (sourceId.isEmpty || sourceId.length > 256)
      invalid('An import sourceId is 1 to 256 characters.');
    final item = ImportedObservation._(sourceId, Map.unmodifiable(j));
    item.observation(namespace, 1); // validates the observation shape
    return item;
  }

  final String sourceId;
  final Map<String, Object?> json;

  /// The stored identity: explicit, or `<namespace>-<24 hex of SHA-256>`.
  String id(String namespace) =>
      json['id'] as String? ??
      '$namespace-${sha256.convert(utf8.encode('$namespace\u0000$sourceId')).toString().substring(0, 24)}';

  Observation observation(String namespace, int contentVersion) =>
      Observation.fromJson({
        for (final e in json.entries)
          if (e.key != 'sourceId') e.key: e.value,
        'id': id(namespace),
        'contentVersion': contentVersion,
        'import': {'namespace': namespace, 'sourceId': sourceId},
      });
}

/// A neutral, documented bulk import of observations of any measure (D16).
/// Entered units, offsets and date-only entries are kept as written.
final class ObservationImportDocument {
  ObservationImportDocument._(this.namespace, this.source, this.observations);

  factory ObservationImportDocument.fromJson(Object? input) {
    final j = jsonObject(input, 'observation import');
    checkKeys(j, {'format', 'source', 'observations'});
    if (j['format'] != observationImportFormat)
      invalid(
        'Unsupported observation import format; expected '
        '$observationImportFormat.',
      );
    final source = jsonObject(j['source'], 'source');
    checkKeys(source, {'namespace', 'app', 'version', 'exportedAt'});
    final namespace = identifier(source, 'namespace');
    if (namespace.length > 64)
      invalid('source namespace must be at most 64 characters.');
    for (final key in ['app', 'version']) {
      final v = source[key];
      if (v != null && (v is! String || v.isEmpty || v.length > 200))
        invalid('source $key is nonempty text of at most 200.');
    }
    if (source['exportedAt'] != null)
      parseInstant(source['exportedAt'], 'exportedAt');
    final list = jsonList(j, 'observations');
    if (list.isEmpty) invalid('An observation import needs observations.');
    if (list.length > _maxObservations)
      invalid(
        'An observation import holds at most $_maxObservations observations.',
      );
    final items = [
      for (final o in list) ImportedObservation.fromJson(o, namespace),
    ];
    final sourceIds = <String>{}, ids = <String>{};
    for (final item in items) {
      if (!sourceIds.add(item.sourceId))
        invalid('Duplicate import sourceId: ${item.sourceId}.');
      if (!ids.add(item.id(namespace)))
        invalid('Duplicate observation id: ${item.id(namespace)}.');
    }
    return ObservationImportDocument._(
      namespace,
      Map.unmodifiable(source),
      List.unmodifiable(items),
    );
  }

  final String namespace;
  final Map<String, Object?> source;
  final List<ImportedObservation> observations;
}
