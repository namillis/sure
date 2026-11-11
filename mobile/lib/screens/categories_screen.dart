import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/category.dart';
import '../providers/auth_provider.dart';
import '../providers/categories_provider.dart';
import '../services/metadata_create_service.dart';
import '../services/metadata_manage_service.dart';
import '../theme/sure_colors.dart';
import '../theme/sure_spacing.dart';
import '../widgets/form_error_text.dart';
import '../widgets/manage_widgets.dart';
import '../widgets/open_on_web_action.dart';
import '../widgets/sure_button.dart';
import '../widgets/sure_icon.dart';
import '../widgets/sure_list_group.dart';
import '../widgets/sure_text_field.dart';

/// Lists the family's categories with their subcategories, and creates new
/// ones. The API can't edit or delete categories, so a row opens an info
/// sheet that links to the web.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({
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
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  late final MetadataManageService _service;
  late final MetadataCreateService _createService;
  final _search = TextEditingController();
  List<Category>? _categories;
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
    final result = await _service.listCategories(accessToken: token);
    if (!mounted) return;
    if (result['error'] == 'unauthorized') return _unauthorized();
    if (result['success'] != true && _categories != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(AppLocalizations.of(context).manageCategoriesLoadFailed)));
    }
    setState(() {
      _loading = false;
      _failed = result['success'] != true;
      if (!_failed) _categories = result['categories'] as List<Category>;
    });
  }

  /// Lets the rest of the app (pickers, filters) see the new category.
  Future<void> _refreshProvider(String token) async {
    try {
      final provider = context.read<CategoriesProvider>();
      provider.clear();
      await provider.fetchCategories(accessToken: token);
    } on ProviderNotFoundException {
      // Not mounted under the app's providers (tests).
    }
  }

  Future<void> _create() async {
    final l = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final parents = (_categories ?? const <Category>[])
        .where((c) => c.parent == null)
        .toList();
    final created = await showManageSheet<Category>(
      context,
      (sheetContext) => CategoryForm(
        parents: parents,
        onSubmit: (name, color, parentId) async {
          final token = await _token();
          if (token == null) {
            await _unauthorized();
            return l.manageActionFailed;
          }
          final result = await _createService.createCategory(
            accessToken: token,
            name: name,
            color: color,
            parentId: parentId,
          );
          if (result['error'] == 'unauthorized') {
            await _unauthorized();
            return l.manageActionFailed;
          }
          if (result['success'] != true) {
            return result['error']?.toString() ?? l.manageActionFailed;
          }
          if (sheetContext.mounted) {
            Navigator.of(sheetContext).pop(result['category'] as Category);
          }
          await _refreshProvider(token);
          return null;
        },
      ),
    );
    if (created == null || !mounted) return;
    messenger.showSnackBar(
        SnackBar(content: Text(l.manageCategoryCreated(created.name))));
    await _load();
  }

  void _showInfo(Category category) {
    final l = AppLocalizations.of(context);
    final children = (_categories ?? const <Category>[])
        .where((c) => c.parent?.id == category.id)
        .length;
    showManageSheet<void>(
      context,
      (sheetContext) => ManageInfoSheet(
        leading: _CategoryBadge(category: category, size: 40),
        title: category.name,
        lines: [
          if (category.parent != null)
            l.manageCategoryInParent(category.parent!.name)
          else
            l.manageCategorySubcategories(children),
          l.manageCategoryInfoBody,
        ],
        onEditOnWeb: () {
          Navigator.of(sheetContext).pop();
          openWebFallback(
            context,
            title: category.name,
            path: '/categories/${Uri.encodeComponent(category.id)}/edit',
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final categories = _categories;

    final Widget content;
    if (categories == null && _loading) {
      content = const Padding(
        padding: EdgeInsets.only(top: 96),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (categories == null || (_failed && categories.isEmpty)) {
      content = ManageMessage(
        icon: Icons.error_outline,
        title: l.manageCategoriesLoadFailed,
        onRetry: _load,
      );
    } else if (categories.isEmpty) {
      content = ManageMessage(
        icon: Icons.category_outlined,
        title: l.manageCategoriesEmpty,
        body: l.manageCategoriesEmptyBody,
      );
    } else {
      final tree = filterCategoryTree(buildCategoryTree(categories), _query);
      content = tree.isEmpty
          ? ManageMessage(
              icon: Icons.search_off, title: l.manageNoMatches(_query.trim()))
          : SureListGroup(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              children: [
                for (final node in tree) ...[
                  SureListRow(
                    title: node.category.name,
                    leading: _CategoryBadge(category: node.category),
                    showChevron: true,
                    onTap: () => _showInfo(node.category),
                  ),
                  for (final child in node.children)
                    Padding(
                      padding: const EdgeInsets.only(left: 28),
                      child: SureListRow(
                        title: child.name,
                        leading: _CategoryBadge(category: child, size: 24),
                        showChevron: true,
                        onTap: () => _showInfo(child),
                      ),
                    ),
                ],
              ],
            );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l.manageCategoriesTitle),
        actions: [
          IconButton(
            tooltip: l.manageCategoryAdd,
            icon: const Icon(Icons.add),
            onPressed: categories == null ? null : _create,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: SureSpacing.huge),
          children: [
            if (categories != null && categories.isNotEmpty)
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

/// A colored circle with the category's icon when the app bundles it, or
/// its first letter otherwise.
class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.category, this.size = 28});

  final Category category;
  final double size;

  // shortcut: the app bundles only a few Lucide SVGs, so other server icons
  // fall back to the first letter. Bundle more SVGs to show them all.
  static const _bundled = {
    SureIcons.landmark,
    SureIcons.creditCard,
    SureIcons.trendingUp,
    SureIcons.trendingDown,
    SureIcons.receipt,
    SureIcons.house,
    SureIcons.car,
    SureIcons.bitcoin,
    SureIcons.shapes,
    SureIcons.handCoins,
    SureIcons.wallet,
  };

  @override
  Widget build(BuildContext context) {
    final icon = category.icon;
    final letter = category.name.isEmpty
        ? '?'
        : category.name.characters.first.toUpperCase();
    return ManageColorDot(
      hex: category.color,
      size: size,
      child: icon != null && _bundled.contains(icon)
          ? SureIcon(icon, size: size * 0.55, color: Colors.white)
          : Text(
              letter,
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.45,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }
}

/// The create category form: name, color and an optional parent. [onSubmit]
/// returns an error message to show, or null on success.
class CategoryForm extends StatefulWidget {
  const CategoryForm({
    super.key,
    required this.parents,
    required this.onSubmit,
  });

  final List<Category> parents;
  final Future<String?> Function(String name, String color, String? parentId)
      onSubmit;

  @override
  State<CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends State<CategoryForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  String _color = kMetadataColors.first;
  String? _parentId;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.onSubmit(_name.text.trim(), _color, _parentId);
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
    final palette = SureColors.of(context).palette;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l.manageCategoryNew, style: theme.textTheme.titleLarge),
          const SizedBox(height: SureSpacing.xl),
          SureTextField(
            controller: _name,
            label: l.manageNameLabel,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
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
          if (widget.parents.isNotEmpty) ...[
            const SizedBox(height: SureSpacing.xl),
            DropdownButtonFormField<String?>(
              initialValue: _parentId,
              isExpanded: true,
              decoration: InputDecoration(labelText: l.manageCategoryParent),
              items: [
                DropdownMenuItem<String?>(
                    value: null, child: Text(l.manageCategoryNoParent)),
                for (final parent in widget.parents)
                  DropdownMenuItem<String?>(
                      value: parent.id, child: Text(parent.name)),
              ],
              onChanged: (value) => setState(() => _parentId = value),
            ),
          ],
          const SizedBox(height: SureSpacing.lg),
          Text(l.manageCategoryIconHint,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: palette.textSecondary)),
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
