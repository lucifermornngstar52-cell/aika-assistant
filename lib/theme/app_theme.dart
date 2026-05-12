import 'package:flutter/material.dart';

class AikaTheme {
  // Colors
  static const Color background = Color(0xFF080B14);
  static const Color surface = Color(0xFF0D1120);
  static const Color card = Color(0xFF111827);
  static const Color neonBlue = Color(0xFF00D4FF);
  static const Color neonPurple = Color(0xFF9D4EDD);
  static const Color neonPink = Color(0xFFFF006E);
  static const Color glassWhite = Color(0x1AFFFFFF);
  static const Color textPrimary = Color(0xFFE8F4FF);
  static const Color textSecondary = Color(0xFF8899AA);
  static const Color userBubble = Color(0xFF1A2744);
  static const Color aikaBubble = Color(0xFF0D1F3C);

  static ThemeData get theme => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: background,
        colorScheme: const ColorScheme.dark(
          primary: neonBlue,
          secondary: neonPurple,
          surface: surface,
          background: background,
        ),
        fontFamily: 'Roboto',
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: textPrimary, fontSize: 16),
          bodyMedium: TextStyle(color: textPrimary, fontSize: 14),
          bodySmall: TextStyle(color: textSecondary, fontSize: 12),
        ),
      );

  // Neon glow decoration
  static BoxDecoration glassCard({
    Color borderColor = neonBlue,
    double borderWidth = 1.0,
    double blurRadius = 20,
    double opacity = 0.08,
  }) =>
      BoxDecoration(
        color: Color.fromRGBO(255, 255, 255, opacity),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: borderColor.withOpacity(0.3),
          width: borderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: borderColor.withOpacity(0.15),
            blurRadius: blurRadius,
            spreadRadius: 1,
          ),
        ],
      );

  static BoxDecoration neonButton({Color color = neonBlue}) => BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: [color.withOpacity(0.8), color.withOpacity(0.4)],
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.5),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      );
}
