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
import '../widgets/ds/ds.dart';
import '../widgets/manage_widgets.dart';
import '../widgets/open_on_web_action.dart';
import 'form_sheet_fields.dart';

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
        leading: _CategoriesScreenState._icon(category,
            size: SureCategoryIcon.heroSize),
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
      content = const ManageLoading();
    } else if (categories == null || (_failed && categories.isEmpty)) {
      content = SureEmptyState(
        key: const ValueKey('categoriesError'),
        icon: SureIcons.circleAlert,
        title: l.manageCategoriesLoadFailed,
        primaryLabel: l.commonTryAgain,
        onPrimary: _load,
      );
    } else if (categories.isEmpty) {
      content = SureEmptyState(
        key: const ValueKey('categoriesEmpty'),
        icon: SureIcons.shapes,
        title: l.manageCategoriesEmpty,
        body: l.manageCategoriesEmptyBody,
        primaryLabel: l.manageCategoryAdd,
        onPrimary: _create,
      );
    } else {
      final tree = filterCategoryTree(buildCategoryTree(categories), _query);
      content = tree.isEmpty
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
                for (final node in tree) ...[
                  SureListRow(
                    title: node.category.name,
                    leading: _icon(node.category),
                    showChevron: true,
                    onTap: () => _showInfo(node.category),
                  ),
                  for (final child in node.children)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                          start: _childIndent),
                      child: SureListRow(
                        title: child.name,
                        leading: _icon(child),
                        showChevron: true,
                        onTap: () => _showInfo(child),
                      ),
                    ),
                ],
              ],
            );
    }

    return SureLargeTitleScaffold(
      title: l.manageCategoriesTitle,
      leading: manageBackLink(context),
      actions: [
        SureNavIconButton(
          icon: SureIcons.plus,
          semanticLabel: l.manageCategoryAdd,
          onPressed: categories == null ? null : _create,
        ),
      ],
      onRefresh: _load,
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
      ],
    );
  }

  /// How far a subcategory row is indented under its parent.
  static const double _childIndent = 24;

  static Widget _icon(Category category,
          {double size = SureCategoryIcon.rowSize}) =>
      SureCategoryIcon(
        name: category.name,
        color: category.color,
        icon: category.icon,
        size: size,
      );
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
  final _nameFocus = FocusNode();
  String _color = kMetadataColors.first;
  String? _parentId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _nameFocus.requestFocus());
  }

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
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

  Future<void> _pickParent() async {
    final l = AppLocalizations.of(context);
    final picked = await showManageOptionSheet<String?>(
      context,
      title: l.manageCategoryParent,
      selected: _parentId,
      options: [
        (null, l.manageCategoryNoParent),
        for (final parent in widget.parents) (parent.id, parent.name),
      ],
    );
    if (picked != null && mounted) setState(() => _parentId = picked.value);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = SureColors.of(context).palette;
    final parent = widget.parents.where((p) => p.id == _parentId).firstOrNull;
    return SureSheet(
      title: l.manageCategoryNew,
      actionLabel: l.commonSave,
      actionKey: const ValueKey('categoryFormSave'),
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
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.done,
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? l.manageNameRequired
                        : null,
                  ),
                  if (widget.parents.isNotEmpty)
                    SureListRow(
                      key: const ValueKey('categoryFormParent'),
                      title: l.manageCategoryParent,
                      value: parent?.name ?? l.manageCategoryNoParent,
                      showChevron: true,
                      onTap: _saving ? null : _pickParent,
                    ),
                ],
              ),
              ManageColorPicker(
                value: _color,
                onChanged: (value) =>
                    setState(() => _color = value ?? kMetadataColors.first),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                child: Text(
                  l.manageCategoryIconHint,
                  style: TextStyle(
                      fontSize: 13, height: 1.35, color: palette.textSecondary),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: SureSpacing.lg),
                ManageErrorText(_error!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
