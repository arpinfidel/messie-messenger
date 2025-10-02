import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

const Color kMessieAccent = Color(0xFF4C8DF6);

const Color kMessieDarkBackground = Color(0xFF0F1115);
const Color kMessieDarkOnBackground = Color(0xFFE6E7EB);
const Color kMessieDarkSurface0 = Color(0xFF14171D);
const Color kMessieDarkSurface1 = Color(0xFF181C23);
const Color kMessieDarkSurface2 = Color(0xFF1D222B);
const Color kMessieDarkSurface3 = Color(0xFF222834);
const Color kMessieDarkMuted = Color(0xFF9AA3AF);
const Color kMessieDarkDivider = Color(0xFF2A3140);
const Color kMessieDarkInfo = Color(0xFF7AA7FF);

const Color kMessieLightBackground = Color(0xFFF5F7FB);
const Color kMessieLightOnBackground = Color(0xFF11161F);
const Color kMessieLightSurface0 = Color(0xFFF9FAFC);
const Color kMessieLightSurface1 = Color(0xFFF1F4F9);
const Color kMessieLightSurface2 = Color(0xFFE7EBF3);
const Color kMessieLightSurface3 = Color(0xFFDCE2EE);
const Color kMessieLightMuted = Color(0xFF5C6674);
const Color kMessieLightDivider = Color(0xFFCED4E0);
const Color kMessieLightInfo = Color(0xFF4A75D9);

const Color kMessieSuccess = Color(0xFF2FBF71);
const Color kMessieWarning = Color(0xFFE8B351);
const Color kMessieError = Color(0xFFEF5A5A);

class MessieSpacing extends ThemeExtension<MessieSpacing> {
  const MessieSpacing({
    required this.scale,
    required this.gap,
    required this.paneGap,
  });

  final List<double> scale;
  final MessieGap gap;
  final double paneGap;

  static const MessieSpacing standard = MessieSpacing(
    scale: [0, 2, 4, 6, 8, 12, 16, 20, 24, 28, 32, 40, 48, 64],
    gap: MessieGap(
      xs: 6,
      sm: 8,
      md: 12,
      lg: 16,
      xl: 24,
      xxl: 32,
    ),
    paneGap: 24,
  );

  static MessieSpacing of(BuildContext context) {
    return Theme.of(context).extension<MessieSpacing>() ?? standard;
  }

  static double gutter(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 720) return 16;
    if (width < 1000) return 24;
    return 32;
  }

  double byIndex(int index) {
    if (index < 0 || index >= scale.length) {
      throw RangeError.index(index, scale, 'index', null, scale.length);
    }
    return scale[index];
  }

  @override
  MessieSpacing copyWith({
    List<double>? scale,
    MessieGap? gap,
    double? paneGap,
  }) {
    return MessieSpacing(
      scale: scale ?? this.scale,
      gap: gap ?? this.gap,
      paneGap: paneGap ?? this.paneGap,
    );
  }

  @override
  MessieSpacing lerp(ThemeExtension<MessieSpacing>? other, double t) {
    if (other is! MessieSpacing) return this;
    return MessieSpacing(
      scale: List<double>.generate(
        scale.length,
        (index) =>
            lerpDouble(scale[index], other.scale[index], t) ?? scale[index],
      ),
      gap: MessieGap(
        xs: lerpDouble(gap.xs, other.gap.xs, t) ?? gap.xs,
        sm: lerpDouble(gap.sm, other.gap.sm, t) ?? gap.sm,
        md: lerpDouble(gap.md, other.gap.md, t) ?? gap.md,
        lg: lerpDouble(gap.lg, other.gap.lg, t) ?? gap.lg,
        xl: lerpDouble(gap.xl, other.gap.xl, t) ?? gap.xl,
        xxl: lerpDouble(gap.xxl, other.gap.xxl, t) ?? gap.xxl,
      ),
      paneGap: lerpDouble(paneGap, other.paneGap, t) ?? paneGap,
    );
  }
}

class MessieGap {
  const MessieGap({
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
    required this.xxl,
  });

  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;
  final double xxl;
}

class MessieRadii extends ThemeExtension<MessieRadii> {
  const MessieRadii({
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
  });

  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;

  static const MessieRadii standard = MessieRadii(
    xs: 6,
    sm: 8,
    md: 12,
    lg: 16,
    xl: 20,
  );

  static MessieRadii of(BuildContext context) {
    return Theme.of(context).extension<MessieRadii>() ?? standard;
  }

  BorderRadius radiusMd() => BorderRadius.circular(md);
  BorderRadius radiusLg() => BorderRadius.circular(lg);
  BorderRadius radiusXl() => BorderRadius.circular(xl);

  @override
  MessieRadii copyWith({
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? xl,
  }) {
    return MessieRadii(
      xs: xs ?? this.xs,
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      xl: xl ?? this.xl,
    );
  }

  @override
  MessieRadii lerp(ThemeExtension<MessieRadii>? other, double t) {
    if (other is! MessieRadii) return this;
    return MessieRadii(
      xs: lerpDouble(xs, other.xs, t) ?? xs,
      sm: lerpDouble(sm, other.sm, t) ?? sm,
      md: lerpDouble(md, other.md, t) ?? md,
      lg: lerpDouble(lg, other.lg, t) ?? lg,
      xl: lerpDouble(xl, other.xl, t) ?? xl,
    );
  }
}

class MessieSurfaces extends ThemeExtension<MessieSurfaces> {
  const MessieSurfaces({
    required this.background,
    required this.onBackground,
    required this.surface0,
    required this.surface1,
    required this.surface2,
    required this.surface3,
  });

  final Color background;
  final Color onBackground;
  final Color surface0;
  final Color surface1;
  final Color surface2;
  final Color surface3;

  static const MessieSurfaces dark = MessieSurfaces(
    background: kMessieDarkBackground,
    onBackground: kMessieDarkOnBackground,
    surface0: kMessieDarkSurface0,
    surface1: kMessieDarkSurface1,
    surface2: kMessieDarkSurface2,
    surface3: kMessieDarkSurface3,
  );

  static const MessieSurfaces light = MessieSurfaces(
    background: kMessieLightBackground,
    onBackground: kMessieLightOnBackground,
    surface0: kMessieLightSurface0,
    surface1: kMessieLightSurface1,
    surface2: kMessieLightSurface2,
    surface3: kMessieLightSurface3,
  );

  static MessieSurfaces of(BuildContext context) {
    return Theme.of(context).extension<MessieSurfaces>() ?? dark;
  }

  Color byLevel(int level) {
    switch (level) {
      case 0:
        return surface0;
      case 1:
        return surface1;
      case 2:
        return surface2;
      case 3:
        return surface3;
      default:
        return surface3;
    }
  }

  @override
  MessieSurfaces copyWith({
    Color? background,
    Color? onBackground,
    Color? surface0,
    Color? surface1,
    Color? surface2,
    Color? surface3,
  }) {
    return MessieSurfaces(
      background: background ?? this.background,
      onBackground: onBackground ?? this.onBackground,
      surface0: surface0 ?? this.surface0,
      surface1: surface1 ?? this.surface1,
      surface2: surface2 ?? this.surface2,
      surface3: surface3 ?? this.surface3,
    );
  }

  @override
  MessieSurfaces lerp(ThemeExtension<MessieSurfaces>? other, double t) {
    if (other is! MessieSurfaces) return this;
    return MessieSurfaces(
      background: Color.lerp(background, other.background, t) ?? background,
      onBackground:
          Color.lerp(onBackground, other.onBackground, t) ?? onBackground,
      surface0: Color.lerp(surface0, other.surface0, t) ?? surface0,
      surface1: Color.lerp(surface1, other.surface1, t) ?? surface1,
      surface2: Color.lerp(surface2, other.surface2, t) ?? surface2,
      surface3: Color.lerp(surface3, other.surface3, t) ?? surface3,
    );
  }
}

class MessieColors extends ThemeExtension<MessieColors> {
  const MessieColors({
    required this.accent,
    required this.muted,
    required this.divider,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
  });

  final Color accent;
  final Color muted;
  final Color divider;
  final Color success;
  final Color warning;
  final Color error;
  final Color info;

  static const MessieColors dark = MessieColors(
    accent: kMessieAccent,
    muted: kMessieDarkMuted,
    divider: kMessieDarkDivider,
    success: kMessieSuccess,
    warning: kMessieWarning,
    error: kMessieError,
    info: kMessieDarkInfo,
  );

  static const MessieColors light = MessieColors(
    accent: kMessieAccent,
    muted: kMessieLightMuted,
    divider: kMessieLightDivider,
    success: kMessieSuccess,
    warning: kMessieWarning,
    error: kMessieError,
    info: kMessieLightInfo,
  );

  static MessieColors of(BuildContext context) {
    return Theme.of(context).extension<MessieColors>() ?? dark;
  }

  @override
  MessieColors copyWith({
    Color? accent,
    Color? muted,
    Color? divider,
    Color? success,
    Color? warning,
    Color? error,
    Color? info,
  }) {
    return MessieColors(
      accent: accent ?? this.accent,
      muted: muted ?? this.muted,
      divider: divider ?? this.divider,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      info: info ?? this.info,
    );
  }

  @override
  MessieColors lerp(ThemeExtension<MessieColors>? other, double t) {
    if (other is! MessieColors) return this;
    return MessieColors(
      accent: Color.lerp(accent, other.accent, t) ?? accent,
      muted: Color.lerp(muted, other.muted, t) ?? muted,
      divider: Color.lerp(divider, other.divider, t) ?? divider,
      success: Color.lerp(success, other.success, t) ?? success,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      error: Color.lerp(error, other.error, t) ?? error,
      info: Color.lerp(info, other.info, t) ?? info,
    );
  }
}

class MessieElevation extends ThemeExtension<MessieElevation> {
  const MessieElevation({
    required this.subtle,
    required this.lifted,
  });

  final List<BoxShadow> subtle;
  final List<BoxShadow> lifted;

  static const MessieElevation dark = MessieElevation(
    subtle: [
      BoxShadow(
        color: Color(0x33000000),
        blurRadius: 6,
        offset: Offset(0, 2),
      ),
    ],
    lifted: [
      BoxShadow(
        color: Color(0x55000000),
        blurRadius: 18,
        offset: Offset(0, 6),
      ),
    ],
  );

  static const MessieElevation light = MessieElevation(
    subtle: [
      BoxShadow(
        color: Color(0x14000000),
        blurRadius: 6,
        offset: Offset(0, 2),
      ),
    ],
    lifted: [
      BoxShadow(
        color: Color(0x26000000),
        blurRadius: 18,
        offset: Offset(0, 6),
      ),
    ],
  );

  static MessieElevation of(BuildContext context) {
    return Theme.of(context).extension<MessieElevation>() ?? dark;
  }

  @override
  MessieElevation copyWith({
    List<BoxShadow>? subtle,
    List<BoxShadow>? lifted,
  }) {
    return MessieElevation(
      subtle: subtle ?? this.subtle,
      lifted: lifted ?? this.lifted,
    );
  }

  @override
  MessieElevation lerp(ThemeExtension<MessieElevation>? other, double t) {
    if (other is! MessieElevation) return this;
    return MessieElevation(
      subtle: _lerpShadows(subtle, other.subtle, t),
      lifted: _lerpShadows(lifted, other.lifted, t),
    );
  }

  List<BoxShadow> _lerpShadows(
    List<BoxShadow> a,
    List<BoxShadow> b,
    double t,
  ) {
    final int maxLength = a.length > b.length ? a.length : b.length;
    return List<BoxShadow>.generate(maxLength, (int index) {
      final BoxShadow first = index < a.length ? a[index] : const BoxShadow();
      final BoxShadow second = index < b.length ? b[index] : const BoxShadow();
      return BoxShadow.lerp(first, second, t)!;
    });
  }
}

extension MessieSpacingX on MessieSpacing {
  double gutterForWidth(double width) {
    if (width < 720) return 16;
    if (width < 1000) return 24;
    return 32;
  }
}
