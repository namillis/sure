import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../services/family_exports_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_spacing.dart';
import '../widgets/manage_widgets.dart';
import '../widgets/sure_button.dart';
import '../widgets/sure_card.dart';
import '../widgets/sure_list_group.dart';

/// Hands a downloaded file to the system share sheet. [origin] anchors the
/// popover on iPad.
typedef ExportFileSharer = Future<void> Function(File file, Rect? origin);

Future<void> _shareWithSystemSheet(File file, Rect? origin) async {
  await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path, mimeType: 'application/zip')],
    sharePositionOrigin: origin,
  ));
}

/// Creates family data exports, lists past ones, and downloads a finished
/// one to the share sheet (so it can be saved to Files). Exports are built
/// in the background; while any is in progress the list is re-read every
/// few seconds, up to a cap.
class ExportScreen extends StatefulWidget {
  const ExportScreen({
    super.key,
    this.service,
    this.accessTokenLoader,
    this.onUnauthorized,
    this.shareFile,
    this.pollInterval = const Duration(seconds: 4),
    this.maxPolls = 45,
  });

  final FamilyExportsService? service;

  /// Defaults to [AuthProvider.getValidAccessToken].
  final Future<String?> Function()? accessTokenLoader;

  /// Defaults to [AuthProvider.logout].
  final Future<void> Function()? onUnauthorized;

  /// Defaults to the share_plus share sheet.
  final ExportFileSharer? shareFile;

  final Duration pollInterval;

  /// Polls before giving up until the next refresh (about 3 minutes).
  final int maxPolls;

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  late final FamilyExportsService _service;
  List<FamilyExport>? _exports;
  bool _loading = true;
  bool _failed = false;
  bool _forbidden = false;
  bool _creating = false;
  String? _downloadingId;
  Timer? _poll;
  int _polls = 0;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? FamilyExportsService();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    if (widget.service == null) _service.close();
    super.dispose();
  }

  Future<String?> _token() {
    final loader = widget.accessTokenLoader;
    if (loader != null) return loader();
    return context.read<AuthProvider>().getValidAccessToken();
  }

  Future<void> _unauthorized() async {
    _poll?.cancel();
    final handler = widget.onUnauthorized;
    if (handler != null) return handler();
    await context.read<AuthProvider>().logout();
  }

  /// A user-started load resets the poll budget; a poll doesn't.
  Future<void> _refresh() async {
    _polls = 0;
    await _load();
  }

  Future<void> _load({bool fromPoll = false}) async {
    if (mounted && !fromPoll) setState(() => _loading = true);
    final token = await _token();
    if (!mounted) return;
    if (token == null) return _unauthorized();
    final result = await _service.list(accessToken: token);
    if (!mounted) return;
    if (result['error'] == 'unauthorized') return _unauthorized();
    if (result['success'] != true && _exports != null && !fromPoll) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context).manageExportLoadFailed)));
    }
    setState(() {
      _loading = false;
      _failed = result['success'] != true;
      _forbidden = result['status'] == 403;
      if (!_failed) _exports = result['exports'] as List<FamilyExport>;
    });
    _schedulePoll();
  }

  void _schedulePoll() {
    _poll?.cancel();
    final inFlight = _exports?.any((e) => e.inProgress) ?? false;
    if (!inFlight || _polls >= widget.maxPolls) return;
    _poll = Timer(widget.pollInterval, () {
      _polls++;
      _load(fromPoll: true);
    });
  }

  Future<void> _create() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _creating = true);
    final token = await _token();
    if (!mounted) return;
    if (token == null) return _unauthorized();
    final result = await _service.create(accessToken: token);
    if (!mounted) return;
    setState(() => _creating = false);
    if (result['error'] == 'unauthorized') return _unauthorized();
    messenger.showSnackBar(SnackBar(
      content: Text(result['success'] == true
          ? l.manageExportStarted
          : (result['status'] == 403
              ? l.manageExportAdminOnly
              : result['error']?.toString() ?? l.manageActionFailed)),
    ));
    if (result['success'] == true) await _refresh();
  }

  Future<void> _download(FamilyExport export, BuildContext buttonContext) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final box = buttonContext.findRenderObject() as RenderBox?;
    final origin = box == null || !box.hasSize
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _downloadingId = export.id);
    final token = await _token();
    if (!mounted) return;
    if (token == null) return _unauthorized();
    final result = await _service.download(
      accessToken: token,
      id: export.id,
      fallbackFilename: export.filename,
    );
    if (!mounted) return;
    if (result['error'] == 'unauthorized') return _unauthorized();
    if (result['success'] != true) {
      setState(() => _downloadingId = null);
      messenger.showSnackBar(
          SnackBar(content: Text(l.manageExportDownloadFailed)));
      return;
    }
    final file = result['file'] as File;
    try {
      await (widget.shareFile ?? _shareWithSystemSheet)(file, origin);
    } catch (_) {
      messenger.showSnackBar(
          SnackBar(content: Text(l.manageExportDownloadFailed)));
    } finally {
      // The share sheet has copied or saved the file by the time it closes.
      try {
        await file.parent.delete(recursive: true);
      } catch (_) {}
      if (mounted) setState(() => _downloadingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final theme = Theme.of(context);
    final exports = _exports;

    final Widget history;
    if (exports == null && _loading) {
      history = const Padding(
        padding: EdgeInsets.only(top: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_forbidden) {
      history = ManageMessage(
          icon: Icons.lock_outline, title: l.manageExportAdminOnly);
    } else if (exports == null || (_failed && exports.isEmpty)) {
      history = ManageMessage(
        icon: Icons.error_outline,
        title: l.manageExportLoadFailed,
        onRetry: _refresh,
      );
    } else if (exports.isEmpty) {
      history = Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Text(l.manageExportEmpty,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: palette.textSecondary)),
      );
    } else {
      final stalled =
          _polls >= widget.maxPolls && exports.any((e) => e.inProgress);
      history = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SureListGroup(
            header: l.manageExportHistory,
            margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            children: [
              for (final export in exports)
                SureListRow(
                  title: _dateLabel(context, export),
                  subtitle: _subtitle(l, export),
                  leading: _StatusIcon(status: export.status),
                  trailing: export.downloadable
                      ? Builder(
                          builder: (buttonContext) => ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 44),
                            child: SureButton(
                              label: l.manageExportDownload,
                              size: SureButtonSize.sm,
                              variant: SureButtonVariant.outline,
                              loading: _downloadingId == export.id,
                              onPressed: _downloadingId != null
                                  ? null
                                  : () => _download(export, buttonContext),
                            ),
                          ),
                        )
                      : (export.inProgress
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : null),
                ),
            ],
          ),
          if (stalled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(l.manageExportStillPreparing,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: palette.textSecondary)),
            ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.manageExportTitle)),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: SureSpacing.huge),
          children: [
            SureCard(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.all(SureSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l.manageExportIntro, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: SureSpacing.xl),
                  SureButton(
                    label: l.manageExportCreate,
                    leading: const Icon(Icons.archive_outlined, size: 16),
                    fullWidth: true,
                    loading: _creating,
                    onPressed: _creating || _forbidden ? null : _create,
                  ),
                ],
              ),
            ),
            history,
          ],
        ),
      ),
    );
  }

  String _dateLabel(BuildContext context, FamilyExport export) {
    final created = export.createdAt;
    if (created == null) return export.filename;
    final locale = Localizations.localeOf(context).toString();
    return DateFormat.yMMMd(locale).add_jm().format(created);
  }

  String _subtitle(AppLocalizations l, FamilyExport export) {
    final status = switch (export.status) {
      'completed' => l.manageExportStatusCompleted,
      'processing' => l.manageExportStatusProcessing,
      'failed' => l.manageExportStatusFailed,
      _ => l.manageExportStatusPending,
    };
    final size = export.byteSize;
    return size == null ? status : '$status · ${formatByteSize(size)}';
  }
}

/// "512 B", "2.0 KB", "3.4 MB".
String formatByteSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    final (icon, color) = switch (status) {
      'completed' => (Icons.check_circle_outline, palette.success),
      'failed' => (Icons.error_outline, palette.destructive),
      _ => (Icons.schedule, palette.textSecondary),
    };
    // Decorative: the row subtitle states the status in words.
    return ExcludeSemantics(child: Icon(icon, color: color));
  }
}
