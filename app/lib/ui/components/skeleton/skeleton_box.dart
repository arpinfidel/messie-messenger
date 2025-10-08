import 'package:flutter/material.dart';
import '../../../theme/messie_tokens.dart';

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height, this.radius});
  final double? width;
  final double? height;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final surfaces = MessieSurfaces.of(context);
    final radii = MessieRadii.of(context);
    final spacing = MessieSpacing.of(context);
    return Container(
      width: width,
      height: height ?? spacing.gap.md,
      decoration: BoxDecoration(
        color: surfaces.surface1,
        borderRadius: BorderRadius.circular(radius ?? radii.sm),
      ),
    );
  }
}
