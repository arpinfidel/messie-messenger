import 'package:flutter/material.dart';
import '../../../theme/messie_tokens.dart';
import '../../core/back_esc/back_esc_policy.dart';

Future<T?> showAdaptiveModal<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final spacing = MessieSpacing.of(context);
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) {
      return BackEscSurface(
        priority: SurfacePriority.modal,
        onDismiss: () async {
          if (Navigator.of(ctx).canPop()) {
            Navigator.of(ctx).pop();
            return true;
          }
          return false;
        },
        child: Dialog(
          insetPadding: EdgeInsets.symmetric(
            horizontal: spacing.gap.lg,
            vertical: spacing.gap.xl,
          ),
          child: Builder(builder: builder),
        ),
      );
    },
  );
}

Future<T?> showAdaptiveSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) {
      final spacing = MessieSpacing.of(ctx);
      return BackEscSurface(
        priority: SurfacePriority.modal,
        onDismiss: () async {
          Navigator.of(ctx).maybePop();
          return true;
        },
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(ctx).bottom + spacing.gap.lg,
          ),
          child: Builder(builder: builder),
        ),
      );
    },
  );
}

Future<T?> showPopupMenuAdaptive<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<PopupMenuEntry<T>> items,
}) async {
  final result = await showMenu<T>(
    context: context,
    position: position,
    items: items,
  );
  return result;
}
