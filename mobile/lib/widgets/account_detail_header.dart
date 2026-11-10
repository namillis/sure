import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/account.dart';
import '../models/account_balance.dart';
import '../providers/auth_provider.dart';
import '../providers/privacy_provider.dart';
import '../services/account_detail_service.dart';
import '../l10n/app_localizations.dart';
import '../theme/sure_colors.dart';
import '../utils/investment_math.dart';
import '../utils/money_masker.dart';
import 'balance_history_chart.dart';
import 'sure_segmented_control.dart';

class AccountDetailHeader extends StatefulWidget {
  final Account account;
  final AccountDetailService? accountDetailService;

  const AccountDetailHeader({
    super.key,
    required this.account,
    this.accountDetailService,
  });

  @override
  State<AccountDetailHeader> createState() => _AccountDetailHeaderState();
}

class _AccountDetailHeaderState extends State<AccountDetailHeader> {
  late final AccountDetailService _accountDetailService =
      widget.accountDetailService ?? AccountDetailService();
  late final bool _ownsAccountDetailService =
      widget.accountDetailService == null;
  late Account _account;
  AccountChartRange _range = AccountChartRange.month;
  bool _isLoading = false;
  bool _detailsUnavailable = false;
  List<AccountBalance> _balances = [];
  AccountBalance? _selectedBalance;
  bool _disposed = false;
  bool _accountDetailServiceClosed = false;
  int _activeDetailLoads = 0;

  // Guards against an older range's response landing after a newer one.
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _account = widget.account;
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    if (_disposed) return;
    final generation = ++_loadGeneration;
    final range = _range;

    // NOTE: this runs synchronously from initState(); do not touch inherited
    // widgets (e.g. AppLocalizations.of) here. The failure message is localized
    // at render time in build() via the _detailsUnavailable flag.
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final accessToken = await authProvider.getValidAccessToken();
    if (_disposed) return;

    if (accessToken == null) {
      await authProvider.logout();
      return;
    }

    _activeDetailLoads += 1;

    if (mounted) {
      setState(() {
        _isLoading = true;
        _detailsUnavailable = false;
      });
    }

    try {
      final results = await Future.wait([
        _accountDetailService.getAccountDetail(
          accessToken: accessToken,
          accountId: widget.account.id,
        ),
        _accountDetailService.getBalanceHistory(
          accessToken: accessToken,
          accountId: widget.account.id,
          startDate: range.startDate(DateTime.now()),
        ),
      ]);

      if (!mounted || _disposed || generation != _loadGeneration) return;

      final accountResult = results[0];
      final balancesResult = results[1];

      if (accountResult['error'] == 'unauthorized' ||
          balancesResult['error'] == 'unauthorized') {
        await authProvider.logout();
        return;
      }

      setState(() {
        if (accountResult['success'] == true &&
            accountResult['account'] is Account) {
          _account = accountResult['account'] as Account;
        }
        if (balancesResult['success'] == true) {
          _balances = (balancesResult['balances'] as List<dynamic>? ?? [])
              .whereType<AccountBalance>()
              .toList();
          _selectedBalance = null;
        }
        if (accountResult['success'] != true &&
            balancesResult['success'] != true) {
          _detailsUnavailable = true;
        }
        _isLoading = false;
      });
    } finally {
      _activeDetailLoads -= 1;
      _closeOwnedAccountDetailServiceIfIdle();
    }
  }

  void _selectRange(AccountChartRange range) {
    if (range == _range) return;
    setState(() => _range = range);
    _loadDetails();
  }

  @override
  void dispose() {
    _disposed = true;
    _closeOwnedAccountDetailServiceIfIdle();
    super.dispose();
  }

  void _closeOwnedAccountDetailServiceIfIdle() {
    if (_ownsAccountDetailService &&
        _disposed &&
        _activeDetailLoads == 0 &&
        !_accountDetailServiceClosed) {
      _accountDetailService.close();
      _accountDetailServiceClosed = true;
    }
  }

  /// Change between the first and last charted balance, in major units, plus
  /// the fraction of the starting balance. Null with fewer than two points.
  ({double amount, double? percent})? _rangeChange() {
    final points =
        _balances.where((balance) => balance.balanceCents != null).toList();
    if (points.length < 2) return null;

    final currency = points.last.currency;
    final start = InvestmentMath.fromMinorUnits(
      points.first.balanceCents!,
      currency: currency,
    );
    final end = InvestmentMath.fromMinorUnits(
      points.last.balanceCents!,
      currency: currency,
    );
    return (
      amount: end - start,
      percent: start == 0 ? null : (end - start) / start.abs(),
    );
  }

  String _rangeLabel(AppLocalizations l, AccountChartRange range) {
    return switch (range) {
      AccountChartRange.week => l.accountRangeWeek,
      AccountChartRange.month => l.accountRangeMonth,
      AccountChartRange.quarter => l.accountRangeQuarter,
      AccountChartRange.year => l.accountRangeYear,
      AccountChartRange.all => l.accountRangeAll,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final palette = SureColors.of(context).palette;
    final locale = Localizations.localeOf(context).toString();
    final hideAmounts = context.watch<PrivacyProvider>().hidden;

    final change = _rangeChange();
    // Rising debt is bad news, so liabilities read the trend inverted.
    final trendIsGood = change == null ||
        (_account.isLiability ? change.amount <= 0 : change.amount >= 0);
    final trendColor = trendIsGood ? palette.success : palette.destructive;

    final selected = _selectedBalance;
    final headlineAmount = selected?.balance ?? _account.balance;

    String? subline;
    Color? sublineColor;
    if (selected != null) {
      subline = DateFormat.yMMMd(locale).format(selected.date);
      sublineColor = colorScheme.onSurfaceVariant;
    } else if (change != null) {
      final currency = _balances.last.currency;
      final changeText = MoneyMasker.mask(
        InvestmentMath.formatMoney(
          change.amount,
          currency: currency,
          locale: locale,
          signed: true,
        ),
        hidden: hideAmounts,
      );
      final percent = change.percent;
      subline = percent == null
          ? l.accountChartChangeOnlyLabel(changeText)
          : l.accountChartChangeLabel(
              changeText,
              InvestmentMath.formatPercent(percent, locale: locale),
            );
      sublineColor = trendColor;
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _account.displayAccountType,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        MoneyMasker.mask(headlineAmount, hidden: hideAmounts),
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _account.isLiability && selected == null
                              ? palette.destructive
                              : null,
                        ),
                      ),
                      if (subline != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subline,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: sublineColor),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    tooltip: l.accountDetailRefreshTooltip,
                    onPressed: _loadDetails,
                  ),
              ],
            ),
            if (_account.institutionName != null ||
                _account.subtype != null ||
                _account.cashBalance != null ||
                _account.status != null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_account.institutionName != null)
                    _DetailChip(
                      label: _account.institutionName!,
                      icon: Icons.account_balance,
                    ),
                  if (_account.subtype != null)
                    _DetailChip(
                      label: _account.subtype!,
                      icon: Icons.category_outlined,
                    ),
                  if (_account.cashBalance != null)
                    _DetailChip(
                      label: l.accountDetailCashChip(
                        MoneyMasker.mask(_account.cashBalance!,
                            hidden: hideAmounts),
                      ),
                      icon: Icons.payments_outlined,
                    ),
                  if (_account.status != null)
                    _DetailChip(
                      label: _account.status!,
                      icon: Icons.sync,
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: 96,
              child: _balances.where((b) => b.balanceCents != null).length >= 2
                  ? BalanceHistoryChart(
                      balances: _balances,
                      color: trendColor,
                      semanticLabel: subline,
                      onSelectionChanged: (balance) =>
                          setState(() => _selectedBalance = balance),
                    )
                  : Center(
                      child: Text(
                        _isLoading ? '' : l.accountChartNoHistory,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            SureSegmentedControl<AccountChartRange>(
              selected: _range,
              onChanged: _selectRange,
              segments: [
                for (final range in AccountChartRange.values)
                  SureSegment(value: range, label: _rangeLabel(l, range)),
              ],
            ),
            if (_detailsUnavailable) ...[
              const SizedBox(height: 8),
              Text(
                l.accountDetailUnavailable,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  final String label;
  final IconData icon;

  const _DetailChip({
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
