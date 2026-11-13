import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/budget.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_tokens.dart';
import '../utils/money_masker.dart';
import 'budget_progress_bar.dart';
import 'ds/ds.dart';

/// The Budget hero: "$2,140.00 left" (or "$120.00 over"), the mono line
/// "$2,860.00 spent of $5,000.00 · 19 days left" (days left only for the
/// current period) and a 6 px progress bar (success, warning at 90%,
/// destructive when over).
class BudgetSummaryCard extends StatelessWidget {
  const BudgetSummaryCard({
    super.key,
    required this.budget,
    required this.hideAmounts,
    this.now,
    this.onEditTotals,
  });

  final Budget budget;
  final bool hideAmounts;

  /// Today, for the days-left count. Defaults to [DateTime.now].
  final DateTime? now;

  /// Shows an "Edit totals" link under the bar (Sure+ `budgets.write`).
  final VoidCallback? onEditTotals;

  String _money(String? formatted) =>
      MoneyMasker.mask(formatted ?? '--', hidden: hideAmounts);

  /// Days from today to the period's last day, or null when [budget] is not
  /// the current period.
  static int? daysLeft(Budget budget, DateTime now) {
    if (!budget.current) return null;
    final today = DateTime.utc(now.year, now.month, now.day);
    final end = DateTime.utc(
        budget.endDate.year, budget.endDate.month, budget.endDate.day);
    final days = end.difference(today).inDays;
    return days < 0 ? null : days;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final over = budget.isOverBudget;
    final available = budget.availableToSpend;
    final heroAmount = _money(
      over ? available?.replaceFirst(RegExp('^[-\u2212]'), '') : available,
    );
    final days = daysLeft(budget, now ?? DateTime.now());
    final subtitle = [
      l.ds2pSpentOf(
        _money(budget.actualSpending),
        _money(budget.budgetedSpending),
      ),
      if (days != null) l.ds2pDaysLeft(days),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            key: const ValueKey('budgetHeroAmount'),
            TextSpan(children: [
              TextSpan(
                text: heroAmount,
                style: SureMoney.tabular(TextStyle(
                  fontSize: 32,
                  height: 1.2,
                  fontWeight: SureTokens.weightSemibold,
                  color: over ? palette.destructive : palette.textPrimary,
                )),
              ),
              TextSpan(
                text: ' ${over ? l.ds2pOver : l.ds2pLeft}',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w400,
                  color: palette.textSecondary,
                ),
              ),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            key: const ValueKey('budgetHeroSubtitle'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: SureMoney.tabular(TextStyle(
              fontSize: 13,
              color: palette.textSecondary,
            )),
          ),
          if (budget.initialized) ...[
            const SizedBox(height: 12),
            BudgetProgressBar(
              fraction: budget.spentFraction,
              overBudget: over,
              nearLimit: budget.isNearLimit,
              hidden: hideAmounts,
            ),
          ],
          if (onEditTotals != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: const ValueKey('budgetEditTotals'),
                onPressed: onEditTotals,
                style: TextButton.styleFrom(
                  foregroundColor: palette.link,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.padded,
                ),
                child: Text(
                  l.spbEditTotals,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: SureTokens.weightMedium,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The month's income as a row in the Categories style: "$5,200 / $5,000"
/// (actual / expected) with a success bar toward the expected amount.
class BudgetIncomeRow extends StatelessWidget {
  const BudgetIncomeRow({
    super.key,
    required this.budget,
    required this.hideAmounts,
  });

  final Budget budget;
  final bool hideAmounts;

  String _money(String? formatted) =>
      MoneyMasker.mask(formatted ?? '--', hidden: hideAmounts);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = SureColors.of(context);
    final palette = colors.palette;
    final expected = budget.expectedIncome;
    final expectedCents = budget.expectedIncomeCents ?? 0;
    final mono = SureMoney.tabular(TextStyle(
      fontSize: 13,
      fontWeight: SureTokens.weightMedium,
      color: palette.success,
    ));

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: SureCategoryIcon.rowSize,
            height: SureCategoryIcon.rowSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.success
                  .withValues(alpha: colors.isDark ? 0.18 : 0.14),
              shape: BoxShape.circle,
            ),
            child: SureIcon(SureIcons.trendingUp,
                size: 15, color: palette.success),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: SureCategoryIcon.rowSize,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l.budgetsIncome,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: SureTokens.weightMedium,
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text.rich(
                          key: const ValueKey('budgetIncomeAmount'),
                          TextSpan(style: mono, children: [
                            TextSpan(text: _money(budget.actualIncome)),
                            if (expected != null)
                              TextSpan(
                                text: ' / ${_money(expected)}',
                                style: mono.copyWith(
                                  color: palette.textSubdued,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                          ]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                ),
                if (expectedCents > 0) ...[
                  const SizedBox(height: 6),
                  BudgetProgressBar(
                    fraction: (budget.actualIncomeCents ?? 0) / expectedCents,
                    hidden: hideAmounts,
                    height: 4,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
