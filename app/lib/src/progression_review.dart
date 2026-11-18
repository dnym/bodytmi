import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:material_ui/material_ui.dart';

import 'format.dart';
import 'profile.dart';
import 'quick_entry.dart' show ProblemText;
import 'session.dart' show metricsText;
import 'widgets.dart';

const _outcomes = {
  'increaseObjective': 'Add reps',
  'increaseLever': 'Add weight',
  'advance': 'Advance',
  'hold': 'Hold',
  'deload': 'Deload',
  'stage': 'Next stage',
  'failed': 'Missed',
  'review': 'Needs review',
  'unknown': 'Not enough data',
  'blocked': 'At the limit',
  'choice': 'Choose the next level',
  'retest': 'Retest',
};

/// A readable outcome label; unknown outcomes keep their id.
String outcomeLabel(Object? outcome) => _outcomes['$outcome'] ?? '$outcome';

/// `60 kg × 9 · 3 sets`, or each set when they differ.
String nextSetsText(Fmt f, Object? sets) {
  final list = [for (final s in (sets as List?) ?? const []) metricsText(f, s)];
  if (list.isEmpty) return '—';
  if (list.toSet().length == 1) {
    return list.length == 1
        ? list.first
        : '${list.first} · ${list.length} sets';
  }
  return list.join(', ');
}

/// After a finished workout: one proposal per slot whose workout names a
/// progression preset, proposed on first view, then accepted or declined by
/// you. Nothing changes until you accept.
final class ProgressionReview extends StatelessWidget {
  const ProgressionReview({
    super.key,
    required this.sessionId,
    required this.slots,
    required this.titleOf,
  });
  final String sessionId;
  final List<Map<String, Object?>> slots; // slots pinning a preset
  final String Function(String slotId) titleOf;

  Future<List<(String, Map<String, Object?>?, String?)>> _load(
    ProfileClient p,
  ) async {
    final out = <(String, Map<String, Object?>?, String?)>[];
    for (final slot in slots) {
      final id = '${slot['id']}';
      try {
        out.add((
          id,
          await p.call<Map<String, Object?>>('progression show', {
            'sessionId': sessionId,
            'slotId': id,
          }),
          null,
        ));
      } on BodyTmiException catch (e) {
        if (e.code != 'not_found') {
          out.add((id, null, e.message));
          continue;
        }
        try {
          out.add((
            id,
            await p.write<Map<String, Object?>>('progression propose', {
              'sessionId': sessionId,
              'slotId': id,
            }),
            null,
          ));
        } on BodyTmiException catch (e) {
          out.add((id, null, e.message));
        }
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) =>
      ProfileLoader<List<(String, Map<String, Object?>?, String?)>>(
        load: _load,
        builder: (context, rows) => SectionCard(
          title: 'Progression',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (slot, decision, problem) in rows)
                _DecisionRow(
                  sessionId: sessionId,
                  slotId: slot,
                  title: titleOf(slot),
                  decision: decision,
                  problem: problem,
                ),
            ],
          ),
        ),
      );
}

final class _DecisionRow extends StatefulWidget {
  const _DecisionRow({
    required this.sessionId,
    required this.slotId,
    required this.title,
    required this.decision,
    required this.problem,
  });
  final String sessionId;
  final String slotId;
  final String title;
  final Map<String, Object?>? decision;
  final String? problem;

  @override
  State<_DecisionRow> createState() => _DecisionRowState();
}

final class _DecisionRowState extends State<_DecisionRow> {
  String? level;
  String? problem;
  bool busy = false;

  Future<void> _act(String command, Map<String, Object?> fields) async {
    setState(() {
      busy = true;
      problem = null;
    });
    try {
      await ProfileScope.of(context).write(command, {
        'sessionId': widget.sessionId,
        'slotId': widget.slotId,
        ...fields,
      });
    } on BodyTmiException catch (e) {
      if (mounted) setState(() => problem = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = Fmt.of(context);
    final d = widget.decision;
    final proposal = (d?['proposal'] as Map?) ?? const {};
    final status = '${d?['status'] ?? ''}';
    final candidates = [
      if (proposal['outcome'] == 'choice')
        for (final c in (proposal['candidates'] as List?) ?? const [])
          '${c is Map ? c['id'] ?? c['level'] : c}',
    ];
    final now = isoInstant(DateTime.now());
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (d != null)
                Pill(
                  status == 'pending'
                      ? outcomeLabel(proposal['outcome'])
                      : status,
                  warn: status == 'pending' && d['stale'] == true,
                ),
            ],
          ),
          if (widget.problem != null) Muted(widget.problem!),
          if (d != null) ...[
            if (proposal['reason'] != null) Muted('${proposal['reason']}'),
            Text(
              status == 'declined'
                  ? 'Targets stay as they were.'
                  : 'Next: ${nextSetsText(f, at(d, ['resolvedState', 'nextSets']) ?? proposal['nextSets'])}',
            ),
            if (status == 'pending' && d['stale'] == true)
              const Muted(
                'This workout was edited after the proposal; propose again.',
              ),
            if (status == 'pending' && candidates.isNotEmpty)
              Wrap(
                spacing: 6,
                children: [
                  for (final c in candidates)
                    ChoiceChip(
                      label: Text(c),
                      selected: level == c,
                      onSelected: (_) => setState(() => level = c),
                    ),
                ],
              ),
            if (status == 'pending')
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (d['stale'] == true)
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => _act('progression propose', const {}),
                      child: const Text('Propose again'),
                    )
                  else ...[
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => _act('progression decline', {
                              'expectedVersion': d['version'],
                              'declinedAt': now,
                            }),
                      child: const Text('Decline'),
                    ),
                    FilledButton(
                      onPressed:
                          busy || (candidates.isNotEmpty && level == null)
                          ? null
                          : () => _act('progression accept', {
                              'expectedVersion': d['version'],
                              'acceptedAt': now,
                              'selectedLevel': ?level,
                            }),
                      child: const Text('Accept'),
                    ),
                  ],
                ],
              ),
          ],
          if (problem != null) ProblemText(problem!),
        ],
      ),
    );
  }
}
