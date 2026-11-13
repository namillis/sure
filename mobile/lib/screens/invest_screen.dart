import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/accounts_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/server_features_provider.dart';
import '../utils/portfolio_math.dart';
import '../widgets/ds/ds.dart';
import 'account_form_sheet.dart';
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
    final accountsProvider = context.watch<AccountsProvider>();
    final accounts = accountsProvider.accounts
        .where((account) =>
            account.accountType == 'investment' ||
            account.accountType == 'crypto')
        .toList();

    // Loading, error and empty states share the tab's large title.
    Widget titled(Widget state) => SureLargeTitleScaffold(
          title: l.shellNavInvest,
          automaticallyImplyLeading: false,
          onRefresh: () => _reload(context),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: state),
            ),
          ],
        );

    if (accounts.isEmpty &&
        (accountsProvider.isInitializing || accountsProvider.isLoading)) {
      return titled(const CircularProgressIndicator());
    }

    if (accounts.isEmpty) {
      final failed = accountsProvider.errorMessage != null &&
          accountsProvider.errorMessage != 'unauthorized';
      if (failed) {
        return titled(SureEmptyState(
          key: const ValueKey('investLoadFailed'),
          icon: SureIcons.circleAlert,
          title: l.shellInvestLoadFailed,
          primaryLabel: l.commonTryAgain,
          onPrimary: () => _reload(context),
        ));
      }
      bool native;
      try {
        native = context
            .watch<ServerFeaturesProvider>()
            .has(ServerFeaturesProvider.accountsWrite);
      } on ProviderNotFoundException {
        native = false;
      }
      return titled(SureEmptyState(
        key: const ValueKey('investEmpty'),
        icon: SureIcons.trendingUp,
        title: l.ds2iEmptyTitle,
        body: native ? l.spaInvestEmptyBody : l.ds2iEmptyBody,
        secondaryLabel: native ? l.dshAddAccount : l.shellOpenOnWeb,
        onSecondary: () => openAddAccount(context),
      ));
    }

    final currency = PortfolioMath.primaryCurrency(
      accounts,
      familyCurrency: accountsProvider.familyCurrency,
    )!;

    return PortfolioScreen(
      // A new account set or currency rebuilds the portfolio from scratch.
      key: ValueKey('$currency:${accounts.map((a) => a.id).join(',')}'),
      accounts: accounts,
      initialCurrency: currency,
    );
  }
}
