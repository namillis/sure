import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../providers/server_features_provider.dart';
import '../screens/account_form_sheet.dart';
import '../screens/trade_form_screen.dart';
import '../screens/update_balance_screen.dart';
import '../theme/sure_colors.dart';
import 'sure_icon.dart';
import 'sync_now_dialog.dart';

enum _AccountAction { updateBalance, addTrade, syncNow, edit }

/// The account screen's nav-bar ⋯ menu: Update balance, Add trade
/// (investment and crypto accounts), Sync now and, on Sure+ servers with
/// `accounts.write`, Edit account. Calls [onChanged] after
/// any of them changed data, so the screen can reload.
class AccountActionsMenu extends StatelessWidget {
  const AccountActionsMenu({
    super.key,
    required this.account,
    required this.onChanged,
    this.onDeleted,
  });

  final Account account;
  final VoidCallback onChanged;

  /// Called after "Edit account" deleted the account (Sure+ `accounts.write`);
  /// [onChanged] when null.
  final VoidCallback? onDeleted;

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
      case _AccountAction.edit:
        final result = await showAccountFormSheet(context, account: account);
        if (result?.deleted == true) {
          (onDeleted ?? onChanged)();
          return;
        }
        changed = result?.account != null;
    }
    if (changed) onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    bool canEdit;
    try {
      final features = context.watch<ServerFeaturesProvider>();
      canEdit = features.has(ServerFeaturesProvider.accountsWrite) &&
          !(features.has(ServerFeaturesProvider.accountsPermissions) &&
              account.canEdit == false);
    } on ProviderNotFoundException {
      canEdit = false;
    }
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
        if (canEdit)
          PopupMenuItem(
            value: _AccountAction.edit,
            child: ListTile(
              leading: leading(SureIcons.pencil),
              title: Text(l.spaEditAccount),
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    );
  }
}
