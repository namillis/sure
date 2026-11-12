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
import '../widgets/ds/ds.dart';
import '../widgets/manage_widgets.dart';
import '../widgets/sure_button.dart';

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
    final exports = _exports;

    final Widget history;
    if (exports == null && _loading) {
      history = const ManageLoading();
    } else if (_forbidden) {
      history = SureEmptyState(
        key: const ValueKey('exportForbidden'),
        icon: ManageIcons.shield,
        title: l.manageExportAdminOnly,
      );
    } else if (exports == null || (_failed && exports.isEmpty)) {
      history = SureEmptyState(
        key: const ValueKey('exportError'),
        icon: SureIcons.circleAlert,
        title: l.manageExportLoadFailed,
        primaryLabel: l.commonTryAgain,
        onPrimary: _refresh,
      );
    } else if (exports.isEmpty) {
      history = SureEmptyState(
        key: const ValueKey('exportEmpty'),
        icon: ManageIcons.package,
        title: l.ds4dExportEmptyTitle,
        body: l.ds4dExportEmptyBody,
      );
    } else {
      final stalled =
          _polls >= widget.maxPolls && exports.any((e) => e.inProgress);
      history = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SureSectionHeader(label: l.manageExportHistory),
          SurePanel.rows(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            dividerIndent: SurePanel.iconRowDividerIndent,
            children: [
              for (final export in exports) _row(context, export),
            ],
          ),
          if (stalled)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(l.manageExportStillPreparing,
                  style:
                      TextStyle(fontSize: 13, color: palette.textSecondary)),
            ),
        ],
      );
    }

    return SureLargeTitleScaffold(
      title: l.manageExportTitle,
      leading: manageBackLink(context),
      onRefresh: _refresh,
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SurePanel(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l.manageExportIntro,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: palette.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SureButton(
                      label: l.manageExportCreate,
                      leading: SureIcon(ManageIcons.package,
                          size: 16, color: palette.textInverse),
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
      ],
    );
  }

  Widget _row(BuildContext context, FamilyExport export) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final downloading = _downloadingId == export.id;
    Widget? trailing;
    if (export.downloadable) {
      trailing = downloading
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(
              l.manageExportDownload,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: _downloadingId == null
                    ? palette.link
                    : palette.textSubdued,
              ),
            );
    } else if (export.inProgress) {
      trailing = const SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    // The row is the download button; Builder gives the share popover an
    // anchor on iPad.
    return Builder(
      builder: (rowContext) => SureListRow(
        title: _dateLabel(context, export),
        subtitle: _subtitle(l, export),
        leading: _StatusIcon(status: export.status),
        trailing: trailing,
        onTap: export.downloadable && _downloadingId == null
            ? () => _download(export, rowContext)
            : null,
      ),
    );
  }

  String _dateLabel(BuildContext context, FamilyExport export) {
    final created = export.createdAt?.toLocal();
    if (created == null) return export.filename;
    final locale = Localizations.localeOf(context).toString();
    return '${SureDates.relativeDayOf(context, created)} · '
        '${DateFormat.jm(locale).format(created)}';
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
      'completed' => (SureIcons.circleCheck, palette.success),
      'failed' => (SureIcons.circleAlert, palette.destructive),
      _ => (SureIcons.clock, null),
    };
    // Decorative: the row subtitle states the status in words.
    return ManageIconBadge(icon: icon, color: color);
  }
}
