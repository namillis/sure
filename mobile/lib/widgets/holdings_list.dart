import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../models/account_holding.dart';
import '../providers/auth_provider.dart';
import '../providers/privacy_provider.dart';
import '../providers/server_features_provider.dart';
import '../services/account_detail_service.dart';
import '../services/preferences_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_tokens.dart';
import '../utils/investment_math.dart';
import '../utils/money_masker.dart';
import '../utils/zero_holdings.dart';
import 'ds/ds.dart';

/// Every current position of an investment or crypto account, largest first,
/// with shares, price and unrealized gain where the provider supplied a cost
/// basis.
class HoldingsList extends StatefulWidget {
  const HoldingsList({
    super.key,
    required this.account,
    this.accountDetailService,
    this.onHoldingTap,
    this.onRefreshed,
  });

  final Account account;
  final AccountDetailService? accountDetailService;

  /// Called when a row is tapped; rows are not tappable when null.
  final void Function(AccountHolding holding)? onHoldingTap;

  /// Called when the user pulls to refresh, so the page can reload too.
  final VoidCallback? onRefreshed;

  @override
  State<HoldingsList> createState() => _HoldingsListState();
}

class _HoldingsListState extends State<HoldingsList>
    with ZeroHoldingsPreference<HoldingsList> {
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
    final stableOrder = context
            .read<ServerFeaturesProvider?>()
            ?.has(ServerFeaturesProvider.holdingsStableOrder) ??
        false;
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
      stableOrder: stableOrder,
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

  Future<void> _pullRefresh() {
    widget.onRefreshed?.call();
    return _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    if (_isLoading && _holdings.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_holdings.isEmpty) {
      return _ListMessage(
        onRefresh: _pullRefresh,
        icon: _failed ? SureIcons.circleAlert : SureIcons.chartPie,
        message: _failed ? l.holdingsLoadFailed : l.holdingsEmpty,
        retryLabel: _failed ? l.transactionsListRetry : null,
      );
    }

    final visible = ZeroHoldings.visible(_holdings, showZero: showZeroHoldings);
    final zeroCount = ZeroHoldings.zeroCount(_holdings);
    final currency = _holdings.first.currency;
    final onHoldingTap = widget.onHoldingTap;

    return RefreshIndicator(
      onRefresh: _pullRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (visible.isEmpty)
            SurePanel(child: AllZeroHoldingsMessage(currency: currency))
          else
            SurePanel.rows(
              dividerIndent: HoldingTile.dividerIndent,
              children: [
                for (final holding in visible)
                  HoldingTile(
                    holding: holding,
                    crypto: widget.account.accountType == 'crypto',
                    onTap: onHoldingTap == null
                        ? null
                        : () => onHoldingTap(holding),
                  ),
              ],
            ),
          if (zeroCount > 0)
            ZeroHoldingsFooter(
              count: zeroCount,
              currency: currency,
              shown: showZeroHoldings,
              onToggle: toggleShowZeroHoldings,
            ),
        ],
      ),
    );
  }
}

/// Shown instead of rows when every holding is worth zero and those are
/// hidden, so the list does not read as empty.
class AllZeroHoldingsMessage extends StatelessWidget {
  const AllZeroHoldingsMessage({super.key, required this.currency});

  final String currency;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    return SureEmptyState(
      icon: SureIcons.chartPie,
      title: l.p3apAllHoldingsZero(
          ZeroHoldings.zeroLabel(currency, locale: locale)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    );
  }
}

/// "N holdings worth $0 hidden · Show" row under a holdings list.
class ZeroHoldingsFooter extends StatelessWidget {
  const ZeroHoldingsFooter({
    super.key,
    required this.count,
    required this.currency,
    required this.shown,
    required this.onToggle,
  });

  final int count;
  final String currency;
  final bool shown;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final locale = Localizations.localeOf(context).toString();
    final zero = ZeroHoldings.zeroLabel(currency, locale: locale);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 0, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              shown
                  ? l.p3apZeroHoldingsShown(count, zero)
                  : l.p3apZeroHoldingsHidden(count, zero),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: palette.textSubdued),
            ),
          ),
          TextButton(
            key: const ValueKey('zeroHoldingsToggle'),
            onPressed: onToggle,
            style: TextButton.styleFrom(foregroundColor: palette.link),
            child: Text(
              shown ? l.p3apHide : l.p3apShow,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// Loads and persists whether zero-value holdings are shown.
mixin ZeroHoldingsPreference<T extends StatefulWidget> on State<T> {
  bool _showZero = false;

  bool get showZeroHoldings => _showZero;

  @override
  void initState() {
    super.initState();
    PreferencesService.instance.getShowZeroHoldings().then((value) {
      if (mounted && value != _showZero) setState(() => _showZero = value);
    });
  }

  void toggleShowZeroHoldings() {
    setState(() => _showZero = !_showZero);
    PreferencesService.instance.setShowZeroHoldings(_showZero);
  }
}

/// One position, as a quiet panel row: a tinted circle with the ticker's
/// first letter (a coin glyph with [crypto]), the ticker, "781.46 sh · $102.00",
/// and on the right the market value over the unrealized gain %. The security
/// name is read out with the ticker. [accountName] prefixes the subtitle when
/// positions from several accounts share a list.
class HoldingTile extends StatelessWidget {
  const HoldingTile({
    super.key,
    required this.holding,
    this.accountName,
    this.onTap,
    this.crypto = false,
  });

  final AccountHolding holding;
  final String? accountName;
  final VoidCallback? onTap;

  /// Shows a coin glyph instead of the ticker's letter (crypto accounts).
  final bool crypto;

  static const double avatarSize = 32;

  /// Divider indent that lines up with the row's text.
  static const double dividerIndent = 14 + avatarSize + 12;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final locale = Localizations.localeOf(context).toString();
    final hidden = context.watch<PrivacyProvider>().hidden;

    final rawTicker = holding.ticker?.trim();
    // The server prefixes some tickers with their exchange ("CRYPTO:BTC");
    // the row shows the symbol alone, and a coin for crypto securities.
    final isCryptoTicker =
        rawTicker?.toUpperCase().startsWith('CRYPTO:') == true;
    final ticker = rawTicker != null && rawTicker.contains(':')
        ? rawTicker.substring(rawTicker.lastIndexOf(':') + 1)
        : rawTicker;
    final showCoin = crypto || isCryptoTicker;
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
        : InvestmentMath.formatPercent(gain.percent, locale: locale);
    final gainColor = gain == null
        ? palette.textSubdued
        : gain.isLoss
            ? palette.destructive
            : palette.success;

    final subtitle = [
      if (accountName?.isNotEmpty == true) accountName!,
      l.dspSharesAtPrice(
        InvestmentMath.formatQuantity(holding.quantity, locale: locale),
        holding.price,
      ),
    ].join(' · ');

    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            _HoldingAvatar(title: title, crypto: showCoin),
            const SizedBox(width: 12),
            Expanded(
              child: Semantics(
                label: showName ? '$title, $name' : null,
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
                ),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    MoneyText(
                      MoneyMasker.mask(holding.amount, hidden: hidden),
                      trend: MoneyTrend.neutral,
                      color: palette.textPrimary,
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: SureTokens.weightMedium,
                      ),
                    ),
                    const SizedBox(height: 2),
                    MoneyText(
                      gainText,
                      trend: gain == null
                          ? MoneyTrend.neutral
                          : gain.isLoss
                              ? MoneyTrend.outflow
                              : MoneyTrend.inflow,
                      color: gainColor,
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
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

class _HoldingAvatar extends StatelessWidget {
  const _HoldingAvatar({required this.title, required this.crypto});

  final String title;
  final bool crypto;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    final tint = crypto ? palette.warning : palette.link;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final letter = title.isEmpty ? '?' : title.characters.first.toUpperCase();
    return ExcludeSemantics(
      child: Container(
        width: HoldingTile.avatarSize,
        height: HoldingTile.avatarSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: tint.withValues(alpha: dark ? 0.18 : 0.14),
        ),
        child: crypto
            ? SureIcon(SureIcons.bitcoin, size: 16, color: tint)
            : Text(
                letter,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: tint,
                ),
              ),
      ),
    );
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
  final String icon;
  final String message;
  final String? retryLabel;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: SureEmptyState(
                icon: icon,
                title: message,
                secondaryLabel: retryLabel,
                onSecondary: retryLabel == null ? null : onRefresh,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
