import 'package:bodytmi_core/bodytmi_core.dart';

const catalogSearchKinds = ['exercise', 'implementation', 'equipment'];
const _ranks = ['exact', 'prefix', 'word-prefix', 'substring'];

typedef _Entry = ({
  String kind,
  String id,
  int revision,
  String? name,
  CatalogLabels labels,
  String? exerciseId,
});

int? _rank(String key, String query) {
  if (key == query) return 0;
  if (key.startsWith(query)) return 1;
  if (key.split(' ').skip(1).any((w) => w.startsWith(query))) return 2;
  if (key.contains(query)) return 3;
  return null;
}

/// Read-only catalog search (policy bodytmi-catalog-search/1) over the latest
/// revision of each exercise, implementation and equipment entry. Matching is
/// case-insensitive with collapsed whitespace and no accent folding; it ranks
/// exact, prefix, word-prefix, then substring matches of the identifier, root
/// name, label names and aliases. With [locale] only that locale's labels
/// (exact, then language-only) plus the root name and identifier are searched;
/// without it every label is. Display names resolve exact, language, then the
/// root name. Labels never change identity, prescriptions or history.
Map<String, Object?> searchCatalog({
  required String query,
  String? locale,
  List<String> kinds = catalogSearchKinds,
  int limit = 50,
  List<ExerciseRevision> exercises = const [],
  List<ImplementationRevision> implementations = const [],
  List<EquipmentRevision> equipment = const [],
}) {
  final normalized = catalogSearchKey(query);
  if (normalized.isEmpty || query.length > 200)
    invalid('query must be nonempty text of at most 200 characters.');
  if (locale != null) catalogLocaleTag(locale, 'locale');
  if (kinds.isEmpty ||
      kinds.toSet().length != kinds.length ||
      kinds.any((k) => !catalogSearchKinds.contains(k)))
    invalid(
      'kinds must list distinct values among exercise, implementation, equipment.',
    );
  if (limit < 1 || limit > 1000) invalid('limit must be within 1–1000.');

  Map<String, T> latest<T>(
    Iterable<T> all,
    String Function(T) id,
    int Function(T) number,
  ) {
    final out = <String, T>{};
    for (final r in all) {
      final prior = out[id(r)];
      if (prior == null || number(prior) < number(r)) out[id(r)] = r;
    }
    return out;
  }

  final entries = <_Entry>[
    if (kinds.contains('exercise'))
      for (final r in latest(
        exercises,
        (r) => r.exercise.id,
        (r) => r.number,
      ).values)
        (
          kind: 'exercise',
          id: r.exercise.id,
          revision: r.number,
          name: r.exercise.name,
          labels: r.exercise.labels,
          exerciseId: null,
        ),
    if (kinds.contains('implementation'))
      for (final r in latest(
        implementations,
        (r) => r.implementation.id,
        (r) => r.number,
      ).values)
        (
          kind: 'implementation',
          id: r.implementation.id,
          revision: r.number,
          name: r.implementation.name,
          labels: r.implementation.labels,
          exerciseId: r.implementation.exerciseId,
        ),
    if (kinds.contains('equipment'))
      for (final r in latest(
        equipment,
        (r) => r.equipment.id,
        (r) => r.number,
      ).values)
        (
          kind: 'equipment',
          id: r.equipment.id,
          revision: r.number,
          name: r.equipment.name,
          labels: r.equipment.labels,
          exerciseId: null,
        ),
  ];

  final hits = <({int rank, _Entry entry, Map<String, Object?> match})>[];
  for (final entry in entries) {
    final candidates = <({String field, String? locale, String text})>[
      (field: 'id', locale: null, text: entry.id),
      if (entry.name != null) (field: 'name', locale: null, text: entry.name!),
      for (final tag
          in locale == null
              ? entry.labels.entries.keys
              : entry.labels.chain(locale)) ...[
        if (entry.labels.entries[tag]!.name != null)
          (field: 'label', locale: tag, text: entry.labels.entries[tag]!.name!),
        for (final alias in entry.labels.entries[tag]!.aliases)
          (field: 'alias', locale: tag, text: alias),
      ],
    ];
    ({int rank, Map<String, Object?> match})? best;
    for (final c in candidates) {
      final rank = _rank(catalogSearchKey(c.text), normalized);
      if (rank == null || (best != null && best.rank <= rank)) continue;
      best = (
        rank: rank,
        match: {
          'rank': _ranks[rank],
          'field': c.field,
          if (c.locale != null) 'locale': c.locale,
          'text': c.text,
        },
      );
    }
    if (best != null)
      hits.add((rank: best.rank, entry: entry, match: best.match));
  }
  hits.sort((a, b) {
    final rank = a.rank.compareTo(b.rank);
    if (rank != 0) return rank;
    final kind = catalogSearchKinds
        .indexOf(a.entry.kind)
        .compareTo(catalogSearchKinds.indexOf(b.entry.kind));
    return kind != 0 ? kind : a.entry.id.compareTo(b.entry.id);
  });
  return {
    'policy': 'bodytmi-catalog-search/1',
    'query': query,
    'normalizedQuery': normalized,
    'locale': locale,
    'kinds': kinds,
    'totalCount': hits.length,
    'truncated': hits.length > limit,
    'results': [
      for (final hit in hits.take(limit))
        () {
          final e = hit.entry;
          final display = locale == null
              ? (
                  name: e.name,
                  match: e.name == null ? 'none' : 'root',
                  locale: null,
                )
              : e.labels.display(locale, e.name);
          return {
            'kind': e.kind,
            'id': e.id,
            'revision': e.revision,
            if (e.exerciseId != null) 'exerciseId': e.exerciseId,
            'displayName': display.name,
            'displayMatch': display.match,
            if (display.locale != null) 'displayLocale': display.locale,
            'match': hit.match,
          };
        }(),
    ],
  };
}
