import 'package:bodytmi_core/bodytmi_core.dart';

import 'diary_budget.dart';
import 'diet_service.dart';
import 'food_service.dart';
import 'training_repository.dart';

const diaryDayKind = 'diary-day';
const diarySettingsKind = 'diary-settings';

/// The food diary: entries, day marks and totals with coverage.
final class DiaryService {
  const DiaryService(this.repository);
  final TrainingRepository repository;

  FoodService get _foods => FoodService(repository);

  Future<DiarySettingsRevision?> settings() async {
    final rows = await repository.dietRecords(kind: diarySettingsKind);
    return rows.isEmpty
        ? null
        : DiarySettingsRevision.fromJson(rows.last.snapshot);
  }

  Future<int> dayStart() async =>
      (await settings())?.dayStart ?? defaultDiaryDayStart;

  Future<DiarySettingsRevision> setDayStart(
    int dayStart,
    int expectedRevision,
  ) => repository.transaction(() async {
    final before = await settings();
    if ((before?.number ?? 0) != expectedRevision)
      throw const BodyTmiException('conflict', 'Diary settings changed.');
    final next = DiarySettingsRevision.publish(dayStart, previous: before);
    await repository.saveDietRecord(
      DietRecord(diarySettingsKind, 'diary', next.number, next.toJson()),
    );
    return next;
  });

  /// Pins the latest revision when the entry names a food without one.
  Future<DiaryEntry> _parse(Map<String, Object?> input, int version) async {
    final json = Map<String, Object?>.of(input);
    if (json.containsKey('version'))
      invalid('The service assigns the entry version.');
    json['version'] = version;
    if (json['food'] case final Map<String, Object?> ref
        when !ref.containsKey('revision')) {
      final id = identifier(ref, 'id');
      json['food'] = {...ref, 'revision': (await _foods.revision(id)).number};
    }
    final entry = DiaryEntry.fromJson(json, dayStart: await dayStart());
    entry.nutrition(FoodMath(await _foods.lookup()));
    return entry;
  }

  Future<DiaryEntry> add(Map<String, Object?> input) =>
      repository.transaction(() async {
        final entry = await _parse(input, 1);
        if (await repository.diaryEntry(entry.id) != null)
          throw BodyTmiException('conflict', 'Diary entry ${entry.id} exists.');
        await repository.saveDiaryEntry(entry);
        return entry;
      });

  Future<DiaryEntry> entry(String id) async =>
      await repository.diaryEntry(id) ??
      (throw BodyTmiException('not_found', 'Diary entry $id not found.'));

  /// Replaces an entry's content; its version increases by one.
  Future<DiaryEntry> update(
    String id,
    int expectedVersion,
    Map<String, Object?> input,
  ) => repository.transaction(() async {
    final before = await entry(id);
    if (before.version != expectedVersion)
      throw const BodyTmiException('conflict', 'Diary entry changed.');
    if (input['id'] != id) invalid('An update keeps the entry id.');
    final next = await _parse(input, before.version + 1);
    await repository.saveDiaryEntry(next);
    return next;
  });

  Future<void> delete(String id, int expectedVersion) =>
      repository.transaction(() async {
        final before = await entry(id);
        if (before.version != expectedVersion)
          throw const BodyTmiException('conflict', 'Diary entry changed.');
        await repository.deleteDiaryEntry(id);
      });

  /// Logs a volume or mass of water through the profile's `water` food,
  /// publishing it on first use.
  Future<DiaryEntry> water({
    required String id,
    required String at,
    required Quantity amount,
    String? meal,
  }) => repository.transaction(() async {
    if (amount.dimension != Dimension.volume &&
        amount.dimension != Dimension.mass)
      invalid('Water is logged by volume or mass.');
    final existing = await repository.foodRevisions(foodId: 'water');
    if (existing.isEmpty) {
      await _foods.publish(Food.fromJson(waterFood), 0);
    }
    return add({
      'id': id,
      'at': at,
      'meal': ?meal,
      'food': {'id': 'water'},
      'amount': amount.toJson(),
    });
  });

  /// Copies the entries of [fromDate] (one [meal] when given) to [toDate]
  /// at the same local times, pinning the same food revisions. New IDs are
  /// `<idPrefix>-<n>` from 1.
  Future<List<DiaryEntry>> repeat({
    required String fromDate,
    required String toDate,
    required String idPrefix,
    String? meal,
  }) => repository.transaction(() async {
    final days = daysBetween(fromDate, toDate);
    if (days == 0) invalid('Repeat to another date.');
    final source = [
      for (final e in await _entries(fromDate))
        if (meal == null || e.meal == meal) e,
    ];
    if (source.isEmpty)
      throw const BodyTmiException('not_found', 'No entries to repeat.');
    final copies = <DiaryEntry>[];
    for (var i = 0; i < source.length; i++) {
      final json = source[i].toJson()..remove('version');
      json['id'] = '$idPrefix-${i + 1}';
      json['date'] = toDate;
      json['at'] = _shiftDays(source[i].at, days);
      copies.add(await add(json));
    }
    return copies;
  });

  Future<List<DiaryEntry>> _entries(String date) =>
      repository.diaryEntries(fromDate: date, untilDate: addDays(date, 1));

  Future<DiaryDayMark?> mark(String date) async {
    final rows = await repository.dietRecords(kind: diaryDayKind);
    for (final r in rows) {
      if (r.id == _markId(date)) {
        return DiaryDayMark.fromJson(r.snapshot);
      }
    }
    return null;
  }

  Future<DiaryDayMark> setMark(String date, String status) =>
      repository.transaction(() async {
        final mark = DiaryDayMark.fromJson({'date': date, 'status': status});
        await repository.saveDietRecord(
          DietRecord(diaryDayKind, _markId(date), 1, mark.toJson()),
        );
        return mark;
      });

  /// Entries, status and totals of one diary date.
  Future<Map<String, Object?>> day(
    String date, {
    List<String>? nutrients,
    bool all = false,
  }) async {
    checkDate(date, 'date');
    final math = FoodMath(await _foods.lookup());
    final entries = await _entries(date);
    final mark = await this.mark(date);
    var total = Nutrition.empty;
    final rows = <Map<String, Object?>>[];
    for (final e in entries) {
      final n = e.nutrition(math);
      total += n;
      rows.add({
        'entry': e.toJson(),
        if (e.food != null) 'foodName': math.lookup(e.food!).food.name,
        'nutrition': n.toJson(ids: nutrients, all: all),
      });
    }
    final plan = await _planDay(date);
    return {
      'date': date,
      'status': diaryDayStatus(mark, entries.length),
      'entries': rows,
      'totals': total.toJson(ids: nutrients, all: all),
      'budget': plan == null ? null : dayBudget(plan, total),
    };
  }

  /// The diet-run day in force on [date] with resolved goals, or null.
  Future<Map<String, Object?>?> _planDay(String date) async {
    final day =
        ((await DietService(repository).schedule(date, 1))['days']! as List)
                .single
            as Map<String, Object?>;
    return day['goals'] == null ? null : day;
  }

  /// Adherence to the diet-run goals over [from, until).
  Future<Map<String, Object?>> adherenceReport(
    String from,
    String until, {
    Decimal? tolerancePercent,
  }) async {
    checkDate(from, 'from');
    checkDate(until, 'until');
    final count = daysBetween(from, until);
    if (count < 1 || count > 366) invalid('Adherence spans 1–366 days.');
    final math = FoodMath(await _foods.lookup());
    final entries = await repository.diaryEntries(
      fromDate: from,
      untilDate: until,
    );
    final marks = {
      for (final r in await repository.dietRecords(kind: diaryDayKind))
        (r.snapshot['date']! as String): DiaryDayMark.fromJson(r.snapshot),
    };
    final schedule =
        (await DietService(repository).schedule(from, count))['days']! as List;
    final days =
        <
          ({
            String date,
            String status,
            Map<String, Object?>? schedule,
            Nutrition eaten,
          })
        >[];
    for (var i = 0; i < count; i++) {
      final date = addDays(from, i);
      var total = Nutrition.empty;
      var n = 0;
      for (final e in entries) {
        if (e.date != date) continue;
        total += e.nutrition(math);
        n++;
      }
      final day = schedule[i] as Map<String, Object?>;
      days.add((
        date: date,
        status: diaryDayStatus(marks[date], n),
        schedule: day['goals'] == null ? null : day,
        eaten: total,
      ));
    }
    return {
      'from': from,
      'until': until,
      ...adherence(days, tolerancePercent: tolerancePercent),
    };
  }

  /// Daily totals over [from, until) and averages over complete days and
  /// over logged (complete or partial) days, each stating how many days
  /// contribute.
  Future<Map<String, Object?>> report(
    String from,
    String until, {
    List<String>? nutrients,
  }) async {
    checkDate(from, 'from');
    checkDate(until, 'until');
    final days = daysBetween(from, until);
    if (days < 1 || days > 3660) invalid('A report spans 1–3660 days.');
    final math = FoodMath(await _foods.lookup());
    final entries = await repository.diaryEntries(
      fromDate: from,
      untilDate: until,
    );
    final marks = {
      for (final r in await repository.dietRecords(kind: diaryDayKind))
        (r.snapshot['date']! as String): DiaryDayMark.fromJson(r.snapshot),
    };
    final ids = nutrients ?? primaryNutrients;
    final perDay = <Map<String, Object?>>[];
    final counts = {'complete': 0, 'partial': 0, 'unlogged': 0};
    final sums = {
      'complete': <String, Fraction>{},
      'logged': <String, Fraction>{},
    };
    final known = {'complete': <String, int>{}, 'logged': <String, int>{}};
    for (var i = 0; i < days; i++) {
      final date = addDays(from, i);
      final todays = [
        for (final e in entries)
          if (e.date == date) e,
      ];
      var total = Nutrition.empty;
      for (final e in todays) {
        total += e.nutrition(math);
      }
      final status = diaryDayStatus(marks[date], todays.length);
      counts[status] = counts[status]! + 1;
      for (final group in ['complete', 'logged']) {
        if (status == 'unlogged' ||
            (group == 'complete' && status != 'complete'))
          continue;
        for (final id in ids) {
          // A day counts toward an average only when every item of it
          // declares the nutrient (an empty complete day counts as zero).
          if (total.status(id) == 'partial') continue;
          if (total.items > 0 && total.status(id) == 'unavailable') continue;
          sums[group]![id] =
              (sums[group]![id] ?? Fraction.zero) +
              (total.display(id) ?? Fraction.zero);
          known[group]![id] = (known[group]![id] ?? 0) + 1;
        }
      }
      perDay.add({
        'date': date,
        'status': status,
        'entries': todays.length,
        'totals': total.toJson(ids: ids),
      });
    }
    Map<String, Object?> averages(String group, int dayCount) => {
      'days': dayCount,
      'nutrients': {
        for (final id in ids)
          id: {
            'days': known[group]![id] ?? 0,
            'value': (known[group]![id] ?? 0) == 0
                ? null
                : (sums[group]![id]! / Fraction.integer(known[group]![id]!))
                      .round()
                      .toString(),
            'unit': nutrient(id).unit.name,
          },
      },
    };
    return {
      'from': from,
      'until': until,
      'days': days,
      'counts': counts,
      'averages': {
        'completeDays': averages('complete', counts['complete']!),
        'loggedDays': averages(
          'logged',
          counts['complete']! + counts['partial']!,
        ),
      },
      'daily': perDay,
    };
  }
}

String _markId(String date) => 'd${date.replaceAll('-', '')}';

String _shiftDays(String at, int days) {
  final offset = parseOffsetMinutes(at, 'at');
  return formatInstant(
    parseInstant(at, 'at').add(Duration(days: days)),
    offset,
  );
}

/// The water shortcut's food. Its density of 1 g per ml is a declared
/// approximation, visible on the food like any other declaration.
const waterFood = <String, Object?>{
  'id': 'water',
  'name': 'Water',
  'labels': {
    'sv': {'name': 'Vatten'},
  },
  'notes': 'Created by the water shortcut. Density 1 g/ml is an approximation.',
  'source': {'kind': 'other'},
  'kind': 'base',
  'basis': '100ml',
  'nutrients': {
    'energy': {'value': '0', 'unit': 'kcal'},
    'protein': {'value': '0', 'unit': 'g'},
    'carbohydrate': {'value': '0', 'unit': 'g'},
    'fat': {'value': '0', 'unit': 'g'},
    'fibre': {'value': '0', 'unit': 'g'},
    'water': {'value': '100', 'unit': 'g'},
  },
  'density': {
    'mass': {'value': '1', 'unit': 'g'},
    'volume': {'value': '1', 'unit': 'ml'},
  },
};
