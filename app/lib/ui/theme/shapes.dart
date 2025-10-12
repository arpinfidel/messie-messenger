import 'package:flutter/material.dart';
import '../../theme/messie_tokens.dart' as legacy;

/// Shape tokens (radii/shadows) bridged from existing ThemeExtensions.
class Shapes {
  static legacy.MessieRadii radii(BuildContext context) =>
      legacy.MessieRadii.of(context);
  static legacy.MessieElevation elevation(BuildContext context) =>
      legacy.MessieElevation.of(context);
}

