import 'package:flutter/material.dart';

/// Centralized typography scale. Uses Inter/SF stack if available.
TextTheme buildMessieTextTheme(ColorScheme scheme) {
  const headline = 22.0; // 20–24 desired
  const body = 14.0; // 14–16 desired
  const caption = 12.0;

  final base = scheme.brightness == Brightness.dark
      ? ThemeData.dark().textTheme
      : ThemeData.light().textTheme;

  return base.copyWith(
    headlineSmall: base.headlineSmall?.copyWith(
      fontSize: headline,
      height: 28 / headline,
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
      fontFamilyFallback: const ['Inter', 'SF Pro Display', 'SF Pro', 'system-ui'],
    ),
    titleLarge: base.titleLarge?.copyWith(
      fontSize: 20,
      height: 26 / 20,
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
      fontFamilyFallback: const ['Inter', 'SF Pro Display', 'SF Pro', 'system-ui'],
    ),
    titleMedium: base.titleMedium?.copyWith(
      fontSize: 16,
      height: 22 / 16,
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
      fontFamilyFallback: const ['Inter', 'SF Pro Display', 'SF Pro', 'system-ui'],
    ),
    bodyMedium: base.bodyMedium?.copyWith(
      fontSize: body,
      height: 20 / body,
      color: scheme.onSurface,
      fontFamilyFallback: const ['Inter', 'SF Pro Text', 'SF Pro', 'system-ui'],
    ),
    bodySmall: base.bodySmall?.copyWith(
      fontSize: caption,
      height: 16 / caption,
      fontWeight: FontWeight.w500,
      color: scheme.onSurfaceVariant,
      fontFamilyFallback: const ['Inter', 'SF Pro Text', 'SF Pro', 'system-ui'],
    ),
  );
}

