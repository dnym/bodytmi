import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bodytmi/bodytmi.dart';
import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:sqlite3/sqlite3.dart';

Future<void> main(List<String> arguments) async {
  try {
    if (arguments.isEmpty ||
        (arguments.length == 1 && arguments.single == '--help')) {
      stdout.writeln(
        jsonEncode({
          'schemaVersion': 1,
          'commands': [...commandNames, ...storedCommandNames],
          'usage': 'bodytmi <group> <action> [--input FILE|-]',
          'input': 'One JSON request, schemaVersion: 1, from stdin or --input.',
          'storage':
              'store commands require a database path in the JSON request. Existing commands use explicit snapshots.',
          'backup':
              'create requires database/destination; validate requires source; restore requires database/source/recoveryDestination/confirm:true. Backup paths are directories.',
          'archive':
              'export requires database/destination; validate requires source; restore requires database/source/recoveryDestination/confirm:true. Logical exports are JSON files; recovery backups are directories.',
          'progression':
              'propose requires database/sessionId/slotId/rule; accept requires database/sessionId/slotId/expectedVersion/acceptedAt; decline requires database/sessionId/slotId/expectedVersion/declinedAt; show requires database/sessionId/slotId. Declines hold targets and resolve exposure counters once. Stored application supports manual double and numeric threshold progression; propose accepts optional ruleType:threshold with all/roundRobin/weighted/chosen/priority coordination. Chosen requires coordination.metric; priority requires a unique order and selects one candidate applicable across the complete target vector, with blocked-set explanations. Chosen/priority retain a zero cursor. Threshold performance:{direction:higher/lower,failureLimit,advancementLimit} replaces legacy minimum/threshold when supplied and is independent of lever directions. Best follows performance direction. Threshold rule aggregation supports all/any/best/last/total/kOfN (count required); failureAggregation supports all (default) or total. Threshold directions map controlled metrics to increase (default) or decrease; increments remain positive step sizes, minimums/maximums are inclusive lever bounds, and configured deloads move in the easier direction. Missing work stays unknown and failure gates advancement. Only accepted applicable transitions consume coordinator positions.',
          'scales':
              'scale validate takes scale{id,unit} with exactly one of ticks:[{id,value,labels?}] or range:{start,step,count,idPrefix?}. Fixed ranges declare 1–1000 native positions with a positive step and deterministic tick IDs. scale resolve also takes target/rounding (nearest/atMost/atLeast), with optional beyond/direction together. Threshold scales bind controlled metrics to frozen scale/rounding/deloadRounding; directional lookup excludes the current setting and records selected ticks. These are nominal numeric settings; inventories and plate arrangements remain separate.',
          'bodyMass':
              'mass record/update/delete/show/list/trend/resolve use stored observations and require database. Updates/deletion require expectedVersion; deletion requires confirm:true. measurement trend/resolve still take explicit measurement arrays.',
          'sessionBodyMass':
              'Slots may explicitly configure bodyMass.context and resolver options. Session starts freeze selected inputs; optional bodyMassOverrides maps slot IDs to measurementId or mass overrides. store mass-status takes database/id; session mass-status takes session/measurements. Source changes do not rewrite captured inputs.',
          'effectiveLoad':
              'Slots may configure an effectiveMass model with explicit bodyMassFraction, addedMass and assistance components. store effective-load takes database/id; session effective-load takes session. Derived suggested/confirmed-actual estimates preserve raw inputs and do not change progression.',
          'programs':
              'program publish pins workout revisions; run create permits multiple active runs. run start selects runId; store finish advances its bound occurrence once. Use run show/list for cursor and currentSessionId.',
          'analytics':
              'session summary takes session; store summary takes database/id. Optional sumMetrics explicitly selects raw metric sums; warmups are excluded by default. history series takes sessions and optional runBySession; store series reads database history. Series support metric, exact context, inclusive from/exclusive until, includeWarmups and includeActive. Only confirmed results appear; series retain separate slot/setup/equipment/run contexts and source versions.',
          'families':
              'family validate takes family{id,name,exercises}. family publish requires database/family/expectedRevision; show takes database/familyId and optional revision; list returns all revisions. Families may overlap and do not imply comparable loads. store series accepts familyId and optional familyRevision; history series accepts a family revision snapshot. Reports pin membership and preserve contextual series.',
          'timing':
              'timer start creates a paused per-set clock; omitted plan resolves the pinned slot timing defaults against its duration suggestion; timer rest times an authored rest occurrence. timer run uses a foreground monotonic clock. Optional stream:true emits NDJSON cue envelopes before the final response. Ctrl-C pauses; unexpected interruption requires explicit timer recover (freeze/adjust). Effort expiry never logs actuals: timer confirm requires expectedSessionVersion and explicit result review. Slots may publish timing defaults with an explicit duration metric, preparation, tempo, near-end and overrun. Explicit clock plans replace defaults. Optional plan.tempo defines repeating effort cues; tempoState exposes logical phase without counting achieved reps. Scoped windows and audio are pending.',
          'execution':
              'execution start/show/list/time/complete/confirm/advance/skip/skip-group/run traverse finite effort/rest occurrences. Completion or timing review prepares the next authored rest. run advances a rest boundary; timed efforts require explicit review. Actions require execution/session versions and stable requestId; corrections never replay cursor advancement. skip-group requires an explicit groupPath from the current groups list and confirm:true; it preserves existing results. Scoped windows are not yet supported.',
        }),
      );
      return;
    }
    if (arguments.length == 1 && arguments.single == '--version') {
      stdout.writeln(jsonEncode({'schemaVersion': 1, 'version': '0.1.0'}));
      return;
    }
    if (arguments.length != 2 && arguments.length != 4) {
      throw const BodyTmiException(
        'usage',
        'Expected <group> <action> [--input FILE|-].',
      );
    }
    final command = arguments.take(2).join(' ');
    if ((!commandNames.contains(command) &&
            !storedCommandNames.contains(command)) ||
        (arguments.length == 4 && arguments[2] != '--input')) {
      throw const BodyTmiException(
        'usage',
        'Unknown command/option. Use --help.',
      );
    }
    const maxBytes = 8 * 1024 * 1024;
    final inputPath = arguments.length == 4 ? arguments[3] : '-';
    final stream = inputPath == '-' ? stdin : File(inputPath).openRead();
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      if (bytes.length + chunk.length > maxBytes)
        invalid('Request exceeds the 8 MiB resource limit.');
      bytes.add(chunk);
    }
    final request = jsonObject(
      jsonDecode(utf8.decode(bytes.takeBytes())),
      'request',
    );
    final response = storedCommandNames.contains(command)
        ? await executeStored(command, request)
        : const Commands().execute(command, request);
    stdout.writeln(jsonEncode(response));
  } on BodyTmiException catch (error) {
    _error(error.code, error.message);
    exitCode = switch (error.code) {
      'not_found' => 3,
      'conflict' || 'in_use' => 5,
      'storage' => 4,
      _ => 2,
    };
  } on FormatException catch (error) {
    _error('validation', 'Invalid JSON/text: ${error.message}');
    exitCode = 2;
  } on SqliteException catch (error) {
    _error('storage', error.message);
    exitCode = 4;
  } on FileSystemException catch (error) {
    _error('io', error.message);
    exitCode = 4;
  } catch (error, stack) {
    _error('internal', '$error');
    stderr.writeln(stack);
    exitCode = 70;
  }
}

void _error(String code, String message) => stderr.writeln(
  jsonEncode({
    'schemaVersion': 1,
    'error': {'code': code, 'message': message},
  }),
);
