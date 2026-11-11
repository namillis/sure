import 'package:flutter/material.dart';

import 'sure_tokens.dart';

/// Exposes the full Sure design-system palette to widgets in a brightness-aware
/// way. The generated [SureTokenPalette] carries semantic colors (success,
/// destructive, textSubdued, …) that the base [ColorScheme] does not, so without
/// this extension widgets have to branch on `Theme.of(context).brightness` and
/// reach into `SureTokens.light`/`SureTokens.dark` by hand. Registering the
/// active palette here lets them resolve the correct token via
/// `SureColors.of(context).palette.success` instead.
@immutable
class SureColors extends ThemeExtension<SureColors> {
  const SureColors(this.palette);

  final SureTokenPalette palette;

  /// The 1px hairline used for panel outlines and row dividers. Light uses
  /// `borderSecondary`; dark uses the lighter `borderSubdued`, because white at
  /// 20% reads heavy on the near-black panels while 10% stays subtle but
  /// clearly visible.
  Color get hairline => identical(palette, SureTokens.dark)
      ? palette.borderSubdued
      : palette.borderSecondary;

  /// Whether [palette] is the dark palette.
  bool get isDark => identical(palette, SureTokens.dark);

  /// The active palette for [context]. Falls back to the palette matching the
  /// active brightness if the extension is missing (e.g. a widget built outside
  /// [SureTheme] in a test), so dark surfaces don't get light-palette colors.
  static SureColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<SureColors>() ??
        SureColors(
          theme.brightness == Brightness.dark
              ? SureTokens.dark
              : SureTokens.light,
        );
  }

  @override
  SureColors copyWith({SureTokenPalette? palette}) {
    return SureColors(palette ?? this.palette);
  }

  @override
  SureColors lerp(ThemeExtension<SureColors>? other, double t) {
    // Design tokens are a discrete light/dark pair; a mid-transition blend of
    // every semantic color is not meaningful, so swap at the midpoint.
    if (other is! SureColors) {
      return this;
    }
    return t < 0.5 ? this : other;
  }
}
