import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/merchant.dart';
import '../providers/auth_provider.dart';
import '../providers/merchants_provider.dart';
import '../providers/server_features_provider.dart';
import '../services/metadata_create_service.dart';
import '../services/metadata_manage_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_spacing.dart';
import '../widgets/ds/ds.dart';
import '../widgets/manage_widgets.dart';
import '../widgets/open_on_web_action.dart';
import 'form_sheet_fields.dart';

/// Lists the merchants the user can see and creates family merchants. On a
/// Sure+ server with `merchants.write` a family merchant opens the edit sheet
/// (with delete); provider merchants, and every merchant on other servers,
/// open a read-only info sheet.
class MerchantsScreen extends StatefulWidget {
  const MerchantsScreen({
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
  State<MerchantsScreen> createState() => _MerchantsScreenState();
}

/// What the edit merchant sheet ended with.
enum _EditOutcome { saved, deleted }

class _MerchantsScreenState extends State<MerchantsScreen> {
  late final MetadataManageService _service;
  late final MetadataCreateService _createService;
  final _search = TextEditingController();
  List<Merchant>? _merchants;
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
    final result = await _service.listMerchants(accessToken: token);
    if (!mounted) return;
    if (result['error'] == 'unauthorized') return _unauthorized();
    if (result['success'] != true && _merchants != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(AppLocalizations.of(context).manageMerchantsLoadFailed)));
    }
    setState(() {
      _loading = false;
      _failed = result['success'] != true;
      if (!_failed) _merchants = result['merchants'] as List<Merchant>;
    });
  }

  Future<void> _refreshProvider(String token) async {
    try {
      await context
          .read<MerchantsProvider>()
          .fetchMerchants(accessToken: token, forceRefresh: true);
    } on ProviderNotFoundException {
      // Not mounted under the app's providers (tests).
    }
  }

  Future<void> _create() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final result = await showManageSheet<Map<String, dynamic>>(
      context,
      (sheetContext) => MerchantForm(
        onSubmit: (name, color, website) async {
          final token = await _token();
          if (token == null) {
            await _unauthorized();
            return l.manageActionFailed;
          }
          final result = await _createService.createMerchant(
            accessToken: token,
            name: name,
            color: color,
            websiteUrl: website,
          );
          if (result['error'] == 'unauthorized') {
            await _unauthorized();
            return l.manageActionFailed;
          }
          if (result['success'] != true) {
            return result['error']?.toString() ?? l.manageActionFailed;
          }
          if (sheetContext.mounted) Navigator.of(sheetContext).pop(result);
          await _refreshProvider(token);
          return null;
        },
      ),
    );
    if (result == null || !mounted) return;
    final name = (result['merchant'] as Merchant).name;
    messenger.showSnackBar(SnackBar(
      content: Text(result['existing'] == true
          ? l.manageMerchantExists(name)
          : l.manageMerchantCreated(name)),
    ));
    await _load();
  }

  /// Runs a write with a token; returns an error message, or null on
  /// success (after refreshing [MerchantsProvider]).
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
    if (result['code'] == 'insufficient_scope') return l.spmReadOnlyAccess;
    if (result['success'] != true) {
      return result['error']?.toString() ?? l.manageActionFailed;
    }
    await _refreshProvider(token);
    return null;
  }

  /// The Sure+ edit sheet (`merchants.write`) for a family merchant.
  Future<void> _openEdit(Merchant merchant) async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final outcome = await showManageSheet<_EditOutcome>(
      context,
      (sheetContext) {
        void close(_EditOutcome outcome) {
          if (sheetContext.mounted) Navigator.of(sheetContext).pop(outcome);
        }

        return MerchantForm(
          existing: merchant,
          onSubmit: (name, color, website) async {
            final error = await _run((token) => _service.updateMerchant(
                  accessToken: token,
                  id: merchant.id,
                  name: name,
                  color: color,
                  // "" clears the website.
                  websiteUrl: website ?? '',
                ));
            if (error == null) close(_EditOutcome.saved);
            return error;
          },
          onDelete: () async {
            final error = await _run((token) =>
                _service.deleteMerchant(accessToken: token, id: merchant.id));
            if (error == null) close(_EditOutcome.deleted);
            return error;
          },
        );
      },
    );
    if (outcome == null || !mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(outcome == _EditOutcome.saved
          ? l.spmMerchantSaved
          : l.spmMerchantDeleted),
    ));
    await _load();
  }

  /// True when the server can edit and delete family merchants. Off when the
  /// app's providers aren't mounted (tests).
  bool get _canEdit {
    try {
      return context
          .read<ServerFeaturesProvider>()
          .has(ServerFeaturesProvider.merchantsWrite);
    } on ProviderNotFoundException {
      return false;
    }
  }

  void _showInfo(Merchant merchant) {
    final l = AppLocalizations.of(context);
    final family = merchant.type == 'FamilyMerchant';
    if (family && _canEdit) {
      _openEdit(merchant);
      return;
    }
    showManageSheet<void>(
      context,
      (sheetContext) => ManageInfoSheet(
        leading: _MerchantBadge(
            merchant: merchant, size: SureCategoryIcon.heroSize),
        title: merchant.name,
        lines: [
          family ? l.manageMerchantFamily : l.manageMerchantProvider,
          l.manageMerchantInfoBody,
        ],
        onEditOnWeb: () {
          Navigator.of(sheetContext).pop();
          openWebFallback(
            context,
            title: merchant.name,
            // Provider merchants have no edit page of their own.
            path: family
                ? '/family_merchants/${Uri.encodeComponent(merchant.id)}/edit'
                : '/family_merchants',
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final merchants = _merchants;

    final Widget content;
    if (merchants == null && _loading) {
      content = const ManageLoading();
    } else if (merchants == null || (_failed && merchants.isEmpty)) {
      content = SureEmptyState(
        key: const ValueKey('merchantsError'),
        icon: SureIcons.circleAlert,
        title: l.manageMerchantsLoadFailed,
        primaryLabel: l.commonTryAgain,
        onPrimary: _load,
      );
    } else if (merchants.isEmpty) {
      content = SureEmptyState(
        key: const ValueKey('merchantsEmpty'),
        icon: SureIcons.store,
        title: l.manageMerchantsEmpty,
        body: l.manageMerchantsEmptyBody,
        primaryLabel: l.manageMerchantAdd,
        onPrimary: _create,
      );
    } else {
      final q = _query.trim().toLowerCase();
      final visible = q.isEmpty
          ? merchants
          : merchants.where((m) => m.name.toLowerCase().contains(q)).toList();
      content = visible.isEmpty
          ? SureEmptyState(
              icon: SureIcons.search,
              title: l.manageNoMatches(_query.trim()),
              secondaryLabel: l.manageClearSearch,
              onSecondary: () {
                _search.clear();
                setState(() => _query = '');
              },
            )
          : SurePanel.rows(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              dividerIndent: SurePanel.iconRowDividerIndent,
              children: [
                for (final merchant in visible)
                  SureListRow(
                    title: merchant.name,
                    subtitle: merchant.type == 'FamilyMerchant'
                        ? null
                        : l.manageMerchantProvider,
                    leading: _MerchantBadge(merchant: merchant),
                    showChevron: true,
                    onTap: () => _showInfo(merchant),
                  ),
              ],
            );
    }

    return SureLargeTitleScaffold(
      title: l.manageMerchantsTitle,
      leading: manageBackLink(context),
      actions: [
        SureNavIconButton(
          icon: SureIcons.plus,
          semanticLabel: l.manageMerchantAdd,
          onPressed: merchants == null ? null : _create,
        ),
      ],
      onRefresh: _load,
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (merchants != null && merchants.isNotEmpty)
                ManageSearchField(
                  controller: _search,
                  onChanged: (value) => setState(() => _query = value),
                ),
              content,
            ],
          ),
        ),
      ],
    );
  }
}

/// The API sends no merchant color, so the badge is a neutral circle with
/// the first letter.
class _MerchantBadge extends StatelessWidget {
  const _MerchantBadge(
      {required this.merchant, this.size = SureCategoryIcon.rowSize});

  final Merchant merchant;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    final letter = merchant.name.isEmpty
        ? '?'
        : merchant.name.characters.first.toUpperCase();
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration:
            BoxDecoration(color: palette.surfaceInset, shape: BoxShape.circle),
        child: Text(
          letter,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            color: palette.textSecondary,
            fontSize: (size * 0.46).roundToDouble(),
            height: 1,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Asks before deleting [merchant]; true when the user confirmed.
Future<bool> confirmMerchantDelete(
    BuildContext context, Merchant merchant) async {
  final l = AppLocalizations.of(context);
  final palette = SureColors.of(context).palette;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l.spmMerchantDeleteTitle(merchant.name)),
      content: Text(l.spmMerchantDeleteBody),
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

/// True for a plausible website: a host with a dot and no spaces, with or
/// without an http(s) scheme.
bool isPlausibleWebsite(String value) {
  final text = value.trim();
  if (text.isEmpty || text.contains(RegExp(r'\s'))) return false;
  final uri = Uri.tryParse(
      text.startsWith(RegExp(r'https?://', caseSensitive: false))
          ? text
          : 'https://$text');
  if (uri == null) return false;
  final host = uri.host;
  return host.contains('.') && !host.startsWith('.') && !host.endsWith('.');
}

/// The create/edit merchant form: name, optional color and website.
/// [onSubmit] and [onDelete] return an error message to show, or null on
/// success. [onDelete] runs only after the user confirms.
class MerchantForm extends StatefulWidget {
  const MerchantForm({
    super.key,
    required this.onSubmit,
    this.existing,
    this.onDelete,
  });

  final Future<String?> Function(String name, String? color, String? website)
      onSubmit;

  /// The family merchant being edited (Sure+ `merchants.write`); null
  /// creates one.
  final Merchant? existing;
  final Future<String?> Function()? onDelete;

  @override
  State<MerchantForm> createState() => _MerchantFormState();
}

class _MerchantFormState extends State<MerchantForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _website;
  final _nameFocus = FocusNode();
  String? _color;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _website = TextEditingController(text: existing?.websiteUrl ?? '');
    final color = existing?.color;
    _color = color != null && color.isNotEmpty ? color : null;
    if (existing == null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _nameFocus.requestFocus());
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _website.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final website = _website.text.trim();
    final error = await widget.onSubmit(
        _name.text.trim(), _color, website.isEmpty ? null : website);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = error;
    });
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    final onDelete = widget.onDelete;
    if (existing == null || onDelete == null) return;
    if (!await confirmMerchantDelete(context, existing) || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await onDelete();
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final editing = widget.existing != null;
    return SureSheet(
      title: editing ? l.spmMerchantEdit : l.manageMerchantNew,
      actionLabel: l.commonSave,
      actionKey: const ValueKey('merchantFormSave'),
      busy: _saving,
      onAction: _submit,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SurePanel.rows(
                children: [
                  FormSheetFieldRow(
                    label: l.manageNameLabel,
                    controller: _name,
                    focusNode: _nameFocus,
                    textCapitalization: TextCapitalization.words,
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? l.manageNameRequired
                        : null,
                  ),
                  FormSheetFieldRow(
                    label: l.manageMerchantWebsite,
                    controller: _website,
                    hint: 'example.com',
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.done,
                    validator: (value) {
                      final text = (value ?? '').trim();
                      if (text.isEmpty || isPlausibleWebsite(text)) return null;
                      return l.manageMerchantWebsiteInvalid;
                    },
                  ),
                ],
              ),
              ManageColorPicker(
                value: _color,
                // An existing merchant always has a color; null would send
                // no change.
                allowAutomatic: !editing,
                onChanged: (value) => setState(() => _color = value),
              ),
              if (_error != null) ...[
                const SizedBox(height: SureSpacing.lg),
                ManageErrorText(_error!),
              ],
              if (editing && widget.onDelete != null)
                SureButtonPanel(
                  key: const ValueKey('merchantFormDelete'),
                  label: l.spmMerchantDelete,
                  destructive: true,
                  margin: const EdgeInsets.only(top: SureSpacing.xxxl),
                  onPressed: _saving ? null : _delete,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
