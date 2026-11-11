import 'package:flutter/material.dart';

import '../../theme/sure_colors.dart';
import '../../theme/sure_tokens.dart';
import '../sure_icon.dart';

/// A section label above a panel: 13 pt `textSecondary` weight 500, sentence
/// case, 16 px above and 6 px below, with an optional trailing action (a
/// "See all" link or a "+" icon).
class SureSectionHeader extends StatelessWidget {
  const SureSectionHeader({
    super.key,
    required this.label,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
    this.actionSemanticLabel,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 6),
  });

  /// The section label, shown as given (no uppercasing).
  final String label;

  /// Text of a trailing link (e.g. "See all"), in the `link` color.
  final String? actionLabel;

  /// Lucide icon name for a trailing icon action (e.g. [SureIcons.plus]).
  /// Ignored when [actionLabel] is set.
  final String? actionIcon;

  /// Screen reader label for an icon action.
  final String? actionSemanticLabel;

  /// Called when the trailing action is tapped. No action shows without it.
  final VoidCallback? onAction;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    Widget? action;
    if (onAction != null && actionLabel != null) {
      action = _Tap(
        onTap: onAction!,
        child: Text(
          actionLabel!,
          maxLines: 1,
          style: TextStyle(
            fontSize: 13,
            fontWeight: SureTokens.weightMedium,
            color: palette.link,
          ),
        ),
      );
    } else if (onAction != null && actionIcon != null) {
      action = Semantics(
        container: true,
        button: true,
        label: actionSemanticLabel,
        child: _Tap(
          onTap: onAction!,
          child: SureIcon(actionIcon!, size: 18, color: palette.link),
        ),
      );
    }

    return Semantics(
      header: true,
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: SureTokens.weightMedium,
                  color: palette.textSecondary,
                ),
              ),
            ),
            if (action != null) ...[const SizedBox(width: 12), action],
          ],
        ),
      ),
    );
  }
}

/// A tap target at least 32 px wide, so a short link or icon is easy to hit
/// without growing the header.
class _Tap extends StatelessWidget {
  const _Tap({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 32),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Center(widthFactor: 1, heightFactor: 1, child: child),
        ),
      ),
    );
  }
}
