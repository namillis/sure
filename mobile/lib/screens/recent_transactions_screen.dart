import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/transaction.dart';
import '../providers/accounts_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/transactions_provider.dart';
import '../widgets/ds/ds.dart';

/// The newest transactions across every account, from the local store
/// (synced when empty or on pull-to-refresh), grouped by day like Activity.
/// Chips pick how many to show.
class RecentTransactionsScreen extends StatefulWidget {
  const RecentTransactionsScreen({super.key});

  static const limitOptions = [10, 20, 50, 100];

  /// The newest [limit] of [transactions], newest first. Rows with an
  /// unreadable date keep their place relative to each other.
  static List<Transaction> newest(List<Transaction> transactions, int limit) {
    final sorted = List<Transaction>.from(transactions);
    sorted.sort((a, b) {
      final dateA = DateTime.tryParse(a.date);
      final dateB = DateTime.tryParse(b.date);
      if (dateA == null || dateB == null) return 0;
      return dateB.compareTo(dateA);
    });
    return sorted.take(limit).toList();
  }

  /// Consecutive rows of [transactions] on the same calendar day.
  static List<({DateTime? day, String raw, List<Transaction> rows})> byDay(
      List<Transaction> transactions) {
    final days = <({DateTime? day, String raw, List<Transaction> rows})>[];
    for (final t in transactions) {
      final day = SureDates.parseDay(t.date);
      final key = day?.toIso8601String() ?? t.date;
      final lastKey = days.isEmpty
          ? null
          : (days.last.day?.toIso8601String() ?? days.last.raw);
      if (lastKey == key) {
        days.last.rows.add(t);
      } else {
        days.add((day: day, raw: t.date, rows: [t]));
      }
    }
    return days;
  }

  @override
  State<RecentTransactionsScreen> createState() =>
      _RecentTransactionsScreenState();
}

class _RecentTransactionsScreenState extends State<RecentTransactionsScreen> {
  int _transactionLimit = 20;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetch(forceSync: false);
    });
  }

  Future<void> _fetch({required bool forceSync}) async {
    final authProvider = context.read<AuthProvider>();
    final transactionsProvider = context.read<TransactionsProvider>();

    final accessToken = await authProvider.getValidAccessToken();

    if (accessToken != null) {
      // Load transactions for all accounts
      await transactionsProvider.fetchTransactions(
        accessToken: accessToken,
        forceSync: forceSync,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final transactionsProvider = context.watch<TransactionsProvider>();
    final accounts = {
      for (final account in context.watch<AccountsProvider>().accounts)
        account.id: account,
    };

    final recent = RecentTransactionsScreen.newest(
      transactionsProvider.transactions,
      _transactionLimit,
    );

    final List<Widget> content;
    if (transactionsProvider.isLoading && recent.isEmpty) {
      content = const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    } else if (recent.isEmpty && transactionsProvider.error != null) {
      content = [
        _centered(SureEmptyState(
          icon: SureIcons.circleAlert,
          title: l.activityLoadFailed,
          secondaryLabel: l.commonTryAgain,
          onSecondary: () => _fetch(forceSync: true),
        )),
      ];
    } else if (recent.isEmpty) {
      content = [
        _centered(SureEmptyState(
          icon: SureIcons.receipt,
          title: l.recentTransactionsEmpty,
          body: l.recentTransactionsPullToRefresh,
        )),
      ];
    } else {
      final days = RecentTransactionsScreen.byDay(recent);
      content = [
        SliverList.builder(
          itemCount: days.length,
          itemBuilder: (context, index) {
            final day = days[index];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (day.day != null)
                  SureDayHeader.forDay(context, day.day!, background: false)
                else
                  SureDayHeader(label: day.raw, background: false),
                SurePanel.rows(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  dividerIndent: SurePanel.iconRowDividerIndent,
                  children: [
                    for (final t in day.rows)
                      SureTransactionRow(
                        transaction: t,
                        account: accounts[t.accountId],
                        accountName: accounts[t.accountId] == null
                            ? l.recentTransactionsUnknownAccount
                            : null,
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ];
    }

    return SureLargeTitleScaffold(
      title: l.recentTransactionsTitle,
      // Recent transactions opens from Settings' Tools group.
      leading: Navigator.of(context).canPop()
          ? SureBackButton(label: l.shellSettingsTitle)
          : null,
      onRefresh: () => _fetch(forceSync: true),
      slivers: [
        SliverToBoxAdapter(
          child: Semantics(
            label: l.recentTransactionsDisplayLimit,
            container: true,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Row(
                children: [
                  for (final limit in RecentTransactionsScreen.limitOptions)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: SureChip(
                        key: ValueKey('recentLimit-$limit'),
                        label: l.recentTransactionsShowN(limit),
                        selected: limit == _transactionLimit,
                        onSelected: (_) =>
                            setState(() => _transactionLimit = limit),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        ...content,
      ],
    );
  }

  Widget _centered(Widget state) => SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: state),
      );
}
