import 'package:flutter/material.dart';

import '../theme/sure_colors.dart';
import '../theme/sure_tokens.dart';
import 'ds/sure_panel.dart';
import 'ds/sure_section_header.dart';
import 'sure_icon.dart';

/// Sure grouped list: a [SureSectionHeader] (optional) over a
/// [SurePanel.rows] of [SureListRow]s, with inset hairlines between rows.
///
/// ```dart
/// SureListGroup(
///   header: 'Tools',
///   children: [
///     SureListRow(title: 'Calendar', subtitle: 'Monthly view', showChevron: true, onTap: ...),
///     SureListRow(title: 'Recent', showChevron: true, onTap: ...),
///   ],
/// )
/// ```
class SureListGroup extends StatelessWidget {
  const SureListGroup({
    super.key,
    required this.children,
    this.header,
    this.margin,
    this.dividerIndent = SurePanel.defaultDividerIndent,
  });

  /// Rows to stack — typically [SureListRow]s. Dividers are inserted between
  /// them automatically (never before the first or after the last).
  final List<Widget> children;

  /// Optional section label rendered above the group, in sentence case.
  final String? header;

  /// Outer spacing around the group (e.g. separation between sections).
  final EdgeInsetsGeometry? margin;

  /// Start inset of the dividers. Use [SurePanel.iconRowDividerIndent] when
  /// the rows have a 28 px leading icon.
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    final group = SurePanel.rows(
      dividerIndent: dividerIndent,
      children: children,
    );

    final content = header == null
        ? group
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SureSectionHeader(
                label: header!,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              ),
              group,
            ],
          );

    if (margin == null) return content;
    return Padding(padding: margin!, child: content);
  }
}

/// A row for a [SurePanel] / [SureListGroup]: optional [leading] (an icon or
/// SureCategoryIcon), a [title] and optional [subtitle] (both ellipsized), and
/// a trailing area: an explicit [trailing] widget, or a [value] text and/or a
/// chevron ([showChevron]).
///
/// Min height 44 for one-line rows and 52 for two-line rows, 14 px horizontal
/// padding. The row paints no background of its own; the enclosing panel
/// supplies the chrome, dividers and corner clipping. With [onTap] the whole
/// row is one button.
class SureListRow extends StatelessWidget {
  const SureListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.value,
    this.onTap,
    this.onLongPress,
    this.showChevron = false,
    this.destructive = false,
    this.titleColor,
    this.subtitleMaxLines = 2,
  });

  final String title;
  final String? subtitle;

  /// Leading widget (e.g. a SureCategoryIcon or a SureIcon).
  final Widget? leading;

  /// Trailing widget (e.g. a MoneyText or a switch). Takes precedence over
  /// [value] and [showChevron].
  final Widget? trailing;

  /// A trailing value in `textSecondary` (e.g. "Groceries"), shown before the
  /// chevron when [showChevron] is set.
  final String? value;

  /// When non-null, the row is tappable.
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Show a chevron disclosure indicator on the trailing edge. Ignored when an
  /// explicit [trailing] is provided.
  final bool showChevron;

  /// Render the title in the destructive token (for delete/reset actions).
  final bool destructive;

  /// Overrides the title color (e.g. `link` for "Open on the web").
  final Color? titleColor;
  final int subtitleMaxLines;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;

    Widget? trailingWidget = trailing;
    if (trailingWidget == null && (value != null || showChevron)) {
      trailingWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.45,
              ),
              child: Text(
                value!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, color: palette.textSecondary),
              ),
            ),
          if (value != null && showChevron) const SizedBox(width: 4),
          if (showChevron)
            SureIcon(
              SureIcons.chevronRight,
              size: 18,
              color: palette.textSubdued,
            ),
        ],
      );
    }

    final hasSubtitle = subtitle != null && subtitle!.isNotEmpty;
    Widget content = ConstrainedBox(
      constraints: BoxConstraints(minHeight: hasSubtitle ? 52 : 44),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.25,
                      fontWeight: SureTokens.weightMedium,
                      color: titleColor ??
                          (destructive
                              ? palette.destructive
                              : palette.textPrimary),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (hasSubtitle) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.25,
                        color: palette.textSecondary,
                      ),
                      maxLines: subtitleMaxLines,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (trailingWidget != null) ...[
              const SizedBox(width: 12),
              trailingWidget,
            ],
          ],
        ),
      ),
    );

    if (onTap != null || onLongPress != null) {
      // MergeSemantics + Semantics(button) restores the button/enabled flags a
      // Material ListTile exposes, so screen readers announce the whole row as
      // one button.
      content = MergeSemantics(
        child: Semantics(
          button: true,
          enabled: true,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              child: content,
            ),
          ),
        ),
      );
    }

    return content;
  }
}
