import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design system Ardoiz : vert emeraude (confiance) + ocre (chaleur),
/// typographie large et lisible pour un public peu digitalise.
class AppColors {
  static const emerald = Color(0xFF0B6E4F);
  static const emeraldDark = Color(0xFF07502F);
  static const ocre = Color(0xFFE8873A);
  static const background = Color(0xFFFBF9F6);
  static const surface = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF1C1C1C);
  static const textSecondary = Color(0xFF6B6B6B);

  // Codes couleur du statut d'une dette
  static const statusPaid = Color(0xFF2E9E5B);
  static const statusPartial = Color(0xFFE8873A);
  static const statusOverdue = Color(0xFFD64545);
}

class AppTheme {
  static ThemeData light() {
    final textTheme = GoogleFonts.interTextTheme().copyWith(
      headlineMedium: GoogleFonts.poppins(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      titleLarge: GoogleFonts.poppins(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      bodyLarge: GoogleFonts.inter(fontSize: 16, color: AppColors.textPrimary),
      bodyMedium: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary),
    );

    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.emerald,
        primary: AppColors.emerald,
        secondary: AppColors.ocre,
        surface: AppColors.surface,
      ),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        titleTextStyle: textTheme.titleLarge,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.emerald,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
