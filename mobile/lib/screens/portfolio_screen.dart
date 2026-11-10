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
import '../utils/investment_math.dart';
import '../utils/money_masker.dart';
import '../utils/portfolio_math.dart';
import '../widgets/balance_history_chart.dart';
import '../widgets/holdings_list.dart';
import '../widgets/sure_segmented_control.dart';
import '../widgets/trades_list.dart';
import 'transactions_list_screen.dart';

/// Every investment and crypto account in one currency: total value with a
/// ranged chart, unrealized gain, allocation, every position and the latest
/// trades. Accounts in other currencies are one tap away in the currency
/// switcher; amounts in different currencies are never added together.
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

  /// How many trades the Recent activity section shows.
  static const int recentTradeCount = 10;

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  late final AccountDetailService _service =
      widget.accountDetailService ?? AccountDetailService();
  late String _currency = widget.initialCurrency;
  AccountChartRange _range = AccountChartRange.month;

  List<AccountHolding> _holdings = [];
  List<AccountTrade> _trades = [];
  List<AccountBalance> _history = [];
  AccountBalance? _selected;
  bool _loadingPositions = true;
  bool _loadingHistory = true;
  bool _failed = false;

  // Guards against an older load landing after a newer one.
  int _positionsGeneration = 0;
  int _historyGeneration = 0;

  List<String> get _currencies =>
      widget.accounts.map((account) => account.currency).toSet().toList()
        ..sort();

  List<Account> get _accountsInCurrency => widget.accounts
      .where((account) => account.currency == _currency)
      .toList();

  @override
  void initState() {
    super.initState();
    // _loadHistory reads Localizations, which isn't available in initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reload();
    });
  }

  @override
  void dispose() {
    if (widget.accountDetailService == null) _service.close();
    super.dispose();
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
          perPage: PortfolioScreen.recentTradeCount,
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
      // Partial data is still worth showing; fail only when nothing loaded.
      _failed = accounts.isNotEmpty &&
          holdingResults.every((result) => result['success'] != true);
      _loadingPositions = false;
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
    });
    _reload();
  }

  void _selectRange(AccountChartRange range) {
    if (range == _range) return;
    setState(() => _range = range);
    _loadHistory();
  }

  void _openAccount(String? accountId) {
    final account = widget.accounts
        .where((candidate) => candidate.id == accountId)
        .firstOrNull;
    if (account == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TransactionsListScreen(account: account),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final accounts = _accountsInCurrency;
    final multipleAccounts = accounts.length > 1;

    return Scaffold(
      appBar: AppBar(title: Text(l.portfolioTitle)),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (_currencies.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: SureSegmentedControl<String>(
                  selected: _currency,
                  onChanged: _selectCurrency,
                  segments: [
                    for (final currency in _currencies)
                      SureSegment(value: currency, label: currency),
                  ],
                ),
              ),
            _SummaryCard(
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
            if (_holdings.isNotEmpty)
              _AllocationCard(
                slices: PortfolioMath.allocation(
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
                ),
                currency: _currency,
              ),
            if (_loadingPositions && _holdings.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_failed)
              _Message(
                icon: Icons.error_outline,
                text: l.portfolioLoadFailed,
                action: TextButton(
                  onPressed: _reload,
                  child: Text(l.transactionsListRetry),
                ),
              )
            else ...[
              _SectionHeading(l.accountTabHoldings),
              if (_holdings.isEmpty)
                _Message(icon: Icons.pie_chart_outline, text: l.holdingsEmpty)
              else
                for (final holding in _holdings)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        HoldingTile(
                          holding: holding,
                          accountName:
                              multipleAccounts ? holding.accountName : null,
                          onTap: () => _openAccount(holding.accountId),
                        ),
                        const Divider(height: 1),
                      ],
                    ),
                  ),
              if (_trades.isNotEmpty) ...[
                _SectionHeading(l.portfolioRecentActivity),
                for (final trade in _trades)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        InkWell(
                          onTap: () => _openAccount(trade.accountId),
                          child: TradeTile(
                            trade: trade,
                            showAccount: multipleAccounts,
                          ),
                        ),
                        const Divider(height: 1),
                      ],
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
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
    final trendColor = change == null || change.amount >= 0
        ? palette.success
        : palette.destructive;
    final gain = PortfolioMath.totalGain(holdings);

    String? subline;
    Color? sublineColor;
    if (selected != null) {
      subline = DateFormat.yMMMd(locale).format(selected!.date);
      sublineColor = colorScheme.onSurfaceVariant;
    } else if (change != null) {
      final percent = change.percent;
      subline = percent == null
          ? l.accountChartChangeOnlyLabel(money(change.amount, signed: true))
          : l.accountChartChangeLabel(
              money(change.amount, signed: true),
              InvestmentMath.formatPercent(percent, locale: locale),
            );
      sublineColor = trendColor;
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.portfolioAccountCount(accounts.length),
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              selected != null
                  ? MoneyMasker.mask(selected!.balance, hidden: hidden)
                  : money(total),
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (subline != null) ...[
              const SizedBox(height: 2),
              Text(subline,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: sublineColor)),
            ],
            if (gain != null) ...[
              const SizedBox(height: 2),
              Text(
                l.portfolioUnrealizedGain(
                  money(gain.amount, signed: true),
                  InvestmentMath.formatPercent(gain.percent, locale: locale),
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: gain.isLoss ? palette.destructive : palette.success,
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: 96,
              child: history.length >= 2
                  ? BalanceHistoryChart(
                      balances: history,
                      color: trendColor,
                      semanticLabel: subline,
                      onSelectionChanged: onSelectionChanged,
                    )
                  : Center(
                      child: loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              l.accountChartNoHistory,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
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
      ),
    );
  }
}

class _AllocationCard extends StatelessWidget {
  const _AllocationCard({required this.slices, required this.currency});

  final List<AllocationSlice> slices;
  final String currency;

  // Distinct hues for the largest positions; "other" and cash are neutral so
  // the eye goes to the named holdings first.
  static final List<Color> _holdingColors = [
    Colors.indigo.shade400,
    Colors.teal.shade400,
    Colors.amber.shade600,
    Colors.pink.shade300,
    Colors.lightBlue.shade400,
  ];

  Color _colorFor(AllocationSlice slice, int index) => switch (slice.kind) {
        AllocationKind.holding =>
          _holdingColors[index % _holdingColors.length],
        AllocationKind.other => Colors.blueGrey.shade300,
        AllocationKind.cash => Colors.grey.shade400,
      };

  @override
  Widget build(BuildContext context) {
    if (slices.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    final hidden = context.watch<PrivacyProvider>().hidden;

    String labelFor(AllocationSlice slice) => switch (slice.kind) {
          AllocationKind.holding => slice.label?.isNotEmpty == true
              ? slice.label!
              : l.accountDetailHoldingFallback,
          AllocationKind.other => l.portfolioAllocationOther,
          AllocationKind.cash => l.portfolioAllocationCash,
        };

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.portfolioAllocation, style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 10,
                child: Row(
                  children: [
                    for (var i = 0; i < slices.length; i++)
                      Expanded(
                        // At least 1 so a tiny slice still shows a sliver.
                        flex: (slices[i].fraction * 1000).round().clamp(1, 1000),
                        child: Container(color: _colorFor(slices[i], i)),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < slices.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _colorFor(slices[i], i),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        labelFor(slices[i]),
                        style: theme.textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      NumberFormat.decimalPercentPattern(
                        locale: locale,
                        decimalDigits: 1,
                      ).format(slices[i].fraction),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 104,
                      child: Text(
                        MoneyMasker.mask(
                          InvestmentMath.formatMoney(slices[i].value,
                              currency: currency, locale: locale),
                          hidden: hidden,
                        ),
                        textAlign: TextAlign.end,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(
            icon,
            size: 40,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 8),
          Text(text, style: TextStyle(color: colorScheme.onSurfaceVariant)),
          if (action != null) action!,
        ],
      ),
    );
  }
}
