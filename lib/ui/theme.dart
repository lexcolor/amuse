import 'package:flutter/material.dart';

abstract final class AmuseColors {
  static const background = Color(0xFF0D0B14);
  static const surface = Color(0xFF16131F);
  static const surfaceHigh = Color(0xFF211C2E);
  static const outline = Color(0x1FFFFFFF);
  static const textPrimary = Color(0xFFF4F1FA);
  static const textSecondary = Color(0xFFA59FB5);
  static const textMuted = Color(0xFF6E6880);
  static const accent = Color(0xFFB48CFF);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AmuseColors.accent,
    brightness: Brightness.dark,
    surface: AmuseColors.surface,
  ).copyWith(primary: AmuseColors.accent);

  const text = TextTheme(
    displaySmall: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: -1.2, height: 1.05),
    headlineSmall: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.4),
    titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.1),
    bodyMedium: TextStyle(fontSize: 14, color: AmuseColors.textSecondary),
    bodySmall: TextStyle(fontSize: 12, color: AmuseColors.textMuted),
    labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AmuseColors.background,
    textTheme: text.apply(
      bodyColor: AmuseColors.textPrimary,
      displayColor: AmuseColors.textPrimary,
    ),
    splashFactory: InkSparkle.splashFactory,
    sliderTheme: const SliderThemeData(
      trackHeight: 3,
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6, elevation: 0),
      overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
      activeTrackColor: AmuseColors.textPrimary,
      inactiveTrackColor: Color(0x33FFFFFF),
      thumbColor: AmuseColors.textPrimary,
    ),
    tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 600)),
  );
}

/// Deterministic two-colour palette for generated artwork, so every album
/// gets its own consistent look until real cover art is loaded.
(Color, Color) artPalette(String seed) {
  var hash = 0;
  for (final unit in seed.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  final hue = (hash % 360).toDouble();
  final shift = 30.0 + (hash >> 9) % 60;
  return (
    HSLColor.fromAHSL(1, hue, 0.62, 0.56).toColor(),
    HSLColor.fromAHSL(1, (hue + shift) % 360, 0.70, 0.28).toColor(),
  );
}

String formatDuration(Duration? d) {
  if (d == null) return '';
  final minutes = d.inMinutes;
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return d.inHours > 0
      ? '${d.inHours}:${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:$seconds'
      : '$minutes:$seconds';
}
