import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_localizations.dart';
import '../services/log_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_tokens.dart';
import '../widgets/ds/ds.dart';

/// Hands the exported log text to the system share sheet. [origin] anchors
/// the popover on iPad.
typedef LogSharer = Future<void> Function(String text, Rect? origin);

Future<void> _shareWithSystemSheet(String text, Rect? origin) async {
  await SharePlus.instance
      .share(ShareParams(text: text, sharePositionOrigin: origin));
}

/// The app's in-memory debug log ([LogService]): level filter chips, an
/// auto-scroll toggle, and share / copy / clear in the nav bar.
class LogViewerScreen extends StatefulWidget {
  const LogViewerScreen({super.key, this.sharer});

  /// Defaults to the system share sheet.
  final LogSharer? sharer;

  /// Dot color for a log [level].
  static Color levelColor(SureTokenPalette palette, String level) =>
      switch (level) {
        'ERROR' => palette.destructive,
        'WARNING' => palette.warning,
        'INFO' => palette.link,
        _ => palette.textSubdued,
      };

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  String _selectedLevel = 'ALL';
  final ScrollController _scrollController = ScrollController();
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    // Set log viewer as active to enable notifications
    LogService.instance.setLogViewerActive(true);
    // Add a test log to confirm logging is working
    LogService.instance.info('LogViewer', 'Log viewer screen opened');
  }

  @override
  void dispose() {
    // Set log viewer as inactive to disable notifications
    LogService.instance.setLogViewerActive(false);
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_autoScroll && _scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _share(BuildContext buttonContext) async {
    final box = buttonContext.findRenderObject() as RenderBox?;
    final origin = box == null || !box.hasSize
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    await (widget.sharer ?? _shareWithSystemSheet)(
        LogService.instance.exportLogs(), origin);
  }

  void _copy() {
    final l = AppLocalizations.of(context);
    Clipboard.setData(ClipboardData(text: LogService.instance.exportLogs()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.logViewerLogsCopied),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _confirmClear() async {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l.logViewerClearLogs),
        content: Text(l.logViewerClearConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: palette.destructive),
            child: Text(l.logViewerClear),
          ),
        ],
      ),
    );
    if (confirmed == true) LogService.instance.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = SureColors.of(context);
    final palette = colors.palette;
    final logService = context.watch<LogService>();
    final logs = _selectedLevel == 'ALL'
        ? logService.logs
        : logService.logs.where((log) => log.level == _selectedLevel).toList();

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    final levels = {
      'ALL': l.logViewerFilterAll,
      'ERROR': l.logViewerFilterError,
      'WARNING': l.logViewerFilterWarning,
      'INFO': l.logViewerFilterInfo,
      'DEBUG': l.logViewerFilterDebug,
    };

    return SureLargeTitleScaffold(
      title: l.logViewerTitle,
      // The log viewer opens from Settings.
      leading: Navigator.of(context).canPop()
          ? SureBackButton(label: l.shellSettingsTitle)
          : null,
      controller: _scrollController,
      actions: [
        Builder(
          builder: (buttonContext) => SureNavIconButton(
            icon: 'share',
            semanticLabel: l.ds4tLogShare,
            onPressed: () => _share(buttonContext),
          ),
        ),
        SureNavIconButton(
          icon: 'copy',
          semanticLabel: l.logViewerCopyLogs,
          onPressed: _copy,
        ),
        SureNavIconButton(
          icon: SureIcons.trash,
          semanticLabel: l.logViewerClearLogs,
          color: palette.destructive,
          onPressed: _confirmClear,
        ),
      ],
      slivers: [
        SliverToBoxAdapter(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Row(
              children: [
                for (final entry in levels.entries) ...[
                  SureChip(
                    key: ValueKey('logLevel-${entry.key}'),
                    label: entry.value,
                    selected: _selectedLevel == entry.key,
                    onSelected: (_) =>
                        setState(() => _selectedLevel = entry.key),
                  ),
                  const SizedBox(width: 8),
                ],
                Tooltip(
                  message: _autoScroll
                      ? l.logViewerAutoScrollDisable
                      : l.logViewerAutoScrollEnable,
                  child: SureChip(
                    key: const ValueKey('logAutoScroll'),
                    label: l.ds4tLogAutoScroll,
                    leading: SureIcon(
                      SureIcons.arrowDown,
                      size: 14,
                      color: _autoScroll
                          ? palette.textInverse
                          : palette.textSecondary,
                    ),
                    selected: _autoScroll,
                    onSelected: (_) =>
                        setState(() => _autoScroll = !_autoScroll),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (logs.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: SureEmptyState(
                icon: SureIcons.inbox,
                title: l.logViewerEmpty,
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: DecoratedSliver(
              decoration: BoxDecoration(
                color: palette.container,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colors.hairline),
              ),
              sliver: SliverList.separated(
                itemCount: logs.length,
                separatorBuilder: (_, __) => const SureHairline(indent: 30),
                itemBuilder: (context, index) => _LogRow(entry: logs[index]),
              ),
            ),
          ),
      ],
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    return Semantics(
      label: entry.level,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Container(
                key: const ValueKey('logLevelDot'),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: LogViewerScreen.levelColor(palette, entry.level),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '[${entry.tag}] ${entry.message}',
                    style: TextStyle(
                      fontFamily: 'Geist Mono',
                      fontSize: 12,
                      height: 1.35,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.formattedTime,
                    style: TextStyle(
                      fontFamily: 'Geist Mono',
                      fontSize: 10,
                      color: palette.textSubdued,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
