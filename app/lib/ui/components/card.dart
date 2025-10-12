import 'package:flutter/material.dart';
import '../utils/theme_ext.dart';

class MessieCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  const MessieCard({super.key, required this.child, this.padding, this.margin});

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    final r = context.radii;
    final e = context.elevation;
    final p = padding ?? EdgeInsets.all(context.spacing.gap.md);
    return Container(
      margin: margin,
      padding: p,
      decoration: BoxDecoration(
        color: s.surface2,
        borderRadius: BorderRadius.circular(r.xl),
        boxShadow: e.subtle,
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: child,
    );
  }
}

