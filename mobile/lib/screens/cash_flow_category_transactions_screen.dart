import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/cash_flow.dart';
import '../models/category.dart';
import '../models/transaction.dart';
import '../providers/accounts_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/categories_provider.dart';
import '../services/categories_service.dart';
import '../services/transactions_service.dart';
import '../utils/amount_parser.dart';
import '../widgets/ds/ds.dart';
import '../widgets/sure_button.dart';
import 'cash_flow_screen.dart' show AccessTokenLoader;

/// Kinds the income statement leaves out of income and spending
/// (`Transaction::BUDGET_EXCLUDED_KINDS`).
const Set<String> cashFlowExcludedKinds = {
  'funds_movement',
  'one_time',
  'cc_payment',
};

/// Whether [transaction] counts in the cash flow report, as far as the
/// transactions index says. Fields an older server leaves out don't filter.
@visibleForTesting
bool countsInCashFlow(Transaction transaction) {
  if (transaction.excluded == true) return false;
  if (transaction.splitParent == true) return false;
  final kind = transaction.kind;
  return kind == null || !cashFlowExcludedKinds.contains(kind);
}

/// Whether the report counts [transaction] as income. Loan payments and
/// investment contributions are outflows whatever their sign
/// (`IncomeStatement::ScopedTransactionsQuery#classification_sql`); other
/// rows follow the amount's sign, so a refund still shows as money in.
@visibleForTesting
bool isCashFlowIncome(Transaction transaction) {
  switch (transaction.kind) {
    case 'loan_payment':
    case 'investment_contribution':
      return false;
  }
  return transaction.isIncome;
}

/// Transactions in one cash flow category (and its subcategories) for the
/// report period, fetched page by page from `GET /api/v1/transactions` with
/// `start_date`, `end_date` and `category_ids[]`. Refunds are included, since
/// the cash flow report nets them within the category.
///
/// Like the web's category filter, every subcategory is included, also one
/// the report leaves out because its refunds net it to zero. Its ids come
/// from `GET /api/v1/categories?parent_id=…`; if that lookup fails, the
/// subcategories named in the report are used.
///
/// Rows the report doesn't count are left out, using the index's `excluded`,
/// `split_parent` and `kind` fields: excluded entries, split parents (their
/// children carry the amount) and transfer-like kinds. Loan payments and
/// investment contributions are shown as outflows whatever their sign, as
/// the report counts them. Servers without these fields show every row.
///
/// Rows are grouped by day under a large title (the category name) with the
/// period as its subtitle.
class CashFlowCategoryTransactionsScreen extends StatefulWidget {
  const CashFlowCategoryTransactionsScreen({
    super.key,
    required this.category,
    required this.range,
    this.service,
    this.categoriesService,
    this.accessTokenLoader,
    this.onUnauthorized,
  });

  final CashFlowCategory category;

  /// Called on a 401; defaults to [AuthProvider.logout].
  final Future<void> Function(BuildContext context)? onUnauthorized;
  final CashFlowDateRange range;
  final TransactionsService? service;
  final CategoriesService? categoriesService;
  final AccessTokenLoader? accessTokenLoader;

  @override
  State<CashFlowCategoryTransactionsScreen> createState() =>
      _CashFlowCategoryTransactionsScreenState();
}

class _CashFlowCategoryTransactionsScreenState
    extends State<CashFlowCategoryTransactionsScreen> {
  static const int _perPage = 50;

  late final TransactionsService _service =
      widget.service ?? TransactionsService();
  late final CategoriesService _categoriesService =
      widget.categoriesService ?? CategoriesService();
  final ScrollController _scroll = ScrollController();
  final List<Transaction> _transactions = [];

  /// The category plus all of its subcategories, once the lookup succeeded.
  List<String>? _categoryIds;
  int _page = 0;
  int? _totalPages;
  bool _loading = false;
  bool _failed = false;

  /// Bumped by [_refresh]; a page response from an older generation is
  /// dropped so it can't land in the reset list.
  int _generation = 0;

  bool get _hasMore => _totalPages == null || _page < _totalPages!;

  /// Pages in a row that had no row to show; capped so a long run of
  /// filtered-out rows doesn't fetch every page at once.
  int _emptyPagesInARow = 0;
  static const int _maxEmptyPagesInARow = 3;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400) _loadMore();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<String?> _accessToken() {
    final loader = widget.accessTokenLoader;
    if (loader != null) return loader(context);
    return context.read<AuthProvider>().getValidAccessToken();
  }

  @visibleForTesting
  Future<void> refreshForTest() => _refresh();

  @visibleForTesting
  Future<void> loadMoreForTest() => _loadMore();

  Future<void> _refresh() async {
    setState(() {
      _generation++;
      _transactions.clear();
      _page = 0;
      _totalPages = null;
      _failed = false;
      _loading = false;
      _emptyPagesInARow = 0;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore || _failed) return;
    final generation = _generation;
    final nextPage = _page + 1;
    setState(() => _loading = true);

    Map<String, dynamic>? result;
    var unauthorized = false;
    try {
      final token = await _accessToken();
      if (token != null) {
        if (mounted) {
          // Rows show their own category's icon; the list is shared and
          // fetched once.
          context
              .read<CategoriesProvider?>()
              ?.fetchCategories(accessToken: token);
        }
        final categoryIds = _categoryIds ?? await _lookUpCategoryIds(token);
        if (categoryIds == null) {
          unauthorized = true;
        } else {
          result = await _service.getTransactions(
            accessToken: token,
            page: nextPage,
            perPage: _perPage,
            startDate: widget.range.startIso,
            endDate: widget.range.endIso,
            categoryIds: categoryIds,
          );
          unauthorized = result['error'] == 'unauthorized';
        }
      }
    } catch (_) {
      // A failed token refresh (or storage error) is a failed page.
      result = null;
    }
    if (!mounted || generation != _generation) return;

    var shown = 0;
    setState(() {
      _loading = false;
      if (result != null && result['success'] == true) {
        final page = (result['transactions'] as List)
            .cast<Transaction>()
            .where(countsInCashFlow)
            .toList();
        shown = page.length;
        _transactions.addAll(page);
        _page = nextPage;
        // GET /api/v1/transactions always returns pagination.total_pages.
        final pagination = result['pagination'];
        if (pagination is Map && pagination['total_pages'] is int) {
          _totalPages = pagination['total_pages'] as int;
        }
      } else {
        _failed = true;
      }
    });
    if (unauthorized) {
      await _handleUnauthorized();
      return;
    }
    // A page whose rows were all filtered out leaves nothing to scroll, so
    // fetch the next one (a few at most per scroll).
    if (result != null && result['success'] == true) {
      _emptyPagesInARow = shown == 0 ? _emptyPagesInARow + 1 : 0;
      if (shown == 0 &&
          _hasMore &&
          _emptyPagesInARow < _maxEmptyPagesInARow) {
        await _loadMore();
      }
    }
  }

  /// The category's id plus all of its subcategory ids. Falls back to the
  /// ids the report knows when the lookup fails, and returns `null` on 401.
  Future<List<String>?> _lookUpCategoryIds(String token) async {
    final known = widget.category.transactionCategoryIds;
    final rootId = widget.category.categoryId;
    if (rootId == null) return known;
    Map<String, dynamic> lookup;
    try {
      lookup = await _categoriesService.getCategories(
        accessToken: token,
        parentId: rootId,
        perPage: 100,
      );
    } catch (_) {
      return known;
    }
    if (lookup['error'] == 'unauthorized') return null;
    if (lookup['success'] != true) return known;
    final ids = {
      ...known,
      for (final category in (lookup['categories'] as List).cast<Category>())
        if (category.id.isNotEmpty) category.id,
    }.toList(growable: false);
    if (mounted) _categoryIds = ids;
    return ids;
  }

  Future<void> _handleUnauthorized() async {
    final handler = widget.onUnauthorized;
    if (handler != null) return handler(context);
    try {
      await context.read<AuthProvider>().logout();
    } on ProviderNotFoundException {
      // No auth provider above this screen (e.g. in isolation).
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    final List<Widget> slivers;
    if (_transactions.isEmpty && _loading) {
      slivers = const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    } else if (_transactions.isEmpty) {
      slivers = [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: SureEmptyState(
              icon: _failed ? SureIcons.circleAlert : SureIcons.receipt,
              title: _failed
                  ? l.cashFlowTransactionsLoadFailed
                  : l.cashFlowTransactionsEmpty,
              secondaryLabel: _failed ? l.commonTryAgain : null,
              onSecondary: _failed ? _refresh : null,
            ),
          ),
        ),
      ];
    } else {
      final accounts = _accountNames();
      final categories = <String, Category>{
        for (final c in context.watch<CategoriesProvider?>()?.categories ??
            const <Category>[])
          c.id: c,
      };
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
                    for (final t in day.rows) _row(t, accounts, categories),
                  ],
                ),
              ],
            );
          },
        ),
        if (_loading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        if (_failed)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: SureButton(
                  label: l.commonTryAgain,
                  variant: SureButtonVariant.outline,
                  size: SureButtonSize.sm,
                  onPressed: () {
                    setState(() => _failed = false);
                    _loadMore();
                  },
                ),
              ),
            ),
          ),
      ];
    }

    return SureLargeTitleScaffold(
      title: widget.category.name,
      subtitle: SureDates.rangeOf(context, widget.range.start, widget.range.end),
      controller: _scroll,
      onRefresh: _refresh,
      slivers: slivers,
    );
  }

  /// Account names by id, for the rows' subtitles.
  Map<String, String> _accountNames() {
    try {
      return {
        for (final account in context.read<AccountsProvider>().accounts)
          account.id: account.name,
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

  Widget _row(
    Transaction transaction,
    Map<String, String> accounts,
    Map<String, Category> categories,
  ) {
    final category = categories[transaction.categoryId];
    return SureTransactionRow(
      key: ValueKey('cashFlowTransaction_${transaction.id}'),
      transaction: _asReported(transaction),
      // No account or account type: the row then shows the amount's own
      // sign, which [_asReported] set the way the report classifies it.
      accountName: accounts[transaction.accountId],
      categoryColor: category?.color ?? widget.category.color,
      categoryIcon: category?.icon,
    );
  }

  /// [transaction] with its amount signed the way the report counts it:
  /// income as a plain magnitude (shown "+" in success), everything else
  /// with a leading minus. The API's `amount` follows Sure's ledger sign
  /// convention, which the report overrides for loan payments and
  /// investment contributions.
  static Transaction _asReported(Transaction transaction) {
    // AmountParser's display text drops hyphen/en/em/figure dashes, minus
    // signs and accounting parentheses.
    String amount;
    try {
      final magnitude = AmountParser.parse(transaction.amount).displayText;
      amount = isCashFlowIncome(transaction) ? magnitude : '-$magnitude';
    } on FormatException {
      amount = transaction.amount;
    }
    return Transaction(
      id: transaction.id,
      accountId: transaction.accountId,
      name: transaction.name,
      date: transaction.date,
      amount: amount,
      currency: transaction.currency,
      nature: transaction.nature,
      categoryId: transaction.categoryId,
      categoryName: transaction.categoryName,
      kind: transaction.kind,
      excluded: transaction.excluded,
      splitParent: transaction.splitParent,
      entryId: transaction.entryId,
    );
  }
}
