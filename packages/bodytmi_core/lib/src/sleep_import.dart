import 'package:crypto/crypto.dart';
import 'dart:convert';

import 'errors.dart';
import 'instant.dart';
import 'sleep.dart';

const sleepImportFormat = 'bodytmi-sleep-import/1';
const _maxSleeps = 100000;

/// One entry of a `bodytmi-sleep-import/1` document: a sleep record without
/// version or storage identity, keyed by its source id.
final class ImportedSleep {
  ImportedSleep._(this.sourceId, this.json);
  factory ImportedSleep.fromJson(Object? input, String namespace) {
    final j = jsonObject(input, 'imported sleep');
    if (j.containsKey('version') || j.containsKey('import'))
      invalid('An imported sleep has no version or import field.');
    final sourceId = requiredString(j, 'sourceId');
    if (sourceId.length > 256)
      invalid('An import sourceId is 1 to 256 characters.');
    final item = ImportedSleep._(sourceId, Map.unmodifiable(j));
    item.record(namespace, 1);
    return item;
  }

  final String sourceId;
  final Map<String, Object?> json;

  /// The stored identity: explicit, or `<namespace>-<24 hex of SHA-256>`.
  String id(String namespace) =>
      json['id'] as String? ??
      '$namespace-${sha256.convert(utf8.encode('$namespace\u0000$sourceId')).toString().substring(0, 24)}';

  SleepRecord record(String namespace, int version) => SleepRecord.fromJson({
    for (final e in json.entries)
      if (e.key != 'sourceId') e.key: e.value,
    'id': id(namespace),
    'version': version,
    'import': {'namespace': namespace, 'sourceId': sourceId},
  });
}

/// A neutral, documented bulk import of sleep and nap intervals (D16).
/// Entered offsets are kept as written.
final class SleepImportDocument {
  SleepImportDocument._(this.namespace, this.source, this.sleeps);

  factory SleepImportDocument.fromJson(Object? input) {
    final j = jsonObject(input, 'sleep import');
    checkKeys(j, {'format', 'source', 'sleeps'});
    if (j['format'] != sleepImportFormat)
      invalid('Unsupported sleep import format; expected $sleepImportFormat.');
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
    final list = jsonList(j, 'sleeps');
    if (list.isEmpty) invalid('A sleep import needs sleeps.');
    if (list.length > _maxSleeps)
      invalid('A sleep import holds at most $_maxSleeps sleeps.');
    final items = [for (final o in list) ImportedSleep.fromJson(o, namespace)];
    final sourceIds = <String>{}, ids = <String>{};
    for (final item in items) {
      if (!sourceIds.add(item.sourceId))
        invalid('Duplicate import sourceId: ${item.sourceId}.');
      if (!ids.add(item.id(namespace)))
        invalid('Duplicate sleep id: ${item.id(namespace)}.');
    }
    validateSleepRecords([for (final i in items) i.record(namespace, 1)]);
    return SleepImportDocument._(
      namespace,
      Map.unmodifiable(source),
      List.unmodifiable(items),
    );
  }

  final String namespace;
  final Map<String, Object?> source;
  final List<ImportedSleep> sleeps;
}
