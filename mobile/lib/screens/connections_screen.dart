import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../models/connection_setup.dart';
import '../models/provider_connection.dart';
import '../providers/accounts_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/server_features_provider.dart';
import '../services/connection_setup_service.dart';
import '../services/provider_connections_service.dart';
import '../services/web_auth_session.dart';
import '../theme/sure_colors.dart';
import '../widgets/ds/ds.dart';
import '../widgets/open_on_web_action.dart';
import '../widgets/sync_now_dialog.dart';
import 'account_form_sheet.dart' show reloadAccounts;
import 'connection_setup_sheets.dart';
import 'settings_links.dart';
import 'sync_schedule_sheet.dart';

/// The family's bank and broker connections from
/// `GET /api/v1/provider_connections`. Connecting and reconnecting happen on
/// the web (`/settings/providers`); rows that need attention link there.
/// "Sync now" in the nav bar runs the family sync. On Sure+ servers with
/// `connections.manage`, swiping a connection offers Sync now and
/// Disconnect for that one connection.
///
/// Round 4a: with `connections.available` the nav bar's "+" lists the
/// providers the user may add. Token providers (`connections.token_create`)
/// connect in a native form; the rest, and reconnects, run a web handoff
/// (`connections.web_handoff`) in [WebAuthSession].
class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({
    super.key,
    this.service,
    this.accessTokenLoader,
    this.onUnauthorized,
    this.now,
    this.setupService,
    this.webAuth,
  });

  final ProviderConnectionsService? service;

  /// Round 4a add/reconnect calls.
  final ConnectionSetupService? setupService;

  /// Defaults to [AppWebAuthSession].
  final WebAuthSession? webAuth;

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
  late final ConnectionSetupService _setup;
  List<ProviderConnection>? _connections;
  bool _loading = true;

  /// A web handoff is being requested or is open.
  bool _handoffBusy = false;

  /// Connections the server said can't have a sync schedule.
  final Set<String> _noSchedule = {};

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? ProviderConnectionsService();
    _setup = widget.setupService ?? ConnectionSetupService();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    if (widget.service == null) _service.close();
    if (widget.setupService == null) _setup.close();
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

  /// FinanceKit syncs from the device, so it never gets a schedule.
  bool _schedulable(ProviderConnection c) =>
      c.provider != 'financekit' &&
      !_noSchedule.contains('${c.provider}:${c.id}');

  Future<void> _schedule(ProviderConnection connection) async {
    final unsupported = await showSyncScheduleSheet(
      context,
      connection: connection,
      service: _service,
      token: _token,
      onUnauthorized: _unauthorized,
      now: widget.now,
    );
    if (unsupported && mounted) {
      setState(() => _noSchedule.add('${connection.provider}:${connection.id}'));
    }
  }

  void _openWeb() {
    openWebFallback(context,
        title: AppLocalizations.of(context).shellConnections,
        path: ConnectionsScreen.webPath);
  }

  bool _has(String feature) =>
      context.read<ServerFeaturesProvider?>()?.has(feature) ?? false;

  void _snack(String message, {SnackBarAction? action}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      duration: Duration(seconds: action == null ? 4 : 6),
      action: action,
    ));
  }

  SnackBarAction _openOnWebAction() => SnackBarAction(
      label: AppLocalizations.of(context).s4cOpenOnWeb, onPressed: _openWeb);

  Future<void> _addConnection() async {
    final entry = await showSureSheet<AvailableConnection>(
      context: context,
      builder: (_) => AddConnectionSheet(load: () async {
        final token = await _token();
        if (token == null) return {'success': false, 'error': 'unauthorized'};
        return _setup.available(accessToken: token);
      }),
    );
    if (entry == null || !mounted) return;
    if (entry.isToken &&
        _has(ServerFeaturesProvider.connectionsTokenCreate) &&
        TokenConnectionSheet.supports(entry.provider)) {
      return _tokenConnect(entry);
    }
    return _connectOnWeb(entry.connectPath);
  }

  /// A handoff to [path], or the old web view without `connections.web_handoff`.
  Future<void> _connectOnWeb(String path) async {
    if (_has(ServerFeaturesProvider.connectionsWebHandoff)) {
      return _handoff(path);
    }
    _openWeb();
  }

  Future<void> _tokenConnect(AvailableConnection entry) async {
    final outcome = await showSureSheet<TokenConnectionResult>(
      context: context,
      builder: (_) => TokenConnectionSheet(
        entry: entry,
        now: widget.now,
        onConnect: (fields) async {
          final token = await _token();
          if (token == null) return {'success': false, 'error': 'unauthorized'};
          return _setup.create(
              accessToken: token, provider: entry.provider, fields: fields);
        },
      ),
    );
    if (outcome == null || !mounted) return;
    if (outcome.fallbackToWeb) return _connectOnWeb(entry.connectPath);
    final result = outcome.result;
    if (result['error'] == 'unauthorized') return _unauthorized();
    final connection = result['connection'] as ProviderConnection;
    if (result['setupRequired'] == true || result['awaitingAccounts'] == true) {
      await _load();
      if (!mounted) return;
      return _finishSetup(connection, providerName: entry.name);
    }
    SureHaptics.success();
    await _load();
    if (mounted) _snack(AppLocalizations.of(context).s4cConnectedSyncing);
  }

  Future<void> _finishSetup(ProviderConnection connection,
      {String? providerName}) async {
    final l = AppLocalizations.of(context);
    List<Account> linkable = const [];
    try {
      linkable = context
          .read<AccountsProvider>()
          .accounts
          .where((a) => a.linked != true)
          .toList();
    } on ProviderNotFoundException {
      // Isolated tests: no account list to link to.
    }
    final result = await showSureSheet<AccountSetupResult>(
      context: context,
      isDismissible: false,
      builder: (_) => AccountSetupSheet(
        connectionId: connection.id,
        provider: connection.provider,
        providerName: providerName ?? connection.providerLabel,
        service: _setup,
        token: _token,
        onUnauthorized: _unauthorized,
        linkableAccounts: linkable,
        now: widget.now,
      ),
    );
    if (!mounted) return;
    switch (result?.outcome) {
      case AccountSetupOutcome.imported:
        await _load();
        if (!mounted) return;
        _snack(l.s4cImported(result!.count));
        await reloadAccounts(context);
      case AccountSetupOutcome.timedOut:
        _snack(l.s4cStillSyncing);
        await _load();
      case AccountSetupOutcome.nothingPending:
        await _load();
        if (mounted) _snack(l.s4cConnectedSyncing);
      case AccountSetupOutcome.linkExisting:
        await _handoff(result!.linkPath!);
      case null:
        await _load();
    }
  }

  /// Opens [path] signed in through a one-time handoff URL. The URL holds a
  /// single-use token: it stays in this method, never in state or a log.
  Future<void> _handoff(String path) async {
    if (_handoffBusy) return;
    setState(() => _handoffBusy = true);
    try {
      final token = await _token();
      if (!mounted) return;
      if (token == null) return await _unauthorized();
      final result = await _setup.createHandoff(accessToken: token, path: path);
      if (!mounted) return;
      if (result['error'] == 'unauthorized') return await _unauthorized();
      final l = AppLocalizations.of(context);
      if (result['success'] != true) {
        final status = result['status'];
        final generic = status != 429 && status != 403;
        _snack(
          generic ? l.s4cConnectError : connectionSetupErrorMessage(l, result),
          action: generic ? _openOnWebAction() : null,
        );
        return;
      }
      final status = await (widget.webAuth ?? const AppWebAuthSession())
          .open(result['url'] as Uri);
      if (!mounted) return;
      switch (status) {
        case WebHandoffStatus.ok:
          SureHaptics.success();
          await _load();
          if (mounted) _snack(l.s4cConnectedSyncing);
        case WebHandoffStatus.cancelled:
          break;
        case WebHandoffStatus.closed:
          // Some flows finish without sending the app back; a quiet refresh
          // shows whatever they did.
          await _load();
        case WebHandoffStatus.error:
          _snack(l.s4cConnectError, action: _openOnWebAction());
      }
    } finally {
      if (mounted) setState(() => _handoffBusy = false);
    }
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
    final canSchedule = context
            .watch<ServerFeaturesProvider?>()
            ?.has(ServerFeaturesProvider.settingsSyncSchedule) ??
        false;
    final features = context.watch<ServerFeaturesProvider?>();
    final canAdd =
        features?.has(ServerFeaturesProvider.connectionsAvailable) ?? false;
    final canHandoff =
        features?.has(ServerFeaturesProvider.connectionsWebHandoff) ?? false;
    final canSetup =
        features?.has(ServerFeaturesProvider.connectionsTokenCreate) ?? false;
    final needsSignIn = canHandoff
        ? connections
            ?.where((c) => c.reconnectPath != null && !c.scheduledForDeletion)
            .firstOrNull
        : null;

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
                onReconnect: canHandoff && connection.reconnectPath != null
                    ? () => _handoff(connection.reconnectPath!)
                    : null,
                onFinishSetup: canSetup &&
                        TokenConnectionSheet.supports(connection.provider) &&
                        (connection.pendingAccountSetup ||
                            connection.unlinkedAccounts > 0)
                    ? () => _finishSetup(connection)
                    : null,
                onSync: canManage ? () => _syncConnection(connection) : null,
                onDisconnect: canManage ? () => _disconnect(connection) : null,
                onSchedule: canSchedule && _schedulable(connection)
                    ? () => _schedule(connection)
                    : null,
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
        if (canAdd)
          SureNavIconButton(
            icon: SureIcons.plus,
            semanticLabel: l.s4cAddConnection,
            onPressed: _handoffBusy ? null : _addConnection,
          ),
        SureNavIconButton(
          icon: SureIcons.refresh,
          semanticLabel: l.accountActionsSyncNow,
          onPressed:
              connections == null || connections.isEmpty ? null : _syncNow,
        ),
      ],
      onRefresh: _load,
      slivers: [
        if (needsSignIn != null)
          SliverToBoxAdapter(
            child: SureBanner(
              key: const ValueKey('s4cReconnectBanner'),
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              message: l.s4cReconnectBanner(needsSignIn.displayName),
              actionLabel: l.s4cReconnect,
              onAction: () => _handoff(needsSignIn.reconnectPath!),
            ),
          ),
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
    this.onReconnect,
    this.onFinishSetup,
    this.onSync,
    this.onDisconnect,
    this.onSchedule,
  });

  final ProviderConnection connection;
  final String lastSynced;
  final VoidCallback onFix;

  /// Round 4a: a web handoff to the row's `reconnect_path`; null hides it.
  final VoidCallback? onReconnect;

  /// Round 4a: account setup for pending accounts; null hides it.
  final VoidCallback? onFinishSetup;

  /// Swipe actions, offered with `connections.manage`; null hides them.
  final VoidCallback? onSync;
  final VoidCallback? onDisconnect;

  /// Opens the sync schedule (`settings.sync_schedule`); null hides it.
  final VoidCallback? onSchedule;

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

    final reconnect = c.scheduledForDeletion ? null : onReconnect;
    final finishSetup = c.scheduledForDeletion ? null : onFinishSetup;
    // A connection that needs a sign-in can't sync; dropping Sync now keeps
    // the actions within a 320 pt row.
    final sync = c.scheduledForDeletion || reconnect != null ? null : onSync;
    final disconnect = c.scheduledForDeletion ? null : onDisconnect;
    final schedule = c.scheduledForDeletion ? null : onSchedule;
    final actions = [
      if (reconnect != null)
        SureSwipeAction(
          label: l.s4cReconnect,
          color: palette.warning,
          onPressed: reconnect,
        ),
      if (sync != null)
        SureSwipeAction(
          label: l.spdConnectionSyncNow,
          color: palette.link,
          onPressed: sync,
        ),
      if (schedule != null)
        SureSwipeAction(
          label: l.s4sSchedule,
          color: palette.warning,
          onPressed: schedule,
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
              if (reconnect != null)
                CustomSemanticsAction(label: l.s4cReconnect): reconnect,
              if (sync != null)
                CustomSemanticsAction(label: l.spdConnectionSyncNow): sync,
              if (schedule != null)
                CustomSemanticsAction(label: l.s4sSchedule): schedule,
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
        if (finishSetup != null)
          SureListRow(
            title: l.s4cFinishSetup,
            titleColor: palette.link,
            showChevron: true,
            onTap: finishSetup,
          ),
        // Pending accounts alone are handled by Finish setup.
        if (c.needsAttention &&
            (finishSetup == null || c.needsReconnect || c.hasSyncError))
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
