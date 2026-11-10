import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../providers/privacy_provider.dart';
import '../utils/investment_math.dart';
import '../utils/money_masker.dart';
import 'sure_card.dart';

/// Dashboard entry point to the portfolio: the investment and crypto
/// accounts' total value per currency. Tapping it opens the portfolio in
/// [primaryCurrency].
class InvestmentsSummaryCard extends StatelessWidget {
  const InvestmentsSummaryCard({
    super.key,
    required this.accounts,
    required this.onTap,
    this.familyCurrency,
  });

  /// Investment and crypto accounts, in any currency.
  final List<Account> accounts;
  final ValueChanged<String> onTap;
  final String? familyCurrency;

  /// Totals by currency in major units.
  Map<String, double> get totals {
    final totals = <String, double>{};
    for (final account in accounts) {
      totals[account.currency] = (totals[account.currency] ?? 0) +
          (InvestmentMath.parse(account.balance) ?? 0);
    }
    return totals;
  }

  /// The family's currency when it has investments in it, otherwise the
  /// currency with the largest total.
  String get primaryCurrency {
    final totals = this.totals;
    if (familyCurrency != null && totals.containsKey(familyCurrency)) {
      return familyCurrency!;
    }
    return totals.entries
        .reduce((best, entry) => entry.value > best.value ? entry : best)
        .key;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final locale = Localizations.localeOf(context).toString();
    final hidden = context.watch<PrivacyProvider>().hidden;
    final totals = this.totals;
    final primary = primaryCurrency;
    final others = totals.keys.where((currency) => currency != primary).toList()
      ..sort();

    String money(String currency) => MoneyMasker.mask(
          InvestmentMath.formatMoney(totals[currency]!,
              currency: currency, locale: locale),
          hidden: hidden,
        );

    return SureCard(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      onTap: () => onTap(primary),
      child: Semantics(
        button: true,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${l.portfolioTitle} · ${l.portfolioAccountCount(accounts.length)}',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    money(primary),
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  for (final currency in others)
                    Text(
                      '+ ${money(currency)}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
