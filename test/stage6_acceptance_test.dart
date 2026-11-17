import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'cli_test.dart';
import 'support.dart';

String _date(int day) => DateTime.utc(
  2026,
  9,
  1,
).add(Duration(days: day)).toIso8601String().substring(0, 10);

/// Stage 6 "done when" (APP-PLAN section 5) through the native CLI: an
/// earlier-caffeine trial defined, run and concluded from diary and sleep
/// data; plus goals, routines, today and a saved review.
void stage6AcceptanceTests() {
  test('stage 6 acceptance: trial, goals, routines and reviews', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-stage6-');
    var db = '${dir.path}/db.sqlite';

    Future<({int code, Map<String, Object?> body})> call(
      String name,
      Map<String, Object?> fields,
    ) async {
      final r = await invoke(
        name.split(' '),
        jsonEncode({'schemaVersion': 1, 'database': db, ...fields}),
      );
      final text = r.code == 0 ? r.output : r.error;
      return (code: r.code, body: jsonObject(jsonDecode(text), 'r'));
    }

    Future<Map<String, Object?>> ok(
      String name,
      Map<String, Object?> fields,
    ) async {
      final r = await call(name, fields);
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

    try {
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
      // Days 0–13 baseline: coffee at 16:30, asleep at 00:00 for 7 h.
      // Days 14–27 trial: coffee at 11:00, asleep at 23:15 for 7 h 30 min.
      // Day 20 is not logged at all: unknown, never counted against you.
      for (var day = 0; day < 28; day++) {
        if (day == 20) continue;
        final trial = day >= 14;
        await ok('diary add', {
          'entry': {
            'id': 'coffee-$day',
            'at': '${_date(day)}T${trial ? '11:00' : '16:30'}:00+02:00',
            'food': {'id': 'coffee'},
            'amount': {'value': '2', 'unit': 'dl'},
          },
        });
        await ok('diary mark', {'date': _date(day), 'status': 'complete'});
        await ok('sleep record', {
          'sleep': {
            'id': 'night-$day',
            'kind': 'main',
            'asleepAt': trial
                ? '${_date(day)}T23:15:00+02:00'
                : '${_date(day + 1)}T00:00:00+02:00',
            'wakeAt': '${_date(day + 1)}T07:00:00+02:00',
            'awakeMinutes': trial ? 10 : 30,
            'quality': trial ? 4 : 3,
          },
        });
      }

      // The trial: question, action check, periods and outcomes.
      final caffeineClock = {
        'source': 'diary',
        'nutrient': 'caffeine',
        'field': 'lastIntakeClock',
        'label': 'Last caffeine',
      };
      await ok('trial save', {
        'trial': {
          'id': 'early-caffeine',
          'question': 'Do I fall asleep earlier with no caffeine after 14:00?',
          'action': {
            'description': 'Last coffee before 14:00.',
            'metric': caffeineClock,
            'target': {'relation': 'atMost', 'value': '840'},
          },
          'baseline': {'from': _date(1), 'until': _date(14)},
          'trial': {'from': _date(15), 'until': _date(29)},
          'outcomes': [
            {'source': 'sleep', 'field': 'onsetClock', 'label': 'Asleep at'},
            {'source': 'sleep', 'field': 'asleepMinutes'},
            {'source': 'sleep', 'field': 'quality'},
          ],
        },
        'expectedVersion': 0,
      });
      await fails('trial save', {
        'trial': {
          'id': 'bad',
          'question': 'Q?',
          'action': {'description': 'A'},
          'baseline': {'from': _date(10), 'until': _date(20)},
          'trial': {'from': _date(15), 'until': _date(25)},
          'outcomes': [
            {'source': 'sleep', 'field': 'quality'},
          ],
        },
        'expectedVersion': 0,
      }, 2);
      final report = await ok('trial report', {'id': 'early-caffeine'});
      final adherence = at(report, ['actionAdherence']);
      // Sleep on date D follows coffee on D-1; the action counts on its own
      // diary days: baseline days 1–13 all late, trial days 15–28 early
      // (day 20 unlogged, day 28 not logged). Day 14 is the switch-over.
      jsonEqual(adherence['baseline'], {'met': 0, 'notMet': 13, 'unknown': 0});
      jsonEqual(adherence['trial'], {'met': 12, 'notMet': 0, 'unknown': 2});
      final onset = at(report, ['outcomes', 0]);
      // Asleep at 00:00 (0) versus 23:15 (−45 minutes before midnight).
      equal(at(onset, ['baseline'])['mean'], 0.0);
      equal(at(onset, ['trial'])['mean'], -45.0);
      equal(onset['meanDifference'], -45.0);
      final asleep = at(report, ['outcomes', 1]);
      equal(asleep['meanDifference'], 65.0);
      // The night after the unlogged day still counts: sleep was logged.
      equal(at(asleep, ['trial'])['known'], 13);
      check((report['note']! as String).contains('not proof'));
      final concluded = await ok('trial conclude', {
        'id': 'early-caffeine',
        'expectedVersion': 1,
        'decision': 'keep',
        'at': '${_date(29)}T20:00:00+02:00',
        'notes': 'Asleep about 45 minutes earlier; keep coffee before noon.',
      });
      equal(at(concluded, ['conclusion'])['decision'], 'keep');
      await fails('trial conclude', {
        'id': 'early-caffeine',
        'expectedVersion': 1,
        'decision': 'stop',
        'at': '${_date(29)}T21:00:00+02:00',
      }, 5);

      // A goal: average time asleep at least 7 h over the trial period.
      await ok('goal save', {
        'goal': {
          'id': 'sleep-7h',
          'name': 'Sleep at least 7 hours',
          'metric': {'source': 'sleep', 'field': 'asleepMinutes'},
          'aggregate': 'mean',
          'target': {'relation': 'atLeast', 'value': '420'},
          'from': _date(15),
          'until': _date(29),
        },
        'expectedVersion': 0,
      });
      final progress = await ok('goal progress', {
        'id': 'sleep-7h',
        'asOf': _date(28),
      });
      equal(progress['status'], 'met');
      equal(progress['value'], 455.0);

      // Routines: a walk counted by its category, a manual check, and a
      // routine due 30 minutes after waking.
      await ok('activity record', {
        'activity': {
          'id': 'walk',
          'kind': 'walk',
          'start': '${_date(28)}T12:00:00+02:00',
          'end': '${_date(28)}T12:30:00+02:00',
          'outdoor': true,
          'countsToward': ['movement', 'outdoor-light'],
        },
      });
      for (final (id, action, schedule) in [
        (
          'daily-walk',
          {'kind': 'activity', 'category': 'movement'},
          {'at': '12:00'},
        ),
        (
          'daylight',
          {'kind': 'activity', 'category': 'outdoor-light'},
          {
            'relative': {'anchor': 'wake', 'offsetMinutes': 30},
            'windowMinutes': 60,
          },
        ),
        ('vitamin-d', {'kind': 'check'}, <String, Object?>{}),
      ]) {
        await ok('routine save', {
          'routine': {
            'id': id,
            'name': id,
            'action': action,
            'schedule': schedule,
            'from': _date(0),
          },
          'expectedVersion': 0,
        });
      }
      var today = await ok('today show', {'date': _date(28)});
      Map<String, Object?> routine(String id) => (today['routines']! as List)
          .cast<Map<String, Object?>>()
          .singleWhere((r) => at(r, ['routine'])['id'] == id);
      // One walk counts toward both routines, once each.
      equal(routine('daily-walk')['status'], 'done');
      equal(routine('daylight')['status'], 'done');
      jsonEqual(routine('daylight')['due'], {
        'clock': '07:30',
        'basis': 'actual',
        'anchor': 'wake',
        'anchorAt': '${_date(28)}T07:00:00+02:00',
        'offsetMinutes': 30,
        'windowMinutes': 60,
      });
      equal(routine('vitamin-d')['status'], 'not-logged');
      await fails('routine check', {
        'routineId': 'daily-walk',
        'date': _date(28),
        'at': '${_date(28)}T09:00:00+02:00',
      }, 2);
      await ok('routine check', {
        'routineId': 'vitamin-d',
        'date': _date(28),
        'at': '${_date(28)}T09:00:00+02:00',
      });
      today = await ok('today show', {'date': _date(28)});
      equal(routine('vitamin-d')['status'], 'done');
      check(today['note'].toString().contains('no streaks'));
      // A day nothing was logged: not-logged, never missed.
      today = await ok('today show', {'date': _date(30)});
      equal(routine('daily-walk')['status'], 'not-logged');
      equal(at(routine('daylight'), ['due'])['basis'], 'unknown');

      // A saved review across sleep and diary.
      await ok('review save', {
        'review': {
          'id': 'sleep-caffeine',
          'name': 'Sleep against caffeine timing',
          'metrics': [
            caffeineClock,
            {'source': 'sleep', 'field': 'onsetClock'},
            {'source': 'diary', 'nutrient': 'caffeine'},
          ],
        },
        'expectedVersion': 0,
      });
      final review = await ok('review run', {
        'id': 'sleep-caffeine',
        'from': _date(18),
        'until': _date(22),
      });
      final caffeine = at(review, ['metrics', 2]);
      equal(at(caffeine, ['summary'])['known'], 3);
      final days = (caffeine['days']! as List).cast<Map<String, Object?>>();
      equal(days[2]['status'], 'unknown');
      equal(days[0]['value'], 80.0);

      // Backup and logical export keep the trial, goals and routines.
      Future<String> snapshot() async => canonicalJson({
        'report': await ok('trial report', {'id': 'early-caffeine'}),
        'today': await ok('today show', {'date': _date(28)}),
        'goals': await ok('goal list', {}),
      });
      final reference = await snapshot();
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
        equal(await snapshot(), reference);
      }
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
