import 'package:flutter/material.dart';
import '../../theme/messie_tokens.dart' as legacy;

/// Spacing tokens bridge to existing MessieSpacing ThemeExtension.
class Spacing {
  static legacy.MessieSpacing of(BuildContext context) =>
      legacy.MessieSpacing.of(context);
}

