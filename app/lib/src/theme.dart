import 'package:material_ui/material_ui.dart';

/// Colours from design A: a calm green accent with a warm warning tone.
final class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.muted,
    required this.line,
    required this.accentSoft,
    required this.warn,
    required this.warnSoft,
    required this.chartFaint,
  });

  final Color muted;
  final Color line;
  final Color accentSoft;
  final Color warn;
  final Color warnSoft;
  final Color chartFaint;

  static const light = AppColors(
    muted: Color(0xFF5F6B64),
    line: Color(0xFFDDE4DF),
    accentSoft: Color(0xFFDCEFE4),
    warn: Color(0xFFB4621B),
    warnSoft: Color(0xFFFBEADB),
    chartFaint: Color(0xFF9CB8A9),
  );
  static const dark = AppColors(
    muted: Color(0xFF97A59D),
    line: Color(0xFF2A352F),
    accentSoft: Color(0xFF1F3A2C),
    warn: Color(0xFFE6A160),
    warnSoft: Color(0xFF3A2A1A),
    chartFaint: Color(0xFF42594C),
  );

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>()!;

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(AppColors? other, double t) => t < 0.5 ? this : other ?? this;
}

ThemeData appTheme(Brightness brightness) {
  final light = brightness == Brightness.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: light ? const Color(0xFF2F7D5B) : const Color(0xFF6CC79B),
    onPrimary: light ? Colors.white : const Color(0xFF0D1210),
    secondary: light ? const Color(0xFF2F7D5B) : const Color(0xFF6CC79B),
    onSecondary: light ? Colors.white : const Color(0xFF0D1210),
    secondaryContainer: light
        ? const Color(0xFFDCEFE4)
        : const Color(0xFF1F3A2C),
    onSecondaryContainer: light
        ? const Color(0xFF17201B)
        : const Color(0xFFE7EEE9),
    error: light ? const Color(0xFFB23B3B) : const Color(0xFFE07D7D),
    onError: Colors.white,
    surface: light ? const Color(0xFFF4F7F4) : const Color(0xFF0D1210),
    onSurface: light ? const Color(0xFF17201B) : const Color(0xFFE7EEE9),
    surfaceContainer: light ? Colors.white : const Color(0xFF161D19),
    surfaceContainerLow: light ? Colors.white : const Color(0xFF161D19),
    outlineVariant: light ? const Color(0xFFDDE4DF) : const Color(0xFF2A352F),
  );
  final colors = light ? AppColors.light : AppColors.dark;
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    extensions: [colors],
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: colors.accentSoft,
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainer,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.line),
      ),
    ),
  );
}
