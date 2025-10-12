import 'package:flutter/material.dart';
import '../../theme/messie_tokens.dart' as legacy;

extension MessieThemeExt on BuildContext {
  legacy.MessieSpacing get spacing => legacy.MessieSpacing.of(this);
  legacy.MessieRadii get radii => legacy.MessieRadii.of(this);
  legacy.MessieSurfaces get surfaces => legacy.MessieSurfaces.of(this);
  legacy.MessieColors get messieColors => legacy.MessieColors.of(this);
  legacy.MessieElevation get elevation => legacy.MessieElevation.of(this);
}

