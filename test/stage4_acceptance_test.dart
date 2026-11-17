import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'cli_test.dart';
import 'support.dart';

/// Stage 4 "done when" (APP-PLAN section 5) through the native CLI.
void stage4AcceptanceTests() {
  test('stage 4 acceptance: sleep, daylight, schedule and statistics', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-stage4-');
    var db = '${dir.path}/db.sqlite';

    Future<({int code, Map<String, Object?> body})> call(
      String name,
      Map<String, Object?> fields, {
      bool database = true,
    }) async {
      final r = await invoke(
        name.split(' '),
        jsonEncode({
          'schemaVersion': 1,
          if (database) 'database': db,
          ...fields,
        }),
      );
      final text = r.code == 0 ? r.output : r.error;
      return (code: r.code, body: jsonObject(jsonDecode(text), 'r'));
    }

    Future<Map<String, Object?>> ok(
      String name,
      Map<String, Object?> fields, {
      bool database = true,
    }) async {
      final r = await call(name, fields, database: database);
      check(r.code == 0, '$name: ${r.body}');
      final data = r.body['data'];
      return data is Map<String, Object?> ? data : {'list': data};
    }

    Future<void> fails(
      String name,
      Map<String, Object?> fields,
      int code,
    ) async {
      final r = await call(name, fields);
      check(r.code == code, '$name: expected $code, got ${r.code} ${r.body}');
    }

    Map<String, Object?> at(Object? value, List<Object> path) {
      var current = value;
      for (final key in path) {
        current = key is int
            ? (current! as List)[key]
            : jsonObject(current, '$key')[key];
      }
      return jsonObject(current, '$path');
    }

    const stockholm = {
      'latitude': '59.3293',
      'longitude': '18.0686',
      'timeZone': 'Europe/Stockholm',
    };
    try {
      // 1. Daylight for Stockholm in June and December, checked against the
      // US Naval Observatory (aa.usno.navy.mil, rounded to the minute):
      // 21 June rise 01:31 UTC, set 20:08, civil dusk 21:40, dawn 23:59;
      // 21 December rise 07:43, set 13:48, civil dawn 06:48, dusk 14:44.
      String minute(Map<String, Object?> day, String threshold, int i) {
        final at =
            jsonObject(
                  (jsonObject(
                        jsonObject(day['thresholds'], 't')[threshold],
                        threshold,
                      )['events']!
                      as List)[i],
                  'e',
                )['at']!
                as String;
        // Round to the minute as USNO does.
        final t = DateTime.parse(at).toUtc().add(const Duration(seconds: 30));
        return '${t.hour.toString().padLeft(2, '0')}:'
            '${t.minute.toString().padLeft(2, '0')}';
      }

      final june = jsonObject(
        ((await ok('sun times', {
                  'location': stockholm,
                  'from': '2026-06-21',
                }, database: false))['days']!
                as List)
            .single,
        'june',
      );
      equal(minute(june, 'sun', 0), '01:31');
      equal(minute(june, 'sun', 1), '20:08');
      // The local day starts at 22:00 UTC: civil dawn (01:59 local, 23:59
      // UTC the day before, the same minute as USNO's next dawn) comes first.
      equal(minute(june, 'civil', 0), '23:59');
      equal(minute(june, 'civil', 1), '21:40');
      // Local summer time, +02:00.
      check(
        (at(june, ['thresholds', 'sun', 'events', 0])['at']! as String)
            .endsWith('+02:00'),
        '$june',
      );
      equal(at(june, ['thresholds', 'nautical'])['state'], 'above');
      final december = jsonObject(
        ((await ok('sun times', {
                  'location': stockholm,
                  'from': '2026-12-21',
                }, database: false))['days']!
                as List)
            .single,
        'december',
      );
      equal(minute(december, 'civil', 0), '06:48');
      equal(minute(december, 'sun', 0), '07:43');
      equal(minute(december, 'sun', 1), '13:48');
      equal(minute(december, 'civil', 1), '14:44');
      check(
        (at(december, ['thresholds', 'sun', 'events', 0])['at']! as String)
            .endsWith('+01:00'),
      );
      // Tromsø in December: the sun never rises, but there is twilight.
      final tromso = jsonObject(
        ((await ok('sun times', {
                  'location': {
                    'latitude': '69.6492',
                    'longitude': '18.9553',
                    'timeZone': 'Europe/Oslo',
                  },
                  'from': '2026-12-21',
                }, database: false))['days']!
                as List)
            .single,
        'tromso',
      );
      equal(at(tromso, ['thresholds', 'sun'])['state'], 'below');
      equal(minute(tromso, 'civil', 0), '08:31');

      await ok('profile set', {
        'profile': {
          'sex': 'male',
          'birthDate': '1988-04-02',
          'location': stockholm,
        },
        'expectedRevision': 0,
      });

      // 2. Overnight sleep and naps across both daylight-saving changes.
      // Spring forward (29 March): 23:30 to 07:30 is 7 hours asleep.
      final spring = await ok('sleep record', {
        'sleep': {
          'id': 'night-0329',
          'kind': 'main',
          'bedAt': '2026-03-28T23:10:00+01:00',
          'latencyMinutes': 20,
          'wakeAt': '2026-03-29T07:30:00+02:00',
          'outOfBedAt': '2026-03-29T07:45:00+02:00',
          'awakeMinutes': 10,
          'awakenings': 1,
          'quality': 4,
        },
      });
      equal(spring['date'], '2026-03-29');
      equal(spring['sleepPeriodMinutes'], 7 * 60);
      equal(spring['asleepMinutes'], 7 * 60 - 10);
      equal(spring['inBedMinutes'], 7 * 60 + 35);
      equal(spring['onset'], '2026-03-28T23:30:00.000+01:00');
      // Fall back (25 October): the same clock times are 9 hours.
      final autumn = await ok('sleep record', {
        'sleep': {
          'id': 'night-1025',
          'kind': 'main',
          'asleepAt': '2026-10-24T23:30:00+02:00',
          'wakeAt': '2026-10-25T07:30:00+01:00',
          'approximate': true,
        },
      });
      equal(autumn['sleepPeriodMinutes'], 9 * 60);
      // Without awake minutes or bed times, asleep and in bed are unknown.
      equal(autumn['asleepMinutes'], null);
      equal(autumn['inBedMinutes'], null);
      await ok('sleep record', {
        'sleep': {
          'id': 'nap-1025',
          'kind': 'nap',
          'asleepAt': '2026-10-25T14:00:00+01:00',
          'wakeAt': '2026-10-25T14:25:00+01:00',
        },
      });
      await fails('sleep record', {
        'sleep': {
          'id': 'overlap',
          'kind': 'nap',
          'asleepAt': '2026-10-25T07:00:00+01:00',
          'wakeAt': '2026-10-25T08:00:00+01:00',
        },
      }, 5);
      await fails('sleep record', {
        'sleep': {
          'id': 'bad',
          'kind': 'main',
          'wakeAt': '2026-10-26T07:00:00+01:00',
        },
      }, 2);

      // 3. A schedule plan compared with actual sleep, with daylight, a
      // commitment and caffeine from the food diary.
      await ok('sleep schedule', {
        'schedule': {
          'from': '2026-10-01',
          'sleepAt': '23:00',
          'wakeAt': '07:00',
          'days': [
            {
              'weekdays': [6, 7],
              'sleepAt': '23:30',
              'wakeAt': '08:00',
            },
          ],
          'commitments': [
            {
              'id': 'work',
              'label': 'Work',
              'weekdays': [1, 2, 3, 4, 5],
              'start': '08:00',
              'end': '16:30',
            },
          ],
        },
        'expectedRevision': 0,
      });
      await ok('food publish', {
        'food': {
          'id': 'coffee',
          'name': 'Brewed coffee',
          'kind': 'base',
          'basis': '100ml',
          'nutrients': {
            'energy': {'value': '2', 'unit': 'kcal'},
            'caffeine': {'value': '40', 'unit': 'mg'},
          },
        },
        'expectedRevision': 0,
      });
      // Monday 26 October: a late coffee and a long sleep into work time.
      await ok('diary add', {
        'entry': {
          'id': 'coffee-1',
          'at': '2026-10-26T15:30:00+01:00',
          'food': {'id': 'coffee'},
          'amount': {'value': '2', 'unit': 'dl'},
        },
      });
      await ok('sleep record', {
        'sleep': {
          'id': 'night-1027',
          'kind': 'main',
          'asleepAt': '2026-10-27T00:15:00+01:00',
          'wakeAt': '2026-10-27T08:20:00+01:00',
        },
      });
      final view = await ok('sleep plan-view', {
        'from': '2026-10-25',
        'until': '2026-10-28',
      });
      final nights = (view['nights']! as List).cast<Map<String, Object?>>();
      equal(nights.length, 3);
      // Sunday 25 October: weekend times; 23:30 → 07:30 against 23:30 → 08:00.
      final sunday = at(nights[0], ['desired']);
      equal(sunday['sleepAt'], '2026-10-24T23:30:00+02:00');
      equal(sunday['wakeAt'], '2026-10-25T08:00:00+01:00');
      equal(sunday['onsetDeviationMinutes'], 0);
      equal(sunday['wakeDeviationMinutes'], -30);
      check(at(nights[0], ['daylight', 'sun'])['events'] != null);
      // Monday: no main sleep logged, so the night is unknown, not awake.
      equal(nights[1]['status'], 'unknown');
      // Tuesday: 75 minutes late to sleep, 80 minutes late up, into work.
      final tuesday = at(nights[2], ['desired']);
      equal(tuesday['onsetDeviationMinutes'], 75);
      equal(tuesday['wakeDeviationMinutes'], 80);
      equal(at(nights[2], ['conflicts', 0])['commitment'], 'work');
      final caffeine = at(nights[2], ['caffeine']);
      equal(caffeine['totalMg'], '80');
      equal(caffeine['status'], 'known');
      equal(caffeine['hoursBeforeOnset'], '8.8');

      // 4. Statistics: missing nights stay unknown; regularity needs
      // consecutive complete days.
      var stats = await ok('sleep stats', {
        'from': '2026-10-25',
        'until': '2026-10-28',
      });
      equal(stats['nightsLogged'], 2);
      jsonEqual(stats['missingNights'], ['2026-10-26']);
      equal(at(stats, ['naps'])['count'], 1);
      equal(
        at(stats, ['main', 'sleepPeriod'])['value'],
        '${(9 * 60 + 8 * 60 + 5) / 2}',
      );
      equal(at(stats, ['regularity'])['status'], 'unavailable');
      // A regular week, imported in the neutral format, marked complete.
      final document = {
        'format': 'bodytmi-sleep-import/1',
        'source': {'namespace': 'band'},
        'sleeps': [
          for (var d = 1; d <= 7; d++)
            {
              'sourceId': 'n$d',
              'kind': 'main',
              'asleepAt':
                  '2026-11-${(d - 1).toString().padLeft(2, '0')}T23:00:00+01:00'
                      .replaceFirst('2026-11-00', '2026-10-31'),
              'wakeAt':
                  '2026-11-${d.toString().padLeft(2, '0')}T07:00:00+01:00',
            },
        ],
      };
      await ok('sleep import-validate', {
        'document': document,
      }, database: false);
      final preview = await ok('sleep import-preview', {'document': document});
      jsonEqual(preview['counts'], {
        'new': 7,
        'unchanged': 0,
        'changed': 0,
        'conflict': 0,
      });
      await fails('sleep import-apply', {'document': document}, 2);
      await ok('sleep import-apply', {'document': document, 'confirm': true});
      final again = await ok('sleep import-apply', {
        'document': document,
        'confirm': true,
      });
      equal(at(again, ['counts'])['unchanged'], 7);
      for (var d = 1; d <= 6; d++) {
        await ok('sleep mark', {'date': '2026-11-0$d', 'status': 'complete'});
      }
      stats = await ok('sleep stats', {
        'from': '2026-11-01',
        'until': '2026-11-08',
      });
      final sri = at(stats, ['regularity']);
      equal(sri['status'], 'resolved');
      equal(sri['pairs'], 5);
      equal(sri['value'], '100.0');
      equal(at(stats, ['main', 'midpoint'])['mean'], '03:00');
      equal(at(stats, ['main', 'midpoint'])['spreadMinutes'], 0);

      // Edit, conflict and delete.
      await ok('sleep update', {
        'id': 'night-1025',
        'expectedVersion': 1,
        'sleep': {
          'id': 'night-1025',
          'kind': 'main',
          'asleepAt': '2026-10-24T23:30:00+02:00',
          'wakeAt': '2026-10-25T07:30:00+01:00',
          'awakeMinutes': 30,
        },
      });
      await fails('sleep update', {
        'id': 'night-1025',
        'expectedVersion': 1,
        'sleep': {
          'id': 'night-1025',
          'kind': 'main',
          'asleepAt': '2026-10-24T23:30:00+02:00',
          'wakeAt': '2026-10-25T07:30:00+01:00',
        },
      }, 5);
      await ok('sleep delete', {
        'id': 'nap-1025',
        'expectedVersion': 1,
        'confirm': true,
      });

      // 5. Backup and logical export keep sleep, marks and the schedule.
      final reference = await ok('sleep plan-view', {
        'from': '2026-10-25',
        'until': '2026-11-03',
      });
      final backup = '${dir.path}/backup';
      await ok('backup create', {'destination': backup});
      final export = '${dir.path}/export.json';
      await ok('archive export', {'destination': export});
      for (final (command, source) in [
        ('backup restore', backup),
        ('archive restore', export),
      ]) {
        db = '${dir.path}/${command.split(' ').first}.sqlite';
        await ok(command, {
          'source': source,
          'recoveryDestination': '${dir.path}/recovery-$command',
          'confirm': true,
        });
        equal(
          canonicalJson(
            await ok('sleep plan-view', {
              'from': '2026-10-25',
              'until': '2026-11-03',
            }),
          ),
          canonicalJson(reference),
        );
      }
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
