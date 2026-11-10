import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/accounts_provider.dart';
import '../providers/auth_provider.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_spacing.dart';
import '../widgets/investments_summary_card.dart';
import '../widgets/sure_button.dart';
import '../widgets/sure_icon.dart';
import 'portfolio_screen.dart';

/// The Invest tab: the [PortfolioScreen] over the investment and crypto
/// accounts in [AccountsProvider] (loaded by the dashboard).
class InvestScreen extends StatelessWidget {
  const InvestScreen({super.key});

  Future<void> _reload(BuildContext context) async {
    final authProvider = context.read<AuthProvider>();
    final accountsProvider = context.read<AccountsProvider>();
    final accessToken = await authProvider.getValidAccessToken();
    if (accessToken == null) {
      await authProvider.logout();
      return;
    }
    await accountsProvider.fetchAccounts(accessToken: accessToken);
    if (accountsProvider.errorMessage == 'unauthorized') {
      await authProvider.logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final accountsProvider = context.watch<AccountsProvider>();
    final accounts = accountsProvider.accounts
        .where((account) =>
            account.accountType == 'investment' ||
            account.accountType == 'crypto')
        .toList();

    // Loading and empty states get the same titled bar PortfolioScreen has.
    Widget titled(Widget body) => Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: Text(l.portfolioTitle),
          ),
          body: body,
        );

    if (accounts.isEmpty &&
        (accountsProvider.isInitializing || accountsProvider.isLoading)) {
      return titled(const Center(child: CircularProgressIndicator()));
    }

    if (accounts.isEmpty) {
      final failed = accountsProvider.errorMessage != null &&
          accountsProvider.errorMessage != 'unauthorized';
      return titled(RefreshIndicator(
        onRefresh: () => _reload(context),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(SureSpacing.xxxl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SureIcon(
                        failed ? SureIcons.circleAlert : SureIcons.trendingUp,
                        size: 64,
                        color:
                            failed ? palette.destructive : palette.textSubdued,
                      ),
                      const SizedBox(height: SureSpacing.xl),
                      Text(
                        failed
                            ? l.shellInvestLoadFailed
                            : l.shellInvestEmptyTitle,
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      if (!failed) ...[
                        const SizedBox(height: SureSpacing.md),
                        Text(
                          l.shellInvestEmptyBody,
                          style: TextStyle(color: palette.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: SureSpacing.xxxl),
                      SureButton(
                        label: failed ? l.commonTryAgain : l.commonRefresh,
                        onPressed: () => _reload(context),
                        leading: const SureIcon(SureIcons.refresh, size: 18),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
    }

    // Same rule as the dashboard's Investments card: the family currency when
    // it has investments, otherwise the currency with the largest total.
    final currency = InvestmentsSummaryCard(
      accounts: accounts,
      familyCurrency: accountsProvider.familyCurrency,
      onTap: (_) {},
    ).primaryCurrency;

    return PortfolioScreen(
      // A new account set or currency rebuilds the portfolio from scratch.
      key: ValueKey('$currency:${accounts.map((a) => a.id).join(',')}'),
      accounts: accounts,
      initialCurrency: currency,
    );
  }
}
