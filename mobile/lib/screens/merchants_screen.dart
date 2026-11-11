import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/merchant.dart';
import '../providers/auth_provider.dart';
import '../providers/merchants_provider.dart';
import '../services/metadata_create_service.dart';
import '../services/metadata_manage_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_spacing.dart';
import '../widgets/form_error_text.dart';
import '../widgets/manage_widgets.dart';
import '../widgets/open_on_web_action.dart';
import '../widgets/sure_button.dart';
import '../widgets/sure_list_group.dart';
import '../widgets/sure_text_field.dart';

/// Lists the merchants the user can see and creates family merchants. The
/// API has no merchant edit or delete, so a row opens an info sheet that
/// links to the web.
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

  void _showInfo(Merchant merchant) {
    final l = AppLocalizations.of(context);
    final family = merchant.type == 'FamilyMerchant';
    showManageSheet<void>(
      context,
      (sheetContext) => ManageInfoSheet(
        leading: _MerchantBadge(merchant: merchant, size: 40),
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
      content = const Padding(
        padding: EdgeInsets.only(top: 96),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (merchants == null || (_failed && merchants.isEmpty)) {
      content = ManageMessage(
        icon: Icons.error_outline,
        title: l.manageMerchantsLoadFailed,
        onRetry: _load,
      );
    } else if (merchants.isEmpty) {
      content = ManageMessage(
        icon: Icons.storefront_outlined,
        title: l.manageMerchantsEmpty,
        body: l.manageMerchantsEmptyBody,
      );
    } else {
      final q = _query.trim().toLowerCase();
      final visible = q.isEmpty
          ? merchants
          : merchants.where((m) => m.name.toLowerCase().contains(q)).toList();
      content = visible.isEmpty
          ? ManageMessage(
              icon: Icons.search_off, title: l.manageNoMatches(_query.trim()))
          : SureListGroup(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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

    return Scaffold(
      appBar: AppBar(
        title: Text(l.manageMerchantsTitle),
        actions: [
          IconButton(
            tooltip: l.manageMerchantAdd,
            icon: const Icon(Icons.add),
            onPressed: merchants == null ? null : _create,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: SureSpacing.huge),
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
    );
  }
}

/// The API sends no merchant color, so the badge is a neutral circle with
/// the first letter.
class _MerchantBadge extends StatelessWidget {
  const _MerchantBadge({required this.merchant, this.size = 28});

  final Merchant merchant;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = SureColors.of(context).palette;
    final letter = merchant.name.isEmpty
        ? '?'
        : merchant.name.characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration:
          BoxDecoration(color: palette.surfaceInset, shape: BoxShape.circle),
      child: Text(
        letter,
        style: TextStyle(
          color: palette.textSecondary,
          fontSize: size * 0.45,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
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

/// The create merchant form: name, optional color and website. [onSubmit]
/// returns an error message to show, or null on success.
class MerchantForm extends StatefulWidget {
  const MerchantForm({super.key, required this.onSubmit});

  final Future<String?> Function(String name, String? color, String? website)
      onSubmit;

  @override
  State<MerchantForm> createState() => _MerchantFormState();
}

class _MerchantFormState extends State<MerchantForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _website = TextEditingController();
  String? _color;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _website.dispose();
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
          Text(l.manageMerchantNew, style: theme.textTheme.titleLarge),
          const SizedBox(height: SureSpacing.xl),
          SureTextField(
            controller: _name,
            label: l.manageNameLabel,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            validator: (value) => (value ?? '').trim().isEmpty
                ? l.manageNameRequired
                : null,
          ),
          const SizedBox(height: SureSpacing.xl),
          SureTextField(
            controller: _website,
            label: l.manageMerchantWebsite,
            hint: 'example.com',
            keyboardType: TextInputType.url,
            validator: (value) {
              final text = (value ?? '').trim();
              if (text.isEmpty || isPlausibleWebsite(text)) return null;
              return l.manageMerchantWebsiteInvalid;
            },
          ),
          const SizedBox(height: SureSpacing.xl),
          ManageColorPicker(
            value: _color,
            allowAutomatic: true,
            onChanged: (value) => setState(() => _color = value),
          ),
          if (_error != null) ...[
            const SizedBox(height: SureSpacing.lg),
            FormErrorText(_error!),
          ],
          const SizedBox(height: SureSpacing.xl),
          SureButton(
            label: l.commonSave,
            fullWidth: true,
            loading: _saving,
            onPressed: _saving ? null : _submit,
          ),
        ],
      ),
    );
  }
}
