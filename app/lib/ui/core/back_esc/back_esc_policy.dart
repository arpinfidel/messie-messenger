import 'package:flutter/widgets.dart';

enum SurfacePriority { popup, modal, route }

typedef DismissCallback = Future<bool> Function();

/// Central Back/Esc policy registry.
/// Maintains three stacks (popup, modal, route) to enforce dismissal order.
class BackEscPolicy extends InheritedWidget {
  BackEscPolicy({super.key, required super.child});

  final List<DismissCallback> _popups = <DismissCallback>[];
  final List<DismissCallback> _modals = <DismissCallback>[];
  final List<DismissCallback> _routes = <DismissCallback>[];

  static BackEscPolicy of(BuildContext context) {
    final policy = context.dependOnInheritedWidgetOfExactType<BackEscPolicy>();
    assert(policy != null, 'BackEscPolicy.of() called with no policy above');
    return policy!;
  }

  /// Register a visible surface; returns an unregister handle.
  VoidCallback registerSurface({
    required SurfacePriority priority,
    required DismissCallback onDismiss,
  }) {
    final stack = _stackFor(priority);
    stack.add(onDismiss);
    return () => stack.remove(onDismiss);
  }

  /// Handle back/esc: popup -> modal -> route -> confirm exit (no-op here).
  Future<bool> handleBack() async {
    final stack = _activeStack();
    if (stack == null || stack.isEmpty) return false;
    final onDismiss = stack.removeLast();
    return onDismiss();
  }

  List<DismissCallback>? _activeStack() {
    if (_popups.isNotEmpty) return _popups;
    if (_modals.isNotEmpty) return _modals;
    if (_routes.isNotEmpty) return _routes;
    return null;
  }

  List<DismissCallback> _stackFor(SurfacePriority p) {
    switch (p) {
      case SurfacePriority.popup:
        return _popups;
      case SurfacePriority.modal:
        return _modals;
      case SurfacePriority.route:
        return _routes;
    }
  }

  @override
  bool updateShouldNotify(covariant InheritedWidget oldWidget) => false;
}

/// Helper widget to auto-register a surface and unregister on dispose.
class BackEscSurface extends StatefulWidget {
  const BackEscSurface({
    super.key,
    required this.priority,
    required this.onDismiss,
    required this.child,
  });

  final SurfacePriority priority;
  final DismissCallback onDismiss;
  final Widget child;

  @override
  State<BackEscSurface> createState() => _BackEscSurfaceState();
}

class _BackEscSurfaceState extends State<BackEscSurface> {
  VoidCallback? _unregister;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _unregister?.call();
    _unregister = BackEscPolicy.of(context).registerSurface(
      priority: widget.priority,
      onDismiss: widget.onDismiss,
    );
  }

  @override
  void dispose() {
    _unregister?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
