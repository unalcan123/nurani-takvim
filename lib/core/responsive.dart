import 'package:flutter/material.dart';

/// Logical-pixel shortest-side threshold below which the UI is treated as a
/// phone rather than a tablet/desktop. Matches the 600dp breakpoint already
/// used ad hoc elsewhere in the app (e.g. `prayer_sound_section.dart`).
const double kPhoneBreakpoint = 600;

/// Phone vs. tablet/desktop, robust to rotation: a phone's shortest side
/// stays roughly constant whether held portrait or landscape, while using
/// raw width alone would misclassify a landscape phone as a tablet.
bool isPhoneSize(Size size) => size.shortestSide < kPhoneBreakpoint;

bool isPhoneContext(BuildContext context) =>
    isPhoneSize(MediaQuery.sizeOf(context));

/// Returns [normal] unless the current context is phone-sized, in which case
/// [phoneMin] is used if it is larger — never shrinks below what the caller
/// intended and never changes tablet/web sizing.
double phoneFont(BuildContext context, double normal, double phoneMin) =>
    isPhoneContext(context) && phoneMin > normal ? phoneMin : normal;

/// Raises [style]'s fontSize to at least [minSize]; leaves it untouched if
/// it is already at or above that size, or if [style] is null.
TextStyle? withMinFontSize(TextStyle? style, double minSize) {
  if (style == null) return style;
  final size = style.fontSize;
  if (size != null && size >= minSize) return style;
  return style.copyWith(fontSize: minSize);
}

/// A copy of [base] with every named style floored to phone-readable
/// minimums (secondary/label text >=14, primary/title text >=16-18).
/// Sizes already at or above the floor are left untouched, so this only
/// ever affects phone-sized layouts where it is applied conditionally.
TextTheme phoneTextTheme(TextTheme base) => base.copyWith(
      displayLarge: withMinFontSize(base.displayLarge, 28),
      displayMedium: withMinFontSize(base.displayMedium, 24),
      displaySmall: withMinFontSize(base.displaySmall, 20),
      headlineLarge: withMinFontSize(base.headlineLarge, 22),
      headlineMedium: withMinFontSize(base.headlineMedium, 20),
      headlineSmall: withMinFontSize(base.headlineSmall, 18),
      titleLarge: withMinFontSize(base.titleLarge, 18),
      titleMedium: withMinFontSize(base.titleMedium, 16),
      titleSmall: withMinFontSize(base.titleSmall, 14),
      bodyLarge: withMinFontSize(base.bodyLarge, 16),
      bodyMedium: withMinFontSize(base.bodyMedium, 14),
      bodySmall: withMinFontSize(base.bodySmall, 14),
      labelLarge: withMinFontSize(base.labelLarge, 14),
      labelMedium: withMinFontSize(base.labelMedium, 14),
      labelSmall: withMinFontSize(base.labelSmall, 14),
    );

/// Minimum logical-pixel side for a comfortably tappable control.
const double kMinTapTarget = 48.0;
