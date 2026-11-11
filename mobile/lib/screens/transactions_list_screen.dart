import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/account.dart';
import '../models/account_holding.dart';
import '../models/category.dart';
import '../models/transaction.dart';
import '../models/offline_transaction.dart';
import '../providers/auth_provider.dart';
import '../providers/categories_provider.dart';
import '../providers/transactions_provider.dart';
import '../screens/transaction_edit_screen.dart';
import '../screens/transaction_form_screen.dart';
import '../screens/trade_form_screen.dart';
import '../widgets/account_actions_menu.dart';
import '../widgets/account_detail_header.dart';
import '../widgets/category_filter.dart';
import '../widgets/ds/ds.dart';
import '../widgets/holdings_list.dart';
import '../widgets/set_price_sheet.dart';
import '../widgets/trades_list.dart';
import '../theme/sure_colors.dart';
import '../providers/privacy_provider.dart';
import '../utils/amount_parser.dart';
import '../utils/investment_math.dart';
import '../utils/money_masker.dart';
import '../l10n/app_localizations.dart';

/// An account's page: back link and ⋯ menu, the account name as a large
/// title over "Brokerage · synced 9h ago", the balance header and chart
/// ([AccountDetailHeader]), then the account's transactions grouped by day.
/// Investment and crypto accounts get a Holdings | Activity | Transactions
/// switcher that stays pinned under the nav bar once the header scrolls away.
class TransactionsListScreen extends StatefulWidget {
  final Account account;

  /// Label of the back link ("‹ Home"); just the chevron when null.
  final String? backLabel;

  const TransactionsListScreen({
    super.key,
    required this.account,
    this.backLabel,
  });

  /// The large title's subtitle: the subtype (or type), then how long ago the
  /// server last updated the account, e.g. "Brokerage · synced 9h ago".
  static String subtitleFor(
    AppLocalizations l,
    Account account, {
    required DateTime now,
  }) {
    final subtype = account.subtype?.trim();
    final type = subtype != null && subtype.isNotEmpty
        ? _humanize(subtype)
        : account.displayAccountType;
    final at = account.updatedAt;
    if (at == null) return type;
    final age = now.difference(at.toLocal());
    final synced = age.inMinutes < 1
        ? l.dspSyncedJustNow
        : age.inHours < 1
            ? l.dspSyncedMinutesAgo(age.inMinutes)
            : age.inDays < 1
                ? l.dspSyncedHoursAgo(age.inHours)
                : l.dspSyncedDaysAgo(age.inDays);
    return '$type · $synced';
  }

  // shortcut: the API sends the raw subtype key ("roth_ira"); this reads
  // "Roth ira". Upgrade if the API exposes the web's subtype labels.
  static String _humanize(String key) {
    final words = key.replaceAll('_', ' ');
    return words[0].toUpperCase() + words.substring(1);
  }

  /// Transaction kinds the server books as transfers between own accounts.
  static const transferKinds = {'funds_movement', 'cc_payment', 'loan_payment'};

  @override
  State<TransactionsListScreen> createState() => _TransactionsListScreenState();
}

/// Sections of an investment/crypto account screen.
enum _AccountSection { holdings, activity, transactions }

class _TransactionsListScreenState extends State<TransactionsListScreen> {
  bool _isSelectionMode = false;
  final Set<String> _selectedTransactions = {};
  Set<String> _selectedCategoryIds = {};

  // The account as last loaded by the header (fresher than the route's copy).
  late Account _account = widget.account;

  // Bumped after an account action so the header and lists rebuild and reload.
  int _refreshTick = 0;

  // Bumped by pull-to-refresh so the header reloads without being rebuilt.
  int _headerReloads = 0;

  final ScrollController _outerController = ScrollController();
  bool _titleCollapsed = false;

  void _onAccountChanged() {
    setState(() => _refreshTick++);
    _loadTransactions();
  }

  void _reloadHeader() => setState(() => _headerReloads++);

  bool get _hasInvestmentSections =>
      widget.account.accountType == 'investment' ||
      widget.account.accountType == 'crypto';

  late _AccountSection _section = _hasInvestmentSections
      ? _AccountSection.holdings
      : _AccountSection.transactions;

  @override
  void initState() {
    super.initState();
    _outerController.addListener(_onOuterScroll);
    _loadTransactions();
    _loadCategories();
  }

  @override
  void dispose() {
    _outerController.dispose();
    super.dispose();
  }

  void _onOuterScroll() {
    // The small nav-bar title shows once most of the large title is gone.
    final collapsed = _outerController.hasClients &&
        _outerController.offset > _LargeTitle.height * 0.7;
    if (collapsed != _titleCollapsed) {
      setState(() => _titleCollapsed = collapsed);
    }
  }

  Future<void> _loadCategories() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final categoriesProvider =
        Provider.of<CategoriesProvider>(context, listen: false);
    final accessToken = await authProvider.getValidAccessToken();
    if (accessToken != null) {
      await categoriesProvider.fetchCategories(accessToken: accessToken);
    }
  }

  List<OfflineTransaction> _getFilteredTransactions(
      List<OfflineTransaction> transactions) {
    if (_selectedCategoryIds.isEmpty) return transactions;
    return transactions
        .where((t) =>
            t.categoryId != null && _selectedCategoryIds.contains(t.categoryId))
        .toList();
  }

  Future<void> _loadTransactions() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final transactionsProvider =
        Provider.of<TransactionsProvider>(context, listen: false);

    final accessToken = await authProvider.getValidAccessToken();
    if (accessToken == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(AppLocalizations.of(context).transactionsListAuthFailed),
            backgroundColor: SureColors.of(context).palette.destructive,
          ),
        );
      }
      return;
    }

    await transactionsProvider.fetchTransactions(
      accessToken: accessToken,
      accountId: widget.account.id,
    );
  }

  Future<void> _pullRefresh() {
    _reloadHeader();
    return _loadTransactions();
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedTransactions.clear();
      }
    });
  }

  void _toggleTransactionSelection(String transactionId) {
    setState(() {
      if (_selectedTransactions.contains(transactionId)) {
        _selectedTransactions.remove(transactionId);
      } else {
        _selectedTransactions.add(transactionId);
      }
    });
  }

  void _startSelection(String transactionId) {
    SureHaptics.selection();
    setState(() {
      _isSelectionMode = true;
      _selectedTransactions.add(transactionId);
    });
  }

  Future<void> _deleteSelectedTransactions() async {
    if (_selectedTransactions.isEmpty) return;
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final dl = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(dl.transactionsListDeleteMultiTitle),
          content: Text(dl.transactionsListDeleteMultiContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(dl.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: palette.destructive),
              child: Text(dl.commonDelete),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final count = _selectedTransactions.length;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final transactionsProvider =
        Provider.of<TransactionsProvider>(context, listen: false);

    final accessToken = await authProvider.getValidAccessToken();
    if (accessToken != null) {
      final success = await transactionsProvider.deleteMultipleTransactions(
        accessToken: accessToken,
        transactionIds: _selectedTransactions.toList(),
      );

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l.transactionsListDeletedMulti(count)),
              backgroundColor: palette.success,
            ),
          );
          setState(() {
            _selectedTransactions.clear();
            _isSelectionMode = false;
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l.transactionsListDeleteFailed),
              backgroundColor: palette.destructive,
            ),
          );
        }
      }
    }
  }

  Future<void> _undoTransaction(OfflineTransaction transaction) async {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final transactionsProvider =
        Provider.of<TransactionsProvider>(context, listen: false);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final isPending = transaction.syncStatus == SyncStatus.pending;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final dl = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(dl.transactionsListUndoTitle),
          content: Text(
            isPending
                ? dl.transactionsListUndoRemovePending
                : dl.transactionsListUndoRestoreConfirm,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(dl.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(dl.commonUndo),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    final success = await transactionsProvider.undoPendingTransaction(
      localId: transaction.localId,
      syncStatus: transaction.syncStatus,
    );

    if (mounted) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            success
                ? (isPending
                    ? l.transactionsListUndoPendingRemoved
                    : l.transactionsListUndoRestored)
                : l.transactionsListUndoFailed,
          ),
          backgroundColor: success ? palette.success : palette.destructive,
        ),
      );
    }
  }

  Future<void> _editTransaction(OfflineTransaction transaction) async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => TransactionEditScreen(transaction: transaction),
      ),
    );

    if (updated == true && mounted) {
      await _loadTransactions();
    }
  }

  Future<bool> _confirmAndDeleteTransaction(Transaction transaction) async {
    if (transaction.id == null) return false;

    // Capture providers and localizations before async gap
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final transactionsProvider =
        Provider.of<TransactionsProvider>(context, listen: false);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final dl = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(dl.transactionsListDeleteTitle),
          content:
              Text(dl.transactionsListDeleteSingleContent(transaction.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(dl.commonCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: palette.destructive),
              child: Text(dl.commonDelete),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return false;

    final accessToken = await authProvider.getValidAccessToken();

    if (accessToken == null) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(l.transactionsListDeleteNoToken),
          backgroundColor: palette.destructive,
        ),
      );
      return false;
    }

    final success = await transactionsProvider.deleteTransaction(
      accessToken: accessToken,
      transactionId: transaction.id!,
    );

    if (mounted) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(
            success
                ? l.transactionsListDeletedSuccess
                : l.transactionsListSingleDeleteFailed,
          ),
          backgroundColor: success ? palette.success : palette.destructive,
        ),
      );
    }

    return success;
  }

  void _showAddTransactionForm() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TransactionFormScreen(account: widget.account),
    ).then((_) {
      if (mounted) {
        _loadTransactions();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final canPop = ModalRoute.of(context)?.canPop ?? false;

    final actions = <Widget>[
      if (_section == _AccountSection.transactions) ...[
        if (_isSelectionMode)
          SureNavIconButton(
            key: const ValueKey('accountDeleteSelected'),
            icon: SureIcons.trash,
            semanticLabel: l.dspDeleteSelected,
            color: palette.destructive,
            onPressed: _selectedTransactions.isEmpty
                ? null
                : _deleteSelectedTransactions,
          ),
        SureNavIconButton(
          key: const ValueKey('accountSelectToggle'),
          icon: _isSelectionMode ? SureIcons.x : SureIcons.listChecks,
          semanticLabel: _isSelectionMode ? l.dspDoneSelecting : l.dspSelect,
          onPressed: _toggleSelectionMode,
        ),
      ],
      AccountActionsMenu(
        account: _account,
        onChanged: _onAccountChanged,
      ),
    ];

    return Scaffold(
      backgroundColor: palette.surface,
      body: Column(
        children: [
          _AccountNavBar(
            key: const ValueKey('accountNavBar'),
            title: _account.name,
            showTitle: _titleCollapsed,
            leading: canPop ? SureBackButton(label: widget.backLabel) : null,
            actions: actions,
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: NestedScrollView(
                controller: _outerController,
                // The header scrolls away with the list. The section switcher
                // sits at the top of the body, so once the header is gone it
                // stays pinned under the nav bar while the section list
                // scrolls below it.
                headerSliverBuilder: (context, innerBoxIsScrolled) => [
                  SliverToBoxAdapter(
                    child: _LargeTitle(
                      title: _account.name,
                      subtitle: TransactionsListScreen.subtitleFor(
                        l,
                        _account,
                        now: DateTime.now(),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: AccountDetailHeader(
                      key: ValueKey('header-$_refreshTick'),
                      account: widget.account,
                      reloadToken: _headerReloads,
                      onAccountLoaded: (account) {
                        if (mounted) setState(() => _account = account);
                      },
                    ),
                  ),
                ],
                body: !_hasInvestmentSections
                    ? _buildSection(l)
                    : Column(
                        children: [
                          Container(
                            key: const ValueKey('accountSectionSwitcher'),
                            color: palette.surface,
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                            child: SureSegmentedControl<_AccountSection>(
                              selected: _section,
                              onChanged: (section) => setState(() {
                                _section = section;
                                _isSelectionMode = false;
                                _selectedTransactions.clear();
                              }),
                              segments: [
                                SureSegment(
                                  value: _AccountSection.holdings,
                                  label: l.accountTabHoldings,
                                ),
                                SureSegment(
                                  value: _AccountSection.activity,
                                  label: l.accountTabActivity,
                                ),
                                SureSegment(
                                  value: _AccountSection.transactions,
                                  label: l.accountTabTransactions,
                                ),
                              ],
                            ),
                          ),
                          Expanded(child: _buildSection(l)),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _section == _AccountSection.transactions
          ? FloatingActionButton(
              tooltip: l.dspNewTransaction,
              backgroundColor: palette.buttonPrimary,
              foregroundColor: palette.textInverse,
              onPressed: _showAddTransactionForm,
              child: SureIcon(SureIcons.plus, color: palette.textInverse),
            )
          : null,
    );
  }

  Future<void> _setHoldingPrice(AccountHolding holding) async {
    final saved = await showSetPriceSheet(context, holding: holding);
    if (saved && mounted) _onAccountChanged();
  }

  Widget _buildSection(AppLocalizations l) {
    return switch (_section) {
      _AccountSection.holdings => HoldingsList(
          key: ValueKey('holdings-$_refreshTick'),
          account: widget.account,
          onHoldingTap: _setHoldingPrice,
          onRefreshed: _reloadHeader,
        ),
      _AccountSection.activity => TradesList(
          key: ValueKey('trades-$_refreshTick'),
          account: widget.account,
          onRefreshed: _reloadHeader,
          onTradeTap: (trade) async {
            final changed = await openTradeEditor(context,
                account: widget.account, trade: trade);
            if (changed && mounted) _onAccountChanged();
          },
        ),
      _AccountSection.transactions => _buildTransactions(l),
    };
  }

  Widget _message(Widget state) {
    return RefreshIndicator(
      onRefresh: _pullRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: state),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactions(AppLocalizations l) {
    return Consumer2<TransactionsProvider, CategoriesProvider>(
      builder: (context, transactionsProvider, categoriesProvider, child) {
        if (transactionsProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (transactionsProvider.error != null) {
          return _message(SureEmptyState(
            icon: SureIcons.circleAlert,
            title: transactionsProvider.error!,
            secondaryLabel: l.transactionsListRetry,
            onSecondary: _loadTransactions,
          ));
        }

        final allTransactions = transactionsProvider.offlineTransactions;

        if (allTransactions.isEmpty) {
          return _message(SureEmptyState(
            icon: SureIcons.receipt,
            title: l.transactionsListNoTransactionsYet,
            body: l.transactionsListEmptyAddFirst,
          ));
        }

        final transactions = _getFilteredTransactions(allTransactions);
        final categories = {
          for (final category in categoriesProvider.categories)
            category.id: category,
        };
        final days = _groupByDay(transactions);
        final locale = Localizations.localeOf(context).toString();
        final hideAmounts = context.watch<PrivacyProvider>().hidden;

        return RefreshIndicator(
          onRefresh: _pullRefresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (!categoriesProvider.isLoading &&
                  categoriesProvider.categories.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: CategoryFilter(
                      availableCategories: categoriesProvider.categories,
                      selectedCategoryIds: _selectedCategoryIds,
                      onSelectionChanged: (categoryIds) {
                        setState(() {
                          _selectedCategoryIds = categoryIds;
                        });
                      },
                    ),
                  ),
                ),
              if (transactions.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: SureEmptyState(
                      key: const ValueKey('accountNoCategoryMatch'),
                      icon: SureIcons.search,
                      title: l.transactionsListNoCategoryMatch,
                      secondaryLabel: l.dspClearFilter,
                      onSecondary: () =>
                          setState(() => _selectedCategoryIds = {}),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.only(bottom: 88),
                  sliver: SliverList.builder(
                    itemCount: days.length,
                    itemBuilder: (context, index) {
                      final day = days[index];
                      final total = _dayTotal(day.transactions, locale);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (day.date != null)
                            SureDayHeader.forDay(
                              context,
                              day.date!,
                              background: false,
                              total: total == null
                                  ? null
                                  : MoneyMasker.mask(total,
                                      hidden: hideAmounts),
                            )
                          else
                            SureDayHeader(label: day.raw, background: false),
                          SurePanel.rows(
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            dividerIndent: SurePanel.iconRowDividerIndent,
                            children: [
                              for (final transaction in day.transactions)
                                _row(transaction, categories),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _row(
      OfflineTransaction transaction, Map<String, Category> categories) {
    final id = transaction.id;
    final category = transaction.categoryId == null
        ? null
        : categories[transaction.categoryId];
    final status = transaction.syncStatus;
    final hasPendingStatus =
        status == SyncStatus.pending || status == SyncStatus.pendingDelete;

    final VoidCallback? onTap;
    if (_isSelectionMode) {
      onTap = id == null ? null : () => _toggleTransactionSelection(id);
    } else if (hasPendingStatus) {
      onTap = () => _undoTransaction(transaction);
    } else if (status == SyncStatus.synced) {
      onTap = () => _editTransaction(transaction);
    } else {
      onTap = null;
    }

    return Opacity(
      key: ValueKey('txn-${id ?? transaction.localId}'),
      opacity: hasPendingStatus ? 0.5 : 1.0,
      child: SureTransactionRow(
        transaction: transaction,
        account: _account,
        showAccount: false,
        categoryColor: category?.color,
        categoryIcon: category?.icon,
        isSplitParent: transaction.splitParent == true,
        isTransfer:
            TransactionsListScreen.transferKinds.contains(transaction.kind),
        syncStatus: status,
        selectionMode: _isSelectionMode,
        selected: id != null && _selectedTransactions.contains(id),
        onTap: onTap,
        onLongPress:
            _isSelectionMode || id == null ? null : () => _startSelection(id),
        onDelete: id == null || hasPendingStatus
            ? null
            : () => _confirmAndDeleteTransaction(transaction),
      ),
    );
  }

  /// Consecutive transactions on the same day, in list order.
  static List<_Day> _groupByDay(List<OfflineTransaction> transactions) {
    final days = <_Day>[];
    for (final transaction in transactions) {
      if (days.isNotEmpty && days.last.raw == transaction.date) {
        days.last.transactions.add(transaction);
      } else {
        days.add(_Day(
          raw: transaction.date,
          date: SureDates.parseDay(transaction.date),
          transactions: [transaction],
        ));
      }
    }
    return days;
  }

  /// The day's net in the account's sign convention (money in positive),
  /// or null when an amount does not parse or currencies are mixed.
  String? _dayTotal(List<OfflineTransaction> transactions, String locale) {
    final currency = transactions.first.currency;
    final flip = _account.isAsset || _account.isLiability;
    var sum = 0.0;
    for (final transaction in transactions) {
      if (transaction.currency != currency) return null;
      try {
        final value = AmountParser.parse(transaction.amount).value;
        sum += flip ? -value : value;
      } on FormatException {
        return null;
      }
    }
    return InvestmentMath.formatMoney(
      sum,
      currency: currency,
      locale: locale,
      signed: true,
    );
  }
}

class _Day {
  _Day({required this.raw, required this.date, required this.transactions});

  final String raw;
  final DateTime? date;
  final List<OfflineTransaction> transactions;
}

/// The page's top bar: back link, a small centered title that fades in once
/// the large title has scrolled away, and the actions; a hairline under it
/// when collapsed. It sits outside the NestedScrollView so the header can
/// scroll under it and the section switcher can pin against it.
///
/// Gap: SureLargeTitleHeader is a pinned sliver, which overlaps the body of a
/// NestedScrollView, so this page draws its own bar and large title.
class _AccountNavBar extends StatelessWidget {
  const _AccountNavBar({
    super.key,
    required this.title,
    required this.showTitle,
    required this.leading,
    required this.actions,
  });

  final String title;
  final bool showTitle;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = SureColors.of(context);
    final palette = colors.palette;
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(
          bottom: BorderSide(
            color: showTitle ? colors.hairline : const Color(0x00000000),
          ),
        ),
      ),
      child: SizedBox(
        height: SureLargeTitleHeader.barHeight,
        child: NavigationToolbar(
          leading: leading,
          middle: Semantics(
            excludeSemantics: !showTitle,
            header: showTitle,
            child: AnimatedOpacity(
              opacity: showTitle ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
            ),
          ),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: actions),
          middleSpacing: 8,
        ),
      ),
    );
  }
}

/// The account name as an iOS large title (the same type as
/// SureLargeTitleHeader) over its subtitle.
class _LargeTitle extends StatelessWidget {
  const _LargeTitle({required this.title, required this.subtitle});

  static const double height = SureLargeTitleHeader.largeTitleHeight +
      SureLargeTitleHeader.subtitleHeight;

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textScaler: scaler,
              style: TextStyle(
                fontSize: 32,
                height: 1.2,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.6,
                color: palette.textPrimary,
              ),
            ),
          ),
          Text(
            subtitle,
            key: const ValueKey('accountSubtitle'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textScaler: scaler,
            style: TextStyle(
              fontSize: 13,
              height: 1.3,
              color: palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
