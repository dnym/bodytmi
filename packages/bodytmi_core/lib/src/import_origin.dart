import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'errors.dart';
import 'instant.dart';

/// Where an imported record came from: the document namespace and the
/// source's own identifier for it.
typedef ImportOrigin = ({String namespace, String sourceId});

ImportOrigin importOriginFromJson(Object? input) {
  final j = jsonObject(input, 'import');
  checkKeys(j, {'namespace', 'sourceId'});
  final namespace = identifier(j, 'namespace');
  if (namespace.length > 64)
    invalid('An import namespace is at most 64 characters.');
  return (namespace: namespace, sourceId: importSourceId(j));
}

Map<String, Object?> importOriginToJson(ImportOrigin origin) => {
  'namespace': origin.namespace,
  'sourceId': origin.sourceId,
};

String importSourceId(Map<String, Object?> j) {
  final s = requiredString(j, 'sourceId');
  if (s.length > 256) invalid('An import sourceId is 1 to 256 characters.');
  return s;
}

/// The stored identity of an imported record without an explicit id:
/// `<namespace>-<first 24 hex digits of SHA-256(namespace NUL sourceId)>`.
String importedId(String namespace, String sourceId) =>
    '$namespace-${sha256.convert(utf8.encode('$namespace\u0000$sourceId')).toString().substring(0, 24)}';

/// The common `source` header of a neutral import document.
({String namespace, Map<String, Object?> source}) importHeader(
  Map<String, Object?> j,
  String format,
  String label,
) {
  if (j['format'] != format)
    invalid('Unsupported $label format; expected $format.');
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
  return (namespace: namespace, source: Map.unmodifiable(source));
}
