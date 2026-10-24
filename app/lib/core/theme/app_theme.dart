import 'package:flutter/material.dart';

/// Paleta do BarclayFlix 3.0 (mockups aprovados): fundo quase preto e destaque âmbar.
abstract final class AppColors {
  static const background = Color(0xFF07080A);
  static const surface = Color(0xFF111318);
  static const border = Color(0xFF262A33);
  static const accent = Color(0xFFFFB224);
  static const onAccent = Color(0xFF1A1200);
  static const textMuted = Color(0xFFA3AAB8);
  static const live = Color(0xFFFF6B6B);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: AppColors.accent,
    onPrimary: AppColors.onAccent,
    surface: AppColors.background,
    surfaceContainerHighest: AppColors.surface,
    outline: AppColors.border,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
    ),
    tabBarTheme: const TabBarThemeData(
      indicatorColor: AppColors.accent,
      labelColor: Colors.white,
      unselectedLabelColor: AppColors.textMuted,
      dividerColor: AppColors.border,
    ),
    // Foco bem visível: obrigatório para navegar com o D-Pad na TV.
    focusColor: Colors.white.withValues(alpha: 0.16),
  );
}
