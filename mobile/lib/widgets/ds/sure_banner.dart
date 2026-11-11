import 'package:flutter/material.dart';

import '../../theme/sure_colors.dart';
import '../../theme/sure_tokens.dart';
import '../sure_icon.dart';

/// A full-width rounded one-line notice (offline, warning): a ~15% `warning`
/// fill, a warning icon and one ellipsized line of text, with an optional
/// trailing action link.
class SureBanner extends StatelessWidget {
  const SureBanner({
    super.key,
    required this.message,
    this.icon = SureIcons.triangleAlert,
    this.actionLabel,
    this.onAction,
    this.onTap,
    this.margin,
  });

  final String message;

  /// Lucide icon name. Use [SureIcons.cloudOff] for offline.
  final String icon;

  /// Trailing link (e.g. "Sync now"); shown only with [onAction].
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Makes the whole banner tappable.
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    final color = palette.warning;
    Widget banner = Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(SureTokens.radiusLg),
      ),
      child: Row(
        children: [
          SureIcon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: SureTokens.weightMedium,
                color: palette.textPrimary,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  actionLabel!,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: palette.link,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
    if (onTap != null) {
      banner = Semantics(
        button: true,
        child: GestureDetector(onTap: onTap, child: banner),
      );
    }
    if (margin == null) return banner;
    return Padding(padding: margin!, child: banner);
  }
}
