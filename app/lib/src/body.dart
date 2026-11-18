import 'package:material_ui/material_ui.dart';

import 'format.dart';
import 'profile.dart';
import 'theme.dart';
import 'widgets.dart';

final class _BodyData {
  _BodyData(this.report, this.trend, this.steps);
  final Map<String, Object?> report;
  final List<Map<String, Object?>> trend;
  final List<Map<String, Object?>> steps;
}

/// The Body tab: mass trend, composition from the selected body-fat
/// source, and a week of steps.
final class BodyScreen extends StatefulWidget {
  const BodyScreen({super.key, this.clock});
  final DateTime? clock;

  @override
  State<BodyScreen> createState() => _BodyScreenState();
}

final class _BodyScreenState extends State<BodyScreen> {
  int weeks = 12;

  Future<_BodyData> _load(ProfileClient p) async {
    final now = widget.clock ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final asOf = isoInstant(now);
    final trend = await p.call<Map<String, Object?>>('mass trend', {
      'context': 'health',
      'asOf': asOf,
    });
    final steps = await p.call<List<Object?>>('observation list', {
      'measure': 'steps',
      'from': isoDate(today.subtract(const Duration(days: 6))),
      'until': isoDate(today.add(const Duration(days: 1))),
    });
    return _BodyData(
      await p.call<Map<String, Object?>>('body report', {'asOf': asOf}),
      [
        for (final d in (trend['days'] as List?) ?? const [])
          d as Map<String, Object?>,
      ],
      [
        for (final o in steps.cast<Map<String, Object?>>())
          if (o['deleted'] != true) o['observation']! as Map<String, Object?>,
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ProfileLoader<_BodyData>(
    load: _load,
    builder: (context, d) {
      final f = Fmt.of(context);
      final cutoff = DateTime.now().subtract(Duration(days: weeks * 7));
      final shown = [
        for (final day in d.trend)
          if (!DateTime.parse(day['date']! as String).isBefore(cutoff)) day,
      ];
      double value(Map<String, Object?> day, String key) =>
          double.parse(at(day, [key, 'value'])! as String);
      final calcs = at(d.report, ['calculations']) as Map? ?? const {};
      final bodyFat = at(d.report, ['bodyFatSource']) as Map?;
      final source = at(bodyFat, ['source']);
      final sourceName = switch (source) {
        {'calculation': 'navy-body-fat'} => 'Navy',
        {'calculation': 'jackson-pollock-3'} => 'Jackson–Pollock 3',
        {'calculation': 'jackson-pollock-7'} => 'Jackson–Pollock 7',
        {'kind': 'mean'} => 'mean',
        {'method': final String m} => m,
        _ => 'source',
      };
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 4, label: Text('4 wk')),
                ButtonSegment(value: 12, label: Text('12 wk')),
                ButtonSegment(value: 52, label: Text('1 yr')),
              ],
              selected: {weeks},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => weeks = s.single),
            ),
          ),
          SectionCard(
            title: 'Mass',
            trailing: const Muted('trend · health'),
            child: shown.length < 2
                ? const EmptyNote('Weigh in on a few days to see a trend.')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      BigFigure(
                        f.number(value(shown.last, 'trend')),
                        unit: 'kg',
                      ),
                      const SizedBox(height: 8),
                      LineChart(
                        values: [for (final x in shown) value(x, 'trend')],
                        raw: [
                          for (final x in shown)
                            if (at(x, ['mass', 'value']) != null)
                              value(x, 'mass'),
                        ],
                        height: 110,
                      ),
                    ],
                  ),
          ),
          SectionCard(
            title: 'Composition',
            child: Column(
              children: [
                _Row(
                  'Body fat',
                  tag: sourceName,
                  value: bodyFat?['status'] == 'resolved'
                      ? '${f.number(double.parse(at(bodyFat, ['value', 'value'])! as String) * 100)} %'
                      : null,
                  note: bodyFat?['reason'] as String?,
                ),
                for (final (key, label, unit, digits) in [
                  ('fat-free-mass', 'Fat-free mass', 'kg', 1),
                  ('ffmi', 'FFMI', '', 1),
                  ('bmi', 'BMI', '', 1),
                  ('waist-to-height', 'Waist-to-height', '', 2),
                ])
                  if (calcs[key] case final Map c)
                    _Row(
                      label,
                      value: c['status'] == 'resolved'
                          ? '${f.number(at(c, ['value', 'value']), digits: digits, pad: true)}'
                                '${unit.isEmpty ? '' : ' $unit'}'
                          : null,
                      note: c['reason'] as String?,
                    ),
              ],
            ),
          ),
          SectionCard(
            title: 'Steps · last 7 days',
            child: d.steps.isEmpty
                ? const EmptyNote('No step counts yet.')
                : _StepBars(d.steps),
          ),
        ],
      );
    },
  );
}

final class _Row extends StatelessWidget {
  const _Row(this.label, {this.value, this.note, this.tag});
  final String label;
  final String? value;
  final String? note;
  final String? tag;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  text: label,
                  children: [
                    if (tag != null)
                      TextSpan(
                        text: '  $tag',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.of(context).muted,
                        ),
                      ),
                  ],
                ),
              ),
              if (value == null && note != null) Muted(note!),
            ],
          ),
        ),
        Text(
          value ?? 'unavailable',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: value == null ? AppColors.of(context).muted : null,
          ),
        ),
      ],
    ),
  );
}

final class _StepBars extends StatelessWidget {
  const _StepBars(this.steps);
  final List<Map<String, Object?>> steps;

  @override
  Widget build(BuildContext context) {
    final f = Fmt.of(context);
    final values = [
      for (final s in steps) double.parse(at(s, ['value', 'value'])! as String),
    ];
    final max = values.fold<double>(1, (a, b) => a > b ? a : b);
    final total = values.fold<double>(0, (a, b) => a + b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 80,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final v in values)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: FractionallySizedBox(
                      heightFactor: (v / max).clamp(0.04, 1),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Muted('Total ${f.number(total, digits: 0)} · today may still grow'),
      ],
    );
  }
}
