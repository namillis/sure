import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/activity_filters.dart';
import '../models/activity_transaction.dart';
import '../models/family_sync.dart';
import '../models/offline_transaction.dart';
import '../providers/accounts_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/privacy_provider.dart';
import '../providers/transactions_provider.dart';
import '../services/connectivity_service.dart';
import '../services/family_sync_service.dart';
import '../services/insights_service.dart';
import '../services/log_service.dart';
import '../services/net_worth_history_service.dart';
import '../services/spending_vs_normal_service.dart';
import '../services/transaction_search_service.dart';
import '../theme/sure_colors.dart';
import '../utils/investment_math.dart';
import '../utils/money_masker.dart';
import '../utils/net_worth_history.dart';
import '../utils/updated_ago.dart';
import '../widgets/account_card.dart';
import '../widgets/balance_history_chart.dart' show AccountChartRange;
import '../widgets/connectivity_banner.dart';
import '../widgets/ds/ds.dart';
import '../widgets/insights_card.dart';
import '../widgets/net_worth_card.dart';
import '../widgets/open_on_web_action.dart';
import '../widgets/spending_vs_normal_card.dart';
import '../widgets/sync_now_dialog.dart';
import '../widgets/sync_status_chip.dart';
import 'account_group_screen.dart';
import 'connections_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'transaction_sheet.dart';

/// Home: a large "Home" title with the sync pill, privacy toggle and
/// settings; the net worth hero with its trend line and range chips; the top
/// insight, spending vs normal and Reports rows; the three latest
/// transactions; and the accounts grouped by type.
///
/// Accounts and the balance sheet are cache first ([AccountsProvider]); the
/// trend line is the Reports net worth history for the selected range, loaded
/// when online.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    this.onOpenActivity,
    this.accessTokenLoader,
    this.netWorthService,
    this.searchService,
    this.insightsService,
    this.spendingService,
    this.syncService,
    this.clock,
  });

  /// "See all" on Recent: switches the shell to the Activity tab. The link
  /// is hidden when null.
  final VoidCallback? onOpenActivity;

  /// Defaults to [AuthProvider.getValidAccessToken].
  final Future<String?> Function()? accessTokenLoader;

  /// Injected for tests; otherwise the screen owns them.
  final NetWorthHistoryService? netWorthService;
  final TransactionSearchService? searchService;
  final InsightsService? insightsService;
  final SpendingVsNormalService? spendingService;
  final FamilySyncService? syncService;

  /// Source of "now"; injectable for tests.
  final DateTime Function()? clock;

  /// Transactions shown under Recent.
  static const int recentCount = 3;

  @override
  DashboardScreenState createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  final LogService _log = LogService.instance;
  late final NetWorthHistoryService _netWorth =
      widget.netWorthService ?? NetWorthHistoryService();
  late final TransactionSearchService _search =
      widget.searchService ?? TransactionSearchService();

  bool _showSyncSuccess = false;
  int _previousPendingCount = 0;
  Timer? _syncSuccessTimer;
  TransactionsProvider? _transactionsProvider;

  /// Bumped on refresh; keys the self-loading rows so they reload.
  int _homeRefreshCount = 0;

  AccountChartRange _range = AccountChartRange.quarter;

  /// Loaded histories by range, cleared on refresh.
  final Map<AccountChartRange, NetWorthHistory> _histories = {};
  String _historyCurrency = '';
  bool _historyLoading = false;
  int _historyGeneration = 0;

  List<ActivityTransaction>? _recent;
  bool _signedOut = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _transactionsProvider = _maybeRead<TransactionsProvider>();
      _previousPendingCount = _transactionsProvider?.pendingCount ?? 0;
      _transactionsProvider?.addListener(_onTransactionsChanged);
      _loadAll();
    });
  }

  @override
  void dispose() {
    _syncSuccessTimer?.cancel();
    _transactionsProvider?.removeListener(_onTransactionsChanged);
    if (widget.netWorthService == null) _netWorth.close();
    super.dispose();
  }

  T? _maybeRead<T>() {
    try {
      return Provider.of<T>(context, listen: false);
    } on ProviderNotFoundException {
      return null;
    }
  }

  DateTime _now() => (widget.clock ?? DateTime.now)();

  bool get _offline =>
      _maybeRead<ConnectivityService>()?.isOffline ?? false;

  Future<String?> _token() {
    final loader = widget.accessTokenLoader;
    if (loader != null) return loader();
    return context.read<AuthProvider>().getValidAccessToken();
  }

  Future<void> _signOut() async {
    if (_signedOut) return;
    _signedOut = true;
    await _maybeRead<AuthProvider>()?.logout();
  }

  void _onTransactionsChanged() {
    final transactionsProvider = _transactionsProvider;
    if (transactionsProvider == null || !mounted) return;
    final currentPendingCount = transactionsProvider.pendingCount;
    // Pending count went down: local transactions were uploaded.
    if (_previousPendingCount > 0 &&
        currentPendingCount < _previousPendingCount) {
      _showSyncSuccessIndicator();
    }
    _previousPendingCount = currentPendingCount;
  }

  void _showSyncSuccessIndicator() {
    _syncSuccessTimer?.cancel();
    setState(() => _showSyncSuccess = true);
    _syncSuccessTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showSyncSuccess = false);
    });
  }

  Future<void> _loadAll() async {
    await Future.wait([
      _loadAccounts().then((_) => _loadHistory()),
      _loadRecent(),
    ]);
  }

  Future<void> _loadAccounts() async {
    final accountsProvider = context.read<AccountsProvider>();
    final accessToken = await _token();
    if (!mounted) return;
    if (accessToken == null) {
      // Token is invalid: back to sign in.
      await _signOut();
      return;
    }
    await accountsProvider.fetchAccounts(accessToken: accessToken);
    if (accountsProvider.errorMessage == 'unauthorized') await _signOut();
  }

  /// The family currency, else the most common account currency.
  static String _mainCurrency(AccountsProvider provider) {
    final known = provider.familyCurrency;
    if (known != null && known.isNotEmpty) return known;
    final counts = <String, int>{};
    for (final a in provider.accounts) {
      counts[a.currency] = (counts[a.currency] ?? 0) + 1;
    }
    if (counts.isEmpty) return '';
    return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }

  Future<void> _loadHistory() async {
    final range = _range;
    if (!mounted || _histories.containsKey(range) || _offline) return;
    final provider = context.read<AccountsProvider>();
    final accounts = provider.accounts;
    if (accounts.isEmpty) return;
    final generation = ++_historyGeneration;
    setState(() => _historyLoading = true);

    final token = await _token();
    if (!mounted || generation != _historyGeneration) return;
    if (token == null) {
      setState(() => _historyLoading = false);
      return;
    }
    final currency = _mainCurrency(provider);
    final now = _now();
    final result = await _netWorth.load(
      accessToken: token,
      accounts: accounts,
      mainCurrency: currency,
      start: range.startDate(now),
      end: DateTime(now.year, now.month, now.day),
    );
    if (!mounted || generation != _historyGeneration) return;
    setState(() {
      _historyLoading = false;
      if (result['success'] == true) {
        _histories[range] = result['history'] as NetWorthHistory;
        _historyCurrency = currency;
      }
    });
    if (result['error'] == 'unauthorized') await _signOut();
  }

  Future<void> _loadRecent() async {
    final token = await _token();
    if (!mounted || token == null) return;
    final result = await _search.search(
      accessToken: token,
      filters: const ActivityFilters(datePreset: ActivityDatePreset.all),
      perPage: DashboardScreen.recentCount,
      now: _now(),
    );
    if (!mounted) return;
    if (result['success'] == true) {
      setState(() => _recent = (result['transactions'] as List<dynamic>)
          .cast<ActivityTransaction>()
          .take(DashboardScreen.recentCount)
          .toList());
    } else if (result['error'] == 'unauthorized') {
      await _signOut();
    }
  }

  void _selectRange(AccountChartRange range) {
    setState(() => _range = range);
    _loadHistory();
  }

  /// Kept for the shell, which calls it when Home is shown or settings close.
  /// Home has no preferences of its own to reload any more.
  void reloadPreferences() {}

  /// Reloads accounts, history, Recent and the Home rows, e.g. after a sync.
  Future<void> reloadData() async {
    setState(() {
      _homeRefreshCount += 1;
      _histories.clear();
      _historyGeneration++;
      _historyLoading = false;
    });
    await _loadAll();
  }

  Future<void> _handleRefresh() async {
    setState(() {
      _homeRefreshCount += 1;
      _histories.clear();
      _historyGeneration++;
      _historyLoading = false;
    });
    await Future.wait([
      _performManualSync().then((_) => _loadHistory()),
      _loadRecent(),
    ]);
  }

  Future<void> _performManualSync() async {
    final transactionsProvider = _maybeRead<TransactionsProvider>();
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final messenger = ScaffoldMessenger.of(context);

    final accessToken = await _token();
    if (!mounted) return;
    if (accessToken == null) {
      await _signOut();
      return;
    }
    if (transactionsProvider == null) {
      await _loadAccounts();
      return;
    }

    void showError(String text) => messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                SureIcon(SureIcons.circleAlert, color: palette.textInverse),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(text,
                      style: TextStyle(color: palette.textInverse)),
                ),
              ],
            ),
            backgroundColor: palette.destructive,
            duration: const Duration(seconds: 3),
          ),
        );

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
            Expanded(child: Text(l.dashboardSyncing)),
          ],
        ),
        duration: const Duration(seconds: 30),
      ),
    );

    try {
      // Full sync: upload pending, download from server, then accounts.
      await transactionsProvider.syncTransactions(accessToken: accessToken);
      await _loadAccounts();
      if (!mounted) return;
      messenger.clearSnackBars();
      if (transactionsProvider.error != null) {
        showError(l.dashboardSyncFailed);
      } else {
        _showSyncSuccessIndicator();
      }
    } catch (e) {
      _log.error('DashboardScreen', 'Error in _performManualSync: $e');
      if (!mounted) return;
      messenger.clearSnackBars();
      showError(l.dashboardSyncError);
    }
  }

  /// "Updated <time> ago" while the accounts shown came from the offline
  /// cache (before the refresh lands, or when it can't) or the device is
  /// offline; null once fresh data is on screen.
  String? _updatedLabel(AccountsProvider accountsProvider, bool offline) {
    final updatedAt = accountsProvider.lastUpdatedAt;
    if (updatedAt == null) return null;
    if (!offline && !accountsProvider.isShowingCachedData) return null;
    return updatedAgoLabel(AppLocalizations.of(context), updatedAt, _now());
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
  }

  Future<void> _openGroup(String accountType) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AccountGroupScreen(
          accountType: accountType,
          onReload: _loadAccounts,
        ),
      ),
    );
  }

  Future<void> _openTransaction(ActivityTransaction row) async {
    final updated = await showTransactionSheet(
      context,
      transaction: OfflineTransaction.fromTransaction(
        row.transaction,
        localId: row.id ?? '',
      ),
    );
    if (updated == true && mounted) await reloadData();
  }

  void _openWeb(String title, String path) =>
      openWebFallback(context, title: title, path: path);

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final hidden = context.watch<PrivacyProvider>().hidden;
    final accountsProvider = context.watch<AccountsProvider>();
    ConnectivityService? connectivity;
    try {
      connectivity = context.watch<ConnectivityService>();
    } on ProviderNotFoundException {
      connectivity = null;
    }
    final offline = connectivity?.isOffline ?? false;

    final actions = <Widget>[
      _SyncPill(
        service: widget.syncService,
        accessTokenLoader: _token,
        onUnauthorized: _signOut,
        onSynced: reloadData,
        clock: _now,
      ),
      SureNavIconButton(
        icon: hidden ? SureIcons.eyeOff : SureIcons.eye,
        semanticLabel: hidden ? l.dshShowAmounts : l.dshHideAmounts,
        onPressed: () => context.read<PrivacyProvider>().toggle(),
      ),
      SureNavIconButton(
        icon: SureIcons.settings,
        semanticLabel: l.shellSettingsTitle,
        onPressed: _openSettings,
      ),
      const SizedBox(width: 4),
    ];

    final List<Widget> body;
    if (accountsProvider.accounts.isEmpty &&
        (accountsProvider.isInitializing || accountsProvider.isLoading)) {
      // Spinner only when there is nothing to show yet: cached accounts stay
      // on screen while a refresh runs.
      body = const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    } else if (accountsProvider.errorMessage != null &&
        accountsProvider.errorMessage != 'unauthorized' &&
        accountsProvider.accounts.isEmpty) {
      body = [
        SliverToBoxAdapter(
          child: ConnectivityBanner(
            updatedAt: accountsProvider.lastUpdatedAt,
            clock: _now,
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          ),
        ),
        SliverToBoxAdapter(
          child: SurePanel(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SureEmptyState(
              icon: SureIcons.circleAlert,
              title: l.dashboardErrorLoadingAccounts,
              body: accountsProvider.errorMessage,
              primaryLabel: l.commonTryAgain,
              onPrimary: _handleRefresh,
            ),
          ),
        ),
      ];
    } else if (accountsProvider.accounts.isEmpty) {
      body = [
        SliverToBoxAdapter(
          child: SurePanel(
            key: const ValueKey('homeFirstRun'),
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SureEmptyState(
              icon: SureIcons.wallet,
              title: l.dashboardNoAccounts,
              body: l.dshEmptyBody,
              primaryLabel: l.dshConnectOnWeb,
              onPrimary: () =>
                  _openWeb(l.shellConnections, ConnectionsScreen.webPath),
              secondaryLabel: l.dshAddManualAccount,
              onSecondary: () =>
                  _openWeb(l.dshAddAccount, _newAccountPath),
            ),
          ),
        ),
      ];
    } else {
      body = _content(l, accountsProvider, offline, hidden);
    }

    return SureLargeTitleScaffold(
      title: l.navHome,
      actions: actions,
      automaticallyImplyLeading: false,
      onRefresh: _handleRefresh,
      slivers: body,
    );
  }

  /// The web's new account flow (choose a type, or connect a provider).
  static const _newAccountPath = '/accounts/new';

  List<Widget> _content(
    AppLocalizations l,
    AccountsProvider accountsProvider,
    bool offline,
    bool hidden,
  ) {
    final palette = SureColors.of(context).palette;
    const rowMargin = EdgeInsets.fromLTRB(16, 0, 16, 8);
    final history = _histories[_range];
    final recent = _recent;
    final groups = AccountGroup.build(
      accountsProvider.accounts,
      mainCurrency: _mainCurrency(accountsProvider),
    );

    return [
      SliverToBoxAdapter(
        child: ConnectivityBanner(
          updatedAt: accountsProvider.lastUpdatedAt,
          clock: _now,
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        ),
      ),
      if (_showSyncSuccess)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                SureIcon(SureIcons.cloudCheck, color: palette.success, size: 16),
                const SizedBox(width: 6),
                Text(
                  l.dashboardSynced,
                  style: TextStyle(color: palette.success, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      SliverToBoxAdapter(
        child: NetWorthCard(
          netWorthFormatted: accountsProvider.netWorthFormatted,
          isStale: accountsProvider.isBalanceSheetStale,
          updatedLabel: _updatedLabel(accountsProvider, offline),
          history: history,
          historyCurrency: _historyCurrency,
          historyLoading: history == null && _historyLoading,
          range: _range,
          // The history needs the network; offline the chips would do nothing.
          onRangeChanged: offline ? null : _selectRange,
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 16)),
      SliverToBoxAdapter(
        child: InsightsCard(
          key: ValueKey('insights-$_homeRefreshCount'),
          service: widget.insightsService,
          accessTokenLoader: widget.accessTokenLoader,
          margin: rowMargin,
        ),
      ),
      SliverToBoxAdapter(
        child: SpendingVsNormalCard(
          key: ValueKey('spending-$_homeRefreshCount'),
          service: widget.spendingService,
          accessTokenLoader: widget.accessTokenLoader,
          margin: rowMargin,
        ),
      ),
      SliverToBoxAdapter(
        child: SurePanel.rows(
          key: const ValueKey('homeReportsRow'),
          margin: rowMargin,
          children: [
            SureListRow(
              leading: const _NeutralIcon(SureIcons.chartLine),
              title: l.p3rpTitle,
              showChevron: true,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReportsScreen()),
              ),
            ),
          ],
        ),
      ),
      if (recent != null && recent.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: SureSectionHeader(
            label: l.dshRecent,
            actionLabel: widget.onOpenActivity == null ? null : l.dshSeeAll,
            onAction: widget.onOpenActivity,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          ),
        ),
        SliverToBoxAdapter(
          child: SurePanel.rows(
            key: const ValueKey('homeRecent'),
            margin: const EdgeInsets.symmetric(horizontal: 16),
            dividerIndent: SurePanel.iconRowDividerIndent,
            children: [
              for (final row in recent)
                SureTransactionRow.activity(
                  row,
                  hideAmount: hidden,
                  onTap: () => _openTransaction(row),
                ),
            ],
          ),
        ),
      ],
      SliverToBoxAdapter(
        child: SureSectionHeader(
          label: l.dshAccounts,
          actionIcon: SureIcons.plus,
          actionSemanticLabel: l.dshAddAccount,
          onAction: () => _openWeb(l.dshAddAccount, _newAccountPath),
        ),
      ),
      SliverToBoxAdapter(
        child: SurePanel.rows(
          key: const ValueKey('homeAccounts'),
          margin: const EdgeInsets.symmetric(horizontal: 16),
          dividerIndent: SurePanel.iconRowDividerIndent,
          children: [
            for (final group in groups)
              _AccountGroupRow(
                group: group,
                hidden: hidden,
                onTap: () => _openGroup(group.accountType),
              ),
          ],
        ),
      ),
    ];
  }
}

/// A 28 px neutral inset circle with a Lucide glyph, for Home's plain rows.
class _NeutralIcon extends StatelessWidget {
  const _NeutralIcon(this.icon);

  final String icon;

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
        child: SureIcon(icon, size: 15, color: palette.textSecondary),
      ),
    );
  }
}

/// "Cash · 3 (1 empty)" with the group's total in the main currency and any
/// other currencies under it ("+ £28,708.00"), then a chevron.
class _AccountGroupRow extends StatelessWidget {
  const _AccountGroupRow({
    required this.group,
    required this.hidden,
    required this.onTap,
  });

  final AccountGroup group;
  final bool hidden;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final locale = Localizations.localeOf(context).toString();
    String money(double value, String currency) => MoneyMasker.mask(
          InvestmentMath.formatMoney(value, currency: currency, locale: locale),
          hidden: hidden,
        );

    final total = group.primaryTotal;
    final negative = total < 0;
    final others = group.otherCurrencies;
    final width = MediaQuery.sizeOf(context).width;

    return Semantics(
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey('group-${group.accountType}'),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 9, 10, 9),
              child: Row(
                children: [
                  AccountTypeIcon(accountType: group.accountType),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l.dshGroupTitle(
                        accountGroupLabel(l, group.accountType),
                        group.accounts.length,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.25,
                        fontWeight: FontWeight.w500,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: width * 0.45),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerEnd,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          MoneyText(
                            money(total, group.primaryCurrency),
                            trend: negative
                                ? MoneyTrend.outflow
                                : MoneyTrend.inflow,
                            color: negative
                                ? palette.destructive
                                : palette.textPrimary,
                            maxLines: 1,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          for (final currency in others)
                            MoneyText(
                              '+ ${money(group.totals[currency]!, currency)}',
                              trend: MoneyTrend.neutral,
                              color: palette.textSubdued,
                              maxLines: 1,
                              style: const TextStyle(fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  SureIcon(
                    SureIcons.chevronRight,
                    size: 18,
                    color: palette.textSubdued,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The compact sync pill in Home's nav bar: "⟳ 9h" for the newest sync
/// (`GET /api/v1/syncs/latest`), a spinner while one runs, "Failed" after a
/// failure. Tapping runs "Sync now" and calls [onSynced] when it completes.
/// Renders nothing until the first status arrives.
///
/// shortcut: duplicates [SyncStatusChip]'s load/poll logic with a shorter
/// label; fold into SyncStatusChip (a `compact` flag) when the shared set is
/// next touched.
class _SyncPill extends StatefulWidget {
  const _SyncPill({
    required this.accessTokenLoader,
    required this.onUnauthorized,
    required this.onSynced,
    required this.clock,
    this.service,
  });

  final FamilySyncService? service;
  final Future<String?> Function() accessTokenLoader;
  final Future<void> Function() onUnauthorized;
  final VoidCallback onSynced;
  final DateTime Function() clock;

  static const pollInterval = Duration(seconds: 5);

  @override
  State<_SyncPill> createState() => _SyncPillState();
}

class _SyncPillState extends State<_SyncPill> {
  late final FamilySyncService _service =
      widget.service ?? FamilySyncService();
  FamilySync? _sync;
  bool _loaded = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    if (widget.service == null) _service.close();
    super.dispose();
  }

  Future<void> _load() async {
    _poll?.cancel();
    final token = await widget.accessTokenLoader();
    if (!mounted || token == null) return;
    final result = await _service.getSync(accessToken: token);
    if (!mounted) return;
    if (result['error'] == 'unauthorized') {
      await widget.onUnauthorized();
      return;
    }
    if (result['success'] != true) return;
    setState(() {
      _loaded = true;
      _sync = result['sync'] as FamilySync?;
    });
    if (_sync?.inProgress == true) {
      _poll = Timer(_SyncPill.pollInterval, _load);
    }
  }

  Future<void> _syncNow() async {
    final completed = await showSyncNowDialog(context, service: widget.service);
    if (!mounted) return;
    if (completed) widget.onSynced();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final sync = _sync;
    final running = sync?.inProgress == true;

    final Widget icon;
    final String label;
    if (running) {
      icon = SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: palette.textSecondary,
        ),
      );
      label = l.accountActionsSyncing;
    } else if (sync != null && sync.failed) {
      icon = SureIcon(SureIcons.circleAlert,
          size: 14, color: palette.destructive);
      label = l.dshSyncFailedShort;
    } else {
      icon = SureIcon(SureIcons.refresh, size: 14, color: palette.textSecondary);
      final at = sync?.completedAt ?? sync?.createdAt;
      label = sync == null
          ? l.dshSyncShort
          : at == null
              ? l.dshAgoNow
              : compactAgeLabel(l, at, widget.clock()) ?? l.dshAgoNow;
    }

    return Semantics(
      label: SyncStatusChip.labelFor(l, sync, now: widget.clock()),
      hint: l.accountActionsSyncChipHint,
      excludeSemantics: true,
      child: SureChip(
        label: label,
        leading: icon,
        onSelected: running ? null : (_) => _syncNow(),
      ),
    );
  }
}
