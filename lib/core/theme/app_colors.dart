import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color background = Color(0xFF080808);
  static const Color surface = Color(0xFF111111);
  static const Color card = Color(0xFF1A1A1A);
  static const Color border = Color(0xFF2A2A2A);
  static const Color borderSubtle = Color(0xFF1E1E1E);

  static const Color neonWhite = Color(0xFFF8F8F8);
  static const Color neonWhiteDim = Color(0xFFD0D0D0);
  static const Color neonWhiteFaint = Color(0xFF8A8A8A);

  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF9A9A9A);
  static const Color textMuted = Color(0xFF555555);

  static const Color userBubble = Color(0xFF1E1E1E);
  static const Color assistantBubble = Color(0xFF141414);

  static Color get neonGlow => neonWhite.withValues(alpha: 0.08);
  static Color get neonGlowStrong => neonWhite.withValues(alpha: 0.15);
  static Color get neonGlowSubtle => neonWhite.withValues(alpha: 0.04);
}
