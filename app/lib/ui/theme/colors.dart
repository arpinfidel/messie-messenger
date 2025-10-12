import 'package:flutter/material.dart';
import 'oklch_color.dart';

/// Theme selection enums.
enum MessieThemeMode { light, dark, system }
enum MessieAccent { aqua, peach, violet, slate }

/// Provides OKLCH seed values for accents and helpers to map to Material color roles.
class MessieColorSeeds {
  const MessieColorSeeds._();

  static Color accent(MessieAccent accent, {double l = 0.75}) {
    switch (accent) {
      case MessieAccent.aqua:
        return oklch(l, 0.12, 180); // inspired by Messie logo
      case MessieAccent.peach:
        return oklch(l, 0.13, 45);
      case MessieAccent.violet:
        return oklch(l, 0.12, 300);
      case MessieAccent.slate:
        return oklch(l, 0.03, 250);
    }
  }

  /// Neutral scales for light/dark backgrounds using OKLCH.
  static List<Color> neutralScale(Brightness b) {
    final isDark = b == Brightness.dark;
    return oklchToneScale(
      c: 0.02,
      h: 250,
      lightnessStops: isDark
          ? const [0.16, 0.18, 0.21, 0.24, 0.28, 0.32, 0.36, 0.40, 0.46, 0.52]
          : const [0.99, 0.97, 0.95, 0.93, 0.90, 0.86, 0.82, 0.78, 0.72, 0.66],
    );
  }
}

