import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/account.dart';
import '../models/account_balance.dart';
import '../providers/auth_provider.dart';
import '../providers/privacy_provider.dart';
import '../services/account_detail_service.dart';
import '../l10n/app_localizations.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_tokens.dart';
import '../utils/sure_dates.dart';
import '../utils/investment_math.dart';
import '../utils/money_masker.dart';
import '../utils/portfolio_math.dart';
import 'balance_history_chart.dart';
import 'money_text.dart';
import 'sure_segmented_control.dart';

class AccountDetailHeader extends StatefulWidget {
  final Account account;
  final AccountDetailService? accountDetailService;

  const AccountDetailHeader({
    super.key,
    required this.account,
    this.accountDetailService,
    this.onAccountLoaded,
    this.reloadToken,
  });

  /// Called with the account as the server returned it, after each load.
  final ValueChanged<Account>? onAccountLoaded;

  /// Changing this value reloads the account and its balance history (e.g.
  /// from the page's pull-to-refresh).
  final Object? reloadToken;

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
      if (accountResult['success'] == true &&
          accountResult['account'] is Account) {
        widget.onAccountLoaded?.call(_account);
      }
    } finally {
      _activeDetailLoads -= 1;
      _closeOwnedAccountDetailServiceIfIdle();
    }
  }

  @override
  void didUpdateWidget(covariant AccountDetailHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reloadToken != oldWidget.reloadToken) _loadDetails();
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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final locale = Localizations.localeOf(context).toString();
    final hideAmounts = context.watch<PrivacyProvider>().hidden;

    final change = PortfolioMath.change(_balances);
    // Rising debt is bad news, so liabilities read the trend inverted.
    final trendIsGood = change == null ||
        (_account.isLiability ? change.amount <= 0 : change.amount >= 0);
    final trendColor = trendIsGood ? palette.success : palette.destructive;

    final selected = _selectedBalance;
    final headlineAmount = selected?.balance ?? _account.balance;

    // While scrubbing, the line under the hero shows the touched day instead
    // of the range's change.
    Widget? subline;
    String? semanticLabel;
    if (selected != null) {
      semanticLabel = SureDates.full(selected.date, locale: locale);
      subline = Text(
        semanticLabel,
        key: const ValueKey('accountHeaderScrubDate'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 13, color: palette.textSecondary),
      );
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
      final changeLine = percent == null
          ? changeText
          : '$changeText (${InvestmentMath.formatPercent(percent, locale: locale)})';
      semanticLabel = '$changeLine ${_range.label(l)}';
      subline = Row(
        key: const ValueKey('accountHeaderChange'),
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
            _range.label(l),
            style: TextStyle(
              fontSize: 13,
              fontFamily: SureTokens.fontMono,
              color: palette.textSubdued,
            ),
          ),
        ],
      );
    }

    final hasChart = _balances.where((b) => b.balanceCents != null).length >= 2;

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
                    MoneyMasker.mask(headlineAmount, hidden: hideAmounts),
                    key: const ValueKey('accountHeaderBalance'),
                    trend: MoneyTrend.neutral,
                    color: _account.isLiability && selected == null
                        ? palette.destructive
                        : palette.textPrimary,
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
              if (_isLoading) ...[
                const SizedBox(width: 10),
                const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
              ],
            ],
          ),
          // Fixed height so scrubbing (date) and the change line swap without
          // the chart jumping.
          SizedBox(
            height: 20,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: subline ?? const SizedBox.shrink(),
            ),
          ),
          if (_account.cashBalance != null)
            MoneyText(
              l.accountDetailCashChip(
                MoneyMasker.mask(_account.cashBalance!, hidden: hideAmounts),
              ),
              trend: MoneyTrend.neutral,
              color: palette.textSecondary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
            ),
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
            child: hasChart
                ? BalanceHistoryChart(
                    balances: _balances,
                    color: trendColor,
                    semanticLabel: semanticLabel,
                    onSelectionChanged: (balance) =>
                        setState(() => _selectedBalance = balance),
                  )
                : Center(
                    child: Text(
                      _isLoading ? '' : l.accountChartNoHistory,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: palette.textSubdued,
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
                SureSegment(value: range, label: range.label(l)),
            ],
          ),
          if (_detailsUnavailable) ...[
            const SizedBox(height: 8),
            Text(
              l.accountDetailUnavailable,
              style: TextStyle(fontSize: 13, color: palette.destructive),
            ),
          ],
        ],
      ),
    );
  }
}
