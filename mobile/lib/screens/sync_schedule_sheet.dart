import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../models/provider_connection.dart';
import '../models/sync_schedule.dart';
import '../services/provider_connections_service.dart';
import '../theme/sure_colors.dart';
import '../widgets/ds/ds.dart';
import '../widgets/manage_widgets.dart';

/// Opens the sync schedule sheet for [connection] (Sure+
/// `settings.sync_schedule`). Returns true when the server said this
/// connection can't have a schedule (`sync_schedule_not_supported`), so the
/// caller can hide the action.
Future<bool> showSyncScheduleSheet(
  BuildContext context, {
  required ProviderConnection connection,
  required ProviderConnectionsService service,
  required Future<String?> Function() token,
  required Future<void> Function() onUnauthorized,
  DateTime Function()? now,
}) async {
  final unsupported = await showSureSheet<bool>(
    context: context,
    builder: (_) => SyncScheduleSheet(
      connection: connection,
      service: service,
      token: token,
      onUnauthorized: onUnauthorized,
      now: now,
    ),
  );
  return unsupported == true;
}

/// "Every 15 min", "Every hour", "Every 2 hours".
String syncIntervalLabel(AppLocalizations l, int minutes) =>
    minutes >= 60 && minutes % 60 == 0
        ? l.s4sScheduleEveryHours(minutes ~/ 60)
        : l.s4sScheduleEveryMinutes(minutes);

/// "Default" plus each allowed interval, with a check on the current one and
/// "Next sync …" under the list. A tap saves at once.
class SyncScheduleSheet extends StatefulWidget {
  const SyncScheduleSheet({
    super.key,
    required this.connection,
    required this.service,
    required this.token,
    required this.onUnauthorized,
    this.now,
  });

  final ProviderConnection connection;
  final ProviderConnectionsService service;
  final Future<String?> Function() token;
  final Future<void> Function() onUnauthorized;
  final DateTime Function()? now;

  @override
  State<SyncScheduleSheet> createState() => _SyncScheduleSheetState();
}

class _SyncScheduleSheetState extends State<SyncScheduleSheet> {
  SyncSchedule? _schedule;
  bool _loading = true;
  bool _unsupported = false;

  /// The interval being saved; `-1` for none.
  int? _saving = -1;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Map<String, dynamic>?> _run(
    Future<Map<String, dynamic>> Function(String token) call,
  ) async {
    final token = await widget.token();
    if (token == null) {
      await _signOut();
      return null;
    }
    final result = await call(token);
    if (result['error'] == 'unauthorized') {
      await _signOut();
      return null;
    }
    return result;
  }

  Future<void> _signOut() async {
    if (mounted) Navigator.of(context).pop();
    await widget.onUnauthorized();
  }

  String _message(Map<String, dynamic> result, String fallback) {
    final status = result['status'];
    return status == 403 || status == 422
        ? result['error']?.toString() ?? fallback
        : fallback;
  }

  Future<void> _load() async {
    final result = await _run((token) => widget.service
        .syncSchedule(accessToken: token, connection: widget.connection));
    if (result == null || !mounted) return;
    final l = AppLocalizations.of(context);
    setState(() {
      _loading = false;
      if (result['success'] == true) {
        _schedule = result['schedule'] as SyncSchedule;
        _error = null;
      } else {
        _unsupported = result['code'] == 'sync_schedule_not_supported';
        _error = _message(result, l.s4sScheduleLoadFailed);
      }
    });
  }

  Future<void> _select(int? interval) async {
    final current = _schedule;
    if (current == null || _saving != -1) return;
    if (interval == current.intervalMinutes) return;
    setState(() {
      _saving = interval;
      _error = null;
    });
    final result = await _run((token) => widget.service.updateSyncSchedule(
        accessToken: token,
        connection: widget.connection,
        intervalMinutes: interval));
    if (result == null || !mounted) return;
    final l = AppLocalizations.of(context);
    setState(() {
      _saving = -1;
      if (result['success'] == true) {
        _schedule = result['schedule'] as SyncSchedule;
      } else {
        _error = _message(result, l.s4sActionFailed);
      }
    });
    if (result['success'] == true) SureHaptics.selection();
  }

  String? _nextLabel(BuildContext context, DateTime? at) {
    if (at == null) return null;
    final local = at.toLocal();
    final now = (widget.now ?? DateTime.now)();
    final locale = Localizations.localeOf(context).toString();
    final time = DateFormat.jm(locale).format(local);
    final sameDay = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    return sameDay ? time : '${SureDates.shortOf(context, local, now: now)}, $time';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final schedule = _schedule;

    final Widget body;
    if (schedule == null && _loading) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (schedule == null) {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: ManageErrorText(_error ?? l.s4sScheduleLoadFailed),
      );
    } else {
      Widget option(int? minutes, String label) {
        final selected = schedule.intervalMinutes == minutes;
        final saving = _saving == minutes;
        return SureListRow(
          key: ValueKey('syncScheduleOption-${minutes ?? 'default'}'),
          title: label,
          trailing: saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : selected
                  ? SureIcon(SureIcons.check, size: 18, color: palette.link)
                  : null,
          onTap: () => _select(minutes),
        );
      }

      final next = _nextLabel(context, schedule.nextRunAt);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SurePanel.rows(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            children: [
              option(null, l.s4sScheduleDefault),
              for (final minutes in schedule.allowedIntervals)
                option(minutes, syncIntervalLabel(l, minutes)),
            ],
          ),
          if (next != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(30, 8, 30, 0),
              child: Text(
                l.s4sScheduleNext(next),
                style: TextStyle(fontSize: 13, color: palette.textSecondary),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: ManageErrorText(_error!),
            ),
        ],
      );
    }

    return SureSheet(
      title: l.s4sScheduleTitle,
      showCancel: false,
      actionLabel: l.dsDone,
      onAction: () => Navigator.of(context).pop(_unsupported),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(30, 0, 30, 0),
              child: Text(
                widget.connection.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: palette.textSecondary),
              ),
            ),
            body,
          ],
        ),
      ),
    );
  }
}
