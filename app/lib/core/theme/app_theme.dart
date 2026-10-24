import 'package:flutter/material.dart';

/// Tema provisório (escuro OLED). O design definitivo será refeito a partir dos
/// mockups; por isso nada aqui deve ser tratado como decisão visual final.
ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF4F7CFF),
    brightness: Brightness.dark,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFF050506),
    // Foco bem visível: obrigatório para navegar com o D-Pad na TV.
    focusColor: scheme.primary.withValues(alpha: 0.35),
  );
}
