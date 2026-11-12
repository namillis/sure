import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../screens/trade_form_screen.dart';
import '../screens/update_balance_screen.dart';
import '../theme/sure_colors.dart';
import 'sure_icon.dart';
import 'sync_now_dialog.dart';

enum _AccountAction { updateBalance, addTrade, syncNow }

/// The account screen's nav-bar ⋯ menu: Update balance, Add trade
/// (investment and crypto accounts) and Sync now. Calls [onChanged] after
/// any of them changed data, so the screen can reload.
class AccountActionsMenu extends StatelessWidget {
  const AccountActionsMenu({
    super.key,
    required this.account,
    required this.onChanged,
  });

  final Account account;
  final VoidCallback onChanged;

  /// The server takes trades on investment accounts and crypto exchanges
  /// (Account#supports_trades?); a crypto account without a subtype is
  /// offered too and the server's refusal is shown if it is a wallet.
  static bool supportsTrades(Account account) =>
      account.accountType == 'investment' ||
      (account.accountType == 'crypto' && account.subtype != 'wallet');

  Future<void> _select(BuildContext context, _AccountAction action) async {
    final bool changed;
    switch (action) {
      case _AccountAction.updateBalance:
        changed =
            await showUpdateBalanceSheet(context, account: account) == true;
      case _AccountAction.addTrade:
        changed = await showTradeFormSheet(context, account: account) == true;
      case _AccountAction.syncNow:
        changed = await showSyncNowDialog(context);
    }
    if (changed) onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    Widget leading(String icon) =>
        SureIcon(icon, size: 20, color: palette.textSecondary);
    return PopupMenuButton<_AccountAction>(
      icon: SureIcon(SureIcons.ellipsis, size: 22, color: palette.textPrimary),
      tooltip: l.accountActions,
      onSelected: (action) => _select(context, action),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: _AccountAction.updateBalance,
          child: ListTile(
            leading: leading(SureIcons.wallet),
            title: Text(l.accountActionsUpdateBalance),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (supportsTrades(account))
          PopupMenuItem(
            value: _AccountAction.addTrade,
            child: ListTile(
              leading: leading(SureIcons.arrowLeftRight),
              title: Text(l.accountActionsAddTrade),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        PopupMenuItem(
          value: _AccountAction.syncNow,
          child: ListTile(
            leading: leading(SureIcons.refresh),
            title: Text(l.accountActionsSyncNow),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}
