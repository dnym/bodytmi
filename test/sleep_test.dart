import 'package:bodytmi_core/bodytmi_core.dart';

import 'support.dart';

SleepRecord _sleep(Map<String, Object?> fields) =>
    SleepRecord.fromJson({'id': 's', 'kind': 'main', ...fields});

void sleepTests() {
  test('sleep records validate onset, order and optional fields', () {
    rejects(() => _sleep({'wakeAt': '2026-11-02T07:00:00+01:00'}));
    rejects(
      () => _sleep({
        'bedAt': '2026-11-01T23:00:00+01:00',
        'wakeAt': '2026-11-02T07:00:00+01:00',
      }),
    );
    rejects(
      () => _sleep({
        'asleepAt': '2026-11-02T07:00:00+01:00',
        'wakeAt': '2026-11-02T06:00:00+01:00',
      }),
    );
    rejects(
      () => _sleep({
        'bedAt': '2026-11-01T23:00:00+01:00',
        'latencyMinutes': 10,
        'asleepAt': '2026-11-01T23:30:00+01:00',
        'wakeAt': '2026-11-02T07:00:00+01:00',
      }),
    );
    rejects(
      () => _sleep({
        'asleepAt': '2026-11-01T23:00:00+01:00',
        'wakeAt': '2026-11-02T07:00:00+01:00',
        'outOfBedAt': '2026-11-02T06:00:00+01:00',
      }),
    );
    rejects(
      () => _sleep({
        'asleepAt': '2026-11-01T23:00:00+01:00',
        'wakeAt': '2026-11-02T07:00:00+01:00',
        'quality': 6,
      }),
    );
    rejects(
      () => _sleep({
        'asleepAt': '2026-11-01T23:00:00+01:00',
        'wakeAt': '2026-11-02T07:00:00+01:00',
        'awakeMinutes': 480,
      }),
    );
    final r = _sleep({
      'bedAt': '2026-11-01T22:50:00+01:00',
      'latencyMinutes': 10,
      'asleepAt': '2026-11-01T23:00:00+01:00',
      'wakeAt': '2026-11-02T07:00:00+01:00',
      'outOfBedAt': '2026-11-02T07:20:00+01:00',
      'awakeMinutes': 20,
    });
    equal(r.date, '2026-11-02');
    equal(r.sleepPeriodMinutes, 480);
    equal(r.asleepMinutes, 460);
    equal(r.inBedMinutes, 510);
    equal(r.describe()['efficiencyPercent'], '90.2');
    // Spring forward: 23:00+01:00 to 07:00+02:00 is seven hours.
    equal(
      _sleep({
        'asleepAt': '2026-03-28T23:00:00+01:00',
        'wakeAt': '2026-03-29T07:00:00+02:00',
      }).sleepPeriodMinutes,
      420,
    );
    rejects(
      () => validateSleepRecords([
        r,
        SleepRecord.fromJson({
          'id': 'nap',
          'kind': 'nap',
          'asleepAt': '2026-11-02T07:10:00+01:00',
          'wakeAt': '2026-11-02T07:40:00+01:00',
        }),
      ]),
    );
  });

  test('schedules pick weekday times and check commitments', () {
    final s = SleepSchedule.fromJson({
      'from': '2026-11-01',
      'sleepAt': '23:00',
      'wakeAt': '07:00',
      'days': [
        {
          'weekdays': [6, 7],
          'sleepAt': '00:30',
          'wakeAt': '09:00',
        },
      ],
      'commitments': [
        {
          'id': 'gym',
          'label': 'Gym',
          'weekdays': [2],
          'start': '06:00',
          'end': '07:00',
        },
      ],
    });
    equal(s.desiredFor(1).sleep, 23 * 60);
    equal(s.desiredFor(7).wake, 9 * 60);
    equal(s.commitmentsOn(2).length, 1);
    equal(s.commitmentsOn(3).length, 0);
    rejects(
      () => SleepSchedule.fromJson({
        'from': '2026-11-01',
        'sleepAt': '23:00',
        'wakeAt': '24:00',
      }),
    );
    rejects(
      () => SleepSchedule.fromJson({
        'from': '2026-11-01',
        'sleepAt': '23:00',
        'wakeAt': '07:00',
        'commitments': [
          {
            'id': 'x',
            'label': 'Night shift',
            'weekdays': [1],
            'start': '22:00',
            'end': '06:00',
          },
        ],
      }),
    );
    rejects(
      () => ProfileLocation.fromJson({
        'latitude': '59.3',
        'longitude': '18.1',
        'timeZone': 'Europe/Atlantis',
      }),
    );
    rejects(
      () => ProfileLocation.fromJson({
        'latitude': '91',
        'longitude': '18.1',
        'timeZone': 'Europe/Stockholm',
      }),
    );
  });
}
