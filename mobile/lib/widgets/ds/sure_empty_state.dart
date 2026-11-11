import 'package:flutter/material.dart';

import '../../theme/sure_colors.dart';
import '../../theme/sure_tokens.dart';
import '../sure_icon.dart';

/// Centered empty/no-results state: a 52 px inset-fill circle with a Lucide
/// icon, a title (15 pt 600), a body (13 pt `textSecondary`), an optional
/// primary button and an optional secondary text link.
///
/// It paints no panel; wrap it in a SurePanel where the spec shows one.
class SureEmptyState extends StatelessWidget {
  const SureEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
  });

  /// Lucide icon name, e.g. [SureIcons.search].
  final String icon;
  final String title;
  final String? body;

  /// Label of the inverse primary button; shown only with [onPrimary].
  final String? primaryLabel;
  final VoidCallback? onPrimary;

  /// Label of the secondary link; shown only with [onSecondary].
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: palette.surfaceInset,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: SureIcon(icon, size: 24, color: palette.textSecondary),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
          if (body != null) ...[
            const SizedBox(height: 6),
            Text(
              body!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: palette.textSecondary,
              ),
            ),
          ],
          if (primaryLabel != null && onPrimary != null) ...[
            const SizedBox(height: 18),
            TextButton(
              onPressed: onPrimary,
              style: TextButton.styleFrom(
                backgroundColor: palette.buttonPrimary,
                foregroundColor: palette.textInverse,
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(SureTokens.radiusMd),
                ),
              ),
              child: Text(
                primaryLabel!,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          if (secondaryLabel != null && onSecondary != null) ...[
            SizedBox(height: primaryLabel != null ? 6 : 14),
            TextButton(
              onPressed: onSecondary,
              style: TextButton.styleFrom(foregroundColor: palette.link),
              child: Text(
                secondaryLabel!,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
