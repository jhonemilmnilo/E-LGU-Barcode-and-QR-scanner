import 'package:flutter/material.dart';

class AppThemeColors {
  final bool isDark;

  const AppThemeColors({required this.isDark});

  Color get scaffoldBg => isDark ? const Color(0xFF0B0F17) : const Color(0xFFF8FAFC);
  Color get cardBg => isDark ? const Color(0xFF151C28) : Colors.white;
  Color get cardBorder => isDark ? const Color(0xFF263346) : const Color(0xFFE2E8F0);
  Color get textPrimary => isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
  Color get textSecondary => isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  Color get textMuted => isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8);
  Color get inputBg => isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);
  Color get inputBorder => isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
  Color get divider => isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
  Color get chipBg => isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
  Color get drawerBg => isDark ? const Color(0xFF111827) : Colors.white;
  Color get modalBg => isDark ? const Color(0xFF151C28) : Colors.white;
}

extension AppThemeContext on BuildContext {
  bool get isDarkMode {
    final theme = Theme.of(this);
    return theme.brightness == Brightness.dark;
  }

  AppThemeColors get colors => AppThemeColors(isDark: isDarkMode);
}
