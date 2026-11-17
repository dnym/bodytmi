import 'package:bodytmi_core/bodytmi_core.dart';

import 'diary_budget.dart';
import 'diary_service.dart' show diaryDayKind;
import 'diet_service.dart';
import 'food_service.dart';
import 'observation_service.dart';
import 'practice_service.dart';
import 'training_repository.dart';

/// Evaluates [DailyMetric]s over date ranges (policy bodytmi-daily-metric/1).
final class DailyMetricService {
  const DailyMetricService(this.repository);
  final TrainingRepository repository;

  Future<List<DayValue>> evaluate(
    DailyMetric metric,
    String from,
    String until,
  ) async {
    checkDate(from, 'from');
    checkDate(until, 'until');
    final count = daysBetween(from, until);
    if (count < 1 || count > 3660) invalid('A metric spans 1–3660 days.');
    final dates = [for (var i = 0; i < count; i++) addDays(from, i)];
    final values = switch (metric.source) {
      'observation' => await _observation(metric, dates),
      'sleep' => await _sleep(metric, from, until),
      'diary' => await _diary(metric, from, until),
      'activity' => await _activity(metric, from, until),
      'practice' => await _practice(metric, from, until),
      'training' => await _training(from, until),
      _ => await _budget(metric, dates),
    };
    return [
      for (final d in dates)
        values[d] ?? (date: d, status: 'unknown', value: null),
    ];
  }

  DayValue _v(String date, double value) =>
      (date: date, status: 'value', value: value);

  Future<Map<String, DayValue>> _observation(
    DailyMetric m,
    List<String> dates,
  ) async {
    final service = ObservationService(repository);
    final measureId = m.json['measure']! as String;
    final definition = await service.measure(measureId);
    final attributes = {
      for (final e in ((m.json['attributes'] as Map?) ?? const {}).entries)
        e.key as String: e.value as String,
    };
    double? number(Object? value) {
      if (value is int) return value.toDouble();
      if (value is bool) return value ? 1 : 0;
      if (value is Map<String, Object?>) {
        final q = Quantity.fromJson(value);
        final unit = definition.unit ?? q.unit;
        return double.parse(q.value.toString()) / double.parse(unit.factor);
      }
      return null;
    }

    final out = <String, DayValue>{};
    if (m.json['resolved'] == true) {
      for (final d in dates) {
        final r = await service.resolve(
          measureId,
          '${d}T23:59:59Z',
          attributes: attributes,
        );
        if (!r.resolved) continue;
        final v = number(r.json['value']);
        if (v != null) out[d] = _v(d, v);
      }
      return out;
    }
    final summary = (m.json['summary'] as String?) ?? 'mean';
    final byDate = <String, List<Observation>>{};
    for (final r in await repository.observationRecords(
      measureId: measureId,
      fromDate: dates.first,
      untilDate: addDays(dates.last, 1),
    )) {
      if (r.deleted) continue;
      final o = r.observation;
      if (o.attributes.length != attributes.length ||
          attributes.entries.any((e) => o.attributes[e.key] != e.value))
        continue;
      byDate.putIfAbsent(o.localDate, () => []).add(o);
    }
    for (final e in byDate.entries) {
      final obs = e.value
        ..sort(
          (a, b) => (a.observedAtText ?? a.localDate).compareTo(
            b.observedAtText ?? b.localDate,
          ),
        );
      if (summary == 'count') {
        out[e.key] = _v(e.key, obs.length.toDouble());
        continue;
      }
      final nums = [
        for (final o in obs)
          if (number(o.value) case final double v) v,
      ];
      if (nums.isEmpty) continue;
      out[e.key] = _v(e.key, switch (summary) {
        'last' => nums.last,
        'sum' => nums.reduce((a, b) => a + b),
        'min' => nums.reduce((a, b) => a < b ? a : b),
        'max' => nums.reduce((a, b) => a > b ? a : b),
        _ => nums.reduce((a, b) => a + b) / nums.length,
      });
    }
    return out;
  }

  /// Minutes after local midnight of [date] for [t] in [offset].
  static int clockOn(String date, DateTime t, int offset) {
    final local = t.add(Duration(minutes: offset));
    final midnight = DateTime.parse('${date}T00:00:00Z');
    return local.difference(midnight).inMinutes;
  }

  Future<Map<String, DayValue>> _sleep(
    DailyMetric m,
    String from,
    String until,
  ) async {
    final out = <String, DayValue>{};
    for (final r in await repository.sleepRecords(
      fromDate: from,
      untilDate: until,
    )) {
      if (!r.isMain || out.containsKey(r.date)) continue;
      final v = switch (m.field) {
        'asleepMinutes' => r.asleepMinutes,
        'sleepPeriodMinutes' => r.sleepPeriodMinutes,
        'inBedMinutes' => r.inBedMinutes,
        'quality' => r.quality,
        'awakenings' => r.awakenings,
        'onsetClock' => clockOn(r.date, r.onset, r.onsetOffset),
        'wakeClock' => clockOn(r.date, r.wakeAt, r.wakeOffset),
        _ => clockOn(
          r.date,
          r.onset.add(Duration(minutes: r.sleepPeriodMinutes ~/ 2)),
          r.wakeOffset,
        ),
      };
      if (v != null) out[r.date] = _v(r.date, v.toDouble());
    }
    return out;
  }

  Future<Map<String, DayValue>> _diary(
    DailyMetric m,
    String from,
    String until,
  ) async {
    final id = m.json['nutrient']! as String;
    final last = m.field == 'lastIntakeClock';
    final math = FoodMath(await FoodService(repository).lookup());
    final marks = {
      for (final r in await repository.dietRecords(kind: diaryDayKind))
        (r.snapshot['date']! as String): r.snapshot['status'],
    };
    final byDate = <String, List<DiaryEntry>>{};
    for (final e in await repository.diaryEntries(
      fromDate: from,
      untilDate: until,
    )) {
      byDate.putIfAbsent(e.date, () => []).add(e);
    }
    final out = <String, DayValue>{};
    for (var d = from; d.compareTo(until) < 0; d = addDays(d, 1)) {
      if (marks[d] != 'complete') continue;
      final entries = byDate[d] ?? const [];
      var total = Nutrition.empty;
      DateTime? latest;
      int? offset;
      for (final e in entries) {
        final n = e.nutrition(math);
        total += n;
        final v = n.display(id);
        if (v != null &&
            !v.isZero &&
            (latest == null || e.instant.isAfter(latest))) {
          latest = e.instant;
          offset = parseOffsetMinutes(e.at, 'at');
        }
      }
      if (total.items > 0 && total.status(id) != 'known') continue;
      if (!last) {
        out[d] = _v(
          d,
          double.parse((total.display(id) ?? Fraction.zero).round().toString()),
        );
      } else if (latest == null) {
        out[d] = (date: d, status: 'none', value: null);
      } else {
        out[d] = _v(d, clockOn(d, latest, offset!).toDouble());
      }
    }
    return out;
  }

  Future<Map<String, DayValue>> _activity(
    DailyMetric m,
    String from,
    String until,
  ) async {
    final category = m.json['category'] as String?;
    final kind = m.json['kind'] as String?;
    final sums = <String, double>{};
    for (final r in await repository.activityRecords(
      fromDate: from,
      untilDate: until,
    )) {
      if (category != null && !r.countsToward.contains(category)) continue;
      if (kind != null && r.kind != kind) continue;
      sums[r.date] =
          (sums[r.date] ?? 0) + (m.field == 'count' ? 1 : r.minutes.toDouble());
    }
    return {for (final e in sums.entries) e.key: _v(e.key, e.value)};
  }

  Future<Map<String, DayValue>> _practice(
    DailyMetric m,
    String from,
    String until,
  ) async {
    final id = m.json['practiceId'] as String?;
    final sums = <String, double>{};
    for (final s in await PracticeService(repository).sessions()) {
      if (s.status != 'confirmed' || (id != null && s.practiceId != id))
        continue;
      if (s.date.compareTo(from) < 0 || s.date.compareTo(until) >= 0) continue;
      final ms = (s.json['actual']! as Map)['milliseconds']! as int;
      sums[s.date] =
          (sums[s.date] ?? 0) + (m.field == 'count' ? 1 : ms / 60000);
    }
    return {for (final e in sums.entries) e.key: _v(e.key, e.value)};
  }

  Future<Map<String, DayValue>> _training(String from, String until) async {
    final counts = <String, double>{};
    for (final s in await repository.sessions()) {
      if (s.finishedAt == null) continue;
      final date = formatInstant(
        s.startedAt,
        s.startOffsetMinutes,
      ).substring(0, 10);
      if (date.compareTo(from) < 0 || date.compareTo(until) >= 0) continue;
      counts[date] = (counts[date] ?? 0) + 1;
    }
    return {for (final e in counts.entries) e.key: _v(e.key, e.value)};
  }

  Future<Map<String, DayValue>> _budget(
    DailyMetric m,
    List<String> dates,
  ) async {
    final goal = m.json['goal']! as String;
    final schedule =
        (await DietService(
              repository,
            ).schedule(dates.first, dates.length))['days']!
            as List;
    final math = FoodMath(await FoodService(repository).lookup());
    final marks = {
      for (final r in await repository.dietRecords(kind: diaryDayKind))
        (r.snapshot['date']! as String): r.snapshot['status'],
    };
    final byDate = <String, List<DiaryEntry>>{};
    for (final e in await repository.diaryEntries(
      fromDate: dates.first,
      untilDate: addDays(dates.last, 1),
    )) {
      byDate.putIfAbsent(e.date, () => []).add(e);
    }
    final out = <String, DayValue>{};
    for (var i = 0; i < dates.length; i++) {
      final plan = schedule[i] as Map<String, Object?>;
      if (plan['goals'] == null || marks[dates[i]] != 'complete') continue;
      var total = Nutrition.empty;
      for (final e in byDate[dates[i]] ?? const <DiaryEntry>[]) {
        total += e.nutrition(math);
      }
      final g = (dayBudget(plan, total)['goals']! as Map)[goal] as Map?;
      if (g == null || g['status'] != 'resolved') continue;
      final eaten = (g['eaten']! as Map)['value'];
      if (eaten == null || (total.items > 0 && total.status(goal) != 'known'))
        continue;
      final e = double.parse(eaten as String);
      double target(String k) =>
          double.parse((g[k]! as Map)['value']! as String);
      final double deviation;
      if (g.containsKey('target')) {
        deviation = e - target('target');
      } else {
        final lo = target('minimum'), hi = target('maximum');
        deviation = e < lo ? e - lo : (e > hi ? e - hi : 0);
      }
      out[dates[i]] = _v(dates[i], deviation);
    }
    return out;
  }
}
