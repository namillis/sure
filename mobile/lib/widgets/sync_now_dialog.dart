import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/family_sync.dart';
import '../providers/auth_provider.dart';
import '../services/family_sync_service.dart';
import '../theme/sure_colors.dart';

/// Starts a family sync and shows its progress until it finishes, fails or
/// two minutes pass. Resolves `true` when the sync completed.
Future<bool> showSyncNowDialog(
  BuildContext context, {
  FamilySyncService? service,
}) async {
  final completed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => SyncNowDialog(service: service),
  );
  return completed == true;
}

class SyncNowDialog extends StatefulWidget {
  const SyncNowDialog({super.key, this.service});

  final FamilySyncService? service;

  @override
  State<SyncNowDialog> createState() => _SyncNowDialogState();
}

enum _Phase { starting, syncing, completed, failed, timedOut }

class _SyncNowDialogState extends State<SyncNowDialog> {
  late final FamilySyncService _service =
      widget.service ?? FamilySyncService();
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _ticker;
  _Phase _phase = _Phase.starting;
  String? _message;

  @override
  void initState() {
    super.initState();
    _stopwatch.start();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _run();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    if (widget.service == null) _service.close();
    super.dispose();
  }

  Future<void> _run() async {
    final authProvider = context.read<AuthProvider>();
    final navigator = Navigator.of(context);
    final token = await authProvider.getValidAccessToken();
    if (!mounted) return;
    if (token == null) {
      navigator.pop(false);
      await authProvider.logout();
      return;
    }

    final result = await _service.syncAndWait(
      accessToken: token,
      onUpdate: (FamilySync sync) {
        if (mounted && sync.inProgress) {
          setState(() => _phase = _Phase.syncing);
        }
      },
    );
    if (!mounted) return;

    if (result['error'] == 'unauthorized') {
      navigator.pop(false);
      await authProvider.logout();
      return;
    }

    _stopwatch.stop();
    _ticker?.cancel();
    setState(() {
      if (result['success'] == true) {
        _phase = _Phase.completed;
      } else if (result['error'] == 'timeout') {
        _phase = _Phase.timedOut;
      } else {
        _phase = _Phase.failed;
        _message = result['error'] == 'failed'
            ? result['message']?.toString()
            : result['error']?.toString();
      }
    });
  }

  String _elapsed() {
    final s = _stopwatch.elapsed.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final running = _phase == _Phase.starting || _phase == _Phase.syncing;

    final Widget leading;
    final String text;
    switch (_phase) {
      case _Phase.starting:
      case _Phase.syncing:
        leading = const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        );
        text = _phase == _Phase.starting
            ? l.accountActionsSyncStarting
            : l.accountActionsSyncing;
      case _Phase.completed:
        leading = Icon(Icons.check_circle, color: palette.success);
        text = l.accountActionsSyncComplete;
      case _Phase.failed:
        leading = Icon(Icons.error_outline, color: palette.destructive);
        text = _message == null || _message!.isEmpty
            ? l.accountActionsSyncFailed
            : l.accountActionsSyncFailedDetail(_message!);
      case _Phase.timedOut:
        leading = Icon(Icons.schedule, color: palette.warning);
        text = l.accountActionsSyncTimeout;
    }

    return AlertDialog(
      title: Text(l.accountActionsSyncNow),
      content: Semantics(
        liveRegion: true,
        child: Row(
          children: [
            leading,
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text),
                  if (running)
                    Text(
                      l.accountActionsSyncElapsed(_elapsed()),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: palette.textSecondary,
                          ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        // Hiding while running leaves the sync going on the server.
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(_phase == _Phase.completed),
          child: Text(running ? l.accountActionsHide : l.accountActionsClose),
        ),
      ],
    );
  }
}
