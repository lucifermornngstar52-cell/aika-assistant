import 'package:flutter/material.dart';

class AikaTheme {
  static const Color background = Color(0xFF121212);
  static const Color surface = Color(0xFF1A1A1A);
  static const Color card = Color(0xFF1E1E1E);
  static const Color accent = Color(0xFFB0B0B0);
  static const Color glassWhite = Color(0x1AFFFFFF);
  static const Color textPrimary = Color(0xFFE8E8E8);
  static const Color textSecondary = Color(0xFF888888);
  static const Color userBubble = Color(0xFF2A2A2A);
  static const Color aikaBubble = Color(0xFF1E1E1E);

  // Backward compat aliases
  static const Color neonBlue = accent;
  static const Color neonPurple = accent;
  static const Color neonPink = accent;

  static ThemeData get theme => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: ColorScheme.dark(
          primary: accent,
          secondary: accent,
          surface: surface,
        ),
        fontFamily: 'Roboto',
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: textPrimary, fontSize: 16),
          bodyMedium: TextStyle(color: textPrimary, fontSize: 14),
          bodySmall: TextStyle(color: textSecondary, fontSize: 12),
        ),
      );

  static BoxDecoration glassCard({
    Color borderColor = glassWhite,
    double borderWidth = 1.0,
    double blurRadius = 20,
    double opacity = 0.08,
  }) =>
      BoxDecoration(
        color: Color.fromRGBO(255, 255, 255, opacity),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: borderColor.withOpacity(0.15),
          width: borderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: blurRadius,
            spreadRadius: 0,
          ),
        ],
      );

  static BoxDecoration neonButton({Color color = accent}) => BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: [color.withOpacity(0.6), color.withOpacity(0.3)],
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.2),
            blurRadius: 10,
            spreadRadius: 0,
          ),
        ],
      );
}
