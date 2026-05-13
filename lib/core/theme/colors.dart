import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── Dark Theme ──────────────────────────────────────────
  static const darkBackground = Color(0xFF070B16);
  static const darkSurface = Color(0xFF0D1426);
  static const darkCard = Color(0xFF131C35);
  static const darkBorder = Color(0xFF1D2B4E);
  static const darkTextPrimary = Color(0xFFD8E2F5);
  static const darkTextMuted = Color(0xFF5A6A92);
  static const darkFaint = Color(0xFF1A2444);

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
