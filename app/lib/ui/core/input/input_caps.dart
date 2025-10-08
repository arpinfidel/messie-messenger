import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Input capabilities available to the current device/context.
/// Defaults target mobile/touch now, can evolve later without breaking API.
class InputCaps extends InheritedWidget {
  const InputCaps._internal({
    required super.child,
    required this.hasKeyboard,
    required this.supportsHover,
    required this.hasMouse,
    required this.usesTouch,
    required this.isAppleLike,
  });

  factory InputCaps({required Widget child}) => _InputCapsBuilder(child: child);

  final bool hasKeyboard;
  final bool supportsHover;
  final bool hasMouse;
  final bool usesTouch;
  final bool isAppleLike;

  static InputCaps of(BuildContext context) {
    final caps = context.dependOnInheritedWidgetOfExactType<InputCaps>();
    assert(caps != null, 'InputCaps.of() called with no InputCaps above');
    return caps!;
  }

  @override
  bool updateShouldNotify(covariant InputCaps oldWidget) {
    return hasKeyboard != oldWidget.hasKeyboard ||
        supportsHover != oldWidget.supportsHover ||
        hasMouse != oldWidget.hasMouse ||
        usesTouch != oldWidget.usesTouch ||
        isAppleLike != oldWidget.isAppleLike;
  }
}

class _InputCapsBuilder extends InputCaps {
  _InputCapsBuilder({required Widget child})
      : super._internal(
          child: _CapsFromEnv(child: child),
          hasKeyboard: false,
          supportsHover: false,
          hasMouse: false,
          usesTouch: true,
          isAppleLike: false,
        );
}

class _CapsFromEnv extends StatefulWidget {
  const _CapsFromEnv({required this.child});
  final Widget child;

  @override
  State<_CapsFromEnv> createState() => _CapsFromEnvState();
}

class _CapsFromEnvState extends State<_CapsFromEnv> {
  @override
  Widget build(BuildContext context) {
    final platform = defaultTargetPlatform;
    final isApple = platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
    // Mobile-first defaults; can be made dynamic later.
    const hasKb = false;
    const hover = false;
    const mouse = false;
    const touch = true;

    return InputCaps._internal(
      hasKeyboard: hasKb,
      supportsHover: hover,
      hasMouse: mouse,
      usesTouch: touch,
      isAppleLike: isApple,
      child: widget.child,
    );
  }
}
