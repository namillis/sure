import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../models/account_holding.dart';
import '../providers/auth_provider.dart';
import '../providers/privacy_provider.dart';
import '../services/account_detail_service.dart';
import '../theme/sure_colors.dart';
import '../utils/investment_math.dart';
import '../utils/money_masker.dart';

/// Every current position of an investment or crypto account, largest first,
/// with shares, price and unrealized gain where the provider supplied a cost
/// basis.
class HoldingsList extends StatefulWidget {
  const HoldingsList({
    super.key,
    required this.account,
    this.accountDetailService,
  });

  final Account account;
  final AccountDetailService? accountDetailService;

  @override
  State<HoldingsList> createState() => _HoldingsListState();
}

class _HoldingsListState extends State<HoldingsList> {
  late final AccountDetailService _service =
      widget.accountDetailService ?? AccountDetailService();
  List<AccountHolding> _holdings = [];
  bool _isLoading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (widget.accountDetailService == null) _service.close();
    super.dispose();
  }

  Future<void> _load() async {
    final authProvider = context.read<AuthProvider>();
    final token = await authProvider.getValidAccessToken();
    if (!mounted) return;
    if (token == null) {
      await authProvider.logout();
      return;
    }

    setState(() {
      _isLoading = true;
      _failed = false;
    });

    final result = await _service.getCurrentHoldings(
      accessToken: token,
      accountId: widget.account.id,
    );
    if (!mounted) return;

    if (result['error'] == 'unauthorized') {
      await authProvider.logout();
      return;
    }

    setState(() {
      _isLoading = false;
      if (result['success'] == true) {
        _holdings = (result['holdings'] as List<dynamic>? ?? [])
            .whereType<AccountHolding>()
            .toList();
      } else {
        _failed = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    if (_isLoading && _holdings.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_holdings.isEmpty) {
      return _ListMessage(
        onRefresh: _load,
        icon: _failed ? Icons.error_outline : Icons.pie_chart_outline,
        message: _failed ? l.holdingsLoadFailed : l.holdingsEmpty,
        retryLabel: _failed ? l.transactionsListRetry : null,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: _holdings.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) =>
            HoldingTile(holding: _holdings[index]),
      ),
    );
  }
}

/// One position: ticker and name, shares at price, market value and
/// unrealized gain. [accountName] prefixes the subtitle when positions from
/// several accounts share a list.
class HoldingTile extends StatelessWidget {
  const HoldingTile({
    super.key,
    required this.holding,
    this.accountName,
    this.onTap,
  });

  final AccountHolding holding;
  final String? accountName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = SureColors.of(context).palette;
    final locale = Localizations.localeOf(context).toString();
    final hidden = context.watch<PrivacyProvider>().hidden;

    final ticker = holding.ticker?.trim();
    final name = holding.securityName?.trim();
    final title = ticker?.isNotEmpty == true
        ? ticker!
        : name?.isNotEmpty == true
            ? name!
            : l.accountDetailHoldingFallback;
    final showName = ticker?.isNotEmpty == true && name?.isNotEmpty == true;

    final gain = InvestmentMath.gainFor(holding);
    final gainText = gain == null
        ? l.holdingNoCostBasis
        : '${MoneyMasker.mask(InvestmentMath.formatMoney(gain.amount, currency: holding.currency, locale: locale, signed: true), hidden: hidden)}'
            ' (${InvestmentMath.formatPercent(gain.percent, locale: locale)})';
    final gainColor = gain == null
        ? theme.colorScheme.onSurfaceVariant
        : gain.isLoss
            ? palette.destructive
            : palette.success;

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                if (showName)
                  Text(
                    name!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
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
                  l.holdingSharesAtPrice(
                    InvestmentMath.formatQuantity(holding.quantity,
                        locale: locale),
                    holding.price,
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                MoneyMasker.mask(holding.amount, hidden: hidden),
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                gainText,
                style: theme.textTheme.bodySmall?.copyWith(color: gainColor),
              ),
            ],
          ),
        ],
      ),
    );

    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

/// Centered empty/error message that still supports pull-to-refresh.
class _ListMessage extends StatelessWidget {
  const _ListMessage({
    required this.onRefresh,
    required this.icon,
    required this.message,
    this.retryLabel,
  });

  final Future<void> Function() onRefresh;
  final IconData icon;
  final String message;
  final String? retryLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: onRefresh,
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
                    icon,
                    size: 48,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  if (retryLabel != null) ...[
                    const SizedBox(height: 12),
                    TextButton(onPressed: onRefresh, child: Text(retryLabel!)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
