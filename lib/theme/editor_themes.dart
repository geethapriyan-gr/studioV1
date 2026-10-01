import 'package:flutter/material.dart';

/// One editor colour palette. Every theme is dark (the editor's video
/// preview and many widgets assume light text on dark surfaces); they differ
/// in surface tint and accent colour.
class EditorThemeData {
  final String id;
  final String name;
  final String description;
  final Color background;
  final Color surface;
  final Color surfaceLight;
  final Color surfaceLighter;
  final Color primary;
  final Color primaryLight;
  final Color primaryDark;
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color border;
  final Color borderLight;
  final Color audioTrack;
  final Color textTrack;

  const EditorThemeData({
    required this.id,
    required this.name,
    required this.description,
    required this.background,
    required this.surface,
    required this.surfaceLight,
    required this.surfaceLighter,
    required this.primary,
    required this.primaryLight,
    required this.primaryDark,
    this.accent = const Color(0xFF06B6D4),
    this.textPrimary = const Color(0xFFFAFAFA),
    this.textSecondary = const Color(0xFFA1A1AA),
    this.textTertiary = const Color(0xFF71717A),
    required this.border,
    required this.borderLight,
    this.audioTrack = const Color(0xFFF97316),
    this.textTrack = const Color(0xFF22C55E),
  });

  static const premium = EditorThemeData(
    id: 'premium',
    name: 'Premium Dark',
    description: 'Deep black with violet accents (default)',
    background: Color(0xFF0A0A0C),
    surface: Color(0xFF111114),
    surfaceLight: Color(0xFF18181C),
    surfaceLighter: Color(0xFF1F1F24),
    primary: Color(0xFF8B5CF6),
    primaryLight: Color(0xFFA78BFA),
    primaryDark: Color(0xFF7C3AED),
    border: Color(0xFF27272A),
    borderLight: Color(0xFF3F3F46),
  );

  static const midnight = EditorThemeData(
    id: 'midnight',
    name: 'Midnight Blue',
    description: 'Navy surfaces with electric blue',
    background: Color(0xFF070B14),
    surface: Color(0xFF0D1320),
    surfaceLight: Color(0xFF131B2C),
    surfaceLighter: Color(0xFF1A2438),
    primary: Color(0xFF3B82F6),
    primaryLight: Color(0xFF60A5FA),
    primaryDark: Color(0xFF2563EB),
    textSecondary: Color(0xFF94A3B8),
    textTertiary: Color(0xFF64748B),
    border: Color(0xFF1E293B),
    borderLight: Color(0xFF334155),
  );

  static const amoled = EditorThemeData(
    id: 'amoled',
    name: 'AMOLED Black',
    description: 'True black — easiest on OLED batteries',
    background: Color(0xFF000000),
    surface: Color(0xFF050505),
    surfaceLight: Color(0xFF0E0E10),
    surfaceLighter: Color(0xFF161618),
    primary: Color(0xFFA78BFA),
    primaryLight: Color(0xFFC4B5FD),
    primaryDark: Color(0xFF8B5CF6),
    border: Color(0xFF1F1F22),
    borderLight: Color(0xFF2E2E33),
  );

  static const ocean = EditorThemeData(
    id: 'ocean',
    name: 'Ocean',
    description: 'Deep teal with aqua highlights',
    background: Color(0xFF061214),
    surface: Color(0xFF0A1A1D),
    surfaceLight: Color(0xFF0F2327),
    surfaceLighter: Color(0xFF152C31),
    primary: Color(0xFF14B8A6),
    primaryLight: Color(0xFF2DD4BF),
    primaryDark: Color(0xFF0D9488),
    accent: Color(0xFF38BDF8),
    textSecondary: Color(0xFF9CB4B6),
    textTertiary: Color(0xFF6B8587),
    border: Color(0xFF1C3438),
    borderLight: Color(0xFF27474C),
  );

  static const rose = EditorThemeData(
    id: 'rose',
    name: 'Rose',
    description: 'Plum surfaces with pink accents',
    background: Color(0xFF120A0E),
    surface: Color(0xFF190F14),
    surfaceLight: Color(0xFF22141B),
    surfaceLighter: Color(0xFF2B1922),
    primary: Color(0xFFEC4899),
    primaryLight: Color(0xFFF472B6),
    primaryDark: Color(0xFFDB2777),
    textSecondary: Color(0xFFB9A2AE),
    textTertiary: Color(0xFF85707B),
    border: Color(0xFF3A2430),
    borderLight: Color(0xFF4D3040),
  );

  static const ember = EditorThemeData(
    id: 'ember',
    name: 'Ember',
    description: 'Warm charcoal with orange glow',
    background: Color(0xFF120C08),
    surface: Color(0xFF1A120C),
    surfaceLight: Color(0xFF231910),
    surfaceLighter: Color(0xFF2C2015),
    primary: Color(0xFFF97316),
    primaryLight: Color(0xFFFB923C),
    primaryDark: Color(0xFFEA580C),
    textSecondary: Color(0xFFB8A898),
    textTertiary: Color(0xFF85766A),
    border: Color(0xFF3B2A1C),
    borderLight: Color(0xFF4E3826),
    audioTrack: Color(0xFFFACC15),
  );

  static const forest = EditorThemeData(
    id: 'forest',
    name: 'Forest',
    description: 'Dark pine with fresh green',
    background: Color(0xFF07110B),
    surface: Color(0xFF0C1811),
    surfaceLight: Color(0xFF112117),
    surfaceLighter: Color(0xFF172A1E),
    primary: Color(0xFF22C55E),
    primaryLight: Color(0xFF4ADE80),
    primaryDark: Color(0xFF16A34A),
    textSecondary: Color(0xFF9DB3A4),
    textTertiary: Color(0xFF6A8272),
    border: Color(0xFF1E3326),
    borderLight: Color(0xFF2A4534),
    textTrack: Color(0xFF06B6D4),
  );

  static const List<EditorThemeData> all = [
    premium,
    midnight,
    amoled,
    ocean,
    rose,
    ember,
    forest,
  ];

  static EditorThemeData byId(String id) =>
      all.firstWhere((t) => t.id == id, orElse: () => premium);
}
