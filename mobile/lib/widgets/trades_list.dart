import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../models/account_trade.dart';
import '../providers/auth_provider.dart';
import '../providers/privacy_provider.dart';
import '../services/account_detail_service.dart';
import '../utils/investment_math.dart';
import '../utils/money_masker.dart';

/// Investment activity (buys, sells, dividends...) for one account, newest
/// first, loading further pages as the user scrolls.
class TradesList extends StatefulWidget {
  const TradesList({
    super.key,
    required this.account,
    this.accountDetailService,
    this.onTradeTap,
  });

  final Account account;
  final AccountDetailService? accountDetailService;

  /// Passed to each [TradeTile.onTap].
  final void Function(AccountTrade trade)? onTradeTap;

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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;

    if (_trades.isEmpty) {
      if (_isLoading) return const Center(child: CircularProgressIndicator());
      return RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _failed ? Icons.error_outline : Icons.swap_vert,
                      size: 48,
                      color:
                          colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _failed ? l.tradesLoadFailed : l.tradesEmpty,
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                    if (_failed) ...[
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _refresh,
                        child: Text(l.transactionsListRetry),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    final showFooter = _hasMore || _failed;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: NotificationListener<ScrollUpdateNotification>(
        onNotification: _maybeLoadMore,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          itemCount: _trades.length + (showFooter ? 1 : 0),
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            if (index == _trades.length) {
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
            final trade = _trades[index];
            final onTap = widget.onTradeTap;
            return TradeTile(
              trade: trade,
              onTap: onTap == null ? null : () => onTap(trade),
            );
          },
        ),
      ),
    );
  }
}

/// One trade: Buy/Sell label and security, date and quantity at price, and
/// amount. [showAccount] adds the trade's account to the subtitle when
/// activity from several accounts shares a list.
class TradeTile extends StatelessWidget {
  const TradeTile({
    super.key,
    required this.trade,
    this.showAccount = false,
    this.onTap,
  });

  final AccountTrade trade;
  final bool showAccount;

  /// Makes the row tappable (e.g. to edit the trade).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
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
      DateFormat.yMMMd(locale).format(trade.date),
      if (showQuantity)
        l.tradeQuantityAtPrice(
          InvestmentMath.formatQuantity(
            trade.quantity.replaceFirst('-', ''),
            locale: locale,
          ),
          trade.price,
        ),
    ].join(' · ');

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                if (accountName?.isNotEmpty == true)
                  Text(
                    accountName!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            // Entry amounts are signed from the cash side (buys are outflows);
            // the activity label already says which way it went.
            MoneyMasker.mask(trade.amount.replaceFirst('-', ''),
                hidden: hidden),
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
    return onTap == null ? row : InkWell(onTap: onTap, child: row);
  }
}
