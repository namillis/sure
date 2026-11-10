import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../models/recurring_transaction.dart';
import '../providers/accounts_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/privacy_provider.dart';
import '../services/recurring_transactions_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_spacing.dart';
import '../utils/investment_math.dart';
import '../utils/money_masker.dart';
import '../utils/recurring_grouping.dart';
import '../widgets/sure_button.dart';
import '../widgets/sure_card.dart';
import '../widgets/sure_list_group.dart';
import 'recurring_form_screen.dart';

/// The Recurring segment of the Plan tab: monthly totals, then active items
/// due this month, later ones, suggestions and inactive ones. Tap a row to
/// edit it; its menu pauses, activates or deletes. Built to sit inside a
/// parent Scaffold, so it has no app bar of its own.
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

  /// "Today" for grouping; injected for tests.
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
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RecurringFormScreen(
          existing: existing,
          accounts: _accounts,
          service: _service,
          accessTokenLoader: _token,
          onUnauthorized: _unauthorized,
        ),
      ),
    );
    if (changed == true) await _load();
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
      content: Text(
          result['success'] == true ? l.recurringDeleted : l.recurringActionFailed),
    ));
    if (result['success'] == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final items = _items;

    final Widget content;
    if (items == null && _loading) {
      content = const Padding(
        padding: EdgeInsets.only(top: 96),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (items == null || (_failed && items.isEmpty)) {
      content = _Message(
        icon: Icons.error_outline,
        title: l.recurringLoadFailed,
        action: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: SureButton(
            label: l.recurringRetry,
            variant: SureButtonVariant.outline,
            onPressed: _load,
          ),
        ),
      );
    } else if (items.isEmpty) {
      content = _Message(
        icon: Icons.event_repeat,
        title: l.recurringEmptyTitle,
        body: l.recurringEmptyBody,
      );
    } else {
      content = _list(context, items);
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: SureSpacing.huge),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: SureButton(
                  label: l.recurringAdd,
                  leading: const Icon(Icons.add, size: 16),
                  onPressed: () => _openForm(),
                ),
              ),
            ),
          ),
          content,
        ],
      ),
    );
  }

  Widget _list(BuildContext context, List<RecurringTransaction> items) {
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (totals.isNotEmpty) _TotalsCard(totals: totals),
        for (final group in RecurringGroup.values)
          if (groups[group]!.isNotEmpty)
            SureListGroup(
              header: headers[group],
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              children: [
                for (final item in groups[group]!)
                  _RecurringRow(
                    item: item,
                    onLiability: _accounts.any((account) =>
                        account.id == item.accountId && account.isLiability),
                    onTap: () => _openForm(item),
                    onSetStatus: (status) => _setStatus(item, status),
                    onDelete: () => _delete(item),
                  ),
              ],
            ),
      ],
    );
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

/// Localized cadence of [item], e.g. "Monthly" or "Every 2 weeks".
String recurringCadenceLabel(AppLocalizations l, RecurringTransaction item) {
  final rule = item.primaryRule;
  if (rule == null) {
    final day = item.expectedDayOfMonth;
    return day == null ? l.recurringEveryMonths(1) : l.recurringMonthlyOnDay(day);
  }
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

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.totals});

  final Map<String, RecurringMonthlyTotal> totals;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = SureColors.of(context).palette;
    final locale = Localizations.localeOf(context).toString();
    final hidden = context.watch<PrivacyProvider>().hidden;
    final currencies = totals.keys.toList()..sort();

    String money(double value, String currency) => MoneyMasker.mask(
          InvestmentMath.formatMoney(value, currency: currency, locale: locale),
          hidden: hidden,
        );

    Widget column(String label, String Function(String) value) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: palette.textSecondary)),
              const SizedBox(height: 4),
              for (final currency in currencies)
                Text(value(currency),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        );

    return SureCard(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(SureSpacing.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          column(l.recurringMonthlyOut,
              (c) => money(totals[c]!.outflow, c)),
          column(l.recurringMonthlyIn,
              (c) => money(totals[c]!.inflow, c)),
        ],
      ),
    );
  }
}

class _RecurringRow extends StatelessWidget {
  const _RecurringRow({
    required this.item,
    required this.onTap,
    required this.onSetStatus,
    required this.onDelete,
    this.onLiability = false,
  });

  final RecurringTransaction item;

  /// True when the item belongs to a loan or credit card. Money flowing into
  /// a liability is a payment toward it, not income.
  final bool onLiability;
  final VoidCallback onTap;
  final ValueChanged<String> onSetStatus;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = SureColors.of(context).palette;
    final locale = Localizations.localeOf(context).toString();
    final hidden = context.watch<PrivacyProvider>().hidden;

    final income = item.isInflow && !onLiability;
    final amount = RecurringGrouping.amountOf(item).abs();
    final formatted = MoneyMasker.mask(
      InvestmentMath.formatMoney(amount, currency: item.currency, locale: locale),
      hidden: hidden,
    );
    final next = item.nextExpectedDate;
    final subtitle = [
      recurringCadenceLabel(l, item),
      if (next != null) l.recurringNextDate(DateFormat.MMMd(locale).format(next)),
      item.accountName ?? l.recurringNoAccount,
      if (!item.isActive) _statusLabel(l, item.status),
    ].join(' · ');

    return SureListRow(
      title: item.displayName,
      subtitle: subtitle,
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                income ? '+$formatted' : formatted,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: income ? palette.success : palette.textPrimary,
                ),
              ),
              if (income)
                Text(l.recurringIncome,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: palette.textSecondary)),
            ],
          ),
          PopupMenuButton<String>(
            tooltip: l.recurringMoreActions(item.displayName),
            icon: Icon(Icons.more_vert, color: palette.textSecondary),
            onSelected: (action) {
              switch (action) {
                case 'edit':
                  onTap();
                case 'delete':
                  onDelete();
                default:
                  onSetStatus(action);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'edit', child: Text(l.recurringActionEdit)),
              if (item.isActive)
                PopupMenuItem(
                    value: 'inactive', child: Text(l.recurringActionPause))
              else if (item.status != 'ended')
                PopupMenuItem(
                    value: 'active', child: Text(l.recurringActionActivate)),
              PopupMenuItem(value: 'delete', child: Text(l.commonDelete)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = SureColors.of(context).palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 64, 32, 0),
      child: Column(
        children: [
          Icon(icon, size: 48, color: palette.textSubdued),
          const SizedBox(height: SureSpacing.lg),
          Text(title,
              textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
          if (body != null) ...[
            const SizedBox(height: SureSpacing.md),
            Text(body!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: palette.textSecondary)),
          ],
          if (action != null) ...[
            const SizedBox(height: SureSpacing.xl),
            action!,
          ],
        ],
      ),
    );
  }
}
