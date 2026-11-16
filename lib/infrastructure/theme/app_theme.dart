import 'package:flutter/material.dart';

class AppTheme {
  static const primary = Color(0xFF2867D5);
  static const secondary = Color(0xFF526071);
  static const tertiary = Color(0xFF10B981);
  static const neutral = Color(0xFF171A20);

  // Apply the requested palette with readable light surfaces and semantic colours.
  static ThemeData lightTheme(BuildContext context) => _theme(Brightness.light);

  // Preserve brand colours while adapting surfaces and text for dark mode.
  static ThemeData darkTheme(BuildContext context) => _theme(Brightness.dark);

  static ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: primary, brightness: brightness).copyWith(
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: dark ? const Color(0xFF1B335D) : const Color(0xFFE5EEFF),
      onPrimaryContainer: dark ? const Color(0xFFDCE7FF) : const Color(0xFF163B82),
      secondary: secondary,
      onSecondary: Colors.white,
      secondaryContainer: dark ? const Color(0xFF283241) : const Color(0xFFE8EDF3),
      onSecondaryContainer: dark ? const Color(0xFFDFE5ED) : neutral,
      tertiary: tertiary,
      onTertiary: neutral,
      tertiaryContainer: dark ? const Color(0xFF123D32) : const Color(0xFFD7F7EB),
      onTertiaryContainer: dark ? const Color(0xFFA7F3D0) : const Color(0xFF064D39),
      surface: dark ? neutral : Colors.white,
      onSurface: dark ? const Color(0xFFF5F7FB) : neutral,
      onSurfaceVariant: dark ? const Color(0xFFBCC6D3) : secondary,
      outline: dark ? const Color(0xFF8290A3) : secondary,
      outlineVariant: dark ? const Color(0xFF3B4553) : const Color(0xFFDCE2EB),
    );
    final background = dark ? neutral : const Color(0xFFF6F8FC);
    final card = dark ? const Color(0xFF20252D) : Colors.white;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: dark ? scheme.onPrimaryContainer : primary),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}
