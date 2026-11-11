import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../models/account_trade.dart';
import '../providers/auth_provider.dart';
import '../providers/privacy_provider.dart';
import '../services/account_detail_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_tokens.dart';
import '../utils/investment_math.dart';
import '../utils/money_masker.dart';
import 'ds/ds.dart';

/// Investment activity (buys, sells, dividends...) for one account, newest
/// first, loading further pages as the user scrolls.
class TradesList extends StatefulWidget {
  const TradesList({
    super.key,
    required this.account,
    this.accountDetailService,
    this.onTradeTap,
    this.onRefreshed,
  });

  final Account account;
  final AccountDetailService? accountDetailService;

  /// Passed to each [TradeTile.onTap].
  final void Function(AccountTrade trade)? onTradeTap;

  /// Called when the user pulls to refresh, so the page can reload too.
  final VoidCallback? onRefreshed;

  @override
  State<TradesList> createState() => _TradesListState();
}

class _TradesListState extends State<TradesList> {
  late final AccountDetailService _service =
      widget.accountDetailService ?? AccountDetailService();
  final List<AccountTrade> _trades = [];
  int _nextPage = 1;
  bool _hasMore = true;
  bool _isLoading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    if (widget.accountDetailService == null) _service.close();
    super.dispose();
  }

  // Driven by scroll notifications rather than an own ScrollController, so
  // the list can take its controller from an enclosing NestedScrollView.
  bool _maybeLoadMore(ScrollUpdateNotification notification) {
    final metrics = notification.metrics;
    if (notification.depth == 0 &&
        metrics.pixels > metrics.maxScrollExtent - 300) {
      _loadPage();
    }
    return false;
  }

  Future<void> _refresh() async {
    _trades.clear();
    _nextPage = 1;
    _hasMore = true;
    await _loadPage(force: true);
  }

  Future<void> _loadPage({bool force = false}) async {
    if (!_hasMore || (_isLoading && !force)) return;

    final authProvider = context.read<AuthProvider>();
    setState(() {
      _isLoading = true;
      _failed = false;
    });

    final token = await authProvider.getValidAccessToken();
    if (!mounted) return;
    if (token == null) {
      await authProvider.logout();
      return;
    }

    final page = _nextPage;
    final result = await _service.getTrades(
      accessToken: token,
      accountId: widget.account.id,
      page: page,
    );
    if (!mounted) return;

    if (result['error'] == 'unauthorized') {
      await authProvider.logout();
      return;
    }

    setState(() {
      _isLoading = false;
      if (result['success'] == true) {
        _trades.addAll(
          (result['trades'] as List<dynamic>? ?? []).whereType<AccountTrade>(),
        );
        _hasMore = result['hasMore'] == true;
        _nextPage = page + 1;
      } else {
        _failed = true;
      }
    });
  }

  Future<void> _pullRefresh() {
    widget.onRefreshed?.call();
    return _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    if (_trades.isEmpty) {
      if (_isLoading) return const Center(child: CircularProgressIndicator());
      return RefreshIndicator(
        onRefresh: _pullRefresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: SureEmptyState(
                  icon: _failed
                      ? SureIcons.circleAlert
                      : SureIcons.arrowLeftRight,
                  title: _failed ? l.tradesLoadFailed : l.tradesEmpty,
                  secondaryLabel: _failed ? l.transactionsListRetry : null,
                  onSecondary: _failed ? _refresh : null,
                ),
              ),
            ),
          ],
        ),
      );
    }

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

    final showFooter = _hasMore || _failed;
    final onTap = widget.onTradeTap;
    return RefreshIndicator(
      onRefresh: _pullRefresh,
      child: NotificationListener<ScrollUpdateNotification>(
        onNotification: _maybeLoadMore,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: days.length + (showFooter ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == days.length) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: _failed
                      ? TextButton(
                          onPressed: _loadPage,
                          child: Text(l.transactionsListRetry),
                        )
                      : const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                ),
              );
            }
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
                        showDate: false,
                        onTap: onTap == null ? null : () => onTap(trade),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One trade as a panel row: "Buy AAPL" (or the server's activity label),
/// "Nov 5 · 10 @ $150.00" and the amount in mono. [showAccount] adds the
/// trade's account to the subtitle when activity from several accounts
/// shares a list; [showDate] false drops the date when rows sit under a day
/// header.
class TradeTile extends StatelessWidget {
  const TradeTile({
    super.key,
    required this.trade,
    this.showAccount = false,
    this.showDate = true,
    this.onTap,
  });

  final AccountTrade trade;
  final bool showAccount;
  final bool showDate;

  /// Makes the row tappable (e.g. to edit the trade).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final locale = Localizations.localeOf(context).toString();
    final hidden = context.watch<PrivacyProvider>().hidden;

    final ticker = trade.ticker?.trim();
    final security = ticker?.isNotEmpty == true
        ? ticker!
        : trade.securityName?.trim().isNotEmpty == true
            ? trade.securityName!.trim()
            : trade.name;
    final quantity = InvestmentMath.parse(trade.quantity);

    // Prefer the server's label; otherwise fall back to the server's own rule
    // (Trade#buy? / #sell?): positive quantity is a buy, negative a sell.
    final serverLabel = trade.activityLabel?.trim();
    final label = serverLabel?.isNotEmpty == true
        ? serverLabel
        : quantity == null || quantity == 0
            ? null
            : quantity > 0
                ? l.tradeBuy
                : l.tradeSell;
    final title = label == null ? security : '$label $security';

    final showQuantity = quantity != null && quantity != 0;
    final accountName = showAccount ? trade.accountName?.trim() : null;
    final subtitle = [
      if (accountName?.isNotEmpty == true) accountName!,
      if (showDate) SureDates.short(trade.date, locale: locale),
      if (showQuantity)
        l.tradeQuantityAtPrice(
          InvestmentMath.formatQuantity(
            trade.quantity.replaceFirst('-', ''),
            locale: locale,
          ),
          trade.price,
        ),
    ].join(' · ');

    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.25,
                      fontWeight: SureTokens.weightMedium,
                      color: palette.textPrimary,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.25,
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.45,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerEnd,
                child: MoneyText(
                  // Entry amounts are signed from the cash side (buys are
                  // outflows); the activity label already says which way it
                  // went.
                  MoneyMasker.mask(trade.amount.replaceFirst('-', ''),
                      hidden: hidden),
                  trend: MoneyTrend.neutral,
                  color: palette.textPrimary,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: SureTokens.weightMedium,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: row),
    );
  }
}
