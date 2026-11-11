import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../providers/privacy_provider.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_tokens.dart';
import '../utils/investment_math.dart';
import '../utils/money_masker.dart';
import 'ds/sure_swipe_actions.dart';
import 'money_text.dart';
import 'sure_icon.dart';

/// Account types in the order Home lists their groups: assets, then
/// liabilities (the web's balance sheet order). Unknown types go last.
const List<String> accountTypeOrder = [
  'depository',
  'investment',
  'crypto',
  'property',
  'vehicle',
  'other_asset',
  'credit_card',
  'loan',
  'other_liability',
];

/// Lucide icon for an account type.
String accountTypeIconName(String accountType) {
  switch (accountType) {
    case 'depository':
      return SureIcons.landmark;
    case 'credit_card':
      return SureIcons.creditCard;
    case 'investment':
      return SureIcons.trendingUp;
    case 'loan':
      return SureIcons.receipt;
    case 'property':
      return SureIcons.house;
    case 'vehicle':
      return SureIcons.car;
    case 'crypto':
      return SureIcons.bitcoin;
    case 'other_asset':
      return SureIcons.shapes;
    case 'other_liability':
      return SureIcons.handCoins;
    default:
      return SureIcons.wallet;
  }
}

/// Plural group name for an account type ("Cash", "Credit cards").
String accountGroupLabel(AppLocalizations l, String accountType) {
  switch (accountType) {
    case 'depository':
      return l.dshTypeDepository;
    case 'credit_card':
      return l.dshTypeCreditCard;
    case 'investment':
      return l.dshTypeInvestment;
    case 'crypto':
      return l.dshTypeCrypto;
    case 'property':
      return l.dshTypeProperty;
    case 'vehicle':
      return l.dshTypeVehicle;
    case 'other_asset':
      return l.dshTypeOtherAsset;
    case 'loan':
      return l.dshTypeLoan;
    case 'other_liability':
      return l.dshTypeOtherLiability;
    default:
      return accountType;
  }
}

/// The account's balance in major units of its own currency: the server's
/// formatted balance parsed back (as the Home investments total did), else
/// its minor units.
double accountBalanceValue(Account account) {
  final parsed = InvestmentMath.parse(account.balance);
  if (parsed != null) return parsed;
  final cents = account.balanceCents;
  if (cents == null) return 0;
  return InvestmentMath.fromMinorUnits(cents, currency: account.currency);
}

/// Whether the account has a zero balance (collapsed as "empty").
bool isEmptyAccount(Account account) => accountBalanceValue(account) == 0;

/// The account type badge: a 28 px neutral inset circle with the type's
/// Lucide glyph in `textSecondary`.
class AccountTypeIcon extends StatelessWidget {
  const AccountTypeIcon({super.key, required this.accountType});

  final String accountType;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return ExcludeSemantics(
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: palette.surfaceInset,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: SureIcon(
          accountTypeIconName(accountType),
          size: 15,
          color: palette.textSecondary,
        ),
      ),
    );
  }
}

/// One account as a row for a SurePanel: type icon, name, optional
/// institution, and the balance in mono (liabilities as a negative amount in
/// `destructive`). Tap opens the account; swiping left reveals "Add"
/// ([onSwipe], the quick new-transaction shortcut).
class AccountCard extends StatelessWidget {
  final Account account;
  final VoidCallback? onTap;
  final VoidCallback? onSwipe;

  const AccountCard({
    super.key,
    required this.account,
    this.onTap,
    this.onSwipe,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final hideAmounts = context.watch<PrivacyProvider>().hidden;
    final locale = Localizations.localeOf(context).toString();

    final value = accountBalanceValue(account);
    final signed = account.isLiability ? -value : value;
    final balance = InvestmentMath.formatMoney(
      signed,
      currency: account.currency,
      locale: locale,
    );
    final institution = account.institutionName?.trim();

    Widget row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            AccountTypeIcon(accountType: account.accountType),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.25,
                      fontWeight: SureTokens.weightMedium,
                      color: palette.textPrimary,
                    ),
                  ),
                  if (institution != null && institution.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      institution,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.25,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.5,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerEnd,
                child: MoneyText(
                  MoneyMasker.mask(balance, hidden: hideAmounts),
                  trend: account.isLiability
                      ? MoneyTrend.outflow
                      : MoneyTrend.inflow,
                  color: account.isLiability
                      ? palette.destructive
                      : palette.textPrimary,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: SureTokens.weightMedium,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    row = Material(
      color: palette.container,
      child: InkWell(onTap: onTap, child: row),
    );

    if (onSwipe == null) return row;
    return SureSwipeActions(
      actions: [
        SureSwipeAction(
          label: l.dshAddTransaction,
          color: palette.info,
          onPressed: onSwipe!,
        ),
      ],
      child: row,
    );
  }
}
