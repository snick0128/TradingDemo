import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Zerodha Palette
  static const Color primary = Color(0xFF387ED1); // kite Blue
  static const Color success = Color(0xFF1DB954); // Gains
  static const Color danger = Color(0xFFE53935); // Losses
  static const Color warning = Color(0xFFFF9800);
  static const Color accent = Color(0xFF4184F3);

  // Backgrounds & Text
  static const Color background = Color(0xFFFBFBFB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceAlt = Color(0xFFF1F1F1);
  static const Color surfaceElevated = Color(0xFFF8F9FA);
  static const Color textPrimary = Color(0xFF444444); // Neutral neutral
  static const Color textSecondary = Color(0xFF9B9B9B);
  static const Color border = Color(0xFFEEEEEE);

  static const double cardRadius = 12.0;

  static List<BoxShadow> softShadow = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.06),
      blurRadius: 12,
      offset: const Offset(0, 2),
    ),
  ];
}

class AppTheme {
  static TextStyle tabular(TextStyle style) {
    return style.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  static ThemeData get lightTheme {
    final baseTextTheme = GoogleFonts.interTextTheme();
    
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        surface: AppColors.surface,
        secondary: AppColors.accent,
        onSurface: AppColors.textPrimary,
        error: AppColors.danger,
      ),
      textTheme: baseTextTheme.copyWith(
        displayLarge: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        headlineMedium: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary), // H1
        headlineSmall: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.textPrimary), // H2
        titleLarge: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),    // H3 Bold
        bodyLarge: GoogleFonts.inter(fontSize: 14, color: AppColors.textPrimary),                                  // Body
        bodyMedium: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary),
        bodySmall: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),                               // Caption
        labelSmall: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary),                               // Micro
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        shape: const Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceElevated,
        elevation: 0,
        margin: EdgeInsets.zero,
        shadowColor: Colors.black.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.cardRadius),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 48),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.cardRadius),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.cardRadius),
          ),
          side: const BorderSide(color: AppColors.border),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.primary,
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        dividerColor: AppColors.border,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        type: BottomNavigationBarType.fixed,
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 11),
        elevation: 8,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: AppColors.primary, width: 1),
        ),
      ),
    );
  }

  static ThemeData get darkTheme {
    final baseTextTheme = GoogleFonts.interTextTheme(ThemeData.dark().textTheme);
    const darkSurface = Color(0xFF1F1F1F);
    const darkBg = Color(0xFF191919);
    const darkBorder = Color(0xFF333333);
    const darkText = Color(0xFFE0E0E0);
    const darkSecondary = Color(0xFF9E9E9E);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: darkBg,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        surface: darkSurface,
        secondary: AppColors.accent,
        onSurface: darkText,
        error: AppColors.danger,
      ),
      textTheme: baseTextTheme.copyWith(
        displayLarge: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.w700, color: darkText),
        headlineMedium: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w700, color: darkText),
        headlineSmall: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w600, color: darkText),
        titleLarge: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: darkText),
        bodyLarge: GoogleFonts.inter(fontSize: 14, color: darkText),
        bodyMedium: GoogleFonts.inter(fontSize: 14, color: darkSecondary),
        bodySmall: GoogleFonts.inter(fontSize: 12, color: darkSecondary),
        labelSmall: GoogleFonts.inter(fontSize: 11, color: darkSecondary),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: darkSurface,
        elevation: 0,
        titleTextStyle: GoogleFonts.inter(color: darkText, fontSize: 18, fontWeight: FontWeight.w600),
        iconTheme: const IconThemeData(color: darkText),
        shape: const Border(bottom: BorderSide(color: darkBorder, width: 1)),
      ),
      cardTheme: CardThemeData(
        color: darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.cardRadius),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 48),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppColors.cardRadius)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.cardRadius),
          ),
          side: const BorderSide(color: darkBorder),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkBg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: darkBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: darkBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4), borderSide: const BorderSide(color: AppColors.primary)),
      ),
      dividerTheme: const DividerThemeData(color: darkBorder),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: darkSecondary,
        indicatorColor: AppColors.primary,
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        dividerColor: darkBorder,
      ),
    );
  }
}


