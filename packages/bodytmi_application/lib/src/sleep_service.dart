import 'dart:math' as math;

import 'package:bodytmi_core/bodytmi_core.dart';

import 'body_service.dart';
import 'food_service.dart';
import 'training_repository.dart';

const sleepDayKind = 'sleep-day';
const sleepScheduleKind = 'sleep-schedule';

String sleepMarkId(String date) => 's${date.replaceAll('-', '')}';

/// A dated sleep schedule revision; the one in force on a date is the
/// latest whose `from` is on or before it.
final class SleepScheduleRevision {
  SleepScheduleRevision._(this.number, this.schedule);
  factory SleepScheduleRevision.fromJson(Object? input) {
    final j = jsonObject(input, 'sleep schedule revision');
    checkKeys(j, {'schemaVersion', 'revision', 'schedule'});
    final n = j['revision'];
    if (j['schemaVersion'] != 1 || n is! int || n < 1)
      invalid('Invalid sleep schedule revision.');
    return SleepScheduleRevision._(n, SleepSchedule.fromJson(j['schedule']));
  }
  final int number;
  final SleepSchedule schedule;
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'revision': number,
    'schedule': schedule.toJson(),
  };
}

/// Sleep diary, daylight, schedule and statistics (APP-PLAN 4.4). The app
/// describes; it does not estimate the internal body clock.
final class SleepService {
  const SleepService(this.repository);
  final TrainingRepository repository;

  Future<SleepRecord> record(String id) async =>
      await repository.sleepRecord(id) ??
      (throw BodyTmiException('not_found', 'Sleep $id not found.'));

  Future<void> _checkOverlap(SleepRecord r) async {
    final near = await repository.sleepRecords(
      fromDate: addDays(r.date, -2),
      untilDate: addDays(r.date, 3),
    );
    for (final o in near) {
      if (o.id == r.id) continue;
      if (r.start.isBefore(o.end) && o.start.isBefore(r.end))
        throw BodyTmiException(
          'conflict',
          'Sleep ${r.id} overlaps sleep ${o.id}.',
        );
    }
  }

  Future<SleepRecord> add(Map<String, Object?> input) =>
      repository.transaction(() async {
        if (input.containsKey('version'))
          invalid('The service assigns the version.');
        final r = SleepRecord.fromJson({...input, 'version': 1});
        if (await repository.sleepRecord(r.id) != null)
          throw BodyTmiException('conflict', 'Sleep ${r.id} exists.');
        await _checkOverlap(r);
        await repository.saveSleepRecord(r);
        return r;
      });

  Future<SleepRecord> update(
    String id,
    int expectedVersion,
    Map<String, Object?> input,
  ) => repository.transaction(() async {
    final before = await record(id);
    if (before.version != expectedVersion)
      throw const BodyTmiException('conflict', 'Sleep record changed.');
    if (input['id'] != id) invalid('An update keeps the sleep id.');
    if (input.containsKey('version'))
      invalid('The service assigns the version.');
    final r = SleepRecord.fromJson({...input, 'version': before.version + 1});
    await _checkOverlap(r);
    await repository.saveSleepRecord(r);
    return r;
  });

  Future<void> delete(String id, int expectedVersion) =>
      repository.transaction(() async {
        final before = await record(id);
        if (before.version != expectedVersion)
          throw const BodyTmiException('conflict', 'Sleep record changed.');
        await repository.deleteSleepRecord(id);
      });

  Future<Map<String, SleepDayMark>> marks() async => {
    for (final r in await repository.dietRecords(kind: sleepDayKind))
      (r.snapshot['date']! as String): SleepDayMark.fromJson(r.snapshot),
  };

  Future<SleepDayMark> mark(String date, String status) =>
      repository.transaction(() async {
        final m = SleepDayMark.fromJson({'date': date, 'status': status});
        await repository.saveDietRecord(
          DietRecord(sleepDayKind, sleepMarkId(date), 1, m.toJson()),
        );
        return m;
      });

  Future<List<SleepScheduleRevision>> schedules() async => [
    for (final r in await repository.dietRecords(kind: sleepScheduleKind))
      SleepScheduleRevision.fromJson(r.snapshot),
  ]..sort((a, b) => a.number.compareTo(b.number));

  Future<SleepScheduleRevision> setSchedule(
    Map<String, Object?> schedule,
    int expectedRevision,
  ) => repository.transaction(() async {
    final all = await schedules();
    if ((all.lastOrNull?.number ?? 0) != expectedRevision)
      throw const BodyTmiException('conflict', 'Sleep schedule changed.');
    final next = SleepScheduleRevision.fromJson({
      'schemaVersion': 1,
      'revision': expectedRevision + 1,
      'schedule': schedule,
    });
    await repository.saveDietRecord(
      DietRecord(sleepScheduleKind, 'schedule', next.number, next.toJson()),
    );
    return next;
  });

  /// The schedule in force on [date]: latest `from` on or before it, later
  /// revision first on the same day.
  SleepSchedule? scheduleOn(String date, List<SleepScheduleRevision> all) {
    SleepScheduleRevision? best;
    for (final r in all) {
      if (r.schedule.from.compareTo(date) > 0) continue;
      if (best == null ||
          r.schedule.from.compareTo(best.schedule.from) > 0 ||
          (r.schedule.from == best.schedule.from && r.number > best.number))
        best = r;
    }
    return best?.schedule;
  }

  Future<ProfileLocation?> location() async =>
      (await BodyService(repository).profile())?.profile.location;

  /// Daylight for [days] dates from [from] at the profile location, or at
  /// an explicit one.
  Future<Map<String, Object?>> sun(
    String from,
    int days, {
    ProfileLocation? at,
  }) async {
    checkDate(from, 'from');
    if (days < 1 || days > 366) invalid('days is from 1 to 366.');
    final loc =
        at ??
        await location() ??
        (throw const BodyTmiException(
          'not_found',
          'Set a location in the profile, or give one.',
        ));
    final zone = timeZone(loc.timeZone);
    return {
      'policy': solarPolicy,
      'source':
          'NOAA solar calculator equations (after Meeus); about one minute '
          'accuracy away from the poles.',
      'location': loc.toJson(),
      'days': [
        for (var i = 0; i < days; i++)
          sunDay(addDays(from, i), loc.latitude, loc.longitude, zone),
      ],
    };
  }

  /// Policy bodytmi-sleep-stats/1 over nights waking in [from, until).
  Future<Map<String, Object?>> stats(String from, String until) async {
    checkDate(from, 'from');
    checkDate(until, 'until');
    final count = daysBetween(from, until);
    if (count < 1 || count > 366) invalid('A period is 1–366 days.');
    final records = await repository.sleepRecords(
      fromDate: from,
      untilDate: until,
    );
    final mains = [
      for (final r in records)
        if (r.isMain) r,
    ];
    final naps = [
      for (final r in records)
        if (!r.isMain) r,
    ];
    final nightDates = {for (final r in mains) r.date};
    final missing = [
      for (var i = 0; i < count; i++)
        if (!nightDates.contains(addDays(from, i))) addDays(from, i),
    ];
    Map<String, Object?>? mean(Iterable<int?> values, String unit) {
      final known = [
        for (final v in values)
          if (v != null) v,
      ];
      if (known.isEmpty) return null;
      return {
        'value': (known.reduce((a, b) => a + b) / known.length).toStringAsFixed(
          1,
        ),
        'unit': unit,
        'nights': known.length,
      };
    }

    int local(DateTime t, int offset) {
      final l = t.add(Duration(minutes: offset));
      return l.hour * 60 + l.minute;
    }

    final onsets = [for (final r in mains) local(r.onset, r.onsetOffset)];
    final wakes = [for (final r in mains) local(r.wakeAt, r.wakeOffset)];
    final midpoints = [
      for (final r in mains)
        local(
          r.onset.add(Duration(minutes: r.sleepPeriodMinutes ~/ 2)),
          r.wakeOffset,
        ),
    ];
    final sri = await _sri(from, until);
    return {
      'policy': 'bodytmi-sleep-stats/1',
      'from': from,
      'until': until,
      'nights': count,
      'nightsLogged': nightDates.length,
      'missingNights': missing,
      'note':
          'A missing night is unknown, never awake or a zero; averages use '
          'logged nights only. Clock times are local to each record.',
      'approximateRecords': records.where((r) => r.approximate).length,
      'main': {
        'sleepPeriod': mean(mains.map((r) => r.sleepPeriodMinutes), 'min'),
        'asleep': mean(mains.map((r) => r.asleepMinutes), 'min'),
        'inBed': mean(mains.map((r) => r.inBedMinutes), 'min'),
        'awakenings': mean(mains.map((r) => r.awakenings), 'count'),
        'quality': mean(mains.map((r) => r.quality), 'rating 1–5'),
        'onset': _clock(onsets),
        'wake': _clock(wakes),
        'midpoint': _clock(midpoints),
      },
      'naps': {
        'count': naps.length,
        'totalPeriodMinutes': naps.fold<int>(
          0,
          (s, r) => s + r.sleepPeriodMinutes,
        ),
      },
      'regularity': sri,
    };
  }

  /// Circular mean and spread of local clock minutes.
  Map<String, Object?>? _clock(List<int> minutes) {
    if (minutes.isEmpty) return null;
    var x = 0.0, y = 0.0;
    for (final m in minutes) {
      final a = m / 1440 * 2 * math.pi;
      x += math.cos(a);
      y += math.sin(a);
    }
    var mean = (math.atan2(y, x) / (2 * math.pi) * 1440).round() % 1440;
    if (mean < 0) mean += 1440;
    var sq = 0.0;
    for (final m in minutes) {
      var d = (m - mean) % 1440;
      if (d > 720) d -= 1440;
      sq += d * d;
    }
    return {
      'mean': clockText(mean),
      'spreadMinutes': math.sqrt(sq / minutes.length).round(),
      'nights': minutes.length,
    };
  }

  /// Sleep Regularity Index on known pairs (bodytmi-sri-known-pairs/1):
  /// the published SRI (Phillips et al. 2017) compares sleep/wake at the
  /// same clock minute 24 h apart over complete records; here only pairs of
  /// consecutive local days both marked complete count, minute by minute in
  /// the profile time zone (a spring-forward gap is skipped, a repeated
  /// autumn hour uses its first occurrence). Each record's sleep period
  /// (onset to wake) counts as asleep, since awake minutes have no times.
  Future<Map<String, Object?>> _sri(String from, String until) async {
    final loc = await location();
    if (loc == null)
      return {
        'status': 'unavailable',
        'reason': 'The profile has no location and time zone.',
      };
    final zone = timeZone(loc.timeZone);
    final marks = await this.marks();
    bool complete(String d) => marks[d]?.status == 'complete';
    final records = await repository.sleepRecords(
      fromDate: addDays(from, -1),
      untilDate: addDays(until, 2),
    );
    List<bool?> states(String date) {
      final out = <bool?>[];
      for (var m = 0; m < 1440; m++) {
        final t = zonedInstant(zone, date, m);
        if (zonedMinute(zone, t) != m) {
          out.add(null);
          continue;
        }
        out.add(
          records.any((r) => !t.isBefore(r.onset) && t.isBefore(r.wakeAt)),
        );
      }
      return out;
    }

    var pairs = 0, agree = 0, compared = 0;
    List<bool?>? previous;
    String? previousDate;
    for (var d = from; d.compareTo(until) < 0; d = addDays(d, 1)) {
      if (!complete(d)) {
        previous = null;
        continue;
      }
      final today = states(d);
      if (previous != null && previousDate == addDays(d, -1)) {
        pairs++;
        for (var m = 0; m < 1440; m++) {
          final a = previous[m], b = today[m];
          if (a == null || b == null) continue;
          compared++;
          if (a == b) agree++;
        }
      }
      previous = today;
      previousDate = d;
    }
    if (pairs == 0)
      return {
        'status': 'unavailable',
        'policy': 'bodytmi-sri-known-pairs/1',
        'reason': 'No two consecutive days are marked complete.',
      };
    return {
      'status': 'resolved',
      'policy': 'bodytmi-sri-known-pairs/1',
      'value': (-100 + 200 * agree / compared).toStringAsFixed(1),
      'pairs': pairs,
      'zone': loc.timeZone,
      'note':
          'Known-pairs adaptation, not the published complete-record SRI; '
          '100 is perfectly regular, 0 random.',
    };
  }

  /// Policy bodytmi-sleep-plan-view/1: per night ending on each date in
  /// [from, until), actual and desired sleep, daylight, commitments and
  /// caffeine before sleep onset.
  Future<Map<String, Object?>> planView(String from, String until) async {
    checkDate(from, 'from');
    checkDate(until, 'until');
    final count = daysBetween(from, until);
    if (count < 1 || count > 62) invalid('A plan view spans 1–62 days.');
    final records = await repository.sleepRecords(
      fromDate: from,
      untilDate: until,
    );
    final all = await schedules();
    final loc = await location();
    final zone = loc == null ? null : timeZone(loc.timeZone);
    final math0 = FoodMath(await FoodService(repository).lookup());
    final diary = await repository.diaryEntries(
      fromDate: addDays(from, -2),
      untilDate: until,
    );
    final nights = <Map<String, Object?>>[];
    for (var i = 0; i < count; i++) {
      final date = addDays(from, i);
      final weekday = DateTime.parse('${date}T00:00:00Z').weekday;
      final main = [
        for (final r in records)
          if (r.isMain && r.date == date) r,
      ];
      final naps = [
        for (final r in records)
          if (!r.isMain && r.date == date) r,
      ];
      final schedule = scheduleOn(date, all);
      final actual = main.isEmpty ? null : main.first;
      // Wall clock → instant: the profile zone, else the record's offset.
      DateTime instant(String day, int minutes) {
        if (zone != null) return zonedInstant(zone, day, minutes);
        final offset = actual?.wakeOffset ?? 0;
        return DateTime.parse(
          '${day}T00:00:00Z',
        ).add(Duration(minutes: minutes - offset));
      }

      String show(DateTime t) => zone != null
          ? zonedText(zone, t)
          : formatInstant(t, actual?.wakeOffset ?? 0);

      Map<String, Object?>? desired;
      if (schedule != null) {
        final d = schedule.desiredFor(weekday);
        final sleepDay = d.sleep > d.wake ? addDays(date, -1) : date;
        final sleepAt = instant(sleepDay, d.sleep);
        final wakeAt = instant(date, d.wake);
        desired = {
          'sleepAt': show(sleepAt),
          'wakeAt': show(wakeAt),
          if (actual != null) ...{
            'onsetDeviationMinutes': actual.onset.difference(sleepAt).inMinutes,
            'wakeDeviationMinutes': actual.wakeAt.difference(wakeAt).inMinutes,
          },
        };
      }
      final conflicts = <Map<String, Object?>>[];
      if (schedule != null && actual != null) {
        for (final day in [addDays(date, -1), date]) {
          final wd = DateTime.parse('${day}T00:00:00Z').weekday;
          for (final c in schedule.commitmentsOn(wd)) {
            final s = instant(day, clockMinutes(c['start'], 'start'));
            final e = instant(day, clockMinutes(c['end'], 'end'));
            if (actual.onset.isBefore(e) && s.isBefore(actual.wakeAt))
              conflicts.add({
                'commitment': c['id'],
                'label': c['label'],
                'start': show(s),
                'end': show(e),
              });
          }
        }
      }
      nights.add({
        'date': date,
        'sleep': actual?.describe(),
        if (main.length > 1) 'otherMainSleeps': main.length - 1,
        'status': actual == null ? 'unknown' : 'logged',
        'naps': [for (final n in naps) n.describe()],
        'desired': desired,
        'conflicts': conflicts,
        'caffeine': actual == null
            ? null
            : _caffeine(actual.onset, diary, math0, show),
        'daylight': loc == null
            ? null
            : _daylight(sunDay(date, loc.latitude, loc.longitude, zone!)),
      });
    }
    return {
      'policy': 'bodytmi-sleep-plan-view/1',
      'from': from,
      'until': until,
      'location': loc?.toJson(),
      if (loc == null)
        'daylightReason': 'The profile has no location and time zone.',
      'nights': nights,
    };
  }

  Map<String, Object?> _daylight(Map<String, Object?> day) {
    final t = day['thresholds']! as Map<String, Object?>;
    Map<String, Object?> pick(String key) {
      final x = t[key]! as Map<String, Object?>;
      return {
        'events': x['events'],
        'state': ?x['state'],
        'minutesAbove': x['minutesAbove'],
      };
    }

    return {'sun': pick('sun'), 'civil': pick('civil')};
  }

  /// Caffeine logged in the 24 hours before [onset]: total and the last
  /// intake. Items that do not declare caffeine make the total partial.
  Map<String, Object?> _caffeine(
    DateTime onset,
    List<DiaryEntry> diary,
    FoodMath math0,
    String Function(DateTime) show,
  ) {
    final windowStart = onset.subtract(const Duration(hours: 24));
    var total = Fraction.zero;
    var unknown = 0, items = 0;
    DateTime? last;
    for (final e in diary) {
      final t = e.instant;
      if (t.isBefore(windowStart) || !t.isBefore(onset)) continue;
      final n = e.nutrition(math0);
      items += n.items;
      unknown += n.items - (n.known['caffeine'] ?? 0);
      final mg = n.display('caffeine');
      if (mg != null && !mg.isZero) {
        total += mg;
        if (last == null || t.isAfter(last)) last = t;
      }
    }
    return {
      'windowHours': 24,
      'totalMg': total.round(fractionDigits: 1).toString(),
      'status': items == 0
          ? 'nothing-logged'
          : unknown == 0
          ? 'known'
          : unknown == items
          ? 'unavailable'
          : 'partial',
      'itemsWithoutCaffeine': unknown,
      if (last != null) ...{
        'lastIntake': show(last),
        'hoursBeforeOnset': (onset.difference(last).inMinutes / 60)
            .toStringAsFixed(1),
      },
    };
  }
}
