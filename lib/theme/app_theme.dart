import 'package:flutter/material.dart';

class AppTheme {
  static const Color background = Color(0xFF0A0410);
  static const Color surface = Color(0xFF1A0B24);
  static const Color primary = Color(0xFFB388FF);
  static const Color accent = Color(0xFFFFC107);
  static const Color danger = Color(0xFFE53935);

  static ThemeData dark() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: accent,
        surface: surface,
      ),
      fontFamily: 'Serif',
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          color: accent,
          fontSize: 42,
          fontWeight: FontWeight.w900,
          letterSpacing: 2,
        ),
        titleLarge: TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
        bodyLarge: TextStyle(color: Colors.white, fontSize: 16),
        bodyMedium: TextStyle(color: Colors.white70, fontSize: 14),
      ),
    );
  }

  static List<Shadow> get glowShadow => const <Shadow>[
        Shadow(color: Color(0xAA9C27B0), blurRadius: 10),
        Shadow(color: Color(0x66FFC107), blurRadius: 20),
      ];
}
