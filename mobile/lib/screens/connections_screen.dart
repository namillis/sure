import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/provider_connection.dart';
import '../providers/auth_provider.dart';
import '../services/provider_connections_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_spacing.dart';
import '../widgets/manage_widgets.dart';
import '../widgets/open_on_web_action.dart';
import '../widgets/sure_button.dart';
import '../widgets/sure_card.dart';
import '../widgets/sure_list_group.dart';
import '../widgets/sync_now_dialog.dart';

/// The family's bank and broker connections from
/// `GET /api/v1/provider_connections`, read-only. Connecting, reconnecting
/// and removing happen on the web (`/settings/providers`); rows that need
/// attention link there. "Sync now" runs the family sync.
class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({
    super.key,
    this.service,
    this.accessTokenLoader,
    this.onUnauthorized,
    this.now,
  });

  final ProviderConnectionsService? service;

  /// Defaults to [AuthProvider.getValidAccessToken].
  final Future<String?> Function()? accessTokenLoader;

  /// Defaults to [AuthProvider.logout].
  final Future<void> Function()? onUnauthorized;

  /// Clock for "Synced 5m ago"; defaults to [DateTime.now].
  final DateTime Function()? now;

  static const webPath = '/settings/providers';

  /// "Synced 5m ago" for [at] seen from [now]; null means never synced.
  static String lastSyncedLabel(
    AppLocalizations l,
    DateTime? at, {
    required DateTime now,
  }) {
    if (at == null) return l.accountActionsNeverSynced;
    final age = now.difference(at);
    if (age.inMinutes < 1) return l.accountActionsSyncedJustNow;
    if (age.inHours < 1) return l.accountActionsSyncedMinutesAgo(age.inMinutes);
    if (age.inDays < 1) return l.accountActionsSyncedHoursAgo(age.inHours);
    return l.accountActionsSyncedDaysAgo(age.inDays);
  }

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  late final ProviderConnectionsService _service;
  List<ProviderConnection>? _connections;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? ProviderConnectionsService();
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

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final token = await _token();
    if (!mounted) return;
    if (token == null) return _unauthorized();
    final result = await _service.list(accessToken: token);
    if (!mounted) return;
    if (result['error'] == 'unauthorized') return _unauthorized();
    final ok = result['success'] == true;
    if (!ok && _connections != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(AppLocalizations.of(context).p3roConnectionsLoadFailed)));
    }
    setState(() {
      _loading = false;
      if (ok) {
        _connections =
            (result['connections'] as List<dynamic>).cast<ProviderConnection>();
      }
    });
  }

  void _openWeb() {
    openWebFallback(context,
        title: AppLocalizations.of(context).shellConnections,
        path: ConnectionsScreen.webPath);
  }

  Future<void> _syncNow() async {
    await showSyncNowDialog(context);
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final connections = _connections;
    final now = (widget.now ?? DateTime.now)();

    final Widget content;
    if (connections == null && _loading) {
      content = const Padding(
        padding: EdgeInsets.only(top: 96),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (connections == null) {
      content = ManageMessage(
        icon: Icons.error_outline,
        title: l.p3roConnectionsLoadFailed,
        onRetry: _load,
      );
    } else if (connections.isEmpty) {
      content = ManageMessage(
        icon: Icons.link_off,
        title: l.p3roConnectionsEmpty,
        body: l.p3roConnectionsEmptyBody,
      );
    } else {
      content = Column(
        children: [
          for (final connection in connections)
            _ConnectionCard(
              connection: connection,
              lastSynced: ConnectionsScreen.lastSyncedLabel(
                  l, connection.lastSyncedAt?.toLocal(),
                  now: now),
              onFix: _openWeb,
            ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l.shellConnections),
        actions: [
          IconButton(
            tooltip: l.accountActionsSyncNow,
            icon: const Icon(Icons.sync),
            onPressed: connections == null || connections.isEmpty
                ? null
                : _syncNow,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: SureSpacing.huge),
          children: [
            SureListGroup(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              children: [
                SureListRow(
                  leading: Icon(Icons.add_link, color: palette.textPrimary),
                  title: l.p3roConnectionsManageOnWeb,
                  trailing: Icon(
                    Icons.language,
                    size: 18,
                    color: palette.textSubdued,
                    semanticLabel: l.shellOpensOnWeb,
                  ),
                  onTap: _openWeb,
                ),
              ],
            ),
            content,
          ],
        ),
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.connection,
    required this.lastSynced,
    required this.onFix,
  });

  final ProviderConnection connection;
  final String lastSynced;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = SureColors.of(context).palette;
    final c = connection;

    final (String status, Color statusColor, IconData statusIcon) =
        c.scheduledForDeletion
            ? (l.p3roConnectionStatusDeleting, palette.textSubdued,
                Icons.delete_outline)
            : c.needsAttention
                ? (l.p3roConnectionStatusNeedsAttention, palette.warning,
                    Icons.error_outline)
                : c.syncing
                    ? (l.p3roConnectionStatusSyncing, palette.textSecondary,
                        Icons.sync)
                    : (l.p3roConnectionStatusConnected, palette.success,
                        Icons.check_circle_outline);

    final problems = <String>[
      if (c.needsReconnect) l.p3roConnectionReconnect,
      if (c.syncErrorMessage != null && c.syncErrorMessage!.isNotEmpty)
        c.syncErrorMessage!,
      if (c.unlinkedAccounts > 0)
        l.p3roConnectionAccountsNeedSetup(c.unlinkedAccounts)
      else if (c.pendingAccountSetup)
        l.p3roConnectionPendingSetup,
    ];

    final secondary = theme.textTheme.bodySmall
        ?.copyWith(color: palette.textSecondary);

    return SureCard(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
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
                    Text(c.displayName,
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    Text(
                      '${c.providerLabel} · ${l.p3roConnectionAccounts(c.totalAccounts)}',
                      style: secondary,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: SureSpacing.md),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(statusIcon, size: 16, color: statusColor),
                  const SizedBox(width: SureSpacing.xs),
                  Text(status,
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: statusColor)),
                ],
              ),
            ],
          ),
          const SizedBox(height: SureSpacing.sm),
          Text(lastSynced, style: secondary),
          for (final problem in problems)
            Padding(
              padding: const EdgeInsets.only(top: SureSpacing.xs),
              child: Text(problem,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: palette.warning)),
            ),
          if (c.needsAttention) ...[
            const SizedBox(height: SureSpacing.lg),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: SureButton(
                label: l.p3roConnectionFixOnWeb,
                leading: const Icon(Icons.language, size: 16),
                variant: SureButtonVariant.outline,
                onPressed: onFix,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
