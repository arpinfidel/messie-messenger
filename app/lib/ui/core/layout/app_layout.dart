import 'package:flutter/widgets.dart';

/// Centralized responsive layout model for the app.
/// Mobile-first today; tablet/desktop slots reserved for later.
class AppLayout extends InheritedWidget {
  const AppLayout._internal({
    required super.child,
    required this.formFactor,
    required this.gutter,
    required this.density,
    required this.typographyScale,
  });

  /// Factory that computes fields from [MediaQuery] once per subtree.
  factory AppLayout({required Widget child}) {
    return _AppLayoutBuilder(child: child);
  }

  final FormFactor formFactor;
  final double gutter;
  final double density; // Higher = denser UI; kept for future tuning
  final double typographyScale;

  static const double mobileMax = 600;
  static const double tabletMax = 1024;

  /// Accessor
  static AppLayout of(BuildContext context) {
    final inherited = context.dependOnInheritedWidgetOfExactType<AppLayout>();
    assert(inherited != null, 'AppLayout.of() called with no AppLayout above');
    return inherited!;
  }

  @override
  bool updateShouldNotify(covariant AppLayout oldWidget) {
    return formFactor != oldWidget.formFactor ||
        gutter != oldWidget.gutter ||
        density != oldWidget.density ||
        typographyScale != oldWidget.typographyScale;
  }
}

class _AppLayoutBuilder extends AppLayout {
  _AppLayoutBuilder({required Widget child})
      : super._internal(
          child: _BuildFromMedia(child: child),
          formFactor: FormFactor.mobile,
          gutter: 16,
          density: 1.0,
          typographyScale: 1.0,
        );
}

class _BuildFromMedia extends StatefulWidget {
  const _BuildFromMedia({required this.child});
  final Widget child;

  @override
  State<_BuildFromMedia> createState() => _BuildFromMediaState();
}

class _BuildFromMediaState extends State<_BuildFromMedia> {
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = size.width;
    final form = _formFactorForWidth(width);
    final gutter = _gutterForWidth(width);
    final density = 1.0; // Placeholder for future density model
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);

    return AppLayout._internal(
      formFactor: form,
      gutter: gutter,
      density: density,
      typographyScale: textScale,
      child: widget.child,
    );
  }

  static FormFactor _formFactorForWidth(double width) {
    if (width < AppLayout.mobileMax) return FormFactor.mobile;
    if (width < AppLayout.tabletMax) return FormFactor.tablet;
    return FormFactor.desktop;
  }

  static double _gutterForWidth(double width) {
    if (width < 720) return 16;
    if (width < 1000) return 24;
    return 32;
  }
}

enum FormFactor { mobile, tablet, desktop }

