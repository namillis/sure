import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/budget.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_tokens.dart';
import '../utils/money_masker.dart';
import 'budget_progress_bar.dart';
import 'ds/ds.dart';

/// One budget category line in the Plan tab's Categories panel: the
/// category's round icon, its name, "spent / limit" in mono on the right, a
/// 4 px progress bar under them (success, warning at 90%, destructive when
/// over) and, when over, an "Over by $90" line. A category without a limit
/// shows "$155 no limit" and no bar. Rollover and shared-budget info sit on a
/// small line under it. Subcategories render indented under their parent.
class BudgetCategoryRow extends StatelessWidget {
  const BudgetCategoryRow({
    super.key,
    required this.budgetCategory,
    required this.hideAmounts,
    this.onTap,
    this.indented = false,
  });

  final BudgetCategory budgetCategory;
  final bool hideAmounts;
  final VoidCallback? onTap;
  final bool indented;

  /// Start inset of a subcategory row, so its icon lines up under the
  /// parent's name.
  static const double indent = 40;

  String _money(String? formatted) =>
      MoneyMasker.mask(formatted ?? '--', hidden: hideAmounts);

  /// The API formats an overspend as a negative amount; show its magnitude.
  static String _abs(String formatted) =>
      formatted.replaceFirst(RegExp('^[-\u2212]'), '');

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final bc = budgetCategory;
    final derived = bc.hasDerivedAmounts;
    final over = derived && bc.isOverBudget;
    final shared = derived && bc.inheritsParentBudget;
    final limited = derived && bc.isBudgeted && !bc.inheritsParentBudget;
    final noLimit = derived && !bc.isBudgeted && !bc.inheritsParentBudget;

    final mono = SureMoney.tabular(TextStyle(
      fontSize: 13,
      fontWeight: SureTokens.weightMedium,
      color: palette.textPrimary,
    ));
    final subdued = mono.copyWith(
      color: palette.textSubdued,
      fontWeight: FontWeight.w400,
    );

    // "$410 / $600", "$155 no limit", or just the spend for a shared line.
    final List<InlineSpan> amount;
    if (!derived) {
      // The index payload has no spending yet: show the limit alone.
      amount = [TextSpan(text: _money(bc.displayBudgetedSpending), style: subdued)];
    } else if (limited) {
      amount = [
        TextSpan(text: _money(bc.actualSpending)),
        TextSpan(
          text: ' / ${_money(bc.displayBudgetedSpending)}',
          style: subdued,
        ),
      ];
    } else if (noLimit) {
      amount = [
        TextSpan(text: _money(bc.actualSpending)),
        TextSpan(text: ' ${l.ds2pNoLimit}', style: subdued),
      ];
    } else {
      amount = [TextSpan(text: _money(bc.actualSpending))];
    }

    final notes = <Widget>[
      if (limited && over)
        _SubLine(
          l.ds2pOverBy(_money(_abs(bc.availableToSpend ?? ''))),
          color: palette.destructive,
          weight: SureTokens.weightMedium,
        ),
      if (shared)
        _SubLine(
          l.budgetsSharedBudget,
          color: over ? palette.destructive : palette.textSubdued,
        ),
      if (derived && !shared && (bc.rolledOverAmountCents ?? 0) > 0)
        _SubLine(
          l.budgetsRolledOver(_money(bc.rolledOverAmount)),
          color: palette.textSubdued,
        ),
    ];

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            14 + (indented ? indent : 0),
            11,
            14,
            11,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SureCategoryIcon(
                name: bc.name,
                color: bc.category.color,
                icon: bc.category.lucideIcon,
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
                              bc.name,
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
                              TextSpan(style: mono, children: amount),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (limited || shared) ...[
                      const SizedBox(height: 6),
                      BudgetProgressBar(
                        fraction: bc.spentFraction,
                        overBudget: over,
                        nearLimit: bc.isNearLimit,
                        hidden: hideAmounts,
                        height: 4,
                      ),
                    ],
                    if (notes.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      ...notes,
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubLine extends StatelessWidget {
  const _SubLine(this.text, {required this.color, this.weight});

  final String text;
  final Color color;
  final FontWeight? weight;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: SureMoney.tabular(
        TextStyle(fontSize: 12, color: color, fontWeight: weight),
      ),
    );
  }
}
