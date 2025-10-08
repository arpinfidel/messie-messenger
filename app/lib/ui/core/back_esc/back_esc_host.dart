import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'back_esc_policy.dart';

/// Hosts BackEscPolicy, FocusTraversalGroup, and Escape shortcut.
class BackEscHost extends StatelessWidget {
  const BackEscHost({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BackEscPolicy(
      child: FocusTraversalGroup(
        child: Shortcuts(
          shortcuts: <LogicalKeySet, Intent>{
            LogicalKeySet(LogicalKeyboardKey.escape): const DismissIntent(),
          },
          child: Actions(
            actions: <Type, Action<Intent>>{
              DismissIntent: CallbackAction<DismissIntent>(
                onInvoke: (intent) {
                  BackEscPolicy.of(context).handleBack();
                  return null;
                },
              ),
            },
            child: child,
          ),
        ),
      ),
    );
  }
}

class DismissIntent extends Intent {
  const DismissIntent();
}
