import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:color_models/color_models.dart';

/// Create a Color from OKLCH components using color_models.
/// l [0..1], c [0..~0.4], h degrees [0..360]. Alpha [0..1].
/// color_models exposes OklabColor publicly; compute a/b from LCh.
Color oklch(double l, double c, double h, [double alpha = 1.0]) {
  final rad = (h % 360) * math.pi / 180.0;
  final a = c * math.cos(rad);
  final b = c * math.sin(rad);
  final alpha8 = (alpha * 255).round().clamp(0, 255);
  final ok = OklabColor(l, a, b, alpha8);
  final rgb = ok.toRgbColor(); // sRGB in 0..255 channel range (double)
  return Color.fromRGBO(
    rgb.red.round().clamp(0, 255),
    rgb.green.round().clamp(0, 255),
    rgb.blue.round().clamp(0, 255),
    alpha,
  );
}

/// Optional alias matching example docs.
Color oklchColor(double l, double c, double h, [double alpha = 1.0]) => oklch(l, c, h, alpha);

/// Generates simple tone steps by varying lightness in OKLCH and converting to sRGB.
List<Color> oklchToneScale({
  required double c,
  required double h,
  List<double> lightnessStops = const [
    0.98, 0.92, 0.86, 0.78, 0.70, 0.62, 0.54, 0.46, 0.38, 0.30
  ],
}) {
  return [for (final l in lightnessStops) oklch(l, c, h)];
}
