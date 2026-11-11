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
          'skipRemaining':
              'store skip-remaining takes database/id/expectedVersion/confirm:true and skips all planned efforts without changing completed results or finishing the session. Stop and review or discard session clocks first; use execution skip-group during traversal. session skip-remaining takes session/confirm:true and requires the caller to account for external clock/traversal state.',
          'skipSlot':
              'store skip-slot takes database/id/expectedVersion/slotId/confirm:true and optional role (work, warmup, backoff or drop); session skip-slot takes session/slotId/confirm:true and optional role. The same clock and traversal safeguards apply.',
          'editTarget':
              'session edit-target takes session/setId/metric/value and optional applyToRemaining; store edit-target takes database/id/expectedVersion/setId/metric/value and optional applyToRemaining. Edits planned suggestions only; explicit carry skips authored, derived and manually edited targets. Stored edits cannot change sets with active or unreviewed effort clocks.',
          'carryActual':
              'session carry-actual takes session/setId/metric; store carry-actual takes database/id/expectedVersion/setId/metric. Copies one completed actual to later compatible untouched suggestions in the same slot and role, with the same safeguards as edit-target.',
          'progression':
              'propose requires database/sessionId/slotId/rule; accept requires database/sessionId/slotId/expectedVersion/acceptedAt; decline requires database/sessionId/slotId/expectedVersion/declinedAt; show requires database/sessionId/slotId. Declines hold targets and resolve exposure counters once. Stored application supports manual double and numeric threshold progression; propose accepts optional ruleType:threshold with all/roundRobin/weighted/chosen/priority coordination. Chosen requires coordination.metric; priority requires a unique order and selects one candidate applicable across the complete target vector, with blocked-set explanations. Chosen/priority retain a zero cursor. Threshold performance:{direction:higher/lower,failureLimit,advancementLimit} replaces legacy minimum/threshold when supplied and is independent of lever directions. Best follows performance direction. Threshold rule aggregation supports all/any/best/last/total/kOfN (count required); failureAggregation supports all (default) or total. Threshold directions map controlled metrics to increase (default) or decrease; increments remain positive step sizes, minimums/maximums are inclusive lever bounds, and configured deloads move in the easier direction. Missing work stays unknown and failure gates advancement. Only accepted applicable transitions consume coordinator positions.',
          'observations':
              'session annotate takes session/setId/observations; store annotate takes database/id/expectedVersion/setId/observations. Replaces optional rpe:{value:decimal string,scale:0-10 or 6-20}, rir:nonnegative decimal string, notes (up to 4000 characters), terminationReason:target-reached/max-effort/grip-failure/pain-discomfort/interrupted/other. RPE/RIR require completed actuals. Empty observations clears with confirm:true. Interrupted sets remain in raw reports but are excluded from prefill, stored progression and records. Other reasons are descriptive. Stop the associated active effort clock before annotating.',
          'effortConditions':
              'Threshold rules optionally declare advancementEffort:{rpe:{scale:0-10/6-20,minimum?,maximum?},rir:{minimum?,maximum?}} with decimal-string inclusive bounds. All configured ratings on all required results must qualify. Only advancement is gated: numeric failures/deloads retain precedence; a known unmet gate holds and resets failures, while missing/mismatched ratings at the advancement boundary yield unknown and preserve failures. RPE scales never convert; pain notes remain descriptive. Pure progression evaluate accepts an aligned observations array; stored threshold proposals use the frozen set observations. Interrupted observations make results unknown. Rule changes require reconciliation.',
          'derivedTargets':
              'target resolve evaluates an explicit acyclic graph of source, scale, add, subtract and round nodes. Sources declare unit, sourceId, sourceVersion and value (null when missing); scales declare unit, input and decimal-string factor; add/subtract declare unit, left and right dependencies; round declares input, native scale and rounding policy. Results retain source provenance, use exact canonical arithmetic, propagate missing inputs, and reject negative subtraction.',
          'derivedTargetSnapshots':
              'target capture takes an authored graph and explicit bindings keyed by sourceId, each with version and value. Missing bindings remain unresolved. target status takes a captured snapshot and current bindings, verifies the snapshot and reports source changes and both resolutions. These pure commands do not publish, persist or refresh workout sessions.',
          'derivedTargetGraphs':
              'graph validate takes a reusable graph with source/scale nodes and per-source binding policies: manual (version + value), bodyMass (context, optional asOf and resolver options) or history (metric, direction highest/lowest, optional template/slot/exercise/implementation/equipment/setup/role/ordinal scope, inclusive from, exclusive until, includeWarmups). graph publish requires database/graph/expectedRevision; show takes database/graphId and optional revision; list returns all revisions. graph resolve takes database/graphId, optional revision and asOf, and optional runId or allRuns:true. History defaults to ad hoc sessions; runId selects one run, allRuns explicitly combines all contexts. asOf excludes history finalized after the cutoff and constrains body mass. Body-mass and history provenance include source fingerprints; their sourceVersion values describe only the maximum individual measurement version or selected session version, not a series version. Resolution returns per-source provenance plus the exact resolution. Resolving never modifies graphs, sessions or progression; unresolved sources propagate without inventing values.',
          'graphPreview':
              'graph preview takes database/templateId/revision/graphId/graphRevision/asOf/bindings and optional runId. Each binding maps occurrenceId/metric/nodeId. It previews explicit graph-derived targets without publishing, starting or changing a session. Unresolved values remain unknown; ordinary history prefill and accepted progression are not applied.',
          'graphWorkoutPlans':
              'Published graphs may include plans with id/templateId/revision/bindings; each binding selects occurrenceId/metric/nodeId. Publishing validates the pinned workout and units. graph plan-preview takes database/graphId/graphRevision/planId/asOf and optional runId to preview a saved plan. Plans can also be selected at session start.',
          'derivedSessionPlans':
              'store start and run start optionally accept derivedPlan:{graphId,graphRevision,planId}. Published plans with manual, body-mass or history graph sources and numeric targets or bounded objectives are frozen and applied at start. History is scoped to the selected run or ad hoc context, and requires earlier finalized sessions. Overlap with accepted progression is rejected; observe and max-effort objectives cannot receive suggestions. Retry must use the same plan reference.',
          'derivedSessionPlanStatus':
              'store plan-status takes database/id and compares the stored session’s frozen plan and source evidence with current inputs at its original start cutoff and run scope. Sessions without a derived plan report configured:false. History must have started before the session and finished by its start time. It is read-only and does not change session suggestions or progression. store plan-refresh takes database/id/expectedVersion/expectedPreview/confirm:true, where expectedPreview is comparison.currentPreview from store plan-status. It verifies that preview atomically and re-resolves the same pinned plan before work, timing or traversal; it does not change slot body-mass inputs.',
          'graphPlanStatus':
              'graph plan-status takes database/planPreview from graph plan-preview. It verifies that the mapping is the published plan and reports source and target changes in its original scope. Captured source evidence is caller-provided and not authenticated; no session is started or modified.',
          'graphPreviewStatus':
              'graph preview-status takes database/preview from graph preview and compares its pinned workout, graph, source fingerprints and mapped values with current data in the same scope. Caller-supplied preview evidence is not authenticated; this read-only query does not authorize or start a session.',
          'graphStatus':
              'graph status takes database/snapshot from graph resolve, checks graph revision, scope and arithmetic, then compares the captured sources with a fresh resolution in the same scope. The supplied snapshot is caller-provided evidence, not an authenticated audit record; status never changes a session or progression.',
          'publishedObjectives':
              'Effort objectives may declare exact, minimum, maximum, range, observe or maxEffort criteria using the objective evaluate schema. Maximum/range require an explicit upperMeaning. Bounds are descriptive, not prohibited actuals or automatic progression rules. Numeric suggestions remain independently accepted; observe/maxEffort require explicitly entered actuals. Targetless objectives require an explicit actual. Pinned criteria appear in session summaries/series, and changed working objectives require progression reconciliation.',
          'objectiveAssessment':
              'objective evaluate takes objectives and actuals; session assess-objectives takes session/setId/objectives; store assess-objectives takes database/id/setId/objectives. Criteria are explicitly supplied for this read-only query, not saved to the workout. Modes: exact(value), minimum(minimum), maximum(maximum,upperMeaning), range(minimum,maximum,upperMeaning), observe(unit), maxEffort(unit:rep). upperMeaning is desiredCeiling/progressionThreshold/stoppingCue. Bounds are inclusive, missing values stay unknown, and the report never applies progression or delivers cues.',
          'objectives':
              'Effort activities may declare objectives:{metric:{mode:maxEffort,unit:rep}}. Each declared repetition metric is explicitly observed without a numeric suggestion; acceptSuggested cannot supply it. Completion, execution and timer confirmation require its actual count, including an explicit zero. Threshold progression can use these actuals without inventing targets. Changing working objective modes requires progression reconciliation. Time-window AMRAP remains pending.',
          'effortTargets':
              'Effort activities may declare nonempty targets overrides for existing slot metrics with compatible dimensions. Other metrics inherit slot targets; repeat occurrences retain independent results. Authored overrides take precedence over history prefill for those metrics. Published slot timing defaults must resolve for each authored override. Accepted progression can supply controlled working targets when the authored baseline is unchanged; changed controlled per-effort targets require reconciliation. Warmups stay independent.',
          'incrementBands':
              'Threshold rules optionally declare incrementBands:{aggregation:{mode:last/best/total},bands:[{id,threshold, increments}]}. Thresholds use the performance metric/direction and must be strictly ordered from easier to harder; strongest qualifying inclusive band replaces every base increment with compatible positive steps. Otherwise base steps apply. Numeric/effort gates precede selection; bounds hold the whole vector without falling back to a lesser band. Existing coordinator selection, native scale rounding and resets remain explicit. Proposals expose incrementBandAssessment. This is generic performance-dependent stepping, including last-set bonus steps.',
          'scales':
              'scale validate takes scale{id,unit} with exactly one of ticks:[{id,value,labels?}] or range:{start,step,count,idPrefix?}. Fixed ranges declare 1–1000 native positions with a positive step and deterministic tick IDs. scale resolve also takes target/rounding (nearest/atMost/atLeast), with optional beyond/direction together. Threshold scales bind controlled metrics to frozen scale/rounding/deloadRounding; directional lookup excludes the current setting and records selected ticks. These are nominal numeric settings; inventories and plate arrangements remain separate.',
          'bodyMass':
              'mass record/update/delete/show/list/trend/resolve use stored observations and require database. Measurements may include optional source and notes; updates replace the observation and require expectedVersion. Deletion requires expectedVersion and confirm:true. measurement trend/resolve still take explicit measurement arrays.',
          'sessionBodyMass':
              'Slots may explicitly configure bodyMass.context and resolver options. Session starts freeze selected inputs; optional bodyMassOverrides maps slot IDs to measurementId or mass overrides. store mass-status takes database/id; session mass-status takes session/measurements. Source changes do not rewrite captured inputs. store mass-refresh requires database/id/expectedVersion/confirm:true and explicitly recaptures slot mass at the original start cutoff before work, timing or traversal; session mass-refresh accepts session/measurements/confirm:true. Existing overrides and derived plans stay pinned. store mass-rebind takes database/id/expectedVersion/bodyMassOverrides/confirm:true to replace selected slot overrides before work; a null slot override returns to its configured trend. Original start identity and derived plans remain pinned.',
          'effectiveLoad':
              'Slots may configure an effectiveMass model with explicit bodyMassFraction, addedMass and assistance components. store effective-load takes database/id; session effective-load takes session. Derived suggested/confirmed-actual estimates preserve raw inputs and do not change progression.',
          'programs':
              'program publish pins workout revisions and may pin a derivedPlan per day; run create permits multiple active runs. Pinned day plans are applied automatically at run start. run start selects runId; store finish advances its bound occurrence once. Use run show/list for cursor and currentSessionId; run schedule takes runId and optional count (1–1000) and includeScopes to inspect upcoming days and authored group/repeat context without dates or changes.',
          'analytics':
              'session summary takes session; store summary takes database/id. Optional sumMetrics explicitly selects raw metric sums; warmups are excluded by default. history series/records take sessions and optional runBySession; store series/records read database history. Summaries, series and records support explicit roles selection; series also support metric, exact context, inclusive from/exclusive until and includeActive. Only confirmed results appear; series retain separate role/slot/setup/equipment/run contexts and source versions.',
          'records':
              'history records takes sessions/metric/direction (higher/lower); store records takes database/metric/direction. Optional atActuals filters exact observed quantities; context/from/until/includeWarmups and family selection mirror series (records always use finalized work). Other observed metrics, setup/run/role and timing guidance stay separate. Tracked body-mass/derived-load contexts are excluded pending record policies. Reports include neutral markers, ties, source versions and exclusions; queries do not apply progression.',
          'families':
              'family validate takes family{id,name,exercises}. family publish requires database/family/expectedRevision; show takes database/familyId and optional revision; list returns all revisions. Families may overlap and do not imply comparable loads. store series accepts familyId and optional familyRevision; history series accepts a family revision snapshot. Reports pin membership and preserve contextual series.',
          'timing':
              'timer start creates a paused per-set clock; omitted metric selects the published timing metric or the only duration target, and omitted plan resolves the pinned slot timing defaults against its duration suggestion; timer rest times an authored rest occurrence. timer run uses a foreground monotonic clock. Optional stream:true emits NDJSON cue envelopes before the final response. Ctrl-C pauses; unexpected interruption requires explicit timer recover (freeze/adjust). Effort expiry never logs actuals: timer confirm requires expectedSessionVersion and explicit result review. Slots may publish timing defaults with an explicit duration metric, preparation, tempo, near-end and overrun. Explicit clock plans replace defaults. Optional plan.tempo defines repeating effort cues; tempoState exposes logical phase without counting achieved reps. Audio is pending.',
          'execution':
              'execution start/show/list/time/complete/confirm/advance/skip/skip-group/run traverse finite effort/rest occurrences. Timed rests prepare a clock; rest nodes with manual:true have no timer and require execution advance. run advances timed rest boundaries; timed efforts require explicit review. Actions require execution/session versions and stable requestId; corrections never replay cursor advancement. skip-group requires an explicit groupPath from the current groups list and confirm:true; it preserves existing results. Scoped windows are not yet supported.',
          'effortRoles':
              'Effort roles are work, warmup, backoff and drop. Prefill and reports keep roles separate; summaries include all except warmups by default and accept an explicit roles list. Graph history sources can explicitly filter by role. Stored progression propose/show/accept/decline accept an optional role, default work; each role has an independent receipt, targets and counter within its run.',
          'activityGroups':
              'activity groups takes definition and optional containing occurrence index. It reports half-open group bounds and authored durations for window scopes, including repeated and nested windows. This is structural inspection only; scoped window execution remains unsupported.',
          'windowStatus':
              'activity window-repeat-page previews one paged virtual round using an explicit deadline and safety limits. activity window-repeat-cursor provides caller-owned structural steps and explicit logical clock samples; it does not save or certify results. activity window-repeat-execution adds explicit effort reviews, including while running with an owner clock sample, version-checked result corrections, explicit boundary batch reviews and round summaries to a caller-owned cursor; it does not persist training sessions. activity window-status takes definition/occurrence/elapsedMilliseconds/windowStarts. It calculates nested authored window deadlines from explicit shared logical milliseconds. activity window-crossing compares two logical samples and identifies the earliest crossed window boundary and its occurrence bounds, including tied deadlines. activity window-transition calculates entered and exited scopes and carries their logical starts to an explicitly selected later occurrence. activity window-clock operates on an explicit caller-owned clock snapshot with start/resume/advance/pause/recover/move actions. Recovery freezes the last sample or accepts explicit adjustmentMilliseconds; samples and adjustments stop at the first deadline. Clock snapshots retain the current occurrence start and boundary paths and unapplied elapsed time; no results are inferred. session window-clock and store window-clock bind caller-owned clock snapshots to a session and require explicit completed or skipped efforts before movement. session window-review and store window-review explicitly complete or skip the current effort and move the caller-owned clock together using session and clock versions; stored review persists the session but not the clock. checkpoint save/show/list/delete manage session-bound snapshots. session rounds and store rounds report explicit completed and partial iterations of a selected finite repeat, without inferring work from time. checkpoint status derives current occurrence, window deadlines, pending boundary reviews and whether recovery is required before a new owner; it does not change state. checkpoint reserve/release explicitly control the profile timing slot; checkpoint action persists owner-supplied clock samples, and checkpoint review atomically saves explicit results and the moved clock. Release and deletion require confirmation; running clocks require recovery after interruption. Window effort reviews may include explicit nonempty observations, including an interrupted termination reason; no interruption is inferred. checkpoint complete-current explicitly records the current effort while leaving the clock on its window, so the remaining time can be used for recovery. checkpoint review-expired-batch records explicitly reviewed efforts and confirmed skips together at a boundary. checkpoint review-expired explicitly completes the current effort and skips remaining planned work atomically at a boundary. checkpoint skip-expired explicitly skips remaining planned work in the expired window and moves its checkpoint atomically, requiring confirm:true. checkpoint advance-boundary moves past expired windows only when all crossed efforts were reviewed. checkpoint advance-rest acknowledges a reached timed rest or confirmed manual rest and prepares the next occurrence paused. checkpoint run uses a foreground monotonic clock until a boundary or optional runForMilliseconds; advanceReviewed:true optionally moves past fully reviewed boundaries and pauses at the next occurrence; stopAtRest:true pauses at the current authored timed-rest target, unless a window boundary comes first; advanceRest:true optionally moves to the next paused occurrence after that target; stream:true emits NDJSON start and boundary events. Ctrl-C pauses; unexpected interruption requires checkpoint action recover. Automatic traversal remains pending.',
          'tempoSample':
              'tempo sample takes tempo/previousElapsedMilliseconds/elapsedMilliseconds and optional includeInitial. It returns the current phase and at most the newest crossed cue from explicit effort-time samples; it does not own a clock, deliver audio or count reps.',
          'unplannedTiming':
              'timer start and execution time/run can time a set without a prescribed duration metric using an explicit plan with unplannedDuration:true and an explicit unused duration metric ID. Specify either effortMilliseconds or openEnded:true; end open-ended effort explicitly. Tempo is optional. Confirming records elapsed duration and requires explicit remaining actuals or acceptSuggested. A slot may instead publish timing with metric and openEnded:true plus optional preparation and tempo; omitted clock plans use the pinned guidance. The workout prescription is unchanged.',
          'roleProgressionPreview':
              'session progression-preview takes session/slotId/rule and optional role, ruleType and state; store progression-preview takes database/id instead of session and optionally useTrack:true to load current run/role lineage instead of state. Active sessions can be previewed but must be finalized before creating durable decisions. Role defaults to work; ruleType defaults to double. Preview is read-only and does not apply targets or create progression decisions.',
          'progressionTrack':
              'progression track takes database/templateId/revision/slotId/asOf and optional runId/role. It reports the latest resolved decision eligible at the cutoff, with controlled targets and current source-change status; omitted runId selects ad hoc sessions. It does not check prescription compatibility or apply progression.',
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
