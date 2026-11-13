import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/provider_connection.dart';
import '../providers/auth_provider.dart';
import '../providers/server_features_provider.dart';
import '../services/provider_connections_service.dart';
import '../theme/sure_colors.dart';
import '../widgets/ds/ds.dart';
import '../widgets/open_on_web_action.dart';
import '../widgets/sync_now_dialog.dart';
import 'settings_links.dart';

/// The family's bank and broker connections from
/// `GET /api/v1/provider_connections`. Connecting and reconnecting happen on
/// the web (`/settings/providers`); rows that need attention link there.
/// "Sync now" in the nav bar runs the family sync. On Sure+ servers with
/// `connections.manage`, swiping a connection offers Sync now and
/// Disconnect for that one connection.
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

  /// Puts the server's updated row in place of the old one.
  void _replace(ProviderConnection updated) {
    final list = _connections;
    if (list == null) return;
    setState(() {
      _connections = [
        for (final c in list)
          c.id == updated.id && c.provider == updated.provider ? updated : c,
      ];
    });
  }

  Future<void> _manage(
    Future<Map<String, dynamic>> Function(String token) call,
  ) async {
    final token = await _token();
    if (!mounted) return;
    if (token == null) return _unauthorized();
    final result = await call(token);
    if (!mounted) return;
    if (result['error'] == 'unauthorized') return _unauthorized();
    if (result['success'] == true) {
      SureHaptics.success();
      final updated = result['connection'];
      updated is ProviderConnection ? _replace(updated) : await _load();
      return;
    }
    _showManageError(result);
  }

  void _showManageError(Map<String, dynamic> result) {
    final l = AppLocalizations.of(context);
    final code = result['code'] as String?;
    final message = switch (code) {
      'sync_not_supported' => l.spdConnectionErrorSyncNotSupported,
      'disconnect_not_supported' => l.spdConnectionErrorDisconnectNotSupported,
      'manual_sync_required' => l.spdConnectionErrorManualSync,
      'not_connected' => l.spdConnectionErrorNotConnected,
      'reconnect_required' => l.spdConnectionErrorReconnect,
      'unlink_failed' => l.spdConnectionErrorUnlinkFailed,
      'insufficient_scope' => l.spdConnectionErrorScope,
      'forbidden' => l.spdConnectionErrorForbidden,
      _ => (result['status'] == 403 || result['status'] == 422)
          ? (result['error'] as String? ?? l.spdConnectionActionFailed)
          : l.spdConnectionActionFailed,
    };
    final fixOnWeb = ProviderConnectionsService.webFixCodes.contains(code) ||
        result['status'] == 403 ||
        result['status'] == 422;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 6),
      action: fixOnWeb
          ? SnackBarAction(label: l.p3roConnectionFixOnWeb, onPressed: _openWeb)
          : null,
    ));
  }

  Future<void> _syncConnection(ProviderConnection connection) => _manage(
      (token) => _service.sync(accessToken: token, connection: connection));

  Future<void> _disconnect(ProviderConnection connection) async {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.spdConnectionDisconnectTitle(connection.displayName)),
        content: Text(l.spdConnectionDisconnectBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: palette.destructive),
            child: Text(l.spdConnectionDisconnect),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _manage((token) =>
        _service.disconnect(accessToken: token, connection: connection));
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
    final canManage = context
            .watch<ServerFeaturesProvider?>()
            ?.has(ServerFeaturesProvider.connectionsManage) ??
        false;

    final List<Widget> content;
    if (connections == null && _loading) {
      content = const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    } else if (connections == null) {
      content = [
        _centered(SureEmptyState(
          icon: SureIcons.circleAlert,
          title: l.p3roConnectionsLoadFailed,
          secondaryLabel: l.commonTryAgain,
          onSecondary: _load,
        )),
      ];
    } else if (connections.isEmpty) {
      content = [
        _centered(SureEmptyState(
          icon: 'unplug',
          title: l.p3roConnectionsEmpty,
          body: l.p3roConnectionsEmptyBody,
        )),
      ];
    } else {
      content = [
        SliverList.list(
          children: [
            const SizedBox(height: 20),
            for (final connection in connections)
              _ConnectionPanel(
                connection: connection,
                lastSynced: ConnectionsScreen.lastSyncedLabel(
                    l, connection.lastSyncedAt?.toLocal(),
                    now: now),
                onFix: _openWeb,
                onSync: canManage ? () => _syncConnection(connection) : null,
                onDisconnect: canManage ? () => _disconnect(connection) : null,
              ),
          ],
        ),
      ];
    }

    return SureLargeTitleScaffold(
      title: l.shellConnections,
      // Connections opens from Settings.
      leading: Navigator.of(context).canPop()
          ? SureBackButton(label: l.shellSettingsTitle)
          : null,
      actions: [
        SureNavIconButton(
          icon: SureIcons.refresh,
          semanticLabel: l.accountActionsSyncNow,
          onPressed:
              connections == null || connections.isEmpty ? null : _syncNow,
        ),
      ],
      onRefresh: _load,
      slivers: [
        SliverToBoxAdapter(
          child: SurePanel.rows(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            dividerIndent: SurePanel.iconRowDividerIndent,
            children: [
              SureListRow(
                leading: SureIcon('plug', size: 20, color: palette.textPrimary),
                title: l.p3roConnectionsManageOnWeb,
                trailing: const SettingsWebMark(),
                onTap: _openWeb,
              ),
            ],
          ),
        ),
        ...content,
      ],
    );
  }

  Widget _centered(Widget state) => SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: state),
      );
}

class _ConnectionPanel extends StatelessWidget {
  const _ConnectionPanel({
    required this.connection,
    required this.lastSynced,
    required this.onFix,
    this.onSync,
    this.onDisconnect,
  });

  final ProviderConnection connection;
  final String lastSynced;
  final VoidCallback onFix;

  /// Swipe actions, offered with `connections.manage`; null hides them.
  final VoidCallback? onSync;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final c = connection;

    final (String status, Color statusColor, String statusIcon) =
        c.scheduledForDeletion
            ? (
                onDisconnect != null
                    ? l.spdConnectionStatusScheduled
                    : l.p3roConnectionStatusDeleting,
                palette.textSubdued,
                SureIcons.trash
              )
            : c.needsAttention
                ? (
                    l.p3roConnectionStatusNeedsAttention,
                    palette.warning,
                    SureIcons.triangleAlert
                  )
                : c.syncing
                    ? (
                        l.p3roConnectionStatusSyncing,
                        palette.textSecondary,
                        SureIcons.refresh
                      )
                    : (
                        l.p3roConnectionStatusConnected,
                        palette.success,
                        SureIcons.circleCheck
                      );

    final problems = <String>[
      if (c.needsReconnect) l.p3roConnectionReconnect,
      if (c.syncErrorMessage != null && c.syncErrorMessage!.isNotEmpty)
        c.syncErrorMessage!,
      if (c.unlinkedAccounts > 0)
        l.p3roConnectionAccountsNeedSetup(c.unlinkedAccounts)
      else if (c.pendingAccountSetup)
        l.p3roConnectionPendingSetup,
    ];

    final secondary = TextStyle(fontSize: 13, color: palette.textSecondary);

    final summary = Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  c.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SureIcon(statusIcon, size: 14, color: statusColor),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${c.providerLabel} · ${l.p3roConnectionAccounts(c.totalAccounts)}',
            style: secondary,
          ),
          Text(lastSynced, style: secondary),
          for (final problem in problems)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(problem,
                  style: TextStyle(fontSize: 13, color: palette.warning)),
            ),
        ],
      ),
    );

    final sync = c.scheduledForDeletion ? null : onSync;
    final disconnect = c.scheduledForDeletion ? null : onDisconnect;
    final actions = [
      if (sync != null)
        SureSwipeAction(
          label: l.spdConnectionSyncNow,
          color: palette.link,
          onPressed: sync,
        ),
      if (disconnect != null)
        SureSwipeAction(
          label: l.spdConnectionDisconnect,
          color: palette.destructive,
          onPressed: disconnect,
        ),
    ];

    return SurePanel.rows(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      children: [
        if (actions.isEmpty)
          summary
        else
          Semantics(
            customSemanticsActions: {
              if (sync != null)
                CustomSemanticsAction(label: l.spdConnectionSyncNow): sync,
              if (disconnect != null)
                CustomSemanticsAction(label: l.spdConnectionDisconnect):
                    disconnect,
            },
            child: SureSwipeActions(
              actionWidth: 96,
              actions: actions,
              child: ColoredBox(color: palette.container, child: summary),
            ),
          ),
        if (c.needsAttention)
          SureListRow(
            title: l.p3roConnectionFixOnWeb,
            titleColor: palette.link,
            trailing: const SettingsWebMark(),
            onTap: onFix,
          ),
      ],
    );
  }
}
