import 'package:flutter/material.dart';

import 'messie_tokens.dart';

class AppTheme {
  const AppTheme._();

  static const MessieSurfaces _darkSurfaces = MessieSurfaces.dark;
  static const MessieSurfaces _lightSurfaces = MessieSurfaces.light;
  static const MessieColors _darkColors = MessieColors.dark;
  static const MessieColors _lightColors = MessieColors.light;
  static const MessieElevation _darkElevation = MessieElevation.dark;
  static const MessieElevation _lightElevation = MessieElevation.light;

  static const ColorScheme _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: kMessieAccent,
    onPrimary: Color(0xFF0A1A33),
    primaryContainer: Color(0xFF1E3F72),
    onPrimaryContainer: Color(0xFFDCE7FF),
    secondary: kMessieDarkMuted,
    onSecondary: Color(0xFF11161F),
    secondaryContainer: Color(0xFF252F3E),
    onSecondaryContainer: Color(0xFFE2E6EF),
    tertiary: kMessieDarkInfo,
    onTertiary: Color(0xFF081021),
    tertiaryContainer: Color(0xFF1E3358),
    onTertiaryContainer: Color(0xFFE0E8FF),
    error: kMessieError,
    onError: Color(0xFF2F0A0A),
    errorContainer: Color(0xFF4A191A),
    onErrorContainer: Color(0xFFFCE2E2),
    // ignore: deprecated_member_use
    background: kMessieDarkBackground,
    // ignore: deprecated_member_use
    onBackground: kMessieDarkOnBackground,
    surface: kMessieDarkSurface0,
    onSurface: kMessieDarkOnBackground,
    // ignore: deprecated_member_use
    surfaceVariant: kMessieDarkDivider,
    // ignore: deprecated_member_use
    onSurfaceVariant: kMessieDarkMuted,
    outline: kMessieDarkDivider,
    outlineVariant: Color(0xFF1F2633),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFE3E6EC),
    onInverseSurface: Color(0xFF0F1115),
    inversePrimary: Color(0xFF1D4CB8),
    surfaceTint: kMessieAccent,
    surfaceDim: Color(0xFF11141A),
    surfaceBright: Color(0xFF2A3140),
    surfaceContainerLowest: kMessieDarkBackground,
    surfaceContainerLow: kMessieDarkSurface0,
    surfaceContainer: kMessieDarkSurface1,
    surfaceContainerHigh: kMessieDarkSurface2,
    surfaceContainerHighest: kMessieDarkSurface3,
  );

  static const ColorScheme _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: kMessieAccent,
    onPrimary: Color(0xFFF5F7FF),
    primaryContainer: Color(0xFFD6E3FF),
    onPrimaryContainer: Color(0xFF031635),
    secondary: kMessieLightMuted,
    onSecondary: Color(0xFFF5F7FB),
    secondaryContainer: Color(0xFFE2E7F1),
    onSecondaryContainer: Color(0xFF121922),
    tertiary: kMessieLightInfo,
    onTertiary: Color(0xFFF0F4FF),
    tertiaryContainer: Color(0xFFDCE4FF),
    onTertiaryContainer: Color(0xFF0D1E45),
    error: kMessieError,
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    // ignore: deprecated_member_use
    background: kMessieLightBackground,
    // ignore: deprecated_member_use
    onBackground: kMessieLightOnBackground,
    surface: kMessieLightSurface0,
    onSurface: kMessieLightOnBackground,
    // ignore: deprecated_member_use
    surfaceVariant: kMessieLightDivider,
    // ignore: deprecated_member_use
    onSurfaceVariant: kMessieLightMuted,
    outline: kMessieLightDivider,
    outlineVariant: Color(0xFFE4E8F1),
    shadow: Color(0x55000000),
    scrim: Color(0x55000000),
    inverseSurface: Color(0xFF232834),
    onInverseSurface: Color(0xFFF4F6FA),
    inversePrimary: Color(0xFFAEC7FF),
    surfaceTint: kMessieAccent,
    surfaceDim: Color(0xFFE6E9F1),
    surfaceBright: Color(0xFFF9FBFF),
    surfaceContainerLowest: kMessieLightBackground,
    surfaceContainerLow: kMessieLightSurface1,
    surfaceContainer: kMessieLightSurface2,
    surfaceContainerHigh: kMessieLightSurface3,
    surfaceContainerHighest: Color(0xFFC8CEDC),
  );

  static ThemeData get dark => _buildTheme(
        colorScheme: _darkScheme,
        surfaces: _darkSurfaces,
        colors: _darkColors,
        elevation: _darkElevation,
      );

  static ThemeData get light => _buildTheme(
        colorScheme: _lightScheme,
        surfaces: _lightSurfaces,
        colors: _lightColors,
        elevation: _lightElevation,
      );

  static ThemeData _buildTheme({
    required ColorScheme colorScheme,
    required MessieSurfaces surfaces,
    required MessieColors colors,
    required MessieElevation elevation,
  }) {
    final TextTheme textTheme = _textTheme(colorScheme);

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: surfaces.background,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: surfaces.surface0,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        titleTextStyle:
            textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      cardTheme: CardThemeData(
        color: surfaces.surface2,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MessieRadii.standard.xl),
        ),
        margin: EdgeInsets.zero,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaces.surface3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MessieRadii.standard.lg),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // Avoid infinite width in unconstrained parents (e.g., Row)
          minimumSize: const Size(64, 48),
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          textStyle:
              textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MessieRadii.standard.lg),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: MessieSpacing.standard.gap.lg,
            vertical: MessieSpacing.standard.gap.sm,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          // Avoid infinite width in unconstrained parents (e.g., Row)
          minimumSize: const Size(64, 48),
          foregroundColor: colorScheme.onSurface,
          textStyle:
              textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          side: BorderSide(color: colors.divider),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MessieRadii.standard.lg),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MessieRadii.standard.lg),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MessieRadii.standard.lg),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MessieRadii.standard.lg),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: MessieSpacing.standard.gap.lg,
          vertical: MessieSpacing.standard.gap.md,
        ),
        labelStyle:
            textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
        prefixIconColor: colorScheme.onSurfaceVariant,
        suffixIconColor: colorScheme.onSurfaceVariant,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surfaces.surface3,
        contentTextStyle:
            textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MessieRadii.standard.lg),
        ),
        insetPadding: EdgeInsets.all(MessieSpacing.standard.gap.lg),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(
          horizontal: MessieSpacing.standard.gap.lg,
          vertical: MessieSpacing.standard.gap.sm,
        ),
        iconColor: colorScheme.onSurfaceVariant,
      ),
      dividerColor: colors.divider,
      iconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
      extensions: <ThemeExtension<dynamic>>[
        MessieSpacing.standard,
        MessieRadii.standard,
        surfaces,
        colors,
        elevation,
      ],
    );
  }

  static TextTheme _textTheme(ColorScheme colorScheme) {
    final bool isDark = colorScheme.brightness == Brightness.dark;
    final TextTheme base =
        isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme;

    const double headlineSize = 22;
    const double bodySize = 14;
    const double captionSize = 12;

    return base.copyWith(
      headlineSmall: base.headlineSmall?.copyWith(
        fontSize: headlineSize,
        height: 28 / headlineSize,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontSize: 20,
        height: 26 / 20,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 16,
        height: 22 / 16,
        fontWeight: FontWeight.w600,
        color: colorScheme.onSurface,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        fontSize: bodySize,
        height: 20 / bodySize,
        fontWeight: FontWeight.w400,
        color: colorScheme.onSurface,
      ),
      bodySmall: base.bodySmall?.copyWith(
        fontSize: captionSize,
        height: 16 / captionSize,
        fontWeight: FontWeight.w500,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }
}
