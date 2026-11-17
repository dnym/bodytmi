import 'diary.dart' show checkDate;
import 'errors.dart';
import 'instant.dart';

/// One sleep: the main sleep or a nap. Sleep onset is [asleepAt], or
/// [bedAt] plus [latencyMinutes] when that is what you know. A night
/// belongs to the local date you woke (F7). Time in bed needs both bed and
/// out-of-bed times; time asleep needs awake minutes. Nothing is assumed:
/// a missing value stays unknown and approximate entries say so.
final class SleepRecord {
  SleepRecord._(this.json);

  factory SleepRecord.fromJson(Object? input) {
    final j = jsonObject(input, 'sleep');
    checkKeys(j, {
      'id',
      'version',
      'kind',
      'bedAt',
      'latencyMinutes',
      'asleepAt',
      'wakeAt',
      'outOfBedAt',
      'awakenings',
      'awakeMinutes',
      'quality',
      'approximate',
      'notes',
      'import',
    });
    identifier(j, 'id');
    final version = j['version'] ?? 1;
    if (version is! int || version < 1) invalid('version must be positive.');
    final kind = j['kind'];
    if (kind != 'main' && kind != 'nap') invalid('A sleep is main or nap.');
    DateTime? at(String key) =>
        j[key] == null ? null : parseInstant(j[key], key);
    int? count(String key, int max) {
      final v = j[key];
      if (v == null) return null;
      if (v is! int || v < 0 || v > max)
        invalid('$key is a whole number from 0 to $max.');
      return v;
    }

    final bed = at('bedAt');
    final latency = count('latencyMinutes', 720);
    final asleep = at('asleepAt');
    final wake = at('wakeAt') ?? invalid('A sleep has wakeAt.');
    final out = at('outOfBedAt');
    if (latency != null && bed == null)
      invalid('latencyMinutes counts from bedAt.');
    final onset = asleep ?? bed?.add(Duration(minutes: latency ?? -1));
    if (asleep == null && (bed == null || latency == null))
      invalid('A sleep has asleepAt, or bedAt with latencyMinutes.');
    if (asleep != null &&
        bed != null &&
        latency != null &&
        asleep.difference(bed).inMinutes != latency)
      invalid('asleepAt, bedAt and latencyMinutes disagree.');
    if (bed != null && bed.isAfter(onset!))
      invalid('bedAt is not after sleep onset.');
    if (!wake.isAfter(onset!)) invalid('wakeAt is after sleep onset.');
    if (out != null && out.isBefore(wake))
      invalid('outOfBedAt is not before wakeAt.');
    final first = bed ?? onset;
    if ((out ?? wake).difference(first).inMinutes > 24 * 60)
      invalid('A sleep record spans at most 24 hours.');
    count('awakenings', 1000);
    final awake = count('awakeMinutes', 24 * 60);
    if (awake != null && awake >= wake.difference(onset).inMinutes)
      invalid('awakeMinutes is shorter than the sleep period.');
    final quality = j['quality'];
    if (quality != null && (quality is! int || quality < 1 || quality > 5))
      invalid('quality is a rating from 1 to 5.');
    final approximate = j['approximate'] ?? false;
    if (approximate is! bool) invalid('approximate is a boolean.');
    final notes = j['notes'];
    if (notes != null &&
        (notes is! String || notes.trim().isEmpty || notes.length > 4000))
      invalid('Notes are nonempty text of at most 4000 characters.');
    if (j['import'] != null) {
      final imp = jsonObject(j['import'], 'import');
      checkKeys(imp, {'namespace', 'sourceId'});
      identifier(imp, 'namespace');
      final s = requiredString(imp, 'sourceId');
      if (s.length > 256) invalid('An import source id is at most 256.');
    }
    return SleepRecord._(
      Map.unmodifiable(
        {
          ...j,
          'version': version,
          if (j['approximate'] == false) 'approximate': null,
        }..removeWhere((k, v) => v == null),
      ),
    );
  }

  final Map<String, Object?> json;
  String get id => json['id']! as String;
  int get version => json['version']! as int;
  bool get isMain => json['kind'] == 'main';
  bool get approximate => json['approximate'] == true;
  DateTime? _at(String key) =>
      json[key] == null ? null : parseInstant(json[key], key);
  DateTime? get bedAt => _at('bedAt');
  DateTime get wakeAt => _at('wakeAt')!;
  DateTime? get outOfBedAt => _at('outOfBedAt');
  int? get awakeMinutes => json['awakeMinutes'] as int?;
  int? get quality => json['quality'] as int?;
  int? get awakenings => json['awakenings'] as int?;
  String? get importNamespace =>
      (json['import'] as Map?)?['namespace'] as String?;
  String? get importSourceId =>
      (json['import'] as Map?)?['sourceId'] as String?;

  /// Sleep onset: asleepAt, or bedAt plus latency.
  DateTime get onset =>
      _at('asleepAt') ??
      bedAt!.add(Duration(minutes: json['latencyMinutes']! as int));

  /// The offset of [wakeAt] as entered; the night's date is local to it.
  int get wakeOffset => parseOffsetMinutes(json['wakeAt'], 'wakeAt');

  /// The text instant the onset was entered as, or bedAt's offset.
  int get onsetOffset => json['asleepAt'] != null
      ? parseOffsetMinutes(json['asleepAt'], 'asleepAt')
      : parseOffsetMinutes(json['bedAt'], 'bedAt');

  /// The local date of waking: the date the night belongs to.
  String get date => (json['wakeAt']! as String).substring(0, 10);

  /// First and last instant this record covers (bed or onset to out of bed
  /// or wake).
  DateTime get start => bedAt ?? onset;
  DateTime get end => outOfBedAt ?? wakeAt;

  int get sleepPeriodMinutes => wakeAt.difference(onset).inMinutes;
  int? get asleepMinutes =>
      awakeMinutes == null ? null : sleepPeriodMinutes - awakeMinutes!;
  int? get inBedMinutes => bedAt == null || outOfBedAt == null
      ? null
      : outOfBedAt!.difference(bedAt!).inMinutes;

  Map<String, Object?> toJson() => json;

  /// The record with its derived durations, for display.
  Map<String, Object?> describe() => {
    ...json,
    'date': date,
    'onset': json['asleepAt'] ?? formatInstant(onset, onsetOffset),
    'sleepPeriodMinutes': sleepPeriodMinutes,
    'asleepMinutes': asleepMinutes,
    'inBedMinutes': inBedMinutes,
    if (asleepMinutes != null && inBedMinutes != null && inBedMinutes! > 0)
      'efficiencyPercent':
          ((asleepMinutes! * 1000 / inBedMinutes!).round() / 10).toString(),
  };
}

/// Records do not overlap and ids are unique.
void validateSleepRecords(List<SleepRecord> records) {
  final ids = <String>{};
  final sorted = [...records]..sort((a, b) => a.start.compareTo(b.start));
  for (var i = 0; i < sorted.length; i++) {
    if (!ids.add(sorted[i].id)) invalid('Duplicate sleep ${sorted[i].id}.');
    if (i > 0 && sorted[i].start.isBefore(sorted[i - 1].end))
      invalid('Sleep ${sorted[i].id} overlaps sleep ${sorted[i - 1].id}.');
  }
}

/// A local calendar day whose sleep is fully logged (`complete`, so time
/// outside the records was awake) or explicitly reset (`unmarked`).
final class SleepDayMark {
  SleepDayMark._(this.date, this.status);
  factory SleepDayMark.fromJson(Object? input) {
    final j = jsonObject(input, 'sleep day');
    checkKeys(j, {'date', 'status'});
    final status = j['status'];
    if (status != 'complete' && status != 'unmarked')
      invalid('A sleep day status is complete or unmarked.');
    return SleepDayMark._(checkDate(j['date'], 'date'), status! as String);
  }
  final String date, status;
  Map<String, Object?> toJson() => {'date': date, 'status': status};
}

/// `HH:MM` as minutes after midnight.
int clockMinutes(Object? value, String label) {
  if (value is! String || !RegExp(r'^\d{2}:\d{2}$').hasMatch(value))
    invalid('$label is HH:MM.');
  final h = int.parse(value.substring(0, 2)), m = int.parse(value.substring(3));
  if (h > 23 || m > 59) invalid('$label is a time from 00:00 to 23:59.');
  return h * 60 + m;
}

String clockText(int minutes) {
  final m = minutes % 1440;
  return '${(m ~/ 60).toString().padLeft(2, '0')}:'
      '${(m % 60).toString().padLeft(2, '0')}';
}

/// A sleep schedule in force from [from]: desired sleep and wake times
/// (optionally different on chosen weekdays) and fixed commitments.
final class SleepSchedule {
  SleepSchedule._(this.json);
  factory SleepSchedule.fromJson(Object? input) {
    final j = jsonObject(input, 'schedule');
    checkKeys(j, {'from', 'sleepAt', 'wakeAt', 'days', 'commitments'});
    checkDate(j['from'], 'from');
    clockMinutes(j['sleepAt'], 'sleepAt');
    clockMinutes(j['wakeAt'], 'wakeAt');
    final seen = <int>{};
    for (final d in (j['days'] as List?) ?? const []) {
      final x = jsonObject(d, 'day');
      checkKeys(x, {'weekdays', 'sleepAt', 'wakeAt'});
      for (final w in jsonList(x, 'weekdays')) {
        if (w is! int || w < 1 || w > 7) invalid('weekdays are 1 (Mon)–7.');
        if (!seen.add(w)) invalid('A weekday has one desired time.');
      }
      clockMinutes(x['sleepAt'], 'sleepAt');
      clockMinutes(x['wakeAt'], 'wakeAt');
    }
    final ids = <String>{};
    final commitments = (j['commitments'] as List?) ?? const [];
    if (commitments.length > 64) invalid('At most 64 commitments.');
    for (final c in commitments) {
      final x = jsonObject(c, 'commitment');
      checkKeys(x, {'id', 'label', 'weekdays', 'start', 'end'});
      if (!ids.add(identifier(x, 'id'))) invalid('Duplicate commitment.');
      final label = requiredString(x, 'label');
      if (label.length > 200) invalid('A label is at most 200 characters.');
      final weekdays = jsonList(x, 'weekdays');
      if (weekdays.isEmpty) invalid('A commitment names its weekdays.');
      for (final w in weekdays) {
        if (w is! int || w < 1 || w > 7) invalid('weekdays are 1 (Mon)–7.');
      }
      final s = clockMinutes(x['start'], 'start');
      final e = clockMinutes(x['end'], 'end');
      if (e <= s) invalid('A commitment ends after it starts, same day.');
    }
    return SleepSchedule._(Map.unmodifiable(j));
  }
  final Map<String, Object?> json;
  String get from => json['from']! as String;

  /// Desired (sleep, wake) minutes for a night ending on a [weekday] date.
  ({int sleep, int wake}) desiredFor(int weekday) {
    for (final d in (json['days'] as List?) ?? const []) {
      final x = d as Map<String, Object?>;
      if ((x['weekdays']! as List).contains(weekday))
        return (
          sleep: clockMinutes(x['sleepAt'], 'sleepAt'),
          wake: clockMinutes(x['wakeAt'], 'wakeAt'),
        );
    }
    return (
      sleep: clockMinutes(json['sleepAt'], 'sleepAt'),
      wake: clockMinutes(json['wakeAt'], 'wakeAt'),
    );
  }

  List<Map<String, Object?>> commitmentsOn(int weekday) => [
    for (final c in (json['commitments'] as List?) ?? const [])
      if (((c as Map)['weekdays']! as List).contains(weekday))
        c.cast<String, Object?>(),
  ];

  Map<String, Object?> toJson() => json;
}
