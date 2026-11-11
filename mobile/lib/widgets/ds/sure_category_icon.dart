import 'package:flutter/material.dart';

import '../../theme/sure_colors.dart';
import '../budget_progress_bar.dart' show parseCategoryColor;
import '../sure_icon.dart';

/// What a [SureCategoryIcon] stands for when it is not a plain category.
enum SureCategoryKind {
  /// A real category (name, color and Lucide icon from the server).
  category,

  /// No category: neutral fill with a "?" glyph.
  uncategorized,

  /// A transfer between accounts: neutral fill with arrow-left-right.
  transfer,

  /// A split parent: neutral fill with the split glyph.
  split,
}

/// Round category badge: the category color at ~14% (dark ~18%) behind its
/// Lucide glyph in the full color.
///
/// Sizes: [SureCategoryIcon.rowSize] (28) in rows, [heroSize] (48) in the
/// transaction sheet, [dotSize] (16) in pickers and split lines. At dot size
/// the glyph is dropped and the dot is the solid category color.
///
/// Fallbacks: no category → neutral inset fill with a "?" in `textSecondary`;
/// transfer → arrow-left-right; split → split; an icon name the app does not
/// bundle → the category's first letter in the category color.
class SureCategoryIcon extends StatelessWidget {
  const SureCategoryIcon({
    super.key,
    this.name,
    this.color,
    this.icon,
    this.kind,
    this.size = rowSize,
  });

  /// A transfer badge.
  const SureCategoryIcon.transfer({super.key, this.size = rowSize})
      : name = null,
        color = null,
        icon = null,
        kind = SureCategoryKind.transfer;

  /// A split-parent badge.
  const SureCategoryIcon.split({super.key, this.size = rowSize})
      : name = null,
        color = null,
        icon = null,
        kind = SureCategoryKind.split;

  static const double rowSize = 28;
  static const double heroSize = 48;
  static const double dotSize = 16;

  /// The category name (used for the first-letter fallback). Null or empty
  /// with no [kind] means uncategorized.
  final String? name;

  /// The server's `#rrggbb` category color.
  final String? color;

  /// The server's Lucide icon name (`category.icon`).
  final String? icon;

  /// Overrides what the badge stands for. When null it is
  /// [SureCategoryKind.category] if [name] is set, else uncategorized.
  final SureCategoryKind? kind;

  final double size;

  SureCategoryKind get _kind =>
      kind ??
      ((name == null || name!.trim().isEmpty)
          ? SureCategoryKind.uncategorized
          : SureCategoryKind.category);

  @override
  Widget build(BuildContext context) {
    final colors = SureColors.of(context);
    final palette = colors.palette;
    final kind = _kind;
    final isDot = size <= dotSize;
    final categoryColor =
        kind == SureCategoryKind.category ? parseCategoryColor(color) : null;
    final tint = categoryColor ?? palette.textSecondary;

    final Color fill;
    if (isDot) {
      fill = categoryColor ?? palette.textSubdued;
    } else if (kind != SureCategoryKind.category) {
      fill = palette.surfaceInset;
    } else {
      fill = tint.withValues(alpha: colors.isDark ? 0.18 : 0.14);
    }

    Widget? glyph;
    if (!isDot) {
      final glyphSize = (size * 0.54).roundToDouble();
      switch (kind) {
        case SureCategoryKind.uncategorized:
          glyph = SureIcon(SureIcons.circleQuestionMark,
              size: glyphSize, color: palette.textSecondary);
        case SureCategoryKind.transfer:
          glyph = SureIcon(SureIcons.arrowLeftRight,
              size: glyphSize, color: palette.textSecondary);
        case SureCategoryKind.split:
          glyph = SureIcon(SureIcons.split,
              size: glyphSize, color: palette.textSecondary);
        case SureCategoryKind.category:
          final asset = SureIcons.forCategory(icon);
          if (asset != null) {
            glyph = SureIcon(asset, size: glyphSize, color: tint);
          } else {
            glyph = Text(
              name!.trim().characters.first.toUpperCase(),
              maxLines: 1,
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontSize: (size * 0.46).roundToDouble(),
                height: 1,
                fontWeight: FontWeight.w600,
                color: tint,
              ),
            );
          }
      }
    }

    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
          child: glyph == null ? null : Center(child: glyph),
        ),
      ),
    );
  }
}
