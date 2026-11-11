import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../providers/transactions_provider.dart';
import '../services/connectivity_service.dart';
import '../theme/sure_colors.dart';
import '../utils/updated_ago.dart';
import 'ds/sure_banner.dart';
import 'sure_icon.dart';

/// The offline / pending-sync banner, as a [SureBanner].
///
/// Offline: "Offline · showing data from 2h ago" when [updatedAt] (when the
/// data on screen was last loaded) is known, else a generic offline line.
/// Online with transactions waiting to upload: "N transactions waiting to
/// sync" with a "Sync now" link. Otherwise renders nothing.
class ConnectivityBanner extends StatefulWidget {
  const ConnectivityBanner({
    super.key,
    this.updatedAt,
    this.margin,
    this.clock,
  });

  final DateTime? updatedAt;
  final EdgeInsetsGeometry? margin;

  /// Source of "now"; injectable for tests.
  final DateTime Function()? clock;

  @override
  State<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<ConnectivityBanner> {
  bool _isSyncing = false;

  T? _maybeWatch<T>() {
    try {
      return Provider.of<T>(context);
    } on ProviderNotFoundException {
      return null;
    }
  }

  Future<void> _syncNow(TransactionsProvider transactionsProvider) async {
    // Capture context-derived objects before the async gap so we never touch
    // `context` after an await.
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final palette = SureColors.of(context).palette;
    final authProvider = context.read<AuthProvider>();
    setState(() => _isSyncing = true);

    void show(String text, Color color) => messenger.showSnackBar(
          SnackBar(content: Text(text), backgroundColor: color),
        );

    try {
      String? accessToken;
      try {
        accessToken = await authProvider.getValidAccessToken();
      } catch (_) {
        show(l.connectivityAuthFailed, palette.destructive);
        return;
      }
      if (accessToken == null) {
        show(l.connectivitySignInToSync, palette.warning);
        return;
      }
      try {
        await transactionsProvider.syncTransactions(accessToken: accessToken);
        if (mounted) show(l.connectivitySyncSuccess, palette.success);
      } catch (_) {
        if (mounted) show(l.connectivitySyncFailed, palette.destructive);
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isOffline = _maybeWatch<ConnectivityService>()?.isOffline ?? false;
    final transactions = _maybeWatch<TransactionsProvider>();
    final hasPending = transactions?.hasPendingTransactions ?? false;

    if (isOffline) {
      final updatedAt = widget.updatedAt;
      final String message;
      if (updatedAt == null) {
        message = l.p3ocOfflineMayBeOutdated;
      } else {
        final now = (widget.clock ?? DateTime.now)();
        final age = compactAgeLabel(l, updatedAt, now);
        message = age == null
            ? l.dshOfflineShowingJustNow
            : l.dshOfflineShowing(age);
      }
      return SureBanner(
        icon: SureIcons.cloudOff,
        message: message,
        margin: widget.margin,
      );
    }

    if (hasPending) {
      return SureBanner(
        icon: SureIcons.cloudUpload,
        message: l.connectivityPendingSync(transactions!.pendingCount),
        actionLabel: _isSyncing ? null : l.connectivitySyncNow,
        onAction: _isSyncing ? null : () => _syncNow(transactions),
        margin: widget.margin,
      );
    }

    return const SizedBox.shrink();
  }
}
