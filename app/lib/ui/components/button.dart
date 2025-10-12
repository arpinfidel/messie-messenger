import 'package:flutter/material.dart';
import '../utils/theme_ext.dart';

enum MessieButtonVariant { primary, secondary, ghost }

class MessieButton extends StatelessWidget {
  final MessieButtonVariant variant;
  final VoidCallback? onPressed;
  final Widget child;
  final bool fullWidth;

  const MessieButton({
    super.key,
    required this.child,
    this.variant = MessieButtonVariant.primary,
    this.onPressed,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = context.radii;
    final pad = EdgeInsets.symmetric(
      horizontal: context.spacing.gap.lg,
      vertical: context.spacing.gap.sm,
    );
    ButtonStyle style;
    switch (variant) {
      case MessieButtonVariant.primary:
        style = FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(40),
          ),
          padding: pad,
        );
        return SizedBox(
          width: fullWidth ? double.infinity : null,
          child: FilledButton(onPressed: onPressed, style: style, child: child),
        );
      case MessieButtonVariant.secondary:
        style = OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          foregroundColor: theme.colorScheme.onSurface,
          side: BorderSide(color: theme.dividerColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(40),
          ),
          padding: pad,
        );
        return SizedBox(
          width: fullWidth ? double.infinity : null,
          child: OutlinedButton(onPressed: onPressed, style: style, child: child),
        );
      case MessieButtonVariant.ghost:
        style = TextButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(r.lg),
          ),
          padding: pad,
        );
        return SizedBox(
          width: fullWidth ? double.infinity : null,
          child: TextButton(onPressed: onPressed, style: style, child: child),
        );
    }
  }
}

