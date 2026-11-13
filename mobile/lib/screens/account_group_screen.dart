import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../providers/accounts_provider.dart';
import '../providers/server_features_provider.dart';
import '../theme/sure_colors.dart';
import '../widgets/account_card.dart';
import '../widgets/ds/ds.dart';
import 'account_form_sheet.dart';
import 'transaction_form_screen.dart';
import 'transactions_list_screen.dart';

/// The accounts of one type, totaled per currency (liabilities negative).
class AccountGroup {
  AccountGroup._({
    required this.accountType,
    required this.accounts,
    required this.emptyCount,
    required this.primaryCurrency,
    required this.totals,
  });

  /// Groups the asset and liability [accounts] by type, in
  /// [accountTypeOrder] (unknown types last, by name). Within a group,
  /// accounts are largest balance first and zero-balance accounts last.
  static List<AccountGroup> build(
    List<Account> accounts, {
    required String? mainCurrency,
  }) {
    final byType = <String, List<Account>>{};
    for (final account in accounts) {
      if (!account.isAsset && !account.isLiability) continue;
      byType.putIfAbsent(account.accountType, () => []).add(account);
    }
    int rank(String type) {
      final i = accountTypeOrder.indexOf(type);
      return i < 0 ? accountTypeOrder.length : i;
    }

    final types = byType.keys.toList()
      ..sort((a, b) {
        final byRank = rank(a).compareTo(rank(b));
        return byRank != 0 ? byRank : a.compareTo(b);
      });
    return [
      for (final type in types) _group(type, byType[type]!, mainCurrency),
    ];
  }

  static AccountGroup _group(
    String type,
    List<Account> accounts,
    String? mainCurrency,
  ) {
    final sorted = [...accounts]..sort((a, b) {
        final byEmpty =
            (isEmptyAccount(a) ? 1 : 0).compareTo(isEmptyAccount(b) ? 1 : 0);
        if (byEmpty != 0) return byEmpty;
        return accountBalanceValue(b)
            .abs()
            .compareTo(accountBalanceValue(a).abs());
      });

    final totals = <String, double>{};
    final counts = <String, int>{};
    for (final a in accounts) {
      final value = accountBalanceValue(a);
      totals[a.currency] =
          (totals[a.currency] ?? 0) + (a.isLiability ? -value : value);
      counts[a.currency] = (counts[a.currency] ?? 0) + 1;
    }

    // The main currency when the group has any; otherwise the currency most
    // of its accounts use (alphabetical on a tie).
    final String primary;
    if (mainCurrency != null && totals.containsKey(mainCurrency)) {
      primary = mainCurrency;
    } else {
      primary = (counts.entries.toList()
            ..sort((a, b) {
              final byCount = b.value.compareTo(a.value);
              return byCount != 0 ? byCount : a.key.compareTo(b.key);
            }))
          .first
          .key;
    }

    return AccountGroup._(
      accountType: type,
      accounts: sorted,
      emptyCount: accounts.where(isEmptyAccount).length,
      primaryCurrency: primary,
      totals: totals,
    );
  }

  final String accountType;
  final List<Account> accounts;
  final int emptyCount;

  /// The currency of the group's headline total.
  final String primaryCurrency;

  /// Signed totals by currency, in major units.
  final Map<String, double> totals;

  bool get isLiability => accounts.every((a) => a.isLiability);

  double get primaryTotal => totals[primaryCurrency] ?? 0;

  /// The other currencies, by code.
  List<String> get otherCurrencies =>
      totals.keys.where((c) => c != primaryCurrency).toList()..sort();
}

/// One account type's accounts (opened from a Home account group row): a
/// large title with the type, rows of accounts, and the zero-balance ones
/// collapsed at the bottom behind "N empty accounts · Show".
///
/// Tapping an account opens it; swiping left adds a transaction to it. Both
/// call [onReload] afterwards so balances refresh, as on Home.
class AccountGroupScreen extends StatefulWidget {
  const AccountGroupScreen({
    super.key,
    required this.accountType,
    this.onReload,
  });

  final String accountType;

  /// Reloads the accounts (Home's account load); also pull to refresh.
  final Future<void> Function()? onReload;

  @override
  State<AccountGroupScreen> createState() => _AccountGroupScreenState();
}

class _AccountGroupScreenState extends State<AccountGroupScreen> {
  bool _showEmpty = false;

  Future<void> _reload() async => widget.onReload?.call();

  /// The "+" adds an account of this type (Sure+ `accounts.write` only).
  bool _canAdd(BuildContext context) {
    try {
      return context
          .watch<ServerFeaturesProvider>()
          .has(ServerFeaturesProvider.accountsWrite);
    } on ProviderNotFoundException {
      return false;
    }
  }

  Future<void> _openAccount(Account account) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TransactionsListScreen(
          account: account,
          backLabel:
              accountGroupLabel(AppLocalizations.of(context), widget.accountType),
        ),
      ),
    );
    if (mounted) await _reload();
  }

  Future<void> _addTransaction(Account account) async {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final messenger = ScaffoldMessenger.of(context);
    final result = await showTransactionFormSheet(context, account: account);
    if (result != true || !mounted) return;

    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(palette.textInverse),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(l.dashboardRefreshing)),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );
    await _reload();
    if (!mounted) return;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              SureIcon(SureIcons.circleCheck, color: palette.textInverse),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l.dashboardAccountsUpdated,
                  style: TextStyle(color: palette.textInverse),
                ),
              ),
            ],
          ),
          backgroundColor: palette.success,
          duration: const Duration(seconds: 1),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final provider = context.watch<AccountsProvider>();
    final groups = AccountGroup.build(
      provider.accounts.where((a) => a.accountType == widget.accountType).toList(),
      mainCurrency: provider.familyCurrency,
    );
    final accounts = groups.isEmpty ? const <Account>[] : groups.first.accounts;
    final filled = accounts.where((a) => !isEmptyAccount(a)).toList();
    final empty = accounts.where(isEmptyAccount).toList();

    Widget row(Account a) => AccountCard(
          key: ValueKey('account-${a.id}'),
          account: a,
          onTap: () => _openAccount(a),
          onSwipe: () => _addTransaction(a),
        );

    return SureLargeTitleScaffold(
      title: accountGroupLabel(l, widget.accountType),
      actions: [
        if (_canAdd(context))
          SureNavIconButton(
            key: const ValueKey('groupAddAccount'),
            icon: SureIcons.plus,
            semanticLabel: l.dshAddAccount,
            onPressed: () => openAddAccount(
              context,
              initialType: widget.accountType,
              onReload: widget.onReload,
            ),
          ),
      ],
      onRefresh: widget.onReload == null ? null : _reload,
      slivers: [
        if (accounts.isEmpty)
          SliverToBoxAdapter(
            child: SurePanel(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SureEmptyState(
                icon: SureIcons.wallet,
                title: l.dshGroupNoAccounts,
              ),
            ),
          )
        else
          SliverToBoxAdapter(
            child: SurePanel.rows(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              dividerIndent: SurePanel.iconRowDividerIndent,
              children: [
                for (final a in filled) row(a),
                if (_showEmpty)
                  for (final a in empty) row(a),
                if (empty.isNotEmpty)
                  Semantics(
                    button: true,
                    child: InkWell(
                      key: const ValueKey('emptyAccountsToggle'),
                      onTap: () => setState(() => _showEmpty = !_showEmpty),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: '${l.dshEmptyAccounts(empty.length)} · ',
                                style: TextStyle(color: palette.textSubdued),
                              ),
                              TextSpan(
                                text: _showEmpty ? l.dshHide : l.dshShow,
                                style: TextStyle(
                                  color: palette.link,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
