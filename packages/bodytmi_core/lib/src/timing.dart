import 'errors.dart';
import 'instant.dart';
import 'quantity.dart';

int timingInt(
  Map<String, Object?> j,
  String key, {
  int min = 0,
  int max = 604800000,
}) {
  final n = j[key];
  if (n is! int || n < min || n > max)
    invalid('$key must be an integer between $min and $max.');
  return n;
}

final class TimingPlan {
  TimingPlan._(
    this.preparationMilliseconds,
    this.effortMilliseconds,
    this.restMilliseconds,
    this.overrun,
    this.nearEndMilliseconds,
  );
  factory TimingPlan.fromJson(Object? input) {
    final j = jsonObject(input, 'timing plan');
    checkKeys(j, {
      'preparationMilliseconds',
      'effortMilliseconds',
      'restMilliseconds',
      'overrun',
      'nearEndMilliseconds',
    });
    final prep = timingInt(
      {...j, 'preparationMilliseconds': j['preparationMilliseconds'] ?? 0},
      'preparationMilliseconds',
      max: 86400000,
    );
    final effort = timingInt(j, 'effortMilliseconds', min: 1, max: 86400000);
    final rest = timingInt(
      {...j, 'restMilliseconds': j['restMilliseconds'] ?? 0},
      'restMilliseconds',
      max: 86400000,
    );
    final overrun = j['overrun'] ?? 'stop';
    if (!{'stop', 'continue'}.contains(overrun))
      invalid('overrun must be stop or continue.');
    final near = j.containsKey('nearEndMilliseconds')
        ? timingInt(j, 'nearEndMilliseconds', min: 1, max: effort - 1)
        : null;
    return TimingPlan._(prep, effort, rest, overrun as String, near);
  }
  final int preparationMilliseconds, effortMilliseconds, restMilliseconds;
  final String overrun;
  final int? nearEndMilliseconds;
  Map<String, Object?> toJson() => {
    'preparationMilliseconds': preparationMilliseconds,
    'effortMilliseconds': effortMilliseconds,
    'restMilliseconds': restMilliseconds,
    'overrun': overrun,
    if (nearEndMilliseconds != null) 'nearEndMilliseconds': nearEndMilliseconds,
  };
}

/// Result provenance. Later ordinary duration corrections explicitly change mode.
final class TimedResult {
  TimedResult(
    this.timerId,
    this.metric,
    this.elapsedMilliseconds,
    this.termination, {
    this.mode = 'timer',
  }) {
    identifier({'id': timerId}, 'id');
    identifier({'id': metric}, 'id');
    if (elapsedMilliseconds <= 0 ||
        elapsedMilliseconds > 604800000 ||
        !{'target', 'early', 'overrun'}.contains(termination) ||
        !{'timer', 'manual-override', 'manual-edit'}.contains(mode))
      invalid('Invalid timed-result provenance.');
  }
  factory TimedResult.fromJson(Object? input) {
    final j = jsonObject(input, 'timed result');
    checkKeys(j, {
      'timerId',
      'metric',
      'elapsedMilliseconds',
      'termination',
      'mode',
    });
    return TimedResult(
      identifier(j, 'timerId'),
      identifier(j, 'metric'),
      timingInt(j, 'elapsedMilliseconds', min: 1),
      requiredString(j, 'termination'),
      mode: requiredString(j, 'mode'),
    );
  }
  final String timerId, metric, termination, mode;
  final int elapsedMilliseconds;
  TimedResult edited() => TimedResult(
    timerId,
    metric,
    elapsedMilliseconds,
    termination,
    mode: 'manual-edit',
  );
  Map<String, Object?> toJson() => {
    'timerId': timerId,
    'metric': metric,
    'elapsedMilliseconds': elapsedMilliseconds,
    'termination': termination,
    'mode': mode,
  };
}

final class TimingActivity {
  TimingActivity._(this._json);
  factory TimingActivity.create({
    required String id,
    required String sessionId,
    required String setId,
    required String metric,
    required TimingPlan plan,
    required DateTime at,
  }) => TimingActivity.fromJson({
    'id': id,
    'sessionId': sessionId,
    'setId': setId,
    'metric': metric,
    'plan': plan.toJson(),
    'createdAt': at.toUtc().toIso8601String(),
    'checkpointAt': at.toUtc().toIso8601String(),
    'version': 1,
    'status': 'paused',
    'phase': plan.preparationMilliseconds > 0 ? 'preparation' : 'effort',
    'phaseElapsedMilliseconds': 0,
    'effortElapsedMilliseconds': 0,
    'elapsedMilliseconds': 0,
    'ownerId': null,
    'ownerElapsedMilliseconds': 0,
    'termination': null,
    'confirmation': null,
  });
  factory TimingActivity.fromJson(Object? input) {
    final j = jsonObject(input, 'timing activity');
    checkKeys(j, {
      'id',
      'sessionId',
      'setId',
      'metric',
      'plan',
      'createdAt',
      'checkpointAt',
      'version',
      'status',
      'phase',
      'phaseElapsedMilliseconds',
      'effortElapsedMilliseconds',
      'elapsedMilliseconds',
      'ownerId',
      'ownerElapsedMilliseconds',
      'termination',
      'confirmation',
    });
    for (final key in ['id', 'sessionId', 'metric']) identifier(j, key);
    requiredString(j, 'setId');
    TimingPlan.fromJson(j['plan']);
    parseInstant(j['createdAt'], 'createdAt');
    parseInstant(j['checkpointAt'], 'checkpointAt');
    final version = j['version'];
    if (version is! int || version < 1) invalid('Invalid timing version.');
    if (!{
          'paused',
          'running',
          'awaitingConfirmation',
          'confirmed',
          'discarded',
        }.contains(j['status']) ||
        !{'preparation', 'effort', 'rest', 'done'}.contains(j['phase']))
      invalid('Invalid timing state.');
    final phase = timingInt(j, 'phaseElapsedMilliseconds');
    final effort = timingInt(j, 'effortElapsedMilliseconds');
    final total = timingInt(j, 'elapsedMilliseconds');
    timingInt(j, 'ownerElapsedMilliseconds');
    if (j['ownerId'] != null) identifier(j, 'ownerId');
    final p = TimingPlan.fromJson(j['plan']);
    final active = {'paused', 'running'}.contains(j['status']);
    if (active == (j['phase'] == 'done') ||
        (j['status'] == 'running' && j['ownerId'] == null) ||
        (p.overrun == 'stop' && effort > p.effortMilliseconds) ||
        (j['termination'] != null &&
            !{
              'target',
              'early',
              'overrun',
              'no-effort',
            }.contains(j['termination'])) ||
        (j['phase'] == 'preparation' &&
            (phase >= p.preparationMilliseconds ||
                effort != 0 ||
                total != phase ||
                j['termination'] != null)) ||
        (j['phase'] == 'effort' &&
            (phase != effort ||
                total != p.preparationMilliseconds + effort ||
                j['termination'] != null ||
                (p.overrun == 'stop' && effort >= p.effortMilliseconds))) ||
        (j['phase'] == 'rest' &&
            (phase >= p.restMilliseconds ||
                total != p.preparationMilliseconds + effort + phase ||
                j['termination'] == null)) ||
        (!active &&
            (phase != 0 ||
                j['termination'] == null ||
                total < effort ||
                (effort > 0 && total < p.preparationMilliseconds + effort) ||
                total >
                    p.preparationMilliseconds + effort + p.restMilliseconds)) ||
        ((j['termination'] == 'no-effort') !=
            (j['termination'] != null && effort == 0)) ||
        (j['termination'] == 'target' && effort != p.effortMilliseconds) ||
        (j['termination'] == 'early' &&
            (effort <= 0 || effort >= p.effortMilliseconds)) ||
        (j['termination'] == 'overrun' &&
            (effort <= p.effortMilliseconds || p.overrun != 'continue')))
      invalid('Inconsistent timing phase/elapsed state.');
    if ((j['status'] == 'confirmed') != (j['confirmation'] != null))
      invalid('Inconsistent timing confirmation.');
    // Freeze nested JSON; only bounded, validated domain snapshots are retained.
    if (j['confirmation'] != null) {
      final c = jsonObject(j['confirmation'], 'confirmation');
      checkKeys(c, {
        'sourceVersion',
        'at',
        'request',
        'setVersion',
        'sessionVersion',
        'actuals',
        'timing',
      });
      for (final k in ['sourceVersion', 'setVersion', 'sessionVersion']) {
        final n = c[k];
        if (n is! int || n < 1) invalid('Invalid confirmation version.');
      }
      parseInstant(c['at'], 'at');
      final request = jsonObject(c['request'], 'confirmation request');
      checkKeys(request, {
        'expectedSessionVersion',
        'at',
        'actuals',
        'acceptSuggested',
      });
      final expected = request['expectedSessionVersion'];
      if (expected is! int ||
          expected < 1 ||
          c['sessionVersion'] != expected + 1 ||
          request['at'] != c['at'] ||
          request['acceptSuggested'] is! bool)
        invalid('Invalid timing confirmation request.');
      metricsFromJson(request['actuals']);
      final actuals = metricsFromJson(c['actuals']);
      final result = TimedResult.fromJson(c['timing']);
      final duration = actuals[j['metric']];
      if (duration?.dimension != Dimension.duration ||
          ((result.mode == 'timer') !=
              (duration!.compareTo(Quantity(effort.toString(), 'ms')) == 0)))
        invalid('Timing confirmation duration/mode is inconsistent.');
      if (result.timerId != j['id'] ||
          result.metric != j['metric'] ||
          result.elapsedMilliseconds != effort ||
          result.termination != j['termination'] ||
          result.mode == 'manual-edit' ||
          c['sourceVersion'] != version - 1)
        invalid('Timing confirmation does not match its clock.');
    }
    return TimingActivity._(_freeze(j) as Map<String, Object?>);
  }
  final Map<String, Object?> _json;
  String get id => _json['id']! as String;
  String get sessionId => _json['sessionId']! as String;
  String get setId => _json['setId']! as String;
  String get metric => _json['metric']! as String;
  String get status => _json['status']! as String;
  String get phase => _json['phase']! as String;
  int get version => _json['version']! as int;
  int get elapsedMilliseconds => _json['elapsedMilliseconds']! as int;
  int get effortElapsedMilliseconds =>
      _json['effortElapsedMilliseconds']! as int;
  int get phaseElapsedMilliseconds => _json['phaseElapsedMilliseconds']! as int;
  String? get ownerId => _json['ownerId'] as String?;
  int get ownerElapsedMilliseconds => _json['ownerElapsedMilliseconds']! as int;
  String? get termination => _json['termination'] as String?;
  Map<String, Object?>? get confirmation =>
      _json['confirmation'] as Map<String, Object?>?;
  TimingPlan get plan => TimingPlan.fromJson(_json['plan']);
  bool get active => status == 'running' || status == 'paused';
  Map<String, Object?> toJson() => Map.of(_json);
  TimingActivity _change(Map<String, Object?> changes, DateTime at) =>
      TimingActivity.fromJson({
        ..._json,
        ...changes,
        'checkpointAt': at.toUtc().toIso8601String(),
        'version': version + 1,
      });

  TimingActivity resume(String owner, DateTime at) {
    if (status != 'paused')
      invalid(
        'Only a paused clock can resume; recover an interrupted clock explicitly.',
      );
    identifier({'id': owner}, 'id');
    if (owner == ownerId)
      invalid('Resume requires a fresh monotonic clock owner.');
    return _change({
      'status': 'running',
      'ownerId': owner,
      'ownerElapsedMilliseconds': 0,
    }, at);
  }

  TimingActivity pause(DateTime at) {
    if (status != 'running') invalid('Only a running clock can pause.');
    return _change({'status': 'paused'}, at);
  }

  TimingActivity recover(DateTime at, {int? adjustmentMilliseconds}) {
    if (status != 'running')
      invalid('Only an interrupted running clock needs recovery.');
    var next = this;
    if (adjustmentMilliseconds != null)
      next = advance(
        ownerElapsedMilliseconds + adjustmentMilliseconds,
        ownerId!,
        at,
      ).activity;
    return next.status == 'running' ? next.pause(at) : next;
  }

  TimingAdvance advance(int cumulative, String owner, DateTime at) {
    timingInt({'n': cumulative}, 'n');
    if (status != 'running' ||
        owner != ownerId ||
        cumulative < ownerElapsedMilliseconds)
      invalid('Invalid monotonic clock owner/sample.');
    var delta = cumulative - ownerElapsedMilliseconds;
    if (delta == 0) return TimingAdvance(this, const []);
    var currentPhase = phase,
        phaseElapsed = phaseElapsedMilliseconds,
        effort = effortElapsedMilliseconds,
        total = elapsedMilliseconds;
    String? end = termination;
    final cues = <Map<String, Object?>>[];
    final p = plan;
    void cue(String kind) => cues.add({
      'kind': kind,
      'phase': currentPhase,
      'elapsedMilliseconds': total,
    });
    while (delta > 0 && currentPhase != 'done') {
      if (currentPhase == 'effort' && p.overrun == 'continue') {
        final before = effort;
        effort += delta;
        phaseElapsed += delta;
        total += delta;
        delta = 0;
        if (before < p.effortMilliseconds && effort >= p.effortMilliseconds)
          cue('target');
        else if (p.nearEndMilliseconds != null &&
            before < p.effortMilliseconds - p.nearEndMilliseconds! &&
            effort >= p.effortMilliseconds - p.nearEndMilliseconds!)
          cue('near-end');
        break;
      }
      final limit = switch (currentPhase) {
        'preparation' => p.preparationMilliseconds,
        'effort' => p.effortMilliseconds,
        _ => p.restMilliseconds,
      };
      final step = delta < limit - phaseElapsed ? delta : limit - phaseElapsed;
      final before = phaseElapsed;
      phaseElapsed += step;
      total += step;
      delta -= step;
      if (currentPhase == 'effort') effort += step;
      if (phaseElapsed == limit) {
        currentPhase = switch (currentPhase) {
          'preparation' => 'effort',
          'effort' => p.restMilliseconds > 0 ? 'rest' : 'done',
          _ => 'done',
        };
        if (end == null && (currentPhase == 'rest' || currentPhase == 'done'))
          end = 'target';
        phaseElapsed = 0;
        cue('phase');
      } else if (currentPhase == 'effort' &&
          p.nearEndMilliseconds != null &&
          before < limit - p.nearEndMilliseconds! &&
          phaseElapsed >= limit - p.nearEndMilliseconds!)
        cue('near-end');
    }
    final next = _change({
      'phase': currentPhase,
      'phaseElapsedMilliseconds': phaseElapsed,
      'effortElapsedMilliseconds': effort,
      'elapsedMilliseconds': total,
      'termination': end,
      'ownerElapsedMilliseconds': cumulative,
      'status': currentPhase == 'done' ? 'awaitingConfirmation' : 'running',
    }, at);
    return TimingAdvance(next, List.unmodifiable(cues));
  }

  TimingActivity endEffort(DateTime at) {
    if (status != 'running' && status != 'paused')
      invalid('Timing activity is not active.');
    if (phase != 'effort') invalid('Clock is not in effort phase.');
    final end = effortElapsedMilliseconds == 0
        ? 'no-effort'
        : effortElapsedMilliseconds < plan.effortMilliseconds
        ? 'early'
        : effortElapsedMilliseconds == plan.effortMilliseconds
        ? 'target'
        : 'overrun';
    final rest = plan.restMilliseconds > 0;
    return _change({
      'phase': rest ? 'rest' : 'done',
      'phaseElapsedMilliseconds': 0,
      'termination': end,
      'status': rest ? status : 'awaitingConfirmation',
    }, at);
  }

  TimingActivity stop(DateTime at, {bool discard = false}) {
    if (!active && status != 'awaitingConfirmation')
      invalid('Timing activity already reviewed.');
    final end =
        termination ??
        (effortElapsedMilliseconds == 0
            ? 'no-effort'
            : effortElapsedMilliseconds < plan.effortMilliseconds
            ? 'early'
            : effortElapsedMilliseconds == plan.effortMilliseconds
            ? 'target'
            : 'overrun');
    return _change({
      'phase': 'done',
      'phaseElapsedMilliseconds': 0,
      'termination': end,
      'status': discard ? 'discarded' : 'awaitingConfirmation',
    }, at);
  }

  TimingActivity confirmed(Map<String, Object?> receipt, DateTime at) {
    if (status != 'awaitingConfirmation' || effortElapsedMilliseconds == 0)
      invalid('Only nonempty effort timing can be confirmed.');
    return _change({'status': 'confirmed', 'confirmation': receipt}, at);
  }
}

final class TimingAdvance {
  const TimingAdvance(this.activity, this.cues);
  final TimingActivity activity;
  final List<Map<String, Object?>> cues;
}

Object? _freeze(Object? input) => switch (input) {
  Map<String, Object?>() => Map<String, Object?>.unmodifiable({
    for (final k in (input.keys.toList()..sort())) k: _freeze(input[k]),
  }),
  List<Object?>() => List<Object?>.unmodifiable(input.map(_freeze)),
  _ => input,
};
