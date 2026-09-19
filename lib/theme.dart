import 'package:flutter/material.dart';

/// Desk instrument palette — charcoal chassis, amber signal.
abstract final class AppColors {
  static const bg = Color(0xFF0A0C10);
  static const surface = Color(0xFF141A1F);
  static const surface2 = Color(0xFF1C242B);
  static const ink = Color(0xFFE6EDF3);
  static const muted = Color(0xFF8B98A5);
  static const accent = Color(0xFFFF9F43);
  static const accentSoft = Color(0x33FF9F43);
  static const ok = Color(0xFF5ED4A6);
  static const danger = Color(0xFFF07178);
  static const track = Color(0xFF2A333B);
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      secondary: AppColors.accent,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      error: AppColors.danger,
    ),
    fontFamily: 'Roboto',
    sliderTheme: SliderThemeData(
      trackHeight: 4,
      activeTrackColor: AppColors.accent,
      inactiveTrackColor: AppColors.track,
      thumbColor: AppColors.ink,
      overlayColor: AppColors.accentSoft,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
    ),
    textTheme: baseTextTheme(),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.ink,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
      iconTheme: IconThemeData(color: AppColors.muted),
    ),
  );
  return base;
}

TextTheme baseTextTheme() {
  return const TextTheme(
    titleLarge: TextStyle(
      color: AppColors.ink,
      fontSize: 22,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
    ),
    bodyMedium: TextStyle(
      color: AppColors.ink,
      fontSize: 15,
      fontWeight: FontWeight.w400,
      height: 1.35,
    ),
    bodySmall: TextStyle(
      color: AppColors.muted,
      fontSize: 13,
      fontWeight: FontWeight.w400,
      height: 1.3,
    ),
    labelLarge: TextStyle(
      color: AppColors.ink,
      fontSize: 14,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
    ),
    labelSmall: TextStyle(
      color: AppColors.muted,
      fontSize: 11,
      fontWeight: FontWeight.w500,
      letterSpacing: 1.1,
    ),
  );
}
