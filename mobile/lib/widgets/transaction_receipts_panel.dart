import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_localizations.dart';
import '../models/transaction.dart';
import '../models/transaction_attachment.dart';
import '../providers/auth_provider.dart';
import '../services/file_pick.dart';
import '../services/transaction_attachments_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_tokens.dart';
import 'ds/ds.dart';

/// Where a new receipt comes from.
enum ReceiptSource { camera, photos, file }

/// Picks a receipt from [source]; null when the user cancels.
typedef ReceiptPickFn = Future<PickedFileData?> Function(ReceiptSource source);

/// Hands a downloaded file to the system so it can be opened or saved.
typedef ReceiptFileOpener = Future<void> Function(
    File file, String contentType, Rect? origin);

/// The server's limits (the web's rules).
const int maxReceiptBytes = 10 * 1024 * 1024;
const int maxReceiptsPerTransaction = 10;

// Lucide assets bundled for this panel.
const String _iconImage = 'image';
const String _iconFile = 'file-text';
const String _iconCamera = 'camera';
const String _iconFolder = 'folder-open';

/// Camera and photo library through `image_picker`, files through
/// `file_picker`. A JPEG quality and size cap make image_picker re-encode
/// every photo, so an iPhone's HEIC comes back as JPEG.
Future<PickedFileData?> pickReceipt(ReceiptSource source) async {
  if (source == ReceiptSource.file) {
    return pickFileWithExtensions(
        const ['jpg', 'jpeg', 'png', 'gif', 'webp', 'pdf']);
  }
  final image = await ImagePicker().pickImage(
    source:
        source == ReceiptSource.camera ? ImageSource.camera : ImageSource.gallery,
    imageQuality: 85,
    maxWidth: 3000,
    maxHeight: 3000,
    requestFullMetadata: false,
  );
  if (image == null) return null;
  return PickedFileData(
    name: image.name,
    size: await image.length(),
    read: image.readAsBytes,
  );
}

Future<void> _openWithSystemSheet(
    File file, String contentType, Rect? origin) async {
  await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path, mimeType: contentType)],
    sharePositionOrigin: origin,
  ));
}

/// The Receipts row of the transaction screen (Sure+
/// `transactions.attachments`): thumbnails of the attached images, a file
/// icon for PDFs, and a "+" tile that takes or picks a new one.
///
/// Tapping an image opens a full-screen viewer; tapping a PDF downloads it
/// and hands it to the share sheet. Long-press (or Delete in the viewer)
/// deletes, when [canDelete].
class TransactionReceiptsPanel extends StatefulWidget {
  const TransactionReceiptsPanel({
    super.key,
    required this.transaction,
    required this.online,
    required this.canDelete,
    this.service,
    this.pick,
    this.openFile,
  });

  final Transaction transaction;
  final bool online;

  /// Owner or full control. A `read_write` share can add but not delete.
  final bool canDelete;

  /// Overrides for tests.
  final TransactionAttachmentsService? service;
  final ReceiptPickFn? pick;
  final ReceiptFileOpener? openFile;

  @override
  State<TransactionReceiptsPanel> createState() =>
      _TransactionReceiptsPanelState();
}

class _TransactionReceiptsPanelState extends State<TransactionReceiptsPanel> {
  static const double _tile = 64;

  late final TransactionAttachmentsService _service =
      widget.service ?? TransactionAttachmentsService();
  late List<TransactionAttachment> _items;
  final Map<String, Uint8List> _bytes = {};
  final Set<String> _loading = {};
  final Set<String> _failed = {};
  bool _uploading = false;

  String get _transactionId => widget.transaction.id ?? '';

  @override
  void initState() {
    super.initState();
    _items = [...?widget.transaction.attachments];
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadThumbnails());
  }

  @override
  void didUpdateWidget(TransactionReceiptsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.transaction.attachments,
        oldWidget.transaction.attachments)) {
      _items = [...?widget.transaction.attachments];
      _loadThumbnails();
    }
  }

  @override
  void dispose() {
    if (widget.service == null) _service.close();
    super.dispose();
  }

  Future<String?> _token() async {
    final auth = context.read<AuthProvider>();
    final token = await auth.getValidAccessToken();
    if (token == null && mounted) await auth.logout();
    return token;
  }

  void _show(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Reports a failed call; true when it was handled as a sign-out.
  Future<bool> _failure(Map<String, dynamic> result) async {
    if (result['error'] == 'unauthorized') {
      await context.read<AuthProvider>().logout();
      return true;
    }
    if (mounted) {
      _show(result['error']?.toString() ??
          AppLocalizations.of(context).s4rLoadFailed);
    }
    return false;
  }

  Future<void> _loadThumbnails() async {
    if (!mounted || !widget.online) return;
    final images = _items
        .where((a) =>
            a.isImage && !_bytes.containsKey(a.id) && !_loading.contains(a.id))
        .toList();
    if (images.isEmpty) return;
    final token = await _token();
    if (token == null || !mounted) return;
    setState(() {
      for (final a in images) {
        _loading.add(a.id);
        _failed.remove(a.id);
      }
    });
    await Future.wait(images.map((a) async {
      final result =
          await _service.download(accessToken: token, attachment: a);
      if (!mounted) return;
      setState(() {
        _loading.remove(a.id);
        if (result['success'] == true) {
          _bytes[a.id] = result['bytes'] as Uint8List;
        } else {
          _failed.add(a.id);
        }
      });
    }));
  }

  /// The file's bytes, downloaded once.
  Future<Uint8List?> _fileBytes(TransactionAttachment attachment) async {
    final cached = _bytes[attachment.id];
    if (cached != null) return cached;
    final token = await _token();
    if (token == null || !mounted) return null;
    final result =
        await _service.download(accessToken: token, attachment: attachment);
    if (!mounted) return null;
    if (result['success'] != true) {
      await _failure({
        ...result,
        if (result['error'] != 'unauthorized')
          'error': AppLocalizations.of(context).s4rLoadFailed,
      });
      return null;
    }
    final bytes = result['bytes'] as Uint8List;
    if (attachment.isImage) setState(() => _bytes[attachment.id] = bytes);
    return bytes;
  }

  Future<void> _open(
      TransactionAttachment attachment, BuildContext tileContext) async {
    final box = tileContext.findRenderObject() as RenderBox?;
    final origin = box == null || !box.hasSize
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    final bytes = await _fileBytes(attachment);
    if (bytes == null || !mounted) return;

    if (attachment.isImage) {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ReceiptViewerScreen(
          filename: attachment.filename,
          bytes: bytes,
          onDelete: widget.canDelete
              ? (viewerContext) => _confirmAndDelete(viewerContext, attachment)
              : null,
        ),
      ));
      return;
    }

    Directory? dir;
    try {
      dir = await Directory.systemTemp.createTemp('sure_receipt_');
      final name = attachmentFilename(attachment.filename,
          attachment.isPdf ? 'application/pdf' : attachment.contentType);
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(bytes, flush: true);
      await (widget.openFile ?? _openWithSystemSheet)(
          file, attachment.contentType, origin);
    } catch (_) {
      if (mounted) _show(AppLocalizations.of(context).s4rLoadFailed);
    } finally {
      // The share sheet has copied or opened the file by the time it closes.
      try {
        await dir?.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Confirms in [dialogContext], then deletes. True when it was deleted.
  Future<bool> _confirmAndDelete(
      BuildContext dialogContext, TransactionAttachment attachment) async {
    final confirmed = await showDialog<bool>(
      context: dialogContext,
      builder: (context) {
        final l = AppLocalizations.of(context);
        final palette = SureColors.of(context).palette;
        return AlertDialog(
          title: Text(l.s4rDeleteTitle),
          content: Text(l.s4rDeleteContent(attachment.filename)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.commonCancel),
            ),
            TextButton(
              key: const ValueKey('receiptDeleteConfirm'),
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: palette.destructive),
              child: Text(l.commonDelete),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return false;
    final l = AppLocalizations.of(context);
    final token = await _token();
    if (token == null || !mounted) return false;
    final result = await _service.delete(
      accessToken: token,
      transactionId: _transactionId,
      attachmentId: attachment.id,
    );
    if (!mounted) return false;
    if (result['success'] != true) {
      await _failure(result);
      return false;
    }
    setState(() {
      _items = _items.where((a) => a.id != attachment.id).toList();
      _bytes.remove(attachment.id);
    });
    _show(l.s4rDeleted);
    return true;
  }

  Future<void> _add() async {
    final l = AppLocalizations.of(context);
    if (_items.length >= maxReceiptsPerTransaction) {
      _show(l.s4rTooMany);
      return;
    }
    final source = await showSureSheet<ReceiptSource>(
      context: context,
      builder: (context) => const _ReceiptSourceSheet(),
    );
    if (source == null || !mounted) return;

    PickedFileData? picked;
    try {
      picked = await (widget.pick ?? pickReceipt)(source);
    } catch (_) {
      if (mounted) _show(l.s4rPickFailed);
      return;
    }
    if (picked == null || !mounted) return;
    if (picked.size > maxReceiptBytes) {
      _show(l.s4rTooLarge);
      return;
    }

    setState(() => _uploading = true);
    try {
      final bytes = await picked.read();
      if (!mounted) return;
      if (bytes.length > maxReceiptBytes) {
        _show(l.s4rTooLarge);
        return;
      }
      final type = attachmentContentType(bytes);
      if (type == null) {
        _show(l.s4rWrongType);
        return;
      }
      final token = await _token();
      if (token == null || !mounted) return;
      final result = await _service.upload(
        accessToken: token,
        transactionId: _transactionId,
        bytes: bytes,
        filename: attachmentFilename(picked.name, type),
        contentType: type,
      );
      if (!mounted) return;
      if (result['success'] != true) {
        await _failure(result);
        return;
      }
      final attachment = result['attachment'] as TransactionAttachment;
      setState(() {
        _items = [..._items, attachment];
        if (attachment.isImage) _bytes[attachment.id] = bytes;
      });
      SureHaptics.success();
      _show(l.s4rAttached);
    } catch (_) {
      if (mounted) _show(l.s4rLoadFailed);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final canAdd = widget.online && !_uploading && _transactionId.isNotEmpty;

    return SurePanel(
      key: const ValueKey('transaction-receipts-panel'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.s4rReceipts,
            style: TextStyle(
              fontSize: 15,
              fontWeight: SureTokens.weightMedium,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final attachment in _items) _thumbnail(l, palette, attachment),
              _addTile(l, palette, canAdd),
            ],
          ),
        ],
      ),
    );
  }

  Widget _frame(SureTokenPalette palette, Widget child) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(SureTokens.radiusMd),
      child: Container(
        width: _tile,
        height: _tile,
        decoration: BoxDecoration(
          color: palette.surfaceInset,
          borderRadius: BorderRadius.circular(SureTokens.radiusMd),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }

  Widget _thumbnail(
    AppLocalizations l,
    SureTokenPalette palette,
    TransactionAttachment attachment,
  ) {
    final bytes = _bytes[attachment.id];
    final Widget content;
    if (attachment.isImage && bytes != null) {
      content = Image.memory(
        bytes,
        width: _tile,
        height: _tile,
        fit: BoxFit.cover,
        cacheWidth: (_tile * 3).round(),
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) =>
            SureIcon(_iconImage, size: 22, color: palette.textSubdued),
      );
    } else if (attachment.isImage && _loading.contains(attachment.id)) {
      content = const SizedBox.square(
        dimension: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else {
      content = SureIcon(
        attachment.isImage ? _iconImage : _iconFile,
        size: 24,
        color: palette.textSecondary,
      );
    }
    return Builder(
      builder: (tileContext) => Semantics(
        button: true,
        label: l.s4rOpenFile(attachment.filename),
        excludeSemantics: true,
        child: GestureDetector(
          key: ValueKey('receipt-${attachment.id}'),
          behavior: HitTestBehavior.opaque,
          onTap: widget.online ? () => _open(attachment, tileContext) : null,
          onLongPress: widget.canDelete && widget.online
              ? () => _confirmAndDelete(context, attachment)
              : null,
          child: _frame(palette, content),
        ),
      ),
    );
  }

  Widget _addTile(AppLocalizations l, SureTokenPalette palette, bool enabled) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: _uploading ? l.s4rUploading : l.s4rAddReceipt,
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('receipt-add'),
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? _add : null,
        child: Opacity(
          opacity: enabled || _uploading ? 1 : 0.5,
          child: _frame(
            palette,
            _uploading
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : SureIcon(SureIcons.plus, size: 22, color: palette.link),
          ),
        ),
      ),
    );
  }
}

/// "Take photo", "Choose photo", "Choose file". Pops with the choice.
class _ReceiptSourceSheet extends StatelessWidget {
  const _ReceiptSourceSheet();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    Widget row(ReceiptSource source, String icon, String label) => SureListRow(
          key: ValueKey('receipt-source-${source.name}'),
          leading: SureIcon(icon, size: 20, color: palette.textSecondary),
          title: label,
          onTap: () => Navigator.of(context).pop(source),
        );
    return SureSheet(
      title: l.s4rAddReceipt,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: SurePanel.rows(children: [
          row(ReceiptSource.camera, _iconCamera, l.s4rTakePhoto),
          row(ReceiptSource.photos, _iconImage, l.s4rChoosePhoto),
          row(ReceiptSource.file, _iconFolder, l.s4rChooseFile),
        ]),
      ),
    );
  }
}

/// A receipt image, full screen, pinch to zoom. Delete (with [onDelete]'s
/// confirm) closes the viewer once the file is gone.
class ReceiptViewerScreen extends StatelessWidget {
  const ReceiptViewerScreen({
    super.key,
    required this.filename,
    required this.bytes,
    this.onDelete,
  });

  final String filename;
  final Uint8List bytes;

  /// Confirms and deletes; true when deleted. Null hides Delete.
  final Future<bool> Function(BuildContext context)? onDelete;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final delete = onDelete;
    return Scaffold(
      backgroundColor: palette.surface,
      appBar: AppBar(
        title: Text(filename, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (delete != null)
            IconButton(
              key: const ValueKey('receiptViewerDelete'),
              tooltip: l.commonDelete,
              icon: SureIcon(SureIcons.trash, size: 20, color: palette.destructive),
              onPressed: () async {
                final navigator = Navigator.of(context);
                if (await delete(context)) navigator.pop();
              },
            ),
        ],
      ),
      body: SafeArea(
        child: InteractiveViewer(
          maxScale: 5,
          child: Center(
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  SureIcon(_iconImage, size: 32, color: palette.textSubdued),
            ),
          ),
        ),
      ),
    );
  }
}
