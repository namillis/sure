import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/family_sync.dart';
import '../providers/auth_provider.dart';
import '../services/family_sync_service.dart';
import '../theme/sure_colors.dart';
import 'sure_chip.dart';
import 'sync_now_dialog.dart';

/// Shows the newest sync (`GET /api/v1/syncs/latest`) as "Synced 5m ago",
/// "Syncing..." or "Sync failed", re-checking every [pollInterval] while one
/// is running. Tapping it runs "Sync now" and calls [onSynced] when that
/// completes. Renders nothing until the first status arrives.
class SyncStatusChip extends StatefulWidget {
  const SyncStatusChip({
    super.key,
    this.service,
    this.onSynced,
    this.pollInterval = const Duration(seconds: 5),
  });

  final FamilySyncService? service;
  final VoidCallback? onSynced;
  final Duration pollInterval;

  /// The chip text for [sync] at [now]; null [sync] means never synced.
  static String labelFor(
    AppLocalizations l,
    FamilySync? sync, {
    required DateTime now,
  }) {
    if (sync == null) return l.accountActionsNeverSynced;
    if (sync.inProgress) return l.accountActionsSyncing;
    if (sync.failed) return l.accountActionsSyncFailed;
    final at = sync.completedAt ?? sync.createdAt;
    if (at == null) return l.accountActionsSyncComplete;
    final age = now.difference(at);
    if (age.inMinutes < 1) return l.accountActionsSyncedJustNow;
    if (age.inHours < 1) return l.accountActionsSyncedMinutesAgo(age.inMinutes);
    if (age.inDays < 1) return l.accountActionsSyncedHoursAgo(age.inHours);
    return l.accountActionsSyncedDaysAgo(age.inDays);
  }

  @override
  State<SyncStatusChip> createState() => _SyncStatusChipState();
}

class _SyncStatusChipState extends State<SyncStatusChip> {
  late final FamilySyncService _service =
      widget.service ?? FamilySyncService();
  FamilySync? _sync;
  bool _loaded = false;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    if (widget.service == null) _service.close();
    super.dispose();
  }

  Future<void> _load() async {
    _poll?.cancel();
    final authProvider = context.read<AuthProvider>();
    final token = await authProvider.getValidAccessToken();
    if (!mounted || token == null) return;

    final result = await _service.getSync(accessToken: token);
    if (!mounted) return;
    if (result['error'] == 'unauthorized') {
      await authProvider.logout();
      return;
    }
    if (result['success'] != true) return;

    setState(() {
      _loaded = true;
      _sync = result['sync'] as FamilySync?;
    });
    if (_sync?.inProgress == true) {
      _poll = Timer(widget.pollInterval, _load);
    }
  }

  Future<void> _syncNow() async {
    final completed = await showSyncNowDialog(context, service: widget.service);
    if (!mounted) return;
    if (completed) widget.onSynced?.call();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final sync = _sync;

    final Widget icon;
    if (sync != null && sync.inProgress) {
      icon = const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (sync != null && sync.failed) {
      icon = Icon(Icons.error_outline, size: 16, color: palette.destructive);
    } else {
      icon = Icon(Icons.sync, size: 16, color: palette.textSecondary);
    }

    return Semantics(
      hint: l.accountActionsSyncChipHint,
      child: SureChip(
        label: SyncStatusChip.labelFor(l, sync, now: DateTime.now()),
        leading: icon,
        onSelected: sync?.inProgress == true ? null : (_) => _syncNow(),
      ),
    );
  }
}
