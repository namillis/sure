import 'package:flutter/material.dart';

import '../../theme/sure_colors.dart';
import '../../theme/sure_tokens.dart';

/// A flat Sure panel: `container` fill, 10 px radius, a 1 px hairline drawn as
/// an outline (the web's `shadow-border-xs`), no elevation, children clipped
/// to the rounded corners.
///
/// Use [SurePanel.rows] for a grouped inset list: it puts a hairline divider
/// between consecutive rows, inset to the text start (iOS style).
///
/// ```dart
/// SurePanel(child: Text('Net worth'))
/// SurePanel.rows(children: [SureListRow(title: 'Cash'), SureListRow(title: 'Loans')])
/// ```
class SurePanel extends StatelessWidget {
  /// A panel around one [child].
  const SurePanel({
    super.key,
    required Widget this.child,
    this.padding,
    this.margin,
    this.onTap,
  })  : children = null,
        dividerIndent = 0;

  /// A panel of rows separated by inset hairlines. Empty [children] renders
  /// nothing.
  const SurePanel.rows({
    super.key,
    required List<Widget> this.children,
    this.dividerIndent = SurePanel.defaultDividerIndent,
    this.margin,
  })  : child = null,
        padding = null,
        onTap = null;

  /// Indent that lines a divider up with a row's text when the row has a
  /// 28 px leading icon: 14 px row padding + 28 px icon + 12 px gap.
  static const double iconRowDividerIndent = 54;

  /// Indent that lines a divider up with a row's text when the row has no
  /// leading widget (the 14 px row padding).
  static const double defaultDividerIndent = 14;

  final Widget? child;
  final List<Widget>? children;

  /// Inner padding around [child]. None by default.
  final EdgeInsetsGeometry? padding;

  /// Outer spacing around the panel.
  final EdgeInsetsGeometry? margin;

  /// Makes a single-child panel tappable.
  final VoidCallback? onTap;

  /// Start inset of the dividers between [children].
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    final colors = SureColors.of(context);
    final rows = children;
    if (rows != null && rows.isEmpty) return const SizedBox.shrink();

    Widget content;
    if (rows != null) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) SureHairline(indent: dividerIndent),
            rows[i],
          ],
        ],
      );
    } else {
      content = child!;
      if (padding != null) content = Padding(padding: padding!, child: content);
      if (onTap != null) {
        content = Material(
          type: MaterialType.transparency,
          child: InkWell(onTap: onTap, child: content),
        );
      }
    }

    final panel = DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SureTokens.radiusLg),
        border: Border.all(color: colors.hairline),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SureTokens.radiusLg),
        child: ColoredBox(color: colors.palette.container, child: content),
      ),
    );
    if (margin == null) return panel;
    return Padding(padding: margin!, child: panel);
  }
}

/// A 1 px hairline divider in the Sure hairline color, inset from the start.
class SureHairline extends StatelessWidget {
  const SureHairline({super.key, this.indent = 0, this.endIndent = 0});

  final double indent;
  final double endIndent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsetsDirectional.only(start: indent, end: endIndent),
      child: SizedBox(
        height: 1,
        width: double.infinity,
        child: ColoredBox(color: SureColors.of(context).hairline),
      ),
    );
  }
}

/// A panel that is one centered button, e.g. "Delete transaction": a 44 px
/// row with the [label] at 15 pt weight 500, in `destructive` when
/// [destructive] is set, else `link`. While [busy] it shows a spinner. While
/// busy or with [onPressed] null it is dimmed to 50% and ignores taps.
class SureButtonPanel extends StatelessWidget {
  const SureButtonPanel({
    super.key,
    required this.label,
    required this.onPressed,
    this.destructive = false,
    this.busy = false,
    this.margin,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool destructive;
  final bool busy;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    final enabled = onPressed != null && !busy;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: SurePanel(
        margin: margin,
        onTap: enabled ? onPressed : null,
        child: Semantics(
          button: true,
          enabled: enabled,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Center(
              child: busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: SureTokens.weightMedium,
                        color:
                            destructive ? palette.destructive : palette.link,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
