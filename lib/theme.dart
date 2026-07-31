import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// TradeKosh V3.0 design tokens.
///
/// Financial colors (primary/success/danger/warning) are brand-fixed and
/// stay the same value on light backgrounds; dark-mode variants exist only
/// where the fixed value would fail contrast against a near-black surface.
///
/// One signature gradient is sanctioned app-wide: [heroGradient], reserved
/// for the single "hero" card per screen (e.g. portfolio/equity value).
/// Every other card, dialog, sheet, and button stays flat — the gradient's
/// value comes from being used exactly once per screen, not everywhere.
class AppColors {
  // ── Brand / semantic ───────────────────────────────────────────────────
  static const Color primary = Color(0xFF1B4FD8); // Financial blue
  static const Color success = Color(0xFF059669); // Profit green
  static const Color danger = Color(0xFFDC2626); // Loss red
  static const Color warning = Color(0xFFD97706); // Amber
  static const Color accent = primary;

  // Signature hero gradient — the one sanctioned gradient in the app.
  static const Color heroGradientStart = Color(0xFF3D6FF2);
  static const Color heroGradientEnd = Color(0xFF13277A);
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [heroGradientStart, heroGradientEnd],
  );

  // Neutral + accent tag chips (e.g. "NSE" / "EQ" badges on watchlist rows)
  static const Color chipNeutralBg = Color(0xFFEAEEF5);
  static const Color chipNeutralText = Color(0xFF6B7280);

  // Dark-mode contrast variants (same hue, lifted lightness for AA on near-black)
  static const Color primaryOnDark = Color(0xFF5B8DFF);
  static const Color successOnDark = Color(0xFF10B981);
  static const Color dangerOnDark = Color(0xFFF87171);
  static const Color warningOnDark = Color(0xFFFBBF24);

  // ── Backgrounds & surfaces (light) ──────────────────────────────────────
  static const Color background = Color(0xFFF1F4F9); // Cool light gray canvas — cards pop as white on top
  static const Color surface = Color(0xFFFFFFFF); // Card fill — pure white
  static const Color surfaceAlt = Color(
    0xFFEAEEF5,
  ); // Slightly deeper cool gray — secondary panels, zebra rows
  static const Color surfaceElevated = Color(
    0xFFFFFFFF,
  ); // Sheets/dialogs/menus
  static const Color textPrimary = Color(0xFF18181B); // Neutral near-black
  static const Color textSecondary = Color(0xFF6B7280); // Neutral gray
  static const Color textTertiary = Color(0xFF9CA3AF); // Placeholder/hint
  static const Color border = Color(0xFFDFE3EA);
  static const Color divider = Color(0xFFE9ECF2);

  // ── Backgrounds & surfaces (dark) ───────────────────────────────────────
  static const Color backgroundDark = Color(0xFF17181A);
  static const Color surfaceDark = Color(0xFF212226);
  static const Color surfaceAltDark = Color(0xFF2A2B2F);
  static const Color textPrimaryDark = Color(0xFFECECEE);
  static const Color textSecondaryDark = Color(0xFF9BA1A6);
  static const Color borderDark = Color(0xFF34363A);
  static const Color dividerDark = Color(0xFF2C2D31);

  // Nav
  static const Color navActive = primary;
  static const Color navInactive = Color(0xFF9CA3AF);
  static const Color navActiveDark = primaryOnDark;
  static const Color navInactiveDark = Color(0xFF71767C);

  // ── Radii ────────────────────────────────────────────────────────────
  static const double radiusSm = 8.0;
  static const double cardRadius = 12.0;
  static const double heroRadius = 16.0;
  static const double radiusPill = 999.0;

  // Cards/dialogs stay flat (border-only). This single subtle shadow token
  // is the only sanctioned elevation cue, reserved for floating chrome
  // (e.g. the floating bottom nav) that needs to visually separate from
  // scrollable content behind it — not for cards or buttons.
  static const List<BoxShadow> floatingShadow = [
    BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 4)),
  ];
  static List<BoxShadow> softShadow = const [];

  static BoxDecoration cardDecoration = BoxDecoration(
    color: surface,
    borderRadius: BorderRadius.circular(cardRadius),
    border: Border.all(color: border, width: 1),
  );
}

/// 8-point spacing scale. Use these instead of literal EdgeInsets values.
class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 40;
  static const double xxxl = 48;
}

class AppTheme {
  static TextStyle tabular(TextStyle style) {
    return style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
  }

  /// The single token for rendering financial numbers — prices, PnL,
  /// margin, LTP, average price, portfolio/current value. Always DM Mono
  /// with tabular figures so digits align in columns.
  static TextStyle mono({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w500,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.dmMono(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
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
        displayLarge: GoogleFonts.inter(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        headlineMedium: GoogleFonts.inter(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        headlineSmall: GoogleFonts.inter(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        titleLarge: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        titleMedium: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 14,
          color: AppColors.textPrimary,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 13,
          color: AppColors.textSecondary,
        ),
        bodySmall: GoogleFonts.inter(
          fontSize: 12,
          color: AppColors.textSecondary,
        ),
        labelSmall: GoogleFonts.inter(
          fontSize: 11,
          color: AppColors.textSecondary,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        shape: const Border(
          bottom: BorderSide(color: AppColors.divider, width: 1),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.cardRadius),
          side: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 48),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.cardRadius),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
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
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        dividerColor: AppColors.border,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        type: BottomNavigationBarType.fixed,
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.navActive,
        unselectedItemColor: AppColors.navInactive,
        selectedLabelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(fontSize: 11),
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusSm),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusSm),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusSm),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }

  static ThemeData get darkTheme {
    final baseTextTheme = GoogleFonts.interTextTheme(
      ThemeData.dark().textTheme,
    );
    const darkSurface = AppColors.surfaceDark;
    const darkBg = AppColors.backgroundDark;
    const darkBorder = AppColors.borderDark;
    const darkText = AppColors.textPrimaryDark;
    const darkSecondary = AppColors.textSecondaryDark;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: AppColors.primaryOnDark,
      scaffoldBackgroundColor: darkBg,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primaryOnDark,
        surface: darkSurface,
        secondary: AppColors.primaryOnDark,
        onSurface: darkText,
        error: AppColors.dangerOnDark,
      ),
      textTheme: baseTextTheme.copyWith(
        displayLarge: GoogleFonts.inter(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: darkText,
        ),
        headlineMedium: GoogleFonts.inter(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: darkText,
        ),
        headlineSmall: GoogleFonts.inter(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: darkText,
        ),
        titleLarge: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: darkText,
        ),
        titleMedium: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: darkText,
        ),
        bodyLarge: GoogleFonts.inter(fontSize: 14, color: darkText),
        bodyMedium: GoogleFonts.inter(fontSize: 13, color: darkSecondary),
        bodySmall: GoogleFonts.inter(fontSize: 12, color: darkSecondary),
        labelSmall: GoogleFonts.inter(fontSize: 11, color: darkSecondary),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: darkSurface,
        elevation: 0,
        titleTextStyle: GoogleFonts.inter(
          color: darkText,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: const IconThemeData(color: darkText),
        shape: const Border(bottom: BorderSide(color: darkBorder, width: 1)),
      ),
      cardTheme: CardThemeData(
        color: darkSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.cardRadius),
          side: const BorderSide(color: darkBorder, width: 1),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryOnDark,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 48),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.cardRadius),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
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
      dividerTheme: const DividerThemeData(color: darkBorder),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.primaryOnDark,
        unselectedLabelColor: darkSecondary,
        indicatorColor: AppColors.primaryOnDark,
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        dividerColor: darkBorder,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        type: BottomNavigationBarType.fixed,
        backgroundColor: darkSurface,
        selectedItemColor: AppColors.navActiveDark,
        unselectedItemColor: AppColors.navInactiveDark,
        selectedLabelStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkBg,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusSm),
          borderSide: const BorderSide(color: darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusSm),
          borderSide: const BorderSide(color: darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusSm),
          borderSide: const BorderSide(
            color: AppColors.primaryOnDark,
            width: 1.5,
          ),
        ),
      ),
    );
  }
}
