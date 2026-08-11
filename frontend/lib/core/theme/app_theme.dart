import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for Annora. Colors and type scale are deliberately
/// centralized here so no screen ever hardcodes a hex value --
/// see docs/architecture.md if we outgrow this and need a proper
/// design-system package.
class AppColors {
  AppColors._();

  static const background = Color(0xFF120E0C);
  static const glow = Color(0xFF8A4A24);
  static const orange = Color(0xFFFF7A3D);
  static const orangeDark = Color(0xFFE8632A);
  static const card = Color(0xFF221B17);
  static const cardBorder = Color(0x14FFFFFF); // white @ 8% opacity
  static const textPrimary = Color(0xFFF7F2EC);
  static const textMuted = Color(0xFFA79C90);
  static const textFaint = Color(0xFF7D7268);
  static const avatarGold = Color(0xFFD9A441);
  static const avatarGreen = Color(0xFF2F4A3C);
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: base.colorScheme.copyWith(
        primary: AppColors.orange,
        surface: AppColors.card,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        // Reserved for the wordmark and other display moments --
        // applied explicitly per-widget, not globally, so body text
        // stays on Inter.
      ),
    );
  }

  static TextStyle get displayFont => GoogleFonts.baloo2(
        fontWeight: FontWeight.w800,
      );
}