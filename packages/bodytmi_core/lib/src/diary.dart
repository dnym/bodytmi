import 'diet.dart' show addDays;
import 'errors.dart';
import 'food.dart';
import 'fraction.dart';
import 'instant.dart';
import 'nutrient.dart';
import 'quantity.dart';

/// Default start of a diary day, minutes after local midnight (04:00): a
/// 01:00 snack belongs to the evening before.
const defaultDiaryDayStart = 240;

final _date = RegExp(r'^\d{4}-\d{2}-\d{2}$');

String checkDate(Object? value, String label) {
  if (value is! String ||
      !_date.hasMatch(value) ||
      DateTime.tryParse(
            '${value}T00:00:00Z',
          )?.toIso8601String().substring(0, 10) !=
          value)
    invalid('$label must be a valid YYYY-MM-DD date.');
  return value;
}

/// The diary date of an instant entered with an offset: its local date,
/// or the day before when the local time is before [dayStart] minutes.
String diaryDate(String at, {int dayStart = defaultDiaryDayStart}) {
  final instant = parseInstant(at, 'at');
  final offset = parseOffsetMinutes(at, 'at');
  final local = instant.add(Duration(minutes: offset - dayStart));
  return local.toIso8601String().substring(0, 10);
}

/// Parses `HH:MM` from 00:00 to 12:00 into minutes after midnight.
int parseDayStart(Object? value) {
  if (value is! String || !RegExp(r'^\d{2}:\d{2}$').hasMatch(value))
    invalid('dayStart is HH:MM.');
  final minutes =
      int.parse(value.substring(0, 2)) * 60 + int.parse(value.substring(3));
  if (int.parse(value.substring(3)) > 59 || minutes > 12 * 60)
    invalid('dayStart is from 00:00 to 12:00.');
  return minutes;
}

String formatDayStart(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

/// One diary entry: a pinned food revision and amount, or a quick entry of
/// nutrients without a food. Entries are edited in place (content version)
/// without an audit trail.
final class DiaryEntry {
  DiaryEntry._({
    required this.id,
    required this.version,
    required this.at,
    required this.date,
    required this.meal,
    required this.notes,
    required this.food,
    required this.amount,
    required this.quick,
  });

  /// [dayStart] assigns the date when the input has none. An explicit date
  /// must be the local date of [at] or the day before.
  factory DiaryEntry.fromJson(
    Object? input, {
    int dayStart = defaultDiaryDayStart,
  }) {
    final j = jsonObject(input, 'diary entry');
    checkKeys(j, {
      'id',
      'version',
      'at',
      'date',
      'meal',
      'notes',
      'food',
      'amount',
      'quick',
    });
    final at = j['at'];
    parseInstant(at, 'at');
    final local = (at as String).substring(0, 10);
    final date = j.containsKey('date')
        ? checkDate(j['date'], 'date')
        : diaryDate(at, dayStart: dayStart);
    if (date != local && date != addDays(local, -1))
      invalid('A diary date is the local date of the entry or the day before.');
    final version = j['version'] ?? 1;
    if (version is! int || version < 1) invalid('version must be positive.');
    final meal = j['meal'];
    if (meal != null &&
        (meal is! String || meal.trim().isEmpty || meal.length > 64))
      invalid('A meal label is nonempty text of at most 64 characters.');
    final notes = j['notes'];
    if (notes != null &&
        (notes is! String || notes.trim().isEmpty || notes.length > 4000))
      invalid('Notes are nonempty text of at most 4000 characters.');
    final hasFood = j.containsKey('food');
    if (hasFood == j.containsKey('quick'))
      invalid('A diary entry has exactly one of food and quick.');
    if (hasFood != j.containsKey('amount'))
      invalid('A food entry has an amount; a quick entry has none.');
    Map<String, Quantity> quick = const {};
    if (!hasFood) {
      final q = jsonObject(j['quick'], 'quick');
      if (q.isEmpty) invalid('A quick entry declares at least one nutrient.');
      quick = {};
      for (final e in q.entries) {
        final def = nutrient(e.key);
        final value = Quantity.fromJson(e.value);
        if (value.dimension != def.unit.dimension)
          invalid('Nutrient ${e.key} must be ${def.unit.dimension.name}.');
        quick[e.key] = value;
      }
    }
    return DiaryEntry._(
      id: identifier(j, 'id'),
      version: version,
      at: at,
      date: date,
      meal: meal as String?,
      notes: notes as String?,
      food: hasFood ? foodRefFromJson(j['food'], 'food') : null,
      amount: hasFood ? FoodAmount.fromJson(j['amount'], 'amount') : null,
      quick: Map.unmodifiable(quick),
    );
  }

  final String id;
  final int version;
  final String at;
  final String date;
  final String? meal;
  final String? notes;
  final FoodRef? food;
  final FoodAmount? amount;
  final Map<String, Quantity> quick;

  DateTime get instant => parseInstant(at, 'at');

  Map<String, Object?> toJson() => {
    'id': id,
    'version': version,
    'at': at,
    'date': date,
    if (meal != null) 'meal': meal,
    if (notes != null) 'notes': notes,
    if (food != null) ...{
      'food': foodRefToJson(food!),
      'amount': amount!.toJson(),
    } else
      'quick': {for (final e in quick.entries) e.key: e.value.toJson()},
  };

  /// Nutrition of this entry; a quick entry is one item.
  Nutrition nutrition(FoodMath math) {
    if (food != null) return math.of(math.lookup(food!), amount!);
    return Nutrition(
      1,
      {for (final e in quick.entries) e.key: Fraction.decimal(e.value.value)},
      {for (final k in quick.keys) k: 1},
      null,
    );
  }
}

/// A day's explicit logging status. Without a mark a day with entries is
/// partial and a day without entries is unlogged; `complete` asserts the
/// diary holds everything eaten (possibly nothing).
const diaryDayStatuses = {'complete', 'partial', 'unmarked'};

final class DiaryDayMark {
  DiaryDayMark._(this.date, this.status);
  factory DiaryDayMark.fromJson(Object? input) {
    final j = jsonObject(input, 'diary day');
    checkKeys(j, {'date', 'status'});
    final status = j['status'];
    if (status is! String || !diaryDayStatuses.contains(status))
      invalid('A diary day status is complete, partial or unmarked.');
    return DiaryDayMark._(checkDate(j['date'], 'date'), status);
  }
  final String date;
  final String status;
  Map<String, Object?> toJson() => {'date': date, 'status': status};
}

/// The effective status of one day.
String diaryDayStatus(DiaryDayMark? mark, int entries) {
  if (mark != null && mark.status != 'unmarked') return mark.status;
  return entries == 0 ? 'unlogged' : 'partial';
}

/// Diary settings: when a diary day starts.
final class DiarySettingsRevision {
  DiarySettingsRevision._(this.number, this.dayStart);
  factory DiarySettingsRevision.publish(
    int dayStart, {
    DiarySettingsRevision? previous,
  }) => DiarySettingsRevision._((previous?.number ?? 0) + 1, dayStart);
  factory DiarySettingsRevision.fromJson(Object? input) {
    final j = jsonObject(input, 'diary settings');
    checkKeys(j, {'schemaVersion', 'revision', 'dayStart'});
    final n = j['revision'];
    if (j['schemaVersion'] != 1 || n is! int || n < 1)
      invalid('Invalid diary settings revision.');
    return DiarySettingsRevision._(n, parseDayStart(j['dayStart']));
  }
  final int number;
  final int dayStart;
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'revision': number,
    'dayStart': formatDayStart(dayStart),
  };
}

/// Entries have unique IDs and reference published food revisions whose
/// amounts can be logged.
void validateDiaryEntries(List<DiaryEntry> entries, List<FoodRevision> foods) {
  final byKey = {for (final f in foods) foodRefKey(f.ref): f};
  final math = FoodMath(
    (ref) =>
        byKey[foodRefKey(ref)] ??
        invalid('Food revision ${foodRefKey(ref)} is not published.'),
  );
  final ids = <String>{};
  for (final e in entries) {
    if (!ids.add(e.id)) invalid('Duplicate diary entry ${e.id}.');
    e.nutrition(math);
  }
}
