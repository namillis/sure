import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../models/account_balance.dart';
import '../models/account_holding.dart';
import '../models/account_trade.dart';
import '../providers/auth_provider.dart';
import '../providers/privacy_provider.dart';
import '../services/account_detail_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_tokens.dart';
import '../utils/investment_math.dart';
import '../utils/money_masker.dart';
import '../utils/portfolio_math.dart';
import '../utils/zero_holdings.dart';
import '../widgets/balance_history_chart.dart';
import '../widgets/ds/ds.dart';
import '../widgets/holdings_list.dart';
import '../widgets/trades_list.dart';
import 'transactions_list_screen.dart';

/// Sections of the Invest tab, under its pinned switcher.
enum PortfolioSection { allocation, holdings, activity }

/// Every investment and crypto account in one currency: the "Invest" large
/// title over the account count, the total value with its change, unrealized
/// gain, a ranged chart, then an Allocation | Holdings | Activity switcher
/// that stays pinned under the nav bar once the header scrolls away. Accounts
/// in other currencies are one tap away in the nav bar's currency control;
/// amounts in different currencies are never added together.
class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({
    super.key,
    required this.accounts,
    required this.initialCurrency,
    this.accountDetailService,
  });

  /// Investment and crypto accounts, in any currency.
  final List<Account> accounts;
  final String initialCurrency;
  final AccountDetailService? accountDetailService;

  /// Trades loaded per page of the Activity section.
  static const int tradePageSize = 25;

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen>
    with ZeroHoldingsPreference<PortfolioScreen> {
  late final AccountDetailService _service =
      widget.accountDetailService ?? AccountDetailService();
  late String _currency = widget.initialCurrency;
  AccountChartRange _range = AccountChartRange.month;
  PortfolioSection _section = PortfolioSection.allocation;

  List<AccountHolding> _holdings = [];
  List<AccountTrade> _trades = [];
  List<AccountBalance> _history = [];
  AccountBalance? _selected;
  bool _loadingPositions = true;
  bool _loadingHistory = true;
  bool _failed = false;

  // Activity paging.
  int _nextTradePage = 2;
  bool _tradesHaveMore = false;
  bool _loadingMoreTrades = false;
  bool _tradesFailed = false;

  // Guards against an older load landing after a newer one.
  int _positionsGeneration = 0;
  int _historyGeneration = 0;

  final ScrollController _outerController = ScrollController();
  bool _titleCollapsed = false;

  List<String> get _currencies =>
      widget.accounts.map((account) => account.currency).toSet().toList()
        ..sort();

  List<Account> get _accountsInCurrency => widget.accounts
      .where((account) => account.currency == _currency)
      .toList();

  @override
  void initState() {
    super.initState();
    _outerController.addListener(_onOuterScroll);
    // _loadHistory reads Localizations, which isn't available in initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reload();
    });
  }

  @override
  void dispose() {
    _outerController.dispose();
    if (widget.accountDetailService == null) _service.close();
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

  Future<void> _reload() => Future.wait([_loadPositions(), _loadHistory()]);

  Future<String?> _token() async {
    final authProvider = context.read<AuthProvider>();
    final token = await authProvider.getValidAccessToken();
    if (token == null) await authProvider.logout();
    return token;
  }

  Future<void> _loadPositions() async {
    final generation = ++_positionsGeneration;
    final accounts = _accountsInCurrency;
    setState(() {
      _loadingPositions = true;
      _failed = false;
    });

    final token = await _token();
    if (token == null || !mounted || generation != _positionsGeneration) {
      return;
    }

    final results = await Future.wait([
      for (final account in accounts)
        _service.getCurrentHoldings(accessToken: token, accountId: account.id),
      if (accounts.isNotEmpty)
        _service.getTrades(
          accessToken: token,
          accountIds: [for (final account in accounts) account.id],
          perPage: PortfolioScreen.tradePageSize,
        ),
    ]);
    if (!mounted || generation != _positionsGeneration) return;

    if (results.any((result) => result['error'] == 'unauthorized')) {
      await context.read<AuthProvider>().logout();
      return;
    }

    final holdingResults = results.take(accounts.length).toList();
    final tradeResult = accounts.isEmpty ? null : results.last;
    setState(() {
      _holdings = [
        for (final result in holdingResults)
          if (result['success'] == true)
            ...(result['holdings'] as List<dynamic>).whereType<AccountHolding>(),
      ]..sort((left, right) => (InvestmentMath.parse(right.amount) ?? 0)
          .compareTo(InvestmentMath.parse(left.amount) ?? 0));
      _trades = tradeResult?['success'] == true
          ? (tradeResult!['trades'] as List<dynamic>)
              .whereType<AccountTrade>()
              .toList()
          : [];
      _tradesFailed = tradeResult != null && tradeResult['success'] != true;
      _tradesHaveMore = tradeResult?['hasMore'] == true;
      _nextTradePage = 2;
      _loadingMoreTrades = false;
      // Partial data is still worth showing; fail only when nothing loaded.
      _failed = accounts.isNotEmpty &&
          holdingResults.every((result) => result['success'] != true);
      _loadingPositions = false;
    });
  }

  Future<void> _loadMoreTrades() async {
    if (!_tradesHaveMore || _loadingMoreTrades || _loadingPositions) return;
    final generation = _positionsGeneration;
    final accounts = _accountsInCurrency;
    final page = _nextTradePage;
    setState(() {
      _loadingMoreTrades = true;
      _tradesFailed = false;
    });

    final token = await _token();
    if (token == null || !mounted || generation != _positionsGeneration) {
      return;
    }
    final result = await _service.getTrades(
      accessToken: token,
      accountIds: [for (final account in accounts) account.id],
      page: page,
      perPage: PortfolioScreen.tradePageSize,
    );
    if (!mounted || generation != _positionsGeneration) return;
    if (result['error'] == 'unauthorized') {
      await context.read<AuthProvider>().logout();
      return;
    }

    setState(() {
      _loadingMoreTrades = false;
      if (result['success'] == true) {
        _trades = [
          ..._trades,
          ...(result['trades'] as List<dynamic>? ?? [])
              .whereType<AccountTrade>(),
        ];
        _tradesHaveMore = result['hasMore'] == true;
        _nextTradePage = page + 1;
      } else {
        _tradesFailed = true;
      }
    });
  }

  Future<void> _loadHistory() async {
    final generation = ++_historyGeneration;
    final accounts = _accountsInCurrency;
    final currency = _currency;
    final range = _range;
    final locale = Localizations.localeOf(context).toString();
    setState(() => _loadingHistory = true);

    final token = await _token();
    if (token == null || !mounted || generation != _historyGeneration) return;

    final results = await Future.wait([
      for (final account in accounts)
        _service.getBalanceHistory(
          accessToken: token,
          accountId: account.id,
          startDate: range.startDate(DateTime.now()),
        ),
    ]);
    if (!mounted || generation != _historyGeneration) return;

    setState(() {
      _history = PortfolioMath.sumHistories(
        [
          for (final result in results)
            if (result['success'] == true)
              (result['balances'] as List<dynamic>)
                  .whereType<AccountBalance>()
                  .toList(),
        ],
        currency: currency,
        locale: locale,
      );
      _selected = null;
      _loadingHistory = false;
    });
  }

  void _selectCurrency(String currency) {
    if (currency == _currency) return;
    setState(() {
      _currency = currency;
      _holdings = [];
      _trades = [];
      _history = [];
      _tradesHaveMore = false;
    });
    _reload();
  }

  void _selectRange(AccountChartRange range) {
    if (range == _range) return;
    setState(() => _range = range);
    _loadHistory();
  }

  Account? _accountFor(String? accountId) => widget.accounts
      .where((candidate) => candidate.id == accountId)
      .firstOrNull;

  void _openAccount(String? accountId) {
    final account = _accountFor(accountId);
    if (account == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TransactionsListScreen(
          account: account,
          backLabel: AppLocalizations.of(context).shellNavInvest,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final accounts = _accountsInCurrency;
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    final currencies = _currencies;

    return Scaffold(
      backgroundColor: palette.surface,
      body: Column(
        children: [
          _NavBar(
            key: const ValueKey('investNavBar'),
            title: l.shellNavInvest,
            showTitle: _titleCollapsed,
            leading: canPop ? const SureBackButton() : null,
            trailing: currencies.length > 1
                ? _CurrencyControl(
                    currencies: currencies,
                    selected: _currency,
                    onChanged: _selectCurrency,
                  )
                : null,
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: NestedScrollView(
                controller: _outerController,
                // The header scrolls away; the switcher at the top of the
                // body then stays pinned under the nav bar.
                headerSliverBuilder: (context, innerBoxIsScrolled) => [
                  SliverToBoxAdapter(
                    child: _LargeTitle(
                      title: l.shellNavInvest,
                      subtitle: l.portfolioAccountCount(accounts.length),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: _Summary(
                      accounts: accounts,
                      currency: _currency,
                      holdings: _holdings,
                      history: _history,
                      selected: _selected,
                      range: _range,
                      loading: _loadingHistory,
                      onRangeChanged: _selectRange,
                      onSelectionChanged: (balance) =>
                          setState(() => _selected = balance),
                    ),
                  ),
                ],
                body: Column(
                  children: [
                    Container(
                      key: const ValueKey('investSectionSwitcher'),
                      color: palette.surface,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: SureSegmentedControl<PortfolioSection>(
                        selected: _section,
                        onChanged: (section) =>
                            setState(() => _section = section),
                        segments: [
                          SureSegment(
                            value: PortfolioSection.allocation,
                            label: l.portfolioAllocation,
                          ),
                          SureSegment(
                            value: PortfolioSection.holdings,
                            label: l.accountTabHoldings,
                          ),
                          SureSegment(
                            value: PortfolioSection.activity,
                            label: l.accountTabActivity,
                          ),
                        ],
                      ),
                    ),
                    Expanded(child: _buildSection(l, accounts)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A section's scroll view, with pull-to-refresh.
  Widget _scroll(List<Widget> slivers, {Key? key}) {
    return RefreshIndicator(
      onRefresh: _reload,
      child: CustomScrollView(
        key: key,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          ...slivers,
          SliverPadding(
            padding: EdgeInsets.only(
              bottom: 24 + MediaQuery.paddingOf(context).bottom,
            ),
          ),
        ],
      ),
    );
  }

  Widget _message(Widget state) => _scroll([
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: state),
        ),
      ]);

  Widget _buildSection(AppLocalizations l, List<Account> accounts) {
    if (_loadingPositions && _holdings.isEmpty && _trades.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return switch (_section) {
      PortfolioSection.allocation => _buildAllocation(l, accounts),
      PortfolioSection.holdings => _buildHoldings(l, accounts),
      PortfolioSection.activity => _buildActivity(l, accounts),
    };
  }

  Widget _failedState(AppLocalizations l) => _message(SureEmptyState(
        key: const ValueKey('investPositionsFailed'),
        icon: SureIcons.circleAlert,
        title: l.portfolioLoadFailed,
        secondaryLabel: l.transactionsListRetry,
        onSecondary: _reload,
      ));

  Widget _buildAllocation(AppLocalizations l, List<Account> accounts) {
    if (_failed) return _failedState(l);
    final slices = _holdings.isEmpty
        ? const <AllocationSlice>[]
        : PortfolioMath.allocation(
            _holdings,
            // The account list has no cash_balance, but an investment
            // account's balance is its holdings plus its cash.
            cash: PortfolioMath.cash(
              accountsTotal: accounts.fold<double>(
                0,
                (sum, account) =>
                    sum + (InvestmentMath.parse(account.balance) ?? 0),
              ),
              holdings: _holdings,
            ),
          );
    if (slices.isEmpty) {
      return _message(SureEmptyState(
        icon: SureIcons.chartPie,
        title: l.holdingsEmpty,
      ));
    }
    return _scroll(key: const ValueKey('investAllocation'), [
      SliverToBoxAdapter(
        child: _AllocationPanel(slices: slices, currency: _currency),
      ),
    ]);
  }

  Widget _buildHoldings(AppLocalizations l, List<Account> accounts) {
    if (_failed) return _failedState(l);
    if (_holdings.isEmpty) {
      return _message(SureEmptyState(
        icon: SureIcons.chartPie,
        title: l.holdingsEmpty,
      ));
    }
    final multipleAccounts = accounts.length > 1;
    final visible = ZeroHoldings.visible(_holdings, showZero: showZeroHoldings);
    final zeroCount = ZeroHoldings.zeroCount(_holdings);
    return _scroll(key: const ValueKey('investHoldings'), [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        sliver: SliverList.list(children: [
          if (visible.isEmpty)
            SurePanel(child: AllZeroHoldingsMessage(currency: _currency))
          else
            SurePanel.rows(
              dividerIndent: HoldingTile.dividerIndent,
              children: [
                for (final holding in visible)
                  HoldingTile(
                    holding: holding,
                    accountName: multipleAccounts ? holding.accountName : null,
                    crypto:
                        _accountFor(holding.accountId)?.accountType == 'crypto',
                    onTap: () => _openAccount(holding.accountId),
                  ),
              ],
            ),
          if (zeroCount > 0)
            ZeroHoldingsFooter(
              count: zeroCount,
              currency: _currency,
              shown: showZeroHoldings,
              onToggle: toggleShowZeroHoldings,
            ),
        ]),
      ),
    ]);
  }

  // Driven by scroll notifications: the list's controller belongs to the
  // enclosing NestedScrollView.
  bool _maybeLoadMoreTrades(ScrollUpdateNotification notification) {
    final metrics = notification.metrics;
    if (notification.depth == 0 &&
        metrics.pixels > metrics.maxScrollExtent - 300) {
      _loadMoreTrades();
    }
    return false;
  }

  Widget _buildActivity(AppLocalizations l, List<Account> accounts) {
    if (_trades.isEmpty) {
      return _message(SureEmptyState(
        key: const ValueKey('investActivityEmpty'),
        icon: _tradesFailed ? SureIcons.circleAlert : SureIcons.arrowLeftRight,
        title: _tradesFailed ? l.tradesLoadFailed : l.tradesEmpty,
        secondaryLabel: _tradesFailed ? l.transactionsListRetry : null,
        onSecondary: _tradesFailed ? _reload : null,
      ));
    }

    final multipleAccounts = accounts.length > 1;
    // One header + panel per day, newest first (the API's order).
    final days = <({DateTime day, List<AccountTrade> trades})>[];
    for (final trade in _trades) {
      final day = DateUtils.dateOnly(trade.date);
      if (days.isEmpty || days.last.day != day) {
        days.add((day: day, trades: [trade]));
      } else {
        days.last.trades.add(trade);
      }
    }
    final showFooter = _tradesHaveMore || _tradesFailed;
    return NotificationListener<ScrollUpdateNotification>(
      onNotification: _maybeLoadMoreTrades,
      child: _scroll(key: const ValueKey('investActivity'), [
        SliverList.builder(
          itemCount: days.length,
          itemBuilder: (context, index) {
            final group = days[index];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SureDayHeader.forDay(context, group.day, background: false),
                SurePanel.rows(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final trade in group.trades)
                      TradeTile(
                        trade: trade,
                        showAccount: multipleAccounts,
                        showDate: false,
                        onTap: () => _openAccount(trade.accountId),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
        if (showFooter)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: _tradesFailed
                    ? TextButton(
                        onPressed: _loadMoreTrades,
                        child: Text(l.transactionsListRetry),
                      )
                    : SizedBox(
                        width: 20,
                        height: 20,
                        // Only spins while a page loads, so an idle footer
                        // does not animate forever.
                        child: _loadingMoreTrades
                            ? const CircularProgressIndicator(strokeWidth: 2)
                            : null,
                      ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Hero total, change line, unrealized gain, chart and range control. While
/// the chart is scrubbed the hero shows that day's value and the line under
/// it the date.
class _Summary extends StatelessWidget {
  const _Summary({
    required this.accounts,
    required this.currency,
    required this.holdings,
    required this.history,
    required this.selected,
    required this.range,
    required this.loading,
    required this.onRangeChanged,
    required this.onSelectionChanged,
  });

  final List<Account> accounts;
  final String currency;
  final List<AccountHolding> holdings;
  final List<AccountBalance> history;
  final AccountBalance? selected;
  final AccountChartRange range;
  final bool loading;
  final ValueChanged<AccountChartRange> onRangeChanged;
  final ValueChanged<AccountBalance?> onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final locale = Localizations.localeOf(context).toString();
    final hidden = context.watch<PrivacyProvider>().hidden;

    String money(double value, {bool signed = false}) => MoneyMasker.mask(
          InvestmentMath.formatMoney(value,
              currency: currency, locale: locale, signed: signed),
          hidden: hidden,
        );

    final total = accounts.fold<double>(
      0,
      (sum, account) => sum + (InvestmentMath.parse(account.balance) ?? 0),
    );
    final change = PortfolioMath.change(history);
    final trendIsGood = change == null || change.amount >= 0;
    final trendColor = trendIsGood ? palette.success : palette.destructive;
    final gain = PortfolioMath.totalGain(holdings);

    Widget? subline;
    String? semanticLabel;
    if (selected != null) {
      semanticLabel = SureDates.full(selected!.date, locale: locale);
      subline = Text(
        semanticLabel,
        key: const ValueKey('investScrubDate'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13, color: palette.textSecondary),
      );
    } else if (change != null) {
      final percent = change.percent;
      final changeText = money(change.amount, signed: true);
      final changeLine = percent == null
          ? changeText
          : '$changeText (${InvestmentMath.formatPercent(percent, locale: locale)})';
      semanticLabel = '$changeLine ${range.label(l)}';
      subline = Row(
        key: const ValueKey('investChange'),
        children: [
          Flexible(
            child: MoneyText(
              changeLine,
              trend: trendIsGood ? MoneyTrend.inflow : MoneyTrend.outflow,
              color: trendColor,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            range.label(l),
            style: TextStyle(
              fontSize: 13,
              fontFamily: SureTokens.fontMono,
              color: palette.textSubdued,
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: MoneyText(
                    selected != null
                        ? MoneyMasker.mask(selected!.balance, hidden: hidden)
                        : money(total),
                    key: const ValueKey('investTotal'),
                    trend: MoneyTrend.neutral,
                    color: palette.textPrimary,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 32,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ),
              if (loading) ...[
                const SizedBox(width: 10),
                const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
              ],
            ],
          ),
          // Fixed height so the date (scrubbing) and the change line swap
          // without the chart jumping.
          SizedBox(
            height: 20,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: subline ?? const SizedBox.shrink(),
            ),
          ),
          if (gain != null)
            MoneyText(
              l.portfolioUnrealizedGain(
                money(gain.amount, signed: true),
                InvestmentMath.formatPercent(gain.percent, locale: locale),
              ),
              key: const ValueKey('investUnrealized'),
              trend: gain.isLoss ? MoneyTrend.outflow : MoneyTrend.inflow,
              color: gain.isLoss ? palette.destructive : palette.success,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
            ),
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
            child: history.where((b) => b.balanceCents != null).length >= 2
                ? BalanceHistoryChart(
                    balances: history,
                    color: trendColor,
                    semanticLabel: semanticLabel,
                    onSelectionChanged: onSelectionChanged,
                  )
                : Center(
                    child: Text(
                      loading ? '' : l.accountChartNoHistory,
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(fontSize: 13, color: palette.textSubdued),
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          SureSegmentedControl<AccountChartRange>(
            selected: range,
            onChanged: onRangeChanged,
            segments: [
              for (final value in AccountChartRange.values)
                SureSegment(value: value, label: value.label(l)),
            ],
          ),
        ],
      ),
    );
  }
}

/// The allocation panel: a 6 px stacked bar and one legend row per slice
/// (color dot, label, "45.6% · $216,489").
class _AllocationPanel extends StatelessWidget {
  const _AllocationPanel({required this.slices, required this.currency});

  final List<AllocationSlice> slices;
  final String currency;

  // Gap: the token palette has no violet or pink. These are the web's own
  // category colors (Category::COLORS in app/models/category.rb), which read
  // on both the light and the dark panel.
  static const Color _violet = Color(0xFF805DEE);
  static const Color _pink = Color(0xFFDF4E92);

  /// The slice's color: distinct hues for the largest positions, neutral for
  /// "Other" and cash so the eye goes to the named holdings first.
  static Color colorFor(SureTokenPalette palette, AllocationSlice slice,
      int index) {
    final holdingColors = [
      palette.warning,
      palette.link,
      palette.success,
      _violet,
      _pink,
    ];
    return switch (slice.kind) {
      AllocationKind.holding => holdingColors[index % holdingColors.length],
      AllocationKind.other => palette.textSubdued,
      AllocationKind.cash => palette.textSubdued.withValues(alpha: 0.45),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final locale = Localizations.localeOf(context).toString();
    final hidden = context.watch<PrivacyProvider>().hidden;
    final percent =
        NumberFormat.decimalPercentPattern(locale: locale, decimalDigits: 1);

    String labelFor(AllocationSlice slice) => switch (slice.kind) {
          AllocationKind.holding => slice.label?.isNotEmpty == true
              // "CRYPTO:BTC" -> "BTC", as in the holding rows.
              ? slice.label!.substring(slice.label!.lastIndexOf(':') + 1)
              : l.accountDetailHoldingFallback,
          AllocationKind.other => l.portfolioAllocationOther,
          AllocationKind.cash => l.portfolioAllocationCash,
        };

    return SurePanel(
      key: const ValueKey('investAllocationPanel'),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              key: const ValueKey('investAllocationBar'),
              height: 6,
              child: Row(
                // Stretch so each slice fills the bar's 6 px height; a bare
                // ColoredBox would otherwise size itself to zero.
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < slices.length; i++)
                    Expanded(
                      // At least 1 so a tiny slice still shows a sliver.
                      flex: (slices[i].fraction * 1000).round().clamp(1, 1000),
                      child: ColoredBox(
                          color: colorFor(palette, slices[i], i)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < slices.length; i++)
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 36),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: colorFor(palette, slices[i], i),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      labelFor(slices[i]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: SureTokens.weightMedium,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerEnd,
                      child: MoneyText(
                        '${percent.format(slices[i].fraction)} · ${MoneyMasker.mask(
                          InvestmentMath.formatMoney(slices[i].value,
                              currency: currency, locale: locale),
                          hidden: hidden,
                        )}',
                        trend: MoneyTrend.neutral,
                        color: palette.textSecondary,
                        maxLines: 1,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w400),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A compact currency switcher for the nav bar (e.g. GBP | USD).
class _CurrencyControl extends StatelessWidget {
  const _CurrencyControl({
    required this.currencies,
    required this.selected,
    required this.onChanged,
  });

  final List<String> currencies;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // shortcut: about 56 px per code, capped so the bar keeps room for its
    // title; more than three currencies ellipsize. Upgrade to a picker sheet
    // if families with many currencies show up.
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 12),
      child: Semantics(
        label: l.ds2iCurrency,
        container: true,
        child: SizedBox(
          key: const ValueKey('investCurrencyControl'),
          width: (currencies.length * 56.0).clamp(112.0, 180.0),
          child: SureSegmentedControl<String>(
            selected: selected,
            onChanged: onChanged,
            segments: [
              for (final currency in currencies)
                SureSegment(value: currency, label: currency),
            ],
          ),
        ),
      ),
    );
  }
}

/// The tab's top bar: optional back link, a small centered title that fades
/// in once the large title has scrolled away, and the currency control; a
/// hairline under it when collapsed. It sits outside the NestedScrollView so
/// the header can scroll under it and the section switcher can pin against
/// it (the same structure as the account page).
///
/// Gap: SureLargeTitleHeader is a pinned sliver, which overlaps the body of a
/// NestedScrollView, so this screen draws its own bar and large title.
class _NavBar extends StatelessWidget {
  const _NavBar({
    super.key,
    required this.title,
    required this.showTitle,
    this.leading,
    this.trailing,
  });

  final String title;
  final bool showTitle;
  final Widget? leading;
  final Widget? trailing;

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
          trailing: trailing,
          middleSpacing: 8,
        ),
      ),
    );
  }
}

/// "Invest" as an iOS large title over the account count.
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
            key: const ValueKey('investSubtitle'),
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
