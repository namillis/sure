import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../models/account_balance.dart';
import '../models/cash_flow.dart';
import '../models/spending_vs_normal.dart';
import '../providers/accounts_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/privacy_provider.dart';
import '../services/cash_flow_service.dart';
import '../services/categories_service.dart';
import '../services/connectivity_service.dart';
import '../services/net_worth_history_service.dart';
import '../services/spending_vs_normal_service.dart';
import '../services/transactions_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_spacing.dart';
import '../theme/sure_tokens.dart';
import '../utils/investment_math.dart';
import '../utils/money_masker.dart';
import '../utils/net_worth_history.dart';
import '../widgets/balance_history_chart.dart';
import '../widgets/cash_flow_donut_chart.dart';
import '../widgets/money_text.dart';
import '../widgets/sure_button.dart';
import '../widgets/sure_card.dart';
import '../widgets/sure_chip.dart';
import '../widgets/sure_icon.dart';
import 'cash_flow_category_transactions_screen.dart';
import 'cash_flow_screen.dart' show AccessTokenLoader, CashFlowFormat;

/// Periods offered on the Reports screen. Each maps to the cash flow preset
/// with the same range, so "Month" is the family's budget month.
enum ReportsPeriod {
  month(CashFlowPeriod.currentMonth),
  threeMonths(CashFlowPeriod.last90Days),
  yearToDate(CashFlowPeriod.currentYear),
  year(CashFlowPeriod.last365Days);

  const ReportsPeriod(this.cashFlowPeriod);

  final CashFlowPeriod cashFlowPeriod;

  String label(AppLocalizations l) => switch (this) {
        ReportsPeriod.month => l.p3rpPeriodMonth,
        ReportsPeriod.threeMonths => l.p3rpPeriodThreeMonths,
        ReportsPeriod.yearToDate => l.p3rpPeriodYearToDate,
        ReportsPeriod.year => l.p3rpPeriodYear,
      };
}

/// Load state of one section, so a slow or failed section never blocks
/// the others.
enum _Status { loading, loaded, failed }

/// One scrolling page of reports for a period: net worth over time, cash
/// flow (in, out, saved) and spending by category.
///
/// Net worth history is summed on the phone from each account's daily
/// balances (the server has no net worth history endpoint); cash flow and
/// categories come from `GET /api/v1/cash_flow`, and for the Month period
/// categories are flagged against `GET /api/v1/spending_vs_normal`.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({
    super.key,
    this.cashFlowService,
    this.netWorthService,
    this.spendingService,
    this.transactionsService,
    this.categoriesService,
    this.accessTokenLoader,
    this.onUnauthorized,
    this.clock,
    this.accounts,
    this.mainCurrency,
  });

  final CashFlowService? cashFlowService;
  final NetWorthHistoryService? netWorthService;
  final SpendingVsNormalService? spendingService;

  /// Passed to the category drill-down screen.
  final TransactionsService? transactionsService;
  final CategoriesService? categoriesService;

  /// Defaults to [AuthProvider.getValidAccessToken].
  final AccessTokenLoader? accessTokenLoader;

  /// Called on a 401; defaults to [AuthProvider.logout].
  final Future<void> Function(BuildContext context)? onUnauthorized;

  /// Source of "today"; injectable for tests.
  final DateTime Function()? clock;

  /// Accounts and the family currency; default to [AccountsProvider].
  final List<Account>? accounts;
  final String? mainCurrency;

  /// Categories shown before "Show all".
  static const int topCategoryCount = 8;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late final CashFlowService _cashFlow =
      widget.cashFlowService ?? CashFlowService();
  late final NetWorthHistoryService _netWorth =
      widget.netWorthService ?? NetWorthHistoryService();
  late final SpendingVsNormalService _spending =
      widget.spendingService ?? SpendingVsNormalService();

  ReportsPeriod _period = ReportsPeriod.month;
  int? _monthStartDay;

  /// Bumped on each load; responses for an older load are dropped.
  int _generation = 0;
  bool _offline = false;
  bool _signedOut = false;

  _Status _cashStatus = _Status.loading;
  CashFlowReport? _report;

  _Status _netWorthStatus = _Status.loading;
  NetWorthHistory? _history;
  String _historyCurrency = '';
  DateTime? _historyStart;
  NetWorthPoint? _selectedPoint;

  /// Above-normal ratio by category id (Month only).
  Map<String, double> _aboveNormal = const {};
  bool _showAllCategories = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    // Only closes services this screen created.
    if (widget.cashFlowService == null) _cashFlow.close();
    if (widget.netWorthService == null) _netWorth.close();
    if (widget.spendingService == null) _spending.close();
    super.dispose();
  }

  DateTime _today() {
    final now = (widget.clock ?? DateTime.now)();
    return DateTime(now.year, now.month, now.day);
  }

  Future<String?> _accessToken() {
    final loader = widget.accessTokenLoader;
    if (loader != null) return loader(context);
    return context.read<AuthProvider>().getValidAccessToken();
  }

  T? _maybeRead<T>() {
    try {
      return Provider.of<T>(context, listen: false);
    } on ProviderNotFoundException {
      return null;
    }
  }

  List<Account> _accounts() =>
      widget.accounts ?? _maybeRead<AccountsProvider>()?.accounts ?? const [];

  /// The family currency, else the most common account currency.
  String? _mainCurrency(List<Account> accounts) {
    final known =
        widget.mainCurrency ?? _maybeRead<AccountsProvider>()?.familyCurrency;
    if (known != null && known.isNotEmpty) return known;
    final counts = <String, int>{};
    for (final a in accounts) {
      counts[a.currency] = (counts[a.currency] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }

  Future<void> _handleUnauthorized() async {
    if (_signedOut || !mounted) return;
    _signedOut = true;
    final handler = widget.onUnauthorized;
    if (handler != null) return handler(context);
    try {
      await context.read<AuthProvider>().logout();
    } on ProviderNotFoundException {
      // No auth provider above this screen (e.g. in isolation).
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final period = _period;
    setState(() {
      _cashStatus = _Status.loading;
      _netWorthStatus = _Status.loading;
      _selectedPoint = null;
      _offline = false;
    });

    String? token;
    final offline = _maybeRead<ConnectivityService>()?.isOffline ?? false;
    try {
      token = offline ? null : await _accessToken();
    } catch (_) {
      token = null;
    }
    if (!mounted || generation != _generation) return;
    if (token == null) {
      setState(() {
        _offline = offline;
        _cashStatus = _Status.failed;
        _netWorthStatus = _Status.failed;
      });
      return;
    }

    if (_monthStartDay == null) {
      // If settings can't load, calendar months are used and the lookup is
      // retried on the next load (as on the cash flow screen).
      final settings = await _cashFlow.getMonthStartDay(accessToken: token);
      if (!mounted || generation != _generation) return;
      if (settings['success'] == true) {
        _monthStartDay = settings['month_start_day'] as int;
      } else if (settings['error'] == 'unauthorized') {
        await _handleUnauthorized();
        return;
      }
    }

    final today = _today();
    final range = period.cashFlowPeriod
        .rangeFor(today, monthStartDay: _monthStartDay ?? 1);
    await Future.wait([
      _loadCashFlow(token, range, period, generation),
      _loadNetWorth(token, range, today, generation),
    ]);
  }

  Future<void> _loadCashFlow(
    String token,
    CashFlowDateRange range,
    ReportsPeriod period,
    int generation,
  ) async {
    final results = await Future.wait([
      _cashFlow.getCashFlow(accessToken: token, range: range),
      if (period == ReportsPeriod.month)
        _spending.getSpendingVsNormal(
          accessToken: token,
          startDate: range.start,
          endDate: range.end,
        ),
    ]);
    if (!mounted || generation != _generation) return;
    final cash = results.first;
    final normal = results.length > 1 ? results[1] : null;
    setState(() {
      if (cash['success'] == true) {
        _report = cash['report'] as CashFlowReport;
        _cashStatus = _Status.loaded;
      } else {
        _report = null;
        _cashStatus = _Status.failed;
      }
      _aboveNormal = normal != null && normal['success'] == true
          ? _aboveNormalRatios(normal['spending'] as SpendingVsNormal)
          : const {};
    });
    if (cash['error'] == 'unauthorized' ||
        normal?['error'] == 'unauthorized') {
      await _handleUnauthorized();
    }
  }

  /// Categories meaningfully above normal: at least one unit over (the
  /// threshold the Home spending card uses) and a positive ratio.
  static Map<String, double> _aboveNormalRatios(SpendingVsNormal data) {
    if (!data.comparable) return const {};
    return {
      for (final c in data.categories)
        if (c.id.isNotEmpty &&
            c.change != null &&
            c.change! >= 1 &&
            c.ratio != null &&
            c.ratio! > 0)
          c.id: c.ratio!,
    };
  }

  Future<void> _loadNetWorth(
    String token,
    CashFlowDateRange range,
    DateTime today,
    int generation,
  ) async {
    final accounts = _accounts();
    final currency = _mainCurrency(accounts) ?? '';
    // A budget month can end after today; history stops at today.
    final end = range.end.isAfter(today) ? today : range.end;
    final result = await _netWorth.load(
      accessToken: token,
      accounts: accounts,
      mainCurrency: currency,
      start: range.start,
      end: end,
    );
    if (!mounted || generation != _generation) return;
    setState(() {
      if (result['success'] == true) {
        _history = result['history'] as NetWorthHistory;
        _historyCurrency = currency;
        _historyStart = range.start;
        _netWorthStatus = _Status.loaded;
      } else {
        _history = null;
        _netWorthStatus = _Status.failed;
      }
    });
    if (result['error'] == 'unauthorized') await _handleUnauthorized();
  }

  void _selectPeriod(ReportsPeriod period) {
    if (period == _period) return;
    setState(() {
      _period = period;
      _showAllCategories = false;
      _aboveNormal = const {};
    });
    _load();
  }

  void _openCategory(CashFlowCategory category) {
    final report = _report;
    if (report == null || !category.canDrillDown) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CashFlowCategoryTransactionsScreen(
          category: category,
          range: CashFlowDateRange(report.startDate, report.endDate),
          service: widget.transactionsService,
          categoriesService: widget.categoriesService,
          accessTokenLoader: widget.accessTokenLoader,
          onUnauthorized: widget.onUnauthorized,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final report = _report;
    final empty = _cashStatus == _Status.loaded && report!.isEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(l.p3rpTitle)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            SureSpacing.xl,
            SureSpacing.md,
            SureSpacing.xl,
            SureSpacing.huge,
          ),
          children: [
            _PeriodPicker(selected: _period, onSelected: _selectPeriod),
            const SizedBox(height: SureSpacing.xl),
            _buildNetWorth(context),
            const SizedBox(height: SureSpacing.xl),
            if (empty)
              _SectionMessage(
                key: const ValueKey('reportsEmpty'),
                icon: SureIcons.receipt,
                title: l.p3rpEmpty,
              )
            else ...[
              _buildCashFlow(context),
              const SizedBox(height: SureSpacing.xl),
              _buildSpending(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _failure(BuildContext context, String title) {
    final l = AppLocalizations.of(context);
    return _SectionMessage(
      icon: SureIcons.circleAlert,
      title: title,
      subtitle: _offline ? l.cashFlowOffline : null,
      action: SureButton(
        label: l.commonTryAgain,
        onPressed: _load,
        leading: const SureIcon(SureIcons.refresh, size: 18),
      ),
    );
  }

  Widget _buildNetWorth(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = SureColors.of(context).palette;
    final hidden = context.watch<PrivacyProvider>().hidden;
    final locale = Localizations.localeOf(context).toString();

    Widget body;
    final history = _history;
    if (_netWorthStatus == _Status.loading) {
      body = const _SectionLoading();
    } else if (_netWorthStatus == _Status.failed || history == null) {
      body = _failure(context, l.p3rpNetWorthFailed);
    } else {
      String money(int cents, String currency, {bool signed = false}) =>
          MoneyMasker.mask(
            InvestmentMath.formatMoney(
              InvestmentMath.fromMinorUnits(cents, currency: currency),
              currency: currency,
              locale: locale,
              signed: signed,
            ),
            hidden: hidden,
          );
      final currency = _historyCurrency;
      final selected = _selectedPoint;
      final current = selected?.cents ?? history.currentCents;
      final change = history.changeCents;
      final dates = DateFormat.MMMd(locale);
      final rising = (change ?? 0) >= 0;
      final trendColor = rising ? palette.success : palette.destructive;

      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (current == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: SureSpacing.md),
              child: Text(
                l.p3rpNetWorthNoHistory,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: palette.textSecondary),
              ),
            )
          else ...[
            Text(
              money(current, currency),
              key: const ValueKey('reportsNetWorthValue'),
              style: SureMoney.tabular(theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: SureTokens.weightMedium)),
            ),
            if (selected != null)
              Text(
                DateFormat.yMMMd(locale).format(selected.date),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: palette.textSecondary),
              )
            else if (change != null && _historyStart != null)
              Text(
                l.p3rpNetWorthChange(
                  money(change, currency, signed: true),
                  dates.format(_historyStart!),
                ),
                key: const ValueKey('reportsNetWorthChange'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: trendColor,
                  fontWeight: SureTokens.weightMedium,
                ),
              ),
            if (history.points.length >= 2) ...[
              const SizedBox(height: SureSpacing.lg),
              SizedBox(
                height: 140,
                child: BalanceHistoryChart(
                  key: const ValueKey('reportsNetWorthChart'),
                  balances: _chartBalances(history, currency),
                  color: trendColor,
                  semanticLabel: l.p3rpNetWorthChartLabel,
                  onSelectionChanged: (balance) => setState(() {
                    _selectedPoint = balance == null
                        ? null
                        : NetWorthPoint(balance.date, balance.balanceCents!);
                  }),
                ),
              ),
            ],
          ],
          for (final other in history.otherCurrencies) ...[
            const SizedBox(height: SureSpacing.sm),
            Text(
              l.p3rpNetWorthOtherCurrency(
                money(other.cents, other.currency),
                other.accountCount,
              ),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: palette.textSecondary),
            ),
          ],
        ],
      );
    }

    return _Section(
      key: const ValueKey('reportsNetWorth'),
      title: l.p3rpNetWorth,
      child: body,
    );
  }

  /// Adapts the series to the balance chart's input. Cached by identity so
  /// the chart keeps its selection while the header rebuilds.
  List<AccountBalance> _chartBalances(NetWorthHistory history, String currency) {
    if (identical(_chartSource, history)) return _chartCache;
    _chartSource = history;
    return _chartCache = [
      for (final p in history.points)
        AccountBalance(
          id: p.date.toIso8601String(),
          date: p.date,
          currency: currency,
          balance: '',
          balanceCents: p.cents,
        ),
    ];
  }

  NetWorthHistory? _chartSource;
  List<AccountBalance> _chartCache = const [];

  Widget _buildCashFlow(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = SureColors.of(context).palette;
    final hidden = context.watch<PrivacyProvider>().hidden;

    Widget body;
    final report = _report;
    if (_cashStatus == _Status.loading) {
      body = const _SectionLoading();
    } else if (_cashStatus == _Status.failed || report == null) {
      body = _failure(context, l.p3rpCashFlowFailed);
    } else {
      String money(double v) => MoneyMasker.mask(
            CashFlowFormat.money(context, v, report.currency),
            hidden: hidden,
          );
      final rate = report.savingsRate;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Stat(
                  label: l.p3rpIn,
                  value: money(report.income),
                  trend: MoneyTrend.inflow,
                ),
              ),
              const SizedBox(width: SureSpacing.lg),
              Expanded(
                child: _Stat(
                  label: l.p3rpOut,
                  value: money(report.spending),
                  trend: MoneyTrend.outflow,
                ),
              ),
              const SizedBox(width: SureSpacing.lg),
              Expanded(
                child: _Stat(
                  key: const ValueKey('reportsSaved'),
                  label: l.p3rpSaved,
                  value: money(report.netSavings),
                  trend: report.netSavings < 0
                      ? MoneyTrend.outflow
                      : MoneyTrend.inflow,
                  footnote: rate == null
                      ? null
                      : l.p3rpSavedShare(MoneyMasker.mask(
                          CashFlowFormat.percent(context, rate),
                          hidden: hidden,
                        )),
                ),
              ),
            ],
          ),
          const SizedBox(height: SureSpacing.sm),
          Text(
            '${DateFormat.yMMMd(Localizations.localeOf(context).toString()).format(report.startDate)} – '
            '${DateFormat.yMMMd(Localizations.localeOf(context).toString()).format(report.endDate)}',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: palette.textSubdued),
          ),
        ],
      );
    }

    return _Section(
      key: const ValueKey('reportsCashFlow'),
      title: l.p3rpCashFlow,
      child: body,
    );
  }

  Widget _buildSpending(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = SureColors.of(context).palette;
    final hidden = context.watch<PrivacyProvider>().hidden;
    final locale = Localizations.localeOf(context).toString();

    Widget body;
    final report = _report;
    if (_cashStatus == _Status.loading) {
      body = const _SectionLoading();
    } else if (_cashStatus == _Status.failed || report == null) {
      // The cash flow section above already offers a retry.
      body = Text(
        l.p3rpCashFlowFailed,
        style: theme.textTheme.bodyMedium
            ?.copyWith(color: palette.textSecondary),
      );
    } else if (report.expenseCategories.isEmpty) {
      body = Text(
        l.p3rpNoSpending,
        style: theme.textTheme.bodyMedium
            ?.copyWith(color: palette.textSecondary),
      );
    } else {
      final all = report.expenseCategories;
      final shown = _showAllCategories
          ? all
          : all.take(ReportsScreen.topCategoryCount).toList();
      final largest = all.first.amount;
      final percentFormat = NumberFormat.percentPattern(locale);
      String? aboveNormal(CashFlowCategory category) {
        final ratio = _aboveNormal[category.categoryId];
        return ratio == null ? null : '+${percentFormat.format(ratio)}';
      }

      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final category in shown)
            _CategoryBar(
              key: ValueKey('reportsCategory_${category.id}'),
              name: category.name,
              amount: MoneyMasker.mask(
                CashFlowFormat.money(context, category.amount, report.currency),
                hidden: hidden,
              ),
              fraction: largest > 0 ? category.amount / largest : 0,
              color: CashFlowDonutChart.colorFromHex(
                  category.color, palette.textSubdued),
              aboveNormal: aboveNormal(category),
              onTap: category.canDrillDown
                  ? () => _openCategory(category)
                  : null,
            ),
          if (all.length > ReportsScreen.topCategoryCount)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: const ValueKey('reportsShowAll'),
                onPressed: () => setState(
                    () => _showAllCategories = !_showAllCategories),
                child: Text(_showAllCategories
                    ? l.p3rpShowLess
                    : l.p3rpShowAll(all.length)),
              ),
            ),
        ],
      );
    }

    return _Section(
      key: const ValueKey('reportsSpending'),
      title: l.p3rpSpending,
      child: body,
    );
  }
}

class _PeriodPicker extends StatelessWidget {
  const _PeriodPicker({required this.selected, required this.onSelected});

  final ReportsPeriod selected;
  final ValueChanged<ReportsPeriod> onSelected;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Wrap(
      spacing: SureSpacing.md,
      runSpacing: SureSpacing.md,
      children: [
        for (final period in ReportsPeriod.values)
          SureChip(
            key: ValueKey('reportsPeriod_${period.name}'),
            label: period.label(l),
            selected: period == selected,
            onSelected: (_) => onSelected(period),
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = SureColors.of(context).palette;
    return SureCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: theme.textTheme.labelLarge
                ?.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: SureSpacing.md),
          child,
        ],
      ),
    );
  }
}

class _SectionLoading extends StatelessWidget {
  const _SectionLoading();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: SureSpacing.huge),
        child: Center(child: CircularProgressIndicator()),
      );
}

class _Stat extends StatelessWidget {
  const _Stat({
    super.key,
    required this.label,
    required this.value,
    required this.trend,
    this.footnote,
  });

  final String label;
  final String value;
  final MoneyTrend trend;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium
              ?.copyWith(color: palette.textSecondary),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: MoneyText(
            value,
            trend: trend,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: SureTokens.weightMedium),
          ),
        ),
        if (footnote != null)
          Text(
            footnote!,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: palette.textSecondary),
          ),
      ],
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    super.key,
    required this.name,
    required this.amount,
    required this.fraction,
    required this.color,
    this.aboveNormal,
    this.onTap,
  });

  final String name;
  final String amount;
  final double fraction;
  final Color color;

  /// Signed percent above normal, e.g. `+32%`; null when not above normal.
  final String? aboveNormal;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = SureColors.of(context).palette;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SureTokens.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SureSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                if (aboveNormal != null) ...[
                  Semantics(
                    label: l.p3rpAboveNormal(aboveNormal!),
                    excludeSemantics: true,
                    child: Text(
                      aboveNormal!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: palette.destructive,
                        fontWeight: SureTokens.weightMedium,
                      ),
                    ),
                  ),
                  const SizedBox(width: SureSpacing.md),
                ],
                Text(
                  amount,
                  style: SureMoney.tabular(theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: SureTokens.weightMedium,
                    color: palette.textPrimary,
                  )),
                ),
                if (onTap != null)
                  SureIcon(
                    SureIcons.chevronRight,
                    size: SureIconSize.sm,
                    color: palette.textSubdued,
                  )
                else
                  const SizedBox(width: SureIconSize.sm),
              ],
            ),
            const SizedBox(height: SureSpacing.xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 6,
                child: Stack(
                  children: [
                    Container(color: palette.surfaceInset),
                    FractionallySizedBox(
                      widthFactor: fraction.clamp(0.0, 1.0),
                      child: Container(color: color),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionMessage extends StatelessWidget {
  const _SectionMessage({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  final String icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SureSpacing.xl),
      child: Column(
        children: [
          SureIcon(icon, size: SureIconSize.xl, color: palette.textSubdued),
          const SizedBox(height: SureSpacing.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: SureSpacing.xs),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: palette.textSecondary),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: SureSpacing.lg),
            action!,
          ],
        ],
      ),
    );
  }
}
