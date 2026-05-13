import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTextStyles {
  AppTextStyles._();

  // ── Display (Outfit) ─────────────────────────────────────
  static TextStyle displayLarge(BuildContext context) => GoogleFonts.outfit(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: Theme.of(context).colorScheme.onBackground,
      );

  static TextStyle displayMedium(BuildContext context) => GoogleFonts.outfit(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: Theme.of(context).colorScheme.onBackground,
      );

  static TextStyle displaySmall(BuildContext context) => GoogleFonts.outfit(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onBackground,
      );

  // ── Headings ─────────────────────────────────────────────
  static TextStyle headingLarge(BuildContext context) => GoogleFonts.outfit(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onBackground,
      );

  static TextStyle headingMedium(BuildContext context) => GoogleFonts.outfit(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onBackground,
      );

  static TextStyle headingSmall(BuildContext context) => GoogleFonts.outfit(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onBackground,
      );

  // ── Body ──────────────────────────────────────────────────
  static TextStyle bodyLarge(BuildContext context) => GoogleFonts.outfit(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: Theme.of(context).colorScheme.onBackground,
      );

  static TextStyle bodyMedium(BuildContext context) => GoogleFonts.outfit(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: Theme.of(context).colorScheme.onBackground,
      );

  static TextStyle bodySmall(BuildContext context) => GoogleFonts.outfit(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );

  // ── Label ─────────────────────────────────────────────────
  static TextStyle labelLarge(BuildContext context) => GoogleFonts.outfit(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: Theme.of(context).colorScheme.onBackground,
      );

  static TextStyle labelMedium(BuildContext context) => GoogleFonts.outfit(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );

  static TextStyle labelSmall(BuildContext context) => GoogleFonts.outfit(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );

  // ── Mono (JetBrains Mono) ─────────────────────────────────
  static TextStyle monoLarge(BuildContext context) => GoogleFonts.jetBrainsMono(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: Theme.of(context).colorScheme.onBackground,
      );

  static TextStyle monoMedium(BuildContext context) =>
      GoogleFonts.jetBrainsMono(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: Theme.of(context).colorScheme.onBackground,
      );

  static TextStyle monoSmall(BuildContext context) => GoogleFonts.jetBrainsMono(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
}
