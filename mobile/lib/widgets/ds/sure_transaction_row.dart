import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/account.dart';
import '../../models/activity_transaction.dart';
import '../../models/offline_transaction.dart';
import '../../models/transaction.dart';
import '../../providers/privacy_provider.dart';
import '../../theme/sure_colors.dart';
import '../../theme/sure_tokens.dart';
import '../../utils/money_masker.dart';
import '../../utils/transaction_amount_display.dart';
import '../money_text.dart';
import '../sure_icon.dart';
import 'sure_category_icon.dart';
import 'sure_swipe_actions.dart';

/// The shared transaction row (Activity, Home "Recent", an account's
/// Transactions tab): a [SureCategoryIcon], the name, "Category · Account"
/// (the account left out with [showAccount] false; "Split"/"Transfer" in
/// place of the category), and a mono amount: expenses `textPrimary` with a
/// minus, income `success` with a plus, transfers `textSecondary`.
///
/// Swipe left reveals Categorize and Delete when [onCategorize] / [onDelete]
/// are set. Long-press calls [onLongPress] (enter multi-select); in
/// [selectionMode] the leading icon becomes a check circle and swiping is off.
/// A pending/failed offline [syncStatus] shows a tiny badge before the amount.
///
/// Amounts are masked when privacy mode is on (from [PrivacyProvider], or
/// [hideAmount] when given).
class SureTransactionRow extends StatelessWidget {
  const SureTransactionRow({
    super.key,
    required this.transaction,
    this.account,
    this.accountName,
    this.accountType,
    this.categoryColor,
    this.categoryIcon,
    this.isTransfer = false,
    this.isSplitParent = false,
    this.showAccount = true,
    this.syncStatus,
    this.hideAmount,
    this.onTap,
    this.onLongPress,
    this.onCategorize,
    this.onDelete,
    this.selectionMode = false,
    this.selected = false,
  });

  /// A row for an `/api/v1/transactions` entry, which carries its account
  /// name and type, category color and icon, and split/transfer flags.
  factory SureTransactionRow.activity(
    ActivityTransaction row, {
    Key? key,
    Account? account,
    bool showAccount = true,
    bool? hideAmount,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    VoidCallback? onCategorize,
    VoidCallback? onDelete,
    bool selectionMode = false,
    bool selected = false,
  }) {
    return SureTransactionRow(
      key: key,
      transaction: row.transaction,
      account: account,
      accountName: row.accountName,
      accountType: row.accountType,
      categoryColor: row.categoryColor,
      categoryIcon: row.categoryIcon,
      isTransfer: row.isTransfer,
      isSplitParent: row.isSplitParent,
      showAccount: showAccount,
      hideAmount: hideAmount,
      onTap: onTap,
      onLongPress: onLongPress,
      onCategorize: onCategorize,
      onDelete: onDelete,
      selectionMode: selectionMode,
      selected: selected,
    );
  }

  final Transaction transaction;

  /// The row's account, when loaded. Decides the amount's sign convention
  /// and supplies the account name when [accountName] is null.
  final Account? account;
  final String? accountName;

  /// The account's `accountable_type` (snake case), used for the sign when
  /// [account] is null.
  final String? accountType;
  final String? categoryColor;
  final String? categoryIcon;
  final bool isTransfer;
  final bool isSplitParent;

  /// Include the account in the subtitle. Off on an account's own page.
  final bool showAccount;

  /// The offline sync state, for rows from the local store. Pending and
  /// failed states show a badge; null or synced shows none.
  final SyncStatus? syncStatus;

  /// Masks the amount. Null reads [PrivacyProvider] (unmasked without one).
  final bool? hideAmount;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Swipe action "Categorize". Hidden when null.
  final VoidCallback? onCategorize;

  /// Swipe action "Delete". Hidden when null. The caller confirms.
  final VoidCallback? onDelete;

  final bool selectionMode;
  final bool selected;

  bool _privacyHidden(BuildContext context) {
    if (hideAmount != null) return hideAmount!;
    try {
      return context.select<PrivacyProvider, bool>((p) => p.hidden);
    } on ProviderNotFoundException {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final hidden = _privacyHidden(context);

    final display = TransactionAmountDisplay.of(
      transaction.amount,
      isAsset: account?.isAsset ??
          TransactionAmountDisplay.assetAccountTypes.contains(accountType),
      isLiability: account?.isLiability ??
          TransactionAmountDisplay.liabilityAccountTypes.contains(accountType),
    );

    final String amountText;
    final Color amountColor;
    if (isTransfer) {
      amountText = display.text;
      amountColor = palette.textSecondary;
    } else {
      switch (display.trend) {
        case MoneyTrend.inflow:
          amountText = '+${display.text}';
          amountColor = palette.success;
        case MoneyTrend.outflow:
          amountText = display.text;
          amountColor = palette.textPrimary;
        case MoneyTrend.neutral:
          amountText = display.text;
          amountColor = palette.textSubdued;
      }
    }

    final categoryName = transaction.categoryName?.trim();
    final hasCategory = categoryName != null && categoryName.isNotEmpty;
    final String kindLabel;
    if (isSplitParent) {
      kindLabel = l.dsSplit;
    } else if (isTransfer) {
      kindLabel = l.dsTransfer;
    } else {
      kindLabel = hasCategory ? categoryName : l.dsUncategorized;
    }
    final accountLabel = (accountName ?? account?.name)?.trim();
    final subtitle = [
      kindLabel,
      if (showAccount && accountLabel != null && accountLabel.isNotEmpty)
        accountLabel,
    ].join(' · ');

    final Widget leading;
    if (selectionMode) {
      leading = _SelectionCircle(selected: selected);
    } else if (isSplitParent) {
      leading = const SureCategoryIcon.split();
    } else if (isTransfer) {
      leading = const SureCategoryIcon.transfer();
    } else {
      leading = SureCategoryIcon(
        name: categoryName,
        color: categoryColor,
        icon: categoryIcon,
      );
    }

    final badge = _badge(l, palette);

    Widget row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transaction.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.25,
                      fontWeight: SureTokens.weightMedium,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.25,
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // The amount never ellipsizes; past half the row it scales down
            // instead, so the name keeps room.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.5,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerEnd,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (badge != null) ...[badge, const SizedBox(width: 6)],
                    MoneyText(
                      MoneyMasker.mask(amountText, hidden: hidden),
                      trend: display.trend,
                      color: amountColor,
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: SureTokens.weightMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    row = Material(
      color: selected ? palette.containerInset : palette.container,
      child: InkWell(onTap: onTap, onLongPress: onLongPress, child: row),
    );

    return SureSwipeActions(
      enabled: !selectionMode,
      actions: [
        if (onCategorize != null)
          SureSwipeAction(
            label: l.dsCategorize,
            color: palette.info,
            onPressed: onCategorize!,
          ),
        if (onDelete != null)
          SureSwipeAction(
            label: l.dsDelete,
            color: palette.destructive,
            onPressed: onDelete!,
          ),
      ],
      child: row,
    );
  }

  Widget? _badge(AppLocalizations l, SureTokenPalette palette) {
    final String label;
    final Color color;
    switch (syncStatus) {
      case SyncStatus.pending:
      case SyncStatus.pendingDelete:
        label = l.dsPending;
        color = palette.warning;
      case SyncStatus.failed:
        label = l.dsFailed;
        color = palette.destructive;
      case SyncStatus.synced:
      case null:
        return null;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _SelectionCircle extends StatelessWidget {
  const _SelectionCircle({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return Semantics(
      checked: selected,
      child: Container(
        width: SureCategoryIcon.rowSize,
        height: SureCategoryIcon.rowSize,
        alignment: Alignment.center,
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: selected ? palette.link : null,
            border: selected
                ? null
                : Border.all(color: palette.textSubdued, width: 1.5),
          ),
          alignment: Alignment.center,
          child: selected
              ? const SureIcon(SureIcons.check,
                  size: 14, color: Color(0xFFFFFFFF))
              : null,
        ),
      ),
    );
  }
}
