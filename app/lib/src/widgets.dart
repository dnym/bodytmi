import 'package:material_ui/material_ui.dart';

import 'theme.dart';

/// A titled card section (design A).
final class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    this.title,
    this.trailing,
    required this.child,
  });

  final String? title;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null || trailing != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  if (title != null)
                    Expanded(child: SectionLabel(title!))
                  else
                    const Spacer(),
                  ?trailing,
                ],
              ),
            ),
          child,
        ],
      ),
    ),
  );
}

/// Small upper-case label.
final class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.8,
      color: AppColors.of(context).muted,
    ),
  );
}

/// A rounded tag; [warn] uses the warning tone.
final class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.warn = false});
  final String text;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: warn ? c.warnSoft : c.accentSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: warn ? c.warn : Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

/// A large figure with a unit, e.g. `83.6 kg`.
final class BigFigure extends StatelessWidget {
  const BigFigure(this.value, {super.key, this.unit});
  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: value,
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
          ),
        ),
        if (unit != null)
          TextSpan(
            text: ' $unit',
            style: TextStyle(fontSize: 15, color: AppColors.of(context).muted),
          ),
      ],
    ),
  );
}

/// Secondary text.
final class Muted extends StatelessWidget {
  const Muted(this.text, {super.key, this.align});
  final String text;
  final TextAlign? align;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: align,
    style: TextStyle(fontSize: 13, color: AppColors.of(context).muted),
  );
}

/// A thin progress bar; [fraction] is clamped to 0–1.
final class Meter extends StatelessWidget {
  const Meter(this.fraction, {super.key});
  final double fraction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: fraction.clamp(0, 1),
        minHeight: 8,
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
    ),
  );
}

/// A message for an empty section, never a fake zero.
final class EmptyNote extends StatelessWidget {
  const EmptyNote(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Muted(text),
  );
}

/// A simple line chart of values (oldest first), with an optional fainter
/// raw series behind it.
final class LineChart extends StatelessWidget {
  const LineChart({
    super.key,
    required this.values,
    this.raw = const [],
    this.height = 80,
  });

  final List<double> values;
  final List<double> raw;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: CustomPaint(
      size: Size.infinite,
      painter: _LinePainter(
        values,
        raw,
        Theme.of(context).colorScheme.primary,
        AppColors.of(context).chartFaint,
      ),
    ),
  );
}

final class _LinePainter extends CustomPainter {
  _LinePainter(this.values, this.raw, this.color, this.faint);
  final List<double> values;
  final List<double> raw;
  final Color color;
  final Color faint;

  @override
  void paint(Canvas canvas, Size size) {
    final all = [...values, ...raw];
    if (all.length < 2) return;
    final lo = all.reduce((a, b) => a < b ? a : b);
    final hi = all.reduce((a, b) => a > b ? a : b);
    final span = hi - lo == 0 ? 1 : hi - lo;
    Path path(List<double> v) {
      final p = Path();
      for (var i = 0; i < v.length; i++) {
        final x = v.length == 1 ? 0.0 : size.width * i / (v.length - 1);
        final y = 4 + (size.height - 8) * (1 - (v[i] - lo) / span);
        i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
      }
      return p;
    }

    if (raw.length > 1) {
      canvas.drawPath(
        path(raw),
        Paint()
          ..color = faint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    canvas.drawPath(
      path(values),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.values != values || old.raw != raw || old.color != color;
}
