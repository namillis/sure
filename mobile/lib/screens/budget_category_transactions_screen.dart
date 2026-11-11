import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../models/transaction.dart';
import '../providers/accounts_provider.dart';
import '../providers/auth_provider.dart';
import '../services/budgets_service.dart';
import '../services/transactions_service.dart';
import '../widgets/ds/ds.dart';
import '../widgets/sure_button.dart';

/// Transactions behind one budget line: the category (and, for a parent, its
/// subcategories) within the budget's date range, newest first, paged from
/// `GET /api/v1/transactions` with `category_ids[]`, `start_date` and
/// `end_date`. Rows are grouped by day under a large title.
class BudgetCategoryTransactionsScreen extends StatefulWidget {
  const BudgetCategoryTransactionsScreen({
    super.key,
    required this.title,
    required this.periodLabel,
    required this.categoryIds,
    required this.startDate,
    required this.endDate,
    this.categoryColor,
    this.categoryIcon,
    this.service,
    this.accessTokenLoader,
  });

  final String title;
  final String periodLabel;
  final List<String> categoryIds;
  final DateTime startDate;
  final DateTime endDate;

  /// The budget category's `#rrggbb` color and Lucide icon, for the rows'
  /// category icons (the transactions payload has neither).
  final String? categoryColor;
  final String? categoryIcon;

  /// Injected for tests.
  final TransactionsService? service;
  final Future<String?> Function()? accessTokenLoader;

  @override
  State<BudgetCategoryTransactionsScreen> createState() =>
      _BudgetCategoryTransactionsScreenState();
}

class _BudgetCategoryTransactionsScreenState
    extends State<BudgetCategoryTransactionsScreen> {
  static const int _perPage = 50;

  late final TransactionsService _service =
      widget.service ?? TransactionsService();
  final List<Transaction> _transactions = [];
  int _page = 0;
  int _totalPages = 1;
  bool _loading = false;
  bool _failed = false;

  /// Whether the request that failed was a reload from page one, so its retry
  /// repeats it instead of appending the next page to stale rows.
  bool _failedWasReset = false;

  bool get _hasMore => _page < _totalPages;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadPage(reset: true);
    });
  }

  Future<String?> _accessToken() {
    final loader = widget.accessTokenLoader;
    if (loader != null) return loader();
    return context.read<AuthProvider>().getValidAccessToken();
  }

  Future<void> _loadPage({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });

    final token = await _accessToken();
    if (!mounted) return;
    if (token == null) {
      setState(() {
        _loading = false;
        _failed = true;
        _failedWasReset = reset;
      });
      return;
    }

    final nextPage = reset ? 1 : _page + 1;
    final result = await _service.getTransactions(
      accessToken: token,
      categoryIds: widget.categoryIds,
      startDate: BudgetsService.formatApiDate(widget.startDate),
      endDate: BudgetsService.formatApiDate(widget.endDate),
      page: nextPage,
      perPage: _perPage,
    );
    if (!mounted) return;

    setState(() {
      _loading = false;
      if (result['success'] == true) {
        if (reset) _transactions.clear();
        _transactions.addAll(result['transactions'] as List<Transaction>);
        _page = nextPage;
        final pagination = result['pagination'];
        _totalPages = pagination is Map
            ? (pagination['total_pages'] as num?)?.toInt() ?? nextPage
            : nextPage;
      } else {
        _failed = true;
        _failedWasReset = reset;
      }
    });
  }

  Map<String, Account> _accountsById() {
    try {
      return {
        for (final account in context.read<AccountsProvider>().accounts)
          account.id: account,
      };
    } on ProviderNotFoundException {
      // Account names are optional context; the rows still render.
      return const {};
    }
  }

  /// Consecutive transactions on the same day, in server order.
  static List<({DateTime? day, String raw, List<Transaction> rows})> _byDay(
      List<Transaction> transactions) {
    final days = <({DateTime? day, String raw, List<Transaction> rows})>[];
    for (final t in transactions) {
      if (days.isNotEmpty && days.last.raw == t.date) {
        days.last.rows.add(t);
      } else {
        days.add((day: SureDates.parseDay(t.date), raw: t.date, rows: [t]));
      }
    }
    return days;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    final List<Widget> slivers;
    if (_loading && _transactions.isEmpty) {
      slivers = const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    } else if (_failed && _transactions.isEmpty) {
      slivers = [
        _centered(SureEmptyState(
          icon: SureIcons.circleAlert,
          title: l.budgetCategoryTransactionsLoadFailed,
          secondaryLabel: l.commonTryAgain,
          onSecondary: () => _loadPage(reset: true),
        )),
      ];
    } else if (_transactions.isEmpty) {
      slivers = [
        _centered(SureEmptyState(
          icon: SureIcons.receipt,
          title: l.budgetCategoryTransactionsEmpty(widget.periodLabel),
        )),
      ];
    } else {
      final accounts = _accountsById();
      final days = _byDay(_transactions);
      slivers = [
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
                        categoryColor: widget.categoryColor,
                        categoryIcon: widget.categoryIcon,
                      ),
                  ],
                ),
              ],
            );
          },
        ),
        if (_hasMore || _failed)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: SureButton(
                  label: _failed
                      ? l.commonTryAgain
                      : l.budgetCategoryTransactionsLoadMore,
                  onPressed: _loading
                      ? null
                      : () => _loadPage(reset: _failed && _failedWasReset),
                  loading: _loading,
                  variant: SureButtonVariant.outline,
                  size: SureButtonSize.sm,
                ),
              ),
            ),
          ),
      ];
    }

    return SureLargeTitleScaffold(
      title: widget.title,
      subtitle: widget.periodLabel,
      onRefresh: () => _loadPage(reset: true),
      slivers: slivers,
    );
  }

  Widget _centered(Widget state) => SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: state),
      );
}
