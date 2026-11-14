import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:intl/intl.dart';

/// Rudimentary message catalogs. Keys are stable identifiers; domain enums
/// and IDs are never replaced by translated labels. Each entry is either a
/// plain template or plural templates keyed by CLDR category, selected with
/// the locale's plural rules. `{name}` placeholders take explicit arguments.
const Map<String, Map<String, Object>> _catalogs = {
  'en': {
    'session.sets': {'one': '{count} set', 'other': '{count} sets'},
    'session.exercises': {
      'one': '{count} exercise',
      'other': '{count} exercises',
    },
    'session.repetitions': {'one': '{count} rep', 'other': '{count} reps'},
    'set.status.planned': 'Planned',
    'set.status.completed': 'Completed',
    'set.status.skipped': 'Skipped',
    'set.role.work': 'Work set',
    'set.role.warmup': 'Warm-up',
    'set.role.backoff': 'Back-off set',
    'set.role.drop': 'Drop set',
    'timer.confirm': 'Confirm the actual result for {exercise}.',
    'timer.nearEnd': '{seconds} seconds left',
    'progression.proposal': 'Proposed: {metric} {from} → {to}',
    'massStale': {
      'one': 'Body mass is {count} day old.',
      'other': 'Body mass is {count} days old.',
    },
    'duration.hour': 'h',
    'duration.minute': 'min',
    'duration.second': 's',
    'duration.millisecond': 'ms',
  },
  'sv': {
    'session.sets': {'one': '{count} set', 'other': '{count} set'},
    'session.exercises': {'one': '{count} övning', 'other': '{count} övningar'},
    'session.repetitions': {
      'one': '{count} repetition',
      'other': '{count} repetitioner',
    },
    'set.status.planned': 'Planerat',
    'set.status.completed': 'Genomfört',
    'set.status.skipped': 'Hoppat över',
    'set.role.work': 'Arbetsset',
    'set.role.warmup': 'Uppvärmning',
    'set.role.backoff': 'Nedtrappningsset',
    'set.role.drop': 'Dropset',
    'timer.confirm': 'Bekräfta det faktiska resultatet för {exercise}.',
    'timer.nearEnd': '{seconds} sekunder kvar',
    'progression.proposal': 'Förslag: {metric} {from} → {to}',
    'massStale': {
      'one': 'Kroppsvikten är {count} dag gammal.',
      'other': 'Kroppsvikten är {count} dagar gammal.',
    },
    'duration.hour': 'h',
    'duration.minute': 'min',
    'duration.second': 's',
    'duration.millisecond': 'ms',
  },
};

List<String> get messageKeys => (_catalogs['en']!.keys.toList()..sort());

/// The catalog a language uses: its own if present, else the `en` root.
String messageCatalogLocale(String language) =>
    _catalogs.containsKey(language) ? language : 'en';

/// Renders one message. A key missing from the language catalog falls back to
/// `en` and says so; an unknown key or argument is an error, never blank text.
Map<String, Object?> renderMessage(
  String locale,
  String language,
  String key,
  Map<String, Object?> args,
) {
  if (!_catalogs['en']!.containsKey(key))
    throw BodyTmiException('not_found', 'Unknown message key: $key.');
  var catalog = messageCatalogLocale(language);
  var entry = _catalogs[catalog]![key];
  if (entry == null) {
    catalog = 'en';
    entry = _catalogs['en']![key]!;
  }
  String template;
  if (entry is Map<String, String>) {
    final count = args['count'];
    if (count is! int || count < 0)
      invalid('Message $key needs a nonnegative integer count.');
    template = Intl.plural(
      count,
      zero: entry['zero'],
      one: entry['one'],
      two: entry['two'],
      few: entry['few'],
      many: entry['many'],
      other: entry['other']!,
      locale: catalog,
    );
  } else {
    template = entry as String;
  }
  final needed = {
    for (final m in RegExp(r'\{(\w+)\}').allMatches(template)) m[1]!,
  };
  if (entry is Map<String, String>) needed.add('count');
  final extra = args.keys.toSet().difference(needed);
  if (extra.isNotEmpty)
    invalid('Unknown message arguments: ${extra.join(', ')}.');
  final text = template.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) {
    final value = args[m[1]!];
    if (value is! String && value is! int)
      invalid('Message $key needs argument ${m[1]}.');
    return '$value';
  });
  return {
    'key': key,
    'locale': locale,
    'catalog': catalog,
    'fallback': catalog != language,
    'text': text,
  };
}
