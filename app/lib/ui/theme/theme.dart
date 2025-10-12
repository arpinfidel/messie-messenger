import 'package:flutter/material.dart';

import '../../theme/messie_tokens.dart' as legacy;
import 'colors.dart';
import 'oklch_color.dart';
import 'text.dart';

/// Build a ThemeData from OKLCH seed + brightness, injecting legacy tokens.
class MessieThemeBuilder {
  static ThemeData build({
    required Brightness brightness,
    required MessieAccent accent,
  }) {
    final seed = MessieColorSeeds.accent(accent);
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );

    final textTheme = buildMessieTextTheme(scheme);
    final surfaces = brightness == Brightness.dark
        ? legacy.MessieSurfaces.dark
        : legacy.MessieSurfaces.light;
    final colors = brightness == Brightness.dark
        ? legacy.MessieColors.dark
        : legacy.MessieColors.light;
    final elevation = brightness == Brightness.dark
        ? legacy.MessieElevation.dark
        : legacy.MessieElevation.light;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: surfaces.background,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: surfaces.surface0,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        titleTextStyle:
            textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      cardTheme: CardThemeData(
        color: surfaces.surface2,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(legacy.MessieRadii.standard.xl),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          textStyle: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(legacy.MessieRadii.standard.lg),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          foregroundColor: scheme.onSurface,
          textStyle: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          side: BorderSide(color: colors.divider),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(legacy.MessieRadii.standard.lg),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(legacy.MessieRadii.standard.lg),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(legacy.MessieRadii.standard.lg),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(legacy.MessieRadii.standard.lg),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
      ),
      dividerColor: colors.divider,
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      extensions: <ThemeExtension<dynamic>>[
        legacy.MessieSpacing.standard,
        legacy.MessieRadii.standard,
        surfaces,
        colors,
        elevation,
      ],
    );
  }
}

