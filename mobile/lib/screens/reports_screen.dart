import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../models/account_balance.dart';
import '../models/cash_flow.dart';
import '../models/category.dart';
import '../models/spending_vs_normal.dart';
import '../providers/accounts_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/categories_provider.dart';
import '../providers/privacy_provider.dart';
import '../services/cash_flow_service.dart';
import '../services/categories_service.dart';
import '../services/connectivity_service.dart';
import '../services/net_worth_history_service.dart';
import '../services/spending_vs_normal_service.dart';
import '../services/transactions_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_tokens.dart';
import '../utils/investment_math.dart';
import '../utils/money_masker.dart';
import '../utils/net_worth_history.dart';
import '../widgets/balance_history_chart.dart';
import '../widgets/cash_flow_donut_chart.dart';
import '../widgets/ds/ds.dart';
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
    // Category rows show their icon; the list is shared and fetched once.
    _maybeRead<CategoriesProvider>()?.fetchCategories(accessToken: token);

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

    return SureLargeTitleScaffold(
      title: l.p3rpTitle,
      // Reports opens from Home's "Reports" row.
      leading: Navigator.of(context).canPop()
          ? SureBackButton(label: l.navHome)
          : null,
      onRefresh: _load,
      slivers: [
        SliverList.list(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child:
                  _PeriodPicker(selected: _period, onSelected: _selectPeriod),
            ),
            _buildNetWorth(context),
            if (empty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                child: SurePanel(
                  key: const ValueKey('reportsEmpty'),
                  child: SureEmptyState(
                    icon: SureIcons.receipt,
                    title: l.cashFlowTransactionsEmpty,
                    body: l.ds3rEmptyBody,
                  ),
                ),
              )
            else ...[
              _buildCashFlow(context),
              _buildSpending(context),
            ],
          ],
        ),
      ],
    );
  }

  Widget _failure(BuildContext context, String title) {
    final l = AppLocalizations.of(context);
    return SureEmptyState(
      icon: SureIcons.circleAlert,
      title: title,
      body: _offline ? l.cashFlowOffline : null,
      secondaryLabel: l.commonTryAgain,
      onSecondary: _load,
    );
  }

  /// A section: its header, then [panel] inset 16 px from the edges.
  Widget _section({
    required Key key,
    required Widget header,
    required Widget panel,
  }) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: panel,
        ),
      ],
    );
  }

  Widget _buildNetWorth(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final hidden = context.watch<PrivacyProvider>().hidden;
    final locale = Localizations.localeOf(context).toString();

    Widget panel;
    final history = _history;
    if (_netWorthStatus == _Status.loading) {
      panel = const SurePanel(child: _SectionLoading());
    } else if (_netWorthStatus == _Status.failed || history == null) {
      panel = SurePanel(child: _failure(context, l.p3rpNetWorthFailed));
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
      final rising = (change ?? 0) >= 0;
      final trendColor = rising ? palette.success : palette.destructive;

      panel = SurePanel(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (current == null)
              Text(
                l.p3rpNetWorthNoHistory,
                style: TextStyle(fontSize: 13, color: palette.textSecondary),
              )
            else ...[
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: MoneyText(
                  money(current, currency),
                  key: const ValueKey('reportsNetWorthValue'),
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
              if (selected != null)
                Text(
                  SureDates.fullOf(context, selected.date),
                  key: const ValueKey('reportsNetWorthScrubDate'),
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: palette.textSecondary,
                  ),
                )
              else if (change != null && _historyStart != null)
                Text.rich(
                  key: const ValueKey('reportsNetWorthChange'),
                  TextSpan(children: [
                    TextSpan(
                      text: money(change, currency, signed: true),
                      style: SureMoney.tabular(TextStyle(
                        color: trendColor,
                        fontWeight: SureTokens.weightMedium,
                      )),
                    ),
                    TextSpan(
                      text: ' ${l.ds3rSince(SureDates.shortOf(
                        context,
                        _historyStart!,
                        now: _today(),
                      ))}',
                      style: TextStyle(color: palette.textSubdued),
                    ),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
              if (history.points.length >= 2) ...[
                const SizedBox(height: 12),
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
              const SizedBox(height: 8),
              Text(
                l.ds3rOtherCurrency(
                  money(other.cents, other.currency),
                  other.accountCount,
                ),
                style: TextStyle(fontSize: 13, color: palette.textSecondary),
              ),
            ],
          ],
        ),
      );
    }

    return _section(
      key: const ValueKey('reportsNetWorth'),
      header: SureSectionHeader(label: l.p3rpNetWorth),
      panel: panel,
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
    final palette = SureColors.of(context).palette;
    final hidden = context.watch<PrivacyProvider>().hidden;

    Widget panel;
    String? range;
    final report = _report;
    if (_cashStatus == _Status.loading) {
      panel = const SurePanel(child: _SectionLoading());
    } else if (_cashStatus == _Status.failed || report == null) {
      panel = SurePanel(child: _failure(context, l.p3rpCashFlowFailed));
    } else {
      String money(double v) => MoneyMasker.mask(
            CashFlowFormat.money(context, v, report.currency),
            hidden: hidden,
          );
      Widget amount(String text, MoneyTrend trend, Color color,
              {FontWeight weight = SureTokens.weightMedium}) =>
          MoneyText(
            text,
            trend: trend,
            color: color,
            maxLines: 1,
            style: TextStyle(fontSize: 15, fontWeight: weight),
          );
      range = SureDates.rangeOf(context, report.startDate, report.endDate,
          now: _today());
      final rate = report.savingsRate;
      final saved = report.netSavings;
      panel = SurePanel.rows(
        children: [
          SureListRow(
            key: const ValueKey('reportsIn'),
            title: l.p3rpIn,
            trailing: amount(
              report.income > 0 ? '+${money(report.income)}' : money(0),
              MoneyTrend.inflow,
              report.income > 0 ? palette.success : palette.textPrimary,
            ),
          ),
          SureListRow(
            key: const ValueKey('reportsOut'),
            title: l.p3rpOut,
            trailing: amount(
              report.spending > 0 ? '-${money(report.spending)}' : money(0),
              MoneyTrend.outflow,
              palette.textPrimary,
            ),
          ),
          SureListRow(
            key: const ValueKey('reportsSaved'),
            title: l.p3rpSaved,
            subtitle: rate == null
                ? null
                : l.p3rpSavedShare(MoneyMasker.mask(
                    CashFlowFormat.percent(context, rate),
                    hidden: hidden,
                  )),
            trailing: amount(
              money(saved),
              saved < 0 ? MoneyTrend.outflow : MoneyTrend.inflow,
              saved < 0 ? palette.destructive : palette.success,
              weight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    return _section(
      key: const ValueKey('reportsCashFlow'),
      header: Row(
        children: [
          Expanded(
            child: SureSectionHeader(
              label: l.p3rpCashFlow,
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 6),
            ),
          ),
          if (range != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 16, 16, 6),
              child: Text(
                range,
                key: const ValueKey('reportsCashFlowRange'),
                maxLines: 1,
                style: TextStyle(fontSize: 13, color: palette.textSubdued),
              ),
            ),
        ],
      ),
      panel: panel,
    );
  }

  Widget _buildSpending(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final hidden = context.watch<PrivacyProvider>().hidden;
    final locale = Localizations.localeOf(context).toString();

    Widget message(String text) => SurePanel(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Text(
            text,
            style: TextStyle(fontSize: 15, color: palette.textSecondary),
          ),
        );

    Widget panel;
    final report = _report;
    if (_cashStatus == _Status.loading) {
      panel = const SurePanel(child: _SectionLoading());
    } else if (_cashStatus == _Status.failed || report == null) {
      // The cash flow section above already offers a retry.
      panel = message(l.p3rpCashFlowFailed);
    } else if (report.expenseCategories.isEmpty) {
      panel = message(l.p3rpNoSpending);
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

      // The cash flow report has colors but no icons; the shared category
      // list fills them in once loaded.
      final known = <String, Category>{
        for (final c in context.watch<CategoriesProvider?>()?.categories ??
            const <Category>[])
          c.id: c,
      };

      panel = SurePanel.rows(
        dividerIndent: SurePanel.iconRowDividerIndent,
        children: [
          for (final category in shown)
            _CategoryRow(
              key: ValueKey('reportsCategory_${category.id}'),
              name: category.name,
              colorHex: category.color ?? known[category.categoryId]?.color,
              icon: known[category.categoryId]?.icon,
              amount: MoneyMasker.mask(
                CashFlowFormat.money(context, category.amount, report.currency),
                hidden: hidden,
              ),
              fraction: largest > 0 ? category.amount / largest : 0,
              barColor: CashFlowDonutChart.colorFromHex(
                  category.color, palette.textSubdued),
              aboveNormal: aboveNormal(category),
              onTap: category.canDrillDown
                  ? () => _openCategory(category)
                  : null,
            ),
          if (all.length > ReportsScreen.topCategoryCount)
            SureListRow(
              key: const ValueKey('reportsShowAll'),
              title: _showAllCategories
                  ? l.p3rpShowLess
                  : l.p3rpShowAll(all.length),
              titleColor: palette.link,
              onTap: () =>
                  setState(() => _showAllCategories = !_showAllCategories),
            ),
        ],
      );
    }

    return _section(
      key: const ValueKey('reportsSpending'),
      header: SureSectionHeader(label: l.p3rpSpending),
      panel: panel,
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
      spacing: 8,
      runSpacing: 8,
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

class _SectionLoading extends StatelessWidget {
  const _SectionLoading();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
}

/// A spending row: the category icon, the name with its above-normal share
/// (Month only), the mono amount, and under them a 4 px bar in the
/// category's color, as wide as its share of the largest category.
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    super.key,
    required this.name,
    required this.amount,
    required this.fraction,
    required this.barColor,
    this.colorHex,
    this.icon,
    this.aboveNormal,
    this.onTap,
  });

  final String name;
  final String amount;
  final double fraction;
  final Color barColor;

  /// The category's `#rrggbb` color and Lucide icon, for its icon.
  final String? colorHex;
  final String? icon;

  /// Signed percent above normal, e.g. `+32%`; null when not above normal.
  final String? aboveNormal;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    Widget row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            SureCategoryIcon(name: name, color: colorHex, icon: icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  height: 1.25,
                                  fontWeight: SureTokens.weightMedium,
                                  color: palette.textPrimary,
                                ),
                              ),
                            ),
                            if (aboveNormal != null) ...[
                              const SizedBox(width: 6),
                              Semantics(
                                label: l.p3rpAboveNormal(aboveNormal!),
                                excludeSemantics: true,
                                child: Text(
                                  aboveNormal!,
                                  maxLines: 1,
                                  style: SureMoney.tabular(TextStyle(
                                    fontSize: 12,
                                    fontWeight: SureTokens.weightMedium,
                                    color: palette.destructive,
                                  )),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      MoneyText(
                        amount,
                        trend: MoneyTrend.neutral,
                        color: palette.textPrimary,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: SureTokens.weightMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FractionallySizedBox(
                      widthFactor: fraction.clamp(0.0, 1.0),
                      child: Container(
                        key: const ValueKey('reportsCategoryBar'),
                        height: 4,
                        decoration: BoxDecoration(
                          color: barColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (onTap != null) {
      row = MergeSemantics(
        child: Semantics(
          button: true,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(onTap: onTap, child: row),
          ),
        ),
      );
    }
    return row;
  }
}
