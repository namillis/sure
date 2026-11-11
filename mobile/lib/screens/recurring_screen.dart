import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../models/category.dart';
import '../models/recurring_transaction.dart';
import '../providers/accounts_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/categories_provider.dart';
import '../providers/privacy_provider.dart';
import '../services/recurring_transactions_service.dart';
import '../theme/sure_colors.dart';
import '../utils/investment_math.dart';
import '../utils/money_masker.dart';
import '../utils/recurring_grouping.dart';
import '../widgets/ds/ds.dart';
import 'recurring_form_screen.dart';

/// The Recurring segment of the Plan tab: a mono "Monthly out · in" line,
/// then active items due this month, later ones, suggestions and inactive
/// ones. Tap a row to edit it in a sheet; swipe it left to pause, resume or
/// delete. Built to sit inside a parent Scaffold, so it has no app bar of its
/// own.
class RecurringScreen extends StatefulWidget {
  const RecurringScreen({
    super.key,
    this.service,
    this.accessTokenLoader,
    this.onUnauthorized,
    this.accounts,
    this.clock,
  });

  /// Injected for tests; otherwise the screen owns one.
  final RecurringTransactionsService? service;

  /// Defaults to [AuthProvider.getValidAccessToken].
  final Future<String?> Function()? accessTokenLoader;

  /// Defaults to [AuthProvider.logout].
  final Future<void> Function()? onUnauthorized;

  /// Accounts offered in the form; defaults to [AccountsProvider.accounts].
  final List<Account>? accounts;

  /// "Today" for grouping and the form's default dates; injected for tests.
  final DateTime Function()? clock;

  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> {
  late final RecurringTransactionsService _service;
  List<RecurringTransaction>? _items;
  bool _loading = true;
  bool _failed = false;

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

  List<Account> get _accounts {
    if (widget.accounts != null) return widget.accounts!;
    try {
      return context.read<AccountsProvider>().accounts;
    } on ProviderNotFoundException {
      return const [];
    }
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final token = await _token();
    if (!mounted) return;
    if (token == null) {
      await _unauthorized();
      return;
    }
    // Rows show their category's icon; the list is shared and fetched once.
    context.read<CategoriesProvider?>()?.fetchCategories(accessToken: token);
    final result = await _service.getAll(accessToken: token);
    if (!mounted) return;
    if (result['error'] == 'unauthorized') {
      await _unauthorized();
      return;
    }
    if (result['success'] != true && _items != null) {
      // Keep the list on a failed refresh; say so instead of blanking it.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context).recurringLoadFailed)));
    }
    setState(() {
      _loading = false;
      _failed = result['success'] != true;
      if (!_failed) {
        _items = (result['recurring_transactions'] as List<dynamic>)
            .cast<RecurringTransaction>();
      }
    });
  }

  Future<void> _openForm([RecurringTransaction? existing]) async {
    final changed = await showSureSheet<bool>(
      context: context,
      builder: (_) => RecurringFormScreen(
        existing: existing,
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

  Future<void> _setStatus(RecurringTransaction item, String status) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final token = await _token();
    if (token == null) return _unauthorized();
    final result = await _service.update(
      accessToken: token,
      id: item.id,
      attributes: {'status': status},
    );
    if (!mounted) return;
    if (result['error'] == 'unauthorized') return _unauthorized();
    messenger.showSnackBar(SnackBar(
      content: Text(result['success'] == true
          ? (status == 'active'
              ? l.recurringActivatedMessage(item.displayName)
              : l.recurringPausedMessage(item.displayName))
          : l.recurringActionFailed),
    ));
    if (result['success'] == true) await _load();
  }

  Future<void> _delete(RecurringTransaction item) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await confirmRecurringDelete(context, item);
    if (!confirmed || !mounted) return;
    final token = await _token();
    if (token == null) return _unauthorized();
    final result = await _service.delete(accessToken: token, id: item.id);
    if (!mounted) return;
    if (result['error'] == 'unauthorized') return _unauthorized();
    messenger.showSnackBar(SnackBar(
      content: Text(result['success'] == true
          ? l.recurringDeleted
          : l.recurringActionFailed),
    ));
    if (result['success'] == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final items = _items;

    final List<Widget> children;
    if (items == null && _loading) {
      children = const [
        Padding(
          padding: EdgeInsets.only(top: 96),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    } else if (items == null || (_failed && items.isEmpty)) {
      children = [
        _state(SureEmptyState(
          icon: SureIcons.circleAlert,
          title: l.recurringLoadFailed,
          secondaryLabel: l.recurringRetry,
          onSecondary: _load,
        )),
      ];
    } else if (items.isEmpty) {
      children = [
        _state(SureEmptyState(
          icon: SureIcons.repeat,
          title: l.recurringEmptyTitle,
          body: l.recurringEmptyBody,
          primaryLabel: l.recurringAdd,
          onPrimary: () => _openForm(),
        )),
      ];
    } else {
      children = _list(context, items);
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        // Clears the shell's see-through tab bar.
        padding: EdgeInsets.only(
          bottom: 32 + MediaQuery.paddingOf(context).bottom,
        ),
        children: children,
      ),
    );
  }

  Widget _state(Widget child) => Padding(
        padding: const EdgeInsets.only(top: 48),
        child: Center(child: child),
      );

  List<Widget> _list(BuildContext context, List<RecurringTransaction> items) {
    final l = AppLocalizations.of(context);
    final now = (widget.clock ?? DateTime.now)();
    final groups = RecurringGrouping.group(items, now);
    final totals = RecurringGrouping.monthlyTotals(items);
    final headers = {
      RecurringGroup.upcoming: l.recurringGroupUpcoming,
      RecurringGroup.later: l.recurringGroupLater,
      RecurringGroup.suggested: l.recurringGroupSuggested,
      RecurringGroup.inactive: l.recurringGroupInactive,
    };
    final accounts = _accounts;
    final categories = {
      for (final category in context.watch<CategoriesProvider?>()?.categories ??
          const <Category>[])
        category.id: category,
    };
    // The "+" sits on the first section shown (normally "Upcoming this
    // month"), so adding works whichever sections exist.
    final firstGroup =
        RecurringGroup.values.firstWhere((g) => groups[g]!.isNotEmpty);

    return [
      if (totals.isNotEmpty) _MonthlySummary(totals: totals),
      for (final group in RecurringGroup.values)
        if (groups[group]!.isNotEmpty) ...[
          SureSectionHeader(
            label: headers[group]!,
            actionIcon: group == firstGroup ? SureIcons.plus : null,
            actionSemanticLabel: l.recurringAdd,
            onAction: group == firstGroup ? () => _openForm() : null,
          ),
          Opacity(
            opacity: group == RecurringGroup.inactive ? 0.55 : 1,
            child: SurePanel.rows(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              dividerIndent: SurePanel.iconRowDividerIndent,
              children: [
                for (final item in groups[group]!)
                  _RecurringRow(
                    key: ValueKey('recurring-${item.id}'),
                    item: item,
                    category: categories[item.categoryId],
                    now: now,
                    onLiability: accounts.any((account) =>
                        account.id == item.accountId && account.isLiability),
                    onTap: () => _openForm(item),
                    onSetStatus: (status) => _setStatus(item, status),
                    onDelete: () => _delete(item),
                  ),
              ],
            ),
          ),
        ],
    ];
  }
}

/// Asks before deleting [item]; true when the user confirmed.
Future<bool> confirmRecurringDelete(
  BuildContext context,
  RecurringTransaction item,
) async {
  final l = AppLocalizations.of(context);
  final palette = SureColors.of(context).palette;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l.recurringDeleteTitle(item.displayName)),
      content: Text(l.recurringDeleteBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: TextButton.styleFrom(foregroundColor: palette.destructive),
          child: Text(l.commonDelete),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Localized cadence of [item], e.g. "Monthly" or "Every 2 weeks". Items
/// without a rule repeat monthly on their expected day, which the row's date
/// already shows.
String recurringCadenceLabel(AppLocalizations l, RecurringTransaction item) {
  final rule = item.primaryRule;
  if (rule == null) return l.recurringEveryMonths(1);
  switch (rule.frequency) {
    case 'weekly':
      return l.recurringEveryWeeks(rule.interval);
    case 'yearly':
      return l.recurringEveryYears(rule.interval);
    default:
      return l.recurringEveryMonths(rule.interval);
  }
}

String _statusLabel(AppLocalizations l, String status) {
  switch (status) {
    case 'active':
      return l.recurringStatusActive;
    case 'paused':
      return l.recurringStatusPaused;
    case 'suggested':
      return l.recurringStatusSuggested;
    case 'ended':
      return l.recurringStatusEnded;
    default:
      return l.recurringStatusInactive;
  }
}

/// "Monthly out $x · in $y" in mono, one line per currency.
class _MonthlySummary extends StatelessWidget {
  const _MonthlySummary({required this.totals});

  final Map<String, RecurringMonthlyTotal> totals;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final locale = Localizations.localeOf(context).toString();
    final hidden = context.watch<PrivacyProvider>().hidden;
    final currencies = totals.keys.toList()..sort();

    String money(double value, String currency) => MoneyMasker.mask(
          InvestmentMath.formatMoney(value, currency: currency, locale: locale),
          hidden: hidden,
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final currency in currencies)
            MoneyText(
              l.ds2pMonthlySummary(
                money(totals[currency]!.outflow, currency),
                money(totals[currency]!.inflow, currency),
              ),
              key: ValueKey('recurringSummary-$currency'),
              trend: MoneyTrend.neutral,
              color: palette.textSecondary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
        ],
      ),
    );
  }
}

class _RecurringRow extends StatelessWidget {
  const _RecurringRow({
    super.key,
    required this.item,
    required this.now,
    required this.onTap,
    required this.onSetStatus,
    required this.onDelete,
    this.onLiability = false,
    this.category,
  });

  final RecurringTransaction item;

  /// The item's category, when it has one and the list has it.
  final Category? category;
  final DateTime now;

  /// True when the item belongs to a loan or credit card. Money flowing into
  /// a liability is a payment toward it, not income.
  final bool onLiability;
  final VoidCallback onTap;
  final ValueChanged<String> onSetStatus;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = SureColors.of(context);
    final palette = colors.palette;
    final locale = Localizations.localeOf(context).toString();
    final hidden = context.watch<PrivacyProvider>().hidden;

    final income = item.isInflow && !onLiability;
    final amount = RecurringGrouping.amountOf(item).abs();
    final formatted = MoneyMasker.mask(
      InvestmentMath.formatMoney(amount,
          currency: item.currency, locale: locale),
      hidden: hidden,
    );
    final next = item.nextExpectedDate;
    final subtitle = [
      recurringCadenceLabel(l, item),
      if (next != null) SureDates.short(next, locale: locale, now: now),
      item.accountName ?? l.recurringNoAccount,
      if (!item.isActive) _statusLabel(l, item.status),
    ].join(' · ');

    // Pause an active item, resume a paused or suggested one; an ended item
    // can only be deleted.
    final String? statusAction =
        item.isActive ? 'inactive' : (item.status == 'ended' ? null : 'active');
    final statusLabel =
        statusAction == 'inactive' ? l.recurringActionPause : l.ds2pResume;

    final row = SureListRow(
      title: item.displayName,
      subtitle: subtitle,
      subtitleMaxLines: 1,
      onTap: onTap,
      leading: category != null
          ? SureCategoryIcon(
              name: category!.name,
              color: category!.color,
              icon: category!.icon,
            )
          : Container(
              width: SureCategoryIcon.rowSize,
              height: SureCategoryIcon.rowSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: palette.surfaceInset,
                shape: BoxShape.circle,
              ),
              child: SureIcon(
                SureIcons.repeat,
                size: 15,
                color: palette.textSecondary,
              ),
            ),
      // Signed like transaction rows: "+" income in success, "-" otherwise.
      trailing: MoneyText(
        income ? '+$formatted' : '-$formatted',
        trend: income ? MoneyTrend.inflow : MoneyTrend.outflow,
        color: income ? palette.success : palette.textPrimary,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
    );

    return Semantics(
      customSemanticsActions: {
        if (statusAction != null)
          CustomSemanticsAction(label: statusLabel): () =>
              onSetStatus(statusAction),
        CustomSemanticsAction(label: l.commonDelete): onDelete,
      },
      child: SureSwipeActions(
        actions: [
          if (statusAction != null)
            SureSwipeAction(
              label: statusLabel,
              color: palette.link,
              onPressed: () => onSetStatus(statusAction),
            ),
          SureSwipeAction(
            label: l.commonDelete,
            color: palette.destructive,
            onPressed: onDelete,
          ),
        ],
        child: ColoredBox(color: palette.container, child: row),
      ),
    );
  }
}
