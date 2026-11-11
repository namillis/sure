import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/transaction_tag.dart';
import '../providers/auth_provider.dart';
import '../providers/tags_provider.dart';
import '../services/metadata_create_service.dart';
import '../services/metadata_manage_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_spacing.dart';
import '../widgets/form_error_text.dart';
import '../widgets/manage_widgets.dart';
import '../widgets/sure_button.dart';
import '../widgets/sure_list_group.dart';
import '../widgets/sure_text_field.dart';

/// Lists, creates, renames, recolors and deletes the family's tags.
class TagsScreen extends StatefulWidget {
  const TagsScreen({
    super.key,
    this.service,
    this.createService,
    this.accessTokenLoader,
    this.onUnauthorized,
  });

  final MetadataManageService? service;
  final MetadataCreateService? createService;

  /// Defaults to [AuthProvider.getValidAccessToken].
  final Future<String?> Function()? accessTokenLoader;

  /// Defaults to [AuthProvider.logout].
  final Future<void> Function()? onUnauthorized;

  @override
  State<TagsScreen> createState() => _TagsScreenState();
}

/// What the tag form sheet ended with.
enum _TagOutcome { created, saved, deleted }

class _TagsScreenState extends State<TagsScreen> {
  late final MetadataManageService _service;
  late final MetadataCreateService _createService;
  final _search = TextEditingController();
  List<TransactionTag>? _tags;
  bool _loading = true;
  bool _failed = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? MetadataManageService();
    _createService = widget.createService ?? MetadataCreateService();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    if (widget.service == null) _service.close();
    _search.dispose();
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
    final result = await _service.listTags(accessToken: token);
    if (!mounted) return;
    if (result['error'] == 'unauthorized') return _unauthorized();
    if (result['success'] != true && _tags != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context).manageTagsLoadFailed)));
    }
    setState(() {
      _loading = false;
      _failed = result['success'] != true;
      if (!_failed) _tags = result['tags'] as List<TransactionTag>;
    });
  }

  Future<void> _refreshProvider(String token) async {
    try {
      await context
          .read<TagsProvider>()
          .fetchTags(accessToken: token, forceRefresh: true);
    } on ProviderNotFoundException {
      // Not mounted under the app's providers (tests).
    }
  }

  /// Runs [call] with a token; returns an error message, or null on success.
  Future<String?> _run(
    Future<Map<String, dynamic>> Function(String token) call,
  ) async {
    final l = AppLocalizations.of(context);
    final token = await _token();
    if (token == null) {
      await _unauthorized();
      return l.manageActionFailed;
    }
    final result = await call(token);
    if (result['error'] == 'unauthorized') {
      await _unauthorized();
      return l.manageActionFailed;
    }
    if (result['success'] != true) {
      return result['error']?.toString() ?? l.manageActionFailed;
    }
    await _refreshProvider(token);
    return null;
  }

  Future<void> _openForm([TransactionTag? existing]) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    String? createdName;
    final outcome = await showManageSheet<_TagOutcome>(
      context,
      (sheetContext) {
        void close(_TagOutcome outcome) {
          if (sheetContext.mounted) Navigator.of(sheetContext).pop(outcome);
        }

        return TagForm(
          existing: existing,
          onSubmit: (name, color) async {
            final error = await _run((token) => existing == null
                ? _createService.createTag(
                    accessToken: token, name: name, color: color)
                : _service.updateTag(
                    accessToken: token,
                    id: existing.id,
                    name: name,
                    color: color));
            if (error == null) {
              createdName = name;
              close(existing == null ? _TagOutcome.created : _TagOutcome.saved);
            }
            return error;
          },
          onDelete: existing == null
              ? null
              : () async {
                  final error = await _run((token) =>
                      _service.deleteTag(accessToken: token, id: existing.id));
                  if (error == null) close(_TagOutcome.deleted);
                  return error;
                },
        );
      },
    );
    if (outcome == null || !mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(switch (outcome) {
        _TagOutcome.created => l.manageTagCreated(createdName ?? ''),
        _TagOutcome.saved => l.manageTagSaved,
        _TagOutcome.deleted => l.manageTagDeleted,
      }),
    ));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tags = _tags;

    final Widget content;
    if (tags == null && _loading) {
      content = const Padding(
        padding: EdgeInsets.only(top: 96),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (tags == null || (_failed && tags.isEmpty)) {
      content = ManageMessage(
        icon: Icons.error_outline,
        title: l.manageTagsLoadFailed,
        onRetry: _load,
      );
    } else if (tags.isEmpty) {
      content = ManageMessage(
        icon: Icons.sell_outlined,
        title: l.manageTagsEmpty,
        body: l.manageTagsEmptyBody,
      );
    } else {
      final q = _query.trim().toLowerCase();
      final visible = q.isEmpty
          ? tags
          : tags.where((t) => t.name.toLowerCase().contains(q)).toList();
      content = visible.isEmpty
          ? ManageMessage(
              icon: Icons.search_off, title: l.manageNoMatches(_query.trim()))
          : SureListGroup(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              children: [
                for (final tag in visible)
                  SureListRow(
                    title: tag.name,
                    leading: ManageColorDot(hex: tag.color, size: 14),
                    showChevron: true,
                    onTap: () => _openForm(tag),
                  ),
              ],
            );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l.manageTagsTitle),
        actions: [
          IconButton(
            tooltip: l.manageTagAdd,
            icon: const Icon(Icons.add),
            onPressed: tags == null ? null : () => _openForm(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: SureSpacing.huge),
          children: [
            if (tags != null && tags.isNotEmpty)
              ManageSearchField(
                controller: _search,
                onChanged: (value) => setState(() => _query = value),
              ),
            content,
          ],
        ),
      ),
    );
  }
}

/// Asks before deleting [tag]; true when the user confirmed.
Future<bool> confirmTagDelete(BuildContext context, TransactionTag tag) async {
  final l = AppLocalizations.of(context);
  final palette = SureColors.of(context).palette;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l.manageTagDeleteTitle(tag.name)),
      content: Text(l.manageTagDeleteBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: TextButton.styleFrom(foregroundColor: palette.destructive),
          child: Text(l.commonDelete),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// The create/edit tag form. [onSubmit] and [onDelete] return an error
/// message to show, or null when they succeeded. [onDelete] runs only after
/// the user confirms.
class TagForm extends StatefulWidget {
  const TagForm({
    super.key,
    this.existing,
    required this.onSubmit,
    this.onDelete,
  });

  final TransactionTag? existing;
  final Future<String?> Function(String name, String color) onSubmit;
  final Future<String?> Function()? onDelete;

  @override
  State<TagForm> createState() => _TagFormState();
}

class _TagFormState extends State<TagForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late String _color;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    final existingColor = widget.existing?.color;
    _color = existingColor != null && existingColor.isNotEmpty
        ? existingColor
        : kMetadataColors.first;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _guard(Future<String?> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await action();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.existing == null ? l.manageTagNew : l.manageTagEdit,
              style: theme.textTheme.titleLarge),
          const SizedBox(height: SureSpacing.xl),
          SureTextField(
            controller: _name,
            label: l.manageNameLabel,
            autofocus: widget.existing == null,
            validator: (value) => (value ?? '').trim().isEmpty
                ? l.manageNameRequired
                : null,
          ),
          const SizedBox(height: SureSpacing.xl),
          ManageColorPicker(
            value: _color,
            onChanged: (value) =>
                setState(() => _color = value ?? kMetadataColors.first),
          ),
          if (_error != null) ...[
            const SizedBox(height: SureSpacing.lg),
            FormErrorText(_error!),
          ],
          const SizedBox(height: SureSpacing.xl),
          SureButton(
            label: l.commonSave,
            fullWidth: true,
            loading: _busy,
            onPressed: _busy
                ? null
                : () {
                    if (!_formKey.currentState!.validate()) return;
                    _guard(() => widget.onSubmit(_name.text.trim(), _color));
                  },
          ),
          if (widget.onDelete != null) ...[
            const SizedBox(height: SureSpacing.md),
            SureButton(
              label: l.manageTagDelete,
              variant: SureButtonVariant.destructive,
              fullWidth: true,
              onPressed: _busy
                  ? null
                  : () async {
                      final existing = widget.existing;
                      if (existing != null &&
                          !await confirmTagDelete(context, existing)) {
                        return;
                      }
                      if (mounted) _guard(widget.onDelete!);
                    },
            ),
          ],
        ],
      ),
    );
  }
}
