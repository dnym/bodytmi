import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:bodytmi_application/bodytmi_application.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'cli_test.dart';
import 'support.dart';

/// Stage 5 "done when" (APP-PLAN section 5) through the native CLI.
void stage5AcceptanceTests() {
  test('stage 5 acceptance: journal, practices and activity', () async {
    final dir = await Directory.systemTemp.createTemp('bodytmi-stage5-');
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

    Future<String> fails(
      String name,
      Map<String, Object?> fields,
      int code,
    ) async {
      final r = await call(name, fields);
      check(r.code == code, '$name: expected $code, got ${r.code} ${r.body}');
      return jsonObject(r.body['error'], 'e')['message']! as String;
    }

    try {
      // 1. Journal: built-in measures, ordinary observations.
      await ok('observation record', {
        'observation': {
          'id': 'mood-1',
          'measure': 'mood',
          'value': 6,
          'observedAt': '2026-11-18T08:00:00+01:00',
        },
      });
      await ok('observation record', {
        'observation': {
          'id': 'pain-1',
          'measure': 'pain',
          'value': 4,
          'observedAt': '2026-11-18T08:00:00+01:00',
          'attributes': {'site': 'lower-back', 'impact': 'limits-activity'},
        },
      });
      await ok('observation record', {
        'observation': {
          'id': 'cold',
          'measure': 'illness',
          'value': {'end': '2026-11-20T18:00:00+01:00'},
          'observedAt': '2026-11-17T07:00:00+01:00',
          'attributes': {'name': 'common-cold'},
        },
      });
      await fails('observation record', {
        'observation': {
          'id': 'mood-2',
          'measure': 'mood',
          'value': 11,
          'observedAt': '2026-11-18T09:00:00+01:00',
        },
      }, 2);
      final pain = await ok('observation resolve', {
        'measure': 'pain',
        'attributes': {'site': 'lower-back', 'impact': 'limits-activity'},
        'asOf': '2026-11-18T12:00:00+01:00',
      });
      equal(pain['value'], 4);

      // 2. A ten-minute breathing practice with phases.
      await ok('practice define', {
        'practice': {
          'id': 'box-breathing',
          'name': 'Slow breathing',
          'kind': 'breathing',
          'durationSeconds': 600,
          'phases': {
            'phases': [
              {'id': 'inhale', 'milliseconds': 4000},
              {'id': 'hold', 'milliseconds': 2000},
              {'id': 'exhale', 'milliseconds': 6000},
            ],
          },
          'ratings': [
            {'id': 'calm', 'label': 'Calm', 'minimum': 0, 'maximum': 10},
          ],
        },
        'expectedRevision': 0,
      });
      final started = await ok('practice start', {
        'id': 'breath-1',
        'practiceId': 'box-breathing',
        'at': '2026-11-18T07:00:00+01:00',
        'before': {'calm': 3},
      });
      equal(jsonObject(started['clock'], 'c')['status'], 'paused');
      // The single foreground clock: nothing else can start meanwhile.
      await fails('practice start', {
        'id': 'breath-2',
        'practiceId': 'box-breathing',
        'at': '2026-11-18T07:01:00+01:00',
      }, 5);
      // Run it in a real process, wait for phase cues, then kill -9.
      final process = await Process.start(await cliExecutable(), [
        'practice',
        'run',
      ]);
      process.stdin.write(
        jsonEncode({
          'schemaVersion': 1,
          'database': db,
          'id': 'breath-1',
          'stream': true,
        }),
      );
      await process.stdin.close();
      final lines = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      final cues = <String>[];
      await for (final line in lines) {
        final data = jsonObject(
          jsonObject(jsonDecode(line), 'line')['data'],
          'data',
        );
        if (data['type'] == 'timing-cue')
          cues.add('${(data['tempo'] as Map?)?['phaseId']}');
        if (cues.contains('hold')) break;
      }
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
      check(cues.contains('inhale') && cues.contains('hold'), '$cues');
      var view = await ok('practice session', {'id': 'breath-1'});
      final clock = jsonObject(view['clock'], 'clock');
      equal(clock['status'], 'running');
      equal(clock['requiresRecovery'], true);
      final elapsed = clock['effortElapsedMilliseconds']! as int;
      check(elapsed >= 4000 && elapsed < 600000, '$elapsed');
      // Confirming before the clock ended is refused.
      await fails('practice confirm', {
        'id': 'breath-1',
        'expectedVersion': 1,
        'at': '2026-11-18T07:11:00+01:00',
      }, 2);
      // Recovery is explicit: here the rest of the ten minutes was done
      // without the app, so the adjustment brings it to its target.
      final recovered = await ok('practice recover', {
        'id': 'breath-1',
        'at': '2026-11-18T07:11:00+01:00',
        'adjustmentMilliseconds': 600000,
      });
      equal(recovered['status'], 'awaitingConfirmation');
      equal(recovered['termination'], 'target');
      // A timer running out does not complete it; confirming does.
      view = await ok('practice session', {'id': 'breath-1'});
      equal(view['status'], 'active');
      final confirmed = await ok('practice confirm', {
        'id': 'breath-1',
        'expectedVersion': 1,
        'at': '2026-11-18T07:11:00+01:00',
        'after': {'calm': 7},
        'notes': 'Lights off.',
      });
      equal(confirmed['status'], 'confirmed');
      jsonEqual(confirmed['before'], {'calm': 3});
      jsonEqual(confirmed['after'], {'calm': 7});
      equal(jsonObject(confirmed['actual'], 'a')['milliseconds'], 600000);
      equal(jsonObject(confirmed['clock'], 'c')['status'], 'confirmed');
      // Now another practice may start; an untimed one can be logged.
      await ok('practice start', {
        'id': 'breath-2',
        'practiceId': 'box-breathing',
        'at': '2026-11-18T21:00:00+01:00',
      });
      await ok('practice abandon', {
        'id': 'breath-2',
        'expectedVersion': 1,
        'confirm': true,
      });
      await ok('practice log', {
        'id': 'stretch-1',
        'practiceId': 'box-breathing',
        'at': '2026-11-18T22:00:00+01:00',
        'milliseconds': 300000,
      });
      await fails('practice log', {
        'id': 'stretch-2',
        'practiceId': 'box-breathing',
        'at': '2026-11-18T22:30:00+01:00',
        'milliseconds': 300000,
        'after': {'calm': 12},
      }, 2);

      // 3. A walk counts toward two categories (routines), once each.
      await ok('activity record', {
        'activity': {
          'id': 'walk-1',
          'kind': 'walk',
          'start': '2026-11-18T12:00:00+01:00',
          'end': '2026-11-18T12:40:00+01:00',
          'outdoor': true,
          'distance': {'value': '3.2', 'unit': 'km'},
          'countsToward': ['movement', 'outdoor-light'],
        },
      });
      await ok('activity record', {
        'activity': {
          'id': 'stairs',
          'kind': 'other',
          'start': '2026-11-18T16:00:00+01:00',
          'end': '2026-11-18T16:10:00+01:00',
          'countsToward': ['movement'],
        },
      });
      await fails('activity record', {
        'activity': {
          'id': 'twice',
          'kind': 'walk',
          'start': '2026-11-18T17:00:00+01:00',
          'end': '2026-11-18T17:10:00+01:00',
          'countsToward': ['movement', 'movement'],
        },
      }, 2);
      final summary = await ok('activity summary', {
        'from': '2026-11-18',
        'until': '2026-11-20',
      });
      final days = (summary['days']! as List).cast<Map<String, Object?>>();
      final categories = jsonObject(days.first['categories'], 'c');
      jsonEqual(categories['movement'], {
        'count': 2,
        'minutes': 50,
        'activities': ['walk-1', 'stairs'],
      });
      jsonEqual(categories['outdoor-light'], {
        'count': 1,
        'minutes': 40,
        'activities': ['walk-1'],
      });
      equal(days.first['outdoorMinutes'], 40);
      equal(days.last['activities'], 0);
      // Imported walks with a GPS track (neutral format).
      final document = {
        'format': 'bodytmi-activity-import/1',
        'source': {'namespace': 'band'},
        'activities': [
          {
            'sourceId': 'w-19',
            'kind': 'walk',
            'start': '2026-11-19T12:00:00+01:00',
            'end': '2026-11-19T12:20:00+01:00',
            'outdoor': true,
            'countsToward': ['movement'],
            'track': [
              {
                'at': '2026-11-19T12:00:00+01:00',
                'latitude': 59.3293,
                'longitude': 18.0686,
              },
              {
                'at': '2026-11-19T12:20:00+01:00',
                'latitude': 59.3383,
                'longitude': 18.0686,
              },
            ],
          },
        ],
      };
      await ok('activity import-validate', {
        'document': document,
      }, database: false);
      await ok('activity import-apply', {
        'document': document,
        'confirm': true,
      });
      final again = await ok('activity import-apply', {
        'document': document,
        'confirm': true,
      });
      equal(jsonObject(again['counts'], 'c')['unchanged'], 1);
      final listed = await ok('activity list', {'from': '2026-11-19'});
      final walk = jsonObject((listed['list']! as List).single, 'w');
      // 0.009° of latitude is about 1.001 km.
      equal(jsonObject(walk['trackDistance'], 't')['value'], '1.001');

      // 4. Backup and logical export keep everything.
      Future<String> snapshot() async => canonicalJson({
        'session': await ok('practice session', {'id': 'breath-1'}),
        'sessions': await ok('practice sessions', {}),
        'summary': await ok('activity summary', {
          'from': '2026-11-18',
          'until': '2026-11-20',
        }),
        'pain': await ok('observation list', {'measure': 'pain'}),
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
