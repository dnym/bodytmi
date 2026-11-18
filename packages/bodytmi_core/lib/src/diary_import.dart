import 'diary.dart';
import 'errors.dart';
import 'import_origin.dart';

const diaryImportFormat = 'bodytmi-diary-import/1';
const _maxEntries = 200000;

/// How an imported entry names its food: a food id (with an optional
/// revision), or the namespace and source id of a food written by a
/// `bodytmi-food-import/1` document. Without a revision the latest revision
/// is pinned on first import and kept on later imports.
typedef ImportedFoodRef = ({
  String? id,
  String? namespace,
  String? sourceId,
  int? revision,
});

/// One entry of a `bodytmi-diary-import/1` document: a diary entry without
/// version, keyed by its source id.
final class ImportedDiaryEntry {
  ImportedDiaryEntry._(this.sourceId, this.id, this.json, this.food);

  factory ImportedDiaryEntry.fromJson(Object? input, String namespace) {
    final j = jsonObject(input, 'imported diary entry');
    if (j.containsKey('version') || j.containsKey('import'))
      invalid('An imported diary entry has no version or import field.');
    final sourceId = importSourceId(j);
    final id = j.containsKey('id')
        ? identifier(j, 'id')
        : importedId(namespace, sourceId);
    ImportedFoodRef? food;
    if (j.containsKey('food')) {
      final f = jsonObject(j['food'], 'food');
      checkKeys(f, {'id', 'namespace', 'sourceId', 'revision'});
      final revision = f['revision'];
      if (revision != null && (revision is! int || revision < 1))
        invalid('food revision must be a positive integer.');
      if (f.containsKey('id') == f.containsKey('sourceId'))
        invalid('An imported entry food names id, or namespace and sourceId.');
      if (f.containsKey('id')) {
        if (f.containsKey('namespace'))
          invalid('A food id is not combined with a namespace.');
        food = (
          id: identifier(f, 'id'),
          namespace: null,
          sourceId: null,
          revision: revision as int?,
        );
      } else {
        food = (
          id: null,
          namespace: identifier(f, 'namespace'),
          sourceId: importSourceId(f),
          revision: revision as int?,
        );
      }
    }
    final item = ImportedDiaryEntry._(sourceId, id, Map.unmodifiable(j), food);
    item.entry(namespace, 1, food == null ? null : (id: 'probe', revision: 1));
    return item;
  }

  final String sourceId;
  final String id;
  final Map<String, Object?> json;
  final ImportedFoodRef? food;

  /// The entry with its food resolved to [pinned].
  DiaryEntry entry(
    String namespace,
    int version,
    ({String id, int revision})? pinned, {
    int dayStart = defaultDiaryDayStart,
  }) => DiaryEntry.fromJson({
    for (final e in json.entries)
      if (e.key != 'sourceId') e.key: e.value,
    'id': id,
    'version': version,
    if (pinned != null) 'food': {'id': pinned.id, 'revision': pinned.revision},
    'import': {'namespace': namespace, 'sourceId': sourceId},
  }, dayStart: dayStart);
}

/// A neutral, documented bulk import of food diary entries and optional
/// day marks (D16).
final class DiaryImportDocument {
  DiaryImportDocument._(this.namespace, this.source, this.entries, this.days);

  factory DiaryImportDocument.fromJson(Object? input) {
    final j = jsonObject(input, 'diary import');
    checkKeys(j, {'format', 'source', 'entries', 'days'});
    final header = importHeader(j, diaryImportFormat, 'diary import');
    final ns = header.namespace;
    final list = jsonList(j, 'entries');
    if (list.length > _maxEntries)
      invalid('A diary import holds at most $_maxEntries entries.');
    final entries = [for (final o in list) ImportedDiaryEntry.fromJson(o, ns)];
    final sourceIds = <String>{}, ids = <String>{};
    for (final e in entries) {
      if (!sourceIds.add(e.sourceId))
        invalid('Duplicate import sourceId: ${e.sourceId}.');
      if (!ids.add(e.id)) invalid('Duplicate diary entry id: ${e.id}.');
    }
    final days = <DiaryDayMark>[];
    if (j.containsKey('days')) {
      final seen = <String>{};
      for (final d in jsonList(j, 'days')) {
        final mark = DiaryDayMark.fromJson(d);
        if (!seen.add(mark.date)) invalid('Duplicate day mark ${mark.date}.');
        days.add(mark);
      }
    }
    if (entries.isEmpty && days.isEmpty)
      invalid('A diary import needs entries or days.');
    return DiaryImportDocument._(
      ns,
      header.source,
      List.unmodifiable(entries),
      List.unmodifiable(days),
    );
  }

  final String namespace;
  final Map<String, Object?> source;
  final List<ImportedDiaryEntry> entries;
  final List<DiaryDayMark> days;
}
