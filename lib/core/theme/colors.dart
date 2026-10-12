import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── Classic Dark Theme (Midnight Deep Blue) ──────────────
  static const classicDarkBackground = Color(0xFF070B16);
  static const classicDarkSurface = Color(0xFF0D1426);
  static const classicDarkCard = Color(0xFF131C35);
  static const classicDarkBorder = Color(0xFF1D2B4E);
  static const classicDarkTextPrimary = Color(0xFFD8E2F5);
  static const classicDarkTextMuted = Color(0xFF5A6A92);
  static const classicDarkFaint = Color(0xFF1A2444);

  // ── Charcoal Dark Theme (Neutral Graphite / Slate) ────────
  static const charcoalDarkBackground = Color(0xFF121214);
  static const charcoalDarkSurface = Color(0xFF18181B);
  static const charcoalDarkCard = Color(0xFF202024);
  static const charcoalDarkBorder = Color(0xFF2E2E33);
  static const charcoalDarkTextPrimary = Color(0xFFF4F4F6);
  static const charcoalDarkTextMuted = Color(0xFF9CA3AF);
  static const charcoalDarkFaint = Color(0xFF242429);

  // ── Pure Black Dark Theme (OLED True Black) ───────────────
  static const oledDarkBackground = Color(0xFF000000);
  static const oledDarkSurface = Color(0xFF0A0A0C);
  static const oledDarkCard = Color(0xFF141416);
  static const oledDarkBorder = Color(0xFF242428);
  static const oledDarkTextPrimary = Color(0xFFFFFFFF);
  static const oledDarkTextMuted = Color(0xFF8E8E93);
  static const oledDarkFaint = Color(0xFF1A1A1E);

  // Default aliases (Classic for backward compatibility)
  static const darkBackground = classicDarkBackground;
  static const darkSurface = classicDarkSurface;
  static const darkCard = classicDarkCard;
  static const darkBorder = classicDarkBorder;
  static const darkTextPrimary = classicDarkTextPrimary;
  static const darkTextMuted = classicDarkTextMuted;
  static const darkFaint = classicDarkFaint;

  // ── Light Theme ──────────────────────────────────────────
  static const lightBackground = Color(0xFFF5F7FF);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightCard = Color(0xFFF0F3FF);
  static const lightBorder = Color(0xFFD6DEFF);
  static const lightTextPrimary = Color(0xFF0D1426);
  static const lightTextMuted = Color(0xFF7B8CB8);
  static const lightFaint = Color(0xFFE8ECFF);

  // ── Accent ──────────────────────────────────────────────
  static const accent = Color(0xFF5B9CF6);
  static const accentGlow = Color(0x335B9CF6);

  // ── Semantic ─────────────────────────────────────────────
  static const success = Color(0xFF34D399);
  static const warning = Color(0xFFFBBF24);
  static const error = Color(0xFFF87171);
  static const critical = Color(0xFFF87171);
  static const high = Color(0xFFFBBF24);

  // ── Goal color presets (16) ───────────────────────────────
  static const List<Color> goalColors = [
    Color(0xFF5B9CF6), // Electric Blue
    Color(0xFF34D399), // Emerald
    Color(0xFFFBBF24), // Amber
    Color(0xFFF472B6), // Rose
    Color(0xFFA78BFA), // Violet
    Color(0xFFFB923C), // Orange
    Color(0xFF2DD4BF), // Teal
    Color(0xFF38BDF8), // Sky
    Color(0xFFA3E635), // Lime
    Color(0xFFF87171), // Red
    Color(0xFF818CF8), // Indigo
    Color(0xFFFDE047), // Yellow
    Color(0xFFE879F9), // Fuchsia
    Color(0xFF67E8F9), // Cyan
    Color(0xFF4ADE80), // Green
    Color(0xFFFB7185), // Pink
  ];

  static const List<int> goalColorHexes = [
    0xFF5B9CF6,
    0xFF34D399,
    0xFFFBBF24,
    0xFFF472B6,
    0xFFA78BFA,
    0xFFFB923C,
    0xFF2DD4BF,
    0xFF38BDF8,
    0xFFA3E635,
    0xFFF87171,
    0xFF818CF8,
    0xFFFDE047,
    0xFFE879F9,
    0xFF67E8F9,
    0xFF4ADE80,
    0xFFFB7185,
  ];
}
