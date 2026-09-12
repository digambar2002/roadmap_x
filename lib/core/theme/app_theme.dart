import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../layout/breakpoints.dart';
import 'colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get dark => _buildTheme(Brightness.dark);
  static ThemeData get light => _buildTheme(Brightness.light);

  /// Desktop trims a little off every size.
  ///
  /// Type and control metrics in this app were picked for a fingertip at arm's
  /// length. On a monitor, at half the viewing distance and with a cursor that
  /// can hit a 24px target, the same numbers read as oversized — which is most
  /// of what makes a ported phone app feel like one. This is a platform test,
  /// not a width test: it follows the input device, so a narrow window on a Mac
  /// still gets desktop metrics.
  static bool get _dense => isPointerPlatform;

  static const double _denseFontFactor = 0.94;

  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    final bg = isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final card = isDark ? AppColors.darkCard : AppColors.lightCard;
    final border = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textMuted =
        isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: AppColors.accent,
      onPrimary: Colors.white,
      secondary: AppColors.accent,
      onSecondary: Colors.white,
      error: AppColors.error,
      onError: Colors.white,
      background: bg,
      onBackground: textPrimary,
      surface: surface,
      onSurface: textPrimary,
      surfaceVariant: card,
      onSurfaceVariant: textMuted,
      outline: border,
      outlineVariant: border.withOpacity(0.5),
    );

    final baseTextTheme = GoogleFonts.outfitTextTheme(
      TextTheme(
        displayLarge: TextStyle(color: textPrimary),
        displayMedium: TextStyle(color: textPrimary),
        displaySmall: TextStyle(color: textPrimary),
        headlineLarge: TextStyle(color: textPrimary),
        headlineMedium: TextStyle(color: textPrimary),
        headlineSmall: TextStyle(color: textPrimary),
        titleLarge: TextStyle(color: textPrimary),
        titleMedium: TextStyle(color: textPrimary),
        titleSmall: TextStyle(color: textPrimary),
        bodyLarge: TextStyle(color: textPrimary),
        bodyMedium: TextStyle(color: textPrimary),
        bodySmall: TextStyle(color: textMuted),
        labelLarge: TextStyle(color: textPrimary),
        labelMedium: TextStyle(color: textMuted),
        labelSmall: TextStyle(color: textMuted),
      ),
    );

    final textTheme = baseTextTheme;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bg,
      textTheme: textTheme,
      // Tightens the built-in Material components (list tiles, buttons,
      // chips) the same way, so spacing stays consistent with the type.
      visualDensity: VisualDensity.adaptivePlatformDensity,

      // Card theme
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),

      // AppBar theme
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: _dense ? 16 : 18,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        toolbarHeight: _dense ? 52 : null,
      ),

      // Input decoration
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: _dense ? 14 : 16,
          vertical: _dense ? 11 : 14,
        ),
        hintStyle: TextStyle(color: textMuted),
        labelStyle: TextStyle(color: textMuted),
      ),

      // Elevated button
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: EdgeInsets.symmetric(
            horizontal: _dense ? 20 : 24,
            vertical: _dense ? 11 : 14,
          ),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.outfit(
            fontSize: _dense ? 14 : 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Text button
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          textStyle: GoogleFonts.outfit(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      // Chip theme
      chipTheme: ChipThemeData(
        backgroundColor: card,
        selectedColor: AppColors.accent.withOpacity(0.2),
        side: BorderSide(color: border),
        labelStyle: GoogleFonts.outfit(
          fontSize: _dense ? 12 : 13,
          color: textPrimary,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: EdgeInsets.symmetric(
          horizontal: _dense ? 8 : 10,
          vertical: _dense ? 4 : 6,
        ),
      ),

      // BottomSheet theme
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        dragHandleColor: border,
        showDragHandle: false,
      ),

      // Divider
      dividerTheme: DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),

      // FloatingActionButton
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      // Icon theme
      iconTheme: IconThemeData(color: textMuted),
      primaryIconTheme: const IconThemeData(color: AppColors.accent),
    );
  }

  /// Applies the desktop type scale to a theme taken from *inside* MaterialApp.
  ///
  /// It has to be done there, not in [_buildTheme]. Typography keeps colour and
  /// geometry in separate text themes and only merges the sizes in when the
  /// theme is localized in the widget tree, so `ThemeData.textTheme` still has
  /// null fontSizes — and `TextStyle.apply(fontSizeFactor:)` asserts on those.
  ///
  /// Returns [theme] untouched on touch platforms.
  static ThemeData densifyForPointer(ThemeData theme) {
    if (!_dense) return theme;
    return theme.copyWith(
      textTheme: theme.textTheme.apply(fontSizeFactor: _denseFontFactor),
    );
  }
}
