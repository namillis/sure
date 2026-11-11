import 'package:flutter/material.dart';

import '../../theme/sure_colors.dart';
import '../../theme/sure_tokens.dart';
import '../../utils/sure_dates.dart';
import '../money_text.dart';

/// A day section header for transaction lists: the date label ("Today",
/// "Yesterday", "Nov 9") on the left and the day's net total in mono on the
/// right, both `textSecondary`. Sits on the page background, so it can be
/// pinned (see [SureDayHeader.height]).
class SureDayHeader extends StatelessWidget {
  const SureDayHeader({
    super.key,
    required this.label,
    this.total,
    this.background = true,
  });

  /// A header for [day], labeled with [SureDates.relativeDayOf].
  SureDayHeader.forDay(
    BuildContext context,
    DateTime day, {
    super.key,
    this.total,
    this.background = true,
    DateTime? now,
  }) : label = SureDates.relativeDayOf(context, day, now: now);

  /// Fixed height, for a pinned SliverPersistentHeader.
  static const double height = 36;

  final String label;

  /// The pre-formatted (and, in privacy mode, masked) day total.
  final String? total;

  /// Paint the page color behind the header (needed when it is pinned over
  /// scrolling content).
  final bool background;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return Semantics(
      header: true,
      child: Container(
        height: height,
        color: background ? palette.surface : null,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        alignment: Alignment.bottomLeft,
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
            if (total != null) ...[
              const SizedBox(width: 12),
              MoneyText(
                total!,
                trend: MoneyTrend.neutral,
                color: palette.textSecondary,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: SureTokens.weightMedium,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
