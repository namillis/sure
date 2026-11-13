import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../models/category.dart';
import '../models/recurring_transaction.dart';
import '../providers/accounts_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/categories_provider.dart';
import '../providers/privacy_provider.dart';
import '../providers/server_features_provider.dart';
import '../services/connectivity_service.dart';
import '../services/recurring_transactions_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_tokens.dart';
import '../utils/bills_sections.dart';
import '../utils/investment_math.dart';
import '../utils/money_masker.dart';
import '../utils/recurring_grouping.dart';
import '../widgets/budget_progress_bar.dart';
import '../widgets/connectivity_banner.dart';
import '../widgets/ds/ds.dart';
import '../widgets/open_on_web_action.dart';
import 'recurring_form_screen.dart';
import 'recurring_screen.dart' show recurringCadenceLabel;

/// The Bills segment of the Plan tab, laid out like the web Bills overview:
/// a "left to pay" summary for the month, then Overdue, Due this month, Paid
/// this month (folded), Later and Paused (folded). Built from the recurring
/// transactions API only; tapping a row opens the recurring editor sheet.
class BillsScreen extends StatefulWidget {
  const BillsScreen({
    super.key,
    this.service,
    this.accessTokenLoader,
    this.onUnauthorized,
    this.accounts,
    this.familyCurrency,
    this.clock,
  });

  /// Injected for tests; otherwise the screen owns one.
  final RecurringTransactionsService? service;

  /// Defaults to [AuthProvider.getValidAccessToken].
  final Future<String?> Function()? accessTokenLoader;

  /// Defaults to [AuthProvider.logout].
  final Future<void> Function()? onUnauthorized;

  /// Accounts offered in the editor; defaults to [AccountsProvider.accounts].
  final List<Account>? accounts;

  /// Currency of the totals; defaults to [AccountsProvider.familyCurrency].
  final String? familyCurrency;

  /// "Today" for the sections; injected for tests.
  final DateTime Function()? clock;

  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  late final RecurringTransactionsService _service;
  List<RecurringTransaction>? _items;
  DateTime? _loadedAt;
  bool _loading = true;
  bool _offline = false;
  bool _showPaid = false;
  bool _showPaused = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? RecurringTransactionsService();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    if (widget.service == null) _service.close();
    super.dispose();
  }

  T? _maybeRead<T>() {
    try {
      return context.read<T>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  DateTime _now() => (widget.clock ?? DateTime.now)();

  Future<String?> _token() {
    final loader = widget.accessTokenLoader;
    if (loader != null) return loader();
    return context.read<AuthProvider>().getValidAccessToken();
  }

  Future<void> _unauthorized() async {
    final handler = widget.onUnauthorized;
    if (handler != null) return handler();
    await context.read<AuthProvider>().logout();
  }

  List<Account> get _accounts =>
      widget.accounts ?? _maybeRead<AccountsProvider>()?.accounts ?? const [];

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final token = await _token();
    if (!mounted) return;
    if (token == null) {
      await _unauthorized();
      return;
    }
    // Rows show their category's icon. Sure+ servers embed it in each row
    // (`recurring.category`), so the shared list is fetched only for rows
    // that lack it; stock Sure needs the list, fetched alongside.
    final embedsCategory = context
            .read<ServerFeaturesProvider?>()
            ?.has(ServerFeaturesProvider.recurringCategory) ??
        false;
    final categories = context.read<CategoriesProvider?>();
    if (!embedsCategory) categories?.fetchCategories(accessToken: token);
    final result = await _service.getAll(accessToken: token);
    if (!mounted) return;
    if (result['error'] == 'unauthorized') {
      await _unauthorized();
      return;
    }
    if (embedsCategory &&
        result['success'] == true &&
        (result['recurring_transactions'] as List<dynamic>)
            .cast<RecurringTransaction>()
            .any((item) => item.needsCategoryLookup)) {
      categories?.fetchCategories(accessToken: token);
    }
    final ok = result['success'] == true;
    final offline =
        !ok && (_maybeRead<ConnectivityService>()?.isOffline ?? false);
    if (!ok && _items != null && !offline) {
      // Keep the list on a failed refresh; say so instead of blanking it.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context).billsRefreshFailed)));
    }
    setState(() {
      _loading = false;
      _offline = offline;
      if (ok) {
        _items = (result['recurring_transactions'] as List<dynamic>)
            .cast<RecurringTransaction>();
        _loadedAt = _now();
      }
    });
  }

  Future<void> _openEditor(RecurringTransaction item) async {
    final changed = await showSureSheet<bool>(
      context: context,
      builder: (_) => RecurringFormScreen(
        existing: item,
        accounts: _accounts,
        service: _service,
        accessTokenLoader: _token,
        onUnauthorized: _unauthorized,
        clock: widget.clock,
      ),
    );
    if (changed == true && mounted) {
      SureHaptics.success();
      await _load();
    }
  }

  Future<void> _openPayment(String url) async {
    final uri = billPaymentUri(url);
    var opened = false;
    if (uri != null) {
      try {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        opened = false;
      }
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context).shellWebOpenFailed)));
    }
  }

  void _openWebBills() {
    final l = AppLocalizations.of(context);
    openWebFallback(context, title: l.shellPlanBills, path: '/bills');
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final items = _items;
    final bills = items?.where(BillsSections.isBill).toList();

    final List<Widget> children;
    if (items == null && _loading) {
      children = const [
        Padding(
          padding: EdgeInsets.only(top: 96),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    } else if (items == null) {
      children = [
        _state(_offline
            ? SureEmptyState(
                icon: SureIcons.cloudOff,
                title: l.billsOfflineTitle,
                body: l.billsOfflineBody,
                secondaryLabel: l.commonTryAgain,
                onSecondary: _load,
              )
            : SureEmptyState(
                icon: SureIcons.circleAlert,
                title: l.billsLoadFailed,
                secondaryLabel: l.commonTryAgain,
                onSecondary: _load,
              )),
      ];
    } else if (bills!.isEmpty) {
      children = [
        _state(SureEmptyState(
          icon: SureIcons.receipt,
          title: l.billsEmptyTitle,
          body: l.billsEmptyBody,
          primaryLabel: l.billsFindOnWeb,
          onPrimary: _openWebBills,
        )),
      ];
    } else {
      children = _list(context, bills);
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        // Clears the shell's see-through tab bar.
        padding: EdgeInsets.only(
          bottom: 32 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          if (items != null)
            ConnectivityBanner(
              updatedAt: _loadedAt,
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            ),
          ...children,
        ],
      ),
    );
  }

  Widget _state(Widget child) => Padding(
        padding: const EdgeInsets.only(top: 48),
        child: Center(child: child),
      );

  List<Widget> _list(BuildContext context, List<RecurringTransaction> bills) {
    final l = AppLocalizations.of(context);
    final now = _now();
    final sections = BillsSections.group(bills, now);
    final currency = BillsSections.mainCurrency(
      bills,
      widget.familyCurrency ?? _maybeRead<AccountsProvider>()?.familyCurrency,
    );
    final categories = {
      for (final category in context.watch<CategoriesProvider?>()?.categories ??
          const <Category>[])
        category.id: category,
    };
    final hasMonth = sections[BillsSection.overdue]!.isNotEmpty ||
        sections[BillsSection.dueThisMonth]!.isNotEmpty ||
        sections[BillsSection.paidThisMonth]!.isNotEmpty;

    Widget panel(BillsSection section) => Opacity(
          opacity: section == BillsSection.paused ? 0.55 : 1,
          child: SurePanel.rows(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            dividerIndent: SurePanel.iconRowDividerIndent,
            children: [
              for (final item in sections[section]!)
                BillRow(
                  key: ValueKey('bill-${item.id}'),
                  item: item,
                  section: section,
                  category: item.resolveCategory(categories),
                  now: now,
                  onTap: () => _openEditor(item),
                  onPay: item.paymentUrl != null &&
                          billPaymentUri(item.paymentUrl!) != null
                      ? () => _openPayment(item.paymentUrl!)
                      : null,
                ),
            ],
          ),
        );

    Widget folded(BillsSection section, String label, bool open,
            VoidCallback toggle) =>
        SureSectionHeader(
          key: ValueKey('billsHeader-${section.name}'),
          label: label,
          actionLabel: open ? l.billsHide : l.billsShow,
          onAction: toggle,
        );

    final paid = sections[BillsSection.paidThisMonth]!;
    final paused = sections[BillsSection.paused]!;
    return [
      if (hasMonth)
        BillsSummaryHeader(
          summary: BillsSections.summary(sections, currency),
          currency: currency,
          month: now,
        ),
      if (sections[BillsSection.overdue]!.isNotEmpty) ...[
        SureSectionHeader(label: l.billsSectionOverdue),
        panel(BillsSection.overdue),
      ],
      if (sections[BillsSection.dueThisMonth]!.isNotEmpty) ...[
        SureSectionHeader(label: l.billsSectionDue),
        panel(BillsSection.dueThisMonth),
      ],
      if (paid.isNotEmpty) ...[
        folded(BillsSection.paidThisMonth, l.billsSectionPaid(paid.length),
            _showPaid, () => setState(() => _showPaid = !_showPaid)),
        if (_showPaid) panel(BillsSection.paidThisMonth),
      ],
      if (sections[BillsSection.later]!.isNotEmpty) ...[
        SureSectionHeader(label: l.billsSectionLater),
        panel(BillsSection.later),
      ],
      if (paused.isNotEmpty) ...[
        folded(BillsSection.paused, l.billsSectionPaused(paused.length),
            _showPaused, () => setState(() => _showPaused = !_showPaused)),
        if (_showPaused) panel(BillsSection.paused),
      ],
    ];
  }
}

/// [url] as a link the Pay button may open: http or https only.
Uri? billPaymentUri(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasAuthority) return null;
  return uri.scheme == 'http' || uri.scheme == 'https' ? uri : null;
}

/// "November", then "$420.00 left to pay", the mono line
/// "$80.00 paid of $500.00 · 2 of 6 bills" and a paid / total progress bar.
class BillsSummaryHeader extends StatelessWidget {
  const BillsSummaryHeader({
    super.key,
    required this.summary,
    required this.currency,
    required this.month,
  });

  final BillsSummary summary;
  final String currency;
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final locale = Localizations.localeOf(context).toString();
    final hidden = context.watch<PrivacyProvider>().hidden;
    String money(double value) => MoneyMasker.mask(
          InvestmentMath.formatMoney(value, currency: currency, locale: locale),
          hidden: hidden,
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat.MMMM(locale).format(month),
            key: const ValueKey('billsMonthLabel'),
            style: TextStyle(fontSize: 13, color: palette.textSecondary),
          ),
          const SizedBox(height: 2),
          Text.rich(
            key: const ValueKey('billsLeftToPay'),
            TextSpan(children: [
              TextSpan(
                text: money(summary.leftToPay),
                style: SureMoney.tabular(TextStyle(
                  fontSize: 32,
                  height: 1.2,
                  fontWeight: SureTokens.weightSemibold,
                  color: palette.textPrimary,
                )),
              ),
              TextSpan(
                text: ' ${l.billsLeftToPay}',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w400,
                  color: palette.textSecondary,
                ),
              ),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            l.billsPaidOf(money(summary.paid), money(summary.total),
                summary.paidCount, summary.billCount),
            key: const ValueKey('billsPaidOf'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: SureMoney.tabular(
                TextStyle(fontSize: 13, color: palette.textSecondary)),
          ),
          if (summary.otherCurrencyCount > 0) ...[
            const SizedBox(height: 2),
            Text(
              l.billsOtherCurrencies(summary.otherCurrencyCount),
              key: const ValueKey('billsOtherCurrencies'),
              style: TextStyle(fontSize: 12, color: palette.textSubdued),
            ),
          ],
          const SizedBox(height: 12),
          BudgetProgressBar(fraction: summary.paidFraction, hidden: hidden),
        ],
      ),
    );
  }
}

/// One bill: category icon, name, type and trial/renewal tags, a date line
/// for its section, the amount and, with a payment link, a small Pay button.
class BillRow extends StatelessWidget {
  const BillRow({
    super.key,
    required this.item,
    required this.section,
    required this.now,
    required this.onTap,
    this.onPay,
    this.category,
  });

  final RecurringTransaction item;
  final BillsSection section;
  final DateTime now;
  final Category? category;
  final VoidCallback onTap;

  /// Opens the payment link; null hides the Pay button.
  final VoidCallback? onPay;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final locale = Localizations.localeOf(context).toString();
    final hidden = context.watch<PrivacyProvider>().hidden;
    String date(DateTime d) => SureDates.short(d, locale: locale, now: now);

    final today = DateTime(now.year, now.month, now.day);
    bool future(DateTime? d) => d != null && !d.isBefore(today);
    final tags = [
      if (item.billType == 'subscription') l.billsTypeSubscription,
      if (item.billType == 'installment') l.billsTypeInstallment,
      if (future(item.trialEndsOn))
        l.billsTrialEnds(date(item.trialEndsOn!))
      else if (future(item.renewsOn))
        l.billsRenews(date(item.renewsOn!)),
    ];

    final next = item.nextExpectedDate;
    final last = item.lastOccurrenceDate;
    final String? when = switch (section) {
      BillsSection.overdue => next == null ? null : l.billsDueOn(date(next)),
      BillsSection.paidThisMonth =>
        last == null ? null : l.billsPaidOn(date(last)),
      BillsSection.later || BillsSection.paused => [
          recurringCadenceLabel(l, item),
          if (next != null) date(next),
        ].join(' · '),
      BillsSection.dueThisMonth => next == null ? null : date(next),
    };
    final subtitle = [
      if (when != null) when,
      if (item.autopay) l.billsAutopay,
    ].join(' · ');
    final overdue = section == BillsSection.overdue;

    final amount = MoneyText(
      MoneyMasker.mask(
        InvestmentMath.formatMoney(RecurringGrouping.amountOf(item),
            currency: item.currency, locale: locale),
        hidden: hidden,
      ),
      trend: MoneyTrend.neutral,
      color: palette.textPrimary,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
    );

    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            _leading(palette),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.25,
                      fontWeight: SureTokens.weightMedium,
                      color: palette.textPrimary,
                    ),
                  ),
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [for (final tag in tags) _Tag(tag)],
                    ),
                  ],
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (section == BillsSection.paidThisMonth) ...[
                          SureIcon(SureIcons.check,
                              size: 13, color: palette.success),
                          const SizedBox(width: 3),
                        ],
                        Flexible(
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.25,
                              color: overdue
                                  ? palette.destructive
                                  : palette.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                amount,
                if (onPay != null) ...[
                  const SizedBox(height: 4),
                  _PayButton(
                    onPressed: onPay!,
                    semanticLabel: l.billsPaySemantics(item.displayName),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );

    return ColoredBox(
      color: palette.container,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(onTap: onTap, child: content),
      ),
    );
  }

  Widget _leading(SureTokenPalette palette) {
    final category = this.category;
    if (category != null) {
      return SureCategoryIcon(
        name: category.name,
        color: category.color,
        icon: category.icon,
      );
    }
    return Container(
      width: SureCategoryIcon.rowSize,
      height: SureCategoryIcon.rowSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.surfaceInset,
        shape: BoxShape.circle,
      ),
      child:
          SureIcon(SureIcons.receipt, size: 15, color: palette.textSecondary),
    );
  }
}

/// A small read-only pill. Gap: SureChip is a 32 px filter chip, too big
/// for a row, so the bill tags use this.
class _Tag extends StatelessWidget {
  const _Tag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = SureColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: ShapeDecoration(
        shape: StadiumBorder(side: BorderSide(color: colors.hairline)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          height: 1.3,
          fontWeight: SureTokens.weightMedium,
          color: colors.palette.textSecondary,
        ),
      ),
    );
  }
}

/// "Pay ↗": a compact outlined link button that opens the payment page.
class _PayButton extends StatelessWidget {
  const _PayButton({required this.onPressed, required this.semanticLabel});

  final VoidCallback onPressed;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = SureColors.of(context);
    final palette = colors.palette;
    final l = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: const ValueKey('billPayButton'),
          onTap: onPressed,
          customBorder: const StadiumBorder(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: ShapeDecoration(
              shape: StadiumBorder(side: BorderSide(color: colors.hairline)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l.billsPay,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: SureTokens.weightMedium,
                    color: palette.link,
                  ),
                ),
                const SizedBox(width: 2),
                SureIcon(SureIcons.arrowUpRight, size: 12, color: palette.link),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
